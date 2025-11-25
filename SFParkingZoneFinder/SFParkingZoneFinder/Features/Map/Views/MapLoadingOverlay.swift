import SwiftUI

/// Subtle loading overlay for the map view (shown to regular users)
struct MapLoadingOverlay: View {
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ZStack {
                // Subtle semi-transparent background
                Color.black.opacity(0.1)
                    .ignoresSafeArea()

                // Simple spinner
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)

                    Text("Loading map...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 8)
                )
            }
            .transition(.opacity)
        }
    }
}

/// Detailed loading overlay for developer view (shows detailed status)
struct DeveloperLoadingOverlay: View {
    let isLoadingZones: Bool
    let isLoadingOverlays: Bool
    let statusMessage: String

    @State private var dots = ""

    var body: some View {
        if isLoadingZones || isLoadingOverlays {
            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(isLoadingZones || isLoadingOverlays ? 360 : 0))
                            .animation(
                                isLoadingZones || isLoadingOverlays ?
                                    .linear(duration: 2).repeatForever(autoreverses: false) : .default,
                                value: isLoadingZones || isLoadingOverlays
                            )

                        Text("Developer: Loading Status")
                            .font(.headline)

                        Spacer()
                    }

                    Divider()

                    // Zone Loading Status
                    HStack(spacing: 12) {
                        if isLoadingZones {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zone Data")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(isLoadingZones ? "Loading zones\(dots)" : "Zones loaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Overlay Loading Status
                    HStack(spacing: 12) {
                        if isLoadingOverlays {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Map Overlays")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(isLoadingOverlays ? "Rendering overlays\(dots)" : "Overlays rendered")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }

                    // Detailed Status Message
                    if !statusMessage.isEmpty {
                        Divider()

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.blue)

                            Text(statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 12)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                startDotsAnimation()
            }
        }
    }

    private func startDotsAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if !isLoadingZones && !isLoadingOverlays {
                timer.invalidate()
                dots = ""
                return
            }

            if dots.count >= 3 {
                dots = ""
            } else {
                dots += "."
            }
        }
    }
}

#Preview("Map Loading") {
    MapLoadingOverlay(isLoading: true)
}

#Preview("Developer Loading - Both") {
    DeveloperLoadingOverlay(
        isLoadingZones: true,
        isLoadingOverlays: true,
        statusMessage: "Processing 421 zones with simplification pipeline..."
    )
}

#Preview("Developer Loading - Overlays Only") {
    DeveloperLoadingOverlay(
        isLoadingZones: false,
        isLoadingOverlays: true,
        statusMessage: "Rendering 617 polygons in batches of 500..."
    )
}
