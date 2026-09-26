import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @ObservedObject var store: SkillStore
    let profileID: String
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var deleteTarget: LocalSkill?
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
                        Button("Retry local library access") {
                            do { try store.reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
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
                        .disabled(store.storageError != nil || isImporting)
                    if isImporting { ProgressView("Reading selected file…") }
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
                    isImporting = true
                    Task { @MainActor in
                        defer { isImporting = false }
                        do {
                            let data = try await Task.detached(priority: .userInitiated) { try SkillFileReader.read(url) }.value
                            inspectedSkill = try store.importSkill(data: data)
                        } catch { errorMessage = error.localizedDescription }
                    }
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
                            Button("Delete this skill from iPhone", role: .destructive) { deleteTarget = skill }
                                .disabled(store.storageError != nil)
                        }
                        .padding()
                    }
                    .navigationTitle(skill.id)
                    .toolbar { Button("Done") { inspectedSkill = nil } }
                    .confirmationDialog("Delete \(skill.id) from the local library?", isPresented: Binding(
                        get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
                    ), titleVisibility: .visible) {
                        Button("Delete Skill", role: .destructive) {
                            do { try store.delete(skillID: skill.id); inspectedSkill = nil }
                            catch { errorMessage = error.localizedDescription }
                            deleteTarget = nil
                        }
                        Button("Cancel", role: .cancel) { deleteTarget = nil }
                    } message: {
                        Text("This removes the local instructions and disables them for every profile. Previous provider requests cannot be recalled.")
                    }
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
