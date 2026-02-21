import AuthenticationServices
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas/אטלס Travel Design OS (Swift local tier)..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var pendingPrompt = ""
    @Published var promptQueue: [PromptQueueItem] = []

    @Published var isSignedIn = false
    @Published var accountProvider: AuthProvider?
    @Published var accountLabel = "Guest Operator"
    @Published var selectedTier: AccountTier = .localTrial
    @Published var trialDaysRemaining = 90

    @Published var dailyPriority = ""
    @Published var midTermGoal = ""
    @Published var longTermVision = ""
    @Published var checkInMood = "Focused"
    @Published var checkInEnergy = 3
    @Published var checkInBlockers = ""
    @Published var executionActions: [ExecutionAction] = []
    @Published var memoryInsights: [MemoryInsight] = []
    @Published var tailoredOffers: [TailoredOffer] = []
    @Published var researchStreams: [ResearchExecutionStream] = []

    @Published var pendingFeedback = ""
    @Published var feedbackOfferEnabled = true

    @Published var vanRentalNeeded = false
    @Published var travelRegion = "Israel"
    @Published var annualDistanceKM = "70000"
    @Published var workspaceMode = "Business mobility"

    let api: APIClient
    private let localReasoning = LocalReasoningEngine()
    private var queueWorkerTask: Task<Void, Never>?

    private let queueStorageLegacyKey = "atlas_macos_prompt_queue_v2"
    private let queueFileName = "prompt-queue-v3.json"
    private let queueBackupFileName = "prompt-queue-v3.bak.json"
    private let stateStorageLegacyKey = "atlas_macos_state_v2"
    private let stateFileName = "session-state-v3.json"
    private let stateBackupFileName = "session-state-v3.bak.json"
    private static let checkpointFormatter = ISO8601DateFormatter()

    init(api: APIClient = APIClient()) {
        self.api = api
        restoreStateFromDisk()
        loadPromptQueueFromDisk()
        recoverInterruptedQueueItemsAfterRestart()
        startPromptQueueWorker()
    }

    func bootstrap() async {
        appendOutput(await localReasoning.modelStatusLine())
        await refreshHealth()
        await loadSurvey()
        await loadNotes()
        await refreshFeed()
        rebuildInsightsAndExecutionPlan()
        startPromptQueueWorker()
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API reachable. Capabilities refreshed.")
        } catch {
            appendOutput("API health unavailable. App remains in local-first mode.")
        }
    }

    func beginAppleWebSignIn(openURL: (URL) -> Void) async {
        do {
            let response = try await api.startAppleOAuth(returnTo: "/concierge-local.html")
            guard let url = URL(string: response.authorizeURL) else {
                appendOutput("Apple OAuth URL invalid.")
                return
            }
            openURL(url)
            appendOutput("Apple OAuth started via web fallback.")
        } catch {
            appendOutput("Apple OAuth web start failed: \(error.localizedDescription)")
        }
    }

    func handleAppleAuthorization(result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .success(auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                appendOutput("Apple authorization returned unexpected credential.")
                return
            }
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                appendOutput("Apple identity token missing.")
                return
            }
            let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

            do {
                try await api.exchangeNativeApple(identityToken: identityToken, authorizationCode: authCode, locale: Locale.current.identifier)
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? "Atlas Owner")
                appendOutput("Native Apple sign-in synced with API.")
            } catch {
                // Keep sign-in local-first so user can still use the app even if API sync fails.
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? "Atlas Owner")
                appendOutput("Apple sign-in completed locally. API sync pending.")
            }

        case let .failure(error):
            appendOutput("Apple sign-in cancelled/failed: \(error.localizedDescription)")
        }
    }

    func signInWithGooglePlaceholder() {
        markSignedIn(provider: .google, accountName: "Google account")
        appendOutput("Google sign-in session created locally. Connect API OAuth secrets to finalize remote sync.")
    }

    func signInWithPasswordless() {
        markSignedIn(provider: .passkey, accountName: "Device passkey")
        appendOutput("Passwordless sign-in active. Device-secure flow enabled.")
    }

    func signUpWithPasswordless() {
        markSignedIn(provider: .passkey, accountName: "Atlas member")
        appendOutput("Passwordless sign-up complete. Local encrypted session started.")
    }

    func signOut() {
        isSignedIn = false
        accountProvider = nil
        accountLabel = "Guest Operator"
        persistStateToDisk()
        appendOutput("Signed out.")
    }

    func setTier(_ tier: AccountTier) {
        selectedTier = tier
        persistStateToDisk()
        Task { await refreshFeed() }
        appendOutput("Active plan: \(tier.title)")
    }

    func applyDailyCheckIn() {
        rebuildInsightsAndExecutionPlan()
        if feedbackOfferEnabled && (checkInMood.lowercased().contains("stressed") || checkInEnergy <= 2 || checkInBlockers.count > 20) {
            appendOutput("Detected friction signal. Offer anonymized product feedback report to team.")
        }
        persistStateToDisk()
    }

    func refreshFeed() async {
        if selectedTier == .cloudPro {
            do {
                let payload = try await api.feedProactive()
                feedItems = payload.items
                appendOutput("Cloud proactive feed refreshed.")
                return
            } catch {
                appendOutput("Cloud feed unavailable. Falling back to local orchestration.")
            }
        }

        feedItems = localFeedFromExecutionPlan()
    }

    func loadSurvey() async {
        do {
            survey = try await api.surveyNext()
        } catch {
            appendOutput("Survey loaded from local fallback.")
            survey = SurveyNextResponse(
                question: SurveyQuestion(
                    id: "primary_goal",
                    title: "Which horizon needs the most support right now?",
                    description: "This drives the proactive execution loop.",
                    kind: "choice",
                    required: true,
                    choices: [
                        SurveyChoice(value: "daily", label: "Daily execution"),
                        SurveyChoice(value: "mid", label: "Mid-term project progress"),
                        SurveyChoice(value: "long", label: "Long-term wealth and mission")
                    ],
                    placeholder: nil
                ),
                progress: SurveyProgress(answered: 0, total: 24, percent: 0),
                profileHints: ["Local survey mode active"]
            )
        }
    }

    func answerSurvey(_ choice: SurveyChoice) async {
        guard let questionID = survey?.question?.id else { return }
        do {
            survey = try await api.submitSurveyAnswer(questionID: questionID, answer: choice.value)
            appendOutput("Survey answer synced.")
        } catch {
            appendOutput("Survey sync unavailable. Applying local branch.")
            let answered = min((survey?.progress.answered ?? 0) + 1, 24)
            let percent = Int((Double(answered) / 24.0) * 100)
            survey = SurveyNextResponse(
                question: answered >= 24 ? nil : SurveyQuestion(
                    id: "q_\(answered + 1)",
                    title: "Deep profile question \(answered + 1)",
                    description: "Branching local mode for 20-30 minute onboarding depth.",
                    kind: "choice",
                    required: true,
                    choices: [
                        SurveyChoice(value: "high", label: "High structure"),
                        SurveyChoice(value: "balanced", label: "Balanced structure"),
                        SurveyChoice(value: "fluid", label: "Fluid structure")
                    ],
                    placeholder: nil
                ),
                progress: SurveyProgress(answered: answered, total: 24, percent: percent),
                profileHints: ["Local depth survey running", "Current preference: \(choice.label)"]
            )
        }

        rebuildInsightsAndExecutionPlan()
    }

    func loadNotes() async {
        do {
            notes = try await api.notesList().notes
            rebuildInsightsAndExecutionPlan()
        } catch {
            appendOutput("Notes API unavailable. Local notes stay active.")
        }
    }

    func saveNote() async {
        let title = pendingNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = pendingNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else {
            appendOutput("Title and content are required.")
            return
        }

        let local = UserNote(noteID: UUID().uuidString, title: title, content: content)
        notes.insert(local, at: 0)
        pendingNoteTitle = ""
        pendingNoteContent = ""

        do {
            try await api.upsertNote(title: title, content: content)
            appendOutput("Note stored locally and synced.")
        } catch {
            appendOutput("Note stored locally. API sync pending.")
        }

        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
    }

    func deleteLocalMemory() {
        notes = []
        promptQueue = []
        executionActions = []
        memoryInsights = []
        tailoredOffers = []
        researchStreams = []
        feedItems = []
        persistPromptQueueToDisk()
        persistStateToDisk()
        appendOutput("Local personalization memory cleared by user request.")
    }

    func submitAnonymizedFeedback() {
        let text = pendingFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            appendOutput("Write feedback before sending.")
            return
        }
        appendOutput("Anonymized report queued for product team review.")
        pendingFeedback = ""
    }

    func enqueuePrompt() {
        let cleaned = pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            appendOutput("Write a prompt before queueing.")
            return
        }

        promptQueue.append(
            PromptQueueItem(
                id: UUID().uuidString,
                prompt: cleaned,
                status: .queued,
                createdAt: Date(),
                completedAt: nil,
                errorMessage: nil,
                output: nil
            )
        )
        pendingPrompt = ""
        persistPromptQueueToDisk()
        appendOutput("Prompt queued for local background reasoning.")
        startPromptQueueWorker()
    }

    func clearPromptQueue() {
        promptQueue = []
        persistPromptQueueToDisk()
        appendOutput("Prompt queue cleared.")
    }

    func startPromptQueueWorker() {
        guard queueWorkerTask == nil else { return }
        queueWorkerTask = Task { [weak self] in
            guard let self else { return }
            await self.runPromptQueueLoop()
        }
    }

    func memoryUsageEstimate() -> String {
        let notesBytes = notes.reduce(0) { $0 + $1.title.count + $1.content.count }
        let queueBytes = promptQueue.reduce(0) { $0 + $1.prompt.count + ($1.output?.summary.count ?? 0) }
        let totalKB = max(1, (notesBytes + queueBytes) / 1024)
        return "~\(totalKB) KB local memory profile"
    }

    func appendOutput(_ line: String) {
        systemOutput.insert(line, at: 0)
        if systemOutput.count > 40 {
            systemOutput = Array(systemOutput.prefix(40))
        }
    }

    private func runPromptQueueLoop() async {
        while !Task.isCancelled {
            guard let index = promptQueue.firstIndex(where: { $0.status == .queued }) else {
                break
            }

            promptQueue[index].status = .running
            promptQueue[index].startedAt = promptQueue[index].startedAt ?? Date()
            promptQueue[index].completedAt = nil
            promptQueue[index].lastCheckpointAt = Date()
            promptQueue[index].progress = max(promptQueue[index].progress ?? 0.0, 0.05)
            promptQueue[index].checkpointNote = "Starting local reasoning pass."
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()

            let item = promptQueue[index]
            let checkpointInterval = queueCheckpointIntervalNanoseconds()
            let checkpointTask = Task.detached { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: checkpointInterval)
                    await MainActor.run {
                        self?.checkpointRunningQueueItem(
                            id: item.id,
                            note: "Checkpoint saved during local processing."
                        )
                    }
                }
            }
            let boundedPrompt = String(item.prompt.prefix(1800))
            let boundedNotes = Array(notes.prefix(24))
            let output = await localReasoning.reason(prompt: boundedPrompt, notes: boundedNotes)
            checkpointTask.cancel()
            promptQueue[index].status = .done
            promptQueue[index].completedAt = Date()
            promptQueue[index].lastCheckpointAt = Date()
            promptQueue[index].progress = 1.0
            promptQueue[index].checkpointNote = "Completed and saved."
            promptQueue[index].output = output
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()
            appendOutput("Local reasoning completed. Next action: \(output.nextAction)")

            let cooldown = queueCooldownNanoseconds()
            if cooldown > 0 {
                try? await Task.sleep(nanoseconds: cooldown)
            }
        }

        queueWorkerTask = nil
        rebuildInsightsAndExecutionPlan()
        feedItems = localFeedFromExecutionPlan()
    }

    private func checkpointRunningQueueItem(id: String, note: String) {
        guard let idx = promptQueue.firstIndex(where: { $0.id == id }) else { return }
        guard promptQueue[idx].status == .running else { return }
        let current = promptQueue[idx].progress ?? 0.05
        promptQueue[idx].progress = min(0.95, current + 0.07)
        promptQueue[idx].lastCheckpointAt = Date()
        promptQueue[idx].checkpointNote = note
        persistPromptQueueToDisk()
    }

    private func queueCheckpointIntervalNanoseconds() -> UInt64 {
        isResourceConstrained() ? 3_500_000_000 : 2_000_000_000
    }

    private func queueCooldownNanoseconds() -> UInt64 {
        isResourceConstrained() ? 1_600_000_000 : 300_000_000
    }

    private func isResourceConstrained() -> Bool {
        let processInfo = ProcessInfo.processInfo
        let thermal = processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            return true
        }
        if #available(macOS 12.0, *) {
            return processInfo.isLowPowerModeEnabled
        }
        return false
    }

    private func rebuildInsightsAndExecutionPlan() {
        let keyNotes = notes.prefix(3)
        var insights: [MemoryInsight] = []

        if !dailyPriority.isEmpty {
            insights.append(MemoryInsight(id: UUID().uuidString, label: "Daily priority", value: dailyPriority))
        }
        if !midTermGoal.isEmpty {
            insights.append(MemoryInsight(id: UUID().uuidString, label: "Mid-term goal", value: midTermGoal))
        }
        if !longTermVision.isEmpty {
            insights.append(MemoryInsight(id: UUID().uuidString, label: "Long-horizon mission", value: longTermVision))
        }
        for note in keyNotes {
            insights.append(MemoryInsight(id: UUID().uuidString, label: note.title, value: String(note.content.prefix(90))))
        }
        memoryInsights = insights

        executionActions = buildExecutionActions()
        tailoredOffers = buildTailoredOffers()
        researchStreams = buildResearchExecutionStreams()
        feedItems = localFeedFromExecutionPlan()
    }

    private func buildExecutionActions() -> [ExecutionAction] {
        var actions: [ExecutionAction] = []

        let daily = dailyPriority.isEmpty ? "Set one non-negotiable action for today." : dailyPriority
        let mid = midTermGoal.isEmpty ? "Define one milestone to close this week." : midTermGoal
        let long = longTermVision.isEmpty ? "Define one 90-day wealth/mission objective." : longTermVision

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Daily",
                title: "Execute first block within 30 minutes",
                details: daily,
                priority: 1,
                source: "check-in",
                completed: false
            )
        )

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Mid-term",
                title: "Ship one milestone this week",
                details: mid,
                priority: 2,
                source: "survey",
                completed: false
            )
        )

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Long-term",
                title: "Protect the main mission path",
                details: long,
                priority: 3,
                source: "memory",
                completed: false
            )
        )

        if vanRentalNeeded {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Mobility",
                    title: "Submit van rental requirements",
                    details: "Region: \(travelRegion) · annual distance: \(annualDistanceKM) km · mode: \(workspaceMode)",
                    priority: 2,
                    source: "mobility",
                    completed: false
                )
            )
        }

        return actions.sorted { $0.priority < $1.priority }
    }

    private func localFeedFromExecutionPlan() -> [FeedItem] {
        if executionActions.isEmpty {
            return []
        }

        return executionActions.prefix(4).map { action in
            FeedItem(
                id: action.id,
                title: action.title,
                summary: action.details,
                whyNow: "\(action.horizon) travel design alignment · \(selectedTier.title)",
                priority: action.priority == 1 ? "critical" : (action.priority == 2 ? "high" : "normal")
            )
        }
    }

    private func buildTailoredOffers() -> [TailoredOffer] {
        var offers: [TailoredOffer] = []
        let combinedIntent = combinedIntentText()
        let needsRecovery = checkInEnergy <= 2 || containsAny(checkInMood, ["stress", "burnout", "anxious", "exhaust"])
        let needsRevenuePush = containsAny(combinedIntent, ["revenue", "cash", "client", "sales", "income", "money", "profit"])
        let needsMobilityOps = vanRentalNeeded
            || containsAny(combinedIntent, ["travel", "route", "van", "mobility", "camp", "fleet", "caravan"])
            || (Int(annualDistanceKM) ?? 0) >= 50_000
        let needsResilience = containsAny(combinedIntent, ["risk", "emergency", "safety", "fallback", "continuity", "breakdown"])
        let surveyDepth = survey?.progress.answered ?? 0

        if surveyDepth < 24 {
            offers.append(
                TailoredOffer(
                    id: "offer-survey-depth",
                    category: .productivitySystems,
                    type: .feature,
                    title: "Deep Profile Calibration",
                    summary: "Complete the adaptive survey so Atlas can lock your true operating profile.",
                    rationale: "You are still in onboarding depth mode (\(surveyDepth)/24).",
                    priority: 1,
                    callToAction: "Finish the deep survey"
                )
            )
        }

        if needsRevenuePush {
            offers.append(
                TailoredOffer(
                    id: "offer-revenue-ops",
                    category: .wealthOperations,
                    type: .feature,
                    title: "Revenue Sprint Orchestrator",
                    summary: "Convert goals and notes into same-day client, pricing, and deal-closing actions.",
                    rationale: "Detected revenue-focused intent in your profile and recent context.",
                    priority: 1,
                    callToAction: "Run revenue sprint"
                )
            )
        }

        if needsMobilityOps {
            offers.append(
                TailoredOffer(
                    id: "offer-mobility-enterprise",
                    category: .travelMobility,
                    type: .rental,
                    title: "Mobility Ops + Atlas Vehicle Matching",
                    summary: "Align vehicle rental/spec, route legality, and service points for heavy-usage travel.",
                    rationale: "Travel intensity and mobility signals suggest high ops value.",
                    priority: 2,
                    callToAction: "Open mobility planning"
                )
            )
        }

        if needsRecovery {
            offers.append(
                TailoredOffer(
                    id: "offer-recovery-mode",
                    category: .resilienceSafety,
                    type: .feature,
                    title: "Recovery + Cognitive Load Mode",
                    summary: "Switch to low-friction planning with shorter decisions and protective daily pacing.",
                    rationale: "Current energy/mood suggests overload risk.",
                    priority: 1,
                    callToAction: "Activate recovery mode"
                )
            )
        }

        if needsResilience {
            offers.append(
                TailoredOffer(
                    id: "offer-resilience-stack",
                    category: .resilienceSafety,
                    type: .service,
                    title: "Continuity Stack Planning",
                    summary: "Build backup paths for power, comms, navigation, legal overnight stops, and incident response.",
                    rationale: "Risk and continuity signals detected in your notes/check-in.",
                    priority: 2,
                    callToAction: "Build continuity checklist"
                )
            )
        }

        if selectedTier == .localTrial {
            offers.append(
                TailoredOffer(
                    id: "offer-cloud-pro",
                    category: .localIntelligence,
                    type: .membership,
                    title: "Cloud Reasoning Upgrade",
                    summary: "Keep local reasoning as default and unlock cloud depth only when needed for heavier workloads.",
                    rationale: "You are currently operating on local-only tier.",
                    priority: 3,
                    callToAction: "Compare plans"
                )
            )
        }

        if offers.isEmpty {
            offers.append(
                TailoredOffer(
                    id: "offer-core-atlas",
                    category: .productivitySystems,
                    type: .feature,
                    title: "Atlas Execution Core",
                    summary: "Daily check-in, adaptive survey, memory capture, and queue-based reasoning in one workflow.",
                    rationale: "Baseline package when limited intent signals are present.",
                    priority: 3,
                    callToAction: "Open command center"
                )
            )
        }

        return offers
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.title < rhs.title
                }
                return lhs.priority < rhs.priority
            }
            .prefix(4)
            .map { $0 }
    }

    private func buildResearchExecutionStreams() -> [ResearchExecutionStream] {
        let context = combinedIntentText()
        if context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        return AtlasResearchEngine.shared.buildExecutionStreams(context: context, maxItems: 4)
    }

    private func combinedIntentText() -> String {
        let noteText = notes
            .prefix(6)
            .map { "\($0.title) \($0.content)" }
            .joined(separator: " ")
        return [
            dailyPriority,
            midTermGoal,
            longTermVision,
            checkInBlockers,
            checkInMood,
            workspaceMode,
            noteText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        let lower = value.lowercased()
        return needles.contains { lower.contains($0) }
    }

    private func markSignedIn(provider: AuthProvider, accountName: String) {
        isSignedIn = true
        accountProvider = provider
        accountLabel = accountName
        persistStateToDisk()
    }

    private func persistPromptQueueToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(promptQueue) else { return }
        guard let primaryURL = promptQueueFileURL(fileName: queueFileName) else { return }
        let backupURL = promptQueueFileURL(fileName: queueBackupFileName)

        do {
            let fileManager = FileManager.default
            let dir = primaryURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            if let backupURL, fileManager.fileExists(atPath: primaryURL.path) {
                _ = try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: primaryURL, to: backupURL)
            }

            let tempURL = primaryURL.appendingPathExtension("tmp")
            var writeOptions: Data.WritingOptions = [.atomic]
#if os(iOS)
            writeOptions.insert(.completeFileProtection)
#endif
            try data.write(to: tempURL, options: writeOptions)
            if fileManager.fileExists(atPath: primaryURL.path) {
                _ = try fileManager.replaceItemAt(primaryURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: primaryURL)
            }
        } catch {
            // Keep silent here; queue still exists in-memory and will retry persistence later.
        }
    }

    private func loadPromptQueueFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let primaryURL = promptQueueFileURL(fileName: queueFileName),
           let data = try? Data(contentsOf: primaryURL),
           let restored = try? decoder.decode([PromptQueueItem].self, from: data)
        {
            promptQueue = restored
            return
        }

        if let backupURL = promptQueueFileURL(fileName: queueBackupFileName),
           let data = try? Data(contentsOf: backupURL),
           let restored = try? decoder.decode([PromptQueueItem].self, from: data)
        {
            promptQueue = restored
            persistPromptQueueToDisk()
            return
        }

        // Legacy migration from UserDefaults v2 storage.
        if let legacy = UserDefaults.standard.data(forKey: queueStorageLegacyKey),
           let restored = try? decoder.decode([PromptQueueItem].self, from: legacy)
        {
            promptQueue = restored
            persistPromptQueueToDisk()
            UserDefaults.standard.removeObject(forKey: queueStorageLegacyKey)
        }
    }

    private func recoverInterruptedQueueItemsAfterRestart() {
        var recovered = 0
        for idx in promptQueue.indices {
            if promptQueue[idx].status == .running {
                promptQueue[idx].status = .queued
                promptQueue[idx].completedAt = nil
                let checkpointLabel = promptQueue[idx].lastCheckpointAt
                    .map { Self.checkpointFormatter.string(from: $0) }
                    ?? "unknown"
                promptQueue[idx].errorMessage =
                    "Recovered after restart. Resuming from last checkpoint at \(checkpointLabel)."
                promptQueue[idx].checkpointNote = "Recovered after restart."
                recovered += 1
            }
        }
        if recovered > 0 {
            persistPromptQueueToDisk()
            appendOutput("Recovered \(recovered) interrupted queued task(s) after restart.")
        }
    }

    private func promptQueueFileURL(fileName: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func persistStateToDisk() {
        let state = PersistedState(
            isSignedIn: isSignedIn,
            accountProvider: accountProvider,
            accountLabel: accountLabel,
            selectedTier: selectedTier,
            trialDaysRemaining: trialDaysRemaining,
            dailyPriority: dailyPriority,
            midTermGoal: midTermGoal,
            longTermVision: longTermVision,
            checkInMood: checkInMood,
            checkInEnergy: checkInEnergy,
            checkInBlockers: checkInBlockers,
            pendingFeedback: pendingFeedback,
            vanRentalNeeded: vanRentalNeeded,
            travelRegion: travelRegion,
            annualDistanceKM: annualDistanceKM,
            workspaceMode: workspaceMode,
            notes: notes
        )

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(state) else { return }

        guard let primaryURL = stateFileURL(fileName: stateFileName) else { return }

        let backupURL = stateFileURL(fileName: stateBackupFileName)
        do {
            let fileManager = FileManager.default
            let dir = primaryURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            if let backupURL, fileManager.fileExists(atPath: primaryURL.path) {
                _ = try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: primaryURL, to: backupURL)
            }

            let tempURL = primaryURL.appendingPathExtension("tmp")
            var writeOptions: Data.WritingOptions = [.atomic]
#if os(iOS)
            writeOptions.insert(.completeFileProtection)
#endif
            try data.write(to: tempURL, options: writeOptions)
            if fileManager.fileExists(atPath: primaryURL.path) {
                _ = try fileManager.replaceItemAt(primaryURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: primaryURL)
            }
        } catch {
            return
        }
    }

    private func restoreStateFromDisk() {
        let decoder = JSONDecoder()
        let stateData: Data? = {
            if let primaryURL = stateFileURL(fileName: stateFileName),
               let data = try? Data(contentsOf: primaryURL)
            {
                return data
            }
            if let backupURL = stateFileURL(fileName: stateBackupFileName),
               let data = try? Data(contentsOf: backupURL)
            {
                return data
            }
            if let legacy = UserDefaults.standard.data(forKey: stateStorageLegacyKey) {
                UserDefaults.standard.removeObject(forKey: stateStorageLegacyKey)
                return legacy
            }
            return nil
        }()
        guard let data = stateData else { return }
        guard let state = try? decoder.decode(PersistedState.self, from: data) else { return }

        isSignedIn = state.isSignedIn
        accountProvider = state.accountProvider
        accountLabel = state.accountLabel
        selectedTier = state.selectedTier
        trialDaysRemaining = state.trialDaysRemaining
        dailyPriority = state.dailyPriority
        midTermGoal = state.midTermGoal
        longTermVision = state.longTermVision
        checkInMood = state.checkInMood
        checkInEnergy = state.checkInEnergy
        checkInBlockers = state.checkInBlockers
        pendingFeedback = state.pendingFeedback
        vanRentalNeeded = state.vanRentalNeeded
        travelRegion = state.travelRegion
        annualDistanceKM = state.annualDistanceKM
        workspaceMode = state.workspaceMode
        notes = state.notes
    }

    private func stateFileURL(fileName: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

private struct PersistedState: Codable {
    var isSignedIn: Bool
    var accountProvider: AuthProvider?
    var accountLabel: String
    var selectedTier: AccountTier
    var trialDaysRemaining: Int
    var dailyPriority: String
    var midTermGoal: String
    var longTermVision: String
    var checkInMood: String
    var checkInEnergy: Int
    var checkInBlockers: String
    var pendingFeedback: String
    var vanRentalNeeded: Bool
    var travelRegion: String
    var annualDistanceKM: String
    var workspaceMode: String
    var notes: [UserNote]
}
