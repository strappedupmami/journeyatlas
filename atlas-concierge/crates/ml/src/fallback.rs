use atlas_retrieval::EmbeddingModel;

#[derive(Debug, Clone)]
pub struct HashEmbeddingModel {
    dims: usize,
}

impl HashEmbeddingModel {
    pub fn new(dims: usize) -> Self {
        Self { dims: dims.max(32) }
    }
}

impl EmbeddingModel for HashEmbeddingModel {
    fn model_name(&self) -> &'static str {
        "hash-fallback"
    }

    fn embed(&self, text: &str) -> Vec<f32> {
        let mut vec = vec![0.0_f32; self.dims];

        for token in text.split_whitespace() {
            let hash = fxhash(token.as_bytes());
            let index = (hash as usize) % self.dims;
            let sign = if (hash & 1) == 0 { 1.0 } else { -1.0 };
            vec[index] += sign;
        }

        normalize(&mut vec);
        vec
    }
}

fn fxhash(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in bytes {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn normalize(values: &mut [f32]) {
    let norm = values.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        for value in values.iter_mut() {
            *value /= norm;
        }
    }
}
