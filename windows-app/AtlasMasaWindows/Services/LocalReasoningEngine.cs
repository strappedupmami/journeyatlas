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
            return new LocalReasoningOutput
            {
                Model = "atlas-windows-local-reasoner-v1",
                Summary = "No prompt supplied.",
                NextAction = "Add one clear objective and queue it again.",
                Confidence = 0.0
            };
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
                ? new LocalReasoningOutput
                {
                    Model = "atlas-windows-local-reasoner-v1",
                    Summary = "זוהה מצב חירום. נדרש תעדוף בטיחות, טריאז' ושרידות תפעולית.",
                    NextAction = "בצעו עכשיו: אבטחת זירה, קריאה לחירום, שיתוף מיקום, ותיעוד זמנים.",
                    Confidence = 0.97
                }
                : new LocalReasoningOutput
                {
                    Model = "atlas-windows-local-reasoner-v1",
                    Summary = "Emergency context detected. Prioritize safety, triage, and continuity.",
                    NextAction = "Do now: secure scene, contact emergency services, share location, log timeline.",
                    Confidence = 0.97
                };
        }

        if (WealthSignals.Any(lower.Contains))
        {
            progressCallback?.Invoke(0.70, "Wealth route synthesis");
            await Task.Delay(perf.HighPerformanceMode ? 80 : 180, cancellationToken);
            return isHebrew
                ? new LocalReasoningOutput
                {
                    Model = "atlas-windows-local-reasoner-v1",
                    Summary = "זוהה הקשר צמיחה כלכלית. נדרש מהלך הכנסה מדיד עם לולאת שיפור.",
                    NextAction = "בחרו מהלך 14 יום אחד: קידום שכר, לקוח ראשון, או שדרוג הצעת ערך + KPI יומי.",
                    Confidence = 0.91
                }
                : new LocalReasoningOutput
                {
                    Model = "atlas-windows-local-reasoner-v1",
                    Summary = "Wealth-growth context detected. Focus on one measurable income route.",
                    NextAction = "Select one 14-day route: compensation upgrade, first client, or offer improvement with daily KPI.",
                    Confidence = 0.91
                };
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
            ? new LocalReasoningOutput
            {
                Model = "atlas-windows-local-reasoner-v1",
                Summary = $"תדריך ביצוע: {firstSentence} | פתקי הקשר: {notesUsed}",
                NextAction = "ב-15 הדקות הקרובות: בצעו צעד אחד מדיד ורשמו תוצאה.",
                Confidence = 0.79
            }
            : new LocalReasoningOutput
            {
                Model = "atlas-windows-local-reasoner-v1",
                Summary = $"Execution brief: {firstSentence} | Context notes used: {notesUsed}",
                NextAction = "In the next 15 minutes: execute one measurable step and log the result.",
                Confidence = 0.79
            };
    }
}
