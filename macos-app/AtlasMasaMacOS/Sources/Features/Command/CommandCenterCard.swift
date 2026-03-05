import SwiftUI

struct CommandCenterCard: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        // Using the updated AtlasScreen from our new Theme
        AtlasScreen(
            title: "Atlas Life OS",
            subtitle: "Swift-native command center for daily, mid-term, and long-horizon execution"
        ) {
            // High-end macOS apps utilize columns for dense information
            HStack(alignment: .top, spacing: 24) {
                
                // MARK: - LEFT COLUMN: Intelligence & Inputs
                VStack(spacing: 24) {
                    accountAndSafetyPanel
                    checkInPanel
                }
                .frame(maxWidth: .infinity, alignment: .top)
                
                // MARK: - RIGHT COLUMN: Output & Briefings
                VStack(spacing: 24) {
                    executionPlanPanel
                    inferenceBriefPanel
                    transparencyPanel
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var accountAndSafetyPanel: some View {
        AtlasPanel(heading: "System Status", caption: "Authentication and active guardrails") {
            VStack(alignment: .leading, spacing: 16) {
                // Account Info
                HStack {
                    AtlasPill(title: session.isSignedIn ? "Signed In" : "Guest")
                    AtlasPill(title: session.selectedTier.title)
                    Spacer()
                    Text(session.accountLabel)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if session.selectedTier == .localTrial {
                    Text("Local-first mode active. Execution runs on-device.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.accentWarm)
                }
                
                Divider()
                
                // Safety Guardrails
                HStack {
                    Label("Guardrails", systemImage: session.safetyModeActive ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                        .foregroundStyle(session.safetyModeActive ? AtlasTheme.accent : .green)
                    Spacer()
                    Text("Risk Score: \(session.safetyRiskScore)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if !session.safetyInterventionSummary.isEmpty {
                    Text(session.safetyInterventionSummary)
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                
                if session.safetyModeActive {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("High-risk content is blocked from operational queueing. Proceed with constructive planning.")
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.accentWarm)
                        
                        Button("Acknowledge Guidance") {
                            session.acknowledgeSafetyGuidance()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                    .padding(12)
                    .background(AtlasTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    private var checkInPanel: some View {
        AtlasPanel(heading: "Daily Execution Check-in", caption: "Set core signals for the orchestration loop") {
            // Native macOS Form automatically aligns labels and inputs beautifully
            Form {
                Section {
                    TextField("Daily Priority", text: $session.dailyPriority)
                    TextField("Mid-term Objective", text: $session.midTermGoal)
                    TextField("Long-term Mission", text: $session.longTermVision)
                    TextField("Current Blockers", text: $session.checkInBlockers)
                }
                
                Divider().padding(.vertical, 8)
                
                Section {
                    Stepper(value: $session.checkInEnergy, in: 1...5) {
                        Text("Energy Level: \(session.checkInEnergy)/5")
                    }
                    TextField("Mood", text: $session.checkInMood)
                    
                    Toggle("Completed Physical Training", isOn: $session.checkInWentToGymToday)
                    Toggle("Made Financial Progress", isOn: $session.checkInMadeMoneyToday)
                    
                    if session.checkInMadeMoneyToday {
                        TextField("Progress Notes", text: $session.checkInMoneySignalNote)
                    }
                }
            }
            // Forces standard control sizing rather than inheriting anything strange
            .controlSize(.regular)
            .textFieldStyle(.roundedBorder)
            .toggleStyle(.switch)
            
            HStack {
                Spacer()
                Button("Generate Execution Plan") {
                    session.applyDailyCheckIn()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .padding(.top, 8)
            }
        }
    }
    
    private var executionPlanPanel: some View {
        AtlasPanel(heading: "Execution Plan", caption: "Prioritized operational horizons") {
            if session.executionActions.isEmpty {
                // High-end native empty state
                ContentUnavailableView(
                    "No Plan Generated",
                    systemImage: "checklist",
                    description: Text("Run your daily check-in to generate prioritized action horizons.")
                )
                .frame(minHeight: 200)
            } else {
                VStack(spacing: 12) {
                    ForEach(session.executionActions) { action in
                        HStack(alignment: .top, spacing: 12) {
                            // A subtle indicator dot
                            Circle()
                                .fill(AtlasTheme.accentWarm)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(action.title)
                                        .font(.headline)
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    AtlasPill(title: action.horizon)
                                }
                                Text(action.details)
                                    .font(.subheadline)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AtlasTheme.border, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
    }
    
    private var inferenceBriefPanel: some View {
        AtlasPanel(heading: "Model Inference Brief", caption: "Always-on local synthesis") {
            Text(session.commandModelBrief)
                .font(.system(.subheadline, design: .monospaced)) // Monospaced gives it a "terminal/brief" feel
                .foregroundStyle(AtlasTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var transparencyPanel: some View {
        AtlasPanel(heading: "AI Transparency", caption: "Why Atlas exists") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Atlas is built for financial mobility, healthier cognitive execution, and resilient operations. This command plan is synthesized from your check-ins, surveys, notes, and workspace memory.")
                    .font(.subheadline)
                    .foregroundStyle(AtlasTheme.textSecondary)
                
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AtlasTheme.accentWarm)
                    Text("See the AI Guide tab for full training and privacy details.")
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.textPrimary)
                }
            }
        }
    }
}
