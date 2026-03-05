import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

struct PromptQueueCard: View {
    @EnvironmentObject private var session: SessionStore
    @FocusState private var composerFocused: Bool
    @State private var processingChoicePresented = false
    @State private var chatSessionsPresented = false
    private let threadBottomID = "atlas-concierge-thread-bottom"
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
                        if commandThreadItems.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                if let starter = session.starterMessageForConciergeSession(sessionID: currentConciergeSessionID) {
                                    AtlasChatBubble(text: starter, isUser: false)
                                } else {
                                    Text("Start with a mission request. Queueing is embedded in this chat flow, so each message runs directly from the thread.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                }

                                HStack(spacing: 8) {
                                    AtlasPill(title: "TACTICAL")
                                    AtlasPill(title: "MEMORY-AWARE")
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
                        } else {
                            ForEach(commandThreadItems) { item in
                                commandThreadMessage(item)
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
                    if session.allConciergeSessions().isEmpty {
                        session.createConciergeSession()
                    }
                    scrollThreadToBottom(proxy, animated: false)
                }
                .onChange(of: chatTimelineSignature) { _, _ in
                    scrollThreadToBottom(proxy, animated: true)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            commandHeader
        }
        .safeAreaInset(edge: .bottom) {
            commandComposer
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissChatKeyboard()
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
        .confirmationDialog(
            "AI is still processing. Choose how Atlas should handle this next message.",
            isPresented: $processingChoicePresented,
            titleVisibility: .visible
        ) {
            Button("Steer") {
                session.steerPrompt()
            }
            Button("Queue") {
                session.enqueuePrompt()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Steer prioritizes this message after the current run. Queue keeps normal order.")
        }
        .sheet(isPresented: $chatSessionsPresented) {
            conciergeSessionsSheet
        }
    }

    private var commandHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Atlas Concierge")
                    .font(AtlasTheme.brandDisplayFont(size: 27))
                    .tracking(0.4)
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(session.activeConciergeSessionTitle())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            Spacer()

            AtlasPill(title: activeRunPillTitle)

            Menu {
                Button("Chats") {
                    chatSessionsPresented = true
                }
                Button("New chat") {
                    session.createConciergeSession()
                }
                if let activeID = currentConciergeSessionID {
                    Button("Delete current chat", role: .destructive) {
                        session.deleteConciergeSession(activeID)
                    }
                }
                Divider()
                Button("Clear conversation", role: .destructive) {
                    session.clearConciergePromptQueue()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
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

    private var commandComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                AtlasPill(title: activeRunPillTitle)
                AtlasPill(title: runtimeModelPillTitle)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
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
                TextField("Message concierge...", text: $session.pendingPrompt, axis: .vertical)
                    .lineLimit(1 ... 8)
                    .atlasFieldStyle()
                    .focused($composerFocused)

                Button {
                    composerFocused = false
                    if session.pendingPromptOutputType == .podcast {
                        session.enqueuePrompt()
                    } else if session.conciergeHasActiveProcessing() {
                        processingChoicePresented = true
                    } else {
                        session.enqueuePrompt()
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

    @ViewBuilder
    private func commandThreadMessage(_ item: PromptQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AtlasChatBubble(text: item.prompt, isUser: true)

            if let output = item.output {
                let outputType = output.outputType ?? item.outputType ?? .standard
                if outputType == .podcast, let artifact = output.podcastAudio {
                    PodcastAudioBubble(
                        artifact: artifact,
                        summary: output.summary
                    )
                } else {
                    AtlasChatBubble(text: assistantMessageText(for: output), isUser: false)
                }
                HStack(spacing: 8) {
                    AtlasPill(title: outputType.title.uppercased())
                    if outputType == .quiz,
                       let difficulty = output.quizDifficulty ?? item.quizDifficulty
                    {
                        AtlasPill(title: difficulty.title.uppercased())
                    }
                }
            } else if let error = item.errorMessage, !error.isEmpty {
                AtlasChatBubble(text: "Runtime notice: \(error)", isUser: false)
            } else {
                AtlasChatBubble(text: pendingAssistantStatusText(for: item), isUser: false)
            }
        }
    }

    private var commandThreadItems: [PromptQueueItem] {
        guard let activeID = currentConciergeSessionID else {
            return []
        }
        return session.promptQueue
            .filter { item in
                guard item.workspaceLane == nil else { return false }
                return item.conciergeSessionID == nil || item.conciergeSessionID == activeID
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var currentConciergeSessionID: String? {
        session.activeConciergeSessionID ?? session.allConciergeSessions().first?.id
    }

    private var activeRunPillTitle: String {
        let active = commandThreadItems.filter { $0.status == .running || $0.status == .queued }.count
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
        commandThreadItems.map { item in
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
        let isPodcast = (item.outputType ?? .standard) == .podcast
        switch item.status {
        case .running:
            if isPodcast {
                return "Generating your podcast-style briefing in cloud runtime..."
            }
            return "Analyzing context and drafting your \(outputType) response..."
        case .queued:
            if let checkpoint = item.checkpointNote?.lowercased(),
               checkpoint.contains("waiting to reconnect") || checkpoint.contains("no internet")
            {
                return "Waiting to reconnect to the internet. Your \(outputType) response will resume automatically."
            }
            if let retry = item.retryCount, retry > 0 {
                if isPodcast {
                    return "Runtime reconnect in progress (\(retry)/\(maxRuntimeRetries)). Continuing podcast audio rendering..."
                }
                return "Runtime reconnect in progress (\(retry)/\(maxRuntimeRetries)). Continuing your \(outputType) response..."
            }
            if isPodcast {
                return "Queued for podcast briefing generation."
            }
            return "Preparing your \(outputType) response..."
        case .failed:
            if isPodcast {
                return "Podcast generation failed. Tap retry."
            }
            return "AI runtime unavailable. No response was generated. Tap retry."
        case .done:
            return isPodcast ? "Podcast ready." : "Response ready."
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

    private var conciergeSessionsSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Concierge chats")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    Spacer()
                    Button("Done") {
                        chatSessionsPresented = false
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                Button("New chat") {
                    session.createConciergeSession()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.allConciergeSessions()) { chat in
                            Button {
                                session.activateConciergeSession(chat.id)
                                chatSessionsPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(chat.title)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                        Spacer()
                                        if chat.id == currentConciergeSessionID {
                                            AtlasPill(title: "ACTIVE")
                                        }
                                    }
                                    Text(chat.summary)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(AtlasTheme.backgroundGradient.ignoresSafeArea())
        }
    }
}

private struct PodcastAudioBubble: View {
    let artifact: PodcastAudioArtifact
    let summary: String

#if canImport(AVFoundation)
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var elapsedSeconds: Double = 0
    @State private var timer: Timer?
#endif
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Podcast Audio")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)
            Text(summary)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.textPrimary)

#if canImport(AVFoundation)
            if let loadError {
                Text(loadError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.95))
            } else {
                HStack(spacing: 10) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(AtlasTheme.accentWarm.opacity(0.92))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(player == nil)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(formatDuration(elapsedSeconds)) / \(formatDuration(durationSeconds))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text("\(artifact.voiceName) · \(artifact.mimeType)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }
                    Spacer()
                }
            }
#else
            Text("Audio playback is unavailable on this platform build.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)
#endif
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AtlasTheme.cardStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AtlasTheme.border, lineWidth: 1)
        )
#if canImport(AVFoundation)
        .onAppear {
            configurePlayerIfNeeded()
        }
        .onDisappear {
            stopPlayback()
        }
#endif
    }

#if canImport(AVFoundation)
    private var durationSeconds: Double {
        if let player {
            return max(1, player.duration)
        }
        return max(1, artifact.estimatedDurationSeconds)
    }

    private func configurePlayerIfNeeded() {
        guard player == nil else { return }
        let audioURL = URL(fileURLWithPath: artifact.filePath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            loadError = "Audio file missing. Re-run podcast generation."
            return
        }
        do {
            let loaded = try AVAudioPlayer(contentsOf: audioURL)
            loaded.prepareToPlay()
            player = loaded
            elapsedSeconds = 0
            loadError = nil
        } catch {
            loadError = "Could not load audio for playback."
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
            return
        }
        if player.currentTime >= player.duration {
            player.currentTime = 0
            elapsedSeconds = 0
        }
        isPlaying = player.play()
        if isPlaying {
            startTimer()
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        elapsedSeconds = 0
        stopTimer()
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let player else { return }
            elapsedSeconds = max(0, player.currentTime)
            if !player.isPlaying {
                isPlaying = false
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let clamped = Int(max(0, round(seconds)))
        let minutes = clamped / 60
        let remainder = clamped % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
#endif
}

#if canImport(UIKit)
private func dismissChatKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
#else
private func dismissChatKeyboard() {}
#endif

struct CodingWorkspaceCard: View {
    @EnvironmentObject private var session: SessionStore
    @State private var workspacePathDraft = ""
    @State private var fileFilter = ""
    @FocusState private var promptFocused: Bool
    @FocusState private var commandFocused: Bool

    var body: some View {
        AtlasScreen(
            title: "Coding Workspace",
            subtitle: "Codex-style local workspace with on-device model reasoning and persistent memory"
        ) {
            AtlasPanel(
                heading: "Workspace root",
                caption: "Set a project path, index files locally, and keep context on this device"
            ) {
                TextField("/private/var/mobile/.../project", text: $workspacePathDraft)
                    .atlasFieldStyle()

                HStack(spacing: 10) {
                    Button("Set root") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Scan files") {
                        session.setCodingWorkspaceRootPath(workspacePathDraft)
                        session.rescanCodingWorkspace()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                }

                HStack(spacing: 8) {
                    AtlasPill(title: "\(session.codingWorkspaceFiles.count) files")
                    AtlasPill(title: "\(session.codingMessages.count) messages")
                    AtlasPill(title: "\(session.codingMemoryRecords.count) memory")
                }

                if !session.codingWorkspaceRootPath.isEmpty {
                    Text("Active root: \(session.codingWorkspaceRootPath)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            AtlasPanel(
                heading: "Navigator and editor",
                caption: "Browse indexed files and edit the active file directly"
            ) {
                TextField("Filter files", text: $fileFilter)
                    .atlasFieldStyle()

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if filteredFiles.isEmpty {
                            Text("No files found. Scan workspace or adjust filter.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        } else {
                            ForEach(filteredFiles, id: \.self) { filePath in
                                Button {
                                    session.openCodingFile(filePath)
                                } label: {
                                    CodingFileRow(
                                        title: session.codingRelativePath(filePath),
                                        isSelected: session.codingSelectedFilePath == filePath
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 210)

                HStack {
                    Text(session.codingSelectedFilePath.map(session.codingRelativePath) ?? "No file open")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    if session.codingEditorIsDirty {
                        AtlasPill(title: "UNSAVED")
                    }
                    Spacer()
                }

                TextEditor(
                    text: Binding(
                        get: { session.codingEditorText },
                        set: { session.setCodingEditorText($0) }
                    )
                )
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .padding(10)
                .frame(minHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )

                HStack(spacing: 10) {
                    Button("Save file") {
                        session.saveCodingFile()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())

                    Button("Reload") {
                        if let path = session.codingSelectedFilePath {
                            session.openCodingFile(path)
                        }
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())

                    Button("Remember") {
                        session.rememberCurrentCodingFile()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }
            }

            AtlasPanel(
                heading: "Local agent and command lane",
                caption: "Prompt the local coding model and run iOS-safe workspace commands"
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if session.codingMessages.isEmpty {
                            Text("No coding conversation yet. Try: /help or ask for a code plan.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                        } else {
                            ForEach(Array(session.codingMessages.suffix(50).reversed())) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(roleLabel(message.role))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(roleColor(message.role))
                                    if message.role == .assistant {
                                        ResponseFeedbackCard(
                                            source: "ios_coding_workspace",
                                            prompt: priorUserPrompt(for: message.id),
                                            response: message.content
                                        )
                                    } else {
                                        Text(message.content)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.black.opacity(0.2))
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)

                TextField("Ask local coding agent (or /help)", text: $session.codingPromptDraft, axis: .vertical)
                    .lineLimit(2 ... 7)
                    .atlasFieldStyle()
                    .focused($promptFocused)

                HStack(spacing: 10) {
                    Button(session.codingIsGeneratingReply ? "Thinking..." : "Send prompt") {
                        promptFocused = false
                        session.submitCodingPrompt()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(session.codingIsGeneratingReply)

                    Button("Clear chat") {
                        promptFocused = false
                        session.clearCodingMemory()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                TextField("Command (pwd, ls, cat <path>, grep <pattern>)", text: $session.codingCommandDraft)
                    .atlasFieldStyle()
                    .focused($commandFocused)

                HStack(spacing: 10) {
                    Button(session.codingIsRunningCommand ? "Running..." : "Run command") {
                        commandFocused = false
                        session.runCodingCommand()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(session.codingIsRunningCommand)

                    Button("Clear output") {
                        commandFocused = false
                        session.codingCommandOutput = ""
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                }

                ScrollView {
                    Text(session.codingCommandOutput.isEmpty ? "No command output yet." : session.codingCommandOutput)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(AtlasTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )
            }

            AtlasPanel(
                heading: "Memory bank",
                caption: "Append-only local coding memory; practical limit is your device storage and RAM"
            ) {
                Text(session.codingMemoryUsageEstimate())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)

                if session.codingMemoryRecords.isEmpty {
                    Text("No coding memory records yet.")
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    ForEach(Array(session.codingMemoryRecords.suffix(10).reversed())) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.summary)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(record.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                                .lineLimit(3)
                            if let path = record.relatedFilePath {
                                Text(session.codingRelativePath(path))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }
                }
            }
        }
        .onAppear {
            if workspacePathDraft.isEmpty {
                workspacePathDraft = session.codingWorkspaceRootPath
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    promptFocused = false
                    commandFocused = false
                }
            }
        }
    }

    private var filteredFiles: [String] {
        let query = fileFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return session.codingWorkspaceFiles }
        return session.codingWorkspaceFiles.filter { filePath in
            session.codingRelativePath(filePath).lowercased().contains(query)
        }
    }

    private func roleLabel(_ role: CodingMessageRole) -> String {
        switch role {
        case .user: return "YOU"
        case .assistant: return "LOCAL AGENT"
        case .system: return "SYSTEM"
        case .command: return "COMMAND"
        }
    }

    private func roleColor(_ role: CodingMessageRole) -> Color {
        switch role {
        case .user: return AtlasTheme.accentWarm
        case .assistant: return AtlasTheme.accent
        case .system: return AtlasTheme.textSecondary
        case .command: return Color.green.opacity(0.9)
        }
    }

    private func priorUserPrompt(for messageID: String) -> String {
        guard let index = session.codingMessages.firstIndex(where: { $0.id == messageID }) else {
            return ""
        }
        guard index > 0 else { return "" }
        for scan in stride(from: index - 1, through: 0, by: -1) {
            let message = session.codingMessages[scan]
            if message.role == .user {
                return message.content
            }
        }
        return ""
    }
}

private struct CodingFileRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(AtlasTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AtlasTheme.cardStrong : Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AtlasTheme.accentWarm : AtlasTheme.border, lineWidth: 1)
            )
    }
}
