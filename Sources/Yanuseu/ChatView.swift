import SwiftUI

struct AppRootView: View {
    @AppStorage("provider.isConfigured") private var isConfigured = false
    private let credentials = ProviderCredentialStore()

    var body: some View {
        if isConfigured && credentials.containsAPIKey() {
            ChatView()
        } else {
            ProviderSetupView()
        }
    }
}

struct ChatView: View {
    @AppStorage("provider.baseURL") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("provider.model") private var model = "gpt-4o-mini"
    @StateObject private var store = ConversationStore()
    @State private var draft = ""
    @State private var streamingText = ""
    @State private var isSending = false
    @State private var showConversations = false
    @State private var showSettings = false
    @State private var requestError: String?
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
                        if store.activeConversation.messages.isEmpty && streamingText.isEmpty {
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
            .navigationTitle(store.activeConversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showConversations = true } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Conversations")
                    Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(isSending)
                        .accessibilityLabel("New conversation")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Provider settings")
                }
            }
            .sheet(isPresented: $showConversations) {
                ConversationListView(store: store)
            }
            .sheet(isPresented: $showSettings) {
                ProviderSetupView()
            }
            .alert("Couldn’t get a response", isPresented: Binding(
                get: { requestError != nil },
                set: { if !$0 { requestError = nil } }
            )) {
                Button("Retry") { requestError = nil; startRequest() }
                Button("Dismiss", role: .cancel) { requestError = nil }
            } message: {
                Text(requestError ?? "Check your provider configuration and connection.")
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Yanuseu", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSending)
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
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        guard !text.isEmpty, !isSending else { return }
        store.append(ChatMessage(role: .user, content: text))
        draft = ""
        startRequest()
    }

    private func startRequest() {
        guard let apiKey = credentials.loadAPIKey() else {
            requestError = "Provider key is missing. Re-enter it in Provider Settings."
            return
        }
        isSending = true
        streamingText = ""
        let messages = store.activeConversation.messages
        requestTask = Task { @MainActor in
            defer { isSending = false; requestTask = nil }
            do {
                for try await delta in ChatService.stream(messages: messages, model: model, baseURL: baseURL, apiKey: apiKey) {
                    streamingText += delta
                }
                if !streamingText.isEmpty {
                    store.append(ChatMessage(role: .assistant, content: streamingText))
                } else {
                    requestError = "The provider completed the request without returning a text response."
                }
            } catch is CancellationError {
                if !streamingText.isEmpty {
                    store.append(ChatMessage(role: .assistant, content: streamingText))
                }
            } catch {
                requestError = error.localizedDescription
            }
            streamingText = ""
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
            if message.role == .assistant {
                Image(systemName: "sparkles").foregroundStyle(.tint).padding(.top, 3)
            } else {
                Spacer(minLength: 32)
            }
            Text(message.content)
                .textSelection(.enabled)
                .padding(12)
                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            if message.role == .assistant { Spacer(minLength: 32) }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct ConversationListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ConversationStore
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var deleteTarget: Conversation?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.conversations) { conversation in
                    Button {
                        store.select(conversation.id)
                        dismiss()
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
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { renameTarget = conversation; renameText = conversation.title }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = conversation }
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
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
        }
    }
}
