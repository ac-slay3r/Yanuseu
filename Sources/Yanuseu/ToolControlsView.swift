import SwiftUI

struct ToolControlsView: View {
    @ObservedObject var profiles: ProfileStore
    let profileID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Only the tools shown here can run on this iPhone. Changes apply to future turns. No shell, files, network actions, or background tools are available.")
                        .font(.footnote)
                }
                Section("This profile") {
                    ForEach(ToolRegistry.descriptors) { tool in
                        Toggle(isOn: binding(for: tool.capability)) {
                            VStack(alignment: .leading) {
                                Text(tool.title)
                                Text(tool.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Local Tools")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func binding(for capability: ToolCapability) -> Binding<Bool> {
        Binding(get: {
            guard let profile = profiles.profiles.first(where: { $0.id == profileID }) else { return false }
            return ToolPolicy(calculatorEnabled: profile.calculatorEnabled).allows(capability)
        }, set: { allowed in
            guard let profile = profiles.profiles.first(where: { $0.id == profileID }) else { return }
            switch capability {
            case .calculator:
                profiles.updateSettings(profileID: profileID, instructions: profile.instructions, calculatorEnabled: allowed)
            }
        })
    }
}
