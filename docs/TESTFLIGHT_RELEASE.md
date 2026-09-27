# Yanuseu TestFlight handoff

The manual workflow is **not an uploaded beta**. It accepts the exact current `main` SHA only after successful iOS Simulator CI. AC confirmed the Yanuseu app record/bundle ID `cool.n0thing.yanuseu` is under Team `2CH5J3W7UH`; portal status has not been independently read back. The previously used `VYJS7JMXU5` certificate belongs to another team and cannot sign Yanuseu. Its two GitHub secrets were removed.

## Apple account setup

1. The CSR has been generated on the Linux release host for Team `2CH5J3W7UH` (Common Name supplied by AC); the private key remains protected there and is **not** in the repository or share. On your iPhone, connected to your VPN, download the [public CSR](http://100.64.0.7:8792/Yanuseu-2CH5J3W7UH.certSigningRequest) or its [ZIP wrapper](http://100.64.0.7:8792/Yanuseu-2CH5J3W7UH.zip) and extract the `.certSigningRequest` in Files. In Apple Developer → Certificates, Identifiers & Profiles → Certificates → + → **Apple Distribution**, under Team `2CH5J3W7UH`, upload that CSR. Download the issued **public `.cer`**; send that `.cer` file as an attachment so b0b can verify it matches the retained private key and make the CI `.p12` on Linux. Never send the private key or `.p12` in chat.
2. [Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/) in Certificates, Identifiers & Profiles → Profiles → + → Distribution → **App Store Connect**. Select the explicit Yanuseu App ID `cool.n0thing.yanuseu`, Team `2CH5J3W7UH`, and that new Team `2CH5J3W7UH` Apple Distribution certificate. Download its `.mobileprovision`. Do not select a profile or certificate from another team.
3. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/), request API access if necessary, create a team API key with sufficient app-upload rights, and record its Key ID and Issuer ID. Download the `.p8` once; protect it. The 10-character Team ID `2CH5J3W7UH` is **not** an API Key ID. Do not send the `.p8` in chat or commit it.
4. Review Yanuseu's App Store Connect app privacy answers, export compliance, TestFlight beta description and contact, age rating, and tester groups. The app sends messages, instructions, and optional local memory to the user-selected HTTPS model provider; it has no developer-hosted relay. Answer Apple's questions based on the actual provider/collection arrangement. Do not declare encryption exemptions by guesswork.

## GitHub repository secrets

Open `ac-slay3r/Yanuseu` → Settings → Secrets and variables → Actions → New repository secret. **No release secrets are currently configured; the wrong-team certificate and mistaken Team-ID-as-Key-ID secrets were removed.** After AC provides the *public* new-team `.cer`, b0b will verify it against the private key retained on the Linux host and set `APP_DISTRIBUTION_P12_BASE64` and `APP_DISTRIBUTION_P12_PASSWORD` directly as GitHub Secrets. AC should never transmit the `.p12`, its password, or the private key in chat. AC adds the remaining secrets only after creating the matching Team `2CH5J3W7UH` assets:
- `YANUSEU_APP_PROFILE_BASE64`: base64 of the downloaded Yanuseu `.mobileprovision` **without line wrapping**. Encode locally, then paste into GitHub's masked secret form; never paste here.
- `ASC_API_KEY_ID`: the Key ID.
- `ASC_API_ISSUER_ID`: the Issuer ID.
- `ASC_API_PRIVATE_KEY_P8`: the **entire** downloaded `.p8` PEM text, including its BEGIN/END lines, in the GitHub secret form. Never share it in chat.

No user-supplied Keychain password is needed; CI generates a temporary one. Confirm only the **names** appear in `gh secret list`; secret values cannot be read back. Once the six secrets are set, tell b0b *only that setup is complete*. b0b can run the manual workflow with the exact green `main` SHA, an intended marketing version, and an unused higher build number, then inspect signed archive/IPA verification, upload, ASC processing, and tester availability before announcing beta readiness. The workflow does not automatically add testers.

## Device acceptance

Use [BETA_TESTING.md](BETA_TESTING.md). Simulator CI, upload acceptance, ASC processing, installation, live-provider turn, and physical-device behavior are separate gates.
