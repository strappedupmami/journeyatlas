import AuthenticationServices
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Masa mobile command center..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var pendingPrompt = ""
    @Published var promptQueue: [PromptQueueItem] = []

    let api: APIClient
    private let localReasoning = LocalReasoningEngine()
    private var queueWorkerTask: Task<Void, Never>?
    private let queueStorageKey = "atlas_macos_prompt_queue_v1"

    init(api: APIClient = APIClient()) {
        self.api = api
        loadPromptQueueFromDisk()
    }

    func bootstrap() async {
        await refreshHealth()
        await loadSurvey()
        await refreshFeed()
        startPromptQueueWorker()
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API health is online.")
        } catch {
            appendOutput("Health check failed: \(error.localizedDescription)")
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
        } catch {
            appendOutput("Apple web sign-in start failed: \(error.localizedDescription)")
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
                appendOutput("Apple token missing from credential.")
                return
            }
            let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

            do {
                try await api.exchangeNativeApple(identityToken: identityToken, authorizationCode: authCode, locale: Locale.current.identifier)
                appendOutput("Native Apple credential captured and sent to backend.")
            } catch {
                appendOutput("Native Apple exchange pending backend endpoint: \(error.localizedDescription)")
            }

        case let .failure(error):
            appendOutput("Apple sign-in cancelled/failed: \(error.localizedDescription)")
        }
    }

    func loadSurvey() async {
        do {
            survey = try await api.surveyNext()
        } catch {
            appendOutput("Survey load failed: \(error.localizedDescription)")
            survey = SurveyNextResponse(
                question: SurveyQuestion(
                    id: "primary_goal",
                    title: "What is your most important mission this quarter?",
                    description: "We use this to prioritize proactive outputs.",
                    kind: "choice",
                    required: true,
                    choices: [
                        SurveyChoice(value: "health", label: "Health and resilience"),
                        SurveyChoice(value: "wealth", label: "Wealth and execution"),
                        SurveyChoice(value: "balance", label: "Balanced growth")
                    ],
                    placeholder: nil
                ),
                progress: SurveyProgress(answered: 0, total: 12, percent: 0),
                profileHints: ["Fallback local mode"]
            )
        }
    }

    func answerSurvey(_ choice: SurveyChoice) async {
        guard let questionID = survey?.question?.id else { return }
        do {
            survey = try await api.submitSurveyAnswer(questionID: questionID, answer: choice.value)
        } catch {
            appendOutput("Survey submit failed: \(error.localizedDescription)")
        }
    }

    func refreshFeed() async {
        do {
            let payload = try await api.feedProactive()
            feedItems = payload.items
        } catch {
            appendOutput("Proactive feed fetch failed: \(error.localizedDescription)")
            feedItems = []
        }
    }

    func loadNotes() async {
        do {
            notes = try await api.notesList().notes
        } catch {
            appendOutput("Notes load requires authenticated API session: \(error.localizedDescription)")
            notes = []
        }
    }

    func saveNote() async {
        guard !pendingNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pendingNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendOutput("Note title and content are required.")
            return
        }

        do {
            try await api.upsertNote(title: pendingNoteTitle, content: pendingNoteContent)
            appendOutput("Note saved to API.")
            pendingNoteTitle = ""
            pendingNoteContent = ""
            await loadNotes()
        } catch {
            appendOutput("Note save failed: \(error.localizedDescription)")
        }
    }

    func appendOutput(_ line: String) {
        systemOutput.insert(line, at: 0)
        if systemOutput.count > 20 {
            systemOutput = Array(systemOutput.prefix(20))
        }
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
            appendOutput("Local reasoning complete for queued prompt: \(output.nextAction)")
        }

        queueWorkerTask = nil
    }

    private func persistPromptQueueToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(promptQueue) else { return }
        UserDefaults.standard.set(data, forKey: queueStorageKey)
    }

    private func loadPromptQueueFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: queueStorageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let restored = try? decoder.decode([PromptQueueItem].self, from: data) else { return }
        promptQueue = restored
    }
}
