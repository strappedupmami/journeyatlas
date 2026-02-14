mod rate_limit;

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
use axum::extract::{Json, State};
use axum::http::{Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Router, body::Body};
use serde::Serialize;
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
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    timestamp_utc: String,
    metrics: atlas_observability::MetricsSnapshot,
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
    };

    Ok(build_router(state))
}

pub fn build_router(state: ApiState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/chat", post(chat))
        .route("/v1/plan_trip", post(plan_trip))
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
    match state.agent.handle_chat(input).await {
        Ok(response) => (StatusCode::OK, Json(response)).into_response(),
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
    if request.uri().path() == "/health" {
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
    if request.uri().path() == "/health" {
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
