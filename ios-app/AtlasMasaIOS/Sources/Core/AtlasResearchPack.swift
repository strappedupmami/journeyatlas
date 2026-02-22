import Foundation

enum AtlasResearchPack {
    static func load() -> [AtlasResearchPaper] {
        guard let data = atlasResearchPackJSON.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([AtlasResearchPaper].self, from: data)) ?? []
    }
}

private let atlasResearchPackJSON = #"""
[
  {
    "id": "hardware-software-co-design-2022",
    "title": "Hardware-software co-design for energy-efficient edge intelligence",
    "year": 2022,
    "domain": "physical-innovation",
    "actionable_insight": "Joint hardware-software optimization improves efficiency and reliability for local intelligence workloads.",
    "action_hint": "Co-design model, runtime, and hardware profile before scaling edge deployment.",
    "source_url": "https://doi.org/10.1145/3492321.3519552",
    "keywords": [
      "hardware software",
      "co-design",
      "edge ai",
      "efficiency"
    ]
  },
  {
    "id": "distributed-teams-problem-solving-2021",
    "title": "Distributed team problem-solving under uncertainty",
    "year": 2021,
    "domain": "problem-solving",
    "actionable_insight": "Shared mental models and explicit communication cadences improve distributed decision quality.",
    "action_hint": "Use structured update rounds with role-specific signal templates during uncertainty.",
    "source_url": "https://doi.org/10.1037/apl0000884",
    "keywords": [
      "distributed teams",
      "problem solving",
      "uncertainty",
      "coordination"
    ]
  },
  {
    "id": "mass-casualty-triage-review-2021",
    "title": "Mass casualty triage and disaster response systems: A systematic review",
    "year": 2021,
    "domain": "emergency-response",
    "actionable_insight": "Standardized triage protocols improve throughput and reduce critical misallocation during surge events.",
    "action_hint": "Define a fixed triage sequence with explicit escalation thresholds before incident onset.",
    "source_url": "https://pubmed.ncbi.nlm.nih.gov/33837115/",
    "keywords": [
      "triage",
      "mass casualty",
      "incident response",
      "prioritization"
    ]
  },
  {
    "id": "crisis-leadership-healthcare-2020",
    "title": "Crisis leadership and coordination in high-stakes healthcare systems",
    "year": 2020,
    "domain": "crisis-management",
    "actionable_insight": "Clear command hierarchy and communication protocols reduce delays under crisis load.",
    "action_hint": "Create command roles, comms channels, and authority handoff rules for each severity tier.",
    "source_url": "https://pubmed.ncbi.nlm.nih.gov/32278330/",
    "keywords": [
      "crisis management",
      "leadership",
      "coordination",
      "command"
    ]
  },
  {
    "id": "digital-physical-twin-2020",
    "title": "Digital twins for resilient cyber-physical operations",
    "year": 2020,
    "domain": "digital-innovation",
    "actionable_insight": "Digital twin simulation enables safer testing before physical deployment.",
    "action_hint": "Validate high-risk decisions in simulation before real-world rollout.",
    "source_url": "https://doi.org/10.1016/j.compind.2020.103299",
    "keywords": [
      "digital twin",
      "simulation",
      "cyber-physical",
      "risk reduction"
    ]
  },
  {
    "id": "stress-executive-meta-2020",
    "title": "Effects of acute stress on executive functions: a meta-analysis",
    "year": 2020,
    "domain": "human-performance",
    "actionable_insight": "Acute stress impairs cognitive flexibility and working memory under time pressure.",
    "action_hint": "Use controlled breathing plus pre-committed checklists before high-stakes problem-solving.",
    "source_url": "https://pubmed.ncbi.nlm.nih.gov/32707058/",
    "keywords": [
      "stress",
      "executive function",
      "cognitive flexibility",
      "human performance"
    ]
  },
  {
    "id": "mobility-wellbeing-2020",
    "title": "Transport and wellbeing: A systematic review",
    "year": 2020,
    "domain": "travel",
    "actionable_insight": "Mobility systems influence stress, autonomy, and life satisfaction.",
    "action_hint": "Design routes and modes for reduced stress load, not only speed.",
    "source_url": "https://doi.org/10.1016/j.jtrangeo.2020.102838",
    "keywords": [
      "mobility",
      "wellbeing",
      "transport",
      "stress"
    ]
  },
  {
    "id": "incident-command-preparedness-2019",
    "title": "Incident command system implementation and preparedness outcomes",
    "year": 2019,
    "domain": "incident-command",
    "actionable_insight": "Prepared organizations with practiced ICS routines recover faster from operational shocks.",
    "action_hint": "Run recurring incident-command drills with post-incident learning capture.",
    "source_url": "https://www.fema.gov/emergency-managers/nims/components",
    "keywords": [
      "incident command",
      "preparedness",
      "drills",
      "continuity"
    ]
  },
  {
    "id": "systems-engineering-resilience-2019",
    "title": "Systems engineering for resilient infrastructure and services",
    "year": 2019,
    "domain": "systems-innovation",
    "actionable_insight": "Resilience increases when systems are designed with graceful degradation and modular recovery.",
    "action_hint": "Engineer critical services for staged degradation and fast component-level recovery.",
    "source_url": "https://doi.org/10.1007/s00158-018-2139-5",
    "keywords": [
      "systems engineering",
      "resilience",
      "modularity",
      "recovery"
    ]
  },
  {
    "id": "digital-overload-2019",
    "title": "Technostress and employee outcomes: A meta-analysis",
    "year": 2019,
    "domain": "recovery",
    "actionable_insight": "Digital overload is linked to strain and reduced performance.",
    "action_hint": "Create bounded communication windows to preserve deep work capacity.",
    "source_url": "https://doi.org/10.1177/0018726719869142",
    "keywords": [
      "technostress",
      "burnout",
      "focus",
      "performance"
    ]
  },
  {
    "id": "fatigue-driving-2018",
    "title": "Fatigue and driving performance: a meta-analysis",
    "year": 2018,
    "domain": "safety",
    "actionable_insight": "Fatigue substantially degrades driving performance and hazard response.",
    "action_hint": "Apply mandatory fatigue gates before long driving segments.",
    "source_url": "https://doi.org/10.1016/j.aap.2018.02.017",
    "keywords": [
      "fatigue",
      "driving",
      "safety",
      "risk"
    ]
  },
  {
    "id": "rapid-prototyping-innovation-2018",
    "title": "Rapid prototyping and innovation performance in product systems",
    "year": 2018,
    "domain": "technology-innovation",
    "actionable_insight": "Short hypothesis-test cycles improve innovation throughput while reducing downstream rework.",
    "action_hint": "Adopt hypothesis-driven prototyping with explicit pass/fail criteria per iteration.",
    "source_url": "https://doi.org/10.1016/j.respol.2017.08.014",
    "keywords": [
      "innovation",
      "prototyping",
      "product systems",
      "iteration"
    ]
  },
  {
    "id": "simulation-disaster-training-2018",
    "title": "Simulation-based disaster training and emergency team performance",
    "year": 2018,
    "domain": "emergency-preparedness",
    "actionable_insight": "High-fidelity simulation improves emergency team coordination and decision quality.",
    "action_hint": "Schedule scenario-based rehearsals that stress communication, triage, and resource allocation.",
    "source_url": "https://pubmed.ncbi.nlm.nih.gov/29621758/",
    "keywords": [
      "simulation",
      "emergency preparedness",
      "team training",
      "decision quality"
    ]
  },
  {
    "id": "metacognition-problem-solving-2017",
    "title": "Metacognitive instruction improves complex problem-solving performance",
    "year": 2017,
    "domain": "human-problem-solving",
    "actionable_insight": "Metacognitive monitoring improves error detection and transfer in complex tasks.",
    "action_hint": "Insert short reflect-check loops after each critical decision in complex workflows.",
    "source_url": "https://doi.org/10.1016/j.learninstruc.2016.12.005",
    "keywords": [
      "metacognition",
      "problem solving",
      "learning transfer",
      "decision quality"
    ]
  },
  {
    "id": "goal-progress-2016",
    "title": "Progress monitoring and goal attainment: A meta-analysis",
    "year": 2016,
    "domain": "execution",
    "actionable_insight": "Monitoring progress improves the likelihood of goal completion.",
    "action_hint": "Add a visible checkpoint log for daily and weekly goals.",
    "source_url": "https://doi.org/10.1037/bul0000025",
    "keywords": [
      "progress",
      "goals",
      "monitoring",
      "execution"
    ]
  },
  {
    "id": "indoor-environment-cognition-2016",
    "title": "The impact of green buildings on cognitive function",
    "year": 2016,
    "domain": "environmental-performance",
    "actionable_insight": "Ventilation and low pollutant exposure significantly improve cognitive performance scores.",
    "action_hint": "Treat air quality and environmental noise as first-class variables in cognitive workloads.",
    "source_url": "https://doi.org/10.1016/S0140-6736(16)30040-3",
    "keywords": [
      "environment",
      "air quality",
      "cognition",
      "performance"
    ]
  },
  {
    "id": "financial-behavior-2015",
    "title": "Financial literacy, financial education, and downstream financial behaviors",
    "year": 2015,
    "domain": "wealth",
    "actionable_insight": "Applied financial education improves downstream behaviors when tied to action.",
    "action_hint": "Tie weekly financial review to one concrete account-level action.",
    "source_url": "https://doi.org/10.1093/jcr/ucv031",
    "keywords": [
      "financial literacy",
      "wealth",
      "behavior",
      "planning"
    ]
  },
  {
    "id": "walking-creativity-2014",
    "title": "Give your ideas some legs: The positive effect of walking on creative thinking",
    "year": 2014,
    "domain": "biological-performance",
    "actionable_insight": "Short walking intervals increase divergent thinking output.",
    "action_hint": "Add 10-15 minute walking ideation intervals before major design decisions.",
    "source_url": "https://doi.org/10.1037/a0036577",
    "keywords": [
      "walking",
      "creativity",
      "biological conditions",
      "problem solving"
    ]
  },
  {
    "id": "travel-novelty-2014",
    "title": "The impact of novelty and familiarity on destination satisfaction",
    "year": 2014,
    "domain": "travel",
    "actionable_insight": "Balanced novelty and familiarity can improve travel satisfaction and adaptability.",
    "action_hint": "Pair one novel segment with one familiar fallback in route plans.",
    "source_url": "https://doi.org/10.1016/j.tourman.2013.10.011",
    "keywords": [
      "travel",
      "novelty",
      "adaptation",
      "route"
    ]
  },
  {
    "id": "scarcity-2013",
    "title": "Some Consequences of Having Too Little",
    "year": 2013,
    "domain": "decision-quality",
    "actionable_insight": "Scarcity captures attention and reduces cognitive bandwidth for other priorities.",
    "action_hint": "Use a minimal daily decision protocol when bandwidth is constrained.",
    "source_url": "https://doi.org/10.1126/science.1232491",
    "keywords": [
      "scarcity",
      "bandwidth",
      "decisions",
      "stress"
    ]
  },
  {
    "id": "self-control-2012",
    "title": "A meta-analysis of self-control and organizational outcomes",
    "year": 2012,
    "domain": "productivity",
    "actionable_insight": "Self-control predicts stronger performance and lower counterproductive behavior.",
    "action_hint": "Pre-commit environment controls around your highest-value task window.",
    "source_url": "https://doi.org/10.1111/j.1744-6570.2012.01285.x",
    "keywords": [
      "self-control",
      "performance",
      "productivity",
      "discipline"
    ]
  },
  {
    "id": "implementation-enterprise-2012",
    "title": "Execution as Strategy",
    "year": 2012,
    "domain": "operations",
    "actionable_insight": "Operational execution quality compounds strategic advantage over time.",
    "action_hint": "Review execution lag weekly and remove one recurring bottleneck.",
    "source_url": "https://doi.org/10.5465/amp.2012.0056",
    "keywords": [
      "execution",
      "strategy",
      "operations",
      "enterprise"
    ]
  },
  {
    "id": "sleep-performance-2010",
    "title": "A Meta-Analysis of the Impact of Short-Term Sleep Deprivation on Cognitive Variables",
    "year": 2010,
    "domain": "recovery",
    "actionable_insight": "Sleep loss impairs attention, working memory, and executive performance.",
    "action_hint": "Prioritize sleep-protective scheduling before high-stakes execution days.",
    "source_url": "https://doi.org/10.1037/a0018883",
    "keywords": [
      "sleep",
      "cognition",
      "performance",
      "recovery"
    ]
  },
  {
    "id": "habit-formation-2010",
    "title": "How are habits formed: Modelling habit formation in the real world",
    "year": 2010,
    "domain": "productivity",
    "actionable_insight": "Habit automaticity grows through repetition in stable contexts.",
    "action_hint": "Anchor your key daily routine to the same time/context for consistency.",
    "source_url": "https://doi.org/10.1002/ejsp.674",
    "keywords": [
      "habits",
      "routine",
      "consistency",
      "behavior"
    ]
  },
  {
    "id": "mental-contrasting-2010",
    "title": "Mental Contrasting and Implementation Intentions",
    "year": 2010,
    "domain": "execution",
    "actionable_insight": "Combining desired outcomes with obstacle planning improves goal attainment.",
    "action_hint": "Define one desired outcome and its biggest obstacle, then attach a trigger plan.",
    "source_url": "https://doi.org/10.1016/j.socec.2010.08.002",
    "keywords": [
      "obstacles",
      "planning",
      "goal attainment",
      "execution"
    ]
  },
  {
    "id": "checklist-medicine-2009",
    "title": "A Surgical Safety Checklist to Reduce Morbidity and Mortality",
    "year": 2009,
    "domain": "operations",
    "actionable_insight": "Standardized checklists can reduce critical failures in complex systems.",
    "action_hint": "Create pre-drive and pre-sleep safety checklists with strict completion states.",
    "source_url": "https://doi.org/10.1056/NEJMsa0810119",
    "keywords": [
      "checklist",
      "safety",
      "operations",
      "reliability"
    ]
  },
  {
    "id": "multitasking-cost-2009",
    "title": "Cognitive control in media multitaskers",
    "year": 2009,
    "domain": "productivity",
    "actionable_insight": "Heavy multitasking is associated with weaker task filtering and switching control.",
    "action_hint": "Run single-task focus sprints and reduce notification switching.",
    "source_url": "https://doi.org/10.1073/pnas.0903620106",
    "keywords": [
      "multitasking",
      "focus",
      "attention",
      "deep work"
    ]
  },
  {
    "id": "acute-stress-2009",
    "title": "Stress and decision making: a review and conceptual framework",
    "year": 2009,
    "domain": "resilience",
    "actionable_insight": "Acute stress can shift decision behavior and reduce strategic flexibility.",
    "action_hint": "Use pre-committed checklists under stress rather than ad-hoc decisions.",
    "source_url": "https://doi.org/10.1016/j.neubiorev.2009.08.007",
    "keywords": [
      "stress",
      "decision",
      "resilience",
      "checklist"
    ]
  },
  {
    "id": "exercise-cognition-2008",
    "title": "Be smart, exercise your heart: exercise effects on brain and cognition",
    "year": 2008,
    "domain": "health",
    "actionable_insight": "Regular aerobic activity is associated with improved cognitive function.",
    "action_hint": "Insert short activity blocks to sustain cognitive throughput.",
    "source_url": "https://doi.org/10.1038/nrn2298",
    "keywords": [
      "exercise",
      "brain",
      "cognition",
      "energy"
    ]
  },
  {
    "id": "prosocial-spending-2008",
    "title": "Spending Money on Others Promotes Happiness",
    "year": 2008,
    "domain": "wellbeing",
    "actionable_insight": "Prosocial spending can improve subjective wellbeing.",
    "action_hint": "Build recurring charity allocation as part of wealth goals.",
    "source_url": "https://doi.org/10.1126/science.1150952",
    "keywords": [
      "charity",
      "wellbeing",
      "money",
      "purpose"
    ]
  },
  {
    "id": "attention-restoration-2008",
    "title": "The Cognitive Benefits of Interacting With Nature",
    "year": 2008,
    "domain": "recovery",
    "actionable_insight": "Nature exposure can improve directed attention and cognitive performance.",
    "action_hint": "Schedule a short restorative outdoor reset before deep work.",
    "source_url": "https://doi.org/10.1111/j.1467-9280.2008.02225.x",
    "keywords": [
      "attention",
      "nature",
      "recovery",
      "focus"
    ]
  },
  {
    "id": "procrastination-2007",
    "title": "The nature of procrastination: a meta-analytic and theoretical review",
    "year": 2007,
    "domain": "execution",
    "actionable_insight": "Procrastination is strongly associated with impulsiveness and poor self-regulation.",
    "action_hint": "Break work into immediate action starts with visible commitment cues.",
    "source_url": "https://doi.org/10.1037/0033-2909.133.1.65",
    "keywords": [
      "procrastination",
      "execution",
      "self-regulation",
      "action"
    ]
  },
  {
    "id": "time-management-2007",
    "title": "Time management: A meta-analysis",
    "year": 2007,
    "domain": "productivity",
    "actionable_insight": "Time management behaviors are associated with performance and perceived control.",
    "action_hint": "Use a fixed daily planning ritual with explicit top priorities.",
    "source_url": "https://doi.org/10.1037/1076-898X.13.4.255",
    "keywords": [
      "time management",
      "productivity",
      "planning",
      "performance"
    ]
  },
  {
    "id": "adaptive-expertise-2006",
    "title": "Adaptive expertise and flexibility in complex problem solving",
    "year": 2006,
    "domain": "skill-building",
    "actionable_insight": "Adaptive expertise combines efficiency with innovation under changing constraints.",
    "action_hint": "Pair routine optimization with one deliberate variation experiment weekly.",
    "source_url": "https://doi.org/10.1007/s11251-006-9008-4",
    "keywords": [
      "adaptation",
      "expertise",
      "problem solving",
      "innovation"
    ]
  },
  {
    "id": "decision-fatigue-2006",
    "title": "Decision Fatigue and Self-Regulatory Resource Depletion",
    "year": 2006,
    "domain": "decision-quality",
    "actionable_insight": "Sequential decision load can degrade later decisions.",
    "action_hint": "Front-load high-stakes decisions and simplify low-impact choices.",
    "source_url": "https://doi.org/10.1037/0022-3514.94.5.883",
    "keywords": [
      "decision fatigue",
      "self-regulation",
      "planning",
      "execution"
    ]
  },
  {
    "id": "resilience-trajectories-2004",
    "title": "Loss, Trauma, and Human Resilience",
    "year": 2004,
    "domain": "resilience",
    "actionable_insight": "Resilience often follows trajectories that can be supported with structured adaptation.",
    "action_hint": "Switch to reduced-load mode after major disruption and ramp deliberately.",
    "source_url": "https://doi.org/10.1037/0003-066X.59.1.20",
    "keywords": [
      "resilience",
      "trauma",
      "adaptation",
      "recovery"
    ]
  },
  {
    "id": "risk-perception-2004",
    "title": "Risk as feelings",
    "year": 2004,
    "domain": "decision-quality",
    "actionable_insight": "Affect can dominate risk judgment under uncertainty.",
    "action_hint": "Use objective risk gates before making high-impact moves under stress.",
    "source_url": "https://doi.org/10.1037/0033-295X.111.2.385",
    "keywords": [
      "risk",
      "decision",
      "uncertainty",
      "safety"
    ]
  },
  {
    "id": "save-more-tomorrow-2004",
    "title": "Save More Tomorrow: Using Behavioral Economics to Increase Employee Saving",
    "year": 2004,
    "domain": "wealth",
    "actionable_insight": "Pre-committing future increases can improve long-term savings behavior.",
    "action_hint": "Set an automatic rule to increase saving rate at each income step-up.",
    "source_url": "https://doi.org/10.1086/380085",
    "keywords": [
      "wealth",
      "saving",
      "automation",
      "behavioral economics"
    ]
  },
  {
    "id": "goal-setting-2002",
    "title": "Building a Practically Useful Theory of Goal Setting and Task Motivation",
    "year": 2002,
    "domain": "execution",
    "actionable_insight": "Specific and challenging goals increase performance when feedback is present.",
    "action_hint": "Convert broad intent into one specific measurable target for the next work block.",
    "source_url": "https://doi.org/10.1037/0033-2909.128.3.705",
    "keywords": [
      "goals",
      "performance",
      "execution",
      "feedback"
    ]
  },
  {
    "id": "high-reliability-2001",
    "title": "Managing the Unexpected: Assuring High Performance in an Age of Complexity",
    "year": 2001,
    "domain": "operations",
    "actionable_insight": "High-reliability organizations maintain preoccupation with failure and recovery capacity.",
    "action_hint": "Track near-misses and convert them into explicit preventive controls.",
    "source_url": "https://doi.org/10.1002/hrm.1003",
    "keywords": [
      "reliability",
      "operations",
      "risk",
      "continuity"
    ]
  },
  {
    "id": "default-effects-2001",
    "title": "The power of suggestion: Inertia in 401(k) participation and savings behavior",
    "year": 2001,
    "domain": "wealth",
    "actionable_insight": "Defaults strongly influence financial behavior choices.",
    "action_hint": "Set robust financial defaults so good behavior is automatic.",
    "source_url": "https://doi.org/10.1162/003355301753265543",
    "keywords": [
      "defaults",
      "saving",
      "wealth",
      "automation"
    ]
  },
  {
    "id": "self-determination-2000",
    "title": "Self-Determination Theory and the Facilitation of Intrinsic Motivation",
    "year": 2000,
    "domain": "motivation",
    "actionable_insight": "Autonomy, competence, and relatedness drive sustainable motivation.",
    "action_hint": "Choose one task that aligns with personal autonomy and competence growth.",
    "source_url": "https://doi.org/10.1037/0003-066X.55.1.68",
    "keywords": [
      "motivation",
      "autonomy",
      "competence",
      "wellbeing"
    ]
  },
  {
    "id": "implementation-intentions-1999",
    "title": "Implementation Intentions: Strong Effects of Simple Plans",
    "year": 1999,
    "domain": "execution",
    "actionable_insight": "If-then planning increases follow-through on intended behaviors.",
    "action_hint": "Write one if-then trigger for the next critical action.",
    "source_url": "https://doi.org/10.1037/0022-3514.54.4.493",
    "keywords": [
      "planning",
      "if-then",
      "habits",
      "execution"
    ]
  },
  {
    "id": "psychological-safety-1999",
    "title": "Psychological Safety and Learning Behavior in Work Teams",
    "year": 1999,
    "domain": "team-ops",
    "actionable_insight": "Psychological safety supports learning, reporting, and iteration quality.",
    "action_hint": "Build low-friction reporting loops for failures and near-misses.",
    "source_url": "https://doi.org/10.2307/2666999",
    "keywords": [
      "team",
      "learning",
      "feedback",
      "operations"
    ]
  },
  {
    "id": "deep-practice-1993",
    "title": "The role of deliberate practice in the acquisition of expert performance",
    "year": 1993,
    "domain": "skill-building",
    "actionable_insight": "Expert performance is strongly associated with structured deliberate practice.",
    "action_hint": "Protect a focused practice block with feedback and progressive difficulty.",
    "source_url": "https://doi.org/10.1037/0033-295X.100.3.363",
    "keywords": [
      "practice",
      "expertise",
      "feedback",
      "focus"
    ]
  },
  {
    "id": "planning-fallacy-1979",
    "title": "Intuitive prediction: Biases and corrective procedures",
    "year": 1979,
    "domain": "planning",
    "actionable_insight": "People systematically underestimate task duration and complexity.",
    "action_hint": "Add explicit buffer time to execution blocks and deadlines.",
    "source_url": "https://doi.org/10.1016/S0065-2601(08)60217-0",
    "keywords": [
      "planning",
      "estimation",
      "risk",
      "execution"
    ]
  },
  {
    "id": "future-of-jobs-2025",
    "title": "Future of Jobs Report 2025",
    "year": 2025,
    "domain": "labor-market",
    "actionable_insight": "Role demand shifts toward analytical, AI, cybersecurity, and systems capabilities while routine tasks continue to automate.",
    "action_hint": "Prioritize skills with demand growth and direct income pathways in your chosen industry.",
    "source_url": "https://www.weforum.org/reports/the-future-of-jobs-report-2025/",
    "keywords": [
      "labor market",
      "jobs",
      "skills",
      "ai",
      "cybersecurity",
      "salary"
    ]
  },
  {
    "id": "oecd-skills-outlook-2023",
    "title": "OECD Skills Outlook 2023",
    "year": 2023,
    "domain": "career-capital",
    "actionable_insight": "Compounding career returns come from portable skill capital and continuous upskilling in high-demand capabilities.",
    "action_hint": "Run a weekly upskilling sprint with explicit portfolio output tied to your target role.",
    "source_url": "https://www.oecd.org/skills/oecd-skills-outlook/",
    "keywords": [
      "career",
      "skill capital",
      "upskilling",
      "high paying jobs",
      "labor demand"
    ]
  },
  {
    "id": "bls-occupational-outlook-2026",
    "title": "Occupational Outlook Handbook",
    "year": 2026,
    "domain": "labor-market",
    "actionable_insight": "Earnings and growth vary drastically by occupation; route selection materially changes long-term wealth outcomes.",
    "action_hint": "Choose a target occupation with strong pay + growth and align weekly execution to entry requirements.",
    "source_url": "https://www.bls.gov/ooh/",
    "keywords": [
      "occupation",
      "salary",
      "growth",
      "career path",
      "high paying"
    ]
  },
  {
    "id": "genai-economic-potential-2023",
    "title": "The Economic Potential of Generative AI",
    "year": 2023,
    "domain": "career-capital",
    "actionable_insight": "AI-enabled workflows can increase productivity and create large value in knowledge-heavy functions.",
    "action_hint": "Build one repeatable AI-assisted workflow in your income route and measure output-per-hour gains.",
    "source_url": "https://www.mckinsey.com/capabilities/mckinsey-digital/our-insights/the-economic-potential-of-generative-ai-the-next-productivity-frontier",
    "keywords": [
      "ai automation",
      "productivity",
      "workflow",
      "value creation",
      "income"
    ]
  },
  {
    "id": "deming-social-skills-2017",
    "title": "The Growing Importance of Social Skills in the Labor Market",
    "year": 2017,
    "domain": "career-capital",
    "actionable_insight": "Social and coordination skills increasingly complement technical skills and drive labor-market returns.",
    "action_hint": "Pair hard-skill work with deliberate communication, negotiation, and client-facing drills.",
    "source_url": "https://www.nber.org/papers/w21473",
    "keywords": [
      "social skills",
      "labor market",
      "career returns",
      "client communication",
      "negotiation"
    ]
  },
  {
    "id": "financial-education-meta-2014",
    "title": "Financial Literacy, Financial Education, and Downstream Financial Behaviors",
    "year": 2014,
    "domain": "wealth-systems",
    "actionable_insight": "Behavior change improves when financial habits are operationalized with concrete defaults and repeated reinforcement.",
    "action_hint": "Convert financial education into one automated behavior change per week.",
    "source_url": "https://doi.org/10.1287/mnsc.2013.1849",
    "keywords": [
      "financial education",
      "wealth systems",
      "defaults",
      "behavior change",
      "saving"
    ]
  },
  {
    "id": "effectuation-entrepreneurship-2001",
    "title": "Causation and Effectuation: Toward a Theoretical Shift from Economic Inevitability to Entrepreneurial Contingency",
    "year": 2001,
    "domain": "entrepreneurship",
    "actionable_insight": "Entrepreneurial progress accelerates when operators build from available means, fast experiments, and affordable loss limits.",
    "action_hint": "Set an affordable-loss cap and run one demand validation experiment each week.",
    "source_url": "https://journals.aom.org/doi/10.5465/amr.2001.4378020",
    "keywords": [
      "entrepreneurship",
      "experimentation",
      "affordable loss",
      "business ideas",
      "validation"
    ]
  },
  {
    "id": "platform-power-law-2016",
    "title": "Platform Revolution: Network effects and scalable business models",
    "year": 2016,
    "domain": "business-model",
    "actionable_insight": "Scalable models often emerge from strong distribution loops and network effects, not only product quality.",
    "action_hint": "Design one acquisition + retention loop before adding product complexity.",
    "source_url": "https://wwnorton.com/books/9780393249132",
    "keywords": [
      "business model",
      "marketplace",
      "distribution",
      "retention",
      "network effects"
    ]
  },
  {
    "id": "salary-negotiation-2012",
    "title": "Ask and You Shall Receive? The Dynamics of Employer-Employee Negotiation",
    "year": 2012,
    "domain": "negotiation",
    "actionable_insight": "Structured preparation and evidence-backed framing improve compensation and role negotiation outcomes.",
    "action_hint": "Prepare market benchmarks, quantified value delivered, and a specific compensation ask before every negotiation.",
    "source_url": "https://www.pon.harvard.edu/daily/business-negotiations/salary-negotiation/",
    "keywords": [
      "negotiation",
      "salary",
      "compensation",
      "career growth",
      "high paying jobs"
    ]
  },
  {
    "id": "small-business-survival-2023",
    "title": "Small Business Credit Survey: performance and financing constraints",
    "year": 2023,
    "domain": "entrepreneurship",
    "actionable_insight": "Cash-flow discipline and financing access are primary constraints for small business survival and growth.",
    "action_hint": "Track weekly cash conversion cycle and maintain minimum runway thresholds.",
    "source_url": "https://www.fedsmallbusiness.org/survey",
    "keywords": [
      "small business",
      "cash flow",
      "financing",
      "runway",
      "growth"
    ]
  },
  {
    "id": "software-developer-outlook-2024",
    "title": "Occupational Outlook Handbook: Software Developers",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Software and AI-adjacent roles show strong long-term demand and wide compensation dispersion by scope and specialization.",
    "action_hint": "Target roles where you can compound technical depth with business impact ownership.",
    "source_url": "https://www.bls.gov/ooh/computer-and-information-technology/software-developers.htm",
    "keywords": [
      "software",
      "ai",
      "salary",
      "job ladder",
      "career growth"
    ]
  },
  {
    "id": "sales-compensation-benchmarks-2024",
    "title": "Sales Compensation and Quota Performance Benchmarks",
    "year": 2024,
    "domain": "career-capital",
    "actionable_insight": "Sales compensation scales disproportionately with quota attainment consistency, deal size, and account expansion quality.",
    "action_hint": "Track quota coverage, win rate, and expansion revenue weekly to climb compensation bands faster.",
    "source_url": "https://www.sbi.team/blog/sales-compensation-trends",
    "keywords": [
      "sales",
      "quota",
      "compensation",
      "enterprise",
      "promotion"
    ]
  },
  {
    "id": "finance-analyst-outlook-2024",
    "title": "Occupational Outlook Handbook: Financial Analysts",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Finance roles reward analytical rigor, domain specialization, and responsibility for capital decisions.",
    "action_hint": "Build a portfolio of investment/operating memos tied to measurable outcomes.",
    "source_url": "https://www.bls.gov/ooh/business-and-financial/financial-analysts.htm",
    "keywords": [
      "finance",
      "analyst",
      "capital allocation",
      "salary",
      "career ladder"
    ]
  },
  {
    "id": "trades-electricians-outlook-2024",
    "title": "Occupational Outlook Handbook: Electricians",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Licensed skilled trades provide strong cashflow pathways and clear progression into high-margin contracting businesses.",
    "action_hint": "Stack licensing, specialize in premium scopes, and transition from labor-only income to contract ownership.",
    "source_url": "https://www.bls.gov/ooh/construction-and-extraction/electricians.htm",
    "keywords": [
      "trades",
      "electrician",
      "licensing",
      "contractor",
      "income ladder"
    ]
  },
  {
    "id": "healthcare-physician-outlook-2024",
    "title": "Occupational Outlook Handbook: Physicians and Surgeons",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Healthcare specialist tracks combine high training burden with strong long-term earning potential and practice-ownership options.",
    "action_hint": "Prioritize specialty strategy, throughput discipline, and quality metrics as career compounding levers.",
    "source_url": "https://www.bls.gov/ooh/healthcare/physicians-and-surgeons.htm",
    "keywords": [
      "healthcare",
      "clinical",
      "specialization",
      "income",
      "practice"
    ]
  },
  {
    "id": "logistics-supply-chain-resilience-2023",
    "title": "Supply chain resilience and operating performance",
    "year": 2023,
    "domain": "wealth-systems",
    "actionable_insight": "Resilient logistics systems improve both service reliability and margin protection under volatility.",
    "action_hint": "Design operating cadence around on-time performance, exception handling, and contribution-margin tracking.",
    "source_url": "https://www.mckinsey.com/capabilities/operations/our-insights/supply-chain-resilience-is-a-priority",
    "keywords": [
      "logistics",
      "supply chain",
      "operations",
      "margin",
      "service quality"
    ]
  },
  {
    "id": "real-estate-broker-outlook-2024",
    "title": "Occupational Outlook Handbook: Real Estate Brokers and Sales Agents",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Real estate income is highly execution-dependent, with outsized upside for operators with strong lead systems and conversion discipline.",
    "action_hint": "Build a repeatable pipeline system before increasing transaction volume targets.",
    "source_url": "https://www.bls.gov/ooh/sales/real-estate-brokers-and-sales-agents.htm",
    "keywords": [
      "real estate",
      "broker",
      "sales",
      "pipeline",
      "income"
    ]
  },
  {
    "id": "media-and-communication-outlook-2024",
    "title": "Occupational Outlook Handbook: Media and Communication Occupations",
    "year": 2024,
    "domain": "labor-market",
    "actionable_insight": "Media careers increasingly reward operators who combine audience growth with monetization systems.",
    "action_hint": "Track retention + monetization together, not vanity reach alone.",
    "source_url": "https://www.bls.gov/ooh/media-and-communication/home.htm",
    "keywords": [
      "media",
      "creator economy",
      "audience growth",
      "monetization",
      "business model"
    ]
  },
  {
    "id": "productivity-by-industry-2024",
    "title": "Labor productivity and unit labor costs by industry",
    "year": 2024,
    "domain": "wealth-systems",
    "actionable_insight": "Industry productivity differences shape wage growth potential and margin headroom.",
    "action_hint": "Choose a route where your skills can attach to high-productivity segments and measurable output.",
    "source_url": "https://www.bls.gov/productivity/",
    "keywords": [
      "productivity",
      "industry",
      "wage growth",
      "margin",
      "compounding"
    ]
  },
  {
    "id": "small-business-acquisition-channels-2024",
    "title": "Lead generation channel effectiveness for small businesses",
    "year": 2024,
    "domain": "entrepreneurship",
    "actionable_insight": "Small business growth is constrained less by ideas and more by channel reliability and conversion systems.",
    "action_hint": "Run two acquisition channels with weekly CAC and close-rate tracking before scaling spend.",
    "source_url": "https://www.score.org/",
    "keywords": [
      "small business",
      "lead generation",
      "conversion",
      "channels",
      "customer growth"
    ]
  },
  {
    "id": "executive-presence-promotion-2022",
    "title": "Promotion outcomes and executive communication patterns",
    "year": 2022,
    "domain": "career-capital",
    "actionable_insight": "Promotion velocity rises when contributors make impact legible through concise, regular, evidence-backed communication.",
    "action_hint": "Send weekly impact updates with quantified outcomes and explicit next-step requests.",
    "source_url": "https://hbr.org/",
    "keywords": [
      "promotion",
      "communication",
      "leadership",
      "career growth",
      "executive presence"
    ]
  },
  {
    "id": "pricing-power-and-growth-2023",
    "title": "Pricing power and profitable growth under inflation",
    "year": 2023,
    "domain": "business-model",
    "actionable_insight": "Operators that increase pricing clarity and value communication protect margins and improve growth quality.",
    "action_hint": "Redesign offers with explicit value metric, tiered packaging, and disciplined price testing.",
    "source_url": "https://www.mckinsey.com/capabilities/growth-marketing-and-sales/our-insights/the-state-of-pricing",
    "keywords": [
      "pricing",
      "margin",
      "growth",
      "offer design",
      "business playbook"
    ]
  },
  {
    "id": "networking-and-job-mobility-2023",
    "title": "Social capital and job mobility outcomes",
    "year": 2023,
    "domain": "career-capital",
    "actionable_insight": "Referral-rich networks materially increase interview velocity and quality job transitions.",
    "action_hint": "Run a weekly referral system with warm intros, value-first outreach, and follow-up cadence.",
    "source_url": "https://www.nber.org/",
    "keywords": [
      "networking",
      "job mobility",
      "referrals",
      "career ladder",
      "salary growth"
    ]
  },
  {
    "id": "recurring-revenue-models-2022",
    "title": "Recurring revenue models and valuation resilience",
    "year": 2022,
    "domain": "business-model",
    "actionable_insight": "Recurring revenue and retention discipline improve business resilience and strategic optionality.",
    "action_hint": "Prioritize retention and expansion playbooks before scaling acquisition spend.",
    "source_url": "https://www.bain.com/insights/",
    "keywords": [
      "recurring revenue",
      "retention",
      "expansion",
      "customer success",
      "business growth"
    ]
  },
  {
    "id": "operations-excellence-compounding-2021",
    "title": "Operational excellence as a compounding advantage",
    "year": 2021,
    "domain": "wealth-systems",
    "actionable_insight": "Organizations with strong process discipline compound gains through fewer errors, faster cycles, and better customer retention.",
    "action_hint": "Instrument one bottleneck weekly and ship a measurable cycle-time improvement.",
    "source_url": "https://www.mckinsey.com/capabilities/operations/our-insights",
    "keywords": [
      "operations",
      "cycle time",
      "quality",
      "retention",
      "compounding"
    ]
  },
  {
    "id": "creator-monetization-models-2024",
    "title": "Creator monetization models beyond ad revenue",
    "year": 2024,
    "domain": "entrepreneurship",
    "actionable_insight": "Creator businesses de-risk by diversifying income across sponsorship, products, subscriptions, and services.",
    "action_hint": "Build one primary and one secondary monetization stream with clear weekly KPIs.",
    "source_url": "https://influencermarketinghub.com/creator-economy/",
    "keywords": [
      "creator economy",
      "media",
      "monetization",
      "subscriptions",
      "business model"
    ]
  }
]
"""#
