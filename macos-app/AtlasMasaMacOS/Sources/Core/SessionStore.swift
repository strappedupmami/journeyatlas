import AppKit
import AuthenticationServices
import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Network
import PDFKit
import Security
import UserNotifications
import WebKit

@MainActor
final class SessionStore: ObservableObject {
    private static let localTrialDurationDays = 30
    private static let guiValidationLaunchSentinelName = "blackhaven-gui-validation.launch"
    private static let guiValidationPendingDefaultsKey = "blackhaven.gui.validation.pending"
    private static let guiValidationPendingSourceDefaultsKey = "blackhaven.gui.validation.pending.source"

    enum LaunchBehavior: Equatable {
        case automatic
        case testing
    }

    nonisolated static func resolvedLaunchBehavior(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchBehavior {
        if environment["BLACKHAVEN_TEST_MODE"] == "1" || environment["XCTestConfigurationFilePath"] != nil {
            return .testing
        }
        return .automatic
    }

    enum LocalAIRuntimeStatusCode: String {
        case notInstalled
        case installingRuntime
        case startingRuntime
        case downloadingModel
        case warmingModel
        case ready
        case degraded
        case error
    }

    enum LocalAISetupStage: String {
        case checking
        case installRequired
        case installing
        case ready
        case deferred
        case failed
    }

    struct LocalAIModelInstallOption: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let modelName: String
        let approximateSizeGB: Double
        let recommended: Bool

        var approximateSizeLabel: String {
            String(format: "%.1f GB", approximateSizeGB)
        }
    }

    struct MemoryVaultPolicy: Codable, Hashable {
        var hardwareTier = "balanced"
        var contextBudgetTokens = 6_000
        var compactionThresholdTokens = 4_680
        var retrievalDepth = 4
        var responseBudgetTokens = 820
        var archiveSearchMode = "native_encrypted_local_index"
        var modelGuidance = "balanced_local_model"
    }

    struct MemoryVaultRawRecord: Codable, Identifiable, Hashable {
        var id: String
        var sourceType: String
        var sourceLabel: String
        var tags: [String]
        var content: String
        var createdAt: Date
        var deepArchived = false
    }

    struct MemoryVaultCompactedRecord: Codable, Identifiable, Hashable {
        var id: String
        var title: String
        var summary: String
        var sourceRecordIDs: [String]
        var createdAt: Date
        var triggerReason: String
    }

    struct MemoryVaultArtifactRecord: Codable, Identifiable, Hashable {
        var id: String
        var artifactType: String
        var title: String
        var detail: String
        var createdAt: Date
    }

    struct MemoryVaultSnapshot: Codable, Hashable {
        var schemaVersion = 1
        var rawRecords: [MemoryVaultRawRecord] = []
        var compactedRecords: [MemoryVaultCompactedRecord] = []
        var artifactRecords: [MemoryVaultArtifactRecord] = []
        var lastTokenPressure = 0
        var lastSyncReason = "startup"
        var lastCompactionReason = "idle"
        var lastArchiveMode = "raw"
        var lastCompactedAt: Date?
        var lastPolicy: MemoryVaultPolicy?
        var lastSavedAt: Date?
    }

    struct MemoryVaultRecallResult: Identifiable, Hashable {
        let id = UUID()
        let summary: String
        let sourceLabel: String
        let timestamp: String
        let matchReason: String
    }

    struct GUIValidationStep: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let dashboardSectionRawValue: String
        let workspaceLane: WorkspaceLane?
        let prompt: String
    }

    private struct IndexedKnowledgeChunk: Hashable {
        let fileID: String
        let fileName: String
        let fileType: String
        let chunkKey: String
        let text: String
        let tokens: [String]
        let tokenSet: Set<String>
        let weight: Double
        let updatedAtUTC: Date
    }

    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Travel Design OS (Swift local tier)..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var operatorStateSnapshot: OperatorStateSnapshot?
    @Published var activeChecklistPlan: ChecklistPlan?
    @Published var currentActivitySuggestion: ActivitySuggestion?
    @Published var currentItineraryPlan: ItineraryPlan?
    @Published var currentSupportRecommendation: SupportRecommendation?
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var memoryVaultStatusLine = "Local memory vault pending."
    @Published var memoryVaultPolicyLine = "Hardware-aware memory policy pending."
    @Published var memoryVaultRecallQuery = ""
    @Published var memoryVaultRecallResults: [MemoryVaultRecallResult] = []
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
    @Published var remoteControlStatus = "Desktop remote control offline."
    @Published var remoteControlURL = "Unavailable"
    @Published var remoteControlToken = ""
    @Published var remoteControlLastAction = "No remote actions yet."

    @Published var isSignedIn = false
    @Published var accountProvider: AuthProvider?
    @Published var accountLabel = "Guest Operator"
    @Published var showRemoteTransferTutorial = false
    @Published var showCADToolsSetupWizard = false
    @Published var prepaidCreditsActive = false
    @Published var mliStudioVisible = true
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
    @Published var contextProfiles: [AtlasContextProfile] = []
    @Published var workspacePlans: [WorkspacePlan] = []
    @Published var rAndDPromptDraft = ""
    @Published var rAndDSelectedProductType = "mechanical_vehicle"
    @Published var rAndDPlanRevisionDraft = ""
    @Published var rAndDChangeRequestDraft = ""
    @Published var rAndDTargetPartID = ""
    @Published var rAndDJobs: [RAndDJobResponse] = []
    @Published var selectedRAndDJobID: String?
    @Published var rAndDArtifacts: [RAndDArtifact] = []
    @Published var rAndDTimeline: [RAndDTimelineStage] = []
    @Published var rAndDGovernance: RAndDGovernanceResponse?
    @Published var rAndDTraceabilityRows: [RAndDTraceabilityRow] = []
    @Published var rAndDDoctrine: RAndDDoctrineResponse?
    @Published var rAndDDocuments: [RAndDDocumentRecord] = []
    @Published var rAndDDocumentationBundles: [RAndDDocumentationBundle] = []
    @Published var rAndDInspectionGuide = ""
    @Published var rAndDWorkspaceRootPath = ""
    @Published var rAndDLocalWorkspaceAssets: [RAndDLocalWorkspaceAsset] = []
    @Published var rAndDLocalExecutionRecords: [RAndDLocalExecutionRecord] = []
    @Published var rAndDLocalExecutionStatusLine = "Local CAD execution idle."
    @Published var rAndDLocalExecutionIsRunning = false
    @Published var rAndDStatusLine = "R&D orchestrator idle."
    @Published var rAndDIsWorking = false
    @Published var rAndDReportTitleDraft = ""
    @Published var rAndDReviewNoteDraft = ""
    @Published var rAndDApprovalReviewerName = "Atlas Internal Reviewer"
    @Published var rAndDApprovalReviewerRole = "internal_engineering_lead"
    @Published var rAndDApprovalAuthorityKind = "internal_engineering_approval"
    @Published var rAndDApprovalCommentDraft = ""
    @Published var rAndDSelectedDocumentType = "manufacturing_build_guide"
    @Published var rAndDDocumentAudienceMode = "private"
    @Published var rAndDDocumentTitleDraft = ""
    @Published var rAndDDocumentPlatformNameDraft = ""
    @Published var rAndDDocumentRevisionDraft = ""
    @Published var rAndDDocumentPurposeDraft = ""
    @Published var rAndDDocumentTargetAudienceDraft = ""
    @Published var rAndDDocumentAuthorDraft = ""
    @Published var selectedRAndDDocumentID: String?
    @Published var rAndDDocumentPreviewHTML = ""
    @Published var rAndDDocumentPreviewStatus = "Generate or select a document to preview it here."
    @Published var rAndDLastExportPath = ""
    @Published var rAndDLastExportError = ""
    @Published var rAndDBundleExportStatus = ""
    @Published var freeCADPath = ""
    @Published var freeCADCmdPath = ""
    @Published var kiCadCLIPath = ""
    @Published var calculiXPath = ""
    @Published var cadToolsStatusLine = "CAD/EDA tools not configured."
    @Published var freeCADHealthLine = "FreeCAD not checked."
    @Published var freeCADCmdHealthLine = "FreeCADCmd not checked."
    @Published var kiCadCLIHealthLine = "KiCad CLI not checked."
    @Published var calculiXHealthLine = "CalculiX not checked."
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
    @Published var localModelRuntimeStatus = "Local model runtime pending."
    @Published var localModelRuntimeDetail = "Enhanced runtime is idle."
    @Published var localModelRuntimeProgress = 0.0
    @Published var localModelRuntimeIsBusy = false
    @Published var localModelRuntimeReady = false
    @Published var localModelRuntimeStatusCode: LocalAIRuntimeStatusCode = .notInstalled
    @Published var localModelRuntimeLastError = ""
    @Published var localReasoningDepthStatus = "Adaptive depth: standard"
    @Published var localModelDownloadBytes: Int64 = 0
    @Published var localModelDownloadTotalBytes: Int64 = 0
    @Published var localModelDownloadETASeconds: Int?
    @Published var localAISetupStage: LocalAISetupStage = .checking
    @Published var localAIInstallOptions: [LocalAIModelInstallOption] = []
    @Published var selectedLocalAIInstallOptionIDs: [String] = []
    @Published var localAISetupCompleted = false
    @Published var localAISetupDeferred = false
    @Published var localAISetupHandoffNonce = 0
    @Published var guiValidationIsRunning = false
    @Published var guiValidationCurrentStep = ""
    @Published var guiValidationRequestedSectionRawValue: String?
    @Published var guiValidationLogs: [String] = []
    @Published var guiValidationLastTriggerSource = ""
    @Published var lastLocalInferenceDiagnostic = ""
    @Published var lastLocalInferenceAttemptDetail = ""

    @Published var pendingFeedback = ""
    @Published var feedbackOfferEnabled = true

    private var memoryVaultSnapshot = MemoryVaultSnapshot()
    private var knowledgeSemanticIndex: [IndexedKnowledgeChunk] = []
    private var knowledgeTokenDocumentFrequency: [String: Int] = [:]

    @Published var wantsRVBuy = false
    @Published var wantsRVRent = false
    @Published var wantsCarBuy = false
    @Published var wantsCarRent = false

    private var ownerAccountLabel: String { "BlackHaven Owner" }
    private var bootstrapCompleted = false
    private var pendingGUIValidationTriggerSource: String?
    private let launchBehavior: LaunchBehavior

    var allowsAutomaticRuntimeWork: Bool {
        launchBehavior == .automatic
    }

    var isBlackHavenOwner: Bool {
        isSignedIn && accountLabel == ownerAccountLabel
    }

    var canViewRuntimeDiagnostics: Bool {
        isBlackHavenOwner
    }

    var shouldShowLocalRuntimeProgressUI: Bool {
        localModelRuntimeIsBusy || (!localModelRuntimeReady && localModelRuntimeProgress > 0)
    }

    var shouldRunGUIValidationSuiteOnLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--run-gui-validation-suite") { return true }
        if ProcessInfo.processInfo.environment["BLACKHAVEN_GUI_VALIDATION"] == "1" { return true }
        return FileManager.default.fileExists(atPath: Self.guiValidationLaunchSentinelURL.path)
    }

    static var guiValidationLaunchSentinelURL: URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(guiValidationLaunchSentinelName)
    }

    func armGUIValidationSuiteForNextLaunch() {
        FileManager.default.createFile(atPath: Self.guiValidationLaunchSentinelURL.path, contents: Data(), attributes: nil)
        appendOutput("GUI validation suite armed for next launch.")
    }

    func clearArmedGUIValidationSuite() {
        try? FileManager.default.removeItem(at: Self.guiValidationLaunchSentinelURL)
        appendOutput("GUI validation launch arm cleared.")
    }

    static func captureLaunchTriggeredGUIValidationRequestIfNeeded() {
        guard launchRequestedGUIValidationSuite() else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: guiValidationPendingDefaultsKey)
        defaults.set("startup", forKey: guiValidationPendingSourceDefaultsKey)
    }

    private static func launchRequestedGUIValidationSuite() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--run-gui-validation-suite") { return true }
        if ProcessInfo.processInfo.environment["BLACKHAVEN_GUI_VALIDATION"] == "1" { return true }
        return FileManager.default.fileExists(atPath: guiValidationLaunchSentinelURL.path)
    }
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
    @Published var savedTravelLocations: [SavedTravelLocation] = []
    @Published var selectedTravelLocationID: String?
    @Published var activeTravelItineraryDraft = TravelItineraryDraft(
        id: "default-travel-itinerary",
        title: "Travel itinerary",
        locationIDs: [],
        updatedAt: ISO8601DateFormatter().string(from: Date())
    )
    @Published var jobMarketOpportunities: [JobOpportunity] = []

    struct GuidedLearningSettingsSnapshot: Hashable {
        let kiwixBaseURL: String
        let ollamaEndpoint: String
        let ollamaModel: String
    }

    struct CADToolsSettingsSnapshot: Hashable {
        let freeCADPath: String
        let freeCADCmdPath: String
        let kiCadCLIPath: String
        let calculiXPath: String
    }

    struct CADToolDownload: Hashable, Identifiable {
        let id: String
        let title: String
        let detail: String
        let url: String
    }

    struct RAndDLocalWorkspaceAsset: Codable, Identifiable, Hashable {
        let artifactID: String
        let title: String
        let artifactType: String
        let format: String
        let localPath: String
        let preview: String

        var id: String { artifactID }
    }

    struct RAndDLocalExecutionRecord: Codable, Identifiable, Hashable {
        let executionID: String
        let artifactID: String
        let tool: String
        let contentHash: String
        let status: String
        let detail: String
        let outputPaths: [String]
        let executedAt: Date

        var id: String { executionID }
    }

    private enum CADToolDefaults {
        static let freeCADPathKey = "atlas.cad.freecad.path"
        static let freeCADCmdPathKey = "atlas.cad.freecadcmd.path"
        static let kiCadCLIPathKey = "atlas.cad.kicadcli.path"
        static let calculiXPathKey = "atlas.cad.calculix.path"
    }

    let cadToolDownloads: [CADToolDownload] = [
        CADToolDownload(
            id: "freecad",
            title: "FreeCAD",
            detail: "Official CAD source tool for the mechanical R&D lane.",
            url: "https://www.freecad.org/downloads.php?lang=en_US"
        ),
        CADToolDownload(
            id: "kicad",
            title: "KiCad",
            detail: "Official EDA/PCB tool for the future electronics lane.",
            url: "https://www.kicad.org/download/macos/"
        ),
        CADToolDownload(
            id: "calculix",
            title: "CalculiX",
            detail: "Recommended structural solver for named mechanical load-case review.",
            url: "https://www.calculix.de/"
        ),
    ]

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
    private var localRuntimeProvisioningTask: Task<Void, Never>?
    private var managedLocalRuntimeProcess: Process?
    private var managedLocalRuntimeLogURL: URL?
    private var surveySyncTask: Task<Void, Never>?
    private var surveyRebuildTask: Task<Void, Never>?
    private var queuedAdaptiveSurveyQuestion: SurveyQuestion?
    private var recentLocalInferenceDurationsSeconds: [Double] = []
    private var localInferenceInFlightCount = 0
    private var hasLoggedSurveySyncUnavailable = false
    private var networkPathMonitor: NWPathMonitor?
    private var isInternetConnectionAvailable = true
    private var hasLoggedQueueReconnectWait = false
    private var remoteControlServer: DesktopRemoteControlServer?
    private var lastResolvedLocalInferenceModel = "llama3.2:latest"
    private var hasLikelyLocalOllamaRoute: Bool {
        Self.detectLikelyOllamaBinary()
    }
    private var localInferencePreferredModels: [String] {
        if let configured = Self.normalizedSingleLocalModelSetting(
            UserDefaults.standard.string(forKey: LocalInferenceDefaults.modelKey)
        ) {
            return [configured]
        }
        return ["qwen2.5:7b"]
    }
    private var localInferencePreferredModelName: String {
        localInferencePreferredModels.first ?? "qwen2.5:7b"
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
            "qwen2.5:7b",
            "qwen2.5:32b",
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
    private var localReasoningPrimaryModeEnabled: Bool {
        false
    }
    private var localInferenceEndpointURL: URL? {
        let configured = UserDefaults.standard.string(forKey: LocalInferenceDefaults.endpointKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "http://127.0.0.1:8080/v1/chat/completions"
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

    private var localInferenceFailoverEndpointURL: URL? {
        URL(string: "http://127.0.0.1:11434/v1/chat/completions")
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
        let fallback = "http://127.0.0.1:8080/v1/chat/completions"
        return (configured?.isEmpty == false) ? configured! : fallback
    }

    private var guidedLearningOllamaModelName: String {
        let configured = UserDefaults.standard.string(forKey: GuidedLearningDefaults.ollamaModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (configured?.isEmpty == false) ? configured! : localInferencePreferredModelName
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
    private static let shortTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    private enum LocalInferenceDefaults {
        static let enabledKey = "atlas.local.llm.enabled"
        static let endpointKey = "atlas.local.llm.endpoint"
        static let modelKey = "atlas.local.llm.model"
        static let catalogKey = "atlas.local.llm.model_catalog"
        static let memoryDepthKey = "atlas.local.memory.depth"
        static let primaryReasonerKey = "atlas.local.reasoner.primary"
    }

    private enum LocalAISetupDefaults {
        static let completedKey = "atlas.local.ai.setup.completed"
        static let deferredKey = "atlas.local.ai.setup.deferred"
        static let selectedModelsKey = "atlas.local.ai.setup.selected_models"
        static let legacySelectedPackKey = "atlas.local.ai.setup.selected_pack"
    }

    private enum GuidedLearningDefaults {
        static let kiwixBaseURLKey = "atlas.guided.learning.kiwix.base_url"
        static let ollamaEndpointKey = "atlas.guided.learning.ollama.endpoint"
        static let ollamaModelKey = "atlas.guided.learning.ollama.model"
    }

    private enum RemoteTransferDefaults {
        static let tutorialSeenKey = "atlas.macos.remote.transfer.tutorial.seen"
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
    private static let minimumSurveyAnswersForExecution = 40

    private struct AdaptiveQuestionModelEnvelope: Codable {
        let question: String
        let options: [String]
    }

    private struct SurveyAdaptiveQuestionEnvelope: Codable {
        struct ChoiceEnvelope: Codable {
            let value: String
            let label: String
        }
        let title: String
        let description: String?
        let choices: [ChoiceEnvelope]
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

    init(
        api: APIClient = APIClient(),
        launchBehavior: LaunchBehavior = SessionStore.resolvedLaunchBehavior()
    ) {
        self.api = api
        self.launchBehavior = launchBehavior
        remoteControlToken = UserDefaults.standard.string(forKey: "atlas.remote.control.token") ?? ""
        localAISetupCompleted = UserDefaults.standard.bool(forKey: LocalAISetupDefaults.completedKey)
        localAISetupDeferred = UserDefaults.standard.bool(forKey: LocalAISetupDefaults.deferredKey)
        selectedLocalAIInstallOptionIDs = Self.parseStoredModelIDs(
            UserDefaults.standard.string(forKey: LocalAISetupDefaults.selectedModelsKey)
        )
        configureNetworkPathMonitor()
        migrateLegacyLocalRuntimeDefaultsIfNeeded()
        configureLocalAIInstallOptions()
        syncLocalModelPreferenceWithInstalledModels()
        restoreStateFromDisk()
        rebuildKnowledgeSemanticIndex()
        loadMemoryVaultFromDisk()
        refreshMemoryVaultStatus()
        restoreCADToolsSettings()
        ensureWorkspaceSessionsSeeded()
        ensureSeedDocumentsAvailable()
        loadPromptQueueFromDisk()
        recoverInterruptedQueueItemsAfterRestart()
        loadAdaptiveBusinessRuntimeFromDefaults()
        refreshQuantumLearningSnapshot(trigger: "startup")
        guard allowsAutomaticRuntimeWork else { return }
        startPromptQueueWorker()
        startAgenticBusinessRuntime()
        ensureDesktopRemoteControlServer()
        Task { await refreshNatureSignalStackNow(sendNotifications: false) }
    }

    deinit {
        networkPathMonitor?.cancel()
        remoteControlServer?.stop()
    }

    private func migrateLegacyLocalRuntimeDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        if let model = defaults.string(forKey: LocalInferenceDefaults.modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            model == "auto" || model == "qwen2.5:7b,deepseek-r1:14b"
        {
            defaults.set("qwen2.5:7b", forKey: LocalInferenceDefaults.modelKey)
        }

        if let guidedModel = defaults.string(forKey: GuidedLearningDefaults.ollamaModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            guidedModel == "llama3.2:latest"
        {
            defaults.set("qwen2.5:7b", forKey: GuidedLearningDefaults.ollamaModelKey)
        }
    }

    private func syncLocalModelPreferenceWithInstalledModels() {
        let defaults = UserDefaults.standard
        let configured = Self.normalizedSingleLocalModelSetting(
            defaults.string(forKey: LocalInferenceDefaults.modelKey)
        )
        let installedModels = Self.locallyInstalledOllamaModels().sorted()

        let chosenModel: String?
        if let configured,
           installedModels.contains(configured)
        {
            chosenModel = configured
        } else if let configured,
                  let resolved = Self.resolvedInstalledOllamaModelName(preferredModel: configured)
        {
            chosenModel = resolved
        } else if let selectedInstalled = installedModels.first(where: { $0 == selectedLocalAIInstallPrimaryModel }) {
            chosenModel = selectedInstalled
        } else {
            chosenModel = installedModels.first
        }

        if let configured, configured != defaults.string(forKey: LocalInferenceDefaults.modelKey) {
            defaults.set(configured, forKey: LocalInferenceDefaults.modelKey)
        }

        guard let chosenModel, !chosenModel.isEmpty else { return }
        defaults.set(chosenModel, forKey: LocalInferenceDefaults.modelKey)
        defaults.set(chosenModel, forKey: GuidedLearningDefaults.ollamaModelKey)
        lastResolvedLocalInferenceModel = chosenModel
    }

    private func routeLocalInference(
        to endpoint: URL,
        model: String,
        statusDetail: String? = nil
    ) {
        let endpointString = endpoint.absoluteString
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = UserDefaults.standard
        defaults.set(endpointString, forKey: LocalInferenceDefaults.endpointKey)
        defaults.set(endpointString, forKey: GuidedLearningDefaults.ollamaEndpointKey)
        if !trimmedModel.isEmpty {
            defaults.set(trimmedModel, forKey: LocalInferenceDefaults.modelKey)
            defaults.set(trimmedModel, forKey: GuidedLearningDefaults.ollamaModelKey)
        }
        if let statusDetail {
            appendOutput(statusDetail)
        }
    }

    private func configureLocalAIInstallOptions() {
        let installOptions = [
            LocalAIModelInstallOption(
                id: "qwen2.5:7b",
                title: "Qwen 2.5 7B",
                subtitle: "Fastest local concierge path and the best default fit for most Macs.",
                modelName: "qwen2.5:7b",
                approximateSizeGB: 4.4,
                recommended: true
            )
        ]
        localAIInstallOptions = installOptions

        let validSelectedIDs = selectedLocalAIInstallOptionIDs.filter { id in
            installOptions.contains(where: { $0.id == id })
        }
        if !validSelectedIDs.isEmpty {
            selectedLocalAIInstallOptionIDs = Self.dedupModels(validSelectedIDs)
        } else if let legacyPackID = UserDefaults.standard.string(forKey: LocalAISetupDefaults.legacySelectedPackKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            switch legacyPackID {
            default:
                selectedLocalAIInstallOptionIDs = ["qwen2.5:7b"]
            }
        } else {
            selectedLocalAIInstallOptionIDs = ["qwen2.5:7b"]
        }
        persistSelectedLocalAIInstallOptions()
    }

    private func markLocalAISetupCompleted(triggerHandoff: Bool) {
        let wasCompleted = localAISetupCompleted
        localAISetupCompleted = true
        localAISetupDeferred = false
        localAISetupStage = .ready
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LocalAISetupDefaults.completedKey)
        defaults.set(false, forKey: LocalAISetupDefaults.deferredKey)
        if triggerHandoff && !wasCompleted {
            localAISetupHandoffNonce += 1
        }
    }

    private func updateLocalAISetupStateFromRuntime(busy: Bool, ready: Bool) {
        if ready {
            markLocalAISetupCompleted(triggerHandoff: true)
        } else if busy {
            localAISetupStage = .installing
        } else if localModelRuntimeStatusCode == .error || localModelRuntimeStatusCode == .degraded {
            localAISetupStage = .failed
        } else if localAISetupDeferred {
            localAISetupStage = .deferred
        } else if localAISetupCompleted {
            localAISetupStage = .failed
        }
    }

    private func setLocalRuntimeHealth(
        statusCode: LocalAIRuntimeStatusCode,
        status: String,
        detail: String,
        progress: Double,
        busy: Bool,
        ready: Bool,
        lastError: String = ""
    ) {
        let wasReady = localModelRuntimeReady
        localModelRuntimeStatusCode = statusCode
        localModelRuntimeLastError = lastError
        setLocalModelRuntimeProgress(
            status: status,
            detail: detail,
            progress: progress,
            busy: busy,
            ready: ready
        )
        if ready && !wasReady {
            Task { [weak self] in
                guard let self else { return }
                await self.refreshCommandModelBrief()
                await self.refreshWorkspaceModelBrief()
            }
        }
    }

    private func markLocalInferenceAvailable(endpoint: URL, model: String) {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailModel = trimmedModel.isEmpty ? selectedLocalAIInstallPrimaryModel : trimmedModel
        routeLocalInference(to: endpoint, model: detailModel)
        setLocalRuntimeHealth(
            statusCode: .ready,
            status: "Local AI ready",
            detail: "Model \(detailModel) is responding on \(endpoint.absoluteString).",
            progress: 1.0,
            busy: false,
            ready: true
        )
    }

    private func prepareLocalAISetupExperienceOnLaunch(forceRecoveryInstall: Bool = false) async {
        configureLocalAIInstallOptions()
        localAISetupStage = .checking

        guard localInferenceEnabled,
              let endpoint = localInferenceEndpointURL,
              isLoopbackHost(endpoint.host)
        else {
            setLocalRuntimeHealth(
                statusCode: .notInstalled,
                status: "Local AI setup required",
                detail: "BlackHaven needs a local runtime endpoint before AI can be installed.",
                progress: 0.0,
                busy: false,
                ready: false
            )
            localAISetupStage = .installRequired
            return
        }

        let preferredModel = selectedLocalAIInstallPrimaryModel
        let ollamaEndpoint = Self.defaultOllamaEndpointURL()
        let directRuntimeReady = await Self.isLocalRuntimeReadyForInference(
            endpoint: endpoint,
            model: preferredModel,
            timeoutSeconds: 8
        )
        let existingOllamaRuntimeReady = await Self.isExistingOllamaRuntimeAvailable(
            endpoint: ollamaEndpoint,
            model: preferredModel,
            timeoutSeconds: 5
        )
        let runtimeReady = directRuntimeReady || existingOllamaRuntimeReady

        if runtimeReady {
            if existingOllamaRuntimeReady && !directRuntimeReady {
                let modelName = Self.resolvedInstalledOllamaModelName(preferredModel: preferredModel) ?? preferredModel
                routeLocalInference(
                    to: ollamaEndpoint,
                    model: modelName,
                    statusDetail: "BlackHaven found your existing Ollama runtime and will use it for local inference."
                )
            }
            setLocalRuntimeHealth(
                statusCode: .ready,
                status: "Local AI ready",
                detail: "BlackHaven detected a working local AI runtime.",
                progress: 1.0,
                busy: false,
                ready: true
            )
            appendOutput("Detected a healthy local AI runtime on launch.")
            return
        }

        if localAISetupDeferred {
            setLocalRuntimeHealth(
                statusCode: .notInstalled,
                status: "Local AI setup deferred",
                detail: "BlackHaven can prepare local AI automatically whenever you resume setup.",
                progress: 0.0,
                busy: false,
                ready: false
            )
            localAISetupStage = .deferred
            return
        }

        if localAISetupCompleted || forceRecoveryInstall || Self.resolvedLlamaServerBinaryPath() != nil {
            startManagedLocalRuntimeProvisioningIfNeeded(force: true)
            return
        }

        setLocalRuntimeHealth(
            statusCode: .notInstalled,
            status: "BlackHaven is preparing local AI",
            detail: "This build does not include the bundled local AI runtime yet.",
            progress: 0.0,
            busy: false,
            ready: false
        )
        localAISetupStage = .installRequired
    }

    func bootstrap() async {
        bootstrapCompleted = false
        migrateLegacyBrandingDefaultsIfNeeded()
        appendOutput("Local AI runtime boot: Qwen 2.5 + DeepSeek R1 routing is enabled.")
        appendOutput(mliStudioVisible ? "MLI Studio is available with seeded vanlife/RV reference context." : "MLI Studio is hidden in Settings.")
        appendOutput(localLLMRuntimeStatusLine())
        if allowsAutomaticRuntimeWork {
            await prepareLocalAISetupExperienceOnLaunch()
        } else {
            appendOutput("Test mode active: skipping automatic local runtime bootstrap.")
        }
        appendOutput("Academic discovery mode ready: OpenAlex + Semantic Scholar + PubMed/arXiv search, abstract scoring, citation snowballing, and DOI/full-text linking.")
        appendOutput("Local sync blueprint mode ready: USB-C/LAN discovery + mTLS pairing workflow.")
        appendOutput("Recovery support mode ready: long-term relapse prevention guardrails.")
        appendOutput("Execution stream mode ready: energy-aware tasks, proactive nudges, guided learning, and resumable queue-backed work.")
        appendOutput("Active memory management: \(activeMemoryDepth) (set atlas.local.memory.depth = lean|balanced|deep).")
        appendOutput(cadToolsStatusLine)
        if allowsAutomaticRuntimeWork {
            startPromptQueueWorker()
            startAgenticBusinessRuntime()
        }
        bootstrapCompleted = true
        consumePendingGUIValidationLaunchRequestIfNeeded()
        if let pendingGUIValidationTriggerSource {
            self.pendingGUIValidationTriggerSource = nil
            requestGUIValidationSuite(triggerSource: pendingGUIValidationTriggerSource)
        }
        if allowsAutomaticRuntimeWork {
            Task { await finishBootstrapBackgroundRefresh() }
        }
    }

    private func finishBootstrapBackgroundRefresh() async {
        await refreshHealth()
        await repairCADToolSettingsIfNeeded()
        await runCADToolsHealthCheck()
        await syncSessionFromServerIfAvailable()
        await loadSurvey()
        await loadNotes()
        rebuildInsightsAndExecutionPlan()
        await refreshCommandModelBrief()
        await refreshWorkspaceModelBrief()
        await refreshFeed()
        await refreshNatureSignalStackNow(sendNotifications: false)
        revealRemoteTransferTutorialIfNeeded()
    }

    private func migrateLegacyBrandingDefaultsIfNeeded() {
        if longTermVision == "Scale Atlas travel design infrastructure." {
            longTermVision = "Scale BlackHaven travel design infrastructure."
        }
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API reachable. Capabilities refreshed.")
        } catch {
            appendOutput("API health unavailable. App remains in local-first mode.")
        }
    }

    var selectedRAndDJob: RAndDJobResponse? {
        guard let selectedRAndDJobID else { return rAndDJobs.first }
        return rAndDJobs.first(where: { $0.jobID == selectedRAndDJobID }) ?? rAndDJobs.first
    }

    var selectedRAndDDocument: RAndDDocumentRecord? {
        guard let selectedRAndDDocumentID else { return rAndDDocuments.first }
        return rAndDDocuments.first(where: { $0.documentID == selectedRAndDDocumentID }) ?? rAndDDocuments.first
    }

    var rAndDMajorDoctrineFailures: [RAndDDoctrineCheck] {
        rAndDDoctrine?.checks.filter(\.blocksRelease) ?? []
    }

    var rAndDSelectedDocumentRevisionDriftMessage: String? {
        guard let document = selectedRAndDDocument, let job = selectedRAndDJob else { return nil }
        var warnings: [String] = []
        if let acceptedPlanVersion = job.acceptedPlanVersion, document.sourcePlanVersion != acceptedPlanVersion {
            warnings.append("source plan v\(document.sourcePlanVersion) is behind current accepted plan v\(acceptedPlanVersion)")
        }
        if let latestRevision = rAndDDoctrine?.revisionHistory.last?.label,
           latestRevision != document.revisionLabel
        {
            warnings.append("document revision \(document.revisionLabel) differs from latest doctrine revision \(latestRevision)")
        }
        return warnings.isEmpty ? nil : warnings.joined(separator: " · ")
    }

    func createRAndDJob() async {
        let prompt = rAndDPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            rAndDStatusLine = "Write a detailed engineering prompt before starting."
            appendOutput(rAndDStatusLine)
            return
        }

        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        rAndDStatusLine = "Building local context pack for R&D planning..."

        let researchSummary = await academicResearchService.discover(prompt: prompt)?.summary ?? ""
        let localPlanningNote = await localRAndDPlanningNote(for: prompt) ?? ""

        do {
            let response = try await api.createRAndDJob(
                payload: RAndDJobCreatePayload(
                    productType: inferredRAndDProductType(from: prompt),
                    prompt: prompt,
                    locale: health?.capabilities.deepPersonalization == true ? "en" : nil,
                    clientResearchSummary: researchSummary,
                    clientLocalPlanningNote: localPlanningNote
                )
            )
            upsertRAndDJob(response)
            selectedRAndDJobID = response.jobID
            rAndDPlanRevisionDraft = ""
            rAndDChangeRequestDraft = ""
            await refreshRAndDSelectedJobDetails()
            rAndDStatusLine = "R&D plan drafted. Review the technical plan before approving long-running execution."
            appendOutput("R&D job created: \(response.jobID). Review the technical plan and simple summary before approving.")
            persistStateToDisk()
        } catch {
            rAndDStatusLine = "Failed to create R&D job: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func refreshRAndDSelectedJobDetails() async {
        guard let selected = selectedRAndDJob else { return }
        do {
            let refreshed = try await api.rAndDJob(jobID: selected.jobID)
            upsertRAndDJob(refreshed)
            let artifacts = try await api.rAndDArtifacts(jobID: refreshed.jobID)
            let timeline = try await api.rAndDTimeline(jobID: refreshed.jobID)
            let governance = try await api.rAndDGovernance(jobID: refreshed.jobID)
            let traceability = try await api.rAndDTraceability(jobID: refreshed.jobID)
            let doctrine = try await api.rAndDDoctrine(jobID: refreshed.jobID)
            let documents = try await api.rAndDDocuments(jobID: refreshed.jobID)
            rAndDArtifacts = artifacts.artifacts
            rAndDInspectionGuide = artifacts.inspectionGuide
            rAndDTimeline = timeline.timeline
            rAndDGovernance = governance
            rAndDTraceabilityRows = traceability.rows
            rAndDDoctrine = doctrine
            rAndDDocuments = documents.documents
            rAndDDocumentationBundles = documents.bundles
            selectedRAndDDocumentID = selectedRAndDDocumentID ?? documents.documents.first?.documentID
            hydrateRAndDDocumentDraftsIfNeeded(from: refreshed)
            refreshRAndDDocumentPreview()
            materializeRAndDLocalWorkspace(job: refreshed, artifacts: artifacts.artifacts, inspectionGuide: artifacts.inspectionGuide)
            await maybeExecuteLocalRAndDArtifacts(job: refreshed, artifacts: artifacts.artifacts, trigger: "refresh")
            rAndDStatusLine = statusLine(for: refreshed)
            persistStateToDisk()
        } catch {
            rAndDStatusLine = "R&D refresh failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func rerunSelectedRAndDLocalCADExecution() async {
        guard let selected = selectedRAndDJob else { return }
        guard canExecuteSelectedRAndDJob(selected) else { return }
        await maybeExecuteLocalRAndDArtifacts(job: selected, artifacts: rAndDArtifacts, trigger: "manual", force: true)
        persistStateToDisk()
    }

    func reviseSelectedRAndDPlan() async {
        guard let selected = selectedRAndDJob else { return }
        let revision = rAndDPlanRevisionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty else {
            rAndDStatusLine = "Write a revision request before asking for a new plan."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.reviseRAndDPlan(jobID: selected.jobID, revisionPrompt: revision)
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            rAndDStatusLine = "Plan revised. Review the updated plan before approving."
            appendOutput("R&D plan revised for job \(response.jobID).")
        } catch {
            rAndDStatusLine = "Plan revision failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func approveSelectedRAndDPlan() async {
        guard let selected = selectedRAndDJob else { return }
        guard canExecuteSelectedRAndDJob(selected) else { return }
        guard rAndDMajorDoctrineFailures.isEmpty else {
            let summary = rAndDMajorDoctrineFailures.map(\.doctrineArea).joined(separator: ", ")
            rAndDStatusLine = "Plan approval blocked by major doctrine findings: \(summary)."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.approveRAndDPlan(jobID: selected.jobID)
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("R&D plan approved. Background execution has started.")
        } catch {
            rAndDStatusLine = "Plan approval failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func approveSelectedRAndDStage() async {
        guard let selected = selectedRAndDJob else { return }
        guard canExecuteSelectedRAndDJob(selected) else { return }
        guard rAndDMajorDoctrineFailures.isEmpty else {
            let summary = rAndDMajorDoctrineFailures.map(\.doctrineArea).joined(separator: ", ")
            rAndDStatusLine = "Stage approval blocked by major doctrine findings: \(summary)."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        let note = rAndDChangeRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await api.approveRAndDStage(jobID: selected.jobID, note: note.isEmpty ? nil : note)
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("R&D execution resumed for \(response.jobID). Current stage: \(response.currentStage.rawValue).")
        } catch {
            rAndDStatusLine = "Stage approval failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func pauseSelectedRAndDExecution() async {
        guard let selected = selectedRAndDJob else { return }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.pauseRAndDExecution(jobID: selected.jobID)
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("R&D execution will pause after the current stage for \(response.jobID).")
        } catch {
            rAndDStatusLine = "Pause request failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func submitSelectedRAndDChangeRequest(scope: String) async {
        guard let selected = selectedRAndDJob else { return }
        let request = rAndDChangeRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            rAndDStatusLine = "Write a change request before submitting one."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.submitRAndDChangeRequest(
                jobID: selected.jobID,
                scope: scope,
                targetPartID: rAndDTargetPartID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rAndDTargetPartID.trimmingCharacters(in: .whitespacesAndNewlines),
                request: request
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("R&D change request submitted for \(scope). Review the revised plan before continuing.")
        } catch {
            rAndDStatusLine = "Change request failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func generateSelectedRAndDComplianceReport() async {
        guard let selected = selectedRAndDJob else { return }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.generateRAndDReport(
                jobID: selected.jobID,
                title: rAndDReportTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rAndDReportTitleDraft,
                reportType: "engineering_compliance_packet"
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("Compliance packet generated for \(response.jobID).")
        } catch {
            rAndDStatusLine = "Compliance report generation failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func generateSelectedRAndDDocument() async {
        guard let selected = selectedRAndDJob else { return }
        if rAndDDocumentAudienceMode == "private", !rAndDMajorDoctrineFailures.isEmpty {
            let summary = rAndDMajorDoctrineFailures.map(\.doctrineArea).joined(separator: ", ")
            rAndDStatusLine = "Private documentation blocked by major doctrine findings: \(summary)."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.generateRAndDDocument(
                jobID: selected.jobID,
                payload: RAndDDocumentGeneratePayload(
                    documentType: rAndDSelectedDocumentType,
                    audienceMode: rAndDDocumentAudienceMode,
                    title: trimmedOrNil(rAndDDocumentTitleDraft),
                    platformName: trimmedOrNil(rAndDDocumentPlatformNameDraft),
                    revisionLabel: trimmedOrNil(rAndDDocumentRevisionDraft),
                    purpose: trimmedOrNil(rAndDDocumentPurposeDraft),
                    targetAudience: trimmedOrNil(rAndDDocumentTargetAudienceDraft),
                    author: trimmedOrNil(rAndDDocumentAuthorDraft)
                )
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            if let generated = rAndDDocuments.last(where: {
                $0.documentType == rAndDSelectedDocumentType && $0.audienceMode == rAndDDocumentAudienceMode
            }) {
                selectedRAndDDocumentID = generated.documentID
                refreshRAndDDocumentPreview()
            }
            appendOutput("Generated \(rAndDSelectedDocumentType.replacingOccurrences(of: "_", with: " ")) for \(response.jobID).")
        } catch {
            if buildOfflineFallbackRAndDDocument() != nil {
                appendOutput("Generated offline fallback documentation from persisted job state.")
            } else {
                rAndDStatusLine = "Document generation failed: \(error.localizedDescription)"
                appendOutput(rAndDStatusLine)
            }
        }
    }

    func generateSelectedRAndDDocumentBundle() async {
        guard let selected = selectedRAndDJob else { return }
        if rAndDDocumentAudienceMode == "private", !rAndDMajorDoctrineFailures.isEmpty {
            let summary = rAndDMajorDoctrineFailures.map(\.doctrineArea).joined(separator: ", ")
            rAndDStatusLine = "Private documentation bundle blocked by major doctrine findings: \(summary)."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.generateRAndDDocumentBundle(
                jobID: selected.jobID,
                payload: RAndDDocumentBundleGeneratePayload(
                    audienceMode: rAndDDocumentAudienceMode,
                    titlePrefix: trimmedOrNil(rAndDDocumentTitleDraft),
                    platformName: trimmedOrNil(rAndDDocumentPlatformNameDraft),
                    revisionLabel: trimmedOrNil(rAndDDocumentRevisionDraft),
                    author: trimmedOrNil(rAndDDocumentAuthorDraft)
                )
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("Generated core documentation bundle for \(response.jobID).")
        } catch {
            rAndDStatusLine = "Bundle generation failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func selectRAndDDocument(_ documentID: String) {
        selectedRAndDDocumentID = documentID
        refreshRAndDDocumentPreview()
        persistStateToDisk()
    }

    func refreshRAndDDocumentPreview() {
        guard let document = selectedRAndDDocument else {
            rAndDDocumentPreviewHTML = ""
            rAndDDocumentPreviewStatus = "Generate or select a document to preview it here."
            return
        }
        rAndDDocumentPreviewHTML = renderRAndDDocumentHTML(document)
        if let drift = rAndDSelectedDocumentRevisionDriftMessage {
            rAndDDocumentPreviewStatus = "Previewing \(document.title) · \(document.revisionLabel) · \(document.audienceMode) · revision drift: \(drift)"
        } else {
            rAndDDocumentPreviewStatus = "Previewing \(document.title) · \(document.revisionLabel) · \(document.audienceMode)"
        }
    }

    func exportSelectedRAndDDocumentToPDF() async {
        guard let document = selectedRAndDDocument else {
            rAndDStatusLine = "Select a generated document before exporting."
            appendOutput(rAndDStatusLine)
            return
        }
        if rAndDDocumentPreviewHTML.isEmpty {
            refreshRAndDDocumentPreview()
        }
        let html = rAndDDocumentPreviewHTML
        let destination = rAndDDocumentExportURL(for: document)
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            try await LocalPDFExporter.export(html: html, to: destination)
            rAndDLastExportPath = destination.path
            rAndDLastExportError = ""
            rAndDStatusLine = "Exported PDF to \(destination.lastPathComponent) (\(document.revisionLabel))."
            appendOutput("R&D PDF export succeeded: \(destination.path)")
            persistStateToDisk()
        } catch {
            rAndDLastExportError = error.localizedDescription
            rAndDStatusLine = "PDF export failed during local render: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func exportCurrentRAndDBundleToPDFs() async {
        guard let job = selectedRAndDJob else {
            rAndDStatusLine = "Select an R&D job before exporting a documentation bundle."
            appendOutput(rAndDStatusLine)
            return
        }
        let bundleDocuments = preferredRAndDBundleDocuments()
        guard !bundleDocuments.isEmpty else {
            rAndDStatusLine = "Generate the documentation bundle first, or create at least one document before exporting."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        let folderURL = rAndDBundleExportFolderURL(for: job, documents: bundleDocuments)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for document in bundleDocuments {
                let outputURL = folderURL
                    .appendingPathComponent(rAndDDocumentFileStem(for: document))
                    .appendingPathExtension("pdf")
                try await LocalPDFExporter.export(html: renderRAndDDocumentHTML(document), to: outputURL)
            }
            rAndDLastExportPath = folderURL.path
            rAndDLastExportError = ""
            rAndDBundleExportStatus = "Exported \(bundleDocuments.count) PDFs to \(folderURL.path)"
            rAndDStatusLine = rAndDBundleExportStatus
            appendOutput(rAndDBundleExportStatus)
            persistStateToDisk()
        } catch {
            rAndDLastExportError = error.localizedDescription
            rAndDBundleExportStatus = "Bundle export failed: \(error.localizedDescription)"
            rAndDStatusLine = rAndDBundleExportStatus
            appendOutput(rAndDBundleExportStatus)
        }
    }

    func recordSelectedRAndDReview(status: String) async {
        guard let selected = selectedRAndDJob else { return }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.recordRAndDReview(
                jobID: selected.jobID,
                title: "macOS structured review",
                status: status,
                note: rAndDReviewNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rAndDReviewNoteDraft
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("Structured review recorded for \(response.jobID).")
        } catch {
            rAndDStatusLine = "Design review recording failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func recordSelectedRAndDApproval(createBaseline: Bool) async {
        guard let selected = selectedRAndDJob else { return }
        let reviewerName = rAndDApprovalReviewerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let reviewerRole = rAndDApprovalReviewerRole.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reviewerName.isEmpty, !reviewerRole.isEmpty else {
            rAndDStatusLine = "Reviewer name and role are required before recording approval."
            appendOutput(rAndDStatusLine)
            return
        }
        rAndDIsWorking = true
        defer { rAndDIsWorking = false }
        do {
            let response = try await api.recordRAndDApproval(
                jobID: selected.jobID,
                payload: RAndDApprovalRecordPayload(
                    reviewerName: reviewerName,
                    reviewerRole: reviewerRole,
                    reviewerOrg: nil,
                    authorityKind: rAndDApprovalAuthorityKind,
                    approvalState: "approved",
                    scopeType: "job",
                    scopeID: selected.jobID,
                    comment: rAndDApprovalCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rAndDApprovalCommentDraft,
                    conditions: [],
                    createBaselineIfApproved: createBaseline,
                    baselineTitle: createBaseline ? "macOS approved baseline" : nil
                )
            )
            upsertRAndDJob(response)
            await refreshRAndDSelectedJobDetails()
            appendOutput("Approval recorded for \(response.jobID).")
        } catch {
            rAndDStatusLine = "Approval recording failed: \(error.localizedDescription)"
            appendOutput(rAndDStatusLine)
        }
    }

    func buildOfflineFallbackRAndDDocument() -> RAndDDocumentRecord? {
        guard let job = selectedRAndDJob else { return nil }
        let doctrineChecks = rAndDDoctrine?.checks ?? []
        let sections = [
            RAndDDocumentSection(
                sectionID: "offline-overview",
                heading: "Overview",
                bodyMarkdown: "\(job.productType.replacingOccurrences(of: "_", with: " ")) in \(rAndDDocumentAudienceMode) mode. Generated locally from persisted job, governance, artifact, and doctrine state.",
                orderIndex: 0
            ),
            RAndDDocumentSection(
                sectionID: "offline-artifacts",
                heading: "Artifacts and Evidence",
                bodyMarkdown: rAndDArtifacts.isEmpty
                    ? "- No artifacts available in persisted state yet."
                    : rAndDArtifacts.prefix(10).map { "- \($0.title) (\($0.artifactType))" }.joined(separator: "\n"),
                orderIndex: 1
            ),
            RAndDDocumentSection(
                sectionID: "offline-doctrine",
                heading: "Doctrine Checks",
                bodyMarkdown: doctrineChecks.isEmpty
                    ? "- Doctrine data unavailable in persisted state."
                    : doctrineChecks.map { check in
                        "- [\(check.severity.uppercased())] \(check.doctrineArea): \(check.passed ? "pass" : "needs work. \(check.suggestedFix)")"
                    }.joined(separator: "\n"),
                orderIndex: 2
            ),
            RAndDDocumentSection(
                sectionID: "offline-traceability",
                heading: "Traceability and Open Issues",
                bodyMarkdown: rAndDTraceabilityRows.isEmpty
                    ? "- No traceability rows available."
                    : rAndDTraceabilityRows.prefix(8).map { row in
                        let openIssues = row.unresolvedItems.isEmpty ? "No open issues." : row.unresolvedItems.joined(separator: " | ")
                        return "- \(row.title): \(openIssues)"
                    }.joined(separator: "\n"),
                orderIndex: 3
            ),
        ]

        let document = RAndDDocumentRecord(
            documentID: "offline-\(UUID().uuidString)",
            documentType: rAndDSelectedDocumentType,
            audienceMode: rAndDDocumentAudienceMode,
            title: trimmedOrNil(rAndDDocumentTitleDraft) ?? "\(job.productType.replacingOccurrences(of: "_", with: " ").capitalized) Documentation",
            projectName: "BlackHaven R&D",
            platformName: trimmedOrNil(rAndDDocumentPlatformNameDraft) ?? job.productType.replacingOccurrences(of: "_", with: " "),
            revisionLabel: trimmedOrNil(rAndDDocumentRevisionDraft) ?? "offline-\(job.acceptedPlanVersion ?? 1)",
            sourceJobID: job.jobID,
            sourcePlanVersion: job.acceptedPlanVersion ?? 1,
            artifactIDs: rAndDArtifacts.map(\.artifactID),
            moduleIDs: rAndDDoctrine?.moduleDefinitions.map(\.moduleID) ?? [],
            purpose: trimmedOrNil(rAndDDocumentPurposeDraft) ?? "Provide a locally generated documentation draft from the current persisted R&D state.",
            targetAudience: trimmedOrNil(rAndDDocumentTargetAudienceDraft) ?? (rAndDDocumentAudienceMode == "public" ? "Public builders, repair learners, and non-expert operators" : "Internal manufacturing, service, and review operators"),
            author: trimmedOrNil(rAndDDocumentAuthorDraft) ?? accountLabel,
            assumptions: job.latestPlan?.assumptions ?? [],
            safetyNotes: [
                "Review locally generated content before using it for manufacturing, service, or safety-critical work.",
                "Keep power isolated and loads supported before repair or inspection."
            ],
            toolsRequired: rAndDDoctrine?.toolRequirements ?? [],
            materialsRequired: rAndDDoctrine?.bomItems.map(\.name) ?? [],
            bomSummary: rAndDDoctrine?.bomItems ?? [],
            sections: sections,
            manufacturabilityNotes: doctrineChecks.filter { $0.doctrineArea == "manufacturability" }.map(\.suggestedFix),
            affordabilityNotes: doctrineChecks.filter { $0.doctrineArea == "affordability" }.map(\.suggestedFix),
            repairabilityNotes: doctrineChecks.filter { $0.doctrineArea == "teenager_repairability" || $0.doctrineArea == "low_tool_variety" }.map(\.suggestedFix),
            serviceabilityNotes: doctrineChecks.filter { $0.doctrineArea == "service_access" }.map(\.suggestedFix),
            publicBenefitRationale: "This offline draft turns persisted R&D structure into a shareable document so manufacturing, serviceability, and repair knowledge remains understandable and local-first.",
            exports: [],
            createdAt: isoTimestamp(),
            updatedAt: isoTimestamp()
        )
        if let index = rAndDDocuments.firstIndex(where: { $0.documentType == document.documentType && $0.audienceMode == document.audienceMode }) {
            rAndDDocuments[index] = document
        } else {
            rAndDDocuments.insert(document, at: 0)
        }
        selectedRAndDDocumentID = document.documentID
        refreshRAndDDocumentPreview()
        persistStateToDisk()
        return document
    }

    private func hydrateRAndDDocumentDraftsIfNeeded(from job: RAndDJobResponse) {
        if rAndDDocumentPlatformNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rAndDDocumentPlatformNameDraft = job.productType.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if rAndDDocumentAuthorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rAndDDocumentAuthorDraft = accountLabel
        }
        if rAndDDocumentRevisionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rAndDDocumentRevisionDraft = "R\(job.acceptedPlanVersion ?? 1)"
        }
    }

    private func renderRAndDDocumentHTML(_ document: RAndDDocumentRecord) -> String {
        let revisionWarning = rAndDSelectedDocumentRevisionDriftMessage.map {
            "<div class=\"callout warning\"><strong>Revision drift:</strong> \(escapeHTML($0))</div>"
        } ?? ""
        let assumptionList = htmlList(document.assumptions)
        let safetyList = htmlList(document.safetyNotes)
        let toolList = document.toolsRequired.isEmpty
            ? "<p class=\"muted\">No tools recorded.</p>"
            : "<ul>" + document.toolsRequired.map { "<li><strong>\(escapeHTML($0.name))</strong> · \(escapeHTML($0.reason))</li>" }.joined() + "</ul>"
        let materialList = htmlList(document.materialsRequired)
        let bomRows = document.bomSummary.isEmpty
            ? "<tr><td colspan=\"3\">No BOM items recorded.</td></tr>"
            : document.bomSummary.map {
                "<tr><td>\(escapeHTML($0.name))</td><td>\(escapeHTML($0.quantity))</td><td>\(escapeHTML($0.notes))</td></tr>"
            }.joined()
        let doctrineSummary = htmlList(document.manufacturabilityNotes + document.affordabilityNotes + document.repairabilityNotes + document.serviceabilityNotes)
        let doctrineBadges = (rAndDDoctrine?.checks ?? [])
            .prefix(8)
            .map { check in
                let state = check.passed ? "pass" : "needs work"
                return "<span class=\"badge \(check.passed ? "pass" : "warn")\">\(escapeHTML(check.doctrineArea)) · \(escapeHTML(check.severity)) · \(escapeHTML(state))</span>"
            }
            .joined(separator: " ")
        let sections = document.sections.sorted(by: { $0.orderIndex < $1.orderIndex }).map { section in
            """
            <section>
                <h2>\(escapeHTML(section.heading))</h2>
                \(markdownishToHTML(section.bodyMarkdown))
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 44px; color: #14202b; line-height: 1.5; }
                h1, h2, h3 { color: #0d2538; page-break-after: avoid; }
                h1 { font-size: 30px; margin-bottom: 8px; }
                h2 { font-size: 18px; margin-top: 26px; border-bottom: 1px solid #d6dde5; padding-bottom: 6px; }
                p, li { font-size: 12px; }
                .meta { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px 16px; margin: 18px 0 26px; }
                .meta div { background: #f3f6f8; padding: 10px 12px; border-radius: 10px; }
                .muted { color: #52616f; }
                .eyebrow { letter-spacing: 0.16em; text-transform: uppercase; font-size: 11px; color: #61717f; margin-bottom: 6px; }
                .hero { border: 1px solid #d6dde5; border-radius: 18px; padding: 22px 24px; background: linear-gradient(180deg, #ffffff 0%, #f4f7f9 100%); }
                .badge-row { display: flex; flex-wrap: wrap; gap: 8px; margin: 10px 0 4px; }
                .badge { display: inline-block; border-radius: 999px; padding: 6px 10px; font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; background: #e8eef2; color: #213445; }
                .badge.pass { background: #e3f4ea; color: #1b5c38; }
                .badge.warn { background: #fff0d8; color: #8a4e00; }
                table { width: 100%; border-collapse: collapse; margin-top: 12px; font-size: 12px; }
                th, td { border: 1px solid #d6dde5; padding: 8px; vertical-align: top; text-align: left; }
                .callout { background: #fff8e8; border: 1px solid #e4cf91; border-radius: 10px; padding: 12px 14px; margin: 18px 0; }
                .callout.warning { background: #fff0f0; border-color: #e3a6a6; }
                .footer { margin-top: 30px; font-size: 11px; color: #6b7a88; }
            </style>
        </head>
        <body>
            <div class="hero">
                <div class="eyebrow">BlackHaven Local-First R&amp;D Documentation</div>
                <h1>\(escapeHTML(document.title))</h1>
                <p class="muted">\(escapeHTML(document.projectName)) · \(escapeHTML(document.documentType.replacingOccurrences(of: "_", with: " ")))</p>
                <div class="badge-row">\(doctrineBadges)</div>
            </div>
            <div class="meta">
                <div><strong>Platform</strong><br>\(escapeHTML(document.platformName))</div>
                <div><strong>Revision</strong><br>\(escapeHTML(document.revisionLabel))</div>
                <div><strong>Audience</strong><br>\(escapeHTML(document.targetAudience))</div>
                <div><strong>Author</strong><br>\(escapeHTML(document.author))</div>
                <div><strong>Purpose</strong><br>\(escapeHTML(document.purpose))</div>
                <div><strong>Source Job</strong><br>\(escapeHTML(document.sourceJobID))</div>
            </div>
            <div class="callout"><strong>Public benefit / rationale:</strong> \(escapeHTML(document.publicBenefitRationale))</div>
            \(revisionWarning)
            <h2>Assumptions</h2>
            \(assumptionList)
            <h2>Safety Notes</h2>
            \(safetyList)
            <h2>Tools Required</h2>
            \(toolList)
            <h2>Materials Required</h2>
            \(materialList)
            <h2>BOM Summary</h2>
            <table>
                <thead><tr><th>Item</th><th>Quantity</th><th>Notes</th></tr></thead>
                <tbody>\(bomRows)</tbody>
            </table>
            <h2>Doctrine Summary</h2>
            \(doctrineSummary)
            \(sections)
            <div class="footer">Generated locally by BlackHaven on \(escapeHTML(document.updatedAt)). Review before field use.</div>
        </body>
        </html>
        """
    }

    private func markdownishToHTML(_ markdown: String) -> String {
        let lines = markdown
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return "<p class=\"muted\">No content available.</p>" }
        var html: [String] = []
        var inList = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                if inList {
                    html.append("</ul>")
                    inList = false
                }
                html.append("<h3>\(escapeHTML(String(trimmed.dropFirst(3))))</h3>")
            } else if trimmed.hasPrefix("- ") {
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(escapeHTML(String(trimmed.dropFirst(2))))</li>")
            } else {
                if inList {
                    html.append("</ul>")
                    inList = false
                }
                html.append("<p>\(escapeHTML(trimmed))</p>")
            }
        }
        if inList {
            html.append("</ul>")
        }
        return html.joined(separator: "\n")
    }

    private func htmlList(_ items: [String]) -> String {
        guard !items.isEmpty else { return "<p class=\"muted\">No items recorded.</p>" }
        return "<ul>" + items.map { "<li>\(escapeHTML($0))</li>" }.joined() + "</ul>"
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func preferredRAndDBundleDocuments() -> [RAndDDocumentRecord] {
        if let latestBundle = rAndDDocumentationBundles
            .filter({ $0.audienceMode == rAndDDocumentAudienceMode })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first
        {
            let lookup = Dictionary(uniqueKeysWithValues: rAndDDocuments.map { ($0.documentID, $0) })
            let bundleDocs = latestBundle.documentIDs.compactMap { lookup[$0] }
            if !bundleDocs.isEmpty {
                return bundleDocs
            }
        }
        let preferredTypes = [
            "manufacturing_build_guide",
            "module_assembly_guide",
            "service_manual",
            "repair_guide",
            "qa_inspection_checklist",
            "public_project_story"
        ]
        return preferredTypes.compactMap { type in
            rAndDDocuments.first(where: {
                $0.documentType == type && ($0.audienceMode == rAndDDocumentAudienceMode || type == "public_project_story")
            })
        }
    }

    private func rAndDBundleExportFolderURL(for job: RAndDJobResponse, documents: [RAndDDocumentRecord]) -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let revision = documents.first?.revisionLabel.replacingOccurrences(of: " ", with: "-") ?? "bundle"
        let folderName = [
            "blackhaven-rnd-docs",
            job.jobID.lowercased(),
            revision.lowercased()
        ].joined(separator: "-")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    private func rAndDDocumentFileStem(for document: RAndDDocumentRecord) -> String {
        [
            document.platformName,
            document.documentType.replacingOccurrences(of: "_", with: "-"),
            document.revisionLabel
        ]
        .map {
            $0.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
        }
        .joined(separator: "-")
    }

    private func rAndDDocumentExportURL(for document: RAndDDocumentRecord) -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(rAndDDocumentFileStem(for: document)).appendingPathExtension("pdf")
    }

    private func upsertRAndDJob(_ job: RAndDJobResponse) {
        if let index = rAndDJobs.firstIndex(where: { $0.jobID == job.jobID }) {
            rAndDJobs[index] = job
        } else {
            rAndDJobs.insert(job, at: 0)
        }
        rAndDJobs.sort { $0.jobID > $1.jobID }
    }

    private func statusLine(for job: RAndDJobResponse) -> String {
        "R&D \(job.currentStage.rawValue) · \(job.progressPercent)% complete · \(job.eta.estimatedRemainingMinutes)m remaining · bottleneck: \(job.eta.currentBottleneck)"
    }

    private func canExecuteSelectedRAndDJob(_ job: RAndDJobResponse) -> Bool {
        if ["mechanical", "mechanical_cad"].contains(job.designDomain), !mechanicalExecutorHealthy {
            rAndDStatusLine = "Mechanical execution needs healthy FreeCAD, FreeCADCmd, and CalculiX paths before starting."
            appendOutput(rAndDStatusLine)
            revealCADToolsSetupWizard()
            return false
        }
        return true
    }

    private func inferredRAndDProductType(from prompt: String) -> String {
        if !rAndDSelectedProductType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lowerSelection = rAndDSelectedProductType.lowercased()
            if lowerSelection != "auto" {
                return rAndDSelectedProductType
            }
        }
        let lower = prompt.lowercased()
        if lower.contains("kicad") || lower.contains("pcb") || lower.contains("schematic") {
            return "pcb_assembly"
        }
        if lower.contains("electronics") || lower.contains("sensor") || lower.contains("board") {
            return "electronic_product"
        }
        if lower.contains("vehicle part") || lower.contains("suspension arm") || lower.contains("battery enclosure") {
            return "vehicle_part"
        }
        if lower.contains("vehicle") || lower.contains("van") || lower.contains("trailer") || lower.contains("car") {
            return "mechanical_vehicle"
        }
        return "general_product"
    }

    private func localRAndDSemanticMemoryDigest(for prompt: String) -> String {
        let queryTokens = Set(
            prompt
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
        let ranked = workspaceMemoryRecords
            .map { record -> (WorkspaceMemoryRecord, Double) in
                let tagScore = Double(record.tags.filter { queryTokens.contains($0.lowercased()) }.count) * 2.0
                let keyScore = queryTokens.contains(record.key.lowercased()) ? 1.5 : 0.0
                let valueScore = queryTokens.reduce(into: 0.0) { partial, token in
                    if record.value.lowercased().contains(token) {
                        partial += 0.4
                    }
                }
                return (record, tagScore + keyScore + valueScore + record.weight)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(12)

        guard !ranked.isEmpty else { return "No strong local semantic memory matches were found." }

        let grouped = Dictionary(grouping: ranked) { pair in
            pair.0.tags.first ?? pair.0.key
        }
        let clusters = grouped
            .sorted { $0.key < $1.key }
            .map { key, values in
                let summaries = values.prefix(3).map { "\($0.0.key): \($0.0.value)" }
                return "\(key): \(summaries.joined(separator: " | "))"
            }
        return clusters.joined(separator: "\n")
    }

    private func localRAndDPlanningNote(for prompt: String) async -> String? {
        guard localInferenceEnabled, let endpoint = localInferenceEndpointURL else { return nil }
        let productType = inferredRAndDProductType(from: prompt)
        let semanticMemoryDigest = localRAndDSemanticMemoryDigest(for: prompt)
        let systemPrompt = """
        You are Atlas local planning and context compaction.
        Build a concise but information-dense R&D planning note from the user prompt, semantic memory digest, and available local context.
        Your job:
        1. infer the likely product/development lane
        2. rewrite the task into a stronger execution-ready internal prompt
        3. preserve all important constraints without losing detail
        4. group relevant memory into semantic categories instead of dropping it
        5. call out assembly stages, likely subsystem boundaries, validation scopes, and exploded-view needs
        6. identify when frontier/cloud models or CAD APIs should be escalated
        7. never claim legal sign-off or guaranteed manufacturing certification
        Keep it under 700 words and use clear section labels.
        """
        let enrichedPrompt = """
        Product type hint: \(productType)

        User prompt:
        \(prompt)

        Local semantic memory digest:
        \(semanticMemoryDigest)
        """
        let plan = await resolveLocalInferenceRuntimePlan(
            task: "general_chat",
            fallbackTemperature: 0.15,
            fallbackMaxTokens: 900,
            fallbackTimeoutSeconds: 24
        )
        for model in plan.modelOrder.prefix(2) {
            if let output = await Self.runOpenAICompatiblePrompt(
                endpoint: endpoint,
                model: model,
                prompt: enrichedPrompt,
                timeoutSeconds: plan.timeoutSeconds,
                temperature: plan.temperature,
                maxTokens: min(900, plan.maxTokens),
                systemPrompt: systemPrompt
            ),
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                appendOutput("Local R&D planning note generated with \(model).")
                return output
            }
        }
        return nil
    }

    private func materializeRAndDLocalWorkspace(
        job: RAndDJobResponse,
        artifacts: [RAndDArtifact],
        inspectionGuide: String
    ) {
        guard let rootURL = rAndDWorkspaceRootURL(jobID: job.jobID) else { return }
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            for folder in ["source", "exports", "simulation", "review", "logs"] {
                try fileManager.createDirectory(
                    at: rootURL.appendingPathComponent(folder, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }

            let metadataURL = rootURL
                .appendingPathComponent("logs", isDirectory: true)
                .appendingPathComponent("routing-summary.json", isDirectory: false)
            let metadata = """
            {
              "job_id": "\(job.jobID)",
              "product_type": "\(job.productType)",
              "design_domain": "\(job.designDomain)",
              "local_only_tasks": \(jsonArrayLiteral(job.routingSummary.localOnlyTasks)),
              "gemini_escalated_tasks": \(jsonArrayLiteral(job.routingSummary.geminiEscalatedTasks)),
              "gpt_escalated_tasks": \(jsonArrayLiteral(job.routingSummary.gptEscalatedTasks)),
              "executor_tasks": \(jsonArrayLiteral(job.routingSummary.executorTasks))
            }
            """
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)

            let guideURL = rootURL
                .appendingPathComponent("review", isDirectory: true)
                .appendingPathComponent("inspection-guide.md", isDirectory: false)
            try inspectionGuide.write(to: guideURL, atomically: true, encoding: .utf8)

            var localAssets: [RAndDLocalWorkspaceAsset] = []
            for artifact in artifacts {
                let destinationFolder = rootURL.appendingPathComponent(subdirectoryForRAndDArtifact(artifact), isDirectory: true)
                let fileName = "\(sanitizeArtifactPathComponent(artifact.artifactID))\(fileExtensionForArtifact(artifact))"
                let destinationURL = destinationFolder.appendingPathComponent(fileName, isDirectory: false)
                try artifact.content.write(to: destinationURL, atomically: true, encoding: .utf8)
                localAssets.append(
                    RAndDLocalWorkspaceAsset(
                        artifactID: artifact.artifactID,
                        title: artifact.title,
                        artifactType: artifact.artifactType,
                        format: artifact.format,
                        localPath: destinationURL.path,
                        preview: String(artifact.content.prefix(220))
                    )
                )
            }

            rAndDWorkspaceRootPath = rootURL.path
            rAndDLocalWorkspaceAssets = localAssets.sorted { $0.title < $1.title }
        } catch {
            appendOutput("Failed to materialize local R&D workspace: \(error.localizedDescription)")
        }
    }

    private func rAndDWorkspaceRootURL(jobID: String) -> URL? {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return baseURL
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent("RnD", isDirectory: true)
            .appendingPathComponent("jobs", isDirectory: true)
            .appendingPathComponent(jobID, isDirectory: true)
    }

    private func subdirectoryForRAndDArtifact(_ artifact: RAndDArtifact) -> String {
        switch artifact.artifactType {
        case "cad_source", "schematic_source", "pcb_layout_source", "blueprint_package":
            return "source"
        case "simulation_input", "simulation_result", "validation_report", "self_check_report":
            return "simulation"
        case "review_scene_package", "assembly_stage_review_scene", "exploded_view_manifest", "assembly_stage_package", "assembly_package", "inspection_guide":
            return "review"
        default:
            return "exports"
        }
    }

    private func fileExtensionForArtifact(_ artifact: RAndDArtifact) -> String {
        let format = artifact.format.lowercased()
        switch format {
        case "py", "md", "csv", "json", "inp", "usda":
            return ".\(format)"
        case "step.manifest":
            return ".step.manifest"
        case "kicad_sch":
            return ".kicad_sch"
        case "kicad_pcb":
            return ".kicad_pcb"
        default:
            return ".txt"
        }
    }

    private func sanitizeArtifactPathComponent(_ raw: String) -> String {
        let filtered = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return filtered.isEmpty ? "artifact" : filtered
    }

    private func jsonArrayLiteral(_ values: [String]) -> String {
        let encoded = values.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        return "[\(encoded.joined(separator: ","))]"
    }

    private func localPathForRAndDArtifact(rootURL: URL, artifact: RAndDArtifact) -> URL {
        let destinationFolder = rootURL.appendingPathComponent(subdirectoryForRAndDArtifact(artifact), isDirectory: true)
        let fileName = "\(sanitizeArtifactPathComponent(artifact.artifactID))\(fileExtensionForArtifact(artifact))"
        return destinationFolder.appendingPathComponent(fileName, isDirectory: false)
    }

    private func mergeRAndDLocalWorkspaceAssets(_ newAssets: [RAndDLocalWorkspaceAsset]) {
        guard !newAssets.isEmpty else { return }
        var merged = Dictionary(uniqueKeysWithValues: rAndDLocalWorkspaceAssets.map { ($0.artifactID, $0) })
        for asset in newAssets {
            merged[asset.artifactID] = asset
        }
        rAndDLocalWorkspaceAssets = merged.values.sorted { lhs, rhs in
            if lhs.title == rhs.title {
                return lhs.artifactID < rhs.artifactID
            }
            return lhs.title < rhs.title
        }
    }

    nonisolated static func isLocalCADExecutableArtifact(artifactType: String, format: String) -> Bool {
        artifactType == "cad_source" && format.lowercased() == "py"
    }

    private func localCADSourceArtifacts(in artifacts: [RAndDArtifact]) -> [RAndDArtifact] {
        artifacts.filter { artifact in
            Self.isLocalCADExecutableArtifact(
                artifactType: artifact.artifactType,
                format: artifact.format
            )
        }
    }

    private func matchingExportManifest(
        for cadArtifact: RAndDArtifact,
        in artifacts: [RAndDArtifact]
    ) -> RAndDArtifact? {
        artifacts.first { artifact in
            artifact.partID == cadArtifact.partID
                && artifact.format.lowercased() == "step.manifest"
        }
    }

    private func exportRequests(from manifestArtifact: RAndDArtifact?) -> [String] {
        guard let manifestArtifact,
              let data = manifestArtifact.content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exports = object["recommended_exports"] as? [String]
        else {
            return []
        }
        return exports.map { $0.uppercased() }
    }

    private func executionRecord(for artifactID: String) -> RAndDLocalExecutionRecord? {
        rAndDLocalExecutionRecords
            .filter { $0.artifactID == artifactID }
            .sorted { $0.executedAt > $1.executedAt }
            .first
    }

    private func upsertRAndDLocalExecutionRecord(_ record: RAndDLocalExecutionRecord) {
        if let index = rAndDLocalExecutionRecords.firstIndex(where: { $0.executionID == record.executionID }) {
            rAndDLocalExecutionRecords[index] = record
        } else if let index = rAndDLocalExecutionRecords.firstIndex(where: { $0.artifactID == record.artifactID && $0.tool == record.tool }) {
            rAndDLocalExecutionRecords[index] = record
        } else {
            rAndDLocalExecutionRecords.insert(record, at: 0)
        }
        rAndDLocalExecutionRecords.sort { $0.executedAt > $1.executedAt }
        if rAndDLocalExecutionRecords.count > 48 {
            rAndDLocalExecutionRecords = Array(rAndDLocalExecutionRecords.prefix(48))
        }
    }

    private func shouldSkipLocalCADExecution(
        for artifact: RAndDArtifact,
        contentHash: String
    ) -> Bool {
        guard let record = executionRecord(for: artifact.artifactID),
              record.status == "success",
              record.contentHash == contentHash,
              !record.outputPaths.isEmpty
        else {
            return false
        }
        return record.outputPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    private func localCADExecutionRootURL(rootURL: URL, artifact: RAndDArtifact) -> URL {
        rootURL
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent("freecad", isDirectory: true)
            .appendingPathComponent(sanitizeArtifactPathComponent(artifact.artifactID), isDirectory: true)
    }

    private func localCADExecutionLogURL(rootURL: URL, artifact: RAndDArtifact) -> URL {
        rootURL
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("\(sanitizeArtifactPathComponent(artifact.artifactID))-freecad.log", isDirectory: false)
    }

    private func localCADGeneratedAssets(
        artifact: RAndDArtifact,
        outputPaths: [String]
    ) -> [RAndDLocalWorkspaceAsset] {
        outputPaths.map { path in
            let fileURL = URL(fileURLWithPath: path)
            return RAndDLocalWorkspaceAsset(
                artifactID: "\(artifact.artifactID):\(fileURL.lastPathComponent)",
                title: "\(artifact.title) output",
                artifactType: "generated_cad_output",
                format: fileURL.pathExtension.lowercased(),
                localPath: path,
                preview: fileURL.lastPathComponent
            )
        }
    }

    private func contentHash(for artifact: RAndDArtifact) -> String {
        let digest = SHA256.hash(data: Data(artifact.content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func localCADExecutionSummary(trigger: String, executed: Int, skipped: Int, failures: Int) -> String {
        if executed == 0, skipped > 0, failures == 0 {
            return "Local CAD execution up to date (\(trigger)). Reused \(skipped) artifact run(s)."
        }
        return "Local CAD execution \(trigger): \(executed) ran, \(skipped) skipped, \(failures) failed."
    }

    private func maybeExecuteLocalRAndDArtifacts(
        job: RAndDJobResponse,
        artifacts: [RAndDArtifact],
        trigger: String,
        force: Bool = false
    ) async {
        guard ["mechanical", "mechanical_cad"].contains(job.designDomain) else {
            rAndDLocalExecutionStatusLine = "Local CAD execution is only enabled for mechanical jobs."
            return
        }
        guard mechanicalExecutorHealthy else {
            rAndDLocalExecutionStatusLine = "Local CAD execution is waiting for healthy FreeCAD, FreeCADCmd, and CalculiX tools."
            return
        }
        guard let rootURL = rAndDWorkspaceRootURL(jobID: job.jobID) else {
            rAndDLocalExecutionStatusLine = "Local CAD execution could not resolve the job workspace."
            return
        }

        let cadArtifacts = localCADSourceArtifacts(in: artifacts)
        guard !cadArtifacts.isEmpty else {
            rAndDLocalExecutionStatusLine = "No executable FreeCAD source artifacts are available yet."
            return
        }

        rAndDLocalExecutionIsRunning = true
        defer { rAndDLocalExecutionIsRunning = false }

        var executedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for artifact in cadArtifacts {
            let hash = contentHash(for: artifact)
            if !force, shouldSkipLocalCADExecution(for: artifact, contentHash: hash) {
                skippedCount += 1
                continue
            }

            let result = await executeLocalFreeCADArtifact(
                job: job,
                artifact: artifact,
                manifestArtifact: matchingExportManifest(for: artifact, in: artifacts),
                rootURL: rootURL,
                contentHash: hash
            )
            upsertRAndDLocalExecutionRecord(result.record)
            if result.record.status == "success" {
                executedCount += 1
                mergeRAndDLocalWorkspaceAssets(result.generatedAssets)
            } else {
                failedCount += 1
                appendOutput("Local CAD execution failed for \(artifact.title): \(result.record.detail)")
            }
        }

        rAndDLocalExecutionStatusLine = localCADExecutionSummary(
            trigger: trigger,
            executed: executedCount,
            skipped: skippedCount,
            failures: failedCount
        )
        appendOutput(rAndDLocalExecutionStatusLine)
    }

    private func executeLocalFreeCADArtifact(
        job: RAndDJobResponse,
        artifact: RAndDArtifact,
        manifestArtifact: RAndDArtifact?,
        rootURL: URL,
        contentHash: String
    ) async -> (record: RAndDLocalExecutionRecord, generatedAssets: [RAndDLocalWorkspaceAsset]) {
        let fileManager = FileManager.default
        let sourceURL = localPathForRAndDArtifact(rootURL: rootURL, artifact: artifact)
        let execRoot = localCADExecutionRootURL(rootURL: rootURL, artifact: artifact)
        let logURL = localCADExecutionLogURL(rootURL: rootURL, artifact: artifact)

        do {
            try fileManager.createDirectory(at: execRoot, withIntermediateDirectories: true)
            if let children = try? fileManager.contentsOfDirectory(at: execRoot, includingPropertiesForKeys: nil) {
                for child in children {
                    try? fileManager.removeItem(at: child)
                }
            }
        } catch {
            let record = RAndDLocalExecutionRecord(
                executionID: "\(artifact.artifactID)-freecad",
                artifactID: artifact.artifactID,
                tool: "FreeCADCmd",
                contentHash: contentHash,
                status: "failed",
                detail: "Failed to prepare execution folder: \(error.localizedDescription)",
                outputPaths: [],
                executedAt: Date()
            )
            return (record, [])
        }

        let runResult = await Self.executeToolCommand(
            binaryPath: freeCADCmdPath,
            arguments: [sourceURL.path],
            currentDirectory: execRoot.path
        )

        var logBody = "Artifact: \(artifact.artifactID)\nJob: \(job.jobID)\nTool: FreeCADCmd\nStatus: \(runResult.status)\n\n\(runResult.output)"
        var outputPaths = Self.generatedCADOutputPaths(in: execRoot)
        var exportNotes: [String] = []

        if runResult.status == 0, let fcstdURL = outputPaths.first(where: { $0.lowercased().hasSuffix(".fcstd") }).map(URL.init(fileURLWithPath:)) {
            let exportResult = await executeManifestDrivenNeutralExports(
                fcstdURL: fcstdURL,
                manifestArtifact: manifestArtifact,
                execRoot: execRoot
            )
            exportNotes.append(exportResult.note)
            outputPaths = Array(Set(outputPaths + exportResult.outputPaths)).sorted()
            if !exportResult.log.isEmpty {
                logBody += "\n\nNeutral export log:\n\(exportResult.log)"
            }
        }

        try? logBody.write(to: logURL, atomically: true, encoding: .utf8)

        let finalStatus = runResult.status == 0 && !outputPaths.isEmpty ? "success" : "failed"
        let detail: String
        if finalStatus == "success" {
            let extra = exportNotes.filter { !$0.isEmpty }.joined(separator: " · ")
            detail = "Generated \(outputPaths.count) local file(s)\(extra.isEmpty ? "" : " · \(extra)")"
        } else {
            detail = Self.trimForDisplay(runResult.output, maxChars: 420)
        }

        let generatedAssets = localCADGeneratedAssets(
            artifact: artifact,
            outputPaths: outputPaths + [logURL.path]
        )
        let record = RAndDLocalExecutionRecord(
            executionID: "\(artifact.artifactID)-freecad",
            artifactID: artifact.artifactID,
            tool: "FreeCADCmd",
            contentHash: contentHash,
            status: finalStatus,
            detail: detail,
            outputPaths: outputPaths,
            executedAt: Date()
        )
        return (record, generatedAssets)
    }

    private func executeManifestDrivenNeutralExports(
        fcstdURL: URL,
        manifestArtifact: RAndDArtifact?,
        execRoot: URL
    ) async -> (outputPaths: [String], note: String, log: String) {
        let requested = exportRequests(from: manifestArtifact)
        guard !requested.isEmpty else {
            return ([], "", "")
        }
        let partID = manifestArtifact?.partID ?? fcstdURL.deletingPathExtension().lastPathComponent
        let scriptURL = execRoot.appendingPathComponent("neutral-export.py", isDirectory: false)
        let stepURL = execRoot.appendingPathComponent("\(partID).step", isDirectory: false)
        let stlURL = execRoot.appendingPathComponent("\(partID).stl", isDirectory: false)
        let wantsSTEP = requested.contains("STEP")
        let wantsSTL = requested.contains("STL")
        let wantsPDF = requested.contains("PDF_DRAWING")
        let script = """
        import FreeCAD as App
        import Part
        import Mesh

        doc = App.openDocument(r"\(fcstdURL.path)")
        doc.recompute()
        exportables = [obj for obj in doc.Objects if hasattr(obj, "Shape") and not obj.Shape.isNull()]
        if not exportables:
            raise RuntimeError("No exportable shape objects found in \(fcstdURL.lastPathComponent)")
        if \(wantsSTEP ? "True" : "False"):
            Part.export(exportables, r"\(stepURL.path)")
            print("exported \(stepURL.lastPathComponent)")
        if \(wantsSTL ? "True" : "False"):
            Mesh.export(exportables, r"\(stlURL.path)")
            print("exported \(stlURL.lastPathComponent)")
        """
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return ([], "Failed to write neutral export script: \(error.localizedDescription)", "")
        }

        let result = await Self.executeToolCommand(
            binaryPath: freeCADCmdPath,
            arguments: [scriptURL.path],
            currentDirectory: execRoot.path
        )

        var outputs: [String] = []
        if wantsSTEP, FileManager.default.fileExists(atPath: stepURL.path) {
            outputs.append(stepURL.path)
        }
        if wantsSTL, FileManager.default.fileExists(atPath: stlURL.path) {
            outputs.append(stlURL.path)
        }
        var notes: [String] = []
        if !outputs.isEmpty {
            notes.append("neutral exports: \(outputs.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))")
        }
        if wantsPDF {
            notes.append("PDF drawing export still pending")
        }
        if result.status != 0, outputs.isEmpty {
            notes.append("neutral export script failed")
        }
        return (outputs, notes.joined(separator: " · "), result.output)
    }

    nonisolated private static func generatedCADOutputPaths(in directory: URL) -> [String] {
        let allowedExtensions = Set(["fcstd", "step", "stl", "obj", "brep", "log"])
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var outputs: [String] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? true else { continue }
            outputs.append(fileURL.path)
        }
        return outputs.sorted()
    }

    func guidedLearningSettingsSnapshot() -> GuidedLearningSettingsSnapshot {
        GuidedLearningSettingsSnapshot(
            kiwixBaseURL: guidedLearningKiwixBaseURLRawValue,
            ollamaEndpoint: guidedLearningOllamaEndpointRawValue,
            ollamaModel: guidedLearningOllamaModelName
        )
    }

    var cadToolsConfigured: Bool {
        !freeCADPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !freeCADCmdPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !kiCadCLIPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !calculiXPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var cadToolsHealthy: Bool {
        freeCADHealthLine.localizedCaseInsensitiveContains("ready")
            && freeCADCmdHealthLine.localizedCaseInsensitiveContains("ready")
            && kiCadCLIHealthLine.localizedCaseInsensitiveContains("ready")
            && calculiXHealthLine.localizedCaseInsensitiveContains("ready")
    }

    var mechanicalExecutorHealthy: Bool {
        freeCADHealthLine.localizedCaseInsensitiveContains("ready")
            && freeCADCmdHealthLine.localizedCaseInsensitiveContains("ready")
            && calculiXHealthLine.localizedCaseInsensitiveContains("ready")
    }

    func cadToolsSettingsSnapshot() -> CADToolsSettingsSnapshot {
        CADToolsSettingsSnapshot(
            freeCADPath: freeCADPath,
            freeCADCmdPath: freeCADCmdPath,
            kiCadCLIPath: kiCadCLIPath,
            calculiXPath: calculiXPath
        )
    }

    func revealCADToolsSetupWizard() {
        showCADToolsSetupWizard = true
    }

    func dismissCADToolsSetupWizard() {
        showCADToolsSetupWizard = false
    }

    func saveCADToolsSettings(
        freeCADPath: String,
        freeCADCmdPath: String,
        kiCadCLIPath: String,
        calculiXPath: String
    ) {
        let defaults = UserDefaults.standard
        let cleanFreeCAD = Self.normalizeCADExecutablePath(freeCADPath)
        let cleanFreeCADCmd = Self.normalizeCADExecutablePath(freeCADCmdPath)
        let cleanKiCadCLI = Self.normalizeCADExecutablePath(kiCadCLIPath)
        let cleanCalculiX = Self.normalizeCADExecutablePath(calculiXPath)

        self.freeCADPath = cleanFreeCAD
        self.freeCADCmdPath = cleanFreeCADCmd
        self.kiCadCLIPath = cleanKiCadCLI
        self.calculiXPath = cleanCalculiX

        if cleanFreeCAD.isEmpty {
            defaults.removeObject(forKey: CADToolDefaults.freeCADPathKey)
        } else {
            defaults.set(cleanFreeCAD, forKey: CADToolDefaults.freeCADPathKey)
        }
        if cleanFreeCADCmd.isEmpty {
            defaults.removeObject(forKey: CADToolDefaults.freeCADCmdPathKey)
        } else {
            defaults.set(cleanFreeCADCmd, forKey: CADToolDefaults.freeCADCmdPathKey)
        }
        if cleanKiCadCLI.isEmpty {
            defaults.removeObject(forKey: CADToolDefaults.kiCadCLIPathKey)
        } else {
            defaults.set(cleanKiCadCLI, forKey: CADToolDefaults.kiCadCLIPathKey)
        }
        if cleanCalculiX.isEmpty {
            defaults.removeObject(forKey: CADToolDefaults.calculiXPathKey)
        } else {
            defaults.set(cleanCalculiX, forKey: CADToolDefaults.calculiXPathKey)
        }

        updateCADToolsStatusLine()
        appendOutput("CAD tool settings updated.")
    }

    func autoDetectCADTools() async {
        let resolved = await resolvedCADToolsSettings(
            fallback: cadToolsSettingsSnapshot(),
            repairMissingOrInvalidOnly: false
        )
        saveCADToolsSettings(
            freeCADPath: resolved.freeCADPath,
            freeCADCmdPath: resolved.freeCADCmdPath,
            kiCadCLIPath: resolved.kiCadCLIPath,
            calculiXPath: resolved.calculiXPath
        )
        await runCADToolsHealthCheck()
        appendOutput("CAD tool auto-detection complete.")
    }

    func runCADToolsHealthCheck() async {
        cadToolsStatusLine = "Running CAD/EDA tool health checks..."
        freeCADHealthLine = await cadToolHealthLine(
            label: "FreeCAD",
            path: freeCADPath,
            probeArguments: ["--help"]
        )
        freeCADCmdHealthLine = await cadToolHealthLine(
            label: "FreeCADCmd",
            path: freeCADCmdPath,
            probeArguments: ["--help"]
        )
        kiCadCLIHealthLine = await cadToolHealthLine(
            label: "KiCad CLI",
            path: kiCadCLIPath,
            probeArguments: ["--version"]
        )
        calculiXHealthLine = await cadToolHealthLine(
            label: "CalculiX",
            path: calculiXPath,
            probeArguments: ["-v"]
        )
        updateCADToolsStatusLine()
        appendOutput(cadToolsStatusLine)
    }

    private func restoreCADToolsSettings() {
        let defaults = UserDefaults.standard
        freeCADPath = Self.normalizeCADExecutablePath(defaults.string(forKey: CADToolDefaults.freeCADPathKey) ?? "")
        freeCADCmdPath = Self.normalizeCADExecutablePath(defaults.string(forKey: CADToolDefaults.freeCADCmdPathKey) ?? "")
        kiCadCLIPath = Self.normalizeCADExecutablePath(defaults.string(forKey: CADToolDefaults.kiCadCLIPathKey) ?? "")
        calculiXPath = Self.normalizeCADExecutablePath(defaults.string(forKey: CADToolDefaults.calculiXPathKey) ?? "")
        updateCADToolsStatusLine()
    }

    private func updateCADToolsStatusLine() {
        if cadToolsHealthy {
            cadToolsStatusLine = "CAD/EDA toolchain ready for FreeCAD, KiCad, and CalculiX-backed execution."
        } else if mechanicalExecutorHealthy {
            cadToolsStatusLine = "Mechanical executor ready. KiCad still needs setup for future PCB/EDA jobs."
        } else if cadToolsConfigured {
            cadToolsStatusLine = "CAD/EDA tool paths saved. Run a health check to verify the executables."
        } else {
            cadToolsStatusLine = "CAD/EDA tools not configured. Use the setup wizard or auto-detect FreeCAD, KiCad, and CalculiX installs."
        }
    }

    nonisolated static func normalizeCADExecutablePath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if standardized.hasSuffix("/FreeCAD.app") {
            return "\(standardized)/Contents/MacOS/FreeCAD"
        }
        if standardized.hasSuffix("/KiCad.app") {
            return "\(standardized)/Contents/MacOS/kicad-cli"
        }
        return standardized
    }

    nonisolated static func deriveFreeCADPaths(from rawPath: String) -> (freeCAD: String?, freeCADCmd: String?) {
        let normalized = normalizeCADExecutablePath(rawPath)
        guard !normalized.isEmpty else { return (nil, nil) }

        let executableName = URL(fileURLWithPath: normalized).lastPathComponent
        let pathComponents = normalized.split(separator: "/")
        guard let appIndex = pathComponents.firstIndex(where: { $0.hasSuffix(".app") }) else {
            switch executableName {
            case "FreeCAD":
                return (normalized, nil)
            case "FreeCADCmd":
                return (nil, normalized)
            default:
                return (nil, nil)
            }
        }

        let appRoot = "/" + pathComponents.prefix(appIndex + 1).joined(separator: "/")
        let freeCADCandidates = [
            "\(appRoot)/Contents/MacOS/FreeCAD",
            "\(appRoot)/Contents/Resources/bin/FreeCAD",
        ]
        let freeCADCmdCandidates = [
            "\(appRoot)/Contents/Resources/bin/FreeCADCmd",
            "\(appRoot)/Contents/MacOS/FreeCADCmd",
        ]
        return (
            firstExecutablePath(in: freeCADCandidates) ?? (executableName == "FreeCAD" ? normalized : nil),
            firstExecutablePath(in: freeCADCmdCandidates) ?? (executableName == "FreeCADCmd" ? normalized : nil)
        )
    }

    nonisolated private static func firstExecutablePath(in candidates: [String]) -> String? {
        for candidate in candidates {
            let normalized = normalizeCADExecutablePath(candidate)
            if FileManager.default.isExecutableFile(atPath: normalized) {
                return normalized
            }
        }
        return nil
    }

    private func defaultCADAutoDetectionCandidates() -> (freeCAD: [String], freeCADCmd: [String], kiCadCLI: [String], calculiX: [String]) {
        (
            freeCAD: [
                freeCADPath,
                freeCADCmdPath,
                "/Applications/FreeCAD.app",
                "/Applications/FreeCAD.app/Contents/MacOS/FreeCAD",
                "/Applications/FreeCAD.app/Contents/Resources/bin/FreeCAD",
                "/opt/homebrew/bin/FreeCAD",
            ],
            freeCADCmd: [
                freeCADCmdPath,
                freeCADPath,
                "/Applications/FreeCAD.app/Contents/Resources/bin/FreeCADCmd",
                "/Applications/FreeCAD.app/Contents/MacOS/FreeCADCmd",
                "/opt/homebrew/bin/FreeCADCmd",
            ],
            kiCadCLI: [
                kiCadCLIPath,
                "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
                "/Applications/KiCad.app/Contents/MacOS/kicad-cli",
                "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad",
                "/opt/homebrew/bin/kicad-cli",
            ],
            calculiX: [
                calculiXPath,
                "/opt/homebrew/bin/ccx",
                "/usr/local/bin/ccx",
                "/Applications/CalculiX/ccx",
            ]
        )
    }

    private func resolvedCADToolsSettings(
        fallback: CADToolsSettingsSnapshot,
        repairMissingOrInvalidOnly: Bool
    ) async -> CADToolsSettingsSnapshot {
        let candidates = defaultCADAutoDetectionCandidates()
        var resolvedFreeCAD = Self.firstExecutablePath(in: [fallback.freeCADPath])
        var resolvedFreeCADCmd = Self.firstExecutablePath(in: [fallback.freeCADCmdPath])

        for candidate in candidates.freeCAD + candidates.freeCADCmd {
            let derived = Self.deriveFreeCADPaths(from: candidate)
            if resolvedFreeCAD == nil, let freeCAD = derived.freeCAD, FileManager.default.isExecutableFile(atPath: freeCAD) {
                resolvedFreeCAD = freeCAD
            }
            if resolvedFreeCADCmd == nil, let freeCADCmd = derived.freeCADCmd, FileManager.default.isExecutableFile(atPath: freeCADCmd) {
                resolvedFreeCADCmd = freeCADCmd
            }
            if resolvedFreeCAD != nil, resolvedFreeCADCmd != nil {
                break
            }
        }

        if resolvedFreeCAD == nil {
            resolvedFreeCAD = await firstResolvedCADPath(candidates: candidates.freeCAD, commandName: "FreeCAD")
        }
        if resolvedFreeCADCmd == nil {
            resolvedFreeCADCmd = await firstResolvedCADPath(candidates: candidates.freeCADCmd, commandName: "FreeCADCmd")
        }
        if let freeCAD = resolvedFreeCAD, resolvedFreeCADCmd == nil {
            resolvedFreeCADCmd = Self.deriveFreeCADPaths(from: freeCAD).freeCADCmd
        }
        if let freeCADCmd = resolvedFreeCADCmd, resolvedFreeCAD == nil {
            resolvedFreeCAD = Self.deriveFreeCADPaths(from: freeCADCmd).freeCAD
        }

        let resolvedKiCadCLI = await firstResolvedCADPath(candidates: candidates.kiCadCLI, commandName: "kicad-cli")
        let resolvedCalculiX = await firstResolvedCADPath(candidates: candidates.calculiX, commandName: "ccx")

        return CADToolsSettingsSnapshot(
            freeCADPath: resolvedFreeCAD ?? (repairMissingOrInvalidOnly ? fallback.freeCADPath : ""),
            freeCADCmdPath: resolvedFreeCADCmd ?? (repairMissingOrInvalidOnly ? fallback.freeCADCmdPath : ""),
            kiCadCLIPath: resolvedKiCadCLI ?? (repairMissingOrInvalidOnly ? fallback.kiCadCLIPath : ""),
            calculiXPath: resolvedCalculiX ?? (repairMissingOrInvalidOnly ? fallback.calculiXPath : "")
        )
    }

    private func repairCADToolSettingsIfNeeded() async {
        let existing = cadToolsSettingsSnapshot()
        let resolved = await resolvedCADToolsSettings(
            fallback: existing,
            repairMissingOrInvalidOnly: true
        )
        guard resolved != existing else { return }
        saveCADToolsSettings(
            freeCADPath: resolved.freeCADPath,
            freeCADCmdPath: resolved.freeCADCmdPath,
            kiCadCLIPath: resolved.kiCadCLIPath,
            calculiXPath: resolved.calculiXPath
        )
        appendOutput("Repaired CAD tool discovery from local installs.")
    }

    private func firstResolvedCADPath(candidates: [String], commandName: String) async -> String? {
        for candidate in candidates {
            let resolved = Self.normalizeCADExecutablePath(candidate)
            if FileManager.default.isExecutableFile(atPath: resolved) {
                return resolved
            }
        }
        let which = await Self.executeShellCommand("command -v \(commandName)", workingDirectory: NSHomeDirectory())
        guard which.status == 0 else { return nil }
        let resolved = Self.normalizeCADExecutablePath(which.output)
        return FileManager.default.isExecutableFile(atPath: resolved) ? resolved : nil
    }

    private func cadToolHealthLine(label: String, path: String, probeArguments: [String]) async -> String {
        let cleanPath = Self.normalizeCADExecutablePath(path)
        guard !cleanPath.isEmpty else { return "\(label) missing path." }
        guard FileManager.default.isExecutableFile(atPath: cleanPath) else {
            return "\(label) path is not executable."
        }
        if label == "FreeCADCmd" {
            let smokeResult = await Self.runFreeCADCmdSmokeTest(binaryPath: cleanPath)
            if smokeResult.success {
                return "FreeCADCmd ready: \(smokeResult.detail)"
            }
            return "FreeCADCmd failed health check: \(smokeResult.detail)"
        }
        let result = await Self.executeToolCommand(binaryPath: cleanPath, arguments: probeArguments)
        if result.status == 0 {
            let firstLine = result.output.split(separator: "\n").first.map(String.init) ?? "command responded"
            return "\(label) ready: \(firstLine)"
        }
        if label == "FreeCAD",
           Self.looksLikeUsableFreeCADProbeOutput(result.output)
        {
            return "FreeCAD ready with optional GUI warning: \(Self.summarizedFreeCADWarning(from: result.output))"
        }
        return "\(label) failed health check: \(result.output)"
    }

    private static func looksLikeUsableFreeCADProbeOutput(_ output: String) -> Bool {
        let lowered = output.lowercased()
        return lowered.contains("usage: freecad")
            || lowered.contains("freecad [options]")
            || lowered.contains("3dconnexionnavlib")
    }

    private static func summarizedFreeCADWarning(from output: String) -> String {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let driverLine = lines.first(where: { $0.localizedCaseInsensitiveContains("3DconnexionNavlib") }) {
            return trimForDisplay(driverLine, maxChars: 220)
        }
        return lines.first.map { trimForDisplay($0, maxChars: 220) } ?? "FreeCAD responded to --help with a non-fatal warning."
    }

    nonisolated private static func runFreeCADCmdSmokeTest(binaryPath: String) async -> (success: Bool, detail: String) {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let smokeRoot = fileManager.temporaryDirectory
                .appendingPathComponent("atlas-freecad-smoke-\(UUID().uuidString)", isDirectory: true)
            let outputURL = smokeRoot.appendingPathComponent("smoke.FCStd")
            let scriptURL = smokeRoot.appendingPathComponent("smoke.py")
            do {
                try fileManager.createDirectory(at: smokeRoot, withIntermediateDirectories: true)
                let script = """
                import FreeCAD as App
                import Part

                doc = App.newDocument("BlackHavenSmoke")
                box = doc.addObject("Part::Box", "SmokeBox")
                box.Length = 20
                box.Width = 10
                box.Height = 5
                doc.recompute()
                doc.saveAs(r"\(outputURL.path)")
                print("generated smoke artifact at \(outputURL.lastPathComponent)")
                """
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                defer { try? fileManager.removeItem(at: smokeRoot) }

                let result = await executeToolCommand(
                    binaryPath: binaryPath,
                    arguments: [scriptURL.path],
                    currentDirectory: smokeRoot.path
                )
                guard result.status == 0 else {
                    return (false, trimForDisplay(result.output, maxChars: 600))
                }
                guard fileManager.fileExists(atPath: outputURL.path),
                      let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path),
                      let fileSize = attributes[.size] as? NSNumber,
                      fileSize.intValue > 0
                else {
                    return (false, "Smoke script ran but did not produce an FCStd artifact.")
                }
                return (true, "generated \(outputURL.lastPathComponent) (\(fileSize.intValue) bytes)")
            } catch {
                try? fileManager.removeItem(at: smokeRoot)
                return (false, "Failed to prepare FreeCADCmd smoke test: \(error.localizedDescription)")
            }
        }.value
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
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? ownerAccountLabel)
                appendOutput("Native Apple sign-in synced with API.")
            } catch {
                // Keep sign-in local-first so user can still use the app even if API sync fails.
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? ownerAccountLabel)
                appendOutput("Apple sign-in completed locally. API sync pending.")
            }

        case let .failure(error):
            appendOutput("Apple sign-in cancelled/failed: \(error.localizedDescription)")
        }
    }

    func signInWithGooglePlaceholder() {
        markSignedIn(provider: .google, accountName: ownerAccountLabel)
        appendOutput("Google sign-in session created locally. Start Google OAuth web flow to sync with backend session.")
    }

    func signInWithPasswordless() {
        markSignedIn(provider: .passkey, accountName: ownerAccountLabel)
        appendOutput("Passwordless sign-in active. Device-secure flow enabled.")
    }

    func signUpWithPasswordless() {
        markSignedIn(provider: .passkey, accountName: ownerAccountLabel)
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
        guard visibleWorkspaceLanes().contains(lane) else { return }
        activeWorkspaceLane = lane
        ensureWorkspaceSessionsSeeded()
        persistStateToDisk()
        Task { await refreshWorkspaceModelBrief() }
    }

    func activeSessionID(for lane: WorkspaceLane) -> String? {
        activeWorkspaceSessionByLane[lane]
    }

    func visibleWorkspaceLanes() -> [WorkspaceLane] {
        WorkspaceLane.allCases.filter { lane in
            lane != .mobileLivingInfrastructure || mliStudioVisible
        }
    }

    func bundledReferenceDocuments() -> [BundledReferenceDocument] {
        [
            BundledReferenceDocument(
                id: "mli-recirculating-showers",
                title: "Recirculating Showers for Vans",
                fileName: "Conversation with ChatGPT_ Recirculating Showers for Vans.pdf",
                audience: "MLI Studio"
            ),
            BundledReferenceDocument(
                id: "wealth-israeli-regulations",
                title: "Israeli Business Regulations Update",
                fileName: "Israeli Business Regulations Update Search-2.pdf",
                audience: "Command + Wealth"
            ),
        ]
    }

    func bundledReferenceDocumentURL(fileName: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: fileName, withExtension: nil) {
            return bundled
        }
        let devURL = URL(fileURLWithPath: "/Users/avrohom/Downloads/BlackHaven/macos-app/AtlasMasaMacOS/ReferenceLibrary/\(fileName)")
        return FileManager.default.fileExists(atPath: devURL.path) ? devURL : nil
    }

    func setMLIStudioVisible(_ visible: Bool) {
        guard mliStudioVisible != visible else { return }
        mliStudioVisible = visible
        if !visible, activeWorkspaceLane == .mobileLivingInfrastructure {
            activeWorkspaceLane = visibleWorkspaceLanes().first ?? .mobilityOps
        }
        persistStateToDisk()
    }

    func contextProfile(
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil
    ) -> AtlasContextProfile {
        if let exact = contextProfiles.first(where: { $0.surface == surface && $0.workspaceLane == workspaceLane }) {
            return exact
        }
        if surface == .workspace, let workspaceLane,
           let generic = contextProfiles.first(where: { $0.surface == .workspace && $0.workspaceLane == nil })
        {
            var inherited = generic
            inherited = AtlasContextProfile(
                id: AtlasContextProfile.makeDefault(surface: surface, workspaceLane: workspaceLane).id,
                surface: surface,
                workspaceLaneRawValue: workspaceLane.rawValue,
                customSystemPrompt: inherited.customSystemPrompt,
                includeSurveyAnswers: inherited.includeSurveyAnswers,
                includeNotes: inherited.includeNotes,
                includeWorkspaceMemory: inherited.includeWorkspaceMemory,
                includeKnowledgeFiles: inherited.includeKnowledgeFiles,
                includeAccountUsagePatterns: inherited.includeAccountUsagePatterns,
                includeRecentUsageTrends: inherited.includeRecentUsageTrends,
                enabledKnowledgeFileIDs: inherited.enabledKnowledgeFileIDs
            )
            return inherited
        }
        var fallback = AtlasContextProfile.makeDefault(surface: surface, workspaceLane: workspaceLane)
        fallback.enabledKnowledgeFileIDs = knowledgeFiles.map(\.id)
        return fallback
    }

    func updateContextProfile(
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil,
        mutate: (inout AtlasContextProfile) -> Void
    ) {
        let base = contextProfile(for: surface, workspaceLane: workspaceLane)
        var updated = base
        mutate(&updated)
        if let index = contextProfiles.firstIndex(where: { $0.id == updated.id }) {
            contextProfiles[index] = updated
        } else {
            contextProfiles.append(updated)
        }
        persistStateToDisk()
    }

    func setCustomSystemPrompt(
        _ prompt: String,
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil
    ) {
        updateContextProfile(for: surface, workspaceLane: workspaceLane) { profile in
            profile.customSystemPrompt = sanitizeModelInput(prompt, maxLength: 1_400)
        }
    }

    func setContextProfileFlag(
        _ keyPath: WritableKeyPath<AtlasContextProfile, Bool>,
        to value: Bool,
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil
    ) {
        updateContextProfile(for: surface, workspaceLane: workspaceLane) { profile in
            profile[keyPath: keyPath] = value
        }
    }

    func setKnowledgeFile(
        _ fileID: String,
        enabled: Bool,
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil
    ) {
        let cleanID = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }
        updateContextProfile(for: surface, workspaceLane: workspaceLane) { profile in
            var enabledIDs = Set(profile.enabledKnowledgeFileIDs)
            if enabled {
                enabledIDs.insert(cleanID)
            } else {
                enabledIDs.remove(cleanID)
            }
            profile.enabledKnowledgeFileIDs = Array(enabledIDs).sorted()
        }
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
        case .mobileLivingInfrastructure:
            return "MLI"
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
        case .mobileLivingInfrastructure:
            if let shower = normalizeWorkspaceNameFragment("recirculating shower + van systems", maxWords: 5, maxLength: 34) {
                return shower
            }
            return "mobile living systems"
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
        case .mobileLivingInfrastructure:
            candidateKeys = ["drive_now", "travel_state_wanted", "annual_distance_km", "public_transport_usage"]
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
        refreshNextLayerExperience()
        if feedbackOfferEnabled && (checkInMood.lowercased().contains("stressed") || checkInEnergy <= 2 || checkInBlockers.count > 20) {
            appendOutput("Detected friction signal. Offer anonymized product feedback report to team.")
        }
        if allowsAutomaticRuntimeWork {
            Task { await submitExecutionCheckInIfPossible() }
            Task {
                await refreshCommandModelBrief()
                await refreshWorkspaceModelBrief()
                await refreshFeed()
            }
        }
        persistStateToDisk()
    }

    func refreshNextLayerExperience() {
        let snapshot = buildOperatorStateSnapshot()
        operatorStateSnapshot = snapshot
        currentSupportRecommendation = buildSupportRecommendation(from: snapshot)
        currentActivitySuggestion = buildActivitySuggestion(from: snapshot)
        currentItineraryPlan = buildItineraryPlan(from: snapshot)
        activeChecklistPlan = buildChecklistPlan(from: snapshot)
        persistStateToDisk()
    }

    func generateChecklistFromCurrentContext() {
        let snapshot = operatorStateSnapshot ?? buildOperatorStateSnapshot()
        activeChecklistPlan = buildChecklistPlan(from: snapshot)
        operatorStateSnapshot = snapshot
        appendOutput("Generated a local-first checklist from the current execution context.")
        persistStateToDisk()
    }

    func generateActivitySuggestion() {
        let snapshot = operatorStateSnapshot ?? buildOperatorStateSnapshot()
        currentActivitySuggestion = buildActivitySuggestion(from: snapshot)
        operatorStateSnapshot = snapshot
        appendOutput("Generated a local activity suggestion from your current state.")
        persistStateToDisk()
    }

    func generateItineraryPlan() {
        let snapshot = operatorStateSnapshot ?? buildOperatorStateSnapshot()
        currentItineraryPlan = buildItineraryPlan(from: snapshot)
        operatorStateSnapshot = snapshot
        appendOutput("Generated a local itinerary plan from your current goals and state.")
        persistStateToDisk()
    }

    func refreshSupportRecommendation() {
        let snapshot = operatorStateSnapshot ?? buildOperatorStateSnapshot()
        currentSupportRecommendation = buildSupportRecommendation(from: snapshot)
        operatorStateSnapshot = snapshot
        appendOutput("Refreshed the support recommendation for the current operator state.")
        persistStateToDisk()
    }

    func toggleChecklistStep(_ stepID: String) {
        guard var plan = activeChecklistPlan else { return }
        guard let index = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        plan.steps[index].isCompleted.toggle()
        activeChecklistPlan = plan
        appendOutput(plan.steps[index].isCompleted ? "Checklist step completed." : "Checklist step reopened.")
        persistStateToDisk()
    }

    func updateChecklistStepNotes(_ stepID: String, notes: String) {
        guard var plan = activeChecklistPlan else { return }
        guard let index = plan.steps.firstIndex(where: { $0.id == stepID }) else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.steps[index].notes = trimmed.isEmpty ? nil : trimmed
        activeChecklistPlan = plan
        persistStateToDisk()
    }

    private func buildOperatorStateSnapshot() -> OperatorStateSnapshot {
        let blocker = checkInBlockers.trimmingCharacters(in: .whitespacesAndNewlines)
        let mood = checkInMood.trimmingCharacters(in: .whitespacesAndNewlines)
        let daily = dailyPriority.trimmingCharacters(in: .whitespacesAndNewlines)
        let continuityRisk = natureRiskScore >= natureElevatedThreshold
            || containsAny(blocker, ["outage", "internet", "offline", "power", "router", "continuity"])

        let mode: OperatorStateSnapshot.ExecutionMode
        if continuityRisk {
            mode = .continuityRiskMode
        } else if checkInEnergy <= 2 || containsAny(mood, ["stressed", "anxious", "burnout", "overloaded", "recover"]) {
            mode = .lowEnergyMode
        } else if !blocker.isEmpty && (blocker.count > 48 || containsAny(blocker, ["stuck", "blocked", "unclear", "friction", "delay"])) {
            mode = .highFrictionStall
        } else if checkInEnergy >= 4 {
            mode = .deepWorkWindow
        } else {
            mode = .shortIdleWindow
        }

        let nextAction = executionActions.first?.details.trimmedNil()
            ?? (!daily.isEmpty ? daily : "Capture one decisive next action and execute it in the next 25 minutes.")

        let summary: String
        let rationale: String
        switch mode {
        case .continuityRiskMode:
            summary = "Infrastructure risk is elevated, so BlackHaven is routing for continuity first."
            rationale = "Local-first execution matters most when power, internet, or environmental conditions are less reliable."
        case .lowEnergyMode:
            summary = "Energy is low enough that the system should protect recovery-safe execution."
            rationale = "The app should lower cognitive overhead instead of forcing a deep-work plan that will likely fail."
        case .highFrictionStall:
            summary = "You have enough friction signals that environment prep and one-step routing beat brute force."
            rationale = "When blockers are sticky, the best move is usually to shrink the scope and clear the first hard edge."
        case .deepWorkWindow:
            summary = "Energy is strong enough to protect a heavier focus block."
            rationale = "This is the right time for coding, strategy, long-form drafting, and other compounding work."
        case .shortIdleWindow:
            summary = "The system is routing for a short useful move instead of a large orchestration block."
            rationale = "When energy and time are moderate, momentum matters more than perfect planning."
        }

        return OperatorStateSnapshot(
            id: "operator-state",
            mode: mode,
            summary: summary,
            nextAction: nextAction,
            rationale: rationale,
            continuityRiskActive: continuityRisk,
            energyLevel: max(1, min(5, checkInEnergy)),
            mood: mood.isEmpty ? "Focused" : mood,
            blockerSummary: blocker.isEmpty ? nil : sanitizeWorkspaceMemoryValue(blocker, maxLength: 180),
            generatedAt: currentNextLayerTimestamp()
        )
    }

    private func buildSupportRecommendation(from snapshot: OperatorStateSnapshot) -> SupportRecommendation {
        let (title, summary, prompt): (String, String, String?)
        switch snapshot.mode {
        case .continuityRiskMode:
            title = "Stabilize continuity before expanding scope"
            summary = "Check desktop power, local networking, and offline-critical files first. Keep the next work block local, simple, and resilient."
            prompt = "If you need a body-double, send: \"I am protecting continuity right now. Can you stay nearby for 20 minutes while I secure power, network, and one core task?\""
        case .lowEnergyMode:
            title = "Reduce friction and protect recovery-safe output"
            summary = "Use one-task-only mode. Consider water, a shower, comfortable clothes, a desk reset, or a short walk before asking for harder output."
            prompt = "If helpful, text someone: \"Can you sit with me for 20 minutes while I finish one small task and reset my environment?\""
        case .highFrictionStall:
            title = "Shrink the problem until motion returns"
            summary = "Clear the desk, write the blocker in one sentence, and route only the first unblock step. Do not expand the plan until momentum is back."
            prompt = "If useful, send: \"I am stuck on a single blocker. Can I talk it through with you for 10 minutes so I can choose the first next step?\""
        case .deepWorkWindow:
            title = "Protect the high-energy window"
            summary = "Silence distractions, keep one tab set, and give the next heavy task a clean uninterrupted block before context-switching."
            prompt = nil
        case .shortIdleWindow:
            title = "Convert the open window into a completed move"
            summary = "Choose one sharp action that fits the next 5-20 minutes: approve, send, summarize, or prepare the next deep-work block."
            prompt = nil
        }

        return SupportRecommendation(
            id: "support-recommendation",
            title: title,
            summary: summary,
            bodyDoublingPrompt: prompt,
            generatedAt: currentNextLayerTimestamp()
        )
    }

    private func buildActivitySuggestion(from snapshot: OperatorStateSnapshot) -> ActivitySuggestion {
        let intent = combinedIntentText().lowercased()
        let hasTravel = hasAnyTravelIntent() || containsAny(intent, ["travel", "trip", "flight", "route"])

        let title: String
        let summary: String
        let duration: String
        let reason: String

        switch snapshot.mode {
        case .continuityRiskMode:
            title = "Run a continuity walk-through"
            summary = "Verify the desktop node, power path, router, and local files, then capture one offline-safe action."
            duration = "15-20 min"
            reason = "Continuity risk is more important than variety when infrastructure is unstable."
        case .lowEnergyMode:
            title = "Choose a recovery-safe reset block"
            summary = "Take a short walk, hydrate, clear the desk, and then do a lightweight admin or summary pass."
            duration = "20-30 min"
            reason = "Low-energy routing should preserve progress without pretending this is a peak-performance block."
        case .highFrictionStall:
            title = "Switch to a blocker-clearing micro session"
            summary = "List the blocker, open the one document or file that matters, and resolve only the first dependency."
            duration = "15 min"
            reason = "High friction calls for simplification, not more scope."
        case .deepWorkWindow:
            title = hasTravel ? "Protect a focused travel-planning sprint" : "Protect a deep-work sprint"
            summary = hasTravel
                ? "Use the next strong block to finalize travel requirements, logistics, and the highest-value work deliverable."
                : "Turn this window into a serious build, drafting, or planning session before lower-value admin."
            duration = "60-90 min"
            reason = "High energy is best spent on compounding work."
        case .shortIdleWindow:
            title = "Complete one sharp administrative win"
            summary = "Send the follow-up, approve the change, or queue the next prompt so the next heavy block starts clean."
            duration = "5-15 min"
            reason = "A short window should end with something actually completed."
        }

        return ActivitySuggestion(
            id: "activity-suggestion",
            title: title,
            summary: summary,
            durationLabel: duration,
            reason: reason,
            generatedAt: currentNextLayerTimestamp()
        )
    }

    private func buildItineraryPlan(from snapshot: OperatorStateSnapshot) -> ItineraryPlan {
        let hasTravel = hasAnyTravelIntent()
        let daily = dailyPriority.trimmedNil() ?? "Define one non-negotiable action for today."
        let blocker = checkInBlockers.trimmedNil() ?? "No blocker captured."
        let kind = hasTravel ? "travel" : "workday"

        let steps: [ItineraryStep]
        if hasTravel {
            let regionSummary = combinedTravelRegions().isEmpty ? "your selected regions" : combinedTravelRegions().joined(separator: ", ")
            steps = [
                ItineraryStep(id: "itinerary-1", timeLabel: "Now", title: "Stabilize operator state", summary: currentSupportRecommendation?.summary ?? "Prepare your environment before making travel moves."),
                ItineraryStep(id: "itinerary-2", timeLabel: "Next", title: "Lock travel constraints", summary: "Confirm dates, route, budget, and equipment requirements for \(regionSummary)."),
                ItineraryStep(id: "itinerary-3", timeLabel: "Later", title: "Protect the main work block", summary: daily),
                ItineraryStep(id: "itinerary-4", timeLabel: "Before close", title: "Capture continuity notes", summary: "Record local files, logistics decisions, and any unresolved travel blockers: \(sanitizeWorkspaceMemoryValue(blocker, maxLength: 120)).")
            ]
        } else {
            steps = [
                ItineraryStep(id: "itinerary-1", timeLabel: "Now", title: "Set the mode", summary: operatorStateSnapshot?.summary ?? snapshot.summary),
                ItineraryStep(id: "itinerary-2", timeLabel: "Block 1", title: "Execute the main priority", summary: daily),
                ItineraryStep(id: "itinerary-3", timeLabel: "Block 2", title: "Handle the current blocker", summary: sanitizeWorkspaceMemoryValue(blocker, maxLength: 140)),
                ItineraryStep(id: "itinerary-4", timeLabel: "Close", title: "Preserve continuity", summary: "Capture notes, update the checklist, and leave the next session with one obvious starting point.")
            ]
        }

        let summary = hasTravel
            ? "A travel-aware itinerary that protects logistics and the highest-value work."
            : "A workday itinerary that matches your current energy and execution mode."

        return ItineraryPlan(
            id: "itinerary-plan",
            title: hasTravel ? "Travel + Work Itinerary" : "Today’s Operating Itinerary",
            summary: summary,
            kind: kind,
            steps: steps,
            generatedAt: currentNextLayerTimestamp()
        )
    }

    private func buildChecklistPlan(from snapshot: OperatorStateSnapshot) -> ChecklistPlan {
        let topActions = executionActions.prefix(3)
        let fileRefs = [codingSelectedFilePath].compactMap { $0?.trimmedNil() }
        let currentWorkspace = workspacePlans.first?.title ?? "Execution stream"
        var steps: [ChecklistStep] = []

        steps.append(
            ChecklistStep(
                id: "checklist-1",
                title: "Clarify the operating target",
                rationale: "A strong checklist starts with the one outcome that matters most right now.",
                instructions: dailyPriority.trimmedNil() ?? "Write one non-negotiable outcome for this session before doing anything else.",
                externalLinks: [],
                fileReferences: fileRefs,
                isCompleted: false,
                notes: nil
            )
        )

        if let blocker = checkInBlockers.trimmedNil() {
            steps.append(
                ChecklistStep(
                    id: "checklist-2",
                    title: "Clear the first blocker",
                    rationale: "Execution stalls when blockers stay vague and unowned.",
                    instructions: sanitizeWorkspaceMemoryValue(blocker, maxLength: 180),
                    externalLinks: [],
                    fileReferences: fileRefs,
                    isCompleted: false,
                    notes: nil
                )
            )
        }

        for (index, action) in topActions.enumerated() {
            steps.append(
                ChecklistStep(
                    id: "checklist-action-\(index)",
                    title: sanitizeWorkspaceMemoryValue(action.title, maxLength: 90),
                    rationale: "This step was promoted from your current execution context.",
                    instructions: sanitizeWorkspaceMemoryValue(action.details, maxLength: 220),
                    externalLinks: linksFromText(action.details),
                    fileReferences: fileRefs,
                    isCompleted: false,
                    notes: nil
                )
            )
        }

        if steps.count < 4 {
            steps.append(
                ChecklistStep(
                    id: "checklist-close",
                    title: "Close the loop",
                    rationale: "A session is more valuable when the next starting point is preserved.",
                    instructions: "Capture what changed, what is still open, and the first move for the next session in \(currentWorkspace).",
                    externalLinks: [],
                    fileReferences: fileRefs,
                    isCompleted: false,
                    notes: nil
                )
            )
        }

        return ChecklistPlan(
            id: "active-checklist-plan",
            title: "Interactive Checklist Hub",
            summary: "Local-first checklist generated from check-in, execution actions, and workspace context.",
            createdFrom: snapshot.mode.title,
            steps: Array(steps.prefix(5)),
            generatedAt: currentNextLayerTimestamp()
        )
    }

    private func currentNextLayerTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func linksFromText(_ text: String) -> [String] {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    func refreshFeed() async {
        guard isExecutionStreamUnlocked else {
            let remaining = surveyAnswersRemainingForExecution
            feedItems = [
                FeedItem(
                    id: "survey-gate-feed",
                    title: "Execution stream locked until adaptive survey depth is complete",
                    summary: "Answer \(remaining) more survey question\(remaining == 1 ? "" : "s") to unlock the execution stream.",
                    whyNow: "BlackHaven needs at least \(surveyAnswersRequiredForExecution) answers before generating AI execution routing.",
                    priority: "High",
                    checklistState: nil
                ),
            ]
            feedInferenceStatus = "Survey depth gate active (\(surveyAnswerCount)/\(surveyAnswersRequiredForExecution))"
            refreshNextLayerExperience()
            return
        }

        if prepaidCreditsActive {
            do {
                let payload = try await api.feedProactive()
                feedItems = payload.items
                feedInferenceStatus = "Cloud proactive feed active"
                appendOutput("Cloud proactive feed refreshed.")
                refreshNextLayerExperience()
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
        refreshNextLayerExperience()
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
        let localOpportunities = buildJobMarketOpportunities()
        var hints = [
            "Local AI adaptive survey active (Qwen 2.5 / DeepSeek R1 routing)",
            "Gym/income cadence enabled",
            "Career/business fit routing enabled",
        ]
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
        await prepareNextAdaptiveSurveyQuestionIfNeeded()
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
        await prepareNextAdaptiveSurveyQuestionIfNeeded()

        applyOptimisticLocalSurveyState(answerLabel: answerLabel)

        // Keep question flow instant; sync with API in the background.
        if allowsAutomaticRuntimeWork {
            surveySyncTask?.cancel()
            surveySyncTask = Task { [weak self] in
                guard let self else { return }
                await self.syncSurveyAnswerInBackground(questionID: questionID, answerValue: answerValue)
            }
        }

        // Rebuild expensive derived state after the UI has advanced to the next question.
        surveyRebuildTask?.cancel()
        surveyRebuildTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.rebuildInsightsAndExecutionPlan()
            self.persistStateToDisk()
        }
    }

    private func applyOptimisticLocalSurveyState(answerLabel: String) {
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

    private func syncSurveyAnswerInBackground(questionID: String, answerValue: String) async {
        do {
            let remote = try await api.submitSurveyAnswer(questionID: questionID, answer: answerValue)
            guard !Task.isCancelled else { return }

            // Keep optimistic progress unless backend reports newer/equal completion.
            if remote.progress.answered >= surveyAnswers.count {
                survey = remote
            }
            if hasLoggedSurveySyncUnavailable {
                appendOutput("Survey sync restored.")
                hasLoggedSurveySyncUnavailable = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            if !hasLoggedSurveySyncUnavailable {
                appendOutput("Survey sync unavailable. Using local flow.")
                hasLoggedSurveySyncUnavailable = true
            }
        }
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
        syncMemoryVault(reason: "note_capture")
        persistStateToDisk()
    }

    private func currentMemoryVaultPolicy() -> MemoryVaultPolicy {
        let hardware = localInferenceHardwareSnapshot()
        let selectedModels = selectedLocalAIInstallOptionIDs.isEmpty
            ? ["qwen2.5:7b"]
            : selectedLocalAIInstallOptionIDs
        let heavyModel = selectedModels.contains { model in
            let normalized = model.lowercased()
            return normalized.contains("14b") || normalized.contains("32b") || normalized.contains("70b")
        }
        let hardwareTier: String
        if hardware.memoryGb >= 32 && hardware.cpuCores >= 10 {
            hardwareTier = "ultra_performance"
        } else if hardware.highPerformance {
            hardwareTier = "high_performance"
        } else {
            hardwareTier = "balanced"
        }

        var contextBudget = hardwareTier == "ultra_performance" ? 16_000 : hardwareTier == "high_performance" ? 10_000 : 6_000
        if hardwareTier != "balanced" && !heavyModel {
            contextBudget += 1_500
        }
        let retrievalDepth = hardwareTier == "ultra_performance" ? 8 : hardwareTier == "high_performance" ? 6 : 4
        let responseBudget = hardwareTier == "ultra_performance" ? 1_600 : hardwareTier == "high_performance" ? 1_200 : 820

        return MemoryVaultPolicy(
            hardwareTier: hardwareTier,
            contextBudgetTokens: contextBudget,
            compactionThresholdTokens: Int(Double(contextBudget) * 0.78),
            retrievalDepth: retrievalDepth,
            responseBudgetTokens: responseBudget,
            archiveSearchMode: "native_encrypted_local_index",
            modelGuidance: heavyModel ? "heavier_local_model" : "balanced_local_model"
        )
    }

    private func memoryVaultOverview() -> String {
        "Raw \(memoryVaultSnapshot.rawRecords.count) · Compacted \(memoryVaultSnapshot.compactedRecords.count) · Artifacts \(memoryVaultSnapshot.artifactRecords.count) · Token pressure \(memoryVaultSnapshot.lastTokenPressure)"
    }

    private func refreshMemoryVaultStatus() {
        let policy = memoryVaultSnapshot.lastPolicy ?? currentMemoryVaultPolicy()
        memoryVaultStatusLine = "Vault mode: \(memoryVaultSnapshot.lastArchiveMode) · last sync \(memoryVaultSnapshot.lastSyncReason) · \(memoryVaultOverview())"
        memoryVaultPolicyLine = "Hardware tier \(policy.hardwareTier) · context \(policy.contextBudgetTokens) · compact at \(policy.compactionThresholdTokens) · retrieval depth \(policy.retrievalDepth) · local-only lossless summary"
    }

    private func loadMemoryVaultFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let url = memoryVaultFileURL() else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let payload: Data
            if let decrypted = try? SecurePersistence.decrypt(
                data,
                context: "memory_vault",
                appNamespace: "AtlasMasaMacOS"
            ) {
                payload = decrypted
            } else {
                payload = data
            }
            memoryVaultSnapshot = try decoder.decode(MemoryVaultSnapshot.self, from: payload)
        } catch {
            memoryVaultSnapshot = MemoryVaultSnapshot()
        }
    }

    private func persistMemoryVaultToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url = memoryVaultFileURL() else { return }
        do {
            memoryVaultSnapshot.lastSavedAt = Date()
            let data = try encoder.encode(memoryVaultSnapshot)
            let encrypted = try SecurePersistence.encrypt(
                data,
                context: "memory_vault",
                appNamespace: "AtlasMasaMacOS"
            )
            let fileManager = FileManager.default
            let directory = url.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let tempURL = url.appendingPathExtension("tmp")
            try encrypted.write(to: tempURL, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            appendOutput("Local memory vault persistence hit a transient issue. In-memory state is still active.")
        }
    }

    private func memoryVaultFileURL() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent("AtlasMasaMacOS", isDirectory: true)
            .appendingPathComponent("Vault", isDirectory: true)
            .appendingPathComponent("atlas_memory_vault_v1.json", isDirectory: false)
    }

    private func syncMemoryVault(reason: String) {
        guard memoryCollectionEnabled else {
            memoryVaultSnapshot = MemoryVaultSnapshot()
            refreshMemoryVaultStatus()
            return
        }

        let policy = currentMemoryVaultPolicy()
        memoryVaultSnapshot.lastPolicy = policy
        memoryVaultSnapshot.lastSyncReason = reason
        memoryVaultSnapshot.schemaVersion = 1

        for note in notes.prefix(48) {
            upsertMemoryVaultRawRecord(
                id: "note:\(note.noteID)",
                sourceType: "note",
                sourceLabel: "macos_note",
                tags: ["notes", "manual_capture"],
                content: "\(note.title): \(note.content)",
                createdAt: note.createdAt
            )
        }

        for item in promptQueue.prefix(120) {
            let body = item.output.map { "\($0.summary) | \($0.nextAction)" } ?? item.prompt
            upsertMemoryVaultRawRecord(
                id: "queue:\(item.id)",
                sourceType: "queue",
                sourceLabel: item.workspaceLane?.rawValue ?? "concierge",
                tags: ["queue", item.status.rawValue.lowercased()],
                content: body,
                createdAt: item.createdAt
            )
            if let output = item.output {
                upsertMemoryVaultArtifact(
                    id: "artifact:\(item.id)",
                    artifactType: "queue_output",
                    title: output.model,
                    detail: "\(output.summary) | Next action: \(output.nextAction)",
                    createdAt: output.generatedAt
                )
            }
        }

        for record in workspaceMemoryRecords.prefix(320) {
            upsertMemoryVaultRawRecord(
                id: "workspace:\(record.key)",
                sourceType: record.source.rawValue,
                sourceLabel: workspaceSignalLabel(for: record.key),
                tags: [record.key, record.sessionID ?? "global"],
                content: record.value,
                createdAt: record.updatedAtUTC
            )
        }

        trimMemoryVaultSnapshot()
        let activeRawChars = memoryVaultSnapshot.rawRecords
            .filter { !$0.deepArchived }
            .reduce(0) { $0 + $1.content.count }
        let compactedChars = memoryVaultSnapshot.compactedRecords.reduce(0) { $0 + $1.summary.count }
        memoryVaultSnapshot.lastTokenPressure = max(1, (activeRawChars + compactedChars) / 4)
        if memoryVaultSnapshot.lastTokenPressure >= policy.compactionThresholdTokens {
            compactMemoryVault(reason: reason)
        }
        refreshMemoryVaultStatus()
        persistMemoryVaultToDisk()
    }

    func compactMemoryVault() {
        compactMemoryVault(reason: "manual_compact_further")
        refreshMemoryVaultStatus()
        persistMemoryVaultToDisk()
        appendOutput("Compacted working memory into a local encrypted summary tier.")
    }

    private func compactMemoryVault(reason: String) {
        let policy = currentMemoryVaultPolicy()
        let activeRaw = memoryVaultSnapshot.rawRecords
            .filter { !$0.deepArchived }
            .sorted { $0.createdAt < $1.createdAt }
        let keepCount = max(10, policy.retrievalDepth * 3)
        let toCompact = Array(activeRaw.dropLast(min(activeRaw.count, keepCount)).prefix(32))
        guard !toCompact.isEmpty else {
            memoryVaultSnapshot.lastCompactionReason = reason
            memoryVaultSnapshot.lastArchiveMode = "no_op"
            memoryVaultSnapshot.lastCompactedAt = Date()
            return
        }

        let grouped = Dictionary(grouping: toCompact, by: \.sourceType)
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let values = Dictionary(grouping: toCompact, by: \.sourceType)[key] else { return nil }
                let details = values
                    .sorted { $0.createdAt > $1.createdAt }
                    .prefix(6)
                    .map { trimMemoryVaultString($0.content, maxLength: 120) }
                    .joined(separator: " | ")
                return "\(key): \(details)"
            }

        memoryVaultSnapshot.compactedRecords.insert(
            MemoryVaultCompactedRecord(
                id: "compact:\(Int(Date().timeIntervalSince1970 * 1000))",
                title: "Compacted \(toCompact.count) raw records",
                summary: trimMemoryVaultString(
                    "Preserved facts, approvals, dependencies, status, file refs, and project commitments from local raw memory. " + grouped.joined(separator: " || "),
                    maxLength: 2_200
                ),
                sourceRecordIDs: toCompact.map(\.id),
                createdAt: Date(),
                triggerReason: reason
            ),
            at: 0
        )

        let compactedIDs = Set(toCompact.map(\.id))
        for idx in memoryVaultSnapshot.rawRecords.indices {
            if compactedIDs.contains(memoryVaultSnapshot.rawRecords[idx].id) {
                memoryVaultSnapshot.rawRecords[idx].deepArchived = true
            }
        }
        memoryVaultSnapshot.lastCompactionReason = reason
        memoryVaultSnapshot.lastArchiveMode = "compacted"
        memoryVaultSnapshot.lastCompactedAt = Date()
        memoryVaultSnapshot.lastTokenPressure = max(0, memoryVaultSnapshot.lastTokenPressure - (policy.compactionThresholdTokens / 4))
        trimMemoryVaultSnapshot()
    }

    func deepArchiveMemoryVault() {
        let candidates = memoryVaultSnapshot.rawRecords
            .enumerated()
            .filter { !$0.element.deepArchived }
            .sorted { $0.element.createdAt < $1.element.createdAt }
            .prefix(24)
        for candidate in candidates {
            memoryVaultSnapshot.rawRecords[candidate.offset].deepArchived = true
        }
        memoryVaultSnapshot.lastArchiveMode = "deep_archive"
        memoryVaultSnapshot.lastCompactionReason = "manual_deep_archive"
        memoryVaultSnapshot.lastCompactedAt = Date()
        refreshMemoryVaultStatus()
        persistMemoryVaultToDisk()
        appendOutput("Moved older raw memory into the deep local archive.")
    }

    func recallMemoryVault() {
        let query = memoryVaultRecallQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            memoryVaultRecallResults = []
            return
        }

        let tokens = query.split(separator: " ").map(String.init)
        let matches = memoryVaultSnapshot.rawRecords
            .map { record -> (MemoryVaultRawRecord, Int) in
                let haystack = "\(record.sourceType) \(record.sourceLabel) \(record.tags.joined(separator: " ")) \(record.content)".lowercased()
                var score = haystack.contains(query) ? 3 : 0
                score += tokens.reduce(0) { partial, token in
                    partial + (token.count > 1 && haystack.contains(token) ? 2 : 0)
                }
                return (record, score)
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.1 > $1.1
            }
            .prefix(max(1, currentMemoryVaultPolicy().retrievalDepth))

        memoryVaultRecallResults = matches.map { record, _ in
            MemoryVaultRecallResult(
                summary: "\(record.sourceType) · \(trimMemoryVaultString(record.content, maxLength: 220))",
                sourceLabel: record.sourceLabel,
                timestamp: Self.shortTimestampFormatter.string(from: record.createdAt),
                matchReason: record.deepArchived ? "deep archive" : "raw archive"
            )
        }
        appendOutput(memoryVaultRecallResults.isEmpty
            ? "No local raw-memory match found for that recall query."
            : "Recalled \(memoryVaultRecallResults.count) raw memory matches from the local encrypted archive.")
    }

    private func upsertMemoryVaultRawRecord(
        id: String,
        sourceType: String,
        sourceLabel: String,
        tags: [String],
        content: String,
        createdAt: Date
    ) {
        let trimmed = trimMemoryVaultString(content, maxLength: 1_800)
        if let index = memoryVaultSnapshot.rawRecords.firstIndex(where: { $0.id == id }) {
            memoryVaultSnapshot.rawRecords[index].sourceType = sourceType
            memoryVaultSnapshot.rawRecords[index].sourceLabel = sourceLabel
            memoryVaultSnapshot.rawRecords[index].tags = Array(Set(tags)).prefix(8).map { $0 }
            memoryVaultSnapshot.rawRecords[index].content = trimmed
            memoryVaultSnapshot.rawRecords[index].createdAt = createdAt
            return
        }
        memoryVaultSnapshot.rawRecords.append(
            MemoryVaultRawRecord(
                id: id,
                sourceType: sourceType,
                sourceLabel: sourceLabel,
                tags: Array(Set(tags)).prefix(8).map { $0 },
                content: trimmed,
                createdAt: createdAt
            )
        )
    }

    private func upsertMemoryVaultArtifact(
        id: String,
        artifactType: String,
        title: String,
        detail: String,
        createdAt: Date
    ) {
        let trimmed = trimMemoryVaultString(detail, maxLength: 1_600)
        if let index = memoryVaultSnapshot.artifactRecords.firstIndex(where: { $0.id == id }) {
            memoryVaultSnapshot.artifactRecords[index].artifactType = artifactType
            memoryVaultSnapshot.artifactRecords[index].title = title
            memoryVaultSnapshot.artifactRecords[index].detail = trimmed
            memoryVaultSnapshot.artifactRecords[index].createdAt = createdAt
            return
        }
        memoryVaultSnapshot.artifactRecords.append(
            MemoryVaultArtifactRecord(
                id: id,
                artifactType: artifactType,
                title: title,
                detail: trimmed,
                createdAt: createdAt
            )
        )
    }

    private func trimMemoryVaultSnapshot() {
        memoryVaultSnapshot.rawRecords = Array(memoryVaultSnapshot.rawRecords.sorted { $0.createdAt > $1.createdAt }.prefix(8_000))
        memoryVaultSnapshot.compactedRecords = Array(memoryVaultSnapshot.compactedRecords.sorted { $0.createdAt > $1.createdAt }.prefix(600))
        memoryVaultSnapshot.artifactRecords = Array(memoryVaultSnapshot.artifactRecords.sorted { $0.createdAt > $1.createdAt }.prefix(600))
    }

    private func trimMemoryVaultString(_ value: String, maxLength: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else {
            return collapsed
        }
        return String(collapsed.prefix(max(0, maxLength - 3))) + "..."
    }

    func debugSyncMemoryVault(reason: String = "debug") {
        syncMemoryVault(reason: reason)
    }

    func debugMemoryVaultSnapshot() -> MemoryVaultSnapshot {
        memoryVaultSnapshot
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
                for index in contextProfiles.indices {
                    if !contextProfiles[index].enabledKnowledgeFileIDs.contains(fingerprint) {
                        contextProfiles[index].enabledKnowledgeFileIDs.append(fingerprint)
                        contextProfiles[index].enabledKnowledgeFileIDs.sort()
                    }
                }
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
        rebuildKnowledgeSemanticIndex()
        rebuildInsightsAndExecutionPlan()
        persistStateToDisk()
        appendOutput("Imported \(importedCount) knowledge file(s). \(skippedCount > 0 ? "\(skippedCount) skipped." : "Global memory updated.")")
    }

    func removeKnowledgeFile(_ fileID: String) {
        let cleanID = fileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { return }

        knowledgeFiles.removeAll { $0.id == cleanID }
        for index in contextProfiles.indices {
            contextProfiles[index].enabledKnowledgeFileIDs.removeAll { $0 == cleanID }
        }
        workspaceMemoryRecords.removeAll {
            $0.source == .document && $0.key.hasPrefix("document:\(cleanID)")
        }
        workspaceMemoryRecords = normalizeWorkspaceMemoryRecords(workspaceMemoryRecords, now: Date())
        rebuildKnowledgeSemanticIndex()
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
        rebuildKnowledgeSemanticIndex()
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
        queuedAdaptiveSurveyQuestion = nil
        learningPackage = nil
        learningVersion = 0
        learningFingerprint = ""
        memoryVaultSnapshot = MemoryVaultSnapshot()
        memoryVaultRecallResults = []
        memoryVaultRecallQuery = ""
        workspaceSessions = workspaceSessions.map { session in
            var updated = session
            updated.summary = "Session cleared."
            updated.isPinned = false
            return updated
        }
        persistPromptQueueToDisk()
        persistMemoryVaultToDisk()
        refreshMemoryVaultStatus()
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

        Context:
        \(contextEnvelope(for: .workspace, workspaceLane: lane))

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

    func startGUIValidationSuiteIfRequested() async {
        guard shouldRunGUIValidationSuiteOnLaunch else { return }
        requestGUIValidationSuite(triggerSource: "process launch")
    }

    func consumePendingGUIValidationLaunchRequestIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.guiValidationPendingDefaultsKey) else { return }
        let source = defaults.string(forKey: Self.guiValidationPendingSourceDefaultsKey) ?? "startup"
        defaults.removeObject(forKey: Self.guiValidationPendingDefaultsKey)
        defaults.removeObject(forKey: Self.guiValidationPendingSourceDefaultsKey)
        if FileManager.default.fileExists(atPath: Self.guiValidationLaunchSentinelURL.path) {
            clearArmedGUIValidationSuite()
        }
        requestGUIValidationSuite(triggerSource: source)
    }

    func requestGUIValidationSuite(triggerSource: String) {
        guiValidationLastTriggerSource = triggerSource
        if guiValidationLogs.isEmpty {
            guiValidationLogs = []
        }
        guiValidationCurrentStep = bootstrapCompleted
            ? "Trigger received. Preparing validation suite..."
            : "Trigger received. Starting before startup finishes..."
        appendGUIValidationLog("GUI validation trigger received from \(triggerSource).")
        appendOutput("GUI validation requested from \(triggerSource).")
        commandModelBrief = bootstrapCompleted
            ? "GUI validation suite is preparing in-app prompt checks."
            : "GUI validation suite is starting while BlackHaven finishes startup."

        guard !guiValidationIsRunning else { return }
        pendingGUIValidationTriggerSource = nil
        Task { await startGUIValidationSuite(triggerSource: triggerSource) }
    }

    func startGUIValidationSuite(triggerSource: String = "manual") async {
        guard !guiValidationIsRunning else { return }

        let steps: [GUIValidationStep] = [
            GUIValidationStep(
                name: "Concierge markdown",
                dashboardSectionRawValue: "concierge",
                workspaceLane: nil,
                prompt: "Reply with a concise answer that includes a bold heading, a 3-item bullet list, and a final next action sentence."
            ),
            GUIValidationStep(
                name: "Concierge Hebrew",
                dashboardSectionRawValue: "concierge",
                workspaceLane: nil,
                prompt: "Explain in Hebrew how to choose the lightest practical materials for an electric RV build, with one short paragraph and 3 bullets."
            ),
            GUIValidationStep(
                name: "Concierge code fence",
                dashboardSectionRawValue: "concierge",
                workspaceLane: nil,
                prompt: "Return a short answer with a Swift code block that defines a struct named PowerBudget and a JSON code block with battery_kwh and solar_watts."
            ),
            GUIValidationStep(
                name: "Concierge comparison table",
                dashboardSectionRawValue: "concierge",
                workspaceLane: nil,
                prompt: "Compare aluminum, carbon fiber, and fiberglass for electric RV body panels in a compact markdown table with columns for weight, cost, and repairability."
            ),
            GUIValidationStep(
                name: "Workspace synthesis",
                dashboardSectionRawValue: "workspaces",
                workspaceLane: .wealthOperations,
                prompt: "Given a founder focused on AI/software income growth, return a sharp workspace answer with a bold title, 3 numbered steps, one risk, and one next action."
            ),
        ]

        guiValidationIsRunning = true
        guiValidationCurrentStep = "Preparing validation suite..."
        if guiValidationLogs.isEmpty {
            guiValidationLogs = []
        }
        appendGUIValidationLog("GUI validation suite started from \(triggerSource).")
        commandModelBrief = "GUI validation suite is running in-app prompt checks."

        clearPromptQueue()
        startPromptQueueWorker()

        for step in steps {
            guiValidationCurrentStep = step.name
            guiValidationRequestedSectionRawValue = step.dashboardSectionRawValue
            appendGUIValidationLog("Running \(step.name).")

            if let lane = step.workspaceLane {
                activeWorkspaceLane = lane
                if activeSessionID(for: lane) == nil {
                    createWorkspaceSession(for: lane, title: "GUI Validation")
                }
                clearWorkspacePromptQueue()
            }

            try? await Task.sleep(nanoseconds: 700_000_000)

            pendingPrompt = sanitizeModelInput(step.prompt, maxLength: 1800)
            let preexistingIDs = Set(promptQueue.map(\.id))
            if step.workspaceLane == nil {
                enqueuePrompt()
            } else {
                enqueueWorkspacePrompt()
            }

            guard let itemID = await waitForNewestQueuedPrompt(excluding: preexistingIDs, workspaceLane: step.workspaceLane) else {
                appendGUIValidationLog("Failed to detect queued item for \(step.name).")
                continue
            }

            guard let completedItem = await waitForPromptCompletion(id: itemID, timeoutSeconds: 90) else {
                appendGUIValidationLog("Timed out waiting for \(step.name).")
                continue
            }

            let analysis = analyzeGUIValidationResult(for: completedItem)
            appendGUIValidationLog("\(step.name): \(analysis)")
        }

        guiValidationCurrentStep = "Completed"
        appendGUIValidationLog("GUI validation suite completed.")
        guiValidationIsRunning = false
    }

    private func waitForNewestQueuedPrompt(
        excluding existingIDs: Set<String>,
        workspaceLane: WorkspaceLane?
    ) async -> String? {
        for _ in 0..<20 {
            if let item = promptQueue.first(where: { item in
                guard !existingIDs.contains(item.id) else { return false }
                return item.workspaceLane == workspaceLane
            }) {
                return item.id
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func waitForPromptCompletion(id: String, timeoutSeconds: Int) async -> PromptQueueItem? {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if let item = promptQueue.first(where: { $0.id == id }),
               item.status == .done || item.status == .failed {
                return item
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return promptQueue.first(where: { $0.id == id })
    }

    private func analyzeGUIValidationResult(for item: PromptQueueItem) -> String {
        let responseText = item.streamedResponseText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.output?.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        var findings: [String] = []
        findings.append(item.status == .done ? "completed" : "failed")

        if responseText.isEmpty {
            findings.append("empty-response")
        } else {
            findings.append("chars=\(responseText.count)")
        }

        if responseText.contains("**") {
            findings.append("raw-bold-markers")
        }

        if responseText.contains("Runtime Notice:") || responseText.contains("AI runtime unavailable") {
            findings.append("runtime-notice-shown")
        }

        if responseText.range(of: #"[א-ת]"#, options: .regularExpression) != nil {
            findings.append("hebrew-detected")
        }

        if responseText.contains("```") {
            findings.append("code-fence-detected")
        }

        return findings.joined(separator: " · ")
    }

    private func appendGUIValidationLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        guiValidationLogs.insert("[\(stamp)] \(line)", at: 0)
        if guiValidationLogs.count > 24 {
            guiValidationLogs = Array(guiValidationLogs.prefix(24))
        }
    }

    private enum CodingCloudRoute: String {
        case frontendDesign = "frontend_design"
        case backendOps = "backend_ops"
    }

    private func ensureCodingCreditsAccess(action: String, addAgentMessage: Bool = true) -> Bool {
        if !allowsAutomaticRuntimeWork {
            return true
        }
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
            return "Routing to Gemini 3.1 Pro Preview for frontend design, with GPT-5.4 fallback for implementation continuity."
        case .backendOps:
            return "Routing to GPT-5.4 for backend, troubleshooting, and build/test work, with Gemini 3.1 Pro Preview fallback."
        }
    }

    private func preferredCloudModel(for route: CodingCloudRoute) -> String {
        switch route {
        case .frontendDesign:
            return "gemini-3.1-pro-preview"
        case .backendOps:
            return "gpt-5.4"
        }
    }

    private func fallbackCloudModel(for route: CodingCloudRoute) -> String {
        switch route {
        case .frontendDesign:
            return "gpt-5.4"
        case .backendOps:
            return "gemini-3.1-pro-preview"
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
        let sharedKnowledgeContext = knowledgeRetrievalDigest(
            for: prompt,
            surface: .command,
            workspaceLane: nil,
            maxLength: 1_000
        )
        let terminalSnapshot = codingCommandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredModel = preferredCloudModel(for: route)
        let fallbackModel = fallbackCloudModel(for: route)
        let routeInstruction: String = switch route {
        case .frontendDesign:
            "You are the frontend design and implementation agent. Use Gemini 3.1 Pro Preview as the preferred model for UI ideation, layout exploration, motion direction, and visual iteration, while keeping the output production-ready."
        case .backendOps:
            "You are the backend and build agent. Use GPT-5.4 as the preferred model for root-cause isolation, safe patches, terminal-aware debugging, verification commands, and concrete build/test recovery."
        }

        return """
        You are Atlas Agentic Coding Interface.
        You are powered by the GPT-5.4 API.
        \(routeInstruction)
        Operate like a desktop coding agent, not a generic chat assistant.
        - Inspect current state before proposing changes.
        - Preserve existing architecture unless a clearer upgrade is justified.
        - Prefer the minimum safe patch over broad rewrites.
        - Give practical commands when verification is needed.
        - Call out risks, assumptions, and anything the user must do locally.
        - If the preferred cloud model is unavailable, continue using the fallback model without changing the requested route.
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

        RECENT TERMINAL OUTPUT:
        \(terminalSnapshot.isEmpty ? "No recent terminal output captured." : terminalSnapshot)

        CLOUD ROUTING:
        Preferred model: \(preferredModel)
        Fallback model: \(fallbackModel)

        SHARED KNOWLEDGE FILE CONTEXT:
        \(sharedKnowledgeContext)

        USER REQUEST:
        \(prompt)

        REQUIRED RESPONSE SHAPE:
        1. Diagnosis
        2. Exact implementation steps
        3. Verification checklist
        4. Risk or fallback notes
        5. What still needs to happen on the user's machine
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

        if !allowsAutomaticRuntimeWork {
            let reply = """
            Local coding test mode: validate the script by running it once, add a small assertion around expected output, and keep the file focused on one behavior per testable unit.
            """
            addCodingMessage(role: .assistant, content: reply, relatedFilePath: codingSelectedFilePath)
            addCodingMemoryRecord(
                kind: .response,
                summary: "Local coding test-mode response",
                detail: reply,
                relatedFilePath: codingSelectedFilePath
            )
            codingIsGeneratingReply = false
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
                    codeAgentRoute: route.rawValue,
                    preferredCloudModel: preferredCloudModel(for: route),
                    cloudFallbackModel: fallbackCloudModel(for: route)
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
                let runtimeNotice = "Coding AI runtime unavailable. No model completion returned. Retry in a few seconds."
                addCodingMessage(role: .assistant, content: runtimeNotice, relatedFilePath: selectedPath)
                addCodingMemoryRecord(
                    kind: .response,
                    summary: "Coding runtime unavailable notice",
                    detail: runtimeNotice,
                    relatedFilePath: selectedPath
                )
                appendOutput(runtimeNotice)
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

    var codingAgentReadinessSummary: String {
        prepaidCreditsActive
            ? "Hybrid cloud coding ready. Frontend work prefers Gemini 3.1 Pro Preview, backend/build work prefers GPT-5.4, and local Qwen remains available on-device."
            : "Hybrid cloud coding is locked until prepaid credits are active. Local Qwen remains available on-device."
    }

    var codingAgentToolingSummary: String {
        let workspaceSummary = codingWorkspaceRootPath.isEmpty
            ? "No coding workspace indexed yet."
            : "\(codingWorkspaceFiles.count) files indexed under \(codingWorkspaceRootPath)."
        let terminalSummary = codingCommandOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No recent terminal output captured."
            : "Recent terminal output is available for GPT-5.4 context."
        return "\(workspaceSummary) \(terminalSummary) Frontend design route prefers Gemini 3.1 Pro Preview with GPT-5.4 fallback."
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
        let vaultBytes = memoryVaultSnapshot.rawRecords.reduce(0) { $0 + $1.content.count }
            + memoryVaultSnapshot.compactedRecords.reduce(0) { $0 + $1.summary.count }
            + memoryVaultSnapshot.artifactRecords.reduce(0) { $0 + $1.detail.count }
        let totalKB = max(1, (notesBytes + queueBytes + codingBytes + vaultBytes) / 1024)
        return "~\(totalKB) KB local memory profile · \(memoryVaultOverview())"
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

    var surveyAnswersRequiredForExecution: Int {
        Self.minimumSurveyAnswersForExecution
    }

    var surveyAnswersRemainingForExecution: Int {
        max(0, surveyAnswersRequiredForExecution - surveyAnswers.count)
    }

    var isExecutionStreamUnlocked: Bool {
        surveyAnswers.count >= surveyAnswersRequiredForExecution
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
        return surveyAnswers.count >= max(surveyAnswersRequiredForExecution, localSurveyTotal())
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
        activeTravelItineraryDraft.locationIDs.compactMap { id in
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
        activeTravelItineraryDraft.locationIDs.removeAll { $0 == id }
        activeTravelItineraryDraft.updatedAt = isoTimestamp()
        if selectedTravelLocationID == id {
            selectedTravelLocationID = savedTravelLocations.first?.id
        }
        persistStateToDisk()
        appendOutput("Removed travel location from the saved list.")
    }

    func addLocationToTravelItinerary(_ id: String) {
        guard activeTravelItineraryDraft.locationIDs.contains(id) == false else { return }
        activeTravelItineraryDraft.locationIDs.append(id)
        activeTravelItineraryDraft.updatedAt = isoTimestamp()
        persistStateToDisk()
        appendOutput("Added location to itinerary.")
    }

    func removeLocationFromTravelItinerary(_ id: String) {
        activeTravelItineraryDraft.locationIDs.removeAll { $0 == id }
        activeTravelItineraryDraft.updatedAt = isoTimestamp()
        persistStateToDisk()
        appendOutput("Removed location from itinerary.")
    }

    func moveTravelItineraryLocations(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = activeTravelItineraryDraft.locationIDs
        let moving = fromOffsets.map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            reordered.remove(at: index)
        }
        reordered.insert(contentsOf: moving, at: min(toOffset, reordered.count))
        activeTravelItineraryDraft.locationIDs = reordered
        activeTravelItineraryDraft.updatedAt = isoTimestamp()
        persistStateToDisk()
    }

    func updateTravelItineraryTitle(_ title: String) {
        activeTravelItineraryDraft.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Travel itinerary"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTravelItineraryDraft.updatedAt = isoTimestamp()
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
    }

    private func setLocalModelRuntimeProgress(
        status: String,
        detail: String,
        progress: Double,
        busy: Bool,
        ready: Bool
    ) {
        localModelRuntimeStatus = status
        localModelRuntimeDetail = detail
        localModelRuntimeProgress = min(1.0, max(0.0, progress))
        localModelRuntimeIsBusy = busy
        localModelRuntimeReady = ready
        updateLocalAISetupStateFromRuntime(busy: busy, ready: ready)
    }

    private func ensureDesktopRemoteControlServer() {
        if remoteControlToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remoteControlToken = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(remoteControlToken, forKey: "atlas.remote.control.token")
        }

        if remoteControlServer == nil {
            remoteControlServer = DesktopRemoteControlServer(port: 8765) { [weak self] request in
                guard let self else {
                    return .init(statusCode: 500, jsonObject: ["error": "server_unavailable"])
                }
                return await self.handleRemoteControlRequest(request)
            }

            do {
                try remoteControlServer?.start()
                appendOutput("Desktop remote control ready for iOS/Android pairing.")
            } catch {
                remoteControlStatus = "Desktop remote control unavailable: \(error.localizedDescription)"
            }
        }

        remoteControlURL = "http://\(Self.primaryLANIPv4Address() ?? "127.0.0.1"):8765"
        remoteControlStatus = "Desktop remote control is listening on \(remoteControlURL)."
    }

    private func handleRemoteControlRequest(_ request: DesktopRemoteControlServer.Request) async -> DesktopRemoteControlServer.Response {
        let expectedAuthorization = "Bearer \(remoteControlToken)"
        guard request.headers["Authorization"] == expectedAuthorization else {
            return .init(statusCode: 401, jsonObject: ["error": "unauthorized"])
        }

        if request.method == "GET", request.path == "/api/remote/status" {
            return .init(statusCode: 200, jsonObject: [
                "app_name": "BlackHaven Mac",
                "platform": "macos",
                "device_name": Host.current().localizedName ?? "Mac",
                "runtime_status": runtimeHealthHeadline,
                "runtime_detail": localModelRuntimeDetail,
                "local_model": localInferencePreferredModelName,
                "cloud_code_models": ["gemini-3.1-pro-preview", "gpt-5.4"],
                "coding_agent_ready": prepaidCreditsActive,
                "coding_agent_summary": codingAgentReadinessSummary,
                "coding_agent_tooling": codingAgentToolingSummary,
                "queue_depth": promptQueue.filter { $0.status == .queued || $0.status == .running }.count,
                "last_action": remoteControlLastAction
            ])
        }

        if request.method == "POST", request.path == "/api/remote/dispatch" {
            guard
                let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                let prompt = (object["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                let target = (object["target"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !prompt.isEmpty
            else {
                return .init(statusCode: 400, jsonObject: ["error": "missing_prompt_or_target"])
            }

            if target == "cloud_gpt5_4" {
                guard prepaidCreditsActive else {
                    remoteControlLastAction = "GPT-5.4 coding is locked until prepaid credits are active on desktop."
                    return .init(statusCode: 200, jsonObject: ["message": remoteControlLastAction, "queue_depth": promptQueue.count])
                }
                codingPromptDraft = prompt
                submitCodingPrompt()
                remoteControlLastAction = "Queued GPT-5.4 coding request from mobile remote."
            } else {
                pendingPrompt = sanitizeModelInput(prompt, maxLength: 1800)
                enqueuePrompt()
                remoteControlLastAction = "Queued local Qwen request from mobile remote."
            }

            return .init(statusCode: 200, jsonObject: [
                "accepted": true,
                "message": remoteControlLastAction,
                "queue_depth": promptQueue.filter { $0.status == .queued || $0.status == .running }.count
            ])
        }

        return .init(statusCode: 404, jsonObject: ["error": "not_found"])
    }

    private static func primaryLANIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer = first
        while true {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name != "lo0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    let candidate = String(cString: host)
                    if !candidate.isEmpty {
                        address = candidate
                        break
                    }
                }
            }

            guard let next = interface.ifa_next else { break }
            pointer = next
        }

        return address
    }

    private func setLocalModelDownloadTelemetry(downloadedBytes: Int64, totalBytes: Int64, etaSeconds: Int?) {
        localModelDownloadBytes = max(0, downloadedBytes)
        localModelDownloadTotalBytes = max(0, totalBytes)
        if let etaSeconds {
            localModelDownloadETASeconds = max(0, etaSeconds)
        } else {
            localModelDownloadETASeconds = nil
        }
    }

    var localModelDownloadSizeText: String {
        if localModelRuntimeReady && !localModelRuntimeIsBusy {
            return "Local model is ready."
        }
        guard localModelDownloadTotalBytes > 0 else {
            switch localModelRuntimeStatusCode {
            case .startingRuntime:
                return "Checking for an existing Qwen install..."
            case .downloadingModel:
                return "Connecting to model source..."
            case .warmingModel:
                return "Loading Qwen into memory..."
            default:
                return "Preparing download..."
            }
        }
        return "\(Self.formatByteCount(localModelDownloadBytes)) / \(Self.formatByteCount(localModelDownloadTotalBytes))"
    }

    var localModelDownloadETAText: String {
        if localModelRuntimeReady && !localModelRuntimeIsBusy {
            return "Ready"
        }
        guard localModelDownloadTotalBytes > 0 else {
            return localModelRuntimeIsBusy ? "Starting automatically..." : "Ready"
        }
        guard let eta = localModelDownloadETASeconds, eta > 0 else { return "Waiting for a stable transfer rate..." }
        let minutes = eta / 60
        let seconds = eta % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return "~\(hours)h \(remMinutes)m remaining"
        }
        if minutes > 0 {
            return "~\(minutes)m \(seconds)s remaining"
        }
        return "~\(seconds)s remaining"
    }

    var localAIHardwareSummary: String {
        let processInfo = ProcessInfo.processInfo
        let memoryGB = max(8, Int(processInfo.physicalMemory / 1_073_741_824))
        let cores = max(1, processInfo.activeProcessorCount)
        return "\(cores)-core CPU · \(memoryGB) GB unified memory"
    }

    var selectedLocalAIInstallOptions: [LocalAIModelInstallOption] {
        localAIInstallOptions.filter { selectedLocalAIInstallOptionIDs.contains($0.id) }
    }

    var selectedLocalAIInstallModelOrder: [String] {
        let selected = Set(selectedLocalAIInstallOptionIDs.map { $0.lowercased() })
        let preferredOrder = localAIInstallOptions.map(\.id)
        let ordered = preferredOrder.filter { selected.contains($0) }
        return ordered.isEmpty ? ["qwen2.5:7b"] : ordered
    }

    var selectedLocalAIInstallPrimaryModel: String {
        selectedLocalAIInstallModelOrder.first ?? "qwen2.5:7b"
    }

    var selectedLocalAIInstallSizeTotalGB: Double {
        selectedLocalAIInstallOptions.reduce(0) { $0 + $1.approximateSizeGB }
    }

    var selectedLocalAIInstallSummary: String {
        let selected = selectedLocalAIInstallOptions
        guard !selected.isEmpty else {
            return "Select at least one model to continue local AI setup."
        }

        let names = selected.map(\.title).joined(separator: " + ")
        return "\(names) · \(String(format: "%.1f GB total", selectedLocalAIInstallSizeTotalGB))"
    }

    var shouldShowLocalAISetupExperience: Bool {
        !localAISetupCompleted && !localAISetupDeferred && localAISetupStage != .ready
    }

    var runtimeHealthHeadline: String {
        switch localModelRuntimeStatusCode {
        case .notInstalled:
            return "BlackHaven Is Preparing Local AI"
        case .installingRuntime:
            return "Installing Local AI Runtime"
        case .startingRuntime:
            return "Starting Local AI"
        case .downloadingModel:
            return "Downloading Local AI Model"
        case .warmingModel:
            return "Warming Local AI"
        case .ready:
            return "Local AI Ready"
        case .degraded:
            return "Local AI Retrying"
        case .error:
            return "Local AI Needs Attention"
        }
    }

    var localAIChatStatusMessage: String? {
        switch localModelRuntimeStatusCode {
        case .notInstalled:
            return "BlackHaven is preparing local AI automatically."
        case .installingRuntime:
            return "BlackHaven is installing local AI runtime support."
        case .startingRuntime:
            return "BlackHaven is starting local AI in the background."
        case .downloadingModel:
            return "BlackHaven is downloading your selected local AI model."
        case .warmingModel:
            return "BlackHaven is warming the local model for first response."
        case .degraded:
            return "Local AI is still warming up. BlackHaven is retrying automatically in the background."
        case .error:
            return localModelRuntimeLastError.isEmpty ? "Local AI needs attention before chat can continue." : localModelRuntimeLastError
        case .ready:
            return nil
        }
    }

    var localAIRuntimeChatNotice: String {
        switch localModelRuntimeStatusCode {
        case .ready:
            return "Local AI had trouble finishing that response. Try a shorter follow-up and it should recover."
        case .notInstalled, .installingRuntime, .startingRuntime, .downloadingModel, .warmingModel, .degraded:
            return "Local AI is still getting ready. BlackHaven is retrying automatically in the background."
        case .error:
            return "Local AI needs attention before chat can continue."
        }
    }

    private func currentLocalInferenceDiagnosticMessage() async -> String {
        var segments: [String] = []
        var reachableRouteCount = 0

        if let primary = localInferenceEndpointURL {
            let reachable = await Self.isLocalRuntimeEndpointReachable(endpoint: primary, timeoutSeconds: 2)
            if reachable {
                reachableRouteCount += 1
            }
            segments.append("Primary route \(primary.absoluteString): \(reachable ? "reachable" : "unreachable")")
        } else {
            segments.append("Primary route: invalid")
        }

        if let fallback = localInferenceFailoverEndpointURL,
           fallback != localInferenceEndpointURL
        {
            let reachable = await Self.isLocalRuntimeEndpointReachable(endpoint: fallback, timeoutSeconds: 2)
            if reachable {
                reachableRouteCount += 1
            }
            segments.append("Fallback route \(fallback.absoluteString): \(reachable ? "reachable" : "unreachable")")
        }

        if !lastLocalInferenceAttemptDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(lastLocalInferenceAttemptDetail)
        }

        if !localModelRuntimeLastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append("Last runtime error: \(sanitizeWorkspaceMemoryValue(localModelRuntimeLastError, maxLength: 220))")
        } else if let status = localAIChatStatusMessage {
            segments.append("Runtime status: \(sanitizeWorkspaceMemoryValue(status, maxLength: 220))")
        }

        let prefix = reachableRouteCount > 0
            ? "BlackHaven reached local AI, but this response did not finish cleanly."
            : "BlackHaven could not reach a working local AI route for this response."
        return prefix + " " + segments.joined(separator: " · ")
    }

    var runtimeEndpointReachabilityLine: String {
        let endpoint = localInferenceEndpointURL?.absoluteString ?? "invalid-endpoint"
        return "Endpoint: \(endpoint) · status: \(localModelRuntimeStatusCode.rawValue)"
    }

    var localAIPrimaryActionTitle: String {
        switch localModelRuntimeStatusCode {
        case .notInstalled, .installingRuntime:
            return "Download Qwen 2.5 7B"
        case .ready:
            return "Repair / Recheck Local AI"
        case .startingRuntime, .downloadingModel, .warmingModel, .degraded, .error:
            return "Repair / Retry Local AI"
        }
    }

    func toggleLocalAIInstallOption(_ optionID: String) {
        var selected = Set(selectedLocalAIInstallOptionIDs)
        if selected.contains(optionID) {
            if selected.count == 1 {
                return
            }
            selected.remove(optionID)
        } else {
            selected.insert(optionID)
        }
        selectedLocalAIInstallOptionIDs = Self.dedupModels(localAIInstallOptions.map(\.id).filter { selected.contains($0) })
        persistSelectedLocalAIInstallOptions()
    }

    func installSelectedLocalAIModels() {
        let selectedModels = selectedLocalAIInstallModelOrder
        guard !selectedModels.isEmpty else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LocalInferenceDefaults.enabledKey)
        defaults.set("http://127.0.0.1:8080/v1/chat/completions", forKey: LocalInferenceDefaults.endpointKey)
        defaults.set(selectedLocalAIInstallPrimaryModel, forKey: GuidedLearningDefaults.ollamaModelKey)
        defaults.set("http://127.0.0.1:8080/v1/chat/completions", forKey: GuidedLearningDefaults.ollamaEndpointKey)
        defaults.set(selectedLocalAIInstallPrimaryModel, forKey: LocalInferenceDefaults.modelKey)
        defaults.set(Self.dedupModels(selectedModels + localInferenceModelCatalog).joined(separator: ","), forKey: LocalInferenceDefaults.catalogKey)
        defaults.set(false, forKey: LocalAISetupDefaults.deferredKey)
        persistSelectedLocalAIInstallOptions()
        localAISetupDeferred = false
        localAISetupStage = .installing
        appendOutput("Installing local AI models: \(selectedModels.joined(separator: ", ")).")
        if Self.resolvedLlamaServerBinaryPath() == nil {
            setLocalRuntimeHealth(
                statusCode: .error,
                status: "Local AI needs attention",
                detail: "The bundled llama-server runtime is missing from this build.",
                progress: 0.0,
                busy: false,
                ready: false,
                lastError: "Bundled llama-server runtime missing from app bundle."
            )
            return
        }
        startManagedLocalRuntimeProvisioningIfNeeded(force: true)
    }

    func deferLocalAISetup() {
        localAISetupDeferred = true
        localAISetupStage = .deferred
        UserDefaults.standard.set(true, forKey: LocalAISetupDefaults.deferredKey)
        appendOutput("Local AI setup deferred. You can return to Runtime Health anytime.")
    }

    func retryLocalAISetup() {
        Task {
            await prepareLocalAISetupExperienceOnLaunch(forceRecoveryInstall: localAISetupCompleted)
        }
    }

    func revealLocalAISetupAgain() {
        localAISetupDeferred = false
        localAISetupStage = .installRequired
        UserDefaults.standard.set(false, forKey: LocalAISetupDefaults.deferredKey)
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

            let item = promptQueue[index]
            let queueItemID = item.id

            guard updatePromptQueueItem(id: queueItemID, mutate: { item in
                item.status = .running
                item.startedAt = item.startedAt ?? Date()
                item.completedAt = nil
                item.lastCheckpointAt = Date()
                item.progress = max(item.progress ?? 0.0, 0.05)
                item.checkpointNote = "Working on your response..."
                item.streamedResponseText = nil
                item.errorMessage = nil
            }) else {
                continue
            }
            persistPromptQueueToDisk()

            let checkpointInterval = queueCheckpointIntervalNanoseconds()
            let checkpointID = queueItemID
            let checkpointTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: checkpointInterval)
                    await MainActor.run { [weak self] in
                        self?.checkpointRunningQueueItem(
                            id: checkpointID,
                            note: "Still working on your response..."
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
            guard let output = await boundedQueueOutput(item: item, prompt: boundedPrompt, notes: boundedNotes) else {
                checkpointTask.cancel()

                if shouldPauseQueueForInternetReconnect {
                    markQueueItemWaitingForInternetReconnect(id: queueItemID)
                    logQueueReconnectWaitIfNeeded()
                    try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                    continue
                }

                if localModelRuntimeIsBusy {
                    if updatePromptQueueItem(id: queueItemID, mutate: { item in
                        item.status = .queued
                        item.completedAt = nil
                        item.lastCheckpointAt = Date()
                        item.progress = max(0.08, min(0.45, item.progress ?? 0.1))
                        item.checkpointNote = "Local runtime is warming up. Retrying automatically."
                        item.streamedResponseText = nil
                        item.errorMessage = nil
                    }) {
                        persistPromptQueueToDisk()
                    }
                    try? await Task.sleep(nanoseconds: queueReconnectWaitNanoseconds())
                    continue
                }

                let diagnostic = await currentLocalInferenceDiagnosticMessage()
                lastLocalInferenceDiagnostic = diagnostic
                let runtimeMessage = diagnostic
                if updatePromptQueueItem(id: queueItemID, mutate: { item in
                    item.status = .failed
                    item.completedAt = Date()
                    item.lastCheckpointAt = Date()
                    item.progress = 1.0
                    item.checkpointNote = "Local AI could not complete this response."
                    item.streamedResponseText = nil
                    item.output = nil
                    item.errorMessage = runtimeMessage
                }) {
                    persistPromptQueueToDisk()
                }
                appendOutput(runtimeMessage)
                let cooldown = queueCooldownNanoseconds()
                if cooldown > 0 {
                    try? await Task.sleep(nanoseconds: cooldown)
                }
                continue
            }
            checkpointTask.cancel()
            guard updatePromptQueueItem(id: queueItemID, mutate: { item in
                item.status = .done
                item.completedAt = Date()
                item.lastCheckpointAt = Date()
                item.progress = 1.0
                item.checkpointNote = "Response ready."
                item.streamedResponseText = nil
                item.output = output
                item.errorMessage = nil
            }) else {
                continue
            }
            syncMemoryVault(reason: "queue_output")
            persistPromptQueueToDisk()
            if output.model == "atlas-academic-discovery-v3" {
                appendOutput("Academic discovery completed. Open the top full-text or DOI sources, compare the matrix, and run citation snowballing.")
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

    private func boundedQueueOutput(
        item: PromptQueueItem,
        prompt: String,
        notes: [UserNote]
    ) async -> LocalReasoningOutput? {
        let timeoutSeconds = queueResponseTimeoutSeconds(item: item)
        return await withTaskGroup(of: LocalReasoningOutput?.self) { group in
            group.addTask { [weak self] in
                guard let self else { return nil }
                return await self.modelDrivenQueueOutput(item: item, prompt: prompt, notes: notes)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func queueResponseTimeoutSeconds(item: PromptQueueItem) -> Int {
        let recentObserved = recentLocalInferenceDurationsSeconds.suffix(6).max() ?? 0
        let observedBudget = recentObserved > 0
            ? Int(ceil(recentObserved * (guiValidationIsRunning ? 1.45 : 1.65))) + 4
            : 0
        let startupBudget: Int
        if let endpoint = localInferenceEndpointURL,
           isLoopbackHost(endpoint.host),
           !localModelRuntimeReady
        {
            startupBudget = Int(ceil(max(Self.recordedManagedLocalRuntimeWarmupSeconds(), recentObserved))) + 10
        } else {
            startupBudget = 0
        }

        let isConciergeValidation = guiValidationIsRunning && item.workspaceLane == nil
        let baseline = isConciergeValidation ? 70 : (guiValidationIsRunning ? 32 : 36)
        return min(90, max(baseline, observedBudget, startupBudget))
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

    private func activeMemoryDigestForQueue(query: String? = nil) -> String {
        syncMemoryVault(reason: "queue_preflight")
        let profile = activeMemoryProfile()
        let policy = memoryVaultSnapshot.lastPolicy ?? currentMemoryVaultPolicy()
        let queryTokens = Set(semanticTokens(from: query ?? ""))
        let working = memoryVaultSnapshot.rawRecords
            .filter { !$0.deepArchived }
            .sorted { lhs, rhs in
                if !queryTokens.isEmpty {
                    let lhsScore = semanticTextScore(text: "\(lhs.sourceType) \(lhs.sourceLabel) \(lhs.content)", queryTokens: queryTokens)
                    let rhsScore = semanticTextScore(text: "\(rhs.sourceType) \(rhs.sourceLabel) \(rhs.content)", queryTokens: queryTokens)
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(policy.retrievalDepth)
            .map { "- [\($0.sourceType)] \(trimMemoryVaultString($0.content, maxLength: 180))" }
        let compacted = memoryVaultSnapshot.compactedRecords
            .sorted { lhs, rhs in
                if !queryTokens.isEmpty {
                    let lhsScore = semanticTextScore(text: "\(lhs.title) \(lhs.summary)", queryTokens: queryTokens)
                    let rhsScore = semanticTextScore(text: "\(rhs.title) \(rhs.summary)", queryTokens: queryTokens)
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(max(2, policy.retrievalDepth))
            .map { "- \($0.title): \(trimMemoryVaultString($0.summary, maxLength: 180))" }
        let artifacts = memoryVaultSnapshot.artifactRecords
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(4)
            .map { "- [\($0.artifactType)] \(trimMemoryVaultString($0.title, maxLength: 40)): \(trimMemoryVaultString($0.detail, maxLength: 120))" }

        let digest = """
        Memory depth: \(activeMemoryDepth) (`atlas.local.memory.depth` = lean|balanced|deep)
        Hardware tier: \(policy.hardwareTier)
        Context budget: \(policy.contextBudgetTokens)
        Compaction threshold: \(policy.compactionThresholdTokens)
        Retrieval depth: \(policy.retrievalDepth)
        Lossless summary path: local-only desktop runtime
        Estimated token pressure: \(memoryVaultSnapshot.lastTokenPressure)

        L1 Working Memory:
        \(working.isEmpty ? "- none" : working.joined(separator: "\n"))

        L2 Compacted Context:
        \(compacted.isEmpty ? "- none" : compacted.joined(separator: "\n"))

        L2 Artifact Records:
        \(artifacts.isEmpty ? "- none" : artifacts.joined(separator: "\n"))

        L3 Local Encrypted Archive:
        - raw records: \(memoryVaultSnapshot.rawRecords.count)
        - compacted records: \(memoryVaultSnapshot.compactedRecords.count)
        - if exact detail is missing, recall raw local memory before finalizing the answer.
        """

        return sanitizeModelInput(digest, maxLength: max(profile.maxChars, policy.contextBudgetTokens / 3))
    }

    private func semanticTextScore(text: String, queryTokens: Set<String>) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        let tokens = Set(semanticTokens(from: text))
        let overlap = tokens.intersection(queryTokens)
        guard !overlap.isEmpty else { return 0 }
        return Double(overlap.count) / Double(max(1, queryTokens.count))
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

        let surface: AtlasContextSurface = item.workspaceLane == nil ? .concierge : .workspace
        let surfaceProfile = contextProfile(for: surface, workspaceLane: item.workspaceLane)
        let sharedKnowledgeContext = selectedKnowledgeFilesContextDigest(for: surfaceProfile, query: prompt, maxLength: 1_100)
        let activeMemoryContext = activeMemoryDigestForQueue(query: prompt)
        let contextualEnvelope = contextEnvelope(for: surface, workspaceLane: item.workspaceLane)
        let isValidationRun = guiValidationIsRunning
        let localContextEnvelopeLimit = isValidationRun ? 900 : (surface == .concierge ? 1_200 : 1_800)
        let localNotesCount = isValidationRun ? 6 : 12
        let localNoteContentLimit = isValidationRun ? 72 : 96
        let localActiveMemoryLimit = isValidationRun ? 800 : (surface == .concierge ? 1_000 : 1_500)
        let localKnowledgeLimit = isValidationRun ? 380 : (surface == .concierge ? 550 : 900)
        let notesSnapshot = notes
            .prefix(16)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: 180))" }
            .joined(separator: "\n")
        let localNotesSnapshot = notes
            .prefix(localNotesCount)
            .map { "- \($0.title): \(sanitizeModelInput($0.content, maxLength: localNoteContentLimit))" }
            .joined(separator: "\n")
        let localActiveMemoryContext = sanitizeModelInput(activeMemoryContext, maxLength: localActiveMemoryLimit)
        let localSharedKnowledgeContext = selectedKnowledgeFilesContextDigest(
            for: surfaceProfile,
            query: prompt,
            maxLength: localKnowledgeLimit
        )

        let instruction = """
        You are Atlas local reasoning engine.
        Return a natural, direct response in markdown.
        Do not return JSON.
        Be specific, concrete, and useful.
        Include clear reasoning and practical steps.
        Keep it concise but complete for a real operator.
        If relevant, end with a short "Next action:" line.

        Prompt:
        \(prompt)

        Surface context:
        \(contextualEnvelope)

        Notes:
        \(notesSnapshot)

        Active memory management:
        \(activeMemoryContext)

        Shared knowledge files:
        \(sharedKnowledgeContext)
        """

        let localInstruction = """
        You are Atlas local reasoning engine.
        Return a natural, direct response in markdown.
        Do not return JSON.
        Compare alternatives quickly, then give the strongest practical answer.
        Keep it concise and operational.
        If relevant, end with a short "Next action:" line.

        Prompt:
        \(sanitizeModelInput(prompt, maxLength: 1_200))

        Surface context:
        \(sanitizeModelInput(contextualEnvelope, maxLength: localContextEnvelopeLimit))

        Notes:
        \(localNotesSnapshot)

        Active memory:
        \(localActiveMemoryContext)

        Shared knowledge:
        \(localSharedKnowledgeContext)
        """

        let shouldStreamLocalQueueResponse = !guiValidationIsRunning
        let localQueueStreamHandler: (@Sendable (String) -> Void)?
        if shouldStreamLocalQueueResponse {
            localQueueStreamHandler = { [weak self] partial in
                DispatchQueue.main.async { [weak self] in
                    self?.updateRunningQueueItemStream(id: item.id, partial: partial)
                }
            }
        } else {
            localQueueStreamHandler = nil
        }

        let preferLocalFirst = shouldPreferLocalInferenceForQueue()

        let localQueueTimeoutSeconds = guiValidationIsRunning ? 42 : 24

        if preferLocalFirst,
           let raw = await requestLocalModelResponse(
                prompt: localInstruction,
                timeoutSeconds: localQueueTimeoutSeconds,
                domain: .general,
                preferredModelOverride: guiValidationIsRunning ? "qwen2.5:7b" : nil,
                streamHandler: localQueueStreamHandler
           ) {
            return naturalQueueOutput(
                from: raw,
                model: "\(sanitizeWorkspaceMemoryValue(lastResolvedLocalInferenceModel, maxLength: 64))-local",
                confidence: 0.62
            )
        }

        if prepaidCreditsActive {
            do {
                let response = try await api.chat(
                    sessionID: item.workspaceSessionID,
                    text: instruction,
                    locale: Locale.current.identifier,
                    preferredFormat: nil,
                    responseDepth: "deep",
                    responseTone: "natural",
                    includeProactive: false
                )
                let reply = response.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    return naturalQueueOutput(
                        from: reply,
                        model: "atlas-cloud-backend/v1-chat",
                        confidence: 0.67
                    )
                }
            } catch {
                // Shared backend failed; continue with local inference fallback.
            }
        }

        guard let raw = await requestLocalModelResponse(
            prompt: localInstruction,
            timeoutSeconds: localQueueTimeoutSeconds,
            domain: .general,
            preferredModelOverride: guiValidationIsRunning ? "qwen2.5:7b" : nil,
            streamHandler: localQueueStreamHandler
        ) else {
            return nil
        }
        return naturalQueueOutput(
            from: raw,
            model: "\(sanitizeWorkspaceMemoryValue(lastResolvedLocalInferenceModel, maxLength: 64))-local",
            confidence: 0.58
        )
    }

    private func shouldPreferLocalInferenceForQueue() -> Bool {
        guard localInferenceEnabled,
              localModelRuntimeReady,
              !localModelRuntimeIsBusy,
              let endpoint = localInferenceEndpointURL
        else {
            return false
        }
        return isLoopbackHost(endpoint.host)
    }

    private func naturalQueueOutput(from raw: String, model: String, confidence: Double) -> LocalReasoningOutput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = sanitizeWorkspaceMemoryValue(text.isEmpty ? "No response generated." : text, maxLength: 3_200)
        let nextAction = inferredNextAction(from: text)
        let reasoning = reasoningSnapshot(from: text, nextAction: nextAction, confidence: confidence)
        return LocalReasoningOutput(
            model: model,
            summary: summary,
            nextAction: sanitizeWorkspaceMemoryValue(nextAction, maxLength: 240),
            confidence: min(1.0, max(0.0, confidence)),
            generatedAt: Date(),
            reasoningSummary: reasoning.summary,
            alternativesConsidered: reasoning.alternatives,
            assumptions: reasoning.assumptions,
            confidenceLabel: reasoning.confidenceLabel
        )
    }

    private func reasoningSnapshot(
        from text: String,
        nextAction: String,
        confidence: Double
    ) -> (summary: String, alternatives: [String], assumptions: [String], confidenceLabel: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let firstParagraph = paragraphs.first ?? cleaned
        let firstSentence = firstParagraph
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Focused on the most actionable path."

        let reasoningSummary = sanitizeWorkspaceMemoryValue(
            "Picked the most actionable option first, compared quick alternatives, and optimized for speed, clarity, and practical follow-through. Core direction: \(firstSentence).",
            maxLength: 420
        )

        var alternatives = [
            "Ask more diagnostic follow-up questions before recommending a move.",
            "Offer a broader multi-step strategy instead of the fastest practical path."
        ]
        if !nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            alternatives.append("Delay action until more certainty is available instead of moving on \"\(sanitizeWorkspaceMemoryValue(nextAction, maxLength: 110))\".")
        }
        alternatives = Array(alternatives.prefix(3))

        let assumptions = [
            "The fastest useful answer is better here than a slower exhaustive analysis.",
            "Current memory, notes, and user prompt reflect the main context well enough to act."
        ]

        let confidenceLabel: String
        switch confidence {
        case ..<0.45:
            confidenceLabel = "Low"
        case ..<0.72:
            confidenceLabel = "Medium"
        case ..<0.9:
            confidenceLabel = "High"
        default:
            confidenceLabel = "Very High"
        }

        return (reasoningSummary, alternatives, assumptions, confidenceLabel)
    }

    private func inferredNextAction(from text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let explicit = lines.first(where: {
            let lower = $0.lowercased()
            return lower.contains("next action:") || lower.hasPrefix("next step:") || lower.contains("action:")
        }) {
            return explicit.replacingOccurrences(of: #"^[\-\*\d\.\)\s]+"#, with: "", options: .regularExpression)
        }

        if let bullet = lines.first(where: { $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.range(of: #"^\d+\."#, options: .regularExpression) != nil }) {
            return bullet.replacingOccurrences(of: #"^[\-\*\d\.\)\s]+"#, with: "", options: .regularExpression)
        }

        return "Pick the highest-impact step from this response and execute it in the next 25 minutes."
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
        let context = contextEnvelope(for: .command)
        let prompt = """
        Return one concise command-brief paragraph (< 500 chars) for this operator.
        Focus on immediate execution leverage and risk control.

        Context:
        \(context)

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
        let context = contextEnvelope(for: .workspace, workspaceLane: lane)
        let prompt = """
        Return one concise workspace brief (< 500 chars).
        Context:
        \(context)
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
        return "Local LLM bridge misconfigured. Check `atlas.local.llm.endpoint`."
    }

    private func localRuntimeFailureMessage(prefix: String = "AI runtime unavailable.") -> String {
        guard localInferenceEnabled else {
            return "\(prefix) Local model runtime is disabled."
        }

        guard let endpoint = localInferenceEndpointURL else {
            return "\(prefix) Local AI service endpoint is misconfigured."
        }

        let endpointLabel = endpoint.absoluteString
        if localModelRuntimeReady {
            return "\(prefix) Local AI runtime is reachable at \(endpointLabel), but this completion failed or timed out. Retrying should work after prompt/context reduction."
        }
        if let chatStatus = localAIChatStatusMessage {
            return "\(prefix) \(chatStatus)"
        }

        if hasLikelyLocalOllamaRoute {
            return "\(prefix) Local AI service is currently unreachable at \(endpointLabel). BlackHaven will keep retrying while its managed local runtime starts."
        }

        return "\(prefix) Local AI service is unavailable right now at \(endpointLabel). BlackHaven should start the bundled runtime automatically; if not, this build may be missing it."
    }

    private func normalizedOwnerAccountLabel(_ accountName: String) -> String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ownerAccountLabel }
        return ownerAccountLabel
    }

    private func startManagedLocalRuntimeProvisioningIfNeeded(force: Bool = false) {
        guard localRuntimeProvisioningTask == nil else { return }
        if force {
            localModelDownloadBytes = 0
            localModelDownloadTotalBytes = 0
            localModelDownloadETASeconds = nil
        }
        setLocalRuntimeHealth(
            statusCode: .startingRuntime,
            status: "BlackHaven is preparing local AI",
            detail: "Verifying local model service availability.",
            progress: 0.08,
            busy: true,
            ready: false
        )
        localRuntimeProvisioningTask = Task { [weak self] in
            guard let self else { return }
            await ensureManagedLocalRuntimeReady()
            localRuntimeProvisioningTask = nil
        }
    }

    private func ensureManagedLocalRuntimeReady() async {
        let preferredModel = localInferencePreferredModelName
        guard localInferenceEnabled,
              let endpoint = localInferenceEndpointURL,
              isLoopbackHost(endpoint.host)
        else {
            setLocalRuntimeHealth(
                statusCode: .error,
                status: "Local AI setup blocked",
                detail: "Local AI provisioning was skipped because the endpoint is invalid or not local.",
                progress: 0.0,
                busy: false,
                ready: false,
                lastError: "Local AI provisioning needs a localhost endpoint."
            )
            return
        }

        let runtimeReadyAtStart = await Self.isLocalRuntimeReadyForInference(
            endpoint: endpoint,
            model: preferredModel,
            timeoutSeconds: 8
        )
        if runtimeReadyAtStart {
            setLocalRuntimeHealth(
                statusCode: .ready,
                status: "Local AI ready",
                detail: "Local model runtime is reachable at \(endpoint.absoluteString).",
                progress: 1.0,
                busy: false,
                ready: true
            )
            appendOutput("Enhanced on-device AI runtime ready (\(preferredModel)).")
            return
        }

        appendOutput("Checking for your local Qwen model.")
        setLocalRuntimeHealth(
            statusCode: .startingRuntime,
            status: "Starting local AI",
            detail: "Looking for a local Qwen model and preparing BlackHaven AI.",
            progress: 0.22,
            busy: true,
            ready: false
        )

        guard let llamaServerBinaryPath = Self.resolvedLlamaServerBinaryPath() else {
            let existingOllamaRuntimeReady = await Self.isExistingOllamaRuntimeAvailable(
                endpoint: Self.defaultOllamaEndpointURL(),
                model: preferredModel,
                timeoutSeconds: 5
            )
            if existingOllamaRuntimeReady {
                let ollamaEndpoint = Self.defaultOllamaEndpointURL()
                let modelName = Self.resolvedInstalledOllamaModelName(preferredModel: preferredModel) ?? preferredModel
                routeLocalInference(
                    to: ollamaEndpoint,
                    model: modelName,
                    statusDetail: "BlackHaven found your existing Ollama runtime and routed local AI through it."
                )
                setLocalRuntimeHealth(
                    statusCode: .ready,
                    status: "Local AI ready",
                    detail: "Legacy Ollama runtime is running locally with model \(preferredModel).",
                    progress: 1.0,
                    busy: false,
                    ready: true
                )
                appendOutput("Detected active legacy Ollama runtime (\(preferredModel)).")
                return
            }

            setLocalRuntimeHealth(
                statusCode: .error,
                status: "Local AI needs attention",
                detail: "This build is missing the bundled llama-server runtime.",
                progress: 0.0,
                busy: false,
                ready: false,
                lastError: "Bundled llama-server runtime missing from app bundle."
            )
            return
        }

        var discoveredModel = Self.resolvedAvailableLlamaModel(
            explicitFileName: ProcessInfo.processInfo.environment["ATLAS_LLM_BUNDLED_MODEL_FILE"],
            fallbackFileName: ProcessInfo.processInfo.environment["ATLAS_LLM_HF_FILE"] ?? "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
        )
        if discoveredModel == nil,
           let ollamaBlobPath = Self.resolvedOllamaModelBlobPath(modelAlias: preferredModel)
        {
            discoveredModel = ResolvedLocalModel(
                path: ollamaBlobPath,
                sourceLabel: "the local Ollama model library"
            )
        }
        let bundledModelPath = discoveredModel?.path
        if let discoveredModel {
            appendOutput("Found your local Qwen model in \(discoveredModel.sourceLabel). Starting AI now.")
        } else {
            appendOutput("Qwen was not found locally. BlackHaven will download it in the app now.")
        }

        if await Self.isLocalRuntimeReadyForInference(
            endpoint: endpoint,
            model: preferredModel,
            timeoutSeconds: 3
        ) {
            appendOutput("Enhanced on-device AI runtime ready (\(preferredModel)).")
            setLocalRuntimeHealth(
                statusCode: .ready,
                status: "Local AI ready",
                detail: "Model \(preferredModel) is active on \(endpoint.host ?? "localhost").",
                progress: 1.0,
                busy: false,
                ready: true
            )
            return
        }

        let launchTiers = Self.managedLocalRuntimeRetryPlan(modelAlias: preferredModel)
        var tierFailures: [String] = []

        for (tierIndex, tier) in launchTiers.enumerated() {
            stopManagedLocalRuntimeProcess(force: true)
            let tierDetailPrefix = bundledModelPath == nil
                ? "Qwen 2.5 7B is not on this Mac yet. BlackHaven is downloading it in the app now."
                : "Found your local Qwen model in \(discoveredModel?.sourceLabel ?? "local storage"). Starting BlackHaven AI now."
            let tierDetail = tierIndex == 0
                ? tierDetailPrefix
                : "BlackHaven is retrying local AI with a lighter \(tier.displayName) profile."
            setLocalRuntimeHealth(
                statusCode: bundledModelPath == nil ? .downloadingModel : .warmingModel,
                status: tierIndex == 0
                    ? (bundledModelPath == nil ? "Downloading model" : "Warming local AI")
                    : "Retrying local AI",
                detail: tierDetail,
                progress: bundledModelPath == nil ? 0.12 : 0.32,
                busy: true,
                ready: false
            )

            if tierIndex > 0 {
                appendOutput("Retrying local AI with the \(tier.displayName) profile.")
            }

            if let launchError = startManagedLlamaServerProcess(
                binaryPath: llamaServerBinaryPath,
                endpoint: endpoint,
                modelAlias: preferredModel,
                bundledModelPath: bundledModelPath,
                tier: tier
            ) {
                tierFailures.append("\(tier.displayName): \(launchError)")
                appendOutput(launchError)
                continue
            }

            if await monitorManagedLocalRuntimeStartup(
                endpoint: endpoint,
                preferredModel: preferredModel,
                bundledModelPath: bundledModelPath,
                tier: tier
            ) {
                appendOutput("Enhanced on-device AI runtime ready (\(preferredModel)).")
                setLocalRuntimeHealth(
                    statusCode: .ready,
                    status: "Local AI ready",
                    detail: "Model \(preferredModel) is active on \(endpoint.host ?? "localhost").",
                    progress: 1.0,
                    busy: false,
                    ready: true
                )
                return
            }

            tierFailures.append("\(tier.displayName): \(managedRuntimeLastLogLine() ?? "warmup did not finish in time")")
            appendOutput("The \(tier.displayName) local AI profile did not finish warming up in time.")
        }

        if let ollamaBinaryPath = Self.resolvedOllamaBinaryPath(),
           let installedOllamaModel = Self.resolvedInstalledOllamaModelName(preferredModel: preferredModel)
        {
            let ollamaEndpoint = Self.defaultOllamaEndpointURL()
            appendOutput("BlackHaven is falling back to the local Ollama install already on this Mac.")
            if await Self.ensureOllamaRuntimeReady(
                binaryPath: ollamaBinaryPath,
                endpoint: ollamaEndpoint,
                model: installedOllamaModel,
                timeoutSeconds: 8
            ) {
                routeLocalInference(
                    to: ollamaEndpoint,
                    model: installedOllamaModel,
                    statusDetail: "BlackHaven is routing local inference through the Qwen model already installed in Ollama."
                )
                appendOutput("Started local Qwen from the existing Ollama install on this Mac.")
                setLocalRuntimeHealth(
                    statusCode: .ready,
                    status: "Local AI ready",
                    detail: "Using the Qwen model already installed on this Mac.",
                    progress: 1.0,
                    busy: false,
                    ready: true
                )
                return
            }
        }

        let combinedFailure = tierFailures.last ?? "Local AI warmup is taking longer than expected."
        setLocalRuntimeHealth(
            statusCode: .degraded,
            status: "Local AI retrying",
            detail: localModelRuntimeDetail,
            progress: max(localModelRuntimeProgress, 0.32),
            busy: true,
            ready: false,
            lastError: combinedFailure
        )
    }

    private func startManagedLlamaServerProcess(
        binaryPath: String,
        endpoint: URL,
        modelAlias: String,
        bundledModelPath: String?,
        tier: ManagedLlamaServerLaunchTier
    ) -> String? {
        let host = endpoint.host ?? "127.0.0.1"
        let port = endpoint.port ?? 8080
        let model = modelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeAlias = model.isEmpty ? "qwen2.5:7b" : model
        let repo = ProcessInfo.processInfo.environment["ATLAS_LLM_HF_REPO"]
            ?? "bartowski/Qwen2.5-7B-Instruct-GGUF"
        let file = ProcessInfo.processInfo.environment["ATLAS_LLM_HF_FILE"]
            ?? "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
        let profile = Self.managedLlamaServerLaunchProfile(modelAlias: safeAlias, tier: tier)
        let cacheRootURL = Self.managedLocalAIStorageRoot()
        let hfHomeURL = cacheRootURL.appendingPathComponent("hf-home", isDirectory: true)
        let xdgCacheURL = cacheRootURL.appendingPathComponent("xdg-cache", isDirectory: true)
        let llamaCacheURL = cacheRootURL.appendingPathComponent("llama.cpp", isDirectory: true)

        let fm = FileManager.default
        let logURL = fm.temporaryDirectory
            .appendingPathComponent("atlas-llama-server-\(UUID().uuidString)")
            .appendingPathExtension("log")
        fm.createFile(atPath: logURL.path, contents: nil)
        managedLocalRuntimeLogURL = logURL
        guard let outputHandle = try? FileHandle(forWritingTo: logURL) else {
            return "BlackHaven could not create a local AI runtime log file."
        }

        do {
            try? fm.createDirectory(at: hfHomeURL, withIntermediateDirectories: true, attributes: nil)
            try? fm.createDirectory(at: xdgCacheURL, withIntermediateDirectories: true, attributes: nil)
            try? fm.createDirectory(at: llamaCacheURL, withIntermediateDirectories: true, attributes: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            var environment = ProcessInfo.processInfo.environment
            environment["HF_HOME"] = hfHomeURL.path
            environment["XDG_CACHE_HOME"] = xdgCacheURL.path
            environment["LLAMA_CACHE"] = llamaCacheURL.path
            process.environment = environment
            process.arguments = [
                "--host", host,
                "--port", String(port),
                "--alias", safeAlias,
                "--ctx-size", String(profile.ctxSize),
                "--parallel", String(profile.parallelSlots),
                "--threads", String(profile.threads),
                "--threads-batch", String(profile.batchThreads),
                "--threads-http", String(profile.httpThreads),
                "--batch-size", String(profile.batchSize),
                "--ubatch-size", String(profile.ubatchSize),
                "--cache-reuse", String(profile.cacheReuse),
                "--prio", "2",
                "--prio-batch", "2",
                "--flash-attn", profile.flashAttention ? "on" : "auto",
                "--n-gpu-layers", "auto",
                "--metrics",
                "--jinja",
            ]
            if let bundledModelPath {
                process.arguments?.append(contentsOf: ["--model", bundledModelPath])
            } else {
                process.arguments?.append(contentsOf: ["--hf-repo", repo, "--hf-file", file])
            }
            if profile.useMlock {
                process.arguments?.append("--mlock")
            }
            if let reasoningFormat = profile.reasoningFormat {
                process.arguments?.append(contentsOf: ["--reasoning-format", reasoningFormat])
            }
            process.standardOutput = outputHandle
            process.standardError = outputHandle
            try process.run()
            managedLocalRuntimeProcess = process
            return nil
        } catch {
            let nsError = error as NSError
            let message = "BlackHaven could not start local AI. \(nsError.domain) \(nsError.code): \(error.localizedDescription)"
            if let data = "\(message)\n".data(using: .utf8) {
                try? outputHandle.write(contentsOf: data)
            }
            try? outputHandle.close()
            return message
        }
    }

    private func monitorManagedLocalRuntimeStartup(
        endpoint: URL,
        preferredModel: String,
        bundledModelPath: String?,
        tier: ManagedLlamaServerLaunchTier
    ) async -> Bool {
        let timeoutAt = Date().addingTimeInterval(bundledModelPath == nil ? 60 * 20 : 90)
        let warmupStartedAt = Date()
        let recordedWarmupSeconds = Self.recordedManagedLocalRuntimeWarmupSeconds()
        let readinessProbeTimeout = max(
            bundledModelPath == nil ? 12 : 18,
            min(60, Int(recordedWarmupSeconds.rounded(.up)) + 6)
        )
        var lastObservedProgress = localModelRuntimeProgress
        var lastObservedLogLine = ""
        var lastObservedDownloadBytes: Int64 = 0
        var lastProgressAt = Date()
        var previousSample: (time: Date, downloaded: Int64)?
        var consecutiveWarmupMisses = 0

        while Date() < timeoutAt {
            if await Self.isLocalRuntimeReadyForInference(
                endpoint: endpoint,
                model: preferredModel,
                timeoutSeconds: readinessProbeTimeout
            ) {
                Self.recordManagedLocalRuntimeWarmupSeconds(Date().timeIntervalSince(warmupStartedAt))
                setLocalModelDownloadTelemetry(
                    downloadedBytes: localModelDownloadTotalBytes,
                    totalBytes: localModelDownloadTotalBytes,
                    etaSeconds: 0
                )
                return true
            }
            consecutiveWarmupMisses += 1

            if let process = managedLocalRuntimeProcess, !process.isRunning {
                let exitCode = process.terminationStatus
                let lastLogLine = managedRuntimeLastLogLine() ?? "Local AI process exited unexpectedly."
                setLocalRuntimeHealth(
                    statusCode: .error,
                    status: "Local AI needs attention",
                    detail: "\(tier.displayName.capitalized) profile failed: \(lastLogLine)",
                    progress: 0.0,
                    busy: false,
                    ready: false,
                    lastError: "Bundled llama-server exited with code \(exitCode)."
                )
                return false
            }

            let telemetry = managedRuntimeDownloadTelemetry()
            if let detail = telemetry.detail, !detail.isEmpty {
                let bytesProgress = telemetry.totalBytes > 0 ? Double(telemetry.downloadedBytes) / Double(telemetry.totalBytes) : 0.0
                let percentProgress = telemetry.percent
                let realProgress = max(bytesProgress, percentProgress)
                if telemetry.downloadedBytes > 0, telemetry.totalBytes > 0 {
                    let now = Date()
                    if let previousSample, telemetry.downloadedBytes > previousSample.downloaded {
                        let elapsed = now.timeIntervalSince(previousSample.time)
                        let delta = Double(telemetry.downloadedBytes - previousSample.downloaded)
                        if elapsed > 0.4, delta > 0 {
                            let bytesPerSecond = delta / elapsed
                            let remaining = Double(max(0, telemetry.totalBytes - telemetry.downloadedBytes))
                            let eta = bytesPerSecond > 0 ? Int((remaining / bytesPerSecond).rounded()) : nil
                            setLocalModelDownloadTelemetry(
                                downloadedBytes: telemetry.downloadedBytes,
                                totalBytes: telemetry.totalBytes,
                                etaSeconds: eta
                            )
                        }
                    } else {
                        setLocalModelDownloadTelemetry(
                            downloadedBytes: telemetry.downloadedBytes,
                            totalBytes: telemetry.totalBytes,
                            etaSeconds: nil
                        )
                    }
                    previousSample = (time: now, downloaded: telemetry.downloadedBytes)
                }

                let stagedProgress = bundledModelPath == nil
                    ? max(0.12, min(0.94, 0.12 + (realProgress * 0.78)))
                    : max(0.32, min(0.94, 0.32 + (realProgress * 0.58)))
                setLocalRuntimeHealth(
                    statusCode: bundledModelPath == nil ? .downloadingModel : .warmingModel,
                    status: bundledModelPath == nil ? "Downloading model" : "Warming local AI",
                    detail: detail,
                    progress: stagedProgress,
                    busy: true,
                    ready: false
                )

                if detail != lastObservedLogLine || telemetry.downloadedBytes > lastObservedDownloadBytes || stagedProgress > lastObservedProgress {
                    lastObservedProgress = stagedProgress
                    lastObservedLogLine = detail
                    lastObservedDownloadBytes = telemetry.downloadedBytes
                    lastProgressAt = Date()
                    consecutiveWarmupMisses = 0
                }
            } else if let lastLogLine = managedRuntimeLastLogLine(), !lastLogLine.isEmpty {
                if lastLogLine != lastObservedLogLine {
                    lastObservedLogLine = lastLogLine
                    lastProgressAt = Date()
                    consecutiveWarmupMisses = 0
                }
                setLocalRuntimeHealth(
                    statusCode: bundledModelPath == nil ? .downloadingModel : .warmingModel,
                    status: bundledModelPath == nil ? "Downloading model" : "Warming local AI",
                    detail: lastLogLine,
                    progress: max(lastObservedProgress, bundledModelPath == nil ? 0.12 : 0.32),
                    busy: true,
                    ready: false
                )
            }

            if Date().timeIntervalSince(lastProgressAt) > 180 {
                let fallbackDetail = managedRuntimeLastLogLine() ?? "The local AI runtime is not reporting progress yet."
                setLocalRuntimeHealth(
                    statusCode: .degraded,
                    status: "Local AI retrying",
                    detail: "\(tier.displayName.capitalized) profile stalled: \(fallbackDetail)",
                    progress: max(lastObservedProgress, bundledModelPath == nil ? 0.12 : 0.32),
                    busy: true,
                    ready: false,
                    lastError: "Local AI startup stalled without fresh progress."
                )
                return false
            }

            let backoffSeconds = min(3.0, 0.7 + (Double(min(consecutiveWarmupMisses, 6)) * 0.35))
            try? await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
        }

        return false
    }

    private func stopManagedLocalRuntimeProcess(force: Bool = false) {
        guard let process = managedLocalRuntimeProcess else { return }
        defer {
            if !process.isRunning {
                managedLocalRuntimeProcess = nil
            }
        }
        guard process.isRunning else {
            managedLocalRuntimeProcess = nil
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(force ? 1.5 : 3.0)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if force && process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        if !process.isRunning {
            managedLocalRuntimeProcess = nil
        }
    }

    private func pullOllamaModelWithProgress(
        binaryPath: String,
        model: String,
        timeoutSeconds: Int
    ) async -> Bool {
        setLocalModelDownloadTelemetry(downloadedBytes: 0, totalBytes: 0, etaSeconds: nil)
        let fm = FileManager.default
        let token = UUID().uuidString
        let outputURL = fm.temporaryDirectory
            .appendingPathComponent("atlas-ollama-pull-\(token)")
            .appendingPathExtension("log")
        fm.createFile(atPath: outputURL.path, contents: nil)
        defer { try? fm.removeItem(at: outputURL) }

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return false
        }
        defer { try? outputHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["pull", model]
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        let timeoutAt = Date().addingTimeInterval(TimeInterval(max(30, timeoutSeconds)))
        var latestLine = ""
        var latestPercent = 0.0
        var latestDownloadedBytes: Int64 = 0
        var latestTotalBytes: Int64 = 0
        var latestETASeconds: Int?
        var previousSample: (time: Date, downloaded: Int64)?

        do {
            try process.run()
        } catch {
            return false
        }

        while process.isRunning {
            if Date() >= timeoutAt {
                process.terminate()
                return false
            }

            outputHandle.synchronizeFile()
            if let data = try? Data(contentsOf: outputURL),
               let text = String(data: data, encoding: .utf8)
            {
                let lines = text
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                if let tail = lines.last {
                    latestLine = tail.count > 220 ? String(tail.prefix(220)) : tail
                }
                for line in lines.suffix(18) {
                    if let percent = Self.extractPercentage(from: line) {
                        latestPercent = max(latestPercent, percent)
                    }
                    if let byteProgress = Self.extractByteProgress(from: line) {
                        latestDownloadedBytes = max(latestDownloadedBytes, byteProgress.downloaded)
                        latestTotalBytes = max(latestTotalBytes, byteProgress.total)
                    }
                }
            }

            if latestTotalBytes > 0, latestDownloadedBytes > 0 {
                let now = Date()
                if let previousSample, latestDownloadedBytes > previousSample.downloaded {
                    let elapsed = now.timeIntervalSince(previousSample.time)
                    let delta = Double(latestDownloadedBytes - previousSample.downloaded)
                    if elapsed > 0.2, delta > 0 {
                        let bytesPerSecond = delta / elapsed
                        let remaining = Double(max(0, latestTotalBytes - latestDownloadedBytes))
                        latestETASeconds = bytesPerSecond > 0 ? Int((remaining / bytesPerSecond).rounded()) : nil
                    }
                }
                previousSample = (time: now, downloaded: latestDownloadedBytes)
            }

            let ratioFromBytes = latestTotalBytes > 0 ? Double(latestDownloadedBytes) / Double(latestTotalBytes) : 0.0
            let stagedProgress = 0.55 + (max(latestPercent, ratioFromBytes) * 0.4)
            setLocalModelRuntimeProgress(
                status: "Downloading model",
                detail: latestLine.isEmpty
                    ? "Downloading \(model). This can take several minutes on first launch."
                    : latestLine,
                progress: stagedProgress,
                busy: true,
                ready: false
            )
            setLocalModelDownloadTelemetry(
                downloadedBytes: latestDownloadedBytes,
                totalBytes: latestTotalBytes,
                etaSeconds: latestETASeconds
            )
            try? await Task.sleep(nanoseconds: 220_000_000)
        }

        outputHandle.synchronizeFile()
        if let data = try? Data(contentsOf: outputURL),
           let text = String(data: data, encoding: .utf8)
        {
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let tail = lines.last {
                latestLine = tail.count > 220 ? String(tail.prefix(220)) : tail
            }
        }

        let success = process.terminationStatus == 0
        if success {
            if latestTotalBytes > 0 {
                setLocalModelDownloadTelemetry(
                    downloadedBytes: latestTotalBytes,
                    totalBytes: latestTotalBytes,
                    etaSeconds: 0
                )
            }
            setLocalModelRuntimeProgress(
                status: "Download complete",
                detail: "Model \(model) downloaded and verified.",
                progress: 0.96,
                busy: true,
                ready: false
            )
        } else if !latestLine.isEmpty {
            setLocalModelRuntimeProgress(
                status: "Download failed",
                detail: latestLine,
                progress: 0.0,
                busy: false,
                ready: false
            )
            setLocalModelDownloadTelemetry(downloadedBytes: latestDownloadedBytes, totalBytes: latestTotalBytes, etaSeconds: nil)
        }

        return success
    }

    private func managedRuntimeLastLogLine() -> String? {
        guard let logURL = managedLocalRuntimeLogURL,
              let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let lastLine = lines.last(where: { !$0.isEmpty }) else {
            return nil
        }
        return lastLine
    }

    private func managedRuntimeDownloadTelemetry() -> (detail: String?, percent: Double, downloadedBytes: Int64, totalBytes: Int64) {
        guard let logURL = managedLocalRuntimeLogURL,
              let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return (detail: nil, percent: 0.0, downloadedBytes: 0, totalBytes: 0)
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let detail = lines.last.map { $0.count > 220 ? String($0.prefix(220)) : $0 }
        var percent = 0.0
        var downloadedBytes: Int64 = 0
        var totalBytes: Int64 = 0

        for line in lines.suffix(24) {
            if let parsedPercent = Self.extractPercentage(from: line) {
                percent = max(percent, parsedPercent)
            }
            if let parsedBytes = Self.extractByteProgress(from: line) {
                downloadedBytes = max(downloadedBytes, parsedBytes.downloaded)
                totalBytes = max(totalBytes, parsedBytes.total)
            }
        }

        return (detail: detail, percent: percent, downloadedBytes: downloadedBytes, totalBytes: totalBytes)
    }

    nonisolated private static func extractPercentage(from line: String) -> Double? {
        let pattern = #"(\d{1,3})(?:\.\d+)?\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: line),
              let value = Double(line[valueRange])
        else {
            return nil
        }
        return min(1.0, max(0.0, value / 100.0))
    }

    nonisolated private static func extractByteProgress(from line: String) -> (downloaded: Int64, total: Int64)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(B|KB|KIB|MB|MIB|GB|GIB|TB|TIB)\s*/\s*(\d+(?:\.\d+)?)\s*(B|KB|KIB|MB|MIB|GB|GIB|TB|TIB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 5,
              let downloadedValueRange = Range(match.range(at: 1), in: line),
              let downloadedUnitRange = Range(match.range(at: 2), in: line),
              let totalValueRange = Range(match.range(at: 3), in: line),
              let totalUnitRange = Range(match.range(at: 4), in: line),
              let downloadedValue = Double(line[downloadedValueRange]),
              let totalValue = Double(line[totalValueRange])
        else {
            return nil
        }

        let downloadedUnit = String(line[downloadedUnitRange])
        let totalUnit = String(line[totalUnitRange])
        let downloadedBytes = Self.byteCount(value: downloadedValue, unit: downloadedUnit)
        let totalBytes = Self.byteCount(value: totalValue, unit: totalUnit)
        guard totalBytes > 0 else { return nil }
        return (downloaded: min(downloadedBytes, totalBytes), total: totalBytes)
    }

    nonisolated private static func byteCount(value: Double, unit: String) -> Int64 {
        let normalized = unit.uppercased()
        let multiplier: Double
        switch normalized {
        case "TIB":
            multiplier = 1_099_511_627_776
        case "TB":
            multiplier = 1_000_000_000_000
        case "GIB":
            multiplier = 1_073_741_824
        case "GB":
            multiplier = 1_000_000_000
        case "MIB":
            multiplier = 1_048_576
        case "MB":
            multiplier = 1_000_000
        case "KIB":
            multiplier = 1_024
        case "KB":
            multiplier = 1_000
        default:
            multiplier = 1
        }
        return Int64(max(0, (value * multiplier).rounded()))
    }

    nonisolated private static func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private func guidedLearningRuntimeStatusLine() -> String {
        let activation = isGuidedLearningRuntimeActive ? "active" : "locked"
        let ollamaHost = guidedLearningOllamaEndpointURL?.host ?? "invalid-endpoint"
        let kiwixHost = guidedLearningKiwixBaseURL?.host ?? "invalid-endpoint"
        return "Guided learning \(activation). Kiwix host: \(kiwixHost) · Ollama host: \(ollamaHost) · model: \(guidedLearningOllamaModelName)."
    }

    private struct AdaptiveReasoningPressure {
        let depthDelta: Int
        let tokenScale: Double
        let timeoutScale: Double
        let summary: String
    }

    private var localAggressivePerformanceModeEnabled: Bool { true }

    private func adaptiveReasoningPressure() -> AdaptiveReasoningPressure {
        let processInfo = ProcessInfo.processInfo
        let thermal = processInfo.thermalState
        let queueDepth = promptQueue.filter { $0.status == .queued || $0.status == .running }.count
        let inFlight = localInferenceInFlightCount
        let latencyAverage = recentLocalInferenceDurationsSeconds.isEmpty
            ? 0.0
            : recentLocalInferenceDurationsSeconds.reduce(0.0, +) / Double(recentLocalInferenceDurationsSeconds.count)

        var depthDelta = 0
        var tokenScale = 1.0
        var timeoutScale = 1.0
        var tags: [String] = []

        switch thermal {
        case .serious, .critical:
            depthDelta -= 2
            tokenScale *= 0.72
            timeoutScale *= 0.85
            tags.append("thermal-high")
        case .fair where !localAggressivePerformanceModeEnabled:
            depthDelta -= 1
            tokenScale *= 0.88
            tags.append("thermal-fair")
        default:
            break
        }

        if isResourceConstrained() {
            depthDelta -= 1
            tokenScale *= 0.9
            tags.append("power-save")
        }
        if inFlight >= 2 {
            depthDelta -= 1
            timeoutScale *= 0.9
            tags.append("parallel-load")
        }
        if queueDepth >= 4 {
            depthDelta -= 1
            timeoutScale *= 0.86
            tags.append("queue-pressure")
        } else if queueDepth == 0,
                  inFlight == 0,
                  thermal == .nominal,
                  latencyAverage > 0,
                  latencyAverage < 6.0,
                  !isResourceConstrained()
        {
            depthDelta += 1
            tokenScale *= 1.08
            timeoutScale *= 1.05
            tags.append("headroom")
        }

        if latencyAverage >= 20.0 {
            depthDelta -= 1
            timeoutScale *= 0.88
            tags.append("latency-high")
        } else if latencyAverage > 0, latencyAverage <= 5.0, queueDepth <= 1, thermal == .nominal {
            depthDelta += 1
            tokenScale *= 1.05
            tags.append("latency-low")
        }

        let summary = tags.isEmpty ? "balanced" : tags.joined(separator: ", ")
        return AdaptiveReasoningPressure(
            depthDelta: depthDelta,
            tokenScale: max(localAggressivePerformanceModeEnabled ? 0.8 : 0.65, min(localAggressivePerformanceModeEnabled ? 1.35 : 1.2, tokenScale)),
            timeoutScale: max(localAggressivePerformanceModeEnabled ? 0.9 : 0.75, min(localAggressivePerformanceModeEnabled ? 1.25 : 1.15, timeoutScale)),
            summary: summary
        )
    }

    private func recordLocalInferenceDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        recentLocalInferenceDurationsSeconds.append(seconds)
        if recentLocalInferenceDurationsSeconds.count > 12 {
            recentLocalInferenceDurationsSeconds.removeFirst(recentLocalInferenceDurationsSeconds.count - 12)
        }
    }

    private func localReasoningProfile(
        for domain: LocalInferenceReasoningDomain,
        timeoutSeconds: Int
    ) -> LocalInferenceReasoningProfile {
        let constrained = isResourceConstrained()
        let pressure = adaptiveReasoningPressure()
        let basePasses = constrained ? 1 : (localAggressivePerformanceModeEnabled ? 3 : 2)
        let passCap: Int
        switch domain {
        case .structuredJSON:
            passCap = localAggressivePerformanceModeEnabled ? 3 : 2
        case .briefing:
            passCap = localAggressivePerformanceModeEnabled ? 3 : 2
        case .general:
            passCap = localAggressivePerformanceModeEnabled ? 4 : 2
        case .coding:
            passCap = localAggressivePerformanceModeEnabled ? 4 : 3
        }
        let analysisPasses = min(passCap, max(1, basePasses + pressure.depthDelta))
        let candidateTimeoutBase: Int
        let synthesisTimeoutBase: Int
        if domain == .general {
            candidateTimeoutBase = max(4, timeoutSeconds)
            synthesisTimeoutBase = max(candidateTimeoutBase, timeoutSeconds + (constrained ? 1 : 2))
        } else {
            candidateTimeoutBase = max(6, timeoutSeconds + (constrained ? 1 : 2))
            synthesisTimeoutBase = max(candidateTimeoutBase, timeoutSeconds + (constrained ? 2 : 4))
        }

        let candidateTokens: Int
        let synthesisTokens: Int
        switch domain {
        case .structuredJSON:
            candidateTokens = constrained ? 720 : 1200
            synthesisTokens = constrained ? 960 : 1600
        case .briefing:
            candidateTokens = constrained ? 760 : 1300
            synthesisTokens = constrained ? 980 : 1700
        case .coding:
            candidateTokens = constrained ? 1400 : 2400
            synthesisTokens = constrained ? 1800 : 3200
        case .general:
            candidateTokens = constrained ? 1000 : 1700
            synthesisTokens = constrained ? 1400 : 2400
        }

        let adjustedCandidateTokens = max(420, Int(Double(candidateTokens) * pressure.tokenScale))
        let adjustedSynthesisTokens = max(560, Int(Double(synthesisTokens) * pressure.tokenScale))
        let candidateTimeout = max(6, Int(Double(candidateTimeoutBase) * pressure.timeoutScale))
        let synthesisTimeout = max(candidateTimeout, Int(Double(synthesisTimeoutBase) * pressure.timeoutScale))
        localReasoningDepthStatus = "Adaptive depth: \(analysisPasses) pass(es) · \(pressure.summary)"

        return LocalInferenceReasoningProfile(
            analysisPasses: analysisPasses,
            candidateTimeoutSeconds: candidateTimeout,
            synthesisTimeoutSeconds: synthesisTimeout,
            candidateMaxTokens: adjustedCandidateTokens,
            synthesisMaxTokens: adjustedSynthesisTokens
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
        let preferredModels = localInferencePreferredModels
        let resolvedLocalModel =
            preferredModels
                .compactMap { candidate in
                    let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }
                    return Self.resolvedInstalledOllamaModelName(preferredModel: trimmed) ?? trimmed
                }
                .first
            ?? Self.locallyInstalledOllamaModels().sorted().first
            ?? preferred
        let modelOrder = [resolvedLocalModel]

        var plan = LocalInferenceRuntimePlan(
            modelOrder: modelOrder,
            reasoningMode: constrained ? "fast" : "max-perf",
            analysisPasses: constrained ? 1 : 2,
            temperature: min(0.95, max(0.0, fallbackTemperature)),
            maxTokens: max(220, fallbackMaxTokens),
            numCtx: constrained ? 16384 : 32768,
            timeoutSeconds: max(8, fallbackTimeoutSeconds),
            statusLine: "Fallback policy active (Rust policy unavailable)."
        )

        if let policy = await requestRustInferencePolicy(task: task, preferredModel: preferred) {
            plan = LocalInferenceRuntimePlan(
                modelOrder: [resolvedLocalModel],
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
        } else if task == "general_chat" {
            plan = LocalInferenceRuntimePlan(
                modelOrder: plan.modelOrder,
                reasoningMode: "fast-chat-max-perf",
                analysisPasses: min(3, max(2, plan.analysisPasses)),
                temperature: min(plan.temperature, 0.22),
                maxTokens: min(1800, max(1400, plan.maxTokens)),
                numCtx: min(max(24576, plan.numCtx), 32768),
                timeoutSeconds: min(max(16, plan.timeoutSeconds), 28),
                statusLine: plan.statusLine
            )
        }
        lastResolvedLocalInferenceModel = resolvedLocalModel
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
        let highPerformance = cores >= 8 && memoryGb >= 16 && !isResourceConstrained()
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

    private func rebuildKnowledgeSemanticIndex() {
        let filesByID = Dictionary(uniqueKeysWithValues: knowledgeFiles.map { ($0.id, $0) })
        let chunks: [IndexedKnowledgeChunk] = workspaceMemoryRecords.compactMap { record in
            guard record.source == .document,
                  let fileID = knowledgeFileID(from: record.key),
                  let file = filesByID[fileID]
            else {
                return nil
            }

            let tokens = semanticTokens(from: record.value)
            guard !tokens.isEmpty else { return nil }

            return IndexedKnowledgeChunk(
                fileID: fileID,
                fileName: file.fileName,
                fileType: file.fileType,
                chunkKey: record.key,
                text: record.value,
                tokens: tokens,
                tokenSet: Set(tokens),
                weight: record.weight,
                updatedAtUTC: record.updatedAtUTC
            )
        }

        knowledgeSemanticIndex = chunks
        knowledgeTokenDocumentFrequency = chunks.reduce(into: [String: Int]()) { partial, chunk in
            for token in chunk.tokenSet {
                partial[token, default: 0] += 1
            }
        }
    }

    private func knowledgeFileID(from key: String) -> String? {
        guard key.hasPrefix("document:") else { return nil }
        let remainder = key.dropFirst("document:".count)
        guard let separator = remainder.firstIndex(of: ":") else { return nil }
        let fileID = remainder[..<separator]
        return fileID.isEmpty ? nil : String(fileID)
    }

    private func semanticTokens(from text: String) -> [String] {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        let stopwords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "into", "your", "have", "will", "about", "after",
            "before", "should", "would", "could", "there", "their", "them", "they", "then", "than", "also", "just",
            "need", "needs", "using", "used", "use", "what", "when", "where", "which", "while", "more", "less",
            "very", "over", "under", "onto", "into", "across", "through", "still", "only", "like", "http", "https"
        ]

        return normalized
            .split(separator: " ")
            .map(String.init)
            .map(normalizeSemanticToken)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }

    private func normalizeSemanticToken(_ token: String) -> String {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 4 else { return value }
        if value.hasSuffix("ing") {
            value.removeLast(3)
        } else if value.hasSuffix("ed") || value.hasSuffix("es") {
            value.removeLast(2)
        } else if value.hasSuffix("s") {
            value.removeLast()
        }
        return value
    }

    private func semanticChunkScore(_ chunk: IndexedKnowledgeChunk, queryTokens: [String], queryTokenSet: Set<String>) -> Double {
        guard !queryTokens.isEmpty else { return 0 }

        let totalChunks = max(1, knowledgeSemanticIndex.count)
        let chunkLower = chunk.text.lowercased()
        let filenameTokens = Set(semanticTokens(from: chunk.fileName))

        var score = 0.0
        var matched = 0
        for token in queryTokenSet {
            guard chunk.tokenSet.contains(token) || filenameTokens.contains(token) else { continue }
            let docFrequency = knowledgeTokenDocumentFrequency[token] ?? 0
            let idf = log(Double(totalChunks + 1) / Double(docFrequency + 1)) + 1.0
            let chunkFrequency = Double(chunk.tokens.filter { $0 == token }.count)
            score += (1.15 * idf) + min(0.9, chunkFrequency * 0.18)
            matched += 1
        }

        if matched == 0 {
            return 0
        }

        let orderedHits = queryTokens
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if orderedHits.count >= 8, chunkLower.contains(orderedHits.lowercased()) {
            score += 2.2
        }

        score += min(1.0, Double(matched) / Double(max(1, queryTokenSet.count))) * 1.4
        score += min(0.6, chunk.weight * 0.45)
        return score
    }

    private func semanticKnowledgeMatches(
        query: String,
        fileIDs: Set<String>,
        limit: Int
    ) -> [IndexedKnowledgeChunk] {
        let queryTokens = semanticTokens(from: query)
        let queryTokenSet = Set(queryTokens)
        guard !queryTokenSet.isEmpty else { return [] }

        return knowledgeSemanticIndex
            .filter { fileIDs.isEmpty || fileIDs.contains($0.fileID) }
            .map { chunk in
                (chunk, semanticChunkScore(chunk, queryTokens: queryTokens, queryTokenSet: queryTokenSet))
            }
            .filter { $0.1 > 0.01 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.updatedAtUTC > rhs.0.updatedAtUTC
                }
                return lhs.1 > rhs.1
            }
            .prefix(max(1, limit))
            .map(\.0)
    }

    private func knowledgeFilesContextDigest(maxLength: Int = 2200) -> String {
        let fileMeta = knowledgeFiles
            .prefix(12)
            .map { file in
                "- \(file.fileName) [\(file.fileType)] chunks:\(file.chunkCount) size:\(file.byteCount)"
            }
            .joined(separator: "\n")

        let previews = knowledgeFiles
            .sorted { $0.importedAtUTC > $1.importedAtUTC }
            .prefix(8)
            .map { "- \($0.fileName): \(sanitizeWorkspaceMemoryValue($0.preview, maxLength: 120))" }
            .joined(separator: "\n")

        let digest = """
        FILE INDEX
        \(fileMeta.isEmpty ? "- No uploaded knowledge files." : fileMeta)

        FILE PREVIEWS
        \(previews.isEmpty ? "- No indexed previews yet." : previews)
        """

        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    private func selectedKnowledgeFilesContextDigest(
        for profile: AtlasContextProfile,
        query: String? = nil,
        maxLength: Int = 2200
    ) -> String {
        guard profile.includeKnowledgeFiles else {
            return "Knowledge files disabled for this surface."
        }

        let enabledIDs = Set(profile.enabledKnowledgeFileIDs)
        let selectedFiles = knowledgeFiles.filter { enabledIDs.contains($0.id) }
        let selectedIDs = Set(selectedFiles.map(\.id))

        let fileMeta = selectedFiles
            .prefix(12)
            .map { file in
                "- \(file.fileName) [\(file.fileType)] chunks:\(file.chunkCount) size:\(file.byteCount)"
            }
            .joined(separator: "\n")

        let retrieval = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let queryTokens = semanticTokens(from: retrieval)
        let semanticMatches = retrieval.isEmpty ? [] : semanticKnowledgeMatches(query: retrieval, fileIDs: selectedIDs, limit: 8)
            .filter { chunk in
                let chunkLower = chunk.text.lowercased()
                return queryTokens.contains { token in
                    token.count >= 3 && chunkLower.contains(token)
                }
            }
        let fallbackChunks = retrieval.isEmpty ? [] : knowledgeSemanticIndex
            .filter { selectedIDs.contains($0.fileID) }
            .filter { chunk in
                let chunkLower = chunk.text.lowercased()
                return queryTokens.contains { token in
                    token.count >= 3 && chunkLower.contains(token)
                }
            }
            .sorted { lhs, rhs in
                if lhs.fileID == rhs.fileID {
                    return lhs.chunkKey < rhs.chunkKey
                }
                if lhs.updatedAtUTC == rhs.updatedAtUTC {
                    return lhs.fileName < rhs.fileName
                }
                return lhs.updatedAtUTC > rhs.updatedAtUTC
            }
            .prefix(2)
            .map { $0 }
        let rawDigestChunks = semanticMatches.isEmpty ? fallbackChunks : semanticMatches
        var seenDigestFileIDs = Set<String>()
        let digestChunks = rawDigestChunks.filter { chunk in
            seenDigestFileIDs.insert(chunk.fileID).inserted
        }
        let retrievedExcerpts = digestChunks
            .map { chunk in
                "- [\(chunk.fileName)] \(sanitizeWorkspaceMemoryValue(chunk.text, maxLength: 180))"
            }
            .joined(separator: "\n")
        let previews: String
        if !retrieval.isEmpty {
            previews = "- Query-guided retrieval mode active; generic file previews were omitted to keep context focused."
        } else {
            previews = selectedFiles
                .sorted { $0.importedAtUTC > $1.importedAtUTC }
                .prefix(6)
                .map { "- \($0.fileName): \(sanitizeWorkspaceMemoryValue($0.preview, maxLength: 120))" }
                .joined(separator: "\n")
        }

        let digest = """
        FILE INDEX
        \(fileMeta.isEmpty ? "- No enabled knowledge files." : fileMeta)

        FILE PREVIEWS
        \(previews.isEmpty ? "- No enabled knowledge file previews." : previews)

        RETRIEVED EVIDENCE
        \(retrieval.isEmpty ? "- Query-guided retrieval will activate when a prompt arrives." : (retrievedExcerpts.isEmpty ? "- No indexed chunks were available for this prompt yet." : retrievedExcerpts))
        """

        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    func knowledgeRetrievalDigest(
        for query: String,
        surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil,
        maxLength: Int = 1200
    ) -> String {
        let profile = contextProfile(for: surface, workspaceLane: workspaceLane)
        return selectedKnowledgeFilesContextDigest(for: profile, query: query, maxLength: maxLength)
    }

    private func accountUsageContextDigest(
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil,
        maxLength: Int = 1000
    ) -> String {
        let queueForSurface = promptQueue.filter { item in
            switch surface {
            case .workspace:
                return item.workspaceLane == workspaceLane
            case .command, .concierge, .survey:
                return item.workspaceLane == nil
            }
        }
        let completed = queueForSurface.filter { $0.status == .done }.count
        let failed = queueForSurface.filter { $0.status == .failed }.count
        let pending = queueForSurface.filter { $0.status == .queued || $0.status == .running }.count
        let activeWorkspaceCount = workspaceSessions.filter { workspaceLane == nil || $0.lane == workspaceLane }.count
        let recentWorkspaceTitles = workspaceSessions
            .filter { workspaceLane == nil || $0.lane == workspaceLane }
            .sorted { $0.updatedAtUTC > $1.updatedAtUTC }
            .prefix(3)
            .map(\.title)
            .joined(separator: " | ")
        let recentNotesCount = notes.count
        let recentUploads = knowledgeFiles
            .sorted { $0.importedAtUTC > $1.importedAtUTC }
            .prefix(3)
            .map(\.fileName)
            .joined(separator: " | ")

        let digest = """
        Account: \(accountLabel)
        Surface: \(surface.title)\(workspaceLane.map { " / \($0.title)" } ?? "")
        Queue status: completed \(completed), pending \(pending), failed \(failed)
        Recent notes in last 14d: \(recentNotesCount)
        Active workspace notebooks: \(activeWorkspaceCount)
        Recent workspace titles: \(recentWorkspaceTitles.isEmpty ? "none" : recentWorkspaceTitles)
        Recent uploads: \(recentUploads.isEmpty ? "none" : recentUploads)
        """

        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    private func recentUsageTrendDigest(
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil,
        maxLength: Int = 1000
    ) -> String {
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
        let recentQueue = promptQueue.filter { item in
            item.createdAt >= weekAgo && (
                surface == .workspace
                    ? item.workspaceLane == workspaceLane
                    : item.workspaceLane == nil
            )
        }
        let recentSessions = workspaceSessions.filter {
            $0.updatedAtUTC >= weekAgo && (workspaceLane == nil || $0.lane == workspaceLane)
        }
        let latestMemory = workspaceMemoryRecords
            .filter {
                $0.updatedAtUTC >= twoDaysAgo && (
                    surface != .workspace || $0.lane == nil || $0.lane == workspaceLane
                )
            }
            .sorted { $0.updatedAtUTC > $1.updatedAtUTC }
            .prefix(6)
            .map { "- [\($0.source.rawValue)] \(workspaceSignalLabel(for: $0.key)): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 82))" }
            .joined(separator: "\n")

        let digest = """
        Last 7d queue items: \(recentQueue.count)
        Last 7d workspace refreshes: \(recentSessions.count)
        Last 48h signal changes:
        \(latestMemory.isEmpty ? "- none" : latestMemory)
        """

        return sanitizeModelInput(digest, maxLength: maxLength)
    }

    private func contextEnvelope(
        for surface: AtlasContextSurface,
        workspaceLane: WorkspaceLane? = nil
    ) -> String {
        let profile = contextProfile(for: surface, workspaceLane: workspaceLane)
        var sections: [String] = []

        let defaultSystemPrompt: String = switch surface {
        case .command:
            "You are BlackHaven Command. Prioritize decisive, high-leverage execution guidance with strong risk control."
        case .survey:
            "You are BlackHaven Survey. Generate questions and interpretations that sharpen personalization without being repetitive."
        case .concierge:
            "You are BlackHaven Concierge. Act like a fast, practical operator assistant grounded in account context."
        case .workspace:
            "You are BlackHaven Workspace. Help the user execute within the selected lane using available notebook, memory, and file context."
        }
        sections.append(profile.customSystemPrompt.trimmedNil() ?? defaultSystemPrompt)

        if profile.includeAccountUsagePatterns {
            sections.append("ACCOUNT USAGE\n\(accountUsageContextDigest(for: surface, workspaceLane: workspaceLane))")
        }
        if profile.includeRecentUsageTrends {
            sections.append("RECENT USAGE TRENDS\n\(recentUsageTrendDigest(for: surface, workspaceLane: workspaceLane))")
        }
        if profile.includeSurveyAnswers {
            let recentSurvey = surveyAnswers
                .sorted { $0.key < $1.key }
                .suffix(18)
                .map { "- \($0.key): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 72))" }
                .joined(separator: "\n")
            sections.append("SURVEY SIGNALS\n\(recentSurvey.isEmpty ? "- none" : recentSurvey)")
        }
        if profile.includeNotes {
            let noteSlice = notes
                .prefix(10)
                .map { "- \($0.title): \(sanitizeWorkspaceMemoryValue($0.content, maxLength: 100))" }
                .joined(separator: "\n")
            sections.append("NOTES\n\(noteSlice.isEmpty ? "- none" : noteSlice)")
        }
        if profile.includeWorkspaceMemory {
            let memorySlice = workspaceMemoryRecords
                .filter { workspaceLane == nil || $0.lane == nil || $0.lane == workspaceLane }
                .sorted { lhs, rhs in
                    if lhs.updatedAtUTC == rhs.updatedAtUTC {
                        return lhs.weight > rhs.weight
                    }
                    return lhs.updatedAtUTC > rhs.updatedAtUTC
                }
                .prefix(10)
                .map { "- [\($0.source.rawValue)] \(workspaceSignalLabel(for: $0.key)): \(sanitizeWorkspaceMemoryValue($0.value, maxLength: 110))" }
                .joined(separator: "\n")
            sections.append("WORKSPACE MEMORY\n\(memorySlice.isEmpty ? "- none" : memorySlice)")
        }
        if profile.includeKnowledgeFiles {
            sections.append("ENABLED KNOWLEDGE FILES\n\(selectedKnowledgeFilesContextDigest(for: profile, maxLength: 1_400))")
        }

        return sanitizeModelInput(sections.joined(separator: "\n\n"), maxLength: 5_500)
    }

    private func composeDeepReasoningEnvelope(
        taskPrompt: String,
        domain: LocalInferenceReasoningDomain
    ) -> String {
        let contextBlock = domain.includeGlobalContext ? globalReasoningContextDigest() : ""
        let contextSection = contextBlock.isEmpty ? "" : "\n\(contextBlock)\n"

        return """
        You are Atlas local inference core running in medium reasoning depth mode.
        Compare alternatives quickly at medium reasoning depth before responding.
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
        preferredModelOverride: String? = nil,
        streamHandler: (@Sendable (String) -> Void)? = nil
    ) async -> String? {
        guard localInferenceEnabled else { return nil }
        if !localAISetupCompleted,
           !localModelRuntimeReady,
           let endpoint = localInferenceEndpointURL,
           isLoopbackHost(endpoint.host)
        {
            let fallbackEndpoint = localInferenceFailoverEndpointURL
            let fallbackReady = await Self.isFallbackLocalRuntimeReachable(
                primaryEndpoint: endpoint,
                fallbackEndpoint: fallbackEndpoint,
                preferredModel: localInferencePreferredModelName
            )
            if !fallbackReady {
                let warmupReady = await Self.waitForLocalRuntime(
                    endpoint: endpoint,
                    preferredModel: localInferencePreferredModelName,
                    timeoutSeconds: max(10, min(18, timeoutSeconds))
                )
                guard warmupReady else { return nil }
            }
        }
        let profile = localReasoningProfile(for: domain, timeoutSeconds: timeoutSeconds)
        let reasoningEnvelope = composeDeepReasoningEnvelope(taskPrompt: prompt, domain: domain)

        // Concierge/general flows must feel real-time on desktop; avoid heavy multi-pass fanout.
        if domain == .general {
            let singlePrompt = """
            \(prompt)

            Return one direct final answer only.
            """
            return await requestSingleLocalModelResponse(
                prompt: singlePrompt,
                timeoutSeconds: profile.candidateTimeoutSeconds,
                temperature: 0.2,
                maxTokens: profile.candidateMaxTokens,
                domain: domain,
                preferredModelOverride: preferredModelOverride,
                streamHandler: streamHandler
            )
        }

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
                domain: domain,
                preferredModelOverride: preferredModelOverride
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
            domain: domain,
            preferredModelOverride: preferredModelOverride
        ) {
            let trimmed = synthesis.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return bestReasoningCandidate(from: candidates, domain: domain)
    }

    nonisolated private static func isFallbackLocalRuntimeReachable(
        primaryEndpoint: URL,
        fallbackEndpoint: URL?,
        preferredModel: String
    ) async -> Bool {
        guard let fallbackEndpoint, fallbackEndpoint != primaryEndpoint else { return false }
        guard await isLocalRuntimeEndpointReachable(endpoint: fallbackEndpoint, timeoutSeconds: 2) else { return false }
        let host = (fallbackEndpoint.host ?? "").lowercased()
        guard host == "localhost" || host == "127.0.0.1" || host == "::1" else { return false }
        return await isExistingOllamaRuntimeAvailable(
            endpoint: fallbackEndpoint,
            model: preferredModel,
            timeoutSeconds: 2
        )
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

    private func localInferenceSystemPrompt(for domain: LocalInferenceReasoningDomain) -> String {
        if domain == .structuredJSON {
            return "You are Atlas local reasoning engine. Use the provided survey data, notes, account memory, and chat history context as primary grounding. Consider 2-4 plausible approaches internally, reason at moderate depth, and return only valid JSON."
        }

        return "You are Atlas local concierge reasoning engine. Use the provided survey data, notes, account memory, and chat history context as primary grounding. Consider 2-4 plausible approaches internally, reason at moderate depth, choose the strongest answer, and return only the final answer without exposing chain-of-thought."
    }

    private func requestSingleLocalModelResponse(
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        domain: LocalInferenceReasoningDomain,
        preferredModelOverride: String? = nil,
        streamHandler: (@Sendable (String) -> Void)? = nil
    ) async -> String? {
        let startedAt = Date()
        localInferenceInFlightCount += 1
        defer {
            localInferenceInFlightCount = max(0, localInferenceInFlightCount - 1)
            recordLocalInferenceDuration(Date().timeIntervalSince(startedAt))
        }

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
        let systemPrompt = localInferenceSystemPrompt(for: domain)
        let allowLegacyLocalFallback = true
        var attemptNotes: [String] = []
        let preferredModel = preferredModelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferredModelOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
            : localInferencePreferredModelName
        let preferredInstalledModel = Self.resolvedInstalledOllamaModelName(
            preferredModel: preferredModel
        ) ?? preferredModel
        let effectiveModelOrder: [String]
        if domain == .general,
           let endpoint = localInferenceEndpointURL,
           isLoopbackHost(endpoint.host)
        {
            effectiveModelOrder = Self.dedupModels([preferredInstalledModel])
        } else {
            effectiveModelOrder = Self.dedupModels(
                [preferredInstalledModel] + plan.modelOrder.filter {
                    $0.caseInsensitiveCompare(preferredInstalledModel) != .orderedSame
                }
            )
        }

        for model in effectiveModelOrder {
            lastResolvedLocalInferenceModel = model
            let primaryEndpoint = localInferenceEndpointURL
            let primaryEndpointReachable: Bool
            if let primaryEndpoint, isLoopbackHost(primaryEndpoint.host) {
                primaryEndpointReachable = await Self.isLocalRuntimeEndpointReachable(
                    endpoint: primaryEndpoint,
                    timeoutSeconds: 2
                )
            } else {
                primaryEndpointReachable = primaryEndpoint != nil
            }

            if allowLegacyLocalFallback,
               let fallbackEndpoint = localInferenceFailoverEndpointURL,
               fallbackEndpoint != primaryEndpoint,
               !primaryEndpointReachable,
               let fallbackOutput = await Self.runOpenAICompatiblePrompt(
                   endpoint: fallbackEndpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   systemPrompt: systemPrompt,
                   streamHandler: streamHandler
               )
            {
                lastLocalInferenceAttemptDetail = ""
                markLocalInferenceAvailable(endpoint: fallbackEndpoint, model: model)
                return fallbackOutput
            } else if allowLegacyLocalFallback,
                      let fallbackEndpoint = localInferenceFailoverEndpointURL,
                      fallbackEndpoint != primaryEndpoint,
                      !primaryEndpointReachable
            {
                attemptNotes.append("Fallback OpenAI route \(fallbackEndpoint.absoluteString) produced no completion within \(runtimeTimeout)s for model \(model)")
            }

            let shouldPreferOpenAIPrimaryRoute = primaryEndpoint?.path.contains("/v1/") == true

            if let endpoint = primaryEndpoint,
               primaryEndpointReachable,
               shouldPreferOpenAIPrimaryRoute,
               let localEndpointOutput = await Self.runOpenAICompatiblePrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   systemPrompt: systemPrompt,
                   streamHandler: streamHandler
               )
            {
                lastLocalInferenceAttemptDetail = ""
                markLocalInferenceAvailable(endpoint: endpoint, model: model)
                return localEndpointOutput
            } else if let endpoint = primaryEndpoint,
                      primaryEndpointReachable,
                      shouldPreferOpenAIPrimaryRoute
            {
                attemptNotes.append("Primary OpenAI route \(endpoint.absoluteString) produced no completion within \(runtimeTimeout)s for model \(model)")
                if allowLegacyLocalFallback,
                   let fallbackEndpoint = localInferenceFailoverEndpointURL,
                   fallbackEndpoint != primaryEndpoint,
                   let fallbackOutput = await Self.runOpenAICompatiblePrompt(
                       endpoint: fallbackEndpoint,
                       model: model,
                       prompt: prompt,
                       timeoutSeconds: runtimeTimeout,
                       temperature: runtimeTemperature,
                       maxTokens: runtimeMaxTokens,
                       systemPrompt: systemPrompt,
                       streamHandler: streamHandler
                   )
                {
                    lastLocalInferenceAttemptDetail = ""
                    markLocalInferenceAvailable(endpoint: fallbackEndpoint, model: model)
                    return fallbackOutput
                } else if allowLegacyLocalFallback,
                          let fallbackEndpoint = localInferenceFailoverEndpointURL,
                          fallbackEndpoint != primaryEndpoint
                {
                    attemptNotes.append("Fallback OpenAI route \(fallbackEndpoint.absoluteString) produced no completion within \(runtimeTimeout)s for model \(model)")
                }
                continue
            }

            if let endpoint = primaryEndpoint,
               primaryEndpointReachable,
               isLoopbackHost(endpoint.host),
               let ollamaNativeOutput = await Self.runOllamaNativeChatPrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   numCtx: runtimeNumCtx,
                   systemPrompt: systemPrompt,
                   streamHandler: streamHandler
               )
            {
                lastLocalInferenceAttemptDetail = ""
                markLocalInferenceAvailable(endpoint: endpoint, model: model)
                return ollamaNativeOutput
            } else if let endpoint = primaryEndpoint,
                      primaryEndpointReachable,
                      isLoopbackHost(endpoint.host)
            {
                attemptNotes.append("Primary Ollama route \(endpoint.absoluteString) produced no completion within \(runtimeTimeout)s for model \(model)")
            }

            if let endpoint = primaryEndpoint,
               primaryEndpointReachable,
               !shouldPreferOpenAIPrimaryRoute,
               let localEndpointOutput = await Self.runOpenAICompatiblePrompt(
                   endpoint: endpoint,
                   model: model,
                   prompt: prompt,
                   timeoutSeconds: runtimeTimeout,
                   temperature: runtimeTemperature,
                   maxTokens: runtimeMaxTokens,
                   systemPrompt: systemPrompt,
                   streamHandler: streamHandler
               )
            {
                lastLocalInferenceAttemptDetail = ""
                markLocalInferenceAvailable(endpoint: endpoint, model: model)
                return localEndpointOutput
            } else if let endpoint = primaryEndpoint,
                      primaryEndpointReachable
            {
                attemptNotes.append("Primary OpenAI route \(endpoint.absoluteString) produced no completion within \(runtimeTimeout)s for model \(model)")
            }

        }
        lastLocalInferenceAttemptDetail = sanitizeWorkspaceMemoryValue(
            attemptNotes.joined(separator: " · "),
            maxLength: 1_000
        )
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
        if promptQueue[idx].progress == nil || (promptQueue[idx].progress ?? 0) < 0.12 {
            promptQueue[idx].progress = 0.12
        }
        promptQueue[idx].lastCheckpointAt = Date()
        promptQueue[idx].checkpointNote = note
        persistPromptQueueToDisk()
    }

    private func updateRunningQueueItemStream(id: String, partial: String) {
        guard let idx = promptQueue.firstIndex(where: { $0.id == id }) else { return }
        guard promptQueue[idx].status == .running else { return }
        let cleaned = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        promptQueue[idx].streamedResponseText = Self.trimForDisplay(cleaned, maxChars: 18_000)
        promptQueue[idx].lastCheckpointAt = Date()
        promptQueue[idx].checkpointNote = "Streaming response..."
        let currentProgress = promptQueue[idx].progress ?? 0.12
        promptQueue[idx].progress = min(0.9, max(currentProgress, 0.2))
        persistPromptQueueToDisk()
    }

    private var shouldPauseQueueForInternetReconnect: Bool {
        inferencePipelineRequiresInternetConnection() && !isInternetConnectionAvailable
    }

    @discardableResult
    func updatePromptQueueItem(
        id: String,
        mutate: (inout PromptQueueItem) -> Void
    ) -> Bool {
        guard let idx = promptQueue.firstIndex(where: { $0.id == id }) else {
            return false
        }
        mutate(&promptQueue[idx])
        return true
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

    private func markQueueItemWaitingForInternetReconnect(id: String) {
        guard updatePromptQueueItem(id: id, mutate: { item in
            item.status = .queued
            item.completedAt = nil
            item.lastCheckpointAt = Date()
            let currentProgress = item.progress ?? 0.08
            item.progress = max(0.04, min(0.4, currentProgress * 0.92))
            item.checkpointNote = "No internet connection. Waiting to reconnect."
            item.errorMessage = nil
        }) else {
            return
        }
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

    nonisolated private static func waitForLocalRuntime(
        endpoint: URL,
        preferredModel: String,
        timeoutSeconds: Int
    ) async -> Bool {
        let timeoutAt = Date().addingTimeInterval(TimeInterval(max(2, timeoutSeconds)))
        while Date() < timeoutAt {
            if await isLocalRuntimeReadyForInference(
                endpoint: endpoint,
                model: preferredModel,
                timeoutSeconds: 3
            ) {
                return true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    nonisolated private static func isLocalRuntimeEndpointReachable(endpoint: URL, timeoutSeconds: Int) async -> Bool {
        await Task.detached(priority: .utility) {
            let config = URLSessionConfiguration.ephemeral
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = TimeInterval(max(1, timeoutSeconds))
            config.timeoutIntervalForResource = TimeInterval(max(1, timeoutSeconds) + 2)
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }

            let probePaths = ["/v1/models", "/api/tags", "/health", "/"]
            for probePath in probePaths {
                guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { continue }
                components.path = probePath
                components.query = nil
                guard let url = components.url else { continue }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = config.timeoutIntervalForRequest
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                do {
                    let (_, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { continue }
                    if (200 ... 299).contains(http.statusCode) {
                        return true
                    }
                } catch {
                    continue
                }
            }
            return false
        }.value
    }

    nonisolated private static func isLocalRuntimeReadyForInference(
        endpoint: URL,
        model: String,
        timeoutSeconds: Int
    ) async -> Bool {
        guard await isLocalRuntimeEndpointReachable(endpoint: endpoint, timeoutSeconds: timeoutSeconds) else {
            return false
        }

        let probePrompt = "Reply with exactly: READY"
        if let probe = await runOpenAICompatiblePrompt(
            endpoint: endpoint,
            model: model,
            prompt: probePrompt,
            timeoutSeconds: max(4, timeoutSeconds),
            temperature: 0.0,
            maxTokens: 32,
            systemPrompt: "Return only READY."
        ) {
            let normalized = probe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.contains("READY") {
                return true
            }
        }

        let host = (endpoint.host ?? "").lowercased()
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if isLoopback,
           let probe = await runOllamaNativeChatPrompt(
               endpoint: endpoint,
               model: model,
               prompt: probePrompt,
               timeoutSeconds: max(4, timeoutSeconds),
               temperature: 0.0,
               maxTokens: 32,
               numCtx: 4096,
               systemPrompt: "Return only READY."
           )
        {
            let normalized = probe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.contains("READY") {
                return true
            }
        }

        return false
    }

    nonisolated private static func isExistingOllamaRuntimeAvailable(
        endpoint: URL,
        model: String,
        timeoutSeconds: Int
    ) async -> Bool {
        guard await isLocalRuntimeEndpointReachable(endpoint: endpoint, timeoutSeconds: timeoutSeconds) else {
            return false
        }

        let host = (endpoint.host ?? "").lowercased()
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard isLoopback else { return false }

        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModel.isEmpty else { return false }

        guard let installedModels = await fetchOllamaInstalledModels(endpoint: endpoint, timeoutSeconds: timeoutSeconds) else {
            return false
        }

        return installedModels.contains(normalizedModel)
    }

    nonisolated private static func fetchOllamaInstalledModels(
        endpoint: URL,
        timeoutSeconds: Int
    ) async -> Set<String>? {
        await Task.detached(priority: .userInitiated) {
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                return nil
            }
            components.path = "/api/tags"
            components.query = nil
            guard let tagsURL = components.url else { return nil }

            var request = URLRequest(url: tagsURL)
            request.httpMethod = "GET"
            request.timeoutInterval = TimeInterval(max(3, timeoutSeconds))
            request.setValue("application/json", forHTTPHeaderField: "Accept")
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
                      (200 ... 299).contains(http.statusCode),
                      let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                else {
                    return nil
                }

                let models = decoded.models
                    .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                return Set(models)
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func defaultOllamaEndpointURL() -> URL {
        URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
    }

    nonisolated private static func resolvedInstalledOllamaModelName(preferredModel: String) -> String? {
        let installedModels = locallyInstalledOllamaModels()
        guard !installedModels.isEmpty else { return nil }

        let normalizedPreferred = normalizedSingleLocalModelSetting(preferredModel) ?? preferredModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let exact = installedModels.first(where: { $0 == normalizedPreferred }) {
            return exact
        }

        let normalizedWithoutLatest = normalizedPreferred.replacingOccurrences(of: ":latest", with: "")
        if normalizedWithoutLatest != normalizedPreferred,
           let exactWithoutLatest = installedModels.first(where: { $0 == normalizedWithoutLatest })
        {
            return exactWithoutLatest
        }

        if normalizedPreferred == "qwen2.5:7b",
           let exactQwen7b = installedModels.first(where: { $0 == "qwen2.5:7b" })
        {
            return exactQwen7b
        }

        if normalizedPreferred == "qwen2.5",
           let qwenLatest = installedModels.first(where: { $0 == "qwen2.5:latest" })
        {
            return qwenLatest
        }

        if let familyMatch = installedModels.first(where: { $0.hasPrefix(normalizedPreferred + ":") }) {
            return familyMatch
        }
        if normalizedWithoutLatest != normalizedPreferred,
           let familyMatch = installedModels.first(where: { $0.hasPrefix(normalizedWithoutLatest + ":") })
        {
            return familyMatch
        }

        return installedModels.sorted().first(where: { $0.hasPrefix("qwen2.5:7b") || $0 == "qwen2.5:7b" })
    }

    nonisolated private static func normalizedSingleLocalModelSetting(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let first = trimmed
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return first?.lowercased()
    }

    nonisolated private static func resolvedOllamaModelBlobPath(modelAlias: String) -> String? {
        guard let installedModel = resolvedInstalledOllamaModelName(preferredModel: modelAlias) else {
            return nil
        }

        let parts = installedModel.split(separator: ":", maxSplits: 1).map(String.init)
        guard let modelName = parts.first, !modelName.isEmpty else { return nil }
        let modelTag = parts.count > 1 ? parts[1] : "latest"

        let fileManager = FileManager.default
        let manifestsRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/library", isDirectory: true)
        let manifestURL = manifestsRoot
            .appendingPathComponent(modelName, isDirectory: true)
            .appendingPathComponent(modelTag, isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = json["layers"] as? [[String: Any]]
        else {
            return nil
        }

        guard let modelDigest = layers.first(where: {
            ($0["mediaType"] as? String) == "application/vnd.ollama.image.model"
        })?["digest"] as? String
        else {
            return nil
        }

        let blobName = modelDigest.replacingOccurrences(of: ":", with: "-")
        let blobURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models/blobs", isDirectory: true)
            .appendingPathComponent(blobName, isDirectory: false)
        return fileManager.fileExists(atPath: blobURL.path) ? blobURL.path : nil
    }

    nonisolated private static func locallyInstalledOllamaModels() -> Set<String> {
        let manifestsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models/manifests", isDirectory: true)
        guard FileManager.default.fileExists(atPath: manifestsRoot.path),
              let enumerator = FileManager.default.enumerator(
                at: manifestsRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              )
        else {
            return []
        }

        var installedModels = Set<String>()
        let rootDepth = manifestsRoot.pathComponents.count
        for case let fileURL as URL in enumerator {
            let depth = fileURL.pathComponents.count - rootDepth
            if depth > 6 {
                enumerator.skipDescendants()
                continue
            }
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  fileURL.hasDirectoryPath == false
            else {
                continue
            }

            let relativeComponents = Array(fileURL.pathComponents.dropFirst(rootDepth))
            guard relativeComponents.count >= 2 else { continue }

            var modelComponents = relativeComponents
            if modelComponents.first == "registry.ollama.ai" {
                modelComponents.removeFirst()
            }
            if modelComponents.first == "library" {
                modelComponents.removeFirst()
            }
            guard modelComponents.count >= 2 else { continue }

            let tag = modelComponents.last!.lowercased()
            let modelName = modelComponents.dropLast().joined(separator: "/").lowercased()
            guard !modelName.isEmpty, !tag.isEmpty else { continue }
            installedModels.insert("\(modelName):\(tag)")
        }
        return installedModels
    }

    nonisolated private static func resolvedOllamaBlobBackedModel(candidateNames: [String]) -> ResolvedLocalModel? {
        let lowercaseCandidates = Set(candidateNames.map { $0.lowercased() })
        let preferredOllamaModel: String?
        if lowercaseCandidates.contains(where: { $0.contains("qwen") }) {
            preferredOllamaModel = locallyInstalledOllamaModels().first(where: { $0.hasPrefix("qwen2.5:") || $0 == "qwen2.5" })
        } else {
            preferredOllamaModel = nil
        }

        guard let modelName = preferredOllamaModel else { return nil }
        return resolvedOllamaBlobBackedModel(modelName: modelName)
    }

    nonisolated private static func resolvedOllamaBlobBackedModel(modelName: String) -> ResolvedLocalModel? {
        let modelComponents = modelName.lowercased().split(separator: ":").map(String.init)
        guard let repository = modelComponents.first, !repository.isEmpty else { return nil }
        let tag = modelComponents.count > 1 ? modelComponents[1] : "latest"

        let fileManager = FileManager.default
        let manifestURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models/manifests/registry.ollama.ai/library/\(repository)/\(tag)")
        let blobsRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/models/blobs", isDirectory: true)
        guard let data = try? Data(contentsOf: manifestURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = payload["layers"] as? [[String: Any]]
        else {
            return nil
        }

        for layer in layers {
            guard let mediaType = layer["mediaType"] as? String,
                  mediaType == "application/vnd.ollama.image.model",
                  let digest = layer["digest"] as? String
            else {
                continue
            }

            let sanitizedDigest = digest.replacingOccurrences(of: ":", with: "-")
            let blobURL = blobsRoot.appendingPathComponent(sanitizedDigest)
            if fileManager.fileExists(atPath: blobURL.path) {
                return ResolvedLocalModel(path: blobURL.path, sourceLabel: "the local model library")
            }
        }

        return nil
    }

    nonisolated private static func ollamaHasModel(named model: String, binaryPath: String) async -> Bool {
        let target = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        let result = await runOllamaCommand(binaryPath: binaryPath, arguments: ["list"], timeoutSeconds: 16)
        guard result.exitCode == 0 else { return false }
        let lines = result.output
            .lowercased()
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        return lines.contains(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix(target + " ") || trimmed == target
        })
    }

    nonisolated private static func startOllamaServeProcess(binaryPath: String) -> Bool {
        let outURL = URL(fileURLWithPath: "/dev/null")
        do {
            let outHandle = try FileHandle(forWritingTo: outURL)
            let errHandle = try FileHandle(forWritingTo: outURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["serve"]
            process.standardOutput = outHandle
            process.standardError = errHandle
            try process.run()
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func ensureOllamaRuntimeReady(
        binaryPath: String,
        endpoint: URL,
        model: String,
        timeoutSeconds: Int
    ) async -> Bool {
        if await isExistingOllamaRuntimeAvailable(
            endpoint: endpoint,
            model: model,
            timeoutSeconds: min(6, timeoutSeconds)
        ) {
            return true
        }

        _ = startOllamaServeProcess(binaryPath: binaryPath)
        let deadline = Date().addingTimeInterval(TimeInterval(max(8, timeoutSeconds)))
        while Date() < deadline {
            if await isExistingOllamaRuntimeAvailable(
                endpoint: endpoint,
                model: model,
                timeoutSeconds: min(6, timeoutSeconds)
            ) {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    nonisolated private static func runOllamaCommand(
        binaryPath: String,
        arguments: [String],
        timeoutSeconds: Int
    ) async -> (exitCode: Int32, output: String) {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let token = UUID().uuidString
            let outURL = fm.temporaryDirectory.appendingPathComponent("atlas-ollama-cmd-\(token)").appendingPathExtension("out")
            let errURL = fm.temporaryDirectory.appendingPathComponent("atlas-ollama-cmd-\(token)").appendingPathExtension("err")
            fm.createFile(atPath: outURL.path, contents: nil)
            fm.createFile(atPath: errURL.path, contents: nil)

            guard let outHandle = try? FileHandle(forWritingTo: outURL),
                  let errHandle = try? FileHandle(forWritingTo: errURL)
            else {
                try? fm.removeItem(at: outURL)
                try? fm.removeItem(at: errURL)
                return (exitCode: -1, output: "")
            }

            defer {
                try? outHandle.close()
                try? errHandle.close()
                try? fm.removeItem(at: outURL)
                try? fm.removeItem(at: errURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            process.standardOutput = outHandle
            process.standardError = errHandle

            do {
                try process.run()
                let timeoutAt = Date().addingTimeInterval(TimeInterval(max(2, timeoutSeconds)))
                while process.isRunning {
                    if Date() >= timeoutAt {
                        process.terminate()
                        return (exitCode: -2, output: "")
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                outHandle.synchronizeFile()
                errHandle.synchronizeFile()

                let outData = (try? Data(contentsOf: outURL)) ?? Data()
                let errData = (try? Data(contentsOf: errURL)) ?? Data()
                let combined = String(decoding: outData, as: UTF8.self) + String(decoding: errData, as: UTF8.self)
                return (exitCode: process.terminationStatus, output: combined)
            } catch {
                return (exitCode: -1, output: "")
            }
        }.value
    }

    nonisolated private static func resolvedLlamaServerBinaryPath() -> String? {
        let bundledPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/BlackHavenLocalAI.app/Contents/MacOS/BlackHaven")
            .path
        if FileManager.default.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        let legacyBundledPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/LocalAIRuntime.app/Contents/MacOS/llama-server")
            .path
        if FileManager.default.isExecutableFile(atPath: legacyBundledPath) {
            return legacyBundledPath
        }

        let homeDirectory = NSHomeDirectory()
        let candidates = [
            "/Applications/AtlasMasaMacOS.app/Contents/Helpers/BlackHavenLocalAI.app/Contents/MacOS/BlackHaven",
            "/Applications/BlackHaven.app/Contents/Helpers/BlackHavenLocalAI.app/Contents/MacOS/BlackHaven",
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "/Applications/AtlasMasaMacOS.app/Contents/Helpers/LocalAIRuntime.app/Contents/MacOS/llama-server",
            "/Applications/BlackHaven.app/Contents/Helpers/LocalAIRuntime.app/Contents/MacOS/llama-server",
            "/Applications/AtlasMasaMacOS.app/Contents/Resources/LocalAIRuntime/llama-server",
            "/Applications/BlackHaven.app/Contents/Resources/LocalAIRuntime/llama-server",
            "\(homeDirectory)/.local/bin/llama-server",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    nonisolated private static func startManagedLlamaServerProcess(
        binaryPath: String,
        endpoint: URL,
        modelAlias: String
    ) -> Bool {
        let host = endpoint.host ?? "127.0.0.1"
        let port = endpoint.port ?? 8080
        let model = modelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeAlias = model.isEmpty ? "qwen2.5:7b" : model

        let repo = ProcessInfo.processInfo.environment["ATLAS_LLM_HF_REPO"]
            ?? "bartowski/Qwen2.5-7B-Instruct-GGUF"
        let file = ProcessInfo.processInfo.environment["ATLAS_LLM_HF_FILE"]
            ?? "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
        let profile = managedLlamaServerLaunchProfile(modelAlias: safeAlias, tier: .balanced)
        let bundledModelPath = resolvedBundledLlamaModelPath(
            explicitFileName: ProcessInfo.processInfo.environment["ATLAS_LLM_BUNDLED_MODEL_FILE"],
            fallbackFileName: file
        )

        do {
            let outHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
            let errHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = [
                "--host", host,
                "--port", String(port),
                "--alias", safeAlias,
                "--ctx-size", String(profile.ctxSize),
                "--parallel", String(profile.parallelSlots),
                "--threads", String(profile.threads),
                "--threads-batch", String(profile.batchThreads),
                "--threads-http", String(profile.httpThreads),
                "--batch-size", String(profile.batchSize),
                "--ubatch-size", String(profile.ubatchSize),
                "--cache-reuse", String(profile.cacheReuse),
                "--prio", "2",
                "--prio-batch", "2",
                "--flash-attn", profile.flashAttention ? "on" : "auto",
                "--n-gpu-layers", "auto",
                "--metrics",
                "--jinja",
            ]
            if let bundledModelPath {
                process.arguments?.append(contentsOf: ["--model", bundledModelPath])
            } else {
                process.arguments?.append(contentsOf: ["--hf-repo", repo, "--hf-file", file])
            }
            if profile.useMlock {
                process.arguments?.append("--mlock")
            }
            if let reasoningFormat = profile.reasoningFormat {
                process.arguments?.append(contentsOf: ["--reasoning-format", reasoningFormat])
            }
            process.standardOutput = outHandle
            process.standardError = errHandle
            try process.run()
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func resolvedBundledLlamaModelPath(
        explicitFileName: String?,
        fallbackFileName: String
    ) -> String? {
        let fileManager = FileManager.default
        let candidateNames = [explicitFileName, fallbackFileName, "Qwen2.5-7B-Instruct-Q4_K_M.gguf"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for name in candidateNames {
            if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name).path,
               fileManager.fileExists(atPath: bundled)
            {
                return bundled
            }
        }
        return nil
    }

    nonisolated private static func managedLocalAIStorageRoot() -> URL {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return cachesURL
            .appendingPathComponent("BlackHaven", isDirectory: true)
            .appendingPathComponent("LocalAI", isDirectory: true)
    }

    private struct ResolvedLocalModel {
        let path: String
        let sourceLabel: String
    }

    nonisolated private static func resolvedAvailableLlamaModel(
        explicitFileName: String?,
        fallbackFileName: String
    ) -> ResolvedLocalModel? {
        if let bundledPath = resolvedBundledLlamaModelPath(
            explicitFileName: explicitFileName,
            fallbackFileName: fallbackFileName
        ) {
            return ResolvedLocalModel(path: bundledPath, sourceLabel: "the app bundle")
        }

        let fileManager = FileManager.default
        let candidateNames = [explicitFileName, fallbackFileName, "Qwen2.5-7B-Instruct-Q4_K_M.gguf"]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !candidateNames.isEmpty else { return nil }

        let searchRoots = [
            (managedLocalAIStorageRoot(), "BlackHaven local AI storage", 5),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface", isDirectory: true), "the Hugging Face cache", 6),
            (fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/llama.cpp", isDirectory: true), "the llama.cpp cache", 6),
        ]

        for (root, sourceLabel, maxDepth) in searchRoots where fileManager.fileExists(atPath: root.path) {
            if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) {
                let rootDepth = root.pathComponents.count
                for case let fileURL as URL in enumerator {
                    let depth = fileURL.pathComponents.count - rootDepth
                    if depth > maxDepth {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard candidateNames.contains(fileURL.lastPathComponent) else { continue }
                    let resolvedURL = fileURL.resolvingSymlinksInPath()
                    if fileManager.fileExists(atPath: resolvedURL.path) {
                        return ResolvedLocalModel(path: resolvedURL.path, sourceLabel: sourceLabel)
                    }
                    if fileManager.fileExists(atPath: fileURL.path) {
                        return ResolvedLocalModel(path: fileURL.path, sourceLabel: sourceLabel)
                    }
                }
            }
        }

        if let ollamaBackedModel = resolvedOllamaBlobBackedModel(candidateNames: candidateNames) {
            return ollamaBackedModel
        }

        return nil
    }

    private struct ManagedLlamaServerLaunchProfile {
        let ctxSize: Int
        let parallelSlots: Int
        let threads: Int
        let batchThreads: Int
        let httpThreads: Int
        let batchSize: Int
        let ubatchSize: Int
        let flashAttention: Bool
        let reasoningFormat: String?
        let cacheReuse: Int
        let useMlock: Bool
    }

    private enum ManagedLlamaServerLaunchTier: String, CaseIterable {
        case balanced
        case conservative
        case rescue

        var displayName: String {
            switch self {
            case .balanced:
                return "balanced"
            case .conservative:
                return "conservative"
            case .rescue:
                return "rescue"
            }
        }
    }

    nonisolated private static func recordedManagedLocalRuntimeWarmupSeconds() -> TimeInterval {
        let value = UserDefaults.standard.double(forKey: "atlas.managedLocalRuntimeWarmupSeconds")
        return value > 0 ? value : 12
    }

    nonisolated private static func recordManagedLocalRuntimeWarmupSeconds(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        let clamped = max(4, min(120, seconds))
        UserDefaults.standard.set(clamped, forKey: "atlas.managedLocalRuntimeWarmupSeconds")
    }

    nonisolated private static func managedLocalRuntimeRetryPlan(modelAlias: String) -> [ManagedLlamaServerLaunchTier] {
        let processInfo = ProcessInfo.processInfo
        let memoryGb = max(8, Int(processInfo.physicalMemory / (1024 * 1024 * 1024)))
        let warmupSeconds = recordedManagedLocalRuntimeWarmupSeconds()

        if memoryGb <= 12 {
            return [.conservative, .rescue]
        }
        if memoryGb <= 16 || warmupSeconds > 18 {
            return [.balanced, .conservative, .rescue]
        }
        return [.balanced, .conservative]
    }

    nonisolated private static func managedLlamaServerLaunchProfile(
        modelAlias: String,
        tier: ManagedLlamaServerLaunchTier
    ) -> ManagedLlamaServerLaunchProfile {
        let processInfo = ProcessInfo.processInfo
        let memoryGb = max(8, Int(processInfo.physicalMemory / (1024 * 1024 * 1024)))
        let logicalCores = max(4, processInfo.activeProcessorCount)
        let likelyAppleSilicon = {
#if arch(arm64)
            true
#else
            false
#endif
        }()

        let ultraCapacity = memoryGb >= 32 && logicalCores >= 10
        let highCapacity = memoryGb >= 24 && logicalCores >= 8
        let constrainedDefault = memoryGb <= 16
        let lowerModelAlias = modelAlias.lowercased()
        let reasoningFormat = lowerModelAlias.contains("deepseek") ? "deepseek" : nil

        let baseThreads = constrainedDefault ? min(6, logicalCores) : logicalCores
        let baseBatchThreads = constrainedDefault ? min(4, logicalCores) : logicalCores
        let baseHTTPThreads = constrainedDefault ? 2 : min(8, max(4, logicalCores / 2))
        let baseCtx = ultraCapacity ? 32768 : (highCapacity ? 16384 : 8192)
        let baseParallel = ultraCapacity ? 3 : 1
        let baseBatch = ultraCapacity ? 4096 : (highCapacity ? 2048 : 1024)
        let baseUBatch = ultraCapacity ? 2048 : (highCapacity ? 1024 : 512)
        let baseCacheReuse = ultraCapacity ? 768 : (highCapacity ? 512 : 256)

        let generationThreads: Int
        let batchThreads: Int
        let httpThreads: Int
        let ctxSize: Int
        let parallelSlots: Int
        let batchSize: Int
        let ubatchSize: Int
        let flashAttention: Bool
        let cacheReuse: Int
        let useMlock: Bool

        switch tier {
        case .balanced:
            generationThreads = baseThreads
            batchThreads = baseBatchThreads
            httpThreads = baseHTTPThreads
            ctxSize = baseCtx
            parallelSlots = baseParallel
            batchSize = baseBatch
            ubatchSize = baseUBatch
            flashAttention = likelyAppleSilicon
            cacheReuse = baseCacheReuse
            useMlock = ultraCapacity
        case .conservative:
            generationThreads = max(4, min(baseThreads, logicalCores >= 8 ? 5 : 4))
            batchThreads = max(2, min(baseBatchThreads, 3))
            httpThreads = max(1, min(baseHTTPThreads, 2))
            ctxSize = max(6144, min(baseCtx, 8192))
            parallelSlots = 1
            batchSize = max(512, min(baseBatch, 1024))
            ubatchSize = max(128, min(baseUBatch, 256))
            flashAttention = likelyAppleSilicon
            cacheReuse = min(baseCacheReuse, 192)
            useMlock = false
        case .rescue:
            generationThreads = max(2, min(logicalCores, 4))
            batchThreads = max(1, min(logicalCores, 2))
            httpThreads = 1
            ctxSize = 4096
            parallelSlots = 1
            batchSize = 256
            ubatchSize = 128
            flashAttention = false
            cacheReuse = 96
            useMlock = false
        }

        return ManagedLlamaServerLaunchProfile(
            ctxSize: ctxSize,
            parallelSlots: parallelSlots,
            threads: generationThreads,
            batchThreads: batchThreads,
            httpThreads: httpThreads,
            batchSize: batchSize,
            ubatchSize: ubatchSize,
            flashAttention: flashAttention,
            reasoningFormat: reasoningFormat,
            cacheReuse: cacheReuse,
            useMlock: useMlock
        )
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

    nonisolated private static func parseStoredModelIDs(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return dedupModels(
            raw.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" || $0 == "\n" })
                .map(String.init)
        )
    }

    private func persistSelectedLocalAIInstallOptions() {
        let normalized = selectedLocalAIInstallOptionIDs.filter { id in
            localAIInstallOptions.contains(where: { $0.id == id })
        }
        selectedLocalAIInstallOptionIDs = Self.dedupModels(normalized)
        UserDefaults.standard.set(
            selectedLocalAIInstallOptionIDs.joined(separator: ","),
            forKey: LocalAISetupDefaults.selectedModelsKey
        )
    }

    private func isResourceConstrained() -> Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            return true
        }
        return false
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

    nonisolated private static func executeToolCommand(binaryPath: String, arguments: [String]) async -> (status: Int32, output: String) {
        await executeToolCommand(
            binaryPath: binaryPath,
            arguments: arguments,
            currentDirectory: nil
        )
    }

    nonisolated private static func executeToolCommand(
        binaryPath: String,
        arguments: [String],
        currentDirectory: String?
    ) async -> (status: Int32, output: String) {
        await Task.detached(priority: .userInitiated) {
            let outputPipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let decoded = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                return (process.terminationStatus, Self.trimForDisplay(decoded.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: 8_000))
            } catch {
                return (1, "Failed to run \(binaryPath): \(error.localizedDescription)")
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
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parts: [String] = []
        for paragraph in paragraphs {
            let sentences = paragraph
                .components(separatedBy: CharacterSet(charactersIn: "\n."))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if sentences.isEmpty {
                parts.append(paragraph)
            } else {
                parts.append(contentsOf: sentences)
                parts.append("\n\n")
            }
        }

        guard !parts.isEmpty else {
            return [sanitizeWorkspaceMemoryValue(text, maxLength: 180)]
        }

        var chunks: [String] = []
        var buffer = ""
        for sentence in parts {
            if sentence == "\n\n" {
                if !buffer.isEmpty {
                    chunks.append(sanitizeWorkspaceMemoryValue(buffer, maxLength: 180))
                    buffer = ""
                    if chunks.count >= maxChunks {
                        break
                    }
                }
                continue
            }
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
                content: "Agent commands: /status, /scan, /open <path>, /save, /run <shell>, /grep <pattern>, /remember"
            )
            return true

        case "/status":
            addCodingMessage(
                role: .assistant,
                content: """
                \(codingAgentReadinessSummary)
                \(codingAgentToolingSummary)
                """
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
        struct Delta: Decodable {
            let content: String?
        }

        struct Message: Decodable {
            let role: String?
            let content: String?
        }

        let message: Message?
        let delta: Delta?
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
        let done: Bool?
    }

    private struct OllamaTagsResponse: Decodable {
        struct ModelEntry: Decodable {
            let name: String
        }

        let models: [ModelEntry]
    }

    nonisolated private static func runOpenAICompatiblePrompt(
        endpoint: URL,
        model: String,
        prompt: String,
        timeoutSeconds: Int,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String,
        streamHandler: (@Sendable (String) -> Void)? = nil
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
                stream: streamHandler != nil
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
                if let streamHandler {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200 ... 299).contains(http.statusCode)
                    else {
                        return nil
                    }

                    var accumulated = ""
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        let payloadLine = trimmed.hasPrefix("data:")
                            ? String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                            : trimmed
                        if payloadLine == "[DONE]" { break }
                        guard let data = payloadLine.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                        else {
                            continue
                        }

                        let chunk = decoded.choices.first?.delta?.content
                            ?? decoded.choices.first?.message?.content
                            ?? decoded.choices.first?.text
                            ?? ""
                        if !chunk.isEmpty {
                            accumulated += chunk
                            streamHandler(Self.trimForDisplay(accumulated, maxChars: 18_000))
                        }
                    }

                    let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                    return final.isEmpty ? nil : Self.trimForDisplay(final, maxChars: 18_000)
                }

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
        systemPrompt: String,
        streamHandler: (@Sendable (String) -> Void)? = nil
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
                stream: streamHandler != nil,
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
                if let streamHandler {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200 ... 299).contains(http.statusCode)
                    else {
                        return nil
                    }

                    var accumulated = ""
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              let data = trimmed.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(OllamaChatResponse.self, from: data)
                        else {
                            continue
                        }

                        let chunk = decoded.message?.content ?? decoded.response ?? ""
                        if !chunk.isEmpty {
                            accumulated += chunk
                            streamHandler(Self.trimForDisplay(accumulated, maxChars: 18_000))
                        }
                        if decoded.done == true {
                            break
                        }
                    }

                    let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                    return final.isEmpty ? nil : Self.trimForDisplay(final, maxChars: 18_000)
                }

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
        guard isExecutionStreamUnlocked else {
            return [
                ExecutionAction(
                    id: UUID().uuidString,
                    horizon: "Onboarding",
                    title: "Complete adaptive survey depth",
                    details: "Answer \(surveyAnswersRemainingForExecution) more question\(surveyAnswersRemainingForExecution == 1 ? "" : "s") to unlock your AI execution stream (minimum \(surveyAnswersRequiredForExecution)).",
                    priority: 1,
                    source: "survey-gate",
                    completed: false
                ),
            ]
        }

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
        let surveyDepthTarget = max(Self.minimumSurveyAnswersForExecution, localSurveyTotal() - 4)

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
        if containsAny(lower, ["vanlife", "rv", "camper", "sprinter", "shower", "water tank", "mobile living", "off-grid", "greywater"]) {
            return .mobileLivingInfrastructure
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
        case "mobile-living", "vanlife", "rv-life", "off-grid-water", "mobile-infrastructure":
            return .mobileLivingInfrastructure
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
        case .mobileLivingInfrastructure:
            return "Design and validate reliable vanlife and RV infrastructure with strong water, power, ventilation, and maintenance tradeoff control."
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
        case .mobileLivingInfrastructure:
            return [
                "Define use case, water/power limits, and maintenance tolerance first.",
                "Compare weight, space, electrical draw, and hygiene tradeoffs before buying.",
                "Validate safety for plumbing, venting, heating, and drainage paths.",
                "Record parts, install sequence, and failure fallback before field use."
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
            activeWorkspaceLane = visibleWorkspaceLanes().first ?? .mobilityOps
        }

        // Rebuild a concise session-line for system output sparingly.
        if !workspaceSessions.isEmpty, workspaceMemoryRecords.count % 12 == 0 {
            appendOutput("Workspace notebooks refreshed across lanes (\(workspaceSessions.count) active sessions).")
        }
    }

    private func ensureSeedDocumentsAvailable() {
        seedKnowledgeDocument(
            resourceName: "Conversation with ChatGPT_ Recirculating Showers for Vans.pdf",
            fallbackPath: "/Users/avrohom/Library/Mobile Documents/com~apple~CloudDocs/Conversation with ChatGPT_ Recirculating Showers for Vans.pdf",
            applyTo: [(.workspace, .mobileLivingInfrastructure)],
            defaultPrompt: "You are MLI Studio, BlackHaven's mobile living infrastructure copilot. Focus on vanlife, RV life, off-grid water, showers, power, ventilation, safety, maintenance burden, and installation tradeoffs. Ground recommendations in uploaded sources before making assumptions."
        )
        seedKnowledgeDocument(
            resourceName: "Israeli Business Regulations Update Search-2.pdf",
            fallbackPath: "/Users/avrohom/Downloads/Israeli Business Regulations Update Search-2.pdf",
            applyTo: [(.command, nil), (.workspace, .wealthOperations)],
            defaultPrompt: nil
        )
    }

    private func seedKnowledgeDocument(
        resourceName: String,
        fallbackPath: String,
        applyTo targets: [(AtlasContextSurface, WorkspaceLane?)],
        defaultPrompt: String?
    ) {
        let sourceURL = bundledReferenceDocumentURL(fileName: resourceName)
            ?? {
                let fallbackURL = URL(fileURLWithPath: fallbackPath)
                return FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil
            }()
        guard let sourceURL else { return }

        let alreadyImported = knowledgeFiles.contains { $0.fileName == sourceURL.lastPathComponent }
        if !alreadyImported {
            importKnowledgeFiles(urls: [sourceURL])
        }

        guard let imported = knowledgeFiles.first(where: { $0.fileName == sourceURL.lastPathComponent }) else { return }

        for (surface, workspaceLane) in targets {
            updateContextProfile(for: surface, workspaceLane: workspaceLane) { profile in
                if let defaultPrompt,
                   profile.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.customSystemPrompt = defaultPrompt
                }
                if !profile.enabledKnowledgeFileIDs.contains(imported.id) {
                    profile.enabledKnowledgeFileIDs.append(imported.id)
                    profile.enabledKnowledgeFileIDs.sort()
                }
                profile.includeKnowledgeFiles = true
                profile.includeRecentUsageTrends = true
                profile.includeAccountUsagePatterns = true
                if surface == .workspace {
                    profile.includeWorkspaceMemory = true
                }
            }
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

        if surveyExpansionActive {
            let adaptiveQuestionID = "adaptive_depth_\(surveyExpansionQuestionCounter + 1)"
            if surveyAnswers[adaptiveQuestionID] != nil {
                surveyExpansionQuestionCounter += 1
                return localSurveyQuestion()
            }
            return localAdaptiveSurveyQuestion(id: adaptiveQuestionID)
        }

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

        let answered = surveyAnswers.count
        if answered >= max(Self.minimumSurveyAnswersForExecution, localSurveyTotal()) {
            if let queued = queuedAdaptiveSurveyQuestion, surveyAnswers[queued.id] == nil {
                return queued
            }
            let adaptiveQuestionID = "adaptive_depth_dynamic_\(answered + 1)"
            return localAdaptiveSurveyQuestion(id: adaptiveQuestionID)
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

    private func prepareNextAdaptiveSurveyQuestionIfNeeded() async {
        let answered = surveyAnswers.count
        guard answered >= Self.minimumSurveyAnswersForExecution else {
            queuedAdaptiveSurveyQuestion = nil
            return
        }

        let nextID = "adaptive_depth_dynamic_\(answered + 1)"
        if let queuedAdaptiveSurveyQuestion, queuedAdaptiveSurveyQuestion.id == nextID {
            return
        }
        guard surveyAnswers[nextID] == nil else { return }

        guard allowsAutomaticRuntimeWork else {
            queuedAdaptiveSurveyQuestion = localAdaptiveSurveyQuestion(id: nextID)
            return
        }

        let latestSignals = surveyAnswers
            .sorted { $0.key < $1.key }
            .suffix(14)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")

        let themeTemplate = """
        Core survey themes to keep:
        - wealth growth and income blockers
        - job/business growth route
        - stress, cognition, and execution resilience
        - travel and mobility constraints
        - family financial pressure and affordability
        - donation capacity and mission alignment
        """

        let prompt = """
        You are BlackHaven local survey engine.
        Generate exactly one adaptive multiple-choice survey question in valid JSON only:
        {"title":"...","description":"...","choices":[{"value":"...","label":"..."},{"value":"...","label":"..."},{"value":"...","label":"..."}]}
        Constraints:
        - title <= 160 chars
        - 3 to 5 choices
        - choices must be concrete and non-overlapping
        - include practical wealth/life execution relevance
        - no markdown, no extra keys, JSON only

        \(themeTemplate)

        Context:
        \(contextEnvelope(for: .survey))

        Recent user signals:
        \(latestSignals.isEmpty ? "- none yet" : latestSignals)
        """

        guard let raw = await requestLocalModelResponse(
            prompt: sanitizeModelInput(prompt, maxLength: 9_000),
            timeoutSeconds: 18,
            domain: .structuredJSON
        ),
        let decoded: SurveyAdaptiveQuestionEnvelope = Self.decodeModelJSON(raw)
        else {
            queuedAdaptiveSurveyQuestion = localAdaptiveSurveyQuestion(id: nextID)
            return
        }

        let title = sanitizeWorkspaceMemoryValue(decoded.title, maxLength: 160)
        let description = decoded.description.flatMap { sanitizeWorkspaceMemoryValue($0, maxLength: 180).trimmedNil() }
        let normalizedChoices = decoded.choices
            .map { item in
                SurveyChoice(
                    value: sanitizeWorkspaceMemoryValue(item.value.lowercased().replacingOccurrences(of: " ", with: "_"), maxLength: 48),
                    label: sanitizeWorkspaceMemoryValue(item.label, maxLength: 72)
                )
            }
            .filter { !$0.value.isEmpty && !$0.label.isEmpty }

        guard !title.isEmpty, normalizedChoices.count >= 3 else {
            queuedAdaptiveSurveyQuestion = localAdaptiveSurveyQuestion(id: nextID)
            return
        }

        queuedAdaptiveSurveyQuestion = localQuestion(
            id: nextID,
            title: title,
            description: description,
            choices: Array(normalizedChoices.prefix(5))
        )
    }

    private func localAdaptiveSurveyQuestion(id: String) -> SurveyQuestion {
        let idx = max(1, surveyExpansionQuestionCounter + 1)
        let financialPressure = surveyAnswers["financial_struggle_self"] == "yes"
            || surveyAnswers["financial_struggle_family"] == "yes"
            || surveyAnswers["public_transport_affordability"] == "often"
            || surveyAnswers["public_transport_affordability"] == "sometimes"
        let growthPriority = surveyAnswers["growth_priority"] ?? ""

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
            ),
            (
                "Adaptive depth \(idx): Which money-system upgrade would create the biggest stability jump this month?",
                "Atlas uses this to route immediate wealth-building and family-support actions.",
                [
                    SurveyChoice(value: "cash_buffer_\(idx)", label: "Emergency cash buffer"),
                    SurveyChoice(value: "income_reps_\(idx)", label: "More weekly income actions"),
                    SurveyChoice(value: "pricing_upgrade_\(idx)", label: "Improve pricing/offer"),
                    SurveyChoice(value: "expense_control_\(idx)", label: "Tighter expense control")
                ]
            ),
            (
                "Adaptive depth \(idx): What should Atlas optimize first in your growth engine this week?",
                "This keeps execution aligned to your selected wealth route.",
                [
                    SurveyChoice(value: "job_ladder_execution_\(idx)", label: "Job ladder progression"),
                    SurveyChoice(value: "business_customer_growth_\(idx)", label: "Business customer growth"),
                    SurveyChoice(value: "hybrid_balance_\(idx)", label: "Balanced hybrid route"),
                    SurveyChoice(value: "stability_first_\(idx)", label: "Stability first")
                ]
            ),
        ]

        let selected: (String, String, [SurveyChoice])
        if financialPressure {
            selected = prompts[3]
        } else if growthPriority == "grow_business_customer_base"
            || growthPriority == "hybrid_growth"
            || growthPriority == "climb_job_ladder"
        {
            selected = prompts[4]
        } else {
            selected = prompts[idx % 3]
        }
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
        accountLabel = normalizedOwnerAccountLabel(accountName)
        revealRemoteTransferTutorialIfNeeded()
        persistStateToDisk()
    }

    func revealRemoteTransferTutorialIfNeeded() {
        showRemoteTransferTutorial = isSignedIn && !UserDefaults.standard.bool(forKey: RemoteTransferDefaults.tutorialSeenKey)
    }

    func dismissRemoteTransferTutorial() {
        UserDefaults.standard.set(true, forKey: RemoteTransferDefaults.tutorialSeenKey)
        showRemoteTransferTutorial = false
        remoteControlLastAction = "Remote pairing guide acknowledged. Keep this Mac on and plugged in for phone-to-desktop handoff."
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
            mliStudioVisible: mliStudioVisible,
            selectedTier: selectedTier,
            trialDaysRemaining: trialDaysRemaining,
            operatorStateSnapshot: operatorStateSnapshot,
            activeChecklistPlan: activeChecklistPlan,
            currentActivitySuggestion: currentActivitySuggestion,
            currentItineraryPlan: currentItineraryPlan,
            currentSupportRecommendation: currentSupportRecommendation,
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
            activeTravelItineraryDraft: activeTravelItineraryDraft,
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
            contextProfiles: contextProfiles,
            rAndDPromptDraft: rAndDPromptDraft,
            rAndDSelectedProductType: rAndDSelectedProductType,
            rAndDPlanRevisionDraft: rAndDPlanRevisionDraft,
            rAndDChangeRequestDraft: rAndDChangeRequestDraft,
            rAndDTargetPartID: rAndDTargetPartID,
            rAndDJobs: rAndDJobs,
            selectedRAndDJobID: selectedRAndDJobID,
            rAndDArtifacts: rAndDArtifacts,
            rAndDTimeline: rAndDTimeline,
            rAndDGovernance: rAndDGovernance,
            rAndDTraceabilityRows: rAndDTraceabilityRows,
            rAndDDoctrine: rAndDDoctrine,
            rAndDDocuments: rAndDDocuments,
            rAndDDocumentationBundles: rAndDDocumentationBundles,
            rAndDInspectionGuide: rAndDInspectionGuide,
            rAndDWorkspaceRootPath: rAndDWorkspaceRootPath,
            rAndDLocalWorkspaceAssets: rAndDLocalWorkspaceAssets,
            rAndDLocalExecutionRecords: rAndDLocalExecutionRecords,
            rAndDLocalExecutionStatusLine: rAndDLocalExecutionStatusLine,
            rAndDStatusLine: rAndDStatusLine,
            rAndDReportTitleDraft: rAndDReportTitleDraft,
            rAndDReviewNoteDraft: rAndDReviewNoteDraft,
            rAndDApprovalReviewerName: rAndDApprovalReviewerName,
            rAndDApprovalReviewerRole: rAndDApprovalReviewerRole,
            rAndDApprovalAuthorityKind: rAndDApprovalAuthorityKind,
            rAndDApprovalCommentDraft: rAndDApprovalCommentDraft,
            rAndDSelectedDocumentType: rAndDSelectedDocumentType,
            rAndDDocumentAudienceMode: rAndDDocumentAudienceMode,
            rAndDDocumentTitleDraft: rAndDDocumentTitleDraft,
            rAndDDocumentPlatformNameDraft: rAndDDocumentPlatformNameDraft,
            rAndDDocumentRevisionDraft: rAndDDocumentRevisionDraft,
            rAndDDocumentPurposeDraft: rAndDDocumentPurposeDraft,
            rAndDDocumentTargetAudienceDraft: rAndDDocumentTargetAudienceDraft,
            rAndDDocumentAuthorDraft: rAndDDocumentAuthorDraft,
            selectedRAndDDocumentID: selectedRAndDDocumentID,
            rAndDDocumentPreviewHTML: rAndDDocumentPreviewHTML,
            rAndDDocumentPreviewStatus: rAndDDocumentPreviewStatus,
            rAndDLastExportPath: rAndDLastExportPath,
            rAndDLastExportError: rAndDLastExportError,
            rAndDBundleExportStatus: rAndDBundleExportStatus,
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
        accountLabel = state.isSignedIn ? normalizedOwnerAccountLabel(state.accountLabel) : state.accountLabel
        mliStudioVisible = state.mliStudioVisible ?? true
        selectedTier = state.selectedTier
        trialDaysRemaining = max(0, min(state.trialDaysRemaining, SessionStore.localTrialDurationDays))
        operatorStateSnapshot = state.operatorStateSnapshot
        activeChecklistPlan = state.activeChecklistPlan
        currentActivitySuggestion = state.currentActivitySuggestion
        currentItineraryPlan = state.currentItineraryPlan
        currentSupportRecommendation = state.currentSupportRecommendation
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
        activeTravelItineraryDraft = state.activeTravelItineraryDraft
            ?? TravelItineraryDraft(
                id: "default-travel-itinerary",
                title: "Travel itinerary",
                locationIDs: [],
                updatedAt: isoTimestamp()
            )
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
        contextProfiles = state.contextProfiles ?? []
        rAndDPromptDraft = state.rAndDPromptDraft ?? ""
        rAndDSelectedProductType = state.rAndDSelectedProductType ?? "mechanical_vehicle"
        rAndDPlanRevisionDraft = state.rAndDPlanRevisionDraft ?? ""
        rAndDChangeRequestDraft = state.rAndDChangeRequestDraft ?? ""
        rAndDTargetPartID = state.rAndDTargetPartID ?? ""
        rAndDJobs = state.rAndDJobs ?? []
        selectedRAndDJobID = state.selectedRAndDJobID
        rAndDArtifacts = state.rAndDArtifacts ?? []
        rAndDTimeline = state.rAndDTimeline ?? []
        rAndDGovernance = state.rAndDGovernance
        rAndDTraceabilityRows = state.rAndDTraceabilityRows ?? []
        rAndDDoctrine = state.rAndDDoctrine
        rAndDDocuments = state.rAndDDocuments ?? []
        rAndDDocumentationBundles = state.rAndDDocumentationBundles ?? []
        rAndDInspectionGuide = state.rAndDInspectionGuide ?? ""
        rAndDWorkspaceRootPath = state.rAndDWorkspaceRootPath ?? ""
        rAndDLocalWorkspaceAssets = state.rAndDLocalWorkspaceAssets ?? []
        rAndDLocalExecutionRecords = state.rAndDLocalExecutionRecords ?? []
        rAndDLocalExecutionStatusLine = state.rAndDLocalExecutionStatusLine ?? "Local CAD execution idle."
        rAndDStatusLine = state.rAndDStatusLine ?? "R&D orchestrator idle."
        rAndDReportTitleDraft = state.rAndDReportTitleDraft ?? ""
        rAndDReviewNoteDraft = state.rAndDReviewNoteDraft ?? ""
        rAndDApprovalReviewerName = state.rAndDApprovalReviewerName ?? "Atlas Internal Reviewer"
        rAndDApprovalReviewerRole = state.rAndDApprovalReviewerRole ?? "internal_engineering_lead"
        rAndDApprovalAuthorityKind = state.rAndDApprovalAuthorityKind ?? "internal_engineering_approval"
        rAndDApprovalCommentDraft = state.rAndDApprovalCommentDraft ?? ""
        rAndDSelectedDocumentType = state.rAndDSelectedDocumentType ?? "manufacturing_build_guide"
        rAndDDocumentAudienceMode = state.rAndDDocumentAudienceMode ?? "private"
        rAndDDocumentTitleDraft = state.rAndDDocumentTitleDraft ?? ""
        rAndDDocumentPlatformNameDraft = state.rAndDDocumentPlatformNameDraft ?? ""
        rAndDDocumentRevisionDraft = state.rAndDDocumentRevisionDraft ?? ""
        rAndDDocumentPurposeDraft = state.rAndDDocumentPurposeDraft ?? ""
        rAndDDocumentTargetAudienceDraft = state.rAndDDocumentTargetAudienceDraft ?? ""
        rAndDDocumentAuthorDraft = state.rAndDDocumentAuthorDraft ?? ""
        selectedRAndDDocumentID = state.selectedRAndDDocumentID
        rAndDDocumentPreviewHTML = state.rAndDDocumentPreviewHTML ?? ""
        rAndDDocumentPreviewStatus = state.rAndDDocumentPreviewStatus ?? "Generate or select a document to preview it here."
        rAndDLastExportPath = state.rAndDLastExportPath ?? ""
        rAndDLastExportError = state.rAndDLastExportError ?? ""
        rAndDBundleExportStatus = state.rAndDBundleExportStatus ?? ""
        workspaceSessions = state.workspaceSessions ?? []
        if let rawLane = state.activeWorkspaceLane,
           let lane = WorkspaceLane(rawValue: rawLane)
        {
            activeWorkspaceLane = (lane == .mobileLivingInfrastructure && !mliStudioVisible) ? .mobilityOps : lane
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
        if operatorStateSnapshot == nil || activeChecklistPlan == nil || currentActivitySuggestion == nil || currentItineraryPlan == nil || currentSupportRecommendation == nil {
            refreshNextLayerExperience()
        }
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
    var mliStudioVisible: Bool?
    var selectedTier: AccountTier
    var trialDaysRemaining: Int
    var operatorStateSnapshot: OperatorStateSnapshot?
    var activeChecklistPlan: ChecklistPlan?
    var currentActivitySuggestion: ActivitySuggestion?
    var currentItineraryPlan: ItineraryPlan?
    var currentSupportRecommendation: SupportRecommendation?
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
    var activeTravelItineraryDraft: TravelItineraryDraft?
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
    var contextProfiles: [AtlasContextProfile]?
    var rAndDPromptDraft: String?
    var rAndDSelectedProductType: String?
    var rAndDPlanRevisionDraft: String?
    var rAndDChangeRequestDraft: String?
    var rAndDTargetPartID: String?
    var rAndDJobs: [RAndDJobResponse]?
    var selectedRAndDJobID: String?
    var rAndDArtifacts: [RAndDArtifact]?
    var rAndDTimeline: [RAndDTimelineStage]?
    var rAndDGovernance: RAndDGovernanceResponse?
    var rAndDTraceabilityRows: [RAndDTraceabilityRow]?
    var rAndDDoctrine: RAndDDoctrineResponse?
    var rAndDDocuments: [RAndDDocumentRecord]?
    var rAndDDocumentationBundles: [RAndDDocumentationBundle]?
    var rAndDInspectionGuide: String?
    var rAndDWorkspaceRootPath: String?
    var rAndDLocalWorkspaceAssets: [SessionStore.RAndDLocalWorkspaceAsset]?
    var rAndDLocalExecutionRecords: [SessionStore.RAndDLocalExecutionRecord]?
    var rAndDLocalExecutionStatusLine: String?
    var rAndDStatusLine: String?
    var rAndDReportTitleDraft: String?
    var rAndDReviewNoteDraft: String?
    var rAndDApprovalReviewerName: String?
    var rAndDApprovalReviewerRole: String?
    var rAndDApprovalAuthorityKind: String?
    var rAndDApprovalCommentDraft: String?
    var rAndDSelectedDocumentType: String?
    var rAndDDocumentAudienceMode: String?
    var rAndDDocumentTitleDraft: String?
    var rAndDDocumentPlatformNameDraft: String?
    var rAndDDocumentRevisionDraft: String?
    var rAndDDocumentPurposeDraft: String?
    var rAndDDocumentTargetAudienceDraft: String?
    var rAndDDocumentAuthorDraft: String?
    var selectedRAndDDocumentID: String?
    var rAndDDocumentPreviewHTML: String?
    var rAndDDocumentPreviewStatus: String?
    var rAndDLastExportPath: String?
    var rAndDLastExportError: String?
    var rAndDBundleExportStatus: String?
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

@MainActor
private enum LocalPDFExporter {
    static func export(html: String, to url: URL) async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = PDFNavigationDelegate { result in
                switch result {
                case .success:
                    if #available(macOS 11.0, *) {
                        let configuration = WKPDFConfiguration()
                        configuration.rect = CGRect(x: 0, y: 0, width: 900, height: 1200)
                        webView.createPDF(configuration: configuration) { pdfResult in
                            switch pdfResult {
                            case .success(let data):
                                do {
                                    try FileManager.default.createDirectory(
                                        at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true
                                    )
                                    try data.write(to: url, options: .atomic)
                                    continuation.resume()
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "BlackHavenPDF",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "PDF export requires macOS 11 or newer."]
                        ))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            PDFNavigationDelegateStore.shared.hold(delegate, for: webView)
            webView.navigationDelegate = delegate
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

private final class PDFNavigationDelegateStore {
    static let shared = PDFNavigationDelegateStore()
    private var delegates: [ObjectIdentifier: PDFNavigationDelegate] = [:]

    func hold(_ delegate: PDFNavigationDelegate, for webView: WKWebView) {
        delegates[ObjectIdentifier(webView)] = delegate
        delegate.onFinish = { [weak self, weak webView] result in
            guard let webView else { return }
            self?.delegates.removeValue(forKey: ObjectIdentifier(webView))
            delegate.finish(result)
        }
    }
}

private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinish: ((Result<Void, Error>) -> Void)?
    private var finished = false
    private let completion: (Result<Void, Error>) -> Void

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        completion(result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFinish?(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFinish?(.failure(error))
    }
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
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
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
