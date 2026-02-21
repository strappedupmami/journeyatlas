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

struct UserNote: Codable, Identifiable {
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
    var completedAt: Date?
    var errorMessage: String?
    var output: LocalReasoningOutput?
}
