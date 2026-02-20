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

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func bootstrap() async {
        await refreshHealth()
        await loadSurvey()
        await refreshFeed()
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
}
