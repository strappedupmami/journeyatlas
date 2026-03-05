import AuthenticationServices
import CryptoKit
import Foundation
import Network
import PDFKit
import Security
import UserNotifications

@MainActor
final class SessionStore: ObservableObject {
    private static let localTrialDurationDays = 30

    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Travel Design OS (Swift local tier)..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var pendingPrompt = ""
    @Published var promptQueue: [PromptQueueItem] = []

    @Published var codingWorkspaceRootPath = ""
    @Published var codingWorkspaceFiles: [String] = []
    @Published var codingSelectedFilePath: String?
    @Published var codingEditorText = ""
    @Published var codingEditorIsDirty = false
    @Published var codingPromptDraft = ""
    @Published var codingMessages: [CodingWorkspaceMessage] = []
    @Published var codingMemoryRecords: [CodingMemoryRecord] = []
    @Published var codingCommandDraft = "git status"
    @Published var codingCommandOutput = ""
    @Published var codingIsRunningCommand = false
    @Published var codingIsGeneratingReply = false
    @Published var commandModelBrief = "Model inference will generate a command brief after your check-in."
    @Published var workspaceModelBrief = "Model inference will generate workspace guidance after lane context is available."
    @Published var feedInferenceStatus = "Model inference idle"

    @Published var isSignedIn = false
    @Published var accountProvider: AuthProvider?
    @Published var accountLabel = "Guest Operator"
    @Published var prepaidCreditsActive = false
    @Published var billingStatusMessage = "On-device AI active. Prepay credits to enable optional cloud models."
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
    @Published var knowledgeFiles: [KnowledgeFileRecord] = []
    @Published var workspacePlans: [WorkspacePlan] = []
    @Published var workspaceSessions: [WorkspaceNotebookSession] = []
    @Published var activeWorkspaceLane: WorkspaceLane = .mobilityOps
    @Published var activeWorkspaceSessionByLane: [WorkspaceLane: String] = [:]
    @Published var learningPackage: AdaptiveLearningPackage?
    @Published var memoryCollectionEnabled = true
    @Published var surveyAdditionalPassesCompleted = 0
    @Published var guidedLearningActivated = false
    @Published var adaptiveBusinessQuestionEngineEnabled = true
    @Published var businessAutopilotEnabled = true
    @Published var adaptiveBusinessQuestions: [AdaptiveBusinessQuestion] = []
    @Published var adaptiveBusinessRuntimeStatusLine = "Adaptive business runtime idle."
    @Published var quantumLearningEnabled = true
    @Published var quantumLearningStatusLine = "Quantum learning simulator idle."
    @Published var quantumLearningSnapshot: QuantumLearningSnapshot?
    @Published var natureSignalTiles: [NatureSignalTile] = []
    @Published var natureRiskScore = 0
    @Published var natureRiskBand = "low"
    @Published var natureAlertSummary = "Nature Signal Stack v2 is starting."
    @Published var natureElevatedThreshold = 45
    @Published var natureCriticalThreshold = 70

    @Published var pendingFeedback = ""
    @Published var feedbackOfferEnabled = true

    @Published var wantsRVBuy = false
    @Published var wantsRVRent = false
    @Published var wantsCarBuy = false
    @Published var wantsCarRent = false
    @Published var wantsHomeBuy = false
    @Published var wantsHomeRent = false
    @Published var wantsApartmentBuy = false
    @Published var wantsApartmentRent = false
    @Published var wantsHotelBuy = false
    @Published var wantsHotelRent = false
    @Published var travelRVRegions: [String] = []
    @Published var travelCarRegions: [String] = []
    @Published var travelAccommodationRegions: [String] = []

    @Published var vanRentalNeeded = false
    @Published var travelRegion = ""
    @Published var annualDistanceKM = ""
    @Published var workspaceMode = ""
    @Published var jobMarketOpportunities: [JobOpportunity] = []

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
    private let academicResearchService = AcademicResearchService()
    private let localSyncBlueprintService = LocalSyncBlueprintService()
    private let recoverySupportService = RecoverySupportService()
    private var queueWorkerTask: Task<Void, Never>?
    private var adaptiveBusinessQuestionTask: Task<Void, Never>?
    private var businessAutopilotTask: Task<Void, Never>?
    private var natureSignalTask: Task<Void, Never>?
    private var lastAdaptiveBusinessQuestionAt = Date.distantPast
    private var lastBusinessAutopilotAt = Date.distantPast
    private var lastNatureSignalRefreshAt = Date.distantPast
    private var lastNatureAlertNotificationAt = Date.distantPast
    private var lastWealthReminderNotificationAt = Date.distantPast
    private var adaptiveBusinessAutopilotCursor = 0
    private var networkPathMonitor: NWPathMonitor?
    private var isInternetConnectionAvailable = true
    private var hasLoggedQueueReconnectWait = false
    private var lastResolvedLocalInferenceModel = "llama3.2:latest"
    private var hasLikelyLocalOllamaRoute: Bool {
        Self.detectLikelyOllamaBinary()
    }
    private var localInferencePreferredModelName: String {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if configured?.isEmpty == false {
            return configured!
        }
        return "auto"
    }
    private var localInferenceModelCatalog: [String] {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.catalogKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = configured
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parsed.isEmpty {
            return Self.dedupModels(parsed)
        }
        return [
            "llama3.1:70b",
            "qwen2.5:32b",
            "deepseek-r1:14b",
            "qwen2.5:7b",
            "llama3.2:latest",
        ]
    }
    private var activeMemoryDepth: String {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.memoryDepthKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch configured {
        case "lean":
            return "lean"
        case "deep":
            return "deep"
        default:
            return "balanced"
        }
    }
    private var localInferenceEnabled: Bool {
        if UserDefaults.standard.object(forKey: LocalInferenceDefaults.enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: LocalInferenceDefaults.enabledKey)
    }
    private var localInferenceEndpointURL: URL? {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.endpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "http://127.0.0.1:11434/v1/chat/completions"
        let raw = (configured?.isEmpty == false) ? configured! : fallback
        guard var url = URL(string: raw) else { return nil }

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

    private let queueStorageLegacyKey = "atlas_macos_prompt_queue_v2"
    private let queueFileName = "prompt-queue-v3.json"
    private let queueBackupFileName = "prompt-queue-v3.bak.json"
    private let stateStorageLegacyKey = "atlas_macos_state_v2"
    private let stateFileName = "session-state-v3.json"
    private let stateBackupFileName = "session-state-v3.bak.json"
    private static let checkpointFormatter = ISO8601DateFormatter()
    private enum LocalInferenceDefaults {
        static let enabledKey = "atlas.local.llm.enabled"
        static let endpointKey = "atlas.local.llm.endpoint"
        static let modelKey = "atlas.local.llm.model"
        static let catalogKey = "atlas.local.llm.model_catalog"
        static let memoryDepthKey = "atlas.local.memory.depth"
    }

    private enum GuidedLearningDefaults {
        static let kiwixBaseURLKey = "atlas.guided.learning.kiwix.base_url"
        static let ollamaEndpointKey = "atlas.guided.learning.ollama.endpoint"
        static let ollamaModelKey = "atlas.guided.learning.ollama.model"
    }

    private enum AdaptiveBusinessDefaults {
        static let questionsKey = "atlas.macos.adaptive.business.questions.v1"
        static let questionEngineEnabledKey = "atlas.macos.adaptive.business.questions.enabled"
        static let autopilotEnabledKey = "atlas.macos.adaptive.business.autopilot.enabled"
        static let lastQuestionAtKey = "atlas.macos.adaptive.business.last_question_at"
        static let lastAutopilotAtKey = "atlas.macos.adaptive.business.last_autopilot_at"
        static let autopilotCursorKey = "atlas.macos.adaptive.business.autopilot.cursor"
    }

    private static let adaptiveQuestionLoopIntervalSeconds: TimeInterval = 55
    private static let adaptiveQuestionGenerationCadenceSeconds: TimeInterval = 210
    private static let adaptiveQuestionPendingCap = 3
    private static let adaptiveQuestionHistoryCap = 42
    private static let businessAutopilotLoopIntervalSeconds: TimeInterval = 65
    private static let businessAutopilotCadenceSeconds: TimeInterval = 240
    private static let natureSignalLoopIntervalSeconds: TimeInterval = 180
    private static let natureSignalRefreshCadenceSeconds: TimeInterval = 1_200
    private static let natureAlertCooldownSeconds: TimeInterval = 5_400
    private static let wealthReminderCadenceSeconds: TimeInterval = 14_400

    private struct AdaptiveQuestionModelEnvelope: Codable {
        let question: String
        let options: [String]
    }

    struct QuantumTrackScore: Codable, Hashable {
        let track: String
        let probability: Double
    }

    struct QuantumLearningSnapshot: Codable, Hashable {
        let generatedAtUTC: Date
        let dominantTrack: String
        let dominantProbability: Double
        let trackProbabilities: [QuantumTrackScore]
        let recommendedQuestion: String
        let recommendedOptions: [String]
        let rationale: String
        let source: String
    }

    private struct KiwixGroundingSnapshot {
        let sourceURL: URL
        let snippets: [String]
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
        ensureWorkspaceSessionsSeeded()
        loadPromptQueueFromDisk()
        recoverInterruptedQueueItemsAfterRestart()
        startPromptQueueWorker()
        loadAdaptiveBusinessRuntimeFromDefaults()
        refreshQuantumLearningSnapshot(trigger: "startup")
        startAgenticBusinessRuntime()
        Task { await refreshNatureSignalStackNow(sendNotifications: false) }
    }

    deinit {
        networkPathMonitor?.cancel()
    }

    func bootstrap() async {
        appendOutput(await localReasoning.modelStatusLine())
        appendOutput(localLLMRuntimeStatusLine())
        appendOutput("Academic discovery mode ready: OpenAlex search + abstract scoring + DOI/PDF linking.")
        appendOutput("Local sync blueprint mode ready: USB-C/LAN discovery + mTLS pairing workflow.")
        appendOutput("Recovery support mode ready: long-term relapse prevention guardrails.")
        appendOutput("Active memory management: \(activeMemoryDepth) (set atlas.local.memory.depth = lean|balanced|deep).")
        await refreshHealth()
        await syncSessionFromServerIfAvailable()
        await loadSurvey()
        await loadNotes()
        rebuildInsightsAndExecutionPlan()
        await refreshCommandModelBrief()
        await refreshWorkspaceModelBrief()
        await refreshFeed()
        await refreshNatureSignalStackNow(sendNotifications: false)
        startPromptQueueWorker()
        startAgenticBusinessRuntime()
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API reachable. Capabilities refreshed.")
        } catch {
            appendOutput("API health unavailable. App remains in local-first mode.")
        }
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
        refreshQuantumLearningSnapshot(trigger: "adaptive_response")
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
        if natureSignalTask == nil {
            natureSignalTask = Task { [weak self] in
                await self?.runNatureSignalLoop()
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

    private func runNatureSignalLoop() async {
        while !Task.isCancelled {
            let now = Date()
            if now.timeIntervalSince(lastNatureSignalRefreshAt) >= Self.natureSignalRefreshCadenceSeconds {
                await refreshNatureSignalStackNow(sendNotifications: true)
            }
            let interval = UInt64(Self.natureSignalLoopIntervalSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: interval)
        }
        natureSignalTask = nil
    }

    func refreshNatureSignalStackNow(sendNotifications: Bool = true) async {
        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        var risk = 18
        var uncertaintyPenalty = 0

        let iucnToken = ProcessInfo.processInfo.environment["IUCN_REDLIST_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasIucnToken = !iucnToken.isEmpty
        var tiles: [NatureSignalTile] = [
            NatureSignalTile(
                id: "iucn_red_list_api",
                title: "IUCN Red List API",
                metric: hasIucnToken ? "Token configured" : "Token missing",
                trend: hasIucnToken ? "ready" : "data_blind_spot",
                severity: hasIucnToken ? "info" : "warning",
                sourceLabel: "api.iucnredlist.org",
                sourceURL: "https://api.iucnredlist.org/",
                updatedAtUTC: now
            )
        ]
        if !hasIucnToken {
            risk += 12
        }

        let gbifCurrent = await Self.fetchGBIFOccurrenceCount(year: currentYear)
        let gbifPrevious = await Self.fetchGBIFOccurrenceCount(year: currentYear - 1)
        if let gbifCurrent, let gbifPrevious, gbifPrevious > 0 {
            let deltaPct = (Double(gbifCurrent - gbifPrevious) / Double(gbifPrevious)) * 100.0
            let trend = deltaPct < -8 ? "declining" : deltaPct > 8 ? "rising" : "stable"
            let severity = deltaPct < -15 ? "critical" : deltaPct < -8 ? "warning" : "info"
            tiles.append(
                NatureSignalTile(
                    id: "gbif_occurrence_trend",
                    title: "GBIF occurrence trend",
                    metric: "\(gbifCurrent.formatted()) vs \(gbifPrevious.formatted()) (\(deltaPct >= 0 ? "+" : "")\(String(format: "%.1f", deltaPct))%)",
                    trend: trend,
                    severity: severity,
                    sourceLabel: "api.gbif.org",
                    sourceURL: "https://api.gbif.org/v1/",
                    updatedAtUTC: now
                )
            )
            if deltaPct < -15 {
                risk += 18
            } else if deltaPct < -8 {
                risk += 10
            }
        } else {
            tiles.append(
                NatureSignalTile(
                    id: "gbif_occurrence_trend",
                    title: "GBIF occurrence trend",
                    metric: "Unavailable",
                    trend: "unknown",
                    severity: "warning",
                    sourceLabel: "api.gbif.org",
                    sourceURL: "https://api.gbif.org/v1/",
                    updatedAtUTC: now
                )
            )
            uncertaintyPenalty += 4
        }

        let eonetOpenEvents = await Self.fetchEONETOpenEventsCount()
        if let eonetOpenEvents {
            let trend = eonetOpenEvents >= 120 ? "rising" : eonetOpenEvents <= 50 ? "stable" : "elevated"
            let severity = eonetOpenEvents >= 150 ? "critical" : eonetOpenEvents >= 100 ? "warning" : "info"
            tiles.append(
                NatureSignalTile(
                    id: "nasa_eonet_open_events",
                    title: "NASA EONET open events",
                    metric: "\(eonetOpenEvents) active events",
                    trend: trend,
                    severity: severity,
                    sourceLabel: "eonet.gsfc.nasa.gov",
                    sourceURL: "https://eonet.gsfc.nasa.gov/api/v3/events?status=open",
                    updatedAtUTC: now
                )
            )
            risk += min(22, max(0, eonetOpenEvents / 8))
        } else {
            tiles.append(
                NatureSignalTile(
                    id: "nasa_eonet_open_events",
                    title: "NASA EONET open events",
                    metric: "Unavailable",
                    trend: "unknown",
                    severity: "warning",
                    sourceLabel: "eonet.gsfc.nasa.gov",
                    sourceURL: "https://eonet.gsfc.nasa.gov/api/v3/events?status=open",
                    updatedAtUTC: now
                )
            )
            uncertaintyPenalty += 4
        }

        let hasFirmsKey = !(ProcessInfo.processInfo.environment["NASA_FIRMS_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        tiles.append(
            NatureSignalTile(
                id: "nasa_firms_access",
                title: "NASA FIRMS feed access",
                metric: hasFirmsKey ? "Map key configured" : "Map key missing",
                trend: hasFirmsKey ? "ready" : "blocked",
                severity: hasFirmsKey ? "info" : "warning",
                sourceLabel: "firms.modaps.eosdis.nasa.gov",
                sourceURL: "https://firms.modaps.eosdis.nasa.gov/",
                updatedAtUTC: now
            )
        )
        if !hasFirmsKey {
            risk += 8
        }

        let copernicusReachable = await Self.fetchEndpointHeartbeat(urlString: "https://climate.copernicus.eu/climate-bulletins")
        tiles.append(
            NatureSignalTile(
                id: "copernicus_climate_heartbeat",
                title: "Copernicus climate bulletins",
                metric: copernicusReachable ? "Endpoint reachable" : "Endpoint unavailable",
                trend: copernicusReachable ? "stable" : "degraded",
                severity: copernicusReachable ? "info" : "warning",
                sourceLabel: "climate.copernicus.eu",
                sourceURL: "https://climate.copernicus.eu/climate-bulletins",
                updatedAtUTC: now
            )
        )
        if !copernicusReachable {
            uncertaintyPenalty += 3
        }

        risk = min(100, max(0, risk + uncertaintyPenalty))
        let band: String
        if risk >= natureCriticalThreshold {
            band = "critical"
        } else if risk >= natureElevatedThreshold {
            band = "elevated"
        } else {
            band = "low"
        }

        let summary: String
        switch band {
        case "critical":
            summary = "Nature risk is critical. Increase climate/biodiversity monitoring and tighten wealth execution so donation capacity can scale."
        case "elevated":
            summary = "Nature risk is elevated. Keep mitigation watch active and prioritize disciplined income compounding for future donations."
        default:
            summary = "Nature risk is stable. Maintain monitoring and keep steady wealth creation execution."
        }

        natureSignalTiles = Array(tiles.prefix(5))
        natureRiskScore = risk
        natureRiskBand = band
        natureAlertSummary = summary
        lastNatureSignalRefreshAt = now
        appendOutput("Nature Signal Stack v2 refreshed: \(natureRiskScore)/100 (\(natureRiskBand)).")

        guard sendNotifications else { return }
        await maybeSendNatureRiskAlert(now: now, summary: summary, band: band)
        await maybeSendWealthExecutionReminder(now: now, riskBand: band)
    }

    private func maybeSendNatureRiskAlert(now: Date, summary: String, band: String) async {
        guard natureRiskScore >= natureElevatedThreshold else { return }
        guard now.timeIntervalSince(lastNatureAlertNotificationAt) >= Self.natureAlertCooldownSeconds else { return }

        lastNatureAlertNotificationAt = now
        let title = natureRiskScore >= natureCriticalThreshold
            ? "Atlas Nature Alert: Critical"
            : "Atlas Nature Alert: Elevated"
        let body = "\(summary) Keep business/job execution tight so you can donate more to frontline climate and biodiversity organizations."
        await Self.sendDesktopNotification(title: title, body: body, identifier: "atlas.nature.alert")
    }

    private func maybeSendWealthExecutionReminder(now: Date, riskBand: String) async {
        var items: [String] = []
        if dailyPriority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("set your daily priority")
        }
        if !checkInMadeMoneyToday {
            items.append("run one direct income action")
        }
        if !checkInBlockers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("clear one major blocker")
        }
        guard !items.isEmpty else { return }
        guard now.timeIntervalSince(lastWealthReminderNotificationAt) >= Self.wealthReminderCadenceSeconds else { return }

        lastWealthReminderNotificationAt = now
        let body = "Action needed: \(items.joined(separator: ", ")). Keep wealth creation moving forward so donation power grows while nature risk is \(riskBand)."
        await Self.sendDesktopNotification(title: "Atlas Wealth Execution Reminder", body: body, identifier: "atlas.wealth.reminder")
    }

    private static func fetchGBIFOccurrenceCount(year: Int) async -> Int? {
        guard let url = URL(string: "https://api.gbif.org/v1/occurrence/search?year=\(year)&limit=0") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let count = object["count"] as? Int else {
                return nil
            }
            return max(0, count)
        } catch {
            return nil
        }
    }

    private static func fetchEONETOpenEventsCount() async -> Int? {
        guard let url = URL(string: "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&limit=300") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return nil }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = object["events"] as? [[String: Any]] else {
                return nil
            }
            return events.count
        } catch {
            return nil
        }
    }

    private static func fetchEndpointHeartbeat(urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ... 399).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func sendDesktopNotification(title: String, body: String, identifier: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = String(body.prefix(300))
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try await center.add(request)
        } catch {
            // Best effort only.
        }
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

        refreshQuantumLearningSnapshot(trigger: "adaptive_question")
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

        refreshQuantumLearningSnapshot(trigger: "autopilot")
        let prompt = businessAutopilotPrompt(for: adaptiveBusinessAutopilotCursor)
        let backupDraft = pendingPrompt
        pendingPrompt = sanitizeModelInput(prompt, maxLength: 1800)
        enqueuePrompt()
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
        let quantumContext = quantumLearningDigest(maxLength: 900)

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

            QUANTUM PRIORITY PROFILE
            \(quantumContext)
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

        if let snapshot = quantumLearningSnapshot,
           snapshot.recommendedOptions.count >= 3
        {
            return AdaptiveBusinessQuestion(
                id: UUID().uuidString,
                prompt: snapshot.recommendedQuestion,
                options: Array(snapshot.recommendedOptions.prefix(5)),
                allowsMultipleSelection: true,
                generatedAtUTC: Date(),
                source: "quantum_fallback",
                response: nil
            )
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
        let quantumDirective = quantumAutopilotDirective()
        switch cursor % 3 {
        case 0:
            return """
            \(baseContext)
            Deliverable: Weekly growth operating brief with north-star focus, experiment cadence, and resource allocation.
            \(quantumDirective)
            """
        case 1:
            return """
            \(baseContext)
            Deliverable: Retention and expansion plan with churn diagnosis, onboarding fixes, and NRR recovery path.
            \(quantumDirective)
            """
        default:
            return """
            \(baseContext)
            Deliverable: Platform leverage plan for distribution flywheel, channel sequencing, and conversion architecture.
            \(quantumDirective)
            """
        }
    }

    private func refreshQuantumLearningSnapshot(trigger: String) {
        guard quantumLearningEnabled else {
            quantumLearningSnapshot = nil
            quantumLearningStatusLine = "Quantum learning simulator disabled."
            return
        }

        var amplitudes: [String: Double] = [
            "acquisition": 0.56,
            "conversion": 0.50,
            "retention": 0.46,
            "productization": 0.42,
            "focus_stability": 0.38,
        ]
        func add(_ track: String, _ delta: Double) {
            amplitudes[track, default: 0.20] += delta
        }

        let combinedSignal = [
            dailyPriority,
            midTermGoal,
            longTermVision,
            checkInBlockers,
            surveyAnswers.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            workspaceMemoryRecords.prefix(30).map(\.value).joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()

        if checkInEnergy <= 2 || containsAny(checkInMood, ["stress", "burnout", "anxious", "exhaust"]) {
            add("focus_stability", 0.24)
            add("retention", 0.04)
        }
        if containsAny(combinedSignal, ["lead", "traffic", "pipeline", "prospect", "audience", "distribution"]) {
            add("acquisition", 0.28)
        }
        if containsAny(combinedSignal, ["close", "conversion", "proposal", "pricing", "offer clarity"]) {
            add("conversion", 0.24)
        }
        if containsAny(combinedSignal, ["retention", "churn", "cancel", "renewal", "expansion", "nrr"]) {
            add("retention", 0.24)
        }
        if containsAny(combinedSignal, ["automation", "system", "sop", "playbook", "productize", "agent"]) {
            add("productization", 0.24)
        }
        if containsAny(combinedSignal, ["sleep", "fatigue", "focus", "cognitive", "recovery"]) {
            add("focus_stability", 0.18)
        }

        if surveyAnswers["growth_priority"] == "grow_business_customer_base" {
            add("acquisition", 0.10)
            add("conversion", 0.08)
        }
        if surveyAnswers["customer_growth_focus"] == "retention_expansion" {
            add("retention", 0.12)
        }
        if surveyAnswers["growth_priority"] == "hybrid_growth" || surveyAnswers["wealth_vehicle"] == "hybrid" {
            add("productization", 0.10)
        }

        for key in amplitudes.keys {
            amplitudes[key] = max(0.12, amplitudes[key] ?? 0.12)
        }

        let probabilities = amplitudes
            .mapValues { amplitude in
                let bounded = max(0.12, amplitude)
                return bounded * bounded
            }
        let total = max(0.0001, probabilities.values.reduce(0, +))
        let normalized = probabilities
            .map { (track: $0.key, probability: $0.value / total) }
            .sorted { lhs, rhs in
                if lhs.probability == rhs.probability {
                    return lhs.track < rhs.track
                }
                return lhs.probability > rhs.probability
            }

        guard let dominant = normalized.first else {
            quantumLearningSnapshot = nil
            quantumLearningStatusLine = "Quantum learning simulator could not derive a valid profile."
            return
        }

        let template = quantumQuestionTemplate(for: dominant.track)
        let scored = normalized.map { entry in
            QuantumTrackScore(track: entry.track, probability: entry.probability)
        }
        quantumLearningSnapshot = QuantumLearningSnapshot(
            generatedAtUTC: Date(),
            dominantTrack: dominant.track,
            dominantProbability: dominant.probability,
            trackProbabilities: scored,
            recommendedQuestion: template.prompt,
            recommendedOptions: template.options,
            rationale: template.rationale,
            source: "quantum_simulator_v1"
        )
        quantumLearningStatusLine = "Quantum profile refreshed (\(trigger)): \(quantumTrackLabel(for: dominant.track)) \(Int((dominant.probability * 100).rounded()))%."
    }

    private func quantumLearningDigest(maxLength: Int) -> String {
        guard quantumLearningEnabled else {
            return "Quantum simulator disabled."
        }
        guard let snapshot = quantumLearningSnapshot else {
            return "Quantum simulator has no snapshot yet."
        }

        let priorities = snapshot.trackProbabilities
            .prefix(3)
            .map { "\(quantumTrackLabel(for: $0.track)): \(Int(($0.probability * 100).rounded()))%" }
            .joined(separator: " | ")
        let options = snapshot.recommendedOptions
            .prefix(5)
            .joined(separator: " ; ")
        let digest = """
        Dominant track: \(quantumTrackLabel(for: snapshot.dominantTrack)) (\(Int((snapshot.dominantProbability * 100).rounded()))%).
        Priority distribution: \(priorities)
        Recommended question: \(snapshot.recommendedQuestion)
        Recommended options: \(options)
        Rationale: \(snapshot.rationale)
        """
        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    private func quantumAutopilotDirective() -> String {
        guard let snapshot = quantumLearningSnapshot else {
            return "If uncertain, prioritize one bottleneck with highest expected 14-day compounding impact."
        }
        let topTracks = snapshot.trackProbabilities
            .prefix(2)
            .map { "\(quantumTrackLabel(for: $0.track)) \(Int(($0.probability * 100).rounded()))%" }
            .joined(separator: " -> ")
        return "Quantum directive: weight actions by current probabilities (\(topTracks)). Do not split effort across more than two tracks."
    }

    private func quantumTrackLabel(for track: String) -> String {
        switch track {
        case "acquisition":
            return "Demand acquisition"
        case "conversion":
            return "Conversion velocity"
        case "retention":
            return "Retention and expansion"
        case "productization":
            return "Productization and systems"
        case "focus_stability":
            return "Cognitive focus stability"
        default:
            return track.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func quantumQuestionTemplate(for track: String) -> (prompt: String, options: [String], rationale: String) {
        switch track {
        case "acquisition":
            return (
                "Where should we focus the next 7-day demand-generation sprint?",
                [
                    "Founder-led outbound to top 20 ideal buyers",
                    "Short educational content mapped to top pain point",
                    "Partnership/referral outreach to channel allies",
                    "Offer-led landing page with one clear CTA",
                ],
                "Acquisition signals currently dominate survey and memory context."
            )
        case "conversion":
            return (
                "Which conversion bottleneck should be fixed first this week?",
                [
                    "Tighten discovery script and qualification criteria",
                    "Rewrite offer/pricing for stronger perceived ROI",
                    "Reduce proposal-to-close friction with clear next steps",
                    "Create objection-handling snippets for common blockers",
                ],
                "Conversion friction signals are elevated in the current operating profile."
            )
        case "retention":
            return (
                "What retention move has the highest leverage over the next 14 days?",
                [
                    "Repair onboarding and first-week activation sequence",
                    "Launch proactive check-ins for at-risk users",
                    "Build expansion path from core to premium value",
                    "Instrument churn reasons and close top two causes",
                ],
                "Retention and expansion probabilities are highest in the latest snapshot."
            )
        case "productization":
            return (
                "Which system or automation should be productized first?",
                [
                    "Template the highest-frequency service workflow",
                    "Automate repetitive follow-up and status updates",
                    "Create a reusable SOP with measurable checkpoints",
                    "Package a repeatable offer around one pain category",
                ],
                "Systemization and leverage signals are strongest right now."
            )
        default:
            return (
                "Which action best protects cognitive execution quality this week?",
                [
                    "Reduce task switching to one primary objective/day",
                    "Schedule deep-work blocks before reactive work",
                    "Improve sleep/recovery protocol for 7 days",
                    "Use a strict reflection loop after major decisions",
                ],
                "Focus-stability signals are elevated and should be de-risked first."
            )
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

    func beginGoogleWebSignIn(openURL: (URL) -> Void) async {
        do {
            let response = try await api.startGoogleOAuth(returnTo: "/concierge-local.html")
            guard let url = URL(string: response.authorizeURL) else {
                appendOutput("Google OAuth URL invalid.")
                return
            }
            openURL(url)
            appendOutput("Google OAuth started via web flow.")
        } catch {
            appendOutput("Google OAuth web start failed: \(error.localizedDescription)")
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
        appendOutput("Google sign-in session created locally. Start Google OAuth web flow to sync with backend session.")
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
        prepaidCreditsActive = false
        selectedTier = .localTrial
        billingStatusMessage = "On-device AI active. Prepay credits to enable optional cloud models."
        persistStateToDisk()
        Task {
            _ = try? await api.logout()
        }
        appendOutput("Signed out.")
    }

    func setTier(_ tier: AccountTier) {
        selectedTier = prepaidCreditsActive ? .cloudPro : .localTrial
        persistStateToDisk()
        Task { await refreshFeed() }
        appendOutput(
            prepaidCreditsActive
                ? "Prepaid credits active. Cloud add-on features are available."
                : "Plan selection is disabled. Add prepaid credits to unlock cloud add-on features."
        )
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
            return "Travel"
        case .deepWork:
            return "Cognition"
        case .innovation:
            return "Innovation"
        }
    }

    private func laneModeDescriptor(for lane: WorkspaceLane) -> String? {
        switch lane {
        case .mobilityOps:
            let region = normalizeWorkspaceNameFragment(primaryTravelRegionHint(), maxWords: 3, maxLength: 20)
            let intent = normalizeWorkspaceNameFragment(travelIntentCompactLabel(), maxWords: 4, maxLength: 26)
            if let region, let intent {
                return "\(region) \(intent)"
            }
            return intent ?? region
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
            candidateKeys = [
                "drive_now",
                "drive_frequency",
                "public_transport_usage",
                "travel_state_wanted",
                "car_intent_multi",
                "accommodation_regions_multi",
            ]
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
        if prepaidCreditsActive {
            do {
                let payload = try await api.feedProactive()
                feedItems = payload.items
                feedInferenceStatus = "Cloud proactive feed active"
                appendOutput("Cloud proactive feed refreshed.")
                return
            } catch {
                appendOutput("Cloud feed unavailable. Falling back to local orchestration.")
            }
        }

        if let modelItems = await modelDrivenFeedItems() {
            feedItems = modelItems
            feedInferenceStatus = "Model-generated local feed active"
            appendOutput("Local model generated execution feed.")
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
        guard prepaidCreditsActive else {
            appendOutput("Task checklist sync requires prepaid credits.")
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
        guard prepaidCreditsActive else {
            appendOutput("Task response sync requires prepaid credits.")
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
        await processSurveyAnswer(
            questionID: questionID,
            answerValue: choice.value,
            answerLabel: choice.label
        )
    }

    func answerSurveyMulti(questionID: String, selectedChoices: [SurveyChoice]) async {
        guard !selectedChoices.isEmpty else { return }
        let selectedValues = selectedChoices.map(\.value)
        let selectedLabels = selectedChoices.map(\.label)
        let encodedValue = selectedValues.joined(separator: "|")
        let encodedLabel = selectedLabels.joined(separator: ", ")
        await processSurveyAnswer(
            questionID: questionID,
            answerValue: encodedValue,
            answerLabel: encodedLabel
        )
    }

    private func processSurveyAnswer(
        questionID: String,
        answerValue: String,
        answerLabel: String
    ) async {
        surveyAnswers[questionID] = answerValue
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

        syncTravelProfileFromSurveyAnswers()

        do {
            survey = try await api.submitSurveyAnswer(questionID: questionID, answer: answerValue)
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
                    "Current preference: \(answerLabel)"
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

    func importKnowledgeFiles(urls: [URL]) {
        guard memoryCollectionEnabled else {
            appendOutput("Memory capture is disabled. Re-enable memory to import files.")
            return
        }
        guard !urls.isEmpty else { return }

        var mergedRecords = workspaceMemoryRecords
        var importedCount = 0
        var skippedCount = 0
        let now = Date()

        for sourceURL in urls {
            let hasScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasScope {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let fileName = sourceURL.lastPathComponent
            do {
                let fileData = try Data(contentsOf: sourceURL)
                guard !fileData.isEmpty else {
                    skippedCount += 1
                    appendOutput("Skipped \(fileName): file is empty.")
                    continue
                }

                let rawText = try extractKnowledgeText(from: sourceURL, data: fileData)
                let normalizedText = normalizeKnowledgeText(rawText)
                guard normalizedText.count >= 40 else {
                    skippedCount += 1
                    appendOutput("Skipped \(fileName): not enough readable text.")
                    continue
                }

                let fingerprint = knowledgeFingerprint(for: fileData, fileName: fileName)
                let keyPrefix = "document:\(fingerprint)"
                mergedRecords.removeAll {
                    $0.source == .document && $0.key.hasPrefix(keyPrefix)
                }
                knowledgeFiles.removeAll { $0.id == fingerprint }

                let chunks = knowledgeMemoryChunks(from: normalizedText, maxChunks: 28)
                for (index, chunk) in chunks.enumerated() {
                    upsertWorkspaceMemoryRecord(
                        in: &mergedRecords,
                        lane: nil,
                        sessionID: nil,
                        source: .document,
                        key: "\(keyPrefix):\(index + 1)",
                        value: chunk,
                        weight: 0.84,
                        tags: ["document", "knowledge", sourceURL.pathExtension.lowercased()],
                        now: now
                    )
                }

                let preview = sanitizeWorkspaceMemoryValue(normalizedText, maxLength: 180)
                let fileRecord = KnowledgeFileRecord(
                    id: fingerprint,
                    fileName: fileName,
                    fileType: sourceURL.pathExtension.uppercased().isEmpty ? "FILE" : sourceURL.pathExtension.uppercased(),
                    byteCount: fileData.count,
                    importedAtUTC: now,
                    chunkCount: chunks.count,
                    preview: preview
                )
                knowledgeFiles.insert(fileRecord, at: 0)
                importedCount += 1
            } catch {
                skippedCount += 1
                appendOutput("Skipped \(fileName): \(error.localizedDescription)")
            }
        }

        if importedCount == 0 {
            appendOutput("No files were imported.")
            return
        }

        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(mergedRecords, now: now)
        knowledgeFiles = Array(knowledgeFiles.prefix(72))
        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
        appendOutput("Imported \(importedCount) knowledge file(s). \(skippedCount > 0 ? "\(skippedCount) skipped." : "Global memory updated.")")
    }

    func removeKnowledgeFile(_ fileID: String) {
        let cleanID = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }

        knowledgeFiles.removeAll { $0.id == cleanID }
        workspaceMemoryRecords.removeAll {
            $0.source == .document && $0.key.hasPrefix("document:\(cleanID)")
        }
        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(workspaceMemoryRecords, now: Date())
        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
        appendOutput("Removed knowledge file context.")
    }

    func deleteLocalMemory() {
        notes = []
        promptQueue = []
        codingMessages = []
        codingMemoryRecords = []
        knowledgeFiles = []
        codingPromptDraft = ""
        codingCommandOutput = ""
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
        enqueuePrompt(
            workspaceLane: nil,
            workspaceSessionID: nil
        )
    }

    func enqueueWorkspacePrompt() {
        let lane = activeWorkspaceLane
        let sessionID = activeSessionID(for: lane)
        enqueuePrompt(
            workspaceLane: lane,
            workspaceSessionID: sessionID
        )
    }

    private func enqueuePrompt(
        workspaceLane: WorkspaceLane?,
        workspaceSessionID: String?
    ) {
        let cleaned = pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            appendOutput("Write a prompt before queueing.")
            return
        }

        let safetySignal = evaluateSuspiciousPattern(input: cleaned, source: "prompt")
        if safetySignal.holdQueue {
            appendOutput("Queue is temporarily paused due to high-risk language. Atlas can only support de-escalation, rehabilitation, and safe next steps.")
            return
        }

        promptQueue.append(
            PromptQueueItem(
                id: UUID().uuidString,
                prompt: cleaned,
                workspaceLane: workspaceLane,
                workspaceSessionID: workspaceSessionID,
                retryCount: nil,
                status: .queued,
                createdAt: Date(),
                completedAt: nil,
                errorMessage: nil,
                output: nil
            )
        )
        pendingPrompt = ""
        persistPromptQueueToDisk()
        if let lane = workspaceLane {
            appendOutput("Prompt queued for local background reasoning in \(lane.title).")
        } else {
            if prepaidCreditsActive {
                appendOutput("Prompt queued. Optional cloud add-on is active with on-device fallback.")
            } else {
                appendOutput("Prompt queued for local background reasoning.")
            }
        }
        startPromptQueueWorker()
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
        enqueuePrompt()

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
        persistPromptQueueToDisk()
        appendOutput("Prompt queue cleared.")
    }

    func clearConciergePromptQueue() {
        promptQueue.removeAll { $0.workspaceLane == nil }
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

    private enum CodingCloudRoute: String {
        case frontendDesign = "frontend_design"
        case backendOps = "backend_ops"
    }

    private func ensureCodingCreditsAccess(action: String, addAgentMessage: Bool = true) -> Bool {
        guard prepaidCreditsActive else {
            let status =
                "Code Agent requires prepaid credits. Add credits to enable agentic coding, build troubleshooting, and terminal operations."
            appendOutput("\(action) blocked: prepaid credits are required for the Code section.")
            if addAgentMessage {
                addCodingMessage(role: .system, content: status)
            }
            return false
        }
        return true
    }

    private func classifyCodingCloudRoute(for prompt: String) -> CodingCloudRoute {
        let lower = prompt.lowercased()
        let frontendHints = [
            "frontend", "front-end", "ui", "ux", "css", "tailwind", "layout", "design system",
            "visual", "animation", "typography", "responsive", "component styling"
        ]
        if frontendHints.contains(where: { lower.contains($0) }) {
            return .frontendDesign
        }
        return .backendOps
    }

    private func codingRouteStatusLine(_ route: CodingCloudRoute) -> String {
        switch route {
        case .frontendDesign:
            return "Routing to Gemini 3.1 Pro for frontend design."
        case .backendOps:
            return "Routing to GPT-5.3 Codex for backend, troubleshooting, and build/test work."
        }
    }

    private func composeCloudCodingPrompt(for prompt: String, route: CodingCloudRoute) -> String {
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
        let sharedKnowledgeContext = knowledgeFilesContextDigest(maxLength: 1_500)
        let routeInstruction: String = switch route {
        case .frontendDesign:
            "You are the frontend design lead. Prioritize layout, typography, spacing, color, accessibility, and responsive behavior with production-ready snippets."
        case .backendOps:
            "You are the backend/troubleshooting/build lead. Prioritize root-cause isolation, safe patches, verification commands, and concrete build/test recovery."
        }

        return """
        You are Atlas Agentic Coding Interface.
        \(routeInstruction)
        Return concise implementation output with exact steps and verification.

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

        SHARED KNOWLEDGE FILE CONTEXT:
        \(sharedKnowledgeContext)

        USER REQUEST:
        \(prompt)
        """
    }

    func setCodingWorkspaceRootPath(_ rawPath: String) {
        codingWorkspaceRootPath = normalizeCodingPath(rawPath)
        persistStateToDisk()
    }

    func rescanCodingWorkspace() {
        guard ensureCodingCreditsAccess(action: "Workspace scan") else {
            return
        }
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
        guard ensureCodingCreditsAccess(action: "Open coding file", addAgentMessage: false) else {
            return
        }
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
        guard ensureCodingCreditsAccess(action: "Edit code", addAgentMessage: false) else {
            return
        }
        codingEditorText = text
        codingEditorIsDirty = true
    }

    func saveCodingFile() {
        guard ensureCodingCreditsAccess(action: "Save file") else {
            return
        }
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
            appendOutput("Write a coding prompt before sending.")
            return
        }
        guard !codingIsGeneratingReply else {
            appendOutput("Code Agent is still generating the previous response.")
            return
        }
        guard ensureCodingCreditsAccess(action: "Code Agent request", addAgentMessage: false) else {
            codingPromptDraft = ""
            persistStateToDisk()
            return
        }

        let safetySignal = evaluateSuspiciousPattern(input: prompt, source: "coding_prompt")
        if safetySignal.holdQueue {
            addCodingMessage(
                role: .system,
                content: "Prompt blocked by safety guard. Atlas coding mode only supports lawful, non-harmful work."
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

        let route = classifyCodingCloudRoute(for: prompt)
        addCodingMessage(role: .system, content: codingRouteStatusLine(route))

        let selectedPath = codingSelectedFilePath
        codingIsGeneratingReply = true
        Task {
            do {
                let modelPrompt = composeCloudCodingPrompt(for: prompt, route: route)
                let response = try await api.chat(
                    sessionID: nil,
                    text: modelPrompt,
                    locale: Locale.current.identifier,
                    preferredFormat: "step_by_step",
                    responseDepth: "deep",
                    responseTone: "direct",
                    includeProactive: false,
                    codeAgentRoute: route.rawValue
                )
                let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reply.isEmpty else {
                    throw APIError.invalidResponse
                }
                addCodingMessage(role: .assistant, content: reply, relatedFilePath: selectedPath)
                addCodingMemoryRecord(
                    kind: .response,
                    summary: "Assistant response for latest prompt",
                    detail: reply,
                    relatedFilePath: selectedPath
                )
            } catch {
                let runtimeMessage =
                    "Cloud Code Agent failed. Verify prepaid credits and backend model runtime settings, then retry."
                addCodingMessage(
                    role: .system,
                    content: runtimeMessage,
                    relatedFilePath: selectedPath
                )
                appendOutput(runtimeMessage)
            }
            codingIsGeneratingReply = false
            persistStateToDisk()
        }
    }

    func runCodingCommand(commandOverride: String? = nil) {
        guard ensureCodingCreditsAccess(action: "Terminal command", addAgentMessage: false) else {
            return
        }
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

        Task {
            let startedAt = Date()
            let commandResult = await Self.executeShellCommand(command, workingDirectory: rootPath)
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
        guard ensureCodingCreditsAccess(action: "Memory checkpoint", addAgentMessage: false) else {
            return
        }
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
        let queueBytes = promptQueue.reduce(0) { $0 + $1.prompt.count + ($1.output?.summary.count ?? 0) }
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

    var isAdditionalSurveyPassActive: Bool {
        surveyExpansionActive
    }

    var isGuidedLearningRuntimeActive: Bool {
        guidedLearningActivated && isPrimarySurveyComplete
    }

    func appendOutput(_ line: String) {
        let sanitized = SensitiveDataRedactor.redact(line)
        systemOutput.insert(String(sanitized.prefix(280)), at: 0)
        if systemOutput.count > 40 {
            systemOutput = Array(systemOutput.prefix(40))
        }
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

    private func runPromptQueueLoop() async {
        while !Task.isCancelled {
            guard let index = promptQueue.firstIndex(where: { $0.status == .queued }) else {
                break
            }

            if shouldPauseQueueForInternetReconnect {
                markQueueItemWaitingForInternetReconnect(at: index)
                logQueueReconnectWaitIfNeeded()
                try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                continue
            }
            hasLoggedQueueReconnectWait = false

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
            guard let output = await modelDrivenQueueOutput(item: item, prompt: boundedPrompt, notes: boundedNotes) else {
                checkpointTask.cancel()

                if shouldPauseQueueForInternetReconnect {
                    markQueueItemWaitingForInternetReconnect(at: index)
                    logQueueReconnectWaitIfNeeded()
                    try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                    continue
                }

                promptQueue[index].status = .failed
                promptQueue[index].completedAt = Date()
                promptQueue[index].lastCheckpointAt = Date()
                promptQueue[index].progress = 1.0
                promptQueue[index].checkpointNote = "AI runtime unavailable."
                promptQueue[index].output = nil
                let runtimeMessage = localRuntimeFailureMessage()
                promptQueue[index].errorMessage = runtimeMessage
                persistPromptQueueToDisk()
                appendOutput(runtimeMessage)
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
            promptQueue[index].errorMessage = nil
            persistPromptQueueToDisk()
            if output.model == "atlas-openalex-research-v1" {
                appendOutput("Academic discovery completed. Open top DOI/PDF sources and run citation expansion.")
            } else if output.model == "atlas-local-sync-v1" {
                appendOutput("Local sync blueprint generated. Start with device pairing and certificate trust setup.")
            } else if output.model == "atlas-recovery-support-v1" {
                appendOutput("Recovery support plan generated. Execute the first guardrail immediately.")
            } else if output.model == "atlas-cloud-backend/v1-chat" {
                appendOutput("Shared backend reasoning completed. Next action: \(output.nextAction)")
            } else {
                appendOutput("Local reasoning completed. Next action: \(output.nextAction)")
            }

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

        enum CodingKeys: String, CodingKey {
            case summary
            case nextAction = "next_action"
            case confidence
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

        var label: String {
            switch self {
            case .general:
                return "general"
            case .briefing:
                return "briefing"
            case .structuredJSON:
                return "structured-json"
            case .coding:
                return "coding"
            }
        }

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
            switch self {
            case .coding:
                return true
            default:
                return true
            }
        }

        var policyTaskID: String {
            switch self {
            case .general:
                return "general_reasoning"
            case .briefing:
                return "briefing"
            case .structuredJSON:
                return "structured_json"
            case .coding:
                return "coding"
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

    private struct LocalInferenceRuntimePlan {
        let modelOrder: [String]
        let reasoningMode: String
        let analysisPasses: Int
        let temperature: Double
        let maxTokens: Int
        let numCtx: Int
        let timeoutSeconds: Int
        let statusLine: String
    }

    private func activeMemoryProfile() -> (l1: Int, l2: Int, maxChars: Int) {
        switch activeMemoryDepth {
        case "lean":
            return (4, 8, 700)
        case "deep":
            return (10, 22, 2200)
        default:
            return (6, 14, 1300)
        }
    }

    private func activeMemoryDigestForQueue() -> String {
        let profile = activeMemoryProfile()
        let recentQueue = promptQueue
            .filter { $0.workspaceLane == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(profile.l1)
            .compactMap { item -> String? in
                guard let output = item.output else { return nil }
                let summary = sanitizeWorkspaceMemoryValue(output.summary, maxLength: 110)
                return "- [\(sanitizeWorkspaceMemoryValue(output.model, maxLength: 28))] \(summary)"
            }

        let episodic = workspaceMemoryRecords
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs)
                let rhsScore = workspaceMemoryScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(profile.l2)
            .map { record in
                let label = workspaceSignalLabel(for: record.key)
                return "- [\(record.source.rawValue)] \(sanitizeWorkspaceMemoryValue(label, maxLength: 36)): \(sanitizeWorkspaceMemoryValue(record.value, maxLength: 110))"
            }

        let noteSlice = notes
            .prefix(max(3, profile.l1 - 1))
            .map { note in
                "- \(sanitizeWorkspaceMemoryValue(note.title, maxLength: 50)): \(sanitizeWorkspaceMemoryValue(note.content, maxLength: 100))"
            }

        let digest = """
        Memory depth: \(activeMemoryDepth) (`atlas.local.memory.depth` = lean|balanced|deep)
        L1 Working Memory (recent queue output):
        \(recentQueue.isEmpty ? "- none" : recentQueue.joined(separator: "\n"))

        L2 Episodic Memory (durable high-signal):
        \(episodic.isEmpty ? "- none" : episodic.joined(separator: "\n"))

        L2 Notes Context:
        \(noteSlice.isEmpty ? "- none" : noteSlice.joined(separator: "\n"))

        L3 Archive:
        - workspace memory records: \(workspaceMemoryRecords.count)
        - notes: \(notes.count)
        - prompt queue history: \(promptQueue.count)
        - retrieve from archive if a missing detail blocks action.
        """

        return sanitizeModelInput(digest, maxLength: profile.maxChars)
    }

    private func modelDrivenQueueOutput(item: PromptQueueItem, prompt: String, notes: [UserNote]) async -> LocalReasoningOutput? {
        if let syncOutput = localSyncBlueprintService.buildPlan(prompt: prompt) {
            return syncOutput
        }

        if let recoveryOutput = recoverySupportService.buildPlan(prompt: prompt) {
            return recoveryOutput
        }

        if let researchOutput = await academicResearchService.discover(prompt: prompt) {
            return researchOutput
        }

        let sharedKnowledgeContext = knowledgeFilesContextDigest(maxLength: 1_600)
        let activeMemoryContext = activeMemoryDigestForQueue()
        let notesSnapshot = notes
            .prefix(16)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: 180))" }
            .joined(separator: "\n")

        let instruction = """
        You are Atlas local reasoning engine. Return ONLY valid JSON:
        {"summary":"...","next_action":"...","confidence":0.0}
        Keep summary <= 280 chars and next_action <= 180 chars.

        Prompt:
        \(prompt)

        Notes:
        \(notesSnapshot)

        Active memory management:
        \(activeMemoryContext)

        Shared knowledge files:
        \(sharedKnowledgeContext)
        """

        if prepaidCreditsActive {
            do {
                let response = try await api.chat(
                    sessionID: item.workspaceSessionID,
                    text: instruction,
                    locale: Locale.current.identifier,
                    preferredFormat: "structured_plan",
                    responseDepth: "deep",
                    responseTone: "executive",
                    includeProactive: false
                )
                let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    if let parsed: LocalModelQueueResponse = Self.decodeModelJSON(reply) {
                        let confidence = min(1.0, max(0.0, parsed.confidence ?? 0.67))
                        return LocalReasoningOutput(
                            model: "atlas-cloud-backend/v1-chat",
                            summary: sanitizeWorkspaceMemoryValue(parsed.summary, maxLength: 420),
                            nextAction: sanitizeWorkspaceMemoryValue(parsed.nextAction, maxLength: 220),
                            confidence: confidence,
                            generatedAt: Date()
                        )
                    }

                    let lines = reply
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let summary = sanitizeWorkspaceMemoryValue(
                        lines.first ?? String(reply.prefix(280)),
                        maxLength: 420
                    )
                    let nextAction = lines.first(where: {
                        let lower = $0.lowercased()
                        return lower.contains("next action") || lower.contains("next step") || lower.contains("action")
                    }) ?? "Execute the first concrete action from this response in the next 25 minutes."
                    return LocalReasoningOutput(
                        model: "atlas-cloud-backend/v1-chat",
                        summary: summary,
                        nextAction: sanitizeWorkspaceMemoryValue(nextAction, maxLength: 220),
                        confidence: 0.67,
                        generatedAt: Date()
                    )
                }
            } catch {
                // Shared backend failed; continue with local inference fallback.
            }
        }

        guard let raw = await requestLocalModelResponse(
            prompt: instruction,
            timeoutSeconds: 20,
            domain: .structuredJSON
        ),
              let parsed: LocalModelQueueResponse = Self.decodeModelJSON(raw)
        else {
            return nil
        }

        let confidence = min(1.0, max(0.0, parsed.confidence ?? 0.62))
        return LocalReasoningOutput(
            model: "\(sanitizeWorkspaceMemoryValue(lastResolvedLocalInferenceModel, maxLength: 64))-local",
            summary: sanitizeWorkspaceMemoryValue(parsed.summary, maxLength: 420),
            nextAction: sanitizeWorkspaceMemoryValue(parsed.nextAction, maxLength: 220),
            confidence: confidence,
            generatedAt: Date()
        )
    }

    private func modelDrivenFeedItems() async -> [FeedItem]? {
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
        let sharedKnowledgeContext = knowledgeFilesContextDigest(maxLength: 1_200)

        let instruction = """
        You are Atlas local execution planner.
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

        Shared knowledge files:
        \(sharedKnowledgeContext)
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

        let mapped = parsed.prefix(3).enumerated().map { idx, item in
            FeedItem(
                id: "model-feed-\(idx)-\(UUID().uuidString)",
                title: sanitizeWorkspaceMemoryValue(item.title, maxLength: 110),
                summary: sanitizeWorkspaceMemoryValue(item.summary, maxLength: 260),
                whyNow: sanitizeWorkspaceMemoryValue(item.whyNow, maxLength: 220),
                priority: sanitizeWorkspaceMemoryValue(item.priority, maxLength: 24),
                checklistState: nil
            )
        }
        return mapped
    }

    private func refreshCommandModelBrief() async {
        let prompt = """
        Return one concise command-brief paragraph (< 500 chars) for this operator.
        Focus on immediate execution leverage and risk control.

        Daily: \(dailyPriority)
        Mid-term: \(midTermGoal)
        Long-term: \(longTermVision)
        Blockers: \(checkInBlockers)
        Mood/Energy: \(checkInMood) / \(checkInEnergy)
        Actions: \(executionActions.prefix(6).map { "\($0.horizon): \($0.title)" }.joined(separator: " | "))
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
        let sessionIDs = sessions(for: lane).prefix(4).map(\.title).joined(separator: " | ")
        let prompt = """
        Return one concise workspace brief (< 500 chars).
        Focus lane: \(lane.title)
        Active session names: \(sessionIDs)
        Workspace plan: \(workspacePlans.first(where: { $0.lane == lane })?.objective ?? "No objective yet.")
        Next action now: \(workspacePlans.first(where: { $0.lane == lane })?.nextActionNow ?? "No next action yet.")
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

    private func localLLMRuntimeStatusLine() -> String {
        guard localInferenceEnabled else {
            return "Local LLM bridge disabled via UserDefaults key `atlas.local.llm.enabled`."
        }
        let profile = localReasoningProfile(for: .general, timeoutSeconds: 18)
        if let endpoint = localInferenceEndpointURL {
            let host = endpoint.host ?? "unknown-host"
            let activeModel = lastResolvedLocalInferenceModel
            return "Local LLM bridge enabled: \(host)\(endpoint.path) · preferred model \(localInferencePreferredModelName) · active \(activeModel) · catalog \(localInferenceModelCatalog.count) models · extra-high \(profile.analysisPasses)-pass reasoning active."
        }
        return "Local LLM bridge misconfigured. Check `atlas.local.llm.endpoint`. Direct local runtime fallback remains active."
    }

    private func localRuntimeFailureMessage(prefix: String = "AI runtime unavailable.") -> String {
        guard localInferenceEnabled else {
            return "\(prefix) Local LLM bridge is disabled (`atlas.local.llm.enabled=false`)."
        }

        guard let endpoint = localInferenceEndpointURL else {
            return "\(prefix) `atlas.local.llm.endpoint` is invalid. Set it to `http://127.0.0.1:11434/v1/chat/completions`."
        }

        let endpointLabel = endpoint.absoluteString
        let configuredModel = localInferencePreferredModelName
        let modelHint = configuredModel == "auto"
            ? "auto catalog (\(localInferenceModelCatalog.joined(separator: ", ")))"
            : configuredModel
        if hasLikelyLocalOllamaRoute {
            return "\(prefix) No completion came back from \(endpointLabel) using model policy `\(modelHint)`. Verify `ollama list` and pull at least one catalog model."
        }

        return "\(prefix) No completion came back from \(endpointLabel), and the Ollama CLI was not detected. Install/start Ollama and ensure a binary exists at `/opt/homebrew/bin/ollama` or `/Applications/Ollama.app/Contents/Resources/ollama`."
    }

    private func guidedLearningRuntimeStatusLine() -> String {
        let activation = isGuidedLearningRuntimeActive ? "active" : "locked"
        let ollamaHost = guidedLearningOllamaEndpointURL?.host ?? "invalid-endpoint"
        let kiwixHost = guidedLearningKiwixBaseURL?.host ?? "invalid-endpoint"
        return "Guided learning \(activation). Kiwix host: \(kiwixHost) · Ollama host: \(ollamaHost) · model: \(guidedLearningOllamaModelName)."
    }

    private func localReasoningProfile(
        for domain: LocalInferenceReasoningDomain,
        timeoutSeconds: Int
    ) -> LocalInferenceReasoningProfile {
        let constrained = isResourceConstrained()
        let analysisPasses = constrained ? 2 : 3
        let candidateTimeout = max(8, timeoutSeconds + (constrained ? 2 : 5))
        let synthesisTimeout = max(candidateTimeout, timeoutSeconds + (constrained ? 4 : 8))

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

    private func resolveLocalInferenceRuntimePlan(
        task: String,
        fallbackTemperature: Double,
        fallbackMaxTokens: Int,
        fallbackTimeoutSeconds: Int
    ) async -> LocalInferenceRuntimePlan {
        let constrained = isResourceConstrained()
        let preferred = localInferencePreferredModelName
        var modelOrder = [String]()

        func addModel(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !modelOrder.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                modelOrder.append(trimmed)
            }
        }

        if preferred.caseInsensitiveCompare("auto") != .orderedSame {
            addModel(preferred)
        }
        for model in localInferenceModelCatalog {
            addModel(model)
        }
        if modelOrder.isEmpty {
            modelOrder = ["llama3.2:latest"]
        }

        var plan = LocalInferenceRuntimePlan(
            modelOrder: modelOrder,
            reasoningMode: constrained ? "fast" : "standard",
            analysisPasses: constrained ? 1 : 2,
            temperature: min(0.95, max(0.0, fallbackTemperature)),
            maxTokens: max(220, fallbackMaxTokens),
            numCtx: constrained ? 8192 : 12288,
            timeoutSeconds: max(8, fallbackTimeoutSeconds),
            statusLine: "Fallback policy active (Rust policy unavailable)."
        )

        if let policy = await requestRustInferencePolicy(task: task, preferredModel: preferred) {
            var ordered = [String]()
            if preferred.caseInsensitiveCompare("auto") != .orderedSame {
                ordered.append(preferred)
            }
            ordered.append(policy.selectedModel)
            ordered.append(contentsOf: policy.fallbackModels)
            ordered.append(contentsOf: localInferenceModelCatalog)
            plan = LocalInferenceRuntimePlan(
                modelOrder: Self.dedupModels(ordered),
                reasoningMode: policy.reasoningMode,
                analysisPasses: min(6, max(1, policy.analysisPasses)),
                temperature: min(0.95, max(0.0, policy.temperature)),
                maxTokens: max(220, policy.maxTokens),
                numCtx: max(4096, policy.numCtx),
                timeoutSeconds: max(8, policy.timeoutSeconds),
                statusLine: policy.statusLine
            )
        }

        if task == "adaptive_question" {
            plan = LocalInferenceRuntimePlan(
                modelOrder: plan.modelOrder,
                reasoningMode: plan.reasoningMode,
                analysisPasses: min(2, plan.analysisPasses),
                temperature: plan.temperature,
                maxTokens: min(720, plan.maxTokens),
                numCtx: plan.numCtx,
                timeoutSeconds: plan.timeoutSeconds,
                statusLine: plan.statusLine
            )
        }
        return plan
    }

    private func requestRustInferencePolicy(task: String, preferredModel: String) async -> RustPolicyResponse? {
        guard let binaryPath = Self.resolvedRustReasonerBinaryPath() else { return nil }

        let snapshot = localInferenceHardwareSnapshot()
        let request = RustPolicyRequest(
            platform: "macos",
            task: task,
            cpuCores: snapshot.cpuCores,
            memoryGb: snapshot.memoryGb,
            highPerformance: snapshot.highPerformance,
            preferredModel: preferredModel,
            modelCatalog: localInferenceModelCatalog
        )

        return await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let token = UUID().uuidString
            let outURL = fm.temporaryDirectory.appendingPathComponent("atlas-rust-policy-\(token)").appendingPathExtension("out")
            let errURL = fm.temporaryDirectory.appendingPathComponent("atlas-rust-policy-\(token)").appendingPathExtension("err")
            fm.createFile(atPath: outURL.path, contents: nil)
            fm.createFile(atPath: errURL.path, contents: nil)

            guard let outHandle = try? FileHandle(forWritingTo: outURL),
                  let errHandle = try? FileHandle(forWritingTo: errURL)
            else {
                try? fm.removeItem(at: outURL)
                try? fm.removeItem(at: errURL)
                return nil
            }

            defer {
                try? outHandle.close()
                try? errHandle.close()
                try? fm.removeItem(at: outURL)
                try? fm.removeItem(at: errURL)
            }

            guard let payload = try? JSONEncoder().encode(request) else { return nil }

            let inputPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["policy"]
            process.standardInput = inputPipe
            process.standardOutput = outHandle
            process.standardError = errHandle

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(payload)
                try? inputPipe.fileHandleForWriting.close()

                let timeoutAt = Date().addingTimeInterval(4.0)
                while process.isRunning {
                    if Date() >= timeoutAt {
                        process.terminate()
                        return nil
                    }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }

                guard process.terminationStatus == 0 else { return nil }
                let data = (try? Data(contentsOf: outURL)) ?? Data()
                guard !data.isEmpty else { return nil }
                return try? JSONDecoder().decode(RustPolicyResponse.self, from: data)
            } catch {
                return nil
            }
        }.value
    }

    private func localInferenceHardwareSnapshot() -> (cpuCores: Int, memoryGb: Int, highPerformance: Bool) {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let memoryGb = max(4, Int(memoryBytes / (1024 * 1024 * 1024)))
        let highPerformance = cores >= 12 && memoryGb >= 24 && !isResourceConstrained()
        return (cores, memoryGb, highPerformance)
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

    private func globalReasoningContextDigest(maxLength: Int = 6200) -> String {
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
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\(sanitizeWorkspaceMemoryValue($0.value, maxLength: 56))" }
            .joined(separator: " | ")
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
        let knowledgeSlice = knowledgeFilesContextDigest(maxLength: 1_800)
        let quantumSlice = quantumLearningDigest(maxLength: 720)

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

        SURVEY SIGNALS (FULL SNAPSHOT)
        \(surveySlice.isEmpty ? "- none yet" : surveySlice)

        MEMORY SIGNALS
        \(memorySlice)

        KNOWLEDGE FILE SIGNALS
        \(knowledgeSlice)

        QUANTUM PRIORITY PROFILE
        \(quantumSlice)
        """

        return sanitizeModelInput(bundle, maxLength: maxLength)
    }

    private func knowledgeFilesContextDigest(maxLength: Int = 2200) -> String {
        let fileMeta = knowledgeFiles
            .prefix(12)
            .map { file in
                "- \(file.fileName) [\(file.fileType)] chunks:\(file.chunkCount) size:\(file.byteCount)"
            }
            .joined(separator: "\n")

        let chunkSignals = workspaceMemoryRecords
            .filter { $0.source == .document }
            .sorted { lhs, rhs in
                let lhsScore = workspaceMemoryScore(lhs)
                let rhsScore = workspaceMemoryScore(rhs)
                if lhsScore == rhsScore {
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                return lhsScore > rhsScore
            }
            .prefix(22)
            .map { "- \(workspaceSignalLabel(for: $0.key)): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 110))" }
            .joined(separator: "\n")

        let digest = """
        FILE INDEX
        \(fileMeta.isEmpty ? "- No uploaded knowledge files." : fileMeta)

        FILE EXCERPTS
        \(chunkSignals.isEmpty ? "- No extracted file excerpts." : chunkSignals)
        """

        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    private func composeDeepReasoningEnvelope(
        taskPrompt: String,
        domain: LocalInferenceReasoningDomain
    ) -> String {
        let contextBlock = domain.includeGlobalContext ? globalReasoningContextDigest() : ""
        let contextSection = contextBlock.isEmpty ? "" : "\n\(contextBlock)\n"

        return """
        You are Atlas local inference core running in extra-high reasoning depth mode.
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
        domain: LocalInferenceReasoningDomain = .general
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
                domain: domain
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
            domain: domain
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
        domain: LocalInferenceReasoningDomain
    ) async -> String? {
        let plan = await resolveLocalInferenceRuntimePlan(
            task: domain.policyTaskID,
            fallbackTemperature: temperature,
            fallbackMaxTokens: maxTokens,
            fallbackTimeoutSeconds: timeoutSeconds
        )
        let runtimeTemperature = min(0.95, max(0.0, plan.temperature))
        let runtimeMaxTokens = max(220, plan.maxTokens)
        let runtimeNumCtx = max(2048, plan.numCtx)
        let runtimeTimeout = max(4, plan.timeoutSeconds)
        for model in plan.modelOrder {
            lastResolvedLocalInferenceModel = model
            if let endpoint = localInferenceEndpointURL,
               let localEndpointOutput = await Self.runOpenAICompatiblePrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   systemPrompt: "You are Atlas local reasoning engine. Operate at extra-high depth and return only final answers."
               )
            {
                return localEndpointOutput
            }

            if let endpoint = localInferenceEndpointURL,
               isLoopbackHost(endpoint.host),
               let ollamaNativeOutput = await Self.runOllamaNativeChatPrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   numCtx: runtimeNumCtx,
                   systemPrompt: "You are Atlas local reasoning engine. Operate at extra-high depth and return only final answers."
               )
            {
                return ollamaNativeOutput
            }

            if let ollamaOutput = await Self.runOllamaPrompt(
                model: model,
                prompt: prompt,
                timeoutSeconds: runtimeTimeout
            ) {
                return ollamaOutput
            }
        }
        return nil
    }

    private func requestGuidedLearningOllama(prompt: String, timeoutSeconds: Int) async -> String? {
        guard let endpoint = guidedLearningOllamaEndpointURL else { return nil }
        let preferred = guidedLearningOllamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let policy = await requestRustInferencePolicy(task: "adaptive_question", preferredModel: preferred)
        let runtimeTemperature = min(0.95, max(0.0, policy?.temperature ?? 0.22))
        let runtimeTokens = max(220, min(1500, policy?.maxTokens ?? 1300))
        let runtimeNumCtx = max(2048, policy?.numCtx ?? 8192)
        let runtimeTimeout = max(timeoutSeconds, policy?.timeoutSeconds ?? timeoutSeconds)

        var modelOrder = [String]()
        if !preferred.isEmpty {
            modelOrder.append(preferred)
        }
        if let policy {
            modelOrder.append(policy.selectedModel)
            modelOrder.append(contentsOf: policy.fallbackModels)
        }
        modelOrder.append(contentsOf: localInferenceModelCatalog)
        modelOrder = Self.dedupModels(modelOrder)
        if modelOrder.isEmpty {
            modelOrder = ["llama3.2:latest"]
        }

        for model in modelOrder {
            lastResolvedLocalInferenceModel = model
            if let openAIOutput = await Self.runOpenAICompatiblePrompt(
                endpoint: endpoint,
                model: model,
                prompt: prompt,
                timeoutSeconds: runtimeTimeout,
                temperature: runtimeTemperature,
                maxTokens: runtimeTokens,
                systemPrompt: "You are Atlas guided learning copilot. Ground responses in provided Kiwix snippets and personalize to user context."
            ) {
                return openAIOutput
            }

            if isLoopbackHost(endpoint.host),
               let ollamaNativeOutput = await Self.runOllamaNativeChatPrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeTokens,
                   numCtx: runtimeNumCtx,
                   systemPrompt: "You are Atlas guided learning copilot. Ground responses in provided Kiwix snippets and personalize to user context."
               )
            {
                return ollamaNativeOutput
            }
        }

        return nil
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
                let fallback = String(decoding: data, as: UTF8.self)
                return fallback.isEmpty ? nil : fallback
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
        let fencePattern = "```"
        var candidates: [String] = []

        if let firstFence = text.range(of: fencePattern),
           let secondFence = text.range(of: fencePattern, range: firstFence.upperBound..<text.endIndex)
        {
            var fenced = String(text[firstFence.upperBound..<secondFence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if fenced.lowercased().hasPrefix("json") {
                let prefix = fenced.index(fenced.startIndex, offsetBy: min(4, fenced.count))
                fenced = fenced[prefix...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !fenced.isEmpty {
                candidates.append(String(fenced))
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
        var start: String.Index?
        var depth = 0
        for idx in text.indices {
            let ch = text[idx]
            if ch == open {
                if start == nil {
                    start = idx
                }
                depth += 1
            } else if ch == close, start != nil {
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...idx])
                }
            }
        }
        return nil
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

    private func logQueueReconnectWaitIfNeeded() {
        guard !hasLoggedQueueReconnectWait else { return }
        hasLoggedQueueReconnectWait = true
        appendOutput("No internet connection. Waiting to reconnect before continuing queued AI requests.")
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

    private func inferencePipelineRequiresInternetConnection() -> Bool {
        guard let endpoint = localInferenceEndpointURL else { return false }
        if isLoopbackHost(endpoint.host) {
            return false
        }
        return !hasLikelyLocalOllamaRoute
    }

    private func isLoopbackHost(_ host: String?) -> Bool {
        let normalized = (host ?? "").lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1"
    }

    private func configureNetworkPathMonitor() {
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor
        let queue = DispatchQueue(label: "com.atlasmasa.macos.network-path")
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
                    self.appendOutput("Internet connection lost. Waiting to reconnect before continuing queued AI requests.")
                }
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated private static func detectLikelyOllamaBinary() -> Bool {
        !candidateOllamaBinaryPaths().isEmpty
    }

    nonisolated private static func candidateOllamaBinaryPaths() -> [String] {
        let fileManager = FileManager.default
        let homeDirectory = NSHomeDirectory()
        let hardcodedCandidates = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/opt/homebrew/opt/ollama/bin/ollama",
            "/usr/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "/Applications/Ollama.app/Contents/MacOS/ollama",
            "\(homeDirectory)/.ollama/bin/ollama",
            "\(homeDirectory)/.local/bin/ollama",
        ]
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = pathValue
            .split(separator: ":")
            .map { String($0) + "/ollama" }
        let allCandidates = hardcodedCandidates + pathCandidates
        var seen = Set<String>()
        var executable: [String] = []
        for candidate in allCandidates {
            guard seen.insert(candidate).inserted else { continue }
            if fileManager.isExecutableFile(atPath: candidate) {
                executable.append(candidate)
            }
        }
        return executable
    }

    nonisolated private static func resolvedOllamaBinaryPath() -> String? {
        candidateOllamaBinaryPaths().first
    }

    nonisolated private static func candidateRustReasonerBinaryPaths() -> [String] {
        let fileManager = FileManager.default
        let homeDirectory = NSHomeDirectory()

        var candidates: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["ATLAS_RUST_REASONER_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPath.isEmpty
        {
            candidates.append(envPath)
        }

        if let resourcePath = Bundle.main.resourcePath {
            candidates.append("\(resourcePath)/atlas-rust-reasoner")
        }

        candidates.append(contentsOf: [
            "/usr/local/bin/atlas-rust-reasoner",
            "/opt/homebrew/bin/atlas-rust-reasoner",
            "\(homeDirectory)/.local/bin/atlas-rust-reasoner",
            "\(homeDirectory)/.cargo/bin/atlas-rust-reasoner",
        ])

        var cursorURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0 ..< 10 {
            candidates.append(
                cursorURL
                    .appendingPathComponent("windows-app")
                    .appendingPathComponent("rust-atlas-reasoner")
                    .appendingPathComponent("target")
                    .appendingPathComponent("release")
                    .appendingPathComponent("atlas-rust-reasoner")
                    .path
            )
            let parent = cursorURL.deletingLastPathComponent()
            if parent.path == cursorURL.path {
                break
            }
            cursorURL = parent
        }

        var seen = Set<String>()
        var executable: [String] = []
        for candidate in candidates {
            guard seen.insert(candidate).inserted else { continue }
            if fileManager.isExecutableFile(atPath: candidate) {
                executable.append(candidate)
            }
        }
        return executable
    }

    nonisolated private static func resolvedRustReasonerBinaryPath() -> String? {
        candidateRustReasonerBinaryPaths().first
    }

    nonisolated private static func dedupModels(_ models: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                ordered.append(trimmed)
            }
        }
        return ordered
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

    nonisolated private static func executeShellCommand(_ command: String, workingDirectory: String) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let outputURL = fm.temporaryDirectory
                .appendingPathComponent("atlas-coding-\(UUID().uuidString)")
                .appendingPathExtension("log")
            fm.createFile(atPath: outputURL.path, contents: nil)
            guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
                return (1, "Failed to create output capture file.")
            }
            defer {
                try? outputHandle.close()
                try? fm.removeItem(at: outputURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            process.standardOutput = outputHandle
            process.standardError = outputHandle

            do {
                try process.run()
                process.waitUntilExit()
                outputHandle.synchronizeFile()
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let decoded = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                return (process.terminationStatus, Self.trimForDisplay(trimmed, maxChars: 24_000))
            } catch {
                return (1, "Failed to run command: \(error.localizedDescription)")
            }
        }.value
    }

    nonisolated private static func trimForDisplay(_ value: String, maxChars: Int) -> String {
        guard value.count > maxChars else { return value }
        let start = value.index(value.endIndex, offsetBy: -maxChars)
        return "...truncated...\n" + value[start...]
    }

    private func normalizeCodingPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
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

    private func extractKnowledgeText(from sourceURL: URL, data: Data) throws -> String {
        let ext = sourceURL.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(data: data) else {
                throw NSError(domain: "AtlasKnowledgeImport", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Unreadable PDF document."
                ])
            }
            var pages: [String] = []
            pages.reserveCapacity(max(1, document.pageCount))
            for index in 0 ..< document.pageCount {
                guard let page = document.page(at: index) else { continue }
                if let content = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                    pages.append(content)
                }
            }
            return pages.joined(separator: "\n")
        }

        if let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func normalizeKnowledgeText(_ raw: String) -> String {
        let collapsedWhitespace = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[\\t\\f ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizeWorkspaceMemoryValue(collapsedWhitespace, maxLength: 120_000)
    }

    private func knowledgeMemoryChunks(from text: String, maxChunks: Int) -> [String] {
        guard !text.isEmpty, maxChunks > 0 else { return [] }
        let parts = text
            .components(separatedBy: CharacterSet(charactersIn: "\n."))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return [sanitizeWorkspaceMemoryValue(text, maxLength: 180)]
        }

        var chunks: [String] = []
        var buffer = ""
        for sentence in parts {
            if buffer.isEmpty {
                buffer = sentence
                continue
            }
            let candidate = "\(buffer). \(sentence)"
            if candidate.count > 170 {
                chunks.append(sanitizeWorkspaceMemoryValue(buffer, maxLength: 180))
                buffer = sentence
                if chunks.count >= maxChunks {
                    break
                }
            } else {
                buffer = candidate
            }
        }
        if chunks.count < maxChunks, !buffer.isEmpty {
            chunks.append(sanitizeWorkspaceMemoryValue(buffer, maxLength: 180))
        }

        return Array(chunks.filter { !$0.isEmpty }.prefix(maxChunks))
    }

    private func knowledgeFingerprint(for data: Data, fileName: String) -> String {
        let digest = SHA256.hash(data: data)
        let digestText = digest.map { String(format: "%02x", $0) }.joined()
        let nameToken = fileName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let shortDigest = String(digestText.prefix(16))
        if nameToken.isEmpty {
            return shortDigest
        }
        return "\(shortDigest)-\(String(nameToken.prefix(20)))"
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
                content: "Agent commands: /scan, /open <path>, /save, /run <shell>, /grep <pattern>, /remember"
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

    nonisolated private static func runOllamaPrompt(model: String, prompt: String, timeoutSeconds: Int) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let ollamaBinaryPath = Self.resolvedOllamaBinaryPath() else {
                return nil
            }
            let fm = FileManager.default
            let token = UUID().uuidString
            let outURL = fm.temporaryDirectory.appendingPathComponent("atlas-ollama-\(token)").appendingPathExtension("out")
            let errURL = fm.temporaryDirectory.appendingPathComponent("atlas-ollama-\(token)").appendingPathExtension("err")
            fm.createFile(atPath: outURL.path, contents: nil)
            fm.createFile(atPath: errURL.path, contents: nil)

            guard let outHandle = try? FileHandle(forWritingTo: outURL),
                  let errHandle = try? FileHandle(forWritingTo: errURL)
            else {
                return nil
            }

            defer {
                try? outHandle.close()
                try? errHandle.close()
                try? fm.removeItem(at: outURL)
                try? fm.removeItem(at: errURL)
            }

            let inputPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaBinaryPath)
            process.arguments = ["run", model]
            process.standardInput = inputPipe
            process.standardOutput = outHandle
            process.standardError = errHandle

            do {
                try process.run()
                if let data = (prompt + "\n").data(using: .utf8) {
                    inputPipe.fileHandleForWriting.write(data)
                }
                try? inputPipe.fileHandleForWriting.close()

                let timeoutAt = Date().addingTimeInterval(TimeInterval(max(2, timeoutSeconds)))
                while process.isRunning {
                    if Date() >= timeoutAt {
                        process.terminate()
                        return nil
                    }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                outHandle.synchronizeFile()
                errHandle.synchronizeFile()

                guard process.terminationStatus == 0 else {
                    return nil
                }

                let outData = (try? Data(contentsOf: outURL)) ?? Data()
                let output = String(data: outData, encoding: .utf8) ?? String(decoding: outData, as: UTF8.self)
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return Self.trimForDisplay(trimmed, maxChars: 18_000)
            } catch {
                return nil
            }
        }.value
    }

    private struct OpenAIChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct RustPolicyRequest: Encodable {
        let platform: String
        let task: String
        let cpuCores: Int
        let memoryGb: Int
        let highPerformance: Bool
        let preferredModel: String
        let modelCatalog: [String]

        enum CodingKeys: String, CodingKey {
            case platform
            case task
            case cpuCores = "cpu_cores"
            case memoryGb = "memory_gb"
            case highPerformance = "high_performance"
            case preferredModel = "preferred_model"
            case modelCatalog = "model_catalog"
        }
    }

    private struct RustPolicyResponse: Decodable {
        let selectedModel: String
        let fallbackModels: [String]
        let reasoningMode: String
        let analysisPasses: Int
        let temperature: Double
        let maxTokens: Int
        let numCtx: Int
        let timeoutSeconds: Int
        let hardwareTier: String
        let statusLine: String

        enum CodingKeys: String, CodingKey {
            case selectedModel = "selected_model"
            case fallbackModels = "fallback_models"
            case reasoningMode = "reasoning_mode"
            case analysisPasses = "analysis_passes"
            case temperature
            case maxTokens = "max_tokens"
            case numCtx = "num_ctx"
            case timeoutSeconds = "timeout_seconds"
            case hardwareTier = "hardware_tier"
            case statusLine = "status_line"
        }
    }

    private struct OpenAIChatRequest: Encodable {
        let model: String
        let messages: [OpenAIChatMessage]
        let temperature: Double
        let maxTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
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

    private struct OllamaChatRequest: Encodable {
        struct Options: Encodable {
            let temperature: Double
            let numPredict: Int
            let numCtx: Int

            enum CodingKeys: String, CodingKey {
                case temperature
                case numPredict = "num_predict"
                case numCtx = "num_ctx"
            }
        }

        let model: String
        let messages: [OpenAIChatMessage]
        let stream: Bool
        let options: Options
    }

    private struct OllamaChatResponse: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        let message: Message?
        let response: String?
    }

    nonisolated private static func runOpenAICompatiblePrompt(
        endpoint: URL,
        model: String,
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

            let payload = OpenAIChatRequest(
                model: model,
                messages: [
                    OpenAIChatMessage(role: "system", content: systemPrompt),
                    OpenAIChatMessage(role: "user", content: prompt)
                ],
                temperature: min(0.95, max(0.0, temperature)),
                maxTokens: max(220, maxTokens),
                stream: false
            )
            guard let body = try? JSONEncoder().encode(payload) else { return nil }
            request.httpBody = body

            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = request.timeoutInterval
            config.timeoutIntervalForResource = request.timeoutInterval + 6
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode),
                      let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                else {
                    return nil
                }

                let content = decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? decoded.choices.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                guard !content.isEmpty else { return nil }
                return Self.trimForDisplay(content, maxChars: 18_000)
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func runOllamaNativeChatPrompt(
        endpoint: URL,
        model: String,
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        numCtx: Int,
        systemPrompt: String
    ) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                return nil
            }
            let originalPath = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if originalPath.isEmpty || originalPath == "/" || originalPath == "/v1/chat/completions" {
                components.path = "/api/chat"
            }
            guard let nativeEndpoint = components.url else { return nil }

            var request = URLRequest(url: nativeEndpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(4, timeoutSeconds))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

            let payload = OllamaChatRequest(
                model: model,
                messages: [
                    OpenAIChatMessage(role: "system", content: systemPrompt),
                    OpenAIChatMessage(role: "user", content: prompt)
                ],
                stream: false,
                options: OllamaChatRequest.Options(
                    temperature: min(0.95, max(0.0, temperature)),
                    numPredict: max(220, maxTokens),
                    numCtx: max(2048, numCtx)
                )
            )
            guard let body = try? JSONEncoder().encode(payload) else { return nil }
            request.httpBody = body

            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = request.timeoutInterval
            config.timeoutIntervalForResource = request.timeoutInterval + 6
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200 ... 299).contains(http.statusCode),
                      let decoded = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
                else {
                    return nil
                }

                let content = decoded.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? ""
                guard !content.isEmpty else { return nil }
                return Self.trimForDisplay(content, maxChars: 18_000)
            } catch {
                return nil
            }
        }.value
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
        refreshWorkspaceSessionSnapshots()
        workspacePlans = buildWorkspacePlans(from: researchStreams, memoryRecords: workspaceMemoryRecords)
        refreshAdaptiveLearningPackageIfNeeded()
        refreshQuantumLearningSnapshot(trigger: "context_rebuild")
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

        if hasAnyTravelIntent() {
            let regionSummary = combinedTravelRegions().isEmpty
                ? "No regions selected yet"
                : combinedTravelRegions().joined(separator: ", ")
            actions.append(
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Travel",
                    title: "Finalize travel requirements",
                    details: "Intent: \(travelIntentCompactLabel()) · Regions: \(regionSummary)",
                    priority: 2,
                    source: "travel",
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
        let needsMobilityOps = hasAnyTravelIntent()
            || containsAny(combinedIntent, ["travel", "route", "van", "mobility", "camp", "fleet", "caravan"])
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

        if !prepaidCreditsActive {
            offers.append(
                TailoredOffer(
                    id: "offer-cloud-pro",
                    category: .localIntelligence,
                    type: .membership,
                    title: "Top Up Prepaid Credits",
                    summary: "Keep local reasoning as default and unlock cloud depth only for exact usage you choose.",
                    rationale: "You are currently operating with local-only compute.",
                    priority: 3,
                    callToAction: "Open prepaid credits"
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
            key: "travel_intents",
            value: travelIntentCompactLabel(),
            weight: 0.67,
            tags: ["travel", "intent"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "travel_regions_rv",
            value: normalizedRegionSelections(travelRVRegions).joined(separator: ", "),
            weight: 0.64,
            tags: ["region", "travel", "rv"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "travel_regions_car",
            value: normalizedRegionSelections(travelCarRegions).joined(separator: ", "),
            weight: 0.61,
            tags: ["region", "travel", "car"],
            now: now
        )
        upsertWorkspaceMemoryRecord(
            in: &merged,
            lane: .mobilityOps,
            sessionID: mobilitySession,
            source: .system,
            key: "travel_regions_accommodation",
            value: normalizedRegionSelections(travelAccommodationRegions).joined(separator: ", "),
            weight: 0.61,
            tags: ["region", "travel", "accommodation"],
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
            .replacingOccurrences(of: "document:", with: "document ")
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
            travelIntentSignalText(),
            surveyText,
            noteText,
            sessionText,
            memoryText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func normalizedRegionSelections(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                cleaned.append(trimmed)
            }
        }
        return cleaned
    }

    private func combinedTravelRegions() -> [String] {
        normalizedRegionSelections(travelRVRegions + travelCarRegions + travelAccommodationRegions)
    }

    private func primaryTravelRegionHint() -> String {
        if let first = combinedTravelRegions().first {
            return first
        }
        let legacy = travelRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy
    }

    private func hasAnyTravelIntent() -> Bool {
        vanRentalNeeded
            || wantsRVBuy
            || wantsRVRent
            || wantsCarBuy
            || wantsCarRent
            || wantsHomeBuy
            || wantsHomeRent
            || wantsApartmentBuy
            || wantsApartmentRent
            || wantsHotelBuy
            || wantsHotelRent
            || !combinedTravelRegions().isEmpty
    }

    private func travelIntentCompactLabel() -> String {
        var parts: [String] = []

        if wantsRVBuy || wantsRVRent {
            var rv = "RV"
            if wantsRVBuy && wantsRVRent {
                rv += " buy+rent"
            } else if wantsRVBuy {
                rv += " buy"
            } else {
                rv += " rent"
            }
            parts.append(rv)
        }

        if wantsCarBuy || wantsCarRent {
            var car = "cars"
            if wantsCarBuy && wantsCarRent {
                car += " buy+rent"
            } else if wantsCarBuy {
                car += " buy"
            } else {
                car += " rent"
            }
            parts.append(car)
        }

        let accommodationIntents = [
            (name: "home", buy: wantsHomeBuy, rent: wantsHomeRent),
            (name: "apartment", buy: wantsApartmentBuy, rent: wantsApartmentRent),
            (name: "hotel", buy: wantsHotelBuy, rent: wantsHotelRent),
        ]
        for item in accommodationIntents where item.buy || item.rent {
            if item.buy && item.rent {
                parts.append("\(item.name) buy+rent")
            } else if item.buy {
                parts.append("\(item.name) buy")
            } else {
                parts.append("\(item.name) rent")
            }
        }

        if parts.isEmpty {
            return "travel planning"
        }
        return parts.joined(separator: " | ")
    }

    private func travelIntentSignalText() -> String {
        let regions = combinedTravelRegions()
        if regions.isEmpty {
            return travelIntentCompactLabel()
        }
        return "\(travelIntentCompactLabel()) regions \(regions.joined(separator: " "))"
    }

    private func decodeMultiSurveyValues(_ raw: String?) -> Set<String> {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return Set(
            text
                .split(separator: "|")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func surveyBoolAnswer(_ questionID: String) -> Bool {
        let value = (surveyAnswers[questionID] ?? "").lowercased()
        return value == "yes" || value == "true" || value == "buy" || value == "rent"
    }

    private func surveyMultiContains(_ questionID: String, option: String) -> Bool {
        decodeMultiSurveyValues(surveyAnswers[questionID]).contains(option)
    }

    private func syncTravelProfileFromSurveyAnswers() {
        wantsRVBuy = surveyMultiContains("rv_intent_multi", option: "buy")
        wantsRVRent = surveyMultiContains("rv_intent_multi", option: "rent")
        wantsCarBuy = surveyMultiContains("car_intent_multi", option: "buy")
        wantsCarRent = surveyMultiContains("car_intent_multi", option: "rent")
        wantsHomeBuy = surveyMultiContains("home_intent_multi", option: "buy")
        wantsHomeRent = surveyMultiContains("home_intent_multi", option: "rent")
        wantsApartmentBuy = surveyMultiContains("apartment_intent_multi", option: "buy")
        wantsApartmentRent = surveyMultiContains("apartment_intent_multi", option: "rent")
        wantsHotelBuy = surveyMultiContains("hotel_intent_multi", option: "buy")
        wantsHotelRent = surveyMultiContains("hotel_intent_multi", option: "rent")

        travelRVRegions = normalizedRegionSelections(Array(decodeMultiSurveyValues(surveyAnswers["rv_regions_multi"])))
        travelCarRegions = normalizedRegionSelections(Array(decodeMultiSurveyValues(surveyAnswers["car_regions_multi"])))
        travelAccommodationRegions = normalizedRegionSelections(Array(decodeMultiSurveyValues(surveyAnswers["accommodation_regions_multi"])))

        // Keep legacy fields synchronized for compatibility with older modules/state.
        vanRentalNeeded = wantsRVBuy || wantsRVRent || surveyBoolAnswer("needs_rv_support")
        travelRegion = primaryTravelRegionHint()
        workspaceMode = surveyAnswers["travel_state_wanted"] ?? ""
        annualDistanceKM = {
            switch surveyAnswers["drive_distance_yearly"] {
            case "under_5000_km": return "5000"
            case "5000_15000_km": return "15000"
            case "15000_30000_km": return "30000"
            case "30000_50000_km": return "50000"
            case "50000_plus_km": return "50000+"
            default: return ""
            }
        }()
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
        let track = surveyAnswers["high_paying_job_track"] ?? "none"
        let industry = surveyAnswers["industry_focus"] ?? "software_ai"
        let wealthVehicle = surveyAnswers["wealth_vehicle"] ?? "hybrid"

        if track == "none", wealthVehicle != "job_ladder", wealthVehicle != "hybrid" {
            return []
        }

        return JobMarketRadar.topOpportunities(
            highPayingTrack: track,
            industryFocus: industry,
            regionHint: primaryTravelRegionHint(),
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
            markSignedIn(provider: provider, accountName: resolvedName)
            let prepaidEnabled = me.subscription?.usageBillingActive
                ?? me.subscription?.cloudComputeEnabled
                ?? false
            prepaidCreditsActive = prepaidEnabled
            selectedTier = prepaidEnabled ? .cloudPro : .localTrial
            billingStatusMessage = prepaidEnabled
                ? "Prepaid credits active. Optional cloud models unlocked."
                : "On-device AI remains active. Prepay credits to enable optional cloud models."
            memoryCollectionEnabled = me.user.memoryOptIn
            if !memoryCollectionEnabled {
                appendOutput("Server profile is set to memory opt-out. Local long-term memory persistence is disabled.")
            }
            if prepaidEnabled {
                startPromptQueueWorker()
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

        let globalRegionChoices = [
            SurveyChoice(value: "north_america", label: "North America"),
            SurveyChoice(value: "south_america", label: "South America"),
            SurveyChoice(value: "europe", label: "Europe"),
            SurveyChoice(value: "middle_east", label: "Middle East"),
            SurveyChoice(value: "africa", label: "Africa"),
            SurveyChoice(value: "south_asia", label: "South Asia"),
            SurveyChoice(value: "east_asia", label: "East Asia"),
            SurveyChoice(value: "southeast_asia", label: "Southeast Asia"),
            SurveyChoice(value: "oceania", label: "Oceania"),
        ]

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
                id: "drive_now",
                title: "Do you currently drive?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes"),
                    SurveyChoice(value: "no", label: "No")
                ]
            ),
            localQuestion(
                id: "drive_frequency",
                title: "How often do you drive?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "daily", label: "Daily"),
                    SurveyChoice(value: "several_weekly", label: "Several times per week"),
                    SurveyChoice(value: "weekly", label: "About weekly"),
                    SurveyChoice(value: "monthly", label: "A few times per month"),
                    SurveyChoice(value: "rarely", label: "Rarely")
                ]
            ),
            localQuestion(
                id: "drive_distance_yearly",
                title: "About how far do you drive per year?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "under_5000_km", label: "Under 5,000 km"),
                    SurveyChoice(value: "5000_15000_km", label: "5,000-15,000 km"),
                    SurveyChoice(value: "15000_30000_km", label: "15,000-30,000 km"),
                    SurveyChoice(value: "30000_50000_km", label: "30,000-50,000 km"),
                    SurveyChoice(value: "50000_plus_km", label: "50,000+ km")
                ]
            ),
            localQuestion(
                id: "public_transport_usage",
                title: "Do you use public transportation?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes"),
                    SurveyChoice(value: "no", label: "No")
                ]
            ),
            localQuestion(
                id: "public_transport_frequency",
                title: "How often do you use public transportation?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "daily", label: "Daily"),
                    SurveyChoice(value: "several_weekly", label: "Several times per week"),
                    SurveyChoice(value: "weekly", label: "About weekly"),
                    SurveyChoice(value: "monthly", label: "A few times per month"),
                    SurveyChoice(value: "rarely", label: "Rarely")
                ]
            ),
            localQuestion(
                id: "public_transport_affordability",
                title: "Do you ever have difficulty affording public transportation?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "often", label: "Often"),
                    SurveyChoice(value: "sometimes", label: "Sometimes"),
                    SurveyChoice(value: "rarely", label: "Rarely"),
                    SurveyChoice(value: "never", label: "Never")
                ]
            ),
            localQuestion(
                id: "financial_struggle_self",
                title: "Are you currently facing financial struggles in your own life?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes"),
                    SurveyChoice(value: "no", label: "No")
                ]
            ),
            localQuestion(
                id: "financial_struggle_family",
                title: "Are close family members currently facing financial struggles?",
                description: "Current state (what is).",
                choices: [
                    SurveyChoice(value: "yes", label: "Yes"),
                    SurveyChoice(value: "no", label: "No")
                ]
            ),
            localQuestion(
                id: "financial_state_wanted",
                title: "What financial state do you want to reach over the next 12 months?",
                description: "Target state (what is wanted).",
                choices: [
                    SurveyChoice(value: "stability", label: "Basic stability"),
                    SurveyChoice(value: "debt_reduction", label: "Debt reduction"),
                    SurveyChoice(value: "emergency_buffer", label: "Emergency buffer"),
                    SurveyChoice(value: "income_growth", label: "Stronger income growth"),
                    SurveyChoice(value: "family_support", label: "Support family finances better")
                ]
            ),
            localQuestion(
                id: "travel_state_wanted",
                title: "What travel state do you want over the next 12 months?",
                description: "Target state (what is wanted).",
                choices: [
                    SurveyChoice(value: "more_flexible", label: "More flexibility"),
                    SurveyChoice(value: "lower_cost", label: "Lower travel cost"),
                    SurveyChoice(value: "higher_reliability", label: "Higher reliability"),
                    SurveyChoice(value: "less_stress", label: "Less stress"),
                    SurveyChoice(value: "broader_access", label: "Broader regional access")
                ]
            ),
            localMultiQuestion(
                id: "rv_intent_multi",
                title: "For RV/van, what is wanted?",
                description: "Select all that apply (wanted state).",
                choices: [
                    SurveyChoice(value: "buy", label: "Buy"),
                    SurveyChoice(value: "rent", label: "Rent"),
                ]
            ),
            localMultiQuestion(
                id: "car_intent_multi",
                title: "For cars, what is wanted?",
                description: "Select all that apply (wanted state).",
                choices: [
                    SurveyChoice(value: "buy", label: "Buy"),
                    SurveyChoice(value: "rent", label: "Rent"),
                ]
            ),
            localMultiQuestion(
                id: "home_intent_multi",
                title: "For homes, what is wanted?",
                description: "Select all that apply (wanted state).",
                choices: [
                    SurveyChoice(value: "buy", label: "Buy"),
                    SurveyChoice(value: "rent", label: "Rent"),
                ]
            ),
            localMultiQuestion(
                id: "apartment_intent_multi",
                title: "For apartments, what is wanted?",
                description: "Select all that apply (wanted state).",
                choices: [
                    SurveyChoice(value: "buy", label: "Buy"),
                    SurveyChoice(value: "rent", label: "Rent"),
                ]
            ),
            localMultiQuestion(
                id: "hotel_intent_multi",
                title: "For hotels, what is wanted?",
                description: "Select all that apply (wanted state).",
                choices: [
                    SurveyChoice(value: "buy", label: "Buy"),
                    SurveyChoice(value: "rent", label: "Rent"),
                ]
            ),
            localMultiQuestion(
                id: "rv_regions_multi",
                title: "Which regions matter for RV/van travel?",
                description: "Select all that apply.",
                choices: globalRegionChoices
            ),
            localMultiQuestion(
                id: "car_regions_multi",
                title: "Which regions matter for car travel?",
                description: "Select all that apply.",
                choices: globalRegionChoices
            ),
            localMultiQuestion(
                id: "accommodation_regions_multi",
                title: "Which regions matter for homes/apartments/hotels?",
                description: "Select all that apply.",
                choices: globalRegionChoices
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
        let normalizedChoices = ensureUnsureChoice(in: choices)
        return SurveyQuestion(
            id: id,
            title: title,
            description: description,
            kind: "choice",
            required: true,
            choices: normalizedChoices,
            placeholder: nil
        )
    }

    private func localMultiQuestion(
        id: String,
        title: String,
        description: String?,
        choices: [SurveyChoice]
    ) -> SurveyQuestion {
        let normalizedChoices = ensureUnsureChoice(in: choices)
        return SurveyQuestion(
            id: id,
            title: title,
            description: description,
            kind: "multi_choice",
            required: true,
            choices: normalizedChoices,
            placeholder: nil
        )
    }

    private func ensureUnsureChoice(in choices: [SurveyChoice]) -> [SurveyChoice] {
        if choices.contains(where: { $0.value == "not_sure" }) {
            return choices
        }
        return choices + [SurveyChoice(value: "not_sure", label: "I don't know / I'm not sure")]
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
                appNamespace: "AtlasMasaMacOS"
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
            appNamespace: "AtlasMasaMacOS"
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
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func persistStateToDisk() {
        let persistedNotes = memoryCollectionEnabled ? notes : []
        let persistedSurveyAnswers = memoryCollectionEnabled ? surveyAnswers : [:]
        let persistedLearningPackage = memoryCollectionEnabled ? learningPackage : nil
        let persistedWorkspaceMemoryRecords = memoryCollectionEnabled ? workspaceMemoryRecords : []
        let persistedKnowledgeFiles = memoryCollectionEnabled ? knowledgeFiles : []
        let persistedCodingMessages = memoryCollectionEnabled ? codingMessages : []
        let persistedCodingMemoryRecords = memoryCollectionEnabled ? codingMemoryRecords : []
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
            wantsRVBuy: wantsRVBuy,
            wantsRVRent: wantsRVRent,
            wantsCarBuy: wantsCarBuy,
            wantsCarRent: wantsCarRent,
            wantsHomeBuy: wantsHomeBuy,
            wantsHomeRent: wantsHomeRent,
            wantsApartmentBuy: wantsApartmentBuy,
            wantsApartmentRent: wantsApartmentRent,
            wantsHotelBuy: wantsHotelBuy,
            wantsHotelRent: wantsHotelRent,
            travelRVRegions: normalizedRegionSelections(travelRVRegions),
            travelCarRegions: normalizedRegionSelections(travelCarRegions),
            travelAccommodationRegions: normalizedRegionSelections(travelAccommodationRegions),
            notes: persistedNotes,
            surveyAnswers: persistedSurveyAnswers,
            surveyQuestionSessionIndex: surveyQuestionSessionIndex,
            surveyQuestionLaneIndex: surveyQuestionLaneIndex,
            noteSessionIndex: noteSessionIndex,
            noteLaneIndex: noteLaneIndex,
            workspaceMemoryRecords: persistedWorkspaceMemoryRecords,
            knowledgeFiles: persistedKnowledgeFiles,
            workspaceSessions: persistedWorkspaceSessions,
            activeWorkspaceLane: activeWorkspaceLane.rawValue,
            activeWorkspaceSessionByLane: persistedActiveSessionMap,
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
            guidedLearningActivated: guidedLearningActivated,
            quantumLearningEnabled: quantumLearningEnabled,
            quantumLearningStatusLine: quantumLearningStatusLine,
            quantumLearningSnapshot: quantumLearningSnapshot
        )

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(state) else { return }

        guard let primaryURL = stateFileURL(fileName: stateFileName) else { return }

        let backupURL = stateFileURL(fileName: stateBackupFileName)
        do {
            let encrypted = try SecurePersistence.encrypt(
                data,
                context: "session_state",
                appNamespace: "AtlasMasaMacOS"
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
                    appNamespace: "AtlasMasaMacOS"
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
                    appNamespace: "AtlasMasaMacOS"
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
        wantsRVBuy = state.wantsRVBuy ?? false
        wantsRVRent = state.wantsRVRent ?? false
        wantsCarBuy = state.wantsCarBuy ?? false
        wantsCarRent = state.wantsCarRent ?? false
        wantsHomeBuy = state.wantsHomeBuy ?? false
        wantsHomeRent = state.wantsHomeRent ?? false
        wantsApartmentBuy = state.wantsApartmentBuy ?? false
        wantsApartmentRent = state.wantsApartmentRent ?? false
        wantsHotelBuy = state.wantsHotelBuy ?? false
        wantsHotelRent = state.wantsHotelRent ?? false
        travelRVRegions = normalizedRegionSelections(state.travelRVRegions ?? [])
        travelCarRegions = normalizedRegionSelections(state.travelCarRegions ?? [])
        travelAccommodationRegions = normalizedRegionSelections(state.travelAccommodationRegions ?? [])
        notes = state.notes
        surveyAnswers = state.surveyAnswers ?? [:]
        surveyQuestionSessionIndex = state.surveyQuestionSessionIndex ?? [:]
        surveyQuestionLaneIndex = state.surveyQuestionLaneIndex ?? [:]
        noteSessionIndex = state.noteSessionIndex ?? [:]
        noteLaneIndex = state.noteLaneIndex ?? [:]
        workspaceMemoryRecords = state.workspaceMemoryRecords ?? []
        knowledgeFiles = state.knowledgeFiles ?? []
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
        codingWorkspaceRootPath = normalizeCodingPath(state.codingWorkspaceRootPath ?? "")
        codingWorkspaceFiles = state.codingWorkspaceFiles ?? []
        codingSelectedFilePath = state.codingSelectedFilePath.map(normalizeCodingPath)
        codingEditorText = state.codingEditorText ?? ""
        codingEditorIsDirty = state.codingEditorIsDirty ?? false
        codingMessages = state.codingMessages ?? []
        codingMemoryRecords = state.codingMemoryRecords ?? []
        codingCommandDraft = state.codingCommandDraft ?? "git status"
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
        quantumLearningEnabled = state.quantumLearningEnabled ?? true
        quantumLearningStatusLine = state.quantumLearningStatusLine ?? "Quantum learning simulator idle."
        quantumLearningSnapshot = state.quantumLearningSnapshot
        syncTravelProfileFromSurveyAnswers()
        ensureWorkspaceSessionsSeeded()
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
    var checkInWentToGymToday: Bool?
    var checkInMadeMoneyToday: Bool?
    var checkInMoneySignalNote: String?
    var pendingFeedback: String
    var vanRentalNeeded: Bool
    var travelRegion: String
    var annualDistanceKM: String
    var workspaceMode: String
    var wantsRVBuy: Bool?
    var wantsRVRent: Bool?
    var wantsCarBuy: Bool?
    var wantsCarRent: Bool?
    var wantsHomeBuy: Bool?
    var wantsHomeRent: Bool?
    var wantsApartmentBuy: Bool?
    var wantsApartmentRent: Bool?
    var wantsHotelBuy: Bool?
    var wantsHotelRent: Bool?
    var travelRVRegions: [String]?
    var travelCarRegions: [String]?
    var travelAccommodationRegions: [String]?
    var notes: [UserNote]
    var surveyAnswers: [String: String]?
    var surveyQuestionSessionIndex: [String: String]?
    var surveyQuestionLaneIndex: [String: String]?
    var noteSessionIndex: [String: String]?
    var noteLaneIndex: [String: String]?
    var workspaceMemoryRecords: [WorkspaceMemoryRecord]?
    var knowledgeFiles: [KnowledgeFileRecord]?
    var workspaceSessions: [WorkspaceNotebookSession]?
    var activeWorkspaceLane: String?
    var activeWorkspaceSessionByLane: [String: String]?
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
    var quantumLearningEnabled: Bool?
    var quantumLearningStatusLine: String?
    var quantumLearningSnapshot: SessionStore.QuantumLearningSnapshot?
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
#if os(macOS)
        if let fileBacked = try? loadFileBackedKeyMaterial(account: account) {
            return fileBacked
        }

        let generated = try generateRandomKeyMaterial()
        try persistFileBackedKeyMaterial(generated, account: account)
        return generated
#else
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
#endif
    }

    private static func generateRandomKeyMaterial() throws -> Data {
        var generated = Data(count: 32)
        let bytesStatus = generated.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard bytesStatus == errSecSuccess else {
            throw SecurePersistenceError.keychainFailure(bytesStatus)
        }
        return generated
    }

#if os(macOS)
    private static func keyMaterialFileURL(account: String) -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let safeAccount = account.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
        return base
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent("Security", isDirectory: true)
            .appendingPathComponent("key-\(safeAccount).bin", isDirectory: false)
    }

    private static func loadFileBackedKeyMaterial(account: String) throws -> Data {
        guard let url = keyMaterialFileURL(account: account) else {
            throw SecurePersistenceError.invalidKeyMaterial
        }
        let data = try Data(contentsOf: url)
        guard data.count == 32 else {
            throw SecurePersistenceError.invalidKeyMaterial
        }
        return data
    }

    private static func persistFileBackedKeyMaterial(_ keyData: Data, account: String) throws {
        guard keyData.count == 32 else {
            throw SecurePersistenceError.invalidKeyMaterial
        }
        guard let url = keyMaterialFileURL(account: account) else {
            throw SecurePersistenceError.invalidKeyMaterial
        }
        let fileManager = FileManager.default
        let directoryURL = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        try keyData.write(to: url, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func loadLegacyKeychainMaterialWithoutPrompt(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data else {
                throw SecurePersistenceError.invalidKeyMaterial
            }
            return data
        }
        if status == errSecItemNotFound || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return nil
        }
        throw SecurePersistenceError.keychainFailure(status)
    }
#endif
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
