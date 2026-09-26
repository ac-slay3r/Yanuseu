import SwiftUI

@main
struct YanuseuApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct ProviderSetupView: View {
    @Environment(\.dismiss) private var dismiss
    var onConfigured: (() -> Void)? = nil
    @State private var baseURL = UserDefaults.standard.string(forKey: "provider.baseURL") ?? "https://api.openai.com/v1"
    @State private var model = UserDefaults.standard.string(forKey: "provider.model") ?? ""
    @AppStorage("provider.isConfigured") private var isConfigured = false
    @AppStorage("agent.calculator.enabled") private var calculatorEnabled = false
    @State private var apiKey = ""
    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var didSucceed = false
    @State private var showRemoveConfirmation = false

    private let credentials = ProviderCredentialStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect a model provider to get Yanuseu ready. The first setup check sends your API key to the endpoint you enter and requests the available-models list; it does not send a chat message.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Before you begin")
                }

                Section("OpenAI-compatible provider") {
                    TextField("API base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("providerBaseURL")
                    TextField("Model ID from your provider", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("providerModel")
                    SecureField(credentials.containsAPIKey() ? "Enter API key to replace saved key" : "API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("providerAPIKey")
                    Text("The API key is stored in iPhone Keychain, not in app preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await verifyAndSave() }
                    } label: {
                        HStack {
                            Spacer()
                            if isChecking { ProgressView().padding(.trailing, 8) }
                            Text(isChecking ? "Checking connection…" : "Test connection and save")
                            Spacer()
                        }
                    }
                    .disabled(isChecking)
                    .accessibilityIdentifier("testAndSaveProvider")
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(didSucceed ? .green : .red)
                            .accessibilityIdentifier("providerStatus")
                    }
                } footer: {
                    Text("Yanuseu sends chat messages to this provider. Conversation history stays on this iPhone unless you remove it.")
                    Text("Provider requests go directly to the HTTPS endpoint you enter; its operator controls any retention. Yanuseu does not add a relay or cloud history service. Review your provider’s policy before sending sensitive content.")
                }

                Section("Agent controls") {
                    Toggle("Calculator tool", isOn: $calculatorEnabled)
                    Text("When enabled, Yanuseu may ask its local calculator to evaluate basic arithmetic. It cannot access files, the network, or other apps. This is off by default.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isConfigured {
                    Section {
                        Label("Provider connection verified", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Model", value: model)
                        Button("Remove saved provider key", role: .destructive) {
                            showRemoveConfirmation = true
                        }
                    } header: {
                        Text("Saved setup")
                    } footer: {
                        Text("Removing the key also resets provider setup on this iPhone.")
                    }
                }
            }
            .confirmationDialog("Remove the saved provider key?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
                Button("Remove Key", role: .destructive, action: removeSavedProvider)
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle(isConfigured ? "Settings" : "Set up Yanuseu")
            .toolbar {
                if isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func removeSavedProvider() {
        do {
            try credentials.deleteAPIKey()
            UserDefaults.standard.removeObject(forKey: "provider.baseURL")
            UserDefaults.standard.removeObject(forKey: "provider.model")
            isConfigured = false
            statusMessage = nil
            dismiss()
        } catch {
            statusMessage = error.localizedDescription
            didSucceed = false
        }
    }

    @MainActor
    private func verifyAndSave() async {
        isChecking = true
        statusMessage = nil
        didSucceed = false
        defer { isChecking = false }

        do {
            try await ProviderConfiguration.verifyConnection(baseURL: baseURL, model: model, apiKey: apiKey)
            try credentials.save(apiKey: apiKey)
            baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(baseURL, forKey: "provider.baseURL")
            UserDefaults.standard.set(model, forKey: "provider.model")
            apiKey = ""
            isConfigured = true
            didSucceed = true
            statusMessage = "Connection verified. Provider settings saved securely."
            onConfigured?()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
