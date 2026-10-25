# Presentation assets

## Cover

[cover.svg](cover.svg) is a repository cover, not a new logo or an app mockup. It reuses the feather path, stroke and transform from [gen_icons.py](../../tools/gen_icons.py), the light palette and panel radius from [tokens.json](../../design/tokens.json), and the bundled Geist fonts. The tagline is editorial lettering; it does not replace the app's custom wordmark.

Text is outlined to preserve Geist when GitHub displays the SVG without installed fonts. Accessible text is included in the SVG title/description and the README image alt. Geist's [SIL Open Font License](../../app/assets/fonts/OFL-Geist.txt) remains in the repository. No remote assets or fonts are loaded.

Regenerate only the cover in an isolated Python environment with `fonttools` installed:

```sh
python3 tools/gen_presentation.py
```

Review the resulting SVG visually before committing, especially after a font, icon or token change. This generator does not alter app icons, tokens or goldens.

## Screenshot provenance

The README links directly to committed goldens, without copies, retouching or fabricated controls. These are screenshots of Flutter widgets under test, not screenshots from a connected mailbox or proof of a working release on a physical device.

| Image | Fixture and capture |
|---|---|
| [Desktop light](../../app/test/goldens/inbox_light.png) | `inbox golden light` in [inbox_test.dart](../../app/test/inbox_test.dart), 1440 × 900 |
| [Desktop dark](../../app/test/goldens/inbox_dark.png) | `inbox golden dark` in the same test, 1440 × 900 |
| [Phone inbox](../../app/test/goldens/phone_inbox_light.png) | `phone inbox golden light` in [phone_test.dart](../../app/test/phone_test.dart), 390 × 844 |
| [Phone compose](../../app/test/goldens/phone_compose_dark.png) | `phone compose golden dark` in the same test, 390 × 844 |

All four use [DemoMailSource](../../app/lib/mail/demo_source.dart), with a fixed test clock. Names, messages and account strings are hard-coded fixture data, not evidence of real correspondence. Some fixture addresses use real domain names rather than reserved example domains; they are not contact links or accounts to use. No device capture, credential, report attachment or live mailbox was used for this presentation. All four images were visually inspected.

## Refreshing the selection

1. Check the test setup still uses only fictional fixtures before using a replacement golden. Do not substitute a live account capture.
2. Follow the normal [UI/mockup workflow](../../CONTRIBUTING.md#mockup-and-app-always-in-sync) if a screen changes. Updating this presentation does not authorize UI changes.
3. When regeneration is needed, use the documented Flutter environment and targeted golden tests, then inspect light and dark images. No goldens were regenerated for this documentation-only change.
4. Check the README at narrow and wide widths, image alt text, captions and relative paths. Keep screenshots labeled as demo data and keep feature claims aligned with the README's [current status](../../README.md#current-status).
