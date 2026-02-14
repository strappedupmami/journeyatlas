use std::fs;
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result};
use atlas_core::Intent;
use atlas_retrieval::EmbeddingModel;
use serde::Deserialize;

use crate::{IntentClassifier, IntentPrediction};

#[derive(Debug, Deserialize)]
struct LabeledExample {
    text: String,
    intent: String,
}

#[derive(Clone)]
pub struct CentroidIntentClassifier {
    model_name: &'static str,
    centroids: Vec<(Intent, Vec<f32>)>,
    embedder: Arc<dyn EmbeddingModel>,
}

impl CentroidIntentClassifier {
    pub fn from_jsonl(
        path: impl AsRef<Path>,
        embedder: Arc<dyn EmbeddingModel>,
        model_name: &'static str,
    ) -> Result<Self> {
        let raw = fs::read_to_string(path.as_ref()).with_context(|| {
            format!(
                "failed reading intent training dataset at {}",
                path.as_ref().display()
            )
        })?;

        let mut by_intent: std::collections::HashMap<Intent, Vec<Vec<f32>>> =
            std::collections::HashMap::new();

        for line in raw.lines().map(str::trim).filter(|line| !line.is_empty()) {
            let example: LabeledExample =
                serde_json::from_str(line).context("invalid jsonl training line")?;
            if let Some(intent) = parse_intent(&example.intent) {
                by_intent
                    .entry(intent)
                    .or_default()
                    .push(embedder.embed(&example.text));
            }
        }

        let mut centroids = Vec::new();
        for (intent, vectors) in by_intent {
            if vectors.is_empty() {
                continue;
            }
            centroids.push((intent, centroid(&vectors)));
        }

        if centroids.is_empty() {
            anyhow::bail!("training dataset produced zero intent centroids");
        }

        Ok(Self {
            model_name,
            centroids,
            embedder,
        })
    }
}

impl IntentClassifier for CentroidIntentClassifier {
    fn predict(&self, text: &str) -> IntentPrediction {
        let query = self.embedder.embed(text);
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
            model: self.model_name,
        }
    }
}

fn parse_intent(value: &str) -> Option<Intent> {
    match value.trim().to_lowercase().as_str() {
        "trip_planning" => Some(Intent::TripPlanning),
        "ops_checklist" => Some(Intent::OpsChecklist),
        "policy" => Some(Intent::Policy),
        "pricing" => Some(Intent::Pricing),
        "troubleshooting" => Some(Intent::Troubleshooting),
        "content" => Some(Intent::Content),
        "small_talk" => Some(Intent::SmallTalk),
        "unknown" => Some(Intent::Unknown),
        _ => None,
    }
}

fn centroid(vectors: &[Vec<f32>]) -> Vec<f32> {
    let dims = vectors.first().map(Vec::len).unwrap_or(0);
    let mut acc = vec![0.0_f32; dims];

    for vector in vectors {
        for (idx, value) in vector.iter().enumerate() {
            acc[idx] += value;
        }
    }

    for value in &mut acc {
        *value /= vectors.len() as f32;
    }
    normalize(&mut acc);
    acc
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
        0.0
    } else {
        dot / (a_norm.sqrt() * b_norm.sqrt())
    }
}

fn normalize(values: &mut [f32]) {
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in values.iter_mut() {
            *value /= norm;
        }
    }
}
