use crate::models::{Intent, PolicySet};

#[derive(Debug, Clone)]
pub enum PolicyViolation {
    IllegalDumpingGuidance,
    DirectMinorTargeting,
    SmokingPolicyConflict,
}

#[derive(Debug, Clone)]
pub struct PolicyGateResult {
    pub blocked: bool,
    pub violations: Vec<PolicyViolation>,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PolicyEngine {
    policies: PolicySet,
}

impl PolicyEngine {
    pub fn new(policies: PolicySet) -> Self {
        Self { policies }
    }

    pub fn policies(&self) -> &PolicySet {
        &self.policies
    }

    pub fn evaluate_user_message(&self, intent: Intent, message: &str) -> PolicyGateResult {
        let lower = message.to_lowercase();
        let mut violations = Vec::new();
        let mut notes = Vec::new();

        if self.policies.illegal_dumping_forbidden
            && contains_any(
                &lower,
                &[
                    "לשפוך",
                    "לרוקן בשטח",
                    "illegal dump",
                    "dump anywhere",
                    "greywater in nature",
                ],
            )
        {
            violations.push(PolicyViolation::IllegalDumpingGuidance);
            notes.push(
                "We only provide legal greywater disposal guidance through authorized points."
                    .to_string(),
            );
        }

        if self.policies.no_minor_targeting
            && contains_any(&lower, &["קטינים", "minors", "ילדים לבד", "under 18"])
        {
            violations.push(PolicyViolation::DirectMinorTargeting);
            notes.push("Communication must target adults only (18+).".to_string());
        }

        if intent == Intent::Policy
            && self.policies.no_smoking_required
            && contains_any(&lower, &["אפשר לעשן", "smoking allowed", "לעשן ברכב"])
        {
            violations.push(PolicyViolation::SmokingPolicyConflict);
            notes.push(
                "No-smoking policy is strict and non-negotiable in all vehicles.".to_string(),
            );
        }

        PolicyGateResult {
            blocked: !violations.is_empty(),
            violations,
            notes,
        }
    }

    pub fn safe_fallback_message_hebrew(&self) -> &'static str {
        "אני לא יכול לתת הנחיה לא חוקית או מסוכנת. כן אפשר לעזור עם חלופה חוקית ומעשית לפי אזור."
    }

    pub fn safe_fallback_message_english(&self) -> &'static str {
        "I can’t provide illegal or unsafe guidance. I can provide a legal and practical alternative plan."
    }
}

fn contains_any(input: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| input.contains(needle))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::PolicySet;

    #[test]
    fn blocks_illegal_dumping_requests() {
        let engine = PolicyEngine::new(PolicySet::default());
        let result =
            engine.evaluate_user_message(Intent::Policy, "איפה אפשר לשפוך מים אפורים בטבע?");
        assert!(result.blocked);
    }
}
