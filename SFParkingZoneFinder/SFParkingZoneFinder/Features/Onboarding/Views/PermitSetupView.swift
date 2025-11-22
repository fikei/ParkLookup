import SwiftUI

/// Allows user to select their RPP permit areas
struct PermitSetupView: View {
    @Binding var selectedAreas: Set<String>
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Your Permits")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Select the RPP areas on your permit")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Selection summary
            if !selectedAreas.isEmpty {
                HStack {
                    Text("Selected: \(selectedAreas.sorted().joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)

                    Spacer()

                    Button("Clear") {
                        selectedAreas.removeAll()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            // Area Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SFPermitAreas.all, id: \.self) { area in
                        PermitAreaButton(
                            area: area,
                            isSelected: selectedAreas.contains(area),
                            onTap: {
                                toggleArea(area)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            // Info note
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.accentColor)
                Text("You can add more permits later in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Buttons
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text(selectedAreas.isEmpty ? "Continue Without Permit" : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }

                if !selectedAreas.isEmpty {
                    Button(action: onSkip) {
                        Text("Skip for Now")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
    }

    private func toggleArea(_ area: String) {
        if selectedAreas.contains(area) {
            selectedAreas.remove(area)
        } else {
            selectedAreas.insert(area)
        }
    }
}

// MARK: - Permit Area Button

struct PermitAreaButton: View {
    let area: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(area)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 56, height: 56)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .accessibilityLabel("Area \(area)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    PermitSetupView(
        selectedAreas: .constant(["Q", "R"]),
        onContinue: {},
        onSkip: {}
    )
}
