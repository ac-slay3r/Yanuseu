# Yanuseu

Yanuseu is a standalone iPhone AI-agent app: the agent loop runs in the app, talks directly to a model provider, and may optionally use on-device inference. It is designed not to require a VPS or companion computer.

## Current status

Early development. Implemented: provider setup and HTTPS connection check, streaming chat, stop/retry, and on-device conversation history. Safe agent tools and TestFlight distribution are still pending; simulator CI compiles the app and test bundles, but does not yet execute XCTest or replace on-device QA. The app is foreground-first: iOS may suspend it when backgrounded.

## Development

Requirements: macOS with Xcode 16 or newer and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Yanuseu.xcodeproj
```

Select an iPhone simulator and build/run from Xcode. GitHub Actions builds the simulator target on pushes and pull requests.

## TestFlight

TestFlight distribution is not configured yet. The registered Bundle ID for the app target is `cool.n0thing.yanuseu`. Create a matching App Store Connect app record and configure signing/API credentials as GitHub Actions secrets. Do not commit credentials, certificates, or provisioning profiles.

## Security boundaries

- Provider credentials belong in iOS Keychain, never source control or plain preferences.
- Agent tools must be purpose-built and permission-bounded for iOS; this is not an unrestricted desktop shell.
- Local-model support will document supported formats, device requirements, and resource limits.
