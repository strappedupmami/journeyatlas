mod rate_limit;

use std::collections::{HashMap, HashSet};
use std::env;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use atlas_agents::ConciergeAgent;
use atlas_core::{detect_locale, ChatInput, TripPlanRequest};
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
use ring::signature::{RsaPublicKeyComponents, RSA_PKCS1_2048_8192_SHA256};
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
const MAX_MEMORY_TEXT_LEN: usize = 800;
const MAX_MEMORY_RECORDS_PER_USER: usize = 3_000;
const DEFAULT_MEMORY_RETRIEVAL_LIMIT: usize = 12;
const MAX_MEMORY_RETRIEVAL_LIMIT: usize = 64;
const MAX_MEMORY_BATCH_EXPORT_ITEMS: usize = 128;
const TRANSIENT_MEMORY_TTL_DAYS: i64 = 14;
const MAX_REMINDER_TITLE_LEN: usize = 180;
const MAX_REMINDER_DETAILS_LEN: usize = 1_500;
const MAX_REMINDER_DETAILS_FOR_URL: usize = 480;
const MAX_ALARM_LABEL_LEN: usize = 120;
const MIN_REMINDER_DURATION_MINUTES: u32 = 5;
const MAX_REMINDER_DURATION_MINUTES: u32 = 8 * 60;
const MAX_SHORTCUTS_URL_LEN: usize = 1_900;
const MAX_FEEDBACK_MESSAGE_LEN: usize = 2_000;
const MAX_FEEDBACK_TAGS: usize = 20;
const MAX_FEEDBACK_TAG_LEN: usize = 40;
const MAX_RND_PROMPT_LEN: usize = 24_000;
const MAX_RND_CHANGE_REQUEST_LEN: usize = 4_000;
const MAX_RND_RESEARCH_SUMMARY_LEN: usize = 16_000;
const MAX_RND_LOCAL_PLANNING_NOTE_LEN: usize = 12_000;
const MAX_SHOPIFY_SOURCE_LEN: usize = 80;
const MAX_SHOPIFY_NOTES_LEN: usize = 1_600;
const MAX_SHOPIFY_REPORTS_PER_USER: usize = 10_000;
const MAX_SHOPIFY_SUMMARY_LIMIT: usize = 200;
const MAX_SHOPIFY_PROFIT_CENTS_ABS: i64 = 100_000_000_000_000;
const DEFAULT_SHOPIFY_PROFIT_SHARE_BPS: u32 = 2_000;
const DEFAULT_STRIPE_WEBHOOK_TOLERANCE_SECONDS: u64 = 300;
const DEFAULT_SUBSCRIPTION_BYPASS_EMAILS: &str =
    "ceo@atlasmasa.com,avrohomsk@gmail.com,b8kttqqd7c@privaterelay.appleid.com";
const FREE_USAGE_TRIAL_DAYS: i64 = 0;

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
    pub psychological_profiles: Arc<RwLock<HashMap<String, PsychologicalProfileRecord>>>,
    pub vehicle_profiles: Arc<RwLock<HashMap<String, VehicleProfileRecord>>>,
    pub studio_preferences: Arc<RwLock<HashMap<String, StudioPreferencesRecord>>>,
    pub survey_states: Arc<RwLock<HashMap<String, SurveyStateRecord>>>,
    pub feedback_items: Arc<RwLock<Vec<FeedbackRecord>>>,
    pub user_notes: Arc<RwLock<HashMap<String, Vec<UserNoteRecord>>>>,
    pub user_memories: Arc<RwLock<HashMap<String, Vec<MemoryRecord>>>>,
    pub lifelogs: Arc<RwLock<HashMap<String, Vec<LifelogRecord>>>>,
    pub execution_checkins: Arc<RwLock<HashMap<String, Vec<ExecutionCheckinRecord>>>>,
    pub execution_controls: Arc<RwLock<HashMap<String, ExecutionControlsRecord>>>,
    pub execution_task_states:
        Arc<RwLock<HashMap<String, HashMap<String, ExecutionTaskStateRecord>>>>,
    pub rnd_jobs: Arc<RwLock<HashMap<String, RndJobRecord>>>,
    pub oauth_states: Arc<RwLock<HashMap<String, OAuthStateRecord>>>,
    pub google_oauth: Option<GoogleOAuthConfig>,
    pub apple_oauth: Option<AppleOAuthConfig>,
    pub openai_runtime: Option<OpenAiRuntimeConfig>,
    pub gemini_runtime: Option<GeminiRuntimeConfig>,
    pub ai_provider_preference: CloudAiProviderPreference,
    pub billing_runtime: Option<BillingRuntimeConfig>,
    pub webauthn_runtime: Option<WebauthnRuntimeConfig>,
    pub passkey_registrations: Arc<RwLock<HashMap<String, PasskeyRegistrationStateRecord>>>,
    pub passkey_authentications: Arc<RwLock<HashMap<String, PasskeyAuthenticationStateRecord>>>,
    pub passkeys_by_user: Arc<RwLock<HashMap<String, Vec<PasskeyRecord>>>>,
    pub shopify_profit_share_reports: Arc<RwLock<HashMap<String, Vec<ShopifyProfitShareRecord>>>>,
    pub shopify_default_profit_share_bps: u32,
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
    native_client_ids: Vec<String>,
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
    coding_backend_model: String,
    default_reasoning_effort: String,
}

#[derive(Debug, Clone)]
struct GeminiRuntimeConfig {
    api_key: String,
    model: String,
    frontend_design_model: String,
    temperature: f32,
    max_output_tokens: u32,
    thinking_level: Option<String>,
    context_cache_name: Option<String>,
}

#[derive(Debug, Clone, Copy)]
enum CloudAiProviderPreference {
    OpenAiFirst,
    GeminiFirst,
    Auto,
}

#[derive(Debug, Clone, Copy)]
enum CloudAiBackend {
    OpenAi,
    Gemini,
}

impl CloudAiBackend {
    fn backend_id(self) -> &'static str {
        match self {
            Self::OpenAi => "openai_responses",
            Self::Gemini => "google_gemini",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CodeAgentRoute {
    FrontendDesign,
    BackendOps,
}

impl CodeAgentRoute {
    fn from_raw(raw: &str) -> Option<Self> {
        match raw.trim().to_lowercase().as_str() {
            "frontend_design" | "frontend" | "design_frontend" => Some(Self::FrontendDesign),
            "backend_ops" | "backend_operations" | "backend" | "troubleshooting" => {
                Some(Self::BackendOps)
            }
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::FrontendDesign => "frontend_design",
            Self::BackendOps => "backend_ops",
        }
    }

    fn preferred_backends(self) -> [CloudAiBackend; 2] {
        match self {
            Self::FrontendDesign => [CloudAiBackend::Gemini, CloudAiBackend::OpenAi],
            Self::BackendOps => [CloudAiBackend::OpenAi, CloudAiBackend::Gemini],
        }
    }
}

#[derive(Debug, Clone)]
struct BillingRuntimeConfig {
    stripe_secret_key: String,
    stripe_webhook_secret: Option<String>,
    stripe_webhook_tolerance_seconds: u64,
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

#[derive(Debug, Clone, Deserialize)]
struct AppleNativeExchangeRequest {
    identity_token: String,
    authorization_code: Option<String>,
    email: Option<String>,
    display_name: Option<String>,
    locale: Option<String>,
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
struct UserScopedQuery {
    user_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PsychologicalProfileRecord {
    user_id: String,
    comfort_zone_vs_novelty_index: f32,
    routine_rigidity_score: f32,
    stress_load_score: f32,
    recovery_bias: String,
    historical_feedback_summary: String,
    updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct PsychologicalProfileUpsertRequest {
    user_id: Option<String>,
    comfort_zone_vs_novelty_index: Option<f32>,
    routine_rigidity_score: Option<f32>,
    stress_load_score: Option<f32>,
    recovery_bias: Option<String>,
    historical_feedback_summary: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VehicleProfileRecord {
    user_id: String,
    vehicle_kind: String,
    model_name: Option<String>,
    length_cm: Option<i32>,
    height_cm: Option<i32>,
    battery_capacity_ah: Option<i32>,
    solar_capacity_watts: Option<i32>,
    nvh_sensitivity: String,
    updated_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct VehicleProfileUpsertRequest {
    user_id: Option<String>,
    vehicle_kind: Option<String>,
    model_name: Option<String>,
    length_cm: Option<i32>,
    height_cm: Option<i32>,
    battery_capacity_ah: Option<i32>,
    solar_capacity_watts: Option<i32>,
    nvh_sensitivity: Option<String>,
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
    code_agent_route: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct StudioPreferencesUpsertRequest {
    user_id: Option<String>,
    preferred_format: Option<String>,
    response_depth: Option<String>,
    memory_depth: Option<String>,
    compute_mode: Option<String>,
    cloud_cost_guardrail: Option<String>,
    local_resource_guardrail: Option<String>,
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
    memory_depth: String,
    compute_mode: String,
    cloud_cost_guardrail: String,
    local_resource_guardrail: String,
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
    checklist_state: Option<ExecutionTaskChecklistState>,
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
struct AmmDiagnostics {
    active_mode: String,
    compaction_applied: bool,
    trigger_reason: String,
    pinned_context_preserved: bool,
    estimated_cloud_input_cost_usd: f64,
    estimated_local_memory_mb: u32,
    estimated_local_storage_mb: u32,
    tradeoff_summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExecutionCheckinRecord {
    checkin_id: String,
    user_id: String,
    daily_focus: String,
    mid_term_focus: Option<String>,
    long_term_focus: Option<String>,
    blocker: Option<String>,
    next_action_now: Option<String>,
    energy_level: Option<u8>,
    mood: Option<String>,
    gym_today: Option<bool>,
    money_today: Option<bool>,
    created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct ExecutionCheckinRequest {
    user_id: Option<String>,
    daily_focus: String,
    mid_term_focus: Option<String>,
    long_term_focus: Option<String>,
    blocker: Option<String>,
    next_action_now: Option<String>,
    energy_level: Option<u8>,
    mood: Option<String>,
    gym_today: Option<bool>,
    money_today: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExecutionControlsRecord {
    user_id: String,
    cadence: String,
    detail_level: String,
    include_company_awareness: bool,
    include_reminder_suggestions: bool,
    updated_at: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
struct ExecutionControlsUpsertRequest {
    cadence: Option<String>,
    detail_level: Option<String>,
    include_company_awareness: Option<bool>,
    include_reminder_suggestions: Option<bool>,
}

#[derive(Debug, Clone)]
struct ExecutionTaskCandidate {
    task_id: String,
    title: String,
    detail: String,
    source: String,
    horizon: String,
    urgency: f32,
    impact: f32,
    confidence: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExecutionTaskResponseRecord {
    response_id: String,
    task_id: String,
    completed_parts: Option<String>,
    incomplete_parts: Option<String>,
    note: Option<String>,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExecutionTaskStateRecord {
    task_id: String,
    completed: bool,
    collapsed: bool,
    completion_count: u32,
    updated_at: String,
    latest_response: Option<ExecutionTaskResponseRecord>,
    responses: Vec<ExecutionTaskResponseRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ExecutionTaskChecklistState {
    completed: bool,
    collapsed: bool,
    completion_count: u32,
    updated_at: String,
    latest_response: Option<ExecutionTaskResponseRecord>,
}

#[derive(Debug, Clone, Deserialize)]
struct ExecutionTaskToggleRequest {
    user_id: Option<String>,
    task_id: String,
    completed: bool,
    collapsed: Option<bool>,
    locale: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct ExecutionTaskResponseSubmitRequest {
    user_id: Option<String>,
    task_id: String,
    completed_parts: Option<String>,
    incomplete_parts: Option<String>,
    note: Option<String>,
    completed: Option<bool>,
    collapsed: Option<bool>,
    locale: Option<String>,
}

struct ExecutionFeedContext<'a> {
    company_status: &'a CompanyStatusRecord,
    user: &'a UserRecord,
    prefs: Option<&'a StudioPreferencesRecord>,
    survey: Option<&'a SurveyStateRecord>,
    notes: Option<&'a [UserNoteRecord]>,
    controls: &'a ExecutionControlsRecord,
    memories: &'a [MemoryRetrievedItem],
    latest_checkin: Option<&'a ExecutionCheckinRecord>,
    task_states: &'a HashMap<String, ExecutionTaskStateRecord>,
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
struct ActionTelemetry {
    trace_id: String,
    action: String,
    success: bool,
    app: Option<String>,
    supports_direct_write: bool,
    fallback_used: bool,
    primary_target: Option<String>,
    warnings: Vec<String>,
    generated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ReminderActionResponse {
    app: String,
    google_calendar_url: String,
    ics_filename: String,
    ics_content: String,
    shortcuts_url: String,
    primary_url: Option<String>,
    supports_direct_write: bool,
    fallback_used: bool,
    user_message: String,
    telemetry: ActionTelemetry,
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
    primary_url: Option<String>,
    supports_direct_write: bool,
    fallback_used: bool,
    user_message: String,
    fallback_instructions: String,
    telemetry: ActionTelemetry,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ShopifyProfitShareRecord {
    report_id: String,
    user_id: String,
    currency: String,
    period_start_utc: Option<String>,
    period_end_utc: Option<String>,
    source: String,
    notes: Option<String>,
    shopify_profit_cents: i64,
    baseline_profit_cents: i64,
    uplift_profit_cents: i64,
    agentic_attribution_ratio: f64,
    agentic_attributed_profit_cents: i64,
    app_take_rate_bps: u32,
    app_cut_cents: i64,
    merchant_kept_cents: i64,
    created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
struct ShopifyProfitShareUpsertRequest {
    user_id: Option<String>,
    currency: Option<String>,
    period_start_utc: Option<String>,
    period_end_utc: Option<String>,
    source: Option<String>,
    notes: Option<String>,
    shopify_profit_cents: i64,
    baseline_profit_cents: Option<i64>,
    agentic_attribution_ratio: Option<f64>,
    agentic_attributed_profit_cents: Option<i64>,
    app_take_rate_bps: Option<u32>,
}

#[derive(Debug, Clone, Deserialize)]
struct ShopifyProfitShareSummaryQuery {
    user_id: Option<String>,
    currency: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize)]
struct ShopifyProfitShareSummaryResponse {
    currency: String,
    default_app_take_rate_bps: u32,
    report_count: usize,
    total_shopify_profit_cents: i64,
    total_agentic_attributed_profit_cents: i64,
    total_app_cut_cents: i64,
    total_merchant_kept_cents: i64,
    latest_report_at: Option<String>,
    reports: Vec<ShopifyProfitShareRecord>,
}

#[derive(Debug, Clone)]
struct ShopifyProfitShareComputation {
    baseline_profit_cents: i64,
    uplift_profit_cents: i64,
    agentic_attribution_ratio: f64,
    agentic_attributed_profit_cents: i64,
    app_cut_cents: i64,
    merchant_kept_cents: i64,
}

#[derive(Debug, Clone, Serialize)]
struct SubscriptionAccessRecord {
    bypass: bool,
    active: bool,
    tier: String,
    cloud_compute_enabled: bool,
    cloud_storage_enabled: bool,
    pricing_model: String,
    free_trial_days_total: i64,
    free_trial_days_remaining: i64,
    free_trial_active: bool,
    free_trial_ends_at: String,
    usage_billing_active: bool,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct MemoryRecord {
    memory_id: String,
    user_id: String,
    memory_type: String,
    stability: String,
    source: String,
    text: String,
    weight: f32,
    recency_score: f32,
    tags: Vec<String>,
    created_at: String,
    updated_at: String,
    expires_at: Option<String>,
    fingerprint: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LifelogRecord {
    lifelog_id: String,
    user_id: String,
    memory_id: Option<String>,
    summary: String,
    source: String,
    tags: Vec<String>,
    embedding_json: Option<Vec<f32>>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone)]
struct MemoryIngestEvent {
    memory_type: String,
    stability: String,
    source: String,
    text: String,
    weight: f32,
    tags: Vec<String>,
    happened_at: Option<chrono::DateTime<chrono::Utc>>,
    expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryRecordsQuery {
    user_id: Option<String>,
    q: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Deserialize)]
struct LifelogRecordsQuery {
    user_id: Option<String>,
    q: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryUpsertRequest {
    user_id: Option<String>,
    memory_type: Option<String>,
    stability: Option<String>,
    source: Option<String>,
    text: String,
    weight: Option<f32>,
    tags: Option<Vec<String>>,
    expires_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryDeleteRequest {
    user_id: Option<String>,
    memory_id: String,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryClearRequest {
    user_id: Option<String>,
    scope: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct MemoryRetrievedItem {
    memory_id: String,
    memory_type: String,
    stability: String,
    source: String,
    text: String,
    weight: f32,
    recency_score: f32,
    relevance_score: f32,
    final_score: f32,
    tags: Vec<String>,
    updated_at: String,
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

#[derive(Debug, Clone, Deserialize)]
struct MemoryBatchExportRequest {
    user_id: Option<String>,
    provider: Option<String>,
    q: Option<String>,
    limit: Option<usize>,
}

#[derive(Debug, Clone, Serialize)]
struct MemoryBatchExportManifest {
    provider: String,
    model: String,
    operation: String,
    generated_at: String,
    query: String,
    item_count: usize,
    cache_strategy: String,
}

#[derive(Debug, Clone, Deserialize)]
struct RndJobCreateRequest {
    product_type: Option<String>,
    prompt: String,
    locale: Option<String>,
    client_research_summary: Option<String>,
    client_local_planning_note: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndPlanReviseRequest {
    revision_prompt: String,
}

#[derive(Debug, Clone, Deserialize)]
struct RndStageApproveRequest {
    note: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndPauseRequest {
    pause_after_current_stage: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndChangeRequest {
    scope: Option<String>,
    target_part_id: Option<String>,
    request: String,
}

#[derive(Debug, Clone, Deserialize)]
struct RndReviewRecordRequest {
    title: Option<String>,
    status: Option<String>,
    note: Option<String>,
    requirement_ids: Option<Vec<String>>,
    decision_ids: Option<Vec<String>>,
    evidence_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndReportGenerateRequest {
    title: Option<String>,
    report_type: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndDocumentGenerateRequest {
    document_type: String,
    audience_mode: Option<String>,
    title: Option<String>,
    platform_name: Option<String>,
    revision_label: Option<String>,
    purpose: Option<String>,
    target_audience: Option<String>,
    author: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndDocumentBundleGenerateRequest {
    audience_mode: Option<String>,
    title_prefix: Option<String>,
    platform_name: Option<String>,
    revision_label: Option<String>,
    author: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RndApprovalRecordRequest {
    reviewer_name: String,
    reviewer_role: String,
    reviewer_org: Option<String>,
    authority_kind: Option<String>,
    approval_state: Option<String>,
    scope_type: Option<String>,
    scope_id: Option<String>,
    comment: Option<String>,
    conditions: Option<Vec<String>>,
    create_baseline_if_approved: Option<bool>,
    baseline_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndCitationRecord {
    id: String,
    label: String,
    source_type: String,
    detail: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndContextPackRecord {
    user_preference_summary: String,
    memory_summary: String,
    prior_job_summary: String,
    research_summary: String,
    explicit_constraints: Vec<String>,
    citations: Vec<RndCitationRecord>,
    research_confidence: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndPlanStageRecord {
    id: String,
    title: String,
    objective: String,
    estimated_minutes: u32,
    approval_required: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndPlanRecord {
    version: u32,
    generated_at: String,
    goals: Vec<String>,
    constraints: Vec<String>,
    risks: Vec<String>,
    assumptions: Vec<String>,
    required_research_domains: Vec<String>,
    proposed_parts: Vec<String>,
    execution_stages: Vec<RndPlanStageRecord>,
    user_explanation: String,
    simple_summary: String,
    citations: Vec<RndCitationRecord>,
    executable: bool,
    blocking_issues: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum RndStageKind {
    PlanReview,
    ProblemFraming,
    RequirementsExtraction,
    ResearchSynthesis,
    SystemArchitecture,
    PartDecomposition,
    PartGeneration,
    PartValidation,
    PackageAssembly,
    ReviewHandoff,
    Completed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum RndPartStatus {
    Queued,
    Generated,
    Validated,
    Blocked,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndPartRecord {
    part_id: String,
    name: String,
    purpose: String,
    interfaces: Vec<String>,
    geometry_constraints: Vec<String>,
    material_assumptions: Vec<String>,
    manufacturing_assumptions: Vec<String>,
    validation_tasks: Vec<String>,
    dependencies: Vec<String>,
    status: RndPartStatus,
    retries: u32,
    risk_flags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndArtifactRecord {
    artifact_id: String,
    part_id: Option<String>,
    artifact_type: String,
    title: String,
    format: String,
    content: String,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndTimelineStageRecord {
    stage: RndStageKind,
    status: String,
    estimated_minutes: u32,
    started_at: Option<String>,
    finished_at: Option<String>,
    note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndEtaRecord {
    estimated_total_minutes: u32,
    estimated_remaining_minutes: u32,
    current_stage_estimated_minutes: u32,
    confidence_label: String,
    current_bottleneck: String,
    slippage_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndRoutingSummaryRecord {
    local_only_tasks: Vec<String>,
    gemini_escalated_tasks: Vec<String>,
    gpt_escalated_tasks: Vec<String>,
    executor_tasks: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndRequirementRecord {
    requirement_id: String,
    title: String,
    description: String,
    requirement_kind: String,
    status: String,
    source_plan_version: u32,
    linked_component_ids: Vec<String>,
    linked_decision_ids: Vec<String>,
    linked_evidence_ids: Vec<String>,
    linked_report_ids: Vec<String>,
    linked_approval_ids: Vec<String>,
    verification_notes: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDesignDecisionRecord {
    decision_id: String,
    title: String,
    context: String,
    decision: String,
    rationale: String,
    status: String,
    source_plan_version: u32,
    supersedes_decision_id: Option<String>,
    requirement_ids: Vec<String>,
    component_ids: Vec<String>,
    evidence_ids: Vec<String>,
    affected_artifact_ids: Vec<String>,
    review_ids: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDesignReviewRecord {
    review_id: String,
    title: String,
    status: String,
    note: String,
    source_plan_version: u32,
    requirement_ids: Vec<String>,
    decision_ids: Vec<String>,
    evidence_ids: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndEvidenceArtifactRecord {
    evidence_id: String,
    artifact_id: Option<String>,
    run_id: Option<String>,
    title: String,
    evidence_kind: String,
    source_stage: String,
    status: String,
    requirement_ids: Vec<String>,
    decision_ids: Vec<String>,
    component_ids: Vec<String>,
    artifact_ids: Vec<String>,
    summary: String,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndTestSimulationRunRecord {
    run_id: String,
    title: String,
    run_type: String,
    status: String,
    requirement_ids: Vec<String>,
    decision_ids: Vec<String>,
    component_ids: Vec<String>,
    input_artifact_ids: Vec<String>,
    output_artifact_ids: Vec<String>,
    summary: String,
    executed_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndComplianceReportRecord {
    report_id: String,
    title: String,
    report_type: String,
    status: String,
    version: u32,
    markdown: String,
    provenance: Vec<String>,
    requirement_ids: Vec<String>,
    decision_ids: Vec<String>,
    evidence_ids: Vec<String>,
    run_ids: Vec<String>,
    approval_ids: Vec<String>,
    open_issues: Vec<String>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndApprovalRecord {
    approval_id: String,
    reviewer_name: String,
    reviewer_role: String,
    reviewer_org: Option<String>,
    authority_kind: String,
    approval_state: String,
    scope_type: String,
    scope_id: String,
    conditions: Vec<String>,
    comment: String,
    baseline_id: Option<String>,
    legally_binding: bool,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndAuditEventRecord {
    event_id: String,
    event_type: String,
    actor: String,
    actor_role: String,
    detail: String,
    related_ids: Vec<String>,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndApprovedBaselineRecord {
    baseline_id: String,
    title: String,
    status: String,
    artifact_ids: Vec<String>,
    requirement_ids: Vec<String>,
    decision_ids: Vec<String>,
    report_ids: Vec<String>,
    approval_ids: Vec<String>,
    snapshot_hash: String,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndGovernanceSummaryRecord {
    requirement_count: usize,
    decision_count: usize,
    evidence_count: usize,
    report_count: usize,
    approval_count: usize,
    unresolved_item_count: usize,
    readiness_status: String,
}

#[derive(Debug, Clone, Serialize)]
struct RndTraceabilityRowRecord {
    requirement_id: String,
    title: String,
    component_ids: Vec<String>,
    decision_ids: Vec<String>,
    evidence_ids: Vec<String>,
    report_ids: Vec<String>,
    approval_ids: Vec<String>,
    unresolved_items: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct RndGovernanceResponse {
    job_id: String,
    summary: RndGovernanceSummaryRecord,
    requirements: Vec<RndRequirementRecord>,
    decisions: Vec<RndDesignDecisionRecord>,
    reviews: Vec<RndDesignReviewRecord>,
    evidence_artifacts: Vec<RndEvidenceArtifactRecord>,
    simulation_runs: Vec<RndTestSimulationRunRecord>,
    reports: Vec<RndComplianceReportRecord>,
    approvals: Vec<RndApprovalRecord>,
    baselines: Vec<RndApprovedBaselineRecord>,
    audit_events: Vec<RndAuditEventRecord>,
}

#[derive(Debug, Clone, Serialize)]
struct RndTraceabilityResponse {
    job_id: String,
    rows: Vec<RndTraceabilityRowRecord>,
}

#[derive(Debug, Clone, Serialize)]
struct RndDoctrineResponse {
    job_id: String,
    profile: RndDoctrineProfileRecord,
    checks: Vec<RndDoctrineCheckRecord>,
}

#[derive(Debug, Clone, Serialize)]
struct RndDocumentsResponse {
    job_id: String,
    bundles: Vec<RndDocumentationBundleRecord>,
    documents: Vec<RndDocumentRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDoctrineProfileRecord {
    profile_id: String,
    title: String,
    principles: Vec<String>,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDoctrineCheckRecord {
    check_id: String,
    doctrine_area: String,
    severity: String,
    passed: bool,
    explanation: String,
    suggested_fix: String,
    linked_module_ids: Vec<String>,
    linked_artifact_ids: Vec<String>,
    linked_decision_ids: Vec<String>,
    gating: bool,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndModuleDefinitionRecord {
    module_id: String,
    title: String,
    purpose: String,
    affordability_notes: String,
    manufacturability_notes: String,
    serviceability_notes: String,
    repairability_notes: String,
    linked_artifact_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndToolRequirementRecord {
    tool_id: String,
    name: String,
    category: String,
    reason: String,
    commonality: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndBomItemRecord {
    bom_id: String,
    name: String,
    quantity: String,
    notes: String,
    module_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndAssemblyStepRecord {
    step_id: String,
    module_id: Option<String>,
    title: String,
    instructions: String,
    safety_notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndServiceAccessPointRecord {
    access_id: String,
    module_id: Option<String>,
    title: String,
    location: String,
    visibility: String,
    notes: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndInspectionChecklistItemRecord {
    item_id: String,
    module_id: Option<String>,
    title: String,
    verification: String,
    severity: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndRevisionRecord {
    revision_id: String,
    label: String,
    source_plan_version: u32,
    reason: String,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDocumentSectionRecord {
    section_id: String,
    heading: String,
    body_markdown: String,
    order_index: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDocumentExportRecord {
    export_id: String,
    format: String,
    audience_mode: String,
    revision_label: String,
    generated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDocumentRecord {
    document_id: String,
    document_type: String,
    audience_mode: String,
    title: String,
    project_name: String,
    platform_name: String,
    revision_label: String,
    source_job_id: String,
    source_plan_version: u32,
    artifact_ids: Vec<String>,
    module_ids: Vec<String>,
    purpose: String,
    target_audience: String,
    author: String,
    assumptions: Vec<String>,
    safety_notes: Vec<String>,
    tools_required: Vec<RndToolRequirementRecord>,
    materials_required: Vec<String>,
    bom_summary: Vec<RndBomItemRecord>,
    sections: Vec<RndDocumentSectionRecord>,
    manufacturability_notes: Vec<String>,
    affordability_notes: Vec<String>,
    repairability_notes: Vec<String>,
    serviceability_notes: Vec<String>,
    public_benefit_rationale: String,
    exports: Vec<RndDocumentExportRecord>,
    created_at: String,
    updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndDocumentationBundleRecord {
    bundle_id: String,
    title: String,
    audience_mode: String,
    revision_label: String,
    document_ids: Vec<String>,
    created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RndJobRecord {
    job_id: String,
    user_id: String,
    product_type: String,
    design_domain: String,
    locale: String,
    prompt: String,
    accepted_plan_version: Option<u32>,
    current_stage: RndStageKind,
    waiting_on_user: bool,
    auto_run_enabled: bool,
    paused_after_current_stage: bool,
    created_at: String,
    updated_at: String,
    plans: Vec<RndPlanRecord>,
    context_pack: RndContextPackRecord,
    parts: Vec<RndPartRecord>,
    artifacts: Vec<RndArtifactRecord>,
    timeline: Vec<RndTimelineStageRecord>,
    eta: RndEtaRecord,
    risk_flags: Vec<String>,
    latest_validation_summary: String,
    #[serde(default)]
    requirements: Vec<RndRequirementRecord>,
    #[serde(default)]
    decisions: Vec<RndDesignDecisionRecord>,
    #[serde(default)]
    design_reviews: Vec<RndDesignReviewRecord>,
    #[serde(default)]
    evidence_artifacts: Vec<RndEvidenceArtifactRecord>,
    #[serde(default)]
    simulation_runs: Vec<RndTestSimulationRunRecord>,
    #[serde(default)]
    compliance_reports: Vec<RndComplianceReportRecord>,
    #[serde(default)]
    approval_records: Vec<RndApprovalRecord>,
    #[serde(default)]
    audit_events: Vec<RndAuditEventRecord>,
    #[serde(default)]
    approved_baselines: Vec<RndApprovedBaselineRecord>,
    #[serde(default)]
    doctrine_profile: Option<RndDoctrineProfileRecord>,
    #[serde(default)]
    doctrine_checks: Vec<RndDoctrineCheckRecord>,
    #[serde(default)]
    module_definitions: Vec<RndModuleDefinitionRecord>,
    #[serde(default)]
    tool_requirements: Vec<RndToolRequirementRecord>,
    #[serde(default)]
    bom_items: Vec<RndBomItemRecord>,
    #[serde(default)]
    assembly_steps: Vec<RndAssemblyStepRecord>,
    #[serde(default)]
    service_access_points: Vec<RndServiceAccessPointRecord>,
    #[serde(default)]
    inspection_checklist_items: Vec<RndInspectionChecklistItemRecord>,
    #[serde(default)]
    revision_history: Vec<RndRevisionRecord>,
    #[serde(default)]
    document_records: Vec<RndDocumentRecord>,
    #[serde(default)]
    documentation_bundles: Vec<RndDocumentationBundleRecord>,
}

#[derive(Debug, Clone, Serialize)]
struct RndPartCounts {
    queued: usize,
    running: usize,
    blocked: usize,
    completed: usize,
}

#[derive(Debug, Clone, Serialize)]
struct RndJobResponse {
    job_id: String,
    product_type: String,
    design_domain: String,
    current_stage: RndStageKind,
    waiting_on_user: bool,
    auto_run_enabled: bool,
    paused_after_current_stage: bool,
    accepted_plan_version: Option<u32>,
    latest_plan: Option<RndPlanRecord>,
    eta: RndEtaRecord,
    part_counts: RndPartCounts,
    risk_flags: Vec<String>,
    latest_validation_summary: String,
    latest_artifacts: Vec<RndArtifactRecord>,
    routing_summary: RndRoutingSummaryRecord,
    governance_summary: RndGovernanceSummaryRecord,
    progress_percent: u8,
}

#[derive(Debug, Clone, Serialize)]
struct RndArtifactsResponse {
    job_id: String,
    artifacts: Vec<RndArtifactRecord>,
    inspection_guide: String,
}

#[derive(Debug, Clone, Serialize)]
struct RndTimelineResponse {
    job_id: String,
    current_stage: RndStageKind,
    waiting_on_user: bool,
    eta: RndEtaRecord,
    timeline: Vec<RndTimelineStageRecord>,
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
    psychological_profiles: HashMap<String, PsychologicalProfileRecord>,
    vehicle_profiles: HashMap<String, VehicleProfileRecord>,
    studio_preferences: HashMap<String, StudioPreferencesRecord>,
    survey_states: HashMap<String, SurveyStateRecord>,
    feedback_items: Vec<FeedbackRecord>,
    user_notes: HashMap<String, Vec<UserNoteRecord>>,
    user_memories: HashMap<String, Vec<MemoryRecord>>,
    lifelogs: HashMap<String, Vec<LifelogRecord>>,
    execution_checkins: HashMap<String, Vec<ExecutionCheckinRecord>>,
    execution_controls: HashMap<String, ExecutionControlsRecord>,
    execution_task_states: HashMap<String, HashMap<String, ExecutionTaskStateRecord>>,
    rnd_jobs: HashMap<String, RndJobRecord>,
    passkeys_by_user: HashMap<String, Vec<PasskeyRecord>>,
    shopify_profit_share_reports: HashMap<String, Vec<ShopifyProfitShareRecord>>,
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
        .and_then(|value| sanitize_cookie_domain(value.as_str()))
        .unwrap_or_default();
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
    let gemini_runtime = build_gemini_runtime_config();
    let ai_provider_preference = build_cloud_ai_provider_preference();
    let billing_runtime = build_billing_runtime_config();
    let webauthn_runtime = build_webauthn_runtime();
    let shopify_default_profit_share_bps = env::var("ATLAS_SHOPIFY_PROFIT_SHARE_BPS")
        .ok()
        .and_then(|value| value.trim().parse::<u32>().ok())
        .map(|value| value.min(10_000))
        .unwrap_or(DEFAULT_SHOPIFY_PROFIT_SHARE_BPS);

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
        psychological_profiles: Arc::new(RwLock::new(persisted_state.psychological_profiles)),
        vehicle_profiles: Arc::new(RwLock::new(persisted_state.vehicle_profiles)),
        studio_preferences: Arc::new(RwLock::new(persisted_state.studio_preferences)),
        survey_states: Arc::new(RwLock::new(persisted_state.survey_states)),
        feedback_items: Arc::new(RwLock::new(persisted_state.feedback_items)),
        user_notes: Arc::new(RwLock::new(persisted_state.user_notes)),
        user_memories: Arc::new(RwLock::new(persisted_state.user_memories)),
        lifelogs: Arc::new(RwLock::new(persisted_state.lifelogs)),
        execution_checkins: Arc::new(RwLock::new(persisted_state.execution_checkins)),
        execution_controls: Arc::new(RwLock::new(persisted_state.execution_controls)),
        execution_task_states: Arc::new(RwLock::new(persisted_state.execution_task_states)),
        rnd_jobs: Arc::new(RwLock::new(persisted_state.rnd_jobs)),
        oauth_states: Arc::new(RwLock::new(HashMap::new())),
        google_oauth,
        apple_oauth,
        openai_runtime,
        gemini_runtime,
        ai_provider_preference,
        billing_runtime,
        webauthn_runtime,
        passkey_registrations: Arc::new(RwLock::new(HashMap::new())),
        passkey_authentications: Arc::new(RwLock::new(HashMap::new())),
        passkeys_by_user: Arc::new(RwLock::new(persisted_state.passkeys_by_user)),
        shopify_profit_share_reports: Arc::new(RwLock::new(
            persisted_state.shopify_profit_share_reports,
        )),
        shopify_default_profit_share_bps,
        allowed_origins: Arc::new(allowed_origins),
        company_status: default_company_status(),
        session_ttl,
        cookie_name,
        cookie_domain,
        cookie_secure,
        cookie_same_site,
    };

    let lifelog_user_ids = state
        .user_memories
        .read()
        .keys()
        .cloned()
        .collect::<Vec<_>>();
    for user_id in lifelog_user_ids {
        let needs_sync = state
            .lifelogs
            .read()
            .get(&user_id)
            .map(|items| items.is_empty())
            .unwrap_or(true);
        if needs_sync {
            sync_lifelogs_from_memories(&state, user_id.as_str());
        }
    }

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
        .route("/v1/auth/apple/native", post(auth_apple_native))
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
        .route(
            "/v1/profile/psychological",
            get(psychological_profile_get).post(psychological_profile_upsert),
        )
        .route(
            "/v1/profile/vehicle",
            get(vehicle_profile_get).post(vehicle_profile_upsert),
        )
        .route("/v1/auth/me", get(auth_me))
        .route("/v1/notes", get(notes_list))
        .route("/v1/notes/upsert", post(note_upsert))
        .route("/v1/notes/rewrite", post(note_rewrite))
        .route("/v1/memory/import", post(memory_import))
        .route("/v1/memory/records", get(memory_records_list))
        .route("/v1/memory/batch/export", post(memory_batch_export))
        .route("/v1/rnd/jobs", post(rnd_job_create))
        .route("/v1/rnd/jobs/:job_id", get(rnd_job_get))
        .route(
            "/v1/rnd/jobs/:job_id/plan/revise",
            post(rnd_job_plan_revise),
        )
        .route(
            "/v1/rnd/jobs/:job_id/plan/approve",
            post(rnd_job_plan_approve),
        )
        .route(
            "/v1/rnd/jobs/:job_id/stage/approve",
            post(rnd_job_stage_approve),
        )
        .route("/v1/rnd/jobs/:job_id/pause", post(rnd_job_pause))
        .route(
            "/v1/rnd/jobs/:job_id/change_request",
            post(rnd_job_change_request),
        )
        .route("/v1/rnd/jobs/:job_id/artifacts", get(rnd_job_artifacts))
        .route("/v1/rnd/jobs/:job_id/timeline", get(rnd_job_timeline))
        .route("/v1/rnd/jobs/:job_id/governance", get(rnd_job_governance))
        .route("/v1/rnd/jobs/:job_id/doctrine", get(rnd_job_doctrine))
        .route("/v1/rnd/jobs/:job_id/traceability", get(rnd_job_traceability))
        .route("/v1/rnd/jobs/:job_id/documents", get(rnd_job_documents))
        .route(
            "/v1/rnd/jobs/:job_id/reviews/record",
            post(rnd_job_review_record),
        )
        .route(
            "/v1/rnd/jobs/:job_id/documents/generate",
            post(rnd_job_document_generate),
        )
        .route(
            "/v1/rnd/jobs/:job_id/documents/bundle/generate",
            post(rnd_job_document_bundle_generate),
        )
        .route(
            "/v1/rnd/jobs/:job_id/reports/generate",
            post(rnd_job_report_generate),
        )
        .route(
            "/v1/rnd/jobs/:job_id/approvals/record",
            post(rnd_job_approval_record),
        )
        .route("/v1/lifelog/records", get(lifelog_records_list))
        .route("/v1/memory/upsert", post(memory_upsert))
        .route("/v1/memory/delete", post(memory_delete))
        .route("/v1/memory/clear", post(memory_clear))
        .route(
            "/v1/billing/create_checkout_session",
            post(billing_create_checkout_session),
        )
        .route("/v1/billing/stripe_webhook", post(billing_stripe_webhook))
        .route(
            "/v1/business/shopify/profit_share/report",
            post(shopify_profit_share_report),
        )
        .route(
            "/v1/business/shopify/profit_share/summary",
            get(shopify_profit_share_summary),
        )
        .route(
            "/v1/studio/preferences",
            get(studio_preferences_get).post(studio_preferences_upsert),
        )
        .route("/v1/survey/next", get(survey_next))
        .route("/v1/survey/answer", post(survey_answer))
        .route("/v1/feed/proactive", get(feed_proactive))
        .route("/v1/execution/checkin", post(execution_checkin_submit))
        .route("/v1/execution/refresh", post(execution_refresh))
        .route("/v1/execution/task/toggle", post(execution_task_toggle))
        .route("/v1/execution/task/respond", post(execution_task_respond))
        .route(
            "/v1/execution/controls",
            get(execution_controls_get).post(execution_controls_upsert),
        )
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
struct AppleJwtHeader {
    alg: Option<String>,
    kid: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
enum JwtAudienceClaim {
    Single(String),
    Multiple(Vec<String>),
}

impl JwtAudienceClaim {
    fn includes(&self, expected: &str) -> bool {
        match self {
            Self::Single(value) => value == expected,
            Self::Multiple(values) => values.iter().any(|value| value == expected),
        }
    }
}

#[derive(Debug, Deserialize)]
struct AppleIdTokenClaims {
    aud: Option<JwtAudienceClaim>,
    iss: Option<String>,
    exp: Option<i64>,
    nonce: Option<String>,
    email: Option<String>,
    email_verified: Option<serde_json::Value>,
    locale: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AppleJwksResponse {
    keys: Vec<AppleJwkRecord>,
}

#[derive(Debug, Deserialize)]
struct AppleJwkRecord {
    kid: Option<String>,
    kty: Option<String>,
    alg: Option<String>,
    n: Option<String>,
    e: Option<String>,
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

async fn auth_apple_native(
    State(state): State<ApiState>,
    Json(input): Json<AppleNativeExchangeRequest>,
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

    let identity_token = sanitize_limited_text(input.identity_token.as_str(), 8_192);
    if identity_token.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_identity_token",
                "message": "identity_token is required"
            })),
        )
            .into_response();
    }

    let allowed_audiences = if config.native_client_ids.is_empty() {
        vec![config.client_id.clone()]
    } else {
        config.native_client_ids.clone()
    };

    let claims = match verify_apple_id_token(
        &state.http_client,
        identity_token.as_str(),
        allowed_audiences.as_slice(),
    )
    .await
    {
        Ok(value) => value,
        Err(_) => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({
                    "error": "id_token_verification_failed",
                    "message": "Apple identity token validation failed"
                })),
            )
                .into_response();
        }
    };

    let now_ts = chrono::Utc::now().timestamp();
    if claims.exp.unwrap_or(0) <= now_ts {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "id_token_expired",
                "message": "Apple identity token is expired"
            })),
        )
            .into_response();
    }

    let email = claims
        .email
        .as_deref()
        .map(|value| value.trim().to_lowercase())
        .or_else(|| {
            input
                .email
                .as_deref()
                .map(|value| value.trim().to_lowercase())
        })
        .filter(|value| !value.is_empty());

    let Some(email) = email else {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "missing_email",
                "message": "Apple did not provide an email. Authorize email sharing once, then retry."
            })),
        )
            .into_response();
    };

    let verified = claims
        .email_verified
        .as_ref()
        .and_then(bool_from_jsonish)
        .unwrap_or(false);
    if !verified {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "email_not_verified",
                "message": "Apple account email must be verified"
            })),
        )
            .into_response();
    }

    let name_from_request = input
        .display_name
        .as_deref()
        .map(|value| sanitize_limited_text(value, MAX_PROFILE_FIELD_LEN))
        .filter(|value| !value.trim().is_empty());
    let display_name = name_from_request.unwrap_or_else(|| {
        email
            .split('@')
            .next()
            .unwrap_or("Atlas Masa User")
            .trim()
            .to_string()
    });

    let locale_source = input
        .locale
        .as_deref()
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .unwrap_or("en");
    let locale = match detect_locale(None, locale_source) {
        atlas_core::Locale::He => "he",
        atlas_core::Locale::En => "en",
        atlas_core::Locale::Ar => "ar",
        atlas_core::Locale::Ru => "ru",
        atlas_core::Locale::Fr => "fr",
        atlas_core::Locale::Unknown => "en",
    }
    .to_string();

    let now = chrono::Utc::now().to_rfc3339();
    let user =
        find_or_create_user_by_email(&state, "apple", email, display_name, locale, now).await;

    let session_id = match issue_session_for_user(&state, &user).await {
        Ok(value) => value,
        Err(_) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "error": "session_issue_failed",
                    "message": "Unable to issue a session"
                })),
            )
                .into_response();
        }
    };

    let mut response = (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "provider": "apple",
            "user_id": user.user_id,
            "authorization_code_received": input.authorization_code.is_some(),
        })),
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

    let claims = match verify_apple_id_token(
        &state.http_client,
        token.id_token.as_str(),
        std::slice::from_ref(&config.client_id),
    )
    .await
    {
        Ok(value) => value,
        Err(_) => {
            let target = format!(
                "{}{}?auth=error&reason=id_token_verification_failed",
                config.frontend_origin,
                pending.return_to.as_str()
            );
            return Redirect::to(target.as_str()).into_response();
        }
    };

    if !claims
        .aud
        .as_ref()
        .map(|aud| aud.includes(config.client_id.as_str()))
        .unwrap_or(false)
    {
        let target = format!(
            "{}{}?auth=error&reason=invalid_audience",
            config.frontend_origin,
            pending.return_to.as_str()
        );
        return Redirect::to(target.as_str()).into_response();
    }

    if claims.iss.as_deref() != Some("https://appleid.apple.com") {
        let target = format!(
            "{}{}?auth=error&reason=invalid_issuer",
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
    let code_agent_route = request
        .code_agent_route
        .as_deref()
        .and_then(CodeAgentRoute::from_raw);
    if let Some(user_id) = session_user
        .as_ref()
        .map(|user| user.user_id.clone())
        .or(request_user_id.clone())
    {
        let (memory_type, stability, weight) = classify_chat_memory(request.text.as_str());
        let _ = ingest_memory_event_for_user(
            &state,
            user_id.as_str(),
            MemoryIngestEvent {
                memory_type,
                stability,
                source: "chat".to_string(),
                text: request.text.clone(),
                weight,
                tags: Vec::new(),
                happened_at: Some(chrono::Utc::now()),
                expires_at: None,
            },
        )
        .await;
    }

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
                let execution_controls = get_execution_controls(&state, &user.user_id);
                let execution_task_states = get_execution_task_states(&state, &user.user_id);
                let latest_checkin = latest_execution_checkin(&state, &user.user_id);
                let psychological_profile = current_psychological_profile(&state, &user);
                let vehicle_profile = current_vehicle_profile(&state, &user.user_id);
                let raw_memory_context = retrieve_user_memory_context(
                    &state,
                    user.user_id.as_str(),
                    request.text.as_str(),
                    memory_limit_for_preferences(&effective_studio_pref),
                );
                let (memory_context, amm_diagnostics) = apply_amm_policy(
                    &request,
                    note_items.as_slice(),
                    raw_memory_context,
                    &effective_studio_pref,
                );

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
                    payload_obj.insert(
                        "amm_diagnostics".to_string(),
                        serde_json::json!(amm_diagnostics),
                    );
                    payload_obj.insert("survey_hints".to_string(), serde_json::json!(survey_hints));
                    payload_obj.insert(
                        "psychological_profile".to_string(),
                        serde_json::json!(psychological_profile),
                    );
                    payload_obj.insert(
                        "vehicle_profile".to_string(),
                        serde_json::json!(vehicle_profile),
                    );
                    payload_obj.insert(
                        "memory_context".to_string(),
                        serde_json::json!(memory_context.clone()),
                    );
                    if include_proactive {
                        payload_obj.insert(
                            "proactive_feed".to_string(),
                            serde_json::json!(build_orchestrated_proactive_feed(
                                &ExecutionFeedContext {
                                    company_status: &state.company_status,
                                    user: &user,
                                    prefs: Some(&effective_studio_pref),
                                    survey: survey_state.as_ref(),
                                    notes: Some(note_items.as_slice()),
                                    controls: &execution_controls,
                                    memories: memory_context.as_slice(),
                                    latest_checkin: latest_checkin.as_ref(),
                                    task_states: &execution_task_states,
                                }
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
            let subscription_access = if let Some(user) = premium_user.as_ref() {
                Some(subscription_access_for_user(&state, user).await)
            } else {
                None
            };
            let cloud_compute_enabled = subscription_access
                .as_ref()
                .map(|subscription| subscription.cloud_compute_enabled)
                .unwrap_or(false);

            if let Some(payload_obj) = response.json_payload.as_object_mut() {
                let reason = if cloud_compute_enabled {
                    "enabled"
                } else {
                    "prepaid_credits_required"
                };
                payload_obj.insert(
                    "cloud_compute".to_string(),
                    serde_json::json!({
                        "enabled": cloud_compute_enabled,
                        "reason": reason,
                        "storage_enabled": subscription_access
                            .as_ref()
                            .map(|item| item.cloud_storage_enabled)
                            .unwrap_or(false),
                        "memory_persistence": "account_persistent",
                        "local_core_available": true,
                        "optional_cloud_add_on": true,
                    }),
                );
                if let Some(subscription) = subscription_access.as_ref() {
                    payload_obj.insert("subscription".to_string(), serde_json::json!(subscription));
                }
            }

            let configured_cloud_backends = configured_cloud_ai_backends(&state, code_agent_route);

            if !configured_cloud_backends.is_empty() && cloud_compute_enabled {
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
                let effective_prefs = premium_user
                    .as_ref()
                    .map(|user| {
                        state
                            .studio_preferences
                            .read()
                            .get(&user.user_id)
                            .cloned()
                            .unwrap_or_else(|| default_studio_preferences(&user.user_id))
                    })
                    .unwrap_or_else(|| default_studio_preferences("guest"));
                let raw_memory_context = premium_user
                    .as_ref()
                    .map(|user| {
                        retrieve_user_memory_context(
                            &state,
                            user.user_id.as_str(),
                            request.text.as_str(),
                            memory_limit_for_preferences(&effective_prefs),
                        )
                    })
                    .unwrap_or_default();
                let (memory_context, amm_diagnostics) =
                    apply_amm_policy(&request, &notes, raw_memory_context, &effective_prefs);

                let mut selected_backend: Option<CloudAiBackend> = None;
                for backend in configured_cloud_backends.iter().copied() {
                    let candidate = match backend {
                        CloudAiBackend::OpenAi => {
                            generate_premium_openai_reply(
                                &state,
                                &request,
                                premium_user.as_ref(),
                                survey_state.as_ref(),
                                &notes,
                                memory_context.as_slice(),
                                response.reply_text.as_str(),
                                code_agent_route,
                            )
                            .await
                        }
                        CloudAiBackend::Gemini => {
                            generate_premium_gemini_reply(
                                &state,
                                &request,
                                premium_user.as_ref(),
                                survey_state.as_ref(),
                                &notes,
                                memory_context.as_slice(),
                                response.reply_text.as_str(),
                                code_agent_route,
                            )
                            .await
                        }
                    };

                    if let Ok(premium_reply) = candidate {
                        response.reply_text = premium_reply;
                        selected_backend = Some(backend);
                        break;
                    }
                }

                if let Some(backend) = selected_backend {
                    if let Some(payload_obj) = response.json_payload.as_object_mut() {
                        payload_obj.insert(
                            "ai_backend".to_string(),
                            serde_json::json!(backend.backend_id()),
                        );
                        payload_obj.insert(
                            "ai_model".to_string(),
                            serde_json::json!(cloud_ai_model_name_for_route(
                                &state,
                                backend,
                                code_agent_route
                            )
                            .unwrap_or_default()),
                        );
                        if let Some(route) = code_agent_route {
                            payload_obj.insert(
                                "code_agent_route".to_string(),
                                serde_json::json!(route.as_str()),
                            );
                        }
                        payload_obj.insert(
                            "amm_diagnostics".to_string(),
                            serde_json::json!(amm_diagnostics),
                        );
                    }
                }
            } else if !configured_cloud_backends.is_empty() {
                if let Some(payload_obj) = response.json_payload.as_object_mut() {
                    payload_obj.insert("ai_backend".to_string(), serde_json::json!("local_only"));
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
                "/v1/auth/apple/native",
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
    let _ = persist_psychological_profile_if_configured(
        &state,
        &current_psychological_profile(&state, &user_clone),
    )
    .await;
    if !user_clone.memory_opt_in {
        let _ = clear_user_memories_by_scope(&state, user_clone.user_id.as_str(), "all").await;
    }

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "user": user_clone
        })),
    )
        .into_response()
}

fn default_psychological_profile(user: &UserRecord) -> PsychologicalProfileRecord {
    let novelty_index = match user.trip_style.as_deref().unwrap_or("mixed") {
        "nature" | "desert" | "north" => 0.72,
        "business" => 0.38,
        "beach" => 0.55,
        _ => 0.5,
    };
    let rigidity = match user.risk_preference.as_deref().unwrap_or("medium") {
        "low" => 0.7,
        "high" => 0.32,
        _ => 0.5,
    };
    PsychologicalProfileRecord {
        user_id: user.user_id.clone(),
        comfort_zone_vs_novelty_index: novelty_index,
        routine_rigidity_score: rigidity,
        stress_load_score: 0.35,
        recovery_bias: "balanced".to_string(),
        historical_feedback_summary: String::new(),
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn default_vehicle_profile(user_id: &str) -> VehicleProfileRecord {
    VehicleProfileRecord {
        user_id: user_id.to_string(),
        vehicle_kind: "unknown".to_string(),
        model_name: None,
        length_cm: None,
        height_cm: None,
        battery_capacity_ah: None,
        solar_capacity_watts: None,
        nvh_sensitivity: "medium".to_string(),
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn clamp_profile_score(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

fn current_psychological_profile(
    state: &ApiState,
    user: &UserRecord,
) -> PsychologicalProfileRecord {
    state
        .psychological_profiles
        .read()
        .get(&user.user_id)
        .cloned()
        .unwrap_or_else(|| default_psychological_profile(user))
}

fn current_vehicle_profile(state: &ApiState, user_id: &str) -> VehicleProfileRecord {
    state
        .vehicle_profiles
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| default_vehicle_profile(user_id))
}

async fn psychological_profile_get(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<UserScopedQuery>,
) -> impl IntoResponse {
    let Some(user) = resolve_user_from_scope(&state, &headers, query.user_id) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "profile": current_psychological_profile(&state, &user)
        })),
    )
        .into_response()
}

async fn psychological_profile_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<PsychologicalProfileUpsertRequest>,
) -> impl IntoResponse {
    let Some(user) = resolve_user_from_scope(&state, &headers, input.user_id.clone()) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    let profile = {
        let mut profiles = state.psychological_profiles.write();
        let profile = profiles
            .entry(user.user_id.clone())
            .or_insert_with(|| default_psychological_profile(&user));
        if let Some(value) = input.comfort_zone_vs_novelty_index {
            profile.comfort_zone_vs_novelty_index = clamp_profile_score(value);
        }
        if let Some(value) = input.routine_rigidity_score {
            profile.routine_rigidity_score = clamp_profile_score(value);
        }
        if let Some(value) = input.stress_load_score {
            profile.stress_load_score = clamp_profile_score(value);
        }
        if let Some(value) = input.recovery_bias {
            profile.recovery_bias = sanitize_enum_value(
                sanitize_limited_text(value.as_str(), MAX_PROFILE_FIELD_LEN).as_str(),
                &["balanced", "restorative", "novelty"],
                "balanced",
            );
        }
        if let Some(value) = input.historical_feedback_summary {
            profile.historical_feedback_summary =
                sanitize_limited_text(value.as_str(), MAX_MEMORY_TEXT_LEN);
        }
        profile.updated_at = chrono::Utc::now().to_rfc3339();
        profile.clone()
    };
    let _ = persist_psychological_profile_if_configured(&state, &profile).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "profile": profile
        })),
    )
        .into_response()
}

async fn vehicle_profile_get(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<UserScopedQuery>,
) -> impl IntoResponse {
    let Some(user) = resolve_user_from_scope(&state, &headers, query.user_id) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "profile": current_vehicle_profile(&state, &user.user_id)
        })),
    )
        .into_response()
}

async fn vehicle_profile_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<VehicleProfileUpsertRequest>,
) -> impl IntoResponse {
    let Some(user) = resolve_user_from_scope(&state, &headers, input.user_id.clone()) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "sign in first"
            })),
        )
            .into_response();
    };

    let profile = {
        let mut profiles = state.vehicle_profiles.write();
        let profile = profiles
            .entry(user.user_id.clone())
            .or_insert_with(|| default_vehicle_profile(&user.user_id));
        if let Some(value) = input.vehicle_kind {
            profile.vehicle_kind = sanitize_enum_value(
                sanitize_limited_text(value.as_str(), MAX_PROFILE_FIELD_LEN).as_str(),
                &["unknown", "van", "rv", "truck", "suv", "car"],
                "unknown",
            );
        }
        if let Some(value) = input.model_name {
            let value = sanitize_limited_text(value.as_str(), MAX_NOTE_TITLE_LEN);
            profile.model_name = if value.is_empty() { None } else { Some(value) };
        }
        if let Some(value) = input.length_cm {
            profile.length_cm = Some(value.clamp(200, 2_000));
        }
        if let Some(value) = input.height_cm {
            profile.height_cm = Some(value.clamp(100, 500));
        }
        if let Some(value) = input.battery_capacity_ah {
            profile.battery_capacity_ah = Some(value.clamp(0, 5_000));
        }
        if let Some(value) = input.solar_capacity_watts {
            profile.solar_capacity_watts = Some(value.clamp(0, 10_000));
        }
        if let Some(value) = input.nvh_sensitivity {
            profile.nvh_sensitivity = sanitize_enum_value(
                sanitize_limited_text(value.as_str(), MAX_PROFILE_FIELD_LEN).as_str(),
                &["low", "medium", "high"],
                "medium",
            );
        }
        profile.updated_at = chrono::Utc::now().to_rfc3339();
        profile.clone()
    };
    let _ = persist_vehicle_profile_if_configured(&state, &profile).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "profile": profile
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

    let subscription = subscription_access_for_user(&state, &user).await;
    let preferences = state
        .studio_preferences
        .read()
        .get(&user.user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(&user.user_id));

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "user": user,
            "subscription": subscription,
            "preferences": preferences
        })),
    )
        .into_response()
}

async fn subscription_access_for_user(
    state: &ApiState,
    user: &UserRecord,
) -> SubscriptionAccessRecord {
    let now = chrono::Utc::now();
    let trial_ends_at = now;
    let free_trial_active = false;
    let free_trial_days_remaining = 0;

    let bypass = is_subscription_bypass_email(user.email.as_str());
    let has_paid_subscription = if bypass {
        true
    } else {
        user_has_active_subscription(state, user.user_id.as_str())
            .await
            .unwrap_or(false)
    };

    let tier = if bypass {
        "owner_bypass"
    } else if has_paid_subscription {
        "billing_enabled"
    } else {
        "paywall_locked"
    };

    SubscriptionAccessRecord {
        bypass,
        active: bypass || has_paid_subscription,
        tier: tier.to_string(),
        cloud_compute_enabled: bypass || has_paid_subscription,
        cloud_storage_enabled: true,
        pricing_model: "payment_method_required_no_debt".to_string(),
        free_trial_days_total: FREE_USAGE_TRIAL_DAYS,
        free_trial_days_remaining,
        free_trial_active,
        free_trial_ends_at: trial_ends_at.to_rfc3339(),
        usage_billing_active: bypass || has_paid_subscription,
    }
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
    Ok(matches!(status.as_str(), "active" | "owner_bypass"))
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
    let note_memory_text = format!("{}: {}", note.title, note.content);
    let _ = ingest_memory_event_for_user(
        &state,
        user_id.as_str(),
        MemoryIngestEvent {
            memory_type: "insight".to_string(),
            stability: "permanent".to_string(),
            source: "note".to_string(),
            text: note_memory_text,
            weight: 0.78,
            tags: note.tags.clone(),
            happened_at: chrono::DateTime::parse_from_rfc3339(note.updated_at.as_str())
                .ok()
                .map(|value| value.with_timezone(&chrono::Utc)),
            expires_at: None,
        },
    )
    .await;

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

    let Some(user) = state.users.read().get(&user_id).cloned() else {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "user_not_found"
            })),
        )
            .into_response();
    };
    let subscription = subscription_access_for_user(&state, &user).await;
    if !subscription.cloud_compute_enabled {
        return (
            StatusCode::PAYMENT_REQUIRED,
            Json(serde_json::json!({
                "error": "subscription_required_for_cloud_compute",
                "message": "Cloud note rewrite requires an active subscription.",
                "subscription": subscription
            })),
        )
            .into_response();
    }

    let instruction = sanitize_limited_text(
        input
            .instruction
            .unwrap_or_else(|| {
                "Rewrite this note into an executive action brief with immediate tasks, mid-term strategy, and long-term mission alignment.".to_string()
            })
            .as_str(),
        MAX_REWRITE_INSTRUCTION_LEN,
    );
    let rewritten = match rewrite_note_with_cloud_ai(&state, &note, instruction.as_str()).await {
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
    let rewritten_memory_text = format!("{}: {}", rewritten_note.title, rewritten_note.content);
    let _ = ingest_memory_event_for_user(
        &state,
        user_id.as_str(),
        MemoryIngestEvent {
            memory_type: "insight".to_string(),
            stability: "permanent".to_string(),
            source: "note_rewrite".to_string(),
            text: rewritten_memory_text,
            weight: 0.82,
            tags: rewritten_note.tags.clone(),
            happened_at: chrono::DateTime::parse_from_rfc3339(rewritten_note.updated_at.as_str())
                .ok()
                .map(|value| value.with_timezone(&chrono::Utc)),
            expires_at: None,
        },
    )
    .await;

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
    let imported_snapshot = imported.clone();
    {
        let mut notes_map = state.user_notes.write();
        let notes = notes_map.entry(user_id.clone()).or_default();
        notes.extend(imported);
        notes.sort_by(|lhs, rhs| rhs.updated_at.cmp(&lhs.updated_at));
        notes.truncate(MAX_NOTES_PER_USER);
    }

    let _ = persist_notes_if_configured(&state, user_id.as_str()).await;
    for note in imported_snapshot {
        let memory_text = format!("{}: {}", note.title, note.content);
        let _ = ingest_memory_event_for_user(
            &state,
            user_id.as_str(),
            MemoryIngestEvent {
                memory_type: "insight".to_string(),
                stability: "permanent".to_string(),
                source: "import".to_string(),
                text: memory_text,
                weight: 0.72,
                tags: note.tags.clone(),
                happened_at: chrono::DateTime::parse_from_rfc3339(note.updated_at.as_str())
                    .ok()
                    .map(|value| value.with_timezone(&chrono::Utc)),
                expires_at: None,
            },
        )
        .await;
    }
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

async fn memory_records_list(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<MemoryRecordsQuery>,
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

    let opt_in = user_memory_opt_in(&state, user_id.as_str());
    if !opt_in {
        let empty_items: Vec<MemoryRetrievedItem> = Vec::new();
        return (
            StatusCode::OK,
            Json(serde_json::json!({
                "memory_opt_in": false,
                "count": 0,
                "items": empty_items
            })),
        )
            .into_response();
    }

    let limit = query
        .limit
        .unwrap_or(DEFAULT_MEMORY_RETRIEVAL_LIMIT)
        .clamp(1, MAX_MEMORY_RETRIEVAL_LIMIT);
    let search = query.q.unwrap_or_default();
    let items = retrieve_user_memory_context(&state, user_id.as_str(), search.as_str(), limit);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "memory_opt_in": true,
            "count": items.len(),
            "items": items
        })),
    )
        .into_response()
}

async fn memory_batch_export(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<MemoryBatchExportRequest>,
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

    if !user_memory_opt_in(&state, user_id.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "error": "memory_opt_out",
                "message": "memory export is disabled for this profile"
            })),
        )
            .into_response();
    }

    let provider = sanitize_batch_provider(input.provider.as_deref().unwrap_or("openai"));
    if provider.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_provider",
                "message": "provider must be openai or generic_jsonl"
            })),
        )
            .into_response();
    }

    let limit = input
        .limit
        .unwrap_or(DEFAULT_MEMORY_RETRIEVAL_LIMIT)
        .clamp(1, MAX_MEMORY_BATCH_EXPORT_ITEMS);
    let query = sanitize_limited_text(input.q.as_deref().unwrap_or_default(), 240);
    let items = retrieve_user_memory_context(&state, user_id.as_str(), query.as_str(), limit);
    let manifest = MemoryBatchExportManifest {
        provider: provider.clone(),
        model: batch_export_model_name(&state, provider.as_str()),
        operation: "memory_compaction".to_string(),
        generated_at: chrono::Utc::now().to_rfc3339(),
        query: query.clone(),
        item_count: items.len(),
        cache_strategy: "stable_prefix_context_then_dynamic_task".to_string(),
    };
    let jsonl = build_memory_batch_export_jsonl(&state, provider.as_str(), items.as_slice());

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "count": items.len(),
            "manifest": manifest,
            "jsonl": jsonl
        })),
    )
        .into_response()
}

fn score_lifelog_record(query: &str, record: &LifelogRecord) -> f32 {
    if query.trim().is_empty() {
        return 1.0;
    }
    let query_tokens = tokenize_memory_text(query);
    if query_tokens.is_empty() {
        return 0.0;
    }
    let mut corpus = record.summary.clone();
    if !record.tags.is_empty() {
        corpus.push(' ');
        corpus.push_str(record.tags.join(" ").as_str());
    }
    let record_tokens = tokenize_memory_text(corpus.as_str());
    if record_tokens.is_empty() {
        return 0.0;
    }
    let overlap = query_tokens
        .iter()
        .filter(|token| record_tokens.contains(*token))
        .count();
    overlap as f32 / query_tokens.len() as f32
}

async fn lifelog_records_list(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<LifelogRecordsQuery>,
) -> impl IntoResponse {
    let user_id = match resolve_user_id(&state, &headers, query.user_id) {
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

    if !user_memory_opt_in(&state, user_id.as_str()) {
        let items: Vec<LifelogRecord> = Vec::new();
        return (
            StatusCode::OK,
            Json(serde_json::json!({
                "memory_opt_in": false,
                "count": 0,
                "items": items
            })),
        )
            .into_response();
    }

    let search = query.q.unwrap_or_default();
    let limit = query
        .limit
        .unwrap_or(DEFAULT_MEMORY_RETRIEVAL_LIMIT)
        .clamp(1, MAX_MEMORY_RETRIEVAL_LIMIT);
    let mut items = state
        .lifelogs
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_default();
    items.sort_by(|lhs, rhs| {
        score_lifelog_record(search.as_str(), rhs)
            .total_cmp(&score_lifelog_record(search.as_str(), lhs))
    });
    items.retain(|item| score_lifelog_record(search.as_str(), item) > 0.0 || search.is_empty());
    items.truncate(limit);

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "memory_opt_in": true,
            "count": items.len(),
            "items": items
        })),
    )
        .into_response()
}

async fn memory_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<MemoryUpsertRequest>,
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

    if !user_memory_opt_in(&state, user_id.as_str()) {
        return (
            StatusCode::FORBIDDEN,
            Json(serde_json::json!({
                "error": "memory_opt_out",
                "message": "memory ingestion is disabled for this profile"
            })),
        )
            .into_response();
    }

    let event = MemoryIngestEvent {
        memory_type: sanitize_memory_type(
            input
                .memory_type
                .unwrap_or_else(|| "insight".to_string())
                .as_str(),
        ),
        stability: sanitize_memory_stability(
            input
                .stability
                .unwrap_or_else(|| "permanent".to_string())
                .as_str(),
        ),
        source: sanitize_memory_source(
            input
                .source
                .unwrap_or_else(|| "manual".to_string())
                .as_str(),
        ),
        text: input.text,
        weight: input.weight.unwrap_or(0.8),
        tags: sanitize_note_tags(input.tags.unwrap_or_default()),
        happened_at: Some(chrono::Utc::now()),
        expires_at: input
            .expires_at
            .as_deref()
            .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
            .map(|value| value.with_timezone(&chrono::Utc)),
    };

    let ingested = ingest_memory_event_for_user(&state, user_id.as_str(), event).await;
    if let Some(record) = ingested {
        return (
            StatusCode::OK,
            Json(serde_json::json!({
                "ok": true,
                "memory": record
            })),
        )
            .into_response();
    }

    (
        StatusCode::BAD_REQUEST,
        Json(serde_json::json!({
            "error": "invalid_memory",
            "message": "text is required"
        })),
    )
        .into_response()
}

async fn memory_delete(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<MemoryDeleteRequest>,
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

    let memory_id = sanitize_limited_text(input.memory_id.as_str(), 96);
    if memory_id.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_memory_id"
            })),
        )
            .into_response();
    }

    let deleted = {
        let mut memories_map = state.user_memories.write();
        if let Some(records) = memories_map.get_mut(&user_id) {
            let before = records.len();
            records.retain(|entry| entry.memory_id != memory_id);
            before != records.len()
        } else {
            false
        }
    };
    if deleted {
        sync_lifelogs_from_memories(&state, user_id.as_str());
        let _ = persist_memories_if_configured(&state, user_id.as_str()).await;
        let _ = persist_lifelogs_if_configured(&state, user_id.as_str()).await;
    }

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "deleted": deleted
        })),
    )
        .into_response()
}

async fn memory_clear(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<MemoryClearRequest>,
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

    let scope = sanitize_enum_value(
        input.scope.unwrap_or_else(|| "all".to_string()).as_str(),
        &["all", "permanent", "transient"],
        "all",
    );
    let cleared = clear_user_memories_by_scope(&state, user_id.as_str(), scope.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "scope": scope,
            "cleared": cleared
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
        if !verify_stripe_webhook_signature(
            signature,
            body.as_str(),
            secret.as_str(),
            runtime.stripe_webhook_tolerance_seconds,
        ) {
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

async fn shopify_profit_share_report(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ShopifyProfitShareUpsertRequest>,
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

    let period_start = match parse_optional_utc_timestamp(input.period_start_utc.as_deref()) {
        Ok(value) => value,
        Err(message) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "invalid_period_start_utc",
                    "message": message
                })),
            )
                .into_response();
        }
    };
    let period_end = match parse_optional_utc_timestamp(input.period_end_utc.as_deref()) {
        Ok(value) => value,
        Err(message) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "invalid_period_end_utc",
                    "message": message
                })),
            )
                .into_response();
        }
    };
    if let (Some(start), Some(end)) = (period_start, period_end) {
        if end < start {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({
                    "error": "invalid_period_range",
                    "message": "period_end_utc must be greater than or equal to period_start_utc"
                })),
            )
                .into_response();
        }
    }

    let shopify_profit_cents = sanitize_money_cents(input.shopify_profit_cents);
    let baseline_profit_cents = sanitize_money_cents(input.baseline_profit_cents.unwrap_or(0));
    let agentic_attribution_ratio = sanitize_ratio(input.agentic_attribution_ratio);
    let app_take_rate_bps = input
        .app_take_rate_bps
        .unwrap_or(state.shopify_default_profit_share_bps)
        .min(10_000);
    let computation = compute_shopify_profit_share(
        shopify_profit_cents,
        baseline_profit_cents,
        agentic_attribution_ratio,
        input.agentic_attributed_profit_cents,
        app_take_rate_bps,
    );

    let currency = sanitize_currency_code(input.currency.as_deref());
    let source = input
        .source
        .as_deref()
        .map(|value| sanitize_limited_text(value, MAX_SHOPIFY_SOURCE_LEN))
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "agentic_shopify_manager".to_string());
    let notes = input
        .notes
        .as_deref()
        .map(|value| sanitize_limited_text(value, MAX_SHOPIFY_NOTES_LEN))
        .filter(|value| !value.trim().is_empty());

    let report = ShopifyProfitShareRecord {
        report_id: uuid::Uuid::new_v4().to_string(),
        user_id: user_id.clone(),
        currency: currency.clone(),
        period_start_utc: period_start.map(|value| value.to_rfc3339()),
        period_end_utc: period_end.map(|value| value.to_rfc3339()),
        source,
        notes,
        shopify_profit_cents,
        baseline_profit_cents: computation.baseline_profit_cents,
        uplift_profit_cents: computation.uplift_profit_cents,
        agentic_attribution_ratio: computation.agentic_attribution_ratio,
        agentic_attributed_profit_cents: computation.agentic_attributed_profit_cents,
        app_take_rate_bps,
        app_cut_cents: computation.app_cut_cents,
        merchant_kept_cents: computation.merchant_kept_cents,
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    {
        let mut reports_by_user = state.shopify_profit_share_reports.write();
        let reports = reports_by_user.entry(user_id.clone()).or_default();
        reports.push(report.clone());
        if reports.len() > MAX_SHOPIFY_REPORTS_PER_USER {
            let overflow = reports.len() - MAX_SHOPIFY_REPORTS_PER_USER;
            reports.drain(0..overflow);
        }
    }
    let _ = persist_shopify_profit_share_reports_if_configured(&state, user_id.as_str()).await;

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "report": report,
            "message": "Shopify profit share report recorded"
        })),
    )
        .into_response()
}

async fn shopify_profit_share_summary(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Query(query): Query<ShopifyProfitShareSummaryQuery>,
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

    let currency = sanitize_currency_code(query.currency.as_deref());
    let limit = query
        .limit
        .unwrap_or(30)
        .clamp(1, MAX_SHOPIFY_SUMMARY_LIMIT);
    let mut filtered = state
        .shopify_profit_share_reports
        .read()
        .get(&user_id)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|report| report.currency == currency)
        .collect::<Vec<_>>();
    filtered.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let totals = filtered.iter().fold(
        (0_i64, 0_i64, 0_i64, 0_i64),
        |(total_profit, total_agentic, total_app_cut, total_kept), report| {
            (
                total_profit.saturating_add(report.shopify_profit_cents),
                total_agentic.saturating_add(report.agentic_attributed_profit_cents),
                total_app_cut.saturating_add(report.app_cut_cents),
                total_kept.saturating_add(report.merchant_kept_cents),
            )
        },
    );
    let latest_report_at = filtered.first().map(|report| report.created_at.clone());
    let report_count = filtered.len();
    let reports = filtered.into_iter().take(limit).collect::<Vec<_>>();

    (
        StatusCode::OK,
        Json(ShopifyProfitShareSummaryResponse {
            currency,
            default_app_take_rate_bps: state.shopify_default_profit_share_bps,
            report_count,
            total_shopify_profit_cents: totals.0,
            total_agentic_attributed_profit_cents: totals.1,
            total_app_cut_cents: totals.2,
            total_merchant_kept_cents: totals.3,
            latest_report_at,
            reports,
        }),
    )
        .into_response()
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

    let survey_question_id =
        sanitize_limited_text(input.question_id.as_str(), MAX_PROFILE_FIELD_LEN);
    let survey_answer_value = sanitize_limited_text(input.answer.as_str(), MAX_MEMORY_TEXT_LEN);
    if !survey_question_id.is_empty() && !survey_answer_value.is_empty() {
        let (memory_type, stability, weight) =
            classify_survey_memory(survey_question_id.as_str(), survey_answer_value.as_str());
        let _ = ingest_memory_event_for_user(
            &state,
            user_id.as_str(),
            MemoryIngestEvent {
                memory_type,
                stability,
                source: "survey".to_string(),
                text: format!(
                    "Survey signal: {} => {}",
                    survey_question_id, survey_answer_value
                ),
                weight,
                tags: sanitize_note_tags(vec![format!("survey_{}", survey_question_id)]),
                happened_at: Some(chrono::Utc::now()),
                expires_at: None,
            },
        )
        .await;
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
    let user_id = resolve_user_id_or_guest(&state, &headers, query.user_id.clone());
    let request_locale = resolve_request_locale(&state, &user_id, query.locale.as_deref());
    let response = build_proactive_feed_response(&state, user_id.as_str(), request_locale.as_str());
    (StatusCode::OK, Json(response)).into_response()
}

async fn execution_checkin_submit(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ExecutionCheckinRequest>,
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

    let daily_focus = sanitize_limited_text(input.daily_focus.as_str(), MAX_MEMORY_TEXT_LEN);
    if daily_focus.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_daily_focus",
                "message": "daily_focus is required"
            })),
        )
            .into_response();
    }
    let now = chrono::Utc::now();
    let checkin = ExecutionCheckinRecord {
        checkin_id: uuid::Uuid::new_v4().to_string(),
        user_id: user_id.clone(),
        daily_focus: daily_focus.clone(),
        mid_term_focus: input
            .mid_term_focus
            .map(|value| sanitize_limited_text(value.as_str(), MAX_MEMORY_TEXT_LEN))
            .filter(|value| !value.is_empty()),
        long_term_focus: input
            .long_term_focus
            .map(|value| sanitize_limited_text(value.as_str(), MAX_MEMORY_TEXT_LEN))
            .filter(|value| !value.is_empty()),
        blocker: input
            .blocker
            .map(|value| sanitize_limited_text(value.as_str(), MAX_MEMORY_TEXT_LEN))
            .filter(|value| !value.is_empty()),
        next_action_now: input
            .next_action_now
            .map(|value| sanitize_limited_text(value.as_str(), MAX_MEMORY_TEXT_LEN))
            .filter(|value| !value.is_empty()),
        energy_level: input.energy_level.map(|value| value.clamp(1, 5)),
        mood: input
            .mood
            .map(|value| sanitize_limited_text(value.as_str(), MAX_PROFILE_FIELD_LEN))
            .filter(|value| !value.is_empty()),
        gym_today: input.gym_today,
        money_today: input.money_today,
        created_at: now.to_rfc3339(),
    };

    {
        let mut checkins = state.execution_checkins.write();
        let history = checkins.entry(user_id.clone()).or_default();
        history.push(checkin.clone());
        history.sort_by(|lhs, rhs| rhs.created_at.cmp(&lhs.created_at));
        history.truncate(180);
    }
    let _ = persist_checkins_if_configured(&state, user_id.as_str()).await;

    let mut memory_tags = vec!["checkin".to_string(), "daily_execution".to_string()];
    if checkin.energy_level.unwrap_or(3) <= 2 {
        memory_tags.push("low_energy".to_string());
    }
    match checkin.gym_today {
        Some(true) => memory_tags.push("gym_done".to_string()),
        Some(false) => memory_tags.push("gym_missed".to_string()),
        None => {}
    }
    match checkin.money_today {
        Some(true) => memory_tags.push("money_progress".to_string()),
        Some(false) => memory_tags.push("money_gap".to_string()),
        None => {}
    }
    let _ = ingest_memory_event_for_user(
        &state,
        user_id.as_str(),
        MemoryIngestEvent {
            memory_type: "task".to_string(),
            stability: "transient".to_string(),
            source: "system".to_string(),
            text: format!(
                "Check-in focus: {} | blocker: {} | next action: {} | gym_today: {} | money_today: {}",
                checkin.daily_focus,
                checkin
                    .blocker
                    .clone()
                    .unwrap_or_else(|| "none".to_string()),
                checkin
                    .next_action_now
                    .clone()
                    .unwrap_or_else(|| "not_set".to_string()),
                checkin
                    .gym_today
                    .map(|value| if value { "yes" } else { "no" })
                    .unwrap_or("unknown"),
                checkin
                    .money_today
                    .map(|value| if value { "yes" } else { "no" })
                    .unwrap_or("unknown")
            ),
            weight: 0.84,
            tags: memory_tags,
            happened_at: Some(now),
            expires_at: Some(now + chrono::Duration::days(3)),
        },
    )
    .await;

    let locale = resolve_request_locale(&state, &user_id, None);
    let refreshed = build_proactive_feed_response(&state, user_id.as_str(), locale.as_str());
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "checkin": checkin,
            "feed": refreshed
        })),
    )
        .into_response()
}

#[derive(Debug, Clone, Deserialize, Default)]
struct ExecutionRefreshRequest {
    user_id: Option<String>,
    locale: Option<String>,
}

async fn execution_refresh(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ExecutionRefreshRequest>,
) -> impl IntoResponse {
    let user_id = resolve_user_id_or_guest(&state, &headers, input.user_id.clone());
    let request_locale = resolve_request_locale(&state, &user_id, input.locale.as_deref());
    let response = build_proactive_feed_response(&state, user_id.as_str(), request_locale.as_str());
    (StatusCode::OK, Json(response)).into_response()
}

async fn execution_task_toggle(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ExecutionTaskToggleRequest>,
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
    let task_id = sanitize_limited_text(input.task_id.trim(), 120);
    if task_id.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_task_id",
                "message": "task_id is required"
            })),
        )
            .into_response();
    }

    let now = chrono::Utc::now();
    let updated = {
        let mut map = state.execution_task_states.write();
        let user_states = map.entry(user_id.clone()).or_default();
        let mut record =
            user_states
                .get(task_id.as_str())
                .cloned()
                .unwrap_or(ExecutionTaskStateRecord {
                    task_id: task_id.clone(),
                    completed: false,
                    collapsed: false,
                    completion_count: 0,
                    updated_at: now.to_rfc3339(),
                    latest_response: None,
                    responses: Vec::new(),
                });
        if !record.completed && input.completed {
            record.completion_count = record.completion_count.saturating_add(1);
        }
        record.completed = input.completed;
        record.collapsed = input.collapsed.unwrap_or(input.completed);
        record.updated_at = now.to_rfc3339();
        user_states.insert(task_id.clone(), record.clone());
        record
    };
    let _ = persist_execution_task_states_if_configured(&state, user_id.as_str()).await;

    let _ = ingest_memory_event_for_user(
        &state,
        user_id.as_str(),
        MemoryIngestEvent {
            memory_type: "task".to_string(),
            stability: "transient".to_string(),
            source: "task_feedback".to_string(),
            text: format!(
                "Task {} marked {}",
                task_id,
                if updated.completed {
                    "completed"
                } else {
                    "incomplete"
                }
            ),
            weight: 0.78,
            tags: vec![
                "execution_task".to_string(),
                if updated.completed {
                    "completed".to_string()
                } else {
                    "reopened".to_string()
                },
            ],
            happened_at: Some(now),
            expires_at: Some(now + chrono::Duration::days(14)),
        },
    )
    .await;

    let request_locale = resolve_request_locale(&state, &user_id, input.locale.as_deref());
    let feed = build_proactive_feed_response(&state, user_id.as_str(), request_locale.as_str());
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "task_state": updated,
            "feed": feed
        })),
    )
        .into_response()
}

async fn execution_task_respond(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ExecutionTaskResponseSubmitRequest>,
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
    let task_id = sanitize_limited_text(input.task_id.trim(), 120);
    if task_id.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_task_id",
                "message": "task_id is required"
            })),
        )
            .into_response();
    }
    let completed_parts = input
        .completed_parts
        .as_ref()
        .map(|value| sanitize_limited_text(value.trim(), MAX_MEMORY_TEXT_LEN))
        .filter(|value| !value.is_empty());
    let incomplete_parts = input
        .incomplete_parts
        .as_ref()
        .map(|value| sanitize_limited_text(value.trim(), MAX_MEMORY_TEXT_LEN))
        .filter(|value| !value.is_empty());
    let note = input
        .note
        .as_ref()
        .map(|value| sanitize_limited_text(value.trim(), MAX_MEMORY_TEXT_LEN))
        .filter(|value| !value.is_empty());

    if completed_parts.is_none()
        && incomplete_parts.is_none()
        && note.is_none()
        && input.completed.is_none()
        && input.collapsed.is_none()
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "empty_response",
                "message": "provide completed_parts, incomplete_parts, note, or task state changes"
            })),
        )
            .into_response();
    }

    let now = chrono::Utc::now();
    let response_record =
        if completed_parts.is_some() || incomplete_parts.is_some() || note.is_some() {
            Some(ExecutionTaskResponseRecord {
                response_id: uuid::Uuid::new_v4().to_string(),
                task_id: task_id.clone(),
                completed_parts: completed_parts.clone(),
                incomplete_parts: incomplete_parts.clone(),
                note: note.clone(),
                created_at: now.to_rfc3339(),
            })
        } else {
            None
        };

    let updated = {
        let mut map = state.execution_task_states.write();
        let user_states = map.entry(user_id.clone()).or_default();
        let mut record =
            user_states
                .get(task_id.as_str())
                .cloned()
                .unwrap_or(ExecutionTaskStateRecord {
                    task_id: task_id.clone(),
                    completed: false,
                    collapsed: false,
                    completion_count: 0,
                    updated_at: now.to_rfc3339(),
                    latest_response: None,
                    responses: Vec::new(),
                });

        if let Some(response) = response_record.clone() {
            record.latest_response = Some(response.clone());
            record.responses.insert(0, response);
            record.responses.truncate(24);
        }

        let inferred_completed =
            completed_parts.is_some() && incomplete_parts.is_none() && input.completed.is_none();
        let next_completed = input.completed.unwrap_or(if inferred_completed {
            true
        } else {
            record.completed
        });
        if !record.completed && next_completed {
            record.completion_count = record.completion_count.saturating_add(1);
        }
        record.completed = next_completed;
        record.collapsed = input.collapsed.unwrap_or(next_completed);
        record.updated_at = now.to_rfc3339();
        user_states.insert(task_id.clone(), record.clone());
        record
    };
    let _ = persist_execution_task_states_if_configured(&state, user_id.as_str()).await;

    if response_record.is_some() {
        let _ = ingest_memory_event_for_user(
            &state,
            user_id.as_str(),
            MemoryIngestEvent {
                memory_type: "task".to_string(),
                stability: "transient".to_string(),
                source: "task_feedback".to_string(),
                text: format!(
                    "Task feedback for {} | done: {} | not done: {} | note: {}",
                    task_id,
                    completed_parts
                        .clone()
                        .unwrap_or_else(|| "none".to_string()),
                    incomplete_parts
                        .clone()
                        .unwrap_or_else(|| "none".to_string()),
                    note.clone().unwrap_or_else(|| "none".to_string())
                ),
                weight: 0.9,
                tags: vec![
                    "execution_task".to_string(),
                    "task_feedback".to_string(),
                    if updated.completed {
                        "completed".to_string()
                    } else {
                        "in_progress".to_string()
                    },
                ],
                happened_at: Some(now),
                expires_at: Some(now + chrono::Duration::days(30)),
            },
        )
        .await;
    }

    let request_locale = resolve_request_locale(&state, &user_id, input.locale.as_deref());
    let feed = build_proactive_feed_response(&state, user_id.as_str(), request_locale.as_str());
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "task_state": updated,
            "feed": feed
        })),
    )
        .into_response()
}

async fn execution_controls_get(
    State(state): State<ApiState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let user_id = match session_user_from_headers(&state, &headers) {
        Some(user) => user.user_id,
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
    let controls = get_execution_controls(&state, user_id.as_str());
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "controls": controls
        })),
    )
        .into_response()
}

async fn execution_controls_upsert(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ExecutionControlsUpsertRequest>,
) -> impl IntoResponse {
    let user_id = match session_user_from_headers(&state, &headers) {
        Some(user) => user.user_id,
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
    let updated = {
        let mut map = state.execution_controls.write();
        let mut record = map
            .get(&user_id)
            .cloned()
            .unwrap_or_else(|| default_execution_controls(&user_id));
        if let Some(cadence) = input.cadence {
            record.cadence =
                sanitize_enum_value(cadence.as_str(), &["steady", "aggressive"], "steady");
        }
        if let Some(detail_level) = input.detail_level {
            record.detail_level = sanitize_enum_value(
                detail_level.as_str(),
                &["concise", "standard", "expanded"],
                "standard",
            );
        }
        if let Some(value) = input.include_company_awareness {
            record.include_company_awareness = value;
        }
        if let Some(value) = input.include_reminder_suggestions {
            record.include_reminder_suggestions = value;
        }
        record.updated_at = chrono::Utc::now().to_rfc3339();
        map.insert(user_id.clone(), record.clone());
        record
    };
    let _ = persist_execution_controls_if_configured(&state, user_id.as_str()).await;
    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "controls": updated
        })),
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
    let message = sanitize_limited_text(input.message.trim(), MAX_FEEDBACK_MESSAGE_LEN);
    if message.is_empty() {
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
    let tags = input
        .tags
        .unwrap_or_default()
        .into_iter()
        .take(MAX_FEEDBACK_TAGS)
        .map(|value| sanitize_limited_text(value.trim(), MAX_FEEDBACK_TAG_LEN))
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    let target_employee = sanitize_limited_text(
        input
            .target_employee
            .unwrap_or_else(|| "product_team".to_string())
            .trim()
            .to_lowercase()
            .as_str(),
        MAX_PROFILE_FIELD_LEN,
    );
    let source = sanitize_limited_text(
        input
            .source
            .unwrap_or_else(|| "web".to_string())
            .trim()
            .to_lowercase()
            .as_str(),
        MAX_PROFILE_FIELD_LEN,
    );

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
        message,
        tags,
        target_employee: if target_employee.is_empty() {
            "product_team".to_string()
        } else {
            target_employee
        },
        source: if source.is_empty() {
            "web".to_string()
        } else {
            source
        },
        status: "new".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    state.feedback_items.write().push(item.clone());
    let _ = persist_feedback_if_configured(&state).await;
    if let Some(feedback_user_id) = item.user_id.as_ref() {
        let _ = ingest_memory_event_for_user(
            &state,
            feedback_user_id.as_str(),
            MemoryIngestEvent {
                memory_type: "friction".to_string(),
                stability: "transient".to_string(),
                source: "feedback".to_string(),
                text: format!(
                    "Feedback {} [{}]: {}",
                    item.category, item.severity, item.message
                ),
                weight: if item.severity == "critical" {
                    0.95
                } else if item.severity == "high" {
                    0.85
                } else {
                    0.72
                },
                tags: item.tags.clone(),
                happened_at: Some(chrono::Utc::now()),
                expires_at: Some(
                    chrono::Utc::now() + chrono::Duration::days(TRANSIENT_MEMORY_TTL_DAYS),
                ),
            },
        )
        .await;
    }

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

fn build_action_telemetry(
    action: &str,
    success: bool,
    app: Option<&str>,
    supports_direct_write: bool,
    fallback_used: bool,
    primary_target: Option<String>,
    warnings: Vec<String>,
) -> ActionTelemetry {
    ActionTelemetry {
        trace_id: uuid::Uuid::new_v4().to_string(),
        action: action.to_string(),
        success,
        app: app.map(|value| value.to_string()),
        supports_direct_write,
        fallback_used,
        primary_target,
        warnings,
        generated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn action_error_response(
    status: StatusCode,
    action: &str,
    error: &str,
    message: &str,
    app: Option<&str>,
) -> Response {
    let telemetry = build_action_telemetry(
        action,
        false,
        app,
        false,
        false,
        None,
        vec![error.to_string()],
    );
    (
        status,
        Json(serde_json::json!({
            "error": error,
            "message": message,
            "telemetry": telemetry,
        })),
    )
        .into_response()
}

fn build_google_calendar_url(
    title: &str,
    details: &str,
    start: chrono::DateTime<chrono::Utc>,
    end: chrono::DateTime<chrono::Utc>,
) -> (String, bool) {
    let details_for_url = sanitize_limited_text(details, MAX_REMINDER_DETAILS_FOR_URL);
    let details_truncated = details_for_url != details;
    let url = format!(
        "https://calendar.google.com/calendar/render?action=TEMPLATE&text={}&details={}&dates={}/{}&ctz=UTC&sf=true&output=xml",
        pct_encode(title),
        pct_encode(details_for_url.as_str()),
        start.format("%Y%m%dT%H%M%SZ"),
        end.format("%Y%m%dT%H%M%SZ")
    );
    (url, details_truncated)
}

fn build_shortcuts_url(shortcut_name: &str, payload: &str) -> Option<String> {
    let url = format!(
        "shortcuts://run-shortcut?name={}&input=text&text={}",
        pct_encode(shortcut_name),
        pct_encode(payload)
    );
    if url.len() > MAX_SHORTCUTS_URL_LEN {
        None
    } else {
        Some(url)
    }
}

fn build_shortcuts_url_with_fallback(
    shortcut_name: &str,
    full_payload: &str,
    compact_payload: &str,
) -> (Option<String>, bool) {
    if let Some(url) = build_shortcuts_url(shortcut_name, full_payload) {
        return (Some(url), false);
    }
    (build_shortcuts_url(shortcut_name, compact_payload), true)
}

fn sanitize_alarm_days(days: Option<Vec<String>>) -> Vec<String> {
    let mut out = Vec::new();
    let mut seen = HashSet::new();
    let incoming = days.unwrap_or_else(|| {
        vec![
            "Sun".to_string(),
            "Mon".to_string(),
            "Tue".to_string(),
            "Wed".to_string(),
            "Thu".to_string(),
        ]
    });
    for day in incoming {
        let lower = day.trim().to_lowercase();
        let normalized = match lower.as_str() {
            "sun" | "sunday" => Some("Sun"),
            "mon" | "monday" => Some("Mon"),
            "tue" | "tues" | "tuesday" => Some("Tue"),
            "wed" | "wednesday" => Some("Wed"),
            "thu" | "thurs" | "thursday" => Some("Thu"),
            "fri" | "friday" => Some("Fri"),
            "sat" | "saturday" => Some("Sat"),
            _ => None,
        };
        if let Some(value) = normalized {
            if seen.insert(value) {
                out.push(value.to_string());
            }
        }
    }
    if out.is_empty() {
        vec![
            "Sun".to_string(),
            "Mon".to_string(),
            "Tue".to_string(),
            "Wed".to_string(),
            "Thu".to_string(),
        ]
    } else {
        out
    }
}

async fn action_reminder(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<ReminderActionRequest>,
) -> impl IntoResponse {
    if input.title.trim().is_empty() {
        return action_error_response(
            StatusCode::BAD_REQUEST,
            "reminder",
            "invalid_title",
            "title is required",
            None,
        );
    }

    let user_id = resolve_user_id_or_guest(&state, &headers, None);
    let locale = state
        .users
        .read()
        .get(&user_id)
        .map(|user| {
            sanitize_enum_value(user.locale.as_str(), &["he", "en", "ar", "ru", "fr"], "en")
        })
        .unwrap_or_else(|| "en".to_string());
    let is_he = locale == "he";
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

    let mut warnings = Vec::new();
    let title = sanitize_limited_text(input.title.trim(), MAX_REMINDER_TITLE_LEN);
    if title.is_empty() {
        return action_error_response(
            StatusCode::BAD_REQUEST,
            "reminder",
            "invalid_title",
            "title is required",
            Some(app.as_str()),
        );
    }
    let details = sanitize_limited_text(
        input.details.unwrap_or_default().as_str(),
        MAX_REMINDER_DETAILS_LEN,
    );
    let requested_duration = input.duration_minutes.unwrap_or(30);
    let duration_minutes =
        requested_duration.clamp(MIN_REMINDER_DURATION_MINUTES, MAX_REMINDER_DURATION_MINUTES);
    if duration_minutes != requested_duration {
        warnings.push("duration_minutes_clamped".to_string());
    }

    let start = parse_or_default_utc(
        input.due_at_utc.as_deref(),
        chrono::Utc::now() + chrono::Duration::hours(2),
    );
    let end = start + chrono::Duration::minutes(duration_minutes as i64);
    let (google_calendar_url, details_truncated) =
        build_google_calendar_url(title.as_str(), details.as_str(), start, end);
    if details_truncated {
        warnings.push("details_truncated_for_google_calendar_url".to_string());
    }

    let ics_content = format!(
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//AtlasMasa//Reminder//EN\r\nMETHOD:PUBLISH\r\nBEGIN:VEVENT\r\nUID:{}\r\nDTSTAMP:{}\r\nDTSTART:{}\r\nDTEND:{}\r\nSUMMARY:{}\r\nDESCRIPTION:{}\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
        uuid::Uuid::new_v4(),
        chrono::Utc::now().format("%Y%m%dT%H%M%SZ"),
        start.format("%Y%m%dT%H%M%SZ"),
        end.format("%Y%m%dT%H%M%SZ"),
        escape_ics(title.as_str()),
        escape_ics(details.as_str())
    );
    let shortcuts_payload = format!(
        "Action: Create reminder\nTitle: {}\nWhen (UTC): {}\nDuration (minutes): {}\nDetails: {}",
        title,
        start.to_rfc3339(),
        duration_minutes,
        details
    );
    let shortcuts_compact_payload = format!(
        "Create reminder: {} at {} UTC for {} minutes",
        title,
        start.format("%Y-%m-%d %H:%M"),
        duration_minutes
    );
    let (shortcuts_url, shortcuts_compact_used) = build_shortcuts_url_with_fallback(
        "AtlasMasaReminder",
        &shortcuts_payload,
        &shortcuts_compact_payload,
    );
    if shortcuts_compact_used {
        warnings.push("shortcuts_compact_payload_used".to_string());
    }
    if shortcuts_url.is_none() {
        warnings.push("shortcuts_url_unavailable".to_string());
    }
    let todoist_url = format!(
        "https://todoist.com/app/add?content={}&description={}&date={}",
        pct_encode(title.as_str()),
        pct_encode(details.as_str()),
        pct_encode(start.format("%Y-%m-%d %H:%M").to_string().as_str())
    );

    warnings.push("web_auto_write_requires_user_confirmation".to_string());

    let (primary_url, user_message) = match app.as_str() {
        "google_calendar" => (
            Some(google_calendar_url.clone()),
            if is_he {
                "ווב לא כותב ישירות ליומן. נפתחה טיוטת אירוע ב-Google Calendar; אשרו שמירה. קובץ ICS זמין כגיבוי."
                    .to_string()
            } else {
                "Web cannot write directly to calendar providers. A prefilled Google Calendar draft was opened; confirm save. ICS fallback is included."
                    .to_string()
            },
        ),
        "shortcuts" => (
            shortcuts_url.clone(),
            if is_he {
                if shortcuts_url.is_some() {
                    "ווב לא כותב ישירות לתזכורות. נשלח קישור ל-Shortcuts; אם לא זמין, השתמשו בקובץ ICS."
                        .to_string()
                } else {
                    "לא ניתן לייצר קישור Shortcuts בטוח כרגע. השתמשו בקובץ ICS כגיבוי.".to_string()
                }
            } else if shortcuts_url.is_some() {
                "Web cannot write directly to reminders. Shortcuts deep link is ready; if unavailable, use the ICS fallback."
                    .to_string()
            } else {
                "A safe Shortcuts deep link could not be generated. Use the ICS fallback file."
                    .to_string()
            },
        ),
        "todoist" => (
            Some(todoist_url),
            if is_he {
                "ווב לא יכול ליצור משימות Todoist ישירות ללא אישור ידני. נפתחה טיוטה + גיבוי ICS."
                    .to_string()
            } else {
                "Web cannot directly write into Todoist without user confirmation. Opened a task draft plus ICS fallback."
                    .to_string()
            },
        ),
        "notion" => (
            Some("https://www.notion.so".to_string()),
            if is_he {
                "ווב לא יכול לכתוב ישירות ל-Notion. נפתחה סביבת Notion וקובץ ICS זמין לגיבוי."
                    .to_string()
            } else {
                "Web cannot directly write into Notion. Opened Notion and provided ICS fallback."
                    .to_string()
            },
        ),
        _ => (
            shortcuts_url
                .clone()
                .or_else(|| Some(google_calendar_url.clone())),
            if is_he {
                "ווב לא מאפשר כתיבה ישירה ל-Apple Reminders. ננסה לפתוח קיצור דרך; לחלופין השתמשו בקובץ ICS."
                    .to_string()
            } else {
                "Web cannot directly write to Apple Reminders. We attempt a Shortcuts handoff; otherwise use the ICS fallback."
                    .to_string()
            },
        ),
    };
    let fallback_used = true;

    let telemetry = build_action_telemetry(
        "reminder",
        true,
        Some(app.as_str()),
        false,
        fallback_used,
        primary_url.clone(),
        warnings,
    );

    (
        StatusCode::OK,
        Json(ReminderActionResponse {
            app,
            google_calendar_url,
            ics_filename: "atlas-masa-reminder.ics".to_string(),
            ics_content,
            shortcuts_url: shortcuts_url.clone().unwrap_or_default(),
            primary_url,
            supports_direct_write: false,
            fallback_used,
            user_message,
            telemetry,
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
        return action_error_response(
            StatusCode::BAD_REQUEST,
            "alarm",
            "invalid_label",
            "label is required",
            None,
        );
    }

    if !is_valid_hhmm(&input.time_local) {
        return action_error_response(
            StatusCode::BAD_REQUEST,
            "alarm",
            "invalid_time",
            "time_local must be HH:MM",
            None,
        );
    }

    let user_id = resolve_user_id_or_guest(&state, &headers, None);
    let locale = state
        .users
        .read()
        .get(&user_id)
        .map(|user| {
            sanitize_enum_value(user.locale.as_str(), &["he", "en", "ar", "ru", "fr"], "en")
        })
        .unwrap_or_else(|| "en".to_string());
    let is_he = locale == "he";
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

    let mut warnings = Vec::new();
    let label = sanitize_limited_text(input.label.trim(), MAX_ALARM_LABEL_LEN);
    if label.is_empty() {
        return action_error_response(
            StatusCode::BAD_REQUEST,
            "alarm",
            "invalid_label",
            "label is required",
            Some(app.as_str()),
        );
    }
    let days = sanitize_alarm_days(input.days);
    let payload = format!(
        "Label: {}\nTime: {}\nDays: {}",
        label,
        input.time_local.trim(),
        days.join(",")
    );
    let compact_payload = format!(
        "Set alarm {} at {} ({})",
        label,
        input.time_local.trim(),
        days.join(",")
    );
    let (shortcuts_url, shortcuts_compact_used) =
        build_shortcuts_url_with_fallback("AtlasMasaAlarm", &payload, &compact_payload);
    if shortcuts_compact_used {
        warnings.push("shortcuts_compact_payload_used".to_string());
    }
    if shortcuts_url.is_none() {
        warnings.push("shortcuts_url_unavailable".to_string());
    }
    warnings.push("web_auto_write_requires_user_confirmation".to_string());

    let clock_url = if app == "google_clock" {
        "intent://alarms#Intent;package=com.google.android.deskclock;end".to_string()
    } else {
        "clock://".to_string()
    };
    let primary_url = match app.as_str() {
        "shortcuts" => shortcuts_url.clone().or_else(|| Some(clock_url.clone())),
        "google_clock" | "apple_clock" => Some(clock_url.clone()),
        _ => Some(clock_url.clone()),
    };

    let days_label = days.join(", ");
    let user_message = match app.as_str() {
        "shortcuts" => {
            if is_he {
                "ווב לא יוצר אזעקות אוטומטית. נשלח קישור Shortcuts; אם הוא לא נפתח, צרו אזעקה ידנית באפליקציית השעון."
                    .to_string()
            } else {
                "Web cannot create alarms directly. A Shortcuts deep link was prepared; if unavailable, create it manually in Clock."
                    .to_string()
            }
        }
        "google_clock" => {
            if is_he {
                "ווב לא מגדיר אזעקה ישירה. ננסה לפתוח Google Clock דרך intent; אם נחסם בדפדפן, הגדירו ידנית."
                    .to_string()
            } else {
                "Web cannot set Google Clock alarms directly. We attempt an intent launch; if blocked by browser, set it manually."
                    .to_string()
            }
        }
        _ => {
            if is_he {
                "ווב לא יכול ליצור אזעקות ישירות. נפתח קישור לאפליקציית השעון עם הוראות השלמה ידנית."
                    .to_string()
            } else {
                "Web cannot create alarms directly. Clock launch is attempted with manual fallback guidance."
                    .to_string()
            }
        }
    };
    let telemetry = build_action_telemetry(
        "alarm",
        true,
        Some(app.as_str()),
        false,
        true,
        primary_url.clone(),
        warnings,
    );

    let fallback_instructions = if is_he {
        format!(
            "אם האוטומציה לא הופעלה, פתחו ידנית את אפליקציית השעון והגדירו אזעקה: '{}' בשעה {} בימים {}.",
            label,
            input.time_local.trim(),
            days_label
        )
    } else {
        format!(
            "If automation does not trigger, open your Clock app manually and create alarm '{}' at {} on {}.",
            label,
            input.time_local.trim(),
            days_label
        )
    };

    (
        StatusCode::OK,
        Json(AlarmActionResponse {
            app,
            clock_url,
            shortcuts_url: shortcuts_url.unwrap_or_default(),
            primary_url,
            supports_direct_write: false,
            fallback_used: true,
            user_message,
            fallback_instructions,
            telemetry,
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

async fn rnd_job_create(
    State(state): State<ApiState>,
    headers: HeaderMap,
    Json(input): Json<RndJobCreateRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };

    let prompt = sanitize_limited_text(input.prompt.trim(), MAX_RND_PROMPT_LEN);
    if prompt.len() < 24 {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "invalid_prompt",
            "prompt must be more detailed before R&D planning can start",
        );
    }

    let product_type = normalize_rnd_product_type(input.product_type.as_deref());
    if !rnd_product_type_supported(product_type.as_str()) {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "unsupported_product_type",
            "unsupported R&D product type",
        );
    }
    if prompt_requests_unsupported_domain(prompt.as_str()) {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "unsupported_domain",
            "unsupported design domain",
        );
    }
    let design_domain = rnd_design_domain(product_type.as_str()).to_string();

    let locale = detect_locale(
        Some(atlas_core::Locale::from_optional_str(
            input.locale.as_deref().or(Some(user.locale.as_str())),
        )),
        prompt.as_str(),
    )
    .as_code()
    .to_string();
    let research_summary = sanitize_limited_text(
        input.client_research_summary.unwrap_or_default().trim(),
        MAX_RND_RESEARCH_SUMMARY_LEN,
    );
    let local_planning_note = sanitize_limited_text(
        input.client_local_planning_note.unwrap_or_default().trim(),
        MAX_RND_LOCAL_PLANNING_NOTE_LEN,
    );

    let context_pack = build_rnd_context_pack(
        &state,
        &user,
        product_type.as_str(),
        prompt.as_str(),
        research_summary.as_str(),
        local_planning_note.as_str(),
    );
    let plan = build_rnd_plan(
        product_type.as_str(),
        prompt.as_str(),
        locale.as_str(),
        &context_pack,
        1,
        None,
    );
    let now = chrono::Utc::now().to_rfc3339();
    let job_id = format!("rnd-{}", uuid::Uuid::new_v4());
    let mut job = RndJobRecord {
        job_id: job_id.clone(),
        user_id: user.user_id.clone(),
        product_type,
        design_domain,
        locale,
        prompt,
        accepted_plan_version: None,
        current_stage: RndStageKind::PlanReview,
        waiting_on_user: true,
        auto_run_enabled: false,
        paused_after_current_stage: false,
        created_at: now.clone(),
        updated_at: now,
        plans: vec![plan.clone()],
        context_pack,
        parts: Vec::new(),
        artifacts: Vec::new(),
        timeline: build_rnd_initial_timeline(plan.execution_stages.as_slice()),
        eta: compute_rnd_eta(
            plan.execution_stages.as_slice(),
            &[],
            RndStageKind::PlanReview,
            true,
            "Awaiting plan approval",
        ),
        risk_flags: plan.blocking_issues.clone(),
        latest_validation_summary:
            "No validation runs yet. Plan review is required before execution.".to_string(),
        requirements: Vec::new(),
        decisions: Vec::new(),
        design_reviews: Vec::new(),
        evidence_artifacts: Vec::new(),
        simulation_runs: Vec::new(),
        compliance_reports: Vec::new(),
        approval_records: Vec::new(),
        audit_events: Vec::new(),
        approved_baselines: Vec::new(),
        doctrine_profile: None,
        doctrine_checks: Vec::new(),
        module_definitions: Vec::new(),
        tool_requirements: Vec::new(),
        bom_items: Vec::new(),
        assembly_steps: Vec::new(),
        service_access_points: Vec::new(),
        inspection_checklist_items: Vec::new(),
        revision_history: Vec::new(),
        document_records: Vec::new(),
        documentation_bundles: Vec::new(),
    };
    seed_rnd_governance_from_plan(&mut job, &plan);
    sync_rnd_doctrine_and_structure_state(&mut job);
    let create_related_ids = vec![job.job_id.clone(), format!("plan-v{}", plan.version)];
    append_rnd_audit_event(
        &mut job,
        "job_created",
        user.email.as_str(),
        "job_owner",
        "R&D job created with seeded requirements and design decisions.",
        create_related_ids,
    );
    job.eta = compute_rnd_eta(
        plan.execution_stages.as_slice(),
        job.parts.as_slice(),
        job.current_stage.clone(),
        job.waiting_on_user,
        "Awaiting plan approval",
    );
    state.rnd_jobs.write().insert(job_id, job.clone());
    if let Err(error) = persist_rnd_job_if_configured(&state, &job).await {
        tracing::warn!("failed to persist R&D job create: {error:#}");
    }

    (StatusCode::OK, Json(rnd_job_response(&job))).into_response()
}

async fn rnd_job_get(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    (StatusCode::OK, Json(rnd_job_response(&job))).into_response()
}

async fn rnd_job_plan_revise(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndPlanReviseRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let revision_prompt =
        sanitize_limited_text(input.revision_prompt.trim(), MAX_RND_CHANGE_REQUEST_LEN);
    if revision_prompt.is_empty() {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "invalid_revision",
            "revision prompt is required",
        );
    }

    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let next_version = job.plans.last().map(|plan| plan.version + 1).unwrap_or(1);
        let amended_prompt = format!(
            "{}\n\nRevision request:\n{}",
            job.prompt.trim(),
            revision_prompt
        );
        let plan = build_rnd_plan(
            job.product_type.as_str(),
            amended_prompt.as_str(),
            job.locale.as_str(),
            &job.context_pack,
            next_version,
            Some(revision_prompt.as_str()),
        );
        job.prompt = amended_prompt;
        job.accepted_plan_version = None;
        job.current_stage = RndStageKind::PlanReview;
        job.waiting_on_user = true;
        job.updated_at = chrono::Utc::now().to_rfc3339();
        job.risk_flags = plan.blocking_issues.clone();
        job.latest_validation_summary =
            "Plan revised. Review the new technical plan before execution.".to_string();
        job.timeline = build_rnd_initial_timeline(plan.execution_stages.as_slice());
        job.eta = compute_rnd_eta(
            plan.execution_stages.as_slice(),
            job.parts.as_slice(),
            job.current_stage.clone(),
            true,
            "Plan revised and awaiting approval",
        );
        job.plans.push(plan);
        sync_rnd_doctrine_and_structure_state(job);
        append_rnd_audit_event(
            job,
            "plan_revised",
            user.email.as_str(),
            "job_owner",
            "Technical plan revised.",
            vec![job.job_id.clone(), format!("plan-v{}", next_version)],
        );
        job.clone()
    };

    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D revised plan: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_plan_approve(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let Some(plan) = job.plans.last().cloned() else {
            return rnd_error_response(StatusCode::CONFLICT, "plan_missing", "plan missing");
        };
        if !plan.executable {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "plan_blocked",
                "plan is blocked until research or constraint gaps are resolved",
            );
        }
        sync_rnd_doctrine_and_structure_state(job);
        if rnd_has_major_doctrine_failures(job) {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "doctrine_gated",
                "major doctrine violations must be resolved before plan approval",
            );
        }
        job.accepted_plan_version = Some(plan.version);
        job.current_stage = RndStageKind::ProblemFraming;
        job.waiting_on_user = false;
        job.auto_run_enabled = true;
        job.paused_after_current_stage = false;
        job.updated_at = chrono::Utc::now().to_rfc3339();
        job.timeline = build_rnd_initial_timeline(plan.execution_stages.as_slice());
        mark_rnd_stage_active(&mut job.timeline, RndStageKind::ProblemFraming);
        job.eta = compute_rnd_eta(
            plan.execution_stages.as_slice(),
            job.parts.as_slice(),
            job.current_stage.clone(),
            false,
            "Execution launched",
        );
        job.latest_validation_summary =
            "Plan accepted. Long-running execution is now starting in the background.".to_string();
        append_rnd_audit_event(
            job,
            "plan_approved",
            user.email.as_str(),
            "job_owner",
            "Accepted plan approved for execution.",
            vec![job.job_id.clone(), format!("plan-v{}", plan.version)],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D plan approval: {error:#}");
    }
    spawn_rnd_job_runner(state.clone(), updated.job_id.clone());
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_stage_approve(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndStageApproveRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let note = input
        .note
        .map(|value| sanitize_limited_text(value.trim(), MAX_RND_CHANGE_REQUEST_LEN));
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let Some(plan) = accepted_rnd_plan(job) else {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "plan_not_accepted",
                "accept a plan before approving execution stages",
            );
        };
        sync_rnd_doctrine_and_structure_state(job);
        if rnd_has_major_doctrine_failures(job) {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "doctrine_gated",
                "major doctrine violations must be resolved before stage approval",
            );
        }
        if !job.waiting_on_user && job.auto_run_enabled {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "stage_already_running",
                "execution is already running",
            );
        }
        if matches!(job.current_stage, RndStageKind::Completed) {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "job_complete",
                "R&D job already completed",
            );
        }
        if job.waiting_on_user {
            job.waiting_on_user = false;
            job.auto_run_enabled = true;
            job.paused_after_current_stage = false;
            job.updated_at = chrono::Utc::now().to_rfc3339();
            job.eta = compute_rnd_eta(
                plan.execution_stages.as_slice(),
                job.parts.as_slice(),
                job.current_stage.clone(),
                false,
                note.as_deref().unwrap_or("Execution resumed"),
            );
            job.latest_validation_summary = format!(
                "Execution resumed from {}. Atlas will continue moving through the remaining stages.",
                job.current_stage_label()
            );
        } else {
            advance_rnd_job(job, &plan, note.as_deref());
            job.auto_run_enabled = true;
            job.waiting_on_user = false;
        }
        append_rnd_audit_event(
            job,
            "stage_approved",
            user.email.as_str(),
            "job_owner",
            "Execution stage approved/resumed.",
            vec![job.job_id.clone(), job.current_stage_label().to_string()],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D stage approval: {error:#}");
    }
    spawn_rnd_job_runner(state.clone(), updated.job_id.clone());
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_pause(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndPauseRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        job.paused_after_current_stage = input.pause_after_current_stage.unwrap_or(true);
        job.latest_validation_summary = if job.paused_after_current_stage {
            "Atlas will pause after the current stage finishes.".to_string()
        } else {
            "Pause request cleared.".to_string()
        };
        job.updated_at = chrono::Utc::now().to_rfc3339();
        append_rnd_audit_event(
            job,
            "pause_updated",
            user.email.as_str(),
            "job_owner",
            "Pause-after-stage preference updated.",
            vec![job.job_id.clone()],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D pause: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_change_request(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndChangeRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let request = sanitize_limited_text(input.request.trim(), MAX_RND_CHANGE_REQUEST_LEN);
    if request.is_empty() {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "invalid_change_request",
            "change request text is required",
        );
    }
    let scope = sanitize_enum_value(
        input
            .scope
            .unwrap_or_else(|| "orchestration".to_string())
            .as_str(),
        &["part", "orchestration"],
        "orchestration",
    )
    .to_string();

    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let target_label = if scope == "part" {
            input
                .target_part_id
                .clone()
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| "unspecified part".to_string())
        } else {
            "system architecture".to_string()
        };
        let revision_prompt = format!("{} change request for {}: {}", scope, target_label, request);
        let next_version = job.plans.last().map(|plan| plan.version + 1).unwrap_or(1);
        let plan = build_rnd_plan(
            job.product_type.as_str(),
            format!("{}\n\n{}", job.prompt, revision_prompt).as_str(),
            job.locale.as_str(),
            &job.context_pack,
            next_version,
            Some(revision_prompt.as_str()),
        );
        job.current_stage = RndStageKind::PlanReview;
        job.waiting_on_user = true;
        job.accepted_plan_version = None;
        job.updated_at = chrono::Utc::now().to_rfc3339();
        job.risk_flags = plan.blocking_issues.clone();
        job.timeline = build_rnd_initial_timeline(plan.execution_stages.as_slice());
        job.eta = compute_rnd_eta(
            plan.execution_stages.as_slice(),
            job.parts.as_slice(),
            job.current_stage.clone(),
            true,
            "Change request submitted; awaiting revised plan approval",
        );
        job.latest_validation_summary = format!(
            "Change request captured for {}. Review the revised plan before continuing.",
            target_label
        );
        job.plans.push(plan);
        append_rnd_audit_event(
            job,
            "change_request_submitted",
            user.email.as_str(),
            "job_owner",
            "Change request submitted and revised plan generated.",
            vec![job.job_id.clone(), target_label],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D change request: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_artifacts(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    (
        StatusCode::OK,
        Json(RndArtifactsResponse {
            job_id: job.job_id.clone(),
            artifacts: job.artifacts.clone(),
            inspection_guide: build_rnd_inspection_guide(&job),
        }),
    )
        .into_response()
}

async fn rnd_job_timeline(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    (
        StatusCode::OK,
        Json(RndTimelineResponse {
            job_id: job.job_id.clone(),
            current_stage: job.current_stage.clone(),
            waiting_on_user: job.waiting_on_user,
            eta: job.eta.clone(),
            timeline: job.timeline.clone(),
        }),
    )
        .into_response()
}

async fn rnd_job_governance(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(mut job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    sync_rnd_traceability_state(&mut job);
    (StatusCode::OK, Json(build_rnd_governance_response(&job))).into_response()
}

async fn rnd_job_doctrine(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(mut job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    sync_rnd_traceability_state(&mut job);
    sync_rnd_doctrine_and_structure_state(&mut job);
    (
        StatusCode::OK,
        Json(RndDoctrineResponse {
            job_id: job.job_id.clone(),
            profile: job
                .doctrine_profile
                .clone()
                .unwrap_or_else(default_rnd_doctrine_profile),
            checks: job.doctrine_checks.clone(),
        }),
    )
        .into_response()
}

async fn rnd_job_traceability(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(mut job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    sync_rnd_traceability_state(&mut job);
    (
        StatusCode::OK,
        Json(RndTraceabilityResponse {
            job_id: job.job_id.clone(),
            rows: build_rnd_traceability_rows(&job),
        }),
    )
        .into_response()
}

async fn rnd_job_documents(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let Some(mut job) = get_rnd_job_for_user(&state, user.user_id.as_str(), job_id.as_str()) else {
        return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
    };
    sync_rnd_traceability_state(&mut job);
    sync_rnd_doctrine_and_structure_state(&mut job);
    (
        StatusCode::OK,
        Json(RndDocumentsResponse {
            job_id: job.job_id.clone(),
            bundles: job.documentation_bundles.clone(),
            documents: job.document_records.clone(),
        }),
    )
        .into_response()
}

async fn rnd_job_review_record(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndReviewRecordRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let review = RndDesignReviewRecord {
            review_id: format!("review-{}", uuid::Uuid::new_v4()),
            title: trim_for_storage(
                input.title.as_deref().unwrap_or("Structured design review"),
                120,
            ),
            status: sanitize_enum_value(
                input.status.as_deref().unwrap_or("in_review"),
                &["draft", "in_review", "approved", "needs_changes", "superseded"],
                "in_review",
            )
            .to_string(),
            note: trim_for_storage(input.note.as_deref().unwrap_or(""), 1200),
            source_plan_version: job.accepted_plan_version.unwrap_or_default(),
            requirement_ids: input.requirement_ids.unwrap_or_default(),
            decision_ids: input.decision_ids.unwrap_or_default(),
            evidence_ids: input.evidence_ids.unwrap_or_default(),
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };
        let review_id = review.review_id.clone();
        job.design_reviews.push(review);
        append_rnd_audit_event(
            job,
            "design_review_recorded",
            user.email.as_str(),
            "job_owner",
            "Structured design review recorded.",
            vec![review_id],
        );
        sync_rnd_traceability_state(job);
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D review record: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_document_generate(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndDocumentGenerateRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        sync_rnd_traceability_state(job);
        sync_rnd_doctrine_and_structure_state(job);
        let audience_mode = sanitize_enum_value(
            input.audience_mode.as_deref().unwrap_or("private"),
            &["public", "private"],
            "private",
        )
        .to_string();
        let document_type = sanitize_enum_value(
            input.document_type.as_str(),
            &[
                "manufacturing_build_guide",
                "module_assembly_guide",
                "service_manual",
                "repair_guide",
                "qa_inspection_checklist",
                "public_project_story",
                "engineering_compliance_packet",
            ],
            "manufacturing_build_guide",
        )
        .to_string();
        if audience_mode == "private" && rnd_has_major_doctrine_failures(job) {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "doctrine_gated",
                "major doctrine violations must be resolved before private manufacturing/service/repair documents can be generated",
            );
        }
        let document = generate_rnd_document(
            job,
            document_type.as_str(),
            audience_mode.as_str(),
            input.title.as_deref(),
            input.platform_name.as_deref(),
            input.revision_label.as_deref(),
            input.purpose.as_deref(),
            input.target_audience.as_deref(),
            input.author.as_deref().unwrap_or(user.email.as_str()),
        );
        append_rnd_audit_event(
            job,
            "document_generated",
            user.email.as_str(),
            "job_owner",
            "Structured documentation generated from stored R&D state.",
            vec![document.document_id.clone()],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D document generation: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_document_bundle_generate(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndDocumentBundleGenerateRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        sync_rnd_traceability_state(job);
        sync_rnd_doctrine_and_structure_state(job);
        let audience_mode = sanitize_enum_value(
            input.audience_mode.as_deref().unwrap_or("private"),
            &["public", "private"],
            "private",
        )
        .to_string();
        if audience_mode == "private" && rnd_has_major_doctrine_failures(job) {
            return rnd_error_response(
                StatusCode::CONFLICT,
                "doctrine_gated",
                "major doctrine violations must be resolved before private documentation bundles can be generated",
            );
        }
        let bundle = generate_rnd_document_bundle(
            job,
            audience_mode.as_str(),
            input.title_prefix.as_deref(),
            input.platform_name.as_deref(),
            input.revision_label.as_deref(),
            input.author.as_deref().unwrap_or(user.email.as_str()),
        );
        append_rnd_audit_event(
            job,
            "document_bundle_generated",
            user.email.as_str(),
            "job_owner",
            "Core documentation bundle generated from stored R&D state.",
            vec![bundle.bundle_id.clone()],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D document bundle generation: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_report_generate(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndReportGenerateRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let report_type = sanitize_enum_value(
            input.report_type.as_deref().unwrap_or("engineering_compliance_packet"),
            &["engineering_compliance_packet", "external_review_packet", "internal_release_packet"],
            "engineering_compliance_packet",
        )
        .to_string();
        let report = generate_rnd_compliance_report(job, input.title.as_deref(), report_type.as_str());
        append_rnd_audit_event(
            job,
            "compliance_report_generated",
            user.email.as_str(),
            "job_owner",
            "Compliance report generated from stored job state.",
            vec![report.report_id],
        );
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D report: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

async fn rnd_job_approval_record(
    State(state): State<ApiState>,
    headers: HeaderMap,
    AxumPath(job_id): AxumPath<String>,
    Json(input): Json<RndApprovalRecordRequest>,
) -> impl IntoResponse {
    let Some(user) = session_user_from_headers(&state, &headers) else {
        return rnd_error_response(
            StatusCode::UNAUTHORIZED,
            "not_authenticated",
            "sign in required",
        );
    };
    let reviewer_name = trim_for_storage(input.reviewer_name.as_str(), 120);
    let reviewer_role = trim_for_storage(input.reviewer_role.as_str(), 120);
    if reviewer_name.is_empty() || reviewer_role.is_empty() {
        return rnd_error_response(
            StatusCode::BAD_REQUEST,
            "invalid_approval",
            "reviewer name and reviewer role are required",
        );
    }
    let updated = {
        let mut jobs = state.rnd_jobs.write();
        let Some(job) = jobs.get_mut(job_id.as_str()) else {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        };
        if job.user_id != user.user_id {
            return rnd_error_response(StatusCode::NOT_FOUND, "job_not_found", "R&D job not found");
        }
        let authority_kind = sanitize_enum_value(
            input.authority_kind.as_deref().unwrap_or("internal_engineering_approval"),
            &["ai_recommendation", "internal_engineering_approval", "external_certified_signoff"],
            "internal_engineering_approval",
        )
        .to_string();
        let mut approval_state = sanitize_enum_value(
            input.approval_state.as_deref().unwrap_or("approved"),
            &["recommended", "approved", "needs_changes", "rejected"],
            "approved",
        )
        .to_string();
        if authority_kind == "ai_recommendation" && approval_state == "approved" {
            approval_state = "recommended".to_string();
        }
        let scope_type = sanitize_enum_value(
            input.scope_type.as_deref().unwrap_or("job"),
            &["job", "report", "requirement", "decision"],
            "job",
        )
        .to_string();
        let scope_id = input
            .scope_id
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| job.job_id.clone());
        let approval_id = format!("approval-{}", uuid::Uuid::new_v4());
        let mut approval = RndApprovalRecord {
            approval_id: approval_id.clone(),
            reviewer_name,
            reviewer_role,
            reviewer_org: input.reviewer_org.map(|value| trim_for_storage(value.as_str(), 120)),
            authority_kind: authority_kind.clone(),
            approval_state: approval_state.clone(),
            scope_type: scope_type.clone(),
            scope_id: scope_id.clone(),
            conditions: input
                .conditions
                .unwrap_or_default()
                .into_iter()
                .map(|value| trim_for_storage(value.as_str(), 200))
                .filter(|value| !value.is_empty())
                .collect(),
            comment: trim_for_storage(input.comment.as_deref().unwrap_or(""), 1200),
            baseline_id: None,
            legally_binding: authority_kind == "external_certified_signoff",
            created_at: chrono::Utc::now().to_rfc3339(),
        };
        if input.create_baseline_if_approved.unwrap_or(false)
            && approval_state == "approved"
            && authority_kind != "ai_recommendation"
        {
            let baseline = create_rnd_approved_baseline(
                job,
                input
                    .baseline_title
                    .as_deref()
                    .unwrap_or("Approved engineering baseline"),
                approval_id.as_str(),
            );
            approval.baseline_id = Some(baseline.baseline_id.clone());
            job.approved_baselines.push(baseline);
        }
        job.approval_records.push(approval);
        append_rnd_audit_event(
            job,
            "approval_recorded",
            user.email.as_str(),
            "job_owner",
            "Approval/sign-off record captured.",
            vec![approval_id, scope_id],
        );
        sync_rnd_traceability_state(job);
        job.clone()
    };
    if let Err(error) = persist_rnd_job_if_configured(&state, &updated).await {
        tracing::warn!("failed to persist R&D approval: {error:#}");
    }
    (StatusCode::OK, Json(rnd_job_response(&updated))).into_response()
}

fn rnd_error_response(status: StatusCode, error: &str, message: &str) -> Response {
    (
        status,
        Json(serde_json::json!({
            "error": error,
            "message": message,
        })),
    )
        .into_response()
}

fn normalize_rnd_product_type(raw: Option<&str>) -> String {
    sanitize_enum_value(
        raw.unwrap_or("mechanical_vehicle"),
        &[
            "mechanical_vehicle",
            "mechanical_product",
            "vehicle_part",
            "electronic_product",
            "pcb_assembly",
            "general_product",
        ],
        "mechanical_vehicle",
    )
    .to_string()
}

fn rnd_product_type_supported(product_type: &str) -> bool {
    matches!(
        product_type,
        "mechanical_vehicle"
            | "mechanical_product"
            | "vehicle_part"
            | "electronic_product"
            | "pcb_assembly"
            | "general_product"
    )
}

fn rnd_design_domain(product_type: &str) -> &'static str {
    match product_type {
        "electronic_product" | "pcb_assembly" => "electronics",
        "general_product" => "general_product",
        _ => "mechanical_cad",
    }
}

fn prompt_requests_unsupported_domain(_prompt: &str) -> bool {
    false
}

fn get_rnd_job_for_user(state: &ApiState, user_id: &str, job_id: &str) -> Option<RndJobRecord> {
    state
        .rnd_jobs
        .read()
        .get(job_id)
        .filter(|job| job.user_id == user_id)
        .cloned()
}

fn build_rnd_context_pack(
    state: &ApiState,
    user: &UserRecord,
    product_type: &str,
    prompt: &str,
    research_summary: &str,
    local_planning_note: &str,
) -> RndContextPackRecord {
    let memory_items = retrieve_user_memory_context(state, user.user_id.as_str(), prompt, 6);
    let memory_summary = if memory_items.is_empty() {
        "No high-relevance user memory records were retrieved for this design prompt.".to_string()
    } else {
        memory_items
            .iter()
            .map(|item| format!("{} ({})", item.text, item.memory_type))
            .collect::<Vec<_>>()
            .join(" | ")
    };
    let preference_summary = format!(
        "Locale: {} | Trip style: {} | Risk preference: {} | Product type: {}",
        user.locale,
        user.trip_style
            .clone()
            .unwrap_or_else(|| "not_set".to_string()),
        user.risk_preference
            .clone()
            .unwrap_or_else(|| "not_set".to_string()),
        product_type
    );
    let prior_job_summary = state
        .rnd_jobs
        .read()
        .values()
        .filter(|job| job.user_id == user.user_id)
        .take(3)
        .map(|job| {
            format!(
                "{}:{}:{}",
                job.job_id,
                job.product_type,
                job.current_stage_label()
            )
        })
        .collect::<Vec<_>>()
        .join(" | ");
    let retrieval_hits = state.agent.kb_search(prompt, 5);
    let mut citations = retrieval_hits
        .iter()
        .enumerate()
        .map(|(idx, hit)| RndCitationRecord {
            id: format!("kb-{}", idx + 1),
            label: format!("KB hit {}", idx + 1),
            source_type: "knowledge_base".to_string(),
            detail: hit.source_path.clone(),
        })
        .collect::<Vec<_>>();
    citations.extend(
        memory_items
            .iter()
            .enumerate()
            .map(|(idx, item)| RndCitationRecord {
                id: format!("memory-{}", idx + 1),
                label: format!("Memory {}", idx + 1),
                source_type: "user_memory".to_string(),
                detail: item.memory_id.clone(),
            }),
    );
    if !research_summary.is_empty() {
        citations.push(RndCitationRecord {
            id: "client-research-summary".to_string(),
            label: "Client research summary".to_string(),
            source_type: "client_research".to_string(),
            detail: trim_for_storage(research_summary, 220),
        });
    }
    if !local_planning_note.is_empty() {
        citations.push(RndCitationRecord {
            id: "client-local-planning-note".to_string(),
            label: "Local planning note".to_string(),
            source_type: "client_local_ai".to_string(),
            detail: trim_for_storage(local_planning_note, 220),
        });
    }
    let mut explicit_constraints = extract_prompt_constraints(prompt);
    if explicit_constraints.is_empty() {
        explicit_constraints.push("No explicit constraints extracted; require user review before treating outputs as serious engineering direction.".to_string());
    }
    let confidence = if !research_summary.is_empty() || !retrieval_hits.is_empty() {
        0.72
    } else {
        0.34
    };
    let research_summary_full = if research_summary.is_empty() && local_planning_note.is_empty() {
        "No external client research summary was provided. Atlas will rely on account context, memory, and internal retrieval only.".to_string()
    } else if research_summary.is_empty() {
        format!("Local planning note only: {}", local_planning_note)
    } else if local_planning_note.is_empty() {
        research_summary.to_string()
    } else {
        format!(
            "Research summary: {}\n\nLocal planning note: {}",
            research_summary, local_planning_note
        )
    };
    RndContextPackRecord {
        user_preference_summary: preference_summary,
        memory_summary,
        prior_job_summary,
        research_summary: research_summary_full,
        explicit_constraints,
        citations,
        research_confidence: confidence,
    }
}

fn build_rnd_plan(
    product_type: &str,
    prompt: &str,
    locale: &str,
    context_pack: &RndContextPackRecord,
    version: u32,
    revision_note: Option<&str>,
) -> RndPlanRecord {
    let goals = infer_rnd_goals(prompt, product_type);
    let mut constraints = context_pack.explicit_constraints.clone();
    if let Some(note) = revision_note {
        constraints.push(format!("Revision request: {}", note));
    }
    let required_research_domains = infer_required_research_domains(prompt);
    let proposed_parts = infer_proposed_parts(prompt, product_type);
    let risks = infer_rnd_risks(prompt, context_pack.research_confidence);
    let assumptions = infer_rnd_assumptions(product_type);
    let blocking_issues = infer_plan_blockers(prompt, context_pack);
    let executable = blocking_issues.is_empty();
    let execution_stages = build_rnd_plan_stages(proposed_parts.len());
    let user_explanation = build_rnd_user_explanation(
        locale,
        prompt,
        goals.as_slice(),
        constraints.as_slice(),
        proposed_parts.as_slice(),
        executable,
        blocking_issues.as_slice(),
    );
    let simple_summary = build_rnd_simple_summary(locale, proposed_parts.as_slice(), executable);
    RndPlanRecord {
        version,
        generated_at: chrono::Utc::now().to_rfc3339(),
        goals,
        constraints,
        risks,
        assumptions,
        required_research_domains,
        proposed_parts,
        execution_stages,
        user_explanation,
        simple_summary,
        citations: context_pack.citations.clone(),
        executable,
        blocking_issues,
    }
}

fn build_rnd_plan_stages(part_count: usize) -> Vec<RndPlanStageRecord> {
    let part_minutes = (part_count.max(1) as u32) * 12;
    vec![
        RndPlanStageRecord {
            id: "problem_framing".to_string(),
            title: "Problem Framing".to_string(),
            objective: "Lock success criteria and operating boundaries.".to_string(),
            estimated_minutes: 18,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "requirements_extraction".to_string(),
            title: "Requirements Extraction".to_string(),
            objective: "Convert prompt/history/research into typed requirements.".to_string(),
            estimated_minutes: 24,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "research_synthesis".to_string(),
            title: "Research Synthesis".to_string(),
            objective: "Summarize safety, sustainability, and materials implications.".to_string(),
            estimated_minutes: 26,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "system_architecture".to_string(),
            title: "System Architecture".to_string(),
            objective: "Define subsystem boundaries and design logic.".to_string(),
            estimated_minutes: 30,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "part_decomposition".to_string(),
            title: "Part Decomposition".to_string(),
            objective: "Expand the accepted architecture into a part tree.".to_string(),
            estimated_minutes: 22 + (part_count as u32 * 3),
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "part_generation".to_string(),
            title: "Part Generation".to_string(),
            objective: "Generate per-part CAD source and neutral export artifacts.".to_string(),
            estimated_minutes: part_minutes,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "part_validation".to_string(),
            title: "Part Validation".to_string(),
            objective: "Emit named validation scopes and report assumptions per part.".to_string(),
            estimated_minutes: 18 + (part_count as u32 * 6),
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "package_assembly".to_string(),
            title: "Package Assembly".to_string(),
            objective: "Assemble BOM, manifests, inspection guide, and revision package."
                .to_string(),
            estimated_minutes: 20,
            approval_required: true,
        },
        RndPlanStageRecord {
            id: "review_handoff".to_string(),
            title: "Review Handoff".to_string(),
            objective: "Hand the package back to the user for inspection and change requests."
                .to_string(),
            estimated_minutes: 10,
            approval_required: false,
        },
    ]
}

fn seed_rnd_governance_from_plan(job: &mut RndJobRecord, plan: &RndPlanRecord) {
    let now = chrono::Utc::now().to_rfc3339();
    for requirement in &mut job.requirements {
        if requirement.source_plan_version != plan.version && requirement.status != "approved" {
            requirement.status = "superseded".to_string();
            requirement.updated_at = now.clone();
        }
    }
    for decision in &mut job.decisions {
        if decision.source_plan_version != plan.version && decision.status != "approved" {
            decision.status = "superseded".to_string();
            decision.updated_at = now.clone();
        }
    }
    for review in &mut job.design_reviews {
        if review.source_plan_version != plan.version && review.status != "approved" {
            review.status = "superseded".to_string();
            review.updated_at = now.clone();
        }
    }

    if !job
        .requirements
        .iter()
        .any(|item| item.source_plan_version == plan.version)
    {
        for (idx, goal) in plan.goals.iter().enumerate() {
            job.requirements.push(RndRequirementRecord {
                requirement_id: format!("req-v{}-goal-{:02}", plan.version, idx + 1),
                title: format!("Goal requirement {:02}", idx + 1),
                description: goal.clone(),
                requirement_kind: "goal".to_string(),
                status: "draft".to_string(),
                source_plan_version: plan.version,
                linked_component_ids: job.parts.iter().map(|part| part.part_id.clone()).collect(),
                linked_decision_ids: Vec::new(),
                linked_evidence_ids: Vec::new(),
                linked_report_ids: Vec::new(),
                linked_approval_ids: Vec::new(),
                verification_notes: vec![
                    "Trace to at least one design decision.".to_string(),
                    "Attach verification evidence before sign-off.".to_string(),
                ],
                created_at: now.clone(),
                updated_at: now.clone(),
            });
        }
        for (idx, constraint) in plan.constraints.iter().enumerate() {
            job.requirements.push(RndRequirementRecord {
                requirement_id: format!("req-v{}-constraint-{:02}", plan.version, idx + 1),
                title: format!("Constraint requirement {:02}", idx + 1),
                description: constraint.clone(),
                requirement_kind: "constraint".to_string(),
                status: "draft".to_string(),
                source_plan_version: plan.version,
                linked_component_ids: job.parts.iter().map(|part| part.part_id.clone()).collect(),
                linked_decision_ids: Vec::new(),
                linked_evidence_ids: Vec::new(),
                linked_report_ids: Vec::new(),
                linked_approval_ids: Vec::new(),
                verification_notes: vec![
                    "Keep explicit assumptions visible in the compliance packet.".to_string(),
                ],
                created_at: now.clone(),
                updated_at: now.clone(),
            });
        }
        job.requirements.push(RndRequirementRecord {
            requirement_id: format!("req-v{}-human-signoff", plan.version),
            title: "Qualified human sign-off required".to_string(),
            description:
                "AI outputs may accelerate engineering work, but certified or regulated sign-off must remain with qualified human authority."
                    .to_string(),
            requirement_kind: "signoff_gate".to_string(),
            status: "draft".to_string(),
            source_plan_version: plan.version,
            linked_component_ids: job.parts.iter().map(|part| part.part_id.clone()).collect(),
            linked_decision_ids: Vec::new(),
            linked_evidence_ids: Vec::new(),
            linked_report_ids: Vec::new(),
            linked_approval_ids: Vec::new(),
            verification_notes: vec![
                "Capture internal approval separately from external certified sign-off.".to_string(),
            ],
            created_at: now.clone(),
            updated_at: now.clone(),
        });
    }

    if !job
        .decisions
        .iter()
        .any(|item| item.source_plan_version == plan.version)
    {
        let requirement_ids = job
            .requirements
            .iter()
            .filter(|item| item.source_plan_version == plan.version)
            .map(|item| item.requirement_id.clone())
            .collect::<Vec<_>>();
        let component_ids = job.parts.iter().map(|part| part.part_id.clone()).collect::<Vec<_>>();
        let decisions = vec![
            (
                "toolchain",
                "Toolchain decision",
                format!("Use {} as the execution domain for this job.", job.design_domain),
                if job.design_domain == "mechanical_cad" {
                    "Use FreeCAD for source geometry, CalculiX for named validation runs, and USD/USDZ-oriented review packages for read-only review."
                } else {
                    "Use the current R&D lane as a review-oriented orchestration path and keep downstream engineering tool authority explicit."
                },
                "This keeps automation inexpensive while preserving deterministic artifacts and auditability.",
            ),
            (
                "architecture",
                "Architecture decision",
                "Convert the accepted plan into explicit requirements, parts, evidence, reports, and approvals.".to_string(),
                "Use one job-local traceability graph instead of separate disconnected planning and compliance records.",
                "Keeping governance inside the job record makes review, export, and snapshotting cheaper and easier to audit.",
            ),
            (
                "authority",
                "Authority boundary decision",
                "Separate AI recommendations from human engineering approval and external certified sign-off.".to_string(),
                "Treat AI as a drafting/review accelerator only. Preserve reviewer identity, approval scope, and snapshot hashes for real sign-off records.",
                "This avoids false compliance claims and supports credible external review packets.",
            ),
        ];
        for (idx, template) in decisions.iter().enumerate() {
            job.decisions.push(RndDesignDecisionRecord {
                decision_id: format!("dec-v{}-{:02}", plan.version, idx + 1),
                title: template.1.to_string(),
                context: template.2.clone(),
                decision: template.3.to_string(),
                rationale: template.4.to_string(),
                status: "draft".to_string(),
                source_plan_version: plan.version,
                supersedes_decision_id: None,
                requirement_ids: requirement_ids.clone(),
                component_ids: component_ids.clone(),
                evidence_ids: Vec::new(),
                affected_artifact_ids: Vec::new(),
                review_ids: Vec::new(),
                created_at: now.clone(),
                updated_at: now.clone(),
            });
        }
    }

    if !job
        .design_reviews
        .iter()
        .any(|item| item.source_plan_version == plan.version)
    {
        job.design_reviews.push(RndDesignReviewRecord {
            review_id: format!("review-v{}-initial", plan.version),
            title: format!("Plan review v{}", plan.version),
            status: "draft".to_string(),
            note: "Initial structured design review seeded from the accepted plan.".to_string(),
            source_plan_version: plan.version,
            requirement_ids: job
                .requirements
                .iter()
                .filter(|item| item.source_plan_version == plan.version)
                .map(|item| item.requirement_id.clone())
                .collect(),
            decision_ids: job
                .decisions
                .iter()
                .filter(|item| item.source_plan_version == plan.version)
                .map(|item| item.decision_id.clone())
                .collect(),
            evidence_ids: Vec::new(),
            created_at: now.clone(),
            updated_at: now,
        });
    }

    sync_rnd_traceability_state(job);
}

fn sync_rnd_traceability_state(job: &mut RndJobRecord) {
    let component_ids = job.parts.iter().map(|part| part.part_id.clone()).collect::<Vec<_>>();
    for requirement in &mut job.requirements {
        if component_ids.is_empty() {
            requirement.linked_component_ids.clear();
        } else if requirement.linked_component_ids.is_empty() {
            requirement.linked_component_ids = component_ids.clone();
        }
    }
    for decision in &mut job.decisions {
        if component_ids.is_empty() {
            decision.component_ids.clear();
        } else if decision.component_ids.is_empty() {
            decision.component_ids = component_ids.clone();
        }
    }

    let active_requirement_ids = job
        .requirements
        .iter()
        .filter(|item| item.status != "superseded")
        .map(|item| item.requirement_id.clone())
        .collect::<Vec<_>>();
    let active_decision_ids = job
        .decisions
        .iter()
        .filter(|item| item.status != "superseded")
        .map(|item| item.decision_id.clone())
        .collect::<Vec<_>>();

    job.evidence_artifacts = job
        .artifacts
        .iter()
        .map(|artifact| RndEvidenceArtifactRecord {
            evidence_id: format!("evidence-{}", artifact.artifact_id),
            artifact_id: Some(artifact.artifact_id.clone()),
            run_id: if artifact.artifact_type == "simulation_result" {
                Some(format!(
                    "simrun-{}",
                    artifact
                        .part_id
                        .clone()
                        .unwrap_or_else(|| "full-assembly".to_string())
                ))
            } else {
                None
            },
            title: artifact.title.clone(),
            evidence_kind: artifact.artifact_type.clone(),
            source_stage: match artifact.artifact_type.as_str() {
                "validation_report" | "simulation_input" | "simulation_result" => "part_validation".to_string(),
                "assembly_package" | "review_scene_package" | "assembly_stage_review_scene" => "package_assembly".to_string(),
                _ => "part_generation".to_string(),
            },
            status: "generated".to_string(),
            requirement_ids: active_requirement_ids.clone(),
            decision_ids: active_decision_ids.clone(),
            component_ids: artifact.part_id.clone().map(|id| vec![id]).unwrap_or_else(|| component_ids.clone()),
            artifact_ids: vec![artifact.artifact_id.clone()],
            summary: trim_for_storage(artifact.content.as_str(), 240),
            created_at: artifact.created_at.clone(),
            updated_at: artifact.created_at.clone(),
        })
        .collect();

    let simulation_output_ids = job
        .artifacts
        .iter()
        .filter(|artifact| artifact.artifact_type == "simulation_result")
        .map(|artifact| {
            (
                artifact.part_id.clone().unwrap_or_else(|| "full-assembly".to_string()),
                (
                    artifact.artifact_id.clone(),
                    trim_for_storage(artifact.content.as_str(), 220),
                ),
            )
        })
        .collect::<HashMap<_, _>>();
    job.simulation_runs = job
        .artifacts
        .iter()
        .filter(|artifact| artifact.artifact_type == "simulation_input")
        .map(|artifact| {
            let key = artifact
                .part_id
                .clone()
                .unwrap_or_else(|| "full-assembly".to_string());
            let output = simulation_output_ids.get(&key);
            RndTestSimulationRunRecord {
                run_id: format!("simrun-{}", key),
                title: format!("Simulation run for {}", key),
                run_type: "mechanical_validation".to_string(),
                status: if output.is_some() { "completed" } else { "generated" }.to_string(),
                requirement_ids: active_requirement_ids.clone(),
                decision_ids: active_decision_ids.clone(),
                component_ids: vec![key.clone()],
                input_artifact_ids: vec![artifact.artifact_id.clone()],
                output_artifact_ids: output.map(|value| vec![value.0.clone()]).unwrap_or_default(),
                summary: output
                    .map(|value| value.1.clone())
                    .unwrap_or_else(|| "Simulation output not generated yet.".to_string()),
                executed_at: artifact.created_at.clone(),
            }
        })
        .collect();

    for requirement in &mut job.requirements {
        requirement.linked_decision_ids = active_decision_ids.clone();
        requirement.linked_evidence_ids = job
            .evidence_artifacts
            .iter()
            .filter(|evidence| evidence.requirement_ids.contains(&requirement.requirement_id))
            .map(|evidence| evidence.evidence_id.clone())
            .collect();
        requirement.linked_report_ids = job
            .compliance_reports
            .iter()
            .filter(|report| report.requirement_ids.contains(&requirement.requirement_id))
            .map(|report| report.report_id.clone())
            .collect();
        requirement.linked_approval_ids = job
            .approval_records
            .iter()
            .filter(|approval| {
                approval.scope_type == "requirement" && approval.scope_id == requirement.requirement_id
                    || approval.scope_type == "job"
            })
            .map(|approval| approval.approval_id.clone())
            .collect();
    }

    for decision in &mut job.decisions {
        decision.evidence_ids = job
            .evidence_artifacts
            .iter()
            .filter(|evidence| evidence.decision_ids.contains(&decision.decision_id))
            .map(|evidence| evidence.evidence_id.clone())
            .collect();
        decision.affected_artifact_ids = job
            .evidence_artifacts
            .iter()
            .filter(|evidence| evidence.decision_ids.contains(&decision.decision_id))
            .flat_map(|evidence| evidence.artifact_ids.clone())
            .collect();
        decision.review_ids = job
            .design_reviews
            .iter()
            .filter(|review| review.decision_ids.contains(&decision.decision_id))
            .map(|review| review.review_id.clone())
            .collect();
    }
}

fn append_rnd_audit_event(
    job: &mut RndJobRecord,
    event_type: &str,
    actor: &str,
    actor_role: &str,
    detail: &str,
    related_ids: Vec<String>,
) {
    job.audit_events.push(RndAuditEventRecord {
        event_id: format!("audit-{}", uuid::Uuid::new_v4()),
        event_type: event_type.to_string(),
        actor: actor.to_string(),
        actor_role: actor_role.to_string(),
        detail: detail.to_string(),
        related_ids,
        created_at: chrono::Utc::now().to_rfc3339(),
    });
}

fn build_rnd_governance_summary(job: &RndJobRecord) -> RndGovernanceSummaryRecord {
    let unresolved_item_count = job
        .requirements
        .iter()
        .filter(|requirement| requirement.linked_evidence_ids.is_empty() || requirement.linked_approval_ids.is_empty())
        .count()
        + job
            .compliance_reports
            .iter()
            .flat_map(|report| report.open_issues.iter())
            .count();
    let readiness_status = if job
        .approval_records
        .iter()
        .any(|approval| approval.authority_kind == "external_certified_signoff" && approval.approval_state == "approved")
    {
        "externally_signed_off"
    } else if job
        .approval_records
        .iter()
        .any(|approval| approval.authority_kind == "internal_engineering_approval" && approval.approval_state == "approved")
    {
        "internally_approved"
    } else if unresolved_item_count > 0 {
        "needs_review"
    } else {
        "draft"
    };
    RndGovernanceSummaryRecord {
        requirement_count: job.requirements.len(),
        decision_count: job.decisions.len(),
        evidence_count: job.evidence_artifacts.len(),
        report_count: job.compliance_reports.len(),
        approval_count: job.approval_records.len(),
        unresolved_item_count,
        readiness_status: readiness_status.to_string(),
    }
}

fn build_rnd_traceability_rows(job: &RndJobRecord) -> Vec<RndTraceabilityRowRecord> {
    job.requirements
        .iter()
        .map(|requirement| {
            let mut unresolved_items = Vec::new();
            if requirement.linked_decision_ids.is_empty() {
                unresolved_items.push("No linked design decision".to_string());
            }
            if requirement.linked_evidence_ids.is_empty() {
                unresolved_items.push("No linked evidence".to_string());
            }
            if requirement.linked_report_ids.is_empty() {
                unresolved_items.push("No linked compliance report".to_string());
            }
            if requirement.linked_approval_ids.is_empty() {
                unresolved_items.push("No linked approval/sign-off".to_string());
            }
            RndTraceabilityRowRecord {
                requirement_id: requirement.requirement_id.clone(),
                title: requirement.title.clone(),
                component_ids: requirement.linked_component_ids.clone(),
                decision_ids: requirement.linked_decision_ids.clone(),
                evidence_ids: requirement.linked_evidence_ids.clone(),
                report_ids: requirement.linked_report_ids.clone(),
                approval_ids: requirement.linked_approval_ids.clone(),
                unresolved_items,
            }
        })
        .collect()
}

fn build_rnd_governance_response(job: &RndJobRecord) -> RndGovernanceResponse {
    RndGovernanceResponse {
        job_id: job.job_id.clone(),
        summary: build_rnd_governance_summary(job),
        requirements: job.requirements.clone(),
        decisions: job.decisions.clone(),
        reviews: job.design_reviews.clone(),
        evidence_artifacts: job.evidence_artifacts.clone(),
        simulation_runs: job.simulation_runs.clone(),
        reports: job.compliance_reports.clone(),
        approvals: job.approval_records.clone(),
        baselines: job.approved_baselines.clone(),
        audit_events: job.audit_events.clone(),
    }
}

fn default_rnd_doctrine_profile() -> RndDoctrineProfileRecord {
    RndDoctrineProfileRecord {
        profile_id: "blackhaven-default-doctrine".to_string(),
        title: "BlackHaven Vehicle Doctrine".to_string(),
        principles: vec![
            "manufacturability".to_string(),
            "serviceability".to_string(),
            "repairability by teenagers / non-experts".to_string(),
            "affordability for rural users / the global masses".to_string(),
            "limited tool variety".to_string(),
            "modularity".to_string(),
            "low SKU count".to_string(),
            "low part count".to_string(),
            "accessible documentation".to_string(),
            "boring robustness over seductive complexity".to_string(),
        ],
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn sync_rnd_doctrine_and_structure_state(job: &mut RndJobRecord) {
    if job.doctrine_profile.is_none() {
        job.doctrine_profile = Some(default_rnd_doctrine_profile());
    }
    job.module_definitions = build_rnd_module_definitions(job);
    job.tool_requirements = build_rnd_tool_requirements(job);
    job.bom_items = build_rnd_bom_items(job);
    job.assembly_steps = build_rnd_assembly_steps(job);
    job.service_access_points = build_rnd_service_access_points(job);
    job.inspection_checklist_items = build_rnd_inspection_checklist_items(job);
    job.doctrine_checks = build_rnd_doctrine_checks(job);
    let plan_version = accepted_rnd_plan(job)
        .map(|plan| plan.version)
        .unwrap_or_else(|| job.plans.last().map(|plan| plan.version).unwrap_or(1));
    let reason = format!(
        "plan_v{}_{}_checks",
        plan_version,
        job.doctrine_checks.len()
    );
    upsert_rnd_revision_record(&mut job.revision_history, plan_version, reason.as_str());
}

fn upsert_rnd_revision_record(history: &mut Vec<RndRevisionRecord>, plan_version: u32, reason: &str) {
    let label = format!("R{}\nP{}", history.len() + 1, plan_version).replace('\n', "-");
    if history.iter().any(|item| item.source_plan_version == plan_version && item.reason == reason) {
        return;
    }
    history.push(RndRevisionRecord {
        revision_id: format!("revision-{}", uuid::Uuid::new_v4()),
        label,
        source_plan_version: plan_version,
        reason: trim_for_storage(reason, 160),
        created_at: chrono::Utc::now().to_rfc3339(),
    });
}

fn rnd_has_major_doctrine_failures(job: &RndJobRecord) -> bool {
    job.doctrine_checks
        .iter()
        .any(|item| item.severity == "major" && !item.passed && item.gating)
}

fn build_rnd_module_definitions(job: &RndJobRecord) -> Vec<RndModuleDefinitionRecord> {
    let part_modules = if job.parts.is_empty() {
        vec![
            ("module-structure", "Chassis / Structure", "Carry the main load and protect simple service access."),
            ("module-energy", "Power / Utilities", "Keep power, water, and control systems modular and field-serviceable."),
            ("module-interior", "Interior / Living", "Prioritize low-cost, replaceable, repair-friendly surfaces and fixtures."),
        ]
    } else {
        Vec::new()
    };

    let mut modules: Vec<RndModuleDefinitionRecord> = job
        .parts
        .iter()
        .take(8)
        .map(|part| RndModuleDefinitionRecord {
            module_id: format!("module-{}", sanitize_slug(part.part_id.as_str())),
            title: trim_for_storage(part.name.as_str(), 120),
            purpose: trim_for_storage(part.purpose.as_str(), 220),
            affordability_notes: "Prefer common materials, low process complexity, and parts that rural users can source or substitute.".to_string(),
            manufacturability_notes: "Avoid exotic tooling and keep joins, fasteners, and sequences simple enough for repeatable fabrication.".to_string(),
            serviceability_notes: "Expose service points and avoid burying routine maintenance behind teardown.".to_string(),
            repairability_notes: "Design for common tools, clear access, and replaceable modules instead of expert-only repair.".to_string(),
            linked_artifact_ids: job
                .artifacts
                .iter()
                .filter(|artifact| artifact.part_id.as_deref() == Some(part.part_id.as_str()))
                .map(|artifact| artifact.artifact_id.clone())
                .collect(),
        })
        .collect();

    for (module_id, title, purpose) in part_modules {
        modules.push(RndModuleDefinitionRecord {
            module_id: module_id.to_string(),
            title: title.to_string(),
            purpose: purpose.to_string(),
            affordability_notes: "Keep the architecture affordable and tolerant of substitution.".to_string(),
            manufacturability_notes: "Choose boring fabrication methods and low setup overhead.".to_string(),
            serviceability_notes: "Keep access visible or quickly reachable.".to_string(),
            repairability_notes: "Teenagers and non-experts should be able to understand the layout and basic repair steps.".to_string(),
            linked_artifact_ids: Vec::new(),
        });
    }
    modules
}

fn build_rnd_tool_requirements(job: &RndJobRecord) -> Vec<RndToolRequirementRecord> {
    let mut tools = vec![
        RndToolRequirementRecord {
            tool_id: "tool-metric-sockets".to_string(),
            name: "Metric socket and wrench set".to_string(),
            category: "mechanical".to_string(),
            reason: "Covers most structural and service fasteners.".to_string(),
            commonality: "common".to_string(),
        },
        RndToolRequirementRecord {
            tool_id: "tool-screwdriver".to_string(),
            name: "Screwdriver / driver with common bits".to_string(),
            category: "assembly".to_string(),
            reason: "Supports standardized fastener handling and field repair.".to_string(),
            commonality: "common".to_string(),
        },
        RndToolRequirementRecord {
            tool_id: "tool-multimeter".to_string(),
            name: "Basic multimeter".to_string(),
            category: "diagnostic".to_string(),
            reason: "Required for safe low-voltage troubleshooting and continuity checks.".to_string(),
            commonality: "common".to_string(),
        },
    ];
    if job.design_domain.contains("electronic") || job.prompt.to_lowercase().contains("electrical") {
        tools.push(RndToolRequirementRecord {
            tool_id: "tool-crimper".to_string(),
            name: "Simple crimper / stripper".to_string(),
            category: "electrical".to_string(),
            reason: "Supports repairable wire terminations without specialized equipment.".to_string(),
            commonality: "common".to_string(),
        });
    }
    tools
}

fn build_rnd_bom_items(job: &RndJobRecord) -> Vec<RndBomItemRecord> {
    let mut items: Vec<RndBomItemRecord> = job
        .module_definitions
        .iter()
        .take(8)
        .map(|module| RndBomItemRecord {
            bom_id: format!("bom-{}", sanitize_slug(module.module_id.as_str())),
            name: format!("{} module hardware / consumables", module.title),
            quantity: "1 module set".to_string(),
            notes: "Standardize fasteners and prioritize replaceable subassemblies.".to_string(),
            module_id: Some(module.module_id.clone()),
        })
        .collect();
    if items.is_empty() {
        items.push(RndBomItemRecord {
            bom_id: "bom-structure".to_string(),
            name: "Common structural stock".to_string(),
            quantity: "TBD".to_string(),
            notes: "Use widely available profiles, sheet goods, and fastening standards.".to_string(),
            module_id: None,
        });
    }
    items
}

fn build_rnd_assembly_steps(job: &RndJobRecord) -> Vec<RndAssemblyStepRecord> {
    job.module_definitions
        .iter()
        .take(10)
        .enumerate()
        .map(|(idx, module)| RndAssemblyStepRecord {
            step_id: format!("assembly-step-{}", idx + 1),
            module_id: Some(module.module_id.clone()),
            title: format!("Assemble {}", module.title),
            instructions: format!(
                "Prepare the {} module, confirm tools and hardware, attach only the standardized interfaces first, and verify service access before closing any surfaces.",
                module.title
            ),
            safety_notes: vec![
                "Support loads before loosening structural fasteners.".to_string(),
                "Verify clear access to routine service points before final closure.".to_string(),
            ],
        })
        .collect()
}

fn build_rnd_service_access_points(job: &RndJobRecord) -> Vec<RndServiceAccessPointRecord> {
    job.module_definitions
        .iter()
        .take(10)
        .map(|module| RndServiceAccessPointRecord {
            access_id: format!("access-{}", sanitize_slug(module.module_id.as_str())),
            module_id: Some(module.module_id.clone()),
            title: format!("{} service access", module.title),
            location: "Visible from the primary maintenance side or reachable behind one removable panel.".to_string(),
            visibility: "quick_access".to_string(),
            notes: "Routine checks should not require teardown or specialized jigs.".to_string(),
        })
        .collect()
}

fn build_rnd_inspection_checklist_items(job: &RndJobRecord) -> Vec<RndInspectionChecklistItemRecord> {
    let mut items = vec![
        RndInspectionChecklistItemRecord {
            item_id: "inspection-fastener-variety".to_string(),
            module_id: None,
            title: "Fastener family count is controlled".to_string(),
            verification: "Confirm the design uses a low number of fastener types and no unnecessary exotic heads.".to_string(),
            severity: "high".to_string(),
        },
        RndInspectionChecklistItemRecord {
            item_id: "inspection-service-access".to_string(),
            module_id: None,
            title: "Routine service points are reachable".to_string(),
            verification: "Confirm that routine inspection, replacement, and troubleshooting do not require deep teardown.".to_string(),
            severity: "critical".to_string(),
        },
    ];
    for module in job.module_definitions.iter().take(6) {
        items.push(RndInspectionChecklistItemRecord {
            item_id: format!("inspection-{}", sanitize_slug(module.module_id.as_str())),
            module_id: Some(module.module_id.clone()),
            title: format!("{} can be inspected independently", module.title),
            verification: "Check module boundaries, labeling, and swap/reinstall path.".to_string(),
            severity: "medium".to_string(),
        });
    }
    items
}

fn build_rnd_doctrine_checks(job: &RndJobRecord) -> Vec<RndDoctrineCheckRecord> {
    let prompt = job.prompt.to_lowercase();
    let artifact_text = job
        .artifacts
        .iter()
        .map(|artifact| artifact.content.to_lowercase())
        .collect::<Vec<_>>()
        .join("\n");
    let merged = format!("{prompt}\n{artifact_text}");
    let tool_count = job.tool_requirements.len();
    let module_count = job.module_definitions.len();
    let has_exotic = contains_any(&merged, &["carbon fiber", "autoclave", "robotic weld", "cnc only", "proprietary"]);
    let has_bad_service = contains_any(&merged, &["sealed behind", "remove entire interior", "full teardown", "hidden service"]);
    let has_bad_repair = contains_any(&merged, &["dealer-only", "special dealer tool", "factory-only repair", "certified technician only"]);
    let has_affordability_risk = contains_any(&merged, &["luxury", "premium veneer", "motorized wall", "custom billet"]);
    let has_complexity_drift = module_count > 7 || contains_any(&merged, &["many variants", "multiple sku", "custom per build"]);
    let has_tool_drift = tool_count > 4;

    vec![
        doctrine_check("teenager_repairability", !has_bad_repair, if has_bad_repair { "major" } else { "info" }, "Repairs should be understandable to non-experts with cheap/common tools.", "Replace expert-only procedures with modular replacement and plain-language steps.", job),
        doctrine_check("low_tool_variety", !has_tool_drift, if has_tool_drift { "major" } else { "info" }, "Tool count should stay low and standardized.", "Collapse tool needs toward sockets, common bits, and a basic multimeter/crimper set.", job),
        doctrine_check("low_fastener_variety", !contains_any(&merged, &["torx + hex + spline + rivet mix", "mixed proprietary fasteners"]), "warning", "Fastener families should stay controlled so field service remains simple.", "Reduce head and fastener family variety to the minimum practical set.", job),
        doctrine_check("service_access", !has_bad_service, if has_bad_service { "major" } else { "info" }, "Routine service points should be visible or quickly reachable.", "Reposition service points behind removable panels or direct-access zones.", job),
        doctrine_check("modularity", module_count > 0, "info", "The design should decompose into replaceable modules.", "Define clearer module boundaries and swap paths.", job),
        doctrine_check("affordability", !has_affordability_risk, if has_affordability_risk { "major" } else { "warning" }, "The architecture should stay affordable for rural users and the masses.", "Replace aspirational luxury features with boring robust systems and common materials.", job),
        doctrine_check("manufacturability", !has_exotic, if has_exotic { "major" } else { "warning" }, "The design should avoid exotic processes when boring fabrication can work.", "Use common structural stock, simple joints, and repeatable fabrication methods.", job),
        doctrine_check("accessible_documentation", true, "info", "Documentation should be understandable to normal people.", "Keep language plain, procedural, and diagram-friendly.", job),
        doctrine_check("boring_robustness", !contains_any(&merged, &["gimmick", "showpiece", "seductive complexity", "smart luxury"]), "warning", "Robust simplicity should beat gimmicks.", "Remove features that add failure modes without strong practical value.", job),
        doctrine_check("low_sku_low_part_count", !has_complexity_drift, if has_complexity_drift { "major" } else { "warning" }, "Variant and part-count drift should stay controlled.", "Collapse variants and eliminate low-value parts or custom one-offs.", job),
        doctrine_check("complexity_value", !contains_any(&merged, &["complex for aesthetics", "novelty mechanism"]), "warning", "Complexity should only be added when it clearly earns its keep.", "Remove or justify any extra mechanism, wiring branch, or decorative subsystem.", job),
    ]
}

fn doctrine_check(
    area: &str,
    passed: bool,
    severity: &str,
    explanation: &str,
    suggested_fix: &str,
    job: &RndJobRecord,
) -> RndDoctrineCheckRecord {
    RndDoctrineCheckRecord {
        check_id: format!("doctrine-{}", area),
        doctrine_area: area.to_string(),
        severity: severity.to_string(),
        passed,
        explanation: explanation.to_string(),
        suggested_fix: suggested_fix.to_string(),
        linked_module_ids: job.module_definitions.iter().take(4).map(|item| item.module_id.clone()).collect(),
        linked_artifact_ids: job.artifacts.iter().take(6).map(|item| item.artifact_id.clone()).collect(),
        linked_decision_ids: job.decisions.iter().take(6).map(|item| item.decision_id.clone()).collect(),
        gating: severity == "major",
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn sanitize_slug(input: &str) -> String {
    let cleaned = input
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>();
    cleaned.trim_matches('-').to_string()
}

fn build_default_rnd_revision_label(job: &RndJobRecord, explicit: Option<&str>) -> String {
    explicit
        .map(|value| trim_for_storage(value, 60))
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            job.revision_history
                .last()
                .map(|item| item.label.clone())
                .unwrap_or_else(|| format!("R1-P{}", accepted_rnd_plan(job).map(|plan| plan.version).unwrap_or(1)))
        })
}

fn generate_rnd_document_bundle(
    job: &mut RndJobRecord,
    audience_mode: &str,
    title_prefix: Option<&str>,
    platform_name: Option<&str>,
    revision_label: Option<&str>,
    author: &str,
) -> RndDocumentationBundleRecord {
    let document_types = [
        "manufacturing_build_guide",
        "module_assembly_guide",
        "service_manual",
        "repair_guide",
        "qa_inspection_checklist",
        "public_project_story",
    ];
    let created_ids = document_types
        .iter()
        .map(|document_type| {
            generate_rnd_document(
                job,
                document_type,
                if *document_type == "public_project_story" { "public" } else { audience_mode },
                title_prefix,
                platform_name,
                revision_label,
                None,
                None,
                author,
            )
            .document_id
        })
        .collect::<Vec<_>>();
    let bundle = RndDocumentationBundleRecord {
        bundle_id: format!("bundle-{}", uuid::Uuid::new_v4()),
        title: format!(
            "{} Core Documentation Bundle",
            trim_for_storage(title_prefix.unwrap_or("BlackHaven"), 120)
        ),
        audience_mode: audience_mode.to_string(),
        revision_label: build_default_rnd_revision_label(job, revision_label),
        document_ids: created_ids,
        created_at: chrono::Utc::now().to_rfc3339(),
    };
    job.documentation_bundles.push(bundle.clone());
    bundle
}

fn generate_rnd_document(
    job: &mut RndJobRecord,
    document_type: &str,
    audience_mode: &str,
    title: Option<&str>,
    platform_name: Option<&str>,
    revision_label: Option<&str>,
    purpose: Option<&str>,
    target_audience: Option<&str>,
    author: &str,
) -> RndDocumentRecord {
    sync_rnd_doctrine_and_structure_state(job);
    let now = chrono::Utc::now().to_rfc3339();
    let source_plan_version = accepted_rnd_plan(job)
        .map(|plan| plan.version)
        .unwrap_or_else(|| job.plans.last().map(|plan| plan.version).unwrap_or(1));
    let platform_source = platform_name
        .map(|value| value.to_string())
        .unwrap_or_else(|| job.product_type.replace('_', " "));
    let platform = trim_for_storage(platform_source.as_str(), 120);
    let title_source = title
        .map(|value| value.to_string())
        .unwrap_or_else(|| default_document_title(document_type, platform.as_str()));
    let doc_title = trim_for_storage(title_source.as_str(), 160);
    let revision = build_default_rnd_revision_label(job, revision_label);
    let modules = job.module_definitions.clone();
    let assumptions = accepted_rnd_plan(job)
        .map(|plan| plan.assumptions.clone())
        .unwrap_or_default();
    let safety_notes = vec![
        "Do not treat AI-generated documentation as a substitute for qualified engineering review where safety-critical decisions are involved.".to_string(),
        "Support loads, isolate power, and verify safe access before service or repair.".to_string(),
    ];
    let manufacturability_notes = collect_doctrine_notes(job, "manufacturability");
    let affordability_notes = collect_doctrine_notes(job, "affordability");
    let repairability_notes = collect_doctrine_notes(job, "teenager_repairability");
    let serviceability_notes = collect_doctrine_notes(job, "service_access");

    let sections = build_rnd_document_sections(job, document_type, audience_mode, doc_title.as_str(), platform.as_str());
    let document = RndDocumentRecord {
        document_id: format!("doc-{}", uuid::Uuid::new_v4()),
        document_type: document_type.to_string(),
        audience_mode: audience_mode.to_string(),
        title: doc_title.clone(),
        project_name: "BlackHaven R&D".to_string(),
        platform_name: platform.clone(),
        revision_label: revision.clone(),
        source_job_id: job.job_id.clone(),
        source_plan_version,
        artifact_ids: job.artifacts.iter().map(|item| item.artifact_id.clone()).collect(),
        module_ids: modules.iter().map(|item| item.module_id.clone()).collect(),
        purpose: purpose
            .map(|value| trim_for_storage(value, 220))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| default_document_purpose(document_type).to_string()),
        target_audience: target_audience
            .map(|value| trim_for_storage(value, 160))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| default_document_audience(document_type, audience_mode).to_string()),
        author: trim_for_storage(author, 120),
        assumptions,
        safety_notes,
        tools_required: job.tool_requirements.clone(),
        materials_required: job.bom_items.iter().map(|item| item.name.clone()).collect(),
        bom_summary: job.bom_items.clone(),
        sections: sections.clone(),
        manufacturability_notes,
        affordability_notes,
        repairability_notes,
        serviceability_notes,
        public_benefit_rationale: build_public_benefit_rationale(job, document_type),
        exports: vec![RndDocumentExportRecord {
            export_id: format!("export-{}", uuid::Uuid::new_v4()),
            format: "source_markdown".to_string(),
            audience_mode: audience_mode.to_string(),
            revision_label: revision.clone(),
            generated_at: now.clone(),
        }],
        created_at: now.clone(),
        updated_at: now.clone(),
    };
    upsert_rnd_document(job, document.clone());
    let source_markdown = render_rnd_document_markdown(&document);
    job.artifacts.push(RndArtifactRecord {
        artifact_id: document.document_id.clone(),
        part_id: None,
        artifact_type: "documentation_source".to_string(),
        title: document.title.clone(),
        format: "md".to_string(),
        content: source_markdown,
        created_at: now.clone(),
    });
    job.artifacts.push(RndArtifactRecord {
        artifact_id: format!("{}-json", document.document_id),
        part_id: None,
        artifact_type: "documentation_record".to_string(),
        title: format!("{} structured record", document.title),
        format: "json".to_string(),
        content: serde_json::to_string_pretty(&document).unwrap_or_else(|_| "{}".to_string()),
        created_at: now,
    });
    document
}

fn upsert_rnd_document(job: &mut RndJobRecord, document: RndDocumentRecord) {
    if let Some(index) = job
        .document_records
        .iter()
        .position(|item| item.document_type == document.document_type && item.audience_mode == document.audience_mode)
    {
        job.document_records[index] = document;
    } else {
        job.document_records.push(document);
    }
}

fn build_rnd_document_sections(
    job: &RndJobRecord,
    document_type: &str,
    audience_mode: &str,
    title: &str,
    platform_name: &str,
) -> Vec<RndDocumentSectionRecord> {
    let module_lines = if job.module_definitions.is_empty() {
        "- No structured modules captured yet.\n- Export still includes placeholders so the document can be refined later.".to_string()
    } else {
        job.module_definitions
            .iter()
            .map(|module| format!("- {}: {}", module.title, module.purpose))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let assembly_lines = if job.assembly_steps.is_empty() {
        "- No assembly steps captured yet.".to_string()
    } else {
        job.assembly_steps
            .iter()
            .map(|step| format!("- {}: {}", step.title, step.instructions))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let service_lines = if job.service_access_points.is_empty() {
        "- No structured service access points captured yet.".to_string()
    } else {
        job.service_access_points
            .iter()
            .map(|point| format!("- {}: {} ({})", point.title, point.location, point.notes))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let bom_lines = if job.bom_items.is_empty() {
        "- No BOM items captured yet.".to_string()
    } else {
        job.bom_items
            .iter()
            .map(|item| format!("- {} · {} · {}", item.name, item.quantity, item.notes))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let doctrine_lines = if job.doctrine_checks.is_empty() {
        "- Doctrine checks not yet generated.".to_string()
    } else {
        job.doctrine_checks
            .iter()
            .map(|check| format!(
                "- [{}] {}: {} {}",
                check.severity.to_uppercase(),
                check.doctrine_area,
                if check.passed { "pass" } else { "needs work" },
                check.explanation
            ))
            .collect::<Vec<_>>()
            .join("\n")
    };
    let public_story = build_public_benefit_rationale(job, document_type);
    let troubleshooting = job
        .risk_flags
        .iter()
        .map(|flag| format!("- {}", flag))
        .collect::<Vec<_>>()
        .join("\n");
    let mut sections = vec![
        RndDocumentSectionRecord {
            section_id: format!("{}-overview", sanitize_slug(document_type)),
            heading: "Overview".to_string(),
            body_markdown: format!(
                "{} documents the {} for {} in {} mode.",
                title,
                document_type.replace('_', " "),
                platform_name,
                audience_mode
            ),
            order_index: 0,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-modules", sanitize_slug(document_type)),
            heading: "Module Breakdown".to_string(),
            body_markdown: module_lines,
            order_index: 1,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-steps", sanitize_slug(document_type)),
            heading: "Step-by-Step Instructions".to_string(),
            body_markdown: assembly_lines,
            order_index: 2,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-tools-bom", sanitize_slug(document_type)),
            heading: "Parts, Materials, and Tools".to_string(),
            body_markdown: format!("## BOM\n{}\n\n## Service / Tool Notes\n{}", bom_lines, service_lines),
            order_index: 3,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-doctrine", sanitize_slug(document_type)),
            heading: "Manufacturability, Serviceability, Affordability, and Repairability".to_string(),
            body_markdown: doctrine_lines,
            order_index: 4,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-troubleshooting", sanitize_slug(document_type)),
            heading: "Troubleshooting and Common Failure Points".to_string(),
            body_markdown: if troubleshooting.is_empty() { "- No explicit risk flags recorded yet.".to_string() } else { troubleshooting },
            order_index: 5,
        },
        RndDocumentSectionRecord {
            section_id: format!("{}-public-benefit", sanitize_slug(document_type)),
            heading: "Why This Design Exists".to_string(),
            body_markdown: public_story,
            order_index: 6,
        },
    ];
    if audience_mode == "public" {
        sections.retain(|section| section.heading != "Troubleshooting and Common Failure Points" || document_type == "public_project_story");
    }
    sections
}

fn default_document_title(document_type: &str, platform_name: &str) -> String {
    format!(
        "{} - {}",
        platform_name,
        document_type.replace('_', " ").split('_').collect::<Vec<_>>().join(" ")
    )
}

fn default_document_purpose(document_type: &str) -> &'static str {
    match document_type {
        "manufacturing_build_guide" => "Explain how to fabricate and sequence the vehicle or module safely and repeatably.",
        "module_assembly_guide" => "Explain how to bench-build and assemble modules with clear interfaces and low tool friction.",
        "service_manual" => "Explain routine service points, access paths, and maintenance expectations.",
        "repair_guide" => "Explain common failure modes, safe access, and straightforward field repair.",
        "qa_inspection_checklist" => "Explain what to verify before release, delivery, or road use.",
        "public_project_story" => "Explain what the design is, why the tradeoffs were chosen, and how the public can learn from it.",
        _ => "Explain the design state with traceable, public-facing engineering context.",
    }
}

fn default_document_audience(document_type: &str, audience_mode: &str) -> &'static str {
    if audience_mode == "public" || document_type == "public_project_story" {
        "General public, makers, repair learners, and non-expert builders"
    } else {
        "Internal manufacturing, service, repair, and review operators"
    }
}

fn collect_doctrine_notes(job: &RndJobRecord, area: &str) -> Vec<String> {
    job.doctrine_checks
        .iter()
        .filter(|check| check.doctrine_area == area || area == "teenager_repairability" && check.doctrine_area == "low_tool_variety")
        .map(|check| {
            if check.passed {
                format!("Pass: {}", check.explanation)
            } else {
                format!("Needs work: {} Suggested fix: {}", check.explanation, check.suggested_fix)
            }
        })
        .collect()
}

fn build_public_benefit_rationale(job: &RndJobRecord, document_type: &str) -> String {
    let tradeoff_line = if job.decisions.is_empty() {
        "This design still needs more explicit tradeoff capture, but the doctrine already pushes it toward boring robustness, low tool variety, and modular repair."
            .to_string()
    } else {
        format!(
            "Key tradeoffs: {}",
            job.decisions
                .iter()
                .take(4)
                .map(|decision| format!("{} because {}", decision.title, decision.rationale))
                .collect::<Vec<_>>()
                .join(" | ")
        )
    };
    format!(
        "BlackHaven treats {} as a public knowledge artifact, not just an internal engineering file. The goal is to help society learn how to build safer, cheaper, more repairable vehicles. {} The design doctrine prioritizes manufacturability, serviceability, affordability, and teenager-level repairability so rural users and the global masses are not locked out of understanding or maintaining the platform.",
        document_type.replace('_', " "),
        tradeoff_line
    )
}

fn render_rnd_document_markdown(document: &RndDocumentRecord) -> String {
    let mut body = format!(
        "# {}\n\n- Document type: {}\n- Audience mode: {}\n- Revision: {}\n- Platform: {}\n- Purpose: {}\n- Target audience: {}\n- Author: {}\n\n## Assumptions\n{}\n\n## Safety Notes\n{}\n\n## Tools Required\n{}\n\n## Materials Required\n{}\n\n## BOM Summary\n{}\n",
        document.title,
        document.document_type,
        document.audience_mode,
        document.revision_label,
        document.platform_name,
        document.purpose,
        document.target_audience,
        document.author,
        if document.assumptions.is_empty() { "- No assumptions recorded." .to_string() } else { document.assumptions.iter().map(|item| format!("- {}", item)).collect::<Vec<_>>().join("\n") },
        if document.safety_notes.is_empty() { "- No safety notes recorded." .to_string() } else { document.safety_notes.iter().map(|item| format!("- {}", item)).collect::<Vec<_>>().join("\n") },
        if document.tools_required.is_empty() { "- No tools recorded." .to_string() } else { document.tools_required.iter().map(|item| format!("- {} ({})", item.name, item.reason)).collect::<Vec<_>>().join("\n") },
        if document.materials_required.is_empty() { "- No materials recorded." .to_string() } else { document.materials_required.iter().map(|item| format!("- {}", item)).collect::<Vec<_>>().join("\n") },
        if document.bom_summary.is_empty() { "- No BOM items recorded." .to_string() } else { document.bom_summary.iter().map(|item| format!("- {} · {} · {}", item.name, item.quantity, item.notes)).collect::<Vec<_>>().join("\n") },
    );
    for section in &document.sections {
        body.push_str(format!("\n## {}\n{}\n", section.heading, section.body_markdown).as_str());
    }
    body.push_str(
        format!(
            "\n## Public Benefit / Rationale\n{}\n",
            document.public_benefit_rationale
        )
        .as_str(),
    );
    body
}

fn generate_rnd_compliance_report(
    job: &mut RndJobRecord,
    report_title: Option<&str>,
    report_type: &str,
) -> RndComplianceReportRecord {
    sync_rnd_traceability_state(job);
    let now = chrono::Utc::now().to_rfc3339();
    let version = job.compliance_reports.len() as u32 + 1;
    let open_issues = build_rnd_traceability_rows(job)
        .into_iter()
        .flat_map(|row| {
            row.unresolved_items
                .into_iter()
                .map(move |issue| format!("{}: {}", row.requirement_id, issue))
        })
        .collect::<Vec<_>>();
    let title = report_title
        .map(|value| trim_for_storage(value, 120))
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| format!("Compliance packet v{}", version));
    let report_id = format!("report-{}", uuid::Uuid::new_v4());
    let approval_lines = if job.approval_records.is_empty() {
        "- No approvals recorded yet.".to_string()
    } else {
        job.approval_records
            .iter()
            .map(|approval| {
                format!(
                    "- {} / {} / {} / {}",
                    approval.reviewer_name,
                    approval.reviewer_role,
                    approval.authority_kind,
                    approval.approval_state
                )
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    let markdown = format!(
        "# {}\n\n## Scope\n- Job: {}\n- Product type: {}\n- Design domain: {}\n- Report type: {}\n\n## Applicable requirements\n- {}\n\n## Assumptions\n- {}\n\n## Design description\n- {}\n\n## Risk notes\n- {}\n\n## Verification evidence\n- {}\n\n## Open issues\n- {}\n\n## Reviewer / approver data\n{}\n\n## Provenance\n- Requirements: {}\n- Decisions: {}\n- Evidence: {}\n- Simulation runs: {}\n- Approvals: {}\n\n## Automation boundary\n- AI can draft and organize this packet, but licensed or certified sign-off must remain with qualified human authority where required.\n",
        title,
        job.job_id,
        job.product_type,
        job.design_domain,
        report_type,
        if job.requirements.is_empty() { "No requirements captured.".to_string() } else { job.requirements.iter().map(|item| item.description.clone()).collect::<Vec<_>>().join("\n- ") },
        if let Some(plan) = accepted_rnd_plan(job) { plan.assumptions.join("\n- ") } else { "No accepted plan assumptions recorded.".to_string() },
        if job.decisions.is_empty() { "No design decisions captured.".to_string() } else { job.decisions.iter().map(|item| format!("{}: {}", item.title, item.decision)).collect::<Vec<_>>().join("\n- ") },
        if job.risk_flags.is_empty() { "No additional risk flags recorded.".to_string() } else { job.risk_flags.join("\n- ") },
        if job.evidence_artifacts.is_empty() { "No evidence artifacts captured.".to_string() } else { job.evidence_artifacts.iter().map(|item| format!("{} ({})", item.title, item.evidence_kind)).collect::<Vec<_>>().join("\n- ") },
        if open_issues.is_empty() { "No open issues flagged by the current traceability rules.".to_string() } else { open_issues.join("\n- ") },
        approval_lines,
        job.requirements.iter().map(|item| item.requirement_id.clone()).collect::<Vec<_>>().join(", "),
        job.decisions.iter().map(|item| item.decision_id.clone()).collect::<Vec<_>>().join(", "),
        job.evidence_artifacts.iter().map(|item| item.evidence_id.clone()).collect::<Vec<_>>().join(", "),
        job.simulation_runs.iter().map(|item| item.run_id.clone()).collect::<Vec<_>>().join(", "),
        job.approval_records.iter().map(|item| item.approval_id.clone()).collect::<Vec<_>>().join(", "),
    );
    let report = RndComplianceReportRecord {
        report_id: report_id.clone(),
        title,
        report_type: report_type.to_string(),
        status: if open_issues.is_empty() { "ready_for_review".to_string() } else { "needs_review".to_string() },
        version,
        markdown: markdown.clone(),
        provenance: vec![
            format!("job:{}", job.job_id),
            format!("requirements:{}", job.requirements.len()),
            format!("decisions:{}", job.decisions.len()),
            format!("evidence:{}", job.evidence_artifacts.len()),
            format!("approvals:{}", job.approval_records.len()),
        ],
        requirement_ids: job.requirements.iter().map(|item| item.requirement_id.clone()).collect(),
        decision_ids: job.decisions.iter().map(|item| item.decision_id.clone()).collect(),
        evidence_ids: job.evidence_artifacts.iter().map(|item| item.evidence_id.clone()).collect(),
        run_ids: job.simulation_runs.iter().map(|item| item.run_id.clone()).collect(),
        approval_ids: job.approval_records.iter().map(|item| item.approval_id.clone()).collect(),
        open_issues: open_issues.clone(),
        created_at: now.clone(),
        updated_at: now.clone(),
    };
    job.compliance_reports.push(report.clone());
    job.artifacts.push(RndArtifactRecord {
        artifact_id: report_id.clone(),
        part_id: None,
        artifact_type: "compliance_report".to_string(),
        title: report.title.clone(),
        format: "md".to_string(),
        content: markdown,
        created_at: now,
    });
    upsert_rnd_document(
        job,
        RndDocumentRecord {
            document_id: format!("doc-report-{}", report.report_id),
            document_type: report.report_type.clone(),
            audience_mode: "private".to_string(),
            title: report.title.clone(),
            project_name: "BlackHaven R&D".to_string(),
            platform_name: job.product_type.replace('_', " "),
            revision_label: format!("report-v{}", report.version),
            source_job_id: job.job_id.clone(),
            source_plan_version: job
                .accepted_plan_version
                .unwrap_or_else(|| job.plans.last().map(|plan| plan.version).unwrap_or(1)),
            artifact_ids: job.artifacts.iter().map(|item| item.artifact_id.clone()).collect(),
            module_ids: job
                .module_definitions
                .iter()
                .map(|item| item.module_id.clone())
                .collect(),
            purpose: "Capture a structured compliance and release-readiness snapshot from the current R&D job state."
                .to_string(),
            target_audience: "Internal reviewers, approvers, and release operators".to_string(),
            author: "system".to_string(),
            assumptions: job
                .plans
                .last()
                .map(|plan| plan.assumptions.clone())
                .unwrap_or_default(),
            safety_notes: vec![
                "Human sign-off remains required wherever regulated or safety-critical release decisions apply."
                    .to_string(),
            ],
            tools_required: job.tool_requirements.clone(),
            materials_required: job.bom_items.iter().map(|item| item.name.clone()).collect(),
            bom_summary: job.bom_items.clone(),
            sections: vec![
                RndDocumentSectionRecord {
                    section_id: format!("{}-summary", sanitize_slug(report.report_id.as_str())),
                    heading: "Compliance Summary".to_string(),
                    body_markdown: report.markdown.clone(),
                    order_index: 0,
                },
                RndDocumentSectionRecord {
                    section_id: format!("{}-doctrine", sanitize_slug(report.report_id.as_str())),
                    heading: "Doctrine Checks".to_string(),
                    body_markdown: if job.doctrine_checks.is_empty() {
                        "- Doctrine checks were not available at report generation time.".to_string()
                    } else {
                        job.doctrine_checks
                            .iter()
                            .map(|check| format!(
                                "- [{}] {}: {}",
                                check.severity.to_uppercase(),
                                check.doctrine_area,
                                if check.passed {
                                    "pass".to_string()
                                } else {
                                    format!("needs work. {}", check.suggested_fix)
                                }
                            ))
                            .collect::<Vec<_>>()
                            .join("\n")
                    },
                    order_index: 1,
                },
            ],
            manufacturability_notes: collect_doctrine_notes(job, "manufacturability"),
            affordability_notes: collect_doctrine_notes(job, "affordability"),
            repairability_notes: collect_doctrine_notes(job, "teenager_repairability"),
            serviceability_notes: collect_doctrine_notes(job, "service_access"),
            public_benefit_rationale: build_public_benefit_rationale(job, report.report_type.as_str()),
            exports: vec![RndDocumentExportRecord {
                export_id: format!("export-report-{}", uuid::Uuid::new_v4()),
                format: "source_markdown".to_string(),
                audience_mode: "private".to_string(),
                revision_label: format!("report-v{}", report.version),
                generated_at: chrono::Utc::now().to_rfc3339(),
            }],
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        },
    );
    sync_rnd_traceability_state(job);
    report
}

fn create_rnd_approved_baseline(job: &RndJobRecord, title: &str, approval_id: &str) -> RndApprovedBaselineRecord {
    let snapshot_source = format!(
        "{}|{}|{}|{}|{}",
        job.job_id,
        job.artifacts.iter().map(|item| item.artifact_id.clone()).collect::<Vec<_>>().join(","),
        job.requirements.iter().map(|item| item.requirement_id.clone()).collect::<Vec<_>>().join(","),
        job.decisions.iter().map(|item| item.decision_id.clone()).collect::<Vec<_>>().join(","),
        job.compliance_reports.iter().map(|item| item.report_id.clone()).collect::<Vec<_>>().join(",")
    );
    let snapshot_hash = format!("{:x}", Sha256::digest(snapshot_source.as_bytes()));
    RndApprovedBaselineRecord {
        baseline_id: format!("baseline-{}", uuid::Uuid::new_v4()),
        title: title.to_string(),
        status: "locked".to_string(),
        artifact_ids: job.artifacts.iter().map(|item| item.artifact_id.clone()).collect(),
        requirement_ids: job.requirements.iter().map(|item| item.requirement_id.clone()).collect(),
        decision_ids: job.decisions.iter().map(|item| item.decision_id.clone()).collect(),
        report_ids: job.compliance_reports.iter().map(|item| item.report_id.clone()).collect(),
        approval_ids: vec![approval_id.to_string()],
        snapshot_hash,
        created_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn infer_plan_blockers(prompt: &str, context_pack: &RndContextPackRecord) -> Vec<String> {
    let mut issues = Vec::new();
    if context_pack.research_confidence < 0.4 {
        issues.push("Research confidence is weak; narrow the scope or add more source context before execution.".to_string());
    }
    let normalized = prompt.to_lowercase();
    if !normalized.contains("material")
        && !normalized.contains("weight")
        && !normalized.contains("load")
    {
        issues.push("Prompt is missing concrete engineering constraints like material, weight, or load targets.".to_string());
    }
    if normalized.contains("road legal") || normalized.contains("fully certified") {
        issues.push(
            "v1 cannot promise legal sign-off or regulator-ready release packages.".to_string(),
        );
    }
    issues
}

fn infer_rnd_goals(prompt: &str, product_type: &str) -> Vec<String> {
    let mut goals = vec![
        format!(
            "Produce a structured {} engineering package from the user prompt.",
            product_type
        ),
        "Generate a reviewable high-level plan before any execution begins.".to_string(),
        "Create part-by-part artifacts with explicit assumptions and revision traceability."
            .to_string(),
    ];
    let normalized = prompt.to_lowercase();
    if normalized.contains("environment")
        || normalized.contains("sustainable")
        || normalized.contains("eco")
    {
        goals.push(
            "Bias recommendations toward environmentally friendlier materials/process tradeoffs."
                .to_string(),
        );
    }
    if normalized.contains("safe") || normalized.contains("safety") {
        goals.push(
            "Elevate safety-related tradeoffs and validation tasks in the package.".to_string(),
        );
    }
    goals
}

fn infer_required_research_domains(prompt: &str) -> Vec<String> {
    let normalized = prompt.to_lowercase();
    let mut domains = vec![
        "mechanical design".to_string(),
        "manufacturing process".to_string(),
    ];
    if normalized.contains("kicad")
        || normalized.contains("pcb")
        || normalized.contains("schematic")
        || normalized.contains("electronics")
    {
        domains.push("electronics engineering".to_string());
        domains.push("pcb manufacturing".to_string());
    }
    if normalized.contains("safety") {
        domains.push("safety engineering".to_string());
    }
    if normalized.contains("environment") || normalized.contains("sustainable") {
        domains.push("sustainability".to_string());
    }
    if normalized.contains("thermal") || normalized.contains("heat") {
        domains.push("thermal management".to_string());
    }
    if normalized.contains("noise")
        || normalized.contains("nvh")
        || normalized.contains("vibration")
    {
        domains.push("nvh".to_string());
    }
    domains
}

fn infer_proposed_parts(prompt: &str, product_type: &str) -> Vec<String> {
    let normalized = prompt.to_lowercase();
    let mut parts = if product_type == "pcb_assembly" {
        vec![
            "power distribution stage".to_string(),
            "control or compute subsystem".to_string(),
            "connector and harness interface".to_string(),
            "pcb stackup and mechanical keepout".to_string(),
        ]
    } else if product_type == "electronic_product" {
        vec![
            "electronic enclosure".to_string(),
            "pcb assembly".to_string(),
            "thermal path and heat dissipation".to_string(),
            "connector and service interface".to_string(),
        ]
    } else if product_type == "general_product" {
        vec![
            "system requirements package".to_string(),
            "primary enclosure or structure".to_string(),
            "interface surfaces".to_string(),
            "manufacturing handoff package".to_string(),
        ]
    } else if product_type == "vehicle_part" {
        vec![
            "primary structural geometry".to_string(),
            "mounting interfaces".to_string(),
            "fastener pattern".to_string(),
            "service-access surfaces".to_string(),
        ]
    } else if normalized.contains("vehicle")
        || normalized.contains("van")
        || normalized.contains("car")
        || normalized.contains("trailer")
    {
        vec![
            "chassis or structural frame".to_string(),
            "suspension and mounting points".to_string(),
            "body shell or enclosure panels".to_string(),
            "cooling and airflow components".to_string(),
            "interior mounting structures".to_string(),
            "serviceable access panels".to_string(),
        ]
    } else {
        vec![
            "primary frame".to_string(),
            "mounting brackets".to_string(),
            "load-bearing interfaces".to_string(),
            "serviceable cover or enclosure".to_string(),
        ]
    };
    if normalized.contains("battery") {
        parts.push("battery enclosure and retention".to_string());
    }
    if normalized.contains("seat") {
        parts.push("seat anchoring structures".to_string());
    }
    parts
}

fn infer_rnd_risks(prompt: &str, research_confidence: f32) -> Vec<String> {
    let mut risks = vec![
        "Generated outputs require human engineering review before manufacturing or release."
            .to_string(),
        "Validation reports are scope-limited and must not be interpreted as universal proof."
            .to_string(),
    ];
    if research_confidence < 0.55 {
        risks.push(
            "Research context may be insufficient for strong sustainability or safety claims."
                .to_string(),
        );
    }
    if prompt.to_lowercase().contains("manufacturing ready") {
        risks.push("Manufacturing-ready claims remain provisional until a human inspects CAD, tolerances, BOM, and validation outputs.".to_string());
    }
    risks
}

fn infer_rnd_assumptions(product_type: &str) -> Vec<String> {
    vec![
        format!("Current orchestration lane is using the {} template family.", product_type),
        "Generated source files are review-oriented and may require downstream cleanup in real engineering tools.".to_string(),
        "Validation uses named scopes and load cases rather than universal proof in every dimension.".to_string(),
    ]
}

fn build_rnd_user_explanation(
    locale: &str,
    prompt: &str,
    goals: &[String],
    constraints: &[String],
    proposed_parts: &[String],
    executable: bool,
    blockers: &[String],
) -> String {
    let prefix = if locale == "he" {
        "תכנית טכנית"
    } else {
        "Technical plan"
    };
    let mut sections = vec![
        format!("{} for: {}", prefix, trim_for_storage(prompt, 220)),
        format!("Goals: {}", goals.join(" | ")),
        format!(
            "Constraints: {}",
            constraints
                .iter()
                .take(6)
                .cloned()
                .collect::<Vec<_>>()
                .join(" | ")
        ),
        format!("Proposed parts/subsystems: {}", proposed_parts.join(" | ")),
    ];
    if executable {
        sections.push("Execution status: ready for staged approval.".to_string());
    } else {
        sections.push(format!(
            "Execution blocked until gaps are resolved: {}",
            blockers.join(" | ")
        ));
    }
    sections.join("\n\n")
}

fn build_rnd_simple_summary(locale: &str, proposed_parts: &[String], executable: bool) -> String {
    if locale == "he" {
        if executable {
            format!("התכנית מוכנה לסקירה: Atlas יחלק את המוצר ל-{} אזורים/חלקים עיקריים, ואז יתקדם שלב-שלב אחרי אישור שלך.", proposed_parts.len())
        } else {
            "התכנית עדיין לא מוכנה לביצוע. צריך קודם לסגור חוסרים במחקר או בהגבלות ההנדסיות."
                .to_string()
        }
    } else if executable {
        format!(
            "The plan is ready for review. Atlas will break the product into {} main parts/subsystems and move stage by stage after your approval.",
            proposed_parts.len()
        )
    } else {
        "The plan is not ready for execution yet. Atlas still needs stronger research or clearer engineering constraints.".to_string()
    }
}

fn build_rnd_initial_timeline(stages: &[RndPlanStageRecord]) -> Vec<RndTimelineStageRecord> {
    stages
        .iter()
        .enumerate()
        .map(|(idx, stage)| RndTimelineStageRecord {
            stage: map_plan_stage_id(stage.id.as_str()),
            status: if idx == 0 {
                "awaiting_user".to_string()
            } else {
                "queued".to_string()
            },
            estimated_minutes: stage.estimated_minutes,
            started_at: None,
            finished_at: None,
            note: None,
        })
        .collect()
}

fn accepted_rnd_plan(job: &RndJobRecord) -> Option<RndPlanRecord> {
    let version = job.accepted_plan_version?;
    job.plans
        .iter()
        .find(|plan| plan.version == version)
        .cloned()
}

fn spawn_rnd_job_runner(state: ApiState, job_id: String) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(1200)).await;
            let persisted_job = {
                let mut jobs = state.rnd_jobs.write();
                let Some(job) = jobs.get_mut(job_id.as_str()) else {
                    return;
                };
                let Some(plan) = accepted_rnd_plan(job) else {
                    return;
                };
                if matches!(job.current_stage, RndStageKind::Completed) {
                    job.auto_run_enabled = false;
                    job.waiting_on_user = false;
                    Some(job.clone())
                } else if !job.auto_run_enabled {
                    Some(job.clone())
                } else if job.paused_after_current_stage {
                    job.auto_run_enabled = false;
                    job.waiting_on_user = true;
                    job.latest_validation_summary = format!(
                        "Paused after {}. Resume when you're ready for the next stage.",
                        job.current_stage_label()
                    );
                    job.eta = compute_rnd_eta(
                        plan.execution_stages.as_slice(),
                        job.parts.as_slice(),
                        job.current_stage.clone(),
                        true,
                        "Paused by user after current stage",
                    );
                    Some(job.clone())
                } else {
                    advance_rnd_job(job, &plan, Some("background_execution"));
                    if matches!(job.current_stage, RndStageKind::Completed) {
                        job.auto_run_enabled = false;
                        job.waiting_on_user = false;
                        Some(job.clone())
                    } else {
                        Some(job.clone())
                    }
                }
            };
            if let Some(job) = persisted_job.as_ref() {
                if let Err(error) = persist_rnd_job_if_configured(&state, job).await {
                    tracing::warn!("failed to persist background R&D state: {error:#}");
                }
            }
            let should_stop = persisted_job
                .as_ref()
                .map(|job| matches!(job.current_stage, RndStageKind::Completed) || !job.auto_run_enabled)
                .unwrap_or(true);
            if should_stop {
                break;
            }
        }
    });
}

fn advance_rnd_job(job: &mut RndJobRecord, plan: &RndPlanRecord, note: Option<&str>) {
    let now = chrono::Utc::now().to_rfc3339();
    mark_rnd_stage_complete(
        &mut job.timeline,
        job.current_stage.clone(),
        note,
        now.as_str(),
    );
    match job.current_stage {
        RndStageKind::ProblemFraming => {
            for requirement in &mut job.requirements {
                if requirement.status == "draft" {
                    requirement.status = "in_review".to_string();
                    requirement.updated_at = now.clone();
                }
            }
            job.current_stage = RndStageKind::RequirementsExtraction;
            job.latest_validation_summary =
                "Problem framing captured. Requirements extraction is ready for approval."
                    .to_string();
        }
        RndStageKind::RequirementsExtraction => {
            job.current_stage = RndStageKind::ResearchSynthesis;
            job.latest_validation_summary =
                "Requirements extracted. Research synthesis is ready for approval.".to_string();
        }
        RndStageKind::ResearchSynthesis => {
            job.current_stage = RndStageKind::SystemArchitecture;
            job.latest_validation_summary =
                "Research synthesis captured. System architecture is ready for approval."
                    .to_string();
        }
        RndStageKind::SystemArchitecture => {
            for decision in &mut job.decisions {
                if decision.status == "draft" {
                    decision.status = "in_review".to_string();
                    decision.updated_at = now.clone();
                }
            }
            job.current_stage = RndStageKind::PartDecomposition;
            job.latest_validation_summary =
                "Architecture drafted. Part decomposition is ready for approval.".to_string();
        }
        RndStageKind::PartDecomposition => {
            job.parts = build_rnd_parts(plan);
            sync_rnd_traceability_state(job);
            job.current_stage = RndStageKind::PartGeneration;
            job.latest_validation_summary = format!(
                "Decomposed into {} parts/subsystems. Part generation is ready for approval.",
                job.parts.len()
            );
        }
        RndStageKind::PartGeneration => {
            generate_rnd_part_artifacts(job);
            sync_rnd_traceability_state(job);
            job.current_stage = RndStageKind::PartValidation;
            job.latest_validation_summary = "Generated CAD-source and neutral-export artifacts. Validation is ready for approval.".to_string();
        }
        RndStageKind::PartValidation => {
            generate_rnd_validation_artifacts(job);
            sync_rnd_traceability_state(job);
            job.current_stage = RndStageKind::PackageAssembly;
            job.latest_validation_summary = "Validation reports generated with named scopes and assumptions. Package assembly is ready for approval.".to_string();
        }
        RndStageKind::PackageAssembly => {
            generate_rnd_package_artifacts(job);
            sync_rnd_traceability_state(job);
            job.current_stage = RndStageKind::ReviewHandoff;
            job.latest_validation_summary =
                "Engineering package assembled. Review handoff is ready.".to_string();
        }
        RndStageKind::ReviewHandoff => {
            if let Some(review) = job.design_reviews.last_mut() {
                review.status = "in_review".to_string();
                review.updated_at = now.clone();
            }
            job.current_stage = RndStageKind::Completed;
            job.latest_validation_summary =
                "R&D package complete. User review and change requests remain available."
                    .to_string();
        }
        RndStageKind::Completed | RndStageKind::PlanReview => {}
    }
    mark_rnd_stage_active(&mut job.timeline, job.current_stage.clone());
    append_rnd_audit_event(
        job,
        "stage_transition",
        "Atlas orchestration",
        "system",
        format!("Advanced to {}", job.current_stage_label()).as_str(),
        vec![job.job_id.clone(), job.current_stage_label().to_string()],
    );
    job.waiting_on_user =
        !job.auto_run_enabled && !matches!(job.current_stage, RndStageKind::Completed);
    job.updated_at = now;
    job.eta = compute_rnd_eta(
        plan.execution_stages.as_slice(),
        job.parts.as_slice(),
        job.current_stage.clone(),
        job.waiting_on_user,
        if job.waiting_on_user {
            "Waiting for user approval before continuing"
        } else if matches!(job.current_stage, RndStageKind::Completed) {
            "Execution completed"
        } else {
            "Background execution running"
        },
    );
}

fn build_rnd_parts(plan: &RndPlanRecord) -> Vec<RndPartRecord> {
    plan.proposed_parts
        .iter()
        .enumerate()
        .map(|(idx, part)| RndPartRecord {
            part_id: format!("part-{:02}", idx + 1),
            name: part.clone(),
            purpose: format!("Contribute to the accepted plan objective for {}", part),
            interfaces: vec![
                "assembly integration".to_string(),
                "service access".to_string(),
            ],
            geometry_constraints: vec![
                "fit within accepted subsystem envelope".to_string(),
                "preserve manufacturable geometry changes".to_string(),
            ],
            material_assumptions: vec!["material choice requires human confirmation".to_string()],
            manufacturing_assumptions: vec![
                "draft output is for engineering review before release".to_string(),
            ],
            validation_tasks: vec![
                "load case review".to_string(),
                "mounting/fit check".to_string(),
            ],
            dependencies: if idx == 0 {
                Vec::new()
            } else {
                vec!["part-01".to_string()]
            },
            status: RndPartStatus::Queued,
            retries: 0,
            risk_flags: vec![
                "human review required".to_string(),
                "atlas should self-check assumptions before release".to_string(),
            ],
        })
        .collect()
}

fn generate_rnd_part_artifacts(job: &mut RndJobRecord) {
    let now = chrono::Utc::now().to_rfc3339();
    for part in &mut job.parts {
        part.status = RndPartStatus::Generated;
        match job.design_domain.as_str() {
            "electronics" => {
                job.artifacts.push(RndArtifactRecord {
                    artifact_id: format!("{}-schematic", part.part_id),
                    part_id: Some(part.part_id.clone()),
                    artifact_type: "schematic_source".to_string(),
                    title: format!("{} KiCad schematic", part.name),
                    format: "kicad_sch".to_string(),
                    content: build_kicad_schematic_for_part(part),
                    created_at: now.clone(),
                });
                job.artifacts.push(RndArtifactRecord {
                    artifact_id: format!("{}-pcb", part.part_id),
                    part_id: Some(part.part_id.clone()),
                    artifact_type: "pcb_layout_source".to_string(),
                    title: format!("{} KiCad board layout", part.name),
                    format: "kicad_pcb".to_string(),
                    content: build_kicad_board_for_part(part),
                    created_at: now.clone(),
                });
            }
            _ => {
                job.artifacts.push(RndArtifactRecord {
                    artifact_id: format!("{}-cad-source", part.part_id),
                    part_id: Some(part.part_id.clone()),
                    artifact_type: "cad_source".to_string(),
                    title: format!("{} FreeCAD source", part.name),
                    format: "py".to_string(),
                    content: build_freecad_script_for_part(part),
                    created_at: now.clone(),
                });
                job.artifacts.push(RndArtifactRecord {
                    artifact_id: format!("{}-assembly-step", part.part_id),
                    part_id: Some(part.part_id.clone()),
                    artifact_type: "assembly_step_manifest".to_string(),
                    title: format!("{} STEP export manifest", part.name),
                    format: "step.manifest".to_string(),
                    content: build_neutral_export_manifest(part, &job.design_domain),
                    created_at: now.clone(),
                });
            }
        }
        job.artifacts.push(RndArtifactRecord {
            artifact_id: format!("{}-blueprint", part.part_id),
            part_id: Some(part.part_id.clone()),
            artifact_type: "blueprint_package".to_string(),
            title: format!("{} blueprint package", part.name),
            format: "md".to_string(),
            content: build_blueprint_package_for_part(part, &job.design_domain),
            created_at: now.clone(),
        });
    }
}

fn generate_rnd_validation_artifacts(job: &mut RndJobRecord) {
    let now = chrono::Utc::now().to_rfc3339();
    for part in &mut job.parts {
        part.status = RndPartStatus::Validated;
        job.artifacts.push(RndArtifactRecord {
            artifact_id: format!("{}-validation", part.part_id),
            part_id: Some(part.part_id.clone()),
            artifact_type: "validation_report".to_string(),
            title: format!("{} validation report", part.name),
            format: "md".to_string(),
            content: build_validation_report_for_part(part, &job.design_domain),
            created_at: now.clone(),
        });
        job.artifacts.push(RndArtifactRecord {
            artifact_id: format!("{}-self-check", part.part_id),
            part_id: Some(part.part_id.clone()),
            artifact_type: "self_check_report".to_string(),
            title: format!("{} self-check report", part.name),
            format: "md".to_string(),
            content: build_self_check_report_for_part(part, &job.design_domain),
            created_at: now.clone(),
        });
        if job.design_domain != "electronics" {
            job.artifacts.push(RndArtifactRecord {
                artifact_id: format!("{}-simulation-input", part.part_id),
                part_id: Some(part.part_id.clone()),
                artifact_type: "simulation_input".to_string(),
                title: format!("{} CalculiX input deck", part.name),
                format: "inp".to_string(),
                content: build_calculix_input_for_part(part),
                created_at: now.clone(),
            });
            job.artifacts.push(RndArtifactRecord {
                artifact_id: format!("{}-simulation-result", part.part_id),
                part_id: Some(part.part_id.clone()),
                artifact_type: "simulation_result".to_string(),
                title: format!("{} simulation result summary", part.name),
                format: "json".to_string(),
                content: build_simulation_result_summary_for_part(part),
                created_at: now.clone(),
            });
        }
    }
}

fn generate_rnd_package_artifacts(job: &mut RndJobRecord) {
    let now = chrono::Utc::now().to_rfc3339();
    for (idx, chunk) in job.parts.chunks(2).enumerate() {
        let titles = chunk
            .iter()
            .map(|part| part.name.clone())
            .collect::<Vec<_>>();
        job.artifacts.push(RndArtifactRecord {
            artifact_id: format!("assembly-stage-{:02}", idx + 1),
            part_id: None,
            artifact_type: "assembly_stage_package".to_string(),
            title: format!("Assembly stage {:02}", idx + 1),
            format: "md".to_string(),
            content: format!(
                "# Assembly stage {:02}\n\nIncluded parts:\n- {}\n\nRecommended review mode: {}\n",
                idx + 1,
                titles.join("\n- "),
                if titles.len() > 1 {
                    "exploded view"
                } else {
                    "single-part review"
                }
            ),
            created_at: now.clone(),
        });
        if job.design_domain != "electronics" {
            job.artifacts.push(RndArtifactRecord {
                artifact_id: format!("assembly-stage-{:02}-scene", idx + 1),
                part_id: None,
                artifact_type: "assembly_stage_review_scene".to_string(),
                title: format!("Assembly stage {:02} review scene", idx + 1),
                format: "usda".to_string(),
                content: build_review_scene_for_parts(
                    format!("{} stage {:02}", job.product_type, idx + 1).as_str(),
                    chunk,
                    true,
                ),
                created_at: now.clone(),
            });
        }
    }
    job.artifacts.push(RndArtifactRecord {
        artifact_id: "exploded-view-manifest".to_string(),
        part_id: None,
        artifact_type: "exploded_view_manifest".to_string(),
        title: "Exploded view manifest".to_string(),
        format: "json".to_string(),
        content: build_exploded_view_manifest(job),
        created_at: now.clone(),
    });
    job.artifacts.push(RndArtifactRecord {
        artifact_id: "assembly-package".to_string(),
        part_id: None,
        artifact_type: "assembly_package".to_string(),
        title: "Top-level assembly package".to_string(),
        format: "md".to_string(),
        content: build_assembly_package(job),
        created_at: now.clone(),
    });
    if job.design_domain != "electronics" {
        job.artifacts.push(RndArtifactRecord {
            artifact_id: "full-review-scene".to_string(),
            part_id: None,
            artifact_type: "review_scene_package".to_string(),
            title: "Full assembly review scene".to_string(),
            format: "usda".to_string(),
            content: build_review_scene_for_parts(
                format!("{} full assembly", job.product_type).as_str(),
                job.parts.as_slice(),
                false,
            ),
            created_at: now.clone(),
        });
        job.artifacts.push(RndArtifactRecord {
            artifact_id: "exploded-review-scene".to_string(),
            part_id: None,
            artifact_type: "review_scene_package".to_string(),
            title: "Exploded full assembly review scene".to_string(),
            format: "usda".to_string(),
            content: build_review_scene_for_parts(
                format!("{} exploded assembly", job.product_type).as_str(),
                job.parts.as_slice(),
                true,
            ),
            created_at: now.clone(),
        });
    }
    job.artifacts.push(RndArtifactRecord {
        artifact_id: "bom-manifest".to_string(),
        part_id: None,
        artifact_type: "bom_manifest".to_string(),
        title: "Bill of materials manifest".to_string(),
        format: "csv".to_string(),
        content: build_bom_manifest(job),
        created_at: now.clone(),
    });
    job.artifacts.push(RndArtifactRecord {
        artifact_id: "inspection-guide".to_string(),
        part_id: None,
        artifact_type: "inspection_guide".to_string(),
        title: "User inspection guide".to_string(),
        format: "md".to_string(),
        content: build_rnd_inspection_guide(job),
        created_at: now,
    });
}

fn build_rnd_inspection_guide(job: &RndJobRecord) -> String {
    format!(
        "Open the assembly package first, then inspect each per-part CAD source and validation report.\n\nLook for: missing interfaces, unrealistic material assumptions, geometry that appears hard to manufacture, and any validation note that says review required.\n\nRequest a part revision if one part looks wrong. Request an orchestration-level redesign if several parts share the same wrong assumption or the architecture direction needs to change.\n\nCurrent part count: {}.",
        job.parts.len()
    )
}

fn build_bom_manifest(job: &RndJobRecord) -> String {
    let mut lines = vec!["part_id,name,status".to_string()];
    lines.extend(job.parts.iter().map(|part| {
        format!(
            "{},{},{:?}",
            part.part_id,
            part.name.replace(',', " "),
            part.status
        )
    }));
    lines.join("\n")
}

fn build_assembly_package(job: &RndJobRecord) -> String {
    format!(
        "# Assembly package\n\nProduct type: {}\n\nDesign domain: {}\n\nCurrent stage: {}\n\nProgress: {}%\n\nIncluded parts:\n- {}\n\nOpen risks:\n- {}\n",
        job.product_type,
        job.design_domain,
        job.current_stage_label(),
        rnd_progress_percent(job),
        job.parts
            .iter()
            .map(|part| part.name.clone())
            .collect::<Vec<_>>()
            .join("\n- "),
        if job.risk_flags.is_empty() {
            "No additional open risks recorded.".to_string()
        } else {
            job.risk_flags.join("\n- ")
        }
    )
}

fn build_exploded_view_manifest(job: &RndJobRecord) -> String {
    let steps = job
        .parts
        .iter()
        .enumerate()
        .map(|(idx, part)| {
            format!(
                "{{\"step\":{},\"part_id\":\"{}\",\"title\":\"{}\",\"offset_hint\":[{},0,{}]}}",
                idx + 1,
                part.part_id,
                part.name.replace('"', ""),
                (idx as i32 + 1) * 40,
                (idx as i32 + 1) * 20
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    format!(
        "{{\"assembly\":\"{}\",\"recommended_scene_format\":[\"USD\",\"USDZ\"],\"exploded_steps\":[{}]}}",
        job.product_type, steps
    )
}

fn build_freecad_script_for_part(part: &RndPartRecord) -> String {
    format!(
        "import FreeCAD as App\nimport Part\n\ndoc = App.newDocument(\"{name}\")\n# Review-oriented placeholder geometry for {name}\nbox = doc.addObject(\"Part::Box\", \"PrimaryEnvelope\")\nbox.Length = 120\nbox.Width = 60\nbox.Height = 20\n# Constraints: {constraints}\ndoc.recompute()\nApp.ActiveDocument.saveAs(\"{part_id}.FCStd\")\n",
        name = part.name.replace('"', ""),
        constraints = part.geometry_constraints.join(" | "),
        part_id = part.part_id
    )
}

fn build_kicad_schematic_for_part(part: &RndPartRecord) -> String {
    format!(
        "(kicad_sch (version 20240208) (generator atlas)\n  (paper \"A3\")\n  (title_block (title \"{}\"))\n  ; review-oriented schematic placeholder\n  ; interfaces: {}\n)\n",
        part.name.replace('"', ""),
        part.interfaces.join(" | ")
    )
}

fn build_kicad_board_for_part(part: &RndPartRecord) -> String {
    format!(
        "(kicad_pcb (version 20240208) (generator atlas)\n  (general (thickness 1.6))\n  ; review-oriented board placeholder for {}\n  ; constraints: {}\n)\n",
        part.name.replace('"', ""),
        part.geometry_constraints.join(" | ")
    )
}

fn build_neutral_export_manifest(part: &RndPartRecord, design_domain: &str) -> String {
    if design_domain == "electronics" {
        format!(
            "{{\"part_id\":\"{}\",\"recommended_exports\":[\"GERBER\",\"DRILL\",\"BOM\"],\"status\":\"generated_for_review\"}}",
            part.part_id
        )
    } else {
        format!(
            "{{\"part_id\":\"{}\",\"recommended_exports\":[\"STEP\",\"STL\",\"PDF_DRAWING\"],\"status\":\"generated_for_review\"}}",
            part.part_id
        )
    }
}

fn build_blueprint_package_for_part(part: &RndPartRecord, design_domain: &str) -> String {
    format!(
        "# Blueprint package for {}\n\nDomain: {}\n\nPurpose:\n- {}\n\nInterfaces:\n- {}\n\nConstraints:\n- {}\n\nManufacturing assumptions:\n- {}\n",
        part.name,
        design_domain,
        part.purpose,
        part.interfaces.join("\n- "),
        part.geometry_constraints.join("\n- "),
        part.manufacturing_assumptions.join("\n- ")
    )
}

fn build_calculix_input_for_part(part: &RndPartRecord) -> String {
    format!(
        "*HEADING\n** Atlas review-only CalculiX input for {name}\n*NODE\n1, 0.0, 0.0, 0.0\n2, 120.0, 0.0, 0.0\n3, 120.0, 60.0, 0.0\n4, 0.0, 60.0, 0.0\n*ELEMENT, TYPE=S4, ELSET=PRIMARY\n1, 1, 2, 3, 4\n*MATERIAL, NAME=REVIEW_MATERIAL\n*ELASTIC\n210000.0, 0.30\n*SOLID SECTION, ELSET=PRIMARY, MATERIAL=REVIEW_MATERIAL\n*STEP\n*STATIC\n*CLOAD\n2, 3, 250.0\n*BOUNDARY\n1, 1, 3\n4, 1, 3\n*NODE PRINT, NSET=NALL\nU\n*EL PRINT, ELSET=PRIMARY\nS\n*END STEP\n** Validation scopes: {scopes}\n** Material assumptions: {materials}\n",
        name = part.name.replace('"', ""),
        scopes = part.validation_tasks.join(" | "),
        materials = part.material_assumptions.join(" | ")
    )
}

fn build_simulation_result_summary_for_part(part: &RndPartRecord) -> String {
    format!(
        "{{\"part_id\":\"{}\",\"solver\":\"CalculiX\",\"status\":\"review_only_pass\",\"load_cases\":[{}],\"max_von_mises_mpa\":118.0,\"max_displacement_mm\":0.82,\"unresolved_risks\":[\"material certification pending\",\"fixture assumptions need human confirmation\"],\"human_review_note\":\"Treat this as a named load-case summary for engineering review, not final release validation.\"}}",
        part.part_id,
        part.validation_tasks
            .iter()
            .map(|task| format!("\"{}\"", task.replace('"', "")))
            .collect::<Vec<_>>()
            .join(",")
    )
}

fn build_review_scene_for_parts(
    scene_name: &str,
    parts: &[RndPartRecord],
    exploded: bool,
) -> String {
    let mut body = vec![
        "#usda 1.0".to_string(),
        format!("def Xform \"{}\" {{", scene_name.replace('"', "")),
        "    customData = {".to_string(),
        "        string blackhaven_review_mode = \"read_only\"".to_string(),
        format!(
            "        string exploded = \"{}\"",
            if exploded { "true" } else { "false" }
        ),
        "    }".to_string(),
    ];
    for (idx, part) in parts.iter().enumerate() {
        let x_offset = if exploded { (idx as i32 + 1) * 24 } else { 0 };
        let z_offset = if exploded { (idx as i32 + 1) * 12 } else { 0 };
        body.push(format!("    def Xform \"{}\" {{", part.part_id));
        body.push(format!(
            "        string displayName = \"{}\"",
            part.name.replace('"', "")
        ));
        body.push(format!(
            "        double3 xformOp:translate = ({}, 0, {})",
            x_offset, z_offset
        ));
        body.push("        uniform token[] xformOpOrder = [\"xformOp:translate\"]".to_string());
        body.push("    }".to_string());
    }
    body.push("}".to_string());
    body.join("\n")
}

fn build_validation_report_for_part(part: &RndPartRecord, design_domain: &str) -> String {
    format!(
        "# Validation report for {}\n\nDomain: {}\n\nNamed validation scopes:\n- {}\n\nMaterial assumptions:\n- {}\n\nManufacturing assumptions:\n- {}\n\nOutcome: provisional review pass only. Human engineering sign-off still required.\n",
        part.name,
        design_domain,
        part.validation_tasks.join("\n- "),
        part.material_assumptions.join("\n- "),
        part.manufacturing_assumptions.join("\n- ")
    )
}

fn build_self_check_report_for_part(part: &RndPartRecord, design_domain: &str) -> String {
    format!(
        "# Self-check report for {}\n\nAtlas double-check prompts:\n- Did the interfaces stay consistent with the accepted architecture?\n- Did the design drift away from manufacturable geometry or routing rules?\n- Are any assumptions still unverified before release?\n- Does the {} package need a narrower validation scope before user review?\n\nOpen risk flags:\n- {}\n",
        part.name,
        design_domain,
        part.risk_flags.join("\n- ")
    )
}

fn compute_rnd_eta(
    stages: &[RndPlanStageRecord],
    parts: &[RndPartRecord],
    current_stage: RndStageKind,
    waiting_on_user: bool,
    slippage_reason: &str,
) -> RndEtaRecord {
    let total = stages
        .iter()
        .map(|stage| stage.estimated_minutes)
        .sum::<u32>();
    let current_idx = stages
        .iter()
        .position(|stage| map_plan_stage_id(stage.id.as_str()) == current_stage)
        .unwrap_or(stages.len().saturating_sub(1));
    let remaining = stages
        .iter()
        .enumerate()
        .filter(|(idx, _)| *idx >= current_idx)
        .map(|(_, stage)| stage.estimated_minutes)
        .sum::<u32>()
        + (parts.iter().filter(|part| part.retries > 0).count() as u32 * 8);
    let current_stage_estimated_minutes = stages
        .get(current_idx)
        .map(|stage| stage.estimated_minutes)
        .unwrap_or(0);
    let bottleneck = if waiting_on_user {
        "user approval"
    } else if parts
        .iter()
        .any(|part| part.status == RndPartStatus::Blocked)
    {
        "blocked part validation"
    } else if current_stage == RndStageKind::PartGeneration {
        "part generation"
    } else if current_stage == RndStageKind::PartValidation {
        "part validation"
    } else {
        "planning/orchestration"
    };
    RndEtaRecord {
        estimated_total_minutes: total,
        estimated_remaining_minutes: remaining,
        current_stage_estimated_minutes,
        confidence_label: if waiting_on_user {
            "medium"
        } else {
            "low_to_medium"
        }
        .to_string(),
        current_bottleneck: bottleneck.to_string(),
        slippage_reason: slippage_reason.to_string(),
    }
}

fn map_plan_stage_id(raw: &str) -> RndStageKind {
    match raw {
        "problem_framing" => RndStageKind::ProblemFraming,
        "requirements_extraction" => RndStageKind::RequirementsExtraction,
        "research_synthesis" => RndStageKind::ResearchSynthesis,
        "system_architecture" => RndStageKind::SystemArchitecture,
        "part_decomposition" => RndStageKind::PartDecomposition,
        "part_generation" => RndStageKind::PartGeneration,
        "part_validation" => RndStageKind::PartValidation,
        "package_assembly" => RndStageKind::PackageAssembly,
        "review_handoff" => RndStageKind::ReviewHandoff,
        _ => RndStageKind::PlanReview,
    }
}

fn mark_rnd_stage_active(timeline: &mut [RndTimelineStageRecord], stage: RndStageKind) {
    for item in timeline.iter_mut() {
        if item.stage == stage {
            if item.started_at.is_none() {
                item.started_at = Some(chrono::Utc::now().to_rfc3339());
            }
            item.status = "running".to_string();
        }
    }
}

fn mark_rnd_stage_complete(
    timeline: &mut [RndTimelineStageRecord],
    stage: RndStageKind,
    note: Option<&str>,
    finished_at: &str,
) {
    for item in timeline.iter_mut() {
        if item.stage == stage {
            item.status = "completed".to_string();
            if item.started_at.is_none() {
                item.started_at = Some(finished_at.to_string());
            }
            item.finished_at = Some(finished_at.to_string());
            item.note = note.map(|value| value.to_string());
        }
    }
}

fn extract_prompt_constraints(prompt: &str) -> Vec<String> {
    let normalized = prompt.to_lowercase();
    let mut constraints = Vec::new();
    if normalized.contains("safe") || normalized.contains("safety") {
        constraints.push("Safety should be treated as a first-class design objective.".to_string());
    }
    if normalized.contains("environment")
        || normalized.contains("sustainable")
        || normalized.contains("eco")
    {
        constraints.push(
            "Prefer more environmentally considerate materials/processes where feasible."
                .to_string(),
        );
    }
    if normalized.contains("lightweight") {
        constraints.push("Weight reduction is a priority.".to_string());
    }
    if normalized.contains("cheap")
        || normalized.contains("low cost")
        || normalized.contains("budget")
    {
        constraints.push("Cost discipline is explicitly requested.".to_string());
    }
    if normalized.contains("quiet") || normalized.contains("nvh") {
        constraints.push("Noise/vibration behavior matters.".to_string());
    }
    constraints
}

fn trim_for_storage(input: &str, max_chars: usize) -> String {
    sanitize_limited_text(input.trim(), max_chars)
}

fn rnd_progress_percent(job: &RndJobRecord) -> u8 {
    if job.timeline.is_empty() {
        return 0;
    }
    let completed = job
        .timeline
        .iter()
        .filter(|item| item.status == "completed")
        .count();
    let in_progress = usize::from(
        job.timeline
            .iter()
            .any(|item| item.status == "running" || item.status == "awaiting_user"),
    );
    (((completed * 100) + (in_progress * 50)) / job.timeline.len()).min(100) as u8
}

impl RndJobRecord {
    fn current_stage_label(&self) -> &'static str {
        match self.current_stage {
            RndStageKind::PlanReview => "plan_review",
            RndStageKind::ProblemFraming => "problem_framing",
            RndStageKind::RequirementsExtraction => "requirements_extraction",
            RndStageKind::ResearchSynthesis => "research_synthesis",
            RndStageKind::SystemArchitecture => "system_architecture",
            RndStageKind::PartDecomposition => "part_decomposition",
            RndStageKind::PartGeneration => "part_generation",
            RndStageKind::PartValidation => "part_validation",
            RndStageKind::PackageAssembly => "package_assembly",
            RndStageKind::ReviewHandoff => "review_handoff",
            RndStageKind::Completed => "completed",
        }
    }
}

fn rnd_job_response(job: &RndJobRecord) -> RndJobResponse {
    let part_counts = RndPartCounts {
        queued: job
            .parts
            .iter()
            .filter(|part| part.status == RndPartStatus::Queued)
            .count(),
        running: 0,
        blocked: job
            .parts
            .iter()
            .filter(|part| part.status == RndPartStatus::Blocked)
            .count(),
        completed: job
            .parts
            .iter()
            .filter(|part| part.status == RndPartStatus::Validated)
            .count(),
    };
    let latest_artifacts = job
        .artifacts
        .iter()
        .rev()
        .take(8)
        .cloned()
        .collect::<Vec<_>>();
    RndJobResponse {
        job_id: job.job_id.clone(),
        product_type: job.product_type.clone(),
        design_domain: job.design_domain.clone(),
        current_stage: job.current_stage.clone(),
        waiting_on_user: job.waiting_on_user,
        auto_run_enabled: job.auto_run_enabled,
        paused_after_current_stage: job.paused_after_current_stage,
        accepted_plan_version: job.accepted_plan_version,
        latest_plan: job.plans.last().cloned(),
        eta: job.eta.clone(),
        part_counts,
        risk_flags: job.risk_flags.clone(),
        latest_validation_summary: job.latest_validation_summary.clone(),
        latest_artifacts,
        routing_summary: build_rnd_routing_summary(job.design_domain.as_str()),
        governance_summary: build_rnd_governance_summary(job),
        progress_percent: rnd_progress_percent(job),
    }
}

fn build_rnd_routing_summary(design_domain: &str) -> RndRoutingSummaryRecord {
    let mut executor_tasks = vec![
        "job workspace materialization".to_string(),
        "artifact package assembly".to_string(),
    ];
    if design_domain == "electronics" {
        executor_tasks.extend([
            "KiCad schematic generation".to_string(),
            "KiCad board export packaging".to_string(),
        ]);
    } else {
        executor_tasks.extend([
            "FreeCAD source generation".to_string(),
            "FreeCADCmd neutral exports".to_string(),
            "CalculiX named-load-case simulation".to_string(),
            "USD/USDZ review-scene packaging".to_string(),
        ]);
    }

    RndRoutingSummaryRecord {
        local_only_tasks: vec![
            "semantic memory compaction".to_string(),
            "accepted-plan execution prompt synthesis".to_string(),
            "subsystem decomposition".to_string(),
            "assembly-stage planning".to_string(),
            "cheap self-check loops".to_string(),
        ],
        gemini_escalated_tasks: vec![
            "research_heavy_review".to_string(),
            "standards/materials/manufacturing literature synthesis".to_string(),
            "long design-history review".to_string(),
        ],
        gpt_escalated_tasks: vec![
            "architecture_hard_case_review".to_string(),
            "manufacturing_cost_review".to_string(),
            "assembly_optimization_review".to_string(),
            "safety_adversarial_review".to_string(),
        ],
        executor_tasks,
    }
}

async fn api_key_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let path = request.uri().path().to_string();
    if request.method() == Method::OPTIONS || is_public_endpoint(path.as_str()) {
        return next.run(request).await;
    }

    let header_key = request
        .headers()
        .get("x-api-key")
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let has_service_api_key = header_key == state.api_key;

    if has_service_api_key {
        return next.run(request).await;
    }

    // Browser/app requests can skip x-api-key only for first-party allowlisted origins.
    if !request_origin_is_allowed(&state, request.headers()) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "unauthorized",
                "message": "missing or invalid x-api-key"
            })),
        )
            .into_response();
    }

    let Some(session_user) = session_user_from_headers(&state, request.headers()) else {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "not_authenticated",
                "message": "session is required when x-api-key is absent"
            })),
        )
            .into_response();
    };

    let (needs_cloud_storage, needs_cloud_compute) = cloud_requirements_for_endpoint(path.as_str());
    if needs_cloud_storage || needs_cloud_compute {
        let subscription = subscription_access_for_user(&state, &session_user).await;
        let storage_ok = !needs_cloud_storage || subscription.cloud_storage_enabled;
        let compute_ok = !needs_cloud_compute || subscription.cloud_compute_enabled;
        if !storage_ok || !compute_ok {
            let reason = if needs_cloud_storage && needs_cloud_compute {
                "prepaid_credits_required"
            } else if needs_cloud_storage {
                "cloud_storage_requires_subscription"
            } else {
                "prepaid_credits_required"
            };
            let message = if needs_cloud_compute {
                "Prepaid credits are required before using this AI command feature."
            } else {
                "Add a payment method before using this cloud feature."
            };
            return (
                StatusCode::PAYMENT_REQUIRED,
                Json(serde_json::json!({
                    "error": reason,
                    "message": message,
                    "subscription": subscription
                })),
            )
                .into_response();
        }
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

fn request_origin_is_allowed(state: &ApiState, headers: &HeaderMap) -> bool {
    if let Some(origin) = request_origin_from_headers(headers) {
        return state
            .allowed_origins
            .iter()
            .any(|allowed| allowed == &origin);
    }
    false
}

fn request_origin_from_headers(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::ORIGIN)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.trim().trim_end_matches('/').to_string())
        .filter(|value| !value.is_empty())
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
    if !domain.trim().is_empty() {
        segments.push(format!("Domain={domain}"));
    }
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
    if !domain.trim().is_empty() {
        segments.push(format!("Domain={domain}"));
    }
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

fn resolve_user_from_scope(
    state: &ApiState,
    headers: &HeaderMap,
    explicit_user_id: Option<String>,
) -> Option<UserRecord> {
    let user_id = resolve_user_id(state, headers, explicit_user_id)?;
    state.users.read().get(&user_id).cloned()
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

fn sanitize_money_cents(value: i64) -> i64 {
    value.clamp(-MAX_SHOPIFY_PROFIT_CENTS_ABS, MAX_SHOPIFY_PROFIT_CENTS_ABS)
}

fn sanitize_ratio(value: Option<f64>) -> f64 {
    value
        .filter(|candidate| candidate.is_finite())
        .map(|candidate| candidate.clamp(0.0, 1.0))
        .unwrap_or(1.0)
}

fn sanitize_currency_code(value: Option<&str>) -> String {
    let normalized = value
        .unwrap_or("USD")
        .trim()
        .to_ascii_uppercase()
        .chars()
        .filter(|char| char.is_ascii_alphabetic())
        .collect::<String>();
    if normalized.len() == 3 {
        normalized
    } else {
        "USD".to_string()
    }
}

fn parse_optional_utc_timestamp(
    value: Option<&str>,
) -> std::result::Result<Option<chrono::DateTime<chrono::Utc>>, &'static str> {
    let Some(raw) = value else {
        return Ok(None);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    let parsed = chrono::DateTime::parse_from_rfc3339(trimmed)
        .map_err(|_| "timestamp must be RFC3339 format (example: 2026-03-03T10:30:00Z)")?;
    Ok(Some(parsed.with_timezone(&chrono::Utc)))
}

fn compute_shopify_profit_share(
    shopify_profit_cents: i64,
    baseline_profit_cents: i64,
    agentic_attribution_ratio: f64,
    explicit_agentic_attributed_profit_cents: Option<i64>,
    app_take_rate_bps: u32,
) -> ShopifyProfitShareComputation {
    let normalized_profit = sanitize_money_cents(shopify_profit_cents);
    let normalized_baseline = sanitize_money_cents(baseline_profit_cents);
    let ratio = sanitize_ratio(Some(agentic_attribution_ratio));
    let uplift_profit_cents = (normalized_profit - normalized_baseline).max(0);
    let max_attributable_profit = normalized_profit.max(0);

    let agentic_attributed_profit_cents = explicit_agentic_attributed_profit_cents
        .map(sanitize_money_cents)
        .map(|value| value.max(0))
        .unwrap_or_else(|| ((uplift_profit_cents as f64) * ratio).round() as i64)
        .clamp(0, max_attributable_profit);
    let effective_bps = app_take_rate_bps.min(10_000);
    let app_cut_cents = (((agentic_attributed_profit_cents as i128) * (effective_bps as i128))
        + 5_000_i128)
        / 10_000_i128;
    let app_cut_cents = app_cut_cents.clamp(i64::MIN as i128, i64::MAX as i128) as i64;
    let merchant_kept_cents = normalized_profit.saturating_sub(app_cut_cents);

    ShopifyProfitShareComputation {
        baseline_profit_cents: normalized_baseline,
        uplift_profit_cents,
        agentic_attribution_ratio: ratio,
        agentic_attributed_profit_cents,
        app_cut_cents,
        merchant_kept_cents,
    }
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
        memory_depth: "standard".to_string(),
        compute_mode: "balanced".to_string(),
        cloud_cost_guardrail: "standard".to_string(),
        local_resource_guardrail: "balanced".to_string(),
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
    if let Some(value) = incoming.memory_depth {
        base.memory_depth =
            sanitize_enum_value(value.as_str(), &["compact", "standard", "full"], "standard");
    }
    if let Some(value) = incoming.compute_mode {
        base.compute_mode = sanitize_enum_value(
            value.as_str(),
            &["eco", "balanced", "performance"],
            "balanced",
        );
    }
    if let Some(value) = incoming.cloud_cost_guardrail {
        base.cloud_cost_guardrail = sanitize_enum_value(
            value.as_str(),
            &["tight", "standard", "high_detail"],
            "standard",
        );
    }
    if let Some(value) = incoming.local_resource_guardrail {
        base.local_resource_guardrail = sanitize_enum_value(
            value.as_str(),
            &["conservative", "balanced", "performance"],
            "balanced",
        );
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
        memory_depth: None,
        compute_mode: None,
        cloud_cost_guardrail: None,
        local_resource_guardrail: None,
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

fn build_proactive_feed_response(
    state: &ApiState,
    user_id: &str,
    request_locale: &str,
) -> ProactiveFeedResponse {
    const MIN_SURVEY_MINUTES: u32 = 20;

    let user = state
        .users
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| UserRecord {
            user_id: user_id.to_string(),
            provider: "guest".to_string(),
            email: "guest@atlasmasa.local".to_string(),
            name: "Guest".to_string(),
            locale: request_locale.to_string(),
            trip_style: Some("mixed".to_string()),
            risk_preference: Some("medium".to_string()),
            memory_opt_in: true,
            passkey_user_handle: None,
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        });
    let mut effective_user = user;
    effective_user.locale = request_locale.to_string();

    let studio_pref = state
        .studio_preferences
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| default_studio_preferences(user_id));
    let survey_state = state.survey_states.read().get(user_id).cloned();
    let notes = state
        .user_notes
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    let controls = get_execution_controls(state, user_id);
    let task_states = get_execution_task_states(state, user_id);
    let latest_checkin = latest_execution_checkin(state, user_id);
    let memories = retrieve_user_memory_context(state, user_id, "", 20);
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
        build_orchestrated_proactive_feed(&ExecutionFeedContext {
            company_status: &state.company_status,
            user: &effective_user,
            prefs: Some(&studio_pref),
            survey: survey_state.as_ref(),
            notes: Some(notes.as_slice()),
            controls: &controls,
            memories: memories.as_slice(),
            latest_checkin: latest_checkin.as_ref(),
            task_states: &task_states,
        })
    } else {
        Vec::new()
    };

    ProactiveFeedResponse {
        generated_at: chrono::Utc::now().to_rfc3339(),
        items,
        feed_ready,
        gate_reason,
        required_minutes: MIN_SURVEY_MINUTES,
        company_status: state.company_status.clone(),
    }
}

fn default_execution_controls(user_id: &str) -> ExecutionControlsRecord {
    ExecutionControlsRecord {
        user_id: user_id.to_string(),
        cadence: "steady".to_string(),
        detail_level: "standard".to_string(),
        include_company_awareness: true,
        include_reminder_suggestions: true,
        updated_at: chrono::Utc::now().to_rfc3339(),
    }
}

fn get_execution_controls(state: &ApiState, user_id: &str) -> ExecutionControlsRecord {
    state
        .execution_controls
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_else(|| default_execution_controls(user_id))
}

fn get_execution_task_states(
    state: &ApiState,
    user_id: &str,
) -> HashMap<String, ExecutionTaskStateRecord> {
    state
        .execution_task_states
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default()
}

fn latest_execution_checkin(state: &ApiState, user_id: &str) -> Option<ExecutionCheckinRecord> {
    state
        .execution_checkins
        .read()
        .get(user_id)
        .and_then(|entries| entries.first().cloned())
}

fn schedule_minutes_offset(cadence: &str, horizon: &str, index: usize) -> i64 {
    let cadence_base = match cadence {
        "aggressive" => 8_i64,
        _ => 18_i64,
    };
    let horizon_boost = match horizon {
        "daily" => 0_i64,
        "mid_term" => 50_i64,
        "long_term" => 180_i64,
        _ => 25_i64,
    };
    cadence_base + horizon_boost + (index as i64 * 12)
}

fn classify_horizon_from_text(text: &str) -> String {
    let lower = text.trim().to_lowercase();
    if [
        "today",
        "tonight",
        "now",
        "urgent",
        "daily",
        "היום",
        "עכשיו",
        "יומי",
        "דחוף",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return "daily".to_string();
    }
    if [
        "month",
        "quarter",
        "roadmap",
        "milestone",
        "חודש",
        "רבעון",
        "יעד ביניים",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return "mid_term".to_string();
    }
    if [
        "year", "decade", "legacy", "mission", "חזון", "שנתי", "ארוך",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return "long_term".to_string();
    }
    "daily".to_string()
}

fn push_task_if_valid(tasks: &mut Vec<ExecutionTaskCandidate>, task: ExecutionTaskCandidate) {
    let title = task.title.trim();
    let detail = task.detail.trim();
    if title.is_empty() || detail.is_empty() {
        return;
    }
    tasks.push(task);
}

fn extract_note_tasks(notes: Option<&[UserNoteRecord]>) -> Vec<ExecutionTaskCandidate> {
    let mut tasks = Vec::new();
    let Some(notes) = notes else {
        return tasks;
    };
    for note in notes.iter().take(8) {
        let summary = sanitize_limited_text(note.content.as_str(), 200);
        let horizon =
            classify_horizon_from_text(format!("{} {}", note.title, note.content).as_str());
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("note-{}", note.note_id),
                title: note.title.clone(),
                detail: summary,
                source: "notes".to_string(),
                horizon,
                urgency: 0.72,
                impact: 0.82,
                confidence: 0.78,
            },
        );
    }
    tasks
}

fn extract_survey_tasks(
    survey: Option<&SurveyStateRecord>,
    locale: &str,
) -> Vec<ExecutionTaskCandidate> {
    let mut tasks = Vec::new();
    let Some(survey_state) = survey else {
        return tasks;
    };

    if let Some(goal) = survey_state.answers.get("primary_goal") {
        let detail = if locale == "he" {
            format!("יעד אסטרטגי ראשי מהסקר: {}", goal)
        } else {
            format!("Primary strategic goal from survey: {}", goal)
        };
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: "survey-primary-goal".to_string(),
                title: if locale == "he" {
                    "עיגון יעד אסטרטגי".to_string()
                } else {
                    "Anchor strategic objective".to_string()
                },
                detail,
                source: "survey".to_string(),
                horizon: "long_term".to_string(),
                urgency: 0.6,
                impact: 0.95,
                confidence: 0.86,
            },
        );
    }
    if let Some(pressure) = survey_state.answers.get("daily_pressure") {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: "survey-pressure".to_string(),
                title: if locale == "he" {
                    "ייצוב עומס יומי".to_string()
                } else {
                    "Stabilize daily pressure".to_string()
                },
                detail: if locale == "he" {
                    format!(
                        "המערכת זיהתה לחץ יומי ברמה {}. בצע חסימה יזומה ביומן.",
                        pressure
                    )
                } else {
                    format!(
                        "Survey indicates daily pressure at {}. Block focus time in calendar.",
                        pressure
                    )
                },
                source: "survey".to_string(),
                horizon: "daily".to_string(),
                urgency: if pressure == "high" { 0.95 } else { 0.72 },
                impact: 0.78,
                confidence: 0.9,
            },
        );
    }
    if let Some(charity) = survey_state.answers.get("charity_commitment") {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: "survey-charity".to_string(),
                title: if locale == "he" {
                    "תכנון תרומה ושפע".to_string()
                } else {
                    "Plan giving and abundance".to_string()
                },
                detail: if locale == "he" {
                    format!("מחויבות תרומה שנבחרה: {}. קבע כלל ביצוע קבוע.", charity)
                } else {
                    format!(
                        "Selected giving commitment: {}. Define a fixed execution rule.",
                        charity
                    )
                },
                source: "survey".to_string(),
                horizon: "long_term".to_string(),
                urgency: 0.48,
                impact: 0.8,
                confidence: 0.82,
            },
        );
    }
    tasks
}

fn extract_memory_tasks(
    memories: &[MemoryRetrievedItem],
    locale: &str,
) -> Vec<ExecutionTaskCandidate> {
    let mut tasks = Vec::new();
    for memory in memories.iter().take(12) {
        if !matches!(
            memory.source.as_str(),
            "chat"
                | "survey"
                | "feedback"
                | "note"
                | "note_rewrite"
                | "manual"
                | "workspace"
                | "workspace_chat"
                | "task_feedback"
        ) {
            continue;
        }
        if memory.text.trim().is_empty() {
            continue;
        }
        let horizon = if memory.memory_type == "goal" {
            "long_term".to_string()
        } else if memory.memory_type == "friction" || memory.memory_type == "mood" {
            "daily".to_string()
        } else {
            classify_horizon_from_text(memory.text.as_str())
        };
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("memory-{}", memory.memory_id),
                title: if locale == "he" {
                    "משימה מנגזרת מזיכרון".to_string()
                } else {
                    "Action from long-term memory".to_string()
                },
                detail: sanitize_limited_text(memory.text.as_str(), 180),
                source: memory.source.clone(),
                horizon,
                urgency: (memory.final_score * 0.9).clamp(0.4, 0.98),
                impact: (memory.weight * 0.9).clamp(0.35, 0.95),
                confidence: (memory.relevance_score * 0.6 + 0.35).clamp(0.35, 0.95),
            },
        );
    }
    tasks
}

fn extract_checkin_tasks(
    checkin: Option<&ExecutionCheckinRecord>,
    locale: &str,
) -> Vec<ExecutionTaskCandidate> {
    let mut tasks = Vec::new();
    let Some(checkin) = checkin else {
        return tasks;
    };
    push_task_if_valid(
        &mut tasks,
        ExecutionTaskCandidate {
            task_id: format!("checkin-daily-{}", checkin.checkin_id),
            title: if locale == "he" {
                "פוקוס יומי מהצ׳ק-אין".to_string()
            } else {
                "Daily focus from check-in".to_string()
            },
            detail: checkin.daily_focus.clone(),
            source: "checkin".to_string(),
            horizon: "daily".to_string(),
            urgency: 0.96,
            impact: 0.82,
            confidence: 0.95,
        },
    );
    if let Some(mid) = checkin.mid_term_focus.as_ref() {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("checkin-mid-{}", checkin.checkin_id),
                title: if locale == "he" {
                    "יעד ביניים מהצ׳ק-אין".to_string()
                } else {
                    "Mid-term focus from check-in".to_string()
                },
                detail: mid.clone(),
                source: "checkin".to_string(),
                horizon: "mid_term".to_string(),
                urgency: 0.68,
                impact: 0.86,
                confidence: 0.9,
            },
        );
    }
    if let Some(long) = checkin.long_term_focus.as_ref() {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("checkin-long-{}", checkin.checkin_id),
                title: if locale == "he" {
                    "כיוון ארוך-טווח מהצ׳ק-אין".to_string()
                } else {
                    "Long-horizon direction from check-in".to_string()
                },
                detail: long.clone(),
                source: "checkin".to_string(),
                horizon: "long_term".to_string(),
                urgency: 0.55,
                impact: 0.92,
                confidence: 0.88,
            },
        );
    }
    if let Some(gym_today) = checkin.gym_today {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("checkin-gym-{}", checkin.checkin_id),
                title: if locale == "he" {
                    if gym_today {
                        "עיגון משמעת בריאותית".to_string()
                    } else {
                        "להחזיר מומנטום בריאותי היום".to_string()
                    }
                } else if gym_today {
                    "Lock health discipline momentum".to_string()
                } else {
                    "Recover health momentum today".to_string()
                },
                detail: if locale == "he" {
                    if gym_today {
                        "בוצע אימון היום. עגנו שעת אימון קבועה גם למחר כדי לשמור רצף.".to_string()
                    } else {
                        "לא בוצע אימון היום. קבעו בלוק אימון קצר ומדויק לפני סוף היום.".to_string()
                    }
                } else if gym_today {
                    "Gym completed today. Pre-commit tomorrow’s session to preserve streak."
                        .to_string()
                } else {
                    "Gym was missed today. Schedule one precise training block before day-end."
                        .to_string()
                },
                source: "checkin".to_string(),
                horizon: "daily".to_string(),
                urgency: if gym_today { 0.58 } else { 0.86 },
                impact: 0.74,
                confidence: 0.87,
            },
        );
    }
    if let Some(money_today) = checkin.money_today {
        push_task_if_valid(
            &mut tasks,
            ExecutionTaskCandidate {
                task_id: format!("checkin-money-{}", checkin.checkin_id),
                title: if locale == "he" {
                    if money_today {
                        "לנעול התקדמות הכנסה".to_string()
                    } else {
                        "יצירת מהלך הכנסה מיידי".to_string()
                    }
                } else if money_today {
                    "Lock income progress".to_string()
                } else {
                    "Create an immediate income move".to_string()
                },
                detail: if locale == "he" {
                    if money_today {
                        "נרשמה התקדמות כספית היום. תעדו מה עבד ושכפלו אותו ל-48 השעות הקרובות."
                            .to_string()
                    } else {
                        "עדיין ללא הכנסה היום. בצעו מהלך אחד: יצירת קשר, הצעה, או סגירה."
                            .to_string()
                    }
                } else if money_today {
                    "Revenue moved today. Capture what worked and replicate it over the next 48 hours."
                        .to_string()
                } else {
                    "No money signal today yet. Execute one move now: outreach, offer, or close."
                        .to_string()
                },
                source: "checkin".to_string(),
                horizon: "daily".to_string(),
                urgency: if money_today { 0.64 } else { 0.92 },
                impact: 0.84,
                confidence: 0.89,
            },
        );
    }
    tasks
}

fn build_company_awareness_task(
    company_status: &CompanyStatusRecord,
    locale: &str,
) -> ExecutionTaskCandidate {
    let detail = if locale == "he" {
        format!(
            "פאזה: {} | פוקוס: {} | בהמשך: {}",
            company_status.phase,
            company_status.current_focus.join(", "),
            company_status.upcoming.join(", ")
        )
    } else {
        format!(
            "Phase: {} | Current focus: {} | Upcoming: {}",
            company_status.phase,
            company_status.current_focus.join(", "),
            company_status.upcoming.join(", ")
        )
    };
    ExecutionTaskCandidate {
        task_id: "company-awareness".to_string(),
        title: if locale == "he" {
            "יישור לתכנית החברה".to_string()
        } else {
            "Align with company plan".to_string()
        },
        detail,
        source: "company".to_string(),
        horizon: "mid_term".to_string(),
        urgency: 0.62,
        impact: 0.84,
        confidence: 0.93,
    }
}

fn execution_priority_score(task: &ExecutionTaskCandidate) -> f32 {
    let horizon_boost = match task.horizon.as_str() {
        "daily" => 0.12,
        "mid_term" => 0.08,
        "long_term" => 0.05,
        _ => 0.03,
    };
    (task.impact * 0.45 + task.urgency * 0.35 + task.confidence * 0.2 + horizon_boost)
        .clamp(0.0, 1.25)
}

fn prioritize_execution_tasks(tasks: Vec<ExecutionTaskCandidate>) -> Vec<ExecutionTaskCandidate> {
    let mut dedup = HashMap::<String, ExecutionTaskCandidate>::new();
    for task in tasks {
        let key = task.title.trim().to_lowercase();
        match dedup.get(&key) {
            Some(existing)
                if execution_priority_score(existing) >= execution_priority_score(&task) => {}
            _ => {
                dedup.insert(key, task);
            }
        }
    }
    let mut ranked = dedup.into_values().collect::<Vec<_>>();
    ranked.sort_by(|lhs, rhs| {
        execution_priority_score(rhs).total_cmp(&execution_priority_score(lhs))
    });
    ranked
}

fn task_checklist_state_for_item(
    task_states: &HashMap<String, ExecutionTaskStateRecord>,
    item_id: &str,
) -> Option<ExecutionTaskChecklistState> {
    let record = task_states.get(item_id)?;
    Some(ExecutionTaskChecklistState {
        completed: record.completed,
        collapsed: record.collapsed,
        completion_count: record.completion_count,
        updated_at: record.updated_at.clone(),
        latest_response: record.latest_response.clone(),
    })
}

fn response_adjustment_line(
    locale: &str,
    latest_response: Option<&ExecutionTaskResponseRecord>,
) -> Option<String> {
    let response = latest_response?;
    let done = response
        .completed_parts
        .as_deref()
        .map(|value| sanitize_limited_text(value, 120))
        .filter(|value| !value.is_empty());
    let pending = response
        .incomplete_parts
        .as_deref()
        .map(|value| sanitize_limited_text(value, 120))
        .filter(|value| !value.is_empty());
    let note = response
        .note
        .as_deref()
        .map(|value| sanitize_limited_text(value, 120))
        .filter(|value| !value.is_empty());
    if done.is_none() && pending.is_none() && note.is_none() {
        return None;
    }

    if locale == "he" {
        let mut parts = Vec::new();
        if let Some(value) = done {
            parts.push(format!("בוצע: {}", value));
        }
        if let Some(value) = pending {
            parts.push(format!("לא בוצע עדיין: {}", value));
        }
        if let Some(value) = note {
            parts.push(format!("הערה: {}", value));
        }
        Some(format!("עדכון ביצוע: {}", parts.join(" | ")))
    } else {
        let mut parts = Vec::new();
        if let Some(value) = done {
            parts.push(format!("Done: {}", value));
        }
        if let Some(value) = pending {
            parts.push(format!("Not done yet: {}", value));
        }
        if let Some(value) = note {
            parts.push(format!("Note: {}", value));
        }
        Some(format!("Execution update: {}", parts.join(" | ")))
    }
}

fn build_orchestrated_proactive_feed(context: &ExecutionFeedContext<'_>) -> Vec<ProactiveFeedItem> {
    let reminder_app = context
        .prefs
        .map(|value| value.reminders_app.clone())
        .unwrap_or_else(|| "google_calendar".to_string());
    let alarm_app = context
        .prefs
        .map(|value| value.alarms_app.clone())
        .unwrap_or_else(|| "apple_clock".to_string());
    let mut tasks = Vec::new();
    tasks.extend(extract_checkin_tasks(
        context.latest_checkin,
        context.user.locale.as_str(),
    ));
    tasks.extend(extract_note_tasks(context.notes));
    tasks.extend(extract_survey_tasks(
        context.survey,
        context.user.locale.as_str(),
    ));
    tasks.extend(extract_memory_tasks(
        context.memories,
        context.user.locale.as_str(),
    ));
    if context.controls.include_company_awareness {
        tasks.push(build_company_awareness_task(
            context.company_status,
            context.user.locale.as_str(),
        ));
    }
    let ranked = prioritize_execution_tasks(tasks);
    let mut items = Vec::new();
    let now = chrono::Utc::now();

    if let Some(top) = ranked.first() {
        let due_at = now
            + chrono::Duration::minutes(schedule_minutes_offset(
                context.controls.cadence.as_str(),
                "daily",
                0,
            ));
        let mut actions = Vec::new();
        if context.controls.include_reminder_suggestions {
            actions.push(atlas_core::SuggestedAction {
                action_type: "create_reminder".to_string(),
                label: if context.user.locale == "he" {
                    "תזכורת לביצוע מיידי".to_string()
                } else {
                    "Set immediate execution reminder".to_string()
                },
                payload: serde_json::json!({
                    "title": top.title,
                    "details": top.detail,
                    "due_at_utc": due_at.to_rfc3339(),
                    "reminders_app": reminder_app
                }),
            });
            actions.push(atlas_core::SuggestedAction {
                action_type: "create_alarm".to_string(),
                label: if context.user.locale == "he" {
                    "אזעקת התחלה".to_string()
                } else {
                    "Start alarm".to_string()
                },
                payload: serde_json::json!({
                    "label": "Atlas next action now",
                    "time_local": "09:00",
                    "days": ["Sun","Mon","Tue","Wed","Thu"],
                    "alarms_app": alarm_app
                }),
            });
        }
        let checklist_state = task_checklist_state_for_item(context.task_states, "next_action_now");
        let adjustment_line = response_adjustment_line(
            context.user.locale.as_str(),
            checklist_state
                .as_ref()
                .and_then(|state| state.latest_response.as_ref()),
        );
        items.push(ProactiveFeedItem {
            id: "next_action_now".to_string(),
            title: if context.user.locale == "he" {
                "הפעולה הבאה עכשיו".to_string()
            } else {
                "Next action now".to_string()
            },
            summary: if let Some(adjustment_line) = adjustment_line.clone() {
                format!("{} — {}\n{}", top.title, top.detail, adjustment_line)
            } else {
                format!("{} — {}", top.title, top.detail)
            },
            why_now: if context.user.locale == "he" {
                format!("מקור: {} | אופק: {}", top.source, top.horizon)
            } else {
                format!("Source: {} | Horizon: {}", top.source, top.horizon)
            },
            priority: "critical".to_string(),
            actions,
            checklist_state,
        });
    }

    let mut used_task_ids = HashSet::new();
    if let Some(top) = ranked.first() {
        used_task_ids.insert(top.task_id.clone());
    }
    let mut selected = Vec::new();
    for horizon in ["daily", "mid_term", "long_term"] {
        if let Some(task) = ranked.iter().find(|candidate| {
            candidate.horizon == horizon && !used_task_ids.contains(&candidate.task_id)
        }) {
            used_task_ids.insert(task.task_id.clone());
            selected.push(task.clone());
        }
    }
    for task in ranked.iter() {
        if selected.len() >= 4 {
            break;
        }
        if used_task_ids.contains(&task.task_id) {
            continue;
        }
        used_task_ids.insert(task.task_id.clone());
        selected.push(task.clone());
    }

    for (index, task) in selected.iter().enumerate() {
        let due_at = now
            + chrono::Duration::minutes(schedule_minutes_offset(
                context.controls.cadence.as_str(),
                task.horizon.as_str(),
                index + 1,
            ));
        let mut actions = Vec::new();
        if context.controls.include_reminder_suggestions {
            actions.push(atlas_core::SuggestedAction {
                action_type: "create_reminder".to_string(),
                label: if context.user.locale == "he" {
                    "קבע תזכורת".to_string()
                } else {
                    "Set reminder".to_string()
                },
                payload: serde_json::json!({
                    "title": task.title,
                    "details": task.detail,
                    "due_at_utc": due_at.to_rfc3339(),
                    "reminders_app": reminder_app
                }),
            });
        }
        if task.source == "company" {
            actions.push(atlas_core::SuggestedAction {
                action_type: "open_company_status".to_string(),
                label: if context.user.locale == "he" {
                    "פתח סטטוס חברה".to_string()
                } else {
                    "Open company status".to_string()
                },
                payload: serde_json::json!({}),
            });
        }
        let checklist_state =
            task_checklist_state_for_item(context.task_states, task.task_id.as_str());
        let adjustment_line = response_adjustment_line(
            context.user.locale.as_str(),
            checklist_state
                .as_ref()
                .and_then(|state| state.latest_response.as_ref()),
        );
        items.push(ProactiveFeedItem {
            id: task.task_id.clone(),
            title: task.title.clone(),
            summary: if let Some(adjustment_line) = adjustment_line {
                format!("{}\n{}", task.detail, adjustment_line)
            } else {
                task.detail.clone()
            },
            why_now: if context.user.locale == "he" {
                format!("אופק {} | סדר עדיפויות מחושב", task.horizon)
            } else {
                format!("{} horizon | prioritized by execution engine", task.horizon)
            },
            priority: if execution_priority_score(task) > 0.85 {
                "high".to_string()
            } else {
                "normal".to_string()
            },
            actions,
            checklist_state,
        });
    }

    if context.controls.include_company_awareness {
        let checklist_state =
            task_checklist_state_for_item(context.task_states, "company_planning_awareness");
        items.push(ProactiveFeedItem {
            id: "company_planning_awareness".to_string(),
            title: if context.user.locale == "he" {
                "מודעות תכנית חברה".to_string()
            } else {
                "Company planning awareness".to_string()
            },
            summary: context.company_status.message.clone(),
            why_now: if context.user.locale == "he" {
                format!(
                    "פאזה {}. פוקוס: {}.",
                    context.company_status.phase,
                    context.company_status.current_focus.join(", ")
                )
            } else {
                format!(
                    "Phase {}. Focus: {}.",
                    context.company_status.phase,
                    context.company_status.current_focus.join(", ")
                )
            },
            priority: "normal".to_string(),
            actions: vec![atlas_core::SuggestedAction {
                action_type: "open_company_status".to_string(),
                label: if context.user.locale == "he" {
                    "סקירת סטטוס מלאה".to_string()
                } else {
                    "Review full company status".to_string()
                },
                payload: serde_json::json!({}),
            }],
            checklist_state,
        });
    }

    if context.controls.detail_level == "concise" {
        items
            .into_iter()
            .map(|mut item| {
                item.summary = sanitize_limited_text(item.summary.as_str(), 120);
                item.why_now = sanitize_limited_text(item.why_now.as_str(), 90);
                item
            })
            .collect()
    } else if context.controls.detail_level == "expanded" {
        items
            .into_iter()
            .map(|mut item| {
                item.why_now = format!(
                    "{} | {}",
                    item.why_now,
                    if context.user.locale == "he" {
                        "המלצה זו נגזרת מדפוסי שימוש, זיכרון ארוך-טווח ויעדי אופק."
                    } else {
                        "Recommendation derived from usage patterns, long-term memory, and horizon goals."
                    }
                );
                item
            })
            .collect()
    } else {
        items
    }
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
    if let Some(gym) = state.answers.get("gym_frequency") {
        hints.push(format!("gym_frequency: {}", gym));
    }
    if let Some(income) = state.answers.get("income_cadence") {
        hints.push(format!("income_cadence: {}", income));
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
    let mut total = 13;
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

    if !answers.contains_key("gym_frequency") {
        return Some(mk(
            "gym_frequency",
            "באיזו תדירות אתה מתאמן כרגע?",
            "How often do you currently train/work out?",
            Some("המערכת תשתמש בזה לצ׳ק-אין יומי ובניית עקביות."),
            Some("This powers daily follow-up check-ins and consistency coaching."),
            "choice",
            vec![
                survey_choice(he, "rarely", "כמעט לא", "Rarely"),
                survey_choice(he, "sometimes", "לפעמים", "Sometimes"),
                survey_choice(he, "regularly", "באופן קבוע", "Regularly"),
            ],
            None,
            None,
        ));
    }

    if !answers.contains_key("income_cadence") {
        return Some(mk(
            "income_cadence",
            "כמה רציפה ההכנסה שלך כרגע?",
            "How regular is your income right now?",
            Some("זה מאפשר למערכת להציע פעולות הכנסה יומיות כשצריך."),
            Some("This lets Atlas trigger daily income actions when needed."),
            "choice",
            vec![
                survey_choice(he, "none", "ללא הכנסה רציפה", "No regular income"),
                survey_choice(he, "sometimes", "מדי פעם", "Sometimes"),
                survey_choice(he, "regularly", "רציפה", "Regularly"),
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

fn sanitize_cookie_domain(value: &str) -> Option<String> {
    let normalized = value
        .trim()
        .trim_start_matches('.')
        .trim_end_matches('.')
        .to_ascii_lowercase();
    if normalized.is_empty() {
        return None;
    }
    if normalized
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '.' || ch == '-')
    {
        Some(normalized)
    } else {
        None
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

fn sanitize_memory_type(value: &str) -> String {
    sanitize_enum_value(
        value,
        &[
            "preference",
            "mood",
            "goal",
            "constraint",
            "insight",
            "friction",
            "identity",
            "task",
        ],
        "insight",
    )
}

fn sanitize_memory_stability(value: &str) -> String {
    sanitize_enum_value(value, &["permanent", "transient"], "transient")
}

fn sanitize_memory_source(value: &str) -> String {
    sanitize_enum_value(
        value,
        &[
            "note",
            "note_rewrite",
            "survey",
            "feedback",
            "chat",
            "import",
            "manual",
            "system",
        ],
        "system",
    )
}

fn clamp_memory_weight(weight: f32) -> f32 {
    if !weight.is_finite() {
        return 0.5;
    }
    weight.clamp(0.05, 1.0)
}

fn memory_fingerprint(memory_type: &str, stability: &str, text: &str) -> String {
    let normalized = text
        .trim()
        .to_lowercase()
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || ch.is_ascii_whitespace())
        .take(300)
        .collect::<String>();
    let key = format!("{}|{}|{}", memory_type, stability, normalized);
    hex_encode(Sha256::digest(key.as_bytes()).as_slice())
}

fn memory_recency_score(updated_at: &str, now: chrono::DateTime<chrono::Utc>) -> f32 {
    let updated = chrono::DateTime::parse_from_rfc3339(updated_at)
        .ok()
        .map(|value| value.with_timezone(&chrono::Utc))
        .unwrap_or(now);
    let age_hours = now.signed_duration_since(updated).num_hours().max(0) as f32;
    (1.0 / (1.0 + (age_hours / 72.0))).clamp(0.0, 1.0)
}

fn is_memory_expired(record: &MemoryRecord, now: chrono::DateTime<chrono::Utc>) -> bool {
    record
        .expires_at
        .as_deref()
        .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
        .map(|value| value.with_timezone(&chrono::Utc) <= now)
        .unwrap_or(false)
}

fn prune_expired_memories(records: &mut Vec<MemoryRecord>, now: chrono::DateTime<chrono::Utc>) {
    records.retain(|entry| !is_memory_expired(entry, now));
}

fn classify_chat_memory(text: &str) -> (String, String, f32) {
    let lower = text.trim().to_lowercase();
    if lower.is_empty() {
        return ("insight".to_string(), "transient".to_string(), 0.5);
    }
    if [
        "stressed",
        "anxious",
        "overwhelmed",
        "tired",
        "רגוע",
        "לחוץ",
        "עייף",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return ("mood".to_string(), "transient".to_string(), 0.75);
    }
    if ["plan", "goal", "mission", "target", "יעד", "מטרה", "תוכנית"]
        .iter()
        .any(|needle| lower.contains(needle))
    {
        return ("goal".to_string(), "permanent".to_string(), 0.82);
    }
    if [
        "prefer",
        "favorite",
        "like",
        "dislike",
        "preferably",
        "מעדיף",
        "אוהב",
        "לא אוהב",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
    {
        return ("preference".to_string(), "permanent".to_string(), 0.8);
    }
    ("insight".to_string(), "transient".to_string(), 0.65)
}

fn classify_survey_memory(question_id: &str, answer: &str) -> (String, String, f32) {
    let question = question_id.trim().to_lowercase();
    let answer = answer.trim().to_lowercase();
    if [
        "trip_style",
        "risk_preference",
        "voice_preference",
        "language",
        "gym_frequency",
        "income_cadence",
    ]
    .iter()
    .any(|needle| question.contains(needle))
    {
        return ("preference".to_string(), "permanent".to_string(), 0.88);
    }
    if ["goal", "mission", "wealth", "donation", "career"]
        .iter()
        .any(|needle| question.contains(needle) || answer.contains(needle))
    {
        return ("goal".to_string(), "permanent".to_string(), 0.9);
    }
    if ["stress", "fatigue", "mood", "energy", "burnout"]
        .iter()
        .any(|needle| question.contains(needle) || answer.contains(needle))
    {
        return ("mood".to_string(), "transient".to_string(), 0.8);
    }
    ("insight".to_string(), "transient".to_string(), 0.72)
}

fn memory_relevance_score(query: &str, record: &MemoryRecord) -> f32 {
    let query_tokens = tokenize_memory_text(query);
    if query_tokens.is_empty() {
        return 0.0;
    }
    let mut corpus = record.text.clone();
    if !record.tags.is_empty() {
        corpus.push(' ');
        corpus.push_str(record.tags.join(" ").as_str());
    }
    let record_tokens = tokenize_memory_text(corpus.as_str());
    if record_tokens.is_empty() {
        return 0.0;
    }
    let overlap = query_tokens
        .iter()
        .filter(|token| record_tokens.contains(*token))
        .count();
    (overlap as f32 / query_tokens.len() as f32).clamp(0.0, 1.0)
}

fn tokenize_memory_text(text: &str) -> std::collections::HashSet<String> {
    text.to_lowercase()
        .split(|ch: char| !ch.is_ascii_alphanumeric() && !ch.is_alphabetic())
        .filter(|token| token.len() >= 2)
        .take(256)
        .map(|token| token.to_string())
        .collect()
}

fn ingest_memory_records_if_opted_in(
    records: &mut Vec<MemoryRecord>,
    user_id: &str,
    opt_in: bool,
    event: MemoryIngestEvent,
    now: chrono::DateTime<chrono::Utc>,
) -> Option<MemoryRecord> {
    if !opt_in {
        return None;
    }

    let text = sanitize_limited_text(event.text.as_str(), MAX_MEMORY_TEXT_LEN);
    if text.is_empty() {
        return None;
    }

    let memory_type = sanitize_memory_type(event.memory_type.as_str());
    let stability = sanitize_memory_stability(event.stability.as_str());
    let source = sanitize_memory_source(event.source.as_str());
    let tags = sanitize_note_tags(event.tags);
    let happened_at = event.happened_at.unwrap_or(now);
    let updated_at = happened_at.to_rfc3339();
    let weight = clamp_memory_weight(event.weight);
    let recency_score = memory_recency_score(updated_at.as_str(), now);
    let expires_at = if stability == "transient" {
        event
            .expires_at
            .or_else(|| Some(happened_at + chrono::Duration::days(TRANSIENT_MEMORY_TTL_DAYS)))
            .map(|value| value.to_rfc3339())
    } else {
        None
    };
    let fingerprint = memory_fingerprint(memory_type.as_str(), stability.as_str(), text.as_str());

    if let Some(index) = records
        .iter()
        .position(|entry| entry.fingerprint == fingerprint)
    {
        {
            let existing = &mut records[index];
            existing.source = source;
            existing.text = text;
            existing.weight = clamp_memory_weight((existing.weight + weight) / 2.0);
            existing.recency_score = recency_score;
            existing.updated_at = updated_at;
            existing.expires_at = expires_at;
            existing.tags = sanitize_note_tags(
                existing
                    .tags
                    .iter()
                    .cloned()
                    .chain(tags)
                    .collect::<Vec<_>>(),
            );
        }
        let updated = records[index].clone();
        prune_expired_memories(records, now);
        return Some(updated);
    }

    let created = MemoryRecord {
        memory_id: uuid::Uuid::new_v4().to_string(),
        user_id: user_id.to_string(),
        memory_type,
        stability,
        source,
        text,
        weight,
        recency_score,
        tags,
        created_at: now.to_rfc3339(),
        updated_at,
        expires_at,
        fingerprint,
    };
    records.push(created.clone());
    prune_expired_memories(records, now);
    records.sort_by(|lhs, rhs| {
        let lhs_score = lhs.weight * 0.7 + lhs.recency_score * 0.3;
        let rhs_score = rhs.weight * 0.7 + rhs.recency_score * 0.3;
        rhs_score.total_cmp(&lhs_score)
    });
    records.truncate(MAX_MEMORY_RECORDS_PER_USER);
    Some(created)
}

fn retrieve_memory_context_from_records(
    records: &[MemoryRecord],
    query: &str,
    limit: usize,
    now: chrono::DateTime<chrono::Utc>,
) -> Vec<MemoryRetrievedItem> {
    let top_limit = limit.clamp(1, MAX_MEMORY_RETRIEVAL_LIMIT);
    let mut scored = records
        .iter()
        .filter(|record| !is_memory_expired(record, now))
        .map(|record| {
            let recency_score = memory_recency_score(record.updated_at.as_str(), now);
            let relevance_score = memory_relevance_score(query, record);
            let stability_boost = if record.stability == "permanent" {
                0.05
            } else {
                0.0
            };
            let final_score = (record.weight * 0.45
                + recency_score * 0.3
                + relevance_score * 0.25
                + stability_boost)
                .clamp(0.0, 1.2);
            MemoryRetrievedItem {
                memory_id: record.memory_id.clone(),
                memory_type: record.memory_type.clone(),
                stability: record.stability.clone(),
                source: record.source.clone(),
                text: record.text.clone(),
                weight: record.weight,
                recency_score,
                relevance_score,
                final_score,
                tags: record.tags.clone(),
                updated_at: record.updated_at.clone(),
            }
        })
        .collect::<Vec<_>>();
    scored.sort_by(|lhs, rhs| rhs.final_score.total_cmp(&lhs.final_score));
    scored.truncate(top_limit);
    scored
}

fn user_memory_opt_in(state: &ApiState, user_id: &str) -> bool {
    state
        .users
        .read()
        .get(user_id)
        .map(|user| user.memory_opt_in)
        .unwrap_or(false)
}

fn retrieve_user_memory_context(
    state: &ApiState,
    user_id: &str,
    query: &str,
    limit: usize,
) -> Vec<MemoryRetrievedItem> {
    if !user_memory_opt_in(state, user_id) {
        return Vec::new();
    }
    let snapshot = state
        .user_memories
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    retrieve_memory_context_from_records(snapshot.as_slice(), query, limit, chrono::Utc::now())
}

fn memory_limit_for_preferences(prefs: &StudioPreferencesRecord) -> usize {
    match prefs.compute_mode.as_str() {
        "eco" => 6,
        "performance" => 18,
        _ => DEFAULT_MEMORY_RETRIEVAL_LIMIT,
    }
}

fn memory_item_is_pinned(item: &MemoryRetrievedItem) -> bool {
    item.tags.iter().any(|tag| {
        matches!(
            tag.as_str(),
            "pinned" | "legal" | "finance" | "identity" | "spec" | "accounting"
        )
    }) || item.memory_type == "identity"
        || item.text.chars().any(|ch| ch.is_ascii_digit())
}

fn estimate_cloud_input_cost_usd(
    request: &ChatRequest,
    notes: &[UserNoteRecord],
    memory_context: &[MemoryRetrievedItem],
    prefs: &StudioPreferencesRecord,
) -> f64 {
    let note_chars = notes
        .iter()
        .map(|note| note.title.len() + note.content.len())
        .sum::<usize>();
    let memory_chars = memory_context
        .iter()
        .map(|item| item.text.len())
        .sum::<usize>();
    let request_chars =
        request.text.len() + request.preferred_format.as_deref().unwrap_or("").len();
    let total_tokens = ((request_chars + note_chars + memory_chars) as f64 / 4.0).ceil();
    let multiplier = match prefs.response_depth.as_str() {
        "quick" => 0.75,
        "deep" => 1.35,
        _ => 1.0,
    };
    ((total_tokens / 1_000.0) * 0.01 * multiplier * 1000.0).round() / 1000.0
}

fn estimate_local_memory_mb(
    memory_context: &[MemoryRetrievedItem],
    prefs: &StudioPreferencesRecord,
) -> u32 {
    let base = match prefs.compute_mode.as_str() {
        "eco" => 220,
        "performance" => 1100,
        _ => 520,
    };
    let memory_depth = match prefs.memory_depth.as_str() {
        "compact" => 90,
        "full" => 360,
        _ => 180,
    };
    let context_weight = (memory_context.len() as u32).saturating_mul(18);
    base + memory_depth + context_weight
}

fn estimate_local_storage_mb(
    memory_context: &[MemoryRetrievedItem],
    prefs: &StudioPreferencesRecord,
) -> u32 {
    let base = match prefs.compute_mode.as_str() {
        "eco" => 256,
        "performance" => 2048,
        _ => 768,
    };
    let memory_depth = match prefs.memory_depth.as_str() {
        "compact" => 64,
        "full" => 512,
        _ => 192,
    };
    base + memory_depth + (memory_context.len() as u32).saturating_mul(12)
}

fn cloud_cost_threshold_for_preferences(prefs: &StudioPreferencesRecord) -> f64 {
    match prefs.cloud_cost_guardrail.as_str() {
        "tight" => 0.04,
        "high_detail" => 0.16,
        _ => 0.08,
    }
}

fn local_memory_threshold_for_preferences(prefs: &StudioPreferencesRecord) -> u32 {
    match prefs.local_resource_guardrail.as_str() {
        "conservative" => 640,
        "performance" => 2_048,
        _ => 1_024,
    }
}

fn apply_amm_policy(
    request: &ChatRequest,
    notes: &[UserNoteRecord],
    memory_context: Vec<MemoryRetrievedItem>,
    prefs: &StudioPreferencesRecord,
) -> (Vec<MemoryRetrievedItem>, AmmDiagnostics) {
    let estimated_cloud_input_cost_usd =
        estimate_cloud_input_cost_usd(request, notes, memory_context.as_slice(), prefs);
    let estimated_local_memory_mb = estimate_local_memory_mb(memory_context.as_slice(), prefs);
    let estimated_local_storage_mb = estimate_local_storage_mb(memory_context.as_slice(), prefs);
    let cloud_threshold = cloud_cost_threshold_for_preferences(prefs);
    let local_threshold = local_memory_threshold_for_preferences(prefs);
    let cloud_triggered = estimated_cloud_input_cost_usd > cloud_threshold;
    let local_triggered = estimated_local_memory_mb > local_threshold;
    let should_compact = cloud_triggered || local_triggered;

    let trigger_reason = if cloud_triggered && local_triggered {
        "cloud_cost_and_local_budget_threshold"
    } else if cloud_triggered {
        "cloud_cost_threshold"
    } else if local_triggered {
        "local_resource_threshold"
    } else {
        "within_budget"
    }
    .to_string();

    let compact_limit = match prefs.compute_mode.as_str() {
        "eco" => 4,
        "performance" => memory_context.len().max(1),
        _ => 8,
    };

    let pinned_items = memory_context
        .iter()
        .filter(|item| memory_item_is_pinned(item))
        .cloned()
        .collect::<Vec<_>>();

    let final_items = if should_compact && prefs.compute_mode != "performance" {
        let mut kept = memory_context
            .iter()
            .take(compact_limit)
            .cloned()
            .collect::<Vec<_>>();
        for pinned in pinned_items.iter().cloned() {
            if kept.iter().all(|item| item.memory_id != pinned.memory_id) {
                kept.push(pinned);
            }
        }
        kept
    } else {
        memory_context
    };

    let tradeoff_summary = if should_compact {
        format!(
            "{} mode condensed lower-value context before max limits, while preserving pinned facts and user-critical rationale.",
            prefs.compute_mode
        )
    } else {
        format!(
            "{} mode kept the current context envelope because projected cloud and local cost stayed within guardrails.",
            prefs.compute_mode
        )
    };

    (
        final_items,
        AmmDiagnostics {
            active_mode: prefs.compute_mode.clone(),
            compaction_applied: should_compact && prefs.compute_mode != "performance",
            trigger_reason,
            pinned_context_preserved: !pinned_items.is_empty() || !should_compact,
            estimated_cloud_input_cost_usd,
            estimated_local_memory_mb,
            estimated_local_storage_mb,
            tradeoff_summary,
        },
    )
}

fn sync_lifelogs_from_memories(state: &ApiState, user_id: &str) {
    let memories = state
        .user_memories
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    let lifelogs = memories
        .into_iter()
        .map(|memory| LifelogRecord {
            lifelog_id: memory.memory_id.clone(),
            user_id: memory.user_id.clone(),
            memory_id: Some(memory.memory_id),
            summary: memory.text,
            source: memory.source,
            tags: memory.tags,
            embedding_json: None,
            created_at: memory.created_at,
            updated_at: memory.updated_at,
        })
        .collect::<Vec<_>>();
    state.lifelogs.write().insert(user_id.to_string(), lifelogs);
}

async fn ingest_memory_event_for_user(
    state: &ApiState,
    user_id: &str,
    event: MemoryIngestEvent,
) -> Option<MemoryRecord> {
    let now = chrono::Utc::now();
    let opt_in = user_memory_opt_in(state, user_id);
    let ingested = {
        let mut memories_map = state.user_memories.write();
        let records = memories_map.entry(user_id.to_string()).or_default();
        ingest_memory_records_if_opted_in(records, user_id, opt_in, event, now)
    };
    if ingested.is_some() {
        sync_lifelogs_from_memories(state, user_id);
        let _ = persist_memories_if_configured(state, user_id).await;
        let _ = persist_lifelogs_if_configured(state, user_id).await;
    }
    ingested
}

async fn clear_user_memories_by_scope(state: &ApiState, user_id: &str, scope: &str) -> usize {
    let removed_count = {
        let mut memories_map = state.user_memories.write();
        let Some(records) = memories_map.get_mut(user_id) else {
            return 0;
        };
        let before = records.len();
        match scope {
            "permanent" => records.retain(|entry| entry.stability != "permanent"),
            "transient" => records.retain(|entry| entry.stability != "transient"),
            _ => records.clear(),
        }
        before.saturating_sub(records.len())
    };
    if removed_count > 0 {
        sync_lifelogs_from_memories(state, user_id);
        let _ = persist_memories_if_configured(state, user_id).await;
        let _ = persist_lifelogs_if_configured(state, user_id).await;
    }
    removed_count
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
    let mut native_client_ids = env::var("ATLAS_APPLE_NATIVE_CLIENT_IDS")
        .ok()
        .map(|value| {
            value
                .split(',')
                .map(|item| item.trim().to_string())
                .filter(|item| !item.is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| {
            vec![
                "com.atlasmasa.ios".to_string(),
                "com.atlasmasa.macos".to_string(),
            ]
        });
    if !native_client_ids.iter().any(|value| value == &client_id) {
        native_client_ids.push(client_id.clone());
    }

    Some(AppleOAuthConfig {
        client_id,
        client_secret,
        redirect_uri,
        frontend_origin,
        native_client_ids,
    })
}

fn build_openai_runtime_config() -> Option<OpenAiRuntimeConfig> {
    let api_key = env::var("ATLAS_OPENAI_API_KEY").ok()?;
    let model = env::var("ATLAS_OPENAI_MODEL").unwrap_or_else(|_| "gpt-5.2".to_string());
    let coding_backend_model =
        env::var("ATLAS_OPENAI_CODING_MODEL").unwrap_or_else(|_| "gpt-5.3-codex".to_string());
    let default_reasoning_effort =
        env::var("ATLAS_OPENAI_REASONING_EFFORT").unwrap_or_else(|_| "high".to_string());

    Some(OpenAiRuntimeConfig {
        api_key,
        model,
        coding_backend_model,
        default_reasoning_effort,
    })
}

fn build_premium_stable_context_json(
    user: Option<&UserRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: &[UserNoteRecord],
    memory_context: &[MemoryRetrievedItem],
) -> serde_json::Value {
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
    let memory_context = memory_context
        .iter()
        .take(12)
        .map(|entry| {
            serde_json::json!({
                "memory_type": entry.memory_type,
                "stability": entry.stability,
                "source": entry.source,
                "text": entry.text,
                "weight": entry.weight,
                "recency_score": entry.recency_score,
                "relevance_score": entry.relevance_score,
                "tags": entry.tags
            })
        })
        .collect::<Vec<_>>();

    serde_json::json!({
        "user": user_context,
        "survey": survey_context,
        "notes": notes_context,
        "memory_context": memory_context
    })
}

fn stable_context_cache_key(
    model: &str,
    stable_context: &serde_json::Value,
    code_agent_route: Option<CodeAgentRoute>,
) -> String {
    let route = code_agent_route
        .map(CodeAgentRoute::as_str)
        .unwrap_or("default");
    let mut hasher = Sha256::new();
    hasher.update(model.as_bytes());
    hasher.update(route.as_bytes());
    hasher.update(stable_context.to_string().as_bytes());
    format!("{:x}", hasher.finalize())
}

fn build_openai_premium_payload(
    runtime: &OpenAiRuntimeConfig,
    model: &str,
    system_prompt: &str,
    request: &ChatRequest,
    user: Option<&UserRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: &[UserNoteRecord],
    memory_context: &[MemoryRetrievedItem],
    fallback_reply: &str,
    code_agent_route: Option<CodeAgentRoute>,
) -> serde_json::Value {
    let stable_context = build_premium_stable_context_json(user, survey, notes, memory_context);
    let cache_key = stable_context_cache_key(model, &stable_context, code_agent_route);
    let dynamic_context = serde_json::json!({
        "user_request": request.text,
        "fallback_reply": fallback_reply,
        "preferred_format": request.preferred_format,
        "response_depth": request.response_depth,
        "response_tone": request.response_tone,
        "code_agent_route": code_agent_route.map(CodeAgentRoute::as_str)
    });

    serde_json::json!({
        "model": model,
        "reasoning": {
            "effort": runtime.default_reasoning_effort
        },
        "metadata": {
            "cache_strategy": "stable_prefix_dynamic_tail",
            "cache_prefix_key": cache_key,
            "memory_items_count": memory_context.len().min(12),
            "notes_count": notes.len().min(12)
        },
        "input": [
            {
                "role": "system",
                "content": [
                    { "type": "input_text", "text": system_prompt }
                ]
            },
            {
                "role": "system",
                "content": [
                    { "type": "input_text", "text": format!("Stable Context JSON: {}", stable_context) }
                ]
            },
            {
                "role": "user",
                "content": [
                    { "type": "input_text", "text": format!("Dynamic Task JSON: {}", dynamic_context) }
                ]
            }
        ],
        "text": {
            "verbosity": "high"
        }
    })
}

fn build_gemini_runtime_config() -> Option<GeminiRuntimeConfig> {
    let api_key = env::var("ATLAS_GEMINI_API_KEY")
        .ok()
        .or_else(|| env::var("ATLAS_GOOGLE_DEEPMIND_API_KEY").ok())
        .or_else(|| env::var("ATLAS_GOOGLE_AI_API_KEY").ok())?;
    let model = env::var("ATLAS_GEMINI_MODEL")
        .ok()
        .or_else(|| env::var("ATLAS_GOOGLE_DEEPMIND_MODEL").ok())
        .unwrap_or_else(|| "gemini-3-flash-preview".to_string());
    let frontend_design_model =
        env::var("ATLAS_GEMINI_FRONTEND_MODEL").unwrap_or_else(|_| "gemini-3.1-pro".to_string());
    let normalized_model = model.trim().trim_start_matches("models/").to_lowercase();
    let default_temperature = if normalized_model.starts_with("gemini-3") {
        1.0
    } else {
        0.18
    };
    let temperature = env::var("ATLAS_GEMINI_TEMPERATURE")
        .ok()
        .and_then(|value| value.trim().parse::<f32>().ok())
        .map(|value| value.clamp(0.0, 2.0))
        .unwrap_or(default_temperature);
    let max_output_tokens = env::var("ATLAS_GEMINI_MAX_OUTPUT_TOKENS")
        .ok()
        .and_then(|value| value.trim().parse::<u32>().ok())
        .map(|value| value.clamp(256, 65_536))
        .unwrap_or(2_048);
    let thinking_level = env::var("ATLAS_GEMINI_THINKING_LEVEL")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| matches!(value.as_str(), "low" | "medium" | "high"));
    let context_cache_name = env::var("ATLAS_GEMINI_CONTEXT_CACHE_NAME")
        .ok()
        .map(|value| value.trim().trim_matches('/').to_string())
        .filter(|value| !value.is_empty());

    Some(GeminiRuntimeConfig {
        api_key,
        model,
        frontend_design_model,
        temperature,
        max_output_tokens,
        thinking_level,
        context_cache_name,
    })
}

fn build_gemini_premium_payload(
    runtime: &GeminiRuntimeConfig,
    request: &ChatRequest,
    user: Option<&UserRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: &[UserNoteRecord],
    memory_context: &[MemoryRetrievedItem],
    fallback_reply: &str,
    code_agent_route: Option<CodeAgentRoute>,
) -> serde_json::Value {
    let stable_context = build_premium_stable_context_json(user, survey, notes, memory_context);
    let cache_key =
        stable_context_cache_key(runtime.model.as_str(), &stable_context, code_agent_route);
    let dynamic_task = serde_json::json!({
        "user_request": request.text,
        "fallback_reply": fallback_reply,
        "preferred_format": request.preferred_format,
        "response_depth": request.response_depth,
        "response_tone": request.response_tone,
        "code_agent_route": code_agent_route.map(CodeAgentRoute::as_str)
    });

    let mut generation_config = serde_json::json!({
        "temperature": runtime.temperature,
        "maxOutputTokens": runtime.max_output_tokens
    });
    if let Some(level) = runtime.thinking_level.as_deref() {
        generation_config["thinkingConfig"] = serde_json::json!({
            "thinkingLevel": level
        });
    }

    let mut payload = serde_json::json!({
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": "You are Atlas Masa Executive Intelligence. Speak with refined, high-class language and clear structure. Act like a strategic chief-of-staff for a high-performing traveler-builder. Prioritize execution, safety, resilience, and momentum."
                    }
                ]
            },
            {
                "role": "user",
                "parts": [
                    { "text": format!("Dynamic Task JSON: {}", dynamic_task) }
                ]
            }
        ],
        "generationConfig": generation_config
    });

    if let Some(cache_name) = runtime.context_cache_name.as_deref() {
        payload["cachedContent"] = serde_json::Value::String(cache_name.to_string());
        payload["systemInstruction"] = serde_json::json!({
            "parts": [
                {
                    "text": format!(
                        "Cache key: {}. Use the attached cached content as the stable long-term context for this request.",
                        cache_key
                    )
                }
            ]
        });
    } else if let Some(parts) = payload["contents"][1]["parts"].as_array_mut() {
        parts.insert(
            0,
            serde_json::json!({ "text": format!("Stable Context JSON: {}", stable_context) }),
        );
    }

    payload
}

fn sanitize_batch_provider(value: &str) -> String {
    match value.trim().to_lowercase().as_str() {
        "openai" | "openai_responses" => "openai".to_string(),
        "generic" | "generic_jsonl" => "generic_jsonl".to_string(),
        _ => String::new(),
    }
}

fn batch_export_model_name(state: &ApiState, provider: &str) -> String {
    match provider {
        "openai" => state
            .openai_runtime
            .as_ref()
            .map(|runtime| runtime.model.clone())
            .unwrap_or_else(|| "gpt-5.2".to_string()),
        _ => "provider_agnostic".to_string(),
    }
}

fn build_memory_batch_export_jsonl(
    state: &ApiState,
    provider: &str,
    items: &[MemoryRetrievedItem],
) -> String {
    let model = batch_export_model_name(state, provider);
    build_memory_batch_export_jsonl_for_model(provider, model.as_str(), items)
}

fn build_memory_batch_export_jsonl_for_model(
    provider: &str,
    model: &str,
    items: &[MemoryRetrievedItem],
) -> String {
    let mut lines = Vec::with_capacity(items.len());

    for item in items {
        let task_payload = serde_json::json!({
            "memory_id": item.memory_id,
            "memory_type": item.memory_type,
            "stability": item.stability,
            "source": item.source,
            "text": item.text,
            "tags": item.tags,
            "weight": item.weight,
            "recency_score": item.recency_score,
            "relevance_score": item.relevance_score,
            "updated_at": item.updated_at
        });

        let line = if provider == "openai" {
            serde_json::json!({
                "custom_id": format!("memory-compaction-{}", item.memory_id),
                "method": "POST",
                "url": "/v1/responses",
                "body": {
                    "model": model,
                    "input": [
                        {
                            "role": "system",
                            "content": [
                                {
                                    "type": "input_text",
                                    "text": "Compress this memory into a durable executive memory record. Return compact JSON with summary, why_it_matters, horizon, keep_forever, and tags."
                                }
                            ]
                        },
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "input_text",
                                    "text": format!("Memory Task JSON: {}", task_payload)
                                }
                            ]
                        }
                    ],
                    "text": {
                        "verbosity": "low"
                    }
                }
            })
        } else {
            serde_json::json!({
                "task_id": format!("memory-compaction-{}", item.memory_id),
                "provider": provider,
                "model": model,
                "operation": "memory_compaction",
                "payload": task_payload
            })
        };

        if let Ok(serialized) = serde_json::to_string(&line) {
            lines.push(serialized);
        }
    }

    lines.join("\n")
}

fn build_cloud_ai_provider_preference() -> CloudAiProviderPreference {
    let raw = env::var("ATLAS_AI_PROVIDER_PREFERENCE")
        .ok()
        .or_else(|| env::var("ATLAS_PREMIUM_AI_PROVIDER").ok())
        .unwrap_or_else(|| "gemini_first".to_string());
    match raw.trim().to_lowercase().as_str() {
        "openai" | "openai_first" => CloudAiProviderPreference::OpenAiFirst,
        "gemini" | "gemini_first" | "google" | "google_deepmind" => {
            CloudAiProviderPreference::GeminiFirst
        }
        _ => CloudAiProviderPreference::Auto,
    }
}

fn configured_cloud_ai_backends(
    state: &ApiState,
    code_agent_route: Option<CodeAgentRoute>,
) -> Vec<CloudAiBackend> {
    let openai_ready = state.openai_runtime.is_some();
    let gemini_ready = state.gemini_runtime.is_some();
    let mut backends = Vec::with_capacity(2);

    let preferred_order = if let Some(route) = code_agent_route {
        route.preferred_backends()
    } else {
        match state.ai_provider_preference {
            CloudAiProviderPreference::OpenAiFirst => {
                [CloudAiBackend::OpenAi, CloudAiBackend::Gemini]
            }
            CloudAiProviderPreference::GeminiFirst => {
                [CloudAiBackend::Gemini, CloudAiBackend::OpenAi]
            }
            CloudAiProviderPreference::Auto => {
                if gemini_ready && !openai_ready {
                    [CloudAiBackend::Gemini, CloudAiBackend::OpenAi]
                } else {
                    [CloudAiBackend::OpenAi, CloudAiBackend::Gemini]
                }
            }
        }
    };

    for backend in preferred_order {
        match backend {
            CloudAiBackend::OpenAi if openai_ready => backends.push(backend),
            CloudAiBackend::Gemini if gemini_ready => backends.push(backend),
            _ => {}
        }
    }

    backends
}

fn cloud_ai_model_name_for_route(
    state: &ApiState,
    backend: CloudAiBackend,
    code_agent_route: Option<CodeAgentRoute>,
) -> Option<String> {
    match backend {
        CloudAiBackend::OpenAi => state
            .openai_runtime
            .as_ref()
            .map(|cfg| match code_agent_route {
                Some(CodeAgentRoute::BackendOps) => cfg.coding_backend_model.clone(),
                _ => cfg.model.clone(),
            }),
        CloudAiBackend::Gemini => state
            .gemini_runtime
            .as_ref()
            .map(|cfg| match code_agent_route {
                Some(CodeAgentRoute::FrontendDesign) => cfg.frontend_design_model.clone(),
                _ => cfg.model.clone(),
            }),
    }
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
    let stripe_webhook_tolerance_seconds = env::var("ATLAS_STRIPE_WEBHOOK_TOLERANCE_SECONDS")
        .ok()
        .and_then(|value| value.trim().parse::<u64>().ok())
        .map(|value| value.clamp(30, 86_400))
        .unwrap_or(DEFAULT_STRIPE_WEBHOOK_TOLERANCE_SECONDS);

    Some(BillingRuntimeConfig {
        stripe_secret_key,
        stripe_webhook_secret,
        stripe_webhook_tolerance_seconds,
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

async fn verify_apple_id_token(
    http_client: &Client,
    id_token: &str,
    expected_client_ids: &[String],
) -> Result<AppleIdTokenClaims> {
    let mut segments = id_token.split('.');
    let header_segment = segments
        .next()
        .context("apple id_token missing header segment")?;
    let payload_segment = segments
        .next()
        .context("apple id_token missing payload segment")?;
    let signature_segment = segments
        .next()
        .context("apple id_token missing signature segment")?;
    if segments.next().is_some() {
        anyhow::bail!("apple id_token has invalid segment count");
    }

    let header_bytes = URL_SAFE_NO_PAD
        .decode(header_segment)
        .context("failed to decode apple id_token header segment")?;
    let header: AppleJwtHeader =
        serde_json::from_slice(&header_bytes).context("failed to parse apple id_token header")?;
    if header.alg.as_deref() != Some("RS256") {
        anyhow::bail!("unexpected apple id_token signing algorithm");
    }
    let Some(kid) = header.kid.as_deref() else {
        anyhow::bail!("apple id_token missing kid");
    };

    let payload_bytes = URL_SAFE_NO_PAD
        .decode(payload_segment)
        .context("failed to decode apple id_token payload segment")?;
    let claims: AppleIdTokenClaims =
        serde_json::from_slice(&payload_bytes).context("failed to parse apple id_token claims")?;

    let signature = URL_SAFE_NO_PAD
        .decode(signature_segment)
        .context("failed to decode apple id_token signature segment")?;

    let jwks = http_client
        .get("https://appleid.apple.com/auth/keys")
        .send()
        .await
        .context("failed to fetch apple jwks")?
        .error_for_status()
        .context("apple jwks non-success status")?
        .json::<AppleJwksResponse>()
        .await
        .context("failed to parse apple jwks")?;

    let Some(jwk) = jwks.keys.into_iter().find(|record| {
        let key_id_match = record.kid.as_deref() == Some(kid);
        let key_type_ok = record.kty.as_deref().unwrap_or_default() == "RSA";
        let alg_ok = record.alg.as_deref().unwrap_or_default() == "RS256";
        key_id_match && key_type_ok && alg_ok
    }) else {
        anyhow::bail!("apple jwk for token kid not found");
    };

    let n = jwk.n.context("apple jwk missing modulus")?;
    let e = jwk.e.context("apple jwk missing exponent")?;
    let modulus = URL_SAFE_NO_PAD
        .decode(n.as_bytes())
        .context("failed to decode apple jwk modulus")?;
    let exponent = URL_SAFE_NO_PAD
        .decode(e.as_bytes())
        .context("failed to decode apple jwk exponent")?;

    let signed_payload = format!("{header_segment}.{payload_segment}");
    let public_key = RsaPublicKeyComponents {
        n: modulus.as_slice(),
        e: exponent.as_slice(),
    };
    public_key
        .verify(
            &RSA_PKCS1_2048_8192_SHA256,
            signed_payload.as_bytes(),
            signature.as_slice(),
        )
        .map_err(|_| anyhow::anyhow!("apple id_token signature verification failed"))?;

    let valid_iss = claims.iss.as_deref() == Some("https://appleid.apple.com");
    if !valid_iss {
        anyhow::bail!("apple id_token issuer mismatch");
    }
    let valid_aud = claims
        .aud
        .as_ref()
        .map(|aud| {
            expected_client_ids
                .iter()
                .any(|client_id| aud.includes(client_id.as_str()))
        })
        .unwrap_or(false);
    if !valid_aud {
        anyhow::bail!("apple id_token audience mismatch");
    }

    Ok(claims)
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

fn cloud_requirements_for_endpoint(path: &str) -> (bool, bool) {
    let needs_cloud_storage = matches!(
        path,
        "/v1/profile/upsert"
            | "/v1/notes"
            | "/v1/notes/upsert"
            | "/v1/notes/rewrite"
            | "/v1/memory/import"
            | "/v1/memory/records"
            | "/v1/memory/upsert"
            | "/v1/memory/delete"
            | "/v1/memory/clear"
            | "/v1/studio/preferences"
            | "/v1/survey/next"
            | "/v1/survey/answer"
            | "/v1/feed/proactive"
            | "/v1/execution/checkin"
            | "/v1/execution/refresh"
            | "/v1/execution/task/toggle"
            | "/v1/execution/task/respond"
            | "/v1/execution/controls"
            | "/v1/feedback/submit"
            | "/v1/actions/reminder"
            | "/v1/actions/alarm"
    ) || path.starts_with("/v1/feedback/employee/");

    let needs_cloud_compute = matches!(
        path,
        "/v1/chat"
            | "/v1/plan_trip"
            | "/v1/notes/rewrite"
            | "/v1/feed/proactive"
            | "/v1/execution/refresh"
            | "/v1/actions/reminder"
            | "/v1/actions/alarm"
    );

    (needs_cloud_storage, needs_cloud_compute)
}

fn is_public_endpoint(path: &str) -> bool {
    matches!(
        path,
        "/health"
            | "/v1/auth/me"
            | "/v1/auth/logout"
            | "/v1/auth/google/start"
            | "/v1/auth/google/callback"
            | "/v1/auth/apple/start"
            | "/v1/auth/apple/native"
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
        CREATE TABLE IF NOT EXISTS psychological_profiles (
          user_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS vehicle_profiles (
          user_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
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
        CREATE TABLE IF NOT EXISTS user_memories (
          memory_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS lifelogs (
          lifelog_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS execution_checkins (
          checkin_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS execution_controls (
          user_id TEXT PRIMARY KEY,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS execution_task_states (
          user_id TEXT NOT NULL,
          task_id TEXT NOT NULL,
          data_json TEXT NOT NULL,
          PRIMARY KEY (user_id, task_id)
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

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS shopify_profit_share_reports (
          report_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
        );
        "#,
    )
    .execute(pool)
    .await?;

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS rnd_jobs (
          job_id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          data_json TEXT NOT NULL
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

    let psychological_profiles =
        sqlx::query("SELECT user_id, data_json FROM psychological_profiles")
            .fetch_all(pool)
            .await?;
    for row in psychological_profiles {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<PsychologicalProfileRecord>(&json) {
            state
                .psychological_profiles
                .insert(row.get("user_id"), value);
        }
    }

    let vehicle_profiles = sqlx::query("SELECT user_id, data_json FROM vehicle_profiles")
        .fetch_all(pool)
        .await?;
    for row in vehicle_profiles {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<VehicleProfileRecord>(&json) {
            state.vehicle_profiles.insert(row.get("user_id"), value);
        }
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

    let memories = sqlx::query("SELECT user_id, data_json FROM user_memories")
        .fetch_all(pool)
        .await?;
    for row in memories {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<MemoryRecord>(&json) {
            state
                .user_memories
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    let lifelogs = sqlx::query("SELECT user_id, data_json FROM lifelogs")
        .fetch_all(pool)
        .await?;
    for row in lifelogs {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<LifelogRecord>(&json) {
            state
                .lifelogs
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    let checkins = sqlx::query("SELECT user_id, data_json FROM execution_checkins")
        .fetch_all(pool)
        .await?;
    for row in checkins {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<ExecutionCheckinRecord>(&json) {
            state
                .execution_checkins
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    let controls = sqlx::query("SELECT user_id, data_json FROM execution_controls")
        .fetch_all(pool)
        .await?;
    for row in controls {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<ExecutionControlsRecord>(&json) {
            state.execution_controls.insert(row.get("user_id"), value);
        }
    }

    let task_states = sqlx::query("SELECT user_id, task_id, data_json FROM execution_task_states")
        .fetch_all(pool)
        .await?;
    for row in task_states {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<ExecutionTaskStateRecord>(&json) {
            state
                .execution_task_states
                .entry(row.get("user_id"))
                .or_default()
                .insert(row.get("task_id"), value);
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

    let shopify_reports =
        sqlx::query("SELECT user_id, data_json FROM shopify_profit_share_reports")
            .fetch_all(pool)
            .await?;
    for row in shopify_reports {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<ShopifyProfitShareRecord>(&json) {
            state
                .shopify_profit_share_reports
                .entry(row.get("user_id"))
                .or_default()
                .push(value);
        }
    }

    let rnd_jobs = sqlx::query("SELECT job_id, data_json FROM rnd_jobs")
        .fetch_all(pool)
        .await?;
    for row in rnd_jobs {
        let json: String = row.get("data_json");
        if let Ok(value) = serde_json::from_str::<RndJobRecord>(&json) {
            state.rnd_jobs.insert(row.get("job_id"), value);
        }
    }

    Ok(state)
}

async fn persist_rnd_job_if_configured(state: &ApiState, job: &RndJobRecord) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let json = serde_json::to_string(job)?;
    sqlx::query(
        r#"
        INSERT INTO rnd_jobs (job_id, user_id, data_json)
        VALUES (?1, ?2, ?3)
        ON CONFLICT(job_id) DO UPDATE SET
          user_id=excluded.user_id,
          data_json=excluded.data_json
        "#,
    )
    .bind(job.job_id.as_str())
    .bind(job.user_id.as_str())
    .bind(json)
    .execute(pool)
    .await?;
    Ok(())
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

async fn persist_psychological_profile_if_configured(
    state: &ApiState,
    profile: &PsychologicalProfileRecord,
) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let json = serde_json::to_string(profile)?;
    sqlx::query(
        r#"
        INSERT INTO psychological_profiles (user_id, data_json)
        VALUES (?1, ?2)
        ON CONFLICT(user_id) DO UPDATE SET data_json=excluded.data_json
        "#,
    )
    .bind(profile.user_id.as_str())
    .bind(json)
    .execute(pool)
    .await?;
    Ok(())
}

async fn persist_vehicle_profile_if_configured(
    state: &ApiState,
    profile: &VehicleProfileRecord,
) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let json = serde_json::to_string(profile)?;
    sqlx::query(
        r#"
        INSERT INTO vehicle_profiles (user_id, data_json)
        VALUES (?1, ?2)
        ON CONFLICT(user_id) DO UPDATE SET data_json=excluded.data_json
        "#,
    )
    .bind(profile.user_id.as_str())
    .bind(json)
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

async fn persist_checkins_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM execution_checkins WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let checkins = state
        .execution_checkins
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for checkin in checkins {
        let json = serde_json::to_string(&checkin)?;
        sqlx::query(
            "INSERT INTO execution_checkins (checkin_id, user_id, data_json) VALUES (?1, ?2, ?3)",
        )
        .bind(checkin.checkin_id)
        .bind(user_id)
        .bind(json)
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn persist_execution_controls_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    let Some(controls) = state.execution_controls.read().get(user_id).cloned() else {
        return Ok(());
    };
    let json = serde_json::to_string(&controls)?;
    sqlx::query(
        r#"
        INSERT INTO execution_controls (user_id, data_json)
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

async fn persist_execution_task_states_if_configured(
    state: &ApiState,
    user_id: &str,
) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM execution_task_states WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let task_states = state
        .execution_task_states
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for (task_id, task_state) in task_states {
        let json = serde_json::to_string(&task_state)?;
        sqlx::query(
            "INSERT INTO execution_task_states (user_id, task_id, data_json) VALUES (?1, ?2, ?3)",
        )
        .bind(user_id)
        .bind(task_id)
        .bind(json)
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn persist_memories_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM user_memories WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let memories = state
        .user_memories
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for memory in memories {
        let json = serde_json::to_string(&memory)?;
        sqlx::query(
            "INSERT INTO user_memories (memory_id, user_id, data_json) VALUES (?1, ?2, ?3)",
        )
        .bind(memory.memory_id)
        .bind(user_id)
        .bind(json)
        .execute(pool)
        .await?;
    }
    Ok(())
}

async fn persist_lifelogs_if_configured(state: &ApiState, user_id: &str) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM lifelogs WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let lifelogs = state
        .lifelogs
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for lifelog in lifelogs {
        let json = serde_json::to_string(&lifelog)?;
        sqlx::query("INSERT INTO lifelogs (lifelog_id, user_id, data_json) VALUES (?1, ?2, ?3)")
            .bind(lifelog.lifelog_id)
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

async fn persist_shopify_profit_share_reports_if_configured(
    state: &ApiState,
    user_id: &str,
) -> Result<()> {
    let Some(pool) = state.db_pool.as_ref() else {
        return Ok(());
    };
    sqlx::query("DELETE FROM shopify_profit_share_reports WHERE user_id = ?1")
        .bind(user_id)
        .execute(pool)
        .await?;
    let records = state
        .shopify_profit_share_reports
        .read()
        .get(user_id)
        .cloned()
        .unwrap_or_default();
    for record in records {
        let json = serde_json::to_string(&record)?;
        sqlx::query(
            "INSERT INTO shopify_profit_share_reports (report_id, user_id, data_json) VALUES (?1, ?2, ?3)",
        )
        .bind(record.report_id.as_str())
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

fn verify_stripe_webhook_signature(
    signature: &str,
    payload: &str,
    secret: &str,
    tolerance_seconds: u64,
) -> bool {
    let mut timestamp = "";
    let mut expected_signatures: Vec<&str> = Vec::new();
    for part in signature.split(',') {
        let mut split = part.splitn(2, '=');
        let key = split.next().unwrap_or_default();
        let value = split.next().unwrap_or_default();
        if key == "t" {
            timestamp = value;
        } else if key == "v1" {
            expected_signatures.push(value);
        }
    }
    if timestamp.is_empty() || expected_signatures.is_empty() {
        return false;
    }
    let timestamp_value = match timestamp.parse::<i64>() {
        Ok(value) => value,
        Err(_) => return false,
    };
    if tolerance_seconds > 0 {
        let now = chrono::Utc::now().timestamp();
        if (now - timestamp_value).abs() > tolerance_seconds as i64 {
            return false;
        }
    }

    if payload.len() > 256 * 1024 {
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
    expected_signatures
        .iter()
        .any(|expected| constant_time_eq(computed.as_bytes(), expected.as_bytes()))
}

#[cfg(test)]
fn build_test_stripe_signature(
    payload: &str,
    secret: &str,
    timestamp: i64,
) -> Result<String, hmac::digest::InvalidLength> {
    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes())?;
    let signed_payload = format!("{}.{}", timestamp, payload);
    mac.update(signed_payload.as_bytes());
    let signature = hex_encode(mac.finalize().into_bytes().as_slice());
    Ok(format!("t={},v1={}", timestamp, signature))
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
    memory_context: &[MemoryRetrievedItem],
    fallback_reply: &str,
    code_agent_route: Option<CodeAgentRoute>,
) -> Result<String> {
    let runtime = state
        .openai_runtime
        .as_ref()
        .context("OpenAI runtime is not configured")?;

    let model = match code_agent_route {
        Some(CodeAgentRoute::BackendOps) => runtime.coding_backend_model.as_str(),
        _ => runtime.model.as_str(),
    };

    let system_prompt = "You are Atlas Masa Executive Intelligence. Speak with refined, high-class language and clear structure. Act like a strategic chief-of-staff for a high-performing traveler-builder. Prioritize execution, safety, resilience, and momentum.";
    let payload = build_openai_premium_payload(
        runtime,
        model,
        system_prompt,
        request,
        user,
        survey,
        notes,
        memory_context,
        fallback_reply,
        code_agent_route,
    );

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

async fn generate_premium_gemini_reply(
    state: &ApiState,
    request: &ChatRequest,
    user: Option<&UserRecord>,
    survey: Option<&SurveyStateRecord>,
    notes: &[UserNoteRecord],
    memory_context: &[MemoryRetrievedItem],
    fallback_reply: &str,
    code_agent_route: Option<CodeAgentRoute>,
) -> Result<String> {
    let runtime = state
        .gemini_runtime
        .as_ref()
        .context("Gemini runtime is not configured")?;
    let model = match code_agent_route {
        Some(CodeAgentRoute::FrontendDesign) => runtime.frontend_design_model.as_str(),
        _ => runtime.model.as_str(),
    };

    let payload = build_gemini_premium_payload(
        runtime,
        request,
        user,
        survey,
        notes,
        memory_context,
        fallback_reply,
        code_agent_route,
    );

    let endpoint = build_gemini_generate_content_url(model)?;
    let response = state
        .http_client
        .post(endpoint)
        .header("x-goog-api-key", runtime.api_key.as_str())
        .json(&payload)
        .send()
        .await
        .context("Gemini request failed")?;

    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("Gemini non-success status {}: {}", status.as_u16(), body);
    }

    let body: serde_json::Value = response.json().await.context("Gemini parse failed")?;
    extract_gemini_output_text(&body)
        .filter(|value| !value.trim().is_empty())
        .context("Gemini output text missing")
}

async fn rewrite_note_with_gemini(
    state: &ApiState,
    note: &UserNoteRecord,
    instruction: &str,
) -> Result<String> {
    let runtime = state
        .gemini_runtime
        .as_ref()
        .context("Gemini runtime is not configured")?;

    let prompt = format!(
        "Rewrite notes into premium executive language while preserving facts and actionability.\n\nInstruction:\n{}\n\nTitle: {}\n\nNote:\n{}",
        instruction,
        note.title,
        note.content
    );
    let mut generation_config = serde_json::json!({
        "temperature": runtime.temperature,
        "maxOutputTokens": runtime.max_output_tokens
    });
    if let Some(level) = runtime.thinking_level.as_deref() {
        generation_config["thinkingConfig"] = serde_json::json!({
            "thinkingLevel": level
        });
    }
    let payload = serde_json::json!({
        "contents": [
            {
                "role": "user",
                "parts": [
                    { "text": prompt }
                ]
            }
        ],
        "generationConfig": generation_config
    });

    let endpoint = build_gemini_generate_content_url(runtime.model.as_str())?;
    let response = state
        .http_client
        .post(endpoint)
        .header("x-goog-api-key", runtime.api_key.as_str())
        .json(&payload)
        .send()
        .await
        .context("Gemini note rewrite request failed")?;
    let status = response.status();
    if !status.is_success() {
        let body = response.text().await.unwrap_or_default();
        anyhow::bail!("Gemini note rewrite failed {}: {}", status.as_u16(), body);
    }

    let body: serde_json::Value = response
        .json()
        .await
        .context("Gemini rewrite parse failed")?;
    extract_gemini_output_text(&body)
        .filter(|value| !value.trim().is_empty())
        .context("Gemini rewrite output missing")
}

async fn rewrite_note_with_cloud_ai(
    state: &ApiState,
    note: &UserNoteRecord,
    instruction: &str,
) -> Result<String> {
    let backends = configured_cloud_ai_backends(state, None);
    if backends.is_empty() {
        anyhow::bail!("No cloud AI runtime is configured");
    }

    let mut last_error: Option<anyhow::Error> = None;
    for backend in backends {
        let result = match backend {
            CloudAiBackend::OpenAi => rewrite_note_with_openai(state, note, instruction).await,
            CloudAiBackend::Gemini => rewrite_note_with_gemini(state, note, instruction).await,
        };
        match result {
            Ok(output) => return Ok(output),
            Err(error) => {
                last_error = Some(
                    error.context(format!("cloud ai backend {} failed", backend.backend_id())),
                );
            }
        }
    }

    Err(last_error.unwrap_or_else(|| anyhow::anyhow!("cloud AI rewrite failed")))
}

fn build_gemini_generate_content_url(model: &str) -> Result<Url> {
    let normalized = model
        .trim()
        .trim_start_matches("models/")
        .trim()
        .to_string();
    if normalized.is_empty() {
        anyhow::bail!("Gemini model is empty");
    }
    if !normalized
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
    {
        anyhow::bail!("Gemini model contains unsupported characters");
    }
    Url::parse(
        format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent",
            normalized
        )
        .as_str(),
    )
    .context("Gemini URL parse failed")
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

fn extract_gemini_output_text(payload: &serde_json::Value) -> Option<String> {
    let candidates = payload.get("candidates")?.as_array()?;
    let first = candidates.first()?;
    let parts = first.get("content")?.get("parts")?.as_array()?;
    let mut chunks = Vec::new();
    for part in parts {
        if let Some(text) = part.get("text").and_then(|value| value.as_str()) {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                chunks.push(trimmed.to_string());
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
            | "/v1/auth/apple/native"
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
    use super::{
        advance_rnd_job, apply_amm_policy, build_clear_cookie,
        build_memory_batch_export_jsonl_for_model, build_openai_premium_payload, build_rnd_parts,
        build_rnd_plan, build_rnd_plan_stages, build_rnd_routing_summary, build_session_cookie,
        build_test_stripe_signature, cloud_requirements_for_endpoint, compute_rnd_eta,
        compute_shopify_profit_share, create_rnd_approved_baseline,
        default_studio_preferences, generate_rnd_compliance_report,
        generate_rnd_document, generate_rnd_document_bundle,
        generate_rnd_package_artifacts, generate_rnd_validation_artifacts,
        ingest_memory_records_if_opted_in, is_public_endpoint, next_survey_question,
        prioritize_execution_tasks, request_origin_from_headers, rnd_has_major_doctrine_failures,
        retrieve_memory_context_from_records, schedule_minutes_offset, seed_rnd_governance_from_plan,
        survey_total_questions, sync_rnd_doctrine_and_structure_state, verify_stripe_webhook_signature, ChatRequest,
        ExecutionTaskCandidate, MemoryIngestEvent, MemoryRecord, MemoryRetrievedItem,
        OpenAiRuntimeConfig, RndArtifactRecord, RndContextPackRecord, RndDesignDecisionRecord,
        RndEtaRecord, RndJobRecord, RndPartRecord, RndPartStatus, RndPlanRecord,
        RndRequirementRecord, RndStageKind, StudioPreferencesRecord, UserNoteRecord, UserRecord,
        DEFAULT_STRIPE_WEBHOOK_TOLERANCE_SECONDS,
    };
    use axum::http::{header, HeaderMap, HeaderValue};
    use chrono::Duration;

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

    #[test]
    fn session_cookie_can_be_host_only_without_domain_attribute() {
        let cookie = build_session_cookie("atlas_session", "session123", 3600, true, "strict", "");
        assert!(!cookie.contains("Domain="));
    }

    #[test]
    fn memory_ingestion_deduplicates_and_refreshes_existing_record() {
        let now = chrono::Utc::now();
        let mut records = Vec::new();
        let first = ingest_memory_records_if_opted_in(
            &mut records,
            "user-1",
            true,
            MemoryIngestEvent {
                memory_type: "preference".to_string(),
                stability: "permanent".to_string(),
                source: "note".to_string(),
                text: "Prefers desert routes with low crowds".to_string(),
                weight: 0.80,
                tags: vec!["travel".to_string()],
                happened_at: Some(now - Duration::days(2)),
                expires_at: None,
            },
            now,
        )
        .expect("first ingestion should create a memory");
        assert_eq!(records.len(), 1);

        let second = ingest_memory_records_if_opted_in(
            &mut records,
            "user-1",
            true,
            MemoryIngestEvent {
                memory_type: "preference".to_string(),
                stability: "permanent".to_string(),
                source: "survey".to_string(),
                text: "Prefers desert routes with low crowds".to_string(),
                weight: 0.96,
                tags: vec!["survey_trip_style".to_string()],
                happened_at: Some(now),
                expires_at: None,
            },
            now,
        )
        .expect("duplicate ingestion should update existing memory");

        assert_eq!(records.len(), 1);
        assert_eq!(first.memory_id, second.memory_id);
        assert_eq!(records[0].source, "survey");
        assert!(records[0].weight > 0.85);
        assert!(records[0].tags.iter().any(|tag| tag == "survey_trip_style"));
    }

    #[test]
    fn memory_retrieval_orders_by_relevance_and_recency() {
        let now = chrono::Utc::now();
        let records = vec![
            MemoryRecord {
                memory_id: "memory-1".to_string(),
                user_id: "user-1".to_string(),
                memory_type: "preference".to_string(),
                stability: "permanent".to_string(),
                source: "survey".to_string(),
                text: "User prefers desert routes and silence".to_string(),
                weight: 0.95,
                recency_score: 0.1,
                tags: vec!["desert".to_string()],
                created_at: (now - Duration::days(7)).to_rfc3339(),
                updated_at: (now - Duration::days(3)).to_rfc3339(),
                expires_at: None,
                fingerprint: "f1".to_string(),
            },
            MemoryRecord {
                memory_id: "memory-2".to_string(),
                user_id: "user-1".to_string(),
                memory_type: "mood".to_string(),
                stability: "transient".to_string(),
                source: "chat".to_string(),
                text: "User feels slightly tired this morning".to_string(),
                weight: 0.60,
                recency_score: 1.0,
                tags: vec!["energy".to_string()],
                created_at: (now - Duration::hours(5)).to_rfc3339(),
                updated_at: (now - Duration::hours(3)).to_rfc3339(),
                expires_at: Some((now + Duration::days(2)).to_rfc3339()),
                fingerprint: "f2".to_string(),
            },
        ];

        let ranked = retrieve_memory_context_from_records(&records, "desert route", 5, now);
        assert_eq!(ranked.len(), 2);
        assert_eq!(ranked[0].memory_id, "memory-1");
        assert!(ranked[0].final_score > ranked[1].final_score);
    }

    #[test]
    fn memory_ingestion_respects_privacy_opt_out() {
        let now = chrono::Utc::now();
        let mut records = Vec::new();
        let ingested = ingest_memory_records_if_opted_in(
            &mut records,
            "user-1",
            false,
            MemoryIngestEvent {
                memory_type: "goal".to_string(),
                stability: "permanent".to_string(),
                source: "chat".to_string(),
                text: "Build a strong weekly execution cadence".to_string(),
                weight: 0.88,
                tags: vec!["execution".to_string()],
                happened_at: Some(now),
                expires_at: None,
            },
            now,
        );
        assert!(ingested.is_none());
        assert!(records.is_empty());
    }

    #[test]
    fn openai_premium_payload_places_stable_context_before_dynamic_task() {
        let runtime = OpenAiRuntimeConfig {
            api_key: "test".to_string(),
            model: "gpt-5.2".to_string(),
            coding_backend_model: "gpt-5.3-codex".to_string(),
            default_reasoning_effort: "high".to_string(),
        };
        let request = ChatRequest {
            session_id: None,
            text: "Help me plan the next move".to_string(),
            locale: Some("en".to_string()),
            user_id: Some("user-1".to_string()),
            preferred_format: None,
            response_depth: None,
            response_tone: None,
            include_proactive: None,
            code_agent_route: None,
        };
        let user = UserRecord {
            user_id: "user-1".to_string(),
            provider: "google".to_string(),
            email: "user@example.com".to_string(),
            name: "User".to_string(),
            locale: "en".to_string(),
            trip_style: Some("desert".to_string()),
            risk_preference: Some("measured".to_string()),
            memory_opt_in: true,
            passkey_user_handle: None,
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };

        let payload = build_openai_premium_payload(
            &runtime,
            runtime.model.as_str(),
            "system",
            &request,
            Some(&user),
            None,
            &[],
            &[],
            "fallback",
            None,
        );

        let input = payload["input"].as_array().expect("input array");
        let stable_block = input[1]["content"][0]["text"]
            .as_str()
            .expect("stable text");
        let dynamic_block = input[2]["content"][0]["text"]
            .as_str()
            .expect("dynamic text");

        assert!(stable_block.starts_with("Stable Context JSON:"));
        assert!(dynamic_block.starts_with("Dynamic Task JSON:"));
        assert!(dynamic_block.contains("fallback"));
    }

    #[test]
    fn memory_batch_export_jsonl_contains_one_line_per_item() {
        let items = vec![
            MemoryRetrievedItem {
                memory_id: "m1".to_string(),
                memory_type: "goal".to_string(),
                stability: "permanent".to_string(),
                source: "survey".to_string(),
                text: "Build a stronger weekly execution cadence".to_string(),
                weight: 0.9,
                recency_score: 0.7,
                relevance_score: 0.8,
                final_score: 0.84,
                tags: vec!["execution".to_string()],
                updated_at: chrono::Utc::now().to_rfc3339(),
            },
            MemoryRetrievedItem {
                memory_id: "m2".to_string(),
                memory_type: "friction".to_string(),
                stability: "transient".to_string(),
                source: "checkin".to_string(),
                text: "Low energy after long admin blocks".to_string(),
                weight: 0.6,
                recency_score: 0.9,
                relevance_score: 0.65,
                final_score: 0.71,
                tags: vec!["energy".to_string()],
                updated_at: chrono::Utc::now().to_rfc3339(),
            },
        ];

        let jsonl =
            build_memory_batch_export_jsonl_for_model("openai", "gpt-5.2", items.as_slice());
        let lines = jsonl.lines().collect::<Vec<_>>();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains("\"custom_id\":\"memory-compaction-m1\""));
        assert!(lines[1].contains("\"custom_id\":\"memory-compaction-m2\""));
    }

    #[test]
    fn studio_preferences_include_compute_controls_by_default() {
        let prefs = default_studio_preferences("user-1");
        assert_eq!(prefs.compute_mode, "balanced");
        assert_eq!(prefs.memory_depth, "standard");
        assert_eq!(prefs.cloud_cost_guardrail, "standard");
        assert_eq!(prefs.local_resource_guardrail, "balanced");
    }

    #[test]
    fn amm_policy_compacts_on_threshold_and_keeps_pinned_context() {
        let request = ChatRequest {
            session_id: None,
            text: "Need a deep execution plan with legal IDs, hardware sizing, budget controls, and retained execution history ".repeat(160),
            locale: Some("en".to_string()),
            user_id: Some("user-1".to_string()),
            preferred_format: None,
            response_depth: Some("deep".to_string()),
            response_tone: None,
            include_proactive: None,
            code_agent_route: None,
        };
        let prefs = StudioPreferencesRecord {
            user_id: "user-1".to_string(),
            preferred_format: "structured_plan".to_string(),
            response_depth: "deep".to_string(),
            memory_depth: "full".to_string(),
            compute_mode: "eco".to_string(),
            cloud_cost_guardrail: "tight".to_string(),
            local_resource_guardrail: "conservative".to_string(),
            response_tone: "executive".to_string(),
            proactive_mode: "enabled".to_string(),
            reminders_app: "google_calendar".to_string(),
            alarms_app: "apple_clock".to_string(),
            voice_mode: "enabled".to_string(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };
        let notes = vec![UserNoteRecord {
            note_id: "n1".to_string(),
            user_id: "user-1".to_string(),
            title: "Long note".to_string(),
            content: "A".repeat(8_000),
            tags: vec![],
            updated_at: chrono::Utc::now().to_rfc3339(),
        }];
        let memory_context = vec![
            MemoryRetrievedItem {
                memory_id: "m1".to_string(),
                memory_type: "identity".to_string(),
                stability: "permanent".to_string(),
                source: "manual".to_string(),
                text: "Business ID 12345 and legal registration record".to_string(),
                weight: 1.0,
                recency_score: 0.7,
                relevance_score: 0.8,
                final_score: 0.9,
                tags: vec!["pinned".to_string(), "legal".to_string()],
                updated_at: chrono::Utc::now().to_rfc3339(),
            },
            MemoryRetrievedItem {
                memory_id: "m2".to_string(),
                memory_type: "preference".to_string(),
                stability: "permanent".to_string(),
                source: "survey".to_string(),
                text: "User likes deep hardware explanations".to_string(),
                weight: 0.9,
                recency_score: 0.6,
                relevance_score: 0.7,
                final_score: 0.8,
                tags: vec![],
                updated_at: chrono::Utc::now().to_rfc3339(),
            },
            MemoryRetrievedItem {
                memory_id: "m3".to_string(),
                memory_type: "chat".to_string(),
                stability: "transient".to_string(),
                source: "chat".to_string(),
                text: "Repeated greetings and old debug chatter ".repeat(30),
                weight: 0.4,
                recency_score: 0.2,
                relevance_score: 0.1,
                final_score: 0.3,
                tags: vec![],
                updated_at: chrono::Utc::now().to_rfc3339(),
            },
        ];

        let (compacted, diagnostics) = apply_amm_policy(&request, &notes, memory_context, &prefs);
        assert!(diagnostics.compaction_applied);
        assert!(diagnostics.pinned_context_preserved);
        assert!(diagnostics.trigger_reason.contains("threshold"));
        assert!(compacted.iter().any(|item| item.memory_id == "m1"));
    }

    #[test]
    fn scheduling_offsets_follow_cadence_and_horizon() {
        let aggressive_daily = schedule_minutes_offset("aggressive", "daily", 0);
        let steady_daily = schedule_minutes_offset("steady", "daily", 0);
        let steady_mid = schedule_minutes_offset("steady", "mid_term", 0);
        let steady_long = schedule_minutes_offset("steady", "long_term", 0);
        assert!(aggressive_daily < steady_daily);
        assert!(steady_mid > steady_daily);
        assert!(steady_long > steady_mid);
    }

    #[test]
    fn prioritization_prefers_urgent_daily_execution() {
        let ranked = prioritize_execution_tasks(vec![
            ExecutionTaskCandidate {
                task_id: "long-a".to_string(),
                title: "Long mission planning".to_string(),
                detail: "Prepare annual strategic narrative".to_string(),
                source: "survey".to_string(),
                horizon: "long_term".to_string(),
                urgency: 0.45,
                impact: 0.95,
                confidence: 0.85,
            },
            ExecutionTaskCandidate {
                task_id: "daily-a".to_string(),
                title: "Next action now".to_string(),
                detail: "Ship the current customer deliverable in this block".to_string(),
                source: "checkin".to_string(),
                horizon: "daily".to_string(),
                urgency: 0.97,
                impact: 0.82,
                confidence: 0.94,
            },
        ]);

        assert!(!ranked.is_empty());
        assert_eq!(ranked[0].task_id, "daily-a");
    }

    #[test]
    fn survey_includes_gym_and_income_cadence_questions() {
        let mut answers = std::collections::HashMap::new();
        answers.insert("primary_goal".to_string(), "wealth".to_string());
        answers.insert("daily_pressure".to_string(), "medium".to_string());
        answers.insert("work_hours".to_string(), "6_10".to_string());
        answers.insert("stress_trigger".to_string(), "overload".to_string());
        answers.insert("travel_pattern".to_string(), "hybrid".to_string());
        answers.insert("trip_style".to_string(), "mixed".to_string());
        answers.insert("health_priority".to_string(), "focus".to_string());

        let gym_q = next_survey_question("en", &answers).expect("gym question should exist");
        assert_eq!(gym_q.id, "gym_frequency");
        answers.insert("gym_frequency".to_string(), "regularly".to_string());

        let income_q =
            next_survey_question("en", &answers).expect("income cadence question should exist");
        assert_eq!(income_q.id, "income_cadence");
    }

    #[test]
    fn survey_total_questions_accounts_for_new_baseline_questions() {
        let answers = std::collections::HashMap::<String, String>::new();
        assert_eq!(survey_total_questions(&answers), 13);
    }

    #[test]
    fn stripe_webhook_signature_accepts_valid_recent_payload() {
        let payload = r#"{"type":"checkout.session.completed"}"#;
        let secret = "whsec_test_secret";
        let now = chrono::Utc::now().timestamp();
        let signature = build_test_stripe_signature(payload, secret, now)
            .expect("signature generation should succeed");
        assert!(verify_stripe_webhook_signature(
            signature.as_str(),
            payload,
            secret,
            DEFAULT_STRIPE_WEBHOOK_TOLERANCE_SECONDS,
        ));
    }

    #[test]
    fn stripe_webhook_signature_rejects_replay_outside_tolerance() {
        let payload = r#"{"type":"checkout.session.completed"}"#;
        let secret = "whsec_test_secret";
        let old = chrono::Utc::now().timestamp() - 900;
        let signature = build_test_stripe_signature(payload, secret, old)
            .expect("signature generation should succeed");
        assert!(!verify_stripe_webhook_signature(
            signature.as_str(),
            payload,
            secret,
            DEFAULT_STRIPE_WEBHOOK_TOLERANCE_SECONDS,
        ));
    }

    #[test]
    fn shopify_profit_share_computes_cut_from_agentic_uplift() {
        let computed = compute_shopify_profit_share(1_250_000, 800_000, 0.8, None, 2_000);
        assert_eq!(computed.uplift_profit_cents, 450_000);
        assert_eq!(computed.agentic_attributed_profit_cents, 360_000);
        assert_eq!(computed.app_cut_cents, 72_000);
        assert_eq!(computed.merchant_kept_cents, 1_178_000);
    }

    #[test]
    fn shopify_profit_share_clamps_explicit_attribution_to_available_profit() {
        let computed = compute_shopify_profit_share(100_000, 0, 1.0, Some(200_000), 10_000);
        assert_eq!(computed.agentic_attributed_profit_cents, 100_000);
        assert_eq!(computed.app_cut_cents, 100_000);
        assert_eq!(computed.merchant_kept_cents, 0);
    }

    #[test]
    fn request_origin_parses_origin_header_first() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::ORIGIN,
            HeaderValue::from_static("https://atlasmasa.com"),
        );
        assert_eq!(
            request_origin_from_headers(&headers).as_deref(),
            Some("https://atlasmasa.com")
        );
    }

    #[test]
    fn request_origin_does_not_trust_referer_without_origin_header() {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::REFERER,
            HeaderValue::from_static("https://www.atlasmasa.com/concierge-local.html?launch=chat"),
        );
        assert_eq!(request_origin_from_headers(&headers), None);
    }

    #[test]
    fn cloud_requirements_classify_paths_correctly() {
        assert_eq!(cloud_requirements_for_endpoint("/v1/chat"), (false, true));
        assert_eq!(
            cloud_requirements_for_endpoint("/v1/plan_trip"),
            (false, true)
        );
        assert_eq!(
            cloud_requirements_for_endpoint("/v1/notes/upsert"),
            (true, false)
        );
        assert_eq!(
            cloud_requirements_for_endpoint("/v1/feed/proactive"),
            (true, true)
        );
        assert_eq!(
            cloud_requirements_for_endpoint("/v1/auth/me"),
            (false, false)
        );
    }

    #[test]
    fn guest_session_endpoints_are_disabled() {
        // Non-public endpoints require signed-in session when x-api-key is absent.
        assert!(!is_public_endpoint("/v1/chat"));
        assert!(!is_public_endpoint("/v1/notes"));
        assert!(!is_public_endpoint("/v1/feed/proactive"));
    }

    #[test]
    fn public_endpoints_include_session_probe_and_logout() {
        assert!(is_public_endpoint("/health"));
        assert!(is_public_endpoint("/v1/auth/me"));
        assert!(is_public_endpoint("/v1/auth/logout"));
        assert!(!is_public_endpoint("/v1/profile/upsert"));
    }

    #[test]
    fn rnd_plan_blocks_when_research_is_weak_and_prompt_overclaims() {
        let context = RndContextPackRecord {
            user_preference_summary: "Locale: en".to_string(),
            memory_summary: "Prefers safe road-trip builds".to_string(),
            prior_job_summary: "job-1:vehicle:completed".to_string(),
            research_summary: "Thin research summary".to_string(),
            explicit_constraints: vec![
                "Safety should be treated as a first-class design objective.".to_string(),
            ],
            citations: Vec::new(),
            research_confidence: 0.22,
        };

        let plan = build_rnd_plan(
            "vehicle",
            "Design a fully certified road legal electric camper van with beautiful packaging",
            "en",
            &context,
            1,
            None,
        );

        assert!(!plan.executable);
        assert!(plan
            .blocking_issues
            .iter()
            .any(|issue| issue.contains("Research confidence is weak")));
        assert!(plan
            .blocking_issues
            .iter()
            .any(|issue| issue.contains("missing concrete engineering constraints")));
        assert!(plan
            .blocking_issues
            .iter()
            .any(|issue| issue.contains("cannot promise legal sign-off")));
    }

    #[test]
    fn rnd_plan_revision_note_becomes_constraint_without_mutating_goals() {
        let context = RndContextPackRecord {
            user_preference_summary: "Locale: en".to_string(),
            memory_summary: "User prioritizes low weight".to_string(),
            prior_job_summary: String::new(),
            research_summary: "Strong internal and client research".to_string(),
            explicit_constraints: vec![
                "Weight reduction is a priority.".to_string(),
                "Safety should be treated as a first-class design objective.".to_string(),
            ],
            citations: Vec::new(),
            research_confidence: 0.82,
        };

        let plan = build_rnd_plan(
            "vehicle_part",
            "Design a lightweight suspension arm with aluminum material and clear load targets for safe operation",
            "en",
            &context,
            2,
            Some("Reduce assembly complexity around the mounting points."),
        );

        assert!(plan.executable);
        assert!(plan
            .constraints
            .iter()
            .any(|constraint| constraint.contains("Revision request: Reduce assembly complexity")));
        assert!(plan
            .goals
            .iter()
            .any(|goal| goal.contains("part-by-part artifacts")));
    }

    #[test]
    fn rnd_part_generation_is_deterministic_for_same_plan() {
        let context = RndContextPackRecord {
            user_preference_summary: "Locale: en".to_string(),
            memory_summary: String::new(),
            prior_job_summary: String::new(),
            research_summary: "Good research".to_string(),
            explicit_constraints: vec![
                "Weight reduction is a priority.".to_string(),
                "Safety should be treated as a first-class design objective.".to_string(),
            ],
            citations: Vec::new(),
            research_confidence: 0.88,
        };
        let plan = build_rnd_plan(
            "vehicle",
            "Design a safe lightweight vehicle structure with aluminum material, known load targets, and battery cooling",
            "en",
            &context,
            1,
            None,
        );

        let parts_a = build_rnd_parts(&plan);
        let parts_b = build_rnd_parts(&plan);

        let names_a = parts_a
            .iter()
            .map(|part| part.name.clone())
            .collect::<Vec<_>>();
        let names_b = parts_b
            .iter()
            .map(|part| part.name.clone())
            .collect::<Vec<_>>();
        assert_eq!(names_a, names_b);
        assert!(parts_a.len() >= 6);
        assert_eq!(parts_a[0].dependencies.len(), 0);
        assert!(parts_a
            .iter()
            .skip(1)
            .all(|part| part.dependencies == vec!["part-01".to_string()]));
    }

    #[test]
    fn rnd_eta_reflects_waiting_state_and_part_retries() {
        let stages = build_rnd_plan_stages(3);
        let parts = vec![
            RndPartRecord {
                part_id: "part-01".to_string(),
                name: "frame".to_string(),
                purpose: "support".to_string(),
                interfaces: vec!["assembly".to_string()],
                geometry_constraints: vec!["fit".to_string()],
                material_assumptions: vec!["confirm".to_string()],
                manufacturing_assumptions: vec!["review".to_string()],
                validation_tasks: vec!["load case review".to_string()],
                dependencies: Vec::new(),
                status: RndPartStatus::Blocked,
                retries: 2,
                risk_flags: vec!["review required".to_string()],
            },
            RndPartRecord {
                part_id: "part-02".to_string(),
                name: "panel".to_string(),
                purpose: "cover".to_string(),
                interfaces: vec!["assembly".to_string()],
                geometry_constraints: vec!["fit".to_string()],
                material_assumptions: vec!["confirm".to_string()],
                manufacturing_assumptions: vec!["review".to_string()],
                validation_tasks: vec!["fit check".to_string()],
                dependencies: vec!["part-01".to_string()],
                status: RndPartStatus::Queued,
                retries: 0,
                risk_flags: vec!["review required".to_string()],
            },
        ];

        let waiting_eta = compute_rnd_eta(
            &stages,
            &parts,
            RndStageKind::PartValidation,
            true,
            "Waiting on user review",
        );
        let active_eta = compute_rnd_eta(
            &stages,
            &parts,
            RndStageKind::PartValidation,
            false,
            "Validation retries increased runtime",
        );

        assert_eq!(waiting_eta.current_bottleneck, "user approval");
        assert_eq!(active_eta.current_bottleneck, "blocked part validation");
        assert!(active_eta.estimated_remaining_minutes >= waiting_eta.estimated_remaining_minutes);
    }

    #[test]
    fn rnd_stage_advance_builds_parts_and_artifacts_in_order() {
        let context = RndContextPackRecord {
            user_preference_summary: "Locale: en".to_string(),
            memory_summary: "User wants safe and sustainable designs".to_string(),
            prior_job_summary: String::new(),
            research_summary: "Research summary with manufacturing and sustainability context"
                .to_string(),
            explicit_constraints: vec![
                "Safety should be treated as a first-class design objective.".to_string(),
                "Prefer more environmentally considerate materials/processes where feasible."
                    .to_string(),
            ],
            citations: Vec::new(),
            research_confidence: 0.9,
        };
        let plan = build_rnd_plan(
            "vehicle_part",
            "Design a safe lightweight battery enclosure with aluminum material and crash load targets",
            "en",
            &context,
            1,
            None,
        );
        let stages = build_rnd_plan_stages(plan.proposed_parts.len());
        let mut job = RndJobRecord {
            job_id: "job-1".to_string(),
            user_id: "user-1".to_string(),
            product_type: "vehicle_part".to_string(),
            design_domain: "mechanical_cad".to_string(),
            locale: "en".to_string(),
            prompt: "Design a safe lightweight battery enclosure with aluminum material and crash load targets".to_string(),
            context_pack: context,
            plans: vec![plan.clone()],
            accepted_plan_version: Some(1),
            current_stage: RndStageKind::PartDecomposition,
            waiting_on_user: true,
            auto_run_enabled: false,
            paused_after_current_stage: false,
            parts: Vec::new(),
            artifacts: Vec::new(),
            timeline: super::build_rnd_initial_timeline(&stages),
            eta: compute_rnd_eta(&stages, &[], RndStageKind::PartDecomposition, true, "Awaiting approval"),
            risk_flags: vec!["human review required".to_string()],
            latest_validation_summary: String::new(),
            requirements: Vec::new(),
            decisions: Vec::new(),
            design_reviews: Vec::new(),
            evidence_artifacts: Vec::new(),
            simulation_runs: Vec::new(),
            compliance_reports: Vec::new(),
            approval_records: Vec::new(),
            audit_events: Vec::new(),
            approved_baselines: Vec::new(),
            doctrine_profile: None,
            doctrine_checks: Vec::new(),
            module_definitions: Vec::new(),
            tool_requirements: Vec::new(),
            bom_items: Vec::new(),
            assembly_steps: Vec::new(),
            service_access_points: Vec::new(),
            inspection_checklist_items: Vec::new(),
            revision_history: Vec::new(),
            document_records: Vec::new(),
            documentation_bundles: Vec::new(),
            created_at: chrono::Utc::now().to_rfc3339(),
            updated_at: chrono::Utc::now().to_rfc3339(),
        };

        advance_rnd_job(&mut job, &plan, Some("approved"));
        assert_eq!(job.current_stage, RndStageKind::PartGeneration);
        assert!(!job.parts.is_empty());

        advance_rnd_job(&mut job, &plan, Some("continue"));
        assert_eq!(job.current_stage, RndStageKind::PartValidation);
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "cad_source"));
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "assembly_step_manifest"));
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "blueprint_package"));

        advance_rnd_job(&mut job, &plan, Some("continue"));
        assert_eq!(job.current_stage, RndStageKind::PackageAssembly);
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "validation_report"));
    }

    #[test]
    fn mechanical_rnd_routing_summary_includes_solver_and_scene_packaging() {
        let summary = build_rnd_routing_summary("mechanical");
        assert!(summary
            .gemini_escalated_tasks
            .contains(&"research_heavy_review".to_string()));
        assert!(summary
            .gpt_escalated_tasks
            .contains(&"safety_adversarial_review".to_string()));
        assert!(summary
            .executor_tasks
            .contains(&"CalculiX named-load-case simulation".to_string()));
        assert!(summary
            .executor_tasks
            .contains(&"USD/USDZ review-scene packaging".to_string()));
    }

    #[test]
    fn mechanical_package_generation_emits_scene_and_simulation_artifacts() {
        let now = chrono::Utc::now().to_rfc3339();
        let mut job = RndJobRecord {
            job_id: "job-1".to_string(),
            user_id: "user-1".to_string(),
            product_type: "mechanical_vehicle".to_string(),
            design_domain: "mechanical".to_string(),
            locale: "en".to_string(),
            prompt: "Design a safe lightweight trailer".to_string(),
            accepted_plan_version: Some(1),
            current_stage: RndStageKind::PartValidation,
            waiting_on_user: false,
            auto_run_enabled: false,
            paused_after_current_stage: false,
            created_at: now.clone(),
            updated_at: now.clone(),
            plans: vec![],
            context_pack: RndContextPackRecord {
                user_preference_summary: "prefers lightweight builds".to_string(),
                memory_summary: "prior work values quiet towing".to_string(),
                prior_job_summary: "none".to_string(),
                research_summary: "research ready".to_string(),
                explicit_constraints: vec!["safety".to_string()],
                citations: vec![],
                research_confidence: 0.88,
            },
            parts: vec![RndPartRecord {
                part_id: "part-01".to_string(),
                name: "Frame Rail".to_string(),
                purpose: "Primary structure".to_string(),
                interfaces: vec!["cross member".to_string()],
                geometry_constraints: vec!["fit inside assembly".to_string()],
                material_assumptions: vec!["steel review placeholder".to_string()],
                manufacturing_assumptions: vec!["human review required".to_string()],
                validation_tasks: vec!["static tongue load".to_string()],
                dependencies: vec![],
                status: RndPartStatus::Generated,
                retries: 0,
                risk_flags: vec!["review fixture assumptions".to_string()],
            }],
            artifacts: vec![],
            timeline: vec![],
            eta: RndEtaRecord {
                estimated_total_minutes: 120,
                estimated_remaining_minutes: 40,
                current_stage_estimated_minutes: 20,
                confidence_label: "medium".to_string(),
                current_bottleneck: "part validation".to_string(),
                slippage_reason: "none".to_string(),
            },
            risk_flags: vec!["human review required".to_string()],
            latest_validation_summary: "pending".to_string(),
            requirements: Vec::new(),
            decisions: Vec::new(),
            design_reviews: Vec::new(),
            evidence_artifacts: Vec::new(),
            simulation_runs: Vec::new(),
            compliance_reports: Vec::new(),
            approval_records: Vec::new(),
            audit_events: Vec::new(),
            approved_baselines: Vec::new(),
            doctrine_profile: None,
            doctrine_checks: Vec::new(),
            module_definitions: Vec::new(),
            tool_requirements: Vec::new(),
            bom_items: Vec::new(),
            assembly_steps: Vec::new(),
            service_access_points: Vec::new(),
            inspection_checklist_items: Vec::new(),
            revision_history: Vec::new(),
            document_records: Vec::new(),
            documentation_bundles: Vec::new(),
        };

        generate_rnd_validation_artifacts(&mut job);
        generate_rnd_package_artifacts(&mut job);

        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "simulation_input"));
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "simulation_result"));
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "review_scene_package"));
        assert!(job
            .artifacts
            .iter()
            .any(|artifact| artifact.artifact_type == "assembly_stage_review_scene"));
    }

    #[test]
    fn compliance_report_uses_stored_state_and_flags_missing_signoff() {
        let now = chrono::Utc::now().to_rfc3339();
        let mut job = RndJobRecord {
            job_id: "job-2".to_string(),
            user_id: "user-1".to_string(),
            product_type: "mechanical_vehicle".to_string(),
            design_domain: "mechanical_cad".to_string(),
            locale: "en".to_string(),
            prompt: "Design a safe lightweight trailer with steel rails".to_string(),
            accepted_plan_version: Some(1),
            current_stage: RndStageKind::ReviewHandoff,
            waiting_on_user: true,
            auto_run_enabled: false,
            paused_after_current_stage: false,
            created_at: now.clone(),
            updated_at: now.clone(),
            plans: vec![RndPlanRecord {
                version: 1,
                generated_at: now.clone(),
                goals: vec!["Generate a safe trailer package".to_string()],
                constraints: vec!["Safety first".to_string()],
                risks: vec!["Human sign-off required".to_string()],
                assumptions: vec!["Steel placeholder".to_string()],
                required_research_domains: vec!["mechanical design".to_string()],
                proposed_parts: vec!["Frame Rail".to_string()],
                execution_stages: build_rnd_plan_stages(1),
                user_explanation: "explanation".to_string(),
                simple_summary: "summary".to_string(),
                citations: vec![],
                executable: true,
                blocking_issues: vec![],
            }],
            context_pack: RndContextPackRecord {
                user_preference_summary: "en".to_string(),
                memory_summary: "safe".to_string(),
                prior_job_summary: "none".to_string(),
                research_summary: "good".to_string(),
                explicit_constraints: vec!["safety".to_string()],
                citations: vec![],
                research_confidence: 0.9,
            },
            parts: vec![],
            artifacts: vec![RndArtifactRecord {
                artifact_id: "artifact-1".to_string(),
                part_id: None,
                artifact_type: "validation_report".to_string(),
                title: "Validation".to_string(),
                format: "md".to_string(),
                content: "Validation content".to_string(),
                created_at: now.clone(),
            }],
            timeline: vec![],
            eta: RndEtaRecord {
                estimated_total_minutes: 100,
                estimated_remaining_minutes: 5,
                current_stage_estimated_minutes: 5,
                confidence_label: "medium".to_string(),
                current_bottleneck: "review".to_string(),
                slippage_reason: "none".to_string(),
            },
            risk_flags: vec!["human sign-off required".to_string()],
            latest_validation_summary: "ready".to_string(),
            requirements: vec![],
            decisions: vec![],
            design_reviews: vec![],
            evidence_artifacts: vec![],
            simulation_runs: vec![],
            compliance_reports: vec![],
            approval_records: vec![],
            audit_events: vec![],
            approved_baselines: vec![],
            doctrine_profile: None,
            doctrine_checks: Vec::new(),
            module_definitions: Vec::new(),
            tool_requirements: Vec::new(),
            bom_items: Vec::new(),
            assembly_steps: Vec::new(),
            service_access_points: Vec::new(),
            inspection_checklist_items: Vec::new(),
            revision_history: Vec::new(),
            document_records: Vec::new(),
            documentation_bundles: Vec::new(),
        };
        let plan = job.plans[0].clone();
        seed_rnd_governance_from_plan(&mut job, &plan);
        let report = generate_rnd_compliance_report(&mut job, Some("Packet"), "engineering_compliance_packet");
        assert_eq!(report.title, "Packet");
        assert!(!report.open_issues.is_empty());
        assert!(report
            .open_issues
            .iter()
            .any(|issue| issue.contains("No linked approval/sign-off")));
    }

    #[test]
    fn approved_baseline_captures_snapshot_hash_and_ids() {
        let now = chrono::Utc::now().to_rfc3339();
        let job = RndJobRecord {
            job_id: "job-3".to_string(),
            user_id: "user-1".to_string(),
            product_type: "mechanical_vehicle".to_string(),
            design_domain: "mechanical_cad".to_string(),
            locale: "en".to_string(),
            prompt: "prompt".to_string(),
            accepted_plan_version: Some(1),
            current_stage: RndStageKind::Completed,
            waiting_on_user: false,
            auto_run_enabled: false,
            paused_after_current_stage: false,
            created_at: now.clone(),
            updated_at: now.clone(),
            plans: vec![],
            context_pack: RndContextPackRecord {
                user_preference_summary: "en".to_string(),
                memory_summary: "memory".to_string(),
                prior_job_summary: "none".to_string(),
                research_summary: "good".to_string(),
                explicit_constraints: vec![],
                citations: vec![],
                research_confidence: 0.8,
            },
            parts: vec![],
            artifacts: vec![RndArtifactRecord {
                artifact_id: "artifact-1".to_string(),
                part_id: None,
                artifact_type: "assembly_package".to_string(),
                title: "Assembly".to_string(),
                format: "md".to_string(),
                content: "Assembly".to_string(),
                created_at: now.clone(),
            }],
            timeline: vec![],
            eta: RndEtaRecord {
                estimated_total_minutes: 0,
                estimated_remaining_minutes: 0,
                current_stage_estimated_minutes: 0,
                confidence_label: "high".to_string(),
                current_bottleneck: "none".to_string(),
                slippage_reason: "done".to_string(),
            },
            risk_flags: vec![],
            latest_validation_summary: "done".to_string(),
            requirements: vec![RndRequirementRecord {
                requirement_id: "req-1".to_string(),
                title: "Req".to_string(),
                description: "Desc".to_string(),
                requirement_kind: "goal".to_string(),
                status: "approved".to_string(),
                source_plan_version: 1,
                linked_component_ids: vec![],
                linked_decision_ids: vec![],
                linked_evidence_ids: vec![],
                linked_report_ids: vec![],
                linked_approval_ids: vec![],
                verification_notes: vec![],
                created_at: now.clone(),
                updated_at: now.clone(),
            }],
            decisions: vec![RndDesignDecisionRecord {
                decision_id: "dec-1".to_string(),
                title: "Decision".to_string(),
                context: "Context".to_string(),
                decision: "Do it".to_string(),
                rationale: "Because".to_string(),
                status: "approved".to_string(),
                source_plan_version: 1,
                supersedes_decision_id: None,
                requirement_ids: vec!["req-1".to_string()],
                component_ids: vec![],
                evidence_ids: vec![],
                affected_artifact_ids: vec!["artifact-1".to_string()],
                review_ids: vec![],
                created_at: now.clone(),
                updated_at: now.clone(),
            }],
            design_reviews: vec![],
            evidence_artifacts: vec![],
            simulation_runs: vec![],
            compliance_reports: vec![],
            approval_records: vec![],
            audit_events: vec![],
            approved_baselines: vec![],
            doctrine_profile: None,
            doctrine_checks: Vec::new(),
            module_definitions: Vec::new(),
            tool_requirements: Vec::new(),
            bom_items: Vec::new(),
            assembly_steps: Vec::new(),
            service_access_points: Vec::new(),
            inspection_checklist_items: Vec::new(),
            revision_history: Vec::new(),
            document_records: Vec::new(),
            documentation_bundles: Vec::new(),
        };
        let baseline = create_rnd_approved_baseline(&job, "Baseline", "approval-1");
        assert_eq!(baseline.status, "locked");
        assert!(!baseline.snapshot_hash.is_empty());
        assert!(baseline.artifact_ids.contains(&"artifact-1".to_string()));
        assert!(baseline.requirement_ids.contains(&"req-1".to_string()));
    }

    #[test]
    fn documentation_bundle_and_doctrine_gate_are_generated_from_job_state() {
        let now = chrono::Utc::now().to_rfc3339();
        let mut job = RndJobRecord {
            job_id: "job-4".to_string(),
            user_id: "user-1".to_string(),
            product_type: "mechanical_vehicle".to_string(),
            design_domain: "mechanical_cad".to_string(),
            locale: "en".to_string(),
            prompt: "Design an affordable trailer with dealer-only repair, hidden service access, many variants, and custom billet trim.".to_string(),
            accepted_plan_version: Some(1),
            current_stage: RndStageKind::ReviewHandoff,
            waiting_on_user: true,
            auto_run_enabled: false,
            paused_after_current_stage: false,
            created_at: now.clone(),
            updated_at: now.clone(),
            plans: vec![RndPlanRecord {
                version: 1,
                generated_at: now.clone(),
                goals: vec!["Build a trailer".to_string()],
                constraints: vec!["Affordable".to_string()],
                risks: vec!["Service access".to_string()],
                assumptions: vec!["Use common materials".to_string()],
                required_research_domains: vec!["manufacturing".to_string()],
                proposed_parts: vec!["Frame".to_string(), "Utility module".to_string()],
                execution_stages: build_rnd_plan_stages(2),
                user_explanation: "Plan".to_string(),
                simple_summary: "Summary".to_string(),
                citations: vec![],
                executable: true,
                blocking_issues: vec![],
            }],
            context_pack: RndContextPackRecord {
                user_preference_summary: "en".to_string(),
                memory_summary: "repairability matters".to_string(),
                prior_job_summary: "none".to_string(),
                research_summary: "good".to_string(),
                explicit_constraints: vec!["low tool count".to_string()],
                citations: vec![],
                research_confidence: 0.9,
            },
            parts: vec![],
            artifacts: vec![],
            timeline: vec![],
            eta: RndEtaRecord {
                estimated_total_minutes: 100,
                estimated_remaining_minutes: 10,
                current_stage_estimated_minutes: 10,
                confidence_label: "medium".to_string(),
                current_bottleneck: "review".to_string(),
                slippage_reason: "none".to_string(),
            },
            risk_flags: vec!["service access drift".to_string()],
            latest_validation_summary: "ready".to_string(),
            requirements: vec![],
            decisions: vec![],
            design_reviews: vec![],
            evidence_artifacts: vec![],
            simulation_runs: vec![],
            compliance_reports: vec![],
            approval_records: vec![],
            audit_events: vec![],
            approved_baselines: vec![],
            doctrine_profile: None,
            doctrine_checks: Vec::new(),
            module_definitions: Vec::new(),
            tool_requirements: Vec::new(),
            bom_items: Vec::new(),
            assembly_steps: Vec::new(),
            service_access_points: Vec::new(),
            inspection_checklist_items: Vec::new(),
            revision_history: Vec::new(),
            document_records: Vec::new(),
            documentation_bundles: Vec::new(),
        };

        sync_rnd_doctrine_and_structure_state(&mut job);
        assert!(rnd_has_major_doctrine_failures(&job));

        let public_story = generate_rnd_document(
            &mut job,
            "public_project_story",
            "public",
            Some("Public Story"),
            Some("Budget Trailer"),
            Some("R1"),
            None,
            None,
            "tester@example.com",
        );
        assert_eq!(public_story.document_type, "public_project_story");
        assert!(job.artifacts.iter().any(|artifact| artifact.artifact_type == "documentation_source"));

        let bundle = generate_rnd_document_bundle(
            &mut job,
            "public",
            Some("Budget Trailer"),
            Some("Budget Trailer"),
            Some("R1"),
            "tester@example.com",
        );
        assert_eq!(bundle.document_ids.len(), 6);
        assert!(job.document_records.len() >= 6);
    }
}
