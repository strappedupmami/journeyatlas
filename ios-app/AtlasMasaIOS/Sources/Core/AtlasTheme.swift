import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AtlasTheme {
    static let backgroundTop = Color(red: 0.06, green: 0.08, blue: 0.10)
    static let backgroundMid = Color(red: 0.05, green: 0.07, blue: 0.09)
    static let backgroundBottom = Color(red: 0.02, green: 0.03, blue: 0.05)
    static let card = Color.white.opacity(0.065)
    static let cardStrong = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.16)
    static let accent = Color(red: 0.06, green: 0.67, blue: 0.52)
    static let accentWarm = Color(red: 0.18, green: 0.84, blue: 0.68)
    static let textPrimary = Color(red: 0.95, green: 0.97, blue: 0.99)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)
    static let assistantBubble = Color.white.opacity(0.055)
    static let inputSurface = Color.white.opacity(0.06)
    static let chromeSurface = Color.black.opacity(0.34)
    static let chromeEdge = Color.white.opacity(0.08)
    static let tabBarSurface = Color.black.opacity(0.56)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundMid, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glowGradient: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.22), .clear],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 560
        )
    }

    static var ambientGradient: RadialGradient {
        RadialGradient(
            colors: [accentWarm.opacity(0.16), .clear],
            center: .bottomLeading,
            startRadius: 0,
            endRadius: 520
        )
    }

    static var chromeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.05), Color.white.opacity(0.015)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func brandDisplayFont(size: CGFloat) -> Font {
#if canImport(UIKit)
        let candidates = [
            "Avenir Next Demi Bold",
            "Avenir Next",
            "Helvetica Neue",
        ]
        for name in candidates where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
#endif
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

struct AtlasScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let titleFont: Font?
    let titleTracking: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String,
        titleFont: Font? = nil,
        titleTracking: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.titleTracking = titleTracking
        self.content = content
    }

    var body: some View {
        ZStack {
            AtlasTheme.backgroundGradient
                .ignoresSafeArea()
            AtlasTheme.glowGradient
                .ignoresSafeArea()
            AtlasTheme.ambientGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(titleFont ?? .system(size: 30, weight: .semibold, design: .default))
                            .tracking(titleTracking)
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AtlasTheme.textSecondary)
                    }

                    content()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
        }
    }
}

struct AtlasPanel<Content: View>: View {
    let heading: String
    let caption: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(AtlasTheme.textPrimary)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AtlasTheme.cardStrong, AtlasTheme.card],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.24), radius: 16, x: 0, y: 8)
        )
    }
}

struct AtlasPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.accent.opacity(0.28), AtlasTheme.accentWarm.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(AtlasTheme.border.opacity(0.9), lineWidth: 1)
                    )
            )
            .foregroundStyle(AtlasTheme.textPrimary)
            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
    }
}

struct AtlasPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.accent, AtlasTheme.accentWarm],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: AtlasTheme.accent.opacity(0.35), radius: 12, x: 0, y: 5)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct AtlasSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.cardStrong, AtlasTheme.card],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AtlasTheme.border, lineWidth: 1)
            )
            .foregroundStyle(AtlasTheme.textPrimary)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

struct ResponseFeedbackCard: View {
    @EnvironmentObject private var session: SessionStore

    let source: String
    let prompt: String
    let response: String

    @State private var selectedText = ""
    @State private var selectedSentiment: ResponseFeedbackSentiment = .thumbsUp
    @State private var includePrompt = true
    @State private var contentScope: ResponseFeedbackContentScope = .fullResponse
    @State private var userNote = ""
    @State private var showingComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select any response text, then send quick quality feedback.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.textSecondary)

            selectableResponseView
                .frame(minHeight: 110, maxHeight: 220)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )

            if !selectedText.isEmpty {
                Text("Highlighted: \(selectedText)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.accentWarm)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                Button {
                    openComposer(.thumbsUp)
                } label: {
                    Label("Helpful", systemImage: "hand.thumbsup.fill")
                }
                .buttonStyle(AtlasSecondaryButtonStyle())

                Button {
                    openComposer(.thumbsDown)
                } label: {
                    Label("Needs work", systemImage: "hand.thumbsdown.fill")
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
            }
        }
        .sheet(isPresented: $showingComposer) {
            ResponseFeedbackComposerSheet(
                sentiment: selectedSentiment,
                hasPrompt: !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                selectedText: selectedText,
                includePrompt: $includePrompt,
                contentScope: $contentScope,
                userNote: $userNote,
                onCancel: {
                    showingComposer = false
                },
                onSend: {
                    session.submitResponseQualityFeedback(
                        source: source,
                        sentiment: selectedSentiment,
                        prompt: prompt,
                        fullResponse: response,
                        selectedText: selectedText,
                        includePrompt: includePrompt,
                        contentScope: contentScope,
                        userNote: userNote
                    )
                    userNote = ""
                    showingComposer = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func openComposer(_ sentiment: ResponseFeedbackSentiment) {
        selectedSentiment = sentiment
        includePrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        contentScope = selectedText.isEmpty ? .fullResponse : .highlightedOnly
        showingComposer = true
    }

    @ViewBuilder
    private var selectableResponseView: some View {
#if canImport(UIKit)
        SelectableReportTextView(text: response, selectedText: $selectedText)
#else
        Text(response)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(AtlasTheme.textPrimary)
            .textSelection(.enabled)
#endif
    }
}

private struct ResponseFeedbackComposerSheet: View {
    let sentiment: ResponseFeedbackSentiment
    let hasPrompt: Bool
    let selectedText: String
    @Binding var includePrompt: Bool
    @Binding var contentScope: ResponseFeedbackContentScope
    @Binding var userNote: String
    let onCancel: () -> Void
    let onSend: () -> Void

    private var highlightRequiredButMissing: Bool {
        contentScope == .highlightedOnly
            && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AtlasTheme.backgroundGradient
                .ignoresSafeArea()
            AtlasTheme.glowGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(sentiment == .thumbsUp ? "Send positive signal" : "Send improvement report")
                        .font(.system(size: 22, weight: .semibold, design: .default))
                        .foregroundStyle(AtlasTheme.textPrimary)

                    Text("Choose what to include in this report.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    Toggle("Include original prompt", isOn: $includePrompt)
                        .tint(AtlasTheme.accent)
                        .foregroundStyle(AtlasTheme.textPrimary)
                        .disabled(!hasPrompt)

                    Picker("Response payload", selection: $contentScope) {
                        ForEach(ResponseFeedbackContentScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !selectedText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Highlighted section")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AtlasTheme.textPrimary)
                            Text(selectedText)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AtlasTheme.textSecondary)
                                .lineLimit(6)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                        )
                    }

                    if highlightRequiredButMissing {
                        Text("Highlight text in the response first, or switch to full response.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }

                    TextField("Optional note for the team", text: $userNote, axis: .vertical)
                        .lineLimit(2 ... 5)
                        .atlasFieldStyle()

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Send report") {
                            onSend()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())
                        .disabled(highlightRequiredButMissing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
    }
}

#if canImport(UIKit)
private struct SelectableReportTextView: UIViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = UIColor(AtlasTheme.textPrimary)
        view.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
            if !selectedText.isEmpty {
                selectedText = ""
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableReportTextView

        init(_ parent: SelectableReportTextView) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            guard range.location != NSNotFound, range.length > 0,
                  let swiftRange = Range(range, in: textView.text ?? "")
            else {
                if !parent.selectedText.isEmpty {
                    parent.selectedText = ""
                }
                return
            }

            let selected = String((textView.text ?? "")[swiftRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if parent.selectedText != selected {
                parent.selectedText = selected
            }
        }
    }
}
#endif

struct AtlasChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser {
                Spacer(minLength: 44)
                bubbleContent
            } else {
                assistantAvatar
                bubbleContent
                Spacer(minLength: 28)
            }
        }
    }

    private var bubbleContent: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(isUser ? Color.white : AtlasTheme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isUser
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AtlasTheme.accent, AtlasTheme.accentWarm],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [AtlasTheme.assistantBubble, Color.white.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isUser ? Color.white.opacity(0.2) : AtlasTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isUser ? 0.22 : 0.16), radius: isUser ? 12 : 9, x: 0, y: 5)
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AtlasTheme.accent.opacity(0.95), AtlasTheme.accentWarm.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

extension View {
    func atlasFieldStyle() -> some View {
        self
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(AtlasTheme.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.inputSurface, Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AtlasTheme.border.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

#if canImport(UIKit)
private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
#else
private func dismissKeyboard() {}
#endif
