use std::env;

use anyhow::Result;
use atlas_api::build_app;
use atlas_observability::init_tracing;

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing("atlas_api");

    let kb_root = env::var("ATLAS_KB_ROOT").unwrap_or_else(|_| "kb".to_string());
    let bind = env::var("ATLAS_BIND")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .or_else(|| {
            env::var("PORT")
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .map(|port| format!("0.0.0.0:{port}"))
        })
        .unwrap_or_else(|| "0.0.0.0:8080".to_string());

    let app = build_app(&kb_root).await?;

    let listener = tokio::net::TcpListener::bind(&bind).await?;
    tracing::info!(bind = %bind, kb_root = %kb_root, "atlas concierge api started");

    axum::serve(listener, app).await?;
    Ok(())
}
