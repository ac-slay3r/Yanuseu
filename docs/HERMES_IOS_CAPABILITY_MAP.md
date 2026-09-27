# Hermes-to-iPhone capability map — beta candidate

Yanuseu owns orchestration, state, sessions, provider configuration, and native tool policy on the iPhone. It sends inference directly to a tester-selected OpenAI-compatible HTTPS endpoint. This map describes code-supported capabilities, not physical-device or TestFlight validation. Source evidence lives in `m0-source-evidence.md`, `m2-*-source-evidence.md`, and `m3-*-source-evidence.md`.

- **Native foreground agent turn — implemented, simulator-tested:** Streaming text, bounded tool rounds, stop/cancel, persisted local history, retry. iOS may suspend the app; no promise of continuous background turns.
- **Provider/model choice — implemented, simulator-tested:** User supplies endpoint, model and Keychain-held credential. Model-list connection check is not proof a chat completion works. No bundled provider credential or desktop relay.
- **Profiles and sessions — implemented, simulator-tested:** Per-profile settings, credentials and conversations; search/resume/rename/archive/export/delete. Unreadable history and profile index require explicit local archive/reset. Compression is not implemented; the chat request uses a bounded recent-message window.
- **Local memory — implemented, simulator-tested:** User-entered notes can be inspected, corrected and deleted per profile. A turn snapshots note text for future provider calls; prior requests/transcripts are not rewritten. No automatic extraction or global recall.
- **Commands and skills — implemented, simulator-tested:** Native commands and palette; reviewed text-only skill imports. Skills are provider instructions, not executable plugins or tool permissions.
- **Calculator — implemented, simulator-tested:** Optional profile-bound arithmetic tool, default off; provider advertisement and local execution gated. No external-effect approval is needed for this side-effect-free tool.
- **Unavailable:** Desktop shell/subprocess, arbitrary host paths, unrestricted device filesystem, desktop plugins, stdio MCP, OS service control, always-on background/cron, automatic messaging/delegation. No remote dashboard or desktop host is required.
- **Deferred:** On-device model inference, selected-file/photo/audio input, remote network MCP, reminders, bounded background tasks, other native tools. None has a user-facing control implying it works.

The beta device acceptance matrix is in `BETA_TESTING.md`. Simulator CI does not verify the signed archive, App Store Connect processing, a live provider, iPhone Keychain locking, or app lifecycle behavior.
