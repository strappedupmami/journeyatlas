mod fallback;
mod centroid;

#[cfg(feature = "burn-ml")]
mod burn_impl;

use std::env;
use std::path::Path;
use std::sync::Arc;

use atlas_core::{classify_intent_rules, Intent};
use atlas_retrieval::EmbeddingModel;

use centroid::CentroidIntentClassifier;
pub use fallback::HashEmbeddingModel;

#[derive(Debug, Clone)]
pub struct IntentPrediction {
    pub intent: Intent,
    pub confidence: f32,
    pub model: &'static str,
}

pub trait IntentClassifier: Send + Sync {
    fn predict(&self, text: &str) -> IntentPrediction;
}

#[derive(Debug, Default)]
pub struct RuleIntentClassifier;

impl IntentClassifier for RuleIntentClassifier {
    fn predict(&self, text: &str) -> IntentPrediction {
        IntentPrediction {
            intent: classify_intent_rules(text),
            confidence: 0.62,
            model: "rules",
        }
    }
}

#[derive(Clone)]
pub struct AtlasMlStack {
    pub embedder: Arc<dyn EmbeddingModel>,
    pub classifier: Arc<dyn IntentClassifier>,
    pub burn_enabled: bool,
}

impl AtlasMlStack {
    pub fn load_default() -> Self {
        let dataset_path = env::var("ATLAS_INTENT_DATASET")
            .unwrap_or_else(|_| "kb/training/intent_he.jsonl".to_string());

        #[cfg(feature = "burn-ml")]
        {
            let embedder = Arc::new(burn_impl::BurnHashEmbeddingModel::new(192));
            let classifier: Arc<dyn IntentClassifier> = if Path::new(&dataset_path).exists() {
                CentroidIntentClassifier::from_jsonl(&dataset_path, embedder.clone(), "burn-centroid-intent")
                    .map(|clf| Arc::new(clf) as Arc<dyn IntentClassifier>)
                    .unwrap_or_else(|_| Arc::new(burn_impl::BurnKeywordIntentClassifier::new(192)))
            } else {
                Arc::new(burn_impl::BurnKeywordIntentClassifier::new(192))
            };
            return Self {
                embedder,
                classifier,
                burn_enabled: true,
            };
        }

        #[cfg(not(feature = "burn-ml"))]
        {
            let embedder = Arc::new(HashEmbeddingModel::new(192));
            let classifier: Arc<dyn IntentClassifier> = if Path::new(&dataset_path).exists() {
                CentroidIntentClassifier::from_jsonl(&dataset_path, embedder.clone(), "fallback-centroid-intent")
                    .map(|clf| Arc::new(clf) as Arc<dyn IntentClassifier>)
                    .unwrap_or_else(|_| Arc::new(RuleIntentClassifier))
            } else {
                Arc::new(RuleIntentClassifier)
            };
            Self {
                embedder,
                classifier,
                burn_enabled: false,
            }
        }
    }
}
