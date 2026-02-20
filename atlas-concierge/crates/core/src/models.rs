use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Locale {
    He,
    En,
    Ar,
    Ru,
    Fr,
    Unknown,
}

impl Locale {
    pub fn from_optional_str(value: Option<&str>) -> Self {
        match value.map(|v| v.trim().to_lowercase()) {
            Some(v) if v == "he" || v == "he-il" || v == "hebrew" => Self::He,
            Some(v) if v == "en" || v == "en-us" || v == "english" => Self::En,
            Some(v) if v == "ar" || v == "ar-sa" || v == "arabic" => Self::Ar,
            Some(v) if v == "ru" || v == "ru-ru" || v == "russian" => Self::Ru,
            Some(v) if v == "fr" || v == "fr-fr" || v == "french" => Self::Fr,
            _ => Self::Unknown,
        }
    }

    pub fn as_code(self) -> &'static str {
        match self {
            Self::He => "he",
            Self::En => "en",
            Self::Ar => "ar",
            Self::Ru => "ru",
            Self::Fr => "fr",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Intent {
    TripPlanning,
    OpsChecklist,
    Policy,
    Pricing,
    Troubleshooting,
    Content,
    SmallTalk,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TripStyle {
    Beach,
    North,
    Desert,
    Mixed,
}

impl TripStyle {
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim().to_lowercase().as_str() {
            "beach" | "coast" | "חוף" | "חופים" => Some(Self::Beach),
            "north" | "galilee" | "צפון" => Some(Self::North),
            "desert" | "south" | "מדבר" | "נגב" => Some(Self::Desert),
            "mixed" | "מעורב" => Some(Self::Mixed),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OpsChecklistType {
    Turnover,
    Cleaning,
    GearKit,
    Incident,
}

impl OpsChecklistType {
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim().to_lowercase().as_str() {
            "turnover" | "סבב" | "החלפה" => Some(Self::Turnover),
            "cleaning" | "ניקיון" => Some(Self::Cleaning),
            "gear" | "kit" | "ציוד" => Some(Self::GearKit),
            "incident" | "תקלה" | "אירוע" => Some(Self::Incident),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserProfile {
    pub user_id: String,
    pub locale: Locale,
    pub risk_preference: Option<String>,
    pub trip_style: Option<TripStyle>,
    pub memory_opt_in: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookingContext {
    pub start_date: Option<String>,
    pub end_date: Option<String>,
    pub people_count: Option<u8>,
    pub vehicle_type: Option<String>,
    pub constraints: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PolicySet {
    pub no_smoking_required: bool,
    pub illegal_dumping_forbidden: bool,
    pub no_minor_targeting: bool,
    pub cleaning_fee_policy: String,
    pub safety_rules: Vec<String>,
}

impl Default for PolicySet {
    fn default() -> Self {
        Self {
            no_smoking_required: true,
            illegal_dumping_forbidden: true,
            no_minor_targeting: true,
            cleaning_fee_policy:
                "Vehicle must be returned clean and odor-free; surcharge applies for deep cleaning"
                    .to_string(),
            safety_rules: vec![
                "Never provide illegal dumping guidance".to_string(),
                "Always include legal sleep/backup options".to_string(),
                "Do not market directly to minors".to_string(),
            ],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KnowledgeDoc {
    pub id: String,
    pub title: String,
    pub source_path: String,
    pub tags: Vec<String>,
    pub body: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievedChunk {
    pub doc_id: String,
    pub title: String,
    pub snippet: String,
    pub score: f32,
    pub source_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationTurn {
    pub at: DateTime<Utc>,
    pub user_text: String,
    pub assistant_text: String,
    pub intent: Intent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationSession {
    pub session_id: String,
    pub user_id: Option<String>,
    pub locale: Locale,
    pub expires_at: DateTime<Utc>,
    pub turns: Vec<ConversationTurn>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatInput {
    pub session_id: Option<String>,
    pub text: String,
    pub locale: Option<String>,
    pub user_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestedAction {
    pub action_type: String,
    pub label: String,
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConciergeReply {
    pub reply_text: String,
    pub suggested_actions: Vec<SuggestedAction>,
    pub json_payload: Value,
    pub locale: Locale,
    pub intent: Intent,
    pub clarifying_questions: Vec<String>,
    pub policy_notes: Vec<String>,
    pub retrieved_sources: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TripPlanRequest {
    pub style: TripStyle,
    pub days: u8,
    pub locale: Locale,
    pub people_count: Option<u8>,
    pub constraints: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TripDayPlan {
    pub day: u8,
    pub title: String,
    pub route_outline: Vec<String>,
    pub sleep_plan: String,
    pub water_grey_plan: String,
    pub shower_options: Vec<String>,
    pub backup_option: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TripPlanResponse {
    pub summary: String,
    pub days: Vec<TripDayPlan>,
    pub safety_notes: Vec<String>,
    pub packing_checklist: Vec<String>,
    pub package_hint: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpsChecklist {
    pub checklist_type: OpsChecklistType,
    pub title: String,
    pub items: Vec<String>,
    pub escalation: Vec<String>,
}
