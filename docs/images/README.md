# Presentation assets

## Cover

[cover.svg](cover.svg) (light) and [cover-dark.svg](cover-dark.svg) (dark) are the repository cover, not a new logo or an app mockup. The README shows the one that matches the reader's GitHub theme through `<picture>` and `prefers-color-scheme`. Both reuse the feather path, stroke and transform from [gen_icons.py](../../tools/gen_icons.py), the panel radius and the `light` or `dark` palette from [tokens.json](../../design/tokens.json) (`bg`, `accent`, `onAccent`, `muted`, `fg`, `accentText`), and the bundled Geist fonts. The layout is identical; only the colors and the description of the background differ. The tagline is editorial lettering; it does not replace the app's custom wordmark.

Text is outlined to preserve Geist when GitHub displays the SVG without installed fonts. Accessible text is included in the SVG title/description and the README image alt. Geist's [SIL Open Font License](../../app/assets/fonts/OFL-Geist.txt) remains in the repository. No remote assets or fonts are loaded.

Regenerate both covers in an isolated Python environment with `fonttools` installed:

```sh
python3 tools/gen_presentation.py
```

Review the resulting SVGs visually before committing, especially after a font, icon or token change. This generator does not alter app icons, tokens or goldens. (The first `cover-dark.svg` was written by swapping the six token colors in `cover.svg` for their dark values, which is what the generator produces; running it should leave both files unchanged.)

## README badges

The badges are [shields.io](https://shields.io) images: the latest release including prereleases, the status of the CI workflow on `main`, and static badges for the license, the platforms with beta builds and the download links. They use the `accent` (`#3451D1`) and `muted` (`#62656C`) light tokens. They load no tracking pixels and link only to this repository's pages or README sections. If the license or the platforms with builds change, update the static badges.

## Screenshot provenance

The README links directly to committed goldens, without copies, retouching or fabricated controls. These are screenshots of Flutter widgets under test, not screenshots from a connected mailbox or proof of a working release on a physical device.

Each screenshot is shown through `<picture>`: the light golden by default and the dark one when the reader's GitHub theme is dark.

| Images | Fixture and capture |
|---|---|
| Desktop inbox ([light](../../app/test/goldens/inbox_light.png), [dark](../../app/test/goldens/inbox_dark.png)) | `inbox golden light/dark` in [inbox_test.dart](../../app/test/inbox_test.dart), 1440 × 900 |
| Phone inbox ([light](../../app/test/goldens/phone_inbox_light.png), [dark](../../app/test/goldens/phone_inbox_dark.png)) | `phone inbox golden light/dark` in [phone_test.dart](../../app/test/phone_test.dart), 390 × 844 |
| Phone reading ([light](../../app/test/goldens/phone_read_light.png), [dark](../../app/test/goldens/phone_read_dark.png)) | `phone read golden light/dark` in the same test, 390 × 844 |
| Phone Vault ([light](../../app/test/goldens/phone_vault_light.png), [dark](../../app/test/goldens/phone_vault_dark.png)) | `phone vault golden light/dark` in [vault_test.dart](../../app/test/vault_test.dart), 390 × 844 |
| Phone Newsletters ([light](../../app/test/goldens/phone_newsletters_light.png), [dark](../../app/test/goldens/phone_newsletters_dark.png)) | `phone newsletters golden light/dark` in [newsletters_test.dart](../../app/test/newsletters_test.dart), 390 × 844 |
| Desktop conversation ([light](../../app/test/goldens/conversation_light.png), [dark](../../app/test/goldens/conversation_dark.png)) | `conversation golden light/dark` in [conversations_test.dart](../../app/test/conversations_test.dart), 1440 × 900 |
| Desktop Vault ([light](../../app/test/goldens/vault_light.png), [dark](../../app/test/goldens/vault_dark.png)) | `vault golden light/dark` in [vault_test.dart](../../app/test/vault_test.dart), 1440 × 900 |

All of them use [DemoMailSource](../../app/lib/mail/demo_source.dart), with a fixed test clock. Names, messages and account strings are hard-coded fixture data, not evidence of real correspondence. Some fixture addresses use real domain names rather than reserved example domains; they are not contact links or accounts to use. No device capture, credential, report attachment or live mailbox was used for this presentation. All fourteen images were visually inspected.

## Refreshing the selection

1. Check the test setup still uses only fictional fixtures before using a replacement golden. Do not substitute a live account capture.
2. Follow the normal [UI/mockup workflow](../../CONTRIBUTING.md#mockup-and-app-always-in-sync) if a screen changes. Updating this presentation does not authorize UI changes.
3. When regeneration is needed, use the documented Flutter environment and targeted golden tests, then inspect light and dark images. No goldens were regenerated for this documentation-only change.
4. Check the README at narrow and wide widths, image alt text, captions and relative paths. Keep screenshots labeled as demo data and keep feature claims aligned with the README's [current status](../../README.md#current-status).
