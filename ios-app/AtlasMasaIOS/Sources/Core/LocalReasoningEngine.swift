import Foundation

actor LocalReasoningEngine {
    private let modelName = "burn-local-reasoner-v1"

    func reason(prompt: String, notes: [UserNote]) async -> LocalReasoningOutput {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()

        // Simulate a lightweight local inference pass.
        try? await Task.sleep(nanoseconds: 220_000_000)

        let summary = summarize(normalized)
        let nextAction = recommendNextAction(from: lowered)
        let confidence = confidenceScore(for: lowered)

        return LocalReasoningOutput(
            model: modelName,
            summary: notes.isEmpty ? summary : "\(summary) | Context notes: \(min(notes.count, 5))",
            nextAction: nextAction,
            confidence: confidence,
            generatedAt: Date()
        )
    }

    private func summarize(_ prompt: String) -> String {
        if prompt.count <= 180 { return prompt }
        let index = prompt.index(prompt.startIndex, offsetBy: 180)
        return String(prompt[..<index]) + "..."
    }

    private func recommendNextAction(from loweredPrompt: String) -> String {
        if loweredPrompt.contains("urgent") || loweredPrompt.contains("asap") || loweredPrompt.contains("critical") {
            return "Create a 25-minute focused sprint now and execute the first critical step immediately."
        }
        if loweredPrompt.contains("money") || loweredPrompt.contains("revenue") || loweredPrompt.contains("client") {
            return "Prioritize one direct revenue action today, then schedule a follow-up reminder before end of day."
        }
        if loweredPrompt.contains("health") || loweredPrompt.contains("stress") || loweredPrompt.contains("burnout") {
            return "Set a recovery block first, then continue with one high-impact task after stabilization."
        }
        return "Break the request into a daily action, a mid-term milestone, and a long-term objective, then execute step one now."
    }

    private func confidenceScore(for loweredPrompt: String) -> Double {
        let signals = ["plan", "execute", "deadline", "priority", "risk", "next", "today", "week"]
        let score = signals.filter { loweredPrompt.contains($0) }.count
        return min(0.98, 0.55 + Double(score) * 0.05)
    }
}
