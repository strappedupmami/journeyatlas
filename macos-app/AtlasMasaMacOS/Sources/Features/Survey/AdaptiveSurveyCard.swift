import SwiftUI

struct AdaptiveSurveyCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List {
            if let survey = session.survey {
                Section("Progress") {
                    ProgressView(value: Double(survey.progress.percent), total: 100)
                    Text("\(survey.progress.answered)/\(survey.progress.total) • \(survey.progress.percent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Current Question") {
                    if let question = survey.question {
                        Text(question.title).font(.headline)
                        if let description = question.description, !description.isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(question.choices) { choice in
                            Button(choice.label) {
                                Task { await session.answerSurvey(choice) }
                            }
                        }
                    } else {
                        Label("Survey complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !survey.profileHints.isEmpty {
                    Section("Profile hints") {
                        ForEach(survey.profileHints, id: \.self) { hint in
                            Text(hint)
                        }
                    }
                }
            } else {
                Section {
                    ProgressView("Loading survey...")
                }
            }
        }
        .navigationTitle("Adaptive Survey")
        .toolbar {
            ToolbarItem {
                Button("Reload") { Task { await session.loadSurvey() } }
            }
        }
    }
}
