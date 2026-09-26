# Janus

Janus is a standalone iPhone AI-agent app: the agent loop runs in the app, talks directly to a model provider, and may optionally use on-device inference. It is designed not to require a VPS or companion computer.

## Current status

Early development scaffold. The current screen is a UI placeholder; model-provider connectivity, secure credential storage, tool execution, and local inference are not implemented yet. Janus is foreground-first: iOS may suspend the app when backgrounded, so this project does not promise continuous background agent execution.

## Development

Requirements: macOS with Xcode 16 or newer and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Janus.xcodeproj
```

Select an iPhone simulator and build/run from Xcode. GitHub Actions builds and tests the simulator target on macOS for pushes and pull requests.

## TestFlight

TestFlight distribution is not configured yet. Before signed builds: confirm the Apple Developer Team, register the explicit bundle identifier `cool.n0thing.janus` (or choose another available ID), create the App Store Connect app record, and configure signing/API credentials as GitHub Actions secrets. Do not commit credentials, certificates, or provisioning profiles.

## Security / product boundaries

- Provider credentials must be stored in iOS Keychain, never source control or plain preferences.
- Agent tools must be purpose-built and permission-bounded for iOS; this is not an unrestricted desktop shell.
- Any local-model support must document supported model formats, device requirements, and resource limits.
