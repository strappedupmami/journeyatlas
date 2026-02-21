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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case whyNow = "why_now"
        case priority
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
    let locale: String

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authorizationCode = "authorization_code"
        case locale
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

struct AuthMeResponse: Codable {
    let user: AuthSessionUser
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

enum PromptQueueStatus: String, Codable, CaseIterable {
    case queued
    case running
    case done
    case failed
}

struct LocalReasoningOutput: Codable, Hashable {
    let model: String
    let summary: String
    let nextAction: String
    let confidence: Double
    let generatedAt: Date
}

struct PromptQueueItem: Codable, Identifiable, Hashable {
    let id: String
    var prompt: String
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

enum AccountTier: String, Codable, CaseIterable, Identifiable {
    case localTrial = "local_trial"
    case cloudPro = "cloud_pro"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localTrial:
            return "Tier 1 · Local Reasoning"
        case .cloudPro:
            return "Tier 2 · Cloud Reasoning"
        }
    }

    var subtitle: String {
        switch self {
        case .localTrial:
            return "Runs locally in Swift apps. No cloud compute required."
        case .cloudPro:
            return "Server reasoning for deeper workloads and scale."
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
    let title: String
    let executionRecommendation: String
    let whyItWorks: String
    let confidence: Double
    let citations: [ResearchCitation]
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
