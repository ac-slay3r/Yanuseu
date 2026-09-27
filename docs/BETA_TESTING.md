# Yanuseu beta acceptance checklist

This is an iPhone-hosted agent, not a desktop Hermes client. In the current build, only an OpenAI-compatible HTTPS provider is supported; on-device inference, shell, arbitrary filesystem access, continuous background turns, and desktop plugins are unavailable. Calculator is the only agent tool and defaults off. No provider key is supplied with the beta.

## Before inviting testers

- Record the exact Git SHA, CFBundleShortVersionString, CFBundleVersion, distribution team, bundle ID (`cool.n0thing.yanuseu`), signed IPA archive, and App Store Connect processed build number. Simulator CI and uploaded IPA are different artifacts.
- Review App Store Connect App Privacy against direct prompt/instruction/memory transmission to the tester's chosen provider, local protected histories and Keychain keys. Verify export compliance and territories/agreements. Never place tester API keys in CI or screenshots.
- Install the processed TestFlight build on a physical iPhone. Run the scenarios below without a desktop, gateway, or VPS. Record device/iOS version, provider type (not key), build number, result, screenshots with secrets redacted, and any crash diagnostics.

## Device scenarios

1. **First launch and credentials:** Configure an HTTPS OpenAI-compatible endpoint, model and personal API key. Model-list check does not establish chat support. Send a harmless first prompt and verify a streamed reply. Kill/relaunch: settings and history remain, key never appears in the UI, exported history, or logs. Lock/unlock during a request and retry deliberately.
2. **Profiles and sessions:** Create two profiles with different instructions/models. Switch and search sessions; verify no cross-profile results. Rename, archive, resume, export, delete and relaunch. Verify export is explicitly user-initiated. For unreadable profiles, confirm reset archives the original preferences; export those bytes in Settings. Sessions from missing profile IDs remain on disk: Conversations → menu → Recover Missing-Profile Sessions → review and explicitly move one into the active profile. Future requests may send that session history to the active profile’s provider.
3. **Memory and skills:** Add a note under one profile, send a question, correct/delete it and send a new question. Verify later requests use corrected content; prior transcript remains intact. Import/review an iOS-compatible text SKILL.md, enable only for one profile and confirm it cannot grant tool permission.
4. **Calculator and permission:** Verify calculator is not advertised or executed when disabled; explicitly enable it for one profile and exercise a simple arithmetic turn. Switch profiles and confirm the other remains disabled. Stop a streaming/tool turn; inspect persisted user/assistant/tool pairing.
5. **Interruption and recovery:** Turn on Airplane Mode during streaming, background/suspend the app, return and retry. Ensure no fabricated completion or duplicate unintended action. Exercise low-storage behavior and confirm an unsaved composer draft is retained when local history cannot be saved. For unreadable local data, confirm explicit recovery preserves exportable original bytes.
6. **Accessibility and layout:** Exercise VoiceOver, Dynamic Type, reduced motion, landscape (if offered), keyboard focus and small-screen layout through provider setup, chat, command palette, memory, sessions and tool controls.

## Exit criteria

No release claim until the signed app installs, the direct provider chat succeeds on device, Keychain lock/restore and interruption are observed, privacy/export-compliance answers are reviewed, and App Store Connect reports the exact processed TestFlight build. Record failures and decide explicitly whether to defer or block the beta.
