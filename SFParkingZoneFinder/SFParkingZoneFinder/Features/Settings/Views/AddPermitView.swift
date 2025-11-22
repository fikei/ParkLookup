import SwiftUI

/// View for adding a new permit
struct AddPermitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedArea: String?

    let onAdd: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Your Permit Area")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Choose the residential permit area shown on your parking permit sticker.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    // Area Grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(PermitAreas.sanFrancisco, id: \.self) { area in
                            AreaButton(
                                area: area,
                                isSelected: selectedArea == area,
                                hint: PermitAreas.neighborhoodHint(for: area)
                            ) {
                                selectedArea = area
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Selected Area Info
                    if let area = selectedArea, let hint = PermitAreas.neighborhoodHint(for: area) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Area \(area)")
                                .font(.headline)
                            Text(hint)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Add Permit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        if let area = selectedArea {
                            onAdd(area)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedArea == nil)
                }
            }
        }
    }
}

// MARK: - Area Button

struct AreaButton: View {
    let area: String
    let isSelected: Bool
    let hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(area)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(width: 60, height: 60)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Area \(area)")
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    AddPermitView { area in
        print("Added area: \(area)")
    }
}
