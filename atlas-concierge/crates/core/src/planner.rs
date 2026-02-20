use serde_json::json;

use crate::models::{
    ConciergeReply, Intent, Locale, OpsChecklist, OpsChecklistType, RetrievedChunk,
    SuggestedAction, TripDayPlan, TripPlanRequest, TripPlanResponse, TripStyle,
};

pub fn compose_chat_reply(
    intent: Intent,
    locale: Locale,
    user_text: &str,
    retrieved: &[RetrievedChunk],
    clarifying_questions: Vec<String>,
    policy_notes: Vec<String>,
) -> ConciergeReply {
    let sources = retrieved
        .iter()
        .map(|chunk| format!("{} ({})", chunk.title, chunk.source_path))
        .collect::<Vec<_>>();

    let top_snippets = retrieved
        .iter()
        .take(3)
        .map(|chunk| chunk.snippet.clone())
        .collect::<Vec<_>>();

    let (reply_text, suggested_actions) = match (intent, locale) {
        (Intent::TripPlanning, Locale::He) => (
            format!(
                "מעולה, נבנה מסלול קצר וברור. הנה התחלה פרקטית:\n1) נגדיר אזור וסגנון (חוף/צפון/מדבר).\n2) נקבע נקודות לינה מוסדרות + גיבוי.\n3) נוסיף תכנית מים/אפור חוקית ומקלחות.\n\nמהחומר שמצאתי: {}",
                top_snippets.join(" | ")
            ),
            vec![
                action("plan_trip", "צור תוכנית 2-3 ימים", json!({ "days": 3 })),
                action("whatsapp", "הכן הודעת WhatsApp ללקוח", json!({ "tone": "friendly-he" })),
            ],
        ),
        (Intent::OpsChecklist, Locale::He) => (
            format!(
                "להפעלת צוות מהירה, זה סדר הפעולות:\n1) בטיחות רכב ותיעוד מצב פתיחה.\n2) ניקיון, ריח, ומדיניות ללא עישון.\n3) בדיקת ערכת ציוד (מים/צינורות/מתאמים).\n\nהקשר רלוונטי: {}",
                top_snippets.join(" | ")
            ),
            vec![action(
                "ops_checklist",
                "פתח צ׳ק-ליסט החלפה",
                json!({ "type": "turnover" }),
            )],
        ),
        (Intent::Policy, Locale::He) => (
            "מדיניות אטלס מסע בקצרה: ללא עישון, ריקון מים אפורים רק בנקודות מורשות, ולינה בהתאם לחוק המקומי. אם תרצה, אבנה לך גרסה ללקוח או גרסה פנימית לצוות.".to_string(),
            vec![action("policy_summary", "גרסת לקוח למדיניות", json!({ "audience": "customer" }))],
        ),
        (Intent::Pricing, Locale::He) => (
            "יש שתי חבילות ברורות: מסע חווייתי (ניסיון קצר) ומנוי מסע (חופש חוזר). בשתיהן תכנון טיול כלול בחינם וזה היתרון המשמעותי מול מלונות.".to_string(),
            vec![action("pricing_compare", "השוואת חבילות", json!({ "packages": ["מסע חווייתי", "מנוי מסע"] }))],
        ),
        (Intent::Troubleshooting, Locale::He) => (
            "במקרה תקלה פועלים כך: עצירה בטוחה, צילום מצב, בדיקת חומרת תקלה, ואז החלטה אם להמשיך/לגרור. אם תתן את סוג התקלה, אחזיר צ׳ק-ליסט מדויק.".to_string(),
            vec![action("incident_triage", "פתח נוהל תקלה", json!({ "priority": "high" }))],
        ),
        (Intent::Content, Locale::He) => (
            "אפשר לייצר תוכן מובנה ומהיר: מדריך מסלול, FAQ להתנגדויות, או הודעת WhatsApp מוכנה למכירה. תגיד לי את קהל היעד ואספק טיוטה מוכנה לפרסום.".to_string(),
            vec![action("content_template", "צור תבנית מדריך", json!({ "locale": "he" }))],
        ),
        (_, Locale::Ar) => (
            format!(
                "هذه استجابة عملية: نحدد الهدف، نبني خطة قانونية، ونرجع بخطوات واضحة مع بدائل. سياق مناسب: {}",
                top_snippets.join(" | ")
            ),
            vec![action("next_step", "Build practical plan", json!({ "locale": "ar" }))],
        ),
        (_, Locale::Ru) => (
            format!(
                "Практический путь: уточняем цель, строим легальный план, возвращаем шаги и резервы. Контекст: {}",
                top_snippets.join(" | ")
            ),
            vec![action("next_step", "Generate practical plan", json!({ "locale": "ru" }))],
        ),
        (_, Locale::Fr) => (
            format!(
                "Parcours pratique: clarifier l'objectif, construire un plan légal, renvoyer des étapes et backups. Contexte: {}",
                top_snippets.join(" | ")
            ),
            vec![action("next_step", "Generate practical plan", json!({ "locale": "fr" }))],
        ),
        (_, Locale::En) => (
            format!(
                "Here is a practical concierge response path: clarify the goal, build a legal logistics plan, and return actionable steps with backups. Relevant context: {}",
                top_snippets.join(" | ")
            ),
            vec![action("next_step", "Generate actionable plan", json!({ "locale": "en" }))],
        ),
        _ => (
            format!(
                "נשמע טוב. כדי להתקדם מהר, אנסח לך תוכנית קצרה עם צעדים ברורים ואפשרויות גיבוי. מקור ידע: {}",
                top_snippets.join(" | ")
            ),
            vec![action("next_step", "המשך", json!({ "mode": "concierge" }))],
        ),
    };

    ConciergeReply {
        reply_text,
        suggested_actions,
        json_payload: json!({
            "intent": intent,
            "locale": locale,
            "input_echo": user_text,
            "retrieved_snippets": top_snippets,
            "brand": {
                "company": "אטלס מסע",
                "promise": "חופשה בלי מלונות",
                "packages": ["מסע חווייתי", "מנוי מסע"],
                "travel_help_included_free": true
            }
        }),
        locale,
        intent,
        clarifying_questions,
        policy_notes,
        retrieved_sources: sources,
    }
}

pub fn build_trip_plan(req: TripPlanRequest) -> TripPlanResponse {
    let days = req.days.clamp(1, 10);

    let mut day_plans = Vec::new();
    for day in 1..=days {
        day_plans.push(match req.style {
            TripStyle::Beach => TripDayPlan {
                day,
                title: format!("יום {}: קו חוף + עצירת שקיעה", day),
                route_outline: vec![
                    "יציאה מוקדמת להימנע מעומסים".to_string(),
                    "חוף מוסדר עם שירותים".to_string(),
                    "עצירת אוכל קלה + תצפית ערב".to_string(),
                ],
                sleep_plan: "חניון לילה מוסדר באזור החוף + חלופה קרובה".to_string(),
                water_grey_plan: "בדיקת מפלס מים אפורים בערב וריקון רק בנקודה מורשית".to_string(),
                shower_options: vec![
                    "מקלחות חניון מוסדר".to_string(),
                    "חדר כושר אזורי כחלופה".to_string(),
                ],
                backup_option: "מעבר לחניון חוף חלופי במקרה תפוסה מלאה".to_string(),
            },
            TripStyle::North => TripDayPlan {
                day,
                title: format!("יום {}: גליל/גולן בקצב רגוע", day),
                route_outline: vec![
                    "תצפית בוקר קצרה".to_string(),
                    "מסלול הליכה קל".to_string(),
                    "כניסה מוקדמת לחניון מוסדר".to_string(),
                ],
                sleep_plan: "לינה מוסדרת בגליל העליון עם גיבוי בטווח 25 דק".to_string(),
                water_grey_plan: "מילוי מים בבוקר וריקון אפורים באמצע מסלול".to_string(),
                shower_options: vec!["חניון מוסדר".to_string(), "מתחם רחצה יישובי".to_string()],
                backup_option: "תכנית גיבוי לפי מזג אוויר/עומס".to_string(),
            },
            TripStyle::Desert => TripDayPlan {
                day,
                title: format!("יום {}: מדבר חכם עם מרווח ביטחון", day),
                route_outline: vec![
                    "נסיעה בשעות קרירות".to_string(),
                    "עצירת נוף קצרה".to_string(),
                    "בדיקת דלק ומים לפני לילה".to_string(),
                ],
                sleep_plan: "חניון לילה מוסדר במדבר + חלופה ליד ציר ראשי".to_string(),
                water_grey_plan: "שומרים רזרבת מים גבוהה וריקון חוקי בלבד".to_string(),
                shower_options: vec!["חניון מוסדר".to_string(), "חלופת רחצה מתוכננת".to_string()],
                backup_option: "במקרה רוח/חום קיצוני עוברים למסלול מקוצר".to_string(),
            },
            TripStyle::Mixed => TripDayPlan {
                day,
                title: format!("יום {}: מסלול משולב", day),
                route_outline: vec![
                    "בוקר עירוני קל".to_string(),
                    "צהריים בטבע".to_string(),
                    "ערב בחניון מוסדר".to_string(),
                ],
                sleep_plan: "לינה מוסדרת מתחלפת לפי אזור".to_string(),
                water_grey_plan: "תיאום נקודות שירות מראש לכל יום".to_string(),
                shower_options: vec!["חניון".to_string(), "חדר כושר".to_string()],
                backup_option: "מסלול אלטרנטיבי מוכן מראש לכל מקטע".to_string(),
            },
        });
    }

    let package_hint = if days <= 4 {
        "מסע חווייתי מתאים לרוב הבדיקות הראשוניות".to_string()
    } else {
        "מנוי מסע מתאים לשימוש חוזר וגמיש לאורך השנה".to_string()
    };

    TripPlanResponse {
        summary: "תכנון תנועה-ראשונה: פחות מעבר בין נקודות לינה, יותר יציבות תפעולית וחופש"
            .to_string(),
        days: day_plans,
        safety_notes: vec![
            "לא מבצעים ריקון מים אפורים מחוץ לנקודה מורשית".to_string(),
            "מדיניות ללא עישון חלה בכל הרכבים".to_string(),
            "בכל יום קובעים חלופת לינה".to_string(),
        ],
        packing_checklist: vec![
            "תעודות ורישיון נהיגה".to_string(),
            "מים אישיים ליום הראשון".to_string(),
            "ערכת טעינה וניווט אופליין".to_string(),
            "ביגוד ערב ושכבת רוח".to_string(),
        ],
        package_hint,
    }
}

pub fn build_ops_checklist(kind: OpsChecklistType) -> OpsChecklist {
    match kind {
        OpsChecklistType::Turnover => OpsChecklist {
            checklist_type: kind,
            title: "Vehicle Turnover Checklist".to_string(),
            items: vec![
                "צילום מצב רכב פנימי/חיצוני".to_string(),
                "בדיקת מיכלי מים ומים אפורים".to_string(),
                "אימות ציוד חובה: צינור, מתאם, וסת, כבלים".to_string(),
                "תדרוך לקוח קצר: לינה חוקית, מקלחות, no-smoking".to_string(),
            ],
            escalation: vec![
                "נזק בטיחותי -> עצירה + מנהל תפעול".to_string(),
                "חוסר ציוד -> לא משחררים רכב עד השלמה".to_string(),
            ],
        },
        OpsChecklistType::Cleaning => OpsChecklist {
            checklist_type: kind,
            title: "Deep Cleaning & Odor Control".to_string(),
            items: vec![
                "אוורור מלא 20 דקות".to_string(),
                "ניקוי משטחים ומטבחון".to_string(),
                "בדיקת ריח לעמידה במדיניות ללא עישון".to_string(),
            ],
            escalation: vec!["זיהוי ריח חריג -> חיוב ניקוי מיוחד".to_string()],
        },
        OpsChecklistType::GearKit => OpsChecklist {
            checklist_type: kind,
            title: "Gear Kit Audit".to_string(),
            items: vec![
                "צינור מים + מתאמים".to_string(),
                "כפפות + חומר ניקוי".to_string(),
                "כלי עבודה בסיסיים + תאורה".to_string(),
            ],
            escalation: vec!["חוסר פריט קריטי -> חסימת יציאה".to_string()],
        },
        OpsChecklistType::Incident => OpsChecklist {
            checklist_type: kind,
            title: "Incident Triage".to_string(),
            items: vec![
                "וידוא בטיחות נוסעים".to_string(),
                "איסוף מיקום ותמונות".to_string(),
                "קביעה: המשך נסיעה / שירות דרך / גרירה".to_string(),
                "תיעוד מלא במערכת".to_string(),
            ],
            escalation: vec![
                "פגיעה בגוף -> חירום 101".to_string(),
                "תקלה משביתה -> ספק גרירה + עדכון לקוח".to_string(),
            ],
        },
    }
}

fn action(action_type: &str, label: &str, payload: serde_json::Value) -> SuggestedAction {
    SuggestedAction {
        action_type: action_type.to_string(),
        label: label.to_string(),
        payload,
    }
}
