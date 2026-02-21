use std::path::PathBuf;

use atlas_api::build_app;
use axum::body::{to_bytes, Body};
use axum::http::{Request, StatusCode};
use serde_json::json;
use tower::ServiceExt;

fn kb_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../kb")
}

fn allowed_origin() -> &'static str {
    "http://localhost:5500"
}

#[tokio::test]
async fn health_is_public() {
    let app = build_app(kb_root()).await.expect("app should build");

    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
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
async fn chat_requires_signin_for_first_party_origin_without_api_key() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/chat")
        .header("origin", allowed_origin())
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "text": "Build a daily execution plan"
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        parsed.get("error").and_then(|value| value.as_str()),
        Some("not_authenticated")
    );
}

#[tokio::test]
async fn chat_blocks_untrusted_origin_without_api_key() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/chat")
        .header("origin", "https://evil.example")
        .header("content-type", "application/json")
        .body(Body::from(
            json!({
                "text": "Build a daily execution plan"
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
async fn legacy_social_login_is_retired() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/auth/social_login")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::from("{}"))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::GONE);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        parsed.get("error").and_then(|value| value.as_str()),
        Some("legacy_auth_retired")
    );
    assert!(parsed
        .get("allowed_methods")
        .and_then(|value| value.as_array())
        .map(|value| !value.is_empty())
        .unwrap_or(false));
}

#[tokio::test]
async fn csrf_origin_required_for_cookie_state_changes() {
    let app = build_app(kb_root()).await.expect("app should build");

    let request = Request::builder()
        .method("POST")
        .uri("/v1/profile/upsert")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("cookie", "atlas_session=fake-session-id")
        .body(Body::from(
            json!({
                "trip_style": "beach",
                "memory_opt_in": true
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        parsed.get("error").and_then(|value| value.as_str()),
        Some("origin_required")
    );
}

#[tokio::test]
async fn auth_endpoints_are_rate_limited_under_abuse() {
    let app = build_app(kb_root()).await.expect("app should build");
    let mut blocked = false;

    for _ in 0..30 {
        let request = Request::builder()
            .method("POST")
            .uri("/v1/auth/passkey/login/start")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "email": "abuse-test@example.com"
                })
                .to_string(),
            ))
            .unwrap();
        let response = app.clone().oneshot(request).await.unwrap();
        if response.status() == StatusCode::TOO_MANY_REQUESTS {
            blocked = true;
            let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
            let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
            assert_eq!(
                parsed.get("error").and_then(|value| value.as_str()),
                Some("auth_rate_limited")
            );
            break;
        }
    }

    assert!(blocked, "auth abuse should eventually be rate limited");
}

#[tokio::test]
async fn survey_feed_and_actions_flow_in_guest_mode() {
    let app = build_app(kb_root()).await.expect("app should build");

    let survey_next_request = Request::builder()
        .method("GET")
        .uri("/v1/survey/next?locale=en")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::empty())
        .unwrap();
    let survey_next_response = app.clone().oneshot(survey_next_request).await.unwrap();
    assert_eq!(survey_next_response.status(), StatusCode::OK);

    let survey_answer_request = Request::builder()
        .method("POST")
        .uri("/v1/survey/answer")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("origin", allowed_origin())
        .body(Body::from(
            json!({
                "question_id": "primary_goal",
                "answer": "wealth",
                "locale": "en"
            })
            .to_string(),
        ))
        .unwrap();
    let survey_answer_response = app.clone().oneshot(survey_answer_request).await.unwrap();
    assert_eq!(survey_answer_response.status(), StatusCode::OK);

    let feed_request = Request::builder()
        .method("GET")
        .uri("/v1/feed/proactive?locale=en")
        .header("x-api-key", "dev-atlas-key")
        .body(Body::empty())
        .unwrap();
    let feed_response = app.clone().oneshot(feed_request).await.unwrap();
    assert_eq!(feed_response.status(), StatusCode::OK);

    let reminder_request = Request::builder()
        .method("POST")
        .uri("/v1/actions/reminder")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("origin", allowed_origin())
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
        .header("origin", allowed_origin())
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

#[tokio::test]
async fn reminder_action_supports_each_app_path() {
    let app = build_app(kb_root()).await.expect("app should build");
    let reminders_apps = [
        "google_calendar",
        "apple_reminders",
        "shortcuts",
        "todoist",
        "notion",
    ];

    for reminders_app in reminders_apps {
        let request = Request::builder()
            .method("POST")
            .uri("/v1/actions/reminder")
            .header("content-type", "application/json")
            .header("x-api-key", "dev-atlas-key")
            .header("origin", allowed_origin())
            .body(Body::from(
                json!({
                    "title": format!("Atlas {}", reminders_app),
                    "details": "integration coverage",
                    "due_at_utc": "2026-03-01T08:30:00Z",
                    "duration_minutes": 45,
                    "reminders_app": reminders_app
                })
                .to_string(),
            ))
            .unwrap();

        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(
            response.status(),
            StatusCode::OK,
            "reminders path should succeed for {reminders_app}"
        );
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();

        assert_eq!(
            parsed.get("app").and_then(|value| value.as_str()),
            Some(reminders_app)
        );
        assert_eq!(
            parsed
                .get("supports_direct_write")
                .and_then(|value| value.as_bool()),
            Some(false)
        );
        assert_eq!(
            parsed
                .get("fallback_used")
                .and_then(|value| value.as_bool()),
            Some(true)
        );
        assert!(parsed
            .get("ics_content")
            .and_then(|value| value.as_str())
            .map(|value| value.contains("BEGIN:VCALENDAR"))
            .unwrap_or(false));
        assert!(parsed
            .get("user_message")
            .and_then(|value| value.as_str())
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false));
        assert_eq!(
            parsed
                .get("telemetry")
                .and_then(|value| value.get("action"))
                .and_then(|value| value.as_str()),
            Some("reminder")
        );
        assert_eq!(
            parsed
                .get("telemetry")
                .and_then(|value| value.get("success"))
                .and_then(|value| value.as_bool()),
            Some(true)
        );

        let primary_url = parsed
            .get("primary_url")
            .and_then(|value| value.as_str())
            .unwrap_or_default()
            .to_string();
        match reminders_app {
            "google_calendar" => assert!(primary_url.starts_with("https://calendar.google.com/")),
            "shortcuts" => assert!(primary_url.starts_with("shortcuts://")),
            "todoist" => assert!(primary_url.starts_with("https://todoist.com/")),
            "notion" => assert_eq!(primary_url, "https://www.notion.so"),
            "apple_reminders" => assert!(!primary_url.is_empty()),
            _ => unreachable!("unexpected reminders app in test"),
        }
    }
}

#[tokio::test]
async fn alarm_action_supports_each_app_path() {
    let app = build_app(kb_root()).await.expect("app should build");
    let alarms_apps = ["apple_clock", "google_clock", "shortcuts"];

    for alarms_app in alarms_apps {
        let request = Request::builder()
            .method("POST")
            .uri("/v1/actions/alarm")
            .header("content-type", "application/json")
            .header("x-api-key", "dev-atlas-key")
            .header("origin", allowed_origin())
            .body(Body::from(
                json!({
                    "label": format!("Atlas {}", alarms_app),
                    "time_local": "07:45",
                    "days": ["Mon", "Tue", "Wed"],
                    "alarms_app": alarms_app
                })
                .to_string(),
            ))
            .unwrap();

        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(
            response.status(),
            StatusCode::OK,
            "alarms path should succeed for {alarms_app}"
        );
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();

        assert_eq!(
            parsed.get("app").and_then(|value| value.as_str()),
            Some(alarms_app)
        );
        assert_eq!(
            parsed
                .get("supports_direct_write")
                .and_then(|value| value.as_bool()),
            Some(false)
        );
        assert_eq!(
            parsed
                .get("fallback_used")
                .and_then(|value| value.as_bool()),
            Some(true)
        );
        assert!(parsed
            .get("user_message")
            .and_then(|value| value.as_str())
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false));
        assert!(parsed
            .get("fallback_instructions")
            .and_then(|value| value.as_str())
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false));
        assert_eq!(
            parsed
                .get("telemetry")
                .and_then(|value| value.get("action"))
                .and_then(|value| value.as_str()),
            Some("alarm")
        );
        assert_eq!(
            parsed
                .get("telemetry")
                .and_then(|value| value.get("success"))
                .and_then(|value| value.as_bool()),
            Some(true)
        );

        let primary_url = parsed
            .get("primary_url")
            .and_then(|value| value.as_str())
            .unwrap_or_default()
            .to_string();
        match alarms_app {
            "apple_clock" => assert!(primary_url.starts_with("clock://")),
            "google_clock" => assert!(primary_url.starts_with("intent://")),
            "shortcuts" => assert!(!primary_url.is_empty()),
            _ => unreachable!("unexpected alarms app in test"),
        }
    }
}

#[tokio::test]
async fn reminder_error_response_contains_failure_telemetry() {
    let app = build_app(kb_root()).await.expect("app should build");
    let request = Request::builder()
        .method("POST")
        .uri("/v1/actions/reminder")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("origin", allowed_origin())
        .body(Body::from(
            json!({
                "title": "   ",
                "reminders_app": "google_calendar"
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        parsed
            .get("telemetry")
            .and_then(|value| value.get("success"))
            .and_then(|value| value.as_bool()),
        Some(false)
    );
    assert_eq!(
        parsed
            .get("telemetry")
            .and_then(|value| value.get("action"))
            .and_then(|value| value.as_str()),
        Some("reminder")
    );
}

#[tokio::test]
async fn alarm_error_response_contains_failure_telemetry() {
    let app = build_app(kb_root()).await.expect("app should build");
    let request = Request::builder()
        .method("POST")
        .uri("/v1/actions/alarm")
        .header("content-type", "application/json")
        .header("x-api-key", "dev-atlas-key")
        .header("origin", allowed_origin())
        .body(Body::from(
            json!({
                "label": "Atlas",
                "time_local": "25:99",
                "alarms_app": "apple_clock"
            })
            .to_string(),
        ))
        .unwrap();

    let response = app.oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        parsed
            .get("telemetry")
            .and_then(|value| value.get("success"))
            .and_then(|value| value.as_bool()),
        Some(false)
    );
    assert_eq!(
        parsed
            .get("telemetry")
            .and_then(|value| value.get("action"))
            .and_then(|value| value.as_str()),
        Some("alarm")
    );
}
