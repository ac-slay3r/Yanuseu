import SwiftUI

@main
struct JanusApp: App {
    var body: some Scene {
        WindowGroup {
            ConversationView()
        }
    }
}

private struct ConversationView: View {
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Janus")
                    .font(.largeTitle.bold())
                Text("Your personal AI, running from your iPhone.")
                    .foregroundStyle(.secondary)
                Text("Connect a model provider in Settings to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack {
                    TextField("Message Janus", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button(action: {}) {
                        Image(systemName: "arrow.up.circle.fill")
                    }
                    .disabled(true)
                }
            }
            .padding()
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
        }
    }
}
