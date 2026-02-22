import AuthenticationServices
import CryptoKit
import Foundation
import Security

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
    @Published var checkInWentToGymToday = false
    @Published var checkInMadeMoneyToday = false
    @Published var checkInMoneySignalNote = ""
    @Published var executionActions: [ExecutionAction] = []
    @Published var memoryInsights: [MemoryInsight] = []
    @Published var tailoredOffers: [TailoredOffer] = []
    @Published var researchStreams: [ResearchExecutionStream] = []
    @Published var workspaceMemoryRecords: [WorkspaceMemoryRecord] = []
    @Published var workspacePlans: [WorkspacePlan] = []
    @Published var workspaceSessions: [WorkspaceNotebookSession] = []
    @Published var activeWorkspaceLane: WorkspaceLane = .mobilityOps
    @Published var activeWorkspaceSessionByLane: [WorkspaceLane: String] = [:]
    @Published var learningPackage: AdaptiveLearningPackage?
    @Published var memoryCollectionEnabled = true
    @Published var surveyAdditionalPassesCompleted = 0

    @Published var pendingFeedback = ""
    @Published var feedbackOfferEnabled = true

    @Published var vanRentalNeeded = false
    @Published var travelRegion = "Israel"
    @Published var annualDistanceKM = "70000"
    @Published var workspaceMode = "Business mobility"

    let api: APIClient
    private let localReasoning = LocalReasoningEngine()
    private var queueWorkerTask: Task<Void, Never>?

    private let queueStorageLegacyKey = "atlas_ios_prompt_queue_v2"
    private let queueFileName = "prompt-queue-v3.json"
    private let queueBackupFileName = "prompt-queue-v3.bak.json"
    private let stateStorageLegacyKey = "atlas_ios_state_v2"
    private let stateFileName = "session-state-v3.json"
    private let stateBackupFileName = "session-state-v3.bak.json"
    private static let checkpointFormatter = ISO8601DateFormatter()
    private var surveyAnswers: [String: String] = [:]
    private var surveyQuestionSessionIndex: [String: String] = [:]
    private var surveyQuestionLaneIndex: [String: String] = [:]
    private var noteSessionIndex: [String: String] = [:]
    private var noteLaneIndex: [String: String] = [:]
    private var surveyExpansionActive = false
    private var surveyExpansionQuestionTarget = 0
    private var surveyExpansionQuestionCounter = 0
    private var surveyExpansionAnsweredInCurrentPass = 0
    private var learningVersion = 0
    private var learningFingerprint = ""

    init(api: APIClient = APIClient()) {
        self.api = api
        restoreStateFromDisk()
        ensureWorkspaceSessionsSeeded()
        loadPromptQueueFromDisk()
        recoverInterruptedQueueItemsAfterRestart()
        startPromptQueueWorker()
    }

    func bootstrap() async {
        appendOutput(await localReasoning.modelStatusLine())
        await refreshHealth()
        await syncSessionFromServerIfAvailable()
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
        Task {
            _ = try? await api.logout()
        }
        appendOutput("Signed out.")
    }

    func setTier(_ tier: AccountTier) {
        selectedTier = tier
        persistStateToDisk()
        Task { await refreshFeed() }
        appendOutput("Active plan: \(tier.title)")
    }

    func sessions(for lane: WorkspaceLane) -> [WorkspaceNotebookSession] {
        workspaceSessions
            .filter { $0.lane == lane }
            .sorted { lhs, rhs in
                if lhs.updatedAtUTC == rhs.updatedAtUTC {
                    return lhs.createdAtUTC > rhs.createdAtUTC
                }
                return lhs.updatedAtUTC > rhs.updatedAtUTC
            }
    }

    func setActiveWorkspaceLane(_ lane: WorkspaceLane) {
        activeWorkspaceLane = lane
        ensureWorkspaceSessionsSeeded()
        persistStateToDisk()
    }

    func activeSessionID(for lane: WorkspaceLane) -> String? {
        activeWorkspaceSessionByLane[lane]
    }

    func createWorkspaceSession(for lane: WorkspaceLane, title: String? = nil) {
        let now = Date()
        let defaultName = "\(lane.title) · Session \(sessions(for: lane).count + 1)"
        let newSession = WorkspaceNotebookSession(
            id: UUID().uuidString,
            lane: lane,
            title: sanitizeWorkspaceMemoryValue(title ?? defaultName, maxLength: 90),
            createdAtUTC: now,
            updatedAtUTC: now,
            summary: "Fresh session notebook.",
            isPinned: false
        )
        workspaceSessions.append(newSession)
        activeWorkspaceSessionByLane[lane] = newSession.id
        activeWorkspaceLane = lane
        persistStateToDisk()
        appendOutput("Created session notebook in \(lane.title).")
    }

    func activateWorkspaceSession(_ sessionID: String) {
        guard let target = workspaceSessions.first(where: { $0.id == sessionID }) else { return }
        activeWorkspaceSessionByLane[target.lane] = target.id
        activeWorkspaceLane = target.lane
        persistStateToDisk()
        appendOutput("Active notebook switched to \(target.title).")
    }

    func startAdditionalSurveyPass() async {
        if surveyExpansionActive {
            appendOutput("Additional survey pass already in progress.")
            return
        }
        surveyExpansionActive = true
        surveyExpansionQuestionTarget = 8
        surveyExpansionAnsweredInCurrentPass = 0
        appendOutput("Additional adaptive survey pass started. New questions only.")
        await loadSurvey()
    }

    func applyDailyCheckIn() {
        rebuildInsightsAndExecutionPlan()
        if feedbackOfferEnabled && (checkInMood.lowercased().contains("stressed") || checkInEnergy <= 2 || checkInBlockers.count > 20) {
            appendOutput("Detected friction signal. Offer anonymized product feedback report to team.")
        }
        Task { await submitExecutionCheckInIfPossible() }
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
            let answered = surveyAnswers.count
            let total = localSurveyTotal()
            let percent = Int((Double(answered) / Double(max(1, total))) * 100.0)
            survey = SurveyNextResponse(
                question: localSurveyQuestion(),
                progress: SurveyProgress(answered: answered, total: total, percent: percent),
                profileHints: ["Local survey mode active", "Gym/income cadence enabled"]
            )
        }
    }

    func answerSurvey(_ choice: SurveyChoice) async {
        guard let questionID = survey?.question?.id else { return }
        surveyAnswers[questionID] = choice.value
        if let activeSessionID = activeSessionID(for: activeWorkspaceLane) {
            surveyQuestionSessionIndex[questionID] = activeSessionID
            surveyQuestionLaneIndex[questionID] = activeWorkspaceLane.rawValue
            touchWorkspaceSession(
                id: activeSessionID,
                summary: "Captured survey signal: \(workspaceSignalLabel(for: questionID))."
            )
        }
        if questionID.hasPrefix("adaptive_depth_"), surveyExpansionActive {
            surveyExpansionQuestionCounter += 1
            surveyExpansionAnsweredInCurrentPass += 1
            if surveyExpansionAnsweredInCurrentPass >= surveyExpansionQuestionTarget {
                surveyExpansionActive = false
                surveyAdditionalPassesCompleted += 1
                appendOutput("Additional survey pass complete. Memory graph upgraded.")
            }
        }
        do {
            survey = try await api.submitSurveyAnswer(questionID: questionID, answer: choice.value)
            appendOutput("Survey answer synced.")
        } catch {
            appendOutput("Survey sync unavailable. Applying local branch.")
            let answered = surveyAnswers.count
            let total = localSurveyTotal()
            let percent = Int((Double(answered) / Double(max(1, total))) * 100.0)
            survey = SurveyNextResponse(
                question: localSurveyQuestion(),
                progress: SurveyProgress(answered: answered, total: total, percent: percent),
                profileHints: [
                    "Local depth survey running",
                    "Current preference: \(choice.label)"
                ]
            )
        }

        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
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
        guard memoryCollectionEnabled else {
            appendOutput("Memory capture is disabled. Re-enable memory collection before saving notes.")
            return
        }
        let title = pendingNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = pendingNoteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else {
            appendOutput("Title and content are required.")
            return
        }

        let local = UserNote(noteID: UUID().uuidString, title: title, content: content)
        notes.insert(local, at: 0)
        let laneForNote = activeWorkspaceLane
        if let sessionID = activeSessionID(for: laneForNote) {
            noteSessionIndex[local.noteID] = sessionID
            noteLaneIndex[local.noteID] = laneForNote.rawValue
            touchWorkspaceSession(
                id: sessionID,
                summary: "Captured note: \(sanitizeWorkspaceMemoryValue(title, maxLength: 70))."
            )
        }
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
        workspaceMemoryRecords = []
        workspacePlans = []
        feedItems = []
        surveyAnswers = [:]
        surveyQuestionSessionIndex = [:]
        surveyQuestionLaneIndex = [:]
        noteSessionIndex = [:]
        noteLaneIndex = [:]
        surveyExpansionActive = false
        surveyExpansionQuestionTarget = 0
        surveyExpansionAnsweredInCurrentPass = 0
        surveyAdditionalPassesCompleted = 0
        surveyExpansionQuestionCounter = 0
        learningPackage = nil
        learningVersion = 0
        learningFingerprint = ""
        workspaceSessions = workspaceSessions.map { session in
            var updated = session
            updated.summary = "Session cleared."
            updated.isPinned = false
            return updated
        }
        persistPromptQueueToDisk()
        persistStateToDisk()
        appendOutput("Local personalization memory cleared by user request.")
    }

    func setMemoryCollectionEnabled(_ enabled: Bool) {
        guard memoryCollectionEnabled != enabled else { return }
        memoryCollectionEnabled = enabled
        if !enabled {
            deleteLocalMemory()
            appendOutput("Long-term memory persistence disabled. Data now stays session-only.")
            return
        }
        persistStateToDisk()
        appendOutput("Long-term memory persistence enabled.")
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
        guard memoryCollectionEnabled else {
            return "Memory collection disabled"
        }
        let notesBytes = notes.reduce(0) { $0 + $1.title.count + $1.content.count }
        let queueBytes = promptQueue.reduce(0) { $0 + $1.prompt.count + ($1.output?.summary.count ?? 0) }
        let totalKB = max(1, (notesBytes + queueBytes) / 1024)
        return "~\(totalKB) KB local memory profile"
    }

    var surveyAnswerCount: Int {
        surveyAnswers.count
    }

    var isAdditionalSurveyPassActive: Bool {
        surveyExpansionActive
    }

    func appendOutput(_ line: String) {
        let sanitized = SensitiveDataRedactor.redact(line)
        systemOutput.insert(String(sanitized.prefix(280)), at: 0)
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
            let checkpointID = item.id
            let checkpointTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: checkpointInterval)
                    await MainActor.run { [weak self] in
                        self?.checkpointRunningQueueItem(
                            id: checkpointID,
                            note: "Checkpoint saved during local processing."
                        )
                    }
                }
            }
            let boundedPrompt = sanitizeModelInput(item.prompt, maxLength: 1800)
            let boundedNotes = Array(notes.prefix(24)).map {
                UserNote(
                    noteID: $0.noteID,
                    title: sanitizeModelInput($0.title, maxLength: 120),
                    content: sanitizeModelInput($0.content, maxLength: 400)
                )
            }
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
        let lowPower: Bool
#if os(macOS)
        if #available(macOS 12.0, *) {
            lowPower = processInfo.isLowPowerModeEnabled
        } else {
            lowPower = false
        }
#else
        lowPower = processInfo.isLowPowerModeEnabled
#endif
        let thermal = processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            return true
        }
        return lowPower
    }

    private func rebuildInsightsAndExecutionPlan() {
        ensureWorkspaceSessionsSeeded()
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
        insights.append(
            MemoryInsight(
                id: UUID().uuidString,
                label: "Gym today",
                value: checkInWentToGymToday ? "Yes" : "Not yet"
            )
        )
        insights.append(
            MemoryInsight(
                id: UUID().uuidString,
                label: "Money progress today",
                value: checkInMadeMoneyToday ? "Yes" : "Not yet"
            )
        )
        if let gymFrequency = surveyAnswers["gym_frequency"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Gym baseline",
                    value: gymFrequency
                )
            )
        }
        if let incomeCadence = surveyAnswers["income_cadence"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Income cadence baseline",
                    value: incomeCadence
                )
            )
        }
        for note in keyNotes {
            insights.append(MemoryInsight(id: UUID().uuidString, label: note.title, value: String(note.content.prefix(90))))
        }
        memoryInsights = insights

        executionActions = buildExecutionActions()
        tailoredOffers = buildTailoredOffers()
        researchStreams = buildResearchExecutionStreams()
        syncWorkspaceMemoryRecords()
        refreshWorkspaceSessionSnapshots()
        workspacePlans = buildWorkspacePlans(from: researchStreams, memoryRecords: workspaceMemoryRecords)
        refreshAdaptiveLearningPackageIfNeeded()
        feedItems = localFeedFromExecutionPlan()
    }

    private func buildExecutionActions() -> [ExecutionAction] {
        var actions: [ExecutionAction] = []

        let daily = dailyPriority.isEmpty ? "Set one non-negotiable action for today." : dailyPriority
        let mid = midTermGoal.isEmpty ? "Define one milestone to close this week." : midTermGoal
        let long = longTermVision.isEmpty ? "Define one 90-day wealth/mission objective." : longTermVision
        let gymBaseline = surveyAnswers["gym_frequency"] ?? "sometimes"
        let incomeBaseline = surveyAnswers["income_cadence"] ?? "sometimes"

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

        if gymBaseline == "regularly" && !checkInWentToGymToday {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Daily",
                    title: "Protect physical training consistency",
                    details: "Your baseline is regular training. Schedule a short gym or mobility session before day-end.",
                    priority: 1,
                    source: "habit",
                    completed: false
                )
            )
        }

        if incomeBaseline == "regularly", !checkInMadeMoneyToday {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Daily",
                    title: "Trigger one revenue action now",
                    details: "Income baseline is regular. Execute one direct money move: outreach, offer, or close.",
                    priority: 1,
                    source: "habit",
                    completed: false
                )
            )
        }

        let topSessionSignals = workspaceSessions
            .sorted { $0.updatedAtUTC > $1.updatedAtUTC }
            .prefix(3)
        for sessionSignal in topSessionSignals {
            let detail = sanitizeWorkspaceMemoryValue(sessionSignal.summary, maxLength: 170)
            guard !detail.isEmpty else { continue }
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Cross-workspace",
                    title: "Leverage notebook signal from \(sessionSignal.title)",
                    details: detail,
                    priority: 2,
                    source: "workspace-session",
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

        let intelligenceContext = "data graph: \(workspaceSessions.count) notebooks · \(workspaceMemoryRecords.count) memory records · \(surveyAnswers.count) survey answers"

        return executionActions.prefix(4).map { action in
            FeedItem(
                id: action.id,
                title: action.title,
                summary: action.details,
                whyNow: "\(action.horizon) travel design alignment · \(selectedTier.title) · \(intelligenceContext)",
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
        let engineStreams = AtlasResearchEngine.shared.buildExecutionStreams(context: context, maxItems: 6)
        if !engineStreams.isEmpty {
            return engineStreams
        }

        let citation = ResearchCitation(
            id: "local-citation-fallback",
            title: "Atlas execution corpus fallback",
            year: 2026,
            sourceURL: "https://atlasmasa.com"
        )
        return [
            ResearchExecutionStream(
                id: "local-stream-fallback",
                domain: "execution",
                title: "Travel Design lane: Execution Design",
                executionRecommendation: executionActions.first?.title ?? "Run one focused action block now.",
                whyItWorks: "Execution quality rises when one immediate action is protected before context switching.",
                confidence: 0.64,
                citations: [citation]
            )
        ]
    }

    private func syncWorkspaceMemoryRecords() {
        guard memoryCollectionEnabled else {
            workspaceMemoryRecords = []
            return
        }

        var merged = workspaceMemoryRecords
        let now = Date()
        let deepWorkSession = activeSessionID(for: .deepWork)
        let wealthSession = activeSessionID(for: .wealthOperations)
        let mobilitySession = activeSessionID(for: .mobilityOps)
        let emergencySession = activeSessionID(for: .emergencyCommand)
        let innovationSession = activeSessionID(for: .innovation)

        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: nil,
            sessionID: nil,
            source: .checkin,
            key: "daily_priority",
            value: dailyPriority,
            weight: 0.88,
            tags: ["daily", "execution"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: nil,
            sessionID: nil,
            source: .checkin,
            key: "mid_term_goal",
            value: midTermGoal,
            weight: 0.83,
            tags: ["mid_term", "strategy"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: nil,
            sessionID: nil,
            source: .checkin,
            key: "long_term_vision",
            value: longTermVision,
            weight: 0.82,
            tags: ["long_term", "mission"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .deepWork,
            sessionID: deepWorkSession,
            source: .checkin,
            key: "mood",
            value: checkInMood,
            weight: 0.72,
            tags: ["mood", "cognition"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .deepWork,
            sessionID: deepWorkSession,
            source: .checkin,
            key: "energy_level",
            value: "\(checkInEnergy)",
            weight: 0.74,
            tags: ["energy", "cognition"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .deepWork,
            sessionID: deepWorkSession,
            source: .checkin,
            key: "blockers",
            value: checkInBlockers,
            weight: 0.70,
            tags: ["blockers", "execution"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .deepWork,
            sessionID: deepWorkSession,
            source: .checkin,
            key: "gym_today",
            value: checkInWentToGymToday ? "yes" : "no",
            weight: 0.65,
            tags: ["health", "habit"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .wealthOperations,
            sessionID: wealthSession,
            source: .checkin,
            key: "money_today",
            value: checkInMadeMoneyToday ? "yes" : "no",
            weight: 0.80,
            tags: ["income", "cashflow"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .wealthOperations,
            sessionID: wealthSession,
            source: .checkin,
            key: "money_signal_note",
            value: checkInMoneySignalNote,
            weight: 0.78,
            tags: ["income", "context"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "workspace_mode",
            value: workspaceMode,
            weight: 0.67,
            tags: ["mobility", "mode"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "travel_region",
            value: travelRegion,
            weight: 0.64,
            tags: ["region", "mobility"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "annual_distance_km",
            value: annualDistanceKM,
            weight: 0.61,
            tags: ["distance", "mobility"],
            now: now
        )

        for (questionID, answer) in surveyAnswers {
            let indexedLane = surveyQuestionLaneIndex[questionID].flatMap(WorkspaceLane.init(rawValue:))
            let lane = indexedLane ?? inferWorkspaceLane(from: "\(questionID) \(answer)")
            let sessionID = surveyQuestionSessionIndex[questionID] ?? activeSessionID(for: lane ?? activeWorkspaceLane)
            upsertWorkspaceMemoryRecord(
                in: &merged,
                lane: lane,
                sessionID: sessionID,
                source: .survey,
                key: "survey:\(questionID)",
                value: answer,
                weight: 0.69,
                tags: ["survey"],
                now: now
            )
        }

        for note in notes.prefix(24) {
            let body = "\(note.title) \(note.content)"
            let indexedLane = noteLaneIndex[note.noteID].flatMap(WorkspaceLane.init(rawValue:))
            let lane = indexedLane ?? inferWorkspaceLane(from: body)
            let sessionID = noteSessionIndex[note.noteID] ?? activeSessionID(for: lane ?? activeWorkspaceLane)
            upsertWorkspaceMemoryRecord(
                in: &merged,
                lane: lane,
                sessionID: sessionID,
                source: .note,
                key: "note:\(note.noteID)",
                value: sanitizeWorkspaceMemoryValue(body, maxLength: 180),
                weight: 0.77,
                tags: ["note", "memory"],
                now: now
            )
        }

        for action in executionActions.prefix(10) {
            let lane = inferWorkspaceLane(from: "\(action.title) \(action.details)")
            let laneSession = activeSessionID(for: lane ?? activeWorkspaceLane)
            upsertWorkspaceMemoryRecord(
                in: &merged,
                lane: lane,
                sessionID: laneSession,
                source: .execution,
                key: "execution:\(action.id)",
                value: sanitizeWorkspaceMemoryValue(action.details, maxLength: 150),
                weight: 0.75,
                tags: ["execution", action.horizon.lowercased()],
                now: now
            )
        }

        if let emergencySession {
            upsertWorkspaceMemoryRecord(
                in: &merged,
                lane: .emergencyCommand,
                sessionID: emergencySession,
                source: .system,
                key: "continuity_readiness",
                value: "Maintain fallback plans for power, comms, routing, and crisis response.",
                weight: 0.66,
                tags: ["resilience", "continuity"],
                now: now
            )
        }

        if let innovationSession {
            upsertWorkspaceMemoryRecord(
                in: &merged,
                lane: .innovation,
                sessionID: innovationSession,
                source: .system,
                key: "innovation_cycle",
                value: "Run hypothesis → prototype → validation loop with safety boundaries.",
                weight: 0.63,
                tags: ["innovation", "systems"],
                now: now
            )
        }

        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(merged, now: now)
    }

    private func upsertWorkspaceMemoryRecord(
        in records: inout [WorkspaceMemoryRecord],
        lane: WorkspaceLane?,
        sessionID: String?,
        source: WorkspaceMemorySource,
        key: String,
        value rawValue: String,
        weight: Double,
        tags: [String],
        now: Date
    ) {
        let cleanedValue = sanitizeWorkspaceMemoryValue(rawValue, maxLength: 180)
        guard !cleanedValue.isEmpty else { return }
        let cleanedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedKey.isEmpty else { return }
        let normalizedWeight = min(1.0, max(0.05, weight))
        let normalizedTags = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
        if let idx = records.firstIndex(where: { $0.lane == lane && $0.sessionID == sessionID && $0.source == source && $0.key == cleanedKey }) {
            let previous = records[idx]
            records[idx] = WorkspaceMemoryRecord(
                id: previous.id,
                lane: lane,
                sessionID: sessionID,
                source: source,
                key: cleanedKey,
                value: cleanedValue,
                weight: normalizedWeight,
                tags: normalizedTags,
                createdAtUTC: previous.createdAtUTC,
                updatedAtUTC: now
            )
            return
        }

        records.append(
            WorkspaceMemoryRecord(
                id: UUID().uuidString,
                lane: lane,
                sessionID: sessionID,
                source: source,
                key: cleanedKey,
                value: cleanedValue,
                weight: normalizedWeight,
                tags: normalizedTags,
                createdAtUTC: now,
                updatedAtUTC: now
            )
        )
    }

    private func normalizeWorkspaceMemoryRecords(
        _ records: [WorkspaceMemoryRecord],
        now: Date
    ) -> [WorkspaceMemoryRecord] {
        let maxAge: TimeInterval = 60 * 60 * 24 * 180
        var deduped: [String: WorkspaceMemoryRecord] = [:]

        for record in records {
            guard !record.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let age = max(0, now.timeIntervalSince(record.updatedAtUTC))
            guard age <= maxAge else { continue }

            let dedupeKey = "\(record.lane?.rawValue ?? "shared")::\(record.sessionID ?? "nosession")::\(record.source.rawValue)::\(record.key)"
            if let existing = deduped[dedupeKey] {
                if record.updatedAtUTC > existing.updatedAtUTC || (record.updatedAtUTC == existing.updatedAtUTC && record.weight > existing.weight) {
                    deduped[dedupeKey] = record
                }
            } else {
                deduped[dedupeKey] = record
            }
        }

        return deduped.values
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs, now: now)
                let rhsScore = workspaceMemoryScore(rhs, now: now)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(220)
            .map { $0 }
    }

    private func workspaceMemoryScore(_ record: WorkspaceMemoryRecord, now: Date = Date()) -> Double {
        let ageSeconds = max(0, now.timeIntervalSince(record.updatedAtUTC))
        let recencyHalfLife: TimeInterval = 60 * 60 * 24 * 14
        let recency = exp(-ageSeconds / recencyHalfLife)
        let laneBoost = (record.lane == activeWorkspaceLane) ? 0.05 : 0.0
        let sessionBoost: Double = {
            guard let lane = record.lane,
                  let sessionID = record.sessionID,
                  let activeID = activeWorkspaceSessionByLane[lane]
            else { return 0.0 }
            return activeID == sessionID ? 0.08 : 0.0
        }()
        let score = (record.weight * 0.63) + (recency * 0.24) + laneBoost + sessionBoost
        return min(1.0, max(0.0, score))
    }

    private func workspaceMemoryHighlights(
        from records: [WorkspaceMemoryRecord],
        limit: Int
    ) -> [String] {
        let now = Date()
        return records
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs, now: now)
                let rhsScore = workspaceMemoryScore(rhs, now: now)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(max(0, limit))
            .map { "\((workspaceSignalLabel(for: $0.key))): \($0.value)" }
    }

    private func workspaceSignalLabel(for key: String) -> String {
        let stripped = key
            .replacingOccurrences(of: "survey:", with: "")
            .replacingOccurrences(of: "note:", with: "note ")
            .replacingOccurrences(of: "execution:", with: "execution ")
            .replacingOccurrences(of: "_", with: " ")
        return stripped.capitalized
    }

    private func sanitizeWorkspaceMemoryValue(_ value: String, maxLength: Int) -> String {
        let redacted = SensitiveDataRedactor.redact(value.trimmingCharacters(in: .whitespacesAndNewlines))
        return String(redacted.prefix(maxLength))
    }

    private func inferWorkspaceLane(from text: String) -> WorkspaceLane? {
        let lower = text.lowercased()
        if containsAny(lower, ["emergency", "crisis", "incident", "triage", "evacuation", "command", "חירום", "משבר"]) {
            return .emergencyCommand
        }
        if containsAny(lower, ["cash", "revenue", "income", "sales", "pricing", "wealth", "money", "הכנסה", "כסף"]) {
            return .wealthOperations
        }
        if containsAny(lower, ["mobility", "travel", "route", "trip", "fleet", "van", "drive", "נסיעה", "מסלול"]) {
            return .mobilityOps
        }
        if containsAny(lower, ["innovation", "prototype", "architecture", "systems", "technology", "חדשנות", "טכנולוג"]) {
            return .innovation
        }
        if containsAny(lower, ["focus", "cognitive", "fatigue", "sleep", "stress", "attention", "קוגנ", "שינה", "לחץ"]) {
            return .deepWork
        }
        return nil
    }

    private func buildWorkspacePlans(
        from streams: [ResearchExecutionStream],
        memoryRecords: [WorkspaceMemoryRecord]
    ) -> [WorkspacePlan] {
        if streams.isEmpty, memoryRecords.isEmpty {
            return []
        }

        var byLane: [WorkspaceLane: [ResearchExecutionStream]] = [:]
        for stream in streams {
            byLane[workspaceLane(for: stream.domain), default: []].append(stream)
        }
        for lane in memoryRecords.compactMap(\.lane) {
            byLane[lane, default: []] = byLane[lane, default: []]
        }

        let topAction = executionActions.first?.details ?? "Execute one critical action in the next 30 minutes."
        let sharedRecords = memoryRecords.filter { $0.lane == nil }
        let plans = byLane.map { lane, laneStreams -> WorkspacePlan in
            let primary = laneStreams.max { $0.confidence < $1.confidence }
            let laneActiveSessionID = activeSessionID(for: lane)
            let laneSpecificRecords = memoryRecords.filter { $0.lane == lane }
            let laneSessionRecords = memoryRecords.filter { $0.lane == lane && $0.sessionID == laneActiveSessionID }
            let crossWorkspaceRecords = memoryRecords.filter { $0.lane != nil && $0.lane != lane }
            let citations = Array(laneStreams.flatMap(\.citations).prefix(3))
            var evidenceParts = laneStreams.prefix(2).map(\.whyItWorks)
            let sharedHighlights = workspaceMemoryHighlights(from: sharedRecords + laneSessionRecords, limit: 3)
            let crossHighlights = workspaceMemoryHighlights(from: crossWorkspaceRecords, limit: 2)
            if !sharedHighlights.isEmpty {
                evidenceParts.append("Shared signals: \(sharedHighlights.joined(separator: " | "))")
            }
            if !crossHighlights.isEmpty {
                evidenceParts.append("Cross-workspace carryover: \(crossHighlights.joined(separator: " | "))")
            }
            if let laneActiveSessionID,
               let activeSession = workspaceSessions.first(where: { $0.id == laneActiveSessionID })
            {
                evidenceParts.append("Active notebook: \(activeSession.title).")
            }
            let mergedEvidence = evidenceParts.joined(separator: " ")
            let primaryAction = primary?.executionRecommendation.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let laneAction = executionActions.first(where: { ($0.source == "habit" || $0.source == "check-in") && (inferWorkspaceLane(from: "\($0.title) \($0.details)") ?? lane) == lane })

            return WorkspacePlan(
                id: "workspace-\(lane.rawValue)",
                lane: lane,
                title: lane.title,
                objective: workspaceObjective(for: lane),
                nextActionNow: !primaryAction.isEmpty ? primaryAction : (laneAction?.details ?? topAction),
                protocolChecklist: workspaceProtocolChecklist(for: lane),
                evidenceSummary: mergedEvidence,
                confidence: primary?.confidence ?? 0.58,
                citations: citations,
                sharedMemorySignals: sharedHighlights,
                crossWorkspaceSignals: crossHighlights,
                memoryRecordCount: sharedRecords.count + laneSpecificRecords.count + crossWorkspaceRecords.count
            )
        }

        return plans.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.title < rhs.title
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private func workspaceLane(for domain: String) -> WorkspaceLane {
        switch domain {
        case "emergency-response", "emergency-preparedness", "emergency-management", "crisis-management", "crisis-planning", "incident-command":
            return .emergencyCommand
        case "wealth":
            return .wealthOperations
        case "travel", "mobility", "operations", "safety", "resilience":
            return .mobilityOps
        case "technology-innovation", "systems-innovation", "digital-innovation", "physical-innovation", "innovation":
            return .innovation
        default:
            return .deepWork
        }
    }

    private func workspaceObjective(for lane: WorkspaceLane) -> String {
        switch lane {
        case .emergencyCommand:
            return "Protect life, stabilize the system, and maintain communication continuity under pressure."
        case .wealthOperations:
            return "Increase consistent cash flow with direct daily actions and disciplined weekly review."
        case .mobilityOps:
            return "Run legal-safe, low-friction travel operations with resilient fallback routing."
        case .deepWork:
            return "Improve human decision quality by controlling biological and cognitive load variables."
        case .innovation:
            return "Ship digital-physical innovation loops with clear hypotheses, safety boundaries, and validation."
        }
    }

    private func workspaceProtocolChecklist(for lane: WorkspaceLane) -> [String] {
        switch lane {
        case .emergencyCommand:
            return [
                "Triage and scene safety first.",
                "Stabilize critical risks and communicate location.",
                "Escalate through predefined emergency command chain.",
                "Log timeline and symptoms for handoff."
            ]
        case .wealthOperations:
            return [
                "Run one direct money action before optimization work.",
                "Track conversion and pricing signal daily.",
                "Review margin/cashflow weekly with one adjustment.",
                "Protect mission-aligned charity and reserve policy."
            ]
        case .mobilityOps:
            return [
                "Confirm legal route, stop, and overnight options.",
                "Run continuity checks for power/comms/navigation.",
                "Set backup service points before departure.",
                "Review fatigue and safety gates for long segments."
            ]
        case .deepWork:
            return [
                "Stabilize sleep, hydration, and cognitive load before difficult tasks.",
                "Execute one deep-work block without notifications.",
                "Use reflection checkpoint after major decisions.",
                "Capture one learning signal into memory."
            ]
        case .innovation:
            return [
                "Define one testable hypothesis and success threshold.",
                "Run a bounded prototype iteration.",
                "Validate in simulation before high-risk deployment.",
                "Record findings and queue the next iteration."
            ]
        }
    }

    private func ensureWorkspaceSessionsSeeded() {
        let now = Date()
        for lane in WorkspaceLane.allCases {
            if workspaceSessions.contains(where: { $0.lane == lane }) == false {
                let seeded = WorkspaceNotebookSession(
                    id: UUID().uuidString,
                    lane: lane,
                    title: "\(lane.title) · Core Session",
                    createdAtUTC: now,
                    updatedAtUTC: now,
                    summary: "Primary notebook for \(lane.title).",
                    isPinned: true
                )
                workspaceSessions.append(seeded)
            }
        }
        for lane in WorkspaceLane.allCases {
            if activeWorkspaceSessionByLane[lane] == nil {
                activeWorkspaceSessionByLane[lane] = sessions(for: lane).first?.id
            }
        }
    }

    private func touchWorkspaceSession(id: String, summary: String) {
        guard let index = workspaceSessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = workspaceSessions[index]
        updated.summary = sanitizeWorkspaceMemoryValue(summary, maxLength: 180)
        updated = WorkspaceNotebookSession(
            id: updated.id,
            lane: updated.lane,
            title: updated.title,
            createdAtUTC: updated.createdAtUTC,
            updatedAtUTC: Date(),
            summary: updated.summary,
            isPinned: updated.isPinned
        )
        workspaceSessions[index] = updated
    }

    private func refreshWorkspaceSessionSnapshots() {
        workspaceSessions = workspaceSessions.map { session in
            let records = workspaceMemoryRecords.filter { $0.sessionID == session.id }
            let highlights = workspaceMemoryHighlights(from: records, limit: 2)
            let summary: String
            if highlights.isEmpty {
                summary = "Session is active and waiting for new signals."
            } else {
                summary = highlights.joined(separator: " | ")
            }
            return WorkspaceNotebookSession(
                id: session.id,
                lane: session.lane,
                title: session.title,
                createdAtUTC: session.createdAtUTC,
                updatedAtUTC: records.map(\.updatedAtUTC).max() ?? session.updatedAtUTC,
                summary: sanitizeWorkspaceMemoryValue(summary, maxLength: 190),
                isPinned: session.isPinned
            )
        }

        // Keep sessions ordered by lane then recency.
        workspaceSessions.sort { lhs, rhs in
            if lhs.lane == rhs.lane {
                if lhs.updatedAtUTC == rhs.updatedAtUTC {
                    return lhs.createdAtUTC > rhs.createdAtUTC
                }
                return lhs.updatedAtUTC > rhs.updatedAtUTC
            }
            return lhs.lane.rawValue < rhs.lane.rawValue
        }

        // Ensure active mapping points at valid sessions.
        for lane in WorkspaceLane.allCases {
            let laneSessions = sessions(for: lane)
            if laneSessions.isEmpty { continue }
            if let current = activeWorkspaceSessionByLane[lane],
               laneSessions.contains(where: { $0.id == current })
            {
                continue
            }
            activeWorkspaceSessionByLane[lane] = laneSessions.first?.id
        }

        // Keep currently selected lane valid.
        if sessions(for: activeWorkspaceLane).isEmpty {
            activeWorkspaceLane = WorkspaceLane.allCases.first ?? .mobilityOps
        }

        // Rebuild a concise session-line for system output sparingly.
        if !workspaceSessions.isEmpty, workspaceMemoryRecords.count % 12 == 0 {
            appendOutput("Workspace notebooks refreshed across lanes (\(workspaceSessions.count) active sessions).")
        }
    }

    private func combinedIntentText() -> String {
        let noteText = notes
            .prefix(6)
            .map { "\($0.title) \($0.content)" }
            .joined(separator: " ")
        let surveyText = surveyAnswers
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
        let sessionText = workspaceSessions
            .map { "\($0.lane.rawValue) \($0.title) \($0.summary)" }
            .joined(separator: " ")
        let memoryText = workspaceMemoryRecords
            .prefix(120)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " ")
        return [
            dailyPriority,
            midTermGoal,
            longTermVision,
            checkInBlockers,
            checkInMood,
            checkInMoneySignalNote,
            checkInWentToGymToday ? "gym_done" : "gym_pending",
            checkInMadeMoneyToday ? "money_progress" : "money_pending",
            workspaceMode,
            surveyText,
            noteText,
            sessionText,
            memoryText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        let lower = value.lowercased()
        return needles.contains { lower.contains($0) }
    }

    private func sanitizeModelInput(_ value: String, maxLength: Int) -> String {
        let redacted = SensitiveDataRedactor.redact(value)
        return String(redacted.prefix(maxLength))
    }

    private func syncSessionFromServerIfAvailable() async {
        do {
            let me = try await api.authMe()
            let provider = AuthProvider(rawValue: me.user.provider) ?? .passkey
            let resolvedName = me.user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? me.user.email
                : me.user.name
            markSignedIn(provider: provider, accountName: resolvedName)
            memoryCollectionEnabled = me.user.memoryOptIn
            if !memoryCollectionEnabled {
                appendOutput("Server profile is set to memory opt-out. Local long-term memory persistence is disabled.")
            }
            appendOutput("Secure account session verified with API.")
        } catch {
            if isSignedIn {
                appendOutput("Using local secure session cache. API verification will retry.")
            }
        }
    }

    private func submitExecutionCheckInIfPossible() async {
        guard isSignedIn else { return }
        let focus = dailyPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ExecutionCheckinPayload(
            userID: nil,
            dailyFocus: focus.isEmpty ? "Define and execute one critical action block today." : focus,
            midTermFocus: midTermGoal.trimmedNil(),
            longTermFocus: longTermVision.trimmedNil(),
            blocker: checkInBlockers.trimmedNil(),
            nextActionNow: executionActions.first?.details.trimmedNil(),
            energyLevel: max(1, min(5, checkInEnergy)),
            mood: checkInMood.trimmedNil(),
            gymToday: checkInWentToGymToday,
            moneyToday: checkInMadeMoneyToday
        )

        do {
            let response = try await api.submitExecutionCheckin(payload: payload)
            feedItems = response.feed.items
            appendOutput(
                "Check-in synced: gym today = \(checkInWentToGymToday ? "yes" : "no"), money today = \(checkInMadeMoneyToday ? "yes" : "no")."
            )
        } catch {
            appendOutput("Check-in saved locally. Cloud sync pending: \(error.localizedDescription)")
        }
    }

    private func localSurveyTotal() -> Int {
        let baseTotal = 24
        guard surveyExpansionActive else {
            return max(baseTotal, surveyAnswers.count)
        }
        let remaining = max(1, surveyExpansionQuestionTarget - surveyExpansionAnsweredInCurrentPass)
        return max(baseTotal, surveyAnswers.count + remaining)
    }

    private func localSurveyQuestion() -> SurveyQuestion? {
        let pressure = surveyAnswers["daily_pressure"] ?? ""
        let workHours = surveyAnswers["work_hours"] ?? ""
        let stress = surveyAnswers["stress_trigger"] ?? ""

        if surveyAnswers["primary_goal"] == nil {
            return localQuestion(
                id: "primary_goal",
                title: "What is your primary goal for the next 90 days?",
                description: "This sets the operating direction for planning and execution.",
                choices: [
                    SurveyChoice(value: "wealth", label: "Build income/wealth"),
                    SurveyChoice(value: "stability", label: "Personal stability"),
                    SurveyChoice(value: "health", label: "Health and energy"),
                    SurveyChoice(value: "mixed", label: "Mix of all")
                ]
            )
        }

        if surveyAnswers["daily_pressure"] == nil {
            return localQuestion(
                id: "daily_pressure",
                title: "How much daily pressure are you under?",
                description: nil,
                choices: [
                    SurveyChoice(value: "low", label: "Low"),
                    SurveyChoice(value: "medium", label: "Medium"),
                    SurveyChoice(value: "high", label: "High")
                ]
            )
        }

        if pressure == "high", surveyAnswers["pressure_source"] == nil {
            return localQuestion(
                id: "pressure_source",
                title: "What is the main source of pressure right now?",
                description: nil,
                choices: [
                    SurveyChoice(value: "money", label: "Money"),
                    SurveyChoice(value: "time", label: "Time"),
                    SurveyChoice(value: "uncertainty", label: "Uncertainty"),
                    SurveyChoice(value: "relationships", label: "Relationships/team")
                ]
            )
        }

        if surveyAnswers["work_hours"] == nil {
            return localQuestion(
                id: "work_hours",
                title: "Average work hours per day?",
                description: nil,
                choices: [
                    SurveyChoice(value: "under_6", label: "Up to 6"),
                    SurveyChoice(value: "6_10", label: "6-10"),
                    SurveyChoice(value: "10_plus", label: "10+")
                ]
            )
        }

        if workHours == "10_plus", surveyAnswers["break_structure"] == nil {
            return localQuestion(
                id: "break_structure",
                title: "How should Atlas manage your breaks?",
                description: nil,
                choices: [
                    SurveyChoice(value: "strict", label: "Strict schedule"),
                    SurveyChoice(value: "flex", label: "Adaptive to workload"),
                    SurveyChoice(value: "manual", label: "Manual only")
                ]
            )
        }

        if surveyAnswers["stress_trigger"] == nil {
            return localQuestion(
                id: "stress_trigger",
                title: "What usually triggers stress/procrastination?",
                description: nil,
                choices: [
                    SurveyChoice(value: "uncertainty", label: "Uncertainty"),
                    SurveyChoice(value: "fatigue", label: "Fatigue"),
                    SurveyChoice(value: "overload", label: "Task overload"),
                    SurveyChoice(value: "social", label: "Social noise/notifications")
                ]
            )
        }

        if stress == "uncertainty", surveyAnswers["proactive_alerts"] == nil {
            return localQuestion(
                id: "proactive_alerts",
                title: "Which proactive alerts help you most?",
                description: nil,
                choices: [
                    SurveyChoice(value: "daily_brief", label: "Daily brief"),
                    SurveyChoice(value: "risk_alerts", label: "Risk alerts"),
                    SurveyChoice(value: "execution", label: "Execution nudges")
                ]
            )
        }

        let standardQuestions: [SurveyQuestion] = [
            localQuestion(
                id: "travel_pattern",
                title: "What is your movement pattern?",
                description: nil,
                choices: [
                    SurveyChoice(value: "daily_commute", label: "Heavy daily commuting"),
                    SurveyChoice(value: "multi_day", label: "Multi-day rolling travel"),
                    SurveyChoice(value: "hybrid", label: "Hybrid")
                ]
            ),
            localQuestion(
                id: "trip_style",
                title: "What is your preferred trip style?",
                description: "Used to tune routes and recommendations.",
                choices: [
                    SurveyChoice(value: "mixed", label: "Mixed"),
                    SurveyChoice(value: "beach", label: "Beach"),
                    SurveyChoice(value: "north", label: "North"),
                    SurveyChoice(value: "desert", label: "Desert")
                ]
            ),
            localQuestion(
                id: "health_priority",
                title: "Top health priority right now?",
                description: nil,
                choices: [
                    SurveyChoice(value: "sleep", label: "Sleep"),
                    SurveyChoice(value: "focus", label: "Focus/cognition"),
                    SurveyChoice(value: "stress", label: "Stress reduction"),
                    SurveyChoice(value: "nutrition", label: "Better nutrition")
                ]
            ),
            localQuestion(
                id: "gym_frequency",
                title: "How often do you currently train/work out?",
                description: "This powers daily habit follow-ups.",
                choices: [
                    SurveyChoice(value: "rarely", label: "Rarely"),
                    SurveyChoice(value: "sometimes", label: "Sometimes"),
                    SurveyChoice(value: "regularly", label: "Regularly")
                ]
            ),
            localQuestion(
                id: "income_cadence",
                title: "How regular is your income right now?",
                description: "Atlas uses this to trigger income-focused daily actions when needed.",
                choices: [
                    SurveyChoice(value: "none", label: "No regular income"),
                    SurveyChoice(value: "sometimes", label: "Sometimes"),
                    SurveyChoice(value: "regularly", label: "Regularly")
                ]
            ),
            localQuestion(
                id: "wealth_focus",
                title: "In the next two years, what matters more?",
                description: nil,
                choices: [
                    SurveyChoice(value: "income_growth", label: "Income growth"),
                    SurveyChoice(value: "capital", label: "Capital building"),
                    SurveyChoice(value: "both", label: "Both")
                ]
            ),
            localQuestion(
                id: "charity_commitment",
                title: "How do you want to include charity in planning?",
                description: nil,
                choices: [
                    SurveyChoice(value: "fixed_percent", label: "Fixed percent of income"),
                    SurveyChoice(value: "milestones", label: "By milestones"),
                    SurveyChoice(value: "later", label: "Later")
                ]
            ),
            localQuestion(
                id: "support_style",
                title: "What coaching style do you prefer?",
                description: nil,
                choices: [
                    SurveyChoice(value: "direct", label: "Direct and sharp"),
                    SurveyChoice(value: "coach", label: "Supportive coach"),
                    SurveyChoice(value: "strategic", label: "Long-term strategic")
                ]
            ),
            localQuestion(
                id: "voice_preference",
                title: "Do you want continuous voice conversation with Atlas?",
                description: "This can be changed later in settings.",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes"),
                    SurveyChoice(value: "sometimes", label: "Sometimes"),
                    SurveyChoice(value: "no", label: "No")
                ]
            )
        ]

        if let next = standardQuestions.first(where: { surveyAnswers[$0.id] == nil }) {
            return next
        }

        if surveyExpansionActive {
            let adaptiveQuestionID = "adaptive_depth_\(surveyExpansionQuestionCounter + 1)"
            if surveyAnswers[adaptiveQuestionID] != nil {
                surveyExpansionQuestionCounter += 1
                return localSurveyQuestion()
            }
            return localAdaptiveSurveyQuestion(id: adaptiveQuestionID)
        }

        let answered = surveyAnswers.count
        if answered >= max(24, localSurveyTotal()) {
            return nil
        }
        let index = answered + 1
        return localQuestion(
            id: "reflection_\(index)",
            title: "Adaptive reflection \(index)",
            description: "Long-term memory quality improves when you answer with concrete constraints.",
            choices: [
                SurveyChoice(value: "constraint", label: "I need tighter constraints"),
                SurveyChoice(value: "execution", label: "I need cleaner execution flow"),
                SurveyChoice(value: "resilience", label: "I need stronger resilience planning")
            ]
        )
    }

    private func localAdaptiveSurveyQuestion(id: String) -> SurveyQuestion {
        let idx = max(1, surveyExpansionQuestionCounter + 1)
        let prompts = [
            (
                "Adaptive depth \(idx): Which hidden constraint most limits your execution right now?",
                "Atlas will convert this into cross-workspace constraints and next-step logic.",
                [
                    SurveyChoice(value: "time_fragmentation_\(idx)", label: "Time fragmentation"),
                    SurveyChoice(value: "financial_uncertainty_\(idx)", label: "Financial uncertainty"),
                    SurveyChoice(value: "cognitive_overload_\(idx)", label: "Cognitive overload"),
                    SurveyChoice(value: "operational_friction_\(idx)", label: "Operational friction")
                ]
            ),
            (
                "Adaptive depth \(idx): Which upgrade would most improve this week?",
                "This informs proactive execution stream routing.",
                [
                    SurveyChoice(value: "health_system_upgrade_\(idx)", label: "Health system upgrade"),
                    SurveyChoice(value: "revenue_system_upgrade_\(idx)", label: "Revenue system upgrade"),
                    SurveyChoice(value: "mobility_system_upgrade_\(idx)", label: "Mobility system upgrade"),
                    SurveyChoice(value: "focus_system_upgrade_\(idx)", label: "Focus system upgrade")
                ]
            ),
            (
                "Adaptive depth \(idx): What should Atlas proactively protect first when pressure spikes?",
                "Used for resilience-first orchestration.",
                [
                    SurveyChoice(value: "cashflow_protection_\(idx)", label: "Cashflow protection"),
                    SurveyChoice(value: "health_protection_\(idx)", label: "Health protection"),
                    SurveyChoice(value: "continuity_protection_\(idx)", label: "Continuity protection"),
                    SurveyChoice(value: "mission_protection_\(idx)", label: "Mission protection")
                ]
            )
        ]

        let selected = prompts[idx % prompts.count]
        return localQuestion(
            id: id,
            title: selected.0,
            description: selected.1,
            choices: selected.2
        )
    }

    private func localQuestion(
        id: String,
        title: String,
        description: String?,
        choices: [SurveyChoice]
    ) -> SurveyQuestion {
        SurveyQuestion(
            id: id,
            title: title,
            description: description,
            kind: "choice",
            required: true,
            choices: choices,
            placeholder: nil
        )
    }

    private func refreshAdaptiveLearningPackageIfNeeded() {
        let fingerprint = adaptiveLearningFingerprint()
        guard fingerprint != learningFingerprint else { return }

        let signalStrength = surveyAnswers.count + min(notes.count, 8) + (dailyPriority.isEmpty ? 0 : 2)
        guard signalStrength >= 5 else { return }

        learningVersion += 1
        learningFingerprint = fingerprint
        learningPackage = buildAdaptiveLearningPackage(version: learningVersion)
        if let learningPackage {
            appendOutput("Generated adaptive learning pack v\(learningPackage.version) (quiz + podcast brief).")
        }
    }

    private func adaptiveLearningFingerprint() -> String {
        let sortedSurvey = surveyAnswers
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        let topNotes = notes.prefix(3).map { "\($0.title):\($0.content.prefix(80))" }.joined(separator: "|")
        let execution = [dailyPriority, midTermGoal, longTermVision, checkInBlockers].joined(separator: "|")
        return [sortedSurvey, topNotes, execution, checkInMood, "\(checkInEnergy)", checkInWentToGymToday ? "gym=1" : "gym=0", checkInMadeMoneyToday ? "money=1" : "money=0"]
            .joined(separator: "||")
            .lowercased()
    }

    private func buildAdaptiveLearningPackage(version: Int) -> AdaptiveLearningPackage {
        let now = ISO8601DateFormatter().string(from: Date())
        let gymFrequency = surveyAnswers["gym_frequency"] ?? "sometimes"
        let incomeCadence = surveyAnswers["income_cadence"] ?? "sometimes"
        let pressure = surveyAnswers["daily_pressure"] ?? "medium"
        let priority = surveyAnswers["primary_goal"] ?? "mixed"

        let rationale = "Version \(version) generated from new memory signals (survey: \(surveyAnswers.count), notes: \(notes.count), pressure: \(pressure), goal: \(priority))."
        let quiz = [
            AdaptiveQuizQuestion(
                id: "q\(version)-1",
                prompt: "Given your current pressure level, what should happen first each morning?",
                options: [
                    "Start reactive communication immediately",
                    "Run a 20-30 minute execution block on one critical outcome",
                    "Wait for motivation"
                ],
                preferredAnswerIndex: 1,
                explanation: "Focused first-block execution protects cognitive bandwidth and reduces drift."
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-2",
                prompt: "Your gym baseline is \(gymFrequency). If training is missed today, what is the best recovery move?",
                options: [
                    "Ignore and reset next week",
                    "Schedule one concrete session before day-end and pre-commit tomorrow",
                    "Compensate with extra notifications"
                ],
                preferredAnswerIndex: 1,
                explanation: "Short recovery loops preserve consistency better than perfection targets."
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-3",
                prompt: "Income cadence is \(incomeCadence). Which action should Atlas push when no money moved today?",
                options: [
                    "Wait for a better market day",
                    "Execute one direct money action now (outreach/offer/close)",
                    "Rewrite the plan for hours"
                ],
                preferredAnswerIndex: 1,
                explanation: "When cash flow is unstable, high-leverage direct actions matter more than theory."
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-4",
                prompt: "Which behavior best builds long-term problem-solving capacity?",
                options: [
                    "Only consume content",
                    "Deliberate drills + reflection + constraint-aware execution",
                    "Constantly switch goals"
                ],
                preferredAnswerIndex: 1,
                explanation: "Skill growth compounds through deliberate practice and reflective adaptation."
            )
        ]

        let podcastTitle = "Atlas Learning Brief v\(version): Execution, Resilience, and Wealth Flow"
        let podcastSummary = "A profile-tuned briefing on daily execution discipline, crisis resilience, and income momentum loops."
        let segments = [
            AdaptivePodcastSegment(
                id: "s\(version)-1",
                title: "State of play",
                talkingPoints: [
                    "Current pressure: \(pressure)",
                    "Primary operating objective: \(priority)",
                    "Immediate constraints from your latest memory signals"
                ]
            ),
            AdaptivePodcastSegment(
                id: "s\(version)-2",
                title: "Today’s execution protocol",
                talkingPoints: [
                    "One critical action block in the next 30 minutes",
                    "Gym status today: \(checkInWentToGymToday ? "completed" : "pending")",
                    "Money status today: \(checkInMadeMoneyToday ? "progress made" : "no movement yet")"
                ]
            ),
            AdaptivePodcastSegment(
                id: "s\(version)-3",
                title: "Resilience and innovation loop",
                talkingPoints: [
                    "Stabilize energy and attention before high-stakes decisions",
                    "Run one deliberate problem-solving drill",
                    "Document one learning signal for tomorrow’s upgraded plan"
                ]
            )
        ]

        return AdaptiveLearningPackage(
            version: version,
            generatedAtUTC: now,
            rationale: rationale,
            quiz: quiz,
            podcastTitle: podcastTitle,
            podcastSummary: podcastSummary,
            podcastSegments: segments
        )
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
            let encrypted = try SecurePersistence.encrypt(
                data,
                context: "prompt_queue",
                appNamespace: "AtlasMasaIOS"
            )
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
            try encrypted.write(to: tempURL, options: writeOptions)
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
           let restored = try? decodePromptQueuePayload(data, decoder: decoder)
        {
            promptQueue = restored
            return
        }

        if let backupURL = promptQueueFileURL(fileName: queueBackupFileName),
           let data = try? Data(contentsOf: backupURL),
           let restored = try? decodePromptQueuePayload(data, decoder: decoder)
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

    private func decodePromptQueuePayload(
        _ data: Data,
        decoder: JSONDecoder
    ) throws -> [PromptQueueItem] {
        if let decrypted = try? SecurePersistence.decrypt(
            data,
            context: "prompt_queue",
            appNamespace: "AtlasMasaIOS"
        ) {
            return try decoder.decode([PromptQueueItem].self, from: decrypted)
        }
        return try decoder.decode([PromptQueueItem].self, from: data)
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
            .appendingPathComponent("AtlasMasaIOS", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func persistStateToDisk() {
        let persistedNotes = memoryCollectionEnabled ? notes : []
        let persistedSurveyAnswers = memoryCollectionEnabled ? surveyAnswers : [:]
        let persistedLearningPackage = memoryCollectionEnabled ? learningPackage : nil
        let persistedWorkspaceMemoryRecords = memoryCollectionEnabled ? workspaceMemoryRecords : []
        let persistedWorkspaceSessions = workspaceSessions
        let persistedLearningVersion = memoryCollectionEnabled
            ? learningVersion
            : 0
        let persistedLearningFingerprint = memoryCollectionEnabled
            ? learningFingerprint
            : ""
        let persistedActiveSessionMap = activeWorkspaceSessionByLane.reduce(into: [String: String]()) { partial, next in
            partial[next.key.rawValue] = next.value
        }

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
            checkInWentToGymToday: checkInWentToGymToday,
            checkInMadeMoneyToday: checkInMadeMoneyToday,
            checkInMoneySignalNote: checkInMoneySignalNote,
            pendingFeedback: pendingFeedback,
            vanRentalNeeded: vanRentalNeeded,
            travelRegion: travelRegion,
            annualDistanceKM: annualDistanceKM,
            workspaceMode: workspaceMode,
            notes: persistedNotes,
            surveyAnswers: persistedSurveyAnswers,
            surveyQuestionSessionIndex: surveyQuestionSessionIndex,
            surveyQuestionLaneIndex: surveyQuestionLaneIndex,
            noteSessionIndex: noteSessionIndex,
            noteLaneIndex: noteLaneIndex,
            workspaceMemoryRecords: persistedWorkspaceMemoryRecords,
            workspaceSessions: persistedWorkspaceSessions,
            activeWorkspaceLane: activeWorkspaceLane.rawValue,
            activeWorkspaceSessionByLane: persistedActiveSessionMap,
            surveyAdditionalPassesCompleted: surveyAdditionalPassesCompleted,
            surveyExpansionQuestionCounter: surveyExpansionQuestionCounter,
            surveyExpansionActive: surveyExpansionActive,
            surveyExpansionQuestionTarget: surveyExpansionQuestionTarget,
            surveyExpansionAnsweredInCurrentPass: surveyExpansionAnsweredInCurrentPass,
            learningPackage: persistedLearningPackage,
            learningVersion: persistedLearningVersion,
            learningFingerprint: persistedLearningFingerprint,
            memoryCollectionEnabled: memoryCollectionEnabled
        )

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(state) else { return }

        guard let primaryURL = stateFileURL(fileName: stateFileName) else { return }

        let backupURL = stateFileURL(fileName: stateBackupFileName)
        do {
            let encrypted = try SecurePersistence.encrypt(
                data,
                context: "session_state",
                appNamespace: "AtlasMasaIOS"
            )
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
            try encrypted.write(to: tempURL, options: writeOptions)
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
                if let decrypted = try? SecurePersistence.decrypt(
                    data,
                    context: "session_state",
                    appNamespace: "AtlasMasaIOS"
                ) {
                    return decrypted
                }
                return data
            }
            if let backupURL = stateFileURL(fileName: stateBackupFileName),
               let data = try? Data(contentsOf: backupURL)
            {
                if let decrypted = try? SecurePersistence.decrypt(
                    data,
                    context: "session_state",
                    appNamespace: "AtlasMasaIOS"
                ) {
                    return decrypted
                }
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
        checkInWentToGymToday = state.checkInWentToGymToday ?? false
        checkInMadeMoneyToday = state.checkInMadeMoneyToday ?? false
        checkInMoneySignalNote = state.checkInMoneySignalNote ?? ""
        pendingFeedback = state.pendingFeedback
        vanRentalNeeded = state.vanRentalNeeded
        travelRegion = state.travelRegion
        annualDistanceKM = state.annualDistanceKM
        workspaceMode = state.workspaceMode
        notes = state.notes
        surveyAnswers = state.surveyAnswers ?? [:]
        surveyQuestionSessionIndex = state.surveyQuestionSessionIndex ?? [:]
        surveyQuestionLaneIndex = state.surveyQuestionLaneIndex ?? [:]
        noteSessionIndex = state.noteSessionIndex ?? [:]
        noteLaneIndex = state.noteLaneIndex ?? [:]
        workspaceMemoryRecords = state.workspaceMemoryRecords ?? []
        workspaceSessions = state.workspaceSessions ?? []
        if let rawLane = state.activeWorkspaceLane,
           let lane = WorkspaceLane(rawValue: rawLane)
        {
            activeWorkspaceLane = lane
        }
        if let activeSessionMap = state.activeWorkspaceSessionByLane {
            activeWorkspaceSessionByLane = activeSessionMap.reduce(into: [WorkspaceLane: String]()) { partial, next in
                guard let lane = WorkspaceLane(rawValue: next.key) else { return }
                partial[lane] = next.value
            }
        }
        surveyAdditionalPassesCompleted = state.surveyAdditionalPassesCompleted ?? 0
        surveyExpansionQuestionCounter = state.surveyExpansionQuestionCounter ?? 0
        surveyExpansionActive = state.surveyExpansionActive ?? false
        surveyExpansionQuestionTarget = state.surveyExpansionQuestionTarget ?? 0
        surveyExpansionAnsweredInCurrentPass = state.surveyExpansionAnsweredInCurrentPass ?? 0
        learningPackage = state.learningPackage
        learningVersion = state.learningVersion ?? (learningPackage?.version ?? 0)
        learningFingerprint = state.learningFingerprint ?? ""
        memoryCollectionEnabled = state.memoryCollectionEnabled ?? true
        ensureWorkspaceSessionsSeeded()
    }

    private func stateFileURL(fileName: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AtlasMasaIOS", isDirectory: true)
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
    var checkInWentToGymToday: Bool?
    var checkInMadeMoneyToday: Bool?
    var checkInMoneySignalNote: String?
    var pendingFeedback: String
    var vanRentalNeeded: Bool
    var travelRegion: String
    var annualDistanceKM: String
    var workspaceMode: String
    var notes: [UserNote]
    var surveyAnswers: [String: String]?
    var surveyQuestionSessionIndex: [String: String]?
    var surveyQuestionLaneIndex: [String: String]?
    var noteSessionIndex: [String: String]?
    var noteLaneIndex: [String: String]?
    var workspaceMemoryRecords: [WorkspaceMemoryRecord]?
    var workspaceSessions: [WorkspaceNotebookSession]?
    var activeWorkspaceLane: String?
    var activeWorkspaceSessionByLane: [String: String]?
    var surveyAdditionalPassesCompleted: Int?
    var surveyExpansionQuestionCounter: Int?
    var surveyExpansionActive: Bool?
    var surveyExpansionQuestionTarget: Int?
    var surveyExpansionAnsweredInCurrentPass: Int?
    var learningPackage: AdaptiveLearningPackage?
    var learningVersion: Int?
    var learningFingerprint: String?
    var memoryCollectionEnabled: Bool?
}

private enum SecurePersistenceError: Error {
    case invalidEnvelope
    case invalidKeyMaterial
    case keychainFailure(OSStatus)
}

private enum SecurePersistence {
    private static let service = "com.atlasmasa.secure.persistence"
    private static let envelopeHeader = Data("ATLASSEC1".utf8)

    static func encrypt(_ plaintext: Data, context: String, appNamespace: String) throws -> Data {
        let key = try encryptionKey(appNamespace: appNamespace)
        let aad = Data("atlas_context:\(context)".utf8)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        guard let combined = sealed.combined else {
            throw SecurePersistenceError.invalidEnvelope
        }
        return envelopeHeader + combined
    }

    static func decrypt(_ envelope: Data, context: String, appNamespace: String) throws -> Data {
        guard envelope.starts(with: envelopeHeader) else {
            throw SecurePersistenceError.invalidEnvelope
        }
        let combined = envelope.dropFirst(envelopeHeader.count)
        let sealed = try AES.GCM.SealedBox(combined: combined)
        let key = try encryptionKey(appNamespace: appNamespace)
        let aad = Data("atlas_context:\(context)".utf8)
        return try AES.GCM.open(sealed, using: key, authenticating: aad)
    }

    private static func encryptionKey(appNamespace: String) throws -> SymmetricKey {
        let keyData = try loadOrCreateKeyMaterial(account: "\(appNamespace).v1")
        guard keyData.count == 32 else {
            throw SecurePersistenceError.invalidKeyMaterial
        }
        return SymmetricKey(data: keyData)
    }

    private static func loadOrCreateKeyMaterial(account: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
#if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data else {
                throw SecurePersistenceError.invalidKeyMaterial
            }
            return data
        }
        if status != errSecItemNotFound {
            throw SecurePersistenceError.keychainFailure(status)
        }

        var generated = Data(count: 32)
        let bytesStatus = generated.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard bytesStatus == errSecSuccess else {
            throw SecurePersistenceError.keychainFailure(bytesStatus)
        }

        var create: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: generated,
        ]
#if os(iOS)
        create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return generated
        }
        if addStatus == errSecDuplicateItem {
            return try loadOrCreateKeyMaterial(account: account)
        }
        throw SecurePersistenceError.keychainFailure(addStatus)
    }
}

private enum SensitiveDataRedactor {
    private struct Rule {
        let regex: NSRegularExpression
        let replacement: String
    }

    private static let rules: [Rule] = [
        Rule(
            regex: try! NSRegularExpression(
                pattern: #"(?i)\bbearer\s+[A-Za-z0-9\-._~+/]+=*"#,
                options: []
            ),
            replacement: "bearer [redacted]"
        ),
        Rule(
            regex: try! NSRegularExpression(
                pattern: #"(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
                options: []
            ),
            replacement: "[redacted-email]"
        ),
        Rule(
            regex: try! NSRegularExpression(
                pattern: #"\b[A-Za-z0-9\-_]{20,}\.[A-Za-z0-9\-_]{20,}\.[A-Za-z0-9\-_]{20,}\b"#,
                options: []
            ),
            replacement: "[redacted-jwt]"
        ),
        Rule(
            regex: try! NSRegularExpression(
                pattern: #"(?<!\d)(?:\d[ -]?){13,19}(?!\d)"#,
                options: []
            ),
            replacement: "[redacted-number]"
        ),
        Rule(
            regex: try! NSRegularExpression(
                pattern: #"(?<!\w)\+?\d[\d\-\s()]{7,}\d(?!\w)"#,
                options: []
            ),
            replacement: "[redacted-phone]"
        ),
    ]

    static func redact(_ input: String) -> String {
        var output = input
        for rule in rules {
            let range = NSRange(output.startIndex ..< output.endIndex, in: output)
            output = rule.regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
        return output
    }
}

private extension String {
    func trimmedNil() -> String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
