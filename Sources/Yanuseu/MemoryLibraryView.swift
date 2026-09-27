import SwiftUI

struct MemoryLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MemoryStore
    let profileID: String
    @State private var draft = ""
    @State private var editText = ""
    @State private var editing: LocalMemoryNote?
    @State private var pendingDelete: LocalMemoryNote?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Notes you enter are stored on this iPhone for this profile. They are sent to your selected provider with future requests, including resumed sessions. Editing or deleting cannot retract prior requests or change a running turn or transcript. The agent does not save memories automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let storageError = store.storageError {
                    Section {
                        Label(storageError, systemImage: "exclamationmark.triangle.fill")
                        Button("Retry reading local memory") {
                            do { try store.reload() } catch { error = error.localizedDescription }
                        }
                    }
                } else {
                    Section("Add a memory note") {
                        TextField("What should Yanuseu remember?", text: $draft, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("memoryDraft")
                        Button("Save Note") {
                            do { try store.add(draft, profileID: profileID); draft = "" }
                            catch { error = error.localizedDescription }
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section("Saved for this profile") {
                        ForEach(store.notes(for: profileID)) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.text).textSelection(.enabled)
                                Text("Added by you · \(note.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Edit") { editText = note.text; editing = note }
                                    Spacer()
                                    Button("Delete", role: .destructive) { pendingDelete = note }
                                }
                            }
                        }
                        if store.notes(for: profileID).isEmpty {
                            Text("No local memory notes yet.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Local Memory")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Edit memory note", isPresented: Binding(
                get: { editing != nil }, set: { if !$0 { editing = nil } }
            )) {
                TextField("Memory", text: $editText)
                Button("Save") {
                    if let note = editing {
                        do { try store.edit(note.id, text: editText, profileID: profileID); editText = "" }
                        catch { error = error.localizedDescription }
                    }
                    editing = nil
                }
                Button("Cancel", role: .cancel) { editing = nil; editText = "" }
            } message: {
                Text("The correction applies to future requests, not the current turn or requests already sent.")
            }
            .confirmationDialog("Delete this local memory note?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) {
                    if let note = pendingDelete {
                        do { try store.delete(note.id, profileID: profileID) }
                        catch { error = error.localizedDescription }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This stops sending the note in future requests. Previously sent copies cannot be recalled.")
            }
            .alert("Memory could not be saved", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "Try again.") }
        }
    }
}
