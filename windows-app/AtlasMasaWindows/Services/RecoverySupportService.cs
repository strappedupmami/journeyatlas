using AtlasMasaWindows.Models;
using System.Text;

namespace AtlasMasaWindows.Services;

public sealed class RecoverySupportService
{
    private static readonly string[] RecoverySignals =
    [
        "quit", "sobriety", "sober", "recovery", "relapse", "craving", "addiction",
        "substance", "alcohol", "nicotine", "smoking", "vaping", "weed", "cannabis", "opioid"
    ];

    private static readonly string[] HighRiskSignals =
    [
        "overdose", "i might use", "i want to use", "can't stop", "can't stay sober", "withdrawal",
        "self harm", "hurt myself", "suicidal", "kill myself"
    ];

    public bool LooksLikeRecoveryPrompt(string prompt)
    {
        var lower = (prompt ?? string.Empty).ToLowerInvariant();
        if (lower.Length < 12)
        {
            return false;
        }
        return RecoverySignals.Any(lower.Contains);
    }

    public LocalReasoningOutput? TryBuildRecoveryPlan(string prompt)
    {
        var normalized = (prompt ?? string.Empty).Trim();
        if (!LooksLikeRecoveryPrompt(normalized))
        {
            return null;
        }

        var lower = normalized.ToLowerInvariant();
        var riskBand = ResolveRiskBand(lower);
        var focus = ResolveFocus(lower);
        var guardrails = BuildGuardrails(focus, riskBand);
        var nextAction = BuildNextAction(focus, riskBand);
        var summary = BuildSummary(focus, riskBand, guardrails);

        return new LocalReasoningOutput
        {
            Model = "atlas-recovery-support-v1",
            Summary = summary,
            NextAction = nextAction,
            Confidence = riskBand == "high" ? 0.9 : riskBand == "elevated" ? 0.83 : 0.76,
            GeneratedAt = DateTimeOffset.UtcNow
        };
    }

    private static string ResolveRiskBand(string prompt)
    {
        if (HighRiskSignals.Any(prompt.Contains))
        {
            return "high";
        }
        if (ContainsAny(prompt, "craving", "trigger", "relapse", "stressed", "stress", "urge"))
        {
            return "elevated";
        }
        return "moderate";
    }

    private static string ResolveFocus(string prompt)
    {
        if (ContainsAny(prompt, "nicotine", "smoking", "vaping", "cigarette"))
        {
            return "nicotine";
        }
        if (ContainsAny(prompt, "alcohol", "drinking", "beer", "wine"))
        {
            return "alcohol";
        }
        if (ContainsAny(prompt, "opioid", "fentanyl", "painkiller"))
        {
            return "opioid";
        }
        if (ContainsAny(prompt, "weed", "cannabis", "thc"))
        {
            return "cannabis";
        }
        return "general";
    }

    private static List<string> BuildGuardrails(string focus, string riskBand)
    {
        var guardrails = new List<string>
        {
            "Trigger map: log top 3 contexts (time/place/people) that predict urges.",
            "Decision fatigue shield: pre-commit your evening routine before stress peaks.",
            "Fast interruption protocol: 90-second breathing + leave trigger location + text support contact."
        };

        if (focus == "nicotine")
        {
            guardrails.Add("Nicotine specific: pair replacement (gum/patch if medically suitable) with fixed craving windows.");
        }
        else if (focus == "alcohol")
        {
            guardrails.Add("Alcohol specific: remove in-home inventory and lock social plan to alcohol-free defaults.");
        }
        else if (focus == "opioid")
        {
            guardrails.Add("Opioid specific: avoid solo periods during peak-risk hours and keep naloxone access ready if prescribed.");
        }
        else if (focus == "cannabis")
        {
            guardrails.Add("Cannabis specific: replace late-night use loop with a fixed wind-down ritual and sleep protection plan.");
        }

        if (riskBand == "high")
        {
            guardrails.Add("High-risk protocol: immediate human escalation (trusted contact + clinician/support line).");
        }

        return guardrails;
    }

    private static string BuildSummary(string focus, string riskBand, IReadOnlyList<string> guardrails)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Recovery support mode: {FocusLabel(focus)}.");
        sb.AppendLine($"Current risk band: {riskBand}.");
        sb.AppendLine("Long-term guardrails:");
        foreach (var item in guardrails.Take(5))
        {
            sb.AppendLine($"- {item}");
        }
        if (riskBand == "high")
        {
            sb.AppendLine("Safety note: if there is immediate danger, contact local emergency services now.");
        }
        return sb.ToString().Trim();
    }

    private static string BuildNextAction(string focus, string riskBand)
    {
        if (riskBand == "high")
        {
            return "Use high-risk protocol now: contact a trusted person, remove access to substances, and call local emergency/support services if immediate danger exists.";
        }

        return focus switch
        {
            "nicotine" => "Start a 72-hour nicotine interruption plan: define trigger windows, prepare replacements, and set two accountability check-ins daily.",
            "alcohol" => "Schedule a 7-day alcohol-free protocol now: clear inventory, pre-plan nightly alternatives, and lock one daily support touchpoint.",
            "opioid" => "Create a same-day protection plan with a trusted contact and clinician-aligned guardrails before the next high-risk time window.",
            "cannabis" => "Run a 7-day cannabis reset with sleep-first routines, trigger journaling, and one daily accountability message.",
            _ => "Define one 24-hour no-use plan now with trigger controls, two check-ins, and one fallback action if cravings spike."
        };
    }

    private static string FocusLabel(string focus)
    {
        return focus switch
        {
            "nicotine" => "Nicotine quit support",
            "alcohol" => "Alcohol recovery support",
            "opioid" => "Opioid recovery support",
            "cannabis" => "Cannabis recovery support",
            _ => "Substance recovery support"
        };
    }

    private static bool ContainsAny(string text, params string[] terms)
    {
        return terms.Any(term => text.Contains(term, StringComparison.OrdinalIgnoreCase));
    }
}
