mod chunking;
mod tokenize;

use std::cmp::Ordering;
use std::collections::HashSet;
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result};
use atlas_core::{KnowledgeDoc, RetrievedChunk};
use regex::Regex;
use walkdir::WalkDir;

pub use chunking::chunk_document;

pub trait EmbeddingModel: Send + Sync {
    fn model_name(&self) -> &'static str;
    fn embed(&self, text: &str) -> Vec<f32>;
}

#[derive(Debug, Clone)]
pub struct IndexedChunk {
    pub chunk_id: String,
    pub doc_id: String,
    pub title: String,
    pub source_path: String,
    pub text: String,
    pub keywords: HashSet<String>,
    pub embedding: Option<Vec<f32>>,
}

#[derive(Debug, Clone)]
pub struct RetrievalStats {
    pub chunks_loaded: usize,
    pub docs_loaded: usize,
    pub vector_enabled: bool,
}

#[derive(Clone)]
pub struct HybridRetriever {
    docs: Vec<KnowledgeDoc>,
    chunks: Vec<IndexedChunk>,
    embedder: Option<Arc<dyn EmbeddingModel>>,
}

impl HybridRetriever {
    pub fn from_kb_dir(
        path: impl AsRef<Path>,
        embedder: Option<Arc<dyn EmbeddingModel>>,
    ) -> Result<Self> {
        let docs = load_docs(path.as_ref())?;
        let mut chunks = Vec::new();

        for doc in &docs {
            let split = chunk_document(&doc.body, 420);
            for (idx, chunk) in split.iter().enumerate() {
                let chunk_id = format!("{}::{}", doc.id, idx);
                let keywords = tokenize::tokenize(chunk)
                    .into_iter()
                    .collect::<HashSet<_>>();
                let embedding = embedder.as_ref().map(|model| model.embed(chunk));

                chunks.push(IndexedChunk {
                    chunk_id,
                    doc_id: doc.id.clone(),
                    title: doc.title.clone(),
                    source_path: doc.source_path.clone(),
                    text: chunk.clone(),
                    keywords,
                    embedding,
                });
            }
        }

        Ok(Self {
            docs,
            chunks,
            embedder,
        })
    }

    pub fn stats(&self) -> RetrievalStats {
        RetrievalStats {
            chunks_loaded: self.chunks.len(),
            docs_loaded: self.docs.len(),
            vector_enabled: self.embedder.is_some(),
        }
    }

    pub fn search(&self, query: &str, top_k: usize) -> Vec<RetrievedChunk> {
        let query_tokens = tokenize::tokenize(query)
            .into_iter()
            .collect::<HashSet<_>>();
        let query_embedding = self.embedder.as_ref().map(|model| model.embed(query));

        let mut scored = self
            .chunks
            .iter()
            .map(|chunk| {
                let keyword_score = keyword_score(&query_tokens, &chunk.keywords);
                let vector_score = match (&query_embedding, &chunk.embedding) {
                    (Some(q), Some(c)) => cosine_similarity(q, c).max(0.0),
                    _ => 0.0,
                };

                let score = if query_embedding.is_some() {
                    (0.65 * keyword_score) + (0.35 * vector_score)
                } else {
                    keyword_score
                };

                (score, chunk)
            })
            .filter(|(score, _)| *score > 0.0)
            .collect::<Vec<_>>();

        scored.sort_by(|(a, _), (b, _)| b.partial_cmp(a).unwrap_or(Ordering::Equal));

        scored
            .into_iter()
            .take(top_k)
            .map(|(score, chunk)| RetrievedChunk {
                doc_id: chunk.doc_id.clone(),
                title: chunk.title.clone(),
                snippet: snippet(&chunk.text, 220),
                score,
                source_path: chunk.source_path.clone(),
            })
            .collect()
    }

    pub fn list_docs(&self) -> &[KnowledgeDoc] {
        &self.docs
    }
}

fn load_docs(root: &Path) -> Result<Vec<KnowledgeDoc>> {
    let heading_regex = Regex::new(r"(?m)^#\s+(.+)$")?;

    let mut docs = Vec::new();
    for entry in WalkDir::new(root)
        .into_iter()
        .filter_map(std::result::Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            matches!(
                entry.path().extension().and_then(|ext| ext.to_str()),
                Some("md") | Some("json")
            )
        })
    {
        let path = entry.path();
        let raw = std::fs::read_to_string(path)
            .with_context(|| format!("failed reading knowledge document: {}", path.display()))?;

        let is_json = path.extension().and_then(|ext| ext.to_str()) == Some("json");
        let body = if is_json {
            serde_json::from_str::<serde_json::Value>(&raw)
                .map(|value| json_to_search_text(&value))
                .unwrap_or(raw)
        } else {
            raw
        };

        let rel_path = path
            .strip_prefix(root)
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| path.to_string_lossy().to_string());

        let title = heading_regex
            .captures(&body)
            .and_then(|captures| {
                captures
                    .get(1)
                    .map(|value| value.as_str().trim().to_string())
            })
            .unwrap_or_else(|| {
                path.file_stem()
                    .and_then(|stem| stem.to_str())
                    .unwrap_or("untitled")
                    .replace('-', " ")
            });

        let tags = rel_path
            .split('/')
            .take(2)
            .map(|segment| segment.replace(".md", ""))
            .collect::<Vec<_>>();

        docs.push(KnowledgeDoc {
            id: rel_path.replace('/', "::"),
            title,
            source_path: rel_path,
            tags,
            body,
        });
    }

    Ok(docs)
}

fn json_to_search_text(value: &serde_json::Value) -> String {
    match value {
        serde_json::Value::Null => String::new(),
        serde_json::Value::Bool(v) => v.to_string(),
        serde_json::Value::Number(v) => v.to_string(),
        serde_json::Value::String(v) => v.clone(),
        serde_json::Value::Array(values) => values
            .iter()
            .map(json_to_search_text)
            .filter(|v| !v.is_empty())
            .collect::<Vec<_>>()
            .join(" "),
        serde_json::Value::Object(map) => map
            .iter()
            .map(|(k, v)| format!("{} {}", k, json_to_search_text(v)))
            .collect::<Vec<_>>()
            .join(" "),
    }
}

fn keyword_score(query_tokens: &HashSet<String>, doc_tokens: &HashSet<String>) -> f32 {
    if query_tokens.is_empty() || doc_tokens.is_empty() {
        return 0.0;
    }

    let overlap = query_tokens
        .iter()
        .filter(|token| doc_tokens.contains(*token))
        .count() as f32;

    overlap / query_tokens.len() as f32
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.is_empty() || b.is_empty() || a.len() != b.len() {
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

fn snippet(input: &str, max_chars: usize) -> String {
    let compact = input.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= max_chars {
        compact
    } else {
        compact.chars().take(max_chars).collect::<String>() + "..."
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cosine_sanity() {
        let a = [1.0, 0.0, 1.0];
        let b = [1.0, 0.0, 1.0];
        assert!(cosine_similarity(&a, &b) > 0.99);
    }
}
