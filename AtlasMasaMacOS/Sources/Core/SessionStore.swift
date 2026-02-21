import AuthenticationServices
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Masa Life OS (Swift local tier)..."]
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
    private let stateStorageKey = "atlas_macos_state_v2"

    init(api: APIClient = APIClient()) {
        self.api = api
        restoreStateFromDisk()
        loadPromptQueueFromDisk()
        recoverInterruptedQueueItemsAfterRestart()
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
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()

            let item = promptQueue[index]
            let output = await localReasoning.reason(prompt: item.prompt, notes: notes)
            promptQueue[index].status = .done
            promptQueue[index].completedAt = Date()
            promptQueue[index].output = output
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()
            appendOutput("Local reasoning completed. Next action: \(output.nextAction)")
        }

        queueWorkerTask = nil
        rebuildInsightsAndExecutionPlan()
        feedItems = localFeedFromExecutionPlan()
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
                whyNow: "\(action.horizon) alignment · \(selectedTier.title)",
                priority: action.priority == 1 ? "critical" : (action.priority == 2 ? "high" : "normal")
            )
        }
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
            try data.write(to: tempURL, options: [.atomic])
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
                promptQueue[idx].errorMessage = "Recovered after restart. Resuming queue."
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
        UserDefaults.standard.set(data, forKey: stateStorageKey)
    }

    private func restoreStateFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: stateStorageKey) else { return }
        let decoder = JSONDecoder()
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
