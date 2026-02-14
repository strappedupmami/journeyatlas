use std::env;

use anyhow::Result;
use atlas_api::build_app;
use atlas_observability::init_tracing;

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing("atlas_api");

    let kb_root = env::var("ATLAS_KB_ROOT").unwrap_or_else(|_| "kb".to_string());
    let bind = env::var("ATLAS_BIND").unwrap_or_else(|_| "0.0.0.0:8080".to_string());

    let app = build_app(&kb_root).await?;

    let listener = tokio::net::TcpListener::bind(&bind).await?;
    tracing::info!(bind = %bind, kb_root = %kb_root, "atlas concierge api started");

    axum::serve(listener, app).await?;
    Ok(())
}
