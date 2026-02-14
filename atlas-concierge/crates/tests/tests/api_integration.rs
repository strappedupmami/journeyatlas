use std::path::PathBuf;

use atlas_api::build_app;
use axum::body::{Body, to_bytes};
use axum::http::{Request, StatusCode};
use serde_json::json;
use tower::ServiceExt;

fn kb_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../kb")
}

#[tokio::test]
async fn health_is_public() {
    let app = build_app(kb_root()).await.expect("app should build");

    let response = app
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn chat_requires_api_key() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/chat")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "text": "תן לי מסלול חוף לסופ״ש"
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn chat_returns_structured_payload() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/chat")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::from(
            json!({
                "text": "אני רוצה תכנון מסלול מדברי ליומיים"
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(parsed.get("reply_text").is_some());
    assert!(parsed.get("json_payload").is_some());
}
