import SwiftUI
import MapKit
import os.log

private let logger = Logger(subsystem: "com.sfparkingzonefinder", category: "AddressSearch")

/// Search card for address lookup with type-ahead suggestions
struct AddressSearchCard: View {
    let currentAddress: String?
    let onAddressSelected: (CLLocationCoordinate2D) -> Void
    let onResetToCurrentLocation: () -> Void

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
                        .onChange(of: searchText) { _, newValue in
                            searchCompleter.search(query: newValue)
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
                            .foregroundColor(.blue)
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
            if let coordinate = response?.mapItems.first?.placemark.coordinate {
                logger.info("Selected address: \(result.title)")
                onAddressSelected(coordinate)
                cancelSearch()
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
        // Bias results towards San Francisco
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
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
            self.results = completer.results
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
