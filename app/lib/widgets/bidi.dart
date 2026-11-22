import 'package:flutter/widgets.dart';

/// Right-to-left support: which way a piece of mail reads, and how to keep
/// a name written the other way from scrambling the sentence around it.
///
/// The app's chrome follows the interface language through
/// [Directionality]; what people wrote (subjects, snippets, names, bodies,
/// a draft being typed) follows its own text, so an Arabic email reads
/// right to left in an English app and an English one left to right in
/// an Arabic app.

/// Forces the whole interface right to left, to check the layout without
/// an Arabic or Hebrew translation: `--dart-define=PIUMA_RTL=true`.
const bool forceRtl = bool.fromEnvironment('PIUMA_RTL');

/// Whether the layout around [context] reads right to left.
bool isRtl(BuildContext context) =>
    Directionality.maybeOf(context) == TextDirection.rtl;

/// [px] toward the reading start, for an optical nudge that lines a
/// control's glyph up with the text above it: left in English, right in
/// Arabic.
Offset towardStart(BuildContext context, double px) =>
    Offset(isRtl(context) ? px : -px, 0);

/// The direction of [text] by its first strong character (Unicode's rule
/// P2), or null when it has none (digits, punctuation, emoji, empty).
/// For a [subject], reply and forward prefixes ("Re:", "Fwd:", "AW:"…)
/// are skipped, so "Re: مرحبا" reads right to left like the subject it
/// answers.
TextDirection? firstStrongDirection(String text, {bool subject = false}) {
  final start = subject ? (_prefixes.matchAsPrefix(text)?.end ?? 0) : 0;
  var isolates = 0;
  for (final r in text.runes.skip(_runeCount(text, start))) {
    // Text inside an isolate doesn't decide the paragraph (rule P2).
    if (r == 0x2066 || r == 0x2067 || r == 0x2068) {
      isolates++;
      continue;
    }
    if (r == 0x2069) {
      if (isolates > 0) isolates--;
      continue;
    }
    if (isolates > 0) continue;
    if (r == 0x200F) return TextDirection.rtl; // RIGHT-TO-LEFT MARK
    if (r == 0x200E) return TextDirection.ltr; // LEFT-TO-RIGHT MARK
    if (_isRtlStrong(r)) return TextDirection.rtl;
    if (_isLtrStrong(r)) return TextDirection.ltr;
  }
  return null;
}

/// [text]'s own direction, else [fallback].
TextDirection directionOf(
  String text,
  TextDirection fallback, {
  bool subject = false,
}) => firstStrongDirection(text, subject: subject) ?? fallback;

/// [text] wrapped in FIRST STRONG ISOLATE … POP DIRECTIONAL ISOLATE, so a
/// name or subject written the other way stays in one piece inside a
/// sentence of the interface ("From {name}") and doesn't pull its
/// punctuation across. Empty text stays empty.
String isolate(String text) => text.isEmpty ? text : '\u2068$text\u2069';

/// [text] isolated where it could scramble the sentence it goes into: when
/// it holds right-to-left letters, or the interface reads right to left.
/// Left-to-right text in a left-to-right interface is left as it is.
String bidiArg(BuildContext context, String text) =>
    isRtl(context) || _hasRtl(text) ? isolate(text) : text;

bool _hasRtl(String text) {
  for (final r in text.runes) {
    if (r >= 0x0590 && _isRtlStrong(r)) return true;
  }
  return false;
}

/// A [Text] whose direction is its own content's, for strings people
/// wrote: a subject, a snippet, a name. Alignment follows the surrounding
/// layout's start ([TextAlign.start] by default), so a column of mixed
/// subjects stays lined up while each reads the right way.
class BidiText extends StatelessWidget {
  const BidiText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textAlign,
    this.semanticsLabel,
    this.subject = false,
  });

  /// A subject: "Re:" and "Fwd:" don't decide.
  final bool subject;

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final around = Directionality.of(context);
    final own = directionOf(data, around, subject: subject);
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      semanticsLabel: semanticsLabel,
      textDirection: own,
      // Lined up with the layout, not with the text's own start.
      textAlign: own == around
          ? (textAlign ?? TextAlign.start)
          : _flip(textAlign ?? TextAlign.start),
    );
  }

  static TextAlign _flip(TextAlign a) => switch (a) {
    TextAlign.start => TextAlign.end,
    TextAlign.end => TextAlign.start,
    _ => a,
  };
}

final _prefixes = RegExp(
  r'^(\s*(re|fwd?|aw|wg|tr|rv|sv|vs|r|i|enc|res|antw|odp|ynt)(\[\d+\])?\s*:\s*)+',
  caseSensitive: false,
);

int _runeCount(String s, int codeUnits) =>
    codeUnits == 0 ? 0 : s.substring(0, codeUnits).runes.length;

/// Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic, Arabic
/// extended, the Hebrew and Arabic presentation forms, and the
/// right-to-left blocks of the supplementary planes.
bool _isRtlStrong(int r) =>
    (r >= 0x0590 && r <= 0x08FF && !_isArabicDigitOrMark(r)) ||
    (r >= 0xFB1D && r <= 0xFDFF) ||
    (r >= 0xFE70 && r <= 0xFEFF && r != 0xFEFF) ||
    (r >= 0x10800 && r <= 0x10FFF) ||
    (r >= 0x1E800 && r <= 0x1EFFF);

/// Arabic-Indic digits and the combining marks in the right-to-left
/// blocks: weak or neutral, they don't decide.
bool _isArabicDigitOrMark(int r) =>
    (r >= 0x0591 && r <= 0x05BD) ||
    (r >= 0x0610 && r <= 0x061A) ||
    (r >= 0x064B && r <= 0x065F) ||
    (r >= 0x0660 && r <= 0x0669) ||
    r == 0x0670 ||
    (r >= 0x06D6 && r <= 0x06ED && r != 0x06E5 && r != 0x06E6) ||
    (r >= 0x06F0 && r <= 0x06F9);

final _letter = RegExp(r'\p{L}', unicode: true);

bool _isLtrStrong(int r) {
  if (r < 0x41) return false;
  if (r < 0x80) return (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
  return _letter.hasMatch(String.fromCharCode(r));
}
