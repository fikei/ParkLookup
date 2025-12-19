import SwiftUI
import MapKit

/// Developer mode view for editing parking regulations on individual blockfaces
struct BlockfaceEditorView: View {
    @StateObject private var viewModel = BlockfaceEditorViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let blockface = viewModel.selectedBlockface {
                    // Blockface info header
                    blockfaceInfoHeader(blockface)

                    Divider()

                    // Regulations list
                    regulationsList

                    Divider()

                    // Action buttons
                    actionButtons
                } else {
                    // Blockface selector
                    blockfaceSelector
                }
            }
            .navigationTitle("Edit Regulations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if viewModel.selectedBlockface != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            viewModel.saveOverride()
                            dismiss()
                        }
                        .disabled(!viewModel.hasChanges)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingRegulationEditor) {
                if let index = viewModel.editingRegulationIndex {
                    RegulationEditorView(
                        regulation: $viewModel.editableRegulations[index],
                        onDelete: {
                            viewModel.deleteRegulation(at: index)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Subviews

    private func blockfaceInfoHeader(_ blockface: Blockface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(blockface.displayName)
                .font(.headline)

            HStack {
                Text("ID: \(blockface.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if viewModel.hasOverride {
                    Label("Override Active", systemImage: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var regulationsList: some View {
        List {
            ForEach(Array(viewModel.editableRegulations.enumerated()), id: \.element.id) { index, regulation in
                RegulationRowView(regulation: regulation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.editRegulation(at: index)
                    }
            }
            .onDelete { indexSet in
                viewModel.deleteRegulations(at: indexSet)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: { viewModel.addNewRegulation() }) {
                Label("Add Regulation", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            if viewModel.hasOverride {
                Button(action: { viewModel.removeOverride() }) {
                    Label("Remove Override", systemImage: "trash.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
    }

    private var blockfaceSelector: some View {
        VStack(spacing: 20) {
            Text("Select a blockface to edit")
                .font(.headline)
                .foregroundColor(.secondary)

            Button(action: { viewModel.loadNearbyBlockfaces() }) {
                Label("Load from Current Location", systemImage: "location.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            if viewModel.isLoading {
                ProgressView("Loading blockfaces...")
            }

            if !viewModel.nearbyBlockfaces.isEmpty {
                List(viewModel.nearbyBlockfaces) { blockface in
                    Button(action: {
                        viewModel.selectBlockface(blockface)
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(blockface.displayName)
                                .font(.subheadline)

                            Text("\(blockface.regulations.count) regulations")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if BlockfaceOverrideManager.shared.hasOverride(for: blockface.id) {
                                Label("Has override", systemImage: "pencil.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Regulation Row View

struct RegulationRowView: View {
    let regulation: BlockfaceRegulationOverride

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                regulationIcon
                Text(regulationTypeLabel)
                    .font(.headline)
                Spacer()
            }

            if let days = regulation.enforcementDays, !days.isEmpty {
                Label(formatDays(days), systemImage: "calendar")
                    .font(.caption)
            }

            if let start = regulation.enforcementStart, let end = regulation.enforcementEnd {
                Label("\(start) - \(end)", systemImage: "clock")
                    .font(.caption)
            }

            if let zones = regulation.permitZones ?? (regulation.permitZone.map { [$0] }) {
                Label("Zones: \(zones.joined(separator: ", "))", systemImage: "parkingsign.circle")
                    .font(.caption)
            }

            if let limit = regulation.timeLimit {
                Label("\(limit) min limit", systemImage: "timer")
                    .font(.caption)
            }

            if let rate = regulation.meterRate {
                Label("$\(NSDecimalNumber(decimal: rate).doubleValue, specifier: "%.2f")/hr", systemImage: "dollarsign.circle")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var regulationIcon: some View {
        Image(systemName: iconName)
            .foregroundColor(iconColor)
            .frame(width: 24)
    }

    private var iconName: String {
        switch regulation.type {
        case "metered": return "parkingsign.circle.fill"
        case "residentialPermit": return "house.circle.fill"
        case "timeLimit": return "timer"
        case "streetCleaning": return "wind"
        case "noParking": return "nosign"
        case "towAway": return "exclamationmark.triangle.fill"
        case "loadingZone": return "truck.box.fill"
        default: return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch regulation.type {
        case "metered": return .blue
        case "residentialPermit": return .orange
        case "timeLimit": return .yellow
        case "streetCleaning": return .red
        case "noParking": return .red
        case "towAway": return .red
        case "loadingZone": return .purple
        default: return .gray
        }
    }

    private var regulationTypeLabel: String {
        switch regulation.type {
        case "metered": return "Metered Parking"
        case "residentialPermit": return "Residential Permit"
        case "timeLimit": return "Time Limit"
        case "streetCleaning": return "Street Cleaning"
        case "noParking": return "No Parking"
        case "towAway": return "Tow-Away Zone"
        case "loadingZone": return "Loading Zone"
        default: return regulation.type.capitalized
        }
    }

    private func formatDays(_ days: [String]) -> String {
        if days.count == 7 {
            return "Every day"
        } else if days.sorted() == ["monday", "tuesday", "wednesday", "thursday", "friday"] {
            return "Mon-Fri"
        } else {
            return days.map { $0.prefix(3).capitalized }.joined(separator: ", ")
        }
    }
}

// MARK: - Regulation Editor View

struct RegulationEditorView: View {
    @Binding var regulation: BlockfaceRegulationOverride
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                typeSection
                enforcementDaysSection
                enforcementTimesSection
                typeSpecificSections
                specialConditionsSection
                deleteSection
            }
            .navigationTitle("Edit Regulation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var typeSection: some View {
        Section("Type") {
            Picker("Regulation Type", selection: $regulation.type) {
                Text("Metered Parking").tag("metered")
                Text("Residential Permit").tag("residentialPermit")
                Text("Time Limit").tag("timeLimit")
                Text("Street Cleaning").tag("streetCleaning")
                Text("No Parking").tag("noParking")
                Text("Tow-Away Zone").tag("towAway")
                Text("Loading Zone").tag("loadingZone")
            }
        }
    }

    private var enforcementDaysSection: some View {
        Section("Enforcement Days") {
            MultiDayPicker(selectedDays: Binding(
                get: { Set(regulation.enforcementDays ?? []) },
                set: { regulation.enforcementDays = Array($0).sorted() }
            ))
        }
    }

    private var enforcementTimesSection: some View {
        Section("Enforcement Times") {
            HStack {
                Text("Start")
                Spacer()
                TextField("HH:MM", text: enforcementStartBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
            }

            HStack {
                Text("End")
                Spacer()
                TextField("HH:MM", text: enforcementEndBinding)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
            }
        }
    }

    private var enforcementStartBinding: Binding<String> {
        Binding(
            get: { regulation.enforcementStart ?? "" },
            set: { regulation.enforcementStart = $0.isEmpty ? nil : $0 }
        )
    }

    private var enforcementEndBinding: Binding<String> {
        Binding(
            get: { regulation.enforcementEnd ?? "" },
            set: { regulation.enforcementEnd = $0.isEmpty ? nil : $0 }
        )
    }

    @ViewBuilder
    private var typeSpecificSections: some View {
        if regulation.type == "residentialPermit" {
            permitZonesSection
        }

        if regulation.type == "timeLimit" {
            timeLimitSection
        }

        if regulation.type == "metered" {
            meterRateSection
        }
    }

    private var permitZonesSection: some View {
        Section("Permit Zones") {
            TextField("Zones (comma-separated)", text: permitZonesBinding)
        }
    }

    private var permitZonesBinding: Binding<String> {
        Binding(
            get: {
                regulation.permitZones?.joined(separator: ", ") ?? regulation.permitZone ?? ""
            },
            set: { newValue in
                let zones = newValue.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
                regulation.permitZones = zones.isEmpty ? nil : zones
                regulation.permitZone = zones.first
            }
        )
    }

    private var timeLimitSection: some View {
        Section("Time Limit") {
            Stepper(value: timeLimitBinding, in: 0...480, step: 15) {
                if let limit = regulation.timeLimit {
                    Text("\(limit) minutes")
                } else {
                    Text("No limit")
                }
            }
        }
    }

    private var timeLimitBinding: Binding<Int> {
        Binding(
            get: { regulation.timeLimit ?? 0 },
            set: { regulation.timeLimit = $0 == 0 ? nil : $0 }
        )
    }

    private var meterRateSection: some View {
        Section("Meter Rate") {
            TextField("Rate ($/hr)", value: meterRateBinding, format: .number)
                .keyboardType(.decimalPad)
        }
    }

    private var meterRateBinding: Binding<Decimal> {
        Binding(
            get: { regulation.meterRate ?? 0 },
            set: { regulation.meterRate = $0 == 0 ? nil : $0 }
        )
    }

    private var specialConditionsSection: some View {
        Section("Special Conditions") {
            TextField("Optional notes", text: specialConditionsBinding)
        }
    }

    private var specialConditionsBinding: Binding<String> {
        Binding(
            get: { regulation.specialConditions ?? "" },
            set: { regulation.specialConditions = $0.isEmpty ? nil : $0 }
        )
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive, action: {
                onDelete()
                dismiss()
            }) {
                Label("Delete Regulation", systemImage: "trash")
            }
        }
    }
}

// MARK: - Multi-Day Picker

struct MultiDayPicker: View {
    @Binding var selectedDays: Set<String>

    private let allDays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(allDays, id: \.self) { day in
                Toggle(day.capitalized, isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { isOn in
                        if isOn {
                            selectedDays.insert(day)
                        } else {
                            selectedDays.remove(day)
                        }
                    }
                ))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BlockfaceEditorView()
}
