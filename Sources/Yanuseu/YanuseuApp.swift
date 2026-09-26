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
    @AppStorage("agent.instructions") private var agentInstructions = ""
    @State private var apiKey = ""
    @State private var isChecking = false
    @State private var isLoadingModels = false
    @State private var availableModels: [String] = []
    @State private var modelsStatus: String?
    @State private var modelsLoadedSuccessfully = false
    @State private var statusMessage: String?
    @State private var didSucceed = false
    @State private var showRemoveConfirmation = false

    private let credentials = ProviderCredentialStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect a model provider to get Yanuseu ready. Testing the connection sends your API key to the endpoint you enter; it does not send a chat message.")
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
                        .disabled(isLoadingModels || isChecking)
                        .accessibilityIdentifier("providerBaseURL")
                        .onChange(of: baseURL) { _, _ in resetLoadedModels() }
                    TextField("Model ID from your provider", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isLoadingModels || isChecking)
                        .accessibilityIdentifier("providerModel")
                    Button {
                        Task { await loadAvailableModels() }
                    } label: {
                        Label(isLoadingModels ? "Loading models…" : "Load available models", systemImage: "arrow.down.circle")
                    }
                    .disabled(isLoadingModels || isChecking)
                    .accessibilityIdentifier("loadProviderModels")
                    .accessibilityLabel("Load available model IDs")
                    if !availableModels.isEmpty {
                        Menu("Choose from loaded models") {
                            ForEach(availableModels, id: \.self) { modelID in
                                Button(modelID) { model = modelID }
                            }
                        }
                    }
                    if let modelsStatus {
                        Text(modelsStatus)
                            .font(.footnote)
                            .foregroundStyle(modelsLoadedSuccessfully ? Color.secondary : Color.red)
                    }
                    Text("Loading the list sends your API key to this provider endpoint. Model IDs remain editable if your provider does not list them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(credentials.containsAPIKey() ? "Enter API key to replace saved key" : "API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isLoadingModels || isChecking)
                        .accessibilityIdentifier("providerAPIKey")
                        .onChange(of: apiKey) { _, _ in resetLoadedModels() }
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
                    .disabled(isChecking || isLoadingModels)
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

                Section("Agent instructions") {
                    TextEditor(text: $agentInstructions)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Agent instructions")
                        .onChange(of: agentInstructions) { _, newValue in
                            if newValue.count > 4_000 {
                                agentInstructions = String(newValue.prefix(4_000))
                            }
                        }
                    HStack {
                        Text("These instructions are sent to the configured provider with each chat request.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("\(agentInstructions.count)/4000")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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

    @MainActor
    private func loadAvailableModels() async {
        guard !isLoadingModels && !isChecking else { return }
        let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if enteredKey.isEmpty {
            guard let savedKey = credentials.loadAPIKey() else {
                modelsLoadedSuccessfully = false
                modelsStatus = "Enter an API key, or save one first, to load model IDs."
                return
            }
            key = savedKey
        } else {
            key = enteredKey
        }
        isLoadingModels = true
        modelsStatus = nil
        modelsLoadedSuccessfully = false
        defer { isLoadingModels = false }
        do {
            availableModels = try await ProviderConfiguration.fetchModelIDs(baseURL: baseURL, apiKey: key)
            modelsLoadedSuccessfully = true
            modelsStatus = availableModels.isEmpty
                ? "No model IDs were listed. You can still enter one manually."
                : "Loaded \(availableModels.count) model IDs. Choose one or enter an ID manually."
        } catch {
            availableModels = []
            modelsStatus = error.localizedDescription
        }
    }

    private func resetLoadedModels() {
        availableModels = []
        modelsStatus = nil
        modelsLoadedSuccessfully = false
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
