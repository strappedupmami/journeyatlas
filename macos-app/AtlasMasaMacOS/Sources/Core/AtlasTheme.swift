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

// MARK: - Native Chat Bubble
struct AtlasChatBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(text)
                .font(.body)
                .foregroundStyle(isUser ? Color.white : AtlasTheme.textPrimary)
                .textSelection(.enabled) // Good that you had this!
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            isUser
                                ? AnyShapeStyle(AtlasTheme.brandGradient)
                                : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                        )
                )
                // Only stroke the AI bubble, keep user bubble clean
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isUser ? Color.clear : AtlasTheme.border, lineWidth: 1)
                )

            if !isUser { Spacer(minLength: 60) }
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
