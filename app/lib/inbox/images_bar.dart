import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/button.dart';

/// The slim bar over an email whose images wait (`ImagesToApprove`):
/// what is off and why, "Load images" for this email, and "Always for
/// this sender", which trusts them. It scrolls with the email.
class ImagesBar extends StatelessWidget {
  const ImagesBar({
    super.key,
    required this.count,
    required this.sender,
    required this.onLoad,
    required this.onTrust,
    this.phone = false,
  });

  final int count;
  final String sender;
  final VoidCallback onLoad;
  final VoidCallback onTrust;
  final bool phone;

  static double _buttonWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: PiumaButtonSize.touch.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + PiumaButtonSize.touch.padding * 2 + 4;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final note = Text(
      l.imagesOffBar(count, sender),
      style: TextStyle(
        fontFamily: PiumaFonts.sans,
        fontSize: 13,
        height: 1.35,
        color: c.muted,
      ),
    );
    final load = PiumaButton(
      label: l.loadImages,
      kind: phone ? PiumaButtonKind.secondary : PiumaButtonKind.tertiary,
      size: phone ? PiumaButtonSize.touch : PiumaButtonSize.compact,
      onPressed: onLoad,
    );
    final trust = PiumaButton(
      label: l.alwaysForSender,
      size: phone ? PiumaButtonSize.touch : PiumaButtonSize.compact,
      onPressed: onTrust,
    );
    return Container(
      padding: phone
          ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
          : const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                note,
                const SizedBox(height: PiumaSpace.s8),
                // Side by side when both labels fit, else stacked.
                LayoutBuilder(
                  builder: (context, box) {
                    final loadWidth = _buttonWidth(context, l.loadImages);
                    final trustWidth = _buttonWidth(context, l.alwaysForSender);
                    final fits =
                        box.maxWidth >= 340 &&
                        loadWidth + PiumaSpace.s8 + trustWidth <= box.maxWidth;
                    if (!fits) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          trust,
                          const SizedBox(height: PiumaSpace.s8),
                          load,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: loadWidth.ceil(), child: load),
                        const SizedBox(width: PiumaSpace.s8),
                        Expanded(flex: trustWidth.ceil(), child: trust),
                      ],
                    );
                  },
                ),
              ],
            )
          : LayoutBuilder(
              // A narrow reader puts the buttons under the words.
              builder: (context, box) => box.maxWidth >= 600
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          PiumaIconView(
                            PiumaIcon.image,
                            size: 16,
                            color: c.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: note),
                          const SizedBox(width: PiumaSpace.s8),
                          load,
                          const SizedBox(width: PiumaSpace.s4),
                          trust,
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: note,
                          ),
                          const SizedBox(height: PiumaSpace.s8),
                          Wrap(
                            spacing: PiumaSpace.s4,
                            runSpacing: PiumaSpace.s4,
                            children: [trust, load],
                          ),
                        ],
                      ),
                    ),
            ),
    );
  }
}

/// Original or clean, for an email built as a layout: a two-part switch
/// on the desktop, one link on the phone.
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({
    super.key,
    required this.original,
    required this.onChanged,
    this.phone = false,
  });

  /// The original layout shows.
  final bool original;
  final ValueChanged<bool> onChanged;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    if (phone) {
      final label = original ? l.cleanView : l.originalLayout;
      return PiumaPressable(
        onTap: () => onChanged(!original),
        semanticLabel: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.accentText,
              ),
            ),
          ),
        ),
      );
    }
    final instant = reduceMotion(context);
    Widget part(String label, bool on, bool value) => Semantics(
      button: true,
      selected: on,
      child: PiumaPressable(
        onTap: on ? null : () => onChanged(value),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.surface : const Color(0x00000000),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: on ? c.fg : c.muted,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(l.viewOriginal, original, true),
          part(l.viewClean, !original, false),
        ],
      ),
    );
  }
}
