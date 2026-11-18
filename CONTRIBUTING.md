# Contributing

## Principles

1. **Design comes first.** A feature that does not fit the minimal design does not go in, or stays hidden until it is needed.
2. **Robust before rich.** Offline-first sync, Undo everywhere, no data lost.
3. **No servers of ours in the data path.**
4. **Small, on-device AI**, off until the user turns it on.

## Mockup and app always in sync

The mockup canvas and the app must always show the same thing.

1. **One source for style:** `design/tokens.json`. From it `tools/gen_tokens.py` generates the Flutter theme (`app/lib/design/tokens.g.dart`) and the canvas CSS (`design/tokens.css`). CI fails if the generated files are out of date.
2. **Screen map:** the maintainer keeps a map of every screen: where it is on the canvas, which Flutter file draws it, its status and the canvas version it matches. If your PR changes a screen, say which one in the PR; the map is updated when it is merged.
3. **Status on the canvas:** every screen is labeled *Mockup only*, *In progress* or *In app (v0.x)*.
4. **A "Mockup" item in every PR** that touches the interface (see the PR template).
5. **Mockup first, then code:** if a screen has to change, the canvas is updated and approved first, then the code is written.
6. **Golden screenshots:** `app/test/goldens/` holds the real screenshots in light and dark. At the end of each phase they go on the canvas next to the mockup.
7. **End of phase:** every screen of the phase is *In app* and matches the mockup.

## Workflow

- `main` always works. Every piece of work has a branch and a draft PR.
- Bugs and ideas: open an issue with the templates, or send them from the app (Settings → Help & feedback). Security problems go through [SECURITY.md](SECURITY.md), never a public issue.
- Small PRs: one feature or one screen at a time.
- Before opening the PR:

```sh
cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test
python3 tools/gen_tokens.py --check
python3 tools/gen_rust_licenses.py --check   # after changing Cargo.lock (also writes app/assets/licenses/)
cargo deny check                             # after changing Cargo.lock (cargo install cargo-deny)
python3 tools/pub_advisories.py              # after changing a pubspec.lock
cd app && dart format lib test && flutter analyze && flutter test
cd ../wear && dart format lib test && flutter analyze && flutter test   # the watch app
```

- Dependabot proposes dependency updates every week. Its pull requests don't regenerate `THIRD_PARTY_RUST.md`, so CI skips that check for them; after merging one that changes `Cargo.lock`, the "Dependencies" workflow on `main` fails until a follow-up PR runs `python3 tools/gen_rust_licenses.py`.
- Engine tests against a real IMAP server: start `tools/test-imap-server.sh` (Dovecot 2.3 or 2.4) in another terminal, then `PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test`. The 50,000-message check: add `--release -- --ignored --nocapture`.
- What CI runs on a pull request: the "CI" workflow (tokens, the engine, the engine against Dovecot 2.4 and 2.3, the app, the watch, and release-mode builds of the platforms the PR touches: a change to `core/`, `app/rust/`, dependencies or CI itself builds them all, iOS included), "Dependencies" (Rust, Dart and relay advisories; Rust licenses and banned crates, policy in `deny.toml`), "Report relay" (its tests) and "DCO". Every platform builds on `main` and every Monday. A license not in `deny.toml`'s list needs a pull request that adds it and says why it is compatible with GPL-3.0-or-later and `LICENSE-APPSTORE.md`.
- If you change how a component looks, regenerate the screenshots with `flutter test --update-goldens` and check the images in the PR.
- Golden screenshots are compared only on Linux, where the references are rendered: other systems draw text slightly differently. On Windows and macOS `flutter test` passes them without comparing (it says so once), so run the comparison and `--update-goldens` on Linux: in CI, or in WSL Ubuntu with a clone on the Linux filesystem (not under `/mnt/`). `PIUMA_GOLDENS=compare flutter test` forces the comparison elsewhere.

## Building the app

- Flutter (the version CI uses) and Rust stable.
- **Android:** the Android SDK with the NDK version Flutter asks for (cargokit builds the Rust core with it). On Windows, turn on Developer Mode (Settings > System > For developers): Flutter plugins need symlinks.
- **Windows desktop:** Visual Studio 2022 (or its Build Tools) with "Desktop development with C++" **and** the "C++ ATL for latest v143 build tools" component; the notifications plugin needs ATL.
- **The tools on Windows:** the scripts in `tools/` need Python 3.10 or newer. Install it from python.org with "Add python.exe to PATH" ticked, or use the `py` launcher that comes with it: `py -3 tools\gen_tokens.py --check`, `py -3 tools\gen_rust_licenses.py --check`, `py -3 tools\pub_advisories.py`. The `python3`/`python` names that Windows itself provides only open the Microsoft Store: turn them off in Settings › Apps › Advanced app settings › App execution aliases if they get in the way. The scripts read and write UTF-8 themselves, so nothing depends on the console's code page (an older checkout needed `py -3 -X utf8`). The `.sh` scripts run in Git Bash (`sh tools/android-beta.sh`) or WSL; `tools/test-imap-server.sh` needs Linux (WSL Ubuntu, Dovecot 2.3 or 2.4: `sudo apt install dovecot-imapd`), or Docker as its header says. `tools\windows-release.ps1` runs in PowerShell. In paths with spaces, use PowerShell and single quotes rather than `cmd.exe`.
- **macOS and iOS:** Xcode.
- **Releases:** the "Release" workflow (`.github/workflows/release.yml`, started by hand from the Actions tab on `main`) makes `v0.1.0-beta.N` (N = commits on `main` + 700) as a GitHub prerelease, once CI passed on that commit: the Windows installer and update packages for x64 and ARM64 (Velopack, `tools/windows-release.ps1`, `vpk` 1.2.161; ARM64 builds on an ARM64 runner, in Velopack's `win-arm64` channel), the Android phone and Wear OS APKs, a Linux AppImage (`tools/linux-appimage.sh`) and, when Apple credentials exist, a signed and notarised macOS app. Build jobs have no secrets and no write access; separate jobs sign; one job uploads everything to a draft release and a last one publishes it once every platform is there, both after approval in the `release` environment. Each file has a build provenance attestation (`gh attestation verify <file> --repo piuma-mail/piuma-mail`). Before publishing, the Windows installer is installed on the runner and the app started with `--smoke-test` (it opens its engine on a throwaway folder and exits). The `canary` choice makes an early release (`canary-v0.1.0-beta.N`, Velopack channels `win-canary` and `win-arm64-canary`, no installer) that apps follow only with Settings › Help & feedback › Updates › Early releases on. The changelog lists the pull requests merged since the last `v*` tag. Run by hand, `tools/windows-release.ps1` only builds and packs into `app\build\releases`; it never publishes.
- **Updates:** installed Windows apps check the feed every few hours and download in the background (`app/lib/updates/`); Android, macOS and Linux builds only show that a newer release is out, with a link to it. Both can be turned off in Settings › Help & feedback › Updates. The feed is `PIUMA_UPDATE_URL` and the channel `PIUMA_UPDATE_CHANNEL` (`beta` follows GitHub prereleases, `stable` only full releases), both set at build time. A release that crashes before its first frame heals itself on Windows: the next launch finds the launch marker the crashed one left, looks for a newer release and restarts into it before opening the engine. A bad release is fixed by the next one, never by going back: see [docs/incident-runbook.md](docs/incident-runbook.md#bad-release).
- **Linux:** releases carry an unsigned AppImage for x86_64. It brings the app, not GTK, WebKitGTK or the Secret Service: it needs a desktop with `libgtk-3`, `libwebkit2gtk-4.1` and a keyring (GNOME Keyring or KWallet), and glibc 2.39 or newer (Ubuntu 24.04, Debian 13, Fedora 40 and later). Mark it executable and run it.
- **macOS:** until the project has an Apple Developer ID, macOS is build-from-source (`flutter build macos`). With one, the "Release" workflow signs with Developer ID, notarises with an App Store Connect API key and staples the ticket (job `macos-sign`), see "Building your own fork" for the secrets.
- **Wear OS watch:** `wear/` is a small Flutter app with no engine of its own: the phone app sends it the inbox over the watch connection (`WatchLink.kt`, `app/rust/src/watch.rs`) and does what its buttons ask. It shares the phone app's application id and key, as Wear OS requires. `cd wear && flutter test`; to try it, start a Wear OS emulator (Round, API 33 or later), pair it with a phone or phone emulator through the Wear OS app, then `flutter run -d <watch>` with the phone app installed on the phone. Its icons and tokens come from `tools/gen_icons.py` and `tools/gen_tokens.py`, like the phone's.
- **Android beta:** `sh tools/android-beta.sh` builds a release APK for 64-bit ARM phones signed with the project's beta key, so each build installs over the last. The key never goes in the repository: the script reads it from `PIUMA_KEYSTORE_B64` (the keystore, base64) and `PIUMA_KEYSTORE_PASSWORD` (alias `piuma`, or `PIUMA_KEY_ALIAS`). Without a key a local release build is signed with the debug key and Gradle says so; on CI (`CI` set) that is an error, so pull requests build with a throwaway key (`.github/actions/android-throwaway-key`). The "Release" workflow builds the phone and watch APKs with a throwaway key too, then re-signs both with the project key in a job that compiles nothing, checks they share it and attaches them to the release. The watch app must be signed with the phone app's key or the two never pair.
- **Keeping the keys:** the Android key cannot be replaced for existing installs: losing it means every user reinstalls. Keep an offline copy of each signing key (Android keystore and its password, the Windows `.pfx`, the Apple `.p12` and API key) outside the workstation and outside GitHub: for example an encrypted USB drive in a safe place plus a second copy with someone you trust, the passwords in a password manager. Check once a year that the copy opens. What to do if one leaks: [docs/incident-runbook.md](docs/incident-runbook.md#signing-key-compromised).

## Building your own fork

Piuma Mail is free software: you can build, sign and ship your own copy. Nothing that identifies the upstream project is required. These are the values a fork sets; where it has none, the default in brackets applies.

**Repository settings (Settings › Secrets and variables › Actions):**

| Name | Kind | Needed | What it is |
|---|---|---|---|
| `PIUMA_UPDATE_URL` | variable | optional | The feed your builds check for updates [this repository's GitHub releases, `https://github.com/<owner>/<repo>`]. Any web folder filled by `vpk upload` works for Windows; only GitHub repositories give the notice on other platforms. |
| `PIUMA_KEYSTORE_B64`, `PIUMA_KEYSTORE_PASSWORD` | secrets | for Android | Your Android release keystore (base64) and its password. Make one with `keytool -genkeypair -keystore piuma.p12 -storetype PKCS12 -alias piuma -keyalg RSA -keysize 4096 -validity 10000`. Without them a release has no APKs. |
| `PIUMA_KEY_ALIAS` | variable | optional | The key's alias [`piuma`]. |
| `PIUMA_ANDROID_CERT_SHA256` | variable | recommended | The key's certificate SHA-256 (`keytool -list -v`): signed APKs must match it. |
| `WINDOWS_SIGN_PFX_B64`, `WINDOWS_SIGN_PFX_PASSWORD` | secrets | optional | An Authenticode code-signing certificate (`.pfx`, base64). |
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` (secrets); `AZURE_SIGN_ENDPOINT`, `AZURE_SIGN_ACCOUNT`, `AZURE_SIGN_PROFILE` (variables) | | optional | Or Azure Trusted Signing instead of a `.pfx`. Without either, Windows packages are unsigned and the workflow warns. |
| `APPLE_CERT_P12_B64`, `APPLE_CERT_PASSWORD` | secrets | for macOS | A "Developer ID Application" certificate with its private key (`.p12`, base64). |
| `APPLE_API_KEY_P8_B64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_TEAM_ID` | secrets | for macOS | An App Store Connect API key (role Developer) for notarisation, and your team id. Without the Apple secrets the release has no macOS app. |
| `PIUMA_REQUIRE_SIGNED` | variable | optional | Comma-separated platforms (`android`, `windows`) that must be signed: the release fails instead of leaving them out or unsigned. |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `FEEDBACK_GITHUB_TOKEN` (secrets); `FEEDBACK_REPO` (variable) | | for in-app reports | Your report relay, see `.github/workflows/report-relay.yml`. |
| environment `release` | environment | recommended | Required reviewers and a `main`-only deployment rule: the publish jobs wait for approval. |

**Build-time values (`--dart-define` or Cargo environment):**

| Name | Where | Default | What it is |
|---|---|---|---|
| `PIUMA_UPDATE_URL` | app (`--dart-define`) | none: updates off | The update feed; the "Release" workflow passes the variable above. |
| `PIUMA_UPDATE_CHANNEL` | app (`--dart-define`) | `beta` | `beta` follows GitHub prereleases, `stable` only full releases. |
| `PIUMA_BUILD` | app (`--dart-define`) | 0 | The build number; 0 shows no number and never offers updates. |
| `PIUMA_REPORT_RELAY` | engine (environment at `cargo build`) | the upstream relay | Your relay's address, so in-app reports reach your repository. |
| Relay contact and repository | `relay/wrangler.toml`, `FEEDBACK_REPO` | upstream's | Where reports become issues. |
| OAuth client IDs (Google, Microsoft) | *to be defined by the OAuth work* | none | Placeholder: sign-in with Google and Microsoft accounts needs client IDs registered by whoever ships the build; they will be listed here, overridable at build time. |

Also yours to change: the application ids (`mail.piuma.piuma_mail` in `app/android`, `wear/android`, `app/linux/CMakeLists.txt`, `app/macos`, `app/ios`) if your build should install next to the upstream app, the Velopack package id (`PiumaMail` in `tools/windows-release.ps1`), `.github/CODEOWNERS` and the contact in `SECURITY.md`.

## License and DCO sign-off

- Every contribution is released under GPL-3.0-or-later plus the additional app store permission described in [`LICENSE-APPSTORE.md`](LICENSE-APPSTORE.md).
- Every commit must be signed off under the [Developer Certificate of Origin](DCO.txt): use `git commit -s`, which adds the line `Signed-off-by: Name <email>`. CI rejects commits without it.
- Forgot the sign-off? On your branch: `git rebase --signoff main`, then `git push --force-with-lease`.

## Language

Everything in the repository is in English: code, comments, documentation, commit messages and PRs. The app's interface is written in English first; Italian ships as a translation.
