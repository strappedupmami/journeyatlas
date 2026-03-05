import Foundation

struct RecoverySupportService {
    private let recoverySignals = [
        "quit", "sobriety", "sober", "recovery", "relapse", "craving", "addiction",
        "substance", "alcohol", "nicotine", "smoking", "vaping", "weed", "cannabis", "opioid",
    ]

    private let highRiskSignals = [
        "overdose", "i might use", "i want to use", "can't stop", "can't stay sober", "withdrawal",
        "self harm", "hurt myself", "suicidal", "kill myself",
    ]

    func looksLikeRecoveryPrompt(_ prompt: String) -> Bool {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 12 else { return false }
        return recoverySignals.contains { lower.contains($0) }
    }

    func buildPlan(prompt: String) -> LocalReasoningOutput? {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeRecoveryPrompt(normalized) else { return nil }

        let lower = normalized.lowercased()
        let riskBand = resolveRiskBand(lower)
        let focus = resolveFocus(lower)
        let guardrails = buildGuardrails(focus: focus, riskBand: riskBand)
        let summary = buildSummary(focus: focus, riskBand: riskBand, guardrails: guardrails)
        let nextAction = buildNextAction(focus: focus, riskBand: riskBand)

        let confidence: Double
        switch riskBand {
        case "high":
            confidence = 0.9
        case "elevated":
            confidence = 0.83
        default:
            confidence = 0.76
        }

        return LocalReasoningOutput(
            model: "atlas-recovery-support-v1",
            summary: summary,
            nextAction: nextAction,
            confidence: confidence,
            generatedAt: Date()
        )
    }

    private func resolveRiskBand(_ prompt: String) -> String {
        if highRiskSignals.contains(where: { prompt.contains($0) }) {
            return "high"
        }
        if containsAny(prompt, ["craving", "trigger", "relapse", "stressed", "stress", "urge"]) {
            return "elevated"
        }
        return "moderate"
    }

    private func resolveFocus(_ prompt: String) -> String {
        if containsAny(prompt, ["nicotine", "smoking", "vaping", "cigarette"]) {
            return "nicotine"
        }
        if containsAny(prompt, ["alcohol", "drinking", "beer", "wine"]) {
            return "alcohol"
        }
        if containsAny(prompt, ["opioid", "fentanyl", "painkiller"]) {
            return "opioid"
        }
        if containsAny(prompt, ["weed", "cannabis", "thc"]) {
            return "cannabis"
        }
        return "general"
    }

    private func buildGuardrails(focus: String, riskBand: String) -> [String] {
        var guardrails = [
            "Trigger map: log top 3 contexts (time/place/people) that predict urges.",
            "Decision fatigue shield: pre-commit your evening routine before stress peaks.",
            "Fast interruption protocol: 90-second breathing + leave trigger location + text support contact.",
        ]

        switch focus {
        case "nicotine":
            guardrails.append("Nicotine specific: pair replacement (gum/patch if medically suitable) with fixed craving windows.")
        case "alcohol":
            guardrails.append("Alcohol specific: remove in-home inventory and lock social plan to alcohol-free defaults.")
        case "opioid":
            guardrails.append("Opioid specific: avoid solo periods during peak-risk hours and keep naloxone access ready if prescribed.")
        case "cannabis":
            guardrails.append("Cannabis specific: replace late-night use loop with a fixed wind-down ritual and sleep protection plan.")
        default:
            break
        }

        if riskBand == "high" {
            guardrails.append("High-risk protocol: immediate human escalation (trusted contact + clinician/support line).")
        }

        return guardrails
    }

    private func buildSummary(focus: String, riskBand: String, guardrails: [String]) -> String {
        var lines: [String] = [
            "Recovery support mode: \(focusLabel(focus)).",
            "Current risk band: \(riskBand).",
            "Long-term guardrails:",
        ]
        lines.append(contentsOf: guardrails.prefix(5).map { "- \($0)" })
        if riskBand == "high" {
            lines.append("Safety note: if there is immediate danger, contact local emergency services now.")
        }
        return lines.joined(separator: "\n")
    }

    private func buildNextAction(focus: String, riskBand: String) -> String {
        if riskBand == "high" {
            return "Use high-risk protocol now: contact a trusted person, remove access to substances, and call local emergency/support services if immediate danger exists."
        }

        switch focus {
        case "nicotine":
            return "Start a 72-hour nicotine interruption plan: define trigger windows, prepare replacements, and set two accountability check-ins daily."
        case "alcohol":
            return "Schedule a 7-day alcohol-free protocol now: clear inventory, pre-plan nightly alternatives, and lock one daily support touchpoint."
        case "opioid":
            return "Create a same-day protection plan with a trusted contact and clinician-aligned guardrails before the next high-risk time window."
        case "cannabis":
            return "Run a 7-day cannabis reset with sleep-first routines, trigger journaling, and one daily accountability message."
        default:
            return "Define one 24-hour no-use plan now with trigger controls, two check-ins, and one fallback action if cravings spike."
        }
    }

    private func focusLabel(_ focus: String) -> String {
        switch focus {
        case "nicotine":
            return "Nicotine quit support"
        case "alcohol":
            return "Alcohol recovery support"
        case "opioid":
            return "Opioid recovery support"
        case "cannabis":
            return "Cannabis recovery support"
        default:
            return "Substance recovery support"
        }
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }
}
