import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct RootDashboardView: View {
    private enum Tab: Hashable {
        case command
        case execution
        case workspaces
        case concierge
        case more
    }

    @EnvironmentObject private var session: SessionStore
    @State private var selectedTab: Tab = .concierge
    @State private var openSurveyFromRequest = false

    init() {
#if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(AtlasTheme.tabBarSurface)
        appearance.shadowColor = UIColor(AtlasTheme.border.opacity(0.55))
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
#endif
    }

    var body: some View {
        Group {
            if session.isSignedIn && session.billingAccessEnabled {
                TabView(selection: $selectedTab) {
                    CommandCenterCard()
                        .tag(Tab.command)
                        .tabItem { Label("Command", systemImage: "sparkles") }

                    ProactiveFeedCard()
                        .tag(Tab.execution)
                        .tabItem { Label("Execution", systemImage: "chart.line.uptrend.xyaxis") }

                    WorkspacesCard()
                        .tag(Tab.workspaces)
                        .tabItem { Label("Projects", systemImage: "square.grid.2x2") }

                    PromptQueueCard()
                        .tag(Tab.concierge)
                        .tabItem { Label("Chat", systemImage: "message.fill") }

                    MoreMenuCard(openSurveyRequested: $openSurveyFromRequest)
                        .tag(Tab.more)
                        .tabItem { Label("More", systemImage: "ellipsis.circle") }
                }
                .tint(AtlasTheme.accentWarm)
                .toolbarColorScheme(.dark, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(AtlasTheme.tabBarSurface, for: .tabBar)
                .onChange(of: session.openSurveyTabRequested) { _, requested in
                    guard requested else { return }
                    selectedTab = .more
                    openSurveyFromRequest = true
                    session.openSurveyTabRequested = false
                }
            } else {
                AccessLockScreen()
            }
        }
    }
}

private struct AccessLockScreen: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        AtlasScreen(
            title: "Atlas Access",
            subtitle: "Sign in and activate billing to unlock the workspace."
        ) {
            AtlasPanel(
                heading: "Step 1 · Sign in or sign up",
                caption: "Guest mode is disabled."
            ) {
                if !session.isSignedIn {
                    Button(session.isAppleSignInInProgress ? "Connecting to Apple…" : "Sign in with Apple") {
                        session.startNativeAppleSignIn()
                    }
                    .buttonStyle(AtlasPrimaryButtonStyle())
                    .disabled(session.isAppleSignInInProgress || session.isGoogleSignInInProgress || session.isPasskeyInProgress)

                    Button(session.isGoogleSignInInProgress ? "Connecting to Google…" : "Sign in with Google") {
                        session.startGoogleSignIn()
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .disabled(session.isAppleSignInInProgress || session.isGoogleSignInInProgress || session.isPasskeyInProgress)

                    HStack(spacing: 10) {
                        Button(session.isPasskeyInProgress ? "Passwordless sign in…" : "Passwordless sign in") {
                            session.signInWithPasswordless()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .disabled(session.isAppleSignInInProgress || session.isGoogleSignInInProgress || session.isPasskeyInProgress)

                        Button("Passwordless sign up") {
                            session.signUpWithPasswordless()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .disabled(session.isAppleSignInInProgress || session.isGoogleSignInInProgress || session.isPasskeyInProgress)
                    }
                } else {
                    HStack {
                        Text("Signed in as \(session.accountLabel).")
                            .foregroundStyle(AtlasTheme.textSecondary)
                        Spacer()
                        Button("Sign out") {
                            session.signOut()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                    }
                }

                Text(session.accountStatusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            AtlasPanel(
                heading: "Step 2 · Add payment method",
                caption: "Cloud AI runs only after billing is active."
            ) {
                Button("In-App Purchase / Apple Pay (Recommended)") {
                    session.startInAppPurchaseFlow()
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
                .disabled(!session.isSignedIn)

                Button("Manual card setup (Stripe)") {
                    Task {
                        await session.startManualCardSetup { url in
                            openURL(url)
                        }
                    }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .disabled(!session.isSignedIn)

                Button("Refresh billing status") {
                    Task { await session.refreshBillingStatus() }
                }
                .buttonStyle(AtlasSecondaryButtonStyle())
                .disabled(!session.isSignedIn)

                Text(session.billingStatusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(session.billingAccessEnabled ? .green : AtlasTheme.textSecondary)
            }
        }
    }
}

private enum MoreDestination: Hashable {
    case survey
    case account
    case planSource
    case memory
    case mobility
    case guide
    case plans
    case systemOutput
}

private struct MoreMenuCard: View {
    @EnvironmentObject private var session: SessionStore
    @Binding var openSurveyRequested: Bool
    @State private var navigationPath: [MoreDestination] = []
    @State private var showPhotoSourceDialog = false
    @State private var showPhotoLibraryPicker = false
    @State private var showDocumentPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingPhotoDraft: ProfilePhotoDraft?
    @State private var isLoadingPhoto = false
    @State private var photoLoadError = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AtlasScreen(
                title: "More",
                subtitle: "Account, mobility, guide, and billing controls"
            ) {
                AtlasPanel(
                    heading: "Profile photo",
                    caption: "Shown above your menu options"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            ProfilePhotoAvatarView(
                                image: session.profilePhotoImage,
                                initials: profileInitials,
                                size: 72
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(session.accountLabel)
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundStyle(AtlasTheme.textPrimary)
                                Text(session.isSignedIn ? "Signed in" : "Signed out")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                                Text("Supports high-resolution images and RAW sources (including CR3).")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            Spacer()

                            VStack(alignment: .trailing, spacing: 8) {
                                Button(session.hasProfilePhoto ? "Adjust photo" : "Upload photo") {
                                    photoLoadError = ""
                                    showPhotoSourceDialog = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AtlasTheme.accentWarm)

                                if session.hasProfilePhoto {
                                    Button("Remove", role: .destructive) {
                                        session.clearProfilePhoto()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        if isLoadingPhoto {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Loading photo...")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            }
                        }

                        if !photoLoadError.isEmpty {
                            Text(photoLoadError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.red.opacity(0.9))
                        }
                    }
                }

                AtlasPanel(
                    heading: "Options",
                    caption: "Open any section from here"
                ) {
                    NavigationLink(value: MoreDestination.survey) {
                        MoreRow(icon: "checklist", title: "Survey", subtitle: "Primary + endless quiz flow")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.account) {
                        MoreRow(icon: "person.badge.key", title: "Account", subtitle: "Security and sign-in methods")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.planSource) {
                        MoreRow(icon: "slider.horizontal.3", title: "Plan Source", subtitle: "Tier + model routing status")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.memory) {
                        MoreRow(icon: "brain.head.profile", title: "Memory", subtitle: "Long-term personalization signals")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.mobility) {
                        MoreRow(icon: "car.side.fill", title: "Mobility", subtitle: "Van rental and planning alignment")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.guide) {
                        MoreRow(icon: "book.closed", title: "AI Guide", subtitle: "How Atlas works and privacy behavior")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.plans) {
                        MoreRow(icon: "creditcard", title: "Plans", subtitle: "Free month, then usage-based billing")
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: MoreDestination.systemOutput) {
                        MoreRow(icon: "terminal", title: "System Output", subtitle: "Operational status and traces")
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .survey:
                    AdaptiveSurveyCard()
                case .account:
                    AppleSignInCard()
                case .planSource:
                    PlanSourceCard()
                case .memory:
                    NotesCard()
                case .mobility:
                    MobilityOpsCard()
                case .guide:
                    AIGuideCard()
                case .plans:
                    SubscriptionCard()
                case .systemOutput:
                    SystemOutputCard()
                }
            }
        }
        .onChange(of: openSurveyRequested) { _, requested in
            guard requested else { return }
            pushSurveyIfNeeded()
            openSurveyRequested = false
        }
        .confirmationDialog(
            "Profile Photo",
            isPresented: $showPhotoSourceDialog,
            titleVisibility: .visible
        ) {
            Button("Photo Library") {
                showPhotoLibraryPicker = true
            }
            Button("Files (including RAW / CR3)") {
                showDocumentPicker = true
            }
            if session.hasProfilePhoto {
                Button("Remove Photo", role: .destructive) {
                    session.clearProfilePhoto()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Import from Photos or Files, then crop and adjust before saving.")
        }
        .photosPicker(
            isPresented: $showPhotoLibraryPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .sheet(isPresented: $showDocumentPicker) {
            ProfilePhotoDocumentPicker { url in
                loadPhoto(from: url)
            }
        }
        .sheet(item: $pendingPhotoDraft) { draft in
            ProfilePhotoEditorView(
                sourceImage: draft.image,
                sourceDescription: draft.sourceDescription,
                onCancel: {
                    pendingPhotoDraft = nil
                },
                onSave: { editedImage in
                    session.saveProfilePhoto(editedImage, sourceDescription: draft.sourceDescription)
                    pendingPhotoDraft = nil
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            loadPhoto(from: item)
        }
    }

    private func pushSurveyIfNeeded() {
        if navigationPath.last == .survey {
            return
        }
        navigationPath.append(.survey)
    }

    private var profileInitials: String {
        let trimmed = session.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let second = parts.dropFirst().first?.first.map(String.init) ?? ""
            let initials = (first + second).uppercased()
            return initials.isEmpty ? "A" : initials
        }
        let first = trimmed.prefix(1).uppercased()
        return first.isEmpty ? "A" : String(first)
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        isLoadingPhoto = true
        photoLoadError = ""

        Task {
            let result = await ProfilePhotoLoader.loadFromPhotosPickerItem(item)
            await MainActor.run {
                isLoadingPhoto = false
                switch result {
                case let .success(image):
                    pendingPhotoDraft = ProfilePhotoDraft(
                        image: image,
                        sourceDescription: "Photo Library"
                    )
                case let .failure(error):
                    photoLoadError = error.localizedDescription
                }
                selectedPhotoItem = nil
            }
        }
    }

    private func loadPhoto(from url: URL) {
        isLoadingPhoto = true
        photoLoadError = ""

        Task {
            let result = await ProfilePhotoLoader.loadFromFileURL(url)
            await MainActor.run {
                isLoadingPhoto = false
                switch result {
                case let .success(image):
                    pendingPhotoDraft = ProfilePhotoDraft(
                        image: image,
                        sourceDescription: "Files (\(url.lastPathComponent))"
                    )
                case let .failure(error):
                    photoLoadError = error.localizedDescription
                }
            }
        }
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasTheme.accentWarm)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AtlasTheme.cardStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AtlasTheme.border, lineWidth: 1)
        )
    }
}

private struct ProfilePhotoDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let sourceDescription: String
}

private struct ProfilePhotoAvatarView: View {
    let image: UIImage?
    let initials: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [AtlasTheme.accent, AtlasTheme.accentWarm],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct ProfilePhotoDocumentPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.image, .rawImage]
        if let cr3 = UTType(filenameExtension: "cr3") {
            types.append(cr3)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPicked: (URL) -> Void

        init(onPicked: @escaping (URL) -> Void) {
            self.onPicked = onPicked
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let first = urls.first else { return }
            onPicked(first)
        }
    }
}

private enum ProfilePhotoLoader {
    private static let maxPixelDimension = 4_096
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func loadFromPhotosPickerItem(_ item: PhotosPickerItem) async -> Result<UIImage, Error> {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return .failure(NSError(
                    domain: "ProfilePhotoLoader",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Could not load this photo from the photo library."]
                ))
            }
            guard let image = decodeImage(from: data, maxPixelDimension: maxPixelDimension) else {
                return .failure(NSError(
                    domain: "ProfilePhotoLoader",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "This photo format could not be decoded."]
                ))
            }
            return .success(image)
        } catch {
            return .failure(NSError(
                domain: "ProfilePhotoLoader",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "Could not load selected photo: \(error.localizedDescription)"]
            ))
        }
    }

    static func loadFromFileURL(_ url: URL) async -> Result<UIImage, Error> {
        await Task.detached(priority: .userInitiated) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if let image = decodeImage(from: url, maxPixelDimension: maxPixelDimension) {
                return Result<UIImage, Error>.success(image)
            }
            return .failure(NSError(
                domain: "ProfilePhotoLoader",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Could not decode this file. Try another photo or export a compatible RAW preview."]
            ))
        }.value
    }

    private static func decodeImage(from data: Data, maxPixelDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }

    private static func decodeImage(from url: URL, maxPixelDimension: Int) -> UIImage? {
        let ext = url.pathExtension.lowercased()
        let likelyRaw = ["cr3", "cr2", "dng", "nef", "arw", "orf", "rw2", "raf", "pef"].contains(ext)

        if likelyRaw, let raw = decodeWithCoreImage(url: url, maxPixelDimension: maxPixelDimension) {
            return raw
        }

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }

        if let coreImage = decodeWithCoreImage(url: url, maxPixelDimension: maxPixelDimension) {
            return coreImage
        }

        if let data = try? Data(contentsOf: url) {
            return decodeImage(from: data, maxPixelDimension: maxPixelDimension)
        }

        return nil
    }

    private static func decodeWithCoreImage(url: URL, maxPixelDimension: Int) -> UIImage? {
        guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            return nil
        }
        let maxDimension = max(input.extent.width, input.extent.height)
        guard maxDimension > 0 else { return nil }

        let scale = min(1.0, CGFloat(maxPixelDimension) / maxDimension)
        let output = scale < 1.0
            ? input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : input

        guard let cg = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct ProfilePhotoEditorView: View {
    let sourceImage: UIImage
    let sourceDescription: String
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var activeMagnification: CGFloat = 1.0
    @State private var activeDrag: CGSize = .zero

    @State private var exposure: Double = 0.0
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0

    @State private var isSaving = false
    @State private var saveError = ""

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    var body: some View {
        NavigationStack {
            let cropSide = min(UIScreen.main.bounds.width - 36, 360)
            let zoomNow = clampedZoom(zoom * activeMagnification)
            let offsetNow = clampedOffset(
                CGSize(width: offset.width + activeDrag.width, height: offset.height + activeDrag.height),
                cropSide: cropSide,
                zoom: zoomNow
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        Color.black.opacity(0.92)

                        Image(uiImage: sourceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cropSide, height: cropSide)
                            .scaleEffect(zoomNow)
                            .offset(offsetNow)
                            .brightness(brightness + (exposure * 0.08))
                            .contrast(contrast)
                            .saturation(saturation)
                            .gesture(cropGesture(cropSide: cropSide))

                        ZStack {
                            Color.black.opacity(0.46)
                            Circle()
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                        .allowsHitTesting(false)

                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .frame(width: cropSide, height: cropSide)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity)

                    Text("Source: \(sourceDescription)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        sliderRow(title: "Zoom", value: Binding(
                            get: { Double(zoom) },
                            set: { zoom = clampedZoom(CGFloat($0)) }
                        ), range: 1 ... 6)
                        sliderRow(title: "Exposure", value: $exposure, range: -2 ... 2)
                        sliderRow(title: "Brightness", value: $brightness, range: -0.4 ... 0.4)
                        sliderRow(title: "Contrast", value: $contrast, range: 0.6 ... 1.8)
                        sliderRow(title: "Saturation", value: $saturation, range: 0 ... 2)
                    }

                    Button("Reset Adjustments") {
                        exposure = 0
                        brightness = 0
                        contrast = 1
                        saturation = 1
                        zoom = 1
                        offset = .zero
                        activeMagnification = 1
                        activeDrag = .zero
                        saveError = ""
                    }
                    .buttonStyle(.bordered)

                    if !saveError.isEmpty {
                        Text(saveError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red.opacity(0.9))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Edit Profile Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        saveEditedPhoto(cropSide: cropSide)
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func cropGesture(cropSide: CGFloat) -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                activeDrag = value.translation
            }
            .onEnded { value in
                let zoomNow = clampedZoom(zoom * activeMagnification)
                offset = clampedOffset(
                    CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                    cropSide: cropSide,
                    zoom: zoomNow
                )
                activeDrag = .zero
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                activeMagnification = value
            }
            .onEnded { value in
                zoom = clampedZoom(zoom * value)
                offset = clampedOffset(offset, cropSide: cropSide, zoom: zoom)
                activeMagnification = 1
            }

        return drag.simultaneously(with: magnify)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AtlasTheme.textPrimary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AtlasTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(AtlasTheme.accentWarm)
        }
    }

    private func clampedZoom(_ candidate: CGFloat) -> CGFloat {
        min(maxZoom, max(minZoom, candidate))
    }

    private func clampedOffset(_ candidate: CGSize, cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        let base = baseDisplaySize(cropSide: cropSide)
        let scaled = CGSize(width: base.width * zoom, height: base.height * zoom)
        let maxX = max(0, (scaled.width - cropSide) / 2)
        let maxY = max(0, (scaled.height - cropSide) / 2)
        return CGSize(
            width: min(max(candidate.width, -maxX), maxX),
            height: min(max(candidate.height, -maxY), maxY)
        )
    }

    private func baseDisplaySize(cropSide: CGFloat) -> CGSize {
        let sourceWidth = max(sourceImage.size.width, 1)
        let sourceHeight = max(sourceImage.size.height, 1)
        let ratio = sourceWidth / sourceHeight
        if ratio >= 1 {
            return CGSize(width: cropSide * ratio, height: cropSide)
        }
        return CGSize(width: cropSide, height: cropSide / ratio)
    }

    private func saveEditedPhoto(cropSide: CGFloat) {
        let zoomNow = clampedZoom(zoom * activeMagnification)
        let offsetNow = clampedOffset(
            CGSize(width: offset.width + activeDrag.width, height: offset.height + activeDrag.height),
            cropSide: cropSide,
            zoom: zoomNow
        )

        isSaving = true
        saveError = ""

        Task {
            let rendered = renderFinalImage(cropSide: cropSide, zoom: zoomNow, offset: offsetNow)
            isSaving = false
            guard let rendered else {
                saveError = "Could not render cropped image."
                return
            }
            onSave(rendered)
        }
    }

    private func renderFinalImage(cropSide: CGFloat, zoom: CGFloat, offset: CGSize) -> UIImage? {
        guard let adjusted = adjustedImage() else { return nil }
        guard let cg = adjusted.cgImage else { return nil }

        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let ratio = pixelWidth / pixelHeight
        let baseWidth = ratio >= 1 ? cropSide * ratio : cropSide
        let baseHeight = ratio >= 1 ? cropSide : cropSide / ratio
        let displayWidth = baseWidth * zoom
        let displayHeight = baseHeight * zoom

        let pxPerPointX = pixelWidth / displayWidth
        let pxPerPointY = pixelHeight / displayHeight
        let cropPixelWidth = cropSide * pxPerPointX
        let cropPixelHeight = cropSide * pxPerPointY
        var cropX = ((displayWidth - cropSide) / 2 - offset.width) * pxPerPointX
        var cropY = ((displayHeight - cropSide) / 2 - offset.height) * pxPerPointY

        cropX = min(max(0, cropX), max(0, pixelWidth - cropPixelWidth))
        cropY = min(max(0, cropY), max(0, pixelHeight - cropPixelHeight))

        let cropRect = CGRect(
            x: cropX.rounded(.down),
            y: cropY.rounded(.down),
            width: min(cropPixelWidth.rounded(.down), pixelWidth),
            height: min(cropPixelHeight.rounded(.down), pixelHeight)
        ).integral

        guard let cropped = cg.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        return resizedSquareImage(croppedImage, targetDimension: 1_400)
    }

    private func adjustedImage() -> UIImage? {
        guard var ci = CIImage(image: sourceImage) else { return sourceImage }

        let exposureFilter = CIFilter.exposureAdjust()
        exposureFilter.inputImage = ci
        exposureFilter.ev = Float(exposure)
        if let output = exposureFilter.outputImage {
            ci = output
        }

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = ci
        colorFilter.brightness = Float(brightness)
        colorFilter.contrast = Float(contrast)
        colorFilter.saturation = Float(saturation)
        if let output = colorFilter.outputImage {
            ci = output
        }

        guard let cg = Self.ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func resizedSquareImage(_ image: UIImage, targetDimension: CGFloat) -> UIImage {
        let side = targetDimension
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
