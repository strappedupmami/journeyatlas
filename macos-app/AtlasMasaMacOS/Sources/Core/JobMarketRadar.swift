import Foundation

enum JobPlatform: String, Codable, CaseIterable, Identifiable {
    case indeed
    case glassdoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .indeed:
            return "Indeed"
        case .glassdoor:
            return "Glassdoor"
        }
    }
}

struct JobPlatformLink: Codable, Hashable, Identifiable {
    let platform: JobPlatform
    let url: String

    var id: String { "\(platform.rawValue):\(url)" }
}

struct JobOpportunity: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let location: String
    let salaryBandUSD: String
    let track: String
    let industryFocus: String
    let remoteFriendly: Bool
    let links: [JobPlatformLink]
}

enum JobMarketRadar {
    static func topOpportunities(
        highPayingTrack: String,
        industryFocus: String,
        regionHint: String,
        limit: Int = 5
    ) -> [JobOpportunity] {
        let normalizedTrack = highPayingTrack.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedIndustry = industryFocus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRegion = regionHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let scored = roleCatalog
            .map { role -> (role: RoleTemplate, score: Int) in
                var score = role.salaryCeilingKUSD
                if normalizedTrack != "none", role.track == normalizedTrack {
                    score += 160
                }
                if role.industryTags.contains(normalizedIndustry) {
                    score += 120
                }
                if !normalizedRegion.isEmpty,
                   role.location.lowercased().contains(normalizedRegion)
                {
                    score += 80
                }
                if role.remoteFriendly {
                    score += 24
                }
                return (role: role, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.role.title < rhs.role.title
                }
                return lhs.score > rhs.score
            }

        return scored
            .prefix(max(1, limit))
            .map { entry in
                JobOpportunity(
                    id: entry.role.id,
                    title: entry.role.title,
                    location: entry.role.location,
                    salaryBandUSD: entry.role.salaryBandUSD,
                    track: entry.role.track,
                    industryFocus: entry.role.industryTags.first ?? "general",
                    remoteFriendly: entry.role.remoteFriendly,
                    links: buildPlatformLinks(title: entry.role.title, location: entry.role.location)
                )
            }
    }

    static func platformSummary(for opportunity: JobOpportunity) -> String {
        opportunity.links
            .map { "\($0.platform.label): \($0.url)" }
            .joined(separator: " | ")
    }

    static func blockerLabel(for blocker: String) -> String {
        switch blocker {
        case "skills_gap":
            return "skills gap"
        case "credential_gap":
            return "credential gap"
        case "language_gap":
            return "language gap"
        case "network_gap":
            return "network gap"
        case "relocation":
            return "relocation constraints"
        case "visa_legal":
            return "visa/legal eligibility"
        case "schedule_family":
            return "schedule/family load"
        case "confidence":
            return "confidence/interview fear"
        default:
            return blocker.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func blockerResolution(blocker: String, supportMode: String?) -> String {
        let blockerText = blockerLabel(for: blocker)
        let supportLabel = supportModeLabel(for: supportMode)

        let blockerPlan: String
        switch blocker {
        case "skills_gap":
            blockerPlan = "Convert target role requirements into a 6-week skill sprint with two proof-of-work projects and weekly review."
        case "credential_gap":
            blockerPlan = "Bridge credentials with a targeted certification, portfolio evidence, and role-adjacent experience plan."
        case "language_gap":
            blockerPlan = "Run daily communication drills plus role-specific interview scripts until fluency pressure drops."
        case "network_gap":
            blockerPlan = "Launch a referral pipeline: 5 warm intros/week + hiring manager outreach + value-first follow-ups."
        case "relocation":
            blockerPlan = "Filter for remote-first or relocation-sponsored roles and design a phased move plan with cost controls."
        case "visa_legal":
            blockerPlan = "Prioritize visa-compatible markets/roles and build an eligibility checklist before applying at scale."
        case "schedule_family":
            blockerPlan = "Switch to high-leverage application windows and async-friendly role targets with predictable shifts."
        case "confidence":
            blockerPlan = "Use mock interviews + negotiation scripts + gradual exposure until response confidence stabilizes."
        default:
            blockerPlan = "Break the blocker into one solvable weekly constraint and execute one direct action daily."
        }

        return "Primary blocker: \(blockerText). Support mode: \(supportLabel). Resolution protocol: \(blockerPlan)"
    }

    private static func supportModeLabel(for supportMode: String?) -> String {
        switch supportMode {
        case "portfolio_plan":
            return "portfolio + proof-of-work"
        case "interview_prep":
            return "interview + negotiation prep"
        case "networking_system":
            return "networking/referral system"
        case "credential_bridge":
            return "credential bridge"
        case "language_plan":
            return "language communication plan"
        case "relocation_plan":
            return "relocation-compatible planning"
        case "legal_eligibility_plan":
            return "legal eligibility plan"
        default:
            return "general execution support"
        }
    }

    private static func buildPlatformLinks(title: String, location: String) -> [JobPlatformLink] {
        let titleQuery = encodeQuery(title)
        let locationQuery = encodeQuery(location)
        let combinedQuery = encodeQuery("\(title) \(location)")

        return [
            JobPlatformLink(
                platform: .indeed,
                url: "https://www.indeed.com/jobs?q=\(titleQuery)&l=\(locationQuery)"
            ),
            JobPlatformLink(
                platform: .glassdoor,
                url: "https://www.glassdoor.com/Job/jobs.htm?sc.keyword=\(combinedQuery)"
            ),
        ]
    }

    private static func encodeQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? value
    }

    private struct RoleTemplate {
        let id: String
        let title: String
        let track: String
        let industryTags: [String]
        let location: String
        let salaryBandUSD: String
        let salaryCeilingKUSD: Int
        let remoteFriendly: Bool
    }

    private static let roleCatalog: [RoleTemplate] = [
        RoleTemplate(
            id: "ai-staff-engineer-zurich",
            title: "Staff AI Engineer",
            track: "engineering",
            industryTags: ["software_ai", "cybersecurity"],
            location: "Zurich, Switzerland",
            salaryBandUSD: "$240k-$480k",
            salaryCeilingKUSD: 480,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "ml-systems-engineer-sf",
            title: "ML Systems Engineer",
            track: "engineering",
            industryTags: ["software_ai"],
            location: "San Francisco, USA",
            salaryBandUSD: "$230k-$450k",
            salaryCeilingKUSD: 450,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "principal-security-engineer-nyc",
            title: "Principal Security Engineer",
            track: "engineering",
            industryTags: ["cybersecurity", "software_ai"],
            location: "New York, USA",
            salaryBandUSD: "$220k-$420k",
            salaryCeilingKUSD: 420,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "director-product-ai-london",
            title: "Director of Product (AI)",
            track: "product",
            industryTags: ["software_ai", "finance"],
            location: "London, UK",
            salaryBandUSD: "$210k-$390k",
            salaryCeilingKUSD: 390,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "vp-enterprise-sales-nyc",
            title: "VP Enterprise Sales",
            track: "sales",
            industryTags: ["enterprise_sales", "software_ai"],
            location: "New York, USA",
            salaryBandUSD: "$250k-$600k (OTE)",
            salaryCeilingKUSD: 600,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "enterprise-ae-singapore",
            title: "Enterprise Account Executive",
            track: "sales",
            industryTags: ["enterprise_sales", "finance"],
            location: "Singapore",
            salaryBandUSD: "$180k-$420k (OTE)",
            salaryCeilingKUSD: 420,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "ops-director-dubai",
            title: "Director of Operations",
            track: "operations",
            industryTags: ["operations_logistics", "healthcare"],
            location: "Dubai, UAE",
            salaryBandUSD: "$180k-$360k",
            salaryCeilingKUSD: 360,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "supply-chain-vp-rotterdam",
            title: "VP Supply Chain",
            track: "operations",
            industryTags: ["operations_logistics"],
            location: "Rotterdam, Netherlands",
            salaryBandUSD: "$200k-$380k",
            salaryCeilingKUSD: 380,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "ib-associate-nyc",
            title: "Investment Banking Associate",
            track: "finance_track",
            industryTags: ["finance"],
            location: "New York, USA",
            salaryBandUSD: "$220k-$500k",
            salaryCeilingKUSD: 500,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "quant-researcher-london",
            title: "Quantitative Researcher",
            track: "finance_track",
            industryTags: ["finance", "software_ai"],
            location: "London, UK",
            salaryBandUSD: "$240k-$550k",
            salaryCeilingKUSD: 550,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "anesthesiology-attending-us",
            title: "Anesthesiology Attending",
            track: "clinical",
            industryTags: ["healthcare"],
            location: "Houston, USA",
            salaryBandUSD: "$300k-$650k",
            salaryCeilingKUSD: 650,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "telemedicine-specialist-global",
            title: "Telemedicine Specialist",
            track: "clinical",
            industryTags: ["healthcare", "software_ai"],
            location: "Remote / Global",
            salaryBandUSD: "$180k-$350k",
            salaryCeilingKUSD: 350,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "master-electrician-australia",
            title: "Master Electrician (Industrial)",
            track: "trade_mastery",
            industryTags: ["skilled_trades", "operations_logistics"],
            location: "Perth, Australia",
            salaryBandUSD: "$160k-$300k",
            salaryCeilingKUSD: 300,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "offshore-tech-specialist-norway",
            title: "Offshore Technical Specialist",
            track: "trade_mastery",
            industryTags: ["skilled_trades", "operations_logistics"],
            location: "Stavanger, Norway",
            salaryBandUSD: "$180k-$340k",
            salaryCeilingKUSD: 340,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "commercial-real-estate-broker-miami",
            title: "Commercial Real Estate Broker",
            track: "real_estate_track",
            industryTags: ["real_estate", "enterprise_sales"],
            location: "Miami, USA",
            salaryBandUSD: "$180k-$520k",
            salaryCeilingKUSD: 520,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "real-estate-asset-manager-london",
            title: "Real Estate Asset Manager",
            track: "real_estate_track",
            industryTags: ["real_estate", "finance"],
            location: "London, UK",
            salaryBandUSD: "$200k-$480k",
            salaryCeilingKUSD: 480,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "industrial-logistics-network-lead-singapore",
            title: "Logistics Network Optimization Lead",
            track: "operations",
            industryTags: ["operations_logistics", "software_ai"],
            location: "Singapore",
            salaryBandUSD: "$190k-$360k",
            salaryCeilingKUSD: 360,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "hospital-operations-chief-toronto",
            title: "Healthcare Operations Chief",
            track: "operations",
            industryTags: ["healthcare", "operations_logistics"],
            location: "Toronto, Canada",
            salaryBandUSD: "$220k-$430k",
            salaryCeilingKUSD: 430,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "global-media-monetization-director-nyc",
            title: "Global Media Monetization Director",
            track: "media_revenue",
            industryTags: ["media_creator", "enterprise_sales"],
            location: "New York, USA",
            salaryBandUSD: "$210k-$520k",
            salaryCeilingKUSD: 520,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "creator-partnerships-lead-la",
            title: "Creator Partnerships Lead",
            track: "media_revenue",
            industryTags: ["media_creator", "software_ai"],
            location: "Los Angeles, USA",
            salaryBandUSD: "$170k-$360k",
            salaryCeilingKUSD: 360,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "ai-solutions-architect-berlin",
            title: "AI Solutions Architect",
            track: "engineering",
            industryTags: ["software_ai", "enterprise_sales"],
            location: "Berlin, Germany",
            salaryBandUSD: "$190k-$390k",
            salaryCeilingKUSD: 390,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "enterprise-revenue-operations-lead-dublin",
            title: "Revenue Operations Lead",
            track: "operations",
            industryTags: ["enterprise_sales", "software_ai"],
            location: "Dublin, Ireland",
            salaryBandUSD: "$170k-$320k",
            salaryCeilingKUSD: 320,
            remoteFriendly: true
        ),
        RoleTemplate(
            id: "private-credit-analyst-chicago",
            title: "Private Credit Analyst",
            track: "finance_track",
            industryTags: ["finance", "real_estate"],
            location: "Chicago, USA",
            salaryBandUSD: "$180k-$420k",
            salaryCeilingKUSD: 420,
            remoteFriendly: false
        ),
        RoleTemplate(
            id: "high-end-remodeling-project-manager-texas",
            title: "High-End Remodeling Project Manager",
            track: "trade_mastery",
            industryTags: ["skilled_trades", "real_estate"],
            location: "Austin, USA",
            salaryBandUSD: "$150k-$320k",
            salaryCeilingKUSD: 320,
            remoteFriendly: false
        ),
    ]
}
