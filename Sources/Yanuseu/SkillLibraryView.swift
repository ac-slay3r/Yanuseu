import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @ObservedObject var store: SkillStore
    let profileID: String
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var inspectedSkill: LocalSkill?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Skills are instructions sent to your provider on future turns. They are not code, a sandbox, or permission to use tools. Inspect imports before enabling them for this profile.")
                        .font(.footnote)
                    if let error = store.storageError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                Section("Local library") {
                    ForEach(store.skills) { skill in
                        Button {
                            inspectedSkill = skill
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(skill.id).font(.headline)
                                    Spacer()
                                    Text(store.isEnabled(skill.id, profileID: profileID) ? "Enabled" : "Disabled")
                                        .font(.caption)
                                }
                                Text(skill.summary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.skills.isEmpty {
                        Text("No skills imported yet.").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Import SKILL.md from Files") { showImporter = true }
                        .disabled(store.storageError != nil)
                } footer: {
                    Text("Text-only imports; no linked files, scripts, dependency installs, network access, or shell execution. Maximum 16 KB, 20 skills.")
                }
            }
            .navigationTitle("Skills")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText]) { result in
                do {
                    let url = try result.get()
                    guard url.lastPathComponent.lowercased() == "skill.md" else { throw SkillError.invalidDocument }
                    let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw SkillError.invalidDocument }
                    guard size <= 16_384 else { throw SkillError.tooLarge }
                    inspectedSkill = try store.importSkill(data: Data(contentsOf: url))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .sheet(item: $inspectedSkill) { skill in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(skill.summary).font(.headline)
                            Text("Review the full text before enabling. Its instructions go directly to the selected model provider on future turns, but cannot grant tool permissions.")
                                .font(.footnote)
                            Text(skill.instructions)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            Toggle("Enable for this profile", isOn: Binding(
                                get: { store.isEnabled(skill.id, profileID: profileID) },
                                set: { value in
                                    do { try store.setEnabled(value, skillID: skill.id, profileID: profileID) }
                                    catch { errorMessage = error.localizedDescription }
                                }
                            ))
                            .disabled(store.storageError != nil)
                        }
                        .padding()
                    }
                    .navigationTitle(skill.id)
                    .toolbar { Button("Done") { inspectedSkill = nil } }
                }
            }
            .alert("Skill operation failed", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Nothing was changed.")
            }
        }
    }
}
