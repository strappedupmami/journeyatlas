use std::{
    env,
    io::{self, Read},
};

use serde::{Deserialize, Serialize};

const EMERGENCY_SIGNALS: &[&str] = &[
    "emergency",
    "urgent",
    "critical",
    "bleeding",
    "unconscious",
    "collapse",
    "חירום",
    "דחוף",
    "דימום",
    "חסר הכרה",
];

const WEALTH_SIGNALS: &[&str] = &[
    "income",
    "salary",
    "promotion",
    "revenue",
    "sales",
    "client",
    "business",
    "הכנסה",
    "משכורת",
    "קידום",
    "לקוחות",
    "עסק",
];

#[derive(Debug, Deserialize)]
struct ReasonRequest {
    prompt: String,
    #[serde(default)]
    notes_used: usize,
}

#[derive(Debug, Serialize)]
struct ReasonResponse {
    model: String,
    summary: String,
    next_action: String,
    confidence: f64,
    reasoning_summary: String,
    alternatives_considered: Vec<String>,
    assumptions: Vec<String>,
    confidence_label: String,
}

#[derive(Debug, Deserialize)]
struct PolicyRequest {
    #[serde(default)]
    platform: String,
    #[serde(default)]
    task: String,
    #[serde(default)]
    cpu_cores: u32,
    #[serde(default)]
    memory_gb: u64,
    #[serde(default)]
    high_performance: bool,
    #[serde(default)]
    preferred_model: String,
    #[serde(default)]
    model_catalog: Vec<String>,
}

#[derive(Debug, Serialize)]
struct PolicyResponse {
    selected_model: String,
    fallback_models: Vec<String>,
    recommended_pack_id: String,
    reasoning_mode: String,
    analysis_passes: u8,
    temperature: f64,
    max_tokens: u32,
    num_ctx: u32,
    timeout_seconds: u32,
    hardware_tier: String,
    status_line: String,
}

#[derive(Clone, Copy, Debug)]
enum HardwareTier {
    Low,
    Balanced,
    High,
    Ultra,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("atlas-rust-reasoner error: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .map_err(|err| format!("failed reading stdin: {err}"))?;

    let command = env::args().nth(1).unwrap_or_else(|| "reason".to_string());
    match command.as_str() {
        "reason" => {
            let request: ReasonRequest = serde_json::from_str(input.trim())
                .map_err(|err| format!("invalid reason request json: {err}"))?;
            let prompt = collapse_whitespace(request.prompt.trim());
            let response = if prompt.is_empty() {
                ReasonResponse {
                    model: "atlas-rust-local-reasoner-v1".to_string(),
                    summary: "No prompt supplied.".to_string(),
                    next_action: "Add one clear objective and queue it again.".to_string(),
                    confidence: 0.0,
                    reasoning_summary: "No reasoning was performed because the prompt was empty.".to_string(),
                    alternatives_considered: vec![
                        "Keep waiting without a concrete prompt.".to_string(),
                        "Ask for more context before defining any objective.".to_string(),
                    ],
                    assumptions: vec![
                        "A concrete objective is required before useful execution planning can happen.".to_string(),
                    ],
                    confidence_label: "Low".to_string(),
                }
            } else {
                reason(&prompt, request.notes_used)
            };

            let output = serde_json::to_string(&response)
                .map_err(|err| format!("failed serializing reason response: {err}"))?;
            println!("{output}");
            Ok(())
        }
        "policy" => {
            let request: PolicyRequest = serde_json::from_str(input.trim())
                .map_err(|err| format!("invalid policy request json: {err}"))?;
            let response = build_policy(request);
            let output = serde_json::to_string(&response)
                .map_err(|err| format!("failed serializing policy response: {err}"))?;
            println!("{output}");
            Ok(())
        }
        other => Err(format!(
            "unknown command `{other}`; expected `reason` or `policy`"
        )),
    }
}

fn reason(prompt: &str, notes_used: usize) -> ReasonResponse {
    let is_hebrew = contains_hebrew(prompt);
    let lower = prompt.to_lowercase();
    let normalized_notes = notes_used.min(16);

    if contains_any(&lower, EMERGENCY_SIGNALS) {
        if is_hebrew {
            return ReasonResponse {
                model: "atlas-rust-local-reasoner-v1".to_string(),
                summary: "זוהה מצב חירום. נדרש תעדוף בטיחות, טריאז' ושרידות תפעולית.".to_string(),
                next_action: "בצעו עכשיו: אבטחת זירה, קריאה לחירום, שיתוף מיקום, ותיעוד זמנים."
                    .to_string(),
                confidence: 0.97,
                reasoning_summary: "המערכת זיהתה אותות חירום ובחרה במסלול שמעדיף בטיחות ותגובה מיידית על פני ניתוח רחב יותר.".to_string(),
                alternatives_considered: vec![
                    "להתחיל בניתוח אסטרטגי רחב יותר לפני פעולה.".to_string(),
                    "להמתין לעוד פרטים לפני הפעלת תגובת חירום.".to_string(),
                ],
                assumptions: vec![
                    "נדרשת תגובה מיידית ומעשית.".to_string(),
                    "הסיכון המיידי חשוב יותר ממיצוי מידע נוסף כרגע.".to_string(),
                ],
                confidence_label: "Very High".to_string(),
            };
        }
        return ReasonResponse {
            model: "atlas-rust-local-reasoner-v1".to_string(),
            summary: "Emergency context detected. Prioritize safety, triage, and continuity."
                .to_string(),
            next_action:
                "Do now: secure scene, contact emergency services, share location, log timeline."
                    .to_string(),
            confidence: 0.97,
            reasoning_summary: "Emergency signals were present, so the response optimized for immediate safety and continuity instead of broader planning.".to_string(),
            alternatives_considered: vec![
                "Pause to gather more context before acting.".to_string(),
                "Start with a broader strategic plan instead of immediate emergency steps.".to_string(),
            ],
            assumptions: vec![
                "The situation may involve immediate harm or instability.".to_string(),
                "Fast action is more valuable than exhaustive analysis right now.".to_string(),
            ],
            confidence_label: "Very High".to_string(),
        };
    }

    if contains_any(&lower, WEALTH_SIGNALS) {
        if is_hebrew {
            return ReasonResponse {
                model: "atlas-rust-local-reasoner-v1".to_string(),
                summary: "זוהה הקשר צמיחה כלכלית. נדרש מהלך הכנסה מדיד עם לולאת שיפור.".to_string(),
                next_action:
                    "בחרו מהלך 14 יום אחד: קידום שכר, לקוח ראשון, או שדרוג הצעת ערך + KPI יומי."
                        .to_string(),
                confidence: 0.91,
                reasoning_summary: "המערכת זיהתה הקשר כלכלי ובחרה במסלול הכנסה יחיד ומדיד כדי לצמצם פיזור ולחזק מומנטום.".to_string(),
                alternatives_considered: vec![
                    "לרדוף אחרי כמה מסלולי הכנסה במקביל.".to_string(),
                    "להתמקד בלמידה בלבד לפני מהלך הכנסה קונקרטי.".to_string(),
                ],
                assumptions: vec![
                    "מומנטום כלכלי ייבנה מהר יותר דרך מסלול אחד ברור.".to_string(),
                    "פשטות מדידה עדיפה כרגע על תכנית צמיחה מורכבת.".to_string(),
                ],
                confidence_label: "High".to_string(),
            };
        }
        return ReasonResponse {
            model: "atlas-rust-local-reasoner-v1".to_string(),
            summary: "Wealth-growth context detected. Focus on one measurable income route.".to_string(),
            next_action: "Select one 14-day route: compensation upgrade, first client, or offer improvement with daily KPI."
                .to_string(),
            confidence: 0.91,
            reasoning_summary: "The prompt pointed to income growth, so the response chose one measurable route to reduce diffusion and improve execution speed.".to_string(),
            alternatives_considered: vec![
                "Pursue multiple income strategies at the same time.".to_string(),
                "Stay in planning mode longer before choosing a route.".to_string(),
            ],
            assumptions: vec![
                "A narrower execution path will beat a scattered approach right now.".to_string(),
                "Short feedback loops matter more than complex long-range planning here.".to_string(),
            ],
            confidence_label: "High".to_string(),
        };
    }

    let first_sentence = first_sentence(prompt, 180);
    if is_hebrew {
        return ReasonResponse {
            model: "atlas-rust-local-reasoner-v1".to_string(),
            summary: format!("תדריך ביצוע: {first_sentence} | פתקי הקשר: {normalized_notes}"),
            next_action: "ב-15 הדקות הקרובות: בצעו צעד אחד מדיד ורשמו תוצאה.".to_string(),
            confidence: 0.79,
            reasoning_summary: "נבחר מסלול פעולה ישיר וקצר, לאחר השוואה מהירה בין חלופות ובמיקוד בביצוע מיידי.".to_string(),
            alternatives_considered: vec![
                "להעמיק באבחון לפני כל המלצה.".to_string(),
                "לתת תכנית רחבה יותר עם יותר שלבים ופחות דחיפות.".to_string(),
            ],
            assumptions: vec![
                "המשתמש צריך מהלך מעשי מהיר יותר מאשר ניתוח ארוך.".to_string(),
                format!("נעשה שימוש ב-{normalized_notes} פתקי הקשר רלוונטיים."),
            ],
            confidence_label: "Medium".to_string(),
        };
    }

    ReasonResponse {
        model: "atlas-rust-local-reasoner-v1".to_string(),
        summary: format!(
            "Execution brief: {first_sentence} | Context notes used: {normalized_notes}"
        ),
        next_action: "In the next 15 minutes: execute one measurable step and log the result."
            .to_string(),
        confidence: 0.79,
        reasoning_summary: "A direct execution path was chosen after a quick comparison of alternatives, prioritizing speed, clarity, and follow-through.".to_string(),
        alternatives_considered: vec![
            "Ask more diagnostic questions before recommending an action.".to_string(),
            "Offer a broader and slower multi-step plan.".to_string(),
        ],
        assumptions: vec![
            "A practical next step is more valuable than deeper analysis right now.".to_string(),
            format!("The current prompt and {normalized_notes} context notes capture enough signal to act."),
        ],
        confidence_label: "Medium".to_string(),
    }
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn contains_hebrew(value: &str) -> bool {
    value
        .chars()
        .any(|ch| ('\u{0590}'..='\u{05FF}').contains(&ch))
}

fn collapse_whitespace(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn first_sentence(prompt: &str, max_chars: usize) -> String {
    let sentence = prompt
        .split(|ch| matches!(ch, '.' | '?' | '!' | '\n'))
        .map(str::trim)
        .find(|part| !part.is_empty())
        .unwrap_or(prompt);

    if sentence.chars().count() <= max_chars {
        return sentence.to_string();
    }

    let mut truncated = String::new();
    for ch in sentence.chars().take(max_chars) {
        truncated.push(ch);
    }
    format!("{truncated}...")
}

fn build_policy(request: PolicyRequest) -> PolicyResponse {
    let task = request.task.trim().to_lowercase();
    let platform = request.platform.trim().to_lowercase();
    let cores = request.cpu_cores.max(1);
    let memory = request.memory_gb.max(4);
    let tier = classify_hardware_tier(cores, memory, request.high_performance);
    let tier_label = hardware_tier_label(tier).to_string();
    let catalog = sanitize_catalog(request.model_catalog);
    let preferred = request.preferred_model.trim().to_lowercase();
    let preferred_is_auto = preferred.is_empty() || preferred == "auto";
    let reasoning_mode = select_reasoning_mode(&task, tier).to_string();

    let (selected_model, fallback_models) = if preferred_is_auto {
        let selected_idx = select_catalog_index(tier, &task, catalog.len());
        let selected = catalog[selected_idx].clone();
        let mut fallback = Vec::new();
        for idx in (selected_idx + 1)..catalog.len() {
            fallback.push(catalog[idx].clone());
        }
        for idx in (0..selected_idx).rev() {
            fallback.push(catalog[idx].clone());
        }
        (selected, dedup_models(fallback))
    } else {
        let selected = request.preferred_model.trim().to_string();
        let fallback = catalog
            .into_iter()
            .filter(|item| !item.eq_ignore_ascii_case(&selected))
            .collect::<Vec<_>>();
        (selected, dedup_models(fallback))
    };

    let mut analysis_passes = match reasoning_mode.as_str() {
        "fast" => match tier {
            HardwareTier::Low => 1,
            HardwareTier::Balanced => 2,
            HardwareTier::High => 3,
            HardwareTier::Ultra => 3,
        },
        "deep" => match tier {
            HardwareTier::Low => 2,
            HardwareTier::Balanced => 4,
            HardwareTier::High => 5,
            HardwareTier::Ultra => 6,
        },
        _ => match tier {
            HardwareTier::Low => 2,
            HardwareTier::Balanced => 3,
            HardwareTier::High => 4,
            HardwareTier::Ultra => 5,
        },
    };

    if task.contains("adaptive_question") {
        analysis_passes = analysis_passes.min(2);
    }

    let mut max_tokens = match reasoning_mode.as_str() {
        "fast" => match tier {
            HardwareTier::Low => 560,
            HardwareTier::Balanced => 900,
            HardwareTier::High => 1200,
            HardwareTier::Ultra => 1500,
        },
        "deep" => match tier {
            HardwareTier::Low => 1100,
            HardwareTier::Balanced => 1700,
            HardwareTier::High => 2600,
            HardwareTier::Ultra => 3600,
        },
        _ => match tier {
            HardwareTier::Low => 900,
            HardwareTier::Balanced => 1300,
            HardwareTier::High => 1900,
            HardwareTier::Ultra => 2600,
        },
    };

    if task.contains("adaptive_question") {
        max_tokens = max_tokens.min(960);
    }
    if task.contains("structured_json") {
        max_tokens = max_tokens.min(1800);
    }

    let mut num_ctx = match tier {
        HardwareTier::Low => 12_288,
        HardwareTier::Balanced => 16_384,
        HardwareTier::High => 24_576,
        HardwareTier::Ultra => 32_768,
    };
    if reasoning_mode == "deep" && num_ctx < 16_384 {
        num_ctx = 16_384;
    }

    let timeout_seconds = match reasoning_mode.as_str() {
        "fast" => match tier {
            HardwareTier::Low => 16,
            HardwareTier::Balanced => 24,
            HardwareTier::High => 32,
            HardwareTier::Ultra => 40,
        },
        "deep" => match tier {
            HardwareTier::Low => 32,
            HardwareTier::Balanced => 44,
            HardwareTier::High => 60,
            HardwareTier::Ultra => 80,
        },
        _ => match tier {
            HardwareTier::Low => 24,
            HardwareTier::Balanced => 32,
            HardwareTier::High => 42,
            HardwareTier::Ultra => 56,
        },
    };

    let temperature = if task.contains("structured_json") {
        0.1
    } else if task.contains("adaptive_question") {
        0.2
    } else if reasoning_mode == "deep" {
        0.16
    } else if reasoning_mode == "fast" {
        0.24
    } else {
        0.2
    };

    let fallback_count = fallback_models.len();
    let recommended_pack_id = match tier {
        HardwareTier::High | HardwareTier::Ultra => "balanced".to_string(),
        HardwareTier::Balanced | HardwareTier::Low => "starter".to_string(),
    };
    let status_line = format!(
        "Rust policy {platform_or_unknown} tier={tier_label} task={task_or_general} selected={selected_model} fallbacks={fallback_count} mode={reasoning_mode} passes={analysis_passes} max_tokens={max_tokens} num_ctx={num_ctx} timeout={timeout_seconds}s",
        platform_or_unknown = if platform.is_empty() { "unknown" } else { &platform },
        task_or_general = if task.is_empty() { "general" } else { &task }
    );

    PolicyResponse {
        selected_model,
        fallback_models,
        recommended_pack_id,
        reasoning_mode,
        analysis_passes,
        temperature,
        max_tokens,
        num_ctx,
        timeout_seconds,
        hardware_tier: tier_label,
        status_line,
    }
}

fn classify_hardware_tier(cores: u32, memory_gb: u64, high_perf: bool) -> HardwareTier {
    if high_perf || (cores >= 16 && memory_gb >= 32) {
        HardwareTier::Ultra
    } else if cores >= 8 && memory_gb >= 16 {
        HardwareTier::High
    } else if cores >= 8 && memory_gb >= 12 {
        HardwareTier::Balanced
    } else {
        HardwareTier::Low
    }
}

fn hardware_tier_label(tier: HardwareTier) -> &'static str {
    match tier {
        HardwareTier::Low => "low",
        HardwareTier::Balanced => "balanced",
        HardwareTier::High => "high",
        HardwareTier::Ultra => "ultra",
    }
}

fn select_reasoning_mode(task: &str, tier: HardwareTier) -> &'static str {
    if task.contains("adaptive_question") {
        return "fast";
    }

    if task.contains("coding") || task.contains("autopilot") || task.contains("queue") {
        return match tier {
            HardwareTier::Low => "standard",
            _ => "deep",
        };
    }

    if task.contains("structured_json") {
        return "standard";
    }

    match tier {
        HardwareTier::Low => "fast",
        _ => "standard",
    }
}

fn select_catalog_index(tier: HardwareTier, task: &str, count: usize) -> usize {
    if count == 0 {
        return 0;
    }

    let base = match tier {
        HardwareTier::Ultra => 0,
        HardwareTier::High => 1.min(count - 1),
        HardwareTier::Balanced => 2.min(count - 1),
        HardwareTier::Low => count - 1,
    };

    let mut idx = base as isize;
    if task.contains("adaptive_question") {
        idx += 1;
    } else if task.contains("coding") || task.contains("autopilot") || task.contains("queue") {
        idx -= 1;
    }

    idx.clamp(0, (count - 1) as isize) as usize
}

fn sanitize_catalog(models: Vec<String>) -> Vec<String> {
    if models.is_empty() {
        return default_model_catalog();
    }

    let cleaned = dedup_models(
        models
            .into_iter()
            .map(|item| item.trim().to_string())
            .filter(|item| !item.is_empty())
            .collect::<Vec<_>>(),
    );
    if cleaned.is_empty() {
        default_model_catalog()
    } else {
        cleaned
    }
}

fn default_model_catalog() -> Vec<String> {
    vec![
        "llama3.1:70b".to_string(),
        "qwen2.5:32b".to_string(),
        "deepseek-r1:14b".to_string(),
        "qwen2.5:7b".to_string(),
        "llama3.2:latest".to_string(),
    ]
}

fn dedup_models(models: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for model in models {
        let key = model.to_lowercase();
        if seen.insert(key) {
            out.push(model);
        }
    }
    out
}
