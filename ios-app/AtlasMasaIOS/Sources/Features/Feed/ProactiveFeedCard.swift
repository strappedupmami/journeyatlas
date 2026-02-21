import SwiftUI

struct ProactiveFeedCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        AtlasScreen(
            title: "Execution Loop",
            subtitle: "Daily, mid-term, and long-term orchestration with executive-grade clarity"
        ) {
            AtlasPanel(heading: "Plan source", caption: "Tier-aware pipeline: local reasoning first, cloud reasoning when upgraded") {
                Text("Active tier: \(session.selectedTier.title)")
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.selectedTier.subtitle)
                    .foregroundStyle(AtlasTheme.textSecondary)

                Button("Refresh execution feed") {
                    Task { await session.refreshFeed() }
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }

            AtlasPanel(heading: "Workspace lanes", caption: "Dedicated operational workspaces generated from research + your profile data") {
                if session.workspacePlans.isEmpty {
                    Text("No workspace lanes yet. Finish deep survey and check-in.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.workspacePlans.prefix(3)) { workspace in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.title)
                                    .font(.system(size: 15, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Text(workspace.nextActionNow)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            Spacer()
                            Text("\(Int(workspace.confidence * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(heading: "Proactive outputs", caption: "What to execute now and why") {
                if session.feedItems.isEmpty {
                    Text("No items yet. Complete survey and check-in, then refresh feed.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.feedItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(item.summary)
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Why now: \(item.whyNow)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)
                            Text("Priority: \(item.priority)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(heading: "Tailored products and services", caption: "Atlas-wide intelligence matched to your profile and current needs") {
                if session.tailoredOffers.isEmpty {
                    Text("Complete survey/check-in to unlock tailored offers.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.tailoredOffers) { offer in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(offer.title)
                                    .font(.system(size: 17, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text(offer.type.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }
                            Text(offer.summary)
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Why this is offered: \(offer.rationale)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                            Text("Next: \(offer.callToAction)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accent)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(heading: "Research-backed execution streams", caption: "Evidence-grounded recommendations from the Atlas scientific pack") {
                if session.researchStreams.isEmpty {
                    Text("No research streams yet. Add notes/check-ins to unlock evidence-matched recommendations.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(session.researchStreams) { stream in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(stream.title)
                                    .font(.system(size: 17, weight: .semibold, design: .serif))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Spacer()
                                Text("CONF \(Int(stream.confidence * 100))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }
                            Text("Action: \(stream.executionRecommendation)")
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text("Evidence: \(stream.whyItWorks)")
                                .foregroundStyle(AtlasTheme.textSecondary)
                            ForEach(stream.citations) { citation in
                                Text("• \(citation.title) (\(citation.year))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }

            AtlasPanel(
                heading: "Adaptive learning mode",
                caption: "Auto-generated quiz + podcast brief updates whenever new memory justifies a new version"
            ) {
                if let learning = session.learningPackage {
                    Text("Version \(learning.version) · \(learning.generatedAtUTC)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                    Text(learning.rationale)
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Text("Quiz")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    ForEach(learning.quiz) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.prompt)
                                .foregroundStyle(AtlasTheme.textPrimary)
                            ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                                Text("\(idx + 1). \(option)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(idx == question.preferredAnswerIndex ? AtlasTheme.accent : AtlasTheme.textSecondary)
                            }
                            Text("Why: \(question.explanation)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }

                    Text(learning.podcastTitle)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Text(learning.podcastSummary)
                        .foregroundStyle(AtlasTheme.textSecondary)
                    ForEach(learning.podcastSegments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.accentWarm)
                            ForEach(segment.talkingPoints, id: \.self) { point in
                                Text("• \(point)")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                    }
                } else {
                    Text("Complete deeper survey/check-ins/notes to unlock adaptive learning outputs.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            AtlasPanel(heading: "Product feedback path", caption: "If friction is detected, offer anonymized report routing") {
                Toggle("Enable feedback offer on negative signal", isOn: $session.feedbackOfferEnabled)
                    .tint(AtlasTheme.accent)
                    .foregroundStyle(AtlasTheme.textPrimary)

                TextField("Optional feedback draft", text: $session.pendingFeedback, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .atlasFieldStyle()

                Button("Send anonymized report") {
                    session.submitAnonymizedFeedback()
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }
        }
    }
}
