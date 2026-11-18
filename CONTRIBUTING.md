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
python3 tools/gen_rust_licenses.py --check   # after changing Cargo.lock
cargo deny check advisories sources          # after changing Cargo.lock (cargo install cargo-deny)
cd app && dart format lib test && flutter analyze && flutter test
cd ../wear && dart format lib test && flutter analyze && flutter test   # the watch app
```

- Dependabot proposes dependency updates every week. Its pull requests don't regenerate `THIRD_PARTY_RUST.md`, so CI skips that check for them; after merging one that changes `Cargo.lock`, the "Dependencies" workflow on `main` fails until a follow-up PR runs `python3 tools/gen_rust_licenses.py`.
- Engine tests against a real IMAP server: start `tools/test-imap-server.sh` (Dovecot) in another terminal, then `PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test`. The 50,000-message check: add `--release -- --ignored --nocapture`.
- If you change how a component looks, regenerate the screenshots with `flutter test --update-goldens` and check the images in the PR.
- Golden screenshots are compared only on Linux, where the references are rendered: other systems draw text slightly differently. On Windows and macOS `flutter test` passes them without comparing (it says so once), so run the comparison and `--update-goldens` on Linux: in CI, or in WSL Ubuntu with a clone on the Linux filesystem (not under `/mnt/`). `PIUMA_GOLDENS=compare flutter test` forces the comparison elsewhere.

## Building the app

- Flutter (the version CI uses) and Rust stable.
- **Android:** the Android SDK with the NDK version Flutter asks for (cargokit builds the Rust core with it). On Windows, turn on Developer Mode (Settings > System > For developers): Flutter plugins need symlinks.
- **Windows desktop:** Visual Studio 2022 (or its Build Tools) with "Desktop development with C++" **and** the "C++ ATL for latest v143 build tools" component; the notifications plugin needs ATL.
- **macOS and iOS:** Xcode.
- **Default mail app, `mailto:` links and `.eml` files:** every link or file another app hands Piuma comes through `app/lib/outside/` (the command line on Windows and Linux, Apple events on macOS, intents on Android). Installed builds register themselves: Windows per user, from the installer's hooks (`app/windows/runner/mail_handler.cpp`: `HKCU\Software\Classes`, Settings › Default apps; removed on uninstall), macOS from `Info.plist`, Android from its intent filters. A Linux build from source registers nothing; to try it, install the desktop file with the path of your build, then pick Piuma in Settings › Notifications › This device or with `xdg-settings`:

  ```sh
  sed "s|^Exec=piuma_mail|Exec=$PWD/app/build/linux/x64/release/bundle/piuma_mail|" \
    app/linux/packaging/mail.piuma.piuma_mail.desktop > ~/.local/share/applications/mail.piuma.piuma_mail.desktop
  update-desktop-database ~/.local/share/applications
  xdg-settings set default-url-scheme-handler mailto mail.piuma.piuma_mail.desktop
  ```

  Closing the window keeps Piuma running in the tray on Windows and Linux (Settings › Notifications › This device). On Linux the tray needs `libayatana-appindicator3` or `libappindicator3` and a desktop that shows them (on GNOME, the AppIndicator extension); without one, closing the window quits as before.
- **Windows release:** the "Release" workflow (`.github/workflows/release.yml`, started by hand from the Actions tab) runs `tools\windows-release.ps1` on a Windows runner: it builds the installer and the update packages with Velopack (`dotnet tool install -g vpk --version 1.2.161`) and publishes them as a GitHub prerelease, `v0.1.0-beta.N`. A second job on a Windows ARM64 runner then runs it with `-Arch arm64` and adds the native ARM64 installer and packages to the same release, in Velopack's `win-arm64` channel (Flutter builds for Windows on ARM only on an ARM64 machine); installed apps follow the channel they were installed from. Run by hand without `GITHUB_TOKEN`, the script only builds them, into `app\build\releases`. The changelog comes from `-Notes notes.md`, or from the pull requests merged since the last `v*` tag. The app checks the repository's releases (prereleases included) every few hours and downloads in the background (`app/lib/updates/`); `PIUMA_UPDATE_URL` changes the address it checks.
- **Wear OS watch:** `wear/` is a small Flutter app with no engine of its own: the phone app sends it the inbox over the watch connection (`WatchLink.kt`, `app/rust/src/watch.rs`) and does what its buttons ask. It shares the phone app's application id and key, as Wear OS requires. `cd wear && flutter test`; to try it, start a Wear OS emulator (Round, API 33 or later), pair it with a phone or phone emulator through the Wear OS app, then `flutter run -d <watch>` with the phone app installed on the phone. Its icons and tokens come from `tools/gen_icons.py` and `tools/gen_tokens.py`, like the phone's.
- **Android beta:** `sh tools/android-beta.sh` builds a release APK for 64-bit ARM phones signed with the project's beta key, so each build installs over the last. The key never goes in the repository: the script reads it from `PIUMA_KEYSTORE_B64` (the keystore, base64) and `PIUMA_KEYSTORE_PASSWORD` (alias `piuma`, or `PIUMA_KEY_ALIAS`). Without them, release builds keep the local debug key. The "Release" workflow builds the same APK, with the key from repository secrets, and attaches it to the GitHub prerelease.

## Platform differences in compose

- **Spell check** uses the platform's own checker, in the language the text is written in (one of the app's six, detected by the engine, else the app's language): Android and, through Flutter, iOS and macOS. Flutter has no spell checker on Windows and Linux yet, so there the body and subject are not checked; nothing else is needed to build.
- **Pasting a picture** into the text reads the system clipboard through the engine on Windows, macOS and Linux (`arboard`; on Linux it uses the X11 clipboard, which XWayland provides). On Android, pictures come from the keyboard (Gboard's clipboard, GIFs, stickers) through the text field. iOS is not wired yet.

## Sign-in with Microsoft and Google

Microsoft 365 and Outlook.com no longer accept passwords from mail apps, and Gmail takes them only as app passwords. Piuma Mail signs in to them with OAuth 2.0 instead: Authorization Code with PKCE in the system browser (never a web view of the app's own), as RFC 8252 asks of native apps. The engine side is `core/src/oauth.rs`; the providers are data in `core/src/oauth_providers.json` (endpoints, scopes, servers, domains and MX hosts), so another provider is a new entry there, not new code.

Every build needs its own registration with each provider, called a client. **None is in the repository, and none is needed to build**: without one, the app explains that it can't sign in to Microsoft, keeps app passwords for Gmail, and anyone can enter their own client ID under "Advanced: your own client ID" when adding the account.

### Giving a build its clients

The engine reads `PIUMA_OAUTH_CLIENTS` when it is compiled (`flutter build` and `flutter run` compile it through cargokit), as entries separated by `;` or new lines:

```sh
export PIUMA_OAUTH_CLIENTS="microsoft=<application id>;google=<desktop client id>;google.secret=<desktop client secret>;google.android=<android client id>"
```

- `<provider>`: the client ID on Windows, macOS and Linux (and on Android when there is no `.android` entry).
- `<provider>.android`: a client of Android type, used on Android. Google needs it; Microsoft's one client works everywhere.
- `<provider>.secret`: the client "secret" of a Google **desktop** client. It is not a secret: an installed app can't keep one, anyone can read it from the program, and Google documents it as such for installed apps (RFC 8252 section 8.5). PKCE is what protects the sign-in. Still, keep it out of the repository with the rest.
- `<provider>.tenant`: Microsoft's tenant, when not `common` (`organizations` for work and school accounts only, or a tenant ID).

The Android build (`app/android/app/build.gradle.kts`) reads the same variable to register Google's redirect scheme (the reversed Android client ID). Microsoft's redirect scheme on Android is always `mail.piuma.app://oauth`.

Refresh tokens are kept only in the system keychain (the Android Keystore on Android), in the account's entry, never in the database or the logs, and never travel through the device-sync space: another device signs in on its own. Access tokens stay in memory and are renewed five minutes before they run out, or once after a server refuses one; a second refusal asks the person to sign in again. Removing an account gives Google its refresh token back (Microsoft has no revocation endpoint for public clients; its token runs out on its own).

### Microsoft (Entra ID)

No paid verification is needed. In the [Microsoft Entra admin center](https://entra.microsoft.com) › Identity › Applications › App registrations › **New registration**:

1. **Name**: Piuma Mail. **Supported account types**: "Accounts in any organizational directory and personal Microsoft accounts" (multitenant and personal), so both Microsoft 365 and Outlook.com sign in.
2. **Authentication** › Add a platform › **Mobile and desktop applications**, with these redirect URIs:
   - `http://localhost` (the portal's own suggestion; keeps working if a later version uses it).
   - `http://127.0.0.1`: what the desktop apps use. The port is chosen at random each time and Microsoft ignores the port of loopback addresses. If the portal refuses an `http` address, add it in the **Manifest** under `replyUrlsWithType` as `{ "url": "http://127.0.0.1", "type": "InstalledClient" }`.
   - `mail.piuma.app://oauth`: Android.
   - Turn on **Allow public client flows** (Advanced settings). There is no client secret for Microsoft.
3. **API permissions** › Add a permission › APIs my organization uses › **Office 365 Exchange Online** (search "Office 365 Exchange Online"), Delegated: `IMAP.AccessAsUser.All` and `SMTP.Send`. `offline_access` (Microsoft Graph, delegated) gives the refresh token; add it too. The app asks for `https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access`.
4. **Branding & properties**: the publisher domain and the links to the privacy statement and terms.
5. **Publisher verification** (optional, free with a Microsoft AI Cloud Partner Program ID): without it the consent page shows the app as "unverified", and some organizations' policies stop people from consenting to unverified multitenant apps; their administrator can still consent for the whole organization. Microsoft 365 administrators can also turn off IMAP or SMTP AUTH per mailbox (SMTP AUTH is off by default in newer tenants): that is the organization's choice, not something the app can change.
6. Copy the **Application (client) ID** into `microsoft=` above.

### Google (Google Cloud)

In the [Google Cloud console](https://console.cloud.google.com), in a project of its own:

1. **Google Auth Platform** › Branding (the OAuth consent screen): app name, support email, logo, the home page, privacy policy and terms links, and the authorized domain they live on. **Audience**: External.
2. **Data access** › Add scope: `https://mail.google.com/` (full mailbox access, needed for IMAP and SMTP). It is a **restricted** scope.
3. **Clients** › Create client:
   - **Desktop app**: for Windows, macOS and Linux. Copy its client ID and client secret into `google=` and `google.secret=`. Desktop clients take any loopback port on `http://127.0.0.1`; there is nothing to add.
   - **Android**: package name `mail.piuma.piuma_mail` and the SHA-1 of the signing key (the beta key for beta builds, the store key for store builds). In its **Advanced settings**, enable **Custom URI scheme**: Google turned it off by default for new Android clients. The redirect is `com.googleusercontent.apps.<id>:/oauth2redirect`. Copy the client ID into `google.android=`.
4. **Testing** (before verification): while the app's publishing status is "Testing", only the **test users** listed in Audience can sign in, at most **100**, and their refresh tokens expire after **7 days**, so they must sign in again every week.
5. **Verification** for "In production": because `https://mail.google.com/` is restricted, Google requires the app verification (brand, domain ownership, a video of the sign-in and of how the data is used, a privacy policy that follows the Google API Services User Data Policy, including its Limited Use requirements) **and** a yearly **CASA security assessment** (Cloud Application Security Assessment) by an authorized assessor, whose cost falls on the publisher. Until it passes, Gmail users outside the test list sign in with an app password, which the app offers on its own.

### Using your own client

A fork, or a person whose organization requires its own app registration, follows the same steps, then either builds with `PIUMA_OAUTH_CLIENTS` or enters the client ID (and, for Microsoft, the tenant; for a Google desktop client, the secret) under "Advanced: your own client ID" in the add-account flow. The client is kept with the account in the keychain and used for every renewal.

One exception: **Google on Android** takes only the client the build was made with. Google sends Android sign-ins back to a scheme made from the client ID (`com.googleusercontent.apps.<id>`), and the app can only answer the scheme registered in its manifest at build time, so the option is hidden there and the engine refuses another Google client on Android. A Microsoft client of one's own works on Android too: its redirect, `mail.piuma.app://oauth`, is the same for every client (add it to your registration).

The sign-in answer is accepted only with this sign-in's `state` (compared in constant time); answers with another `state` are ignored and the app keeps waiting until the five minutes run out. When the provider names itself in the answer (`iss`, RFC 9207; Google does), it must be the `issuer` in `oauth_providers.json`.

## Reports in a fork

In-app reports go to the project's report relay ([`relay/`](relay/README.md)), which files them in
the project's private feedback repository; the privacy notice ([PRIVACY.md](PRIVACY.md)) names who
handles them. A fork that ships its own build points these at itself with environment variables
read when the Rust engine is built (`flutter build`, `flutter run` and `cargo build` all pass them
through; nothing is read at run time):

| Variable | What | Project default |
| --- | --- | --- |
| `PIUMA_REPORT_RELAY` | The relay's address; empty turns the relay off, leaving "Send by email instead" | `https://piuma-report-relay.matte-maraffio.workers.dev` |
| `PIUMA_FEEDBACK_ADDRESS` | Where "Send by email instead" writes; empty hides it | `piuma@matteomaraffio.com` |
| `PIUMA_PRIVACY_CONTROLLER` | Who handles reports, as the privacy notice in the app says | `Matteo Maraffio, maintainer of Piuma Mail` |
| `PIUMA_PRIVACY_CONTACT` | Where to ask about or erase a report | the feedback address |
| `PIUMA_PRIVACY_URL` | The full privacy notice | this repository's `PRIVACY.md` |
| `PIUMA_REPORT_FILES_DAYS` | Days the relay keeps attachments, as the notice says | `90` |

For example `PIUMA_REPORT_RELAY=https://reports.example.org flutter build apk`. Run your own relay
from `relay/` (its README has the setup, including the R2 bucket and its lifecycle rule), set
`REPO` to your feedback repository, and adapt `PRIVACY.md`. Moving the project's own relay from
`workers.dev` to a project domain is a maintainer step (DNS, a Workers route, then a build with the
new address): see the relay's README, "A project domain".

## License and DCO sign-off

- Every contribution is released under GPL-3.0-or-later plus the additional app store permission described in [`LICENSE-APPSTORE.md`](LICENSE-APPSTORE.md).
- Every commit must be signed off under the [Developer Certificate of Origin](DCO.txt): use `git commit -s`, which adds the line `Signed-off-by: Name <email>`. CI rejects commits without it.
- Forgot the sign-off? On your branch: `git rebase --signoff main`, then `git push --force-with-lease`.

## Language

Everything in the repository is in English: code, comments, documentation, commit messages and PRs. The app's interface is written in English first; Italian ships as a translation.
