use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use atlas_core::intent::needs_clarification;
use atlas_core::{
    build_ops_checklist, build_trip_plan, classify_intent_rules, compose_chat_reply, detect_locale,
    normalize_text, ChatInput, ConciergeReply, ConversationSession, ConversationTurn, Intent,
    Locale, OpsChecklist, OpsChecklistType, PolicyEngine, PolicySet, RetrievedChunk,
    TripPlanRequest, TripPlanResponse,
};
use atlas_ml::AtlasMlStack;
use atlas_observability::AppMetrics;
use atlas_retrieval::HybridRetriever;
use atlas_storage::{InventoryRepository, SessionRepository};
use chrono::{Duration, Utc};
use tracing::{info, instrument};
use uuid::Uuid;

#[derive(Clone)]
pub struct ConciergeAgent<S>
where
    S: SessionRepository + InventoryRepository,
{
    retriever: Arc<HybridRetriever>,
    ml_stack: AtlasMlStack,
    policy_engine: PolicyEngine,
    store: Arc<S>,
    metrics: Arc<AppMetrics>,
}

impl<S> ConciergeAgent<S>
where
    S: SessionRepository + InventoryRepository,
{
    pub fn new(
        retriever: Arc<HybridRetriever>,
        ml_stack: AtlasMlStack,
        policy_set: PolicySet,
        store: Arc<S>,
        metrics: Arc<AppMetrics>,
    ) -> Self {
        Self {
            retriever,
            ml_stack,
            policy_engine: PolicyEngine::new(policy_set),
            store,
            metrics,
        }
    }

    #[instrument(skip(self, input))]
    pub async fn handle_chat(&self, input: ChatInput) -> Result<ConciergeReply> {
        let started = Instant::now();
        self.metrics.inc_request();

        let normalized = normalize_text(&input.text);
        let explicit_locale = Locale::from_optional_str(input.locale.as_deref());
        let locale = detect_locale(Some(explicit_locale), &normalized);

        let rule_intent = classify_intent_rules(&normalized);
        let ml_prediction = self.ml_stack.classifier.predict(&normalized);
        self.metrics.inc_ml_inference();

        let intent = match rule_intent {
            Intent::Unknown if ml_prediction.confidence > 0.55 => ml_prediction.intent,
            _ => rule_intent,
        };

        let retrieved = self.retriever.search(&normalized, 5);
        self.metrics.add_retrieval_hits(retrieved.len());

        let mut clarifying_questions = Vec::new();
        if needs_clarification(intent, &normalized) {
            clarifying_questions = clarifying_questions_for(intent, locale);
        }

        let policy_result = self
            .policy_engine
            .evaluate_user_message(intent, &normalized);
        let mut reply = if policy_result.blocked {
            self.metrics.inc_fallback();
            blocked_reply(locale, &policy_result.notes)
        } else {
            compose_chat_reply(
                intent,
                locale,
                &normalized,
                &retrieved,
                clarifying_questions,
                policy_result.notes.clone(),
            )
        };

        let session_id = input
            .session_id
            .unwrap_or_else(|| Uuid::new_v4().to_string());
        let user_id = input.user_id.clone();

        self.persist_turn(
            &session_id,
            user_id.as_deref(),
            locale,
            &normalized,
            &reply.reply_text,
            intent,
        )
        .await?;

        if let Some(payload_obj) = reply.json_payload.as_object_mut() {
            payload_obj.insert("session_id".to_string(), serde_json::json!(session_id));
            payload_obj.insert(
                "classifier".to_string(),
                serde_json::json!({
                    "rule_intent": rule_intent,
                    "ml_intent": ml_prediction.intent,
                    "ml_confidence": ml_prediction.confidence,
                    "ml_model": ml_prediction.model,
                    "burn_enabled": self.ml_stack.burn_enabled
                }),
            );
            payload_obj.insert(
                "retrieval".to_string(),
                serde_json::json!({
                    "hits": retrieved.len(),
                    "vector_enabled": self.retriever.stats().vector_enabled,
                    "sources": retrieved
                        .iter()
                        .map(|hit| hit.source_path.clone())
                        .collect::<Vec<_>>()
                }),
            );
        }

        self.metrics.observe_latency(started.elapsed());
        info!(
            session_id = %session_id,
            locale = %locale.as_code(),
            intent = ?intent,
            retrieved = retrieved.len(),
            "chat handled"
        );

        Ok(reply)
    }

    pub async fn plan_trip(&self, request: TripPlanRequest) -> Result<TripPlanResponse> {
        self.metrics.inc_request();
        let response = build_trip_plan(request);
        Ok(response)
    }

    pub async fn ops_checklist(&self, kind: OpsChecklistType) -> Result<OpsChecklist> {
        self.metrics.inc_request();
        Ok(build_ops_checklist(kind))
    }

    pub fn kb_search(&self, query: &str, limit: usize) -> Vec<RetrievedChunk> {
        self.retriever.search(query, limit)
    }

    pub async fn purge_expired_sessions(&self) -> Result<u64> {
        self.store.purge_expired(Utc::now()).await
    }

    async fn persist_turn(
        &self,
        session_id: &str,
        user_id: Option<&str>,
        locale: Locale,
        user_text: &str,
        assistant_text: &str,
        intent: Intent,
    ) -> Result<()> {
        let mut session = self
            .store
            .load_session(session_id)
            .await?
            .unwrap_or_else(|| ConversationSession {
                session_id: session_id.to_string(),
                user_id: None,
                locale,
                expires_at: Utc::now() + Duration::hours(24),
                turns: Vec::new(),
            });

        session.locale = locale;
        if let Some(user_id) = user_id {
            session.user_id = Some(user_id.to_string());
        }
        session.expires_at = Utc::now() + Duration::hours(24);
        session.turns.push(ConversationTurn {
            at: Utc::now(),
            user_text: user_text.to_string(),
            assistant_text: assistant_text.to_string(),
            intent,
        });

        if session.turns.len() > 40 {
            let keep_from = session.turns.len() - 40;
            session.turns = session.turns.split_off(keep_from);
        }

        self.store.upsert_session(&session).await
    }
}

fn clarifying_questions_for(intent: Intent, locale: Locale) -> Vec<String> {
    match (intent, locale) {
        (Intent::TripPlanning, Locale::He) => vec![
            "מה סגנון הטיול המועדף: חוף / צפון / מדבר?".to_string(),
            "לכמה ימים וכמה אנשים?".to_string(),
        ],
        (Intent::OpsChecklist, Locale::He) => {
            vec!["איזה צ׳ק-ליסט צריך עכשיו: החלפה / ניקיון / ציוד / תקלה?".to_string()]
        }
        (Intent::Troubleshooting, Locale::He) => {
            vec!["מה בדיוק התקלה כרגע ובאיזה אזור אתם?".to_string()]
        }
        (Intent::TripPlanning, Locale::En) => vec![
            "Preferred style: beach, north, desert, or mixed?".to_string(),
            "How many days and people?".to_string(),
        ],
        _ => Vec::new(),
    }
}

fn blocked_reply(locale: Locale, notes: &[String]) -> ConciergeReply {
    let reply_text = match locale {
        Locale::He => "לא ניתן לספק הנחיה לא חוקית או מסוכנת. כן אפשר לקבל חלופה חוקית ומעשית לפי האזור.".to_string(),
        _ => "I can’t provide illegal or unsafe instructions. I can provide a legal alternative plan.".to_string(),
    };

    ConciergeReply {
        reply_text,
        suggested_actions: vec![atlas_core::SuggestedAction {
            action_type: "safe_alternative".to_string(),
            label: if locale == Locale::He {
                "בנה חלופה חוקית"
            } else {
                "Build legal alternative"
            }
            .to_string(),
            payload: serde_json::json!({ "mode": "policy_safe" }),
        }],
        json_payload: serde_json::json!({
            "blocked": true,
            "reason": "policy_violation",
            "notes": notes,
        }),
        locale,
        intent: Intent::Policy,
        clarifying_questions: Vec::new(),
        policy_notes: notes.to_vec(),
        retrieved_sources: Vec::new(),
    }
}
