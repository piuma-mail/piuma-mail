# Third-party components

Piuma Mail is distributed under GPL-3.0-or-later. It includes these components under their own licenses.

## Fonts

| Component | Author | License | File |
|---|---|---|---|
| Geist, Geist Mono | © 2023 Vercel, in collaboration with basement.studio | SIL Open Font License 1.1 | `app/assets/fonts/OFL-Geist.txt` |

The font files stay next to the license text in `app/assets/fonts/`. The license is also shown on the app's licenses screen.

## Libraries

The Rust crates compiled into the engine, with their licenses, are listed in [`THIRD_PARTY_RUST.md`](THIRD_PARTY_RUST.md) (regenerate it with `python3 tools/gen_rust_licenses.py` after changing `Cargo.lock`). Dart libraries are listed in `app/pubspec.lock` and their licenses are shown on the app's licenses screen; the Rust crates' license texts will be added to that screen before the first release.

| Component | Author | License | Used for |
|---|---|---|---|
| pdf | © 2017 David PHAM-VAN | Apache License 2.0 | Building the printed page (Print, or save as PDF) |
| printing | © 2017 David PHAM-VAN | Apache License 2.0 | The system's print window, with Save as PDF |
| velopack | © Velopack Ltd. and contributors | MIT License | Windows installer and updates (with `vpk`, its packaging tool) |

## Translation engine

On-device translation uses a patched copy of fxtranslate in [`third_party/fxtranslate/`](third_party/fxtranslate/); the changes are listed in its [`PIUMA.md`](third_party/fxtranslate/PIUMA.md) and stay under its license.

| Component | Author | License | File |
|---|---|---|---|
| fxtranslate 0.5.0 | fxtranslate contributors ([source](https://github.com/gregtatum/translations)) | Mozilla Public License 2.0 | `third_party/fxtranslate/LICENSE` |
| gemmology (vendored in fxtranslate) | © 2023 Serge Guelton | MIT License | `third_party/fxtranslate/vendor/gemmology/LICENSE` |
| xsimd (vendored in fxtranslate) | © 2016 Johan Mabille, Sylvain Corlay, Wolf Vollprecht, Martin Renou, QuantStack; © 2018 Serge Guelton | BSD 3-Clause License | `third_party/fxtranslate/vendor/xsimd/LICENSE` |

The translation models are not part of the repository or the app: they are downloaded from Mozilla's servers the first time a language pair is used.
