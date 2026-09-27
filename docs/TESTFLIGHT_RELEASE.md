# Yanuseu TestFlight handoff

The manual workflow is **not an uploaded beta**. It accepts the exact current `main` SHA only after successful iOS Simulator CI. App record/bundle ID `cool.n0thing.yanuseu` under Team `VYJS7JMXU5` were confirmed by AC; portal status has not been independently read back.

## Apple account setup

1. [Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/) in Certificates, Identifiers & Profiles → Profiles → + → Distribution → **App Store Connect**. Select the *explicit* Yanuseu App ID `cool.n0thing.yanuseu`, Team `VYJS7JMXU5`, and the matching Apple Distribution certificate **ANDREW CONNER (VYJS7JMXU5)**. Download the new `.mobileprovision`. Do not select the Hermes app's profile.
2. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/), request API access if necessary, create a team API key with sufficient app-upload rights, and record its Key ID and Issuer ID. Download the `.p8` once; protect it. Do not send it in chat or commit it.
3. Review Yanuseu's App Store Connect app privacy answers, export compliance, TestFlight beta description and contact, age rating, and tester groups. The app sends messages, instructions, and optional local memory to the user-selected HTTPS model provider; it has no developer-hosted relay. Answer Apple's questions based on the actual provider/collection arrangement. Do not declare encryption exemptions by guesswork.

## GitHub repository secrets

Open `ac-slay3r/Yanuseu` → Settings → Secrets and variables → Actions → New repository secret. Two certificate secrets, `APP_DISTRIBUTION_P12_BASE64` and `APP_DISTRIBUTION_P12_PASSWORD`, have already been set from the verified Team distribution identity; do not replace them with chat text. Add:

- `YANUSEU_APP_PROFILE_BASE64`: base64 of the downloaded Yanuseu `.mobileprovision` **without line wrapping**. Encode locally, then paste into GitHub's masked secret form; never paste here.
- `ASC_API_KEY_ID`: the Key ID.
- `ASC_API_ISSUER_ID`: the Issuer ID.
- `ASC_API_PRIVATE_KEY_P8`: the **entire** downloaded `.p8` PEM text, including its BEGIN/END lines, in the GitHub secret form. Never share it in chat.

No user-supplied Keychain password is needed; CI generates a temporary one. Confirm only the **names** appear in `gh secret list`; secret values cannot be read back. Once the four secrets are set, tell b0b *only that setup is complete*. b0b can run the manual workflow with the exact green `main` SHA, an intended marketing version, and an unused higher build number, then inspect signed archive/IPA verification, upload, ASC processing, and tester availability before announcing beta readiness. The workflow does not automatically add testers.

## Device acceptance

Use [BETA_TESTING.md](BETA_TESTING.md). Simulator CI, upload acceptance, ASC processing, installation, live-provider turn, and physical-device behavior are separate gates.
