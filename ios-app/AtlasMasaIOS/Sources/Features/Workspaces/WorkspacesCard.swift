import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WorkspacesCard: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var composerFocused: Bool
    @State private var notebookControlsPresented = false
    @State private var workspaceLanesPresented = false
    @State private var processingChoicePresented = false

    private let threadBottomID = "atlas-workspaces-thread-bottom"
    private let maxRuntimeRetries = 3

    var body: some View {
        ZStack {
            AtlasTheme.backgroundGradient
                .ignoresSafeArea()
            AtlasTheme.glowGradient
                .ignoresSafeArea()
            AtlasTheme.ambientGradient
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if workspaceThreadItems.isEmpty {
                            workspaceEmptyState
                        } else {
                            ForEach(workspaceThreadItems) { item in
                                workspaceThreadMessage(item)
                            }
                        }

                        Color.clear
                            .frame(height: 4)
                            .id(threadBottomID)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                }
                .onAppear {
                    scrollThreadToBottom(proxy, animated: false)
                }
                .onChange(of: chatTimelineSignature) { _, _ in
                    scrollThreadToBottom(proxy, animated: true)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            workspaceHeader
        }
        .safeAreaInset(edge: .bottom) {
            workspaceComposer
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissWorkspaceKeyboard()
            }
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    composerFocused = false
                }
            }
        }
        .sheet(isPresented: $notebookControlsPresented) {
            notebookControlsSheet
        }
        .sheet(isPresented: $workspaceLanesPresented) {
            workspaceLanesSheet
        }
        .confirmationDialog(
            "AI is still processing. Choose how Atlas should handle this next message.",
            isPresented: $processingChoicePresented,
            titleVisibility: .visible
        ) {
            Button("Steer") {
                session.steerWorkspacePrompt()
            }
            Button("Queue") {
                session.enqueueWorkspacePrompt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Steer prioritizes this message after the current run. Queue keeps normal order.")
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Workspaces")
                    .font(AtlasTheme.brandDisplayFont(size: 27))
                    .tracking(0.4)
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(compactLaneTitle(session.activeWorkspaceLane))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            Spacer()

            AtlasPill(title: activeRunPillTitle)

            Menu {
                Button("Projects & chats") {
                    notebookControlsPresented = true
                }
                Button("Workspace lanes") {
                    workspaceLanesPresented = true
                }
                Button("New chat") {
                    session.createWorkspaceSession(for: session.activeWorkspaceLane)
                }

                Divider()

                ForEach(WorkspaceLane.allCases) { lane in
                    Button {
                        session.setActiveWorkspaceLane(lane)
                    } label: {
                        if lane == session.activeWorkspaceLane {
                            Label(lane.title, systemImage: "checkmark")
                        } else {
                            Text(lane.title)
                        }
                    }
                }

                Divider()

                Button("Clear active chat", role: .destructive) {
                    session.clearWorkspacePromptQueue()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AtlasTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(AtlasTheme.cardStrong)
                    )
                    .overlay(
                        Circle()
                            .stroke(AtlasTheme.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background(
            ZStack {
                AtlasTheme.chromeSurface
                AtlasTheme.chromeGradient
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AtlasTheme.chromeEdge)
                    .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
    }

    private var composerContainerBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AtlasTheme.chromeSurface, Color.black.opacity(0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AtlasTheme.chromeEdge, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.26), radius: 14, x: 0, y: 8)
    }

    private var sendButtonLabel: some View {
        let enabled = !trimmedPendingPrompt.isEmpty
        return Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(
                        enabled
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AtlasTheme.accent, AtlasTheme.accentWarm],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.white.opacity(0.18))
                    )
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(enabled ? 0.18 : 0.1), lineWidth: 1)
            )
    }

    private var workspaceComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AtlasPill(title: activeRunPillTitle)
                AtlasPill(title: compactLaneTitle(session.activeWorkspaceLane).uppercased())
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Menu {
                    ForEach(WorkspaceLane.allCases) { lane in
                        Button {
                            session.setActiveWorkspaceLane(lane)
                        } label: {
                            if lane == session.activeWorkspaceLane {
                                Label(lane.title, systemImage: "checkmark")
                            } else {
                                Text(lane.title)
                            }
                        }
                    }
                } label: {
                    AtlasPill(title: "LANE · \(compactLaneTitle(session.activeWorkspaceLane).uppercased())")
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(PromptOutputType.allCases) { outputType in
                        Button {
                            session.pendingPromptOutputType = outputType
                        } label: {
                            Label(outputType.title, systemImage: outputTypeSymbol(outputType))
                        }
                    }
                } label: {
                    AtlasPill(title: selectedOutputPillTitle)
                }
                .buttonStyle(.plain)

                if session.pendingPromptOutputType == .quiz {
                    Menu {
                        ForEach(QuizDifficulty.allCases) { difficulty in
                            Button {
                                session.pendingPromptQuizDifficulty = difficulty
                            } label: {
                                Text(difficulty.title)
                            }
                        }
                    } label: {
                        AtlasPill(title: session.pendingPromptQuizDifficulty.title.uppercased())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message workspace...", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(1 ... 8)
                    .atlasFieldStyle()
                    .focused($composerFocused)

                Button {
                    composerFocused = false
                    if session.workspaceHasActiveProcessing() {
                        processingChoicePresented = true
                    } else {
                        session.enqueueWorkspacePrompt()
                    }
                } label: {
                    sendButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(trimmedPendingPrompt.isEmpty)
            }
        }
        .padding(12)
        .background(composerContainerBackground)
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AtlasTheme.chromeEdge.opacity(0.9))
                        .frame(height: 1)
                }
        )
    }

    private var workspaceEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let starter = session.starterMessageForWorkspaceSession(
                lane: session.activeWorkspaceLane,
                sessionID: activeNotebookID
            ) {
                AtlasChatBubble(text: starter, isUser: false)
            }
            Text("Chat in this project to generate tactical outputs grounded in workspace memory and prior chats.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)

            HStack(spacing: 8) {
                AtlasPill(title: compactLaneTitle(session.activeWorkspaceLane).uppercased())
                AtlasPill(title: runtimeModelPillTitle)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AtlasTheme.assistantBubble, Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AtlasTheme.border.opacity(0.9), lineWidth: 1)
        )
    }

    private var workspaceLanesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Workspace lanes")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Spacer()
                        Button("Done") {
                            workspaceLanesPresented = false
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }

                    Text("Dedicated operational workspaces generated from memory + research.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    ForEach(session.workspacePlans) { plan in
                        Button {
                            session.setActiveWorkspaceLane(plan.lane)
                            workspaceLanesPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(plan.title)
                                        .font(.system(size: 16, weight: .semibold, design: .default))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Spacer()
                                    Text("\(Int(plan.confidence * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.accentWarm)
                                }
                                Text(plan.nextActionNow)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.2))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(AtlasTheme.backgroundGradient.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func workspaceThreadMessage(_ item: PromptQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtlasChatBubble(text: item.prompt, isUser: true)

            if let output = item.output {
                let responseText = assistantMessageText(for: output)
                AtlasChatBubble(text: responseText, isUser: false)
                HStack(spacing: 8) {
                    let outputType = output.outputType ?? item.outputType ?? .standard
                    AtlasPill(title: outputType.title.uppercased())
                    if outputType == .quiz,
                       let difficulty = output.quizDifficulty ?? item.quizDifficulty
                    {
                        AtlasPill(title: difficulty.title.uppercased())
                    }
                }
                ResponseFeedbackCard(
                    source: "ios_workspace_chat",
                    prompt: item.prompt,
                    response: responseText
                )
            } else if let error = item.errorMessage, !error.isEmpty {
                AtlasChatBubble(text: "Runtime notice: \(error)", isUser: false)
            } else {
                AtlasChatBubble(text: pendingAssistantStatusText(for: item), isUser: false)
            }
        }
    }

    private var workspaceThreadItems: [PromptQueueItem] {
        let lane = session.activeWorkspaceLane
        let activeSession = session.activeSessionID(for: lane)
        return session.promptQueue
            .filter { item in
                guard item.workspaceLane == lane else { return false }
                guard let activeSession else { return true }
                return item.workspaceSessionID == nil || item.workspaceSessionID == activeSession
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var activeRunPillTitle: String {
        let active = workspaceThreadItems.filter { $0.status == .running || $0.status == .queued }.count
        return active == 0 ? "READY" : "\(active) ACTIVE"
    }

    private var runtimeModelPillTitle: String {
        session.inferenceSettingsSnapshot().model.uppercased()
    }

    private var selectedOutputPillTitle: String {
        let type = session.pendingPromptOutputType
        if type == .quiz {
            return "\(type.title.uppercased()) · \(session.pendingPromptQuizDifficulty.title.uppercased())"
        }
        return type.title.uppercased()
    }

    private var trimmedPendingPrompt: String {
        session.pendingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chatTimelineSignature: String {
        workspaceThreadItems.map { item in
            let outputStamp = item.output?.generatedAt.timeIntervalSince1970 ?? 0
            return "\(item.id)|\(item.status.rawValue)|\(item.retryCount ?? 0)|\(item.errorMessage ?? "")|\(outputStamp)"
        }.joined(separator: ";")
    }

    private func assistantMessageText(for output: LocalReasoningOutput) -> String {
        let body = (output.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return body
        }
        return """
        \(output.summary)

        Next action: \(output.nextAction)
        """
    }

    private func pendingAssistantStatusText(for item: PromptQueueItem) -> String {
        let outputType = (item.outputType ?? .standard).title.lowercased()
        switch item.status {
        case .running:
            return "Analyzing context and drafting your \(outputType) response..."
        case .queued:
            if let checkpoint = item.checkpointNote?.lowercased(),
               checkpoint.contains("waiting to reconnect") || checkpoint.contains("no internet")
            {
                return "Waiting to reconnect to the internet. Your \(outputType) response will resume automatically."
            }
            if let retry = item.retryCount, retry > 0 {
                return "Runtime reconnect in progress (\(retry)/\(maxRuntimeRetries)). Continuing your \(outputType) response..."
            }
            return "Preparing your \(outputType) response..."
        case .failed:
            return "AI runtime unavailable. No response was generated. Tap retry."
        case .done:
            return "Response ready."
        }
    }

    private func outputTypeSymbol(_ outputType: PromptOutputType) -> String {
        switch outputType {
        case .standard:
            return "text.bubble"
        case .podcast:
            return "waveform"
        case .quiz:
            return "checklist"
        }
    }

    private func compactLaneTitle(_ lane: WorkspaceLane) -> String {
        switch lane {
        case .emergencyCommand:
            return "Emergency"
        case .wealthOperations:
            return "Wealth"
        case .mobilityOps:
            return "Mobility"
        case .deepWork:
            return "Deep Work"
        case .innovation:
            return "Innovation"
        }
    }

    private func scrollThreadToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(threadBottomID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.22), action)
        } else {
            action()
        }
    }

    private var notebookControlsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Projects & chats")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Spacer()
                    Button("Done") {
                        notebookControlsPresented = false
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                Picker("Workspace project", selection: Binding(
                    get: { session.activeWorkspaceLane },
                    set: { session.setActiveWorkspaceLane($0) }
                )) {
                    ForEach(WorkspaceLane.allCases) { lane in
                        Text(compactLaneTitle(lane)).tag(lane)
                    }
                }
                .pickerStyle(.menu)
                .atlasFieldStyle()

                HStack(spacing: 10) {
                    Button("New chat") {
                        session.createWorkspaceSession(for: session.activeWorkspaceLane)
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Text("\(laneSessions.count) chats")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.accentWarm)
                }

                if !laneNameSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(laneNameSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    session.createWorkspaceSession(
                                        for: session.activeWorkspaceLane,
                                        title: suggestion
                                    )
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.22))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(AtlasTheme.border, lineWidth: 1)
                                )
                                .foregroundStyle(AtlasTheme.textPrimary)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if laneSessions.isEmpty {
                            Text("Awaiting first AI response.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        } else {
                            ForEach(laneSessions) { notebook in
                                Button {
                                    session.activateWorkspaceSession(notebook.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(notebook.title)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(AtlasTheme.textPrimary)
                                            Spacer()
                                            if notebook.id == activeNotebookID {
                                                AtlasPill(title: "ACTIVE")
                                            }
                                        }
                                        Text(sessionGuidePreview(for: notebook))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.black.opacity(0.2))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(AtlasTheme.backgroundGradient.ignoresSafeArea())
        }
    }

    private var laneSessions: [WorkspaceNotebookSession] {
        session.sessions(for: session.activeWorkspaceLane)
    }

    private var activeNotebookID: String? {
        session.activeSessionID(for: session.activeWorkspaceLane)
    }

    private var laneNameSuggestions: [String] {
        session.workspaceNameSuggestions(for: session.activeWorkspaceLane, limit: 3)
    }

    private func sessionGuidePreview(for notebook: WorkspaceNotebookSession) -> String {
        let trimmed = notebook.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if trimmed.isEmpty
            || lowered == "fresh session notebook."
            || lowered.hasPrefix("primary notebook for ")
        {
            return "Awaiting first AI response."
        }
        let compact = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(compact.prefix(130))
    }
}

#if canImport(UIKit)
private func dismissWorkspaceKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
#else
private func dismissWorkspaceKeyboard() {}
#endif
