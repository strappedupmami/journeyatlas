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

#[tokio::test]
async fn social_login_sets_cookie_and_auth_me_uses_session() {
    let app = build_app(kb_root()).await.expect("app should build");

    let login_request = Request::builder()
        .method("POST")
        .uri("/v1/auth/social_login")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::from(
            json!({
                "provider": "apple",
                "email": "test@example.com",
                "name": "Test User",
                "locale": "he"
            })
            .to_string(),
        ))
        .unwrap();

    let login_response = app.clone().oneshot(login_request).await.unwrap();
    assert_eq!(login_response.status(), StatusCode::OK);
    let set_cookie = login_response
        .headers()
        .get("set-cookie")
        .and_then(|value| value.to_str().ok())
        .expect("set-cookie header should be present");
    let cookie_pair = set_cookie
        .split(';')
        .next()
        .expect("cookie pair should be present")
        .to_string();

    let me_request = Request::builder()
        .method("GET")
        .uri("/v1/auth/me")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::empty())
        .unwrap();

    let me_response = app.clone().oneshot(me_request).await.unwrap();
    assert_eq!(me_response.status(), StatusCode::OK);

    let profile_request = Request::builder()
        .method("POST")
        .uri("/v1/profile/upsert")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair)
        .body(Body::from(
            json!({
                "trip_style": "beach",
                "risk_preference": "low",
                "memory_opt_in": true,
                "locale": "he"
            })
            .to_string(),
        ))
        .unwrap();

    let profile_response = app.oneshot(profile_request).await.unwrap();
    assert_eq!(profile_response.status(), StatusCode::OK);
}

#[tokio::test]
async fn studio_survey_feed_and_actions_flow() {
    let app = build_app(kb_root()).await.expect("app should build");

    let login_request = Request::builder()
        .method("POST")
        .uri("/v1/auth/social_login")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::from(
            json!({
                "provider": "google",
                "email": "studio@example.com",
                "name": "Studio User",
                "locale": "he"
            })
            .to_string(),
        ))
        .unwrap();

    let login_response = app.clone().oneshot(login_request).await.unwrap();
    assert_eq!(login_response.status(), StatusCode::OK);
    let set_cookie = login_response
        .headers()
        .get("set-cookie")
        .and_then(|value| value.to_str().ok())
        .expect("set-cookie should be set");
    let cookie_pair = set_cookie
        .split(';')
        .next()
        .expect("cookie pair should exist")
        .to_string();

    let save_studio_request = Request::builder()
        .method("POST")
        .uri("/v1/studio/preferences")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::from(
            json!({
                "preferred_format": "notebook_style",
                "response_depth": "deep",
                "response_tone": "coach",
                "proactive_mode": "enabled",
                "reminders_app": "google_calendar",
                "alarms_app": "apple_clock",
                "voice_mode": "enabled"
            })
            .to_string(),
        ))
        .unwrap();
    let save_studio_response = app.clone().oneshot(save_studio_request).await.unwrap();
    assert_eq!(save_studio_response.status(), StatusCode::OK);

    let survey_next_request = Request::builder()
        .method("GET")
        .uri("/v1/survey/next")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::empty())
        .unwrap();
    let survey_next_response = app.clone().oneshot(survey_next_request).await.unwrap();
    assert_eq!(survey_next_response.status(), StatusCode::OK);

    let survey_answer_request = Request::builder()
        .method("POST")
        .uri("/v1/survey/answer")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::from(
            json!({
                "question_id": "primary_goal",
                "answer": "wealth"
            })
            .to_string(),
        ))
        .unwrap();
    let survey_answer_response = app.clone().oneshot(survey_answer_request).await.unwrap();
    assert_eq!(survey_answer_response.status(), StatusCode::OK);

    let feed_request = Request::builder()
        .method("GET")
        .uri("/v1/feed/proactive")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::empty())
        .unwrap();
    let feed_response = app.clone().oneshot(feed_request).await.unwrap();
    assert_eq!(feed_response.status(), StatusCode::OK);

    let reminder_request = Request::builder()
        .method("POST")
        .uri("/v1/actions/reminder")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair.clone())
        .body(Body::from(
            json!({
                "title": "Atlas reminder",
                "details": "review daily plan"
            })
            .to_string(),
        ))
        .unwrap();
    let reminder_response = app.clone().oneshot(reminder_request).await.unwrap();
    assert_eq!(reminder_response.status(), StatusCode::OK);

    let alarm_request = Request::builder()
        .method("POST")
        .uri("/v1/actions/alarm")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", cookie_pair)
        .body(Body::from(
            json!({
                "label": "Atlas focus",
                "time_local": "08:30",
                "days": ["Sun", "Mon"]
            })
            .to_string(),
        ))
        .unwrap();
    let alarm_response = app.oneshot(alarm_request).await.unwrap();
    assert_eq!(alarm_response.status(), StatusCode::OK);
}
