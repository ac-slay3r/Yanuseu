# Yanuseu

Yanuseu is a standalone iPhone AI-agent app: the agent loop runs in the app, talks directly to a model provider, and may optionally use on-device inference. It is designed not to require a VPS or companion computer.

## Current status

Early development. The current source includes provider setup and an HTTPS connection check; provider-backed streaming chat with stop/retry; on-device conversation history with deletion controls; and a calculator-only agent tool loop with bounded arithmetic parsing. The tool loop has no shell, filesystem, or network actions. GitHub Actions runs tests on an iOS Simulator; a green simulator run does not verify a live provider or physical-device behavior. The app is foreground-first: iOS may suspend it when backgrounded.

## Development

Requirements: macOS with Xcode 16 or newer and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Yanuseu.xcodeproj
```

Select an iPhone simulator and build/run from Xcode. GitHub Actions builds the simulator target on pushes and pull requests.

## TestFlight

TestFlight readiness is still pending verification: confirm the matching App Store Connect app record, distribution signing and provisioning, a signed device archive upload, export-compliance information, and app privacy details. Keep distribution credentials in protected CI secrets. Provider API keys are supplied by each user and belong only in iOS Keychain; never put them in repository or CI configuration.

## Security boundaries

- Provider credentials belong in iOS Keychain, never source control, plain preferences, or CI secrets.
- Agent tools must be purpose-built and permission-bounded for iOS; this is not an unrestricted desktop shell.
- Conversation history is stored on device with iOS file protection and excluded from device backups; deleting history cannot recall prompts already sent to a provider.
- Local-model support will document supported formats, device requirements, and resource limits.
