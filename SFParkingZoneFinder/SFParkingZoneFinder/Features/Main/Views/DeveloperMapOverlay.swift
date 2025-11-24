import SwiftUI

/// Floating developer panel overlay for the map
/// Only appears when developer mode is unlocked
/// Provides real-time controls for polygon simplification settings
struct DeveloperMapOverlay: View {
    @ObservedObject var devSettings: DeveloperSettings
    @Binding var isPanelExpanded: Bool
    @State private var showingSaveConfirmation = false
    @State private var savedCandidateName: String = ""
    var onRefreshLayers: (() -> Void)?  // Callback to trigger layer refresh

    /// Panel height as fraction of screen
    private var panelHeight: CGFloat {
        UIScreen.main.bounds.height / 3
    }

    var body: some View {
        VStack {
            Spacer()

            HStack {
                // Developer panel (bottom left, aligned with expand/collapse button)
                VStack(alignment: .leading, spacing: 8) {
                    // Expanded panel (appears above button)
                    if isPanelExpanded {
                        developerPanel
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .scale(scale: 0.9))
                            ))
                    }

                    // Code button to toggle panel - matches expand/collapse style
                    // Shows pressed/active state when panel is open
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPanelExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isPanelExpanded ? "xmark" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isPanelExpanded ? .black : .white)
                            .frame(width: 44, height: 44)
                            .background(isPanelExpanded ? Color.white : Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.leading, 16)
                .padding(.bottom, 16)

                Spacer()
            }
        }
        .alert("Configuration Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Saved as '\(savedCandidateName)'\n\nConfiguration copied to clipboard and logged to console.")
        }
    }

    // MARK: - Developer Panel

    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.secondary)
                    Text("Layer Settings")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Refresh button
                    Button {
                        refreshLayers()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }

                // Pipeline status
                Text(devSettings.simplificationDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Merging section (top)
                    mergingToggles

                    Divider()

                    // Simplification toggles
                    simplificationToggles

                    // Sliders section (always shown - overlap tolerance is always available)
                    Divider()
                    slidersSection

                    Divider()

                    // Color and opacity settings
                    colorSettings

                    Divider()

                    // Debug visualization toggles
                    debugToggles

                    Divider()

                    // Save candidate button
                    saveCandidateButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 280, height: panelHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Merging Toggles

    private var mergingToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Merging")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            compactToggle("Overlap Clipping", isOn: $devSettings.useOverlapClipping, icon: "square.on.square.intersection.dashed")
            compactToggle("Merge Overlapping", isOn: $devSettings.mergeOverlappingSameZone, icon: "arrow.triangle.merge")
            compactToggle("Proximity Merge", isOn: $devSettings.useProximityMerging, icon: "arrow.left.and.right.righttriangle.left.righttriangle.right")
        }
    }

    // MARK: - Simplification Toggles

    private var simplificationToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Simplification")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            compactToggle("Douglas-Peucker", isOn: $devSettings.useDouglasPeucker, icon: "waveform.path")
            compactToggle("Grid Snapping", isOn: $devSettings.useGridSnapping, icon: "grid")
            compactToggle("Corner Rounding", isOn: $devSettings.useCornerRounding, icon: "circle.bottomhalf.filled")
            compactToggle("Convex Hull", isOn: $devSettings.useConvexHull, icon: "pentagon")

            if devSettings.useDouglasPeucker {
                compactToggle("Preserve Curves", isOn: $devSettings.preserveCurves, icon: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
    }

    // MARK: - Sliders

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parameters")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if devSettings.useDouglasPeucker {
                sliderControl(
                    label: "D-P Tolerance",
                    value: $devSettings.douglasPeuckerTolerance,
                    range: 0.00001...0.001,
                    step: 0.00001,
                    formatter: { String(format: "%.5f° (~%dm)", $0, Int($0 * 111000)) }
                )
            }

            if devSettings.useGridSnapping {
                sliderControl(
                    label: "Grid Size",
                    value: $devSettings.gridSnapSize,
                    range: 0.00001...0.0005,
                    step: 0.00001,
                    formatter: { String(format: "%.5f° (~%dm)", $0, Int($0 * 111000)) }
                )
            }

            if devSettings.useCornerRounding {
                sliderControl(
                    label: "Corner Radius",
                    value: $devSettings.cornerRoundingRadius,
                    range: 0.00001...0.0002,
                    step: 0.00001,
                    formatter: { String(format: "%.5f° (~%dm)", $0, Int($0 * 111000)) }
                )
            }

            if devSettings.preserveCurves && devSettings.useDouglasPeucker {
                sliderControl(
                    label: "Curve Threshold",
                    value: $devSettings.curveAngleThreshold,
                    range: 5...45,
                    step: 1,
                    formatter: { "\(Int($0))°" }
                )
            }

            // Overlap tolerance (always shown for future overlap cleanup feature)
            sliderControl(
                label: "Overlap Tolerance",
                value: $devSettings.overlapTolerance,
                range: 0.000001...0.0001,
                step: 0.000001,
                formatter: { String(format: "%.6f° (~%.1fm)", $0, $0 * 111000) }
            )

            // Proximity merge distance (only shown when proximity merge is enabled)
            if devSettings.useProximityMerging {
                sliderControl(
                    label: "Merge Distance",
                    value: $devSettings.proximityMergeDistance,
                    range: 0.0...10.0,
                    step: 0.5,
                    formatter: { String(format: "%.1fm", $0) }
                )
            }

            // Deduplication overlap threshold (always shown for filtering duplicate polygons)
            sliderControl(
                label: "Dedup Threshold",
                value: $devSettings.deduplicationThreshold,
                range: 0.0...1.0,
                step: 0.05,
                formatter: { String(format: "%.0f%%", $0 * 100) }
            )
        }
    }

    // MARK: - Color Settings

    private var colorSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colors & Style")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            // Permitted Zone (user has permit)
            zoneColorGroup(
                label: "Permitted Zone",
                colorHex: $devSettings.userZoneColorHex,
                previewColor: devSettings.userZoneColor,
                fillOpacity: $devSettings.otherZoneFillOpacity,
                strokeOpacity: $devSettings.otherZoneStrokeOpacity,
                strokeWidth: $devSettings.permittedZoneStrokeWidth
            )

            // Non-Permitted Zone (no permit held)
            zoneColorGroup(
                label: "Non-Permitted Zone",
                colorHex: $devSettings.rppZoneColorHex,
                previewColor: devSettings.rppZoneColor,
                fillOpacity: $devSettings.otherZoneFillOpacity,
                strokeOpacity: $devSettings.otherZoneStrokeOpacity,
                strokeWidth: $devSettings.nonPermittedZoneStrokeWidth
            )

            // Metered/Paid Zones
            zoneColorGroup(
                label: "Metered/Paid Zones",
                colorHex: $devSettings.meteredZoneColorHex,
                previewColor: devSettings.meteredZoneColor,
                fillOpacity: $devSettings.otherZoneFillOpacity,
                strokeOpacity: $devSettings.otherZoneStrokeOpacity,
                strokeWidth: $devSettings.meteredZoneStrokeWidth
            )

            // In Zone opacity (current zone only)
            Text("In Zone")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.top, 8)

            sliderControl(
                label: "Fill Opacity",
                value: $devSettings.currentZoneFillOpacity,
                range: 0.0...1.0,
                step: 0.05,
                formatter: { String(format: "%.0f%%", $0 * 100) }
            )

            sliderControl(
                label: "Stroke Opacity",
                value: $devSettings.currentZoneStrokeOpacity,
                range: 0.0...1.0,
                step: 0.05,
                formatter: { String(format: "%.0f%%", $0 * 100) }
            )
        }
    }

    // MARK: - Debug Toggles

    private var debugToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            compactToggle("Lookup Bounds", isOn: $devSettings.showLookupBoundaries, icon: "rectangle.dashed")
            compactToggle("Original Overlay", isOn: $devSettings.showOriginalOverlay, icon: "square.on.square.dashed")
            compactToggle("Vertex Counts", isOn: $devSettings.showVertexCounts, icon: "number")
        }
    }

    // MARK: - Save Candidate Button

    private var saveCandidateButton: some View {
        Button {
            saveCandidate()
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Save Candidate")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
        }
    }

    // MARK: - Helper Views

    private func compactToggle(_ label: String, isOn: Binding<Bool>, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isOn.wrappedValue ? .accentColor : .secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .scaleEffect(0.8)
        }
    }

    private func sliderControl(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                Text(formatter(value.wrappedValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)
                .tint(.accentColor)
        }
    }

    private func hexColorField(label: String, value: Binding<String>, previewColor: UIColor) -> some View {
        HStack {
            // Color preview circle
            Circle()
                .fill(Color(uiColor: previewColor))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            // Hex input field
            HStack(spacing: 2) {
                Text("#")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("RRGGBB", text: value)
                    .font(.caption.monospaced())
                    .textCase(.uppercase)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
        }
    }

    private func zoneColorGroup(
        label: String,
        colorHex: Binding<String>,
        previewColor: UIColor,
        fillOpacity: Binding<Double>,
        strokeOpacity: Binding<Double>,
        strokeWidth: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Color header
            hexColorField(label: label, value: colorHex, previewColor: previewColor)

            // Fill opacity
            sliderControl(
                label: "Fill",
                value: fillOpacity,
                range: 0.0...1.0,
                step: 0.05,
                formatter: { String(format: "%.0f%%", $0 * 100) }
            )

            // Stroke opacity
            sliderControl(
                label: "Stroke",
                value: strokeOpacity,
                range: 0.0...1.0,
                step: 0.05,
                formatter: { String(format: "%.0f%%", $0 * 100) }
            )

            // Stroke width
            sliderControl(
                label: "Width",
                value: strokeWidth,
                range: 0.0...5.0,
                step: 0.25,
                formatter: { String(format: "%.2f", $0) }
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Layer Refresh

    private func refreshLayers() {
        // Force reload of overlays by incrementing reload trigger
        devSettings.forceReloadOverlays()

        // Call optional callback (for future use)
        onRefreshLayers?()

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Save Candidate Logic

    private func saveCandidate() {
        let config = SimplificationCandidate(
            timestamp: Date(),
            useDouglasPeucker: devSettings.useDouglasPeucker,
            douglasPeuckerTolerance: devSettings.douglasPeuckerTolerance,
            useGridSnapping: devSettings.useGridSnapping,
            gridSnapSize: devSettings.gridSnapSize,
            useConvexHull: devSettings.useConvexHull,
            preserveCurves: devSettings.preserveCurves,
            curveAngleThreshold: devSettings.curveAngleThreshold
        )

        // Generate name from settings
        savedCandidateName = config.suggestedName

        // Export as JSON
        if let jsonData = try? JSONEncoder().encode(config),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Copy to clipboard
            UIPasteboard.general.string = jsonString

            // Log to console for pipeline integration
            print("=== SIMPLIFICATION CANDIDATE SAVED ===")
            print("Name: \(savedCandidateName)")
            print("JSON:")
            print(jsonString)
            print("=====================================")

            // Also log human-readable format
            print("\nHuman-readable config:")
            print(config.humanReadableDescription)
            print("")
        }

        // Show confirmation
        showingSaveConfirmation = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Simplification Candidate Model

/// Represents a saved simplification configuration candidate
/// Used for exporting settings to integrate into the pipeline
struct SimplificationCandidate: Codable {
    let timestamp: Date
    let useDouglasPeucker: Bool
    let douglasPeuckerTolerance: Double
    let useGridSnapping: Bool
    let gridSnapSize: Double
    let useConvexHull: Bool
    let preserveCurves: Bool
    let curveAngleThreshold: Double

    /// Generate a suggested name based on enabled features
    var suggestedName: String {
        var parts: [String] = []

        if useDouglasPeucker {
            let tolMeters = Int(douglasPeuckerTolerance * 111000)
            parts.append("dp\(tolMeters)m")
        }
        if useGridSnapping {
            let gridMeters = Int(gridSnapSize * 111000)
            parts.append("grid\(gridMeters)m")
        }
        if useConvexHull {
            parts.append("hull")
        }
        if preserveCurves && useDouglasPeucker {
            parts.append("curves\(Int(curveAngleThreshold))deg")
        }

        if parts.isEmpty {
            return "original"
        }

        return parts.joined(separator: "_")
    }

    /// Human-readable description for logging
    var humanReadableDescription: String {
        var lines: [String] = []

        lines.append("Pipeline: \(suggestedName)")
        lines.append("")

        if useDouglasPeucker {
            lines.append("Douglas-Peucker: ON")
            lines.append("  Tolerance: \(String(format: "%.5f", douglasPeuckerTolerance))° (~\(Int(douglasPeuckerTolerance * 111000))m)")
            if preserveCurves {
                lines.append("  Curve preservation: ON (>\(Int(curveAngleThreshold))°)")
            }
        } else {
            lines.append("Douglas-Peucker: OFF")
        }

        if useGridSnapping {
            lines.append("Grid Snapping: ON")
            lines.append("  Grid size: \(String(format: "%.5f", gridSnapSize))° (~\(Int(gridSnapSize * 111000))m)")
        } else {
            lines.append("Grid Snapping: OFF")
        }

        if useConvexHull {
            lines.append("Convex Hull: ON (aggressive)")
        }

        return lines.joined(separator: "\n")
    }

    /// Swift code snippet for pipeline integration
    var swiftCodeSnippet: String {
        """
        // Simplification preset: \(suggestedName)
        static let \(suggestedName.replacingOccurrences(of: "-", with: "_")) = SimplificationPreset(
            useDouglasPeucker: \(useDouglasPeucker),
            douglasPeuckerTolerance: \(douglasPeuckerTolerance),
            useGridSnapping: \(useGridSnapping),
            gridSnapSize: \(gridSnapSize),
            useConvexHull: \(useConvexHull),
            preserveCurves: \(preserveCurves),
            curveAngleThreshold: \(curveAngleThreshold)
        )
        """
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isExpanded = false

        var body: some View {
            ZStack {
                Color.gray.opacity(0.3)
                    .ignoresSafeArea()

                DeveloperMapOverlay(devSettings: DeveloperSettings.shared, isPanelExpanded: $isExpanded)
            }
        }
    }

    return PreviewWrapper()
}
