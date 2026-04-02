import SwiftUI
import WebKit

struct MobilityOpsCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var draftName = ""
    @State private var draftQuery = ""
    @State private var draftNotes = ""

    var body: some View {
        AtlasScreen(
            title: "Travel Maps + Itinerary",
            subtitle: "Google Maps powered planning, saved places, and location notes"
        ) {
            AtlasPanel(
                heading: "Travel profile",
                caption: "Set the context used by itinerary and travel planning"
            ) {
                Toggle("I need van rental support", isOn: $session.vanRentalNeeded)
                    .tint(AtlasTheme.accent)
                    .foregroundStyle(AtlasTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Primary region")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter region", text: $session.travelRegion)
                        .atlasFieldStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Annual distance (km)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter yearly distance", text: $session.annualDistanceKM)
                        .keyboardType(.numberPad)
                        .atlasFieldStyle()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Work mode")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AtlasTheme.textPrimary)
                    TextField("Enter work mode", text: $session.workspaceMode)
                        .atlasFieldStyle()
                }

                Button("Apply mobility profile") {
                    session.applyDailyCheckIn()
                    session.appendOutput("Mobility profile updated for itinerary and location planning.")
                }
                .buttonStyle(AtlasPrimaryButtonStyle())
            }

            AtlasPanel(
                heading: "Google Maps",
                caption: "Integrated map preview for the selected place or itinerary lead stop"
            ) {
                GoogleMapsPreviewCard(query: mapQuery)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 10) {
                    Button("Open In Google Maps") {
                        guard let url = googleMapsSearchURL(for: mapQuery) else { return }
                        openURL(url)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .disabled(mapQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Open Directions") {
                        guard let url = googleMapsDirectionsURL() else { return }
                        openURL(url)
                    }
                    .buttonStyle(AtlasSecondaryButtonStyle())
                    .disabled(session.activeTravelItineraryLocations.isEmpty)
                }
            }

            AtlasPanel(
                heading: "Save location",
                caption: "Name a place, keep notes on it, and reuse it in itineraries"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Location name", text: $draftName)
                        .atlasFieldStyle()
                    TextField("Google Maps search query or address", text: $draftQuery)
                        .textInputAutocapitalization(.words)
                        .atlasFieldStyle()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AtlasTheme.textPrimary)
                        TextEditor(text: $draftNotes)
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AtlasTheme.surface.opacity(0.95))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AtlasTheme.border, lineWidth: 1)
                            )
                    }

                    HStack(spacing: 10) {
                        Button(selectedLocation == nil ? "Save Location" : "Update Location") {
                            saveDraft()
                        }
                        .buttonStyle(AtlasPrimaryButtonStyle())

                        Button("Clear") {
                            clearDraft()
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())

                        Button("Add To Itinerary") {
                            guard let id = selectedLocation?.id else { return }
                            session.addLocationToTravelItinerary(id)
                        }
                        .buttonStyle(AtlasSecondaryButtonStyle())
                        .disabled(selectedLocation == nil)
                    }
                }
            }

            AtlasPanel(
                heading: "Saved locations",
                caption: "Select, edit, note, and reuse saved travel places"
            ) {
                if session.savedTravelLocations.isEmpty {
                    Text("No saved locations yet. Add a place above to start building your map library.")
                        .font(.footnote)
                        .foregroundStyle(AtlasTheme.textSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(session.savedTravelLocations) { location in
                            Button {
                                session.selectedTravelLocationID = location.id
                                loadDraft(from: location)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(location.name)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AtlasTheme.textPrimary)
                                        Spacer()
                                        if location.id == session.selectedTravelLocationID {
                                            Text("Selected")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AtlasTheme.accentWarm)
                                        }
                                    }
                                    Text(location.googleMapsQuery)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    if !location.notes.isEmpty {
                                        Text(location.notes)
                                            .font(.caption)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(location.id == session.selectedTravelLocationID ? AtlasTheme.surfaceElevated : AtlasTheme.surface.opacity(0.92))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(location.id == session.selectedTravelLocationID ? AtlasTheme.accentWarm : AtlasTheme.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Add To Itinerary") {
                                    session.addLocationToTravelItinerary(location.id)
                                }
                                Button("Delete", role: .destructive) {
                                    session.removeSavedTravelLocation(id: location.id)
                                    if session.selectedTravelLocationID == nil {
                                        clearDraft()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            AtlasPanel(
                heading: "Travel itinerary",
                caption: "Name the itinerary and order saved stops"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "Itinerary title",
                        text: Binding(
                            get: { session.activeTravelItinerary.title },
                            set: { session.updateTravelItineraryTitle($0) }
                        )
                    )
                    .atlasFieldStyle()

                    if session.activeTravelItineraryLocations.isEmpty {
                        Text("No itinerary stops yet. Save a location and add it to the itinerary.")
                            .font(.footnote)
                            .foregroundStyle(AtlasTheme.textSecondary)
                    } else {
                        ForEach(Array(session.activeTravelItineraryLocations.enumerated()), id: \.element.id) { index, location in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(AtlasTheme.accentWarm)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(AtlasTheme.surfaceElevated))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    Text(location.googleMapsQuery)
                                        .font(.caption)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                    if !location.notes.isEmpty {
                                        Text(location.notes)
                                            .font(.caption)
                                            .foregroundStyle(AtlasTheme.textSecondary)
                                    }
                                }

                                Spacer()

                                VStack(spacing: 6) {
                                    Button {
                                        moveLocation(at: index, delta: -1)
                                    } label: {
                                        Image(systemName: "arrow.up")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == 0)

                                    Button {
                                        moveLocation(at: index, delta: 1)
                                    } label: {
                                        Image(systemName: "arrow.down")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(index == session.activeTravelItineraryLocations.count - 1)

                                    Button(role: .destructive) {
                                        session.removeLocationFromTravelItinerary(location.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(AtlasTheme.textSecondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .onAppear {
            if let selected = session.selectedTravelLocation {
                loadDraft(from: selected)
            }
        }
        .onChange(of: session.selectedTravelLocationID) { _, _ in
            if let selected = session.selectedTravelLocation {
                loadDraft(from: selected)
            }
        }
    }

    private var selectedLocation: SavedTravelLocation? {
        session.selectedTravelLocation
    }

    private var mapQuery: String {
        if let selectedLocation {
            return selectedLocation.googleMapsQuery
        }
        if let first = session.activeTravelItineraryLocations.first {
            return first.googleMapsQuery
        }
        return draftQuery
    }

    private func saveDraft() {
        if let selectedLocation {
            session.updateSavedTravelLocation(
                id: selectedLocation.id,
                name: draftName,
                query: draftQuery,
                notes: draftNotes
            )
        } else {
            session.addSavedTravelLocation(name: draftName, query: draftQuery, notes: draftNotes)
        }
    }

    private func clearDraft() {
        draftName = ""
        draftQuery = ""
        draftNotes = ""
        session.selectedTravelLocationID = nil
    }

    private func loadDraft(from location: SavedTravelLocation) {
        draftName = location.name
        draftQuery = location.googleMapsQuery
        draftNotes = location.notes
    }

    private func moveLocation(at index: Int, delta: Int) {
        let target = index + delta
        guard target >= 0, target < session.activeTravelItinerary.locationIDs.count else { return }
        session.moveTravelItineraryLocations(fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? target + 1 : target)
    }

    private func googleMapsSearchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: trimmed)
        ]
        return components?.url
    }

    private func googleMapsDirectionsURL() -> URL? {
        let locations = session.activeTravelItineraryLocations
        guard let destination = locations.last?.googleMapsQuery else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        var items = [URLQueryItem(name: "api", value: "1")]
        if let origin = locations.first?.googleMapsQuery, locations.count > 1 {
            items.append(URLQueryItem(name: "origin", value: origin))
        }
        items.append(URLQueryItem(name: "destination", value: destination))
        let waypoints = locations.dropFirst().dropLast().map(\.googleMapsQuery).joined(separator: "|")
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: waypoints))
        }
        components?.queryItems = items
        return components?.url
    }
}

private struct GoogleMapsPreviewCard: UIViewRepresentable {
    let query: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            webView.loadHTMLString(placeholderHTML, baseURL: nil)
            return
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/maps?q=\(encoded)&output=embed")
        else {
            webView.loadHTMLString(placeholderHTML, baseURL: nil)
            return
        }
        webView.load(URLRequest(url: url))
    }

    private var placeholderHTML: String {
        """
        <html><body style="margin:0;background:#0f1620;color:#c8d3df;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100%;">
        <div style="text-align:center;padding:24px;">
        <div style="font-size:18px;font-weight:600;margin-bottom:8px;">Google Maps preview</div>
        <div style="font-size:14px;opacity:0.8;">Save or select a location to preview it here.</div>
        </div></body></html>
        """
    }
}
