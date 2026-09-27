import SwiftUI

struct AppRootView: View {
    @StateObject private var profiles = ProfileStore()
    @State private var hasKey = false
    @State private var checked = false
    @State private var credentialError: String?
    @State private var profileRecoveryError: String?
    @State private var showProfileRecoveryConfirmation = false
    private let credentials = ProviderCredentialStore()

    var body: some View {
        Group {
            if let profileError = profiles.storageError {
                VStack(spacing: 16) {
                    ContentUnavailableView("Profiles need attention", systemImage: "person.crop.circle.badge.exclamationmark",
                                           description: Text(profileError))
                    Text("The saved profile index cannot be read. Resetting it will not delete Keychain keys or conversations, but you may need to configure your profiles again.")
                        .font(.footnote).padding(.horizontal)
                    Button("Archive unreadable profiles and reset", role: .destructive) {
                        showProfileRecoveryConfirmation = true
                    }
                    if let profileRecoveryError { Text(profileRecoveryError).foregroundStyle(.red) }
                }.padding()
            } else if let credentialError {
                VStack(spacing: 16) {
                    Text(credentialError)
                    Button("Retry Keychain Access") { refreshKey() }
                }.padding()
            } else if !checked {
                ProgressView("Checking iPhone Keychain…")
            } else if profiles.selected.isConfigured && hasKey {
                ChatView(profiles: profiles)
            } else {
                ProviderSetupView(profiles: profiles, onConfigured: refreshKey)
            }
        }
        .task {
            do { try credentials.migrateLegacyDefault() }
            catch { credentialError = error.localizedDescription; checked = true; return }
            refreshKey()
        }
        .onChange(of: profiles.selectedID) { _, _ in refreshKey() }
        .onChange(of: profiles.selected.isConfigured) { _, _ in refreshKey() }
        .confirmationDialog("Archive unreadable profiles and reset?", isPresented: $showProfileRecoveryConfirmation) {
            Button("Archive and Reset", role: .destructive) {
                do { _ = try profiles.archiveUnreadableProfilesAndReset(); refreshKey() }
                catch { profileRecoveryError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original profile bytes will be preserved in protected app storage. Existing provider keys and conversations are not deleted. This does not repair unreadable data.")
        }
    }

    private func refreshKey() {
        checked = true
        do {
            hasKey = try credentials.containsAPIKey(profileID: profiles.selectedID)
            credentialError = nil
        } catch {
            credentialError = error.localizedDescription
        }
    }
}

struct ChatView: View {
    @ObservedObject var profiles: ProfileStore
    @StateObject private var store: ConversationStore
    @StateObject private var skills = SkillStore()
    @StateObject private var memory = MemoryStore()
    init(profiles: ProfileStore) {
        self.profiles = profiles
        _store = StateObject(wrappedValue: ConversationStore(profileID: profiles.selectedID))
        _draft = State(initialValue: profiles.draft(for: profiles.selectedID))
    }
    @State private var draft: String
    @State private var streamingText = ""
    @State private var isSending = false
    @State private var showConversations = false
    @State private var showSettings = false
    @State private var showSkills = false
    @State private var showMemory = false
    @State private var showTools = false
    @State private var showCommands = false
    @State private var pendingPaletteCommand: AppCommand?
    @State private var showClearConfirmation = false
    @State private var showRecoveryConfirmation = false
    @State private var recoveryError: String?
    @State private var requestError: String?
    @State private var unsentDraftAfterSaveFailure = false
    @State private var requestTask: Task<Void, Never>?

    private let credentials = ProviderCredentialStore()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let persistenceError = store.persistenceError {
                            Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.horizontal)
                        }
                        ForEach(store.archivedHistoryURLs, id: \.self) { archive in
                            ShareLink(item: archive) {
                                Label("Export archive \(archive.lastPathComponent)", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                            .padding(.horizontal)
                        }
                        if store.needsRecovery {
                            ContentUnavailableView("History needs attention", systemImage: "externaldrive.badge.exclamationmark", description: Text("The saved history could not be read. It will not be overwritten or sent to your provider."))
                                .padding(.top, 40)
                            Button("Archive unreadable history and start fresh") { showRecoveryConfirmation = true }
                                .padding(.horizontal)
                        } else if store.activeConversation.messages.isEmpty && streamingText.isEmpty {
                            ContentUnavailableView("Start a conversation", systemImage: "bubble.left.and.bubble.right", description: Text("Messages go directly to your configured provider."))
                                .padding(.top, 80)
                        }
                        ForEach(store.activeConversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isSending {
                            if streamingText.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Yanuseu is responding…").foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)
                            } else {
                                MessageBubble(message: ChatMessage(role: .assistant, content: streamingText))
                                    .id("streaming")
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical)
                }
                .onChange(of: store.activeConversation.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: streamingText) { _, _ in scrollToBottom(proxy) }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("\(profiles.selected.name) · \(store.activeConversation.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showConversations = true } label: { Image(systemName: "list.bullet") }
                        .disabled(isSending || store.needsRecovery)
                        .accessibilityLabel("Conversations")
                    Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(isSending || store.needsRecovery)
                        .accessibilityLabel("New conversation")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showCommands = true } label: { Image(systemName: "command") }
                        .disabled(isSending || store.needsRecovery)
                        .accessibilityLabel("Commands")
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .disabled(isSending)
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView(store: store, knownProfileIDs: Set(profiles.profiles.map(\.id)))
            }
            .sheet(isPresented: $showSettings) {
                ProviderSetupView(profiles: profiles)
            }
            .sheet(isPresented: $showSkills) {
                SkillLibraryView(store: skills, profileID: profiles.selectedID)
            }
            .sheet(isPresented: $showMemory) {
                MemoryLibraryView(store: memory, profileID: profiles.selectedID)
            }
            .sheet(isPresented: $showTools) {
                ToolControlsView(profiles: profiles, profileID: profiles.selectedID)
            }
            .sheet(isPresented: $showCommands, onDismiss: {
                if let command = pendingPaletteCommand {
                    pendingPaletteCommand = nil
                    run(command)
                }
            }) {
                NavigationStack {
                    List(AppCommand.registry) { entry in
                        Button {
                            pendingPaletteCommand = entry.command
                            showCommands = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).font(.headline)
                                Text(entry.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Commands")
                    .toolbar { Button("Done") { showCommands = false } }
                }
            }
            .confirmationDialog("Archive unreadable local history?", isPresented: $showRecoveryConfirmation, titleVisibility: .visible) {
                Button("Archive and Start Fresh", role: .destructive) {
                    do { try store.archiveUnreadableHistoryAndReset() }
                    catch { recoveryError = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The original bytes will be kept in the app’s local storage. This starts a new empty history; it does not repair the archived file.")
            }
            .alert("History recovery failed", isPresented: Binding(
                get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } }
            )) {
                Button("OK") { recoveryError = nil }
            } message: {
                Text(recoveryError ?? "The original history has not been discarded.")
            }
            .confirmationDialog("Clear this conversation?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear This Conversation", role: .destructive) {
                    store.clearActiveConversation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes only the current conversation from this iPhone. Other conversations are unchanged.")
            }
            .alert("Couldn’t get a response", isPresented: Binding(
                get: { requestError != nil },
                set: { if !$0 { requestError = nil } }
            )) {
                Button("Retry") {
                    requestError = nil
                    if unsentDraftAfterSaveFailure {
                        send() // Save the unsent draft first; never dispatch a history that omitted it.
                    } else {
                        startRequest()
                    }
                }
                Button("Dismiss", role: .cancel) { requestError = nil }
            } message: {
                Text(requestError ?? "Check your provider configuration and connection.")
            }
        }
        .onChange(of: profiles.selectedID) { oldID, id in
            if !isSending {
                profiles.saveDraft(draft, for: oldID)
                draft = profiles.draft(for: id)
                unsentDraftAfterSaveFailure = false
                store.switchProfile(id)
            }
        }
        .onChange(of: draft) { _, newValue in profiles.saveDraft(newValue, for: profiles.selectedID) }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if !AppCommand.suggestions(for: draft).isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(AppCommand.suggestions(for: draft)) { entry in
                            Button("\(entry.name) · \(entry.summary)") { draft = entry.name }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .accessibilityLabel("Slash command suggestions")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Yanuseu or type /help", text: $draft, axis: .vertical)
                    .accessibilityHint("Type slash help to see native commands.")
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending || store.needsRecovery)
                    .accessibilityIdentifier("chatComposer")
                if isSending {
                    Button(action: stopRequest) {
                        Image(systemName: "stop.circle.fill").font(.system(size: 30))
                    }
                    .tint(.red)
                    .accessibilityLabel("Stop response")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    }
                    .disabled(store.needsRecovery || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                }
            }
            Text("Sent to your provider · history stays on this iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending, !store.needsRecovery else { return }
        if let command = AppCommand.parse(text) {
            draft = ""
            run(command)
            return
        }
        guard store.append(ChatMessage(role: .user, content: text)) else {
            unsentDraftAfterSaveFailure = true
            requestError = "Conversation history could not be saved. Your draft is still in the composer; no request was sent."
            return
        }
        unsentDraftAfterSaveFailure = false
        draft = ""
        startRequest()
    }

    private func run(_ command: AppCommand) {
        switch command {
        case .help:
            store.append(ChatMessage(role: .assistant, content: AppCommand.helpText))
        case .newConversation:
            store.newConversation()
            store.append(ChatMessage(role: .assistant, content: "Started a new conversation."))
        case .clearConversation:
            showClearConfirmation = true
        case .tools:
            showTools = true
        case .settings:
            showSettings = true
        case .skills:
            showSkills = true
        case .memory:
            showMemory = true
        case .unknown(let token):
            store.append(ChatMessage(role: .assistant, content: "Unknown command \(token). Use /help to see available native commands."))
        }
    }

    private func startRequest() {
        let profile = profiles.selected
        let apiKey: String
        do {
            guard let value = try credentials.loadAPIKey(profileID: profile.id) else {
                requestError = "Provider key is missing. Re-enter it in Provider Settings."
                return
            }
            apiKey = value
        } catch {
            requestError = error.localizedDescription
            return
        }
        guard store.persistenceError == nil else {
            requestError = "Conversation history could not be saved; no request was sent."
            return
        }
        let skillInstructions: [String]
        do { skillInstructions = try skills.instructions(for: profile.id) }
        catch { requestError = error.localizedDescription; return }
        let memoryNotes: [String]
        do { memoryNotes = try memory.context(for: profile.id) }
        catch { requestError = error.localizedDescription; return }
        let conversationID = store.activeID
        let history = store.activeConversation.messages
        let configuration = AgentTurnConfiguration(model: profile.model, baseURL: profile.baseURL, apiKey: apiKey,
                                                    calculatorEnabled: profile.calculatorEnabled, instructions: profile.instructions,
                                                    skillInstructions: skillInstructions, memoryNotes: memoryNotes)
        isSending = true
        streamingText = ""
        requestTask = Task { @MainActor in
            defer { isSending = false; requestTask = nil; streamingText = "" }
            do {
                try await AgentRuntime().run(messages: history, configuration: configuration) { event in
                    guard store.activeID == conversationID && store.selectedProfileID == profile.id else {
                        throw AgentRuntimeError.persistenceFailed
                    }
                    switch event {
                    case .text(let text): streamingText = text
                    case .message(let message):
                        store.append(message)
                        if store.persistenceError != nil { throw AgentRuntimeError.persistenceFailed }
                        streamingText = ""
                    case .cancelled(let partial):
                        if !partial.isEmpty { store.append(ChatMessage(role: .assistant, content: partial)) }
                    }
                }
            } catch {
                requestError = error.localizedDescription
            }
        }
    }

    private func stopRequest() {
        requestTask?.cancel()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 32)
            } else if message.role == .assistant {
                Image(systemName: "sparkles").foregroundStyle(.tint).padding(.top, 3)
            } else {
                Image(systemName: "function").foregroundStyle(.orange).padding(.top, 3)
            }
            Text(displayText)
                .textSelection(.enabled)
                .padding(12)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
            if message.role != .user { Spacer(minLength: 32) }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var displayText: String {
        if message.role == .tool {
            return "\(message.toolName ?? "Tool") result: \(message.content)"
        }
        if message.role == .assistant, message.content.isEmpty, let calls = message.toolCalls, !calls.isEmpty {
            return "Calling \(calls.map(\.function.name).joined(separator: ", "))…"
        }
        return message.content
    }

    private var background: Color {
        switch message.role {
        case .user: return Color.accentColor.opacity(0.15)
        case .assistant: return Color.secondary.opacity(0.10)
        case .tool: return Color.orange.opacity(0.12)
        }
    }
}

private struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ConversationStore
    let knownProfileIDs: Set<String>
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var deleteTarget: Conversation?
    @State private var confirmClearAll = false
    @State private var searchText = ""
    @State private var showingArchived = false
    @State private var showingOrphans = false
    @State private var orphanToRecover: Conversation?
    @State private var orphanRecoveryError: String?

    private var sessions: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if showingOrphans {
            let orphans = store.orphanedConversations(knownProfileIDs: knownProfileIDs)
            return query.isEmpty ? orphans : orphans.filter { $0.title.localizedStandardContains(query) }
        }
        if !showingArchived { return store.search(query) }
        guard !query.isEmpty else { return store.archivedConversations }
        return store.archivedConversations.filter { session in
            session.title.localizedStandardContains(query) ||
            session.messages.contains { $0.content.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if showingOrphans {
                    Section {
                        Text("These sessions belonged to a profile no longer in the profile list. Moving one into your active profile makes its history available to future provider requests. Review before recovering.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(sessions) { conversation in
                    Button {
                        if showingOrphans { orphanToRecover = conversation }
                        else { store.select(conversation.id); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title).font(.headline).lineLimit(1)
                            Text(conversation.messages.last?.content ?? "No messages yet")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        ShareLink(item: ConversationExporter.text(for: conversation), subject: Text(conversation.title)) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        ShareLink(item: ConversationExporter.text(for: conversation), subject: Text(conversation.title)) {
                            Label("Export Conversation", systemImage: "square.and.arrow.up")
                        }
                        if !showingOrphans {
                            Button("Rename", systemImage: "pencil") { renameTarget = conversation; renameText = conversation.title }
                            if conversation.isArchived {
                                Button("Unarchive", systemImage: "archivebox.fill") { store.unarchive(conversation.id) }
                            } else {
                                Button("Archive", systemImage: "archivebox") { store.archive(conversation.id) }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = conversation }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions and messages")
            .overlay {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sessions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle(showingOrphans ? "Recover Sessions" : showingArchived ? "Archived Sessions" : "Conversations")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(showingArchived ? "Show Conversations" : "Show Archived Sessions", systemImage: "archivebox") {
                            showingArchived.toggle()
                            showingOrphans = false
                        }
                        if !store.orphanedConversations(knownProfileIDs: knownProfileIDs).isEmpty {
                            Button(showingOrphans ? "Show Conversations" : "Recover Missing-Profile Sessions", systemImage: "person.crop.circle.badge.questionmark") {
                                showingOrphans.toggle()
                                showingArchived = false
                            }
                        }
                        Button("Clear All Conversation History", systemImage: "trash", role: .destructive) {
                            confirmClearAll = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename conversation", isPresented: Binding(
                get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Save") { if let target = renameTarget { store.rename(target.id, to: renameText) }; renameTarget = nil }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog("Delete this conversation and its messages from this iPhone?", isPresented: Binding(
                get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Conversation", role: .destructive) { if let target = deleteTarget { store.delete(target.id) }; deleteTarget = nil }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            }
            .confirmationDialog("Remove all saved conversation history?", isPresented: $confirmClearAll, titleVisibility: .visible) {
                Button("Clear All History", role: .destructive) { store.deleteAll() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This clears transcripts from this iPhone. Requests already sent to your provider cannot be recalled.")
            }
            .confirmationDialog("Move this session into the active profile?", isPresented: Binding(
                get: { orphanToRecover != nil }, set: { if !$0 { orphanToRecover = nil } }
            ), titleVisibility: .visible) {
                Button("Move Session") {
                    if let orphan = orphanToRecover,
                       !store.recoverOrphanedConversation(orphan.id, knownProfileIDs: knownProfileIDs) {
                        orphanRecoveryError = store.persistenceError ?? "The session was not moved."
                    }
                    orphanToRecover = nil
                }
                Button("Cancel", role: .cancel) { orphanToRecover = nil }
            } message: {
                Text("The old profile is missing. Its messages will be available to the selected profile and may be sent to that profile’s provider on future turns. The original archive is not changed.")
            }
            .alert("Session recovery failed", isPresented: Binding(
                get: { orphanRecoveryError != nil }, set: { if !$0 { orphanRecoveryError = nil } }
            )) {
                Button("OK") { orphanRecoveryError = nil }
            } message: { Text(orphanRecoveryError ?? "No session was moved.") }
        }
    }
}
