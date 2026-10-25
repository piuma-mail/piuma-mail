import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/readable.dart' show fileSize;
import '../widgets/progress.dart';

/// "Written in German · Translate" under the sender, as on the
/// `TranslateQuiet` board: nothing happens until it is tapped. While the
/// first translation of a pair downloads, "Getting German–Italian · 28 MB"
/// with a thin progress line.
class TranslatePill extends StatelessWidget {
  const TranslatePill({
    super.key,
    required this.from,
    required this.to,
    required this.onTap,
    this.busy = false,
    this.download = false,
    this.bytes,
    this.progress,
    this.phone = false,
  });

  /// Two-letter codes.
  final String from;
  final String to;
  final VoidCallback onTap;

  /// Translating (or downloading, with [download]).
  final bool busy;

  /// The pair is downloaded first.
  final bool download;
  final int? bytes;

  /// How far the download is, 0 to 1; null before it says.
  final double? progress;

  /// "German · Translate", for room.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final language = l.languageName(from);
    final style = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 12,
      color: c.muted,
    );
    final String text;
    if (busy && download) {
      final first = _capital(language);
      final second = l.languageName(to);
      text = switch (bytes) {
        final b? => l.translateGettingSize(
          first,
          second,
          fileSize(b, locale: locale),
        ),
        null => l.translateGetting(first, second),
      };
    } else if (busy) {
      text = l.translating;
    } else {
      text = phone ? _capital(language) : l.translateWrittenIn(language);
    }
    final line = busy && download;
    return PiumaPressable(
      onTap: busy ? null : onTap,
      semanticLabel: busy ? text : '$text, ${l.translateAction}',
      child: Container(
        height: 26,
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(PiumaIcon.spark, size: 13, color: c.muted),
                  const SizedBox(width: 6),
                  Text(text, style: style),
                  if (!busy) ...[
                    Text(' · ', style: style),
                    Text(
                      l.translateAction,
                      style: style.copyWith(
                        color: c.accentText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (line)
              // A thin wavy line along the pill's foot, filling as the
              // download goes.
              Positioned(
                left: 10,
                right: 10,
                bottom: 1,
                child: PiumaProgress(value: progress, thickness: 2),
              ),
          ],
        ),
      ),
    );
  }
}

/// On top of a translated email: "Translated from German · on this
/// device" and "Show original" ("Translated · Original" on a phone).
class TranslatedBar extends StatelessWidget {
  const TranslatedBar({
    super.key,
    required this.from,
    required this.onOriginal,
    this.phone = false,
  });

  final String from;
  final VoidCallback onOriginal;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final style = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 12.5,
      color: c.accentText,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(PiumaRadius.button),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              phone
                  ? l.translatedShort
                  : l.translatedFrom(l.languageName(from)),
              style: style,
            ),
          ),
          PiumaPressable(
            onTap: onOriginal,
            semanticLabel: l.translateShowOriginal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                phone ? l.translateOriginalShort : l.translateShowOriginal,
                style: style.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _capital(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
