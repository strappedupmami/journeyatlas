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
use axum::extract::{Json, Path as AxPath, State};
use axum::http::{Method, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Router, body::Body};
use parking_lot::RwLock;
use serde::Serialize;
use tower_http::cors::{Any, CorsLayer};
use tower_http::limit::RequestBodyLimitLayer;
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tower_http::trace::TraceLayer;

use crate::rate_limit::IpRateLimiter;

#[derive(Clone)]
pub struct ApiState {
    pub agent: Arc<ConciergeAgent<Store>>,
    pub metrics: Arc<AppMetrics>,
    pub api_key: String,
    pub limiter: IpRateLimiter,
    pub users: Arc<RwLock<HashMap<String, UserRecord>>>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    timestamp_utc: String,
    metrics: atlas_observability::MetricsSnapshot,
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
struct SocialLoginRequest {
    provider: String,
    email: String,
    name: Option<String>,
    locale: Option<String>,
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize)]
struct ProfileUpsertRequest {
    user_id: String,
    trip_style: Option<String>,
    risk_preference: Option<String>,
    memory_opt_in: Option<bool>,
    locale: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
struct AuthResponse {
    token: String,
    user: UserRecord,
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

    let store = Arc::new(store);

    let agent = Arc::new(ConciergeAgent::new(
        retriever,
        ml_stack,
        policy_set,
        store,
        metrics.clone(),
    ));

    let api_key = env::var("ATLAS_API_KEY").unwrap_or_else(|_| "dev-atlas-key".to_string());

    let state = ApiState {
        agent,
        metrics,
        api_key,
        limiter: IpRateLimiter::new(Duration::from_secs(60), 80),
        users: Arc::new(RwLock::new(HashMap::new())),
    };

    Ok(build_router(state))
}

pub fn build_router(state: ApiState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/chat", post(chat))
        .route("/v1/plan_trip", post(plan_trip))
        .route("/v1/auth/social_login", post(social_login))
        .route("/v1/profile/upsert", post(profile_upsert))
        .route("/v1/auth/me/:user_id", get(auth_me))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
        .layer(PropagateRequestIdLayer::x_request_id())
        .layer(RequestBodyLimitLayer::new(64 * 1024))
        .layer(middleware::from_fn_with_state(state.clone(), api_key_middleware))
        .layer(middleware::from_fn_with_state(state.clone(), rate_limit_middleware))
        .with_state(state)
}

async fn health(State(state): State<ApiState>) -> impl IntoResponse {
    let payload = HealthResponse {
        status: "ok",
        timestamp_utc: chrono::Utc::now().to_rfc3339(),
        metrics: state.metrics.snapshot(),
    };
    (StatusCode::OK, Json(payload))
}

async fn chat(State(state): State<ApiState>, Json(input): Json<ChatInput>) -> impl IntoResponse {
    let request_user_id = input.user_id.clone();
    match state.agent.handle_chat(input).await {
        Ok(mut response) => {
            if let Some(user_id) = request_user_id {
                if let Some(user) = state.users.read().get(&user_id).cloned() {
                    if let Some(payload_obj) = response.json_payload.as_object_mut() {
                        payload_obj.insert("input_user_id".to_string(), serde_json::json!(user_id));
                        payload_obj.insert("user_profile".to_string(), serde_json::json!(user));
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

async fn social_login(
    State(state): State<ApiState>,
    Json(input): Json<SocialLoginRequest>,
) -> impl IntoResponse {
    if input.email.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_email",
                "message": "email is required"
            })),
        )
            .into_response();
    }

    let provider = input.provider.trim().to_lowercase();
    if provider != "google" && provider != "apple" {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({
                "error": "invalid_provider",
                "message": "provider must be google or apple"
            })),
        )
            .into_response();
    }

    let email = input.email.trim().to_lowercase();
    let existing = state
        .users
        .read()
        .values()
        .find(|user| user.email == email && user.provider == provider)
        .cloned();

    let user = if let Some(user) = existing {
        user
    } else {
        let user_id = uuid::Uuid::new_v4().to_string();
        let user = UserRecord {
            user_id: user_id.clone(),
            provider: provider.clone(),
            email: email.clone(),
            name: input.name.unwrap_or_else(|| email.clone()),
            locale: input.locale.unwrap_or_else(|| "he".to_string()),
            trip_style: Some("mixed".to_string()),
            risk_preference: Some("medium".to_string()),
            memory_opt_in: true,
        };
        state.users.write().insert(user_id, user.clone());
        user
    };

    let token = format!("dev-token-{}", user.user_id);
    (StatusCode::OK, Json(AuthResponse { token, user })).into_response()
}

async fn profile_upsert(
    State(state): State<ApiState>,
    Json(input): Json<ProfileUpsertRequest>,
) -> impl IntoResponse {
    let mut users = state.users.write();
    let Some(user) = users.get_mut(&input.user_id) else {
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
        user.trip_style = Some(style);
    }
    if let Some(risk) = input.risk_preference {
        user.risk_preference = Some(risk);
    }
    if let Some(opt_in) = input.memory_opt_in {
        user.memory_opt_in = opt_in;
    }
    if let Some(locale) = input.locale {
        user.locale = locale;
    }

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "ok": true,
            "user": user
        })),
    )
        .into_response()
}

async fn auth_me(
    State(state): State<ApiState>,
    AxPath(user_id): AxPath<String>,
) -> impl IntoResponse {
    let users = state.users.read();
    let Some(user) = users.get(&user_id).cloned() else {
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({
                "error": "user_not_found"
            })),
        )
            .into_response();
    };

    (StatusCode::OK, Json(serde_json::json!({ "user": user }))).into_response()
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
    if request.uri().path() == "/health" || request.method() == Method::OPTIONS {
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

async fn rate_limit_middleware(
    State(state): State<ApiState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    if request.uri().path() == "/health" || request.method() == Method::OPTIONS {
        return next.run(request).await;
    }

    let ip = request
        .headers()
        .get("x-forwarded-for")
        .and_then(|value| value.to_str().ok())
        .map(|value| value.split(',').next().unwrap_or("unknown").trim().to_string())
        .unwrap_or_else(|| "local".to_string());

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
