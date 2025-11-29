import SwiftUI
import MapKit
import CoreLocation
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "AddressSearch")

// San Francisco bounds for filtering search results
private let sfBounds = (
    north: 37.8324,
    south: 37.6398,
    east: -122.3281,
    west: -122.5274
)

private func isWithinSF(_ coordinate: CLLocationCoordinate2D) -> Bool {
    coordinate.latitude >= sfBounds.south &&
    coordinate.latitude <= sfBounds.north &&
    coordinate.longitude >= sfBounds.west &&
    coordinate.longitude <= sfBounds.east
}

/// Search card for address lookup with type-ahead suggestions
struct AddressSearchCard: View {
    let currentAddress: String?
    let isAtCurrentLocation: Bool
    let onAddressSelected: (CLLocationCoordinate2D) -> Void
    let onResetToCurrentLocation: () -> Void
    let onOutsideCoverage: (() -> Void)?

    init(
        currentAddress: String?,
        isAtCurrentLocation: Bool = true,
        onAddressSelected: @escaping (CLLocationCoordinate2D) -> Void,
        onResetToCurrentLocation: @escaping () -> Void,
        onOutsideCoverage: (() -> Void)? = nil
    ) {
        self.currentAddress = currentAddress
        self.isAtCurrentLocation = isAtCurrentLocation
        self.onAddressSelected = onAddressSelected
        self.onResetToCurrentLocation = onResetToCurrentLocation
        self.onOutsideCoverage = onOutsideCoverage
    }

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [MKLocalSearchCompletion] = []
    @StateObject private var searchCompleter = SearchCompleterDelegate()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))

                if isSearching {
                    TextField("Search address...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .autocorrectionDisabled()
                        .onChange(of: searchText) {
                            searchCompleter.search(query: searchText)
                        }
                } else {
                    // Show current address when not searching
                    Text(currentAddress ?? "Current Location")
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearching = true
                                isSearchFocused = true
                            }
                        }
                }

                Spacer()

                // Reset to current location button
                if isSearching {
                    Button {
                        cancelSearch()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                } else {
                    Button {
                        onResetToCurrentLocation()
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(isAtCurrentLocation ? .blue : .gray)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            // Search results dropdown
            if isSearching && !searchCompleter.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchCompleter.results.prefix(5), id: \.self) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 20))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        if result != searchCompleter.results.prefix(5).last {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSearching)
        .animation(.easeInOut(duration: 0.2), value: searchCompleter.results.count)
    }

    private func cancelSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            searchText = ""
            isSearching = false
            isSearchFocused = false
            searchCompleter.results = []
        }
    }

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)

        search.start { response, error in
            if let location = response?.mapItems.first?.placemark.location {
                let coordinate = location.coordinate
                // Log the exact coordinate returned by MKLocalSearch
                logger.info("📍 MKLocalSearch returned: (\(coordinate.latitude), \(coordinate.longitude)) for '\(result.title)'")

                // Validate coordinate is within SF coverage area
                if isWithinSF(coordinate) {
                    logger.info("✅ Selected address within SF: \(result.title)")
                    onAddressSelected(coordinate)
                    cancelSearch()
                } else {
                    logger.warning("❌ Selected address outside SF coverage: \(result.title)")
                    onOutsideCoverage?()
                    cancelSearch()
                }
            } else if let error = error {
                logger.error("Search failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Delegate for MKLocalSearchCompleter to provide type-ahead suggestions
class SearchCompleterDelegate: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Restrict results to San Francisco area
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        )
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            // Filter results to only show San Francisco addresses
            self.results = completer.results.filter { result in
                let subtitle = result.subtitle.lowercased()
                let title = result.title.lowercased()
                let combined = "\(title) \(subtitle)"
                // Only accept results that explicitly mention San Francisco
                return combined.contains("san francisco") ||
                       combined.contains("sf, ca") ||
                       combined.contains("sf,ca") ||
                       combined.contains(", sf")
            }
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        logger.error("Search completer error: \(error.localizedDescription)")
    }
}

#Preview {
    VStack {
        AddressSearchCard(
            currentAddress: "123 Main St, San Francisco",
            onAddressSelected: { _ in },
            onResetToCurrentLocation: { }
        )
        .padding()

        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
