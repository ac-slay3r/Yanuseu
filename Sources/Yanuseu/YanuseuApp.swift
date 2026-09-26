import SwiftUI

@main
struct YanuseuApp: App {
    var body: some Scene {
        WindowGroup {
            ProviderSetupView()
        }
    }
}

private struct ProviderSetupView: View {
    @State private var baseURL = UserDefaults.standard.string(forKey: "provider.baseURL") ?? "https://api.openai.com/v1"
    @State private var model = UserDefaults.standard.string(forKey: "provider.model") ?? "gpt-4o-mini"
    @AppStorage("provider.isConfigured") private var isConfigured = false
    @State private var apiKey = ""
    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var didSucceed = false

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
                    TextField("Model ID", text: $model)
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
                    Text("Yanuseu currently supports OpenAI-compatible chat-completions providers. The agent chat experience is the next build step.")
                }

                if isConfigured {
                    Section("Saved setup") {
                        Label("Provider connection verified", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Model", value: model)
                    }
                }
            }
            .navigationTitle("Set up Yanuseu")
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
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
