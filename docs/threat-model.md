# Threat model

What Piuma Mail protects, from whom, and where the lines of trust run. It covers the app and engine
(`app/`, `core/`, `app/rust/`), the watch app (`wear/`), the report relay (`relay/`), the release chain
(`.github/workflows/`, `tools/`) and the planned self-hosted companion. Keep it current: a pull request
that moves a trust boundary or adds a network service updates this file. Reporting a problem:
[SECURITY.md](../SECURITY.md). What to do when something goes wrong:
[incident-runbook.md](incident-runbook.md).

## Assets

| Asset | Where it lives | Why it matters |
|---|---|---|
| Mail, contacts, calendars, drafts, attachments | Each device's SQLite database (app support folder); the user's mail servers | The user's private correspondence |
| Account credentials (passwords, app passwords, future OAuth tokens) | The system keychain (Keychain, Credential Manager, Secret Service, Android Keystore), never the database | Full access to the mailbox |
| Sync space key and device list | The device keychain; the encrypted space folder on the user's IMAP server | Settings and state shared between the user's devices |
| The release signing keys: Android key, Windows Authenticode certificate, Apple Developer ID | The `signing` environment's secrets in GitHub Actions (deployment from `main` only, read only by the signing jobs); the maintainer's offline backup | Whoever holds one can ship code that users' devices accept as Piuma Mail |
| The release feed | GitHub Releases of the repository (`PIUMA_UPDATE_URL`) | Installed Windows apps install what it lists; other platforms link to it |
| The relay's GitHub token and ticket secret | Cloudflare Worker secrets | The token opens issues in the feedback repository |
| Reports sent from the app | The feedback repository (private) | May hold logs and descriptions written by users |
| The maintainer's GitHub account and the repository settings | GitHub | Control over everything above |

## Attackers

1. **A sender of mail.** Anyone can send the user a message: HTML, images, attachments, calendar
   invitations, links, forged sender names. The most common and most important attacker.
2. **A hostile or compromised mail server**, or someone on the network path when TLS is off or broken:
   can answer IMAP, SMTP, JMAP, Sieve and autoconfig requests with anything.
3. **Someone on the same network** (public Wi-Fi): can see and change traffic that is not TLS.
4. **A malicious or hijacked dependency**: a Rust crate, a Dart package, an npm package of the relay, a
   GitHub Action, a Flutter or toolchain release.
5. **Someone with a leaked token or key**: a GitHub token, a signing key, the relay's token.
6. **An abuser of the relay**: floods it, uses it to post content to the feedback repository, or tries
   to reach other repositories.
7. **Someone with the unlocked device** or a copy of its disk. Out of scope beyond what the operating
   system provides: the database is not encrypted separately, the keychain is the OS's. The optional
   app lock (see "App lock" below) keeps a person holding the unlocked device out of the app's
   screens; it is not encryption and doesn't stand against a copy of the disk.
8. **A malicious contributor**: a pull request that hides harmful code or changes a workflow.

## Trust boundaries

### Mail content → app

Everything inside a message is untrusted. Defences: the engine parses MIME, HTML and calendars in Rust
and normally redraws a message as one clean column of native widgets (`core/src/reading.rs`). The
"original layout" view hands the system web view an HTML document the engine cleaned first
(`core/src/original.rs`): scripts, frames, forms, plugins, media, SVG, `on…` handlers and
`javascript:` values removed, a `default-src 'none'` Content-Security-Policy on top, remote images
shown as placeholders until the user loads them (then fetched by the engine, with size limits, and
inlined as `data:`), and every navigation stopped and handed to the app. Links ask before opening and
warn when the text and the target differ (`core/src/impostor.rs`); attachments that can run ask
first; sender authentication results (SPF, DKIM, DMARC) are shown (`core/src/sender_auth.rs`).
On-device AI only sees messages after the user turns it on, and its output is never executed.

### Mail servers → engine

Servers are trusted with the mailbox they hold, nothing more. TLS with the platform's certificate
check (`core/src/tls.rs`; Mozilla's roots on Android); plain connections only where the user chose them.
Server answers are parsed with limits; a server cannot make the engine read or write outside the app's
folder. Autoconfig answers only fill in a form the user confirms.

### Device-sync space

Devices share settings through a folder on the user's own IMAP server, end-to-end encrypted with a key
that pairing passes between devices (`core/src/space.rs`, `core/src/space_sync.rs`). The server sees
only ciphertext and timing; a device removed from the space stops receiving the key on the next round.
A hostile server can delete or replay space messages: sync must stay safe (never decrypt to something
the key did not sign) and only become stale.

### App → report relay

The app sends bug reports and ideas to the relay (`relay/`, a Cloudflare Worker), which opens issues
in the feedback repository; no GitHub credential ships in the app. Reports carry only what the user
saw and confirmed in the report sheet. The relay holds the only token, scoped to the feedback
repository (issues and contents), and signs short-lived tickets so a client cannot replay or forge
another's. Issue text is untrusted data for maintainers and their tools, never instructions. The relay
itself is hardened in its own branch; its abuse runbook is in
[incident-runbook.md](incident-runbook.md#relay-abuse).

### Release chain

From a commit on `main` to code running on users' devices:

1. **Source**: changes reach `main` only through reviewed pull requests with required checks
   (protected branch; [CODEOWNERS](../.github/CODEOWNERS) on workflows, tools and dependency policy).
   Every commit is signed off (DCO).
2. **Dependencies**: Cargo.lock, pubspec.lock and package-lock.json pin every version; cargo-deny
   checks advisories, licenses, banned crates and registries on every pull request and every push to
   `main`, with no path filter (the release gate needs its result on the exact commit); OSV checks the
   Dart packages; `npm audit` the relay's; Dependabot proposes updates after a 14-day cooldown and security
   fixes at once; the vendored fxtranslate is watched by a weekly job. Every GitHub Action in our
   workflow files is pinned by commit. The repository setting that would enforce it ("Require actions to
   be pinned to a full-length commit SHA") stays off: it also covers the actions those actions call, and
   `subosito/flutter-action` calls `actions/cache` by tag (see CONTRIBUTING.md › Actions policy).
3. **Build**: the "Release" workflow runs from `main` only, after CI passed on that commit. Jobs that
   compile anything (build scripts, cargokit, Gradle, native hooks) get a read-only token and no
   signing secret.
4. **Signing**: separate jobs that compile nothing sign the packages: Velopack with Authenticode on
   Windows, `apksigner` with the project key on Android, `codesign` and notarisation on macOS. The
   keys never reach a build step.
5. **Provenance**: each signing or packaging job reports the SHA-256 of its files as a job output;
   the attest job downloads only those jobs' artifacts, by exact name, and refuses any file they did
   not report, so an artifact uploaded by a compromised build job is never shipped. Every file, and
   the `SHA256SUMS` list of their checksums, gets a build provenance attestation; verify it with
   `gh attestation verify` naming `--signer-workflow` (the release workflow) and
   `--source-ref refs/heads/main`, as in [SECURITY.md](../SECURITY.md).
6. **Publication**: one job with write access uploads the files to a **draft** release, removes any
   file an earlier run left there, and runs nothing from the repository; a final job un-drafts it once
   every platform is there, the draft's `SHA256SUMS` is the one this run's attest job made (its hash is
   a job output), the draft holds exactly the files it lists and each file's attestation names this
   commit. Both wait for a reviewer in the `release` environment. Apps never see drafts.
7. **Update**: installed Windows apps follow Velopack's feed in the release, check package hashes from
   that feed and, once releases are signed, run only Authenticode-signed code; other platforms only
   show a notice that links to the release page. Android refuses an update signed with another key.

Residual risks, accepted for now: the feed's hashes come from the same release as the packages, so
whoever can publish a release can ship an update (hence the environment, the draft step and the
attestations); someone with write access could swap a draft's file between the final check and the
un-draft: the job checks every file again once the release is published (release immutability then
locks them) and fails loudly, to be handled as a bad release ([incident runbook](incident-runbook.md)); until a Windows certificate exists, Windows packages are unsigned; GitHub itself, its
runners and the Actions pinned by commit are trusted; a compromised maintainer account defeats the
environment's review (use a hardware security key and keep admin rights to as few accounts as possible).

### App lock

Settings › Privacy & security › Lock Piuma, off by default (`app/lib/lock/`, `core/src/app_lock.rs`).

- **What it stops:** someone picking up the unlocked phone or computer and reading mail in Piuma,
  or seeing it in the recent apps (Android `FLAG_SECURE`, iOS app switcher cover), in notifications
  or on a paired Wear OS watch.
- **The PIN** (4 to 12 digits) is kept only as an Argon2id hash (19 MiB, 2 passes, random 16-byte
  salt) in the system keychain, or the Android Keystore through the app, never in the database or a
  file. A kept hash weaker than these parameters is refused, so editing it down doesn't speed up
  guessing. Wrong PINs wait longer and longer (free for 5, then 30 s, 1, 5, 15 minutes, then an hour
  each); the count is kept with the hash, so restarting the app doesn't reset it. Device unlock
  (BiometricPrompt with the screen lock as fallback, Windows Hello, Touch ID/Face ID with the device
  password) clears it. There is no reset: forgetting the PIN means the device unlock or removing
  Piuma's data.
- **Settings file:** `app-lock.json` next to the database says the lock is on, how long after leaving
  it locks and the notice text. It is not secret; deleting it turns the lock off, which needs the same
  access to the device's files that would read the database anyway. If the keychain can't give the
  hash back, the app stays locked and only the device unlock opens it.
- **Notifications and the watch:** while the lock is on, every notice (the app's and Android's
  background service's) says only "New message", without sender, subject, preview or buttons (the
  buttons would act on mail without unlocking). Wear OS mirrors those notices, so they are blank
  there too, and the phone sends the watch app an empty, locked summary and refuses its requests to
  open or act on a message until the lock is turned off. Sign-in problem notices from Android's
  background service still name the account, not any mail.
- **Not covered:** desktop reader windows are hidden when the lock closes but their window
  thumbnails depend on the system; Windows and macOS window previews are not blanked; the lock
  guards the app's screens only while it runs, not the data at rest.

### Self-hosted companion (planned)

An optional server the user runs themselves, which will also serve the mailbox as webmail. It changes
the model and must not ship before this section is filled in with its own review. What is known now:

- It is the user's server, not ours: "no servers of ours in the data path" still holds.
- It will hold mail and probably credentials or tokens to the mail servers: the same assets as a
  device, but reachable from the internet. Its authentication (strong passwords or passkeys, rate
  limits, sessions), its TLS and its updates become part of the user's attack surface.
- Webmail renders mail content in a browser on the companion's origin: the "mail content → app"
  defences must be redone for the web (strict Content Security Policy, sandboxed iframes on a separate
  origin, no scripts, remote content blocked), and cross-site request forgery and session theft
  become relevant.
- Its releases go through the same chain as the app (container images built, signed and attested the
  same way).

## Out of scope

The security of the user's mail provider and its servers; malware already on the device; physical
attacks beyond what the operating system defends; denial of service against GitHub, Cloudflare or a
mail provider.
