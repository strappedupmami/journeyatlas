import SwiftUI
import WebKit

// MARK: - Navigation Enum
enum DashboardSection: String, CaseIterable, Identifiable {
    case command, aiGuide, survey, concierge, code, workspaces
    case execution, memory, mobility, world, access, plans, output

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .command: return "Command"
        case .aiGuide: return "AI Guide"
        case .survey: return "Survey"
        case .concierge: return "Concierge"
        case .code: return "Code"
        case .workspaces: return "Workspaces"
        case .execution: return "Execution"
        case .memory: return "Memory"
        case .mobility: return "Travel"
        case .world: return "World Monitor"
        case .access: return "Access"
        case .plans: return "Plans"
        case .output: return "Output"
        }
    }

    var icon: String {
        switch self {
        case .command: return "sparkles.square.filled.on.square"
        case .aiGuide: return "book.closed"
        case .survey: return "point.3.connected.trianglepath.dotted"
        case .concierge: return "message.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .workspaces: return "folder"
        case .execution: return "bolt.heart"
        case .memory: return "brain.head.profile"
        case .mobility: return "airplane"
        case .world: return "globe.europe.africa.fill"
        case .access: return "person.badge.key"
        case .plans: return "creditcard"
        case .output: return "terminal"
        }
    }
}

// MARK: - Root Dashboard
struct RootDashboardView: View {
    @State private var selectedSection: DashboardSection? = .world

    var body: some View {
        let visibleSections = DashboardSection.allCases.filter { $0 != .mobility }
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("BLACKHAVEN")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.primary.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .background(Color.clear)

                List(visibleSections, selection: $selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.icon)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
                .listStyle(.sidebar)
                .environment(\.defaultMinListRowHeight, 32)
            }
            .navigationTitle("")
            .navigationSplitViewColumnWidth(min: 180, ideal: 204, max: 220)
        } detail: {
            // Main Content Area
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

                switch selectedSection {
                case .command:
                    CommandCenterCard()
                case .aiGuide:
                    AIGuideCard()
                case .survey:
                    AdaptiveSurveyCard()
                case .concierge:
                    PromptQueueCard()
                case .code:
                    CodingWorkspaceCard()
                case .workspaces:
                    WorkspacesCard()
                case .execution:
                    ProactiveFeedCard()
                case .memory:
                    NotesCard()
                case .mobility:
                    AdaptiveSurveyCard()
                case .world:
                    WorldMonitorCard()
                case .access:
                    AppleSignInCard()
                case .plans:
                    SubscriptionCard()
                case .output:
                    SystemOutputCard()
                case .none:
                    VStack {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                        Text("Select a module")
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - World Monitor Card
struct WorldMonitorCard: View {
    private static let endpointStorageKey = "atlas.macos.worldmonitor.endpoint"
    private static let hostedEndpoint = "https://worldmonitor.app"
    private static let localEndpoint = "http://127.0.0.1:5173"
    private static let natureSources: [NatureSignalSource] = [
        NatureSignalSource(
            title: "IUCN Red List",
            detail: "Threat status index for species and conservation categories.",
            kind: "Web",
            urlString: "https://www.iucnredlist.org/"
        ),
        NatureSignalSource(
            title: "IUCN Red List API",
            detail: "Programmatic species and category access. API key/token required.",
            kind: "API",
            urlString: "https://api.iucnredlist.org/"
        ),
        NatureSignalSource(
            title: "GBIF",
            detail: "Global biodiversity occurrence records and taxonomy references.",
            kind: "Web",
            urlString: "https://www.gbif.org/"
        ),
        NatureSignalSource(
            title: "GBIF API",
            detail: "Open species occurrence API for biodiversity monitoring workflows.",
            kind: "API",
            urlString: "https://api.gbif.org/v1/"
        ),
        NatureSignalSource(
            title: "Protected Planet (WDPA)",
            detail: "Protected area coverage and conservation boundary datasets.",
            kind: "Web",
            urlString: "https://www.protectedplanet.net/en"
        ),
        NatureSignalSource(
            title: "Global Forest Watch",
            detail: "Tree cover loss and forest pressure indicators.",
            kind: "Web",
            urlString: "https://www.globalforestwatch.org/"
        ),
        NatureSignalSource(
            title: "NASA FIRMS",
            detail: "Active fire and thermal anomaly monitoring.",
            kind: "Web",
            urlString: "https://firms.modaps.eosdis.nasa.gov/"
        ),
        NatureSignalSource(
            title: "NOAA Climate at a Glance",
            detail: "Climate trend indicators and regional anomalies.",
            kind: "Indicator",
            urlString: "https://www.ncei.noaa.gov/access/monitoring/climate-at-a-glance/"
        ),
        NatureSignalSource(
            title: "Copernicus Climate Bulletins",
            detail: "Global monthly climate bulletins and key planetary indicators.",
            kind: "Indicator",
            urlString: "https://climate.copernicus.eu/climate-bulletins"
        )
    ]
    private static let charitySources: [NatureSignalSource] = [
        NatureSignalSource(
            title: "Charity Navigator",
            detail: "Charity profiles, ratings, and accountability context.",
            kind: "Web",
            urlString: "https://www.charitynavigator.org/"
        ),
        NatureSignalSource(
            title: "Charity Navigator Data API",
            detail: "Developer access for organization/rating data (requires approved credentials).",
            kind: "API",
            urlString: "https://developer.charitynavigator.org/"
        ),
        NatureSignalSource(
            title: "Charity Navigator GraphQL API",
            detail: "Official GraphQL product channel for partner data integrations.",
            kind: "API",
            urlString: "https://www.charitynavigator.org/products-and-services/graphql-api/"
        ),
        NatureSignalSource(
            title: "CN Ratings Methodology",
            detail: "How impact/accountability dimensions are scored.",
            kind: "Method",
            urlString: "https://www.charitynavigator.org/about-us/our-methodology/ratings/"
        ),
        NatureSignalSource(
            title: "IRS EO Search",
            detail: "Federal tax-exempt lookup and filing validation.",
            kind: "Reg",
            urlString: "https://apps.irs.gov/app/eos/"
        ),
        NatureSignalSource(
            title: "ProPublica Nonprofit Explorer",
            detail: "Form 990 history, compensation, and financial trend review.",
            kind: "Data",
            urlString: "https://projects.propublica.org/nonprofits/"
        ),
        NatureSignalSource(
            title: "Candid / GuideStar",
            detail: "Program descriptions, transparency seals, and nonprofit profiles.",
            kind: "Data",
            urlString: "https://www.guidestar.org/"
        ),
        NatureSignalSource(
            title: "GiveWell Top Charities",
            detail: "Evidence-driven charity effectiveness benchmarks.",
            kind: "Impact",
            urlString: "https://www.givewell.org/charities/top-charities"
        )
    ]

    @EnvironmentObject private var session: SessionStore
    @State private var endpointURL = URL(string: Self.hostedEndpoint)!
    @State private var endpointDraft = Self.hostedEndpoint
    @State private var endpointStatusLine = "World Monitor hosted endpoint active."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AtlasPanel(heading: "Nature + World Monitor", caption: "Live dashboard with biodiversity and environmental intelligence sources.") {
                VStack(alignment: .leading, spacing: 9) {
                    TextField("World Monitor URL", text: $endpointDraft)
                        .atlasFieldStyle()
                    HStack(spacing: 8) {
                        Button("Load URL") {
                            applyEndpoint(endpointDraft)
                        }
                        Button("Use Hosted") {
                            applyEndpoint(Self.hostedEndpoint)
                        }
                        Button("Use Local Dev") {
                            applyEndpoint(Self.localEndpoint)
                        }
                    }
                    Text(endpointStatusLine)
                        .font(.footnote)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text("Local dev tip: run npm install and npm run dev in /Users/avrohom/Downloads/BlackHaven/worldmonitor-main.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            AtlasPanel(heading: "Nature Signal Stack v2", caption: "Live top-5 signals + risk score + alert thresholds.") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Risk: \(session.natureRiskScore)/100 (\(session.natureRiskBand))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Button("Refresh now") {
                            Task { await session.refreshNatureSignalStackNow(sendNotifications: true) }
                        }
                    }
                    Text("Alert thresholds: elevated >= \(session.natureElevatedThreshold), critical >= \(session.natureCriticalThreshold)")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Text(session.natureAlertSummary)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    if session.natureSignalTiles.isEmpty {
                        Text("No live tiles yet. Tap refresh to fetch current nature signals.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else {
                        ForEach(session.natureSignalTiles) { tile in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tile.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(tile.metric)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(tile.trend)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    Text(tile.severity)
                                        .font(.caption2)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                            }
                            if tile.id != session.natureSignalTiles.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            AtlasPanel(heading: "Critical Indicators", caption: "IUCN Red List + high-value wildlife/environment indicators and APIs.") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Self.natureSources) { source in
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(source.detail)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }
                                Spacer(minLength: 8)
                                if let url = URL(string: source.urlString) {
                                    Link(source.kind, destination: url)
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            if source.id != Self.natureSources.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            AtlasPanel(heading: "Charity Impact Monitor", caption: "Track progress, gaps, and funding need using Charity Navigator and nonprofit transparency sources.") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recommended scorecard dimensions:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Text("Impact progress trend · Where outcomes are lacking · Funding gap (needed vs secured) · Charity Navigator accountability signal.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Self.charitySources) { source in
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                        Text(source.detail)
                                            .font(.caption)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                    Spacer(minLength: 8)
                                    if let url = URL(string: source.urlString) {
                                        Link(source.kind, destination: url)
                                            .font(.caption.weight(.semibold))
                                    }
                                }
                                if source.id != Self.charitySources.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            AtlasPanel(heading: "Live Dashboard", caption: "Embedded worldmonitor.app or local endpoint.") {
                WorldMonitorWebView(url: endpointURL)
                    .frame(minHeight: 280)
            }
        }
        .padding(18)
        .onAppear {
            restoreEndpoint()
        }
    }

    // MARK: Logic
    private func restoreEndpoint() {
        let saved = UserDefaults.standard.string(forKey: Self.endpointStorageKey) ?? Self.hostedEndpoint
        applyEndpoint(saved, persist: false)
    }

    private func applyEndpoint(_ raw: String, persist: Bool = true) {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            endpointURL = URL(string: Self.hostedEndpoint)!
            endpointDraft = Self.hostedEndpoint
            endpointStatusLine = "World Monitor hosted endpoint active."
            return
        }

        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }

        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            endpointURL = URL(string: Self.hostedEndpoint)!
            endpointDraft = Self.hostedEndpoint
            endpointStatusLine = "Invalid endpoint; switched back to hosted World Monitor."
            if persist {
                UserDefaults.standard.set(Self.hostedEndpoint, forKey: Self.endpointStorageKey)
            }
            return
        }

        endpointURL = url
        endpointDraft = normalized
        let host = url.host?.lowercased() ?? ""
        if host == "127.0.0.1" || host == "localhost" {
            endpointStatusLine = "World Monitor local dev endpoint active."
        } else {
            endpointStatusLine = "World Monitor endpoint active: \(url.absoluteString)"
        }
        if persist {
            UserDefaults.standard.set(normalized, forKey: Self.endpointStorageKey)
        }
    }
}

private struct NatureSignalSource: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let kind: String
    let urlString: String
}

// MARK: - WebView Representable
private struct WorldMonitorWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if #available(macOS 13.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .desktop
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
