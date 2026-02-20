use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use once_cell::sync::OnceCell;
use serde::Serialize;
use tracing_subscriber::EnvFilter;

static TRACING_INIT: OnceCell<()> = OnceCell::new();

#[derive(Debug, Default)]
pub struct AppMetrics {
    requests_total: AtomicU64,
    retrieval_hits_total: AtomicU64,
    fallback_total: AtomicU64,
    ml_inference_total: AtomicU64,
    total_latency_millis: AtomicU64,
}

#[derive(Debug, Clone, Serialize)]
pub struct MetricsSnapshot {
    pub requests_total: u64,
    pub retrieval_hits_total: u64,
    pub fallback_total: u64,
    pub ml_inference_total: u64,
    pub avg_latency_millis: f64,
}

impl AppMetrics {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub fn inc_request(&self) {
        self.requests_total.fetch_add(1, Ordering::Relaxed);
    }

    pub fn add_retrieval_hits(&self, hits: usize) {
        self.retrieval_hits_total
            .fetch_add(hits as u64, Ordering::Relaxed);
    }

    pub fn inc_fallback(&self) {
        self.fallback_total.fetch_add(1, Ordering::Relaxed);
    }

    pub fn inc_ml_inference(&self) {
        self.ml_inference_total.fetch_add(1, Ordering::Relaxed);
    }

    pub fn observe_latency(&self, duration: Duration) {
        self.total_latency_millis
            .fetch_add(duration.as_millis() as u64, Ordering::Relaxed);
    }

    pub fn snapshot(&self) -> MetricsSnapshot {
        let requests = self.requests_total.load(Ordering::Relaxed);
        let latency = self.total_latency_millis.load(Ordering::Relaxed);

        MetricsSnapshot {
            requests_total: requests,
            retrieval_hits_total: self.retrieval_hits_total.load(Ordering::Relaxed),
            fallback_total: self.fallback_total.load(Ordering::Relaxed),
            ml_inference_total: self.ml_inference_total.load(Ordering::Relaxed),
            avg_latency_millis: if requests == 0 {
                0.0
            } else {
                latency as f64 / requests as f64
            },
        }
    }
}

pub fn init_tracing(service_name: &str) {
    TRACING_INIT.get_or_init(|| {
        let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
            EnvFilter::new(format!(
                "{}=info,atlas_api=info,atlas_agents=info",
                service_name
            ))
        });

        tracing_subscriber::fmt()
            .json()
            .with_env_filter(filter)
            .with_current_span(true)
            .with_span_list(true)
            .init();
    });
}
