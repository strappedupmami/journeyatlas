pub fn chunk_document(body: &str, max_chunk_chars: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut current = String::new();

    for paragraph in body.split("\n\n") {
        let trimmed = paragraph.trim();
        if trimmed.is_empty() {
            continue;
        }

        if current.len() + trimmed.len() + 2 > max_chunk_chars && !current.is_empty() {
            chunks.push(current.trim().to_string());
            current.clear();
        }

        if !current.is_empty() {
            current.push_str("\n\n");
        }
        current.push_str(trimmed);
    }

    if !current.trim().is_empty() {
        chunks.push(current.trim().to_string());
    }

    chunks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_multiple_chunks() {
        let body = "# title\n\nabc\n\n".repeat(40);
        let chunks = chunk_document(&body, 120);
        assert!(chunks.len() > 1);
    }
}
