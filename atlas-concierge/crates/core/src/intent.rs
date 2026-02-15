use crate::models::{Intent, Locale};

pub fn normalize_text(input: &str) -> String {
    input
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string()
}

pub fn detect_locale(explicit: Option<Locale>, text: &str) -> Locale {
    if let Some(locale) = explicit {
        if locale != Locale::Unknown {
            return locale;
        }
    }

    let mut hebrew_count = 0usize;
    let mut arabic_count = 0usize;
    let mut cyrillic_count = 0usize;
    let mut latin_count = 0usize;

    for ch in text.chars() {
        let code = ch as u32;
        if (0x0590..=0x05FF).contains(&code) {
            hebrew_count += 1;
        } else if (0x0600..=0x06FF).contains(&code) {
            arabic_count += 1;
        } else if (0x0400..=0x04FF).contains(&code) {
            cyrillic_count += 1;
        } else if ch.is_ascii_alphabetic() {
            latin_count += 1;
        }
    }

    if hebrew_count > latin_count && hebrew_count > 0 {
        Locale::He
    } else if arabic_count > 0 {
        Locale::Ar
    } else if cyrillic_count > 0 {
        Locale::Ru
    } else if latin_count > 0 {
        Locale::En
    } else {
        Locale::Unknown
    }
}

pub fn classify_intent_rules(text: &str) -> Intent {
    let lower = text.to_lowercase();

    if contains_any(
        &lower,
        &[
            "מסלול",
            "טיול",
            "plan",
            "trip",
            "weekend",
            "חוף",
            "צפון",
            "מדבר",
            "כנרת",
            "אילת",
        ],
    ) {
        return Intent::TripPlanning;
    }

    if contains_any(
        &lower,
        &[
            "sop",
            "checklist",
            "turnover",
            "ops",
            "מלאי",
            "ציוד",
            "ניקיון",
            "תחזוקה",
            "תקלה",
            "גרירה",
        ],
    ) {
        return Intent::OpsChecklist;
    }

    if contains_any(
        &lower,
        &[
            "policy",
            "מדיניות",
            "עישון",
            "מים אפורים",
            "grey",
            "no smoking",
            "חוקי",
            "deposit",
        ],
    ) {
        return Intent::Policy;
    }

    if contains_any(
        &lower,
        &[
            "price",
            "pricing",
            "cost",
            "מחיר",
            "כמה עולה",
            "מסע חווייתי",
            "מנוי מסע",
        ],
    ) {
        return Intent::Pricing;
    }

    if contains_any(
        &lower,
        &[
            "problem",
            "broken",
            "stuck",
            "תקוע",
            "בעיה",
            "לא עובד",
            "breakdown",
            "incident",
        ],
    ) {
        return Intent::Troubleshooting;
    }

    if contains_any(
        &lower,
        &[
            "guide",
            "content",
            "seo",
            "faq",
            "מדריך",
            "תוכן",
            "תסריט",
            "כתיבה",
        ],
    ) {
        return Intent::Content;
    }

    if contains_any(&lower, &["hello", "hi", "היי", "שלום", "מה נשמע"]) {
        return Intent::SmallTalk;
    }

    Intent::Unknown
}

pub fn needs_clarification(intent: Intent, text: &str) -> bool {
    let short = text.split_whitespace().count() <= 3;

    match intent {
        Intent::TripPlanning => short,
        Intent::OpsChecklist => short,
        Intent::Troubleshooting => !contains_any(
            &text.to_lowercase(),
            &["מים", "power", "engine", "מנוע", "brake", "חשמל"],
        ),
        _ => false,
    }
}

fn contains_any(input: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| input.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_hebrew() {
        assert_eq!(detect_locale(None, "אני רוצה מסלול לחוף"), Locale::He);
    }

    #[test]
    fn classifies_pricing() {
        assert_eq!(classify_intent_rules("כמה עולה מנוי מסע?"), Intent::Pricing);
    }
}
