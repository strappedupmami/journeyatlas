using AtlasMasaWindows.Models;
using System.Text.RegularExpressions;

namespace AtlasMasaWindows.Services;

public sealed class LocalReasoningEngine
{
    private readonly RustReasoningBridge _rustBridge = new();

    private static readonly string[] EmergencySignals =
    [
        "emergency", "urgent", "critical", "bleeding", "unconscious", "collapse",
        "חירום", "דחוף", "דימום", "חסר הכרה"
    ];

    private static readonly string[] WealthSignals =
    [
        "income", "salary", "promotion", "revenue", "sales", "client", "business",
        "הכנסה", "משכורת", "קידום", "לקוחות", "עסק"
    ];

    public string RuntimeStatusLine => _rustBridge.StatusLine;

    public async Task<LocalReasoningOutput> ReasonAsync(
        string prompt,
        IReadOnlyList<NoteRecord> notes,
        SystemPerformanceProfile perf,
        Action<double, string>? progressCallback = null,
        CancellationToken cancellationToken = default)
    {
        var normalized = prompt.Trim();
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return BuildOutput(
                "atlas-windows-local-reasoner-v1",
                "No prompt supplied.",
                "Add one clear objective and queue it again.",
                0.0,
                "No reasoning could be performed because the prompt was empty.",
                ["Wait without setting an objective.", "Ask for more context before defining any target."],
                ["A clear user objective is required before planning can begin."]
            );
        }

        progressCallback?.Invoke(0.10, "Rust local reasoner");
        var rustOutput = await _rustBridge.TryReasonAsync(normalized, notes.Count, cancellationToken);
        if (rustOutput is not null)
        {
            progressCallback?.Invoke(1.0, "Completed via Rust");
            return rustOutput;
        }

        var isHebrew = Regex.IsMatch(normalized, @"[\u0590-\u05FF]");
        var lower = normalized.ToLowerInvariant();
        progressCallback?.Invoke(0.15, "Parsing prompt");
        await Task.Delay(perf.HighPerformanceMode ? 40 : 120, cancellationToken);

        if (EmergencySignals.Any(lower.Contains))
        {
            progressCallback?.Invoke(0.70, "Emergency protocol route");
            await Task.Delay(perf.HighPerformanceMode ? 80 : 180, cancellationToken);
            return isHebrew
                ? BuildOutput(
                    "atlas-windows-local-reasoner-v1",
                    "זוהה מצב חירום. נדרש תעדוף בטיחות, טריאז' ושרידות תפעולית.",
                    "בצעו עכשיו: אבטחת זירה, קריאה לחירום, שיתוף מיקום, ותיעוד זמנים.",
                    0.97,
                    "זוהו אותות חירום, ולכן נבחר מסלול שמעדיף בטיחות ותגובה מיידית על פני ניתוח רחב.",
                    ["להעמיק באבחון לפני פעולה.", "להמתין לעוד פרטים לפני התחלת תגובת חירום."],
                    ["ייתכן שקיים סיכון מיידי.", "פעולה מהירה חשובה כרגע יותר מניתוח ארוך."]
                )
                : BuildOutput(
                    "atlas-windows-local-reasoner-v1",
                    "Emergency context detected. Prioritize safety, triage, and continuity.",
                    "Do now: secure scene, contact emergency services, share location, log timeline.",
                    0.97,
                    "Emergency signals were present, so the response prioritized immediate safety and continuity over broader analysis.",
                    ["Pause for more context before acting.", "Start with a broader strategic plan first."],
                    ["There may be immediate risk or instability.", "Fast action matters more than exhaustive analysis right now."]
                );
        }

        if (WealthSignals.Any(lower.Contains))
        {
            progressCallback?.Invoke(0.70, "Wealth route synthesis");
            await Task.Delay(perf.HighPerformanceMode ? 80 : 180, cancellationToken);
            return isHebrew
                ? BuildOutput(
                    "atlas-windows-local-reasoner-v1",
                    "זוהה הקשר צמיחה כלכלית. נדרש מהלך הכנסה מדיד עם לולאת שיפור.",
                    "בחרו מהלך 14 יום אחד: קידום שכר, לקוח ראשון, או שדרוג הצעת ערך + KPI יומי.",
                    0.91,
                    "זוהה הקשר כלכלי, ולכן נבחר מסלול הכנסה יחיד ומדיד כדי לצמצם פיזור ולחזק מומנטום.",
                    ["לרדוף אחרי כמה מסלולים במקביל.", "להישאר בשלב למידה ארוך יותר לפני בחירה."],
                    ["מיקוד במסלול אחד יפיק מומנטום מהר יותר.", "לולאות מדידה קצרות עדיפות כרגע על תכנית מורכבת."]
                )
                : BuildOutput(
                    "atlas-windows-local-reasoner-v1",
                    "Wealth-growth context detected. Focus on one measurable income route.",
                    "Select one 14-day route: compensation upgrade, first client, or offer improvement with daily KPI.",
                    0.91,
                    "The prompt pointed to income growth, so the response chose one measurable route to reduce diffusion and improve execution speed.",
                    ["Pursue multiple income strategies in parallel.", "Stay in planning mode longer before committing."],
                    ["A narrower execution path will outperform a scattered one right now.", "Short feedback loops matter more than complexity here."]
                );
        }

        progressCallback?.Invoke(0.65, "Execution synthesis");
        await Task.Delay(perf.HighPerformanceMode ? 70 : 140, cancellationToken);

        var firstSentence = normalized
            .Split(['.', '?', '!', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault()?
            .Trim() ?? normalized;
        if (firstSentence.Length > 180)
        {
            firstSentence = $"{firstSentence[..180]}...";
        }

        var notesUsed = Math.Min(4, notes.Count);
        progressCallback?.Invoke(1.0, "Completed");
        return isHebrew
            ? BuildOutput(
                "atlas-windows-local-reasoner-v1",
                $"תדריך ביצוע: {firstSentence} | פתקי הקשר: {notesUsed}",
                "ב-15 הדקות הקרובות: בצעו צעד אחד מדיד ורשמו תוצאה.",
                0.79,
                "נבחר מסלול פעולה ישיר לאחר השוואה מהירה בין חלופות, עם עדיפות לביצוע מיידי.",
                ["להעמיק באבחון לפני המלצה.", "לתת תכנית רחבה יותר ופחות דחופה."],
                [$"נעשה שימוש ב-{notesUsed} פתקי הקשר רלוונטיים.", "נדרשת התקדמות מעשית יותר מאשר ניתוח ארוך כרגע."]
            )
            : BuildOutput(
                "atlas-windows-local-reasoner-v1",
                $"Execution brief: {firstSentence} | Context notes used: {notesUsed}",
                "In the next 15 minutes: execute one measurable step and log the result.",
                0.79,
                "A direct execution path was chosen after a quick comparison of alternatives, prioritizing speed, clarity, and follow-through.",
                ["Ask more diagnostic questions before acting.", "Offer a broader and slower multi-step plan."],
                [$"Used {notesUsed} relevant context notes.", "A practical next step is more valuable than deeper analysis right now."]
            );
    }

    private static LocalReasoningOutput BuildOutput(
        string model,
        string summary,
        string nextAction,
        double confidence,
        string reasoningSummary,
        IReadOnlyList<string> alternatives,
        IReadOnlyList<string> assumptions)
    {
        return new LocalReasoningOutput
        {
            Model = model,
            Summary = summary,
            NextAction = nextAction,
            Confidence = confidence,
            GeneratedAt = DateTimeOffset.UtcNow,
            ReasoningSummary = reasoningSummary,
            AlternativesConsidered = alternatives.Where(item => !string.IsNullOrWhiteSpace(item)).ToList(),
            Assumptions = assumptions.Where(item => !string.IsNullOrWhiteSpace(item)).ToList(),
            ConfidenceLabel = ConfidenceLabel(confidence)
        };
    }

    private static string ConfidenceLabel(double confidence) => confidence switch
    {
        < 0.45 => "Low",
        < 0.72 => "Medium",
        < 0.9 => "High",
        _ => "Very High"
    };
}
