# Yanuseu

Yanuseu is a standalone iPhone AI-agent app: the agent loop runs in the app, talks directly to a model provider, and may optionally use on-device inference. It is designed not to require a VPS or companion computer.

## Current status

Early development. The current source includes local agent profiles with separate provider/model, instructions, calculator settings, Keychain credentials, and scoped conversations (legacy history migrates into Default); provider setup, HTTPS connection checks, and native model-list discovery/selection from an OpenAI-compatible endpoint; provider-backed streaming chat with stop/retry; on-device conversation history with profile-scoped search by session title/message and tap-to-resume, rename, archive/unarchive, deletion, and user-initiated text export. Unreadable history is never silently overwritten: explicit recovery preserves original bytes in an exportable archive, including across an interrupted recovery. Native slash commands (`/help`, `/new`, `/clear`, `/tools`, `/settings`, `/skills`, `/memory`) have live suggestions and a command palette. The text-only, user-reviewed local SKILL.md library has per-profile enablement for future turns. Local memory notes are entered, inspected, corrected, and deleted on-device in `/memory`; they are profile-scoped, labeled as user-entered, and sent to the configured provider only on future requests. Corrections do not retract previous requests, alter an active turn, or rewrite transcripts; there is no automatic memory extraction. Provider-sent instructions are editable in Settings (capped at 4,000 characters). The calculator-only tool loop is off by default and controlled through a local Tools screen; typed permissions filter advertised tools and are enforced again at runtime and executor. Agent controls have an explicit Save action; unsaved edits require a choice before switching profiles, and unfinished chat drafts remain isolated in memory while the app is open. The tool loop has no shell, filesystem, or network actions. GitHub Actions runs tests on an iOS Simulator; a green simulator run does not verify a live provider or physical-device behavior. The app is foreground-first: iOS may suspend it when backgrounded.

## Development

Requirements: macOS with Xcode 16 or newer and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Yanuseu.xcodeproj
```

Select an iPhone simulator and build/run from Xcode. GitHub Actions builds the simulator target on pushes and pull requests.

## TestFlight and beta testing

The [manual TestFlight workflow](.github/workflows/testflight.yml) signs and uploads only an exact green `main` SHA after its Apple credentials are configured. **No signed archive, TestFlight upload, ASC processing, or physical-device turn has been verified yet.** See [release setup](docs/TESTFLIGHT_RELEASE.md), [device acceptance](docs/BETA_TESTING.md), and the [capability map](docs/HERMES_IOS_CAPABILITY_MAP.md). Provider API keys are supplied by each user and belong only in iOS Keychain; never put them in repository or CI configuration.

## Security boundaries

- Provider credentials belong in iOS Keychain, never source control, plain preferences, or CI secrets.
- Agent tools must be purpose-built and permission-bounded for iOS; this is not an unrestricted desktop shell.
- Conversation history is stored on device with iOS file protection and excluded from device backups; deleting history cannot recall prompts already sent to a provider.
- Local memory notes use protected app storage excluded from device backups; their text is included with future provider requests for the selected profile, not stored in Keychain (reserved for credentials).
- Local-model support will document supported formats, device requirements, and resource limits.
