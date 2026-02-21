mod rate_limit;

use std::collections::HashMap;
use std::env;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use atlas_agents::ConciergeAgent;
use atlas_core::{ChatInput, TripPlanRequest};
use atlas_ml::AtlasMlStack;
use atlas_observability::AppMetrics;
use atlas_retrieval::HybridRetriever;
use atlas_storage::Store;
use axum::extract::{Form, Json, Path as AxumPath, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{body::Body, Router};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use hmac::{Hmac, Mac};
use parking_lot::RwLock;
use rand::{rng, RngCore};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use tower_http::cors::{AllowOrigin, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;
use url::Url;
use webauthn_rs::prelude::{
    AuthenticationResult, Passkey, PasskeyAuthentication, PasskeyRegistration, PublicKeyCredential,
    RegisterPublicKeyCredential, Webauthn, WebauthnBuilder,
};

use crate::rate_limit::IpRateLimiter;

const MAX_PROFILE_FIELD_LEN: usize = 64;
const MAX_NOTE_TITLE_LEN: usize = 160;
const MAX_NOTE_CONTENT_LEN: usize = 8_000;
const MAX_NOTE_TAGS: usize = 16;
const MAX_NOTE_TAG_LEN: usize = 32;
const MAX_REWRITE_INSTRUCTION_LEN: usize = 400;
const MAX_MEMORY_IMPORT_ITEMS: usize = 250;
const MAX_NOTES_PER_USER: usize = 5_000;
const DEFAULT_SUBSCRIPTION_BYPASS_EMAILS: &str = "ceo@atlasmasa.com";

#[derive(Clone)]
#[allow(private_interfaces)]
pub struct ApiState {
    pub agent: Arc<ConciergeAgent<Store>>,
    pub metrics: Arc<AppMetrics>,
    pub api_key: String,
    pub limiter: IpRateLimiter,
    pub auth_limiter: IpRateLimiter,
    pub http_client: Client,
    pub db_pool: Option<SqlitePool>,
    pub users: Arc<RwLock<HashMap<String, UserRecord>>>,
    pub sessions: Arc<RwLock<HashMap<String, SessionRecord>>>,
    pub studio_preferences: Arc<RwLock<HashMap<String, StudioPreferencesRecord>>>,
    pub survey_states: Arc<RwLock<HashMap<String, SurveyStateRecord>>>,
    pub feedback_items: Arc<RwLock<Vec<FeedbackRecord>>>,
    pub user_notes: Arc<RwLock<HashMap<String, Vec<UserNoteRecord>>>>,
    pub oauth_states: Arc<RwLock<HashMap<String, OAuthStateRecord>>>,
    pub google_oauth: Option<GoogleOAuthConfig>,
    pub apple_oauth: Option<AppleOAuthConfig>,
    pub openai_runtime: Option<OpenAiRuntimeConfig>,
    pub billing_runtime: Option<BillingRuntimeConfig>,
    pub webauthn_runtime: Option<WebauthnRuntimeConfig>,
    pub passkey_registrations: Arc<RwLock<HashMap<String, PasskeyRegistrationStateRecord>>>,
    pub passkey_authentications: Arc<RwLock<HashMap<String, PasskeyAuthenticationStateRecord>>>,
    pub passkeys_by_user: Arc<RwLock<HashMap<String, Vec<PasskeyRecord>>>>,
    pub allowed_origins: Arc<Vec<String>>,
    pub company_status: CompanyStatusRecord,
    pub session_ttl: Duration,
    pub cookie_name: String,
    pub cookie_domain: String,
    pub cookie_secure: bool,
    pub cookie_same_site: String,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    timestamp_utc: String,
    metrics: atlas_observability::MetricsSnapshot,
    capabilities: HealthCapabilities,
}

#[derive(Debug, Clone)]
struct GoogleOAuthConfig {
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    frontend_origin: String,
}

#[derive(Debug, Clone)]
struct AppleOAuthConfig {
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    frontend_origin: String,
}

#[derive(Debug, Serialize)]
struct HealthCapabilities {
    google_oauth: bool,
    apple_oauth: bool,
    passkey: bool,
    billing: bool,
    deep_personalization: bool,
}

#[derive(Debug, Clone)]
struct OpenAiRuntimeConfig {
    api_key: String,
    model: String,
    default_reasoning_effort: String,
}

#[derive(Debug, Clone)]
struct BillingRuntimeConfig {
    stripe_secret_key: String,
    stripe_webhook_secret: Option<String>,
    monthly_price_id: String,
    success_url: String,
    cancel_url: String,
}

#[derive(Debug, Clone)]
struct WebauthnRuntimeConfig {
    webauthn: Arc<Webauthn>,
}

#[derive(Debug, Clone, Deserialize)]
struct GoogleOAuthStartQuery {
    return_to: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct GoogleOAuthCallbackQuery {
    code: Option<String>,
    state: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct AppleOAuthStartQuery {
    return_to: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct AppleOAuthCallbackQuery {
    code: Option<String>,
    state: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
}

#[derive(Debug, Clone)]
struct OAuthStateRecord {
    provider: String,
    code_verifier: Option<String>,
    nonce: Option<String>,
    return_to: String,
    expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
struct PasskeyRegistrationStateRecord {
    user_id: String,
    state: PasskeyRegistration,
    expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
struct PasskeyAuthenticationStateRecord {
    user_id: Option<String>,
    state: PasskeyAuthentication,
    expires_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
struct ProfileUpsertRequest {
    user_id: Option<String>,
    trip_style: Option<String>,
    risk_preference: Option<String>,
    memory_opt_in: Option<bool>,
    locale: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct ChatRequest {
    session_id: Option<String>,
    text: String,
    locale: Option<String>,
    user_id: Option<String>,
    preferred_format: Option<String>,
    response_depth: Option<String>,
    response_tone: Option<String>,
    include_proactive: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
struct StudioPreferencesUpsertRequest {
    user_id: Option<String>,
    preferred_format: Option<String>,
    response_depth: Option<String>,
    response_tone: Option<String>,
    proactive_mode: Option<String>,
    reminders_app: Option<String>,
    alarms_app: Option<String>,
    voice_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StudioPreferencesRecord {
    user_id: String,
    preferred_format: String,
    response_depth: String,
    response_tone: String,
    proactive_mode: String,
    reminders_app: String,
    alarms_app: String,
    voice_mode: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SurveyStateRecord {
    user_id: String,
    answers: HashMap<String, String>,
    completed: bool,
    started_at: Option<String>,
    completed_at: Option<String>,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SurveyChoice {
    value: String,
    label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SurveyQuestion {
    id: String,
    title: String,
    description: Option<String>,
    kind: String,
    required: bool,
    choices: Vec<SurveyChoice>,
    placeholder: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SurveyProgress {
    answered: usize,
    total: usize,
    percent: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SurveyNextResponse {
    question: Option<SurveyQuestion>,
    progress: SurveyProgress,
    profile_hints: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct SurveyAnswerRequest {
    user_id: Option<String>,
    question_id: String,
    answer: String,
    locale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProactiveFeedItem {
    id: String,
    title: String,
    summary: String,
    why_now: String,
    priority: String,
    actions: Vec<atlas_core::SuggestedAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProactiveFeedResponse {
    generated_at: String,
    items: Vec<ProactiveFeedItem>,
    feed_ready: bool,
    gate_reason: Option<String>,
    required_minutes: u32,
    company_status: CompanyStatusRecord,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CompanyStatusRecord {
    phase: String,
    current_focus: Vec<String>,
    upcoming: Vec<String>,
    open_for_investment: bool,
    message: String,
}

#[derive(Debug, Clone, Deserialize)]
struct UserLookupQuery {
    user_id: Option<String>,
    locale: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedbackSubmitRequest {
    user_id: Option<String>,
    category: String,
    severity: Option<String>,
    message: String,
    tags: Option<Vec<String>>,
    target_employee: Option<String>,
    source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FeedbackRecord {
    feedback_id: String,
    user_id: Option<String>,
    category: String,
    severity: String,
    message: String,
    tags: Vec<String>,
    target_employee: String,
    source: String,
    status: String,
    created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct FeedbackListQuery {
    limit: Option<usize>,
}

#[derive(Debug, Clone, Deserialize)]
struct ReminderActionRequest {
    title: String,
    details: Option<String>,
    due_at_utc: Option<String>,
    duration_minutes: Option<u32>,
    reminders_app: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ReminderActionResponse {
    app: String,
    google_calendar_url: String,
    ics_filename: String,
    ics_content: String,
    shortcuts_url: String,
}

#[derive(Debug, Clone, Deserialize)]
struct AlarmActionRequest {
    label: String,
    time_local: String,
    days: Option<Vec<String>>,
    alarms_app: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AlarmActionResponse {
    app: String,
    clock_url: String,
    shortcuts_url: String,
    fallback_instructions: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
struct BillingCheckoutRequest {}

#[derive(Debug, Clone, Serialize)]
struct BillingCheckoutResponse {
    checkout_url: String,
    checkout_session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct BillingStatusRecord {
    user_id: String,
    stripe_customer_id: Option<String>,
    stripe_subscription_id: Option<String>,
    status: String,
    current_period_end: Option<String>,
    updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct PasskeyRegistrationStartRequest {
    email: Option<String>,
    display_name: Option<String>,
    locale: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct PasskeyRegistrationStartResponse {
    request_id: String,
    options: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
struct PasskeyRegistrationFinishRequest {
    request_id: String,
    credential: RegisterPublicKeyCredential,
}

#[derive(Debug, Clone, Deserialize)]
struct PasskeyLoginStartRequest {
    email: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct PasskeyLoginStartResponse {
    request_id: String,
    options: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
struct PasskeyLoginFinishRequest {
    request_id: String,
    credential: PublicKeyCredential,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PasskeyRecord {
    passkey_id: String,
    user_id: String,
    credential: Passkey,
    created_at: String,
    last_used_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct UserNoteRecord {
    note_id: String,
    user_id: String,
    title: String,
    content: String,
    tags: Vec<String>,
    updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct NoteUpsertRequest {
    user_id: Option<String>,
    note_id: Option<String>,
    title: String,
    content: String,
    tags: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize)]
struct NotesQuery {
    user_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct NoteRewriteRequest {
    user_id: Option<String>,
    note_id: String,
    instruction: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryImportItem {
    title: String,
    content: String,
    tags: Option<Vec<String>>,
    source: Option<String>,
    happened_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryImportRequest {
    user_id: Option<String>,
    items: Vec<MemoryImportItem>,
}

#[derive(Debug, Clone, serde::Serialize)]
struct AuthResponse {
    token: String,
    user: UserRecord,
    session_expires_at: String,
}

#[derive(Debug, Clone, serde::Serialize)]
struct UserRecord {
    user_id: String,
    provider: String,
    email: String,
    name: String,
    locale: String,
    trip_style: Option<String>,
    risk_preference: Option<String>,
    memory_opt_in: bool,
    passkey_user_handle: Option<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone)]
struct SessionRecord {
    user_id: String,
    expires_at: chrono::DateTime<chrono::Utc>,
    created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Default)]
struct PersistedState {
    users: HashMap<String, UserRecord>,
    sessions: HashMap<String, SessionRecord>,
    studio_preferences: HashMap<String, StudioPreferencesRecord>,
    survey_states: HashMap<String, SurveyStateRecord>,
    feedback_items: Vec<FeedbackRecord>,
    user_notes: HashMap<String, Vec<UserNoteRecord>>,
    passkeys_by_user: HashMap<String, Vec<PasskeyRecord>>,
}

pub async fn build_app(kb_root: impl AsRef<Path>) -> Result<Router> {
    let metrics = AppMetrics::shared();
    let ml_stack = AtlasMlStack::load_default();

    let retriever = Arc::new(
        HybridRetriever::from_kb_dir(kb_root, Some(ml_stack.embedder.clone()))
            .context("failed to initialize retriever")?,
    );

    let policy_set = atlas_core::PolicySet::default();

    let store = if let Ok(database_url) = env::var("ATLAS_DATABASE_URL") {
        Store::sqlite(&database_url).await?
    } else {
        Store::memory()
    };
    let db_pool = match &store {
        Store::Sqlite(sqlite) => Some(sqlite.pool().clone()),
        Store::Memory(_) => None,
    };
    if let Some(pool) = db_pool.as_ref() {
        ensure_app_schema(pool).await?;
    }
    let persisted_state = load_persistent_state(db_pool.as_ref()).await?;

    let store = Arc::new(store);

    let agent = Arc::new(ConciergeAgent::new(
        retriever,
        ml_stack,
        policy_set,
        store,
        metrics.clone(),
    ));

    let api_key = env::var("ATLAS_API_KEY").unwrap_or_else(|_| "dev-atlas-key".to_string());
    let session_ttl = Duration::from_secs(
        env::var("ATLAS_SESSION_TTL_SECONDS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(60 * 60 * 24 * 30),
    );
    let cookie_name =
        env::var("ATLAS_SESSION_COOKIE_NAME").unwrap_or_else(|_| "atlas_session".to_string());
    let cookie_domain = env::var("ATLAS_SESSION_COOKIE_DOMAIN")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "localhost".to_string());
    let cookie_secure = true;
    let cookie_same_site = sanitize_enum_value(
        env::var("ATLAS_COOKIE_SAMESITE")
            .ok()
            .unwrap_or_else(|| "strict".to_string())
            .as_str(),
        &["strict", "lax", "none"],
        "strict",
    );
    let api_rate_limit_window = Duration::from_secs(
        env::var("ATLAS_API_RATE_LIMIT_WINDOW_SECONDS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(60),
    );
    let api_rate_limit_max = env::var("ATLAS_API_RATE_LIMIT_MAX")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(80);
    let auth_rate_limit_window = Duration::from_secs(
        env::var("ATLAS_AUTH_RATE_LIMIT_WINDOW_SECONDS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(60),
    );
    let auth_rate_limit_max = env::var("ATLAS_AUTH_RATE_LIMIT_MAX")
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .unwrap_or(12);
    let allowed_origins = parse_allowed_origins();
    let google_oauth = build_google_oauth_config();
    let apple_oauth = build_apple_oauth_config();
    let openai_runtime = build_openai_runtime_config();
    let billing_runtime = build_billing_runtime_config();
    let webauthn_runtime = build_webauthn_runtime();

    let state = ApiState {
        agent,
        metrics,
        api_key,
        limiter: IpRateLimiter::new(api_rate_limit_window, api_rate_limit_max),
        auth_limiter: IpRateLimiter::new(auth_rate_limit_window, auth_rate_limit_max),
        http_client: Client::builder()
            .connect_timeout(Duration::from_secs(6))
            .timeout(Duration::from_secs(20))
            .build()
            .context("failed to build HTTP client")?,
        db_pool,
        users: Arc::new(RwLock::new(persisted_state.users)),
        sessions: Arc::new(RwLock::new(persisted_state.sessions)),
        studio_preferences: Arc::new(RwLock::new(persisted_state.studio_preferences)),
        survey_states: Arc::new(RwLock::new(persisted_state.survey_states)),
        feedback_items: Arc::new(RwLock::new(persisted_state.feedback_items)),
        user_notes: Arc::new(RwLock::new(persisted_state.user_notes)),
        oauth_states: Arc::new(RwLock::new(HashMap::new())),
        google_oauth,
        apple_oauth,
        openai_runtime,
        billing_runtime,
        webauthn_runtime,
        passkey_registrations: Arc::new(RwLock::new(HashMap::new())),
        passkey_authentications: Arc::new(RwLock::new(HashMap::new())),
        passkeys_by_user: Arc::new(RwLock::new(persisted_state.passkeys_by_user)),
        allowed_origins: Arc::new(allowed_origins),
        company_status: default_company_status(),
        session_ttl,
        cookie_name,
        cookie_domain,
        cookie_secure,
        cookie_same_site,
    };

    Ok(build_router(state))
}

pub fn build_router(state: ApiState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/chat", post(chat))
        .route("/v1/plan_trip", post(plan_trip))
        .route("/v1/auth/google/start", get(auth_google_start))
        .route("/v1/auth/google/callback", get(auth_google_callback))
        .route("/v1/auth/apple/start", get(auth_apple_start))
        .route(
            "/v1/auth/apple/callback",
            get(auth_apple_callback_get).post(auth_apple_callback_post),
        )
        .route(
            "/v1/auth/passkey/register/start",
            post(auth_passkey_register_start),
        )
        .route(
            "/v1/auth/passkey/register/finish",
            post(auth_passkey_register_finish),
        )
        .route(
            "/v1/auth/passkey/login/start",
            post(auth_passkey_login_start),
        )
        .route(
            "/v1/auth/passkey/login/finish",
            post(auth_passkey_login_finish),
        )
        .route("/v1/auth/social_login", post(social_login))
        .route("/v1/auth/logout", post(auth_logout))
        .route("/v1/profile/upsert", post(profile_upsert))
        .route("/v1/auth/me", get(auth_me))
        .route("/v1/notes", get(notes_list))
        .route("/v1/notes/upsert", post(note_upsert))
        .route("/v1/notes/rewrite", post(note_rewrite))
        .route("/v1/memory/import", post(memory_import))
        .route(
            "/v1/billing/create_checkout_session",
            post(billing_create_checkout_session),
        )
        .route("/v1/billing/stripe_webhook", post(billing_stripe_webhook))
        .route(
            "/v1/studio/preferences",
            get(studio_preferences_get).post(studio_preferences_upsert),
        )
        .route("/v1/survey/next", get(survey_next))
        .route("/v1/survey/answer", post(survey_answer))
        .route("/v1/feed/proactive", get(feed_proactive))
        .route("/v1/company/status", get(company_status))
        .route("/v1/feedback/submit", post(feedback_submit))
        .route(
            "/v1/feedback/employee/{employee}",
            get(feedback_for_employee),
        )
        .route("/v1/actions/reminder", post(action_reminder))
        .route("/v1/actions/alarm", post(action_alarm))
        .layer(build_cors_layer(&state.allowed_origins))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            security_headers_middleware,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            csrf_origin_middleware,
        ))
        .layer(TraceLayer::new_for_http())
        .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
        .layer(PropagateRequestIdLayer::x_request_id())
        .layer(RequestBodyLimitLayer::new(64 * 1024))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            api_key_middleware,
        ))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            rate_limit_middleware,
        ))
        .with_state(state)
}

async fn health(State(state): State<ApiState>) -> impl IntoResponse {
    let payload = HealthResponse {
        status: "ok",
        timestamp_utc: chrono::Utc::now().to_rfc3339(),
        metrics: state.metrics.snapshot(),
        capabilities: HealthCapabilities {
            google_oauth: state.google_oauth.is_some(),
            apple_oauth: state.apple_oauth.is_some(),
            passkey: state.webauthn_runtime.is_some(),
            billing: state.billing_runtime.is_some(),
            deep_personalization: true,
        },
    };
    (StatusCode::OK, Json(payload))
}

#[derive(Debug, Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
}

#[derive(Debug, Deserialize)]
struct GoogleUserInfoResponse {
    email: String,
    verified_email: Option<bool>,
    name: Option<String>,
    locale: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AppleTokenResponse {
    id_token: String,
}

#[derive(Debug, Deserialize)]
struct AppleIdTokenClaims {
    aud: Option<String>,
    exp: Option<i64>,
    nonce: Option<String>,
    email: Option<String>,
    email_verified: Option<serde_json::Value>,
    locale: Option<String>,
}

async fn auth_google_start(
    State(state): State<ApiState>,
    Query(query): Query<GoogleOAuthStartQuery>,
) -> impl IntoResponse {
    let Some(config) = state.google_oauth.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "oauth_unavailable",
                "message": "Google OAuth is not configured"
            })),
        )
            .into_response();
    };

    let state_token = generate_urlsafe_token(24);
    let code_verifier = generate_urlsafe_token(64);
    let code_challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(code_verifier.as_bytes()));
    let return_to = sanitize_return_to(
        query
            .return_to
            .as_deref()
            .unwrap_or("/concierge-local.html"),
    );

    state.oauth_states.write().insert(
        state_token.clone(),
        OAuthStateRecord {
            provider: "google".to_string(),
            code_verifier: Some(code_verifier),
            nonce: None,
            return_to,
            expires_at: chrono::Utc::now() + chrono::Duration::minutes(12),
        },
    );

    let authorize_url = format!(
        "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope={}&state={}&code_challenge={}&code_challenge_method=S256&prompt=select_account",
        pct_encode(config.client_id.as_str()),
        pct_encode(config.redirect_uri.as_str()),
        pct_encode("openid email profile"),
        pct_encode(state_token.as_str()),
        pct_encode(code_challenge.as_str()),
    );

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "authorize_url": authorize_url
        })),
    )
        .into_response()
}

async fn auth_google_callback(
    State(state): State<ApiState>,
    Query(query): Query<GoogleOAuthCallbackQuery>,
) -> impl IntoResponse {
    let Some(config) = state.google_oauth.as_ref() else {
        return Redirect::to("/").into_response();
    };

    if let Some(error) = query.error.as_ref() {
        let target = format!(
            "{}{}?auth=error&reason={}",
            config.frontend_origin,
            "/concierge-local.html",
            pct_encode(query.error_description.as_deref().unwrap_or(error.as_str()))
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let Some(state_token) = query.state.as_deref() else {
        let target = format!(
            "{}{}?auth=error&reason=missing_state",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    };

    let Some(pending) = state.oauth_states.write().remove(state_token) else {
        let target = format!(
            "{}{}?auth=error&reason=invalid_state",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    };
    if pending.expires_at <= chrono::Utc::now() {
        let target = format!(
            "{}{}?auth=error&reason=state_expired",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    }
    if pending.provider != "google" {
        let target = format!(
            "{}{}?auth=error&reason=provider_mismatch",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    }
    let Some(code_verifier) = pending.code_verifier.as_deref() else {
        let target = format!(
            "{}{}?auth=error&reason=missing_pkce_verifier",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    };

    let Some(code) = query.code.as_deref() else {
        let target = format!(
            "{}{}?auth=error&reason=missing_code",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    };

    let token = match state
        .http_client
        .post("https://oauth2.googleapis.com/token")
        .form(&[
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", config.client_id.as_str()),
            ("client_secret", config.client_secret.as_str()),
            ("redirect_uri", config.redirect_uri.as_str()),
            ("code_verifier", code_verifier),
        ])
        .send()
        .await
    {
        Ok(response) if response.status().is_success() => {
            match response.json::<GoogleTokenResponse>().await {
                Ok(payload) => payload,
                Err(_) => {
                    let target = format!(
                        "{}{}?auth=error&reason=token_parse_failed",
                        config.frontend_origin,
                        pending.return_to.as_str()
                    );
                    return Redirect::to(target.as_str()).into_response();
                }
            }
        }
        Ok(response) => {
            let target = format!(
                "{}{}?auth=error&reason=token_exchange_failed_{}",
                config.frontend_origin,
                pending.return_to.as_str(),
                response.status().as_u16()
            );
            return Redirect::to(target.as_str()).into_response();
        }
        Err(_) => {
            let target = format!(
                "{}{}?auth=error&reason=token_exchange_network_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    let userinfo = match state
        .http_client
        .get("https://www.googleapis.com/oauth2/v2/userinfo")
        .bearer_auth(token.access_token)
        .send()
        .await
    {
        Ok(response) if response.status().is_success() => {
            match response.json::<GoogleUserInfoResponse>().await {
                Ok(payload) => payload,
                Err(_) => {
                    let target = format!(
                        "{}{}?auth=error&reason=userinfo_parse_failed",
                        config.frontend_origin,
                        pending.return_to.as_str()
                    );
                    return Redirect::to(target.as_str()).into_response();
                }
            }
        }
        _ => {
            let target = format!(
                "{}{}?auth=error&reason=userinfo_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    if !userinfo.verified_email.unwrap_or(true) {
        let target = format!(
            "{}{}?auth=error&reason=email_not_verified",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let now = chrono::Utc::now().to_rfc3339();
    let user = find_or_create_user_by_email(
        &state,
        "google",
        userinfo.email.to_lowercase(),
        userinfo
            .name
            .unwrap_or_else(|| "Atlas Masa User".to_string()),
        userinfo.locale.unwrap_or_else(|| "en".to_string()),
        now,
    )
    .await;

    let session_id = match issue_session_for_user(&state, &user).await {
        Ok(value) => value,
        Err(_) => {
            let target = format!(
                "{}{}?auth=error&reason=session_issue_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    let target = format!(
        "{}{}?auth=success",
        config.frontend_origin,
        pending.return_to.as_str()
    );
    let mut response = Redirect::to(target.as_str()).into_response();
    let cookie_value = build_session_cookie(
        &state.cookie_name,
        session_id.as_str(),
        state.session_ttl.as_secs(),
        state.cookie_secure,
        state.cookie_same_site.as_str(),
        state.cookie_domain.as_str(),
    );
    if let Ok(header_value) = HeaderValue::from_str(&cookie_value) {
        response
            .headers_mut()
            .insert(header::SET_COOKIE, header_value);
    }
    response
}

async fn auth_apple_start(
    State(state): State<ApiState>,
    Query(query): Query<AppleOAuthStartQuery>,
) -> impl IntoResponse {
    let Some(config) = state.apple_oauth.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "oauth_unavailable",
                "message": "Apple Sign In is not configured"
            })),
        )
            .into_response();
    };

    let state_token = generate_urlsafe_token(24);
    let nonce = generate_urlsafe_token(24);
    let return_to = sanitize_return_to(
        query
            .return_to
            .as_deref()
            .unwrap_or("/concierge-local.html"),
    );

    state.oauth_states.write().insert(
        state_token.clone(),
        OAuthStateRecord {
            provider: "apple".to_string(),
            code_verifier: None,
            nonce: Some(nonce.clone()),
            return_to,
            expires_at: chrono::Utc::now() + chrono::Duration::minutes(12),
        },
    );

    let authorize_url = format!(
        "https://appleid.apple.com/auth/authorize?client_id={}&redirect_uri={}&response_type=code&response_mode=form_post&scope={}&state={}&nonce={}",
        pct_encode(config.client_id.as_str()),
        pct_encode(config.redirect_uri.as_str()),
        pct_encode("name email"),
        pct_encode(state_token.as_str()),
        pct_encode(nonce.as_str()),
    );

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "authorize_url": authorize_url
        })),
    )
        .into_response()
}

async fn auth_apple_callback_get(
    State(state): State<ApiState>,
    Query(query): Query<AppleOAuthCallbackQuery>,
) -> impl IntoResponse {
    auth_apple_callback_inner(state, query).await
}

async fn auth_apple_callback_post(
    State(state): State<ApiState>,
    Form(form): Form<AppleOAuthCallbackQuery>,
) -> impl IntoResponse {
    auth_apple_callback_inner(state, form).await
}

async fn auth_apple_callback_inner(state: ApiState, query: AppleOAuthCallbackQuery) -> Response {
    let Some(config) = state.apple_oauth.as_ref() else {
        return Redirect::to("/").into_response();
    };

    if let Some(error) = query.error.as_ref() {
        let target = format!(
            "{}{}?auth=error&reason={}",
            config.frontend_origin,
            "/concierge-local.html",
            pct_encode(query.error_description.as_deref().unwrap_or(error.as_str()))
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let Some(state_token) = query.state.as_deref() else {
        let target = format!(
            "{}{}?auth=error&reason=missing_state",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    };

    let Some(pending) = state.oauth_states.write().remove(state_token) else {
        let target = format!(
            "{}{}?auth=error&reason=invalid_state",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    };
    if pending.expires_at <= chrono::Utc::now() {
        let target = format!(
            "{}{}?auth=error&reason=state_expired",
            config.frontend_origin, "/concierge-local.html"
        );
        return Redirect::to(target.as_str()).into_response();
    }
    if pending.provider != "apple" {
        let target = format!(
            "{}{}?auth=error&reason=provider_mismatch",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let Some(code) = query.code.as_deref() else {
        let target = format!(
            "{}{}?auth=error&reason=missing_code",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    };

    let token = match state
        .http_client
        .post("https://appleid.apple.com/auth/token")
        .form(&[
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", config.client_id.as_str()),
            ("client_secret", config.client_secret.as_str()),
            ("redirect_uri", config.redirect_uri.as_str()),
        ])
        .send()
        .await
    {
        Ok(response) if response.status().is_success() => {
            match response.json::<AppleTokenResponse>().await {
                Ok(payload) => payload,
                Err(_) => {
                    let target = format!(
                        "{}{}?auth=error&reason=token_parse_failed",
                        config.frontend_origin,
                        pending.return_to.as_str()
                    );
                    return Redirect::to(target.as_str()).into_response();
                }
            }
        }
        Ok(response) => {
            let target = format!(
                "{}{}?auth=error&reason=token_exchange_failed_{}",
                config.frontend_origin,
                pending.return_to.as_str(),
                response.status().as_u16()
            );
            return Redirect::to(target.as_str()).into_response();
        }
        Err(_) => {
            let target = format!(
                "{}{}?auth=error&reason=token_exchange_network_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    let Some(claims) = parse_untrusted_jwt_payload::<AppleIdTokenClaims>(token.id_token.as_str())
    else {
        let target = format!(
            "{}{}?auth=error&reason=id_token_parse_failed",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    };

    if claims.aud.as_deref() != Some(config.client_id.as_str()) {
        let target = format!(
            "{}{}?auth=error&reason=invalid_audience",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let now_ts = chrono::Utc::now().timestamp();
    if claims.exp.unwrap_or(0) <= now_ts {
        let target = format!(
            "{}{}?auth=error&reason=id_token_expired",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    if let Some(expected_nonce) = pending.nonce.as_deref() {
        if claims.nonce.as_deref() != Some(expected_nonce) {
            let target = format!(
                "{}{}?auth=error&reason=nonce_mismatch",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    }

    let Some(email) = claims
        .email
        .as_deref()
        .map(|value| value.trim().to_lowercase())
    else {
        let target = format!(
            "{}{}?auth=error&reason=missing_email",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    };
    let verified = claims
        .email_verified
        .as_ref()
        .and_then(bool_from_jsonish)
        .unwrap_or(false);
    if !verified {
        let target = format!(
            "{}{}?auth=error&reason=email_not_verified",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    let display_name = email
        .split('@')
        .next()
        .unwrap_or("Atlas Masa User")
        .trim()
        .to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let user = find_or_create_user_by_email(
        &state,
        "apple",
        email,
        if display_name.is_empty() {
            "Atlas Masa User".to_string()
        } else {
            display_name
        },
        claims.locale.unwrap_or_else(|| "en".to_string()),
        now,
    )
    .await;

    let session_id = match issue_session_for_user(&state, &user).await {
        Ok(value) => value,
        Err(_) => {
            let target = format!(
                "{}{}?auth=error&reason=session_issue_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    let target = format!(
        "{}{}?auth=success",
        config.frontend_origin,
        pending.return_to.as_str()
    );
    let mut response = Redirect::to(target.as_str()).into_response();
    let cookie_value = build_session_cookie(
        &state.cookie_name,
        session_id.as_str(),
        state.session_ttl.as_secs(),
        state.cookie_secure,
        state.cookie_same_site.as_str(),
        state.cookie_domain.as_str(),
    );
    if let Ok(header_value) = HeaderValue::from_str(&cookie_value) {
        response
            .headers_mut()
            .insert(header::SET_COOKIE, header_value);
    }
    response
}

async fn auth_passkey_register_start(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<PasskeyRegistrationStartRequest>,
) -> impl IntoResponse {
    let Some(runtime) = state.webauthn_runtime.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "passkey_unavailable",
                "message": "Passkey auth is not configured"
            })),
        )
            .into_response();
    };

    let requested_email = input
        .email
        .as_deref()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty());
    let display_name = input
        .display_name
        .clone()
        .unwrap_or_else(|| "Atlas Masa User".to_string());
    let locale = input.locale.clone().unwrap_or_else(|| "en".to_string());
    let now = chrono::Utc::now().to_rfc3339();

    let mut user = if let Some(existing) = session_user_from_headers(&state, &headers) {
        existing
    } else {
        let email = requested_email.unwrap_or_else(|| {
            format!("passkey-{}@atlasmasa.local", uuid::Uuid::new_v4().simple())
        });
        find_or_create_user_by_email(&state, "passkey", email, display_name, locale, now).await
    };

    if user.passkey_user_handle.is_none() {
        user.passkey_user_handle = Some(uuid::Uuid::new_v4().to_string());
        user.updated_at = chrono::Utc::now().to_rfc3339();
        state
            .users
            .write()
            .insert(user.user_id.clone(), user.clone());
        let _ = persist_user_if_configured(&state, &user).await;
    }

    let user_handle = user
        .passkey_user_handle
        .as_deref()
        .and_then(|value| uuid::Uuid::parse_str(value).ok())
        .unwrap_or_else(uuid::Uuid::new_v4);

    let registration = runtime.webauthn.start_passkey_registration(
        user_handle,
        user.email.as_str(),
        user.name.as_str(),
        None,
    );

    let (creation_response, registration_state) = match registration {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "passkey_registration_start_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    let request_id = uuid::Uuid::new_v4().to_string();
    state.passkey_registrations.write().insert(
        request_id.clone(),
        PasskeyRegistrationStateRecord {
            user_id: user.user_id.clone(),
            state: registration_state,
            expires_at: chrono::Utc::now() + chrono::Duration::minutes(10),
        },
    );

    (
        StatusCode::OK,
        Json(PasskeyRegistrationStartResponse {
            request_id,
            options: serde_json::to_value(creation_response)
                .unwrap_or_else(|_| serde_json::json!({})),
        }),
    )
        .into_response()
}

async fn auth_passkey_register_finish(
    State(state): State<ApiState>,
    Json(input): Json<PasskeyRegistrationFinishRequest>,
) -> impl IntoResponse {
    let Some(runtime) = state.webauthn_runtime.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "passkey_unavailable"
            })),
        )
            .into_response();
    };

    let Some(pending) = state
        .passkey_registrations
        .write()
        .remove(input.request_id.as_str())
    else {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_request_id"
            })),
        )
            .into_response();
    };

    if pending.expires_at <= chrono::Utc::now() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "request_expired"
            })),
        )
            .into_response();
    }

    let credential = match runtime
        .webauthn
        .finish_passkey_registration(&input.credential, &pending.state)
    {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "passkey_registration_finish_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    let entry = PasskeyRecord {
        passkey_id: uuid::Uuid::new_v4().to_string(),
        user_id: pending.user_id.clone(),
        credential,
        created_at: chrono::Utc::now().to_rfc3339(),
        last_used_at: None,
    };
    state
        .passkeys_by_user
        .write()
        .entry(pending.user_id.clone())
        .or_default()
        .push(entry.clone());
    let _ = persist_passkeys_if_configured(&state, pending.user_id.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "passkey_id": entry.passkey_id
        })),
    )
        .into_response()
}

async fn auth_passkey_login_start(
    State(state): State<ApiState>,
    Json(input): Json<PasskeyLoginStartRequest>,
) -> impl IntoResponse {
    let Some(runtime) = state.webauthn_runtime.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "passkey_unavailable"
            })),
        )
            .into_response();
    };

    let requested_email = input
        .email
        .as_deref()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty());

    let (user_id, passkeys) = if let Some(email) = requested_email {
        let Some(user) = state
            .users
            .read()
            .values()
            .find(|value| value.email == email)
            .cloned()
        else {
            return (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({
                    "error": "user_not_found"
                })),
            )
                .into_response();
        };

        let passkeys = state
            .passkeys_by_user
            .read()
            .get(&user.user_id)
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .map(|entry| entry.credential)
            .collect::<Vec<_>>();
        (Some(user.user_id), passkeys)
    } else {
        let passkeys = state
            .passkeys_by_user
            .read()
            .values()
            .flat_map(|entries| entries.iter().map(|entry| entry.credential.clone()))
            .collect::<Vec<_>>();
        (None, passkeys)
    };

    if passkeys.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "no_passkeys_registered"
            })),
        )
            .into_response();
    }

    let authentication = runtime
        .webauthn
        .start_passkey_authentication(passkeys.as_slice());
    let (request, auth_state) = match authentication {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "passkey_login_start_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    let request_id = uuid::Uuid::new_v4().to_string();
    state.passkey_authentications.write().insert(
        request_id.clone(),
        PasskeyAuthenticationStateRecord {
            user_id,
            state: auth_state,
            expires_at: chrono::Utc::now() + chrono::Duration::minutes(8),
        },
    );

    (
        StatusCode::OK,
        Json(PasskeyLoginStartResponse {
            request_id,
            options: serde_json::to_value(request).unwrap_or_else(|_| serde_json::json!({})),
        }),
    )
        .into_response()
}

async fn auth_passkey_login_finish(
    State(state): State<ApiState>,
    Json(input): Json<PasskeyLoginFinishRequest>,
) -> impl IntoResponse {
    let Some(runtime) = state.webauthn_runtime.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "passkey_unavailable"
            })),
        )
            .into_response();
    };

    let Some(pending) = state
        .passkey_authentications
        .write()
        .remove(input.request_id.as_str())
    else {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_request_id"
            })),
        )
            .into_response();
    };

    if pending.expires_at <= chrono::Utc::now() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "request_expired"
            })),
        )
            .into_response();
    }

    let auth_result: AuthenticationResult = match runtime
        .webauthn
        .finish_passkey_authentication(&input.credential, &pending.state)
    {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "passkey_authentication_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };
    let resolved_user_id = pending.user_id.or_else(|| {
        resolve_user_id_for_passkey_credential(&state, auth_result.cred_id().as_slice())
    });
    let Some(user_id) = resolved_user_id else {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "user_not_found"
            })),
        )
            .into_response();
    };
    let Some(user) = state.users.read().get(&user_id).cloned() else {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "user_not_found"
            })),
        )
            .into_response();
    };

    let session_id = match issue_session_for_user(&state, &user).await {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "error": "session_issue_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    update_passkey_credential_usage(&state, user.user_id.as_str(), &auth_result);
    let _ = persist_passkeys_if_configured(&state, user.user_id.as_str()).await;

    let token = format!("session-{}", session_id);
    let mut response = (
        StatusCode::OK,
        Json(AuthResponse {
            token,
            user,
            session_expires_at: (chrono::Utc::now()
                + chrono::Duration::seconds(state.session_ttl.as_secs() as i64))
            .to_rfc3339(),
        }),
    )
        .into_response();
    let cookie_value = build_session_cookie(
        &state.cookie_name,
        session_id.as_str(),
        state.session_ttl.as_secs(),
        state.cookie_secure,
        state.cookie_same_site.as_str(),
        state.cookie_domain.as_str(),
    );
    if let Ok(header_value) = HeaderValue::from_str(&cookie_value) {
        response
            .headers_mut()
            .insert(header::SET_COOKIE, header_value);
    }
    response
}

async fn chat(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(mut request): Json<ChatRequest>,
) -> impl IntoResponse {
    let session_user = session_user_from_headers(&state, &headers);
    if let Some(user) = session_user.as_ref() {
        request.user_id = Some(user.user_id.clone());
    }
    let request_user_id = request.user_id.clone();
    let include_proactive = request.include_proactive.unwrap_or(true);

    let input = ChatInput {
        session_id: request.session_id.clone(),
        text: request.text.clone(),
        locale: request.locale.clone(),
        user_id: request.user_id.clone(),
    };

    match state.agent.handle_chat(input).await {
        Ok(mut response) => {
            let resolved_user = session_user.clone().or_else(|| {
                request_user_id
                    .as_ref()
                    .and_then(|user_id| state.users.read().get(user_id).cloned())
            });

            if let Some(user) = resolved_user {
                let stored_studio_pref = state
                    .studio_preferences
                    .read()
                    .get(&user.user_id)
                    .cloned()
                    .unwrap_or_else(|| default_studio_preferences(&user.user_id));
                let effective_studio_pref = merge_studio_preferences(
                    stored_studio_pref,
                    request_overrides_to_studio(&request),
                );

                response.reply_text = apply_studio_format(
                    response.reply_text,
                    &effective_studio_pref,
                    response.locale,
                    &user,
                );

                let survey_state = state.survey_states.read().get(&user.user_id).cloned();
                let survey_hints = survey_state
                    .as_ref()
                    .map(build_survey_hints)
                    .unwrap_or_default();
                let note_items = state
                    .user_notes
                    .read()
                    .get(&user.user_id)
                    .cloned()
                    .unwrap_or_default();

                // Base suggested actions that make daily follow-through easier.
                response.suggested_actions.push(atlas_core::SuggestedAction {
                    action_type: "create_reminder".to_string(),
                    label: match response.locale {
                        atlas_core::Locale::He => "יצירת תזכורת".to_string(),
                        _ => "Create reminder".to_string(),
                    },
                    payload: serde_json::json!({
                        "title": "Atlas Masa follow-up",
                        "details": "Review plan and execute first action",
                        "due_at_utc": (chrono::Utc::now() + chrono::Duration::hours(2)).to_rfc3339(),
                        "reminders_app": effective_studio_pref.reminders_app
                    }),
                });
                response
                    .suggested_actions
                    .push(atlas_core::SuggestedAction {
                        action_type: "create_alarm".to_string(),
                        label: match response.locale {
                            atlas_core::Locale::He => "יצירת אזעקה".to_string(),
                            _ => "Create alarm".to_string(),
                        },
                        payload: serde_json::json!({
                            "label": "Atlas Masa focus sprint",
                            "time_local": "08:30",
                            "days": ["Mon", "Tue", "Wed", "Thu", "Sun"],
                            "alarms_app": effective_studio_pref.alarms_app
                        }),
                    });

                if let Some(payload_obj) = response.json_payload.as_object_mut() {
                    payload_obj
                        .insert("input_user_id".to_string(), serde_json::json!(user.user_id));
                    payload_obj.insert("user_profile".to_string(), serde_json::json!(user));
                    payload_obj.insert(
                        "studio_preferences".to_string(),
                        serde_json::json!(effective_studio_pref),
                    );
                    payload_obj.insert("survey_hints".to_string(), serde_json::json!(survey_hints));
                    if include_proactive {
                        payload_obj.insert(
                            "proactive_feed".to_string(),
                            serde_json::json!(build_proactive_feed(
                                &state.company_status,
                                &user,
                                Some(&effective_studio_pref),
                                survey_state.as_ref(),
                                Some(note_items.as_slice()),
                            )),
                        );
                    }
                }
            } else {
                // Guest formatting fallback.
                let guest_pref = merge_studio_preferences(
                    default_studio_preferences("guest"),
                    request_overrides_to_studio(&request),
                );
                response.reply_text =
                    apply_studio_format_guest(response.reply_text, &guest_pref, response.locale);
                response.suggested_actions.push(atlas_core::SuggestedAction {
                    action_type: "create_reminder".to_string(),
                    label: match response.locale {
                        atlas_core::Locale::He => "יצירת תזכורת".to_string(),
                        _ => "Create reminder".to_string(),
                    },
                    payload: serde_json::json!({
                        "title": "Atlas Masa guest follow-up",
                        "details": "Execute your next step",
                        "due_at_utc": (chrono::Utc::now() + chrono::Duration::hours(2)).to_rfc3339(),
                        "reminders_app": guest_pref.reminders_app
                    }),
                });
                response
                    .suggested_actions
                    .push(atlas_core::SuggestedAction {
                        action_type: "create_alarm".to_string(),
                        label: match response.locale {
                            atlas_core::Locale::He => "יצירת אזעקה".to_string(),
                            _ => "Create alarm".to_string(),
                        },
                        payload: serde_json::json!({
                            "label": "Atlas guest focus sprint",
                            "time_local": "08:30",
                            "days": ["Mon", "Tue", "Wed", "Thu", "Sun"],
                            "alarms_app": guest_pref.alarms_app
                        }),
                    });
            }

            let premium_user = session_user.or_else(|| {
                request_user_id
                    .as_ref()
                    .and_then(|user_id| state.users.read().get(user_id).cloned())
            });
            if state.openai_runtime.is_some() {
                let survey_state = premium_user
                    .as_ref()
                    .and_then(|user| state.survey_states.read().get(&user.user_id).cloned());
                let notes = premium_user
                    .as_ref()
                    .map(|user| {
                        state
                            .user_notes
                            .read()
                            .get(&user.user_id)
                            .cloned()
                            .unwrap_or_default()
                    })
                    .unwrap_or_default();
                if let Ok(premium_reply) = generate_premium_openai_reply(
                    &state,
                    &request,
                    premium_user.as_ref(),
                    survey_state.as_ref(),
                    &notes,
                    response.reply_text.as_str(),
                )
                .await
                {
                    response.reply_text = premium_reply;
                    if let Some(payload_obj) = response.json_payload.as_object_mut() {
                        payload_obj.insert(
                            "ai_backend".to_string(),
                            serde_json::json!("openai_responses"),
                        );
                        payload_obj.insert(
                            "ai_model".to_string(),
                            serde_json::json!(state
                                .openai_runtime
                                .as_ref()
                                .map(|cfg| cfg.model.clone())
                                .unwrap_or_default()),
                        );
                    }
                }
            }

            (StatusCode::OK, Json(response)).into_response()
        }
        Err(error) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({
                "error": "chat_failed",
                "message": error.to_string()
            })),
        )
            .into_response(),
    }
}

async fn social_login(State(_state): State<ApiState>) -> impl IntoResponse {
    (
        StatusCode::GONE,
        Json(serde_json::json!({
            "error": "legacy_auth_retired",
            "message": "Legacy /v1/auth/social_login is permanently disabled in strict passwordless mode.",
            "allowed_methods": [
                "/v1/auth/google/start",
                "/v1/auth/apple/start",
                "/v1/auth/passkey/register/start",
                "/v1/auth/passkey/login/start"
            ]
        })),
    )
        .into_response()
}

async fn auth_logout(State(state): State<ApiState>, headers: HeaderMap) -> impl IntoResponse {
    if let Some(session_id) = read_cookie_value(&headers, &state.cookie_name) {
        state.sessions.write().remove(&session_id);
        let _ = persist_sessions_if_configured(&state).await;
    }

    let mut response = (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true
        })),
    )
        .into_response();
    let clear_cookie = build_clear_cookie(
        &state.cookie_name,
        state.cookie_secure,
        state.cookie_same_site.as_str(),
        state.cookie_domain.as_str(),
    );
    if let Ok(header_value) = HeaderValue::from_str(&clear_cookie) {
        response
            .headers_mut()
            .insert(header::SET_COOKIE, header_value);
    }
    response
}

async fn profile_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ProfileUpsertRequest>,
) -> impl IntoResponse {
    let session_user = session_user_from_headers(&state, &headers);
    if let (Some(from_session), Some(from_body)) = (session_user.as_ref(), input.user_id.as_ref()) {
        if from_session.user_id != *from_body {
            return (
                StatusCode::FORBIDDEN,
                Json(serde_json::json!({
                    "error": "user_mismatch",
                    "message": "signed-in user does not match requested user_id"
                })),
            )
                .into_response();
        }
    }

    let target_user_id = session_user
        .as_ref()
        .map(|user| user.user_id.clone())
        .or(input.user_id.clone());

    let Some(target_user_id) = target_user_id else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    let user_clone = {
        let mut users = state.users.write();
        let Some(user) = users.get_mut(&target_user_id) else {
            return (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({
                    "error": "user_not_found",
                    "message": "sign in first"
                })),
            )
                .into_response();
        };

        if let Some(style) = input.trip_style {
            let style = sanitize_limited_text(style.as_str(), MAX_PROFILE_FIELD_LEN);
            if !style.is_empty() {
                user.trip_style = Some(sanitize_enum_value(
                    style.as_str(),
                    &["mixed", "beach", "north", "desert", "business", "nature"],
                    "mixed",
                ));
            }
        }
        if let Some(risk) = input.risk_preference {
            let risk = sanitize_limited_text(risk.as_str(), MAX_PROFILE_FIELD_LEN);
            if !risk.is_empty() {
                user.risk_preference = Some(sanitize_enum_value(
                    risk.as_str(),
                    &["low", "medium", "high"],
                    "medium",
                ));
            }
        }
        if let Some(opt_in) = input.memory_opt_in {
            user.memory_opt_in = opt_in;
        }
        if let Some(locale) = input.locale {
            let locale = sanitize_limited_text(locale.as_str(), MAX_PROFILE_FIELD_LEN);
            if !locale.is_empty() {
                user.locale =
                    sanitize_enum_value(locale.as_str(), &["he", "en", "ar", "ru", "fr"], "he");
            }
        }
        user.updated_at = chrono::Utc::now().to_rfc3339();
        user.clone()
    };
    let _ = persist_user_if_configured(&state, &user_clone).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "user": user_clone
        })),
    )
        .into_response()
}

async fn auth_me(State(state): State<ApiState>, headers: HeaderMap) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated"
            })),
        )
            .into_response();
    };

    let bypass = is_subscription_bypass_email(user.email.as_str());
    let active_subscription = if bypass {
        true
    } else {
        user_has_active_subscription(&state, user.user_id.as_str())
            .await
            .unwrap_or(false)
    };

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "user": user,
            "subscription": {
                "bypass": bypass,
                "active": active_subscription,
                "tier": if bypass { "owner_bypass" } else if active_subscription { "subscriber" } else { "standard" }
            }
        })),
    )
        .into_response()
}

async fn user_has_active_subscription(state: &ApiState, user_id: &str) -> Result<bool> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(false);
    };

    let row = sqlx::query("SELECT status FROM billing_subscriptions WHERE user_id = ?1 LIMIT 1")
        .bind(user_id)
        .fetch_optional(pool)
        .await?;

    let status = row
        .and_then(|value| value.try_get::<String, _>("status").ok())
        .unwrap_or_default()
        .to_ascii_lowercase();
    Ok(matches!(
        status.as_str(),
        "active" | "trialing" | "owner_bypass"
    ))
}

async fn notes_list(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<NotesQuery>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, query.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated",
                    "message": "sign in first"
                })),
            )
                .into_response()
        }
    };

    let items = state
        .user_notes
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_default();

    (StatusCode::OK, Json(serde_json::json!({ "notes": items }))).into_response()
}

async fn note_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<NoteUpsertRequest>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, input.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated",
                    "message": "sign in first"
                })),
            )
                .into_response()
        }
    };

    let title = sanitize_limited_text(input.title.as_str(), MAX_NOTE_TITLE_LEN);
    let content = sanitize_limited_text(input.content.as_str(), MAX_NOTE_CONTENT_LEN);

    if title.is_empty() || content.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_note",
                "message": "title and content are required"
            })),
        )
            .into_response();
    }

    let note_id = input
        .note_id
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
    let note = UserNoteRecord {
        note_id: note_id.clone(),
        user_id: user_id.clone(),
        title,
        content,
        tags: sanitize_note_tags(input.tags.unwrap_or_default()),
        updated_at: chrono::Utc::now().to_rfc3339(),
    };

    {
        let mut notes_map = state.user_notes.write();
        let notes = notes_map.entry(user_id.clone()).or_default();
        if let Some(existing) = notes.iter_mut().find(|entry| entry.note_id == note_id) {
            *existing = note.clone();
        } else {
            notes.push(note.clone());
        }
        notes.sort_by(|lhs, rhs| rhs.updated_at.cmp(&lhs.updated_at));
    }
    let _ = persist_notes_if_configured(&state, user_id.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "note": note
        })),
    )
        .into_response()
}

async fn note_rewrite(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<NoteRewriteRequest>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, input.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated"
                })),
            )
                .into_response()
        }
    };

    let note = state.user_notes.read().get(&user_id).and_then(|list| {
        list.iter()
            .find(|entry| entry.note_id == input.note_id)
            .cloned()
    });
    let Some(note) = note else {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "note_not_found"
            })),
        )
            .into_response();
    };

    let instruction = sanitize_limited_text(
        input
            .instruction
            .unwrap_or_else(|| {
                "Rewrite this note into an executive action brief with immediate tasks, mid-term strategy, and long-term mission alignment.".to_string()
            })
            .as_str(),
        MAX_REWRITE_INSTRUCTION_LEN,
    );
    let rewritten = match rewrite_note_with_openai(&state, &note, instruction.as_str()).await {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({
                    "error": "note_rewrite_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    let rewritten_note = UserNoteRecord {
        note_id: note.note_id.clone(),
        user_id: note.user_id.clone(),
        title: note.title.clone(),
        content: rewritten,
        tags: note.tags.clone(),
        updated_at: chrono::Utc::now().to_rfc3339(),
    };
    {
        let mut notes_map = state.user_notes.write();
        let notes = notes_map.entry(user_id.clone()).or_default();
        if let Some(existing) = notes
            .iter_mut()
            .find(|entry| entry.note_id == rewritten_note.note_id)
        {
            *existing = rewritten_note.clone();
        } else {
            notes.push(rewritten_note.clone());
        }
    }
    let _ = persist_notes_if_configured(&state, user_id.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "note": rewritten_note
        })),
    )
        .into_response()
}

async fn memory_import(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<MemoryImportRequest>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, input.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated",
                    "message": "sign in first"
                })),
            )
                .into_response()
        }
    };

    if input.items.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "memory_items_required",
                "message": "at least one memory item is required"
            })),
        )
            .into_response();
    }
    if input.items.len() > MAX_MEMORY_IMPORT_ITEMS {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "memory_batch_too_large",
                "message": format!("max {} items per import request", MAX_MEMORY_IMPORT_ITEMS)
            })),
        )
            .into_response();
    }

    let now = chrono::Utc::now();
    let mut imported = Vec::new();
    for item in input.items {
        let title = sanitize_limited_text(item.title.as_str(), MAX_NOTE_TITLE_LEN);
        let content = sanitize_limited_text(item.content.as_str(), MAX_NOTE_CONTENT_LEN);
        if title.is_empty() || content.is_empty() {
            continue;
        }

        let mut tags = sanitize_note_tags(item.tags.unwrap_or_default());
        if let Some(source) = item.source {
            let source_tag = normalize_tag(source.as_str());
            if !source_tag.is_empty() {
                tags.push(format!("source_{}", source_tag));
            }
        }
        tags = sanitize_note_tags(tags);

        imported.push(UserNoteRecord {
            note_id: uuid::Uuid::new_v4().to_string(),
            user_id: user_id.clone(),
            title,
            content,
            tags,
            updated_at: parse_or_default_utc(item.happened_at.as_deref(), now).to_rfc3339(),
        });
    }

    if imported.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "no_valid_memory_items",
                "message": "all imported items were empty after sanitization"
            })),
        )
            .into_response();
    }

    let imported_count = imported.len();
    {
        let mut notes_map = state.user_notes.write();
        let notes = notes_map.entry(user_id.clone()).or_default();
        notes.extend(imported);
        notes.sort_by(|lhs, rhs| rhs.updated_at.cmp(&lhs.updated_at));
        notes.truncate(MAX_NOTES_PER_USER);
    }

    let _ = persist_notes_if_configured(&state, user_id.as_str()).await;
    let total_notes = state
        .user_notes
        .read()
        .get(&user_id)
        .map(|items| items.len())
        .unwrap_or(0);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "imported": imported_count,
            "total_notes": total_notes
        })),
    )
        .into_response()
}

async fn billing_create_checkout_session(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(_input): Json<BillingCheckoutRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    if is_subscription_bypass_email(user.email.as_str()) {
        let now = chrono::Utc::now().to_rfc3339();
        let billing = BillingStatusRecord {
            user_id: user.user_id.clone(),
            stripe_customer_id: None,
            stripe_subscription_id: None,
            status: "owner_bypass".to_string(),
            current_period_end: None,
            updated_at: now,
        };
        let _ = persist_billing_status_if_configured(&state, &billing).await;

        return (
            StatusCode::OK,
            Json(serde_json::json!({
                "checkout_url": "https://atlasmasa.com/concierge-local.html?billing=owner_bypass",
                "checkout_session_id": "owner-bypass",
                "bypass": true
            })),
        )
            .into_response();
    }

    let Some(runtime) = state.billing_runtime.as_ref() else {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(serde_json::json!({
                "error": "billing_unavailable",
                "message": "Stripe billing is not configured"
            })),
        )
            .into_response();
    };

    // Authoritative billing config is server-side only. Do not allow client overrides
    // for Stripe price IDs or redirect URLs to prevent plan tampering/open redirects.
    let price_id = runtime.monthly_price_id.clone();
    let success_url = runtime.success_url.clone();
    let cancel_url = runtime.cancel_url.clone();

    let response = match state
        .http_client
        .post("https://api.stripe.com/v1/checkout/sessions")
        .bearer_auth(runtime.stripe_secret_key.as_str())
        .form(&[
            ("mode", "subscription"),
            ("line_items[0][price]", price_id.as_str()),
            ("line_items[0][quantity]", "1"),
            ("payment_method_types[0]", "card"),
            ("success_url", success_url.as_str()),
            ("cancel_url", cancel_url.as_str()),
            ("allow_promotion_codes", "true"),
            ("automatic_tax[enabled]", "true"),
            ("customer_email", user.email.as_str()),
            ("client_reference_id", user.user_id.as_str()),
            ("metadata[user_id]", user.user_id.as_str()),
            ("metadata[product]", "atlas_masa_pro"),
            (
                "subscription_data[metadata][user_id]",
                user.user_id.as_str(),
            ),
        ])
        .send()
        .await
    {
        Ok(value) => value,
        Err(error) => {
            return (
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({
                    "error": "stripe_network_failed",
                    "message": error.to_string()
                })),
            )
                .into_response()
        }
    };

    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    if !status.is_success() {
        return (
            StatusCode::BAD_GATEWAY,
            Json(serde_json::json!({
                "error": "stripe_checkout_failed",
                "status": status.as_u16(),
                "response": body
            })),
        )
            .into_response();
    }

    let parsed: serde_json::Value = serde_json::from_str(body.as_str()).unwrap_or_default();
    let checkout_url = parsed
        .get("url")
        .and_then(|value| value.as_str())
        .unwrap_or_default()
        .to_string();
    let session_id = parsed
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or_default()
        .to_string();

    if checkout_url.is_empty() || session_id.is_empty() {
        return (
            StatusCode::BAD_GATEWAY,
            Json(serde_json::json!({
                "error": "stripe_checkout_parse_failed"
            })),
        )
            .into_response();
    }

    (
        StatusCode::OK,
        Json(BillingCheckoutResponse {
            checkout_url,
            checkout_session_id: session_id,
        }),
    )
        .into_response()
}

async fn billing_stripe_webhook(
    State(state): State<ApiState>,
    headers: HeaderMap,
    body: String,
) -> impl IntoResponse {
    let Some(runtime) = state.billing_runtime.as_ref() else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };

    if let Some(secret) = runtime.stripe_webhook_secret.as_ref() {
        let signature = headers
            .get("stripe-signature")
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default();
        if !verify_stripe_webhook_signature(signature, body.as_str(), secret.as_str()) {
            return StatusCode::UNAUTHORIZED.into_response();
        }
    }

    let event: serde_json::Value = match serde_json::from_str(body.as_str()) {
        Ok(value) => value,
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };

    let event_type = event
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or_default();
    let object = event
        .get("data")
        .and_then(|value| value.get("object"))
        .cloned()
        .unwrap_or_default();

    match event_type {
        "checkout.session.completed" => {
            let user_id = object
                .get("metadata")
                .and_then(|value| value.get("user_id"))
                .and_then(|value| value.as_str())
                .map(|value| value.to_string())
                .or_else(|| {
                    object
                        .get("customer_details")
                        .and_then(|value| value.get("email"))
                        .and_then(|value| value.as_str())
                        .and_then(|email| {
                            state
                                .users
                                .read()
                                .values()
                                .find(|user| user.email == email.to_lowercase())
                                .map(|user| user.user_id.clone())
                        })
                });

            if let Some(user_id) = user_id {
                let billing = BillingStatusRecord {
                    user_id: user_id.clone(),
                    stripe_customer_id: object
                        .get("customer")
                        .and_then(|value| value.as_str())
                        .map(|value| value.to_string()),
                    stripe_subscription_id: object
                        .get("subscription")
                        .and_then(|value| value.as_str())
                        .map(|value| value.to_string()),
                    status: "active".to_string(),
                    current_period_end: None,
                    updated_at: chrono::Utc::now().to_rfc3339(),
                };
                let _ = persist_billing_status_if_configured(&state, &billing).await;
            }
        }
        "customer.subscription.updated" | "customer.subscription.deleted" => {
            let subscription_id = object
                .get("id")
                .and_then(|value| value.as_str())
                .unwrap_or_default()
                .to_string();
            let customer_id = object
                .get("customer")
                .and_then(|value| value.as_str())
                .map(|value| value.to_string());
            let status = object
                .get("status")
                .and_then(|value| value.as_str())
                .unwrap_or("unknown")
                .to_string();
            let period_end = object
                .get("current_period_end")
                .and_then(|value| value.as_i64())
                .and_then(|epoch| chrono::DateTime::<chrono::Utc>::from_timestamp(epoch, 0))
                .map(|value| value.to_rfc3339());

            let user_id_from_customer = if let Some(customer) = customer_id.as_ref() {
                resolve_user_id_by_customer(&state, customer.as_str()).await
            } else {
                None
            };
            if let Some(user_id) = user_id_from_customer {
                let billing = BillingStatusRecord {
                    user_id,
                    stripe_customer_id: customer_id,
                    stripe_subscription_id: Some(subscription_id),
                    status,
                    current_period_end: period_end,
                    updated_at: chrono::Utc::now().to_rfc3339(),
                };
                let _ = persist_billing_status_if_configured(&state, &billing).await;
            }
        }
        _ => {}
    }

    StatusCode::OK.into_response()
}

async fn studio_preferences_get(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<UserLookupQuery>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, query.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated",
                    "message": "sign in first"
                })),
            )
                .into_response();
        }
    };

    let prefs = state
        .studio_preferences
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(&user_id));

    (
        StatusCode::OK,
        Json(serde_json::json!({ "preferences": prefs })),
    )
        .into_response()
}

async fn studio_preferences_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<StudioPreferencesUpsertRequest>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, input.user_id.clone()) {
        Some(value) => value,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "not_authenticated",
                    "message": "sign in first"
                })),
            )
                .into_response();
        }
    };

    let merged = {
        let mut prefs_map = state.studio_preferences.write();
        let current = prefs_map
            .get(&user_id)
            .cloned()
            .unwrap_or_else(|| default_studio_preferences(&user_id));
        let merged = merge_studio_preferences(current, input);
        prefs_map.insert(user_id, merged.clone());
        merged
    };
    let _ = persist_studio_preferences_if_configured(&state, merged.user_id.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({ "ok": true, "preferences": merged })),
    )
        .into_response()
}

async fn survey_next(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<UserLookupQuery>,
) -> impl IntoResponse {
    let user_id = resolve_user_id_or_guest(&state, &headers, query.user_id.clone());
    let user_locale = resolve_request_locale(&state, &user_id, query.locale.as_deref());

    let survey_state = state
        .survey_states
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| SurveyStateRecord {
            user_id: user_id.clone(),
            answers: HashMap::new(),
            completed: false,
            started_at: None,
            completed_at: None,
            updated_at: chrono::Utc::now().to_rfc3339(),
        });

    let question = next_survey_question(&user_locale, &survey_state.answers);
    let total = survey_total_questions(&survey_state.answers);
    let answered = survey_state.answers.len().min(total);
    let progress = SurveyProgress {
        answered,
        total,
        percent: if total == 0 {
            0
        } else {
            ((answered as f32 / total as f32) * 100.0).round() as u8
        },
    };

    (
        StatusCode::OK,
        Json(SurveyNextResponse {
            question,
            progress,
            profile_hints: build_survey_hints(&survey_state),
        }),
    )
        .into_response()
}

async fn survey_answer(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<SurveyAnswerRequest>,
) -> impl IntoResponse {
    if input.question_id.trim().is_empty() || input.answer.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_answer",
                "message": "question_id and answer are required"
            })),
        )
            .into_response();
    }

    let user_id = resolve_user_id_or_guest(&state, &headers, input.user_id.clone());
    let user_locale = resolve_request_locale(&state, &user_id, input.locale.as_deref());

    let persisted_user = {
        let mut states = state.survey_states.write();
        let now = chrono::Utc::now();
        let entry = states
            .entry(user_id.clone())
            .or_insert_with(|| SurveyStateRecord {
                user_id: user_id.clone(),
                answers: HashMap::new(),
                completed: false,
                started_at: None,
                completed_at: None,
                updated_at: now.to_rfc3339(),
            });
        if entry.started_at.is_none() {
            entry.started_at = Some(now.to_rfc3339());
        }
        entry.answers.insert(
            input.question_id.trim().to_string(),
            input.answer.trim().to_string(),
        );
        entry.completed = next_survey_question(&user_locale, &entry.answers).is_none();
        entry.completed_at = if entry.completed {
            entry
                .completed_at
                .clone()
                .or_else(|| Some(now.to_rfc3339()))
        } else {
            None
        };
        entry.updated_at = now.to_rfc3339();
        entry.user_id.clone()
    };
    let _ = persist_survey_state_if_configured(&state, persisted_user.as_str()).await;

    if input.question_id.trim() == "trip_style" {
        let normalized = sanitize_enum_value(
            input.answer.trim(),
            &["mixed", "beach", "north", "desert"],
            "mixed",
        );
        let updated_user = {
            let mut users = state.users.write();
            if let Some(user) = users.get_mut(&user_id) {
                user.trip_style = Some(normalized);
                user.updated_at = chrono::Utc::now().to_rfc3339();
                Some(user.clone())
            } else {
                None
            }
        };
        if let Some(user) = updated_user {
            let _ = persist_user_if_configured(&state, &user).await;
        }
    }

    let state_snapshot =
        state
            .survey_states
            .read()
            .get(&user_id)
            .cloned()
            .unwrap_or(SurveyStateRecord {
                user_id: user_id.clone(),
                answers: HashMap::new(),
                completed: false,
                started_at: None,
                completed_at: None,
                updated_at: chrono::Utc::now().to_rfc3339(),
            });

    let total = survey_total_questions(&state_snapshot.answers);
    let answered = state_snapshot.answers.len().min(total);
    let progress = SurveyProgress {
        answered,
        total,
        percent: if total == 0 {
            0
        } else {
            ((answered as f32 / total as f32) * 100.0).round() as u8
        },
    };

    (
        StatusCode::OK,
        Json(SurveyNextResponse {
            question: next_survey_question(&user_locale, &state_snapshot.answers),
            progress,
            profile_hints: build_survey_hints(&state_snapshot),
        }),
    )
        .into_response()
}

async fn feed_proactive(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<UserLookupQuery>,
) -> impl IntoResponse {
    const MIN_SURVEY_MINUTES: u32 = 20;

    let user_id = resolve_user_id_or_guest(&state, &headers, query.user_id.clone());
    let request_locale = resolve_request_locale(&state, &user_id, query.locale.as_deref());
    let user = state
        .users
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| UserRecord {
            user_id: user_id.clone(),
            provider: "guest".to_string(),
            email: "guest@atlasmasa.local".to_string(),
            name: "Guest".to_string(),
            locale: request_locale.clone(),
            trip_style: Some("mixed".to_string()),
            risk_preference: Some("medium".to_string()),
            memory_opt_in: true,
            passkey_user_handle: None,
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        });
    let mut effective_user = user;
    effective_user.locale = request_locale.clone();

    let studio_pref = state
        .studio_preferences
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(&user_id));
    let survey_state = state.survey_states.read().get(&user_id).cloned();
    let note_items = state
        .user_notes
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_default();
    let elapsed_minutes = survey_state
        .as_ref()
        .and_then(survey_elapsed_minutes)
        .unwrap_or(0);
    let survey_complete = survey_state
        .as_ref()
        .map(|value| value.completed)
        .unwrap_or(false);
    let feed_ready = survey_complete && elapsed_minutes >= MIN_SURVEY_MINUTES;
    let gate_reason = if feed_ready {
        None
    } else if request_locale.starts_with("he") {
        Some(format!(
            "זרם הביצוע ייפתח אחרי השלמת סקר העומק ולאחר לפחות {} דקות תהליך.",
            MIN_SURVEY_MINUTES
        ))
    } else {
        Some(format!(
            "Execution Stream unlocks after completing the adaptive deep survey and at least {} minutes of survey process.",
            MIN_SURVEY_MINUTES
        ))
    };
    let items = if feed_ready {
        build_proactive_feed(
            &state.company_status,
            &effective_user,
            Some(&studio_pref),
            survey_state.as_ref(),
            Some(note_items.as_slice()),
        )
    } else {
        Vec::new()
    };

    (
        StatusCode::OK,
        Json(ProactiveFeedResponse {
            generated_at: chrono::Utc::now().to_rfc3339(),
            items,
            feed_ready,
            gate_reason,
            required_minutes: MIN_SURVEY_MINUTES,
            company_status: state.company_status.clone(),
        }),
    )
        .into_response()
}

async fn company_status(State(state): State<ApiState>) -> impl IntoResponse {
    (StatusCode::OK, Json(state.company_status.clone())).into_response()
}

async fn feedback_submit(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<FeedbackSubmitRequest>,
) -> impl IntoResponse {
    if input.message.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_message",
                "message": "feedback message is required"
            })),
        )
            .into_response();
    }

    let user_id = resolve_user_id(&state, &headers, input.user_id.clone());
    let item = FeedbackRecord {
        feedback_id: uuid::Uuid::new_v4().to_string(),
        user_id,
        category: sanitize_enum_value(
            input.category.trim(),
            &["product", "ux", "bug", "safety", "support", "other"],
            "other",
        ),
        severity: sanitize_enum_value(
            input
                .severity
                .unwrap_or_else(|| "normal".to_string())
                .as_str(),
            &["low", "normal", "high", "critical"],
            "normal",
        ),
        message: input.message.trim().to_string(),
        tags: input.tags.unwrap_or_default(),
        target_employee: input
            .target_employee
            .unwrap_or_else(|| "product_team".to_string())
            .trim()
            .to_lowercase(),
        source: input
            .source
            .unwrap_or_else(|| "web".to_string())
            .trim()
            .to_lowercase(),
        status: "new".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    state.feedback_items.write().push(item.clone());
    let _ = persist_feedback_if_configured(&state).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "feedback": item
        })),
    )
        .into_response()
}

async fn feedback_for_employee(
    State(state): State<ApiState>,
    AxumPath(employee): AxumPath<String>,
    Query(query): Query<FeedbackListQuery>,
) -> impl IntoResponse {
    let employee_normalized = employee.trim().to_lowercase();
    let limit = query.limit.unwrap_or(30).clamp(1, 200);

    let mut items = state
        .feedback_items
        .read()
        .iter()
        .filter(|entry| entry.target_employee == employee_normalized)
        .cloned()
        .collect::<Vec<_>>();
    items.sort_by(|lhs, rhs| rhs.created_at.cmp(&lhs.created_at));
    items.truncate(limit);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "employee": employee_normalized,
            "count": items.len(),
            "items": items
        })),
    )
        .into_response()
}

async fn action_reminder(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ReminderActionRequest>,
) -> impl IntoResponse {
    if input.title.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_title",
                "message": "title is required"
            })),
        )
            .into_response();
    }

    let user_id = resolve_user_id_or_guest(&state, &headers, None);
    let prefs = state
        .studio_preferences
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(&user_id));

    let app = sanitize_enum_value(
        input
            .reminders_app
            .unwrap_or_else(|| prefs.reminders_app.clone())
            .as_str(),
        &[
            "google_calendar",
            "apple_reminders",
            "shortcuts",
            "todoist",
            "notion",
        ],
        "google_calendar",
    );

    let start = parse_or_default_utc(
        input.due_at_utc.as_deref(),
        chrono::Utc::now() + chrono::Duration::hours(2),
    );
    let end = start + chrono::Duration::minutes(input.duration_minutes.unwrap_or(30) as i64);

    let title = input.title.trim();
    let details = input.details.unwrap_or_default();
    let google_calendar_url = format!(
        "https://calendar.google.com/calendar/render?action=TEMPLATE&text={}&details={}&dates={}/{}",
        pct_encode(title),
        pct_encode(details.as_str()),
        start.format("%Y%m%dT%H%M%SZ"),
        end.format("%Y%m%dT%H%M%SZ")
    );

    let ics_content = format!(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//AtlasMasa//Reminder//EN\r\nBEGIN:VEVENT\r\nUID:{}\r\nDTSTAMP:{}\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:{}\r\nDESCRIPTION:{}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        uuid::Uuid::new_v4(),
        chrono::Utc::now().format("%Y%m%dT%H%M%SZ"),
        start.format("%Y%m%dT%H%M%SZ"),
        end.format("%Y%m%dT%H%M%SZ"),
        escape_ics(title),
        escape_ics(details.as_str())
    );
    let shortcuts_payload = format!(
        "Title: {}\nWhen: {}\nDetails: {}",
        title,
        start.to_rfc3339(),
        details
    );
    let shortcuts_url = format!(
        "shortcuts://run-shortcut?name=AtlasMasaReminder&input=text&text={}",
        pct_encode(&shortcuts_payload)
    );

    (
        StatusCode::OK,
        Json(ReminderActionResponse {
            app,
            google_calendar_url,
            ics_filename: "atlas-masa-reminder.ics".to_string(),
            ics_content,
            shortcuts_url,
        }),
    )
        .into_response()
}

async fn action_alarm(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<AlarmActionRequest>,
) -> impl IntoResponse {
    if input.label.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_label",
                "message": "label is required"
            })),
        )
            .into_response();
    }

    if !is_valid_hhmm(&input.time_local) {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_time",
                "message": "time_local must be HH:MM"
            })),
        )
            .into_response();
    }

    let user_id = resolve_user_id_or_guest(&state, &headers, None);
    let prefs = state
        .studio_preferences
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(&user_id));
    let app = sanitize_enum_value(
        input
            .alarms_app
            .unwrap_or_else(|| prefs.alarms_app.clone())
            .as_str(),
        &["apple_clock", "google_clock", "shortcuts"],
        "apple_clock",
    );

    let days = input.days.unwrap_or_else(|| {
        vec![
            "Sun".to_string(),
            "Mon".to_string(),
            "Tue".to_string(),
            "Wed".to_string(),
            "Thu".to_string(),
        ]
    });
    let payload = format!(
        "Label: {}\nTime: {}\nDays: {}",
        input.label.trim(),
        input.time_local.trim(),
        days.join(",")
    );
    let shortcuts_url = format!(
        "shortcuts://run-shortcut?name=AtlasMasaAlarm&input=text&text={}",
        pct_encode(&payload)
    );

    (
        StatusCode::OK,
        Json(AlarmActionResponse {
            app,
            clock_url: "clock://".to_string(),
            shortcuts_url,
            fallback_instructions:
                "Open your Clock app and paste the suggested label/time if automation is unavailable."
                    .to_string(),
        }),
    )
        .into_response()
}

async fn plan_trip(
    State(state): State<ApiState>,
    Json(input): Json<TripPlanRequest>,
) -> impl IntoResponse {
    match state.agent.plan_trip(input).await {
        Ok(response) => (StatusCode::OK, Json(response)).into_response(),
        Err(error) => (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "plan_trip_failed",
                "message": error.to_string()
            })),
        )
            .into_response(),
    }
}

async fn api_key_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request.method() == Method::OPTIONS || is_public_endpoint(request.uri().path()) {
        return next.run(request).await;
    }

    let header_key = request
        .headers()
        .get("x-api-key")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();

    if header_key != state.api_key {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "unauthorized",
                "message": "missing or invalid x-api-key"
            })),
        )
            .into_response();
    }

    next.run(request).await
}

fn session_user_from_headers(state: &ApiState, headers: &HeaderMap) -> Option<UserRecord> {
    let session_id = read_cookie_value(headers, &state.cookie_name)?;

    let session = {
        let mut sessions = state.sessions.write();
        let now = chrono::Utc::now();

        match sessions.get(&session_id).cloned() {
            Some(session) if session.expires_at > now => Some(session),
            Some(_) => {
                sessions.remove(&session_id);
                None
            }
            None => None,
        }
    }?;

    state.users.read().get(&session.user_id).cloned()
}

fn read_cookie_value(headers: &HeaderMap, cookie_name: &str) -> Option<String> {
    let raw_cookie = headers.get(header::COOKIE)?.to_str().ok()?;
    raw_cookie.split(';').find_map(|part| {
        let mut split = part.trim().splitn(2, '=');
        let key = split.next()?.trim();
        let value = split.next()?.trim();
        if key == cookie_name {
            Some(value.to_string())
        } else {
            None
        }
    })
}

fn cookie_same_site_attr(value: &str) -> &'static str {
    match value.trim().to_ascii_lowercase().as_str() {
        "none" => "None",
        "lax" => "Lax",
        _ => "Strict",
    }
}

fn build_session_cookie(
    cookie_name: &str,
    session_id: &str,
    max_age_seconds: u64,
    secure: bool,
    same_site: &str,
    domain: &str,
) -> String {
    let mut segments = vec![
        format!("{cookie_name}={session_id}"),
        "Path=/".to_string(),
        "HttpOnly".to_string(),
        format!("SameSite={}", cookie_same_site_attr(same_site)),
        format!("Max-Age={max_age_seconds}"),
    ];
    if secure {
        segments.push("Secure".to_string());
    }
    segments.push(format!("Domain={domain}"));
    segments.join("; ")
}

fn build_clear_cookie(cookie_name: &str, secure: bool, same_site: &str, domain: &str) -> String {
    let mut segments = vec![
        format!("{cookie_name}="),
        "Path=/".to_string(),
        "HttpOnly".to_string(),
        format!("SameSite={}", cookie_same_site_attr(same_site)),
        "Max-Age=0".to_string(),
        "Expires=Thu, 01 Jan 1970 00:00:00 GMT".to_string(),
    ];
    if secure {
        segments.push("Secure".to_string());
    }
    segments.push(format!("Domain={domain}"));
    segments.join("; ")
}

fn default_company_status() -> CompanyStatusRecord {
    CompanyStatusRecord {
        phase: "Build now, launch in controlled stages".to_string(),
        current_focus: vec![
            "Mobile-first AI concierge and studio".to_string(),
            "Deep personalization and proactive support".to_string(),
            "Atlas Masa travel/work ecosystem MVP".to_string(),
        ],
        upcoming: vec![
            "Expanded user account intelligence".to_string(),
            "Vehicle integration APIs".to_string(),
            "Pilot-ready operations and legal routing".to_string(),
        ],
        open_for_investment: true,
        message: "Atlas Masa is open to strategic partnerships and investments while building a long-term mobility ecosystem.".to_string(),
    }
}

fn resolve_user_id(
    state: &ApiState,
    headers: &HeaderMap,
    explicit_user_id: Option<String>,
) -> Option<String> {
    let session_user = session_user_from_headers(state, headers)?;
    if let Some(from_body) = explicit_user_id.as_ref() {
        if from_body != &session_user.user_id {
            return None;
        }
    }
    Some(session_user.user_id)
}

fn resolve_user_id_or_guest(
    state: &ApiState,
    headers: &HeaderMap,
    explicit_user_id: Option<String>,
) -> String {
    resolve_user_id(state, headers, explicit_user_id).unwrap_or_else(|| "guest".to_string())
}

fn resolve_request_locale(state: &ApiState, user_id: &str, requested: Option<&str>) -> String {
    let requested = requested.unwrap_or_default().trim().to_lowercase();
    if matches!(requested.as_str(), "he" | "en" | "ar" | "ru" | "fr") {
        return requested;
    }
    state
        .users
        .read()
        .get(user_id)
        .map(|user| {
            sanitize_enum_value(user.locale.as_str(), &["he", "en", "ar", "ru", "fr"], "en")
        })
        .unwrap_or_else(|| "en".to_string())
}

fn survey_elapsed_minutes(state: &SurveyStateRecord) -> Option<u32> {
    let start = state
        .started_at
        .as_deref()
        .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())?;
    let end = state
        .completed_at
        .as_deref()
        .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
        .unwrap_or_else(|| chrono::Utc::now().into());
    let duration = end.signed_duration_since(start);
    if duration.num_minutes() < 0 {
        Some(0)
    } else {
        Some(duration.num_minutes() as u32)
    }
}

fn default_studio_preferences(user_id: &str) -> StudioPreferencesRecord {
    StudioPreferencesRecord {
        user_id: user_id.to_string(),
        preferred_format: "structured_plan".to_string(),
        response_depth: "deep".to_string(),
        response_tone: "executive".to_string(),
        proactive_mode: "enabled".to_string(),
        reminders_app: "google_calendar".to_string(),
        alarms_app: "apple_clock".to_string(),
        voice_mode: "enabled".to_string(),
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn merge_studio_preferences(
    mut base: StudioPreferencesRecord,
    incoming: StudioPreferencesUpsertRequest,
) -> StudioPreferencesRecord {
    if let Some(value) = incoming.preferred_format {
        base.preferred_format = sanitize_enum_value(
            value.as_str(),
            &[
                "structured_plan",
                "checklist",
                "step_by_step",
                "concise",
                "timeline",
                "json",
                "notebook_style",
            ],
            "structured_plan",
        );
    }
    if let Some(value) = incoming.response_depth {
        base.response_depth =
            sanitize_enum_value(value.as_str(), &["quick", "balanced", "deep"], "deep");
    }
    if let Some(value) = incoming.response_tone {
        base.response_tone = sanitize_enum_value(
            value.as_str(),
            &["coach", "direct", "calm", "strategic", "executive"],
            "executive",
        );
    }
    if let Some(value) = incoming.proactive_mode {
        base.proactive_mode = sanitize_enum_value(
            value.as_str(),
            &["enabled", "focus_only", "disabled"],
            "enabled",
        );
    }
    if let Some(value) = incoming.reminders_app {
        base.reminders_app = sanitize_enum_value(
            value.as_str(),
            &[
                "google_calendar",
                "apple_reminders",
                "shortcuts",
                "todoist",
                "notion",
            ],
            "google_calendar",
        );
    }
    if let Some(value) = incoming.alarms_app {
        base.alarms_app = sanitize_enum_value(
            value.as_str(),
            &["apple_clock", "google_clock", "shortcuts"],
            "apple_clock",
        );
    }
    if let Some(value) = incoming.voice_mode {
        base.voice_mode = sanitize_enum_value(value.as_str(), &["enabled", "disabled"], "enabled");
    }
    base.updated_at = chrono::Utc::now().to_rfc3339();
    base
}

fn request_overrides_to_studio(request: &ChatRequest) -> StudioPreferencesUpsertRequest {
    StudioPreferencesUpsertRequest {
        user_id: request.user_id.clone(),
        preferred_format: request.preferred_format.clone(),
        response_depth: request.response_depth.clone(),
        response_tone: request.response_tone.clone(),
        proactive_mode: None,
        reminders_app: None,
        alarms_app: None,
        voice_mode: None,
    }
}

fn apply_studio_format(
    base_reply: String,
    prefs: &StudioPreferencesRecord,
    locale: atlas_core::Locale,
    user: &UserRecord,
) -> String {
    let profile_line = if locale == atlas_core::Locale::He {
        format!(
            "פרופיל פעיל: {} | סגנון: {} | סיכון: {}",
            user.name,
            user.trip_style
                .clone()
                .unwrap_or_else(|| "mixed".to_string()),
            user.risk_preference
                .clone()
                .unwrap_or_else(|| "medium".to_string())
        )
    } else {
        format!(
            "Active profile: {} | style: {} | risk: {}",
            user.name,
            user.trip_style
                .clone()
                .unwrap_or_else(|| "mixed".to_string()),
            user.risk_preference
                .clone()
                .unwrap_or_else(|| "medium".to_string())
        )
    };

    format_by_mode(base_reply, prefs, locale, profile_line)
}

fn apply_studio_format_guest(
    base_reply: String,
    prefs: &StudioPreferencesRecord,
    locale: atlas_core::Locale,
) -> String {
    let profile_line = if locale == atlas_core::Locale::He {
        "מצב אורח: אפשר להתחבר כדי לשמור זיכרון ארוך-טווח.".to_string()
    } else {
        "Guest mode: sign in to unlock long-term personalization.".to_string()
    };
    format_by_mode(base_reply, prefs, locale, profile_line)
}

fn format_by_mode(
    base_reply: String,
    prefs: &StudioPreferencesRecord,
    locale: atlas_core::Locale,
    profile_line: String,
) -> String {
    let rendered = match prefs.preferred_format.as_str() {
        "concise" => {
            if locale == atlas_core::Locale::He {
                format!(
                    "{}\n\nתכל'ס עכשיו: בצעו צעד אחד ב-15 הדקות הקרובות.",
                    base_reply
                )
            } else {
                format!(
                    "{}\n\nDo this now: execute one action in the next 15 minutes.",
                    base_reply
                )
            }
        }
        "checklist" => {
            if locale == atlas_core::Locale::He {
                format!(
                    "{}\n\nצ'ק-ליסט ביצוע:\n1) הגדירו יעד קצר.\n2) קבעו זמן ביצוע.\n3) הגדירו תזכורת.\n4) שלחו פידבק אחרי ביצוע.\n\n{}",
                    base_reply, profile_line
                )
            } else {
                format!(
                    "{}\n\nExecution checklist:\n1) Set one short goal.\n2) Set execution time.\n3) Create a reminder.\n4) Send feedback after completion.\n\n{}",
                    base_reply, profile_line
                )
            }
        }
        "step_by_step" => {
            if locale == atlas_core::Locale::He {
                format!(
                    "{}\n\nשלבים:\nשלב 1: בהירות - מה המטרה היום.\nשלב 2: תנועה - מה הפעולה הראשונה.\nשלב 3: רצף - מה הפעולה הבאה אחרי זה.\n\n{}",
                    base_reply, profile_line
                )
            } else {
                format!(
                    "{}\n\nSteps:\nStep 1: Clarity - define today's target.\nStep 2: Motion - execute first action.\nStep 3: Continuity - define next action.\n\n{}",
                    base_reply, profile_line
                )
            }
        }
        "timeline" => {
            if locale == atlas_core::Locale::He {
                format!(
                    "{}\n\nציר זמן מומלץ:\n08:30-10:00 פוקוס עמוק\n10:00-10:15 הפסקת איפוס\n10:15-12:00 ביצוע והתקדמות\n\n{}",
                    base_reply, profile_line
                )
            } else {
                format!(
                    "{}\n\nSuggested timeline:\n08:30-10:00 deep focus\n10:00-10:15 reset break\n10:15-12:00 execution and follow-through\n\n{}",
                    base_reply, profile_line
                )
            }
        }
        "json" => serde_json::json!({
            "mode": "json",
            "tone": prefs.response_tone,
            "depth": prefs.response_depth,
            "profile": profile_line,
            "response": base_reply
        })
        .to_string(),
        "notebook_style" => {
            if locale == atlas_core::Locale::He {
                format!(
                    "סטודיו אטלס: תשובה בפורמט מחברת עבודה\n\nתמצית:\n{}\n\nפעולות מומלצות:\n- הפעלת תזכורת\n- קביעת אזעקת פוקוס\n- בדיקת פיד יזום\n\n{}",
                    base_reply, profile_line
                )
            } else {
                format!(
                    "Atlas Studio response (notebook style)\n\nSummary:\n{}\n\nSuggested actions:\n- trigger reminder\n- set focus alarm\n- review proactive feed\n\n{}",
                    base_reply, profile_line
                )
            }
        }
        _ => format!("{}\n\n{}", base_reply, profile_line),
    };

    if prefs.response_tone == "executive" {
        if locale == atlas_core::Locale::He {
            format!("סטנדרט הנהלה: מסר מדויק, מכובד ותכליתי.\n\n{}", rendered)
        } else {
            format!(
                "Executive standard: precise, high-caliber, and mission-aligned guidance.\n\n{}",
                rendered
            )
        }
    } else {
        rendered
    }
}

fn build_proactive_feed(
    _company_status: &CompanyStatusRecord,
    user: &UserRecord,
    prefs: Option<&StudioPreferencesRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: Option<&[UserNoteRecord]>,
) -> Vec<ProactiveFeedItem> {
    let style = user
        .trip_style
        .clone()
        .unwrap_or_else(|| "mixed".to_string());
    let reminder_app = prefs
        .map(|value| value.reminders_app.clone())
        .unwrap_or_else(|| "google_calendar".to_string());
    let alarm_app = prefs
        .map(|value| value.alarms_app.clone())
        .unwrap_or_else(|| "apple_clock".to_string());

    let mut items = vec![ProactiveFeedItem {
        id: "daily_momentum".to_string(),
        title: if user.locale == "he" {
            "תכנית מומנטום יומית".to_string()
        } else {
            "Daily momentum plan".to_string()
        },
        summary: if user.locale == "he" {
            "להגדיר יעד יומי, להפעיל תזכורת, ולבצע בלוק פוקוס ראשון תוך 30 דקות.".to_string()
        } else {
            "Define one daily target, trigger a reminder, and execute first focus block in 30 minutes."
                .to_string()
        },
        why_now: if user.locale == "he" {
            format!("העדפות פעילות: סגנון {}.", style)
        } else {
            format!("Your profile suggests style={}.", style)
        },
        priority: "high".to_string(),
        actions: vec![
            atlas_core::SuggestedAction {
                action_type: "create_reminder".to_string(),
                label: if user.locale == "he" {
                    "תזכורת לביצוע".to_string()
                } else {
                    "Execution reminder".to_string()
                },
                payload: serde_json::json!({
                    "title": "Atlas Masa daily momentum",
                    "details": "Execute first strategic action now",
                    "due_at_utc": (chrono::Utc::now() + chrono::Duration::minutes(20)).to_rfc3339(),
                    "reminders_app": reminder_app
                }),
            },
            atlas_core::SuggestedAction {
                action_type: "create_alarm".to_string(),
                label: if user.locale == "he" {
                    "אזעקת פוקוס".to_string()
                } else {
                    "Focus alarm".to_string()
                },
                payload: serde_json::json!({
                    "label": "Atlas focus sprint",
                    "time_local": "09:00",
                    "days": ["Sun","Mon","Tue","Wed","Thu"],
                    "alarms_app": alarm_app
                }),
            },
        ],
    }];

    if let Some(survey_state) = survey {
        if survey_state
            .answers
            .get("daily_pressure")
            .map(|value| value == "high")
            .unwrap_or(false)
        {
            items.push(ProactiveFeedItem {
                id: "stress_routine".to_string(),
                title: if user.locale == "he" {
                    "רוטינת איפוס עומס".to_string()
                } else {
                    "Stress reset routine".to_string()
                },
                summary: if user.locale == "he" {
                    "הפסקת 12 דקות: נשימה, שתייה קרה, והליכה קצרה לפני בלוק העבודה הבא."
                        .to_string()
                } else {
                    "12-minute reset: breathing, cold drink, and short walk before next work block."
                        .to_string()
                },
                why_now: if user.locale == "he" {
                    "הסקר זיהה עומס יומי גבוה.".to_string()
                } else {
                    "Survey detected high daily pressure.".to_string()
                },
                priority: "high".to_string(),
                actions: vec![atlas_core::SuggestedAction {
                    action_type: "create_reminder".to_string(),
                    label: if user.locale == "he" {
                        "תזכורת להפסקת איפוס".to_string()
                    } else {
                        "Reset break reminder".to_string()
                    },
                    payload: serde_json::json!({
                        "title": "Atlas reset break",
                        "details": "12 minutes reset routine",
                        "due_at_utc": (chrono::Utc::now() + chrono::Duration::minutes(45)).to_rfc3339(),
                        "reminders_app": reminder_app
                    }),
                }],
            });
        }
    }

    if let Some(notes) = notes {
        if let Some(note) = notes.first() {
            items.push(ProactiveFeedItem {
                id: "note_alignment".to_string(),
                title: if user.locale == "he" {
                    "יישור למשימה מרכזית".to_string()
                } else {
                    "Priority alignment".to_string()
                },
                summary: if user.locale == "he" {
                    format!("מהפתק \"{}\": {}.", note.title, note.content.chars().take(120).collect::<String>())
                } else {
                    format!("From note \"{}\": {}.", note.title, note.content.chars().take(120).collect::<String>())
                },
                why_now: if user.locale == "he" {
                    "המערכת מושכת את המשימה החשובה ביותר לזירת הביצוע היומית.".to_string()
                } else {
                    "The system elevates your highest-priority note into daily execution.".to_string()
                },
                priority: "high".to_string(),
                actions: vec![atlas_core::SuggestedAction {
                    action_type: "create_reminder".to_string(),
                    label: if user.locale == "he" {
                        "תזכורת למשימה מהפתק".to_string()
                    } else {
                        "Reminder from note".to_string()
                    },
                    payload: serde_json::json!({
                        "title": note.title,
                        "details": note.content,
                        "due_at_utc": (chrono::Utc::now() + chrono::Duration::minutes(35)).to_rfc3339(),
                        "reminders_app": reminder_app
                    }),
                }],
            });
        }
    }

    items
}

fn build_survey_hints(state: &SurveyStateRecord) -> Vec<String> {
    let mut hints = Vec::new();
    if let Some(goal) = state.answers.get("primary_goal") {
        hints.push(format!("goal: {}", goal));
    }
    if let Some(pressure) = state.answers.get("daily_pressure") {
        hints.push(format!("pressure: {}", pressure));
    }
    if let Some(pattern) = state.answers.get("travel_pattern") {
        hints.push(format!("travel_pattern: {}", pattern));
    }
    if let Some(style) = state.answers.get("trip_style") {
        hints.push(format!("trip_style: {}", style));
    }
    if let Some(wealth) = state.answers.get("wealth_focus") {
        hints.push(format!("wealth_focus: {}", wealth));
    }
    if let Some(charity) = state.answers.get("charity_commitment") {
        hints.push(format!("charity_commitment: {}", charity));
    }
    hints
}

fn survey_total_questions(answers: &HashMap<String, String>) -> usize {
    let mut total = 11;
    if answers
        .get("daily_pressure")
        .map(|value| value == "high")
        .unwrap_or(false)
    {
        total += 1;
    }
    if answers
        .get("work_hours")
        .map(|value| value == "10_plus")
        .unwrap_or(false)
    {
        total += 1;
    }
    if answers
        .get("stress_trigger")
        .map(|value| value == "uncertainty")
        .unwrap_or(false)
    {
        total += 1;
    }
    total
}

fn next_survey_question(locale: &str, answers: &HashMap<String, String>) -> Option<SurveyQuestion> {
    let he = locale.starts_with("he");
    let en = !he;

    let mk = |id: &str,
              title_he: &str,
              title_en: &str,
              desc_he: Option<&str>,
              desc_en: Option<&str>,
              kind: &str,
              choices: Vec<SurveyChoice>,
              placeholder_he: Option<&str>,
              placeholder_en: Option<&str>| SurveyQuestion {
        id: id.to_string(),
        title: if he { title_he } else { title_en }.to_string(),
        description: if he { desc_he } else { desc_en }.map(|value| value.to_string()),
        kind: kind.to_string(),
        required: true,
        choices,
        placeholder: if he { placeholder_he } else { placeholder_en }
            .map(|value| value.to_string()),
    };

    if !answers.contains_key("primary_goal") {
        return Some(mk(
            "primary_goal",
            "מה המטרה המרכזית שלך ל-90 הימים הקרובים?",
            "What is your primary goal for the next 90 days?",
            Some("זה מכוון את כל ההמלצות והפיד היזום."),
            Some("This tunes your recommendations and proactive feed."),
            "choice",
            vec![
                survey_choice(he, "wealth", "בניית הכנסה/עושר", "Build income/wealth"),
                survey_choice(he, "stability", "יציבות וסדר אישי", "Personal stability"),
                survey_choice(he, "health", "בריאות ואנרגיה", "Health and energy"),
                survey_choice(he, "mixed", "שילוב הכל", "Mix of all"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("daily_pressure") {
        return Some(mk(
            "daily_pressure",
            "כמה עומס אתה מרגיש ביום-יום?",
            "How much daily pressure are you under?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "low", "נמוך", "Low"),
                survey_choice(he, "medium", "בינוני", "Medium"),
                survey_choice(he, "high", "גבוה", "High"),
            ],
            None,
            None,
        ));
    }

    if answers
        .get("daily_pressure")
        .map(|value| value == "high")
        .unwrap_or(false)
        && !answers.contains_key("pressure_source")
    {
        return Some(mk(
            "pressure_source",
            "מה המקור המרכזי לעומס כרגע?",
            "What is the main source of pressure right now?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "money", "כסף", "Money"),
                survey_choice(he, "time", "זמן", "Time"),
                survey_choice(he, "uncertainty", "חוסר ודאות", "Uncertainty"),
                survey_choice(he, "relationships", "יחסים/צוות", "Relationships/team"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("work_hours") {
        return Some(mk(
            "work_hours",
            "כמה שעות עבודה ממוצעות ביום?",
            "Average work hours per day?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "under_6", "עד 6", "Up to 6"),
                survey_choice(he, "6_10", "6-10", "6-10"),
                survey_choice(he, "10_plus", "10+", "10+"),
            ],
            None,
            None,
        ));
    }

    if answers
        .get("work_hours")
        .map(|value| value == "10_plus")
        .unwrap_or(false)
        && !answers.contains_key("break_structure")
    {
        return Some(mk(
            "break_structure",
            "איך אתה רוצה שהמערכת תנהל הפסקות?",
            "How should the system handle your breaks?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "strict", "משמעת קבועה", "Strict schedule"),
                survey_choice(he, "flex", "גמיש לפי עומס", "Adaptive to workload"),
                survey_choice(he, "manual", "ידני בלבד", "Manual only"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("stress_trigger") {
        return Some(mk(
            "stress_trigger",
            "מה הטריגר הנפוץ ללחץ/דחיינות?",
            "What usually triggers stress/procrastination?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "uncertainty", "חוסר ודאות", "Uncertainty"),
                survey_choice(he, "fatigue", "עייפות", "Fatigue"),
                survey_choice(he, "overload", "עומס משימות", "Task overload"),
                survey_choice(
                    he,
                    "social",
                    "רעש חברתי/התראות",
                    "Social noise/notifications",
                ),
            ],
            None,
            None,
        ));
    }

    if answers
        .get("stress_trigger")
        .map(|value| value == "uncertainty")
        .unwrap_or(false)
        && !answers.contains_key("proactive_alerts")
    {
        return Some(mk(
            "proactive_alerts",
            "איזה סוג עדכונים יזומים יעזור לך?",
            "Which proactive alerts help you most?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "daily_brief", "בריף יומי", "Daily brief"),
                survey_choice(he, "risk_alerts", "התראות סיכון", "Risk alerts"),
                survey_choice(he, "execution", "דחיפת ביצוע", "Execution nudges"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("travel_pattern") {
        return Some(mk(
            "travel_pattern",
            "מה דפוס התנועה שלך?",
            "What is your movement pattern?",
            None,
            None,
            "choice",
            vec![
                survey_choice(
                    he,
                    "daily_commute",
                    "נסיעות יומיות כבדות",
                    "Heavy daily commuting",
                ),
                survey_choice(
                    he,
                    "multi_day",
                    "שהייה מתגלגלת רב-יומית",
                    "Multi-day rolling travel",
                ),
                survey_choice(he, "hybrid", "היברידי", "Hybrid"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("trip_style") {
        return Some(mk(
            "trip_style",
            "מה סגנון המסע המועדף עליך?",
            "What is your preferred trip style?",
            Some("נשתמש בזה כדי לכוון מסלולים ופיד יזום."),
            Some("Used to tune routes and proactive feed recommendations."),
            "choice",
            vec![
                survey_choice(he, "mixed", "משולב", "Mixed"),
                survey_choice(he, "beach", "חוף", "Beach"),
                survey_choice(he, "north", "צפון", "North"),
                survey_choice(he, "desert", "מדבר", "Desert"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("health_priority") {
        return Some(mk(
            "health_priority",
            "מה העדיפות הבריאותית החשובה כרגע?",
            "Top health priority right now?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "sleep", "שינה", "Sleep"),
                survey_choice(he, "focus", "פוקוס וקוגניציה", "Focus/cognition"),
                survey_choice(he, "stress", "הורדת סטרס", "Stress reduction"),
                survey_choice(he, "nutrition", "תזונה טובה", "Better nutrition"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("wealth_focus") {
        return Some(mk(
            "wealth_focus",
            "מה חשוב לך יותר בשנתיים הקרובות?",
            "In the next two years, what matters more?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "income_growth", "צמיחת הכנסה", "Income growth"),
                survey_choice(he, "capital", "בניית הון", "Capital building"),
                survey_choice(he, "both", "שניהם יחד", "Both"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("charity_commitment") {
        return Some(mk(
            "charity_commitment",
            "איך תרצה לשלב תרומה/נתינה בתכנון?",
            "How do you want to include charity in planning?",
            None,
            None,
            "choice",
            vec![
                survey_choice(
                    he,
                    "fixed_percent",
                    "אחוז קבוע מהכנסות",
                    "Fixed percent of income",
                ),
                survey_choice(he, "milestones", "לפי אבני דרך", "By milestones"),
                survey_choice(he, "later", "בהמשך", "Later"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("support_style") {
        return Some(mk(
            "support_style",
            "איזה סגנון ליווי אתה מעדיף?",
            "What coaching style do you prefer?",
            None,
            None,
            "choice",
            vec![
                survey_choice(he, "direct", "ישיר וחד", "Direct and sharp"),
                survey_choice(he, "coach", "מאמן תומך", "Supportive coach"),
                survey_choice(he, "strategic", "אסטרטגי ארוך טווח", "Long-term strategic"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("voice_preference") {
        return Some(mk(
            "voice_preference",
            "האם אתה רוצה שיחה קולית רציפה עם המערכת?",
            "Do you want continuous voice conversation with the system?",
            if en {
                Some("This can be changed later in Studio settings.")
            } else {
                Some("אפשר לשנות בכל רגע בהגדרות הסטודיו.")
            },
            if en {
                Some("This can be changed later in Studio settings.")
            } else {
                Some("אפשר לשנות בכל רגע בהגדרות הסטודיו.")
            },
            "choice",
            vec![
                survey_choice(he, "yes", "כן", "Yes"),
                survey_choice(he, "sometimes", "לפעמים", "Sometimes"),
                survey_choice(he, "no", "לא", "No"),
            ],
            None,
            None,
        ));
    }

    None
}

fn survey_choice(is_he: bool, value: &str, he: &str, en: &str) -> SurveyChoice {
    SurveyChoice {
        value: value.to_string(),
        label: if is_he { he } else { en }.to_string(),
    }
}

fn sanitize_enum_value(value: &str, allowed: &[&str], default_value: &str) -> String {
    let normalized = value.trim().to_lowercase();
    if allowed.iter().any(|candidate| *candidate == normalized) {
        normalized
    } else {
        default_value.to_string()
    }
}

fn sanitize_limited_text(value: &str, max_chars: usize) -> String {
    value.trim().chars().take(max_chars).collect::<String>()
}

fn normalize_tag(tag: &str) -> String {
    tag.trim()
        .chars()
        .take(MAX_NOTE_TAG_LEN)
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
        .collect::<String>()
        .to_lowercase()
}

fn is_subscription_bypass_email(email: &str) -> bool {
    let target = email.trim().to_lowercase();
    if target.is_empty() {
        return false;
    }

    let configured = env::var("ATLAS_SUBSCRIPTION_BYPASS_EMAILS")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_SUBSCRIPTION_BYPASS_EMAILS.to_string());

    configured
        .split(',')
        .map(|value| value.trim().to_lowercase())
        .any(|value| !value.is_empty() && value == target)
}

fn sanitize_note_tags(tags: Vec<String>) -> Vec<String> {
    tags.into_iter()
        .map(|tag| normalize_tag(tag.as_str()))
        .filter(|tag| !tag.is_empty())
        .take(MAX_NOTE_TAGS)
        .collect()
}

fn parse_or_default_utc(
    input: Option<&str>,
    fallback: chrono::DateTime<chrono::Utc>,
) -> chrono::DateTime<chrono::Utc> {
    input
        .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
        .map(|value| value.with_timezone(&chrono::Utc))
        .unwrap_or(fallback)
}

fn pct_encode(input: &str) -> String {
    let mut output = String::with_capacity(input.len() * 2);
    for byte in input.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            output.push(byte as char);
        } else {
            output.push('%');
            output.push_str(&format!("{:02X}", byte));
        }
    }
    output
}

fn escape_ics(input: &str) -> String {
    input
        .replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\n', "\\n")
}

fn is_valid_hhmm(value: &str) -> bool {
    let parts = value.split(':').collect::<Vec<_>>();
    if parts.len() != 2 {
        return false;
    }
    let hour = parts[0].parse::<u8>().ok();
    let minute = parts[1].parse::<u8>().ok();
    matches!((hour, minute), (Some(h), Some(m)) if h < 24 && m < 60)
}

fn parse_allowed_origins() -> Vec<String> {
    let default_origins = [
        "http://localhost:5500",
        "http://127.0.0.1:5500",
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "https://atlasmasa.com",
        "https://www.atlasmasa.com",
    ];

    env::var("ATLAS_ALLOWED_ORIGINS")
        .ok()
        .map(|value| {
            value
                .split(',')
                .map(|origin| origin.trim().trim_end_matches('/').to_string())
                .filter(|origin| !origin.is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| {
            default_origins
                .iter()
                .map(|value| value.trim_end_matches('/').to_string())
                .collect()
        })
}

fn build_google_oauth_config() -> Option<GoogleOAuthConfig> {
    let client_id = env::var("ATLAS_GOOGLE_CLIENT_ID").ok()?;
    let client_secret = env::var("ATLAS_GOOGLE_CLIENT_SECRET").ok()?;
    let redirect_uri = env::var("ATLAS_GOOGLE_REDIRECT_URI").ok()?;
    let frontend_origin = env::var("ATLAS_FRONTEND_ORIGIN")
        .ok()
        .unwrap_or_else(|| "https://atlasmasa.com".to_string());

    Some(GoogleOAuthConfig {
        client_id,
        client_secret,
        redirect_uri,
        frontend_origin,
    })
}

fn build_apple_oauth_config() -> Option<AppleOAuthConfig> {
    let client_id = env::var("ATLAS_APPLE_CLIENT_ID").ok()?;
    let client_secret = env::var("ATLAS_APPLE_CLIENT_SECRET").ok()?;
    let redirect_uri = env::var("ATLAS_APPLE_REDIRECT_URI").ok()?;
    let frontend_origin = env::var("ATLAS_FRONTEND_ORIGIN")
        .ok()
        .unwrap_or_else(|| "https://atlasmasa.com".to_string());

    Some(AppleOAuthConfig {
        client_id,
        client_secret,
        redirect_uri,
        frontend_origin,
    })
}

fn build_openai_runtime_config() -> Option<OpenAiRuntimeConfig> {
    let api_key = env::var("ATLAS_OPENAI_API_KEY").ok()?;
    let model = env::var("ATLAS_OPENAI_MODEL").unwrap_or_else(|_| "gpt-5.2".to_string());
    let default_reasoning_effort =
        env::var("ATLAS_OPENAI_REASONING_EFFORT").unwrap_or_else(|_| "high".to_string());

    Some(OpenAiRuntimeConfig {
        api_key,
        model,
        default_reasoning_effort,
    })
}

fn build_billing_runtime_config() -> Option<BillingRuntimeConfig> {
    let stripe_secret_key = env::var("ATLAS_STRIPE_SECRET_KEY").ok()?;
    let monthly_price_id = env::var("ATLAS_STRIPE_MONTHLY_PRICE_ID").ok()?;
    let success_url = env::var("ATLAS_STRIPE_SUCCESS_URL").unwrap_or_else(|_| {
        "https://atlasmasa.com/concierge-local.html?billing=success".to_string()
    });
    let cancel_url = env::var("ATLAS_STRIPE_CANCEL_URL").unwrap_or_else(|_| {
        "https://atlasmasa.com/concierge-local.html?billing=cancel".to_string()
    });
    let stripe_webhook_secret = env::var("ATLAS_STRIPE_WEBHOOK_SECRET")
        .ok()
        .filter(|value| !value.trim().is_empty());

    Some(BillingRuntimeConfig {
        stripe_secret_key,
        stripe_webhook_secret,
        monthly_price_id,
        success_url,
        cancel_url,
    })
}

fn build_webauthn_runtime() -> Option<WebauthnRuntimeConfig> {
    let rp_id = env::var("ATLAS_WEBAUTHN_RP_ID")
        .ok()
        .unwrap_or_else(|| "atlasmasa.com".to_string());
    let origin = env::var("ATLAS_WEBAUTHN_ORIGIN")
        .ok()
        .unwrap_or_else(|| "https://atlasmasa.com".to_string());
    let rp_name = env::var("ATLAS_WEBAUTHN_RP_NAME")
        .ok()
        .unwrap_or_else(|| "Atlas Masa".to_string());

    let origin_url = Url::parse(origin.as_str()).ok()?;
    let builder = WebauthnBuilder::new(rp_id.as_str(), &origin_url)
        .ok()?
        .rp_name(rp_name.as_str());
    let webauthn = builder.build().ok()?;

    Some(WebauthnRuntimeConfig {
        webauthn: Arc::new(webauthn),
    })
}

fn generate_urlsafe_token(bytes: usize) -> String {
    let mut buffer = vec![0_u8; bytes];
    rng().fill_bytes(buffer.as_mut_slice());
    URL_SAFE_NO_PAD.encode(buffer)
}

fn sanitize_return_to(value: &str) -> String {
    let cleaned = value.trim();
    if cleaned.is_empty() {
        return "/concierge-local.html".to_string();
    }
    if cleaned.starts_with('/') && !cleaned.starts_with("//") {
        return cleaned.to_string();
    }
    "/concierge-local.html".to_string()
}

fn parse_untrusted_jwt_payload<T: for<'de> serde::Deserialize<'de>>(token: &str) -> Option<T> {
    let payload_b64 = token.split('.').nth(1)?;
    let payload_raw = URL_SAFE_NO_PAD.decode(payload_b64).ok()?;
    serde_json::from_slice::<T>(&payload_raw).ok()
}

fn bool_from_jsonish(value: &serde_json::Value) -> Option<bool> {
    if let Some(parsed) = value.as_bool() {
        return Some(parsed);
    }
    value.as_str().and_then(|parsed| match parsed {
        "true" | "1" => Some(true),
        "false" | "0" => Some(false),
        _ => None,
    })
}

fn is_public_endpoint(path: &str) -> bool {
    matches!(
        path,
        "/health"
            | "/v1/auth/google/start"
            | "/v1/auth/google/callback"
            | "/v1/auth/apple/start"
            | "/v1/auth/apple/callback"
            | "/v1/auth/passkey/register/start"
            | "/v1/auth/passkey/register/finish"
            | "/v1/auth/passkey/login/start"
            | "/v1/auth/passkey/login/finish"
            | "/v1/billing/stripe_webhook"
    )
}

async fn ensure_app_schema(pool: &SqlitePool) -> Result<()> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_users (
          user_id TEXT PRIMARY KEY,
          provider TEXT NOT NULL,
          email TEXT NOT NULL,
          name TEXT NOT NULL,
          locale TEXT NOT NULL,
          trip_style TEXT,
          risk_preference TEXT,
          memory_opt_in INTEGER NOT NULL,
          passkey_user_handle TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS auth_sessions (
          session_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          expires_at TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS studio_preferences (
          user_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS survey_states (
          user_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS feedback_items (
          feedback_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS user_notes (
          note_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS passkeys (
          passkey_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS billing_subscriptions (
          user_id TEXT PRIMARY KEY,
          stripe_customer_id TEXT,
          stripe_subscription_id TEXT,
          status TEXT NOT NULL,
          current_period_end TEXT,
          updated_at TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    Ok(())
}

async fn load_persistent_state(pool: Option<&SqlitePool>) -> Result<PersistedState> {
    let Some(pool) = pool else {
        return Ok(PersistedState::default());
    };

    let mut state = PersistedState::default();

    let users = sqlx::query(
        r#"
        SELECT user_id, provider, email, name, locale, trip_style, risk_preference, memory_opt_in, passkey_user_handle, created_at, updated_at
        FROM auth_users
        "#,
    )
    .fetch_all(pool)
    .await?;
    for row in users {
        let user = UserRecord {
            user_id: row.get("user_id"),
            provider: row.get("provider"),
            email: row.get("email"),
            name: row.get("name"),
            locale: row.get("locale"),
            trip_style: row.get("trip_style"),
            risk_preference: row.get("risk_preference"),
            memory_opt_in: row.get::<i64, _>("memory_opt_in") > 0,
            passkey_user_handle: row.get("passkey_user_handle"),
            created_at: row.get("created_at"),
            updated_at: row.get("updated_at"),
        };
        state.users.insert(user.user_id.clone(), user);
    }

    let sessions =
        sqlx::query("SELECT session_id, user_id, expires_at, created_at FROM auth_sessions")
            .fetch_all(pool)
            .await?;
    for row in sessions {
        let expires_at = row
            .get::<String, _>("expires_at")
            .parse()
            .unwrap_or_else(|_| chrono::Utc::now());
        let created_at = row
            .get::<String, _>("created_at")
            .parse()
            .unwrap_or_else(|_| chrono::Utc::now());
        state.sessions.insert(
            row.get("session_id"),
            SessionRecord {
                user_id: row.get("user_id"),
                expires_at,
                created_at,
            },
        );
    }

    let studio = sqlx::query("SELECT user_id, data_json FROM studio_preferences")
        .fetch_all(pool)
        .await?;
    for row in studio {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<StudioPreferencesRecord>(&json) {
            state.studio_preferences.insert(row.get("user_id"), value);
        }
    }

    let surveys = sqlx::query("SELECT user_id, data_json FROM survey_states")
        .fetch_all(pool)
        .await?;
    for row in surveys {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<SurveyStateRecord>(&json) {
            state.survey_states.insert(row.get("user_id"), value);
        }
    }

    let feedback = sqlx::query("SELECT data_json FROM feedback_items")
        .fetch_all(pool)
        .await?;
    for row in feedback {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<FeedbackRecord>(&json) {
            state.feedback_items.push(value);
        }
    }

    let notes = sqlx::query("SELECT user_id, data_json FROM user_notes")
        .fetch_all(pool)
        .await?;
    for row in notes {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<UserNoteRecord>(&json) {
            state
                .user_notes
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    let passkeys = sqlx::query("SELECT user_id, data_json FROM passkeys")
        .fetch_all(pool)
        .await?;
    for row in passkeys {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<PasskeyRecord>(&json) {
            state
                .passkeys_by_user
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    Ok(state)
}

async fn persist_user_if_configured(state: &ApiState, user: &UserRecord) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };

    sqlx::query(
        r#"
        INSERT INTO auth_users (user_id, provider, email, name, locale, trip_style, risk_preference, memory_opt_in, passkey_user_handle, created_at, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        ON CONFLICT(user_id) DO UPDATE SET
          provider=excluded.provider,
          email=excluded.email,
          name=excluded.name,
          locale=excluded.locale,
          trip_style=excluded.trip_style,
          risk_preference=excluded.risk_preference,
          memory_opt_in=excluded.memory_opt_in,
          passkey_user_handle=excluded.passkey_user_handle,
          updated_at=excluded.updated_at
        "#,
    )
    .bind(user.user_id.as_str())
    .bind(user.provider.as_str())
    .bind(user.email.as_str())
    .bind(user.name.as_str())
    .bind(user.locale.as_str())
    .bind(user.trip_style.as_deref())
    .bind(user.risk_preference.as_deref())
    .bind(if user.memory_opt_in { 1_i64 } else { 0_i64 })
    .bind(user.passkey_user_handle.as_deref())
    .bind(user.created_at.as_str())
    .bind(user.updated_at.as_str())
    .execute(pool)
    .await?;
    Ok(())
}

async fn persist_studio_preferences_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let value = state
        .studio_preferences
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(user_id));
    let json = serde_json::to_string(&value)?;
    sqlx::query(
        r#"
        INSERT INTO studio_preferences (user_id, data_json)
        VALUES (?1, ?2)
        ON CONFLICT(user_id) DO UPDATE SET data_json=excluded.data_json
        "#,
    )
    .bind(user_id)
    .bind(json)
    .execute(pool)
    .await?;
    Ok(())
}

async fn persist_survey_state_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let Some(value) = state.survey_states.read().get(user_id).cloned() else {
        return Ok(());
    };
    let json = serde_json::to_string(&value)?;
    sqlx::query(
        r#"
        INSERT INTO survey_states (user_id, data_json)
        VALUES (?1, ?2)
        ON CONFLICT(user_id) DO UPDATE SET data_json=excluded.data_json
        "#,
    )
    .bind(user_id)
    .bind(json)
    .execute(pool)
    .await?;
    Ok(())
}

async fn persist_feedback_if_configured(state: &ApiState) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM feedback_items")
        .execute(pool)
        .await?;
    let items = state.feedback_items.read().clone();
    for item in &items {
        let json = serde_json::to_string(item)?;
        sqlx::query("INSERT INTO feedback_items (feedback_id, data_json) VALUES (?1, ?2)")
            .bind(item.feedback_id.as_str())
            .bind(json)
            .execute(pool)
            .await?;
    }
    Ok(())
}

async fn persist_sessions_if_configured(state: &ApiState) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };

    sqlx::query("DELETE FROM auth_sessions")
        .execute(pool)
        .await?;
    let snapshot = state
        .sessions
        .read()
        .iter()
        .map(|(session_id, session)| {
            (
                session_id.clone(),
                session.user_id.clone(),
                session.expires_at.to_rfc3339(),
                session.created_at.to_rfc3339(),
            )
        })
        .collect::<Vec<_>>();
    for (session_id, user_id, expires_at, created_at) in snapshot {
        sqlx::query(
            "INSERT INTO auth_sessions (session_id, user_id, expires_at, created_at) VALUES (?1, ?2, ?3, ?4)",
        )
        .bind(session_id.as_str())
        .bind(user_id.as_str())
        .bind(expires_at)
        .bind(created_at)
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn persist_notes_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM user_notes WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let notes = state
        .user_notes
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for note in notes {
        let json = serde_json::to_string(&note)?;
        sqlx::query("INSERT INTO user_notes (note_id, user_id, data_json) VALUES (?1, ?2, ?3)")
            .bind(note.note_id)
            .bind(user_id)
            .bind(json)
            .execute(pool)
            .await?;
    }
    Ok(())
}

async fn persist_passkeys_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM passkeys WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let records = state
        .passkeys_by_user
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for record in records {
        let json = serde_json::to_string(&record)?;
        sqlx::query("INSERT INTO passkeys (passkey_id, user_id, data_json) VALUES (?1, ?2, ?3)")
            .bind(record.passkey_id)
            .bind(user_id)
            .bind(json)
            .execute(pool)
            .await?;
    }
    Ok(())
}

async fn persist_billing_status_if_configured(
    state: &ApiState,
    billing: &BillingStatusRecord,
) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };

    sqlx::query(
        r#"
        INSERT INTO billing_subscriptions (user_id, stripe_customer_id, stripe_subscription_id, status, current_period_end, updated_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        ON CONFLICT(user_id) DO UPDATE SET
          stripe_customer_id=excluded.stripe_customer_id,
          stripe_subscription_id=excluded.stripe_subscription_id,
          status=excluded.status,
          current_period_end=excluded.current_period_end,
          updated_at=excluded.updated_at
        "#,
    )
    .bind(billing.user_id.as_str())
    .bind(billing.stripe_customer_id.as_deref())
    .bind(billing.stripe_subscription_id.as_deref())
    .bind(billing.status.as_str())
    .bind(billing.current_period_end.as_deref())
    .bind(billing.updated_at.as_str())
    .execute(pool)
    .await?;
    Ok(())
}

async fn resolve_user_id_by_customer(state: &ApiState, customer_id: &str) -> Option<String> {
    let pool = state.db_pool.as_ref()?;
    sqlx::query("SELECT user_id FROM billing_subscriptions WHERE stripe_customer_id = ?1 LIMIT 1")
        .bind(customer_id)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .map(|row| row.get::<String, _>("user_id"))
}

fn verify_stripe_webhook_signature(signature: &str, payload: &str, secret: &str) -> bool {
    let mut timestamp = "";
    let mut expected = "";
    for part in signature.split(',') {
        let mut split = part.splitn(2, '=');
        let key = split.next().unwrap_or_default();
        let value = split.next().unwrap_or_default();
        if key == "t" {
            timestamp = value;
        } else if key == "v1" {
            expected = value;
        }
    }
    if timestamp.is_empty() || expected.is_empty() {
        return false;
    }

    let signed_payload = format!("{}.{}", timestamp, payload);
    let mut mac = match Hmac::<Sha256>::new_from_slice(secret.as_bytes()) {
        Ok(value) => value,
        Err(_) => return false,
    };
    mac.update(signed_payload.as_bytes());
    let result = mac.finalize().into_bytes();
    let computed = hex_encode(result.as_slice());
    constant_time_eq(computed.as_bytes(), expected.as_bytes())
}

fn constant_time_eq(lhs: &[u8], rhs: &[u8]) -> bool {
    if lhs.len() != rhs.len() {
        return false;
    }
    let mut diff = 0_u8;
    for (a, b) in lhs.iter().zip(rhs.iter()) {
        diff |= a ^ b;
    }
    diff == 0
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(format!("{:02x}", byte).as_str());
    }
    out
}

async fn find_or_create_user_by_email(
    state: &ApiState,
    provider: &str,
    email: String,
    name: String,
    locale: String,
    now: String,
) -> UserRecord {
    if let Some(existing) = state
        .users
        .read()
        .values()
        .find(|value| {
            value.email == email && (value.provider == provider || value.provider == "passkey")
        })
        .cloned()
    {
        return existing;
    }

    let user_id = uuid::Uuid::new_v4().to_string();
    let user = UserRecord {
        user_id: user_id.clone(),
        provider: provider.to_string(),
        email,
        name,
        locale,
        trip_style: Some("mixed".to_string()),
        risk_preference: Some("medium".to_string()),
        memory_opt_in: true,
        passkey_user_handle: Some(uuid::Uuid::new_v4().to_string()),
        created_at: now.clone(),
        updated_at: now,
    };
    state.users.write().insert(user_id, user.clone());
    let _ = persist_user_if_configured(state, &user).await;
    user
}

async fn issue_session_for_user(state: &ApiState, user: &UserRecord) -> Result<String> {
    let session_id = uuid::Uuid::new_v4().to_string();
    let expires_at =
        chrono::Utc::now() + chrono::Duration::seconds(state.session_ttl.as_secs() as i64);
    state.sessions.write().insert(
        session_id.clone(),
        SessionRecord {
            user_id: user.user_id.clone(),
            expires_at,
            created_at: chrono::Utc::now(),
        },
    );
    persist_sessions_if_configured(state).await?;
    Ok(session_id)
}

fn resolve_user_id_for_passkey_credential(state: &ApiState, cred_id: &[u8]) -> Option<String> {
    state
        .passkeys_by_user
        .read()
        .iter()
        .find_map(|(user_id, entries)| {
            if entries
                .iter()
                .any(|entry| entry.credential.cred_id().as_slice() == cred_id)
            {
                Some(user_id.clone())
            } else {
                None
            }
        })
}

fn update_passkey_credential_usage(
    state: &ApiState,
    user_id: &str,
    auth_result: &AuthenticationResult,
) {
    if let Some(entries) = state.passkeys_by_user.write().get_mut(user_id) {
        let now = chrono::Utc::now().to_rfc3339();
        for entry in entries.iter_mut() {
            if entry.credential.update_credential(auth_result).is_some() {
                entry.last_used_at = Some(now.clone());
            }
        }
    }
}

async fn generate_premium_openai_reply(
    state: &ApiState,
    request: &ChatRequest,
    user: Option<&UserRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: &[UserNoteRecord],
    fallback_reply: &str,
) -> Result<String> {
    let runtime = state
        .openai_runtime
        .as_ref()
        .context("OpenAI runtime is not configured")?;

    let user_context = user.map(|value| {
        serde_json::json!({
            "name": value.name,
            "locale": value.locale,
            "trip_style": value.trip_style,
            "risk_preference": value.risk_preference,
            "memory_opt_in": value.memory_opt_in
        })
    });
    let survey_context = survey.map(|value| serde_json::to_value(value).unwrap_or_default());
    let notes_context = notes
        .iter()
        .take(12)
        .map(|note| {
            serde_json::json!({
                "title": note.title,
                "content": note.content,
                "tags": note.tags
            })
        })
        .collect::<Vec<_>>();

    let system_prompt = "You are Atlas Masa Executive Intelligence. Speak with refined, high-class language and clear structure. Act like a strategic chief-of-staff for a high-performing traveler-builder. Prioritize execution, safety, resilience, and momentum.";
    let payload = serde_json::json!({
        "model": runtime.model,
        "reasoning": {
            "effort": runtime.default_reasoning_effort
        },
        "input": [
            {
                "role": "system",
                "content": [
                    { "type": "input_text", "text": system_prompt }
                ]
            },
            {
                "role": "user",
                "content": [
                    { "type": "input_text", "text": request.text }
                ]
            },
            {
                "role": "user",
                "content": [
                    { "type": "input_text", "text": format!("Context JSON: {}", serde_json::json!({
                        "user": user_context,
                        "survey": survey_context,
                        "notes": notes_context,
                        "fallback_reply": fallback_reply
                    })) }
                ]
            }
        ],
        "text": {
            "verbosity": "high"
        }
    });

    let response = state
        .http_client
        .post("https://api.openai.com/v1/responses")
        .bearer_auth(runtime.api_key.as_str())
        .json(&payload)
        .send()
        .await
        .context("OpenAI request failed")?;

    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("OpenAI non-success status {}: {}", status.as_u16(), body);
    }

    let body: serde_json::Value = response.json().await.context("OpenAI parse failed")?;
    extract_openai_output_text(&body)
        .filter(|value| !value.trim().is_empty())
        .context("OpenAI output text missing")
}

async fn rewrite_note_with_openai(
    state: &ApiState,
    note: &UserNoteRecord,
    instruction: &str,
) -> Result<String> {
    let runtime = state
        .openai_runtime
        .as_ref()
        .context("OpenAI runtime is not configured")?;

    let payload = serde_json::json!({
        "model": runtime.model,
        "reasoning": {
            "effort": runtime.default_reasoning_effort
        },
        "input": [
            {
                "role": "system",
                "content": [
                    { "type": "input_text", "text": "Rewrite notes into premium executive language while preserving facts and actionability." }
                ]
            },
            {
                "role": "user",
                "content": [
                    { "type": "input_text", "text": instruction },
                    { "type": "input_text", "text": format!("Title: {}\n\nNote:\n{}", note.title, note.content) }
                ]
            }
        ],
        "text": {
            "verbosity": "high"
        }
    });

    let response = state
        .http_client
        .post("https://api.openai.com/v1/responses")
        .bearer_auth(runtime.api_key.as_str())
        .json(&payload)
        .send()
        .await
        .context("OpenAI note rewrite request failed")?;
    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("OpenAI note rewrite failed {}: {}", status.as_u16(), body);
    }

    let body: serde_json::Value = response
        .json()
        .await
        .context("OpenAI rewrite parse failed")?;
    extract_openai_output_text(&body)
        .filter(|value| !value.trim().is_empty())
        .context("OpenAI rewrite output missing")
}

fn extract_openai_output_text(payload: &serde_json::Value) -> Option<String> {
    if let Some(value) = payload.get("output_text").and_then(|value| value.as_str()) {
        return Some(value.to_string());
    }
    let output = payload.get("output")?.as_array()?;
    let mut chunks = Vec::new();
    for item in output {
        if let Some(content) = item.get("content").and_then(|value| value.as_array()) {
            for content_item in content {
                if content_item
                    .get("type")
                    .and_then(|value| value.as_str())
                    .map(|value| value == "output_text")
                    .unwrap_or(false)
                {
                    if let Some(text) = content_item.get("text").and_then(|value| value.as_str()) {
                        chunks.push(text.to_string());
                    }
                }
            }
        }
    }
    if chunks.is_empty() {
        None
    } else {
        Some(chunks.join("\n\n"))
    }
}

fn build_cors_layer(allowed_origins: &Arc<Vec<String>>) -> CorsLayer {
    let origins = allowed_origins
        .iter()
        .filter_map(|origin| HeaderValue::from_str(origin).ok())
        .collect::<Vec<_>>();
    let origins = if origins.is_empty() {
        vec![HeaderValue::from_static("http://localhost:5500")]
    } else {
        origins
    };

    CorsLayer::new()
        .allow_origin(AllowOrigin::list(origins))
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers([
            header::CONTENT_TYPE,
            header::HeaderName::from_static("x-api-key"),
        ])
        .allow_credentials(true)
}

async fn rate_limit_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request.method() == Method::OPTIONS {
        return next.run(request).await;
    }

    let path = request.uri().path().to_string();
    let ip = request_ip(&request);

    if is_auth_rate_limited_endpoint(path.as_str()) {
        let auth_key = format!("auth:{}:{}", path, ip);
        if !state.auth_limiter.allow(&auth_key) {
            return (
                StatusCode::TOO_MANY_REQUESTS,
                Json(serde_json::json!({
                    "error": "auth_rate_limited",
                    "message": "too many authentication attempts from this IP. wait and retry."
                })),
            )
                .into_response();
        }
    }

    if is_public_endpoint(path.as_str()) {
        return next.run(request).await;
    }

    if !state.limiter.allow(&ip) {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(serde_json::json!({
                "error": "rate_limited",
                "message": "rate limit exceeded for this IP"
            })),
        )
            .into_response();
    }

    next.run(request).await
}

async fn csrf_origin_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request.method() == Method::GET
        || request.method() == Method::HEAD
        || request.method() == Method::OPTIONS
    {
        return next.run(request).await;
    }

    let has_cookie_session = read_cookie_value(request.headers(), &state.cookie_name).is_some();
    if !has_cookie_session {
        return next.run(request).await;
    }

    let origin = request
        .headers()
        .get(header::HeaderName::from_static("origin"))
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .trim()
        .trim_end_matches('/')
        .to_string();

    if origin.is_empty() {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "error": "origin_required",
                "message": "origin header is required for cookie-authenticated state changes"
            })),
        )
            .into_response();
    }

    if !state.allowed_origins.iter().any(|value| value == &origin) {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "error": "origin_not_allowed",
                "message": "request origin is not in ATLAS_ALLOWED_ORIGINS"
            })),
        )
            .into_response();
    }

    next.run(request).await
}

fn is_auth_rate_limited_endpoint(path: &str) -> bool {
    matches!(
        path,
        "/v1/auth/google/start"
            | "/v1/auth/google/callback"
            | "/v1/auth/apple/start"
            | "/v1/auth/apple/callback"
            | "/v1/auth/passkey/register/start"
            | "/v1/auth/passkey/register/finish"
            | "/v1/auth/passkey/login/start"
            | "/v1/auth/passkey/login/finish"
    )
}

fn request_ip(request: &Request<Body>) -> String {
    request
        .headers()
        .get("x-forwarded-for")
        .and_then(|value| value.to_str().ok())
        .map(|value| {
            value
                .split(',')
                .next()
                .unwrap_or("unknown")
                .trim()
                .to_string()
        })
        .unwrap_or_else(|| "local".to_string())
}

async fn security_headers_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let mut response = next.run(request).await;

    response.headers_mut().insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response.headers_mut().insert(
        header::HeaderName::from_static("x-frame-options"),
        HeaderValue::from_static("DENY"),
    );
    response.headers_mut().insert(
        header::HeaderName::from_static("referrer-policy"),
        HeaderValue::from_static("strict-origin-when-cross-origin"),
    );
    response.headers_mut().insert(
        header::HeaderName::from_static("permissions-policy"),
        HeaderValue::from_static("camera=(), microphone=(), geolocation=(self)"),
    );
    response.headers_mut().insert(
        header::HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static("default-src 'none'; frame-ancestors 'none'; base-uri 'none'"),
    );
    if state.cookie_secure {
        response.headers_mut().insert(
            header::HeaderName::from_static("strict-transport-security"),
            HeaderValue::from_static("max-age=31536000; includeSubDomains; preload"),
        );
    }

    response
}

#[cfg(test)]
mod tests {
    use super::{build_clear_cookie, build_session_cookie};

    #[test]
    fn session_cookie_is_secure_and_domain_scoped() {
        let cookie = build_session_cookie(
            "atlas_session",
            "session123",
            3600,
            true,
            "strict",
            "atlasmasa.com",
        );
        assert!(cookie.contains("HttpOnly"));
        assert!(cookie.contains("Secure"));
        assert!(cookie.contains("SameSite=Strict"));
        assert!(cookie.contains("Domain=atlasmasa.com"));
    }

    #[test]
    fn clear_cookie_preserves_security_attributes() {
        let cookie = build_clear_cookie("atlas_session", true, "lax", "atlasmasa.com");
        assert!(cookie.contains("HttpOnly"));
        assert!(cookie.contains("Secure"));
        assert!(cookie.contains("SameSite=Lax"));
        assert!(cookie.contains("Domain=atlasmasa.com"));
        assert!(cookie.contains("Max-Age=0"));
    }
}
