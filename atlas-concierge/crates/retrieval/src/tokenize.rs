use regex::Regex;

pub fn tokenize(input: &str) -> Vec<String> {
    let cleaner = Regex::new(r"[^\p{Hebrew}\p{Latin}\p{Nd}\s]+").expect("valid tokenizer regex");
    let normalized = cleaner.replace_all(input, " ").to_lowercase();

    normalized
        .split_whitespace()
        .map(str::trim)
        .filter(|token| token.chars().count() > 1)
        .map(|token| token.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenizes_hebrew_and_english() {
        let tokens = tokenize("מים אפורים + grey water");
        assert!(tokens.iter().any(|t| t == "מים"));
        assert!(tokens.iter().any(|t| t == "grey"));
    }
}
