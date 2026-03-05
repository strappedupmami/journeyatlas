using AtlasMasaWindows.Models;

namespace AtlasMasaWindows.Services;

public sealed class QuantumLearningPlanner
{
    public QuantumLearningSnapshot BuildSnapshot(
        AtlasSessionState session,
        IReadOnlyDictionary<string, string> surveyAnswers,
        IReadOnlyList<NoteRecord> notes,
        IReadOnlyList<MemoryRecord> memory)
    {
        var amplitudes = new Dictionary<string, double>(StringComparer.Ordinal)
        {
            ["acquisition"] = 0.56,
            ["conversion"] = 0.50,
            ["retention"] = 0.46,
            ["productization"] = 0.42,
            ["focus_stability"] = 0.38
        };

        void Add(string track, double delta)
        {
            amplitudes[track] = amplitudes.TryGetValue(track, out var current)
                ? current + delta
                : 0.20 + delta;
        }

        var combinedSignal = string.Join(
            " ",
            new[]
            {
                session.DailyPriority,
                session.MidTermGoal,
                session.LongTermVision,
                session.Blockers,
                string.Join(" ", surveyAnswers.Select(entry => $"{entry.Key}={entry.Value}")),
                string.Join(" ", notes.Take(8).Select(note => $"{note.Title} {note.Content}")),
                string.Join(" ", memory.Take(16).Select(item => item.Value))
            })
            .ToLowerInvariant();

        if (session.Energy <= 2 || ContainsAny(session.Mood, ["stress", "burnout", "anxious", "exhaust"]))
        {
            Add("focus_stability", 0.24);
            Add("retention", 0.04);
        }
        if (ContainsAny(combinedSignal, ["lead", "traffic", "pipeline", "prospect", "audience", "distribution"]))
        {
            Add("acquisition", 0.28);
        }
        if (ContainsAny(combinedSignal, ["close", "conversion", "proposal", "pricing", "offer clarity"]))
        {
            Add("conversion", 0.24);
        }
        if (ContainsAny(combinedSignal, ["retention", "churn", "cancel", "renewal", "expansion", "nrr"]))
        {
            Add("retention", 0.24);
        }
        if (ContainsAny(combinedSignal, ["automation", "system", "sop", "playbook", "productize", "agent"]))
        {
            Add("productization", 0.24);
        }
        if (ContainsAny(combinedSignal, ["sleep", "fatigue", "focus", "cognitive", "recovery"]))
        {
            Add("focus_stability", 0.18);
        }

        if (surveyAnswers.TryGetValue("growth_priority", out var growthPriority))
        {
            if (string.Equals(growthPriority, "grow_business_customer_base", StringComparison.OrdinalIgnoreCase))
            {
                Add("acquisition", 0.10);
                Add("conversion", 0.08);
            }
            else if (string.Equals(growthPriority, "hybrid_growth", StringComparison.OrdinalIgnoreCase))
            {
                Add("productization", 0.10);
            }
        }
        if (surveyAnswers.TryGetValue("customer_growth_focus", out var growthFocus) &&
            string.Equals(growthFocus, "retention_expansion", StringComparison.OrdinalIgnoreCase))
        {
            Add("retention", 0.12);
        }

        foreach (var key in amplitudes.Keys.ToList())
        {
            amplitudes[key] = Math.Max(0.12, amplitudes[key]);
        }

        var probabilities = amplitudes
            .Select(entry => new
            {
                Track = entry.Key,
                Probability = Math.Pow(Math.Max(0.12, entry.Value), 2)
            })
            .ToList();
        var probabilityMass = Math.Max(0.0001, probabilities.Sum(entry => entry.Probability));
        var normalized = probabilities
            .Select(entry => new QuantumTrackScore
            {
                Track = entry.Track,
                Probability = entry.Probability / probabilityMass
            })
            .OrderByDescending(entry => entry.Probability)
            .ThenBy(entry => entry.Track, StringComparer.Ordinal)
            .ToList();

        var dominant = normalized.FirstOrDefault() ?? new QuantumTrackScore
        {
            Track = "acquisition",
            Probability = 1.0
        };
        var template = BuildQuestionTemplate(dominant.Track);

        return new QuantumLearningSnapshot
        {
            GeneratedAt = DateTimeOffset.UtcNow,
            DominantTrack = dominant.Track,
            DominantProbability = dominant.Probability,
            TrackProbabilities = normalized,
            RecommendedQuestion = template.Prompt,
            RecommendedOptions = template.Options,
            Rationale = template.Rationale,
            Source = "quantum_simulator_v1"
        };
    }

    public static string TrackLabel(string track)
    {
        return track switch
        {
            "acquisition" => "Demand acquisition",
            "conversion" => "Conversion velocity",
            "retention" => "Retention and expansion",
            "productization" => "Productization and systems",
            "focus_stability" => "Cognitive focus stability",
            _ => track.Replace("_", " ", StringComparison.Ordinal).Trim()
        };
    }

    private static (string Prompt, List<string> Options, string Rationale) BuildQuestionTemplate(string track)
    {
        return track switch
        {
            "acquisition" => (
                "Where should we focus the next 7-day demand-generation sprint?",
                new List<string>
                {
                    "Founder-led outbound to top 20 ideal buyers",
                    "Short educational content mapped to top pain point",
                    "Partnership/referral outreach to channel allies",
                    "Offer-led landing page with one clear CTA"
                },
                "Acquisition signals currently dominate survey and memory context."
            ),
            "conversion" => (
                "Which conversion bottleneck should be fixed first this week?",
                new List<string>
                {
                    "Tighten discovery script and qualification criteria",
                    "Rewrite offer/pricing for stronger perceived ROI",
                    "Reduce proposal-to-close friction with clear next steps",
                    "Create objection-handling snippets for common blockers"
                },
                "Conversion friction signals are elevated in the current operating profile."
            ),
            "retention" => (
                "What retention move has the highest leverage over the next 14 days?",
                new List<string>
                {
                    "Repair onboarding and first-week activation sequence",
                    "Launch proactive check-ins for at-risk users",
                    "Build expansion path from core to premium value",
                    "Instrument churn reasons and close top two causes"
                },
                "Retention and expansion probabilities are highest in the latest snapshot."
            ),
            "productization" => (
                "Which system or automation should be productized first?",
                new List<string>
                {
                    "Template the highest-frequency service workflow",
                    "Automate repetitive follow-up and status updates",
                    "Create a reusable SOP with measurable checkpoints",
                    "Package a repeatable offer around one pain category"
                },
                "Systemization and leverage signals are strongest right now."
            ),
            _ => (
                "Which action best protects cognitive execution quality this week?",
                new List<string>
                {
                    "Reduce task switching to one primary objective/day",
                    "Schedule deep-work blocks before reactive work",
                    "Improve sleep/recovery protocol for 7 days",
                    "Use a strict reflection loop after major decisions"
                },
                "Focus-stability signals are elevated and should be de-risked first."
            )
        };
    }

    private static bool ContainsAny(string value, IReadOnlyList<string> needles)
    {
        var lower = value.ToLowerInvariant();
        return needles.Any(lower.Contains);
    }
}
