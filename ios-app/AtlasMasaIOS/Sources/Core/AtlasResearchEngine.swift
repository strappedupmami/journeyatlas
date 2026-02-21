import Foundation

enum AtlasResearchEngine {
    static let shared = AtlasResearchEngineModel(papers: AtlasResearchPack.load())
}

struct AtlasResearchEngineModel {
    private let papers: [AtlasResearchPaper]

    init(papers: [AtlasResearchPaper]) {
        self.papers = papers
    }

    func buildExecutionStreams(context: String, maxItems: Int = 4) -> [ResearchExecutionStream] {
        let tokens = tokenize(context)
        guard !tokens.isEmpty else { return [] }
        let prefersHebrew = containsHebrew(context)
        let emergencyMode = isEmergencyContext(context)

        let scored = papers
            .map { paper in
                let keywordScore = overlapScore(tokens: tokens, keywords: paper.keywords)
                let domainBoost = domainBoostForContext(context: context, domain: paper.domain)
                let recencyBoost = Double(max(0, paper.year - 2005)) * 0.005
                let score = keywordScore + domainBoost + recencyBoost
                return (paper, score)
            }
            .filter { $0.1 > 0.2 }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }

        let top = Array(scored.prefix(maxItems))
        return top.map { paper, score in
            let citation = ResearchCitation(
                id: paper.id,
                title: paper.title,
                year: paper.year,
                sourceURL: paper.sourceURL
            )
            let lane = travelDesignLane(for: paper.domain, prefersHebrew: prefersHebrew)
            let titlePrefix = streamTitlePrefix(prefersHebrew: prefersHebrew, emergencyMode: emergencyMode)
            let recommendation = emergencyMode
                ? emergencyRecommendation(base: paper.actionHint, prefersHebrew: prefersHebrew)
                : paper.actionHint
            return ResearchExecutionStream(
                id: "stream-\(paper.id)",
                domain: paper.domain,
                title: "\(titlePrefix): \(lane)",
                executionRecommendation: recommendation,
                whyItWorks: paper.actionableInsight,
                confidence: min(0.99, max(0.35, score)),
                citations: [citation]
            )
        }
    }

    private func overlapScore(tokens: Set<String>, keywords: [String]) -> Double {
        guard !keywords.isEmpty else { return 0 }
        let keywordSet = Set(keywords.map { $0.lowercased() })
        let overlap = tokens.intersection(keywordSet).count
        if overlap == 0 { return 0 }
        return Double(overlap) / Double(keywordSet.count)
    }

    private func domainBoostForContext(context: String, domain: String) -> Double {
        let lower = context.lowercased()
        switch domain {
        case "wealth":
            return containsAny(lower, ["cash", "revenue", "sales", "money", "profit", "pricing", "margin", "הכנסה", "רווח", "תמחור", "מכירות"]) ? 0.35 : 0
        case "travel", "safety", "resilience":
            return containsAny(lower, [
                "travel",
                "route",
                "van",
                "fleet",
                "risk",
                "emergency",
                "fallback",
                "journey",
                "novelty",
                "microadventure",
                "exploration",
                "מסלול",
                "נסיעה",
                "תפעול",
                "חוסן",
                "בטיחות",
            ]) ? 0.35 : 0
        case "emergency-response", "emergency-preparedness", "emergency-management", "crisis-management", "crisis-planning", "incident-command":
            return containsAny(lower, [
                "emergency",
                "crisis",
                "incident",
                "triage",
                "escalation",
                "rescue",
                "evacuation",
                "containment",
                "fallback",
                "command",
                "חירום",
                "משבר",
                "אירוע",
                "טריאז",
                "חילוץ",
                "פינוי",
                "פיקוד",
                "הסלמה",
                "מענה",
            ]) ? 0.45 : 0
        case "human-problem-solving", "human-performance", "biological-performance", "environmental-performance", "problem-solving":
            return containsAny(lower, [
                "problem solving",
                "cognitive",
                "metacognition",
                "focus",
                "sleep",
                "environment",
                "uncertainty",
                "fatigue",
                "decision quality",
                "human factors",
                "פתרון בעיות",
                "קוגניטיבי",
                "מטא קוגניציה",
                "גורמי אנוש",
                "שינה",
                "סביבה",
                "ביצועים",
            ]) ? 0.4 : 0
        case "technology-innovation", "systems-innovation", "digital-innovation", "physical-innovation", "innovation":
            return containsAny(lower, [
                "innovation",
                "prototype",
                "simulation",
                "hardware",
                "software",
                "digital",
                "physical",
                "systems design",
                "engineering",
                "experimentation",
                "חדשנות",
                "אב טיפוס",
                "סימולציה",
                "הנדסה",
                "מערכות",
                "דיגיטלי",
                "פיזי",
            ]) ? 0.4 : 0
        case "recovery", "health":
            return containsAny(lower, [
                "burnout",
                "fatigue",
                "stress",
                "recovery",
                "sleep",
                "focus",
                "nervous",
                "reflection",
                "neuroplasticity",
                "brain aging",
                "cognitive reserve",
                "התאוששות",
                "שחיקה",
                "רפלקציה",
                "נוירופלסטיות",
                "הזדקנות",
            ]) ? 0.35 : 0
        case "execution", "productivity", "planning":
            return containsAny(lower, ["action", "execute", "goal", "plan", "priorities", "next step", "design", "ביצוע", "יעד", "תוכנית", "תיעדוף"]) ? 0.35 : 0
        default:
            return 0.1
        }
    }

    private func travelDesignLane(for domain: String, prefersHebrew: Bool) -> String {
        if prefersHebrew {
            switch domain {
            case "wealth":
                return "עיצוב הכנסה וצמיחה"
            case "travel", "operations", "mobility":
                return "עיצוב תפעול מסע"
            case "safety", "resilience":
                return "עיצוב חוסן ובטיחות"
            case "emergency-response", "emergency-preparedness", "emergency-management", "crisis-management", "crisis-planning", "incident-command":
                return "עיצוב פיקוד חירום וניהול משבר"
            case "human-problem-solving", "human-performance", "biological-performance", "environmental-performance", "problem-solving":
                return "עיצוב יכולת פתרון בעיות אנושית"
            case "technology-innovation", "systems-innovation", "digital-innovation", "physical-innovation", "innovation":
                return "עיצוב חדשנות טכנולוגית"
            case "recovery", "health", "wellbeing":
                return "עיצוב התאוששות ותפקוד"
            case "execution", "productivity":
                return "עיצוב ביצוע יומי"
            case "planning", "decision-quality", "motivation", "skill-building", "team-ops":
                return "עיצוב אסטרטגיה"
            default:
                return "עיצוב מסע"
            }
        }
        switch domain {
        case "wealth":
            return "Revenue Design"
        case "travel", "operations", "mobility":
            return "Journey Operations Design"
        case "safety", "resilience":
            return "Continuity and Safety Design"
        case "emergency-response", "emergency-preparedness", "emergency-management", "crisis-management", "crisis-planning", "incident-command":
            return "Emergency Command Design"
        case "human-problem-solving", "human-performance", "biological-performance", "environmental-performance", "problem-solving":
            return "Human Problem-Solving Design"
        case "technology-innovation", "systems-innovation", "digital-innovation", "physical-innovation", "innovation":
            return "Technology Innovation Design"
        case "recovery", "health", "wellbeing":
            return "Recovery Design"
        case "execution", "productivity":
            return "Execution Design"
        case "planning", "decision-quality", "motivation", "skill-building", "team-ops":
            return "Strategy Design"
        default:
            return "Travel Design"
        }
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func containsHebrew(_ text: String) -> Bool {
        text.range(of: "[\\u0590-\\u05FF]", options: .regularExpression) != nil
    }

    private func isEmergencyContext(_ text: String) -> Bool {
        let lower = text.lowercased()
        return containsAny(lower, [
            "emergency",
            "crisis",
            "incident",
            "triage",
            "evacuate",
            "rescue",
            "urgent",
            "life threatening",
            "חירום",
            "משבר",
            "אירוע",
            "דחוף",
            "פיקוד",
            "חילוץ",
            "פינוי",
        ])
    }

    private func streamTitlePrefix(prefersHebrew: Bool, emergencyMode: Bool) -> String {
        if prefersHebrew {
            return emergencyMode ? "מסלול פיקוד חירום" : "מסלול תכנון מסע"
        }
        return emergencyMode ? "Emergency command lane" : "Travel Design lane"
    }

    private func emergencyRecommendation(base: String, prefersHebrew: Bool) -> String {
        if prefersHebrew {
            return "עכשיו: טריאז', ייצוב, תקשורת, והפעלה לפי נוהל חירום. \(base)"
        }
        return "Immediate order: triage, stabilize, communicate, and execute emergency protocol. \(base)"
    }

    private func tokenize(_ input: String) -> Set<String> {
        Set(
            input.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }
}
