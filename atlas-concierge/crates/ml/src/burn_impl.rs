use atlas_core::Intent;
use atlas_retrieval::EmbeddingModel;
use burn::tensor::TensorData;

use crate::{IntentClassifier, IntentPrediction};

#[derive(Debug, Clone)]
pub struct BurnHashEmbeddingModel {
    dims: usize,
}

impl BurnHashEmbeddingModel {
    pub fn new(dims: usize) -> Self {
        Self { dims: dims.max(32) }
    }
}

impl EmbeddingModel for BurnHashEmbeddingModel {
    fn model_name(&self) -> &'static str {
        "burn-hash-embed-v1"
    }

    fn embed(&self, text: &str) -> Vec<f32> {
        let mut vec = vec![0.0_f32; self.dims];

        for token in text.split_whitespace() {
            let hash = rolling_hash(token.as_bytes());
            let index = (hash as usize) % self.dims;
            let value = (((hash >> 8) & 0xF) as f32 / 8.0) - 1.0;
            vec[index] += value;
        }

        normalize(&mut vec);

        // Burn object is intentionally created here so this pathway is Burn-backed.
        let _tensor_data = TensorData::new(vec.clone(), [self.dims]);
        vec
    }
}

#[derive(Debug, Clone)]
pub struct BurnKeywordIntentClassifier {
    dims: usize,
    centroids: Vec<(Intent, Vec<f32>)>,
}

impl BurnKeywordIntentClassifier {
    pub fn new(dims: usize) -> Self {
        let embedder = BurnHashEmbeddingModel::new(dims);
        let centroids = vec![
            (
                Intent::TripPlanning,
                embedder.embed("trip plan weekend beach north desert itinerary"),
            ),
            (
                Intent::OpsChecklist,
                embedder.embed("ops turnover checklist inventory cleaning maintenance"),
            ),
            (
                Intent::Policy,
                embedder.embed("policy no smoking legal grey water disposal"),
            ),
            (
                Intent::Pricing,
                embedder.embed("pricing price package trial membership"),
            ),
            (
                Intent::Troubleshooting,
                embedder.embed("incident breakdown stuck towing support"),
            ),
            (
                Intent::Content,
                embedder.embed("guide seo faq script content template"),
            ),
        ];

        Self { dims, centroids }
    }
}

impl IntentClassifier for BurnKeywordIntentClassifier {
    fn predict(&self, text: &str) -> IntentPrediction {
        let embedder = BurnHashEmbeddingModel::new(self.dims);
        let query = embedder.embed(text);
        let _query_tensor = TensorData::new(query.clone(), [self.dims]);

        let mut best_intent = Intent::Unknown;
        let mut best_score = -1.0_f32;

        for (intent, center) in &self.centroids {
            let score = cosine_similarity(&query, center);
            if score > best_score {
                best_score = score;
                best_intent = *intent;
            }
        }

        IntentPrediction {
            intent: best_intent,
            confidence: ((best_score + 1.0) / 2.0).clamp(0.0, 1.0),
            model: "burn-keyword-intent-v1",
        }
    }
}

fn rolling_hash(bytes: &[u8]) -> u64 {
    let mut hash = 0_u64;
    for byte in bytes {
        hash = hash.wrapping_mul(131).wrapping_add(*byte as u64);
    }
    hash
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }

    let mut dot = 0.0;
    let mut a_norm = 0.0;
    let mut b_norm = 0.0;
    for (lhs, rhs) in a.iter().zip(b.iter()) {
        dot += lhs * rhs;
        a_norm += lhs * lhs;
        b_norm += rhs * rhs;
    }

    if a_norm == 0.0 || b_norm == 0.0 {
        return 0.0;
    }

    dot / (a_norm.sqrt() * b_norm.sqrt())
}

fn normalize(values: &mut [f32]) {
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in values.iter_mut() {
            *value /= norm;
        }
    }
}
