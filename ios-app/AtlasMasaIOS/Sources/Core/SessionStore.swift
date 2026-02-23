import AuthenticationServices
import CryptoKit
import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SessionStore: ObservableObject {
    private static let localTrialDurationDays = 60

    @Published var health: HealthResponse?
    @Published var systemOutput: [String] = ["Booting Atlas Masa Travel Design OS (Swift local tier)..."]
    @Published var survey: SurveyNextResponse?
    @Published var feedItems: [FeedItem] = []
    @Published var notes: [UserNote] = []
    @Published var pendingNoteTitle = ""
    @Published var pendingNoteContent = ""
    @Published var pendingPrompt = ""
    @Published var promptQueue: [PromptQueueItem] = []

    @Published var isSignedIn = false
    @Published var isAppleSignInInProgress = false
    @Published var isGoogleSignInInProgress = false
    @Published var isPasskeyInProgress = false
    @Published var accountProvider: AuthProvider?
    @Published var accountLabel = "Guest Operator"
    @Published var accountStatusMessage = "Use provider auth or passwordless to activate your account."
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
    @Published var jobMarketOpportunities: [JobOpportunity] = []

    let api: APIClient
    private let localReasoning = LocalReasoningEngine()
    private var queueWorkerTask: Task<Void, Never>?
    private var runtimeTelemetryTask: Task<Void, Never>?
    private var pendingRuntimeTelemetry: [String] = []
    private var lastRuntimeTelemetryAt = Date.distantPast
    private var appleAuthCoordinator: AppleAuthorizationCoordinator?
    private var passkeyAuthCoordinator: AppleAuthorizationCoordinator?

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

    func handleAppBecameActive() async {
        await syncSessionFromServerIfAvailable()
    }

    func refreshHealth() async {
        do {
            health = try await api.health()
            appendOutput("API reachable. Capabilities refreshed.")
        } catch {
            appendOutput("API health unavailable. App remains in local-first mode.")
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
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? "Atlas Owner")
                appendOutput("Native Apple sign-in synced with API.")
                accountStatusMessage = "Apple account activated and synced."
            } catch {
                // Keep sign-in local-first so user can still use the app even if API sync fails.
                markSignedIn(provider: .apple, accountName: credential.fullName?.givenName ?? "Atlas Owner")
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
            displayName: "Atlas Masa Member",
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
        markSignedIn(provider: provider, accountName: displayName)
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
            ?? "Atlas Masa Member"

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
        persistStateToDisk()
        Task {
            _ = try? await api.logout()
        }
        appendOutput("Signed out.")
        accountStatusMessage = "Signed out. Re-authenticate to continue synced personalization."
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

        let safetySignal = evaluateSuspiciousPattern(input: cleaned, source: "prompt")
        if safetySignal.holdQueue {
            appendOutput("Queue is temporarily paused due to high-risk language. Atlas can only support de-escalation, rehabilitation, and safe next steps.")
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
        feedItems = localFeedFromExecutionPlan()
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
            workspaceMode,
            surveyText,
            noteText,
            sessionText,
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
