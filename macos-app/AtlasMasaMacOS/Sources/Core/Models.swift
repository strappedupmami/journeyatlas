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
    let codeAgentRoute: String?
    let preferredCloudModel: String?
    let cloudFallbackModel: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case text
        case locale
        case userID = "user_id"
        case preferredFormat = "preferred_format"
        case responseDepth = "response_depth"
        case responseTone = "response_tone"
        case includeProactive = "include_proactive"
        case codeAgentRoute = "code_agent_route"
        case preferredCloudModel = "preferred_cloud_model"
        case cloudFallbackModel = "cloud_fallback_model"
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

struct NatureSignalTile: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let metric: String
    let trend: String
    let severity: String
    let sourceLabel: String
    let sourceURL: String
    let updatedAtUTC: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case metric
        case trend
        case severity
        case sourceLabel = "source_label"
        case sourceURL = "source_url"
        case updatedAtUTC = "updated_at_utc"
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

struct OperatorStateSnapshot: Codable, Identifiable, Hashable {
    enum ExecutionMode: String, Codable, CaseIterable {
        case shortIdleWindow = "short_idle_window"
        case deepWorkWindow = "deep_work_window"
        case lowEnergyMode = "low_energy_mode"
        case highFrictionStall = "high_friction_stall"
        case continuityRiskMode = "continuity_risk_mode"

        var title: String {
            switch self {
            case .shortIdleWindow: return "Short Idle Window"
            case .deepWorkWindow: return "Deep-Work Window"
            case .lowEnergyMode: return "Low-Energy Mode"
            case .highFrictionStall: return "High-Friction Stall"
            case .continuityRiskMode: return "Continuity-Risk Mode"
            }
        }
    }

    let id: String
    let mode: ExecutionMode
    let summary: String
    let nextAction: String
    let rationale: String
    let continuityRiskActive: Bool
    let energyLevel: Int
    let mood: String
    let blockerSummary: String?
    let generatedAt: String
}

struct ChecklistPlan: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let createdFrom: String
    var steps: [ChecklistStep]
    let generatedAt: String

    var completionRatio: Double {
        guard !steps.isEmpty else { return 0 }
        let completed = steps.filter(\.isCompleted).count
        return Double(completed) / Double(steps.count)
    }
}

struct ChecklistStep: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let rationale: String
    let instructions: String
    let externalLinks: [String]
    let fileReferences: [String]
    var isCompleted: Bool
    var notes: String?
}

struct ActivitySuggestion: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let durationLabel: String
    let reason: String
    let generatedAt: String
}

struct ItineraryStep: Codable, Identifiable, Hashable {
    let id: String
    let timeLabel: String
    let title: String
    let summary: String
}

struct ItineraryPlan: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let kind: String
    let steps: [ItineraryStep]
    let generatedAt: String
}

struct SavedTravelLocation: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var googleMapsQuery: String
    var notes: String
    var createdAt: String
}

struct TravelItineraryDraft: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var locationIDs: [String]
    var updatedAt: String
}

struct SupportRecommendation: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let bodyDoublingPrompt: String?
    let generatedAt: String
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
    let createdAt: Date

    var id: String { noteID }

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case title
        case content
        case createdAt = "created_at"
    }

    init(noteID: String, title: String, content: String, createdAt: Date = Date()) {
        self.noteID = noteID
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteID = try container.decode(String.self, forKey: .noteID)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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

struct RAndDJobCreatePayload: Encodable {
    let productType: String?
    let prompt: String
    let locale: String?
    let clientResearchSummary: String?
    let clientLocalPlanningNote: String?

    enum CodingKeys: String, CodingKey {
        case productType = "product_type"
        case prompt
        case locale
        case clientResearchSummary = "client_research_summary"
        case clientLocalPlanningNote = "client_local_planning_note"
    }
}

struct RAndDPlanRevisePayload: Encodable {
    let revisionPrompt: String

    enum CodingKeys: String, CodingKey {
        case revisionPrompt = "revision_prompt"
    }
}

struct RAndDStageApprovePayload: Encodable {
    let note: String?
}

struct RAndDPausePayload: Encodable {
    let pauseAfterCurrentStage: Bool

    enum CodingKeys: String, CodingKey {
        case pauseAfterCurrentStage = "pause_after_current_stage"
    }
}

struct RAndDChangeRequestPayload: Encodable {
    let scope: String?
    let targetPartID: String?
    let request: String

    enum CodingKeys: String, CodingKey {
        case scope
        case targetPartID = "target_part_id"
        case request
    }
}

struct RAndDReviewRecordPayload: Encodable {
    let title: String?
    let status: String?
    let note: String?
    let requirementIDs: [String]?
    let decisionIDs: [String]?
    let evidenceIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case status
        case note
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case evidenceIDs = "evidence_ids"
    }
}

struct RAndDReportGeneratePayload: Encodable {
    let title: String?
    let reportType: String?

    enum CodingKeys: String, CodingKey {
        case title
        case reportType = "report_type"
    }
}

struct RAndDDocumentGeneratePayload: Encodable {
    let documentType: String
    let audienceMode: String?
    let title: String?
    let platformName: String?
    let revisionLabel: String?
    let purpose: String?
    let targetAudience: String?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case audienceMode = "audience_mode"
        case title
        case platformName = "platform_name"
        case revisionLabel = "revision_label"
        case purpose
        case targetAudience = "target_audience"
        case author
    }
}

struct RAndDDocumentBundleGeneratePayload: Encodable {
    let audienceMode: String?
    let titlePrefix: String?
    let platformName: String?
    let revisionLabel: String?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case audienceMode = "audience_mode"
        case titlePrefix = "title_prefix"
        case platformName = "platform_name"
        case revisionLabel = "revision_label"
        case author
    }
}

struct RAndDApprovalRecordPayload: Encodable {
    let reviewerName: String
    let reviewerRole: String
    let reviewerOrg: String?
    let authorityKind: String?
    let approvalState: String?
    let scopeType: String?
    let scopeID: String?
    let comment: String?
    let conditions: [String]?
    let createBaselineIfApproved: Bool?
    let baselineTitle: String?

    enum CodingKeys: String, CodingKey {
        case reviewerName = "reviewer_name"
        case reviewerRole = "reviewer_role"
        case reviewerOrg = "reviewer_org"
        case authorityKind = "authority_kind"
        case approvalState = "approval_state"
        case scopeType = "scope_type"
        case scopeID = "scope_id"
        case comment
        case conditions
        case createBaselineIfApproved = "create_baseline_if_approved"
        case baselineTitle = "baseline_title"
    }
}

enum RAndDStageKind: String, Codable, Hashable {
    case planReview = "plan_review"
    case problemFraming = "problem_framing"
    case requirementsExtraction = "requirements_extraction"
    case researchSynthesis = "research_synthesis"
    case systemArchitecture = "system_architecture"
    case partDecomposition = "part_decomposition"
    case partGeneration = "part_generation"
    case partValidation = "part_validation"
    case packageAssembly = "package_assembly"
    case reviewHandoff = "review_handoff"
    case completed = "completed"
}

struct RAndDCitation: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let sourceType: String
    let detail: String

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case sourceType = "source_type"
        case detail
    }
}

struct RAndDPlanStage: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let objective: String
    let estimatedMinutes: Int
    let approvalRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case objective
        case estimatedMinutes = "estimated_minutes"
        case approvalRequired = "approval_required"
    }
}

struct RAndDPlan: Codable, Hashable {
    let version: Int
    let generatedAt: String
    let goals: [String]
    let constraints: [String]
    let risks: [String]
    let assumptions: [String]
    let requiredResearchDomains: [String]
    let proposedParts: [String]
    let executionStages: [RAndDPlanStage]
    let userExplanation: String
    let simpleSummary: String
    let citations: [RAndDCitation]
    let executable: Bool
    let blockingIssues: [String]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case goals
        case constraints
        case risks
        case assumptions
        case requiredResearchDomains = "required_research_domains"
        case proposedParts = "proposed_parts"
        case executionStages = "execution_stages"
        case userExplanation = "user_explanation"
        case simpleSummary = "simple_summary"
        case citations
        case executable
        case blockingIssues = "blocking_issues"
    }
}

struct RAndDEta: Codable, Hashable {
    let estimatedTotalMinutes: Int
    let estimatedRemainingMinutes: Int
    let currentStageEstimatedMinutes: Int
    let confidenceLabel: String
    let currentBottleneck: String
    let slippageReason: String

    enum CodingKeys: String, CodingKey {
        case estimatedTotalMinutes = "estimated_total_minutes"
        case estimatedRemainingMinutes = "estimated_remaining_minutes"
        case currentStageEstimatedMinutes = "current_stage_estimated_minutes"
        case confidenceLabel = "confidence_label"
        case currentBottleneck = "current_bottleneck"
        case slippageReason = "slippage_reason"
    }
}

struct RAndDPartCounts: Codable, Hashable {
    let queued: Int
    let running: Int
    let blocked: Int
    let completed: Int
}

struct RAndDRoutingSummary: Codable, Hashable {
    let localOnlyTasks: [String]
    let geminiEscalatedTasks: [String]
    let gptEscalatedTasks: [String]
    let executorTasks: [String]

    enum CodingKeys: String, CodingKey {
        case localOnlyTasks = "local_only_tasks"
        case geminiEscalatedTasks = "gemini_escalated_tasks"
        case gptEscalatedTasks = "gpt_escalated_tasks"
        case executorTasks = "executor_tasks"
    }
}

struct RAndDRequirement: Codable, Identifiable, Hashable {
    let requirementID: String
    let title: String
    let description: String
    let requirementKind: String
    let status: String
    let sourcePlanVersion: Int
    let linkedComponentIDs: [String]
    let linkedDecisionIDs: [String]
    let linkedEvidenceIDs: [String]
    let linkedReportIDs: [String]
    let linkedApprovalIDs: [String]
    let verificationNotes: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { requirementID }

    enum CodingKeys: String, CodingKey {
        case requirementID = "requirement_id"
        case title
        case description
        case requirementKind = "requirement_kind"
        case status
        case sourcePlanVersion = "source_plan_version"
        case linkedComponentIDs = "linked_component_ids"
        case linkedDecisionIDs = "linked_decision_ids"
        case linkedEvidenceIDs = "linked_evidence_ids"
        case linkedReportIDs = "linked_report_ids"
        case linkedApprovalIDs = "linked_approval_ids"
        case verificationNotes = "verification_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDDesignDecision: Codable, Identifiable, Hashable {
    let decisionID: String
    let title: String
    let context: String
    let decision: String
    let rationale: String
    let status: String
    let sourcePlanVersion: Int
    let supersedesDecisionID: String?
    let requirementIDs: [String]
    let componentIDs: [String]
    let evidenceIDs: [String]
    let affectedArtifactIDs: [String]
    let reviewIDs: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { decisionID }

    enum CodingKeys: String, CodingKey {
        case decisionID = "decision_id"
        case title
        case context
        case decision
        case rationale
        case status
        case sourcePlanVersion = "source_plan_version"
        case supersedesDecisionID = "supersedes_decision_id"
        case requirementIDs = "requirement_ids"
        case componentIDs = "component_ids"
        case evidenceIDs = "evidence_ids"
        case affectedArtifactIDs = "affected_artifact_ids"
        case reviewIDs = "review_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDDesignReview: Codable, Identifiable, Hashable {
    let reviewID: String
    let title: String
    let status: String
    let note: String
    let sourcePlanVersion: Int
    let requirementIDs: [String]
    let decisionIDs: [String]
    let evidenceIDs: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { reviewID }

    enum CodingKeys: String, CodingKey {
        case reviewID = "review_id"
        case title
        case status
        case note
        case sourcePlanVersion = "source_plan_version"
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case evidenceIDs = "evidence_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDEvidenceArtifact: Codable, Identifiable, Hashable {
    let evidenceID: String
    let artifactID: String?
    let runID: String?
    let title: String
    let evidenceKind: String
    let sourceStage: String
    let status: String
    let requirementIDs: [String]
    let decisionIDs: [String]
    let componentIDs: [String]
    let artifactIDs: [String]
    let summary: String
    let createdAt: String
    let updatedAt: String

    var id: String { evidenceID }

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case artifactID = "artifact_id"
        case runID = "run_id"
        case title
        case evidenceKind = "evidence_kind"
        case sourceStage = "source_stage"
        case status
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case componentIDs = "component_ids"
        case artifactIDs = "artifact_ids"
        case summary
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDSimulationRun: Codable, Identifiable, Hashable {
    let runID: String
    let title: String
    let runType: String
    let status: String
    let requirementIDs: [String]
    let decisionIDs: [String]
    let componentIDs: [String]
    let inputArtifactIDs: [String]
    let outputArtifactIDs: [String]
    let summary: String
    let executedAt: String

    var id: String { runID }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case title
        case runType = "run_type"
        case status
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case componentIDs = "component_ids"
        case inputArtifactIDs = "input_artifact_ids"
        case outputArtifactIDs = "output_artifact_ids"
        case summary
        case executedAt = "executed_at"
    }
}

struct RAndDComplianceReport: Codable, Identifiable, Hashable {
    let reportID: String
    let title: String
    let reportType: String
    let status: String
    let version: Int
    let markdown: String
    let provenance: [String]
    let requirementIDs: [String]
    let decisionIDs: [String]
    let evidenceIDs: [String]
    let runIDs: [String]
    let approvalIDs: [String]
    let openIssues: [String]
    let createdAt: String
    let updatedAt: String

    var id: String { reportID }

    enum CodingKeys: String, CodingKey {
        case reportID = "report_id"
        case title
        case reportType = "report_type"
        case status
        case version
        case markdown
        case provenance
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case evidenceIDs = "evidence_ids"
        case runIDs = "run_ids"
        case approvalIDs = "approval_ids"
        case openIssues = "open_issues"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDApprovalRecord: Codable, Identifiable, Hashable {
    let approvalID: String
    let reviewerName: String
    let reviewerRole: String
    let reviewerOrg: String?
    let authorityKind: String
    let approvalState: String
    let scopeType: String
    let scopeID: String
    let conditions: [String]
    let comment: String
    let baselineID: String?
    let legallyBinding: Bool
    let createdAt: String

    var id: String { approvalID }

    enum CodingKeys: String, CodingKey {
        case approvalID = "approval_id"
        case reviewerName = "reviewer_name"
        case reviewerRole = "reviewer_role"
        case reviewerOrg = "reviewer_org"
        case authorityKind = "authority_kind"
        case approvalState = "approval_state"
        case scopeType = "scope_type"
        case scopeID = "scope_id"
        case conditions
        case comment
        case baselineID = "baseline_id"
        case legallyBinding = "legally_binding"
        case createdAt = "created_at"
    }
}

struct RAndDAuditEvent: Codable, Identifiable, Hashable {
    let eventID: String
    let eventType: String
    let actor: String
    let actorRole: String
    let detail: String
    let relatedIDs: [String]
    let createdAt: String

    var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case eventType = "event_type"
        case actor
        case actorRole = "actor_role"
        case detail
        case relatedIDs = "related_ids"
        case createdAt = "created_at"
    }
}

struct RAndDApprovedBaseline: Codable, Identifiable, Hashable {
    let baselineID: String
    let title: String
    let status: String
    let artifactIDs: [String]
    let requirementIDs: [String]
    let decisionIDs: [String]
    let reportIDs: [String]
    let approvalIDs: [String]
    let snapshotHash: String
    let createdAt: String

    var id: String { baselineID }

    enum CodingKeys: String, CodingKey {
        case baselineID = "baseline_id"
        case title
        case status
        case artifactIDs = "artifact_ids"
        case requirementIDs = "requirement_ids"
        case decisionIDs = "decision_ids"
        case reportIDs = "report_ids"
        case approvalIDs = "approval_ids"
        case snapshotHash = "snapshot_hash"
        case createdAt = "created_at"
    }
}

struct RAndDGovernanceSummary: Codable, Hashable {
    let requirementCount: Int
    let decisionCount: Int
    let evidenceCount: Int
    let reportCount: Int
    let approvalCount: Int
    let unresolvedItemCount: Int
    let readinessStatus: String

    enum CodingKeys: String, CodingKey {
        case requirementCount = "requirement_count"
        case decisionCount = "decision_count"
        case evidenceCount = "evidence_count"
        case reportCount = "report_count"
        case approvalCount = "approval_count"
        case unresolvedItemCount = "unresolved_item_count"
        case readinessStatus = "readiness_status"
    }
}

struct RAndDTraceabilityRow: Codable, Identifiable, Hashable {
    let requirementID: String
    let title: String
    let componentIDs: [String]
    let decisionIDs: [String]
    let evidenceIDs: [String]
    let reportIDs: [String]
    let approvalIDs: [String]
    let unresolvedItems: [String]

    var id: String { requirementID }

    enum CodingKeys: String, CodingKey {
        case requirementID = "requirement_id"
        case title
        case componentIDs = "component_ids"
        case decisionIDs = "decision_ids"
        case evidenceIDs = "evidence_ids"
        case reportIDs = "report_ids"
        case approvalIDs = "approval_ids"
        case unresolvedItems = "unresolved_items"
    }
}

struct RAndDArtifact: Codable, Identifiable, Hashable {
    let artifactID: String
    let partID: String?
    let artifactType: String
    let title: String
    let format: String
    let content: String
    let createdAt: String

    var id: String { artifactID }

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case partID = "part_id"
        case artifactType = "artifact_type"
        case title
        case format
        case content
        case createdAt = "created_at"
    }
}

struct RAndDDoctrineProfile: Codable, Hashable {
    let profileID: String
    let title: String
    let principles: [String]
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case title
        case principles
        case updatedAt = "updated_at"
    }
}

struct RAndDDoctrineCheck: Codable, Identifiable, Hashable {
    let checkID: String
    let doctrineArea: String
    let severity: String
    let passed: Bool
    let explanation: String
    let suggestedFix: String
    let linkedModuleIDs: [String]
    let linkedArtifactIDs: [String]
    let linkedDecisionIDs: [String]
    let gating: Bool
    let updatedAt: String

    var id: String { checkID }
    var blocksRelease: Bool { severity == "major" && !passed && gating }

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case doctrineArea = "doctrine_area"
        case severity
        case passed
        case explanation
        case suggestedFix = "suggested_fix"
        case linkedModuleIDs = "linked_module_ids"
        case linkedArtifactIDs = "linked_artifact_ids"
        case linkedDecisionIDs = "linked_decision_ids"
        case gating
        case updatedAt = "updated_at"
    }
}

struct RAndDModuleDefinition: Codable, Identifiable, Hashable {
    let moduleID: String
    let title: String
    let purpose: String
    let affordabilityNotes: String
    let manufacturabilityNotes: String
    let serviceabilityNotes: String
    let repairabilityNotes: String
    let linkedArtifactIDs: [String]

    var id: String { moduleID }

    enum CodingKeys: String, CodingKey {
        case moduleID = "module_id"
        case title
        case purpose
        case affordabilityNotes = "affordability_notes"
        case manufacturabilityNotes = "manufacturability_notes"
        case serviceabilityNotes = "serviceability_notes"
        case repairabilityNotes = "repairability_notes"
        case linkedArtifactIDs = "linked_artifact_ids"
    }
}

struct RAndDToolRequirement: Codable, Identifiable, Hashable {
    let toolID: String
    let name: String
    let category: String
    let reason: String
    let commonality: String

    var id: String { toolID }

    enum CodingKeys: String, CodingKey {
        case toolID = "tool_id"
        case name
        case category
        case reason
        case commonality
    }
}

struct RAndDBomItem: Codable, Identifiable, Hashable {
    let bomID: String
    let name: String
    let quantity: String
    let notes: String
    let moduleID: String?

    var id: String { bomID }

    enum CodingKeys: String, CodingKey {
        case bomID = "bom_id"
        case name
        case quantity
        case notes
        case moduleID = "module_id"
    }
}

struct RAndDAssemblyStep: Codable, Identifiable, Hashable {
    let stepID: String
    let moduleID: String?
    let title: String
    let instructions: String
    let safetyNotes: [String]

    var id: String { stepID }

    enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case moduleID = "module_id"
        case title
        case instructions
        case safetyNotes = "safety_notes"
    }
}

struct RAndDServiceAccessPoint: Codable, Identifiable, Hashable {
    let accessID: String
    let moduleID: String?
    let title: String
    let location: String
    let visibility: String
    let notes: String

    var id: String { accessID }

    enum CodingKeys: String, CodingKey {
        case accessID = "access_id"
        case moduleID = "module_id"
        case title
        case location
        case visibility
        case notes
    }
}

struct RAndDInspectionChecklistItem: Codable, Identifiable, Hashable {
    let itemID: String
    let moduleID: String?
    let title: String
    let verification: String
    let severity: String

    var id: String { itemID }

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case moduleID = "module_id"
        case title
        case verification
        case severity
    }
}

struct RAndDRevisionRecord: Codable, Identifiable, Hashable {
    let revisionID: String
    let label: String
    let sourcePlanVersion: Int
    let reason: String
    let createdAt: String

    var id: String { revisionID }

    enum CodingKeys: String, CodingKey {
        case revisionID = "revision_id"
        case label
        case sourcePlanVersion = "source_plan_version"
        case reason
        case createdAt = "created_at"
    }
}

struct RAndDDocumentSection: Codable, Identifiable, Hashable {
    let sectionID: String
    let heading: String
    let bodyMarkdown: String
    let orderIndex: Int

    var id: String { sectionID }

    enum CodingKeys: String, CodingKey {
        case sectionID = "section_id"
        case heading
        case bodyMarkdown = "body_markdown"
        case orderIndex = "order_index"
    }
}

struct RAndDDocumentExportRecord: Codable, Identifiable, Hashable {
    let exportID: String
    let format: String
    let audienceMode: String
    let revisionLabel: String
    let generatedAt: String

    var id: String { exportID }

    enum CodingKeys: String, CodingKey {
        case exportID = "export_id"
        case format
        case audienceMode = "audience_mode"
        case revisionLabel = "revision_label"
        case generatedAt = "generated_at"
    }
}

struct RAndDDocumentRecord: Codable, Identifiable, Hashable {
    let documentID: String
    let documentType: String
    let audienceMode: String
    let title: String
    let projectName: String
    let platformName: String
    let revisionLabel: String
    let sourceJobID: String
    let sourcePlanVersion: Int
    let artifactIDs: [String]
    let moduleIDs: [String]
    let purpose: String
    let targetAudience: String
    let author: String
    let assumptions: [String]
    let safetyNotes: [String]
    let toolsRequired: [RAndDToolRequirement]
    let materialsRequired: [String]
    let bomSummary: [RAndDBomItem]
    let sections: [RAndDDocumentSection]
    let manufacturabilityNotes: [String]
    let affordabilityNotes: [String]
    let repairabilityNotes: [String]
    let serviceabilityNotes: [String]
    let publicBenefitRationale: String
    let exports: [RAndDDocumentExportRecord]
    let createdAt: String
    let updatedAt: String

    var id: String { documentID }

    enum CodingKeys: String, CodingKey {
        case documentID = "document_id"
        case documentType = "document_type"
        case audienceMode = "audience_mode"
        case title
        case projectName = "project_name"
        case platformName = "platform_name"
        case revisionLabel = "revision_label"
        case sourceJobID = "source_job_id"
        case sourcePlanVersion = "source_plan_version"
        case artifactIDs = "artifact_ids"
        case moduleIDs = "module_ids"
        case purpose
        case targetAudience = "target_audience"
        case author
        case assumptions
        case safetyNotes = "safety_notes"
        case toolsRequired = "tools_required"
        case materialsRequired = "materials_required"
        case bomSummary = "bom_summary"
        case sections
        case manufacturabilityNotes = "manufacturability_notes"
        case affordabilityNotes = "affordability_notes"
        case repairabilityNotes = "repairability_notes"
        case serviceabilityNotes = "serviceability_notes"
        case publicBenefitRationale = "public_benefit_rationale"
        case exports
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RAndDDocumentationBundle: Codable, Identifiable, Hashable {
    let bundleID: String
    let title: String
    let audienceMode: String
    let revisionLabel: String
    let documentIDs: [String]
    let createdAt: String

    var id: String { bundleID }

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case title
        case audienceMode = "audience_mode"
        case revisionLabel = "revision_label"
        case documentIDs = "document_ids"
        case createdAt = "created_at"
    }
}

struct RAndDDoctrineResponse: Codable, Hashable {
    let jobID: String
    let profile: RAndDDoctrineProfile
    let checks: [RAndDDoctrineCheck]
    let moduleDefinitions: [RAndDModuleDefinition]
    let toolRequirements: [RAndDToolRequirement]
    let bomItems: [RAndDBomItem]
    let assemblySteps: [RAndDAssemblyStep]
    let serviceAccessPoints: [RAndDServiceAccessPoint]
    let inspectionChecklistItems: [RAndDInspectionChecklistItem]
    let revisionHistory: [RAndDRevisionRecord]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case profile
        case checks
        case moduleDefinitions = "module_definitions"
        case toolRequirements = "tool_requirements"
        case bomItems = "bom_items"
        case assemblySteps = "assembly_steps"
        case serviceAccessPoints = "service_access_points"
        case inspectionChecklistItems = "inspection_checklist_items"
        case revisionHistory = "revision_history"
    }
}

struct RAndDDocumentsResponse: Codable, Hashable {
    let jobID: String
    let bundles: [RAndDDocumentationBundle]
    let documents: [RAndDDocumentRecord]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case bundles
        case documents
    }
}

struct RAndDJobResponse: Codable, Identifiable, Hashable {
    let jobID: String
    let productType: String
    let designDomain: String
    let currentStage: RAndDStageKind
    let waitingOnUser: Bool
    let autoRunEnabled: Bool
    let pausedAfterCurrentStage: Bool
    let acceptedPlanVersion: Int?
    let latestPlan: RAndDPlan?
    let eta: RAndDEta
    let partCounts: RAndDPartCounts
    let riskFlags: [String]
    let latestValidationSummary: String
    let latestArtifacts: [RAndDArtifact]
    let routingSummary: RAndDRoutingSummary
    let governanceSummary: RAndDGovernanceSummary
    let progressPercent: Int

    var id: String { jobID }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case productType = "product_type"
        case designDomain = "design_domain"
        case currentStage = "current_stage"
        case waitingOnUser = "waiting_on_user"
        case autoRunEnabled = "auto_run_enabled"
        case pausedAfterCurrentStage = "paused_after_current_stage"
        case acceptedPlanVersion = "accepted_plan_version"
        case latestPlan = "latest_plan"
        case eta
        case partCounts = "part_counts"
        case riskFlags = "risk_flags"
        case latestValidationSummary = "latest_validation_summary"
        case latestArtifacts = "latest_artifacts"
        case routingSummary = "routing_summary"
        case governanceSummary = "governance_summary"
        case progressPercent = "progress_percent"
    }
}

struct RAndDArtifactsResponse: Codable, Hashable {
    let jobID: String
    let artifacts: [RAndDArtifact]
    let inspectionGuide: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case artifacts
        case inspectionGuide = "inspection_guide"
    }
}

struct RAndDTimelineStage: Codable, Identifiable, Hashable {
    let stage: RAndDStageKind
    let status: String
    let estimatedMinutes: Int
    let startedAt: String?
    let finishedAt: String?
    let note: String?

    var id: String { "\(stage.rawValue)-\(status)-\(estimatedMinutes)" }

    enum CodingKeys: String, CodingKey {
        case stage
        case status
        case estimatedMinutes = "estimated_minutes"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case note
    }
}

struct RAndDTimelineResponse: Codable, Hashable {
    let jobID: String
    let currentStage: RAndDStageKind
    let waitingOnUser: Bool
    let eta: RAndDEta
    let timeline: [RAndDTimelineStage]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case currentStage = "current_stage"
        case waitingOnUser = "waiting_on_user"
        case eta
        case timeline
    }
}

struct RAndDGovernanceResponse: Codable, Hashable {
    let jobID: String
    let summary: RAndDGovernanceSummary
    let requirements: [RAndDRequirement]
    let decisions: [RAndDDesignDecision]
    let reviews: [RAndDDesignReview]
    let evidenceArtifacts: [RAndDEvidenceArtifact]
    let simulationRuns: [RAndDSimulationRun]
    let reports: [RAndDComplianceReport]
    let approvals: [RAndDApprovalRecord]
    let baselines: [RAndDApprovedBaseline]
    let auditEvents: [RAndDAuditEvent]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case summary
        case requirements
        case decisions
        case reviews
        case evidenceArtifacts = "evidence_artifacts"
        case simulationRuns = "simulation_runs"
        case reports
        case approvals
        case baselines
        case auditEvents = "audit_events"
    }
}

struct RAndDTraceabilityResponse: Codable, Hashable {
    let jobID: String
    let rows: [RAndDTraceabilityRow]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case rows
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
    var reasoningSummary: String? = nil
    var alternativesConsidered: [String] = []
    var assumptions: [String] = []
    var confidenceLabel: String? = nil

    enum CodingKeys: String, CodingKey {
        case model
        case summary
        case nextAction
        case confidence
        case generatedAt
        case reasoningSummary
        case alternativesConsidered
        case assumptions
        case confidenceLabel
    }

    init(
        model: String,
        summary: String,
        nextAction: String,
        confidence: Double,
        generatedAt: Date,
        reasoningSummary: String? = nil,
        alternativesConsidered: [String] = [],
        assumptions: [String] = [],
        confidenceLabel: String? = nil
    ) {
        self.model = model
        self.summary = summary
        self.nextAction = nextAction
        self.confidence = confidence
        self.generatedAt = generatedAt
        self.reasoningSummary = reasoningSummary
        self.alternativesConsidered = alternativesConsidered
        self.assumptions = assumptions
        self.confidenceLabel = confidenceLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        summary = try container.decode(String.self, forKey: .summary)
        nextAction = try container.decode(String.self, forKey: .nextAction)
        confidence = try container.decode(Double.self, forKey: .confidence)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        reasoningSummary = try container.decodeIfPresent(String.self, forKey: .reasoningSummary)
        alternativesConsidered = try container.decodeIfPresent([String].self, forKey: .alternativesConsidered) ?? []
        assumptions = try container.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        confidenceLabel = try container.decodeIfPresent(String.self, forKey: .confidenceLabel)
    }
}

struct PromptQueueItem: Codable, Identifiable, Hashable {
    let id: String
    var prompt: String
    var workspaceLane: WorkspaceLane? = nil
    var workspaceSessionID: String? = nil
    var retryCount: Int? = nil
    var status: PromptQueueStatus
    var createdAt: Date
    var startedAt: Date? = nil
    var completedAt: Date?
    var lastCheckpointAt: Date? = nil
    var progress: Double? = nil
    var checkpointNote: String? = nil
    var streamedResponseText: String? = nil
    var errorMessage: String?
    var output: LocalReasoningOutput?
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
            return "On-device Core"
        case .cloudPro:
            return "Cloud Add-on"
        }
    }

    var subtitle: String {
        switch self {
        case .localTrial:
            return "AI processing and memory remain local on this device."
        case .cloudPro:
            return "Optional prepaid credits unlock Gemini/GPT cloud processing."
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
    case mobileLivingInfrastructure = "mobile_living_infrastructure"
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
            return "Travel Operations Workspace"
        case .mobileLivingInfrastructure:
            return "MLI Studio"
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
    case system
    case document

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

struct KnowledgeFileRecord: Codable, Identifiable, Hashable {
    let id: String
    let fileName: String
    let fileType: String
    let byteCount: Int
    let importedAtUTC: Date
    let chunkCount: Int
    let preview: String
}

struct BundledReferenceDocument: Identifiable, Hashable {
    let id: String
    let title: String
    let fileName: String
    let audience: String
}

enum AtlasContextSurface: String, Codable, CaseIterable, Identifiable {
    case command
    case survey
    case concierge
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command:
            return "Command"
        case .survey:
            return "Survey"
        case .concierge:
            return "Concierge"
        case .workspace:
            return "Workspace"
        }
    }
}

struct AtlasContextProfile: Codable, Identifiable, Hashable {
    let id: String
    let surface: AtlasContextSurface
    let workspaceLaneRawValue: String?
    var customSystemPrompt: String
    var includeSurveyAnswers: Bool
    var includeNotes: Bool
    var includeWorkspaceMemory: Bool
    var includeKnowledgeFiles: Bool
    var includeAccountUsagePatterns: Bool
    var includeRecentUsageTrends: Bool
    var enabledKnowledgeFileIDs: [String]

    var workspaceLane: WorkspaceLane? {
        workspaceLaneRawValue.flatMap(WorkspaceLane.init(rawValue:))
    }

    static func makeDefault(surface: AtlasContextSurface, workspaceLane: WorkspaceLane? = nil) -> AtlasContextProfile {
        let id = workspaceLane == nil
            ? "context:\(surface.rawValue)"
            : "context:\(surface.rawValue):\(workspaceLane!.rawValue)"
        return AtlasContextProfile(
            id: id,
            surface: surface,
            workspaceLaneRawValue: workspaceLane?.rawValue,
            customSystemPrompt: "",
            includeSurveyAnswers: true,
            includeNotes: true,
            includeWorkspaceMemory: surface == .workspace || surface == .command || surface == .concierge,
            includeKnowledgeFiles: true,
            includeAccountUsagePatterns: true,
            includeRecentUsageTrends: true,
            enabledKnowledgeFileIDs: []
        )
    }
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
