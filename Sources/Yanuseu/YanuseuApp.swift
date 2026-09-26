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
    @ObservedObject var profiles: ProfileStore
    var onConfigured: (() -> Void)? = nil
    @State private var baseURL: String
    @State private var model: String
    @State private var calculatorEnabled: Bool
    @State private var agentInstructions: String
    @State private var newProfileName = ""
    @State private var pendingProfileID: String?
    @State private var showUnsavedControlsConfirmation = false
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

    init(profiles: ProfileStore, onConfigured: (() -> Void)? = nil) {
        self.profiles = profiles
        self.onConfigured = onConfigured
        _baseURL = State(initialValue: profiles.selected.baseURL)
        _model = State(initialValue: profiles.selected.model)
        _agentInstructions = State(initialValue: profiles.selected.instructions)
        _calculatorEnabled = State(initialValue: profiles.selected.calculatorEnabled)
    }

    private var hasUnsavedProviderFields: Bool {
        baseURL != profiles.selected.baseURL || model != profiles.selected.model || !apiKey.isEmpty
    }

    private var hasUnsavedControls: Bool {
        agentInstructions != profiles.selected.instructions || calculatorEnabled != profiles.selected.calculatorEnabled
    }

    private var hasUnsavedChanges: Bool { hasUnsavedProviderFields || hasUnsavedControls }

    private func selectProfile(_ id: String) {
        guard id != profiles.selectedID else { return }
        if hasUnsavedChanges {
            pendingProfileID = id
            showUnsavedControlsConfirmation = true
        } else {
            profiles.select(id)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Local agent profile") {
                    Picker("Active profile", selection: Binding(get: { profiles.selectedID }, set: selectProfile)) {
                        ForEach(profiles.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .disabled(isChecking || isLoadingModels)
                    TextField("New profile name", text: $newProfileName)
                        .disabled(isChecking || isLoadingModels)
                    Button("Create and select profile") {
                        profiles.create(name: newProfileName)
                        newProfileName = ""
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChecking || isLoadingModels || hasUnsavedChanges)
                    if hasUnsavedChanges {
                        Text("Save or discard changes before creating a profile.").font(.caption).foregroundStyle(.secondary)
                    }
                    if hasUnsavedChanges {
                        Button("Discard edits for this profile", role: .destructive) { hydrateSelectedProfile() }
                    }
                    Text("Profiles keep separate provider settings, Keychain keys, instructions, and conversations. Only OpenAI-compatible HTTPS providers are supported here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    SecureField(((try? credentials.containsAPIKey(profileID: profiles.selectedID)) ?? false) ? "Enter API key to replace saved key" : "API key", text: $apiKey)
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
                    Button("Save agent controls") {
                        profiles.updateSettings(profileID: profiles.selectedID, instructions: agentInstructions,
                                                calculatorEnabled: calculatorEnabled)
                        didSucceed = true
                        statusMessage = "Agent controls saved for \(profiles.selected.name)."
                    }
                    Text("When enabled, Yanuseu may ask its local calculator to evaluate basic arithmetic. It cannot access files, the network, or other apps. This is off by default.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if profiles.selected.isConfigured {
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
            .confirmationDialog("Switch profiles with unsaved edits?", isPresented: $showUnsavedControlsConfirmation, titleVisibility: .visible) {
                if !hasUnsavedProviderFields && hasUnsavedControls {
                    Button("Save controls and switch") {
                        guard let id = pendingProfileID else { return }
                        profiles.updateSettings(profileID: profiles.selectedID, instructions: agentInstructions,
                                                calculatorEnabled: calculatorEnabled)
                        profiles.select(id)
                        pendingProfileID = nil
                    }
                }
                Button("Discard changes and switch", role: .destructive) {
                    guard let id = pendingProfileID else { return }
                    profiles.select(id)
                    pendingProfileID = nil
                }
                Button("Keep editing", role: .cancel) { pendingProfileID = nil }
            }
            .confirmationDialog("Remove the saved provider key?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
                Button("Remove Key", role: .destructive, action: removeSavedProvider)
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle(profiles.selected.isConfigured ? "Settings" : "Set up Yanuseu")
            .toolbar {
                if profiles.selected.isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onChange(of: profiles.selectedID) { _, _ in hydrateSelectedProfile() }
        }
    }

    @MainActor
    private func loadAvailableModels() async {
        guard !isLoadingModels && !isChecking else { return }
        let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if enteredKey.isEmpty {
            do {
                guard let savedKey = try credentials.loadAPIKey(profileID: profiles.selectedID) else {
                    modelsLoadedSuccessfully = false
                    modelsStatus = "Enter an API key, or save one first, to load model IDs."
                    return
                }
                key = savedKey
            } catch {
                modelsStatus = error.localizedDescription
                return
            }
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

    private func hydrateSelectedProfile() {
        let profile = profiles.selected
        baseURL = profile.baseURL
        model = profile.model
        agentInstructions = profile.instructions
        calculatorEnabled = profile.calculatorEnabled
        apiKey = ""
        statusMessage = nil
        resetLoadedModels()
    }

    private func removeSavedProvider() {
        do {
            try credentials.deleteAPIKey(profileID: profiles.selectedID)
            profiles.resetProvider(profileID: profiles.selectedID)
            statusMessage = nil
            onConfigured?()
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
        let profileID = profiles.selectedID
        do {
            let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String
            if enteredKey.isEmpty {
                guard let saved = try credentials.loadAPIKey(profileID: profileID) else {
                    statusMessage = "Enter an API key for this profile."
                    return
                }
                key = saved
            } else { key = enteredKey }
            try await ProviderConfiguration.verifyConnection(baseURL: baseURL, model: model, apiKey: key)
            guard profiles.selectedID == profileID else { return }
            try credentials.save(apiKey: key, profileID: profileID)
            baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            profiles.configure(profileID: profileID, baseURL: baseURL, model: model,
                               instructions: agentInstructions, calculatorEnabled: calculatorEnabled)
            apiKey = ""
            didSucceed = true
            statusMessage = "Connection verified for \(profiles.selected.name)."
            onConfigured?()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
