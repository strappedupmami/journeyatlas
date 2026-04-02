import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SessionStore: ObservableObject {
    private static let localTrialDurationDays = 30
    private static let modelBriefRefreshWindowSeconds: TimeInterval = 75
    private static let feedRefreshWindowSeconds: TimeInterval = 90
    private static let minimumSurveyAnswersForModelAutofill = 50
    nonisolated private static let localInferenceCacheTTLSeconds: TimeInterval = 120
    private static let queueRuntimeRetryLimit = 3
    nonisolated private static let geminiReasoningModel = "gemini-3-flash-preview"
    nonisolated private static let geminiPodcastTTSModel = "gemini-2.5-pro-preview-tts"
    nonisolated private static let geminiPodcastVoiceName = "Kore"

    private enum PromptDispatchMode {
        case queue
        case steer
    }

    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Travel Design OS (Swift local tier)..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var pendingPrompt = ""
    @Published var pendingPromptOutputType: PromptOutputType = .standard
    @Published var pendingPromptQuizDifficulty: QuizDifficulty = .medium
    @Published var pendingLessonInput = ""
    @Published var promptQueue: [PromptQueueItem] = []
    @Published var codingWorkspaceRootPath = ""
    @Published var codingWorkspaceFiles: [String] = []
    @Published var codingSelectedFilePath: String?
    @Published var codingEditorText = ""
    @Published var codingEditorIsDirty = false
    @Published var codingPromptDraft = ""
    @Published var codingMessages: [CodingWorkspaceMessage] = []
    @Published var codingMemoryRecords: [CodingMemoryRecord] = []
    @Published var codingCommandDraft = "pwd"
    @Published var codingCommandOutput = ""
    @Published var codingIsRunningCommand = false
    @Published var codingIsGeneratingReply = false
    @Published var commandModelBrief = "Model inference will generate a command brief after your check-in."
    @Published var workspaceModelBrief = "Model inference will generate workspace guidance after lane context is available."
    @Published var feedInferenceStatus = "Model inference idle"

    @Published var isSignedIn = false
    @Published var isAppleSignInInProgress = false
    @Published var isGoogleSignInInProgress = false
    @Published var isPasskeyInProgress = false
    @Published var accountProvider: AuthProvider?
    @Published var accountLabel = "Guest Operator"
    @Published var accountFirstName = ""
    @Published var accountMiddleName = ""
    @Published var accountLastName = ""
    @Published var accountUsername = ""
    @Published private(set) var profilePhotoData: Data?
    @Published var accountStatusMessage = "Use provider auth or passwordless to activate your account."
    @Published var billingAccessEnabled = false
    @Published var billingStatusMessage = "Add a payment method to unlock cloud AI."
    @Published var selectedTier: AccountTier = .localTrial
    @Published var trialDaysRemaining = SessionStore.localTrialDurationDays
    @Published var safetyModeActive = false
    @Published var safetyRiskScore = 0
    @Published var safetyInterventionSummary = "No active safety concern signals."

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
    @Published var conciergeSessions: [ConciergeChatSession] = []
    @Published var activeConciergeSessionID: String?
    @Published var workspaceSessions: [WorkspaceNotebookSession] = []
    @Published var activeWorkspaceLane: WorkspaceLane = .mobilityOps
    @Published var activeWorkspaceSessionByLane: [WorkspaceLane: String] = [:]
    @Published var executionSelectedLane: WorkspaceLane = .mobilityOps
    @Published var learningPackage: AdaptiveLearningPackage?
    @Published var memoryCollectionEnabled = true
    @Published var surveyAdditionalPassesCompleted = 0
    @Published var openSurveyTabRequested = false
    @Published var guidedLearningActivated = false
    @Published var adaptiveBusinessQuestionEngineEnabled = true
    @Published var businessAutopilotEnabled = true
    @Published var adaptiveBusinessQuestions: [AdaptiveBusinessQuestion] = []
    @Published var adaptiveBusinessRuntimeStatusLine = "Adaptive business runtime idle."

    @Published var pendingFeedback = ""
    @Published var feedbackOfferEnabled = true

    @Published var vanRentalNeeded = false
    @Published var travelRegion = "Israel"
    @Published var annualDistanceKM = "70000"
    @Published var workspaceMode = "Business mobility"
    @Published var savedTravelLocations: [SavedTravelLocation] = []
    @Published var selectedTravelLocationID: String?
    @Published var activeTravelItinerary = TravelItineraryDraft(
        id: "default-travel-itinerary",
        title: "Travel itinerary",
        locationIDs: [],
        updatedAt: ISO8601DateFormatter().string(from: Date())
    )
    @Published var jobMarketOpportunities: [JobOpportunity] = []
    @Published var jobOpportunityNarratives: [String: String] = [:]

    struct InferenceProviderOption: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
    }

    struct InferenceSettingsSnapshot: Hashable {
        let providerID: String
        let model: String
        let endpoint: String
        let apiKeyStored: Bool
        let apiKeyHint: String?
        let statusLine: String
    }

    struct GuidedLearningSettingsSnapshot: Hashable {
        let kiwixBaseURL: String
        let ollamaEndpoint: String
        let ollamaModel: String
    }

    struct GuidedLearningResult: Hashable {
        let answer: String
        let groundingSummary: String
        let kiwixSourceURL: String?
        let runtimeStatus: String
    }

    struct AdaptiveBusinessQuestionResponse: Codable, Hashable {
        let selectedOptions: [String]
        let freeformText: String
        let answeredAtUTC: Date
    }

    struct AdaptiveBusinessQuestion: Codable, Hashable, Identifiable {
        let id: String
        let prompt: String
        let options: [String]
        let allowsMultipleSelection: Bool
        let generatedAtUTC: Date
        let source: String
        var response: AdaptiveBusinessQuestionResponse?
    }

    let api: APIClient
    private let localReasoning = LocalReasoningEngine()
    nonisolated private static let localInferenceTransport = LocalInferenceTransport()
    nonisolated private static let localInferenceResponseCache = LocalInferenceResponseCache(
        defaultTTL: SessionStore.localInferenceCacheTTLSeconds
    )

    private enum LocalInferenceProvider: String, CaseIterable {
        case openAICompatible = "openai_compatible"
        case gemini = "gemini"

        static var selectableCases: [LocalInferenceProvider] {
            LocalInferenceProvider.allCases
        }

        var title: String {
            switch self {
            case .openAICompatible:
                return "OpenAI-Compatible"
            case .gemini:
                return "Gemini"
            }
        }

        var subtitle: String {
            switch self {
            case .openAICompatible:
                return "OpenAI /v1/chat/completions endpoint (locked: gpt-5.2)"
            case .gemini:
                return "Google Gemini cloud endpoint (locked: gemini-3-flash-preview)"
            }
        }

        var defaultModel: String {
            switch self {
            case .openAICompatible:
                return "gpt-5.2"
            case .gemini:
                return SessionStore.geminiReasoningModel
            }
        }
    }

    private var localInferenceProvider: LocalInferenceProvider {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.providerKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let configured, !configured.isEmpty else { return .gemini }
        return LocalInferenceProvider(rawValue: configured) ?? .gemini
    }

    private var localInferenceModelName: String {
        localInferenceProvider.defaultModel
    }

    private var preferredInferenceProviders: [LocalInferenceProvider] {
        [.gemini, .openAICompatible]
    }

    private var localInferenceEnabled: Bool {
        // Local inference is a mandatory core path across Atlas features.
        true
    }

    private var configuredLocalInferenceEndpointRawValue: String {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.endpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "https://api.openai.com/v1/chat/completions"
        return (configured?.isEmpty == false ? configured! : fallback)
    }

    private var localInferenceOpenAIEndpointURL: URL? {
        guard var url = URL(string: configuredLocalInferenceEndpointRawValue) else { return nil }

        if (url.path.isEmpty || url.path == "/"),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.path = "/v1/chat/completions"
            if let rebuilt = components.url {
                url = rebuilt
            }
        }

        guard let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" {
            let host = (url.host ?? "").lowercased()
            guard host == "localhost" || host == "127.0.0.1" else { return nil }
        } else if scheme != "https" {
            return nil
        }

        return url
    }

    private func localInferenceAPIKey(for provider: LocalInferenceProvider) -> String? {
        let stored = readLocalInferenceAPIKey(for: provider)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return nil }
        return stored
    }

    private var guidedLearningKiwixBaseURLRawValue: String {
        let configured = UserDefaults.standard.string(forKey: GuidedLearningDefaults.kiwixBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "http://127.0.0.1:8080"
        return (configured?.isEmpty == false) ? configured! : fallback
    }

    private var guidedLearningOllamaEndpointRawValue: String {
        let configured = UserDefaults.standard.string(forKey: GuidedLearningDefaults.ollamaEndpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "http://127.0.0.1:11434/v1/chat/completions"
        return (configured?.isEmpty == false) ? configured! : fallback
    }

    private var guidedLearningOllamaModelName: String {
        let configured = UserDefaults.standard.string(forKey: GuidedLearningDefaults.ollamaModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (configured?.isEmpty == false) ? configured! : "llama3.2:latest"
    }

    private var guidedLearningKiwixBaseURL: URL? {
        normalizeEndpointURL(
            guidedLearningKiwixBaseURLRawValue,
            defaultPath: "",
            allowPrivateNetworkHTTP: true
        )
    }

    private var guidedLearningOllamaEndpointURL: URL? {
        normalizeEndpointURL(
            guidedLearningOllamaEndpointRawValue,
            defaultPath: "/v1/chat/completions",
            allowPrivateNetworkHTTP: true
        )
    }

    private var queueWorkerTask: Task<Void, Never>?
    private var adaptiveBusinessQuestionTask: Task<Void, Never>?
    private var businessAutopilotTask: Task<Void, Never>?
    private var lastAdaptiveBusinessQuestionAt = Date.distantPast
    private var lastBusinessAutopilotAt = Date.distantPast
    private var adaptiveBusinessAutopilotCursor = 0
    private var runtimeTelemetryTask: Task<Void, Never>?
    private var pendingRuntimeTelemetry: [String] = []
    private var lastRuntimeTelemetryAt = Date.distantPast
    private var networkPathMonitor: NWPathMonitor?
    private var isInternetConnectionAvailable = true
    private var hasLoggedQueueReconnectWait = false
    private var appleAuthCoordinator: AppleAuthorizationCoordinator?
    private var passkeyAuthCoordinator: AppleAuthorizationCoordinator?

    private let queueStorageLegacyKey = "atlas_ios_prompt_queue_v2"
    private let queueFileName = "prompt-queue-v3.json"
    private let queueBackupFileName = "prompt-queue-v3.bak.json"
    private let stateStorageLegacyKey = "atlas_ios_state_v2"
    private let stateFileName = "session-state-v3.json"
    private let stateBackupFileName = "session-state-v3.bak.json"
    private let profilePhotoFileName = "profile-photo-v1.bin"
    private let profilePhotoBackupFileName = "profile-photo-v1.bak.bin"
    private static let checkpointFormatter = ISO8601DateFormatter()
    private enum LocalInferenceDefaults {
        static let endpointKey = "atlas.local.llm.endpoint"
        static let modelKey = "atlas.local.llm.model"
        static let providerKey = "atlas.local.llm.provider"
        static let keychainService = "com.atlasmasa.local.llm"
        static let keychainAccountPrefix = "provider_api_key"
        static let legacyKeychainAccount = "provider_api_key"
    }

    private enum GuidedLearningDefaults {
        static let kiwixBaseURLKey = "atlas.guided.learning.kiwix.base_url"
        static let ollamaEndpointKey = "atlas.guided.learning.ollama.endpoint"
        static let ollamaModelKey = "atlas.guided.learning.ollama.model"
    }

    private enum AdaptiveBusinessDefaults {
        static let questionsKey = "atlas.adaptive.business.questions.v1"
        static let questionEngineEnabledKey = "atlas.adaptive.business.questions.enabled"
        static let autopilotEnabledKey = "atlas.adaptive.business.autopilot.enabled"
        static let lastQuestionAtKey = "atlas.adaptive.business.last_question_at"
        static let lastAutopilotAtKey = "atlas.adaptive.business.last_autopilot_at"
        static let autopilotCursorKey = "atlas.adaptive.business.autopilot.cursor"
    }

    private static let adaptiveQuestionLoopIntervalSeconds: TimeInterval = 55
    private static let adaptiveQuestionGenerationCadenceSeconds: TimeInterval = 210
    private static let adaptiveQuestionPendingCap = 3
    private static let adaptiveQuestionHistoryCap = 42
    private static let businessAutopilotLoopIntervalSeconds: TimeInterval = 65
    private static let businessAutopilotCadenceSeconds: TimeInterval = 240

    private struct AdaptiveQuestionModelEnvelope: Codable {
        let question: String
        let options: [String]
    }

    private struct KiwixGroundingSnapshot {
        let sourceURL: URL
        let snippets: [String]
    }

    private func keychainAccount(for provider: LocalInferenceProvider) -> String {
        "\(LocalInferenceDefaults.keychainAccountPrefix).\(provider.rawValue)"
    }
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
    private var consecutiveSafeInputs = 0
    private var lastCommandBriefSignature = ""
    private var lastCommandBriefRefreshAt = Date.distantPast
    private var lastWorkspaceBriefSignatureByLane: [WorkspaceLane: String] = [:]
    private var lastWorkspaceBriefRefreshAtByLane: [WorkspaceLane: Date] = [:]
    private var lastFeedInferenceSignature = ""
    private var lastFeedInferenceAt = Date.distantPast
    private var lastJobNarrativeSignature = ""
    private var lastJobNarrativeRefreshAt = Date.distantPast

    private enum CareerRouteMode {
        case employee
        case business
        case hybrid
        case stability
    }

    private struct CareerRouteDecision {
        let mode: CareerRouteMode
        let title: String
        let details: String
    }

    private struct WealthIncomeLadderStep: Hashable {
        let stage: String
        let annualIncomeBandUSD: String
        let leverageMove: String
    }

    private struct WealthBusinessPlaybookStep: Hashable {
        let phase: String
        let objective: String
        let keyActions: [String]
        let metricTarget: String
    }

    private struct WealthIndustryCorpusProfile: Hashable {
        let id: String
        let title: String
        let incomeLadder: [WealthIncomeLadderStep]
        let promotionPlaybook: [String]
        let businessPlaybook: [WealthBusinessPlaybookStep]
        let customerChannels: [String]
    }

    private static let wealthIndustryAliases: [String: String] = [
        "software_ai": "ai_software",
        "cybersecurity": "ai_software",
        "enterprise_sales": "sales",
        "finance": "finance",
        "skilled_trades": "trades",
        "healthcare": "healthcare",
        "operations_logistics": "logistics",
        "real_estate": "real_estate",
        "media_creator": "media",
    ]

    private static let wealthIndustryCorpus: [String: WealthIndustryCorpusProfile] = [
        "ai_software": WealthIndustryCorpusProfile(
            id: "ai_software",
            title: "AI / Software",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Builder foundation", annualIncomeBandUSD: "$60k-$120k", leverageMove: "Ship production features and learn one cloud/runtime stack deeply."),
                WealthIncomeLadderStep(stage: "Mid-level impact", annualIncomeBandUSD: "$120k-$220k", leverageMove: "Own measurable product outcomes and reduce cycle time."),
                WealthIncomeLadderStep(stage: "Senior/staff leverage", annualIncomeBandUSD: "$220k-$420k", leverageMove: "Lead architecture and mentor teams while driving business metrics."),
                WealthIncomeLadderStep(stage: "Principal/director", annualIncomeBandUSD: "$350k-$700k+", leverageMove: "Shape roadmap, multiply teams, and negotiate scope with executives."),
                WealthIncomeLadderStep(stage: "Owner/operator upside", annualIncomeBandUSD: "$500k-$2M+", leverageMove: "Productize expertise via AI automation agency, B2B SaaS, or licensing."),
            ],
            promotionPlaybook: [
                "Map role rubric to weekly scorecard with manager.",
                "Publish impact memo every week (revenue, quality, cycle time).",
                "Build sponsor map across product, engineering, and GTM.",
                "Package promotion case with quantified evidence + compensation benchmark.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Niche selection",
                    objective: "Pick a high-pain vertical where automation yields ROI in 30-90 days.",
                    keyActions: ["Run 15 customer interviews", "Quantify current manual cost", "Define one transformation offer"],
                    metricTarget: "3 design partners in 2 weeks"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Offer launch",
                    objective: "Ship productized service or MVP with strict scope.",
                    keyActions: ["Fixed deliverable + timeline", "Case-study instrumentation", "Weekly ROI report"],
                    metricTarget: "First paid pilot >$5k MRR equivalent"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Distribution",
                    objective: "Create repeatable outbound + inbound engine.",
                    keyActions: ["Founder-led outreach", "Authority content", "Referral flywheel"],
                    metricTarget: "20 qualified opportunities/month"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Scale",
                    objective: "Convert services into leverage assets.",
                    keyActions: ["Templatize delivery", "Layer software workflow", "Add retention/expansion offers"],
                    metricTarget: "Net revenue retention >105%"
                ),
            ],
            customerChannels: ["Founder-led outbound", "Technical content", "Partner referrals", "Product-led signups"]
        ),
        "sales": WealthIndustryCorpusProfile(
            id: "sales",
            title: "Sales",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "SDR/BDR", annualIncomeBandUSD: "$55k-$110k OTE", leverageMove: "Master pipeline generation and qualification consistency."),
                WealthIncomeLadderStep(stage: "AE / closing role", annualIncomeBandUSD: "$120k-$300k OTE", leverageMove: "Increase close rate and average contract value."),
                WealthIncomeLadderStep(stage: "Enterprise / strategic", annualIncomeBandUSD: "$250k-$600k OTE", leverageMove: "Own multi-stakeholder cycles and expansion strategy."),
                WealthIncomeLadderStep(stage: "Sales leadership", annualIncomeBandUSD: "$300k-$900k+", leverageMove: "Build team systems: forecast accuracy, coaching cadence, and territory design."),
                WealthIncomeLadderStep(stage: "Revenue business owner", annualIncomeBandUSD: "$500k-$2M+", leverageMove: "Launch agency/advisory or vertical reseller with recurring contracts."),
            ],
            promotionPlaybook: [
                "Track quota attainment + quality pipeline weekly.",
                "Prove deal coaching impact on teammates.",
                "Document forecast accuracy and strategic account wins.",
                "Negotiate role scope tied to revenue influence.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "ICP precision",
                    objective: "Focus on one profitable buyer segment.",
                    keyActions: ["Define target account profile", "Rewrite messaging to pain + ROI", "Build objection map"],
                    metricTarget: "Reply rate >8%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Acquisition",
                    objective: "Run multi-channel demand generation.",
                    keyActions: ["Outbound sequences", "Warm intro network", "Short educational webinars"],
                    metricTarget: "15 qualified calls/month"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Conversion",
                    objective: "Increase win rate and deal speed.",
                    keyActions: ["Discovery scripts", "Proof-first proposals", "Time-boxed next-step discipline"],
                    metricTarget: "Win rate >25%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Expansion",
                    objective: "Compound account value.",
                    keyActions: ["Land-and-expand motion", "Quarterly business reviews", "Referral asks"],
                    metricTarget: "Expansion revenue >25% of new revenue"
                ),
            ],
            customerChannels: ["Outbound sequencing", "Channel partners", "Referrals", "Events/webinars"]
        ),
        "finance": WealthIndustryCorpusProfile(
            id: "finance",
            title: "Finance",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Analyst foundation", annualIncomeBandUSD: "$70k-$150k", leverageMove: "Build modeling, reporting, and risk discipline."),
                WealthIncomeLadderStep(stage: "Associate / senior analyst", annualIncomeBandUSD: "$150k-$300k", leverageMove: "Own transaction execution or portfolio analysis quality."),
                WealthIncomeLadderStep(stage: "VP / portfolio lead", annualIncomeBandUSD: "$250k-$600k", leverageMove: "Drive deal strategy, stakeholder trust, and risk-adjusted returns."),
                WealthIncomeLadderStep(stage: "Director/partner track", annualIncomeBandUSD: "$500k-$1.5M+", leverageMove: "Source proprietary opportunities and lead capital allocation."),
                WealthIncomeLadderStep(stage: "Capital owner/operator", annualIncomeBandUSD: "$1M-$5M+", leverageMove: "Launch fund, advisory platform, or cash-flowing asset portfolio."),
            ],
            promotionPlaybook: [
                "Track deal quality, speed, and downside protection.",
                "Build trusted relationships with decision-makers.",
                "Publish concise investment/operating memos.",
                "Negotiate compensation with market and impact benchmarks.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Offer structure",
                    objective: "Define advisory, brokerage, or operator model with clear fee economics.",
                    keyActions: ["Model margin by service line", "Set risk controls", "Document client onboarding"],
                    metricTarget: "Gross margin >45%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Trust acquisition",
                    objective: "Build authority and credibility.",
                    keyActions: ["Publish informed analyses", "Case-study track record", "Warm network mobilization"],
                    metricTarget: "10 qualified introductions/month"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Conversion",
                    objective: "Close high-value retained mandates.",
                    keyActions: ["Discovery and suitability process", "Transparent pricing", "Clear downside scenarios"],
                    metricTarget: "Close rate >20%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Compounding",
                    objective: "Retain and expand client accounts.",
                    keyActions: ["Quarterly reviews", "Adjacent service expansion", "Referral compounding"],
                    metricTarget: "Retention >85%"
                ),
            ],
            customerChannels: ["Network intros", "Thought leadership", "Strategic partnerships", "Client referrals"]
        ),
        "trades": WealthIndustryCorpusProfile(
            id: "trades",
            title: "Skilled Trades",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Apprentice", annualIncomeBandUSD: "$45k-$80k", leverageMove: "Stack certifications and reliability reputation."),
                WealthIncomeLadderStep(stage: "Licensed technician", annualIncomeBandUSD: "$80k-$140k", leverageMove: "Master premium scopes and emergency response jobs."),
                WealthIncomeLadderStep(stage: "Lead tech / foreman", annualIncomeBandUSD: "$120k-$220k", leverageMove: "Increase project throughput and quality control."),
                WealthIncomeLadderStep(stage: "Specialist contractor", annualIncomeBandUSD: "$180k-$380k", leverageMove: "Own niche high-margin jobs and repeat contracts."),
                WealthIncomeLadderStep(stage: "Multi-crew owner", annualIncomeBandUSD: "$350k-$1.5M+", leverageMove: "Standardize dispatch, QA, and maintenance plans across teams."),
            ],
            promotionPlaybook: [
                "Document zero-callback quality and speed metrics.",
                "Get advanced licensure for premium scopes.",
                "Lead safety + training programs to prove leadership readiness.",
                "Negotiate compensation from profitability impact, not hours alone.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Niche specialization",
                    objective: "Focus on high-margin service categories.",
                    keyActions: ["Analyze local demand", "Select profitable niches", "Build standard service packages"],
                    metricTarget: "Average ticket size +25%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Dispatch system",
                    objective: "Reduce downtime and no-show losses.",
                    keyActions: ["Route optimization", "SMS confirmation", "Time-window reliability"],
                    metricTarget: "Utilization >75%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Contract compounding",
                    objective: "Build recurring maintenance revenue.",
                    keyActions: ["Service agreements", "Commercial accounts", "Seasonal bundles"],
                    metricTarget: "Recurring revenue >40%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Scale crew",
                    objective: "Grow without service quality collapse.",
                    keyActions: ["Playbook training", "QA checklist", "Supervisor cadence"],
                    metricTarget: "Callback rate <3%"
                ),
            ],
            customerChannels: ["Local SEO", "Property managers", "Commercial contracts", "Referral loops"]
        ),
        "healthcare": WealthIndustryCorpusProfile(
            id: "healthcare",
            title: "Healthcare",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Support/entry clinical", annualIncomeBandUSD: "$50k-$95k", leverageMove: "Build credential base and patient outcome discipline."),
                WealthIncomeLadderStep(stage: "Licensed clinician", annualIncomeBandUSD: "$90k-$180k", leverageMove: "Develop specialty skills and high-demand procedural competence."),
                WealthIncomeLadderStep(stage: "Advanced specialist", annualIncomeBandUSD: "$180k-$420k", leverageMove: "Pursue scarce expertise with measurable care outcomes."),
                WealthIncomeLadderStep(stage: "Department lead/director", annualIncomeBandUSD: "$250k-$600k", leverageMove: "Own service-line quality, economics, and staffing systems."),
                WealthIncomeLadderStep(stage: "Practice/platform owner", annualIncomeBandUSD: "$500k-$2M+", leverageMove: "Operate clinics or telehealth platforms with recurring care programs."),
            ],
            promotionPlaybook: [
                "Track patient outcomes + throughput + quality signals.",
                "Build specialty certifications that shift compensation tiers.",
                "Lead protocol and training upgrades in your unit.",
                "Negotiate from service-line impact and quality outcomes.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Care model design",
                    objective: "Choose high-demand service line with clear value proposition.",
                    keyActions: ["Define patient segment", "Package treatment path", "Set compliance framework"],
                    metricTarget: "Patient satisfaction >90%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Acquisition",
                    objective: "Build referral and digital pipeline.",
                    keyActions: ["Physician referral network", "Outcome-focused content", "Local search optimization"],
                    metricTarget: "New patient growth >10% monthly"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Retention",
                    objective: "Increase repeat and preventive care engagement.",
                    keyActions: ["Follow-up automation", "Care plan adherence", "Membership/plan options"],
                    metricTarget: "Retention >75%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Expansion",
                    objective: "Scale capacity with quality control.",
                    keyActions: ["Standard operating protocols", "Staff training loops", "Utilization dashboard"],
                    metricTarget: "Provider utilization >80%"
                ),
            ],
            customerChannels: ["Referral networks", "Local health partnerships", "Search + reviews", "Telehealth funnels"]
        ),
        "logistics": WealthIndustryCorpusProfile(
            id: "logistics",
            title: "Logistics",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Coordinator/dispatcher", annualIncomeBandUSD: "$50k-$95k", leverageMove: "Master routing reliability and exception handling."),
                WealthIncomeLadderStep(stage: "Planner/supervisor", annualIncomeBandUSD: "$90k-$160k", leverageMove: "Improve on-time metrics and cost per route."),
                WealthIncomeLadderStep(stage: "Ops manager", annualIncomeBandUSD: "$150k-$280k", leverageMove: "Drive throughput, labor efficiency, and SLA quality."),
                WealthIncomeLadderStep(stage: "Regional director/VP", annualIncomeBandUSD: "$250k-$500k", leverageMove: "Lead multi-site optimization and vendor economics."),
                WealthIncomeLadderStep(stage: "3PL/platform owner", annualIncomeBandUSD: "$450k-$3M+", leverageMove: "Build specialized logistics network with recurring contracts."),
            ],
            promotionPlaybook: [
                "Track on-time delivery, damage rate, and cost-to-serve.",
                "Lead cross-functional process upgrades with quantifiable gains.",
                "Own escalation and recovery playbooks for critical incidents.",
                "Negotiate role scope with proven margin and reliability impact.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Segment and promise",
                    objective: "Select vertical and SLA promise with clear differentiation.",
                    keyActions: ["Pick lane specialization", "Define SLA tiers", "Map unit economics"],
                    metricTarget: "Contribution margin >25%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Acquire accounts",
                    objective: "Win anchor customers with measurable reliability.",
                    keyActions: ["Direct outreach", "Broker/channel partnerships", "Pilot program offers"],
                    metricTarget: "5 anchor accounts in 90 days"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Operational discipline",
                    objective: "Increase throughput without service failures.",
                    keyActions: ["Standard load planning", "Exception escalation matrix", "Driver/crew scorecards"],
                    metricTarget: "On-time >97%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Contract expansion",
                    objective: "Expand wallet share and term length.",
                    keyActions: ["Upsell premium services", "Multi-site rollout", "Quarterly value reviews"],
                    metricTarget: "NRR >110%"
                ),
            ],
            customerChannels: ["Direct B2B outbound", "Freight broker networks", "Industry partnerships", "RFP pipelines"]
        ),
        "real_estate": WealthIndustryCorpusProfile(
            id: "real_estate",
            title: "Real Estate",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Analyst/assistant", annualIncomeBandUSD: "$55k-$110k", leverageMove: "Learn underwriting, comps, and deal operations."),
                WealthIncomeLadderStep(stage: "Licensed agent/broker associate", annualIncomeBandUSD: "$90k-$220k", leverageMove: "Build pipeline discipline and niche positioning."),
                WealthIncomeLadderStep(stage: "Top producer / acquisitions manager", annualIncomeBandUSD: "$200k-$500k", leverageMove: "Scale transaction volume with referral systems."),
                WealthIncomeLadderStep(stage: "Team lead / principal broker", annualIncomeBandUSD: "$400k-$1M+", leverageMove: "Build team machine for lead conversion and execution quality."),
                WealthIncomeLadderStep(stage: "Portfolio owner/developer", annualIncomeBandUSD: "$800k-$5M+", leverageMove: "Compound cash-flowing assets and development upside."),
            ],
            promotionPlaybook: [
                "Track conversion rate and average transaction value.",
                "Build referral network with lenders, attorneys, and operators.",
                "Systematize lead response and pipeline follow-up cadence.",
                "Negotiate split/compensation from measurable production impact.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Market selection",
                    objective: "Pick one niche market and asset class.",
                    keyActions: ["Define neighborhood thesis", "Map demand/supply", "Set clear buy box"],
                    metricTarget: "20 qualified leads/month"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Lead machine",
                    objective: "Build predictable inbound + outbound channels.",
                    keyActions: ["Local content + SEO", "Referral partnerships", "Direct outreach cadence"],
                    metricTarget: "Lead-to-meeting >25%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Conversion",
                    objective: "Improve close ratio and deal economics.",
                    keyActions: ["Discovery script", "Offer strategy", "Negotiation playbook"],
                    metricTarget: "Close rate >18%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Portfolio compounding",
                    objective: "Turn transactions into recurring wealth engine.",
                    keyActions: ["Asset management dashboard", "Refinance/rehab strategy", "Cash reserve discipline"],
                    metricTarget: "DSCR >1.25 across portfolio"
                ),
            ],
            customerChannels: ["Local SEO + listings", "Referral partnerships", "Investor circles", "Direct owner outreach"]
        ),
        "media": WealthIndustryCorpusProfile(
            id: "media",
            title: "Media",
            incomeLadder: [
                WealthIncomeLadderStep(stage: "Creator/editor foundation", annualIncomeBandUSD: "$45k-$100k", leverageMove: "Build audience consistency and content system."),
                WealthIncomeLadderStep(stage: "Strategist/producer", annualIncomeBandUSD: "$90k-$180k", leverageMove: "Drive measurable audience and retention growth."),
                WealthIncomeLadderStep(stage: "Growth/brand lead", annualIncomeBandUSD: "$150k-$320k", leverageMove: "Monetize distribution via sponsorship and product funnels."),
                WealthIncomeLadderStep(stage: "Media executive", annualIncomeBandUSD: "$250k-$700k+", leverageMove: "Lead multi-channel monetization and team systems."),
                WealthIncomeLadderStep(stage: "Media company owner", annualIncomeBandUSD: "$500k-$3M+", leverageMove: "Build diversified revenue: ads, subscriptions, products, licensing."),
            ],
            promotionPlaybook: [
                "Track audience retention, watch-time, and monetization per asset.",
                "Own flagship content properties tied to revenue outcomes.",
                "Build sponsor + distribution partner network.",
                "Negotiate role growth based on revenue and brand impact.",
            ],
            businessPlaybook: [
                WealthBusinessPlaybookStep(
                    phase: "Audience niche",
                    objective: "Select one audience with urgent recurring problems.",
                    keyActions: ["Define content thesis", "Consistency calendar", "Audience feedback loop"],
                    metricTarget: "30-day retention trend up"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Monetization baseline",
                    objective: "Launch first repeatable revenue stream.",
                    keyActions: ["Sponsorship packages", "Affiliate stacks", "Service/product funnel"],
                    metricTarget: "First $10k monthly revenue"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Offer expansion",
                    objective: "Add higher-margin products and community engines.",
                    keyActions: ["Digital products", "Membership/community", "B2B brand services"],
                    metricTarget: "Blended gross margin >60%"
                ),
                WealthBusinessPlaybookStep(
                    phase: "Brand system scale",
                    objective: "Scale output without burnout.",
                    keyActions: ["Editorial SOPs", "Production team pods", "Channel-specific analytics"],
                    metricTarget: "Consistent weekly publishing + QoQ growth"
                ),
            ],
            customerChannels: ["Organic content", "Short-form distribution", "Brand partnerships", "Community/email list"]
        ),
    ]

    init(api: APIClient = APIClient()) {
        self.api = api
        configureNetworkPathMonitor()
        restoreStateFromDisk()
        restoreProfilePhotoFromDisk()
        if codingWorkspaceRootPath.isEmpty {
            codingWorkspaceRootPath = defaultCodingWorkspaceRootPath()
        }
        ensureConciergeSessionsSeeded()
        ensureWorkspaceSessionsSeeded()
        loadPromptQueueFromDisk()
        reconcileSessionIDsForLegacyPromptQueue()
        recoverInterruptedQueueItemsAfterRestart()
        startPromptQueueWorker()
        loadAdaptiveBusinessRuntimeFromDefaults()
        startAgenticBusinessRuntime()
    }

    deinit {
        networkPathMonitor?.cancel()
    }

    var hasProfilePhoto: Bool {
        profilePhotoData != nil
    }

    var profilePhotoImage: UIImage? {
        guard let profilePhotoData else { return nil }
        return UIImage(data: profilePhotoData)
    }

    func bootstrap() async {
        appendOutput(await localReasoning.modelStatusLine())
        appendOutput(localLLMRuntimeStatusLine())
        await refreshHealth()
        await syncSessionFromServerIfAvailable()
        await loadSurvey()
        await loadNotes()
        rebuildInsightsAndExecutionPlan()
        await refreshCommandModelBrief()
        await refreshWorkspaceModelBrief()
        await refreshFeed()
        startPromptQueueWorker()
        startAgenticBusinessRuntime()
    }

    func handleAppBecameActive() async {
        await syncSessionFromServerIfAvailable()
        startAgenticBusinessRuntime()
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API reachable. Capabilities refreshed.")
        } catch {
            appendOutput("API health unavailable. App remains in offline-first continuity mode.")
        }
    }

    func inferenceProviderOptions() -> [InferenceProviderOption] {
        LocalInferenceProvider.selectableCases.map { provider in
            InferenceProviderOption(
                id: provider.rawValue,
                title: provider.title,
                subtitle: provider.subtitle
            )
        }
    }

    func inferenceSettingsSnapshot() -> InferenceSettingsSnapshot {
        let provider = localInferenceProvider
        let providerAPIKey = localInferenceAPIKey(for: provider)
        return InferenceSettingsSnapshot(
            providerID: provider.rawValue,
            model: provider.defaultModel,
            endpoint: configuredLocalInferenceEndpointRawValue,
            apiKeyStored: providerAPIKey != nil,
            apiKeyHint: providerAPIKey.map(maskedAPIKey),
            statusLine: localLLMRuntimeStatusLine()
        )
    }

    func saveInferenceSettings(
        providerID: String,
        model: String,
        endpoint: String,
        newAPIKey: String
    ) {
        let provider = LocalInferenceProvider(rawValue: providerID) ?? .gemini
        UserDefaults.standard.set(provider.rawValue, forKey: LocalInferenceDefaults.providerKey)
        UserDefaults.standard.set(provider.defaultModel, forKey: LocalInferenceDefaults.modelKey)
        let requestedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestedModel.isEmpty, requestedModel != provider.defaultModel {
            appendOutput("Model target is locked to \(provider.defaultModel) for \(provider.title).")
        }

        let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEndpoint.isEmpty {
            UserDefaults.standard.removeObject(forKey: LocalInferenceDefaults.endpointKey)
        } else {
            UserDefaults.standard.set(cleanEndpoint, forKey: LocalInferenceDefaults.endpointKey)
        }

        let cleanAPIKey = newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAPIKey.isEmpty {
            if storeLocalInferenceAPIKey(cleanAPIKey, for: provider) {
                appendOutput("\(provider.title) API key stored securely in Keychain.")
            } else {
                appendOutput("Could not store \(provider.title) API key in Keychain.")
            }
        }

        appendOutput("Inference runtime updated: \(provider.title) keychain settings saved. Runtime policy remains Gemini primary with GPT-5.2 fallback.")
        appendOutput(localLLMRuntimeStatusLine())
    }

    func clearInferenceAPIKey() {
        let provider = localInferenceProvider
        if deleteLocalInferenceAPIKey(for: provider) {
            appendOutput("\(provider.title) API key removed from Keychain.")
        } else {
            appendOutput("Could not remove \(provider.title) API key from Keychain.")
        }
        appendOutput(localLLMRuntimeStatusLine())
    }

    func guidedLearningSettingsSnapshot() -> GuidedLearningSettingsSnapshot {
        GuidedLearningSettingsSnapshot(
            kiwixBaseURL: guidedLearningKiwixBaseURLRawValue,
            ollamaEndpoint: guidedLearningOllamaEndpointRawValue,
            ollamaModel: guidedLearningOllamaModelName
        )
    }

    func saveGuidedLearningSettings(
        kiwixBaseURL: String,
        ollamaEndpoint: String,
        ollamaModel: String
    ) {
        let cleanKiwix = kiwixBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOllamaEndpoint = ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanOllamaModel = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanKiwix.isEmpty {
            UserDefaults.standard.removeObject(forKey: GuidedLearningDefaults.kiwixBaseURLKey)
        } else {
            UserDefaults.standard.set(cleanKiwix, forKey: GuidedLearningDefaults.kiwixBaseURLKey)
        }

        if cleanOllamaEndpoint.isEmpty {
            UserDefaults.standard.removeObject(forKey: GuidedLearningDefaults.ollamaEndpointKey)
        } else {
            UserDefaults.standard.set(cleanOllamaEndpoint, forKey: GuidedLearningDefaults.ollamaEndpointKey)
        }

        if cleanOllamaModel.isEmpty {
            UserDefaults.standard.removeObject(forKey: GuidedLearningDefaults.ollamaModelKey)
        } else {
            UserDefaults.standard.set(cleanOllamaModel, forKey: GuidedLearningDefaults.ollamaModelKey)
        }

        appendOutput("Guided learning settings updated. \(guidedLearningRuntimeStatusLine())")
    }

    func activateGuidedLearningAfterSurvey() {
        guard isPrimarySurveyComplete else {
            appendOutput("Guided learning activation blocked. Finish the initialization survey first.")
            openSurveyTabRequested = true
            return
        }
        guard !guidedLearningActivated else {
            appendOutput("Guided learning is already active.")
            return
        }

        guidedLearningActivated = true
        persistStateToDisk()
        startAgenticBusinessRuntime()
        Task { await generateAdaptiveBusinessQuestionIfNeeded(force: true, trigger: "activation") }
        appendOutput("Guided learning activated after survey completion. Kiwix + Ollama runtime is now available.")
    }

    func requestGuidedLearningResponse(for query: String) async -> GuidedLearningResult {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return GuidedLearningResult(
                answer: "Add a concrete learning question to continue.",
                groundingSummary: "No query provided.",
                kiwixSourceURL: nil,
                runtimeStatus: guidedLearningRuntimeStatusLine()
            )
        }

        guard isGuidedLearningRuntimeActive else {
            return GuidedLearningResult(
                answer: "Complete the initialization survey, then confirm that you are ready to start using the app to enable guided learning.",
                groundingSummary: "Runtime locked until explicit post-survey activation.",
                kiwixSourceURL: nil,
                runtimeStatus: guidedLearningRuntimeStatusLine()
            )
        }

        let grounding = await fetchKiwixGroundingSnapshot(for: cleanQuery)
        let groundingLines = grounding?.snippets.prefix(6).map { "- \($0)" }.joined(separator: "\n") ?? "- No snippets returned from Kiwix."
        let profileSignals = surveyAnswers
            .sorted { $0.key < $1.key }
            .prefix(16)
            .map { "- \($0.key): \($0.value)" }
            .joined(separator: "\n")
        let noteSignals = notes
            .prefix(5)
            .map { "- \($0.title): \(sanitizeWorkspaceMemoryValue($0.content, maxLength: 120))" }
            .joined(separator: "\n")

        let prompt = sanitizeModelInput(
            """
            You are Atlas guided learning copilot.
            Use the Kiwix snippets as factual grounding and adapt the explanation to this user's profile.
            Return concise markdown with these sections:
            1) Personalized overview
            2) Guided learning path (now, this week, this month)
            3) Practice drill
            4) Reflection checkpoint
            Keep it practical and execution-oriented.

            USER QUESTION
            \(cleanQuery)

            KIWIX GROUNDED SNIPPETS
            \(groundingLines)

            PROFILE SIGNALS
            \(profileSignals.isEmpty ? "- No survey signals yet." : profileSignals)

            NOTES SIGNALS
            \(noteSignals.isEmpty ? "- No notes captured." : noteSignals)

            GLOBAL CONTEXT
            \(globalReasoningContextDigest(maxLength: 2200))
            """,
            maxLength: 13_000
        )

        let answer = await requestGuidedLearningOllama(prompt: prompt, timeoutSeconds: 28)
            ?? "Ollama is unreachable right now. Verify the Ollama endpoint/model settings, keep Kiwix reachable, and try again."

        let sourceURL = grounding?.sourceURL.absoluteString
        let groundingSummary: String
        if let sourceURL {
            groundingSummary = "Kiwix grounding loaded from \(sourceURL) (\(grounding?.snippets.count ?? 0) snippets)."
        } else {
            groundingSummary = "No Kiwix snippets returned. Response was personalized from survey/notes only."
        }

        return GuidedLearningResult(
            answer: answer,
            groundingSummary: groundingSummary,
            kiwixSourceURL: sourceURL,
            runtimeStatus: guidedLearningRuntimeStatusLine()
        )
    }

    var pendingAdaptiveBusinessQuestion: AdaptiveBusinessQuestion? {
        adaptiveBusinessQuestions.first(where: { $0.response == nil })
    }

    var answeredAdaptiveBusinessQuestionCount: Int {
        adaptiveBusinessQuestions.filter { $0.response != nil }.count
    }

    func saveAdaptiveBusinessRuntimeSettings(
        questionEngineEnabled: Bool,
        businessAutopilotEnabled: Bool
    ) {
        adaptiveBusinessQuestionEngineEnabled = questionEngineEnabled
        self.businessAutopilotEnabled = businessAutopilotEnabled
        adaptiveBusinessRuntimeStatusLine = "Adaptive runtime updated. Questions: \(questionEngineEnabled ? "on" : "off"), autopilot: \(businessAutopilotEnabled ? "on" : "off")."
        persistAdaptiveBusinessRuntimeToDefaults()
    }

    func answerAdaptiveBusinessQuestion(
        questionID: String,
        selectedOptions: [String],
        freeformText: String
    ) {
        guard let index = adaptiveBusinessQuestions.firstIndex(where: { $0.id == questionID }) else {
            adaptiveBusinessRuntimeStatusLine = "Question not found. Generate a new one."
            return
        }
        guard adaptiveBusinessQuestions[index].response == nil else {
            adaptiveBusinessRuntimeStatusLine = "This question was already answered."
            return
        }

        let availableOptions = Set(adaptiveBusinessQuestions[index].options)
        let normalizedSelections = Array(
            Set(selectedOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .intersection(availableOptions)
        ).sorted()
        let cleanFreeform = sanitizeModelInput(freeformText, maxLength: 360)
        guard !normalizedSelections.isEmpty || !cleanFreeform.isEmpty else {
            adaptiveBusinessRuntimeStatusLine = "Choose at least one option or add a freeform response."
            return
        }

        let response = AdaptiveBusinessQuestionResponse(
            selectedOptions: normalizedSelections,
            freeformText: cleanFreeform,
            answeredAtUTC: Date()
        )
        adaptiveBusinessQuestions[index].response = response

        let summary = """
        Q: \(adaptiveBusinessQuestions[index].prompt)
        Selected: \(normalizedSelections.isEmpty ? "none" : normalizedSelections.joined(separator: ", "))
        Notes: \(cleanFreeform.isEmpty ? "none" : cleanFreeform)
        """
        var records = workspaceMemoryRecords
        upsertWorkspaceMemoryRecord(
            in: &records,
            lane: .wealthOperations,
            sessionID: activeSessionID(for: .wealthOperations),
            source: .system,
            key: "adaptive_business_question.\(questionID)",
            value: summary,
            weight: 0.82,
            tags: ["adaptive", "business", "questionnaire", "ollama"],
            now: Date()
        )
        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(records, now: Date())
        persistStateToDisk()
        persistAdaptiveBusinessRuntimeToDefaults()
        adaptiveBusinessRuntimeStatusLine = "Response captured and added to memory."
    }

    func requestNextAdaptiveBusinessQuestionNow() {
        Task {
            await generateAdaptiveBusinessQuestionIfNeeded(force: true, trigger: "manual")
        }
    }

    func startAgenticBusinessRuntime() {
        if adaptiveBusinessQuestionTask == nil {
            adaptiveBusinessQuestionTask = Task { [weak self] in
                await self?.runAdaptiveBusinessQuestionLoop()
            }
        }
        if businessAutopilotTask == nil {
            businessAutopilotTask = Task { [weak self] in
                await self?.runBusinessAutopilotLoop()
            }
        }
    }

    private func runAdaptiveBusinessQuestionLoop() async {
        while !Task.isCancelled {
            await generateAdaptiveBusinessQuestionIfNeeded(force: false, trigger: "loop")
            let interval = UInt64(Self.adaptiveQuestionLoopIntervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: interval)
        }
        adaptiveBusinessQuestionTask = nil
    }

    private func runBusinessAutopilotLoop() async {
        while !Task.isCancelled {
            await performBusinessAutopilotTickIfNeeded(force: false, trigger: "loop")
            let interval = UInt64(Self.businessAutopilotLoopIntervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: interval)
        }
        businessAutopilotTask = nil
    }

    private func generateAdaptiveBusinessQuestionIfNeeded(force: Bool, trigger: String) async {
        guard isGuidedLearningRuntimeActive else {
            if force {
                adaptiveBusinessRuntimeStatusLine = "Adaptive questions are locked until guided learning is active."
            }
            return
        }
        guard adaptiveBusinessQuestionEngineEnabled || force else { return }

        let pendingCount = adaptiveBusinessQuestions.filter { $0.response == nil }.count
        if !force, pendingCount >= Self.adaptiveQuestionPendingCap {
            return
        }

        let now = Date()
        if !force, now.timeIntervalSince(lastAdaptiveBusinessQuestionAt) < Self.adaptiveQuestionGenerationCadenceSeconds {
            return
        }

        let generated = await buildAdaptiveBusinessQuestion()
        adaptiveBusinessQuestions.insert(generated, at: 0)
        if adaptiveBusinessQuestions.count > Self.adaptiveQuestionHistoryCap {
            adaptiveBusinessQuestions = Array(adaptiveBusinessQuestions.prefix(Self.adaptiveQuestionHistoryCap))
        }
        lastAdaptiveBusinessQuestionAt = now
        persistAdaptiveBusinessRuntimeToDefaults()
        adaptiveBusinessRuntimeStatusLine = "Adaptive question generated (\(trigger))."
        appendOutput("Adaptive question generated from memory context (\(generated.source)).")
    }

    private func performBusinessAutopilotTickIfNeeded(force: Bool, trigger: String) async {
        guard isGuidedLearningRuntimeActive else { return }
        guard businessAutopilotEnabled || force else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastBusinessAutopilotAt) < Self.businessAutopilotCadenceSeconds {
            return
        }

        let prompt = businessAutopilotPrompt(for: adaptiveBusinessAutopilotCursor)
        let backupDraft = pendingPrompt
        pendingPrompt = sanitizeModelInput(prompt, maxLength: 1800)
        enqueuePrompt(outputType: .standard)
        if !backupDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingPrompt = backupDraft
        }

        adaptiveBusinessAutopilotCursor = (adaptiveBusinessAutopilotCursor + 1) % 3
        lastBusinessAutopilotAt = now
        persistAdaptiveBusinessRuntimeToDefaults()
        adaptiveBusinessRuntimeStatusLine = "Business autopilot enqueued a task (\(trigger))."
    }

    private func buildAdaptiveBusinessQuestion() async -> AdaptiveBusinessQuestion {
        let answeredSnapshot = adaptiveBusinessQuestions
            .compactMap { question -> String? in
                guard let response = question.response else { return nil }
                let selected = response.selectedOptions.joined(separator: ", ")
                let text = response.freeformText
                return "- Q: \(question.prompt)\n  A: \(selected)\n  Notes: \(text)"
            }
            .prefix(4)
            .joined(separator: "\n")

        let prompt = sanitizeModelInput(
            """
            You are Atlas adaptive business interviewer running on Ollama.
            Generate exactly one multiple-choice question from user memory context.
            Output ONLY valid JSON:
            {"question":"...","options":["...","...","...","..."]}
            Constraints:
            - options must be 3 to 5 concise choices
            - each option <= 72 chars
            - question <= 180 chars
            - question should improve business execution precision now
            - avoid repeating previous answered questions

            PREVIOUS ANSWERS
            \(answeredSnapshot.isEmpty ? "- none yet" : answeredSnapshot)

            GLOBAL USER CONTEXT
            \(globalReasoningContextDigest(maxLength: 2400))
            """,
            maxLength: 13_000
        )

        if let raw = await requestGuidedLearningOllama(prompt: prompt, timeoutSeconds: 22),
           let decoded: AdaptiveQuestionModelEnvelope = Self.decodeModelJSON(raw)
        {
            let questionText = sanitizeWorkspaceMemoryValue(decoded.question, maxLength: 180)
            let options = decoded.options
                .map { sanitizeWorkspaceMemoryValue($0, maxLength: 72) }
                .filter { !$0.isEmpty }
            if !questionText.isEmpty, options.count >= 3 {
                return AdaptiveBusinessQuestion(
                    id: UUID().uuidString,
                    prompt: questionText,
                    options: Array(options.prefix(5)),
                    allowsMultipleSelection: true,
                    generatedAtUTC: Date(),
                    source: "ollama",
                    response: nil
                )
            }
        }

        return AdaptiveBusinessQuestion(
            id: UUID().uuidString,
            prompt: "What is the highest-leverage growth bottleneck right now?",
            options: [
                "Top-of-funnel lead flow is too weak",
                "Offer/value proposition is unclear",
                "Conversion calls close too slowly",
                "Retention/expansion is underperforming"
            ],
            allowsMultipleSelection: true,
            generatedAtUTC: Date(),
            source: "fallback",
            response: nil
        )
    }

    private func businessAutopilotPrompt(for cursor: Int) -> String {
        let baseContext = """
        Use all memory context to produce a concise, execution-ready deliverable.
        Include:
        1) Immediate action
        2) 7-day sequence
        3) KPI checkpoint
        4) Risk + mitigation
        """
        switch cursor % 3 {
        case 0:
            return """
            \(baseContext)
            Deliverable: Weekly growth operating brief with north-star focus, experiment cadence, and resource allocation.
            """
        case 1:
            return """
            \(baseContext)
            Deliverable: Retention and expansion plan with churn diagnosis, onboarding fixes, and NRR recovery path.
            """
        default:
            return """
            \(baseContext)
            Deliverable: Platform leverage plan for distribution flywheel, channel sequencing, and conversion architecture.
            """
        }
    }

    private func loadAdaptiveBusinessRuntimeFromDefaults() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AdaptiveBusinessDefaults.questionEngineEnabledKey) != nil {
            adaptiveBusinessQuestionEngineEnabled = defaults.bool(forKey: AdaptiveBusinessDefaults.questionEngineEnabledKey)
        }
        if defaults.object(forKey: AdaptiveBusinessDefaults.autopilotEnabledKey) != nil {
            businessAutopilotEnabled = defaults.bool(forKey: AdaptiveBusinessDefaults.autopilotEnabledKey)
        }
        if let timestamp = defaults.object(forKey: AdaptiveBusinessDefaults.lastQuestionAtKey) as? TimeInterval {
            lastAdaptiveBusinessQuestionAt = Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = defaults.object(forKey: AdaptiveBusinessDefaults.lastAutopilotAtKey) as? TimeInterval {
            lastBusinessAutopilotAt = Date(timeIntervalSince1970: timestamp)
        }
        if defaults.object(forKey: AdaptiveBusinessDefaults.autopilotCursorKey) != nil {
            adaptiveBusinessAutopilotCursor = max(0, defaults.integer(forKey: AdaptiveBusinessDefaults.autopilotCursorKey))
        }
        if let data = defaults.data(forKey: AdaptiveBusinessDefaults.questionsKey),
           let decoded = try? JSONDecoder().decode([AdaptiveBusinessQuestion].self, from: data)
        {
            adaptiveBusinessQuestions = decoded
                .sorted(by: { $0.generatedAtUTC > $1.generatedAtUTC })
                .prefix(Self.adaptiveQuestionHistoryCap)
                .map { $0 }
        }
        adaptiveBusinessRuntimeStatusLine = "Adaptive business runtime restored."
    }

    private func persistAdaptiveBusinessRuntimeToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(adaptiveBusinessQuestionEngineEnabled, forKey: AdaptiveBusinessDefaults.questionEngineEnabledKey)
        defaults.set(businessAutopilotEnabled, forKey: AdaptiveBusinessDefaults.autopilotEnabledKey)
        defaults.set(lastAdaptiveBusinessQuestionAt.timeIntervalSince1970, forKey: AdaptiveBusinessDefaults.lastQuestionAtKey)
        defaults.set(lastBusinessAutopilotAt.timeIntervalSince1970, forKey: AdaptiveBusinessDefaults.lastAutopilotAtKey)
        defaults.set(adaptiveBusinessAutopilotCursor, forKey: AdaptiveBusinessDefaults.autopilotCursorKey)
        if let encoded = try? JSONEncoder().encode(adaptiveBusinessQuestions) {
            defaults.set(encoded, forKey: AdaptiveBusinessDefaults.questionsKey)
        }
    }

    func handleAppleAuthorization(result: Result<ASAuthorization, Error>) async {
        switch result {
        case let .success(auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                appendOutput("Apple authorization returned unexpected credential.")
                accountStatusMessage = "Apple sign-in returned an unexpected credential payload."
                return
            }
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                appendOutput("Apple identity token missing.")
                accountStatusMessage = "Apple sign-in did not return an identity token on this build."
                return
            }
            let authCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fullNameParts = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let displayName = fullNameParts.isEmpty ? nil : fullNameParts.joined(separator: " ")

            do {
                try await api.exchangeNativeApple(
                    identityToken: identityToken,
                    authorizationCode: authCode,
                    email: email,
                    displayName: displayName,
                    locale: Locale.current.identifier
                )
                markSignedIn(
                    provider: .apple,
                    accountName: displayName ?? credential.fullName?.givenName ?? "Atlas Owner",
                    email: email
                )
                appendOutput("Native Apple sign-in synced with API.")
                accountStatusMessage = "Apple account activated and synced."
            } catch {
                // Keep sign-in local-first so user can still use the app even if API sync fails.
                markSignedIn(
                    provider: .apple,
                    accountName: displayName ?? credential.fullName?.givenName ?? "Atlas Owner",
                    email: email
                )
                appendOutput("Apple sign-in completed locally. API sync pending.")
                accountStatusMessage = "Apple account activated locally. Cloud sync endpoint is pending."
            }

        case let .failure(error):
            appendOutput("Apple sign-in cancelled/failed: \(error.localizedDescription)")
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue
            {
                accountStatusMessage = "Apple sign-in was cancelled."
            } else {
                accountStatusMessage = appleSignInFailureMessage(error: nsError)
                appendOutput("Apple sign-in technical details: domain=\(nsError.domain) code=\(nsError.code)")
            }
        }
    }

    func startNativeAppleSignIn() {
        guard !isAppleSignInInProgress else { return }
        isAppleSignInInProgress = true
        accountStatusMessage = "Launching Apple sign-in…"
        Task { @MainActor in
            defer { isAppleSignInInProgress = false }
            do {
                let auth = try await requestAppleAuthorization()
                await handleAppleAuthorization(result: .success(auth))
            } catch {
                await handleAppleAuthorization(result: .failure(error))
            }
        }
    }

    func startGoogleSignIn() {
        guard !isGoogleSignInInProgress else { return }
        isGoogleSignInInProgress = true
        accountStatusMessage = "Launching Google sign-in…"

        Task { @MainActor in
            defer { isGoogleSignInInProgress = false }
            do {
                let start = try await api.startGoogleOAuth(returnTo: "/signin.html?native_app=ios&provider=google")
                guard let url = URL(string: start.authorizeURL) else {
                    throw NSError(domain: "AtlasGoogleAuth", code: 3001, userInfo: [
                        NSLocalizedDescriptionKey: "Google OAuth URL is invalid."
                    ])
                }
                guard isAllowedOAuthLaunchURL(url) else {
                    throw NSError(domain: "AtlasGoogleAuth", code: 3002, userInfo: [
                        NSLocalizedDescriptionKey: "Blocked non-trusted OAuth launch URL."
                    ])
                }
#if canImport(UIKit)
                let opened = await openExternalURL(url)
                if !opened {
                    throw NSError(domain: "AtlasGoogleAuth", code: 3003, userInfo: [
                        NSLocalizedDescriptionKey: "Could not open Google sign-in page."
                    ])
                }
#endif
                appendOutput("Google sign-in opened in secure browser flow.")
                accountStatusMessage = "Complete Google sign-in in browser, then return to app."
            } catch {
                let message = googleSignInFailureMessage(error: error)
                appendOutput("Google sign-in launch failed: \(message)")
                accountStatusMessage = message
            }
        }
    }

    private func requestAppleAuthorization() async throws -> ASAuthorization {
        guard let anchor = activePresentationAnchor() else {
            throw AppleAuthFlowError.missingPresentationAnchor
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let coordinator = AppleAuthorizationCoordinator(
                anchor: anchor,
                onSuccess: { authorization in
                    continuation.resume(returning: authorization)
                },
                onFailure: { error in
                    continuation.resume(throwing: error)
                },
                onFinish: { [weak self] in
                    self?.appleAuthCoordinator = nil
                }
            )
            appleAuthCoordinator = coordinator
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }

    private func appleSignInFailureMessage(error: NSError) -> String {
        if error.domain == ASAuthorizationError.errorDomain {
            if error.code == ASAuthorizationError.unknown.rawValue {
                return "Apple sign-in failed (AuthorizationError 1000). Check Apple capability + provisioning for bundle \(Bundle.main.bundleIdentifier ?? "unknown.bundle")."
            }
            if error.code == ASAuthorizationError.notHandled.rawValue {
                return "Apple sign-in could not be completed by the OS right now. Try again in a few seconds."
            }
            if error.code == ASAuthorizationError.failed.rawValue {
                return "Apple sign-in failed. Confirm your Apple ID is active on this device and app capability is enabled."
            }
        }
        if let code = AppleAuthFlowError(rawValue: error.code) {
            switch code {
            case .missingPresentationAnchor:
                return "Apple sign-in UI could not be presented. Reopen the app and try again."
            }
        }
        return "Native Apple sign-in failed on this device. Please try again."
    }

    private func activePresentationAnchor() -> ASPresentationAnchor? {
#if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return nil
        }
        if let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return scene.windows.first
#else
        return nil
#endif
    }

    private func performPasskeySignUpFlow() async throws {
        let start = try await api.passkeyRegisterStart(
            displayName: "Atlas Member",
            locale: currentLocaleCode()
        )
        let parsed = try parsePasskeyRegistrationStart(start)
        let credential = try await requestPasskeyRegistration(
            rpID: parsed.rpID,
            challenge: parsed.challenge,
            userID: parsed.userID,
            userName: parsed.userName,
            userVerification: parsed.userVerification
        )
        try await api.passkeyRegisterFinish(
            payload: PasskeyRegistrationFinishPayload(
                requestID: parsed.requestID,
                credential: serializePasskeyRegistrationCredential(credential)
            )
        )
        appendOutput("Passkey registration completed. Finalizing secure sign-in.")
        try await performPasskeySignInFlow()
    }

    private func performPasskeySignInFlow() async throws {
        let start = try await api.passkeyLoginStart()
        let parsed = try parsePasskeyLoginStart(start)
        let credential = try await requestPasskeyAssertion(
            rpID: parsed.rpID,
            challenge: parsed.challenge,
            userVerification: parsed.userVerification
        )
        let response = try await api.passkeyLoginFinish(
            payload: PasskeyLoginFinishPayload(
                requestID: parsed.requestID,
                credential: serializePasskeyAssertionCredential(credential)
            )
        )
        let provider = AuthProvider(rawValue: response.user.provider) ?? .passkey
        let displayName = response.user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? response.user.email
            : response.user.name
        markSignedIn(provider: provider, accountName: displayName, email: response.user.email)
        memoryCollectionEnabled = response.user.memoryOptIn
        appendOutput("Passwordless sign-in completed and verified with API.")
        accountStatusMessage = "Passwordless sign-in active."
    }

    private func requestPasskeyRegistration(
        rpID: String,
        challenge: Data,
        userID: Data,
        userName: String,
        userVerification: String?
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        guard !rpID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "AtlasPasskey", code: 2001, userInfo: [
                NSLocalizedDescriptionKey: "Passkey RP identifier is missing from server payload."
            ])
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: userName,
            userID: userID
        )
        if let preference = passkeyUserVerificationPreference(from: userVerification) {
            request.userVerificationPreference = preference
        }

        let authorization = try await requestPasskeyAuthorization(request: request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw NSError(domain: "AtlasPasskey", code: 2002, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected passkey registration credential type."
            ])
        }
        return credential
    }

    private func requestPasskeyAssertion(
        rpID: String,
        challenge: Data,
        userVerification: String?
    ) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        guard !rpID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "AtlasPasskey", code: 2003, userInfo: [
                NSLocalizedDescriptionKey: "Passkey RP identifier is missing from server payload."
            ])
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if let preference = passkeyUserVerificationPreference(from: userVerification) {
            request.userVerificationPreference = preference
        }

        let authorization = try await requestPasskeyAuthorization(request: request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw NSError(domain: "AtlasPasskey", code: 2004, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected passkey sign-in credential type."
            ])
        }
        return credential
    }

    private func requestPasskeyAuthorization(request: ASAuthorizationRequest) async throws -> ASAuthorization {
        guard let anchor = activePresentationAnchor() else {
            throw AppleAuthFlowError.missingPresentationAnchor
        }
        return try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let coordinator = AppleAuthorizationCoordinator(
                anchor: anchor,
                onSuccess: { authorization in
                    continuation.resume(returning: authorization)
                },
                onFailure: { error in
                    continuation.resume(throwing: error)
                },
                onFinish: { [weak self] in
                    self?.passkeyAuthCoordinator = nil
                }
            )
            passkeyAuthCoordinator = coordinator
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            controller.performRequests()
        }
    }

    private func parsePasskeyRegistrationStart(_ start: PasskeyStartEnvelope) throws -> ParsedPasskeyRegistrationStart {
        let options = passkeyPublicKeyOptions(from: start.options)

        guard let challengeString = options["challenge"] as? String,
              let challenge = decodeBase64URL(challengeString)
        else {
            throw NSError(domain: "AtlasPasskey", code: 2010, userInfo: [
                NSLocalizedDescriptionKey: "Passkey challenge payload is invalid."
            ])
        }

        guard let user = options["user"] as? [String: Any],
              let userIDString = user["id"] as? String,
              let userID = decodeBase64URL(userIDString)
        else {
            throw NSError(domain: "AtlasPasskey", code: 2011, userInfo: [
                NSLocalizedDescriptionKey: "Passkey user payload is invalid."
            ])
        }

        let rp = options["rp"] as? [String: Any]
        let rpID = ((rp?["id"] as? String)?.trimmedNil())
            ?? AppEnvironment.apiBaseURL.host
            ?? "api.atlasmasa.com"

        let userName = ((user["name"] as? String)?.trimmedNil())
            ?? ((user["displayName"] as? String)?.trimmedNil())
            ?? "Atlas Member"

        let authenticatorSelection = (options["authenticatorSelection"] as? [String: Any])
            ?? (options["authenticator_selection"] as? [String: Any])
        let userVerification = (authenticatorSelection?["userVerification"] as? String)
            ?? (authenticatorSelection?["user_verification"] as? String)

        return ParsedPasskeyRegistrationStart(
            requestID: start.requestID,
            rpID: rpID,
            challenge: challenge,
            userID: userID,
            userName: userName,
            userVerification: userVerification
        )
    }

    private func parsePasskeyLoginStart(_ start: PasskeyStartEnvelope) throws -> ParsedPasskeyLoginStart {
        let options = passkeyPublicKeyOptions(from: start.options)
        guard let challengeString = options["challenge"] as? String,
              let challenge = decodeBase64URL(challengeString)
        else {
            throw NSError(domain: "AtlasPasskey", code: 2012, userInfo: [
                NSLocalizedDescriptionKey: "Passkey challenge payload is invalid."
            ])
        }

        let rpID = ((options["rpId"] as? String)?.trimmedNil())
            ?? ((options["rp_id"] as? String)?.trimmedNil())
            ?? AppEnvironment.apiBaseURL.host
            ?? "api.atlasmasa.com"

        let userVerification = (options["userVerification"] as? String)
            ?? (options["user_verification"] as? String)

        return ParsedPasskeyLoginStart(
            requestID: start.requestID,
            rpID: rpID,
            challenge: challenge,
            userVerification: userVerification
        )
    }

    private func passkeyPublicKeyOptions(from options: [String: Any]) -> [String: Any] {
        if let value = options["publicKey"] as? [String: Any] {
            return value
        }
        if let value = options["public_key"] as? [String: Any] {
            return value
        }
        return options
    }

    private func serializePasskeyRegistrationCredential(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration
    ) -> PasskeyRegistrationCredentialPayload {
        let id = encodeBase64URL(credential.credentialID)
        let attestationObject = credential.rawAttestationObject ?? Data()
        return PasskeyRegistrationCredentialPayload(
            id: id,
            rawId: id,
            type: "public-key",
            response: PasskeyRegistrationCredentialResponsePayload(
                clientDataJSON: encodeBase64URL(credential.rawClientDataJSON),
                attestationObject: encodeBase64URL(attestationObject),
                transports: []
            ),
            clientExtensionResults: [:]
        )
    }

    private func serializePasskeyAssertionCredential(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) -> PasskeyAuthenticationCredentialPayload {
        let id = encodeBase64URL(credential.credentialID)
        let userHandleData = credential.userID as Data?
        return PasskeyAuthenticationCredentialPayload(
            id: id,
            rawId: id,
            type: "public-key",
            response: PasskeyAuthenticationCredentialResponsePayload(
                clientDataJSON: encodeBase64URL(credential.rawClientDataJSON),
                authenticatorData: encodeBase64URL(credential.rawAuthenticatorData),
                signature: encodeBase64URL(credential.signature),
                userHandle: userHandleData.flatMap { $0.isEmpty ? nil : encodeBase64URL($0) }
            ),
            clientExtensionResults: [:]
        )
    }

    private func passkeyUserVerificationPreference(
        from value: String?
    ) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference? {
        switch value?.lowercased() {
        case "required":
            return .required
        case "discouraged":
            return .discouraged
        case "preferred":
            return .preferred
        default:
            return nil
        }
    }

    private func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private func currentLocaleCode() -> String {
        if #available(iOS 16.0, *) {
            if let code = Locale.current.language.languageCode?.identifier,
               !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return code
            }
        }
        let fallback = Locale.current.identifier
            .split(separator: "_")
            .first
            .map(String.init)
            ?? "en"
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "en" : fallback
    }

    private func passkeyFailureMessage(error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain {
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                return "Passkey flow was cancelled."
            }
            if nsError.code == ASAuthorizationError.notHandled.rawValue {
                return "Passkey request was not handled by the OS. Verify device passcode and iCloud Keychain."
            }
            if nsError.code == ASAuthorizationError.failed.rawValue {
                return "Passkey flow failed on this device. Verify Associated Domains + passkey capability, then retry."
            }
            if nsError.code == ASAuthorizationError.unknown.rawValue {
                return "Passkey flow failed with an unknown OS error. Verify app entitlements and server RP ID."
            }
        }
        if let code = AppleAuthFlowError(rawValue: nsError.code) {
            switch code {
            case .missingPresentationAnchor:
                return "Passkey UI could not be presented. Reopen the app and try again."
            }
        }
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        return error.localizedDescription
    }

    private func googleSignInFailureMessage(error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == "AtlasGoogleAuth" {
            return nsError.localizedDescription
        }
        return "Google sign-in could not start. Verify provider setup and try again."
    }

    private func isAllowedOAuthLaunchURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        if host == "accounts.google.com" || host == "appleid.apple.com" {
            return true
        }
        if host == "api.atlasmasa.com" || host == "journeyatlas-production.up.railway.app" {
            return true
        }
        return false
    }

#if canImport(UIKit)
    private func openExternalURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
#endif

    func signInWithPasswordless() {
        guard !isPasskeyInProgress else { return }
        isPasskeyInProgress = true
        accountStatusMessage = "Launching passwordless sign-in…"

        Task { @MainActor in
            defer { isPasskeyInProgress = false }
            do {
                try await performPasskeySignInFlow()
            } catch {
                let message = passkeyFailureMessage(error: error)
                appendOutput("Passkey sign-in failed: \(message)")
                accountStatusMessage = message
            }
        }
    }

    func signUpWithPasswordless() {
        guard !isPasskeyInProgress else { return }
        isPasskeyInProgress = true
        accountStatusMessage = "Creating secure passwordless account…"

        Task { @MainActor in
            defer { isPasskeyInProgress = false }
            do {
                try await performPasskeySignUpFlow()
                accountStatusMessage = "Passwordless account created and signed in."
            } catch {
                let message = passkeyFailureMessage(error: error)
                appendOutput("Passkey sign-up failed: \(message)")
                accountStatusMessage = message
            }
        }
    }

    func signOut() {
        isSignedIn = false
        accountProvider = nil
        accountLabel = "Guest Operator"
        accountFirstName = ""
        accountMiddleName = ""
        accountLastName = ""
        accountUsername = ""
        billingAccessEnabled = false
        billingStatusMessage = "Add a payment method to unlock cloud AI."
        selectedTier = .localTrial
        persistStateToDisk()
        Task {
            _ = try? await api.logout()
        }
        appendOutput("Signed out.")
        accountStatusMessage = "Signed out. Sign in again to continue."
    }

    func saveAccountIdentity(
        firstName: String,
        middleName: String,
        lastName: String,
        username: String
    ) {
        guard isSignedIn else {
            accountStatusMessage = "Sign in first to edit your account identity."
            appendOutput("Account identity update blocked: sign in required.")
            return
        }

        let normalizedFirst = sanitizeNameComponent(firstName, maxLength: 40)
        let normalizedMiddle = sanitizeNameComponent(middleName, maxLength: 40)
        let normalizedLast = sanitizeNameComponent(lastName, maxLength: 40)
        let normalizedUsername = sanitizeUsername(username, maxLength: 32)

        accountFirstName = normalizedFirst
        accountMiddleName = normalizedMiddle
        accountLastName = normalizedLast
        accountUsername = normalizedUsername
        accountLabel = resolvedAccountLabel(fallback: accountLabel)
        accountStatusMessage = "Profile identity updated."
        appendOutput("Account identity saved: \(accountLabel)")
        persistStateToDisk()
    }

    func setTier(_ tier: AccountTier) {
        if tier == .cloudPro && !billingAccessEnabled {
            selectedTier = .localTrial
            billingStatusMessage = "Billing is required before cloud mode can be enabled."
            appendOutput("Plan change blocked: billing not active yet.")
            return
        }
        selectedTier = tier
        persistStateToDisk()
        Task { await refreshFeed() }
        appendOutput("Active plan: \(tier.title)")
    }

    func refreshBillingStatus() async {
        await syncSessionFromServerIfAvailable()
    }

    func startInAppPurchaseFlow() {
        billingStatusMessage = "In-app purchase flow is not wired yet. Use manual card setup as fallback for now."
        appendOutput("Billing notice: StoreKit purchase flow is pending integration.")
    }

    func startManualCardSetup(openURL: (URL) -> Void) async {
        guard isSignedIn else {
            accountStatusMessage = "Sign in before adding a payment method."
            appendOutput("Billing notice: sign in first, then add payment method.")
            return
        }
        do {
            let checkout = try await api.createBillingCheckoutSession()
            guard let url = URL(string: checkout.checkoutURL) else {
                billingStatusMessage = "Billing checkout URL is invalid."
                appendOutput("Billing setup failed: checkout URL is invalid.")
                return
            }
            openURL(url)
            billingStatusMessage = "Checkout opened. Complete payment setup, then tap Refresh billing status."
            appendOutput("Billing checkout opened in secure browser.")
        } catch {
            billingStatusMessage = "Could not open billing checkout: \(error.localizedDescription)"
            appendOutput("Billing setup failed: \(error.localizedDescription)")
        }
    }

    func allConciergeSessions() -> [ConciergeChatSession] {
        conciergeSessions
            .sorted { lhs, rhs in
                if lhs.updatedAtUTC == rhs.updatedAtUTC {
                    return lhs.createdAtUTC > rhs.createdAtUTC
                }
                return lhs.updatedAtUTC > rhs.updatedAtUTC
            }
    }

    func activeConciergeSessionTitle() -> String {
        let activeID = resolvedActiveConciergeSessionID()
        return conciergeSessions.first(where: { $0.id == activeID })?.title ?? "Chat"
    }

    func createConciergeSession(title: String? = nil) {
        let now = Date()
        let custom = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = "Concierge Chat \(allConciergeSessions().count + 1)"
        let resolvedTitle = sanitizeWorkspaceMemoryValue(custom?.isEmpty == false ? custom! : defaultTitle, maxLength: 90)

        let session = ConciergeChatSession(
            id: UUID().uuidString,
            title: resolvedTitle,
            createdAtUTC: now,
            updatedAtUTC: now,
            summary: "Fresh chat. Atlas will preload personalized opportunities.",
            isPinned: false
        )
        conciergeSessions.append(session)
        activeConciergeSessionID = session.id
        persistStateToDisk()
        appendOutput("Created concierge chat: \(resolvedTitle).")
    }

    func activateConciergeSession(_ sessionID: String) {
        guard conciergeSessions.contains(where: { $0.id == sessionID }) else { return }
        activeConciergeSessionID = sessionID
        persistStateToDisk()
    }

    func deleteConciergeSession(_ sessionID: String) {
        guard conciergeSessions.contains(where: { $0.id == sessionID }) else { return }
        let removedCount = promptQueue.reduce(0) { partial, item in
            partial + ((item.workspaceLane == nil && item.conciergeSessionID == sessionID) ? 1 : 0)
        }
        promptQueue.removeAll { item in
            item.workspaceLane == nil && item.conciergeSessionID == sessionID
        }
        conciergeSessions.removeAll { $0.id == sessionID }
        ensureConciergeSessionsSeeded()
        persistPromptQueueToDisk()
        persistStateToDisk()
        appendOutput("Deleted concierge chat (\(removedCount) messages removed).")
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
        executionSelectedLane = lane
        ensureWorkspaceSessionsSeeded()
        persistStateToDisk()
        Task { await refreshWorkspaceModelBrief() }
    }

    func activeSessionID(for lane: WorkspaceLane) -> String? {
        activeWorkspaceSessionByLane[lane]
    }

    func createWorkspaceSession(for lane: WorkspaceLane, title: String? = nil) {
        let now = Date()
        let defaultName = "\(lane.title) · Chat \(sessions(for: lane).count + 1)"
        let customTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle: String
        if let customTitle, !customTitle.isEmpty {
            resolvedTitle = customTitle
        } else {
            resolvedTitle = workspaceNameSuggestions(for: lane, limit: 1).first ?? defaultName
        }

        let newSession = WorkspaceNotebookSession(
            id: UUID().uuidString,
            lane: lane,
            title: sanitizeWorkspaceMemoryValue(resolvedTitle, maxLength: 90),
            createdAtUTC: now,
            updatedAtUTC: now,
            summary: "Awaiting first AI response.",
            isPinned: false
        )
        workspaceSessions.append(newSession)
        activeWorkspaceSessionByLane[lane] = newSession.id
        activeWorkspaceLane = lane
        executionSelectedLane = lane
        persistStateToDisk()
        appendOutput("Created workspace chat in \(lane.title).")
        Task { await refreshWorkspaceModelBrief() }
    }

    func workspaceNameSuggestions(for lane: WorkspaceLane, limit: Int = 3) -> [String] {
        let safeLimit = max(1, min(6, limit))
        let nextSessionIndex = sessions(for: lane).count + 1
        let defaultName = "\(lane.title) · Chat \(nextSessionIndex)"
        let personalizationDepth = workspacePersonalizationDepth(for: lane)
        let prefix = laneNamingPrefix(for: lane)

        var signalFragments: [String] = []
        if let plan = workspacePlans.first(where: { $0.lane == lane }) {
            if let objective = normalizeWorkspaceNameFragment(plan.objective, maxWords: 6, maxLength: 44) {
                signalFragments.append(objective)
            }
            if let nextAction = normalizeWorkspaceNameFragment(plan.nextActionNow, maxWords: 6, maxLength: 44) {
                signalFragments.append(nextAction)
            }
        }
        if let daily = normalizeWorkspaceNameFragment(dailyPriority, maxWords: 6, maxLength: 44) {
            signalFragments.append(daily)
        }
        if let mid = normalizeWorkspaceNameFragment(midTermGoal, maxWords: 6, maxLength: 44) {
            signalFragments.append(mid)
        }
        if let long = normalizeWorkspaceNameFragment(longTermVision, maxWords: 6, maxLength: 44) {
            signalFragments.append(long)
        }
        if let blocker = normalizeWorkspaceNameFragment(checkInBlockers, maxWords: 5, maxLength: 34) {
            signalFragments.append("Unblock \(blocker)")
        }
        if let laneMode = laneModeDescriptor(for: lane) {
            signalFragments.append(laneMode)
        }
        if let noteTitle = laneNoteTitle(for: lane) {
            signalFragments.append(noteTitle)
        }
        if personalizationDepth >= 5, let surveyDescriptor = laneSurveyDescriptor(for: lane) {
            signalFragments.append(surveyDescriptor)
        }

        var suggestions: [String] = []
        if let first = signalFragments.first {
            suggestions.append("\(prefix): \(first)")
        }
        if personalizationDepth >= 3, signalFragments.count > 1 {
            suggestions.append("\(prefix): \(signalFragments[1])")
        }
        if personalizationDepth >= 6, signalFragments.count > 1 {
            suggestions.append("\(signalFragments[0]) - \(signalFragments[1])")
        }
        if personalizationDepth >= 8 {
            let tempo: String
            if checkInEnergy >= 4 {
                tempo = "High-energy execution sprint"
            } else if checkInEnergy <= 2 {
                tempo = "Friction reset and stabilization"
            } else {
                tempo = "Steady execution block"
            }
            suggestions.append("\(prefix): \(tempo)")
        }
        if suggestions.isEmpty, let laneMode = laneModeDescriptor(for: lane) {
            suggestions.append("\(prefix): \(laneMode)")
        }

        suggestions.append(defaultName)

        var seen = Set<String>()
        let unique = suggestions
            .map { sanitizeWorkspaceMemoryValue($0, maxLength: 90) }
            .filter { candidate in
                let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return false }
                let dedupeKey = normalized.lowercased()
                guard !seen.contains(dedupeKey) else { return false }
                seen.insert(dedupeKey)
                return true
            }

        return Array(unique.prefix(safeLimit))
    }

    private func workspacePersonalizationDepth(for lane: WorkspaceLane) -> Int {
        var score = 0
        if dailyPriority.trimmedNil() != nil { score += 2 }
        if midTermGoal.trimmedNil() != nil { score += 2 }
        if longTermVision.trimmedNil() != nil { score += 2 }
        if checkInBlockers.trimmedNil() != nil { score += 1 }
        if checkInMood.trimmedNil() != nil { score += 1 }
        if workspacePlans.contains(where: { $0.lane == lane }) { score += 2 }
        score += min(4, surveyAnswers.count / 6)
        score += min(3, notes.count / 4)
        score += min(2, sessions(for: lane).count / 2)
        return score
    }

    private func laneNamingPrefix(for lane: WorkspaceLane) -> String {
        switch lane {
        case .emergencyCommand:
            return "Command"
        case .wealthOperations:
            return "Wealth"
        case .mobilityOps:
            return "Mobility"
        case .deepWork:
            return "Cognition"
        case .innovation:
            return "Innovation"
        }
    }

    private func laneModeDescriptor(for lane: WorkspaceLane) -> String? {
        switch lane {
        case .mobilityOps:
            let region = normalizeWorkspaceNameFragment(travelRegion, maxWords: 3, maxLength: 20)
            let mode = normalizeWorkspaceNameFragment(workspaceMode, maxWords: 4, maxLength: 26)
            if let region, let mode {
                return "\(region) \(mode)"
            }
            return mode ?? region
        case .emergencyCommand:
            if checkInEnergy <= 2 {
                return "Stabilize load and response"
            }
            return "Readiness and response cadence"
        case .wealthOperations:
            if let incomeEngine = surveyAnswers["income_engine"] {
                return normalizeWorkspaceNameFragment(incomeEngine.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            if let wealthVehicle = surveyAnswers["wealth_vehicle"] {
                return normalizeWorkspaceNameFragment(wealthVehicle.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            return nil
        case .deepWork:
            if let focus = surveyAnswers["brain_focus_stability"] {
                return normalizeWorkspaceNameFragment(focus.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            if let sleep = surveyAnswers["brain_sleep_quality"] {
                return normalizeWorkspaceNameFragment(sleep.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            return nil
        case .innovation:
            if let industry = surveyAnswers["industry_focus"] {
                return normalizeWorkspaceNameFragment(industry.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            if let model = surveyAnswers["business_model_focus"] {
                return normalizeWorkspaceNameFragment(model.replacingOccurrences(of: "_", with: " "), maxWords: 4, maxLength: 30)
            }
            return nil
        }
    }

    private func laneSurveyDescriptor(for lane: WorkspaceLane) -> String? {
        let candidateKeys: [String]
        switch lane {
        case .emergencyCommand:
            candidateKeys = ["daily_pressure", "stress_trigger", "runway_months"]
        case .wealthOperations:
            candidateKeys = ["high_paying_job_track", "income_gap_primary", "weekly_revenue_reps"]
        case .mobilityOps:
            candidateKeys = ["travel_priority", "vehicle_strategy", "travel_risk_tolerance"]
        case .deepWork:
            candidateKeys = ["brain_stress_regulation", "decision_protocol", "break_structure"]
        case .innovation:
            candidateKeys = ["monetizable_skill_stack", "growth_priority", "customer_growth_focus"]
        }

        for key in candidateKeys {
            if let value = surveyAnswers[key] {
                let readable = value.replacingOccurrences(of: "_", with: " ")
                if let fragment = normalizeWorkspaceNameFragment(readable, maxWords: 5, maxLength: 34) {
                    return fragment
                }
            }
        }
        return nil
    }

    private func laneNoteTitle(for lane: WorkspaceLane) -> String? {
        guard let note = notes.first(where: { noteLaneIndex[$0.noteID] == lane.rawValue }) else {
            return nil
        }
        return normalizeWorkspaceNameFragment(note.title, maxWords: 5, maxLength: 36)
    }

    private func normalizeWorkspaceNameFragment(_ text: String, maxWords: Int, maxLength: Int) -> String? {
        let cleaned = sanitizeWorkspaceMemoryValue(text, maxLength: 180)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        let compact = cleaned
            .split(separator: " ")
            .prefix(max(1, maxWords))
            .joined(separator: " ")
        let bounded = String(compact.prefix(max(1, maxLength)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.trimmedNil()
    }

    func activateWorkspaceSession(_ sessionID: String) {
        guard let target = workspaceSessions.first(where: { $0.id == sessionID }) else { return }
        activeWorkspaceSessionByLane[target.lane] = target.id
        activeWorkspaceLane = target.lane
        executionSelectedLane = target.lane
        persistStateToDisk()
        appendOutput("Active notebook switched to \(target.title).")
        Task { await refreshWorkspaceModelBrief() }
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
        Task {
            await refreshCommandModelBrief()
            await refreshWorkspaceModelBrief()
            await refreshFeed()
        }
        persistStateToDisk()
    }

    func refreshFeed() async {
        if !isModelAutofillUnlocked {
            feedItems = []
            let statusLine = "AI feed autofill unlocks after \(Self.minimumSurveyAnswersForModelAutofill) survey answers (\(modelAutofillSurveyAnswersRemaining) remaining)."
            let shouldLog = feedInferenceStatus != statusLine
            feedInferenceStatus = statusLine
            if shouldLog {
                appendOutput("Execution feed AI autofill locked until \(Self.minimumSurveyAnswersForModelAutofill) survey answers are completed.")
            }
            return
        }

        if selectedTier == .cloudPro {
            do {
                let payload = try await api.feedProactive()
                feedItems = payload.items
                feedInferenceStatus = "Cloud proactive feed active"
                appendOutput("Cloud proactive feed refreshed.")
                return
            } catch {
                appendOutput("Cloud feed unavailable. Falling back to on-device orchestration.")
            }
        }

        let feedSignature = feedInferenceSignature()
        let now = Date()
        if feedSignature == lastFeedInferenceSignature,
           now.timeIntervalSince(lastFeedInferenceAt) < Self.feedRefreshWindowSeconds,
           !feedItems.isEmpty
        {
            feedInferenceStatus = "Model-generated feed active (cached)"
            return
        }
        defer {
            lastFeedInferenceSignature = feedSignature
            lastFeedInferenceAt = Date()
        }

        if let modelItems = await modelDrivenFeedItems() {
            feedItems = modelItems
            feedInferenceStatus = "Model-generated feed active"
            appendOutput("AI model generated execution feed.")
        } else {
            feedItems = []
            feedInferenceStatus = "AI feed unavailable"
            appendOutput("AI feed generation unavailable. No synthesized feed was generated.")
        }
    }

    func updateExecutionTaskChecklist(
        taskID: String,
        completed: Bool,
        collapsed: Bool? = nil
    ) async {
        let cleanTaskID = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTaskID.isEmpty else { return }
        guard isSignedIn else {
            appendOutput("Task checklist sync requires sign-in.")
            return
        }
        guard selectedTier == .cloudPro else {
            appendOutput("Task checklist sync requires cloud tier.")
            return
        }
        do {
            let feed = try await api.toggleExecutionTask(taskID: cleanTaskID, completed: completed, collapsed: collapsed)
            feedItems = feed.items
            feedInferenceStatus = "Cloud proactive feed active"
            appendOutput("Execution task \(completed ? "completed" : "reopened"): \(cleanTaskID)")
        } catch {
            appendOutput("Execution task sync failed: \(error.localizedDescription)")
        }
    }

    func submitExecutionTaskResponse(
        taskID: String,
        completedParts: String?,
        incompleteParts: String?,
        note: String?,
        completed: Bool? = nil,
        collapsed: Bool? = nil
    ) async {
        let cleanTaskID = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTaskID.isEmpty else { return }
        guard isSignedIn else {
            appendOutput("Task response sync requires sign-in.")
            return
        }
        guard selectedTier == .cloudPro else {
            appendOutput("Task response sync requires cloud tier.")
            return
        }
        let done = completedParts?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = incompleteParts?.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (done?.isEmpty ?? true) && (pending?.isEmpty ?? true) && (noteValue?.isEmpty ?? true) {
            appendOutput("Add task response details before sending.")
            return
        }
        do {
            let feed = try await api.respondExecutionTask(
                taskID: cleanTaskID,
                completedParts: done,
                incompleteParts: pending,
                note: noteValue,
                completed: completed,
                collapsed: collapsed
            )
            feedItems = feed.items
            feedInferenceStatus = "Cloud proactive feed active"
            appendOutput("Execution task response synced: \(cleanTaskID)")
        } catch {
            appendOutput("Task response sync failed: \(error.localizedDescription)")
        }
    }

    func executionActions(for lane: WorkspaceLane) -> [ExecutionAction] {
        executionActions.filter { action in
            let inferredLane = inferWorkspaceLane(from: "\(action.title) \(action.details)")
            return inferredLane == lane
        }
    }

    func feedItems(for lane: WorkspaceLane) -> [FeedItem] {
        let laneToken = lane.rawValue.replacingOccurrences(of: "_", with: " ")
        return feedItems.filter { item in
            let text = "\(item.title) \(item.summary) \(item.whyNow)".lowercased()
            if text.contains(laneToken) {
                return true
            }
            if let inferred = inferWorkspaceLane(from: text) {
                return inferred == lane
            }
            return false
        }
    }

    func starterMessageForConciergeSession(sessionID: String?) -> String? {
        let resolvedSessionID = sessionID ?? resolvedActiveConciergeSessionID()
        let hasMessages = promptQueue.contains { item in
            item.workspaceLane == nil && item.conciergeSessionID == resolvedSessionID
        }
        guard !hasMessages else { return nil }

        let lane = executionSelectedLane
        let lanePlan = workspacePlans.first(where: { $0.lane == lane })
        let topOpportunity = jobMarketOpportunities.first
        let opportunityLine: String
        if isJobRadarReady, let topOpportunity {
            let narrative = jobNarrative(for: topOpportunity)
            opportunityLine = "Top opportunity now: \(topOpportunity.title) (\(topOpportunity.salaryBandUSD)) in \(topOpportunity.location). \(narrative)"
        } else {
            opportunityLine = "Complete the adaptive survey to unlock personalized global job radar context."
        }

        return """
        Session brief (\(activeConciergeSessionTitle())):
        \(lanePlan?.nextActionNow ?? "Define one high-leverage mission for this chat and I will convert it into a tactical execution sequence.")
        \(opportunityLine)
        """
    }

    func starterMessageForWorkspaceSession(lane: WorkspaceLane, sessionID: String?) -> String? {
        guard let sessionID else { return nil }
        let hasMessages = promptQueue.contains { item in
            item.workspaceLane == lane && item.workspaceSessionID == sessionID
        }
        guard !hasMessages else { return nil }

        let plan = workspacePlans.first(where: { $0.lane == lane })
        let topOpportunity = jobMarketOpportunities.first
        let opportunityContext: String
        if isJobRadarReady, let topOpportunity {
            opportunityContext = "Career context: \(topOpportunity.title) — \(jobNarrative(for: topOpportunity))"
        } else {
            opportunityContext = "Career context unlocks after primary survey completion."
        }

        return """
        \(lane.title) briefing:
        Objective: \(plan?.objective ?? workspaceObjective(for: lane))
        Next action: \(plan?.nextActionNow ?? "Capture one concrete next action.")
        \(opportunityContext)
        """
    }

    func jobNarrative(for opportunity: JobOpportunity) -> String {
        if let narrative = jobOpportunityNarratives[opportunity.id],
           !narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return narrative
        }
        let whyLine = opportunity.whyHighlights.prefix(2).joined(separator: " ")
        let howLine = opportunity.capabilityPath.prefix(2).joined(separator: " ")
        return "Why: \(whyLine) How: \(howLine)"
    }

    func loadSurvey() async {
        do {
            survey = try await api.surveyNext()
        } catch {
            appendOutput("Survey loaded from local fallback.")
            let localOpportunities = buildJobMarketOpportunities()
            var hints = ["Local survey mode active", "Gym/income cadence enabled", "Career/business fit routing enabled"]
            if !localOpportunities.isEmpty {
                hints.append("Global job radar active (\(localOpportunities.count) opportunities)")
            }
            let answered = surveyAnswers.count
            let total = localSurveyTotal()
            let percent = Int((Double(answered) / Double(max(1, total))) * 100.0)
            survey = SurveyNextResponse(
                question: localSurveyQuestion(),
                progress: SurveyProgress(answered: answered, total: total, percent: percent),
                profileHints: hints
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
        Task {
            await refreshCommandModelBrief()
            await refreshFeed()
        }
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
        evaluateSuspiciousPattern(input: "\(title)\n\(content)", source: "note")
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

        _ = await ingestYouTubeLinksIntoMemory(from: "\(title)\n\(content)", noteTitle: title)

        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
    }

    private struct YouTubeVideoCandidate {
        let videoID: String
        let canonicalURL: URL
    }

    private struct YouTubeVideoMetadata {
        let title: String
        let channel: String
        let description: String
    }

    private struct YouTubeOEmbedEnvelope: Decodable {
        let title: String?
        let authorName: String?

        enum CodingKeys: String, CodingKey {
            case title
            case authorName = "author_name"
        }
    }

    private func ingestYouTubeLinksIntoMemory(from text: String, noteTitle: String) async -> Int {
        let candidates = Self.extractYouTubeVideoCandidates(from: text)
        guard !candidates.isEmpty else { return 0 }

        let now = Date()
        var mergedRecords = workspaceMemoryRecords
        var imported = 0

        for candidate in candidates.prefix(3) {
            guard let metadata = await Self.fetchYouTubeVideoMetadata(videoID: candidate.videoID, canonicalURL: candidate.canonicalURL) else {
                continue
            }

            let summary = """
            YouTube context from note "\(sanitizeWorkspaceMemoryValue(noteTitle, maxLength: 60))": \
            \(metadata.title) by \(metadata.channel). \
            \(sanitizeWorkspaceMemoryValue(metadata.description, maxLength: 120))
            """
            upsertWorkspaceMemoryRecord(
                in: &mergedRecords,
                lane: nil,
                sessionID: nil,
                source: .document,
                key: "youtube.video.\(candidate.videoID)",
                value: summary,
                weight: 0.78,
                tags: ["youtube", "video", "context", "scraped"],
                now: now
            )
            imported += 1
        }

        guard imported > 0 else {
            appendOutput("Detected YouTube link(s), but no readable metadata was extracted.")
            return 0
        }

        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(mergedRecords, now: now)
        appendOutput("Indexed \(imported) YouTube link(s) into AI memory context.")
        return imported
    }

    nonisolated private static func extractYouTubeVideoCandidates(from text: String) -> [YouTubeVideoCandidate] {
        let pattern = #"https?://(?:www\.)?(?:youtube\.com|m\.youtube\.com|youtu\.be)/[^\s)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        var output: [YouTubeVideoCandidate] = []

        for match in matches {
            let raw = nsText.substring(with: match.range)
            guard let parsed = URL(string: raw),
                  let videoID = youtubeVideoID(from: parsed),
                  seen.insert(videoID).inserted,
                  let canonical = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
            else {
                continue
            }
            output.append(YouTubeVideoCandidate(videoID: videoID, canonicalURL: canonical))
        }
        return output
    }

    nonisolated private static func youtubeVideoID(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        let path = url.path

        func normalizeID(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
            guard trimmed.count >= 6,
                  trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) })
            else {
                return nil
            }
            return String(trimmed.prefix(11))
        }

        if host.contains("youtu.be") {
            let candidate = path.split(separator: "/").first.map(String.init)
            return normalizeID(candidate)
        }

        if path == "/watch",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryID = components.queryItems?.first(where: { $0.name == "v" })?.value
        {
            return normalizeID(queryID)
        }

        if path.hasPrefix("/shorts/") || path.hasPrefix("/embed/") {
            let parts = path.split(separator: "/")
            if parts.count >= 2 {
                return normalizeID(String(parts[1]))
            }
        }

        return nil
    }

    nonisolated private static func fetchYouTubeVideoMetadata(
        videoID: String,
        canonicalURL: URL
    ) async -> YouTubeVideoMetadata? {
        async let oembed = fetchYouTubeOEmbed(videoURL: canonicalURL)
        async let description = fetchYouTubeDescription(videoID: videoID)

        let oembedResult = await oembed
        let descriptionResult = await description

        let title = normalizeWhitespace((oembedResult?.title ?? "YouTube Video").trimmingCharacters(in: .whitespacesAndNewlines))
        let channel = normalizeWhitespace((oembedResult?.authorName ?? "Unknown channel").trimmingCharacters(in: .whitespacesAndNewlines))
        let descriptionText = String(normalizeWhitespace(descriptionResult ?? "No description extracted.").prefix(260))
        guard !title.isEmpty else { return nil }

        return YouTubeVideoMetadata(title: title, channel: channel, description: descriptionText)
    }

    nonisolated private static func fetchYouTubeOEmbed(videoURL: URL) async -> YouTubeOEmbedEnvelope? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: videoURL.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let endpoint = components.url,
              let data = await fetchHTTPData(url: endpoint, timeoutSeconds: 12)
        else {
            return nil
        }
        return try? JSONDecoder().decode(YouTubeOEmbedEnvelope.self, from: data)
    }

    nonisolated private static func fetchYouTubeDescription(videoID: String) async -> String? {
        guard let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)"),
              let htmlData = await fetchHTTPData(url: watchURL, timeoutSeconds: 14),
              let html = String(data: htmlData, encoding: .utf8)
        else {
            return nil
        }

        let escapedPatterns = [
            #""shortDescription":"([^"]+)""#,
            #"<meta name="description" content="([^"]+)""#,
        ]

        for pattern in escapedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsHTML = html as NSString
            let range = NSRange(location: 0, length: nsHTML.length)
            guard let match = regex.firstMatch(in: html, options: [], range: range), match.numberOfRanges >= 2 else { continue }
            let raw = nsHTML.substring(with: match.range(at: 1))
            let decoded = decodeEscapedYouTubeString(raw)
            if !decoded.isEmpty {
                return decoded
            }
        }

        return nil
    }

    nonisolated private static func decodeEscapedYouTubeString(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\r", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\u003d", with: "=")
            .replacingOccurrences(of: "\\u003c", with: "<")
            .replacingOccurrences(of: "\\u003e", with: ">")
        return normalizeWhitespace(decodeHTMLEntities(replaced))
    }

    nonisolated private static func fetchHTTPData(url: URL, timeoutSeconds: Int) async -> Data? {
        await Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("Mozilla/5.0 AtlasMasa/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("text/html,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            let session = URLSession(configuration: config)
            defer {
                session.invalidateAndCancel()
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }.value
    }

    func saveLessonToSharedMemory() {
        guard memoryCollectionEnabled else {
            appendOutput("Memory capture is disabled. Re-enable memory collection before saving lessons.")
            return
        }
        let cleaned = sanitizeWorkspaceMemoryValue(pendingLessonInput, maxLength: 600)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 12 else {
            appendOutput("Add a fuller lesson before saving (at least one clear sentence).")
            return
        }

        let now = Date()
        let lane = activeWorkspaceLane
        let laneSessionID = activeSessionID(for: lane)
        var merged = workspaceMemoryRecords
        let sharedKey = "lesson:shared:\(Int(now.timeIntervalSince1970)):\(workspaceStudioKey(from: cleaned))"
        let laneKey = "lesson:lane:\(lane.rawValue):\(workspaceStudioKey(from: cleaned))"

        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: nil,
            sessionID: nil,
            source: .lesson,
            key: sharedKey,
            value: cleaned,
            weight: 0.97,
            tags: ["lesson", "shared", "learning", "execution"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: lane,
            sessionID: laneSessionID,
            source: .lesson,
            key: laneKey,
            value: cleaned,
            weight: 0.90,
            tags: ["lesson", "lane", lane.rawValue],
            now: now
        )

        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(merged, now: now)
        pendingLessonInput = ""
        refreshWorkspaceSessionSnapshots()
        workspacePlans = buildWorkspacePlans(from: researchStreams, memoryRecords: workspaceMemoryRecords)
        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
        appendOutput("Lesson saved to shared AI memory. Command, feed, and quizzes will integrate it.")

        Task {
            await refreshCommandModelBrief()
            await refreshWorkspaceModelBrief()
            await refreshFeed()
        }
    }

    func recentLessonHighlights(limit: Int = 4) -> [String] {
        lessonMemoryHighlights(limit: limit)
    }

    func saveProfilePhoto(_ image: UIImage, sourceDescription: String) {
        let normalized = Self.normalizeProfilePhotoImage(image)
        guard let encoded = normalized.jpegData(compressionQuality: 0.90) else {
            appendOutput("Could not encode profile photo. Try a different image.")
            return
        }

        let maxPersistedBytes = 10_000_000
        let persisted = encoded.count > maxPersistedBytes
            ? (normalized.jpegData(compressionQuality: 0.74) ?? encoded)
            : encoded

        profilePhotoData = persisted
        persistProfilePhotoToDisk()
        appendOutput("Profile photo updated from \(sourceDescription).")
    }

    func clearProfilePhoto() {
        guard profilePhotoData != nil else { return }
        profilePhotoData = nil
        persistProfilePhotoToDisk()
        appendOutput("Profile photo removed.")
    }

    func deleteLocalMemory() {
        notes = []
        pendingPrompt = ""
        pendingPromptOutputType = .standard
        pendingPromptQuizDifficulty = .medium
        pendingLessonInput = ""
        promptQueue = []
        codingMessages = []
        codingMemoryRecords = []
        codingPromptDraft = ""
        codingCommandOutput = ""
        codingCommandDraft = "pwd"
        codingSelectedFilePath = nil
        codingEditorText = ""
        codingEditorIsDirty = false
        executionActions = []
        memoryInsights = []
        tailoredOffers = []
        researchStreams = []
        workspaceMemoryRecords = []
        workspacePlans = []
        feedItems = []
        jobMarketOpportunities = []
        jobOpportunityNarratives = [:]
        openSurveyTabRequested = false
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
        lastJobNarrativeSignature = ""
        lastJobNarrativeRefreshAt = .distantPast
        conciergeSessions = []
        activeConciergeSessionID = nil
        workspaceSessions = workspaceSessions.map { session in
            var updated = session
            updated.summary = "Session cleared."
            updated.isPinned = false
            return updated
        }
        executionSelectedLane = .mobilityOps
        ensureConciergeSessionsSeeded()
        profilePhotoData = nil
        persistProfilePhotoToDisk()
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

    func submitResponseQualityFeedback(
        source: String,
        sentiment: ResponseFeedbackSentiment,
        prompt: String?,
        fullResponse: String,
        selectedText: String?,
        includePrompt: Bool,
        contentScope: ResponseFeedbackContentScope,
        userNote: String
    ) {
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = Self.trimForDisplay(prompt ?? "", maxChars: 4_000)
        let cleanResponse = Self.trimForDisplay(fullResponse, maxChars: 14_000)
        let cleanSelection = Self.trimForDisplay(selectedText ?? "", maxChars: 6_000)
        let cleanNote = Self.trimForDisplay(userNote, maxChars: 1_600)

        guard !cleanResponse.isEmpty else {
            appendOutput("Feedback not sent: response content is empty.")
            return
        }
        if contentScope == .highlightedOnly && cleanSelection.isEmpty {
            appendOutput("Highlight a section before sending highlight-only feedback.")
            return
        }

        var lines = [
            "IOS_RESPONSE_QUALITY_REPORT",
            "source: \(cleanSource.isEmpty ? "ios_unknown_surface" : cleanSource)",
            "sentiment: \(sentiment.rawValue)",
            "content_scope: \(contentScope.rawValue)",
            "include_prompt: \(includePrompt ? "true" : "false")",
        ]

        if !cleanNote.isEmpty {
            lines.append("user_note:")
            lines.append(cleanNote)
        }

        if includePrompt && !cleanPrompt.isEmpty {
            lines.append("prompt:")
            lines.append(cleanPrompt)
        }

        switch contentScope {
        case .fullResponse:
            lines.append("response:")
            lines.append(cleanResponse)
            if !cleanSelection.isEmpty {
                lines.append("highlighted_excerpt:")
                lines.append(cleanSelection)
            }
        case .highlightedOnly:
            lines.append("highlighted_section:")
            lines.append(cleanSelection)
        }

        let payload = lines.joined(separator: "\n")
        let severity = sentiment == .thumbsDown ? "normal" : "low"
        let tags = [
            "ios",
            "response-feedback",
            sentiment.rawValue,
            contentScope.rawValue,
            cleanSource.isEmpty ? "unknown-surface" : cleanSource,
        ]

        Task {
            do {
                try await api.submitFeedback(
                    category: "model_quality",
                    severity: severity,
                    message: payload,
                    tags: tags,
                    source: cleanSource.isEmpty ? "ios_response_feedback" : cleanSource
                )
                appendOutput("Response feedback sent to product team (\(sentiment.title.lowercased())).")
            } catch {
                appendOutput("Feedback send failed: \(error.localizedDescription)")
            }
        }
    }

    func enqueuePrompt(
        outputType overrideType: PromptOutputType? = nil,
        quizDifficulty overrideQuizDifficulty: QuizDifficulty? = nil
    ) {
        enqueuePromptInternal(
            outputType: overrideType,
            quizDifficulty: overrideQuizDifficulty,
            dispatchMode: .queue,
            workspaceLane: nil,
            conciergeSessionID: resolvedActiveConciergeSessionID(),
            workspaceSessionID: nil
        )
    }

    func steerPrompt(
        outputType overrideType: PromptOutputType? = nil,
        quizDifficulty overrideQuizDifficulty: QuizDifficulty? = nil
    ) {
        enqueuePromptInternal(
            outputType: overrideType,
            quizDifficulty: overrideQuizDifficulty,
            dispatchMode: .steer,
            workspaceLane: nil,
            conciergeSessionID: resolvedActiveConciergeSessionID(),
            workspaceSessionID: nil
        )
    }

    func enqueueWorkspacePrompt(
        outputType overrideType: PromptOutputType? = nil,
        quizDifficulty overrideQuizDifficulty: QuizDifficulty? = nil
    ) {
        let lane = activeWorkspaceLane
        let sessionID = activeSessionID(for: lane)
        enqueuePromptInternal(
            outputType: overrideType,
            quizDifficulty: overrideQuizDifficulty,
            dispatchMode: .queue,
            workspaceLane: lane,
            conciergeSessionID: nil,
            workspaceSessionID: sessionID
        )
    }

    func steerWorkspacePrompt(
        outputType overrideType: PromptOutputType? = nil,
        quizDifficulty overrideQuizDifficulty: QuizDifficulty? = nil
    ) {
        let lane = activeWorkspaceLane
        let sessionID = activeSessionID(for: lane)
        enqueuePromptInternal(
            outputType: overrideType,
            quizDifficulty: overrideQuizDifficulty,
            dispatchMode: .steer,
            workspaceLane: lane,
            conciergeSessionID: nil,
            workspaceSessionID: sessionID
        )
    }

    func conciergeHasActiveProcessing() -> Bool {
        hasActivePromptProcessing(
            workspaceLane: nil,
            conciergeSessionID: resolvedActiveConciergeSessionID(),
            workspaceSessionID: nil
        )
    }

    func workspaceHasActiveProcessing() -> Bool {
        let lane = activeWorkspaceLane
        let sessionID = activeSessionID(for: lane)
        return hasActivePromptProcessing(
            workspaceLane: lane,
            conciergeSessionID: nil,
            workspaceSessionID: sessionID
        )
    }

    private func enqueuePromptInternal(
        outputType overrideType: PromptOutputType?,
        quizDifficulty overrideQuizDifficulty: QuizDifficulty?,
        dispatchMode: PromptDispatchMode,
        workspaceLane: WorkspaceLane?,
        conciergeSessionID: String?,
        workspaceSessionID: String?
    ) {
        let cleaned = pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            appendOutput("Write a prompt before queueing.")
            return
        }
        let selectedOutputType = overrideType ?? pendingPromptOutputType
        let selectedQuizDifficulty = selectedOutputType == .quiz
            ? (overrideQuizDifficulty ?? pendingPromptQuizDifficulty)
            : nil

        let safetySignal = evaluateSuspiciousPattern(input: cleaned, source: "prompt")
        if safetySignal.holdQueue {
            appendOutput("Queue is temporarily paused due to high-risk language. Atlas can only support de-escalation, rehabilitation, and safe next steps.")
            return
        }

        let queueItem = PromptQueueItem(
            id: UUID().uuidString,
            prompt: cleaned,
            outputType: selectedOutputType,
            quizDifficulty: selectedQuizDifficulty,
            workspaceLane: workspaceLane,
            conciergeSessionID: conciergeSessionID,
            workspaceSessionID: workspaceSessionID,
            retryCount: nil,
            status: .queued,
            createdAt: Date(),
            completedAt: nil,
            errorMessage: nil,
            output: nil
        )

        if dispatchMode == .steer {
            let insertionIndex = steerInsertionIndex(
                workspaceLane: workspaceLane,
                conciergeSessionID: conciergeSessionID,
                workspaceSessionID: workspaceSessionID
            )
            promptQueue.insert(queueItem, at: insertionIndex)
        } else {
            promptQueue.append(queueItem)
        }

        pendingPrompt = ""
        persistPromptQueueToDisk()
        let outputDescriptor: String = {
            if selectedOutputType == .quiz, let selectedQuizDifficulty {
                return "\(selectedOutputType.title) · \(selectedQuizDifficulty.title)"
            }
            return selectedOutputType.title
        }()
        let actionLabel = dispatchMode == .steer ? "Steer update prioritized" : "Prompt queued for AI processing"
        if let lane = workspaceLane {
            appendOutput("\(actionLabel) (\(outputDescriptor)) in \(lane.title).")
        } else {
            appendOutput("\(actionLabel) (\(outputDescriptor)).")
            if let conciergeSessionID {
                touchConciergeSession(
                    id: conciergeSessionID,
                    summary: "Queued: \(sanitizeWorkspaceMemoryValue(cleaned, maxLength: 120))"
                )
            }
        }
        refreshConciergeSessionSnapshots()
        startPromptQueueWorker()
    }

    private func hasActivePromptProcessing(
        workspaceLane: WorkspaceLane?,
        conciergeSessionID: String?,
        workspaceSessionID: String?
    ) -> Bool {
        promptQueue.contains { item in
            queueItemBelongsToScope(
                item,
                workspaceLane: workspaceLane,
                conciergeSessionID: conciergeSessionID,
                workspaceSessionID: workspaceSessionID
            ) && (item.status == .running || item.status == .queued)
        }
    }

    private func steerInsertionIndex(
        workspaceLane: WorkspaceLane?,
        conciergeSessionID: String?,
        workspaceSessionID: String?
    ) -> Int {
        let globalRunningIndex = promptQueue.firstIndex { $0.status == .running }
        let scopedRunningIndex = promptQueue.firstIndex { item in
            queueItemBelongsToScope(
                item,
                workspaceLane: workspaceLane,
                conciergeSessionID: conciergeSessionID,
                workspaceSessionID: workspaceSessionID
            ) && item.status == .running
        }
        let scopedQueuedIndex = promptQueue.firstIndex { item in
            queueItemBelongsToScope(
                item,
                workspaceLane: workspaceLane,
                conciergeSessionID: conciergeSessionID,
                workspaceSessionID: workspaceSessionID
            ) && item.status == .queued
        }

        var index = promptQueue.count
        if let scopedRunningIndex {
            index = scopedRunningIndex + 1
        } else if let scopedQueuedIndex {
            index = scopedQueuedIndex
        } else if let globalRunningIndex {
            index = globalRunningIndex + 1
        }

        if let globalRunningIndex, index <= globalRunningIndex {
            index = globalRunningIndex + 1
        }

        return max(0, min(index, promptQueue.count))
    }

    private func queueItemBelongsToScope(
        _ item: PromptQueueItem,
        workspaceLane: WorkspaceLane?,
        conciergeSessionID: String?,
        workspaceSessionID: String?
    ) -> Bool {
        guard let workspaceLane else {
            guard item.workspaceLane == nil else { return false }
            guard let conciergeSessionID else { return true }
            return item.conciergeSessionID == conciergeSessionID
        }
        guard item.workspaceLane == workspaceLane else { return false }
        guard let workspaceSessionID else { return true }
        return item.workspaceSessionID == nil || item.workspaceSessionID == workspaceSessionID
    }

    func launchWorkspaceStudioModule(moduleTitle: String, moduleInstruction: String) {
        let title = sanitizeWorkspaceMemoryValue(moduleTitle, maxLength: 72)
        let instruction = sanitizeWorkspaceMemoryValue(moduleInstruction, maxLength: 420)
        guard !title.isEmpty, !instruction.isEmpty else { return }

        let lane = activeWorkspaceLane
        let lanePlan = workspacePlans.first(where: { $0.lane == lane })
        let sessionID = activeSessionID(for: lane)
        let activeSessionTitle = sessionID
            .flatMap { id in workspaceSessions.first(where: { $0.id == id })?.title } ?? "Core Session"

        let signalLines = workspaceMemoryRecords
            .filter { $0.lane == lane || $0.lane == nil }
            .sorted { lhs, rhs in
                if lhs.updatedAtUTC == rhs.updatedAtUTC {
                    return lhs.weight > rhs.weight
                }
                return lhs.updatedAtUTC > rhs.updatedAtUTC
            }
            .prefix(5)
            .map {
                "- \(workspaceSignalLabel(for: $0.key)): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 110))"
            }
            .joined(separator: "\n")

        let prompt = """
        You are Atlas Workspace Studio, a pro-grade on-device operator assistant.
        Return concise, execution-ready output.

        Workspace lane: \(lane.title)
        Module: \(title)
        Objective: \(lanePlan?.objective ?? workspaceObjective(for: lane))
        Active notebook: \(activeSessionTitle)
        Next action baseline: \(lanePlan?.nextActionNow ?? "No baseline action yet.")
        Model lane brief: \(workspaceModelBrief)

        Relevant signals:
        \(signalLines.isEmpty ? "- No strong memory signals yet." : signalLines)

        Task:
        \(instruction)

        Required format:
        1) Immediate move (one sentence)
        2) Three-step execution plan
        3) Primary risk + fallback protocol
        4) Metric to review in 24 hours
        """

        pendingPrompt = sanitizeModelInput(prompt, maxLength: 1800)
        enqueueWorkspacePrompt(outputType: .standard)

        var merged = workspaceMemoryRecords
        let now = Date()
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: lane,
            sessionID: sessionID,
            source: .system,
            key: "studio_module_\(workspaceStudioKey(from: title))",
            value: "\(title): \(instruction)",
            weight: 0.76,
            tags: ["workspace_studio", lane.rawValue, "model_module"],
            now: now
        )
        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(merged, now: now)
        refreshWorkspaceSessionSnapshots()
        workspacePlans = buildWorkspacePlans(from: researchStreams, memoryRecords: workspaceMemoryRecords)
        persistStateToDisk()
        appendOutput("Workspace studio module queued: \(title) (\(lane.title)).")
        Task { await refreshWorkspaceModelBrief() }
    }

    func clearPromptQueue() {
        promptQueue = []
        refreshConciergeSessionSnapshots()
        persistPromptQueueToDisk()
        appendOutput("Prompt queue cleared.")
    }

    func clearConciergePromptQueue() {
        let sessionID = resolvedActiveConciergeSessionID()
        promptQueue.removeAll {
            $0.workspaceLane == nil && $0.conciergeSessionID == sessionID
        }
        touchConciergeSession(id: sessionID, summary: "Chat cleared.")
        refreshConciergeSessionSnapshots()
        persistPromptQueueToDisk()
        appendOutput("Concierge chat cleared.")
    }

    func clearWorkspacePromptQueue() {
        let lane = activeWorkspaceLane
        let activeSession = activeSessionID(for: lane)
        promptQueue.removeAll { item in
            guard item.workspaceLane == lane else { return false }
            guard let activeSession else { return true }
            return item.workspaceSessionID == nil || item.workspaceSessionID == activeSession
        }
        persistPromptQueueToDisk()
        appendOutput("Workspace chat cleared for \(lane.title).")
    }

    func setCodingWorkspaceRootPath(_ rawPath: String) {
        let normalized = normalizeCodingPath(rawPath)
        codingWorkspaceRootPath = normalized.isEmpty ? defaultCodingWorkspaceRootPath() : normalized
        persistStateToDisk()
    }

    func rescanCodingWorkspace() {
        let normalizedRoot = normalizeCodingPath(codingWorkspaceRootPath)
        guard !normalizedRoot.isEmpty else {
            appendOutput("Set a coding workspace root path before scanning.")
            return
        }

        let rootURL = URL(fileURLWithPath: normalizedRoot)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            appendOutput("Coding workspace root is invalid: \(normalizedRoot)")
            return
        }

        let skipDirectories: Set<String> = [
            ".git", ".svn", ".hg", ".next", ".derived", ".build", "node_modules", "dist", "build", "DerivedData"
        ]
        let skipExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "gz", "xz", "7z", "tar",
            "mp4", "mov", "mp3", "wav", "aiff", "ico", "icns", "ttf", "otf",
            "o", "a", "dylib", "so", "class", "jar", "pyc", "sqlite", "db", "bin"
        ]

        var files: [String] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            while let nextURL = enumerator.nextObject() as? URL {
                let name = nextURL.lastPathComponent
                if skipDirectories.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                let values = try? nextURL.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    continue
                }

                let ext = nextURL.pathExtension.lowercased()
                if skipExtensions.contains(ext) {
                    continue
                }

                files.append(nextURL.path)
            }
        }

        files.sort()
        codingWorkspaceRootPath = normalizedRoot
        codingWorkspaceFiles = files

        if let selected = codingSelectedFilePath,
           !files.contains(selected)
        {
            codingSelectedFilePath = nil
            codingEditorText = ""
            codingEditorIsDirty = false
        }

        persistStateToDisk()
        appendOutput("Coding workspace indexed: \(files.count) files.")
        addCodingMessage(
            role: .system,
            content: "Workspace scan complete. Indexed \(files.count) files under \(normalizedRoot)."
        )
    }

    func selectCodingFile(relativePath: String) {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetPath: String
        if trimmed.hasPrefix("/") {
            targetPath = normalizeCodingPath(trimmed)
        } else {
            targetPath = normalizeCodingPath((codingWorkspaceRootPath as NSString).appendingPathComponent(trimmed))
        }
        openCodingFile(targetPath)
    }

    func openCodingFile(_ absolutePath: String) {
        let normalizedPath = normalizeCodingPath(absolutePath)
        guard !normalizedPath.isEmpty else {
            appendOutput("Select a valid file path.")
            return
        }

        guard isPathInsideCodingWorkspace(normalizedPath) else {
            appendOutput("Refusing to open file outside coding workspace root.")
            return
        }

        let fileURL = URL(fileURLWithPath: normalizedPath)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            appendOutput("Coding file not found: \(codingRelativePath(normalizedPath))")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if data.count > 2_500_000 {
                appendOutput("File is too large for inline editor (>2.5 MB). Open a smaller file.")
                return
            }
            guard isLikelyText(data) else {
                appendOutput("File appears binary and cannot be edited in text mode.")
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            codingSelectedFilePath = normalizedPath
            codingEditorText = text
            codingEditorIsDirty = false
            persistStateToDisk()
            addCodingMessage(
                role: .system,
                content: "Opened \(codingRelativePath(normalizedPath)) (\(text.split(whereSeparator: \.isNewline).count) lines).",
                relatedFilePath: normalizedPath
            )
        } catch {
            appendOutput("Failed to open coding file: \(error.localizedDescription)")
        }
    }

    func setCodingEditorText(_ text: String) {
        codingEditorText = text
        codingEditorIsDirty = true
    }

    func saveCodingFile() {
        guard let filePath = codingSelectedFilePath else {
            appendOutput("Open a coding file before saving.")
            return
        }
        guard isPathInsideCodingWorkspace(filePath) else {
            appendOutput("Refusing to save file outside coding workspace root.")
            return
        }
        guard let data = codingEditorText.data(using: .utf8) else {
            appendOutput("Failed to encode file as UTF-8.")
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: filePath), options: [.atomic])
            codingEditorIsDirty = false
            addCodingMessage(
                role: .system,
                content: "Saved \(codingRelativePath(filePath)) (\(codingEditorText.count) chars).",
                relatedFilePath: filePath
            )
            addCodingMemoryRecord(
                kind: .fileSnapshot,
                summary: "Saved \(codingRelativePath(filePath))",
                detail: String(codingEditorText.prefix(2400)),
                relatedFilePath: filePath
            )
            persistStateToDisk()
        } catch {
            appendOutput("Failed to save file: \(error.localizedDescription)")
        }
    }

    func submitCodingPrompt() {
        let prompt = codingPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            appendOutput("Write a local coding prompt before sending.")
            return
        }
        guard !codingIsGeneratingReply else {
            appendOutput("Local coding agent is still generating the previous response.")
            return
        }

        let safetySignal = evaluateSuspiciousPattern(input: prompt, source: "coding_prompt")
        if safetySignal.holdQueue {
            addCodingMessage(
                role: .system,
                content: "Prompt blocked by safety guard. Atlas local coding mode only supports lawful, non-harmful work."
            )
            codingPromptDraft = ""
            persistStateToDisk()
            return
        }

        addCodingMessage(role: .user, content: prompt, relatedFilePath: codingSelectedFilePath)
        addCodingMemoryRecord(
            kind: .prompt,
            summary: "Prompt: \(sanitizeWorkspaceMemoryValue(prompt, maxLength: 120))",
            detail: prompt,
            relatedFilePath: codingSelectedFilePath
        )
        codingPromptDraft = ""

        if handleCodingSlashCommand(prompt) {
            persistStateToDisk()
            return
        }

        let selectedPath = codingSelectedFilePath
        codingIsGeneratingReply = true
        Task {
            let modelPrompt = composeOllamaPrompt(for: prompt)
            let modelReply = await requestLocalModelResponse(
                prompt: modelPrompt,
                timeoutSeconds: 24,
                domain: .coding
            )
            let trimmedReply = modelReply?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let reply = trimmedReply, !reply.isEmpty {
                addCodingMessage(role: .assistant, content: reply, relatedFilePath: selectedPath)
                addCodingMemoryRecord(
                    kind: .response,
                    summary: "Assistant response for latest prompt",
                    detail: reply,
                    relatedFilePath: selectedPath
                )
            } else {
                addCodingMessage(
                    role: .system,
                    content: "AI coding runtime unavailable. No response was generated. Verify runtime settings and retry.",
                    relatedFilePath: selectedPath
                )
                appendOutput("AI coding runtime unavailable. No synthesized response was generated.")
            }
            codingIsGeneratingReply = false
            persistStateToDisk()
        }
    }

    func runCodingCommand(commandOverride: String? = nil) {
        let command = (commandOverride ?? codingCommandDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            appendOutput("Write a shell command before running.")
            return
        }

        let rootPath = normalizeCodingPath(codingWorkspaceRootPath)
        guard !rootPath.isEmpty else {
            appendOutput("Set coding workspace root before running shell commands.")
            return
        }

        guard !codingIsRunningCommand else {
            appendOutput("A coding command is already running.")
            return
        }

        codingIsRunningCommand = true
        codingCommandDraft = command
        addCodingMessage(role: .command, content: "$ \(command)")

        let indexedFiles = codingWorkspaceFiles
        Task {
            let startedAt = Date()
            let commandResult = await Self.executeIOSLocalCommand(
                command,
                workingDirectory: rootPath,
                indexedFiles: indexedFiles
            )
            let elapsed = max(0.01, Date().timeIntervalSince(startedAt))
            let output = commandResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = output.isEmpty ? "(no output)" : output
            let summary = """
            Exit \(commandResult.status) in \(String(format: "%.2fs", elapsed))
            \(body)
            """
            codingCommandOutput = summary
            codingIsRunningCommand = false
            addCodingMessage(role: .command, content: summary)
            addCodingMemoryRecord(
                kind: .command,
                summary: "Command: \(sanitizeWorkspaceMemoryValue(command, maxLength: 120))",
                detail: summary,
                relatedFilePath: codingSelectedFilePath
            )
            persistStateToDisk()
            appendOutput("Local command completed: \(command)")
        }
    }

    func clearCodingMemory() {
        codingMessages = []
        codingMemoryRecords = []
        codingCommandOutput = ""
        codingPromptDraft = ""
        persistStateToDisk()
        appendOutput("Coding workspace memory cleared.")
    }

    func rememberCurrentCodingFile() {
        guard let filePath = codingSelectedFilePath else {
            appendOutput("Open a coding file before remembering context.")
            return
        }
        addCodingMemoryRecord(
            kind: .fileSnapshot,
            summary: "Manual memory checkpoint: \(codingRelativePath(filePath))",
            detail: String(codingEditorText.prefix(2800)),
            relatedFilePath: filePath
        )
        persistStateToDisk()
        addCodingMessage(role: .system, content: "Stored a memory checkpoint for \(codingRelativePath(filePath)).")
    }

    func codingRelativePath(_ absolutePath: String) -> String {
        let normalized = normalizeCodingPath(absolutePath)
        let root = normalizeCodingPath(codingWorkspaceRootPath)
        guard !root.isEmpty else { return normalized }
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        if normalized == root {
            return "."
        }
        if normalized.hasPrefix(rootWithSlash) {
            return String(normalized.dropFirst(rootWithSlash.count))
        }
        return normalized
    }

    func codingMemoryUsageEstimate() -> String {
        let messageBytes = codingMessages.reduce(0) { $0 + $1.content.count }
        let memoryBytes = codingMemoryRecords.reduce(0) { $0 + $1.summary.count + $1.detail.count }
        let totalMB = Double(messageBytes + memoryBytes) / 1_048_576.0
        return String(format: "%.2f MB local coding memory", totalMB)
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
        let queueBytes = promptQueue.reduce(into: 0) { total, item in
            var itemBytes = item.prompt.count
            if let output = item.output {
                itemBytes += output.summary.count
                itemBytes += output.content?.count ?? 0
                itemBytes += output.podcastAudio?.bytes ?? 0
            }
            total += itemBytes
        }
        let codingBytes = codingMessages.reduce(0) { $0 + $1.content.count }
            + codingMemoryRecords.reduce(0) { $0 + $1.summary.count + $1.detail.count }
        let totalKB = max(1, (notesBytes + queueBytes + codingBytes) / 1024)
        return "~\(totalKB) KB local memory profile"
    }

    var surveyAnswerCount: Int {
        surveyAnswers.count
    }

    var surveyCompletionPercent: Int {
        if let survey {
            return max(0, min(100, survey.progress.percent))
        }
        let total = max(1, localSurveyTotal())
        return Int((Double(surveyAnswers.count) / Double(total)) * 100.0)
    }

    var isPrimarySurveyComplete: Bool {
        if let survey {
            if survey.question == nil || survey.progress.percent >= 100 {
                return true
            }
        }
        if surveyExpansionActive {
            return false
        }
        return surveyAnswers.count >= max(34, localSurveyTotal())
    }

    var isJobRadarReady: Bool {
        isPrimarySurveyComplete
    }

    var modelAutofillMinimumSurveyAnswers: Int {
        Self.minimumSurveyAnswersForModelAutofill
    }

    var isModelAutofillUnlocked: Bool {
        surveyAnswers.count >= Self.minimumSurveyAnswersForModelAutofill
    }

    var modelAutofillSurveyAnswersRemaining: Int {
        max(0, Self.minimumSurveyAnswersForModelAutofill - surveyAnswers.count)
    }

    var isAdditionalSurveyPassActive: Bool {
        surveyExpansionActive
    }

    var isGuidedLearningRuntimeActive: Bool {
        guidedLearningActivated && isPrimarySurveyComplete
    }

    var selectedTravelLocation: SavedTravelLocation? {
        guard let selectedTravelLocationID else { return nil }
        return savedTravelLocations.first(where: { $0.id == selectedTravelLocationID })
    }

    var activeTravelItineraryLocations: [SavedTravelLocation] {
        activeTravelItinerary.locationIDs.compactMap { id in
            savedTravelLocations.first(where: { $0.id == id })
        }
    }

    func addSavedTravelLocation(name: String, query: String, notes: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty else { return }
        let location = SavedTravelLocation(
            id: UUID().uuidString,
            name: trimmedName,
            googleMapsQuery: trimmedQuery,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: isoTimestamp()
        )
        savedTravelLocations.insert(location, at: 0)
        selectedTravelLocationID = location.id
        persistStateToDisk()
        appendOutput("Saved travel location: \(trimmedName)")
    }

    func updateSavedTravelLocation(id: String, name: String, query: String, notes: String) {
        guard let index = savedTravelLocations.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedQuery.isEmpty else { return }
        savedTravelLocations[index].name = trimmedName
        savedTravelLocations[index].googleMapsQuery = trimmedQuery
        savedTravelLocations[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        persistStateToDisk()
        appendOutput("Updated travel location: \(trimmedName)")
    }

    func removeSavedTravelLocation(id: String) {
        savedTravelLocations.removeAll { $0.id == id }
        activeTravelItinerary.locationIDs.removeAll { $0 == id }
        activeTravelItinerary.updatedAt = isoTimestamp()
        if selectedTravelLocationID == id {
            selectedTravelLocationID = savedTravelLocations.first?.id
        }
        persistStateToDisk()
        appendOutput("Removed travel location from the saved list.")
    }

    func addLocationToTravelItinerary(_ id: String) {
        guard activeTravelItinerary.locationIDs.contains(id) == false else { return }
        activeTravelItinerary.locationIDs.append(id)
        activeTravelItinerary.updatedAt = isoTimestamp()
        persistStateToDisk()
        appendOutput("Added location to itinerary.")
    }

    func removeLocationFromTravelItinerary(_ id: String) {
        activeTravelItinerary.locationIDs.removeAll { $0 == id }
        activeTravelItinerary.updatedAt = isoTimestamp()
        persistStateToDisk()
        appendOutput("Removed location from itinerary.")
    }

    func moveTravelItineraryLocations(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = activeTravelItinerary.locationIDs
        let moving = fromOffsets.map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            reordered.remove(at: index)
        }
        reordered.insert(contentsOf: moving, at: min(toOffset, reordered.count))
        activeTravelItinerary.locationIDs = reordered
        activeTravelItinerary.updatedAt = isoTimestamp()
        persistStateToDisk()
    }

    func updateTravelItineraryTitle(_ title: String) {
        activeTravelItinerary.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Travel itinerary"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTravelItinerary.updatedAt = isoTimestamp()
        persistStateToDisk()
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    func appendOutput(_ line: String) {
        let sanitized = SensitiveDataRedactor.redact(line)
        systemOutput.insert(String(sanitized.prefix(280)), at: 0)
        if systemOutput.count > 40 {
            systemOutput = Array(systemOutput.prefix(40))
        }
        forwardRuntimeTelemetryIfNeeded(String(sanitized.prefix(280)))
    }

    func acknowledgeSafetyGuidance() {
        if safetyModeActive {
            safetyModeActive = false
        }
        appendOutput("Safety guidance acknowledged. Atlas remains in preventive monitoring mode.")
    }

    private struct SafetySignal {
        let score: Int
        let categories: [String]
        let holdQueue: Bool
    }

    @discardableResult
    private func evaluateSuspiciousPattern(input: String, source: String) -> SafetySignal {
        let normalized = input.lowercased()
        var score = 0
        var categories: [String] = []

        let violenceTerms = [
            "kill", "shoot", "stab", "bomb", "attack", "assassinate", "slaughter",
            "להרוג", "לירות", "לדקור", "לפוצץ", "פיגוע", "לתקוף"
        ]
        let extremistTerms = [
            "isis", "daesh", "al-qaeda", "neo-nazi", "race war", "martyrdom", "terror",
            "דאעש", "אל קאעידה", "נאצי", "טרור", "ג'יהאד"
        ]
        let dehumanizationTerms = [
            "subhuman", "vermin", "exterminate", "cleanse them", "parasites",
            "תת-אדם", "להשמיד", "לטהר", "שרצים"
        ]
        let operationalHarmTerms = [
            "how to make bomb", "build a bomb", "attack plan", "manifesto", "evade police", "illegal gun",
            "איך להכין פצצה", "להכין פצצה", "תכנית פיגוע", "להתחמק מהמשטרה", "נשק לא חוקי"
        ]

        if containsAny(normalized, violenceTerms) {
            score += 3
            categories.append("violence")
        }
        if containsAny(normalized, extremistTerms) {
            score += 3
            categories.append("extremism")
        }
        if containsAny(normalized, dehumanizationTerms) {
            score += 2
            categories.append("dehumanization")
        }
        if containsAny(normalized, operationalHarmTerms) {
            score += 4
            categories.append("operational_harm")
        }

        let signal = SafetySignal(
            score: score,
            categories: categories,
            holdQueue: score >= 6
        )

        if score == 0 {
            consecutiveSafeInputs += 1
            if consecutiveSafeInputs >= 3 {
                safetyRiskScore = 0
                safetyInterventionSummary = "No active safety concern signals."
                safetyModeActive = false
            }
            return signal
        }

        consecutiveSafeInputs = 0
        safetyRiskScore = max(safetyRiskScore, score)
        safetyModeActive = score >= 6

        let categoryText = categories.joined(separator: ", ")
        safetyInterventionSummary = "Preventive support active (\(source)): \(categoryText). Atlas is restricted to de-escalation and safe guidance."

        appendOutput("Safety intervention triggered (\(source)). Atlas cannot assist with violence, extremism, or harmful operational planning.")
        appendOutput("De-escalation protocol: pause for 2 minutes, slow breathing, and contact a trusted person before taking action.")
        appendOutput("Rehabilitation protocol: redirect energy into constructive mission steps, community service, and long-horizon wealth-building actions.")
        appendOutput("If there is immediate danger to you or others, call local emergency services now.")

        let safetyActions: [ExecutionAction] = [
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Immediate",
                title: "Regulate and De-escalate",
                details: "Do a 2-minute breathing reset and physical pause before any further input.",
                priority: 0,
                source: "safety_guard",
                completed: false
            ),
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Today",
                title: "Reconnect with a Trusted Human",
                details: "Message or call one trusted person and state one constructive goal for today.",
                priority: 0,
                source: "safety_guard",
                completed: false
            ),
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Week",
                title: "Constructive Mission Redirect",
                details: "Convert current intensity into a lawful, pro-social project that improves your life or community.",
                priority: 1,
                source: "safety_guard",
                completed: false
            ),
        ]

        executionActions = safetyActions + Array(executionActions.prefix(4))
        persistStateToDisk()
        return signal
    }

    private func forwardRuntimeTelemetryIfNeeded(_ line: String) {
        guard shouldForwardRuntimeEvent(line) else { return }
        pendingRuntimeTelemetry.append(line)
        if pendingRuntimeTelemetry.count > 24 {
            pendingRuntimeTelemetry = Array(pendingRuntimeTelemetry.suffix(24))
        }
        guard runtimeTelemetryTask == nil else { return }
        runtimeTelemetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self?.flushRuntimeTelemetry()
        }
    }

    private func shouldForwardRuntimeEvent(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("failed")
            || lower.contains("error")
            || lower.contains("unavailable")
            || lower.contains("missing")
            || lower.contains("cancelled")
            || lower.contains("pending")
    }

    private func flushRuntimeTelemetry() async {
        runtimeTelemetryTask = nil
        guard !pendingRuntimeTelemetry.isEmpty else { return }
        guard Date().timeIntervalSince(lastRuntimeTelemetryAt) >= 45 else {
            runtimeTelemetryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await self?.flushRuntimeTelemetry()
            }
            return
        }

        let payload = pendingRuntimeTelemetry
        pendingRuntimeTelemetry.removeAll(keepingCapacity: true)

        do {
            try await api.submitFeedback(
                category: "bug",
                severity: "normal",
                message: "IOS_RUNTIME_TELEMETRY\n" + payload.joined(separator: "\n"),
                tags: ["ios", "runtime", "auto-report"],
                source: "ios_runtime_auto"
            )
            lastRuntimeTelemetryAt = Date()
        } catch {
            // Keep latest items for a retry without interrupting user flow.
            pendingRuntimeTelemetry = Array((payload + pendingRuntimeTelemetry).suffix(24))
        }
    }

    private func runPromptQueueLoop() async {
        while !Task.isCancelled {
            guard let index = promptQueue.firstIndex(where: { $0.status == .queued }) else {
                break
            }

            if shouldPauseQueueForInternetReconnect {
                let requestedOutputType = promptQueue[index].outputType ?? .standard
                markQueueItemWaitingForInternetReconnect(at: index)
                logQueueReconnectWaitIfNeeded(for: requestedOutputType)
                try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                continue
            }
            hasLoggedQueueReconnectWait = false

            if let runtimeIssue = runtimeAccessBlockingIssue() {
                promptQueue[index].status = .failed
                promptQueue[index].completedAt = Date()
                promptQueue[index].lastCheckpointAt = Date()
                promptQueue[index].progress = 1.0
                promptQueue[index].checkpointNote = "AI runtime blocked by account/billing policy."
                promptQueue[index].output = nil
                promptQueue[index].retryCount = nil
                promptQueue[index].errorMessage = runtimeIssue
                persistPromptQueueToDisk()
                appendOutput(runtimeIssue)
                continue
            }

            promptQueue[index].status = .running
            promptQueue[index].startedAt = promptQueue[index].startedAt ?? Date()
            promptQueue[index].completedAt = nil
            promptQueue[index].lastCheckpointAt = Date()
            promptQueue[index].progress = max(promptQueue[index].progress ?? 0.0, 0.05)
            promptQueue[index].checkpointNote = "Starting AI model pass."
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
                            note: "Checkpoint saved during processing."
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
            let requestedOutputType = item.outputType ?? .standard
            let requestedQuizDifficulty = requestedOutputType == .quiz
                ? (item.quizDifficulty ?? .medium)
                : nil
            let scopeLane = item.workspaceLane
            let scopeSessionID = item.workspaceSessionID
            let scopedMemoryHighlights = queueMemoryHighlights(
                for: scopeLane,
                sessionID: scopeSessionID,
                limit: 6
            )
            let lessonHighlights = lessonMemoryHighlights(limit: 4)
            let queueMemoryHighlights = uniqueOrdered(scopedMemoryHighlights + lessonHighlights)
            let queueMemorySnapshot = queueMemoryHighlights.isEmpty
                ? "- No strong workspace memory signals yet."
                : queueMemoryHighlights.map { "- \($0)" }.joined(separator: "\n")
            let surveySnapshotLimit = requestedOutputType == .quiz ? 40 : 24
            let surveySnapshot = queueSurveySnapshot(for: scopeLane, limit: surveySnapshotLimit)
            let generationFailureDefault = "Cloud AI runtime unavailable after \(Self.queueRuntimeRetryLimit) retries. No AI response was generated."
            var generationFailureMessage: String? = nil
            var generationFailureRetryable = true

            let cloudResult = await serverDrivenQueueOutput(
                item: item,
                prompt: boundedPrompt,
                notes: boundedNotes,
                outputType: requestedOutputType,
                quizDifficulty: requestedQuizDifficulty,
                workspaceMemorySnapshot: queueMemorySnapshot,
                surveySnapshot: surveySnapshot,
                lessonHighlights: lessonHighlights
            )
            let modelOutput: LocalReasoningOutput?
            switch cloudResult {
            case let .success(output):
                modelOutput = output
            case let .retryableFailure(message):
                generationFailureMessage = message
                generationFailureRetryable = true
                modelOutput = nil
            case let .terminalFailure(message):
                generationFailureMessage = message
                generationFailureRetryable = false
                modelOutput = nil
            }

            guard let output = modelOutput else {
                checkpointTask.cancel()

                let sanitizedFailureMessage = generationFailureMessage
                    .map {
                        String(
                            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                .prefix(220)
                        )
                    }
                    .flatMap { $0.isEmpty ? nil : $0 }
                let resolvedFailureMessage = sanitizedFailureMessage ?? generationFailureDefault

                if !generationFailureRetryable {
                    promptQueue[index].status = .failed
                    promptQueue[index].completedAt = Date()
                    promptQueue[index].lastCheckpointAt = Date()
                    promptQueue[index].progress = 1.0
                    promptQueue[index].checkpointNote = "Generation failed."
                    promptQueue[index].output = nil
                    promptQueue[index].retryCount = nil
                    promptQueue[index].errorMessage = resolvedFailureMessage
                    persistPromptQueueToDisk()
                    appendOutput("\(requestedOutputType.title) generation failed: \(resolvedFailureMessage)")
                    continue
                }

                if shouldPauseQueueForInternetReconnect {
                    markQueueItemWaitingForInternetReconnect(at: index)
                    logQueueReconnectWaitIfNeeded(for: requestedOutputType)
                    try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                    continue
                }

                let retryAttempt = (promptQueue[index].retryCount ?? 0) + 1
                if retryAttempt <= Self.queueRuntimeRetryLimit {
                    promptQueue[index].retryCount = retryAttempt
                    promptQueue[index].status = .queued
                    promptQueue[index].lastCheckpointAt = Date()
                    let currentProgress = promptQueue[index].progress ?? 0.08
                    promptQueue[index].progress = max(0.04, min(0.55, currentProgress * 0.72))
                    promptQueue[index].checkpointNote = "Runtime unavailable. Retrying \(retryAttempt)/\(Self.queueRuntimeRetryLimit)..."
                    promptQueue[index].errorMessage = nil
                    persistPromptQueueToDisk()
                    appendOutput("Cloud AI runtime unavailable for \(requestedOutputType.title). Retrying \(retryAttempt)/\(Self.queueRuntimeRetryLimit).")
                    try? await Task.sleep(nanoseconds: queueRuntimeRetryNanoseconds(for: retryAttempt))
                    continue
                }

                promptQueue[index].status = .failed
                promptQueue[index].completedAt = Date()
                promptQueue[index].lastCheckpointAt = Date()
                promptQueue[index].progress = 1.0
                promptQueue[index].checkpointNote = "Cloud AI runtime unavailable after retries."
                promptQueue[index].output = nil
                promptQueue[index].retryCount = Self.queueRuntimeRetryLimit
                promptQueue[index].errorMessage = resolvedFailureMessage
                persistPromptQueueToDisk()
                appendOutput("Cloud AI runtime unavailable after \(Self.queueRuntimeRetryLimit) retries. Queue item marked failed with no synthesized response.")
                let cooldown = queueCooldownNanoseconds()
                if cooldown > 0 {
                    try? await Task.sleep(nanoseconds: cooldown)
                }
                continue
            }
            checkpointTask.cancel()
            promptQueue[index].status = .done
            promptQueue[index].completedAt = Date()
            promptQueue[index].lastCheckpointAt = Date()
            promptQueue[index].progress = 1.0
            promptQueue[index].checkpointNote = "Completed and saved."
            promptQueue[index].output = output
            promptQueue[index].retryCount = nil
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()
            let outputDescriptor: String = {
                if (output.outputType ?? .standard) == .quiz,
                   let difficulty = output.quizDifficulty ?? requestedQuizDifficulty
                {
                    return "\((output.outputType ?? .standard).title) · \(difficulty.title)"
                }
                return (output.outputType ?? .standard).title
            }()
            appendOutput("AI model completed (\(outputDescriptor)). Next action: \(output.nextAction)")

            let cooldown = queueCooldownNanoseconds()
            if cooldown > 0 {
                try? await Task.sleep(nanoseconds: cooldown)
            }
        }

        queueWorkerTask = nil
        rebuildInsightsAndExecutionPlan()
        await refreshCommandModelBrief()
        await refreshWorkspaceModelBrief()
        await refreshFeed()
    }

    private struct LocalModelQueueResponse: Decodable {
        let summary: String
        let nextAction: String
        let confidence: Double?
        let content: String?
        let outputType: String?
        let quizDifficulty: String?

        enum CodingKeys: String, CodingKey {
            case summary
            case nextAction = "next_action"
            case confidence
            case content
            case outputType = "output_type"
            case quizDifficulty = "quiz_difficulty"
        }
    }

    private struct LocalModelFeedItem: Decodable {
        let title: String
        let summary: String
        let whyNow: String
        let priority: String

        enum CodingKeys: String, CodingKey {
            case title
            case summary
            case whyNow = "why_now"
            case priority
        }
    }

    private struct LocalModelFeedEnvelope: Decodable {
        let items: [LocalModelFeedItem]
    }

    private enum LocalInferenceReasoningDomain: Equatable {
        case general
        case briefing
        case structuredJSON
        case coding

        var styleInstruction: String {
            switch self {
            case .general:
                return "Produce high-signal operational output with concrete, testable next steps."
            case .briefing:
                return "Produce one concise executive brief paragraph with clear leverage + risk signal."
            case .structuredJSON:
                return "Return ONLY valid JSON that matches the requested schema. No prose or markdown."
            case .coding:
                return "Produce precise implementation guidance, commands, and quick verification steps."
            }
        }

        var includeGlobalContext: Bool {
            true
        }

        var contextMaxLength: Int {
            switch self {
            case .general:
                return 4200
            case .briefing:
                return 2200
            case .structuredJSON:
                return 2600
            case .coding:
                return 1800
            }
        }
    }

    private struct LocalInferenceReasoningProfile {
        let analysisPasses: Int
        let candidateTimeoutSeconds: Int
        let synthesisTimeoutSeconds: Int
        let candidateMaxTokens: Int
        let synthesisMaxTokens: Int
    }

    private struct OpenAIChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct OpenAIChatRequest: Encodable {
        let model: String
        let messages: [OpenAIChatMessage]
        let temperature: Double
        let maxTokens: Int
        let reasoningEffort: String?
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case reasoningEffort = "reasoning_effort"
            case stream
        }
    }

    private struct OpenAIChatChoice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        let message: Message?
        let text: String?
    }

    private struct OpenAIChatResponse: Decodable {
        let choices: [OpenAIChatChoice]
    }

    private struct GeminiInlineData: Codable {
        let mimeType: String?
        let data: String?
    }

    private struct GeminiTextPart: Codable {
        let text: String?
        let inlineData: GeminiInlineData?

        init(text: String?, inlineData: GeminiInlineData? = nil) {
            self.text = text
            self.inlineData = inlineData
        }
    }

    private struct GeminiMessageContent: Codable {
        let role: String?
        let parts: [GeminiTextPart]
    }

    private struct GeminiSystemInstruction: Encodable {
        let parts: [GeminiTextPart]
    }

    private struct GeminiGenerationConfig: Encodable {
        let temperature: Double
        let maxOutputTokens: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case maxOutputTokens
        }
    }

    private struct GeminiGenerateRequest: Encodable {
        let systemInstruction: GeminiSystemInstruction?
        let contents: [GeminiMessageContent]
        let generationConfig: GeminiGenerationConfig

        enum CodingKeys: String, CodingKey {
            case systemInstruction
            case contents
            case generationConfig
        }
    }

    private struct GeminiGenerateResponse: Decodable {
        struct Candidate: Decodable {
            let content: GeminiMessageContent?
        }

        let candidates: [Candidate]?
    }

    private struct GeminiSpeechVoiceConfig: Encodable {
        struct PrebuiltVoiceConfig: Encodable {
            let voiceName: String
        }

        let prebuiltVoiceConfig: PrebuiltVoiceConfig
    }

    private struct GeminiSpeechConfig: Encodable {
        let voiceConfig: GeminiSpeechVoiceConfig
    }

    private struct GeminiTTSGenerationConfig: Encodable {
        let responseModalities: [String]
        let speechConfig: GeminiSpeechConfig
    }

    private struct GeminiTTSGenerateRequest: Encodable {
        let contents: [GeminiMessageContent]
        let generationConfig: GeminiTTSGenerationConfig
    }

    private actor LocalInferenceTransport {
        private let session: URLSession

        init() {
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = 22
            config.timeoutIntervalForResource = 34
            config.httpMaximumConnectionsPerHost = 4
            config.httpShouldUsePipelining = true
            config.httpAdditionalHeaders = [
                "Accept-Encoding": "gzip, deflate, br",
                "Connection": "keep-alive",
            ]
            if #available(iOS 13.0, macOS 10.15, *) {
                config.tlsMinimumSupportedProtocolVersion = .TLSv12
            }
            session = URLSession(configuration: config)
        }

        func requestData(for request: URLRequest, maxRetries: Int) async -> Data? {
            var attempt = 0
            while !Task.isCancelled {
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { return nil }
                    if (200 ... 299).contains(http.statusCode) {
                        return data
                    }
                    guard attempt < maxRetries, shouldRetry(statusCode: http.statusCode) else {
                        return nil
                    }
                    let delay = retryDelaySeconds(httpResponse: http, attempt: attempt)
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(max(0.0, delay) * 1_000_000_000))
                } catch {
                    guard attempt < maxRetries else { return nil }
                    let delay = min(4.0, 0.35 * pow(2.0, Double(attempt)))
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            return nil
        }

        private func shouldRetry(statusCode: Int) -> Bool {
            statusCode == 408 || statusCode == 409 || statusCode == 429 || (500 ... 599).contains(statusCode)
        }

        private func retryDelaySeconds(httpResponse: HTTPURLResponse, attempt: Int) -> Double {
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let retryAfterSeconds = Double(retryAfter),
               retryAfterSeconds > 0
            {
                return min(6.0, retryAfterSeconds)
            }
            return min(4.0, 0.35 * pow(2.0, Double(attempt)))
        }
    }

    private actor LocalInferenceResponseCache {
        private struct CacheEntry {
            let value: String
            let expiresAt: Date
        }

        private let defaultTTL: TimeInterval
        private var entries: [String: CacheEntry] = [:]
        private var inflight: [String: Task<String?, Never>] = [:]

        init(defaultTTL: TimeInterval) {
            self.defaultTTL = max(20, defaultTTL)
        }

        func resolve(
            key: String,
            ttl: TimeInterval? = nil,
            operation: @escaping @Sendable () async -> String?
        ) async -> String? {
            let now = Date()
            purgeExpired(now: now)

            if let cached = entries[key], cached.expiresAt > now {
                return cached.value
            }

            if let running = inflight[key] {
                return await running.value
            }

            let effectiveTTL = max(10, ttl ?? defaultTTL)
            let task = Task { await operation() }
            inflight[key] = task
            let value = await task.value
            inflight.removeValue(forKey: key)

            if let value, !value.isEmpty {
                entries[key] = CacheEntry(
                    value: value,
                    expiresAt: Date().addingTimeInterval(effectiveTTL)
                )
            }
            return value
        }

        private func purgeExpired(now: Date) {
            entries = entries.filter { $0.value.expiresAt > now }
        }
    }

    nonisolated private static func localInferenceCacheKey(
        providerID: String,
        model: String,
        endpointID: String,
        prompt: String,
        systemPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) -> String {
        let raw = [
            providerID,
            model,
            endpointID,
            String(format: "%.4f", temperature),
            "\(maxTokens)",
            systemPrompt,
            prompt
        ].joined(separator: "||")
        return sha256Hex(raw)
    }

    nonisolated private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func localLLMRuntimeStatusLine() -> String {
        let host = AppEnvironment.apiBaseURL.host ?? "api-host"
        let sessionStatus: String
        if !isSignedIn {
            sessionStatus = "locked: sign in required"
        } else if !billingAccessEnabled {
            sessionStatus = "locked: add payment method"
        } else {
            sessionStatus = "session + billing active"
        }
        return "Runtime policy: server-managed /v1/chat on \(host). Gemini (\(Self.geminiReasoningModel)) primary with GPT-5.2 high-reasoning fallback. \(sessionStatus)."
    }

    private func guidedLearningRuntimeStatusLine() -> String {
        let activation = isGuidedLearningRuntimeActive ? "active" : "locked"
        let ollamaHost = guidedLearningOllamaEndpointURL?.host ?? "invalid-endpoint"
        let kiwixHost = guidedLearningKiwixBaseURL?.host ?? "invalid-endpoint"
        return "Guided learning \(activation). Kiwix host: \(kiwixHost) · Ollama host: \(ollamaHost) · model: \(guidedLearningOllamaModelName)."
    }

    private func readLocalInferenceAPIKey(for provider: LocalInferenceProvider) -> String? {
        if let scoped = readLocalInferenceAPIKey(account: keychainAccount(for: provider)) {
            return scoped
        }
        return readLocalInferenceAPIKey(account: LocalInferenceDefaults.legacyKeychainAccount)
    }

    private func readLocalInferenceAPIKey(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalInferenceDefaults.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
#if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        guard let decoded = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func storeLocalInferenceAPIKey(_ apiKey: String, for provider: LocalInferenceProvider) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        let account = keychainAccount(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalInferenceDefaults.keychainService,
            kSecAttrAccount as String: account,
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            return false
        }

        var create: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalInferenceDefaults.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
#if os(iOS)
        create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
#endif
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        if addStatus == errSecSuccess {
            _ = deleteLocalInferenceAPIKey(account: LocalInferenceDefaults.legacyKeychainAccount)
        }
        return addStatus == errSecSuccess
    }

    private func deleteLocalInferenceAPIKey(for provider: LocalInferenceProvider) -> Bool {
        let scopedDeleted = deleteLocalInferenceAPIKey(account: keychainAccount(for: provider))
        let legacyDeleted = deleteLocalInferenceAPIKey(account: LocalInferenceDefaults.legacyKeychainAccount)
        return scopedDeleted && legacyDeleted
    }

    private func deleteLocalInferenceAPIKey(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: LocalInferenceDefaults.keychainService,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func maskedAPIKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return String(repeating: "•", count: trimmed.count) }
        let suffix = String(trimmed.suffix(4))
        return "••••\(suffix)"
    }

    private func modelDrivenQueueOutput(
        prompt: String,
        notes: [UserNote],
        outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonHighlights: [String]
    ) async -> LocalReasoningOutput? {
        guard localInferenceEnabled else { return nil }

        let notesSnapshot = notes
            .prefix(16)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: 180))" }
            .joined(separator: "\n")
        let historySnapshot = promptQueue
            .suffix(8)
            .compactMap { item -> String? in
                guard let output = item.output else { return nil }
                let typeLabel = output.outputType?.title ?? item.outputType?.title ?? "Standard"
                return "- [\(typeLabel)] \(output.summary)"
            }
            .joined(separator: "\n")
        let lessonSnapshot = lessonHighlights.isEmpty
            ? "- No explicit user lessons captured yet."
            : lessonHighlights.map { "- \($0)" }.joined(separator: "\n")

        if outputType == .quiz {
            return await modelDrivenFrontierQuizOutput(
                prompt: prompt,
                quizDifficulty: quizDifficulty ?? .medium,
                notesSnapshot: notesSnapshot,
                historySnapshot: historySnapshot,
                workspaceMemorySnapshot: workspaceMemorySnapshot,
                surveySnapshot: surveySnapshot,
                lessonSnapshot: lessonSnapshot
            )
        }

        let instruction = queueOutputInstruction(
            for: outputType,
            quizDifficulty: nil,
            prompt: prompt,
            notesSnapshot: notesSnapshot,
            historySnapshot: historySnapshot,
            workspaceMemorySnapshot: workspaceMemorySnapshot,
            surveySnapshot: surveySnapshot,
            lessonSnapshot: lessonSnapshot
        )

        let providerOrder = preferredInferenceProviders

        for provider in providerOrder {
            guard let raw = await requestLocalModelResponse(
                prompt: instruction,
                timeoutSeconds: 20,
                domain: .structuredJSON,
                providerOverride: provider,
                modelOverride: provider.defaultModel
            ) else {
                continue
            }

            if let parsed: LocalModelQueueResponse = Self.decodeModelJSON(raw) {
                if let output = queueOutputFromParsed(
                    parsed: parsed,
                    outputType: outputType,
                    quizDifficulty: nil,
                    modelLabel: "frontier-\(provider.defaultModel)"
                ) {
                    return output
                }
            }

            if let loose = queueOutputFromLooseRaw(
                raw: raw,
                outputType: outputType,
                quizDifficulty: nil,
                modelLabel: "frontier-\(provider.defaultModel)"
            ) {
                return loose
            }
        }
        return nil
    }

    private enum PodcastGenerationResult {
        case success(LocalReasoningOutput)
        case retryableFailure(String)
        case terminalFailure(String)
    }

    private enum CloudQueueGenerationResult {
        case success(LocalReasoningOutput)
        case retryableFailure(String)
        case terminalFailure(String)
    }

    private struct PodcastScriptPlanResponse: Decodable {
        let outputType: String?
        let summary: String
        let nextAction: String
        let confidence: Double?
        let title: String?
        let script: String
        let voiceName: String?

        enum CodingKeys: String, CodingKey {
            case outputType = "output_type"
            case summary
            case nextAction = "next_action"
            case confidence
            case title
            case script
            case voiceName = "voice_name"
        }
    }

    private func serverDrivenQueueOutput(
        item: PromptQueueItem,
        prompt: String,
        notes: [UserNote],
        outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonHighlights: [String]
    ) async -> CloudQueueGenerationResult {
        let notesSnapshot = notes
            .prefix(14)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: 180))" }
            .joined(separator: "\n")
        let historySnapshot = promptQueue
            .suffix(8)
            .compactMap { item -> String? in
                guard let output = item.output else { return nil }
                let typeLabel = output.outputType?.title ?? item.outputType?.title ?? "Standard"
                return "- [\(typeLabel)] \(output.summary)"
            }
            .joined(separator: "\n")
        let lessonSnapshot = lessonHighlights.isEmpty
            ? "- No explicit user lessons captured yet."
            : lessonHighlights.map { "- \($0)" }.joined(separator: "\n")
        let scopeLabel = item.workspaceLane?.title ?? "Concierge"
        let scopeSession = item.workspaceSessionID ?? item.conciergeSessionID ?? "default"

        let instruction = serverQueueInstruction(
            outputType: outputType,
            quizDifficulty: quizDifficulty,
            prompt: prompt,
            scopeLabel: scopeLabel,
            scopeSession: scopeSession,
            notesSnapshot: notesSnapshot.isEmpty ? "- No notes saved." : notesSnapshot,
            historySnapshot: historySnapshot.isEmpty ? "- No prior outputs." : historySnapshot,
            workspaceMemorySnapshot: workspaceMemorySnapshot,
            surveySnapshot: surveySnapshot,
            lessonSnapshot: lessonSnapshot
        )
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        let sessionID = item.workspaceSessionID ?? item.conciergeSessionID

        do {
            let response = try await api.chat(
                sessionID: sessionID,
                text: instruction,
                locale: locale,
                preferredFormat: "structured_plan",
                responseDepth: "deep",
                responseTone: "executive",
                includeProactive: false
            )

            let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                return .retryableFailure("Cloud runtime returned an empty response.")
            }

            let modelLabel = "cloud-v1-chat"
            if let parsed: LocalModelQueueResponse = Self.decodeModelJSON(reply),
               let output = queueOutputFromParsed(
                   parsed: parsed,
                   outputType: outputType,
                   quizDifficulty: quizDifficulty,
                   modelLabel: modelLabel
               )
            {
                return .success(output)
            }

            if let loose = queueOutputFromLooseRaw(
                raw: reply,
                outputType: outputType,
                quizDifficulty: quizDifficulty,
                modelLabel: modelLabel
            ) {
                return .success(loose)
            }

            if outputType == .standard {
                let compact = Self.trimForDisplay(
                    sanitizeWorkspaceMemoryValue(reply, maxLength: 8_000),
                    maxChars: 8_000
                )
                let lines = compact
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let summary = sanitizeWorkspaceMemoryValue(
                    lines.first ?? String(compact.prefix(280)),
                    maxLength: 420
                )
                let nextAction = lines
                    .first(where: { $0.lowercased().contains("next action") })
                    .flatMap { line -> String? in
                        if let colonIndex = line.firstIndex(of: ":") {
                            let action = String(line[line.index(after: colonIndex)...])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            return action.isEmpty ? nil : action
                        }
                        return line.isEmpty ? nil : line
                    }
                    ?? "Execute the first concrete step from this response in the next 25 minutes."
                return .success(
                    LocalReasoningOutput(
                        model: modelLabel,
                        summary: summary,
                        nextAction: sanitizeWorkspaceMemoryValue(nextAction, maxLength: 220),
                        confidence: 0.67,
                        generatedAt: Date(),
                        outputType: .standard,
                        quizDifficulty: nil,
                        content: nil
                    )
                )
            }

            return .retryableFailure("Cloud runtime returned unexpected \(outputType.title) format.")
        } catch let APIError.server(status, message) {
            let sanitized = sanitizeWorkspaceMemoryValue(message, maxLength: 220)
            switch status {
            case 401:
                return .terminalFailure("Cloud AI requires an active signed-in account session.")
            case 402:
                return .terminalFailure("Billing setup is required before cloud AI chat can run. Add a payment method in Plans.")
            case 403:
                return .terminalFailure("Cloud chat request was rejected by server policy. Verify session/origin settings.")
            case 404:
                return .terminalFailure("Cloud chat route /v1/chat is unavailable on the backend.")
            case 429:
                return .retryableFailure("Cloud runtime is rate-limited (429). Retrying.")
            case 500 ... 599:
                return .retryableFailure("Cloud runtime server error (\(status)). Retrying.")
            default:
                return .retryableFailure("Cloud runtime failed (\(status)): \(sanitized)")
            }
        } catch let apiError as APIError {
            return .terminalFailure(apiError.localizedDescription)
        } catch {
            return .retryableFailure("Cloud runtime request failed: \(error.localizedDescription)")
        }
    }

    private func serverQueueInstruction(
        outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        prompt: String,
        scopeLabel: String,
        scopeSession: String,
        notesSnapshot: String,
        historySnapshot: String,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonSnapshot: String
    ) -> String {
        switch outputType {
        case .standard:
            return """
            You are Atlas cloud execution intelligence.
            Produce concise, high-signal output for one queue request.

            Output format:
            Summary: <one sentence, max 220 chars>
            Next action: <one sentence, max 160 chars>
            Why now: <optional one sentence, max 160 chars>

            Context:
            Scope: \(scopeLabel) | Session: \(scopeSession)
            Prompt: \(prompt)
            Notes:
            \(notesSnapshot)
            Workspace memory:
            \(workspaceMemorySnapshot)
            Lesson signals:
            \(lessonSnapshot)
            Survey signals:
            \(surveySnapshot)
            Prior outputs:
            \(historySnapshot)
            """
        case .quiz:
            let difficulty = quizDifficulty ?? .medium
            return """
            You are Atlas cloud rehearsal intelligence.
            Generate a 6-question quiz at \(difficulty.rawValue) difficulty.

            Required format (plain text):
            Q1: ...
            Choices: A) ... | B) ... | C) ... | D) ...
            Correct: A|B|C|D
            Why it matters: ...
            (repeat through Q6)

            Rules:
            - Exactly 6 questions.
            - At least 2 questions must use lesson signals when available.
            - Questions must reflect prompt + survey + workspace memory.
            - Keep total output under 6000 chars.

            Context:
            Scope: \(scopeLabel) | Session: \(scopeSession)
            Prompt: \(prompt)
            Notes:
            \(notesSnapshot)
            Workspace memory:
            \(workspaceMemorySnapshot)
            Lesson signals:
            \(lessonSnapshot)
            Survey signals:
            \(surveySnapshot)
            Prior outputs:
            \(historySnapshot)
            """
        case .podcast:
            return """
            You are Atlas cloud script intelligence.
            Return concise show-notes text only with this format:
            Summary: ...
            Next action: ...
            Script:
            Opening:
            Main Brief:
            Action Drill:
            Closing:

            Context:
            Scope: \(scopeLabel) | Session: \(scopeSession)
            Prompt: \(prompt)
            Notes:
            \(notesSnapshot)
            Workspace memory:
            \(workspaceMemorySnapshot)
            Lesson signals:
            \(lessonSnapshot)
            Survey signals:
            \(surveySnapshot)
            Prior outputs:
            \(historySnapshot)
            """
        }
    }

    private func modelDrivenPodcastOutput(
        prompt: String,
        notes: [UserNote],
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonHighlights: [String]
    ) async -> PodcastGenerationResult {
        let notesSnapshot = notes
            .prefix(16)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: 180))" }
            .joined(separator: "\n")
        let historySnapshot = promptQueue
            .suffix(8)
            .compactMap { item -> String? in
                guard let output = item.output else { return nil }
                let typeLabel = output.outputType?.title ?? item.outputType?.title ?? "Standard"
                return "- [\(typeLabel)] \(output.summary)"
            }
            .joined(separator: "\n")
        let lessonSnapshot = lessonHighlights.isEmpty
            ? "- No explicit user lessons captured yet."
            : lessonHighlights.map { "- \($0)" }.joined(separator: "\n")
        let instruction = podcastScriptInstruction(
            prompt: prompt,
            notesSnapshot: notesSnapshot,
            historySnapshot: historySnapshot,
            workspaceMemorySnapshot: workspaceMemorySnapshot,
            surveySnapshot: surveySnapshot,
            lessonSnapshot: lessonSnapshot
        )

        let stageOneProviders: [(provider: LocalInferenceProvider, model: String)] = [
            (.gemini, Self.geminiReasoningModel),
            (.openAICompatible, LocalInferenceProvider.openAICompatible.defaultModel),
        ]

        var stageOnePlan: PodcastScriptPlanResponse?
        var stageOneModelLabel = ""
        for stageOneProvider in stageOneProviders {
            guard let raw = await requestLocalModelResponse(
                prompt: instruction,
                timeoutSeconds: 28,
                domain: .structuredJSON,
                providerOverride: stageOneProvider.provider,
                modelOverride: stageOneProvider.model
            ),
            let parsed: PodcastScriptPlanResponse = Self.decodeModelJSON(raw)
            else {
                continue
            }

            let normalizedScript = parsed.script
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSummary = parsed.summary
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAction = parsed.nextAction
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOutputType = parsed.outputType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? "podcast"

            guard normalizedOutputType == "podcast",
                  !normalizedScript.isEmpty,
                  !normalizedSummary.isEmpty,
                  !normalizedAction.isEmpty
            else {
                continue
            }

            stageOnePlan = PodcastScriptPlanResponse(
                outputType: "podcast",
                summary: normalizedSummary,
                nextAction: normalizedAction,
                confidence: parsed.confidence,
                title: parsed.title,
                script: normalizedScript,
                voiceName: parsed.voiceName
            )
            stageOneModelLabel = stageOneProvider.model
            break
        }

        guard let plan = stageOnePlan else {
            return .retryableFailure(
                "Podcast script stage failed (Gemini 3 Flash + GPT fallback unavailable)."
            )
        }

        guard let geminiKey = localInferenceAPIKey(for: .gemini),
              !geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .terminalFailure(
                "Gemini API key missing. Add a Gemini key in Account > Model runtime to render podcast audio."
            )
        }

        let selectedVoice = plan.voiceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false ? plan.voiceName! : Self.geminiPodcastVoiceName
        guard let rendered = await Self.runGeminiTTSPrompt(
            model: Self.geminiPodcastTTSModel,
            apiKey: geminiKey,
            script: plan.script,
            voiceName: selectedVoice
        ) else {
            return .retryableFailure(
                "Podcast audio stage failed on \(Self.geminiPodcastTTSModel)."
            )
        }

        guard let normalizedAudio = normalizePodcastAudioPayload(
            audioData: rendered.data,
            mimeType: rendered.mimeType
        ) else {
            return .retryableFailure("Podcast audio payload was invalid or empty.")
        }

        guard let artifact = persistPodcastAudioArtifact(
            audioData: normalizedAudio.data,
            mimeType: normalizedAudio.mimeType,
            voiceName: selectedVoice,
            rawPCMByteCount: normalizedAudio.rawPCMByteCount
        ) else {
            return .terminalFailure("Podcast audio could not be saved on device.")
        }

        let confidence = min(1.0, max(0.0, plan.confidence ?? 0.74))
        return .success(
            LocalReasoningOutput(
                model: "podcast-pipeline[\(stageOneModelLabel) -> \(Self.geminiPodcastTTSModel)]",
                summary: sanitizeWorkspaceMemoryValue(plan.summary, maxLength: 420),
                nextAction: sanitizeWorkspaceMemoryValue(plan.nextAction, maxLength: 220),
                confidence: confidence,
                generatedAt: Date(),
                outputType: .podcast,
                quizDifficulty: nil,
                content: nil,
                podcastAudio: artifact
            )
        )
    }

    private func podcastScriptInstruction(
        prompt: String,
        notesSnapshot: String,
        historySnapshot: String,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonSnapshot: String
    ) -> String {
        """
        You are Atlas Podcast Planning Engine.
        Build a high-signal, concise podcast script from user context.

        Return ONLY valid JSON with this exact schema:
        {"output_type":"podcast","summary":"...","next_action":"...","confidence":0.0,"title":"...","voice_name":"Kore","script":"..."}

        Requirements:
        - output_type must be "podcast"
        - summary <= 280 chars
        - next_action <= 180 chars
        - confidence must be 0.0..1.0
        - script must be 2-6 minutes when spoken, max 3200 chars
        - script sections must be clearly labeled:
          Opening
          Main Brief
          Action Drill
          Closing
        - make it specific to prompt + memory + survey + lessons.

        Prompt:
        \(prompt)

        Notes:
        \(notesSnapshot)

        Workspace memory signals:
        \(workspaceMemorySnapshot)

        Lesson signals:
        \(lessonSnapshot)

        Survey signals:
        \(surveySnapshot)

        Prior memory outputs:
        \(historySnapshot)
        """
    }

    private func normalizePodcastAudioPayload(
        audioData: Data,
        mimeType: String
    ) -> (data: Data, mimeType: String, rawPCMByteCount: Int)? {
        guard !audioData.isEmpty else { return nil }
        let normalizedMime = mimeType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedMime.contains("l16") || normalizedMime.contains("pcm") {
            let wavData = Self.wrapPCM16MonoAsWAV(audioData, sampleRate: 24_000)
            return (wavData, "audio/wav", audioData.count)
        }
        return (audioData, mimeType, 0)
    }

    private func persistPodcastAudioArtifact(
        audioData: Data,
        mimeType: String,
        voiceName: String,
        rawPCMByteCount: Int
    ) -> PodcastAudioArtifact? {
        let fm = FileManager.default
        let baseDirectory: URL
        if let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            baseDirectory = support
        } else {
            baseDirectory = fm.temporaryDirectory
        }
        let artifactDirectory = baseDirectory
            .appendingPathComponent("atlas-podcast-audio", isDirectory: true)
        do {
            try fm.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let ext: String = {
            let lower = mimeType.lowercased()
            if lower.contains("wav") { return "wav" }
            if lower.contains("mpeg") || lower.contains("mp3") { return "mp3" }
            if lower.contains("ogg") { return "ogg" }
            if lower.contains("aac") { return "aac" }
            return "bin"
        }()
        let fileURL = artifactDirectory
            .appendingPathComponent("podcast-\(UUID().uuidString)")
            .appendingPathExtension(ext)

        do {
            try audioData.write(to: fileURL, options: [.atomic])
        } catch {
            return nil
        }

        let durationSeconds: Double = {
            if rawPCMByteCount > 0 {
                return max(1.0, Double(rawPCMByteCount) / (24_000.0 * 2.0))
            }
            return max(1.0, Double(audioData.count) / (24_000.0 * 2.0))
        }()

        return PodcastAudioArtifact(
            filePath: fileURL.path,
            mimeType: mimeType,
            voiceName: voiceName,
            bytes: audioData.count,
            estimatedDurationSeconds: durationSeconds
        )
    }

    nonisolated private static func wrapPCM16MonoAsWAV(_ pcmData: Data, sampleRate: Int) -> Data {
        var data = Data()
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(pcmData.count)
        let chunkSize: UInt32 = 36 + subchunk2Size

        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: chunkSize.littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes) // PCM format
        data.append(contentsOf: channels.littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: subchunk2Size.littleEndianBytes)
        data.append(pcmData)
        return data
    }

    private func queueOutputInstruction(
        for outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        prompt: String,
        notesSnapshot: String,
        historySnapshot: String,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonSnapshot: String
    ) -> String {
        let schemaInstruction: String
        let typeRequirements: String

        switch outputType {
        case .standard:
            schemaInstruction = #"{"output_type":"standard","summary":"...","next_action":"...","confidence":0.0}"#
            typeRequirements = """
            - output_type must be "standard"
            - summary <= 280 chars
            - next_action <= 180 chars
            - no extra fields
            """
        case .podcast:
            schemaInstruction = #"{"output_type":"podcast","summary":"...","next_action":"...","confidence":0.0,"content":"..."}"#
            typeRequirements = """
            - output_type must be "podcast"
            - summary <= 280 chars
            - next_action <= 180 chars
            - content <= 2500 chars
            - content must read like a short podcast script with sections:
              Opening, Main Brief, Action Drill, Closing
            """
        case .quiz:
            let difficulty = quizDifficulty ?? .medium
            schemaInstruction = #"{"output_type":"quiz","quiz_difficulty":"easy|medium|hard","summary":"...","next_action":"...","confidence":0.0,"content":"..."}"#
            typeRequirements = """
            - output_type must be "quiz"
            - quiz_difficulty must be "\(difficulty.rawValue)"
            - summary <= 280 chars
            - next_action <= 180 chars
            - content <= 6000 chars
            - content must include exactly 6 rehearsal questions in this exact style:
              Q1: ...
              Choices: A) ... | B) ... | C) ... | D) ...
              Correct: A|B|C|D
              Why it matters: ...
            - each question must reflect the user's prompt plus available memory + lesson signals.
            - at least 2 questions must directly test lessons from Lesson signals when lessons exist.
            - quiz must explicitly incorporate relevant survey signals when available.
            - if the prompt is travel/itinerary related, quiz questions must rehearse itinerary execution (timing, route, checkpoints, contingencies).
            """
        }

        return """
        You are Atlas AI reasoning engine.
        Return ONLY valid JSON with this schema:
        \(schemaInstruction)

        Requirements:
        \(typeRequirements)
        - concise, concrete, and personalized from prompt + memory context.

        Prompt:
        \(prompt)

        Notes:
        \(notesSnapshot)

        Workspace memory signals:
        \(workspaceMemorySnapshot)

        Lesson signals:
        \(lessonSnapshot)

        Survey signals:
        \(surveySnapshot)

        Prior memory outputs:
        \(historySnapshot)
        """
    }

    private func modelDrivenFrontierQuizOutput(
        prompt: String,
        quizDifficulty: QuizDifficulty,
        notesSnapshot: String,
        historySnapshot: String,
        workspaceMemorySnapshot: String,
        surveySnapshot: String,
        lessonSnapshot: String
    ) async -> LocalReasoningOutput? {
        let instruction = queueOutputInstruction(
            for: .quiz,
            quizDifficulty: quizDifficulty,
            prompt: prompt,
            notesSnapshot: notesSnapshot,
            historySnapshot: historySnapshot,
            workspaceMemorySnapshot: workspaceMemorySnapshot,
            surveySnapshot: surveySnapshot,
            lessonSnapshot: lessonSnapshot
        )

        for provider in preferredInferenceProviders {
            guard let raw = await requestLocalModelResponse(
                prompt: instruction,
                timeoutSeconds: 24,
                domain: .structuredJSON,
                providerOverride: provider,
                modelOverride: provider.defaultModel
            ) else {
                continue
            }

            if let parsed: LocalModelQueueResponse = Self.decodeModelJSON(raw) {
                if let output = queueOutputFromParsed(
                    parsed: parsed,
                    outputType: .quiz,
                    quizDifficulty: quizDifficulty,
                    modelLabel: "frontier-\(provider.defaultModel)"
                ) {
                    return output
                }
            }

            if let loose = queueOutputFromLooseRaw(
                raw: raw,
                outputType: .quiz,
                quizDifficulty: quizDifficulty,
                modelLabel: "frontier-\(provider.defaultModel)"
            ) {
                return loose
            }
        }
        return nil
    }

    private func queueOutputFromParsed(
        parsed: LocalModelQueueResponse,
        outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        modelLabel: String
    ) -> LocalReasoningOutput? {
        let confidence = min(1.0, max(0.0, parsed.confidence ?? 0.66))
        let parsedDifficulty = parsed.quizDifficulty.flatMap { raw -> QuizDifficulty? in
            let normalized = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return QuizDifficulty(rawValue: normalized)
        }
        let resolvedQuizDifficulty = outputType == .quiz
            ? (quizDifficulty ?? parsedDifficulty ?? .medium)
            : nil
        let sanitizedContent = sanitizeWorkspaceMemoryValue(parsed.content ?? "", maxLength: 8_000)

        if outputType == .quiz {
            let trimmedQuiz = sanitizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuiz.isEmpty else { return nil }
            let lowered = trimmedQuiz.lowercased()
            guard lowered.contains("q1:"), lowered.contains("correct:"), lowered.contains("why it matters:") else {
                return nil
            }
            let questionCount = trimmedQuiz
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { $0.hasPrefix("q") && $0.contains(":") }
                .count
            let correctCount = lowered.components(separatedBy: "correct:").count - 1
            guard questionCount >= 6, correctCount >= 6 else {
                return nil
            }
        }
        if outputType == .podcast {
            let trimmedPodcast = sanitizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPodcast.isEmpty else { return nil }
        }

        let normalizedContent: String?
        if outputType == .standard {
            normalizedContent = nil
        } else {
            let trimmedContent = sanitizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else { return nil }
            normalizedContent = Self.trimForDisplay(trimmedContent, maxChars: 8_000)
        }

        return LocalReasoningOutput(
            model: modelLabel,
            summary: sanitizeWorkspaceMemoryValue(parsed.summary, maxLength: 420),
            nextAction: sanitizeWorkspaceMemoryValue(parsed.nextAction, maxLength: 220),
            confidence: confidence,
            generatedAt: Date(),
            outputType: outputType,
            quizDifficulty: resolvedQuizDifficulty,
            content: normalizedContent
        )
    }

    private func queueOutputFromLooseRaw(
        raw: String,
        outputType: PromptOutputType,
        quizDifficulty: QuizDifficulty?,
        modelLabel: String
    ) -> LocalReasoningOutput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch outputType {
        case .standard:
            let compact = Self.trimForDisplay(
                sanitizeWorkspaceMemoryValue(trimmed.replacingOccurrences(of: "\n\n", with: "\n"), maxLength: 8_000),
                maxChars: 8_000
            )
            let lines = compact
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let summarySource = lines.first ?? String(compact.prefix(280))
            let summary = sanitizeWorkspaceMemoryValue(String(summarySource), maxLength: 420)

            let nextAction = lines
                .first(where: { $0.lowercased().contains("next action") })
                .map { line -> String in
                    if let colonIndex = line.firstIndex(of: ":") {
                        return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return line
                }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "Execute the first concrete step from this response in the next 25 minutes."

            return LocalReasoningOutput(
                model: modelLabel,
                summary: summary,
                nextAction: sanitizeWorkspaceMemoryValue(nextAction, maxLength: 220),
                confidence: 0.58,
                generatedAt: Date(),
                outputType: .standard,
                quizDifficulty: nil,
                content: nil
            )
        case .quiz:
            let lowered = trimmed.lowercased()
            guard lowered.contains("q1:") || lowered.contains("choices:") || lowered.contains("question 1")
            else {
                return nil
            }
            let normalizedDifficulty = quizDifficulty ?? .medium
            let content = Self.trimForDisplay(
                sanitizeWorkspaceMemoryValue(trimmed, maxLength: 8_000),
                maxChars: 8_000
            )
            return LocalReasoningOutput(
                model: modelLabel,
                summary: "Gemini quiz draft generated from your prompt.",
                nextAction: "Answer the first two questions now, then request a harder follow-up drill.",
                confidence: 0.55,
                generatedAt: Date(),
                outputType: .quiz,
                quizDifficulty: normalizedDifficulty,
                content: content
            )
        case .podcast:
            let content = Self.trimForDisplay(
                sanitizeWorkspaceMemoryValue(trimmed, maxLength: 8_000),
                maxChars: 8_000
            )
            let lines = content
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let summary = sanitizeWorkspaceMemoryValue(
                lines.first ?? "Podcast script generated.",
                maxLength: 420
            )
            let nextAction = lines
                .first(where: { $0.lowercased().contains("next action") })
                .flatMap { line -> String? in
                    if let colonIndex = line.firstIndex(of: ":") {
                        let action = String(line[line.index(after: colonIndex)...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return action.isEmpty ? nil : action
                    }
                    return line.isEmpty ? nil : line
                }
                ?? "Play this briefing now, then execute the first action in the next 25 minutes."
            return LocalReasoningOutput(
                model: modelLabel,
                summary: summary,
                nextAction: sanitizeWorkspaceMemoryValue(nextAction, maxLength: 220),
                confidence: 0.56,
                generatedAt: Date(),
                outputType: .podcast,
                quizDifficulty: nil,
                content: content
            )
        }
    }

    private func queueMemoryHighlights(
        for lane: WorkspaceLane?,
        sessionID: String?,
        limit: Int
    ) -> [String] {
        workspaceMemoryRecords
            .filter { record in
                let laneMatch = lane == nil || record.lane == nil || record.lane == lane
                let sessionMatch = sessionID == nil || record.sessionID == nil || record.sessionID == sessionID
                return laneMatch && sessionMatch
            }
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs)
                let rhsScore = workspaceMemoryScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(max(1, limit))
            .map { "\((workspaceSignalLabel(for: $0.key))): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 110))" }
    }

    private func lessonMemoryHighlights(limit: Int) -> [String] {
        let cappedLimit = max(1, limit)
        return workspaceMemoryRecords
            .filter { $0.source == .lesson }
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs)
                let rhsScore = workspaceMemoryScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(cappedLimit)
            .map { "\((workspaceSignalLabel(for: $0.key))): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 110))" }
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, !seen.contains(clean) else { continue }
            seen.insert(clean)
            ordered.append(clean)
        }
        return ordered
    }

    private func queueSurveySnapshot(for lane: WorkspaceLane?, limit: Int) -> String {
        let signals = surveyAnswers
            .map { questionID, answer -> (laneScore: Int, questionID: String, answer: String) in
                let indexedLane = surveyQuestionLaneIndex[questionID].flatMap(WorkspaceLane.init(rawValue:))
                let laneScore: Int
                if let lane {
                    if indexedLane == lane {
                        laneScore = 2
                    } else if indexedLane == nil {
                        laneScore = 1
                    } else {
                        laneScore = 0
                    }
                } else {
                    laneScore = 1
                }
                return (laneScore: laneScore, questionID: questionID, answer: answer)
            }
            .sorted { lhs, rhs in
                if lhs.laneScore != rhs.laneScore {
                    return lhs.laneScore > rhs.laneScore
                }
                return lhs.questionID < rhs.questionID
            }
            .prefix(max(1, limit))

        guard !signals.isEmpty else {
            return "- No survey signals yet."
        }

        return signals
            .map { signal in
                let label = workspaceSignalLabel(for: signal.questionID)
                let value = sanitizeWorkspaceMemoryValue(signal.answer, maxLength: 120)
                return "- \(label): \(value)"
            }
            .joined(separator: "\n")
    }

    private func modelDrivenFeedItems() async -> [FeedItem]? {
        guard localInferenceEnabled, isModelAutofillUnlocked else { return nil }

        let actions = executionActions
            .prefix(8)
            .map { "- [\($0.horizon)] \($0.title): \(sanitizeWorkspaceMemoryValue($0.details, maxLength: 140))" }
            .joined(separator: "\n")
        let workspaceSignals = workspacePlans
            .prefix(6)
            .map { "- \($0.title): \($0.nextActionNow)" }
            .joined(separator: "\n")
        let noteSignals = notes
            .prefix(8)
            .map { "- \($0.title): \(sanitizeWorkspaceMemoryValue($0.content, maxLength: 120))" }
            .joined(separator: "\n")
        let lessonSignals = lessonMemoryHighlights(limit: 5)
            .map { "- \($0)" }
            .joined(separator: "\n")

        let instruction = """
        You are Atlas AI execution planner.
        Return ONLY JSON in this schema:
        {"items":[{"title":"...","summary":"...","why_now":"...","priority":"High|Medium|Low"}]}
        Provide 3 items max.
        Each title <= 90 chars, summary <= 220 chars, why_now <= 180 chars.

        Current priorities:
        Daily: \(dailyPriority)
        Mid-term: \(midTermGoal)
        Long-term: \(longTermVision)
        Blockers: \(checkInBlockers)
        Mood/Energy: \(checkInMood) / \(checkInEnergy)

        Execution actions:
        \(actions)

        Workspace signals:
        \(workspaceSignals)

        Notes:
        \(noteSignals)

        Lessons to integrate:
        \(lessonSignals.isEmpty ? "- No lesson signals yet." : lessonSignals)
        """

        guard let raw = await requestLocalModelResponse(
            prompt: instruction,
            timeoutSeconds: 18,
            domain: .structuredJSON
        ) else {
            return nil
        }

        let items: [LocalModelFeedItem]?
        if let envelope: LocalModelFeedEnvelope = Self.decodeModelJSON(raw) {
            items = envelope.items
        } else {
            let direct: [LocalModelFeedItem]? = Self.decodeModelJSON(raw)
            items = direct
        }

        guard let parsed = items, !parsed.isEmpty else {
            return nil
        }

        return parsed.prefix(3).enumerated().map { idx, item in
            FeedItem(
                id: "model-feed-\(idx)-\(UUID().uuidString)",
                title: sanitizeWorkspaceMemoryValue(item.title, maxLength: 110),
                summary: sanitizeWorkspaceMemoryValue(item.summary, maxLength: 260),
                whyNow: sanitizeWorkspaceMemoryValue(item.whyNow, maxLength: 220),
                priority: sanitizeWorkspaceMemoryValue(item.priority, maxLength: 24),
                checklistState: nil
            )
        }
    }

    private func refreshCommandModelBrief() async {
        guard isModelAutofillUnlocked else {
            commandModelBrief = "AI command brief unlocks after \(Self.minimumSurveyAnswersForModelAutofill) survey answers (\(modelAutofillSurveyAnswersRemaining) remaining)."
            return
        }

        let signature = commandBriefSignature()
        let now = Date()
        if signature == lastCommandBriefSignature,
           now.timeIntervalSince(lastCommandBriefRefreshAt) < Self.modelBriefRefreshWindowSeconds
        {
            return
        }
        defer {
            lastCommandBriefSignature = signature
            lastCommandBriefRefreshAt = Date()
        }

        let lessonSnapshot = lessonMemoryHighlights(limit: 4)
            .map { "- \($0)" }
            .joined(separator: "\n")
        let prompt = """
        Return one concise command-brief paragraph (< 500 chars) for this operator.
        Focus on immediate execution leverage and risk control.

        Daily: \(dailyPriority)
        Mid-term: \(midTermGoal)
        Long-term: \(longTermVision)
        Blockers: \(checkInBlockers)
        Mood/Energy: \(checkInMood) / \(checkInEnergy)
        Actions: \(executionActions.prefix(6).map { "\($0.horizon): \($0.title)" }.joined(separator: " | "))
        Lessons to integrate:
        \(lessonSnapshot.isEmpty ? "- No explicit lessons yet." : lessonSnapshot)
        """

        if let text = await requestLocalModelResponse(
            prompt: prompt,
            timeoutSeconds: 12,
            domain: .briefing
        ) {
            commandModelBrief = sanitizeWorkspaceMemoryValue(text, maxLength: 520)
        } else {
            commandModelBrief = "AI command brief unavailable. Restore model runtime access and retry."
        }
    }

    private func refreshWorkspaceModelBrief() async {
        let lane = activeWorkspaceLane
        let signature = workspaceBriefSignature(for: lane)
        let now = Date()
        if let lastSignature = lastWorkspaceBriefSignatureByLane[lane],
           lastSignature == signature,
           let lastRefresh = lastWorkspaceBriefRefreshAtByLane[lane],
           now.timeIntervalSince(lastRefresh) < Self.modelBriefRefreshWindowSeconds
        {
            return
        }
        defer {
            lastWorkspaceBriefSignatureByLane[lane] = signature
            lastWorkspaceBriefRefreshAtByLane[lane] = Date()
        }

        let sessionIDs = sessions(for: lane).prefix(4).map(\.title).joined(separator: " | ")
        let lessonSnapshot = lessonMemoryHighlights(limit: 4)
            .map { "- \($0)" }
            .joined(separator: "\n")
        let prompt = """
        Return one concise workspace brief (< 500 chars).
        Focus lane: \(lane.title)
        Active session names: \(sessionIDs)
        Workspace plan: \(workspacePlans.first(where: { $0.lane == lane })?.objective ?? "No objective yet.")
        Next action now: \(workspacePlans.first(where: { $0.lane == lane })?.nextActionNow ?? "No next action yet.")
        Lessons to integrate:
        \(lessonSnapshot.isEmpty ? "- No explicit lessons yet." : lessonSnapshot)
        """

        if let text = await requestLocalModelResponse(
            prompt: prompt,
            timeoutSeconds: 12,
            domain: .briefing
        ) {
            workspaceModelBrief = sanitizeWorkspaceMemoryValue(text, maxLength: 520)
        } else {
            workspaceModelBrief = "AI workspace brief unavailable. Restore model runtime access and retry."
        }
    }

    private func refreshJobOpportunityNarrativesIfNeeded(opportunities: [JobOpportunity]) async {
        guard isJobRadarReady else {
            jobOpportunityNarratives = [:]
            return
        }
        let topOpportunities = Array(opportunities.prefix(4))
        guard !topOpportunities.isEmpty else {
            jobOpportunityNarratives = [:]
            return
        }

        let signatureComponents = [
            topOpportunities.map(\.id).joined(separator: "|"),
            topOpportunities.map(\.salaryBandUSD).joined(separator: "|"),
            surveyAnswers
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&"),
            dailyPriority,
            midTermGoal,
            checkInBlockers,
        ]
        let signature = Self.sha256Hex(signatureComponents.joined(separator: "||"))
        let now = Date()
        if signature == lastJobNarrativeSignature,
           now.timeIntervalSince(lastJobNarrativeRefreshAt) < Self.feedRefreshWindowSeconds,
           topOpportunities.allSatisfy({ jobOpportunityNarratives[$0.id] != nil })
        {
            return
        }
        defer {
            lastJobNarrativeSignature = signature
            lastJobNarrativeRefreshAt = Date()
        }

        var updated = jobOpportunityNarratives
        for opportunity in topOpportunities {
            let prompt = """
            Return a concise opportunity brief in 2 short lines:
            Line 1 must start with "Why:"
            Line 2 must start with "How:"
            Keep the total under 220 characters.

            Role: \(opportunity.title)
            Location: \(opportunity.location)
            Salary: \(opportunity.salaryBandUSD)
            Track: \(opportunity.track)
            Industry: \(opportunity.industryFocus)
            Profile signals: goal=\(dailyPriority), blocker=\(checkInBlockers), priority=\(midTermGoal)
            """

            if let text = await requestLocalModelResponse(
                prompt: prompt,
                timeoutSeconds: 10,
                domain: .briefing,
                providerOverride: .gemini,
                modelOverride: Self.geminiReasoningModel
            ) {
                let trimmed = sanitizeWorkspaceMemoryValue(text.replacingOccurrences(of: "\n\n", with: "\n"), maxLength: 240)
                if !trimmed.isEmpty {
                    updated[opportunity.id] = trimmed
                    continue
                }
            }

            let fallback = "Why: \(opportunity.whyHighlights.prefix(1).joined(separator: " "))\nHow: \(opportunity.capabilityPath.prefix(1).joined(separator: " "))"
            updated[opportunity.id] = sanitizeWorkspaceMemoryValue(fallback, maxLength: 240)
        }

        let validIDs = Set(topOpportunities.map(\.id))
        updated = updated.filter { validIDs.contains($0.key) }
        jobOpportunityNarratives = updated
    }

    private func commandBriefSignature() -> String {
        let components = [
            dailyPriority,
            midTermGoal,
            longTermVision,
            checkInBlockers,
            checkInMood,
            "\(checkInEnergy)",
            executionActions
                .prefix(6)
                .map { "\($0.horizon):\($0.title)" }
                .joined(separator: "|"),
            workspacePlans
                .prefix(4)
                .map { "\($0.lane.rawValue):\($0.nextActionNow)" }
                .joined(separator: "|"),
            lessonMemoryHighlights(limit: 6).joined(separator: "|"),
        ]
        return Self.sha256Hex(components.joined(separator: "||").lowercased())
    }

    private func workspaceBriefSignature(for lane: WorkspaceLane) -> String {
        let laneSessions = sessions(for: lane)
            .prefix(5)
            .map { "\($0.id):\($0.title):\($0.updatedAtUTC.timeIntervalSince1970)" }
            .joined(separator: "|")
        let lanePlan = workspacePlans.first(where: { $0.lane == lane })
        let components = [
            lane.rawValue,
            laneSessions,
            lanePlan?.objective ?? "",
            lanePlan?.nextActionNow ?? "",
            workspaceMode,
            travelRegion,
            annualDistanceKM,
            lessonMemoryHighlights(limit: 5).joined(separator: "|"),
        ]
        return Self.sha256Hex(components.joined(separator: "||").lowercased())
    }

    private func feedInferenceSignature() -> String {
        let executionSlice = executionActions
            .prefix(10)
            .map { "\($0.horizon):\($0.title):\($0.details)" }
            .joined(separator: "|")
        let workspaceSlice = workspacePlans
            .prefix(8)
            .map { "\($0.lane.rawValue):\($0.nextActionNow)" }
            .joined(separator: "|")
        let noteSlice = notes
            .prefix(8)
            .map { "\($0.noteID):\($0.title)" }
            .joined(separator: "|")
        let components = [
            dailyPriority,
            midTermGoal,
            longTermVision,
            checkInBlockers,
            checkInMood,
            "\(checkInEnergy)",
            executionSlice,
            workspaceSlice,
            noteSlice,
            lessonMemoryHighlights(limit: 6).joined(separator: "|"),
            "\(surveyAnswers.count)",
            "\(workspaceMemoryRecords.count)",
        ]
        return Self.sha256Hex(components.joined(separator: "||").lowercased())
    }

    private func localReasoningProfile(
        for domain: LocalInferenceReasoningDomain,
        timeoutSeconds: Int
    ) -> LocalInferenceReasoningProfile {
        let constrained = isResourceConstrained()
        let analysisPasses: Int
        switch domain {
        case .structuredJSON:
            analysisPasses = 1
        case .briefing:
            analysisPasses = constrained ? 2 : 3
        case .coding:
            analysisPasses = constrained ? 2 : 3
        case .general:
            analysisPasses = constrained ? 2 : 3
        }
        let candidateTimeout = max(8, timeoutSeconds + (constrained ? 1 : 3))
        let synthesisTimeout = max(candidateTimeout, timeoutSeconds + (constrained ? 2 : 4))

        let candidateTokens: Int
        let synthesisTokens: Int
        switch domain {
        case .structuredJSON:
            candidateTokens = constrained ? 700 : 1100
            synthesisTokens = constrained ? 850 : 1300
        case .briefing:
            candidateTokens = constrained ? 760 : 1200
            synthesisTokens = constrained ? 900 : 1450
        case .coding:
            candidateTokens = constrained ? 900 : 1500
            synthesisTokens = constrained ? 1100 : 1800
        case .general:
            candidateTokens = constrained ? 820 : 1300
            synthesisTokens = constrained ? 980 : 1600
        }

        return LocalInferenceReasoningProfile(
            analysisPasses: analysisPasses,
            candidateTimeoutSeconds: candidateTimeout,
            synthesisTimeoutSeconds: synthesisTimeout,
            candidateMaxTokens: candidateTokens,
            synthesisMaxTokens: synthesisTokens
        )
    }

    private func reasoningPassFocus(pass: Int, totalPasses: Int) -> String {
        let catalog = [
            "Map constraints and objective boundaries before proposing output.",
            "Stress-test tradeoffs, edge cases, and likely failure points.",
            "Prioritize execution order, safety checks, and measurable outcomes."
        ]
        guard totalPasses > 0 else { return catalog[0] }
        let index = min(max(pass, 0), totalPasses - 1) % catalog.count
        return catalog[index]
    }

    private func globalReasoningContextDigest(maxLength: Int = 4200) -> String {
        let actionSlice = executionActions
            .prefix(8)
            .map { "- \($0.horizon): \($0.title) :: \(sanitizeWorkspaceMemoryValue($0.details, maxLength: 120))" }
            .joined(separator: "\n")
        let workspaceSlice = workspacePlans
            .prefix(6)
            .map { "- \($0.title): \($0.nextActionNow)" }
            .joined(separator: "\n")
        let researchSlice = researchStreams
            .prefix(6)
            .map { "- [\($0.domain)] \($0.title): \(sanitizeWorkspaceMemoryValue($0.executionRecommendation, maxLength: 100))" }
            .joined(separator: "\n")
        let noteSlice = notes
            .prefix(8)
            .map { "- \($0.title): \(sanitizeWorkspaceMemoryValue($0.content, maxLength: 120))" }
            .joined(separator: "\n")
        let surveySlice = surveyAnswers
            .sorted { $0.key < $1.key }
            .prefix(18)
            .map {
                let label = workspaceSignalLabel(for: "survey:\($0.key)")
                let value = sanitizeWorkspaceMemoryValue(
                    $0.value.replacingOccurrences(of: "_", with: " "),
                    maxLength: 96
                )
                return "- \(label): \(value)"
            }
            .joined(separator: "\n")
        let memorySlice = workspaceMemoryRecords
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs)
                let rhsScore = workspaceMemoryScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(10)
            .map { "- \(workspaceSignalLabel(for: $0.key)): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 96))" }
            .joined(separator: "\n")
        let lessonSlice = lessonMemoryHighlights(limit: 6)
            .map { "- \($0)" }
            .joined(separator: "\n")

        let bundle = """
        OPERATOR CONTEXT SNAPSHOT
        Daily priority: \(dailyPriority)
        Mid-term: \(midTermGoal)
        Long-term: \(longTermVision)
        Blockers: \(checkInBlockers)
        Mood/Energy: \(checkInMood) / \(checkInEnergy)

        EXECUTION ACTIONS
        \(actionSlice)

        WORKSPACE PLANS
        \(workspaceSlice)

        RESEARCH SIGNALS
        \(researchSlice)

        NOTES
        \(noteSlice)

        SURVEY SIGNALS
        \(surveySlice)

        MEMORY SIGNALS
        \(memorySlice)

        LESSONS TO INTEGRATE
        \(lessonSlice)
        """

        return sanitizeModelInput(bundle, maxLength: maxLength)
    }

    private func composeDeepReasoningEnvelope(
        taskPrompt: String,
        domain: LocalInferenceReasoningDomain
    ) -> String {
        let contextBlock = domain.includeGlobalContext
            ? globalReasoningContextDigest(maxLength: domain.contextMaxLength)
            : ""
        let contextSection = contextBlock.isEmpty ? "" : "\n\(contextBlock)\n"

        return """
        You are Atlas inference core running in extra-high reasoning depth mode.
        Think deeply and compare alternatives internally before responding.
        Never reveal internal chain-of-thought.
        \(domain.styleInstruction)
        \(contextSection)
        TASK
        \(taskPrompt)
        """
    }

    private func requestLocalModelResponse(
        prompt: String,
        timeoutSeconds: Int,
        domain: LocalInferenceReasoningDomain = .general,
        providerOverride: LocalInferenceProvider? = nil,
        modelOverride: String? = nil
    ) async -> String? {
        guard localInferenceEnabled else { return nil }
        let profile = localReasoningProfile(for: domain, timeoutSeconds: timeoutSeconds)
        let reasoningEnvelope = composeDeepReasoningEnvelope(taskPrompt: prompt, domain: domain)
        var candidates: [String] = []

        for pass in 0 ..< profile.analysisPasses {
            let passPrompt = """
            \(reasoningEnvelope)

            PASS \(pass + 1)/\(profile.analysisPasses)
            Focus: \(reasoningPassFocus(pass: pass, totalPasses: profile.analysisPasses))

            Return final answer for this pass only.
            """

            let temperature = domain == .structuredJSON ? 0.12 : min(0.42, 0.18 + Double(pass) * 0.08)
            if let candidate = await requestSingleLocalModelResponse(
                prompt: passPrompt,
                timeoutSeconds: profile.candidateTimeoutSeconds,
                temperature: temperature,
                maxTokens: profile.candidateMaxTokens,
                providerOverride: providerOverride,
                modelOverride: modelOverride
            ) {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    candidates.append(trimmed)
                }
            }
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return candidates[0]
        }

        let draftBlock = candidates
            .prefix(4)
            .enumerated()
            .map { "[Draft \($0.offset + 1)]\n\($0.element)" }
            .joined(separator: "\n\n")

        let synthesisPrompt = """
        \(reasoningEnvelope)

        CANDIDATE DRAFTS
        \(draftBlock)

        Synthesize the strongest final answer.
        Keep strongest details, remove contradictions, and tighten execution precision.
        \(domain == .structuredJSON ? "Return ONLY valid JSON." : "Return only the final answer text.")
        """

        let synthesisTemperature = domain == .structuredJSON ? 0.08 : 0.16
        if let synthesis = await requestSingleLocalModelResponse(
            prompt: synthesisPrompt,
            timeoutSeconds: profile.synthesisTimeoutSeconds,
            temperature: synthesisTemperature,
            maxTokens: profile.synthesisMaxTokens,
            providerOverride: providerOverride,
            modelOverride: modelOverride
        ) {
            let trimmed = synthesis.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return bestReasoningCandidate(from: candidates, domain: domain)
    }

    private func bestReasoningCandidate(
        from candidates: [String],
        domain: LocalInferenceReasoningDomain
    ) -> String {
        if domain == .structuredJSON {
            if let jsonCandidate = candidates.first(where: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    return true
                }
                return !Self.extractJSONCandidates(from: trimmed).isEmpty
            }) {
                return jsonCandidate
            }
        }
        return candidates.max(by: { $0.count < $1.count }) ?? candidates[0]
    }

    private func requestSingleLocalModelResponse(
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        providerOverride: LocalInferenceProvider? = nil,
        modelOverride: String? = nil
    ) async -> String? {
        let systemPrompt = "You are Atlas AI reasoning engine. Operate at extra-high depth and return only final answers."
        let requestedModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providers = providerOverride.map { [$0] } ?? preferredInferenceProviders

        for provider in providers {
            let modelName: String
            if let requestedModel, !requestedModel.isEmpty {
                modelName = requestedModel
            } else {
                modelName = provider.defaultModel
            }
            let apiKey = localInferenceAPIKey(for: provider)

            var response: String?
            switch provider {
            case .openAICompatible:
                guard let endpoint = localInferenceOpenAIEndpointURL else {
                    continue
                }
                response = await Self.runOpenAICompatiblePrompt(
                    endpoint: endpoint,
                    model: modelName,
                    apiKey: apiKey,
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    systemPrompt: systemPrompt
                )
            case .gemini:
                guard let apiKey, !apiKey.isEmpty else {
                    continue
                }
                response = await Self.runGeminiPrompt(
                    model: modelName,
                    apiKey: apiKey,
                    prompt: prompt,
                    timeoutSeconds: timeoutSeconds,
                    temperature: temperature,
                    maxTokens: maxTokens,
                    systemPrompt: systemPrompt
                )
            }

            if let response, !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return response
            }
        }
        return nil
    }

    private func requestGuidedLearningOllama(prompt: String, timeoutSeconds: Int) async -> String? {
        guard let endpoint = guidedLearningOllamaEndpointURL else { return nil }
        return await Self.runOpenAICompatiblePrompt(
            endpoint: endpoint,
            model: guidedLearningOllamaModelName,
            apiKey: nil,
            prompt: prompt,
            timeoutSeconds: timeoutSeconds,
            temperature: 0.22,
            maxTokens: 1300,
            systemPrompt: "You are Atlas guided learning copilot. Ground responses in provided Kiwix snippets and personalize to user context."
        )
    }

    private func fetchKiwixGroundingSnapshot(for query: String) async -> KiwixGroundingSnapshot? {
        let candidateURLs = kiwixSearchCandidateURLs(for: query)
        guard !candidateURLs.isEmpty else { return nil }

        for url in candidateURLs {
            guard let html = await Self.fetchKiwixHTML(url: url, timeoutSeconds: 12) else { continue }
            let snippets = Self.extractKiwixSnippets(from: html, query: query)
            if !snippets.isEmpty {
                return KiwixGroundingSnapshot(sourceURL: url, snippets: snippets)
            }
        }
        return nil
    }

    private func kiwixSearchCandidateURLs(for query: String) -> [URL] {
        guard let baseURL = guidedLearningKiwixBaseURL else { return [] }

        let querySets: [(suffix: String, items: [URLQueryItem])] = [
            ("search", [URLQueryItem(name: "pattern", value: query)]),
            ("search", [URLQueryItem(name: "content", value: query)]),
            ("search", [URLQueryItem(name: "query", value: query)]),
            ("", [URLQueryItem(name: "search", value: query)]),
            ("", [URLQueryItem(name: "q", value: query)]),
        ]

        var built: [URL] = []
        var seen = Set<String>()
        for candidate in querySets {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { continue }

            let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if candidate.suffix.isEmpty {
                components.path = basePath.isEmpty ? "/" : "/\(basePath)"
            } else if basePath.isEmpty {
                components.path = "/\(candidate.suffix)"
            } else {
                components.path = "/\(basePath)/\(candidate.suffix)"
            }
            components.queryItems = candidate.items

            guard let url = components.url else { continue }
            if seen.insert(url.absoluteString).inserted {
                built.append(url)
            }
        }
        return built
    }

    nonisolated private static func fetchKiwixHTML(url: URL, timeoutSeconds: Int) async -> String? {
        await Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = request.timeoutInterval
            config.timeoutIntervalForResource = request.timeoutInterval + 4
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode)
                else {
                    return nil
                }
                if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
                    return utf8
                }
                let latin1 = String(decoding: data, as: Unicode.UTF8.self)
                return latin1.isEmpty ? nil : latin1
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func extractKiwixSnippets(from html: String, query: String) -> [String] {
        let plain = normalizeWhitespace(decodeHTMLEntities(stripHTML(html)))
        guard !plain.isEmpty else { return [] }

        let tokens = query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 }
        let tokenSet = Set(tokens)
        let fragments = plain
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { normalizeWhitespace($0) }
            .filter { $0.count >= 28 }

        var ranked: [String] = []
        for fragment in fragments {
            let lowered = fragment.lowercased()
            let hasQueryToken = tokenSet.isEmpty || tokenSet.contains(where: { lowered.contains($0) })
            if hasQueryToken {
                ranked.append(trimForDisplay(fragment, maxChars: 240))
            }
            if ranked.count >= 8 {
                break
            }
        }

        if ranked.isEmpty {
            ranked = fragments.prefix(5).map { trimForDisplay($0, maxChars: 240) }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for line in ranked {
            let key = line.lowercased()
            if seen.insert(key).inserted {
                deduped.append(line)
            }
        }
        return deduped
    }

    nonisolated private static func stripHTML(_ raw: String) -> String {
        var output = raw
        output = output.replacingOccurrences(
            of: "(?is)<script[^>]*>.*?</script>",
            with: " ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: "(?is)<style[^>]*>.*?</style>",
            with: " ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: "(?is)<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return output
    }

    nonisolated private static func decodeHTMLEntities(_ text: String) -> String {
        var output = text
        let replacements: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
        ]
        for replacement in replacements {
            output = output.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
        return output
    }

    nonisolated private static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeEndpointURL(
        _ raw: String,
        defaultPath: String,
        allowPrivateNetworkHTTP: Bool
    ) -> URL? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if !normalized.contains("://") {
            normalized = "http://\(normalized)"
        }
        guard var url = URL(string: normalized) else { return nil }

        if (url.path.isEmpty || url.path == "/"),
           !defaultPath.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.path = defaultPath
            if let rebuilt = components.url {
                url = rebuilt
            }
        }

        guard let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" {
            let host = (url.host ?? "").lowercased()
            let loopbackHosts = Set(["localhost", "127.0.0.1", "::1"])
            if !loopbackHosts.contains(host) {
                guard allowPrivateNetworkHTTP, Self.isPrivateNetworkHost(host) else {
                    return nil
                }
            }
        } else if scheme != "https" {
            return nil
        }
        return url
    }

    nonisolated private static func isPrivateNetworkHost(_ host: String) -> Bool {
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16 ... 31).contains(second) {
                return true
            }
        }
        return false
    }

    nonisolated private static func runOpenAICompatiblePrompt(
        endpoint: URL,
        model: String,
        apiKey: String?,
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String
    ) async -> String? {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanModel.isEmpty else { return nil }

        let normalizedTemperature = min(0.95, max(0.0, temperature))
        let normalizedMaxTokens = max(220, maxTokens)
        let cacheKey = localInferenceCacheKey(
            providerID: "openai_compatible",
            model: cleanModel,
            endpointID: endpoint.absoluteString,
            prompt: prompt,
            systemPrompt: systemPrompt,
            temperature: normalizedTemperature,
            maxTokens: normalizedMaxTokens
        )

        return await localInferenceResponseCache.resolve(
            key: cacheKey,
            ttl: SessionStore.localInferenceCacheTTLSeconds
        ) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            if let apiKey, !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let payload = OpenAIChatRequest(
                model: cleanModel,
                messages: [
                    OpenAIChatMessage(role: "system", content: systemPrompt),
                    OpenAIChatMessage(role: "user", content: prompt)
                ],
                temperature: normalizedTemperature,
                maxTokens: normalizedMaxTokens,
                reasoningEffort: cleanModel.lowercased().hasPrefix("gpt-5") ? "high" : nil,
                stream: false
            )
            guard let body = try? JSONEncoder().encode(payload) else { return nil }
            request.httpBody = body

            guard let data = await localInferenceTransport.requestData(for: request, maxRetries: 2) else {
                return nil
            }
            return parseOpenAIResponseContent(data)
        }
    }

    nonisolated private static func runGeminiPrompt(
        model: String,
        apiKey: String,
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String
    ) async -> String? {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { return nil }
        let cleanModel = normalizedModel.hasPrefix("models/")
            ? String(normalizedModel.dropFirst("models/".count))
            : normalizedModel

        var allowedModelChars = CharacterSet.urlPathAllowed
        allowedModelChars.remove(charactersIn: "/")
        let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: allowedModelChars) ?? cleanModel

        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        else {
            return nil
        }

        let normalizedTemperature = min(0.95, max(0.0, temperature))
        let normalizedMaxTokens = max(220, maxTokens)
        let cacheKey = localInferenceCacheKey(
            providerID: "gemini",
            model: cleanModel,
            endpointID: endpoint.absoluteString,
            prompt: prompt,
            systemPrompt: systemPrompt,
            temperature: normalizedTemperature,
            maxTokens: normalizedMaxTokens
        )

        return await localInferenceResponseCache.resolve(
            key: cacheKey,
            ttl: SessionStore.localInferenceCacheTTLSeconds
        ) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let cleanSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = GeminiGenerateRequest(
                systemInstruction: cleanSystemPrompt.isEmpty
                    ? nil
                    : GeminiSystemInstruction(parts: [GeminiTextPart(text: cleanSystemPrompt)]),
                contents: [
                    GeminiMessageContent(
                        role: "user",
                        parts: [GeminiTextPart(text: prompt)]
                    ),
                ],
                generationConfig: GeminiGenerationConfig(
                    temperature: normalizedTemperature,
                    maxOutputTokens: normalizedMaxTokens
                )
            )

            guard let body = try? JSONEncoder().encode(payload) else { return nil }
            request.httpBody = body

            guard let data = await localInferenceTransport.requestData(for: request, maxRetries: 2) else {
                return nil
            }
            return parseGeminiResponseContent(data)
        }
    }

    nonisolated private static func runGeminiTTSPrompt(
        model: String,
        apiKey: String,
        script: String,
        voiceName: String
    ) async -> (data: Data, mimeType: String)? {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { return nil }
        let cleanModel = normalizedModel.hasPrefix("models/")
            ? String(normalizedModel.dropFirst("models/".count))
            : normalizedModel

        var allowedModelChars = CharacterSet.urlPathAllowed
        allowedModelChars.remove(charactersIn: "/")
        let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: allowedModelChars) ?? cleanModel

        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
        else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let payload = GeminiTTSGenerateRequest(
            contents: [
                GeminiMessageContent(
                    role: "user",
                    parts: [GeminiTextPart(text: script)]
                ),
            ],
            generationConfig: GeminiTTSGenerationConfig(
                responseModalities: ["AUDIO"],
                speechConfig: GeminiSpeechConfig(
                    voiceConfig: GeminiSpeechVoiceConfig(
                        prebuiltVoiceConfig: GeminiSpeechVoiceConfig.PrebuiltVoiceConfig(
                            voiceName: voiceName
                        )
                    )
                )
            )
        )

        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        request.httpBody = body

        guard let data = await localInferenceTransport.requestData(for: request, maxRetries: 2) else {
            return nil
        }
        return parseGeminiTTSAudioContent(data)
    }

    nonisolated private static func parseOpenAIResponseContent(_ data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data) else {
            return nil
        }
        let content = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? decoded.choices.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !content.isEmpty else { return nil }
        return trimForDisplay(content, maxChars: 18_000)
    }

    nonisolated private static func parseGeminiResponseContent(_ data: Data) -> String? {
        guard let decoded = try? JSONDecoder().decode(GeminiGenerateResponse.self, from: data) else {
            return nil
        }
        let content = decoded.candidates?
            .first?
            .content?
            .parts
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        return trimForDisplay(content, maxChars: 18_000)
    }

    nonisolated private static func parseGeminiTTSAudioContent(
        _ data: Data
    ) -> (data: Data, mimeType: String)? {
        guard let decoded = try? JSONDecoder().decode(GeminiGenerateResponse.self, from: data) else {
            return nil
        }
        guard let parts = decoded.candidates?.first?.content?.parts else { return nil }
        for part in parts {
            guard let inlineData = part.inlineData,
                  let mimeType = inlineData.mimeType?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !mimeType.isEmpty,
                  let encoded = inlineData.data?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !encoded.isEmpty,
                  let decodedAudio = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
                  !decodedAudio.isEmpty
            else {
                continue
            }
            return (decodedAudio, mimeType)
        }
        return nil
    }

    nonisolated private static func decodeModelJSON<T: Decodable>(_ raw: String) -> T? {
        let decoder = JSONDecoder()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = [trimmed]
        candidates.append(contentsOf: Self.extractJSONCandidates(from: trimmed))

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? decoder.decode(T.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    nonisolated private static func extractJSONCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        let fence = "```"

        if let firstFence = text.range(of: fence),
           let secondFence = text.range(of: fence, range: firstFence.upperBound..<text.endIndex)
        {
            var fenced = String(text[firstFence.upperBound..<secondFence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced.lowercased().hasPrefix("json") {
                fenced = fenced.replacingOccurrences(of: "json", with: "", options: [.caseInsensitive], range: fenced.startIndex..<fenced.index(fenced.startIndex, offsetBy: min(4, fenced.count)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !fenced.isEmpty {
                candidates.append(fenced)
            }
        }

        if let object = extractBalancedSegment(text, open: "{", close: "}") {
            candidates.append(object)
        }
        if let array = extractBalancedSegment(text, open: "[", close: "]") {
            candidates.append(array)
        }
        return candidates
    }

    nonisolated private static func extractBalancedSegment(_ text: String, open: Character, close: Character) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for idx in text.indices {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    continue
                }
                if ch == "\"" {
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                continue
            }

            if ch == open {
                if depth == 0 {
                    start = idx
                }
                depth += 1
            } else if ch == close, depth > 0 {
                depth -= 1
                if depth == 0, let start {
                    return String(text[start ... idx])
                }
            }
        }
        return nil
    }

    nonisolated private static func trimForDisplay(_ value: String, maxChars: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxChars else { return normalized }
        let idx = normalized.index(normalized.startIndex, offsetBy: max(0, maxChars))
        return String(normalized[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func executeIOSLocalCommand(
        _ command: String,
        workingDirectory: String,
        indexedFiles: [String]
    ) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return (1, "Empty command.") }

            let root = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
            let rootWithSlash = root.hasSuffix("/") ? root : root + "/"

            func normalizedPath(_ path: String) -> String {
                URL(fileURLWithPath: path).standardizedFileURL.path
            }

            func pathInsideRoot(_ path: String) -> Bool {
                let normalized = normalizedPath(path)
                return normalized == root || normalized.hasPrefix(rootWithSlash)
            }

            func resolvePath(_ raw: String) -> String {
                let argument = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if argument.hasPrefix("/") {
                    return normalizedPath(argument)
                }
                return normalizedPath((root as NSString).appendingPathComponent(argument))
            }

            func isLikelyText(_ data: Data) -> Bool {
                guard !data.isEmpty else { return true }
                return !data.prefix(2048).contains(0)
            }

            let lower = trimmed.lowercased()

            if lower == "pwd" {
                return (0, root)
            }

            if lower == "ls" || lower == "ls -la" || lower == "ls -l" {
                let lines = indexedFiles
                    .prefix(400)
                    .map { path -> String in
                        let normalized = normalizedPath(path)
                        if normalized.hasPrefix(rootWithSlash) {
                            return String(normalized.dropFirst(rootWithSlash.count))
                        }
                        return normalized
                    }
                    .sorted()
                if lines.isEmpty {
                    return (0, "(no indexed files)")
                }
                return (0, lines.joined(separator: "\n"))
            }

            if lower.hasPrefix("cat ") {
                let argument = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !argument.isEmpty else {
                    return (1, "Usage: cat <path>")
                }
                let resolved = resolvePath(argument)
                guard pathInsideRoot(resolved) else {
                    return (1, "Refusing to read outside workspace root.")
                }
                let url = URL(fileURLWithPath: resolved)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                    return (1, "File not found: \(argument)")
                }
                guard let data = try? Data(contentsOf: url), data.count <= 800_000 else {
                    return (1, "File too large for inline cat preview.")
                }
                guard isLikelyText(data) else {
                    return (1, "Binary file cannot be previewed.")
                }
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                return (0, Self.trimForDisplay(text, maxChars: 14_000))
            }

            if lower.hasPrefix("grep ") {
                var query = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                if (query.hasPrefix("\"") && query.hasSuffix("\"")) || (query.hasPrefix("'") && query.hasSuffix("'")) {
                    query = String(query.dropFirst().dropLast())
                }
                let normalizedQuery = query.lowercased()
                guard !normalizedQuery.isEmpty else {
                    return (1, "Usage: grep <pattern>")
                }

                var hits: [String] = []
                for filePath in indexedFiles {
                    if hits.count >= 40 { break }
                    let normalizedFile = normalizedPath(filePath)
                    guard pathInsideRoot(normalizedFile),
                          let data = try? Data(contentsOf: URL(fileURLWithPath: normalizedFile)),
                          data.count <= 500_000,
                          isLikelyText(data)
                    else {
                        continue
                    }
                    let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                    for (lineIndex, line) in lines.enumerated() {
                        if line.lowercased().contains(normalizedQuery) {
                            let displayPath = normalizedFile.hasPrefix(rootWithSlash)
                                ? String(normalizedFile.dropFirst(rootWithSlash.count))
                                : normalizedFile
                            hits.append("\(displayPath):\(lineIndex + 1): \(String(line).trimmingCharacters(in: .whitespaces))")
                            if hits.count >= 40 {
                                break
                            }
                        }
                    }
                }
                if hits.isEmpty {
                    return (1, "No matches for \"\(query)\".")
                }
                return (0, Self.trimForDisplay(hits.joined(separator: "\n"), maxChars: 16_000))
            }

            if lower.hasPrefix("git ")
                || lower.hasPrefix("npm ")
                || lower.hasPrefix("pnpm ")
                || lower.hasPrefix("yarn ")
                || lower.hasPrefix("swift ")
                || lower.hasPrefix("cargo ")
                || lower.hasPrefix("python ")
                || lower.hasPrefix("pytest")
            {
                return (127, "Process execution is unavailable in iOS runtime. Use /grep, /open, /scan, and model guidance.")
            }

            return (127, "Unsupported iOS command. Supported: pwd, ls, cat <path>, grep <pattern>.")
        }.value
    }

    private func normalizeCodingPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func defaultCodingWorkspaceRootPath() -> String {
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documents.standardizedFileURL.path
        }
        return ""
    }

    private func isPathInsideCodingWorkspace(_ candidatePath: String) -> Bool {
        let root = normalizeCodingPath(codingWorkspaceRootPath)
        guard !root.isEmpty else { return false }
        let normalized = normalizeCodingPath(candidatePath)
        let rootWithSlash = root.hasSuffix("/") ? root : root + "/"
        return normalized == root || normalized.hasPrefix(rootWithSlash)
    }

    private func isLikelyText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        let sample = data.prefix(2048)
        return !sample.contains(0)
    }

    private func addCodingMessage(role: CodingMessageRole, content: String, relatedFilePath: String? = nil) {
        let normalizedPath = relatedFilePath.map(normalizeCodingPath)
        codingMessages.append(
            CodingWorkspaceMessage(
                id: UUID().uuidString,
                role: role,
                content: sanitizeWorkspaceMemoryValue(content, maxLength: 12_000),
                createdAtUTC: Date(),
                relatedFilePath: normalizedPath
            )
        )
    }

    private func addCodingMemoryRecord(
        kind: CodingMemoryKind,
        summary: String,
        detail: String,
        relatedFilePath: String? = nil
    ) {
        let cleanSummary = sanitizeWorkspaceMemoryValue(summary, maxLength: 220)
        let cleanDetail = sanitizeWorkspaceMemoryValue(detail, maxLength: 8_000)
        guard !cleanSummary.isEmpty || !cleanDetail.isEmpty else { return }
        codingMemoryRecords.append(
            CodingMemoryRecord(
                id: UUID().uuidString,
                kind: kind,
                summary: cleanSummary,
                detail: cleanDetail,
                relatedFilePath: relatedFilePath.map(normalizeCodingPath),
                createdAtUTC: Date()
            )
        )
    }

    private func handleCodingSlashCommand(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }

        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let commandPart = parts.first else { return false }
        let slash = commandPart.lowercased()
        let argument = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch slash {
        case "/help":
            addCodingMessage(
                role: .assistant,
                content: "Local commands: /scan, /open <path>, /save, /run <cmd>, /grep <pattern>, /remember"
            )
            return true

        case "/scan":
            rescanCodingWorkspace()
            addCodingMessage(role: .assistant, content: "Workspace rescan started.")
            return true

        case "/open":
            guard !argument.isEmpty else {
                addCodingMessage(role: .assistant, content: "Usage: /open <relative-or-absolute-path>")
                return true
            }
            selectCodingFile(relativePath: argument)
            if let selected = codingSelectedFilePath {
                addCodingMessage(role: .assistant, content: "Opened \(codingRelativePath(selected)).", relatedFilePath: selected)
            }
            return true

        case "/save":
            saveCodingFile()
            addCodingMessage(role: .assistant, content: "Save requested for current file.")
            return true

        case "/run":
            guard !argument.isEmpty else {
                addCodingMessage(role: .assistant, content: "Usage: /run <command>")
                return true
            }
            runCodingCommand(commandOverride: argument)
            return true

        case "/grep":
            guard !argument.isEmpty else {
                addCodingMessage(role: .assistant, content: "Usage: /grep <pattern>")
                return true
            }
            let matches = grepCodingWorkspace(argument, limit: 20)
            if matches.isEmpty {
                addCodingMessage(role: .assistant, content: "No matches for \"\(argument)\" in indexed files.")
            } else {
                addCodingMessage(
                    role: .assistant,
                    content: "Matches for \"\(argument)\":\n" + matches.joined(separator: "\n")
                )
            }
            return true

        case "/remember":
            rememberCurrentCodingFile()
            return true

        default:
            addCodingMessage(role: .assistant, content: "Unknown slash command. Use /help.")
            return true
        }
    }

    private func composeOllamaPrompt(for prompt: String) -> String {
        let activeFile = codingSelectedFilePath.map(codingRelativePath) ?? "none"
        let fileSnapshot = String(codingEditorText.prefix(9_000))
        let memorySnapshot = codingMemoryRecords
            .suffix(8)
            .map { "- [\($0.kind.rawValue)] \($0.summary)" }
            .joined(separator: "\n")
        let fileIndexSnapshot = codingWorkspaceFiles
            .prefix(60)
            .map(codingRelativePath)
            .joined(separator: "\n")

        return """
        You are Atlas local coding assistant running entirely on-device.
        Prioritize precision, concise actionable steps, and concrete commands.
        If unsure, say what information is missing and suggest the fastest verification command.
        Never suggest cloud dependencies unless explicitly asked.

        WORKSPACE ROOT:
        \(codingWorkspaceRootPath)

        ACTIVE FILE:
        \(activeFile)

        ACTIVE FILE SNAPSHOT (may be truncated):
        \(fileSnapshot)

        RECENT MEMORY:
        \(memorySnapshot)

        INDEXED FILES (sample):
        \(fileIndexSnapshot)

        USER REQUEST:
        \(prompt)
        """
    }

    private func grepCodingWorkspace(_ pattern: String, limit: Int) -> [String] {
        let query = pattern.lowercased()
        guard !query.isEmpty else { return [] }

        var hits: [String] = []
        for filePath in codingWorkspaceFiles {
            if hits.count >= limit { break }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
                  data.count <= 500_000,
                  isLikelyText(data)
            else {
                continue
            }

            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (lineIndex, line) in lines.enumerated() {
                if line.lowercased().contains(query) {
                    let snippet = sanitizeWorkspaceMemoryValue(String(line), maxLength: 180)
                    hits.append("\(codingRelativePath(filePath)):\(lineIndex + 1): \(snippet)")
                    if hits.count >= limit {
                        break
                    }
                }
            }
        }
        return hits
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

    private var shouldPauseQueueForInternetReconnect: Bool {
        inferencePipelineRequiresInternetConnection() && !isInternetConnectionAvailable
    }

    private func runtimeAccessBlockingIssue() -> String? {
        if !isSignedIn {
            return "Cloud AI is locked. Sign in or sign up to continue."
        }
        if !billingAccessEnabled {
            return "Cloud AI is locked until billing is active. Add a payment method in Plans."
        }
        return nil
    }

    private func markQueueItemWaitingForInternetReconnect(at index: Int) {
        guard promptQueue.indices.contains(index) else { return }
        promptQueue[index].status = .queued
        promptQueue[index].completedAt = nil
        promptQueue[index].lastCheckpointAt = Date()
        let currentProgress = promptQueue[index].progress ?? 0.08
        promptQueue[index].progress = max(0.04, min(0.4, currentProgress * 0.92))
        promptQueue[index].checkpointNote = "No internet connection. Waiting to reconnect."
        promptQueue[index].errorMessage = nil
        persistPromptQueueToDisk()
    }

    private func logQueueReconnectWaitIfNeeded(for outputType: PromptOutputType) {
        guard !hasLoggedQueueReconnectWait else { return }
        hasLoggedQueueReconnectWait = true
        appendOutput("No internet connection. Waiting to reconnect before generating \(outputType.title).")
    }

    private func queueCheckpointIntervalNanoseconds() -> UInt64 {
        isResourceConstrained() ? 3_500_000_000 : 2_000_000_000
    }

    private func queueCooldownNanoseconds() -> UInt64 {
        isResourceConstrained() ? 1_600_000_000 : 300_000_000
    }

    private func queueReconnectWaitNanoseconds() -> UInt64 {
        isResourceConstrained() ? 4_500_000_000 : 2_500_000_000
    }

    private func queueRuntimeRetryNanoseconds(for attempt: Int) -> UInt64 {
        let base: UInt64 = isResourceConstrained() ? 2_200_000_000 : 1_100_000_000
        let clampedAttempt = max(1, min(6, attempt))
        return UInt64(clampedAttempt) * base
    }

    private func inferencePipelineRequiresInternetConnection() -> Bool {
        true
    }

    private func configureNetworkPathMonitor() {
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor
        let queue = DispatchQueue(label: "com.atlasmasa.ios.network-path")
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let isAvailable = path.status == .satisfied
                guard self.isInternetConnectionAvailable != isAvailable else { return }

                self.isInternetConnectionAvailable = isAvailable
                if isAvailable {
                    self.hasLoggedQueueReconnectWait = false
                    if self.promptQueue.contains(where: { $0.status == .queued }) {
                        self.appendOutput("Internet connection restored. Resuming queued AI requests.")
                        self.startPromptQueueWorker()
                    }
                } else if self.inferencePipelineRequiresInternetConnection(),
                          self.promptQueue.contains(where: { $0.status == .queued || $0.status == .running })
                {
                    self.appendOutput("Internet connection lost. Waiting to reconnect before continuing cloud AI requests.")
                }
            }
        }
        monitor.start(queue: queue)
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
        ensureConciergeSessionsSeeded()
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
        if let incomeGap = surveyAnswers["income_gap_primary"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Primary income blocker",
                    value: wealthLabel(for: incomeGap)
                )
            )
        }
        if let sleepQuality = surveyAnswers["brain_sleep_quality"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Sleep quality baseline",
                    value: wealthLabel(for: sleepQuality)
                )
            )
        }
        if let focusStability = surveyAnswers["brain_focus_stability"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Focus stability baseline",
                    value: wealthLabel(for: focusStability)
                )
            )
        }
        if let stressRegulation = surveyAnswers["brain_stress_regulation"] {
            insights.append(
                MemoryInsight(
                    id: UUID().uuidString,
                    label: "Stress regulation baseline",
                    value: wealthLabel(for: stressRegulation)
                )
            )
        }
        for note in keyNotes {
            insights.append(MemoryInsight(id: UUID().uuidString, label: note.title, value: String(note.content.prefix(90))))
        }
        memoryInsights = insights

        let jobOpportunities = buildJobMarketOpportunities()
        jobMarketOpportunities = jobOpportunities
        executionActions = buildExecutionActions(jobOpportunities: jobOpportunities)
        tailoredOffers = buildTailoredOffers(jobOpportunities: jobOpportunities)
        researchStreams = buildResearchExecutionStreams()
        syncWorkspaceMemoryRecords()
        refreshConciergeSessionSnapshots()
        refreshWorkspaceSessionSnapshots()
        workspacePlans = buildWorkspacePlans(from: researchStreams, memoryRecords: workspaceMemoryRecords)
        refreshAdaptiveLearningPackageIfNeeded()
        Task {
            await refreshJobOpportunityNarrativesIfNeeded(opportunities: jobOpportunities)
        }
    }

    private func buildExecutionActions(jobOpportunities: [JobOpportunity]) -> [ExecutionAction] {
        var actions: [ExecutionAction] = []

        let daily = dailyPriority.isEmpty ? "Set one non-negotiable action for today." : dailyPriority
        let mid = midTermGoal.isEmpty ? "Define one milestone to close this week." : midTermGoal
        let long = longTermVision.isEmpty ? "Define one 90-day wealth/mission objective." : longTermVision
        let gymBaseline = surveyAnswers["gym_frequency"] ?? "sometimes"
        let incomeBaseline = surveyAnswers["income_cadence"] ?? "sometimes"
        let wealthVehicle = surveyAnswers["wealth_vehicle"] ?? "hybrid"
        let industryFocus = surveyAnswers["industry_focus"] ?? "software_ai"
        let incomeEngine = surveyAnswers["income_engine"] ?? "salary_plus_projects"
        let jobTrack = surveyAnswers["high_paying_job_track"] ?? "none"
        let businessModel = surveyAnswers["business_model_focus"] ?? "not_now"
        let skillStack = surveyAnswers["monetizable_skill_stack"] ?? "problem_solving"
        let compoundingPlan = surveyAnswers["compounding_plan"] ?? "auto_index"
        let employmentState = surveyAnswers["employment_state"] ?? "between_roles"
        let businessState = surveyAnswers["business_state"] ?? "no_business"
        let growthPriority = surveyAnswers["growth_priority"] ?? "hybrid_growth"
        let promotionHorizon = surveyAnswers["promotion_horizon"] ?? "not_applicable"
        let customerGrowthFocus = surveyAnswers["customer_growth_focus"] ?? "not_applicable"
        let runwayMonths = surveyAnswers["runway_months"] ?? "3_6"
        let incomeGapPrimary = surveyAnswers["income_gap_primary"] ?? "execution_consistency"
        let sleepQuality = surveyAnswers["brain_sleep_quality"] ?? "inconsistent"
        let focusStability = surveyAnswers["brain_focus_stability"] ?? "variable"
        let stressRegulation = surveyAnswers["brain_stress_regulation"] ?? "slow_recovery"
        let weeklyRevenueReps = surveyAnswers["weekly_revenue_reps"] ?? "1_2"
        let wealthDiagnostic = buildWealthBrainDiagnostic()
        let careerDecision = buildCareerRouteDecision(
            employmentState: employmentState,
            businessState: businessState,
            growthPriority: growthPriority,
            wealthVehicle: wealthVehicle,
            jobTrack: jobTrack,
            runwayMonths: runwayMonths
        )
        let industryProfile = wealthIndustryProfile(for: industryFocus)

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

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Career",
                title: careerDecision.title,
                details: careerDecision.details,
                priority: 1,
                source: "career-fit",
                completed: false
            )
        )

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Wealth",
                title: "Resolve primary income blocker: \(wealthDiagnostic.primaryBlockerTitle)",
                details: "Signals: blocker=\(wealthLabel(for: incomeGapPrimary)), sleep=\(wealthLabel(for: sleepQuality)), focus=\(wealthLabel(for: focusStability)), stress=\(wealthLabel(for: stressRegulation)), reps=\(wealthLabel(for: weeklyRevenueReps)). Immediate protocol: \(wealthDiagnostic.immediateProtocol) 7-day protocol: \(wealthDiagnostic.sevenDayProtocol)",
                priority: 1,
                source: "wealth-brain-diagnostic",
                completed: false
            )
        )

        if wealthDiagnostic.requiresCognitiveProtection {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Daily",
                    title: "Stabilize cognitive conditions for wealth execution",
                    details: wealthDiagnostic.cognitiveProtectionProtocol,
                    priority: 1,
                    source: "wealth-brain-conditions",
                    completed: false
                )
            )
        }

        if careerDecision.mode == .employee || careerDecision.mode == .hybrid {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Career",
                    title: "Promotion velocity sprint",
                    details: promotionExecutionDetails(
                        employmentState: employmentState,
                        promotionHorizon: promotionHorizon,
                        jobTrack: jobTrack
                    ),
                    priority: 1,
                    source: "promotion-sprint",
                    completed: false
                )
            )
        }

        if careerDecision.mode == .business || careerDecision.mode == .hybrid {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Business",
                    title: "Customer growth sprint",
                    details: customerGrowthExecutionDetails(
                        businessState: businessState,
                        customerGrowthFocus: customerGrowthFocus,
                        businessModel: businessModel
                    ),
                    priority: 1,
                    source: "customer-growth-sprint",
                    completed: false
                )
            )
        }

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

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Wealth",
                title: "Define this week’s wealth route sprint",
                details: wealthRouteSprintDetails(
                    vehicle: wealthVehicle,
                    industry: industryFocus,
                    incomeEngine: incomeEngine,
                    jobTrack: jobTrack,
                    businessModel: businessModel,
                    skillStack: skillStack
                ),
                priority: 1,
                source: "wealth-route",
                completed: false
            )
        )

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Wealth",
                title: "\(industryProfile.title) income ladder",
                details: incomeLadderExecutionDetails(
                    profile: industryProfile,
                    wealthVehicle: wealthVehicle,
                    jobTrack: jobTrack
                ),
                priority: 1,
                source: "wealth-corpus-ladder",
                completed: false
            )
        )

        if careerDecision.mode == .employee || careerDecision.mode == .hybrid {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Career",
                    title: "\(industryProfile.title) promotion playbook",
                    details: promotionPlaybookExecutionDetails(
                        profile: industryProfile,
                        promotionHorizon: promotionHorizon
                    ),
                    priority: 1,
                    source: "wealth-corpus-promotion",
                    completed: false
                )
            )
        }

        if careerDecision.mode == .business || careerDecision.mode == .hybrid {
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Business",
                    title: "\(industryProfile.title) customer growth playbook",
                    details: businessPlaybookExecutionDetails(
                        profile: industryProfile,
                        businessModel: businessModel,
                        customerGrowthFocus: customerGrowthFocus
                    ),
                    priority: 1,
                    source: "wealth-corpus-business",
                    completed: false
                )
            )
        }

        actions.append(
            ExecutionAction(
                id: UUID().uuidString,
                horizon: "Wealth",
                title: "Protect compounding autopilot",
                details: compoundingProtocolDetails(plan: compoundingPlan),
                priority: 2,
                source: "wealth-compounding",
                completed: false
            )
        )

        if let topOpportunity = jobOpportunities.first {
            let spotlight = jobOpportunities.prefix(3).map { opportunity in
                let links = JobMarketRadar.platformSummary(for: opportunity)
                return "\(opportunity.title) · \(opportunity.location) · \(opportunity.salaryBandUSD) · \(links)"
            }.joined(separator: " | ")

            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Career",
                    title: "Global high-pay opportunity radar",
                    details: "Top route now: \(topOpportunity.title) in \(topOpportunity.location). \(spotlight)",
                    priority: 1,
                    source: "job-radar",
                    completed: false
                )
            )
        }

        let jobInterest = surveyAnswers["job_radar_interest"] ?? "maybe"
        if jobInterest != "yes",
           let blocker = surveyAnswers["job_radar_blocker"],
           !blocker.isEmpty
        {
            let supportMode = surveyAnswers["job_radar_support_mode"]
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Career",
                    title: "Remove job adoption blocker",
                    details: JobMarketRadar.blockerResolution(blocker: blocker, supportMode: supportMode),
                    priority: 1,
                    source: "job-blocker",
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

        let sorted = actions.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title < rhs.title
            }
            return lhs.priority < rhs.priority
        }

        var selected = Array(sorted.prefix(10))
        let pinnedSources: [String] = [
            "career-fit",
            "wealth-route",
            "wealth-compounding",
            "wealth-corpus-ladder",
        ]

        for source in pinnedSources {
            guard let pinned = sorted.first(where: { $0.source == source }) else { continue }
            if selected.contains(where: { $0.source == source }) { continue }

            if let replaceIndex = selected.lastIndex(where: { !pinnedSources.contains($0.source) }) {
                selected[replaceIndex] = pinned
            } else if selected.count < 10 {
                selected.append(pinned)
            } else if !selected.isEmpty {
                selected[selected.count - 1] = pinned
            }
        }

        return selected.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title < rhs.title
            }
            return lhs.priority < rhs.priority
        }
    }

    private func buildTailoredOffers(jobOpportunities: [JobOpportunity]) -> [TailoredOffer] {
        var offers: [TailoredOffer] = []
        let combinedIntent = combinedIntentText()
        let needsRecovery = checkInEnergy <= 2 || containsAny(checkInMood, ["stress", "burnout", "anxious", "exhaust"])
        let needsRevenuePush = containsAny(combinedIntent, ["revenue", "cash", "client", "sales", "income", "money", "profit"])
        let wealthVehicle = surveyAnswers["wealth_vehicle"] ?? "hybrid"
        let industryFocus = surveyAnswers["industry_focus"] ?? "software_ai"
        let businessModel = surveyAnswers["business_model_focus"] ?? "not_now"
        let highPayingTrack = surveyAnswers["high_paying_job_track"] ?? "none"
        let employmentState = surveyAnswers["employment_state"] ?? "between_roles"
        let businessState = surveyAnswers["business_state"] ?? "no_business"
        let growthPriority = surveyAnswers["growth_priority"] ?? "hybrid_growth"
        let promotionHorizon = surveyAnswers["promotion_horizon"] ?? "not_applicable"
        let customerGrowthFocus = surveyAnswers["customer_growth_focus"] ?? "not_applicable"
        let runwayMonths = surveyAnswers["runway_months"] ?? "3_6"
        let careerDecision = buildCareerRouteDecision(
            employmentState: employmentState,
            businessState: businessState,
            growthPriority: growthPriority,
            wealthVehicle: wealthVehicle,
            jobTrack: highPayingTrack,
            runwayMonths: runwayMonths
        )
        let industryProfile = wealthIndustryProfile(for: industryFocus)
        let needsMobilityOps = vanRentalNeeded
            || containsAny(combinedIntent, ["travel", "route", "van", "mobility", "camp", "fleet", "caravan"])
            || (Int(annualDistanceKM) ?? 0) >= 50_000
        let needsResilience = containsAny(combinedIntent, ["risk", "emergency", "safety", "fallback", "continuity", "breakdown"])
        let surveyDepth = survey?.progress.answered ?? 0
        let surveyDepthTarget = max(34, localSurveyTotal() - 4)

        if surveyDepth < surveyDepthTarget {
            offers.append(
                TailoredOffer(
                    id: "offer-survey-depth",
                    category: .productivitySystems,
                    type: .feature,
                    title: "Deep Profile Calibration",
                    summary: "Complete the adaptive survey so Atlas can lock your true operating profile.",
                    rationale: "You are still in onboarding depth mode (\(surveyDepth)/\(surveyDepthTarget)).",
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

        if surveyAnswers["income_gap_primary"] != nil {
            let diagnostic = buildWealthBrainDiagnostic()
            offers.append(
                TailoredOffer(
                    id: "offer-wealth-neuro-diagnostic",
                    category: .wealthOperations,
                    type: .feature,
                    title: "Income Blocker Diagnostic",
                    summary: "Translate cognitive, behavioral, and financial signals into one clear income bottleneck and a corrective execution protocol.",
                    rationale: "Primary blocker detected: \(diagnostic.primaryBlockerTitle). \(diagnostic.summary)",
                    priority: 1,
                    callToAction: "Open diagnostic protocol"
                )
            )
        }

        if careerDecision.mode == .employee || careerDecision.mode == .hybrid {
            offers.append(
                TailoredOffer(
                    id: "offer-promotion-accelerator",
                    category: .wealthOperations,
                    type: .feature,
                    title: "Promotion Accelerator System",
                    summary: "A structured route for higher role scope, promotion readiness, and compensation growth.",
                    rationale: "Career route set to employee growth. Current status: \(wealthLabel(for: employmentState)), target: \(wealthLabel(for: promotionHorizon)).",
                    priority: 1,
                    callToAction: "Open promotion accelerator"
                )
            )
        }

        if careerDecision.mode == .business || careerDecision.mode == .hybrid {
            offers.append(
                TailoredOffer(
                    id: "offer-customer-growth-engine",
                    category: .wealthOperations,
                    type: .service,
                    title: "Customer Growth Engine",
                    summary: "Acquisition + conversion + retention system tuned to your business stage and model.",
                    rationale: "Business route active: \(wealthLabel(for: businessState)). Current growth focus: \(wealthLabel(for: customerGrowthFocus)).",
                    priority: 1,
                    callToAction: "Open customer growth engine"
                )
            )
        }

        if careerDecision.mode == .stability {
            offers.append(
                TailoredOffer(
                    id: "offer-income-stability-bridge",
                    category: .wealthOperations,
                    type: .feature,
                    title: "Income Stability Bridge",
                    summary: "Build dependable income first, then scale into promotion/business expansion from a safer base.",
                    rationale: "Route decision is stability-first due to runway and profile signals.",
                    priority: 1,
                    callToAction: "Build stability bridge"
                )
            )
        }

        if highPayingTrack != "none" || wealthVehicle == "job_ladder" || wealthVehicle == "hybrid" {
            offers.append(
                TailoredOffer(
                    id: "offer-high-paying-job-route",
                    category: .wealthOperations,
                    type: .feature,
                    title: "High-Paying Job Ladder",
                    summary: "Weekly plan for skill capital, portfolio assets, interview velocity, and compensation negotiation.",
                    rationale: "Your profile indicates a job-ladder path in \(wealthLabel(for: industryFocus)).",
                    priority: 1,
                    callToAction: "Build job ladder sprint"
                )
            )
        }

        if let topOpportunity = jobOpportunities.first {
            let links = JobMarketRadar.platformSummary(for: topOpportunity)
            let blocker = surveyAnswers["job_radar_blocker"]
            let blockerSuffix: String
            if let blocker, !blocker.isEmpty {
                blockerSuffix = " Current blocker: \(JobMarketRadar.blockerLabel(for: blocker))."
            } else {
                blockerSuffix = ""
            }
            offers.append(
                TailoredOffer(
                    id: "offer-global-job-market-radar",
                    category: .wealthOperations,
                    type: .feature,
                    title: "Indeed + Glassdoor Global Job Radar",
                    summary: "Track highest-paying global roles and open direct platform searches by track, region, and compensation band.",
                    rationale: "Top match now: \(topOpportunity.title) (\(topOpportunity.salaryBandUSD)) via \(links).\(blockerSuffix)",
                    priority: 1,
                    callToAction: "Open global opportunities"
                )
            )
        }

        if businessModel != "not_now" || wealthVehicle == "business_builder" || wealthVehicle == "hybrid" {
            offers.append(
                TailoredOffer(
                    id: "offer-business-ops-lane",
                    category: .wealthOperations,
                    type: .service,
                    title: "Business Model Launch Sequencer",
                    summary: "Offer definition, demand validation, pricing tests, and weekly cash-flow dashboard setup.",
                    rationale: "Business-building signals detected for \(wealthLabel(for: businessModel)).",
                    priority: 1,
                    callToAction: "Launch business route"
                )
            )
        }

        offers.append(
            TailoredOffer(
                id: "offer-industry-intelligence-map",
                category: .wealthOperations,
                type: .feature,
                title: "Industry Intelligence Map",
                summary: "Route map for earnings paths, adjacent opportunities, and skills transfer across industries.",
                rationale: "Selected industry focus: \(wealthLabel(for: industryFocus)).",
                priority: 2,
                callToAction: "Open industry map"
            )
        )

        offers.append(
            TailoredOffer(
                id: "offer-income-ladder-\(industryProfile.id)",
                category: .wealthOperations,
                type: .feature,
                title: "\(industryProfile.title) Income Ladder Blueprint",
                summary: "Explicit earnings ladder with stage-by-stage leverage moves so the next jump is operational, not vague.",
                rationale: "Industry corpus loaded for \(industryProfile.title): \(incomeLadderSummary(profile: industryProfile)).",
                priority: 1,
                callToAction: "Open income ladder blueprint"
            )
        )

        if careerDecision.mode == .business || careerDecision.mode == .hybrid {
            offers.append(
                TailoredOffer(
                    id: "offer-business-playbook-\(industryProfile.id)",
                    category: .wealthOperations,
                    type: .service,
                    title: "\(industryProfile.title) Business Playbook",
                    summary: "Stage-based customer growth playbook mapped to acquisition, conversion, retention, and expansion.",
                    rationale: "Business corpus channels: \(industryProfile.customerChannels.prefix(3).joined(separator: ", ")).",
                    priority: 1,
                    callToAction: "Open business playbook"
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
                    summary: "Keep default AI depth active and unlock extra cloud depth when workloads get heavier.",
                    rationale: "You are currently operating on the default tier.",
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

        let uniqueOffers = Dictionary(uniqueKeysWithValues: offers.map { ($0.id, $0) }).values
        let sortedOffers = uniqueOffers
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.title < rhs.title
                }
                return lhs.priority < rhs.priority
            }

        var finalOffers: [TailoredOffer] = []
        let pinnedPrefixes = ["offer-income-ladder-", "offer-business-playbook-"]

        for offer in sortedOffers where pinnedPrefixes.contains(where: { offer.id.hasPrefix($0) }) {
            if !finalOffers.contains(where: { $0.id == offer.id }) {
                finalOffers.append(offer)
            }
        }

        for offer in sortedOffers where finalOffers.count < 6 {
            if !finalOffers.contains(where: { $0.id == offer.id }) {
                finalOffers.append(offer)
            }
        }

        return finalOffers
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
        let maxValueLength = source == .lesson ? 420 : 180
        let cleanedValue = sanitizeWorkspaceMemoryValue(rawValue, maxLength: maxValueLength)
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
            .replacingOccurrences(of: "lesson:", with: "lesson ")
            .replacingOccurrences(of: "execution:", with: "execution ")
            .replacingOccurrences(of: "_", with: " ")
        return stripped.capitalized
    }

    private func sanitizeWorkspaceMemoryValue(_ value: String, maxLength: Int) -> String {
        let redacted = SensitiveDataRedactor.redact(value.trimmingCharacters(in: .whitespacesAndNewlines))
        return String(redacted.prefix(maxLength))
    }

    private func workspaceStudioKey(from value: String) -> String {
        let normalized = String(
            value.lowercased().map { ch in
                (ch.isLetter || ch.isNumber) ? ch : "_"
            }
        )
        let collapsed = normalized.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "module" : String(trimmed.prefix(48))
    }

    private func inferWorkspaceLane(from text: String) -> WorkspaceLane? {
        let lower = text.lowercased()
        if containsAny(lower, ["emergency", "crisis", "incident", "triage", "evacuation", "command", "חירום", "משבר"]) {
            return .emergencyCommand
        }
        if containsAny(lower, [
            "cash",
            "revenue",
            "income",
            "sales",
            "pricing",
            "wealth",
            "money",
            "salary",
            "job",
            "industry",
            "business",
            "offer",
            "profit",
            "margin",
            "compounding",
            "portfolio",
            "negotiation",
            "הכנסה",
            "כסף",
            "משכורת",
            "עבודה",
            "עסק",
            "תמחור",
            "מכירות",
        ]) {
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

    private func ensureConciergeSessionsSeeded() {
        let now = Date()
        if conciergeSessions.isEmpty {
            conciergeSessions = [
                ConciergeChatSession(
                    id: UUID().uuidString,
                    title: "Concierge Chat 1",
                    createdAtUTC: now,
                    updatedAtUTC: now,
                    summary: "Primary concierge chat.",
                    isPinned: true
                )
            ]
        }
        if activeConciergeSessionID == nil
            || conciergeSessions.contains(where: { $0.id == activeConciergeSessionID }) == false
        {
            activeConciergeSessionID = allConciergeSessions().first?.id
        }
    }

    private func resolvedActiveConciergeSessionID() -> String {
        ensureConciergeSessionsSeeded()
        return activeConciergeSessionID ?? conciergeSessions.first?.id ?? "concierge-default"
    }

    private func reconcileSessionIDsForLegacyPromptQueue() {
        ensureConciergeSessionsSeeded()
        let activeID = resolvedActiveConciergeSessionID()
        for index in promptQueue.indices {
            if promptQueue[index].workspaceLane == nil,
               promptQueue[index].conciergeSessionID == nil
            {
                promptQueue[index].conciergeSessionID = activeID
            }
        }
    }

    private func touchConciergeSession(id: String, summary: String) {
        guard let index = conciergeSessions.firstIndex(where: { $0.id == id }) else { return }
        let existing = conciergeSessions[index]
        conciergeSessions[index] = ConciergeChatSession(
            id: existing.id,
            title: existing.title,
            createdAtUTC: existing.createdAtUTC,
            updatedAtUTC: Date(),
            summary: sanitizeWorkspaceMemoryValue(summary, maxLength: 180),
            isPinned: existing.isPinned
        )
    }

    private func refreshConciergeSessionSnapshots() {
        conciergeSessions = conciergeSessions.map { session in
            let items = promptQueue.filter { item in
                item.workspaceLane == nil && item.conciergeSessionID == session.id
            }
            let latestOutput = items
                .sorted { $0.createdAt > $1.createdAt }
                .compactMap { $0.output?.summary }
                .first
                .map { sanitizeWorkspaceMemoryValue($0, maxLength: 130) }

            let summary: String
            if let latestOutput, !latestOutput.isEmpty {
                summary = latestOutput
            } else if let firstPrompt = items.last?.prompt {
                summary = sanitizeWorkspaceMemoryValue(firstPrompt, maxLength: 130)
            } else {
                summary = "Fresh chat. Atlas will preload personalized opportunities."
            }

            let updatedAt = items.map(\.createdAt).max() ?? session.updatedAtUTC
            return ConciergeChatSession(
                id: session.id,
                title: session.title,
                createdAtUTC: session.createdAtUTC,
                updatedAtUTC: updatedAt,
                summary: summary,
                isPinned: session.isPinned
            )
        }

        conciergeSessions.sort { lhs, rhs in
            if lhs.updatedAtUTC == rhs.updatedAtUTC {
                return lhs.createdAtUTC > rhs.createdAtUTC
            }
            return lhs.updatedAtUTC > rhs.updatedAtUTC
        }

        if let activeConciergeSessionID,
           conciergeSessions.contains(where: { $0.id == activeConciergeSessionID })
        {
            return
        }
        activeConciergeSessionID = conciergeSessions.first?.id
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
        if sessions(for: executionSelectedLane).isEmpty {
            executionSelectedLane = activeWorkspaceLane
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
        let conciergeText = conciergeSessions
            .map { "\($0.title) \($0.summary)" }
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
            conciergeText,
            memoryText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func wealthRouteSprintDetails(
        vehicle: String,
        industry: String,
        incomeEngine: String,
        jobTrack: String,
        businessModel: String,
        skillStack: String
    ) -> String {
        let vehicleLabel = wealthLabel(for: vehicle)
        let industryLabel = wealthLabel(for: industry)
        let engineLabel = wealthLabel(for: incomeEngine)
        let trackLabel = wealthLabel(for: jobTrack)
        let modelLabel = wealthLabel(for: businessModel)
        let skillLabel = wealthLabel(for: skillStack)
        let profile = wealthIndustryProfile(for: industry)
        let ladder = incomeLadderSummary(profile: profile)
        let playbook = businessPlaybookSummary(
            profile: profile,
            businessModel: businessModel,
            customerGrowthFocus: surveyAnswers["customer_growth_focus"] ?? "not_applicable"
        )

        switch vehicle {
        case "job_ladder":
            return "Route: \(vehicleLabel). Industry: \(industryLabel). Track: \(trackLabel). Build one portfolio proof-of-work, run 5 targeted applications/outreach touches, and schedule one compensation negotiation prep block. Income ladder: \(ladder). Promotion playbook: \(profile.promotionPlaybook.prefix(2).joined(separator: " -> "))."
        case "business_builder":
            return "Route: \(vehicleLabel). Model: \(modelLabel). Industry: \(industryLabel). Define one offer, run one paid acquisition/organic experiment, and measure weekly cash conversion. Income ladder: \(ladder). Business playbook: \(playbook)."
        case "enterprise_operator":
            return "Route: \(vehicleLabel). Engine: \(engineLabel). Industry: \(industryLabel). Execute one operations upgrade tied to margin, cycle time, or service quality this week. Income ladder: \(ladder)."
        default:
            return "Route: \(vehicleLabel). Engine: \(engineLabel). Skill stack: \(skillLabel). Run one job-ladder move + one business move so income compounds through multiple channels. Industry ladder: \(ladder). Business playbook: \(playbook)."
        }
    }

    private func buildCareerRouteDecision(
        employmentState: String,
        businessState: String,
        growthPriority: String,
        wealthVehicle: String,
        jobTrack: String,
        runwayMonths: String
    ) -> CareerRouteDecision {
        let employedStates = Set(["employed_full_time", "employed_part_time", "freelance_consultant", "both_employee_and_business"])
        let businessActiveStates = Set(["idea_stage", "pre_revenue", "early_revenue", "recurring_revenue", "scaling_team"])
        let businessMomentumStates = Set(["early_revenue", "recurring_revenue", "scaling_team"])

        let isEmployed = employedStates.contains(employmentState)
        let hasBusiness = businessActiveStates.contains(businessState)
        let hasBusinessMomentum = businessMomentumStates.contains(businessState)
        let lowRunway = runwayMonths == "under_3"

        if growthPriority == "climb_job_ladder" {
            return CareerRouteDecision(
                mode: .employee,
                title: "Primary route: promotion and compensation growth",
                details: "You selected job-ladder growth. Build promotion evidence weekly, raise visibility with sponsors, and negotiate compensation based on measurable business impact."
            )
        }

        if growthPriority == "grow_business_customer_base" {
            return CareerRouteDecision(
                mode: .business,
                title: "Primary route: customer and revenue growth",
                details: "You selected business growth. Focus on offer-market fit, lead flow, conversion quality, retention, and recurring revenue expansion."
            )
        }

        if growthPriority == "stabilize_income" {
            if isEmployed || jobTrack != "none" {
                return CareerRouteDecision(
                    mode: .employee,
                    title: "Primary route: income stabilization through role growth",
                    details: "Stability-first profile detected. Prioritize secure role performance, promotion readiness, and compensation progression before higher-risk expansion."
                )
            }

            if hasBusinessMomentum && !lowRunway {
                return CareerRouteDecision(
                    mode: .business,
                    title: "Primary route: stabilize through business cashflow",
                    details: "Business momentum is present with enough runway. Standardize acquisition and retention to convert revenue into predictable monthly cashflow."
                )
            }

            return CareerRouteDecision(
                mode: .stability,
                title: "Primary route: stabilize income before aggressive scaling",
                details: "Runway and signal profile suggest a stability bridge. Secure baseline income, then layer growth bets with controlled risk."
            )
        }

        if wealthVehicle == "hybrid" || growthPriority == "hybrid_growth" || (isEmployed && hasBusiness) {
            return CareerRouteDecision(
                mode: .hybrid,
                title: "Primary route: hybrid promotion + business growth",
                details: "Hybrid profile detected. Protect career progression while compounding business distribution and customer acquisition in parallel."
            )
        }

        if wealthVehicle == "business_builder" || (hasBusiness && hasBusinessMomentum && !lowRunway) {
            return CareerRouteDecision(
                mode: .business,
                title: "Primary route: business-led growth",
                details: "Business-first signals dominate. Improve customer acquisition economics, retention loops, and expansion pathways before adding complexity."
            )
        }

        if wealthVehicle == "job_ladder" || isEmployed || jobTrack != "none" {
            return CareerRouteDecision(
                mode: .employee,
                title: "Primary route: employee growth ladder",
                details: "Employee-growth signals dominate. Optimize promotion leverage, internal sponsorship, and compensation strategy."
            )
        }

        return CareerRouteDecision(
            mode: .stability,
            title: "Primary route: secure base and de-risk decisions",
            details: "Atlas recommends a baseline-income phase first, then selective growth bets based on validated traction."
        )
    }

    private func promotionExecutionDetails(
        employmentState: String,
        promotionHorizon: String,
        jobTrack: String
    ) -> String {
        let stateLabel = wealthLabel(for: employmentState)
        let horizonLabel = wealthLabel(for: promotionHorizon)
        let trackLabel = wealthLabel(for: jobTrack)
        return "Status: \(stateLabel). Target: \(horizonLabel). Track: \(trackLabel). Promotion protocol: align rubric with manager, publish weekly impact memo, build sponsor map, capture quantified outcomes, and package a promotion case with compensation band evidence."
    }

    private func customerGrowthExecutionDetails(
        businessState: String,
        customerGrowthFocus: String,
        businessModel: String
    ) -> String {
        let stageLabel = wealthLabel(for: businessState)
        let focusLabel = wealthLabel(for: customerGrowthFocus)
        let modelLabel = wealthLabel(for: businessModel)
        return "Business stage: \(stageLabel). Focus: \(focusLabel). Model: \(modelLabel). Customer growth protocol: tighten ICP + offer, run two channels at measurable CAC, improve conversion scripts, and deploy retention/expansion loops to raise LTV."
    }

    private func wealthIndustryProfile(for industryFocus: String) -> WealthIndustryCorpusProfile {
        let normalized = industryFocus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedID = Self.wealthIndustryAliases[normalized] ?? normalized
        return Self.wealthIndustryCorpus[resolvedID]
            ?? Self.wealthIndustryCorpus["ai_software"]!
    }

    private func incomeLadderSummary(profile: WealthIndustryCorpusProfile) -> String {
        profile.incomeLadder
            .prefix(3)
            .map { "\($0.stage) \($0.annualIncomeBandUSD)" }
            .joined(separator: " -> ")
    }

    private func incomeLadderExecutionDetails(
        profile: WealthIndustryCorpusProfile,
        wealthVehicle: String,
        jobTrack: String
    ) -> String {
        let routeLabel = wealthLabel(for: wealthVehicle)
        let trackLabel = wealthLabel(for: jobTrack)
        let ladder = profile.incomeLadder
            .map { "\($0.stage): \($0.annualIncomeBandUSD) (\($0.leverageMove))" }
            .joined(separator: " | ")
        return "Route: \(routeLabel). Track: \(trackLabel). \(profile.title) income ladder: \(ladder)"
    }

    private func promotionPlaybookExecutionDetails(
        profile: WealthIndustryCorpusProfile,
        promotionHorizon: String
    ) -> String {
        let horizonLabel = wealthLabel(for: promotionHorizon)
        let steps = profile.promotionPlaybook.prefix(4).joined(separator: " | ")
        return "Promotion horizon: \(horizonLabel). \(profile.title) promotion playbook: \(steps)"
    }

    private func businessPlaybookSummary(
        profile: WealthIndustryCorpusProfile,
        businessModel: String,
        customerGrowthFocus: String
    ) -> String {
        let modelLabel = wealthLabel(for: businessModel)
        let focusLabel = wealthLabel(for: customerGrowthFocus)
        let phases = profile.businessPlaybook
            .prefix(3)
            .map { "\($0.phase): \($0.objective)" }
            .joined(separator: " -> ")
        return "Model: \(modelLabel). Focus: \(focusLabel). \(phases)"
    }

    private func businessPlaybookExecutionDetails(
        profile: WealthIndustryCorpusProfile,
        businessModel: String,
        customerGrowthFocus: String
    ) -> String {
        let modelLabel = wealthLabel(for: businessModel)
        let focusLabel = wealthLabel(for: customerGrowthFocus)
        let steps = profile.businessPlaybook
            .map { step in
                let actions = step.keyActions.joined(separator: ", ")
                return "\(step.phase) -> \(step.objective) | actions: \(actions) | metric: \(step.metricTarget)"
            }
            .joined(separator: " || ")
        let channels = profile.customerChannels.joined(separator: ", ")
        return "Model: \(modelLabel). Focus: \(focusLabel). \(profile.title) business playbook: \(steps). Priority channels: \(channels)."
    }

    private func compoundingProtocolDetails(plan: String) -> String {
        switch plan {
        case "auto_index":
            return "Automate contributions first. Keep fixed weekly/monthly transfers to diversified low-cost index exposure before discretionary spending."
        case "cash_buffer_then_invest":
            return "Build and protect emergency buffer first, then auto-route surplus to long-term compounding buckets."
        case "business_reinvestment":
            return "Set explicit reinvestment ratio for growth assets (distribution, product, systems) while preserving tax + safety reserves."
        case "debt_reduction_then_growth":
            return "Execute high-interest debt reduction sequence, then convert the freed cash flow into automated long-term investing."
        default:
            return "Define a simple default compounding protocol and automate it so progress does not depend on daily motivation."
        }
    }

    private struct WealthBrainDiagnostic {
        let primaryBlockerTitle: String
        let summary: String
        let immediateProtocol: String
        let sevenDayProtocol: String
        let requiresCognitiveProtection: Bool
        let cognitiveProtectionProtocol: String
    }

    private func buildWealthBrainDiagnostic() -> WealthBrainDiagnostic {
        let incomeGapPrimary = surveyAnswers["income_gap_primary"] ?? "execution_consistency"
        let sleepQuality = surveyAnswers["brain_sleep_quality"] ?? "inconsistent"
        let focusStability = surveyAnswers["brain_focus_stability"] ?? "variable"
        let stressRegulation = surveyAnswers["brain_stress_regulation"] ?? "slow_recovery"
        let decisionProtocol = surveyAnswers["decision_protocol"] ?? "mixed_protocol"
        let weeklyRevenueReps = surveyAnswers["weekly_revenue_reps"] ?? "1_2"
        let moneyLeak = surveyAnswers["behavioral_money_leak"] ?? "no_tracking"
        let allocationDiscipline = surveyAnswers["capital_allocation_discipline"] ?? "inconsistent_rules"

        var scores: [String: Int] = [:]
        func boost(_ key: String, _ points: Int) {
            scores[key, default: 0] += points
        }

        switch incomeGapPrimary {
        case "pipeline_volume":
            boost("pipeline", 4)
        case "conversion_close":
            boost("conversion", 4)
        case "pricing_positioning":
            boost("pricing", 4)
        case "skill_capital_gap":
            boost("skill_capital", 4)
        case "money_leak":
            boost("money_leak", 4)
        case "cognitive_drain":
            boost("cognitive", 4)
        case "unclear_strategy":
            boost("strategy", 4)
        default:
            boost("execution", 4)
        }

        if weeklyRevenueReps == "0" {
            boost("pipeline", 3)
            boost("execution", 2)
        } else if weeklyRevenueReps == "1_2" {
            boost("pipeline", 2)
        }

        if sleepQuality == "poor" || sleepQuality == "broken" {
            boost("cognitive", 3)
        }
        if focusStability == "fragile" || focusStability == "variable" {
            boost("cognitive", 2)
            boost("execution", 1)
        }
        if stressRegulation == "slow_recovery" || stressRegulation == "rollover" {
            boost("cognitive", 2)
            boost("decision", 1)
        }
        if decisionProtocol == "reactive_protocol" || decisionProtocol == "avoidant_protocol" {
            boost("decision", 3)
            boost("strategy", 1)
        }

        if moneyLeak == "underpricing" {
            boost("pricing", 2)
        } else if moneyLeak == "impulse_spending" || moneyLeak == "unclear_budget" || moneyLeak == "no_tracking" {
            boost("money_leak", 3)
        }

        if allocationDiscipline == "ad_hoc" {
            boost("money_leak", 2)
            boost("strategy", 1)
        } else if allocationDiscipline == "inconsistent_rules" {
            boost("money_leak", 1)
        }

        let topBlocker = scores.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }?.key ?? "execution"

        let requiresCognitiveProtection = sleepQuality == "poor"
            || sleepQuality == "broken"
            || focusStability == "fragile"
            || stressRegulation == "rollover"

        let cognitiveProtectionProtocol = "Run a cognitive protection protocol for 7 days: fixed sleep window, one 60-90 minute deep block before notifications, 10-minute decompression after stress spikes, and no high-stakes decisions after cognitive fatigue."

        let summary = "Atlas diagnosis combines income route + brain-state + behavior signals: blocker \(wealthLabel(for: incomeGapPrimary)); sleep \(wealthLabel(for: sleepQuality)); focus \(wealthLabel(for: focusStability)); stress \(wealthLabel(for: stressRegulation)); decision mode \(wealthLabel(for: decisionProtocol))."

        switch topBlocker {
        case "pipeline":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Qualified pipeline deficit",
                summary: summary,
                immediateProtocol: "Schedule and execute 5 direct outbound touches today with one clear offer and deadline.",
                sevenDayProtocol: "Complete 25 outbound touches, publish 2 proof assets, and review response rates daily to tighten ICP + message.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "conversion":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Conversion and close weakness",
                summary: summary,
                immediateProtocol: "Run one live closing attempt today using objection map + explicit next-step ask.",
                sevenDayProtocol: "Review 5 calls/proposals, fix one objection script per day, and track close-rate delta by segment.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "pricing":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Pricing and positioning gap",
                summary: summary,
                immediateProtocol: "Raise price or package value today for one offer and test on the next 3 opportunities.",
                sevenDayProtocol: "Run a structured pricing test, rewrite positioning around outcome value, and track margin + close impact.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "skill_capital":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Skill capital and proof gap",
                summary: summary,
                immediateProtocol: "Define one monetizable skill sprint and produce one proof-of-work artifact this week.",
                sevenDayProtocol: "Run 5 deliberate practice blocks, ship 2 portfolio artifacts, and map each to a target opportunity.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "money_leak":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Money leakage and allocation drift",
                summary: summary,
                immediateProtocol: "Enable 24-hour hold on non-essential spend and create one automatic transfer rule today.",
                sevenDayProtocol: "Track all inflow/outflow for 7 days, cut one leak category, and lock a fixed allocation template.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "strategy":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Unclear strategy and route fragmentation",
                summary: summary,
                immediateProtocol: "Choose one primary wealth route for this quarter and kill non-aligned initiatives today.",
                sevenDayProtocol: "Translate the chosen route into one weekly scoreboard and one daily non-negotiable action block.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "decision":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Decision quality under pressure",
                summary: summary,
                immediateProtocol: "Use a 3-criteria decision template with a hard deadline for the next high-stakes choice.",
                sevenDayProtocol: "Run a decision log for 7 days, capture outcome quality, and remove one recurring decision failure pattern.",
                requiresCognitiveProtection: true,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        case "cognitive":
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Cognitive throughput instability",
                summary: summary,
                immediateProtocol: "Protect first 90 minutes for deep, revenue-linked work before messaging and low-value tasks.",
                sevenDayProtocol: "Stabilize sleep/focus/recovery loops for 7 days and measure output from high-value deep blocks.",
                requiresCognitiveProtection: true,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        default:
            return WealthBrainDiagnostic(
                primaryBlockerTitle: "Execution consistency gap",
                summary: summary,
                immediateProtocol: "Define one measurable outcome and execute the first block in the next 30 minutes.",
                sevenDayProtocol: "Repeat daily execution block for 7 days with end-of-day scoreboard and next-step precommitment.",
                requiresCognitiveProtection: requiresCognitiveProtection,
                cognitiveProtectionProtocol: cognitiveProtectionProtocol
            )
        }
    }

    private func buildJobMarketOpportunities() -> [JobOpportunity] {
        guard isPrimarySurveyComplete else {
            return []
        }
        let track = surveyAnswers["high_paying_job_track"] ?? "none"
        let industry = surveyAnswers["industry_focus"] ?? "software_ai"
        let wealthVehicle = surveyAnswers["wealth_vehicle"] ?? "hybrid"

        if track == "none", wealthVehicle != "job_ladder", wealthVehicle != "hybrid" {
            return []
        }

        return JobMarketRadar.topOpportunities(
            highPayingTrack: track,
            industryFocus: industry,
            regionHint: travelRegion,
            limit: 5
        )
    }

    private func wealthLabel(for value: String) -> String {
        switch value {
        case "job_ladder":
            return "High-paying job ladder"
        case "business_builder":
            return "Business ownership"
        case "enterprise_operator":
            return "Enterprise operator path"
        case "hybrid":
            return "Hybrid salary + business"
        case "software_ai":
            return "Software and AI"
        case "cybersecurity":
            return "Cybersecurity"
        case "enterprise_sales":
            return "Enterprise sales"
        case "healthcare":
            return "Healthcare"
        case "finance":
            return "Finance and investing"
        case "operations_logistics":
            return "Operations and logistics"
        case "real_estate":
            return "Real estate"
        case "skilled_trades":
            return "Skilled trades"
        case "media_creator":
            return "Media and creator economy"
        case "salary_only":
            return "Salary growth"
        case "salary_plus_projects":
            return "Salary plus side projects"
        case "projects_plus_business":
            return "Projects plus business"
        case "portfolio_income":
            return "Portfolio income"
        case "engineering":
            return "Engineering"
        case "product":
            return "Product management"
        case "sales":
            return "Sales leadership"
        case "operations":
            return "Operations leadership"
        case "finance_track":
            return "Finance track"
        case "real_estate_track":
            return "Real estate track"
        case "media_revenue":
            return "Media revenue track"
        case "clinical":
            return "Clinical specialization"
        case "trade_mastery":
            return "Trade mastery"
        case "agency":
            return "Agency"
        case "saas":
            return "B2B SaaS"
        case "ecommerce":
            return "E-commerce"
        case "local_service":
            return "Local service operations"
        case "education_products":
            return "Education products"
        case "marketplace":
            return "Marketplace"
        case "ai_automation":
            return "AI automation"
        case "problem_solving":
            return "Problem-solving systems"
        case "copywriting":
            return "Copywriting and positioning"
        case "operations_systems":
            return "Operations systems design"
        case "analytics":
            return "Analytics and measurement"
        case "auto_index":
            return "Auto-index investing"
        case "cash_buffer_then_invest":
            return "Cash buffer then invest"
        case "business_reinvestment":
            return "Business reinvestment"
        case "debt_reduction_then_growth":
            return "Debt reduction then growth"
        case "pipeline_volume":
            return "Pipeline volume gap"
        case "conversion_close":
            return "Conversion and close gap"
        case "pricing_positioning":
            return "Pricing and positioning gap"
        case "skill_capital_gap":
            return "Skill capital gap"
        case "execution_consistency":
            return "Execution consistency gap"
        case "cognitive_drain":
            return "Cognitive drain"
        case "money_leak":
            return "Money leakage"
        case "unclear_strategy":
            return "Unclear strategy"
        case "restorative":
            return "Restorative sleep"
        case "inconsistent":
            return "Inconsistent sleep"
        case "poor":
            return "Poor sleep quality"
        case "broken":
            return "Fragmented sleep"
        case "stable_90_plus":
            return "Stable 90+ minute focus"
        case "stable_45_90":
            return "Stable 45-90 minute focus"
        case "variable":
            return "Variable focus stability"
        case "fragile":
            return "Fragile focus stability"
        case "fast_recovery":
            return "Fast stress recovery"
        case "moderate_recovery":
            return "Moderate stress recovery"
        case "slow_recovery":
            return "Slow stress recovery"
        case "rollover":
            return "Stress rollover across days"
        case "structured_protocol":
            return "Structured decision protocol"
        case "mixed_protocol":
            return "Mixed decision protocol"
        case "reactive_protocol":
            return "Reactive decisions"
        case "avoidant_protocol":
            return "Decision avoidance"
        case "0":
            return "No weekly revenue reps"
        case "1_2":
            return "1-2 weekly revenue reps"
        case "3_5":
            return "3-5 weekly revenue reps"
        case "6_plus":
            return "6+ weekly revenue reps"
        case "impulse_spending":
            return "Impulse spending leak"
        case "unclear_budget":
            return "Budget clarity leak"
        case "underpricing":
            return "Underpricing leak"
        case "inconsistent_saving":
            return "Inconsistent saving"
        case "no_tracking":
            return "No tracking discipline"
        case "strict_rules":
            return "Strict allocation rules"
        case "mostly_disciplined":
            return "Mostly disciplined allocation"
        case "inconsistent_rules":
            return "Inconsistent allocation rules"
        case "ad_hoc":
            return "Ad-hoc allocation"
        case "employed_full_time":
            return "Employed full-time"
        case "employed_part_time":
            return "Employed part-time"
        case "freelance_consultant":
            return "Freelance/consulting"
        case "between_roles":
            return "Between roles"
        case "student_transition":
            return "Student/transition phase"
        case "both_employee_and_business":
            return "Employee + business owner"
        case "no_business":
            return "No business yet"
        case "idea_stage":
            return "Business idea stage"
        case "pre_revenue":
            return "Pre-revenue"
        case "early_revenue":
            return "Early revenue"
        case "recurring_revenue":
            return "Recurring revenue"
        case "scaling_team":
            return "Scaling team/company"
        case "climb_job_ladder":
            return "Climb the job ladder"
        case "grow_business_customer_base":
            return "Grow business customer base"
        case "hybrid_growth":
            return "Hybrid growth"
        case "stabilize_income":
            return "Stabilize income first"
        case "not_applicable":
            return "Not applicable"
        case "individual_contributor_to_senior":
            return "IC to senior progression"
        case "senior_to_staff":
            return "Senior to staff/principal"
        case "manager_to_director":
            return "Manager to director"
        case "executive_track":
            return "Executive track"
        case "offer_clarity":
            return "Offer clarity"
        case "lead_generation":
            return "Lead generation"
        case "conversion_rate":
            return "Conversion rate optimization"
        case "retention_expansion":
            return "Retention and expansion"
        case "referrals_partnerships":
            return "Referrals and partnerships"
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
            markSignedIn(provider: provider, accountName: resolvedName, email: me.user.email)
            memoryCollectionEnabled = me.user.memoryOptIn
            let cloudEnabled = me.subscription?.cloudComputeEnabled ?? false
            billingAccessEnabled = cloudEnabled
            selectedTier = cloudEnabled ? .cloudPro : .localTrial
            billingStatusMessage = cloudEnabled
                ? "Billing is active. Cloud AI unlocked."
                : "Billing setup required. Add a payment method to unlock cloud AI."
            if !memoryCollectionEnabled {
                appendOutput("Server profile is set to memory opt-out. Local long-term memory persistence is disabled.")
            }
            if cloudEnabled {
                appendOutput("Billing access verified. Cloud AI unlocked.")
            } else {
                appendOutput("Billing setup required before cloud AI usage.")
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
        let baseTotal = 47
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

        if let highPayingTrack = surveyAnswers["high_paying_job_track"],
           highPayingTrack != "none",
           surveyAnswers["job_radar_interest"] == nil
        {
            return localQuestion(
                id: "job_radar_interest",
                title: "Atlas found global high-paying roles for you. Do you want to pursue them?",
                description: "Atlas maps opportunities through Indeed + Glassdoor and adapts your execution stream based on your answer.",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes, actively pursue"),
                    SurveyChoice(value: "maybe", label: "Maybe, with support"),
                    SurveyChoice(value: "no", label: "Not right now")
                ]
            )
        }

        if let jobInterest = surveyAnswers["job_radar_interest"],
           jobInterest != "yes",
           surveyAnswers["job_radar_blocker"] == nil
        {
            return localQuestion(
                id: "job_radar_blocker",
                title: "What is the main blocker stopping you from taking a high-paying role now?",
                description: "Atlas uses this to tailor recommendations and solve the gap.",
                choices: [
                    SurveyChoice(value: "skills_gap", label: "Skills gap"),
                    SurveyChoice(value: "credential_gap", label: "Credential/experience gap"),
                    SurveyChoice(value: "language_gap", label: "Language confidence"),
                    SurveyChoice(value: "network_gap", label: "No network/referrals"),
                    SurveyChoice(value: "relocation", label: "Relocation constraints"),
                    SurveyChoice(value: "visa_legal", label: "Visa/legal eligibility"),
                    SurveyChoice(value: "schedule_family", label: "Schedule/family load"),
                    SurveyChoice(value: "confidence", label: "Confidence/interview fear")
                ]
            )
        }

        if surveyAnswers["job_radar_blocker"] != nil,
           surveyAnswers["job_radar_support_mode"] == nil
        {
            return localQuestion(
                id: "job_radar_support_mode",
                title: "How should Atlas help you close this blocker?",
                description: "This routes practical job-readiness actions directly into your daily plan.",
                choices: [
                    SurveyChoice(value: "portfolio_plan", label: "Portfolio + proof-of-work plan"),
                    SurveyChoice(value: "interview_prep", label: "Interview + negotiation prep"),
                    SurveyChoice(value: "networking_system", label: "Referral/networking system"),
                    SurveyChoice(value: "credential_bridge", label: "Credential bridging roadmap"),
                    SurveyChoice(value: "language_plan", label: "Language + communication drills"),
                    SurveyChoice(value: "relocation_plan", label: "Relocation-compatible route"),
                    SurveyChoice(value: "legal_eligibility_plan", label: "Visa/legal readiness plan")
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
                id: "income_gap_primary",
                title: "What most explains why your income is below what you need or want?",
                description: "Atlas uses this as your primary income blocker diagnosis.",
                choices: [
                    SurveyChoice(value: "pipeline_volume", label: "Not enough qualified opportunities"),
                    SurveyChoice(value: "conversion_close", label: "Closing/conversion is weak"),
                    SurveyChoice(value: "pricing_positioning", label: "Pricing/positioning is too low"),
                    SurveyChoice(value: "skill_capital_gap", label: "Skills or credibility gap"),
                    SurveyChoice(value: "execution_consistency", label: "Inconsistent execution"),
                    SurveyChoice(value: "cognitive_drain", label: "Mental overload and low cognitive energy"),
                    SurveyChoice(value: "money_leak", label: "Spending/leakage destroys progress"),
                    SurveyChoice(value: "unclear_strategy", label: "No clear strategy or route")
                ]
            ),
            localQuestion(
                id: "brain_sleep_quality",
                title: "How has your sleep quality been over the last 14 days?",
                description: "Sleep quality strongly affects executive control, impulse discipline, and decision quality.",
                choices: [
                    SurveyChoice(value: "restorative", label: "Restorative most nights"),
                    SurveyChoice(value: "inconsistent", label: "Inconsistent"),
                    SurveyChoice(value: "poor", label: "Poor"),
                    SurveyChoice(value: "broken", label: "Fragmented / broken")
                ]
            ),
            localQuestion(
                id: "brain_focus_stability",
                title: "How stable is your focus during high-value work blocks?",
                description: "Atlas uses this to shape your execution cadence and blocker protocols.",
                choices: [
                    SurveyChoice(value: "stable_90_plus", label: "Stable for 90+ minutes"),
                    SurveyChoice(value: "stable_45_90", label: "Stable for 45-90 minutes"),
                    SurveyChoice(value: "variable", label: "Variable day to day"),
                    SurveyChoice(value: "fragile", label: "Breaks quickly")
                ]
            ),
            localQuestion(
                id: "brain_stress_regulation",
                title: "After a stress spike, how quickly do you return to effective execution?",
                description: "Fast recovery preserves throughput and reduces costly decision errors.",
                choices: [
                    SurveyChoice(value: "fast_recovery", label: "Within 10-20 minutes"),
                    SurveyChoice(value: "moderate_recovery", label: "Within 1-2 hours"),
                    SurveyChoice(value: "slow_recovery", label: "Most of the day"),
                    SurveyChoice(value: "rollover", label: "Carries into the next day")
                ]
            ),
            localQuestion(
                id: "decision_protocol",
                title: "When stakes are high, how do you usually make decisions?",
                description: "Atlas uses this to reduce decision noise and improve expected value.",
                choices: [
                    SurveyChoice(value: "structured_protocol", label: "Structured criteria + clear deadlines"),
                    SurveyChoice(value: "mixed_protocol", label: "Sometimes structured, sometimes reactive"),
                    SurveyChoice(value: "reactive_protocol", label: "Mostly reactive"),
                    SurveyChoice(value: "avoidant_protocol", label: "I delay difficult decisions")
                ]
            ),
            localQuestion(
                id: "weekly_revenue_reps",
                title: "How many direct revenue actions do you run each week?",
                description: "Examples: outreach, offers, negotiation, proposals, closing calls.",
                choices: [
                    SurveyChoice(value: "0", label: "0"),
                    SurveyChoice(value: "1_2", label: "1-2"),
                    SurveyChoice(value: "3_5", label: "3-5"),
                    SurveyChoice(value: "6_plus", label: "6+")
                ]
            ),
            localQuestion(
                id: "behavioral_money_leak",
                title: "What is the biggest money leak in your current system?",
                description: nil,
                choices: [
                    SurveyChoice(value: "impulse_spending", label: "Impulse spending"),
                    SurveyChoice(value: "unclear_budget", label: "No clear budget protocol"),
                    SurveyChoice(value: "underpricing", label: "Underpricing my work"),
                    SurveyChoice(value: "inconsistent_saving", label: "Inconsistent saving/investing"),
                    SurveyChoice(value: "no_tracking", label: "No tracking of inflow/outflow")
                ]
            ),
            localQuestion(
                id: "capital_allocation_discipline",
                title: "How disciplined is your capital allocation plan?",
                description: "Capital allocation = where income goes after tax and essentials.",
                choices: [
                    SurveyChoice(value: "strict_rules", label: "Strict rules with automation"),
                    SurveyChoice(value: "mostly_disciplined", label: "Mostly disciplined"),
                    SurveyChoice(value: "inconsistent_rules", label: "Inconsistent"),
                    SurveyChoice(value: "ad_hoc", label: "Mostly ad-hoc")
                ]
            ),
            localQuestion(
                id: "employment_state",
                title: "Which option best describes your current employment status?",
                description: "Atlas uses this to choose promotion vs transition strategy.",
                choices: [
                    SurveyChoice(value: "employed_full_time", label: "Employed full-time"),
                    SurveyChoice(value: "employed_part_time", label: "Employed part-time"),
                    SurveyChoice(value: "freelance_consultant", label: "Freelance/consulting"),
                    SurveyChoice(value: "between_roles", label: "Between roles"),
                    SurveyChoice(value: "student_transition", label: "Student/transition"),
                    SurveyChoice(value: "both_employee_and_business", label: "Employee + business owner")
                ]
            ),
            localQuestion(
                id: "business_state",
                title: "Which option best describes your current business status?",
                description: "This helps Atlas decide whether to prioritize promotions or customer growth.",
                choices: [
                    SurveyChoice(value: "no_business", label: "No business now"),
                    SurveyChoice(value: "idea_stage", label: "Idea stage"),
                    SurveyChoice(value: "pre_revenue", label: "Built but pre-revenue"),
                    SurveyChoice(value: "early_revenue", label: "Early revenue"),
                    SurveyChoice(value: "recurring_revenue", label: "Recurring revenue"),
                    SurveyChoice(value: "scaling_team", label: "Scaling team")
                ]
            ),
            localQuestion(
                id: "growth_priority",
                title: "What should Atlas prioritize first for your wealth growth?",
                description: nil,
                choices: [
                    SurveyChoice(value: "climb_job_ladder", label: "Promotion and salary growth"),
                    SurveyChoice(value: "grow_business_customer_base", label: "Customer growth in business"),
                    SurveyChoice(value: "hybrid_growth", label: "Both in parallel"),
                    SurveyChoice(value: "stabilize_income", label: "Stabilize income first")
                ]
            ),
            localQuestion(
                id: "promotion_horizon",
                title: "If career growth matters, what promotion target fits now?",
                description: nil,
                choices: [
                    SurveyChoice(value: "not_applicable", label: "Not applicable"),
                    SurveyChoice(value: "individual_contributor_to_senior", label: "IC to senior"),
                    SurveyChoice(value: "senior_to_staff", label: "Senior to staff/principal"),
                    SurveyChoice(value: "manager_to_director", label: "Manager to director"),
                    SurveyChoice(value: "executive_track", label: "Executive track")
                ]
            ),
            localQuestion(
                id: "customer_growth_focus",
                title: "If business growth matters, which customer-growth lever is the bottleneck?",
                description: nil,
                choices: [
                    SurveyChoice(value: "not_applicable", label: "Not applicable"),
                    SurveyChoice(value: "offer_clarity", label: "Offer clarity"),
                    SurveyChoice(value: "lead_generation", label: "Lead generation"),
                    SurveyChoice(value: "conversion_rate", label: "Conversion rate"),
                    SurveyChoice(value: "retention_expansion", label: "Retention/expansion"),
                    SurveyChoice(value: "referrals_partnerships", label: "Referrals/partnerships")
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
                id: "wealth_vehicle",
                title: "Which primary wealth route fits you now?",
                description: "Atlas uses this to generate route-specific execution streams.",
                choices: [
                    SurveyChoice(value: "job_ladder", label: "High-paying job ladder"),
                    SurveyChoice(value: "business_builder", label: "Build a business"),
                    SurveyChoice(value: "enterprise_operator", label: "Enterprise/operator career"),
                    SurveyChoice(value: "hybrid", label: "Hybrid: job + business")
                ]
            ),
            localQuestion(
                id: "industry_focus",
                title: "Which industry focus should Atlas prioritize?",
                description: nil,
                choices: [
                    SurveyChoice(value: "software_ai", label: "Software + AI"),
                    SurveyChoice(value: "cybersecurity", label: "Cybersecurity"),
                    SurveyChoice(value: "enterprise_sales", label: "Enterprise sales"),
                    SurveyChoice(value: "healthcare", label: "Healthcare"),
                    SurveyChoice(value: "finance", label: "Finance"),
                    SurveyChoice(value: "operations_logistics", label: "Operations/logistics"),
                    SurveyChoice(value: "real_estate", label: "Real estate"),
                    SurveyChoice(value: "skilled_trades", label: "Skilled trades"),
                    SurveyChoice(value: "media_creator", label: "Media/creator economy")
                ]
            ),
            localQuestion(
                id: "income_engine",
                title: "What income engine do you want to build?",
                description: nil,
                choices: [
                    SurveyChoice(value: "salary_only", label: "Salary growth"),
                    SurveyChoice(value: "salary_plus_projects", label: "Salary + projects"),
                    SurveyChoice(value: "projects_plus_business", label: "Projects + business"),
                    SurveyChoice(value: "portfolio_income", label: "Portfolio income track")
                ]
            ),
            localQuestion(
                id: "high_paying_job_track",
                title: "If job ladder is in play, choose your high-paying track",
                description: nil,
                choices: [
                    SurveyChoice(value: "engineering", label: "Engineering"),
                    SurveyChoice(value: "product", label: "Product"),
                    SurveyChoice(value: "sales", label: "Sales"),
                    SurveyChoice(value: "operations", label: "Operations"),
                    SurveyChoice(value: "finance_track", label: "Finance"),
                    SurveyChoice(value: "real_estate_track", label: "Real estate"),
                    SurveyChoice(value: "clinical", label: "Clinical/health"),
                    SurveyChoice(value: "media_revenue", label: "Media revenue"),
                    SurveyChoice(value: "trade_mastery", label: "Skilled trade mastery"),
                    SurveyChoice(value: "none", label: "Not focused on jobs now")
                ]
            ),
            localQuestion(
                id: "business_model_focus",
                title: "If building a business, which model should Atlas optimize?",
                description: nil,
                choices: [
                    SurveyChoice(value: "agency", label: "Agency"),
                    SurveyChoice(value: "saas", label: "B2B SaaS"),
                    SurveyChoice(value: "ecommerce", label: "E-commerce"),
                    SurveyChoice(value: "local_service", label: "Local service business"),
                    SurveyChoice(value: "education_products", label: "Education products"),
                    SurveyChoice(value: "marketplace", label: "Marketplace"),
                    SurveyChoice(value: "not_now", label: "Not now")
                ]
            ),
            localQuestion(
                id: "monetizable_skill_stack",
                title: "Which monetizable skill stack should Atlas train most aggressively?",
                description: nil,
                choices: [
                    SurveyChoice(value: "ai_automation", label: "AI automation"),
                    SurveyChoice(value: "problem_solving", label: "Problem-solving systems"),
                    SurveyChoice(value: "copywriting", label: "Copywriting/positioning"),
                    SurveyChoice(value: "operations_systems", label: "Operations systems"),
                    SurveyChoice(value: "analytics", label: "Analytics")
                ]
            ),
            localQuestion(
                id: "earnings_target_yearly",
                title: "Target annual income band (3-year horizon)?",
                description: "Used for pacing, opportunity filtering, and execution pressure tuning.",
                choices: [
                    SurveyChoice(value: "under_150k", label: "Under $150k"),
                    SurveyChoice(value: "150k_300k", label: "$150k-$300k"),
                    SurveyChoice(value: "300k_750k", label: "$300k-$750k"),
                    SurveyChoice(value: "750k_plus", label: "$750k+")
                ]
            ),
            localQuestion(
                id: "runway_months",
                title: "Cash runway available right now?",
                description: nil,
                choices: [
                    SurveyChoice(value: "under_3", label: "Under 3 months"),
                    SurveyChoice(value: "3_6", label: "3-6 months"),
                    SurveyChoice(value: "6_12", label: "6-12 months"),
                    SurveyChoice(value: "12_plus", label: "12+ months")
                ]
            ),
            localQuestion(
                id: "compounding_plan",
                title: "Which compounding plan should Atlas enforce by default?",
                description: nil,
                choices: [
                    SurveyChoice(value: "auto_index", label: "Auto-index investing"),
                    SurveyChoice(value: "cash_buffer_then_invest", label: "Cash buffer then invest"),
                    SurveyChoice(value: "business_reinvestment", label: "Business reinvestment"),
                    SurveyChoice(value: "debt_reduction_then_growth", label: "Debt reduction then growth")
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
        if answered >= max(34, localSurveyTotal()) {
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
        let wealthVehicle = surveyAnswers["wealth_vehicle"] ?? "hybrid"
        let industryFocus = surveyAnswers["industry_focus"] ?? "software_ai"
        let businessModel = surveyAnswers["business_model_focus"] ?? "not_now"
        let skillStack = surveyAnswers["monetizable_skill_stack"] ?? "problem_solving"
        let compoundingPlan = surveyAnswers["compounding_plan"] ?? "auto_index"
        let incomeGapPrimary = surveyAnswers["income_gap_primary"] ?? "execution_consistency"
        let sleepQuality = surveyAnswers["brain_sleep_quality"] ?? "inconsistent"
        let focusStability = surveyAnswers["brain_focus_stability"] ?? "variable"
        let stressRegulation = surveyAnswers["brain_stress_regulation"] ?? "slow_recovery"
        let diagnostic = buildWealthBrainDiagnostic()

        let rationale = "Version \(version) generated from new memory signals (survey: \(surveyAnswers.count), notes: \(notes.count), pressure: \(pressure), goal: \(priority), wealth route: \(wealthLabel(for: wealthVehicle)))."
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
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-5",
                prompt: "Your wealth route is \(wealthLabel(for: wealthVehicle)). What should be protected weekly?",
                options: [
                    "Random activity and hope",
                    "A repeatable route sprint with measurable output",
                    "Only strategic planning, no shipping"
                ],
                preferredAnswerIndex: 1,
                explanation: "Wealth routes only compound when execution is measured and repeated."
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-6",
                prompt: "Which compounding protocol should stay automatic by default?",
                options: [
                    "No default, decide emotionally each week",
                    wealthLabel(for: compoundingPlan),
                    "Delay all compounding until perfect conditions"
                ],
                preferredAnswerIndex: 1,
                explanation: "Automatic defaults beat intention-only behavior in long-horizon wealth systems."
            ),
            AdaptiveQuizQuestion(
                id: "q\(version)-7",
                prompt: "Atlas mapped your primary blocker as \(diagnostic.primaryBlockerTitle). What should happen next?",
                options: [
                    diagnostic.immediateProtocol,
                    "Collect more information for weeks before acting",
                    "Switch strategies daily to stay flexible"
                ],
                preferredAnswerIndex: 0,
                explanation: "Fast correction of the primary blocker improves income velocity and reduces drift."
            )
        ]

        let podcastTitle = "Atlas Learning Brief v\(version): Wealth Route + Execution Command"
        let podcastSummary = "A profile-tuned briefing on income route design, compounding systems, resilience discipline, and daily execution."
        let segments = [
            AdaptivePodcastSegment(
                id: "s\(version)-1",
                title: "State of play",
                talkingPoints: [
                    "Current pressure: \(pressure)",
                    "Primary operating objective: \(priority)",
                    "Immediate constraints from your latest memory signals",
                    "Active wealth route: \(wealthLabel(for: wealthVehicle)) in \(wealthLabel(for: industryFocus))"
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
                title: "Wealth route sprint",
                talkingPoints: [
                    wealthRouteSprintDetails(
                        vehicle: wealthVehicle,
                        industry: industryFocus,
                        incomeEngine: surveyAnswers["income_engine"] ?? "salary_plus_projects",
                        jobTrack: surveyAnswers["high_paying_job_track"] ?? "none",
                        businessModel: businessModel,
                        skillStack: skillStack
                    ),
                    "Protect one leverage activity linked to \(wealthLabel(for: skillStack))",
                    "If business path is active, run one offer/distribution experiment this week"
                ]
            ),
            AdaptivePodcastSegment(
                id: "s\(version)-4",
                title: "Compounding and risk control",
                talkingPoints: [
                    compoundingProtocolDetails(plan: compoundingPlan),
                    "Keep an explicit runway policy and avoid operating blind under volatility",
                    "Document one corrective signal and one reinforcement signal each day"
                ]
            ),
            AdaptivePodcastSegment(
                id: "s\(version)-5",
                title: "Brain conditions for wealth execution",
                talkingPoints: [
                    "Primary blocker: \(wealthLabel(for: incomeGapPrimary))",
                    "Brain-state profile: sleep \(wealthLabel(for: sleepQuality)), focus \(wealthLabel(for: focusStability)), stress \(wealthLabel(for: stressRegulation)).",
                    "Immediate protocol: \(diagnostic.immediateProtocol)",
                    "7-day protocol: \(diagnostic.sevenDayProtocol)"
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

    private func markSignedIn(provider: AuthProvider, accountName: String, email: String?) {
        isSignedIn = true
        accountProvider = provider
        seedAccountIdentityIfNeeded(accountName: accountName, email: email)
        accountLabel = resolvedAccountLabel(fallback: accountName)
        billingAccessEnabled = false
        billingStatusMessage = "Add a payment method to unlock cloud AI."
        selectedTier = .localTrial
        persistStateToDisk()
    }

    private func seedAccountIdentityIfNeeded(accountName: String, email: String?) {
        let needsSeed = accountFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountMiddleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && accountUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard needsSeed else { return }

        let parts = accountName
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = parts.first {
            accountFirstName = sanitizeNameComponent(first, maxLength: 40)
        }
        if parts.count > 2 {
            accountMiddleName = sanitizeNameComponent(parts[1], maxLength: 40)
        }
        if parts.count >= 2, let last = parts.last {
            accountLastName = sanitizeNameComponent(last, maxLength: 40)
        }

        if let email {
            let emailLocalPart = email.split(separator: "@").first.map(String.init) ?? ""
            accountUsername = sanitizeUsername(emailLocalPart, maxLength: 32)
        }
    }

    private func sanitizeNameComponent(_ value: String, maxLength: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(maxLength))
    }

    private func sanitizeUsername(_ value: String, maxLength: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let replaced = trimmed.replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
        let collapsed = replaced
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        return String(collapsed.prefix(maxLength))
    }

    private func resolvedAccountLabel(fallback: String) -> String {
        let first = accountFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middle = accountMiddleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = accountLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = accountUsername.trimmingCharacters(in: .whitespacesAndNewlines)

        let fullName = [first, middle, last]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }
        if !username.isEmpty {
            return "@\(username)"
        }

        let cleanFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanFallback.isEmpty ? "Atlas Operator" : cleanFallback
    }

    private static func normalizeProfilePhotoImage(_ image: UIImage) -> UIImage {
        let targetMaxDimension: CGFloat = 2_000
        let sourceSize = image.size
        let maxDimension = max(sourceSize.width, sourceSize.height)
        let resizeScale = maxDimension > targetMaxDimension
            ? (targetMaxDimension / maxDimension)
            : 1.0
        let targetSize = CGSize(
            width: max(1, sourceSize.width * resizeScale),
            height: max(1, sourceSize.height * resizeScale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
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
        var loaded = false

        if let primaryURL = promptQueueFileURL(fileName: queueFileName),
           let data = try? Data(contentsOf: primaryURL),
           let restored = try? decodePromptQueuePayload(data, decoder: decoder)
        {
            promptQueue = restored
            loaded = true
        }

        if !loaded,
           let backupURL = promptQueueFileURL(fileName: queueBackupFileName),
           let data = try? Data(contentsOf: backupURL),
           let restored = try? decodePromptQueuePayload(data, decoder: decoder)
        {
            promptQueue = restored
            persistPromptQueueToDisk()
            loaded = true
        }

        if !loaded,
           let legacy = UserDefaults.standard.data(forKey: queueStorageLegacyKey),
           let restored = try? decoder.decode([PromptQueueItem].self, from: legacy)
        {
            promptQueue = restored
            persistPromptQueueToDisk()
            UserDefaults.standard.removeObject(forKey: queueStorageLegacyKey)
            loaded = true
        }

        if loaded {
            reconcileSessionIDsForLegacyPromptQueue()
            refreshConciergeSessionSnapshots()
            persistPromptQueueToDisk()
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

    private func persistProfilePhotoToDisk() {
        guard let primaryURL = stateFileURL(fileName: profilePhotoFileName) else { return }
        let backupURL = stateFileURL(fileName: profilePhotoBackupFileName)
        let fileManager = FileManager.default

        do {
            let dir = primaryURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            guard let profilePhotoData else {
                _ = try? fileManager.removeItem(at: primaryURL)
                if let backupURL {
                    _ = try? fileManager.removeItem(at: backupURL)
                }
                return
            }

            let encrypted = try SecurePersistence.encrypt(
                profilePhotoData,
                context: "profile_photo",
                appNamespace: "AtlasMasaIOS"
            )

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

    private func restoreProfilePhotoFromDisk() {
        let fileManager = FileManager.default
        let urls = [stateFileURL(fileName: profilePhotoFileName), stateFileURL(fileName: profilePhotoBackupFileName)]

        for url in urls.compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: url.path),
                  let stored = try? Data(contentsOf: url)
            else {
                continue
            }

            let decoded = (try? SecurePersistence.decrypt(
                stored,
                context: "profile_photo",
                appNamespace: "AtlasMasaIOS"
            )) ?? stored

            guard UIImage(data: decoded) != nil else { continue }
            profilePhotoData = decoded

            if url.lastPathComponent == profilePhotoBackupFileName {
                persistProfilePhotoToDisk()
            }
            return
        }
    }

    private func persistStateToDisk() {
        let persistedNotes = memoryCollectionEnabled ? notes : []
        let persistedSurveyAnswers = memoryCollectionEnabled ? surveyAnswers : [:]
        let persistedLearningPackage = memoryCollectionEnabled ? learningPackage : nil
        let persistedWorkspaceMemoryRecords = memoryCollectionEnabled ? workspaceMemoryRecords : []
        let persistedCodingMessages = memoryCollectionEnabled ? codingMessages : []
        let persistedCodingMemoryRecords = memoryCollectionEnabled ? codingMemoryRecords : []
        let persistedConciergeSessions = conciergeSessions
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
            accountFirstName: accountFirstName,
            accountMiddleName: accountMiddleName,
            accountLastName: accountLastName,
            accountUsername: accountUsername,
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
            savedTravelLocations: savedTravelLocations,
            selectedTravelLocationID: selectedTravelLocationID,
            activeTravelItinerary: activeTravelItinerary,
            notes: persistedNotes,
            surveyAnswers: persistedSurveyAnswers,
            surveyQuestionSessionIndex: surveyQuestionSessionIndex,
            surveyQuestionLaneIndex: surveyQuestionLaneIndex,
            noteSessionIndex: noteSessionIndex,
            noteLaneIndex: noteLaneIndex,
            workspaceMemoryRecords: persistedWorkspaceMemoryRecords,
            conciergeSessions: persistedConciergeSessions,
            activeConciergeSessionID: activeConciergeSessionID,
            workspaceSessions: persistedWorkspaceSessions,
            activeWorkspaceLane: activeWorkspaceLane.rawValue,
            activeWorkspaceSessionByLane: persistedActiveSessionMap,
            executionSelectedLane: executionSelectedLane.rawValue,
            codingWorkspaceRootPath: codingWorkspaceRootPath,
            codingWorkspaceFiles: codingWorkspaceFiles,
            codingSelectedFilePath: codingSelectedFilePath,
            codingEditorText: codingEditorText,
            codingEditorIsDirty: codingEditorIsDirty,
            codingMessages: persistedCodingMessages,
            codingMemoryRecords: persistedCodingMemoryRecords,
            codingCommandDraft: codingCommandDraft,
            codingCommandOutput: codingCommandOutput,
            surveyAdditionalPassesCompleted: surveyAdditionalPassesCompleted,
            surveyExpansionQuestionCounter: surveyExpansionQuestionCounter,
            surveyExpansionActive: surveyExpansionActive,
            surveyExpansionQuestionTarget: surveyExpansionQuestionTarget,
            surveyExpansionAnsweredInCurrentPass: surveyExpansionAnsweredInCurrentPass,
            learningPackage: persistedLearningPackage,
            learningVersion: persistedLearningVersion,
            learningFingerprint: persistedLearningFingerprint,
            memoryCollectionEnabled: memoryCollectionEnabled,
            guidedLearningActivated: guidedLearningActivated
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
        accountFirstName = state.accountFirstName ?? ""
        accountMiddleName = state.accountMiddleName ?? ""
        accountLastName = state.accountLastName ?? ""
        accountUsername = state.accountUsername ?? ""
        if isSignedIn {
            accountLabel = resolvedAccountLabel(fallback: accountLabel)
        }
        selectedTier = state.selectedTier
        trialDaysRemaining = max(0, min(state.trialDaysRemaining, SessionStore.localTrialDurationDays))
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
        savedTravelLocations = state.savedTravelLocations ?? []
        selectedTravelLocationID = state.selectedTravelLocationID
        activeTravelItinerary = state.activeTravelItinerary
            ?? TravelItineraryDraft(
                id: "default-travel-itinerary",
                title: "Travel itinerary",
                locationIDs: [],
                updatedAt: isoTimestamp()
            )
        notes = state.notes
        surveyAnswers = state.surveyAnswers ?? [:]
        surveyQuestionSessionIndex = state.surveyQuestionSessionIndex ?? [:]
        surveyQuestionLaneIndex = state.surveyQuestionLaneIndex ?? [:]
        noteSessionIndex = state.noteSessionIndex ?? [:]
        noteLaneIndex = state.noteLaneIndex ?? [:]
        workspaceMemoryRecords = state.workspaceMemoryRecords ?? []
        conciergeSessions = state.conciergeSessions ?? []
        activeConciergeSessionID = state.activeConciergeSessionID
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
        if let rawExecutionLane = state.executionSelectedLane,
           let lane = WorkspaceLane(rawValue: rawExecutionLane)
        {
            executionSelectedLane = lane
        } else {
            executionSelectedLane = activeWorkspaceLane
        }
        codingWorkspaceRootPath = normalizeCodingPath(state.codingWorkspaceRootPath ?? defaultCodingWorkspaceRootPath())
        codingWorkspaceFiles = state.codingWorkspaceFiles ?? []
        codingSelectedFilePath = state.codingSelectedFilePath.map(normalizeCodingPath)
        codingEditorText = state.codingEditorText ?? ""
        codingEditorIsDirty = state.codingEditorIsDirty ?? false
        codingMessages = state.codingMessages ?? []
        codingMemoryRecords = state.codingMemoryRecords ?? []
        codingCommandDraft = state.codingCommandDraft ?? "pwd"
        codingCommandOutput = state.codingCommandOutput ?? ""
        surveyAdditionalPassesCompleted = state.surveyAdditionalPassesCompleted ?? 0
        surveyExpansionQuestionCounter = state.surveyExpansionQuestionCounter ?? 0
        surveyExpansionActive = state.surveyExpansionActive ?? false
        surveyExpansionQuestionTarget = state.surveyExpansionQuestionTarget ?? 0
        surveyExpansionAnsweredInCurrentPass = state.surveyExpansionAnsweredInCurrentPass ?? 0
        learningPackage = state.learningPackage
        learningVersion = state.learningVersion ?? (learningPackage?.version ?? 0)
        learningFingerprint = state.learningFingerprint ?? ""
        memoryCollectionEnabled = state.memoryCollectionEnabled ?? true
        guidedLearningActivated = state.guidedLearningActivated ?? false
        ensureConciergeSessionsSeeded()
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
    var accountFirstName: String?
    var accountMiddleName: String?
    var accountLastName: String?
    var accountUsername: String?
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
    var savedTravelLocations: [SavedTravelLocation]?
    var selectedTravelLocationID: String?
    var activeTravelItinerary: TravelItineraryDraft?
    var notes: [UserNote]
    var surveyAnswers: [String: String]?
    var surveyQuestionSessionIndex: [String: String]?
    var surveyQuestionLaneIndex: [String: String]?
    var noteSessionIndex: [String: String]?
    var noteLaneIndex: [String: String]?
    var workspaceMemoryRecords: [WorkspaceMemoryRecord]?
    var conciergeSessions: [ConciergeChatSession]?
    var activeConciergeSessionID: String?
    var workspaceSessions: [WorkspaceNotebookSession]?
    var activeWorkspaceLane: String?
    var activeWorkspaceSessionByLane: [String: String]?
    var executionSelectedLane: String?
    var codingWorkspaceRootPath: String?
    var codingWorkspaceFiles: [String]?
    var codingSelectedFilePath: String?
    var codingEditorText: String?
    var codingEditorIsDirty: Bool?
    var codingMessages: [CodingWorkspaceMessage]?
    var codingMemoryRecords: [CodingMemoryRecord]?
    var codingCommandDraft: String?
    var codingCommandOutput: String?
    var surveyAdditionalPassesCompleted: Int?
    var surveyExpansionQuestionCounter: Int?
    var surveyExpansionActive: Bool?
    var surveyExpansionQuestionTarget: Int?
    var surveyExpansionAnsweredInCurrentPass: Int?
    var learningPackage: AdaptiveLearningPackage?
    var learningVersion: Int?
    var learningFingerprint: String?
    var memoryCollectionEnabled: Bool?
    var guidedLearningActivated: Bool?
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

private struct ParsedPasskeyRegistrationStart {
    let requestID: String
    let rpID: String
    let challenge: Data
    let userID: Data
    let userName: String
    let userVerification: String?
}

private struct ParsedPasskeyLoginStart {
    let requestID: String
    let rpID: String
    let challenge: Data
    let userVerification: String?
}

private enum AppleAuthFlowError: Int, Error {
    case missingPresentationAnchor
}

private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private let onSuccess: (ASAuthorization) -> Void
    private let onFailure: (Error) -> Void
    private let onFinish: () -> Void
    private var completed = false

    init(
        anchor: ASPresentationAnchor,
        onSuccess: @escaping (ASAuthorization) -> Void,
        onFailure: @escaping (Error) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onFinish = onFinish
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard !completed else { return }
        completed = true
        onSuccess(authorization)
        onFinish()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard !completed else { return }
        completed = true
        onFailure(error)
        onFinish()
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

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        var value = self.littleEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
