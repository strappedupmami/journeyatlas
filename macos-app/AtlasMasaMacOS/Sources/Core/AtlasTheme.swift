import SwiftUI

// MARK: - Atlas Design System
enum AtlasTheme {
    // Dark red + black palette for a stricter desktop look.
    static let accent = Color(red: 0.60, green: 0.06, blue: 0.14)
    static let accentWarm = Color(red: 0.34, green: 0.04, blue: 0.09)
    static let pureBlack = Color.black

    // Utilize native system colors for text and borders to ensure
    // perfect Dark/Light mode support and high-end feel.
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)

    // Compatibility aliases for existing views in this repo.
    static let card = cardBackground
    static let cardStrong = cardBackground.opacity(0.92)
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    static var glowGradient: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.24), .clear],
            center: .topTrailing,
            startRadius: 12,
            endRadius: 460
        )
    }

    // Brand gradient used sparingly (e.g., prominent buttons, primary chat bubbles)
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [pureBlack, accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - High-End Screen Wrapper
struct AtlasScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Area
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        // Using native title font instead of hardcoded 30pt serif
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AtlasTheme.textPrimary)

                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
                .padding(.bottom, 8)

                content()
            }
            .padding(24) // Desktop-appropriate padding
        }
        // Native macOS window background
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Refined Panel (Card)
struct AtlasPanel<Content: View>: View {
    let heading: String
    let caption: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
                    .font(.headline)
                    .foregroundStyle(AtlasTheme.textPrimary)

                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textSecondary)
                }
            }

            Divider()

            content()
        }
        .padding(16)
        .background(AtlasTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) // Tighter native curve
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AtlasTheme.border, lineWidth: 1)
        )
        // Subtle macOS-style shadow
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - macOS Styled Pill
struct AtlasPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // Using a subtle material background instead of a heavy gradient
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(AtlasTheme.border, lineWidth: 0.5)
            )
    }
}

struct AtlasModelRuntimeProgressStrip: View {
    let progress: Double
    let busy: Bool
    let title: String
    let sizeText: String
    let etaText: String
    let compact: Bool
    @State private var shimmerOffset: CGFloat = -0.8

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            GeometryReader { proxy in
                let width = max(0, proxy.size.width)
                let clamped = min(1.0, max(0.0, progress))
                let fillWidth = max(6, width * (busy ? max(0.04, clamped) : clamped))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.54, blue: 0.98),
                                    Color(red: 0.12, green: 0.78, blue: 0.86),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                        .overlay(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.35), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(28, width * 0.2))
                                .offset(x: width * shimmerOffset)
                                .opacity(busy ? 1 : 0)
                        }
                }
            }
            .frame(height: compact ? 9 : 11)

            HStack {
                Text(title)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(AtlasTheme.textSecondary)
                Spacer()
                Text("\(Int((min(1.0, max(0.0, progress)) * 100).rounded()))%")
                    .font((compact ? Font.caption2 : Font.caption).monospacedDigit())
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            HStack {
                Text(sizeText)
                    .font(.caption2)
                    .foregroundStyle(AtlasTheme.textSecondary)
                Spacer()
                Text(etaText)
                    .font(.caption2)
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
        }
        .onAppear {
            updateShimmerState()
        }
        .onChange(of: busy) { _, _ in
            updateShimmerState()
        }
    }

    private func updateShimmerState() {
        if busy {
            shimmerOffset = -0.8
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.15
            }
        } else {
            shimmerOffset = -0.8
        }
    }
}

// MARK: - Native Chat Bubble
struct AtlasChatBubble: View {
    let text: String
    let isUser: Bool
    let isStreaming: Bool
    @State private var shimmerOffset: CGFloat = -0.45

    init(text: String, isUser: Bool, isStreaming: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            bubbleText
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isUser
                                ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                                : (isStreaming
                                    ? AnyShapeStyle(Color.white.opacity(0.05))
                                    : AnyShapeStyle(AtlasTheme.brandGradient))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isUser ? AtlasTheme.border : (isStreaming ? Color.white.opacity(0.12) : AtlasTheme.accent), lineWidth: 1)
                )
                .onAppear {
                    guard isStreaming else { return }
                    shimmerOffset = -0.45
                    withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                        shimmerOffset = 1.15
                    }
                }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleText: some View {
        if isStreaming && !isUser {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.34))
                .overlay {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.98),
                                Color.white.opacity(0.2),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(72, width * 0.42))
                        .offset(x: width * shimmerOffset)
                        .mask(
                            Text(text)
                                .font(.body)
                        )
                    }
                }
        } else {
            Text(renderedAttributedText)
                .font(.body)
                .foregroundStyle(isUser ? AtlasTheme.textPrimary : Color.white)
        }
    }

    private var renderedAttributedText: AttributedString {
        if let rendered = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return rendered
        }
        return AttributedString(text)
    }
}

struct AtlasAssistantResponseView: View {
    let output: LocalReasoningOutput

    @State private var showReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AtlasChatBubble(text: primaryText, isUser: false)

            if hasReasoningDetails {
                DisclosureGroup(isExpanded: $showReasoning) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let reasoning = cleanReasoningSummary {
                            reasoningBlock(
                                title: "Why this answer",
                                body: reasoning
                            )
                        }

                        if !output.alternativesConsidered.isEmpty {
                            bulletBlock(
                                title: "Alternatives considered",
                                items: output.alternativesConsidered
                            )
                        }

                        if !output.assumptions.isEmpty {
                            bulletBlock(
                                title: "Assumptions",
                                items: output.assumptions
                            )
                        }

                        HStack(spacing: 12) {
                            if let label = cleanConfidenceLabel {
                                AtlasPill(title: "CONFIDENCE \(label.uppercased())")
                            }
                            if !output.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                AtlasPill(title: "NEXT ACTION READY")
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 720, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AtlasTheme.border, lineWidth: 1)
                    )
                    .padding(.leading, 12)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: showReasoning ? "chevron.down.circle.fill" : "chevron.right.circle")
                            .foregroundStyle(AtlasTheme.accentWarm)
                        Text("Thought process")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                }
                .tint(AtlasTheme.accentWarm)
            }
        }
    }

    private var primaryText: String {
        let body = output.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = output.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty, !body.localizedCaseInsensitiveContains(action) else {
            return body
        }
        return "\(body)\n\nNext action: \(action)"
    }

    private var cleanReasoningSummary: String? {
        let value = output.reasoningSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var cleanConfidenceLabel: String? {
        let value = output.confidenceLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private var hasReasoningDetails: Bool {
        cleanReasoningSummary != nil
            || !output.alternativesConsidered.isEmpty
            || !output.assumptions.isEmpty
            || cleanConfidenceLabel != nil
    }

    @ViewBuilder
    private func reasoningBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AtlasTheme.textSecondary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(AtlasTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func bulletBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AtlasTheme.textSecondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(AtlasTheme.accentWarm)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(AtlasTheme.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Native-Feeling Custom Button Styles
struct AtlasPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)) // Desktop standard size
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AtlasTheme.brandGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AtlasTheme.accent, lineWidth: 1)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            // Focus ring support (Standard macOS accessibility)
            .focusable()
    }
}

struct AtlasSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AtlasTheme.border, lineWidth: 1)
            )
            .foregroundStyle(AtlasTheme.textPrimary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .focusable()
    }
}

// MARK: - Text Field Styling
extension View {
    func atlasFieldStyle() -> some View {
        self
            // Instead of rebuilding the text field, we style the native one
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
        // This ensures it uses standard macOS focus rings when clicked
    }
}
