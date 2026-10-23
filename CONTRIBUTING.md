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
- Small PRs: one feature or one screen at a time.
- Before opening the PR:

```sh
cargo fmt --all && cargo clippy --all-targets -- -D warnings && cargo test
python3 tools/gen_tokens.py --check
python3 tools/gen_rust_licenses.py --check   # after changing Cargo.lock
cd app && dart format lib test && flutter analyze && flutter test
cd ../wear && dart format lib test && flutter analyze && flutter test   # the watch app
```

- Engine tests against a real IMAP server: start `tools/test-imap-server.sh` (Dovecot) in another terminal, then `PIUMA_TEST_IMAP=127.0.0.1:31143 cargo test`. The 50,000-message check: add `--release -- --ignored --nocapture`.
- If you change how a component looks, regenerate the screenshots with `flutter test --update-goldens` and check the images in the PR.

## Building the app

- Flutter (the version CI uses) and Rust stable.
- **Android:** the Android SDK with the NDK version Flutter asks for (cargokit builds the Rust core with it). On Windows, turn on Developer Mode (Settings > System > For developers): Flutter plugins need symlinks.
- **Windows desktop:** Visual Studio 2022 (or its Build Tools) with "Desktop development with C++" **and** the "C++ ATL for latest v143 build tools" component; the notifications plugin needs ATL.
- **macOS and iOS:** Xcode.
- **Windows release:** `powershell -File tools\windows-release.ps1` builds the installer and the update packages with Velopack (`dotnet tool install -g vpk --version 1.2.161`) and uploads them to the update feed. The feed's address goes in `PIUMA_UPDATE_URL` and its keys in `PIUMA_S3_ENDPOINT`, `PIUMA_S3_KEY_ID` and `PIUMA_S3_SECRET`, never in the repository. The changelog comes from `-Notes notes.md`, or from the pull requests merged since the last release. The app checks the feed every few hours and downloads in the background (`app/lib/updates/`). A Cloudflare R2 bucket while the repository is private, GitHub Releases after: give a `https://github.com/...` address and the app reads the repository's releases.
- **Wear OS watch:** `wear/` is a small Flutter app with no engine of its own: the phone app sends it the inbox over the watch connection (`WatchLink.kt`, `app/rust/src/watch.rs`) and does what its buttons ask. It shares the phone app's application id and key, as Wear OS requires. `cd wear && flutter test`; to try it, start a Wear OS emulator (Round, API 33 or later), pair it with a phone or phone emulator through the Wear OS app, then `flutter run -d <watch>` with the phone app installed on the phone. Its icons and tokens come from `tools/gen_icons.py` and `tools/gen_tokens.py`, like the phone's.
- **Android beta:** `sh tools/android-beta.sh` builds a release APK for 64-bit ARM phones signed with the project's beta key, so each build installs over the last. The key never goes in the repository: the script reads it from `PIUMA_KEYSTORE_B64` (the keystore, base64) and `PIUMA_KEYSTORE_PASSWORD` (alias `piuma`, or `PIUMA_KEY_ALIAS`). Without them, release builds keep the local debug key.

## License and DCO sign-off

- Every contribution is released under GPL-3.0-or-later plus the additional app store permission described in [`LICENSE-APPSTORE.md`](LICENSE-APPSTORE.md).
- Every commit must be signed off under the [Developer Certificate of Origin](DCO.txt): use `git commit -s`, which adds the line `Signed-off-by: Name <email>`. CI rejects commits without it.
- Forgot the sign-off? On your branch: `git rebase --signoff main`, then `git push --force-with-lease`.

## Language

Everything in the repository is in English: code, comments, documentation, commit messages and PRs. The app's interface is written in English first; Italian ships as a translation.
