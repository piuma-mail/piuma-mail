<p align="center">
  <img src="docs/images/cover.svg" alt="Piuma Mail — Mail, made light. An email client in development." width="100%">
</p>

# Piuma Mail

**Mail, made light.** A free, open-source email client with a clean, minimal interface. A quieter place to read, write and find your mail, with direct connections to your mailbox.

> [!NOTE]
> **In active development, not a stable release.** Mail protocols and the main interface flows are in the code; provider and platform coverage still need validation. See [current status](#current-status).

[Screenshots](#screenshots) · [Current status](#current-status) · [Build from source](#build-from-source) · [Contribute](#contribute) · [License](#license)

## A quieter place for your mail

- **One place to read.** A unified inbox, conversations, search and a reading pane that adapts to desktop and phone layouts.
- **Room to focus.** Light and dark themes, considered typography and motion, with separate views for newsletters, attachments and the Vault.
- **Your mailbox, directly.** IMAP/SMTP and JMAP implementations connect to mail providers without a Piuma-operated mail proxy. Optional reports use a separate feedback relay.
- **Free software.** The aim is a free client without paid account tiers, with source you can inspect and contribute to.

## Screenshots

Golden screenshots from the app's test suite, using **fictional demo mail**. [Sources and capture notes](docs/images/README.md).

<p align="center">
  <img src="app/test/goldens/inbox_light.png" alt="Desktop light theme: unified inbox beside a fictional dinner invitation" width="100%">
  <br><sub>Desktop · inbox and reading, light theme</sub>
</p>

<details>
<summary>See the desktop in dark mode</summary>

<p align="center">
  <img src="app/test/goldens/inbox_dark.png" alt="Desktop dark theme with the same fictional inbox and dinner invitation" width="100%">
</p>

</details>

<table>
  <tr>
    <td align="center"><img src="app/test/goldens/phone_inbox_light.png" alt="Phone light theme: fictional messages and shortcuts to newsletters, Vault and attachments" width="260"></td>
    <td align="center"><img src="app/test/goldens/phone_compose_dark.png" alt="Phone dark theme: a new empty message in the composer" width="260"></td>
  </tr>
  <tr>
    <td align="center">A shared inbox, sized for your phone</td>
    <td align="center">Space to write, in dark mode</td>
  </tr>
</table>

## Current status

**Source review: October 24, 2026.** This describes implementations in this repository, not a tested-provider list or a release announcement. The older “Phase 0” label no longer describes the breadth of the code; many screens in the maintainer's mockup map are still marked *In progress*.

| Area | Present in the source | Limits and next steps |
|---|---|---|
| Mail connections | IMAP/SMTP, JMAP, account discovery and manual setup | Validate real-provider behavior; do not assume every provider or authentication method works |
| Everyday mail | Unified inbox, reading, composing, drafts, attachments, search, archive and Undo | Core flows remain in development; test with a disposable mailbox before relying on them |
| Organization | Newsletters, Vault, labels, snooze and attachment views | Coverage varies by feature and provider |
| Certified mail (PEC) | Provider presets and receipt handling | Implementation exists; no claim of comprehensive provider validation |
| Platforms | Windows, macOS, Linux, Android and iOS project scaffolding; desktop, phone and tablet layouts | A build target or tablet layout does not establish shipping support; iPhone/iPad readiness is not claimed |
| Microsoft 365 / Proton | Dedicated Graph and Bridge flows deferred | Not advertised as available integrations |
| Optional companion | A future direction for instant iPhone notifications and reliable sending while the app is closed | Not an available service or a current dependency |

There is no public download destination announced yet.

## Build from source

For developers exploring the current code. Install Flutter and Rust plus the tools for your target platform; see [build prerequisites](CONTRIBUTING.md#building-the-app). The current CI configuration specifies Flutter 3.47.7.

```sh
# From the repository root: engine tests
cargo test

# App: resolve packages, then run on an available device
cd app
flutter pub get
flutter run
```

Use a test mailbox for development. Platform build instructions and the full validation commands are in [CONTRIBUTING.md](CONTRIBUTING.md); release scripts are not needed for a local run.

## Contribute

Start with a small, concrete improvement: a reproducible bug, a clearer setup guide, a provider compatibility finding, or an accessibility issue. Include the platform, build/commit, steps and expected behavior. Use invented messages and redact personal information from attachments.

For code or documentation, work on a branch, open a draft PR and sign off commits with `git commit -s` for the [Developer Certificate of Origin](DCO.txt). Report the checks you actually ran. Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the app; UI changes require mockup alignment and approval.

In builds configured for it, **Settings → Help & feedback** offers reporting with a preview of what will be sent. The feedback tracker is private; it is not a public issue destination. Public contribution and download destinations will be announced when they are chosen.

## Inside the repository

| Folder | Purpose |
|---|---|
| [`core/`](core/) | Rust mail engine, synchronization, SQLite storage and search |
| [`app/`](app/) | Flutter interface and engine bridge |
| [`design/`](design/) | `tokens.json`, the single source for colors, fonts, shapes and motion |
| [`relay/`](relay/) | Optional in-app report delivery, separate from mailbox traffic |
| [`tools/`](tools/) | Development and asset generation scripts |
| [`docs/`](docs/) | Presentation assets and where they come from |

Style comes from [`design/tokens.json`](design/tokens.json). The mockups define design; the app defines behavior. [Keep them in sync](CONTRIBUTING.md#mockup-and-app-always-in-sync).

## How this was built

Piuma Mail is AI-assisted: Matteo directs the product and design and decides what to accept; coding agents help with code and documentation.

## License

[GPL-3.0-or-later](LICENSE), with an additional permission for app store distribution under GPL section 7: [LICENSE-APPSTORE.md](LICENSE-APPSTORE.md). Third-party components and licenses: [THIRD_PARTY.md](THIRD_PARTY.md).
