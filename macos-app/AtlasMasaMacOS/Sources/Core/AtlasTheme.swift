import SwiftUI

enum AtlasTheme {
    static let backgroundTop = Color(red: 0.09, green: 0.03, blue: 0.06)
    static let backgroundBottom = Color(red: 0.02, green: 0.04, blue: 0.12)
    static let card = Color.white.opacity(0.08)
    static let cardStrong = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.18)
    static let accent = Color(red: 0.86, green: 0.20, blue: 0.23)
    static let accentWarm = Color(red: 0.98, green: 0.55, blue: 0.30)
    static let textPrimary = Color(red: 0.95, green: 0.96, blue: 1.0)
    static let textSecondary = Color.white.opacity(0.72)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glowGradient: RadialGradient {
        RadialGradient(
            colors: [accent.opacity(0.24), .clear],
            center: .topTrailing,
            startRadius: 10,
            endRadius: 520
        )
    }
}

struct AtlasScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AtlasTheme.backgroundGradient
                .ignoresSafeArea()
            AtlasTheme.glowGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))
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
                    .font(.system(size: 20, weight: .semibold, design: .serif))
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
                .fill(AtlasTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AtlasTheme.border, lineWidth: 1)
                )
        )
    }
}

struct AtlasPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AtlasTheme.accent.opacity(0.44), AtlasTheme.accentWarm.opacity(0.28)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .foregroundStyle(AtlasTheme.textPrimary)
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
                    .fill(AtlasTheme.cardStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AtlasTheme.border, lineWidth: 1)
            )
            .foregroundStyle(AtlasTheme.textPrimary)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }
}

extension View {
    func atlasFieldStyle() -> some View {
        self
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(AtlasTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AtlasTheme.border, lineWidth: 1)
            )
    }
}
