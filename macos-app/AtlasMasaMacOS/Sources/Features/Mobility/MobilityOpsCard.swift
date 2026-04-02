import SwiftUI
import WebKit

struct MobilityOpsCard: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var draftName = ""
    @State private var draftQuery = ""
    @State private var draftNotes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Travel Maps & Itinerary")
                        .font(.largeTitle.weight(.bold))
                    Text("Integrated Google Maps, saved locations, itinerary naming, and place notes")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        AtlasPanel(heading: "Travel profile", caption: "Context that shapes itinerary planning") {
                            Form {
                                Section {
                                    Toggle("I need van rental support", isOn: $session.vanRentalNeeded)
                                        .toggleStyle(.switch)
                                }

                                Divider().padding(.vertical, 8)

                                Section {
                                    TextField("Primary Region", text: $session.travelRegion)
                                    TextField("Annual Distance (km)", text: $session.annualDistanceKM)
                                    TextField("Work Mode", text: $session.workspaceMode)
                                }
                            }
                            .controlSize(.regular)
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Spacer()
                                Button("Apply Mobility Profile") {
                                    session.applyDailyCheckIn()
                                    session.appendOutput("Mobility profile updated for itinerary and location planning.")
                                }
                                .buttonStyle(AtlasPrimaryButtonStyle())
                            }
                        }

                        AtlasPanel(heading: "Save location", caption: "Create named places with Google Maps query and notes") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Location name", text: $draftName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Google Maps search query or address", text: $draftQuery)
                                    .textFieldStyle(.roundedBorder)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Location notes")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AtlasTheme.textPrimary)
                                    TextEditor(text: $draftNotes)
                                        .frame(minHeight: 120)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(nsColor: .textBackgroundColor))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 24) {
                        AtlasPanel(heading: "Google Maps", caption: "Preview the selected location or itinerary lead stop") {
                            GoogleMapsPreviewCard(query: mapQuery)
                                .frame(height: 310)
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

                        AtlasPanel(heading: "Saved locations", caption: "Select, edit, and reuse places") {
                            if session.savedTravelLocations.isEmpty {
                                Text("No saved locations yet. Add a place on the left to start building your travel library.")
                                    .font(.footnote)
                                    .foregroundStyle(AtlasTheme.textSecondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(session.savedTravelLocations) { location in
                                        Button {
                                            session.selectedTravelLocationID = location.id
                                            loadDraft(from: location)
                                        } label: {
                                            HStack(alignment: .top, spacing: 12) {
                                                VStack(alignment: .leading, spacing: 6) {
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
                                                            .lineLimit(2)
                                                    }
                                                }
                                                Spacer()
                                                if location.id == session.selectedTravelLocationID {
                                                    Text("Selected")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(AtlasTheme.accentWarm)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(location.id == session.selectedTravelLocationID ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
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

                        AtlasPanel(heading: "Travel itinerary", caption: "Name it, order the stops, and keep location notes attached") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(
                                    "Itinerary title",
                                    text: Binding(
                                        get: { session.activeTravelItineraryDraft.title },
                                        set: { session.updateTravelItineraryTitle($0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                if session.activeTravelItineraryLocations.isEmpty {
                                    Text("No itinerary stops yet. Save a location and add it to the itinerary.")
                                        .font(.footnote)
                                        .foregroundStyle(AtlasTheme.textSecondary)
                                } else {
                                    ForEach(Array(session.activeTravelItineraryLocations.enumerated()), id: \.element.id) { index, location in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundStyle(AtlasTheme.accentWarm)
                                                .frame(width: 24, height: 24)
                                                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))

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

                                            HStack(spacing: 8) {
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
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(32)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        guard target >= 0, target < session.activeTravelItineraryDraft.locationIDs.count else { return }
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

private struct GoogleMapsPreviewCard: NSViewRepresentable {
    let query: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
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
        <html><body style="margin:0;background:#111820;color:#c8d3df;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100%;">
        <div style="text-align:center;padding:24px;">
        <div style="font-size:18px;font-weight:600;margin-bottom:8px;">Google Maps preview</div>
        <div style="font-size:14px;opacity:0.8;">Save or select a location to preview it here.</div>
        </div></body></html>
        """
    }
}
