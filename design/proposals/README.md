# Design proposals

These proposals are **Mockup only** and must be approved by Matteo before app UI changes. They do not supersede the approved canvas or change the app's current screen status.

| Screen | Proposal | App files (unchanged) | Status |
| --- | --- | --- | --- |
| Phone original email layout | [Fullscreen original](original-fullscreen.html), proposal v1, feedback [#17](https://github.com/TeoVader/piuma-mail-feedback/issues/17) | `app/lib/inbox/original_view.dart`, `app/lib/inbox/reader.dart`, `app/lib/inbox/message_body.dart` | Mockup only · pending Matteo approval |

The maintainer screen map is `~/wiki/projects/piuma-mail/design/MOCKUP.md`; its proposal entry must stay pending until explicit approval.

The HTML is self-contained, with the generated `design/tokens.css` embedded verbatim. It makes no network requests; image loading, sender trust and external links are illustrative interactions only. Open the file directly or render it through the parent thread's HTML preview.

## Proposed phone behavior

- Original layout opens on a full page above the existing reader. A quiet toolbar provides back, the layout name and Privacy. Back and the system back gesture restore the reader's previous position. The demo's back button illustrates this; actual Android navigation is future app work.
- The document occupies the remaining viewport and owns the only vertical reading scroll. There is no inset stage, rounded paper frame, measured height cap or finite height retry loop. Initial width fitting, pinch zoom and horizontal panning for wide email are future web-view behavior, not simulated here.
- Privacy keeps the existing Load images once, sender trust and clean-view controls. Trackers stay blocked, tracking parameters stay stripped, scripts stay removed and blocked by CSP, and links go through existing interception and suspicious-link checks. The mockup's safe-link explanatory dialog is a preview aid, **not** a proposal to add confirmation for every safe link. Existing sender-warning behavior must also remain effective.
- Reply, attachments and other message actions remain in the underlying reader. Desktop and tablet behavior is unchanged. No Flutter or native UI implementation is included.
- Future implementation must cover loading/error, long or late-resizing email, large text, dark chrome with white email paper, route restoration, accessibility and reduced motion. Entry uses the existing spatial spring, instant with reduced motion. No new tokens are introduced.

This is a local proposal for approval, not an approved canvas version and not an implemented screen. Approval is required before coding the phone route or updating app goldens.
