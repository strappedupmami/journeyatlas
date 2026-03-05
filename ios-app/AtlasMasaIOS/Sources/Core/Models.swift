import Foundation

struct HealthCapabilities: Codable {
    let googleOAuth: Bool
    let appleOAuth: Bool
    let passkey: Bool
    let billing: Bool
    let deepPersonalization: Bool

    enum CodingKeys: String, CodingKey {
        case googleOAuth = "google_oauth"
        case appleOAuth = "apple_oauth"
        case passkey
        case billing
        case deepPersonalization = "deep_personalization"
    }
}

struct HealthResponse: Codable {
    let status: String
    let timestampUTC: String
    let capabilities: HealthCapabilities

    enum CodingKeys: String, CodingKey {
        case status
        case timestampUTC = "timestamp_utc"
        case capabilities
    }
}

struct OAuthStartResponse: Codable {
    let authorizeURL: String

    enum CodingKeys: String, CodingKey {
        case authorizeURL = "authorize_url"
    }
}

struct ChatRequestPayload: Encodable {
    let sessionID: String?
    let text: String
    let locale: String?
    let userID: String?
    let preferredFormat: String?
    let responseDepth: String?
    let responseTone: String?
    let includeProactive: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case text
        case locale
        case userID = "user_id"
        case preferredFormat = "preferred_format"
        case responseDepth = "response_depth"
        case responseTone = "response_tone"
        case includeProactive = "include_proactive"
    }
}

struct ConciergeChatResponse: Codable {
    let replyText: String

    enum CodingKeys: String, CodingKey {
        case replyText = "reply_text"
    }
}

struct SurveyChoice: Codable, Identifiable, Hashable {
    var id: String { value }
    let value: String
    let label: String
}

struct SurveyQuestion: Codable {
    let id: String
    let title: String
    let description: String?
    let kind: String
    let required: Bool
    let choices: [SurveyChoice]
    let placeholder: String?
}

struct SurveyProgress: Codable {
    let answered: Int
    let total: Int
    let percent: Int
}

struct SurveyNextResponse: Codable {
    let question: SurveyQuestion?
    let progress: SurveyProgress
    let profileHints: [String]

    enum CodingKeys: String, CodingKey {
        case question
        case progress
        case profileHints = "profile_hints"
    }
}

struct SurveyAnswerPayload: Encodable {
    let userID: String?
    let questionID: String
    let answer: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case questionID = "question_id"
        case answer
    }
}

struct FeedItem: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let whyNow: String
    let priority: String
    let checklistState: FeedItemChecklistState?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case whyNow = "why_now"
        case priority
        case checklistState = "checklist_state"
    }
}

struct FeedItemChecklistState: Codable {
    let completed: Bool
    let collapsed: Bool
    let completionCount: Int
    let updatedAt: String
    let latestResponse: FeedItemTaskResponse?

    enum CodingKeys: String, CodingKey {
        case completed
        case collapsed
        case completionCount = "completion_count"
        case updatedAt = "updated_at"
        case latestResponse = "latest_response"
    }
}

struct FeedItemTaskResponse: Codable {
    let responseID: String
    let taskID: String
    let completedParts: String?
    let incompleteParts: String?
    let note: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case responseID = "response_id"
        case taskID = "task_id"
        case completedParts = "completed_parts"
        case incompleteParts = "incomplete_parts"
        case note
        case createdAt = "created_at"
    }
}

struct ProactiveFeedResponse: Codable {
    let generatedAt: String
    let items: [FeedItem]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case items
    }
}

struct NotesListResponse: Codable {
    let notes: [UserNote]
}

struct UserNote: Codable, Identifiable, Hashable {
    let noteID: String
    let title: String
    let content: String

    var id: String { noteID }

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case title
        case content
    }
}

struct NoteUpsertPayload: Encodable {
    let userID: String?
    let title: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case title
        case content
    }
}

struct NativeAppleExchangePayload: Encodable {
    let identityToken: String
    let authorizationCode: String?
    let email: String?
    let displayName: String?
    let locale: String

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case email
        case displayName = "display_name"
        case locale
    }
}

struct PasskeyRegistrationStartPayload: Encodable {
    let email: String?
    let displayName: String?
    let locale: String?

    enum CodingKeys: String, CodingKey {
        case email
        case displayName = "display_name"
        case locale
    }
}

struct PasskeyLoginStartPayload: Encodable {
    let email: String?
}

struct PasskeyRegistrationCredentialResponsePayload: Encodable {
    let clientDataJSON: String
    let attestationObject: String
    let transports: [String]

    enum CodingKeys: String, CodingKey {
        case clientDataJSON
        case attestationObject
        case transports
    }
}

struct PasskeyRegistrationCredentialPayload: Encodable {
    let id: String
    let rawId: String
    let type: String
    let response: PasskeyRegistrationCredentialResponsePayload
    let clientExtensionResults: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case rawId
        case type
        case response
        case clientExtensionResults
    }
}

struct PasskeyRegistrationFinishPayload: Encodable {
    let requestID: String
    let credential: PasskeyRegistrationCredentialPayload

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case credential
    }
}

struct PasskeyAuthenticationCredentialResponsePayload: Encodable {
    let clientDataJSON: String
    let authenticatorData: String
    let signature: String
    let userHandle: String?

    enum CodingKeys: String, CodingKey {
        case clientDataJSON
        case authenticatorData
        case signature
        case userHandle
    }
}

struct PasskeyAuthenticationCredentialPayload: Encodable {
    let id: String
    let rawId: String
    let type: String
    let response: PasskeyAuthenticationCredentialResponsePayload
    let clientExtensionResults: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case rawId
        case type
        case response
        case clientExtensionResults
    }
}

struct PasskeyLoginFinishPayload: Encodable {
    let requestID: String
    let credential: PasskeyAuthenticationCredentialPayload

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case credential
    }
}

struct AuthSessionUser: Codable {
    let userID: String
    let provider: String
    let email: String
    let name: String
    let locale: String
    let memoryOptIn: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case provider
        case email
        case name
        case locale
        case memoryOptIn = "memory_opt_in"
    }
}

struct SubscriptionAccess: Codable {
    let bypass: Bool?
    let active: Bool?
    let tier: String?
    let cloudComputeEnabled: Bool?
    let cloudStorageEnabled: Bool?
    let pricingModel: String?
    let freeTrialDaysTotal: Int?
    let freeTrialDaysRemaining: Int?
    let freeTrialActive: Bool?
    let freeTrialEndsAt: String?
    let usageBillingActive: Bool?

    enum CodingKeys: String, CodingKey {
        case bypass
        case active
        case tier
        case cloudComputeEnabled = "cloud_compute_enabled"
        case cloudStorageEnabled = "cloud_storage_enabled"
        case pricingModel = "pricing_model"
        case freeTrialDaysTotal = "free_trial_days_total"
        case freeTrialDaysRemaining = "free_trial_days_remaining"
        case freeTrialActive = "free_trial_active"
        case freeTrialEndsAt = "free_trial_ends_at"
        case usageBillingActive = "usage_billing_active"
    }
}

struct AuthMeResponse: Codable {
    let user: AuthSessionUser
    let subscription: SubscriptionAccess?
}

struct AuthLoginResponse: Codable {
    let token: String
    let user: AuthSessionUser
    let sessionExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case token
        case user
        case sessionExpiresAt = "session_expires_at"
    }
}

struct BillingCheckoutSessionResponse: Codable {
    let checkoutURL: String
    let checkoutSessionID: String
    let bypass: Bool?

    enum CodingKeys: String, CodingKey {
        case checkoutURL = "checkout_url"
        case checkoutSessionID = "checkout_session_id"
        case bypass
    }
}

struct ExecutionCheckinPayload: Encodable {
    let userID: String?
    let dailyFocus: String
    let midTermFocus: String?
    let longTermFocus: String?
    let blocker: String?
    let nextActionNow: String?
    let energyLevel: Int?
    let mood: String?
    let gymToday: Bool?
    let moneyToday: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case dailyFocus = "daily_focus"
        case midTermFocus = "mid_term_focus"
        case longTermFocus = "long_term_focus"
        case blocker
        case nextActionNow = "next_action_now"
        case energyLevel = "energy_level"
        case mood
        case gymToday = "gym_today"
        case moneyToday = "money_today"
    }
}

struct ExecutionCheckinRecord: Codable {
    let checkinID: String
    let dailyFocus: String
    let midTermFocus: String?
    let longTermFocus: String?
    let blocker: String?
    let nextActionNow: String?
    let energyLevel: Int?
    let mood: String?
    let gymToday: Bool?
    let moneyToday: Bool?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case checkinID = "checkin_id"
        case dailyFocus = "daily_focus"
        case midTermFocus = "mid_term_focus"
        case longTermFocus = "long_term_focus"
        case blocker
        case nextActionNow = "next_action_now"
        case energyLevel = "energy_level"
        case mood
        case gymToday = "gym_today"
        case moneyToday = "money_today"
        case createdAt = "created_at"
    }
}

struct ExecutionCheckinResponse: Codable {
    let ok: Bool
    let checkin: ExecutionCheckinRecord
    let feed: ProactiveFeedResponse
}

struct ExecutionTaskTogglePayload: Encodable {
    let userID: String?
    let taskID: String
    let completed: Bool
    let collapsed: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case taskID = "task_id"
        case completed
        case collapsed
    }
}

struct ExecutionTaskRespondPayload: Encodable {
    let userID: String?
    let taskID: String
    let completedParts: String?
    let incompleteParts: String?
    let note: String?
    let completed: Bool?
    let collapsed: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case taskID = "task_id"
        case completedParts = "completed_parts"
        case incompleteParts = "incomplete_parts"
        case note
        case completed
        case collapsed
    }
}

struct ExecutionTaskMutationResponse: Codable {
    let ok: Bool
    let feed: ProactiveFeedResponse
}

enum PromptQueueStatus: String, Codable, CaseIterable {
    case queued
    case running
    case done
    case failed
}

enum PromptOutputType: String, Codable, CaseIterable, Identifiable {
    case standard
    case podcast
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .podcast:
            return "Podcast"
        case .quiz:
            return "Quiz"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            return "Summary + next action"
        case .podcast:
            return "Studio-quality audio briefing"
        case .quiz:
            return "Rehearsal quiz format"
        }
    }
}

enum QuizDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy:
            return "Easy"
        case .medium:
            return "Medium"
        case .hard:
            return "Hard"
        }
    }

    var subtitle: String {
        switch self {
        case .easy:
            return "Recall and core understanding checks"
        case .medium:
            return "Mixed recall and application drills"
        case .hard:
            return "Scenario-based, high-pressure rehearsal"
        }
    }
}

enum ResponseFeedbackSentiment: String, Codable, CaseIterable, Identifiable {
    case thumbsUp = "thumbs_up"
    case thumbsDown = "thumbs_down"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thumbsUp:
            return "Helpful"
        case .thumbsDown:
            return "Needs work"
        }
    }
}

enum ResponseFeedbackContentScope: String, Codable, CaseIterable, Identifiable {
    case fullResponse = "full_response"
    case highlightedOnly = "highlighted_only"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullResponse:
            return "Full response"
        case .highlightedOnly:
            return "Highlighted section"
        }
    }
}

struct LocalReasoningOutput: Codable, Hashable {
    let model: String
    let summary: String
    let nextAction: String
    let confidence: Double
    let generatedAt: Date
    var outputType: PromptOutputType? = nil
    var quizDifficulty: QuizDifficulty? = nil
    var content: String? = nil
    var podcastAudio: PodcastAudioArtifact? = nil
}

struct PodcastAudioArtifact: Codable, Hashable {
    let filePath: String
    let mimeType: String
    let voiceName: String
    let bytes: Int
    let estimatedDurationSeconds: Double
}

struct PromptQueueItem: Codable, Identifiable, Hashable {
    let id: String
    var prompt: String
    var outputType: PromptOutputType? = nil
    var quizDifficulty: QuizDifficulty? = nil
    var workspaceLane: WorkspaceLane? = nil
    var conciergeSessionID: String? = nil
    var workspaceSessionID: String? = nil
    var retryCount: Int? = nil
    var status: PromptQueueStatus
    var createdAt: Date
    var startedAt: Date? = nil
    var completedAt: Date?
    var lastCheckpointAt: Date? = nil
    var progress: Double? = nil
    var checkpointNote: String? = nil
    var errorMessage: String?
    var output: LocalReasoningOutput?
}

struct ConciergeChatSession: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let createdAtUTC: Date
    let updatedAtUTC: Date
    var summary: String
    var isPinned: Bool
}

enum CodingMessageRole: String, Codable, CaseIterable, Identifiable {
    case user
    case assistant
    case system
    case command

    var id: String { rawValue }
}

enum CodingMemoryKind: String, Codable, CaseIterable, Identifiable {
    case prompt
    case response
    case command
    case fileSnapshot
    case system

    var id: String { rawValue }
}

struct CodingWorkspaceMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: CodingMessageRole
    let content: String
    let createdAtUTC: Date
    let relatedFilePath: String?
}

struct CodingMemoryRecord: Codable, Identifiable, Hashable {
    let id: String
    let kind: CodingMemoryKind
    let summary: String
    let detail: String
    let relatedFilePath: String?
    let createdAtUTC: Date
}

enum AccountTier: String, Codable, CaseIterable, Identifiable {
    case localTrial = "local_trial"
    case cloudPro = "cloud_pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localTrial:
            return "Locked"
        case .cloudPro:
            return "Cloud Active"
        }
    }

    var subtitle: String {
        switch self {
        case .localTrial:
            return "Sign in and add a payment method to unlock cloud AI."
        case .cloudPro:
            return "Cloud AI unlocked for this account."
        }
    }
}

enum AuthProvider: String, Codable, CaseIterable, Identifiable {
    case apple
    case google
    case passkey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        case .passkey:
            return "Passwordless"
        }
    }
}

struct ExecutionAction: Codable, Identifiable, Hashable {
    let id: String
    var horizon: String
    var title: String
    var details: String
    var priority: Int
    var source: String
    var completed: Bool
}

struct MemoryInsight: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
}

enum AtlasOfferCategory: String, Codable, CaseIterable, Identifiable {
    case localIntelligence = "local_intelligence"
    case travelMobility = "travel_mobility"
    case wealthOperations = "wealth_operations"
    case resilienceSafety = "resilience_safety"
    case productivitySystems = "productivity_systems"

    var id: String { rawValue }
}

enum AtlasOfferType: String, Codable, CaseIterable, Identifiable {
    case feature
    case service
    case membership
    case rental

    var id: String { rawValue }
}

struct TailoredOffer: Codable, Identifiable, Hashable {
    let id: String
    let category: AtlasOfferCategory
    let type: AtlasOfferType
    let title: String
    let summary: String
    let rationale: String
    let priority: Int
    let callToAction: String
}

struct AtlasResearchPaper: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int
    let domain: String
    let actionableInsight: String
    let actionHint: String
    let sourceURL: String
    let keywords: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case domain
        case actionableInsight = "actionable_insight"
        case actionHint = "action_hint"
        case sourceURL = "source_url"
        case keywords
    }
}

struct ResearchCitation: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int
    let sourceURL: String
}

struct ResearchExecutionStream: Codable, Identifiable, Hashable {
    let id: String
    let domain: String
    let title: String
    let executionRecommendation: String
    let whyItWorks: String
    let confidence: Double
    let citations: [ResearchCitation]
}

enum WorkspaceLane: String, Codable, CaseIterable, Identifiable {
    case emergencyCommand = "emergency_command"
    case wealthOperations = "wealth_operations"
    case mobilityOps = "mobility_ops"
    case deepWork = "deep_work"
    case innovation = "innovation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emergencyCommand:
            return "Emergency Command Workspace"
        case .wealthOperations:
            return "Wealth Operations Workspace"
        case .mobilityOps:
            return "Mobility Operations Workspace"
        case .deepWork:
            return "Cognitive Performance Workspace"
        case .innovation:
            return "Innovation Systems Workspace"
        }
    }
}

enum WorkspaceMemorySource: String, Codable, CaseIterable, Identifiable {
    case survey
    case note
    case checkin
    case execution
    case lesson
    case system

    var id: String { rawValue }
}

struct WorkspaceNotebookSession: Codable, Identifiable, Hashable {
    let id: String
    let lane: WorkspaceLane
    var title: String
    let createdAtUTC: Date
    let updatedAtUTC: Date
    var summary: String
    var isPinned: Bool
}

struct WorkspaceMemoryRecord: Codable, Identifiable, Hashable {
    let id: String
    let lane: WorkspaceLane?
    let sessionID: String?
    let source: WorkspaceMemorySource
    let key: String
    let value: String
    let weight: Double
    let tags: [String]
    let createdAtUTC: Date
    let updatedAtUTC: Date
}

struct WorkspacePlan: Codable, Identifiable, Hashable {
    let id: String
    let lane: WorkspaceLane
    let title: String
    let objective: String
    let nextActionNow: String
    let protocolChecklist: [String]
    let evidenceSummary: String
    let confidence: Double
    let citations: [ResearchCitation]
    let sharedMemorySignals: [String]
    let crossWorkspaceSignals: [String]
    let memoryRecordCount: Int
}

struct AdaptiveQuizQuestion: Codable, Identifiable, Hashable {
    let id: String
    let prompt: String
    let options: [String]
    let preferredAnswerIndex: Int
    let explanation: String
}

struct AdaptivePodcastSegment: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let talkingPoints: [String]
}

struct AdaptiveLearningPackage: Codable, Hashable {
    let version: Int
    let generatedAtUTC: String
    let rationale: String
    let quiz: [AdaptiveQuizQuestion]
    let podcastTitle: String
    let podcastSummary: String
    let podcastSegments: [AdaptivePodcastSegment]
}
