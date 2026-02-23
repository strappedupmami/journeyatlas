package com.atlasmasa.android.domain

import java.util.Locale

class LocalReasoningEngine {
    data class Output(
        val summary: String,
        val nextAction: String,
        val confidence: Double,
        val model: String = "atlas-mobile-local-reasoner-v1",
    )

    fun reason(prompt: String, notesContext: List<UserNote>): Output {
        val compact = prompt.trim().take(420)
        if (compact.isEmpty()) {
            return Output(
                summary = "No prompt supplied.",
                nextAction = "Add one clear prompt and rerun queue.",
                confidence = 0.0,
            )
        }
        val lower = compact.lowercase(Locale.getDefault())
        val isHebrew = compact.any { it.code in 0x0590..0x05FF }

        val emergencySignals = listOf("emergency", "critical", "bleeding", "unconscious", "חירום", "דחוף", "דימום")
        if (emergencySignals.any { lower.contains(it) }) {
            return if (isHebrew) {
                Output(
                    summary = "מצב חירום זוהה. עדיפות מיידית לבטיחות, טריאז' ותקשורת רציפה.",
                    nextAction = "בצעו עכשיו: 1) אבטחת זירה 2) טריאז' 3) יצירת קשר עם חירום 4) שיתוף מיקום 5) תיעוד זמנים.",
                    confidence = 0.97,
                )
            } else {
                Output(
                    summary = "Emergency context detected. Prioritize scene safety, triage, and communications continuity.",
                    nextAction = "Do now: 1) secure scene 2) triage 3) contact emergency/satellite 4) share exact location 5) log timeline.",
                    confidence = 0.97,
                )
            }
        }

        val wealthSignals = listOf("salary", "job", "income", "revenue", "sales", "promotion", "עסק", "הכנסה", "משכורת")
        if (wealthSignals.any { lower.contains(it) }) {
            return if (isHebrew) {
                Output(
                    summary = "מסלול צמיחה כלכלית זוהה. המיקוד הוא מהלך הכנסה קצר-טווח עם מנגנון צמיחה חוזר.",
                    nextAction = "בחרו מסלול אחד ל-14 יום: שדרוג שכר, לקוח ראשון, או שיפור הצעת ערך. קבעו KPI יומי ובקרה שבועית.",
                    confidence = 0.91,
                )
            } else {
                Output(
                    summary = "Wealth-growth context detected. Focus on one near-term income move with a repeatable growth loop.",
                    nextAction = "Pick one 14-day route: raise comp, land first client, or upgrade offer. Track daily KPI + weekly review.",
                    confidence = 0.91,
                )
            }
        }

        val noteCount = notesContext.size.coerceAtMost(4)
        return if (isHebrew) {
            Output(
                summary = "תדריך ביצוע: ${compact.take(170)}${if (compact.length > 170) "..." else ""} | פתקי הקשר: $noteCount",
                nextAction = "ב-15 הדקות הקרובות: בצעו צעד אחד מדיד והוסיפו תיעוד תוצאה.",
                confidence = 0.78,
            )
        } else {
            Output(
                summary = "Execution brief: ${compact.take(170)}${if (compact.length > 170) "..." else ""} | Context notes: $noteCount",
                nextAction = "In the next 15 minutes: execute one measurable step and log outcome.",
                confidence = 0.78,
            )
        }
    }
}
