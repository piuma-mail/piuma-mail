import 'package:flutter/widgets.dart';

import 'bidi_table.g.dart';

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
    switch (_strength(r)) {
      case 0x52: // R or AL
        return TextDirection.rtl;
      case 0x4C: // L
        return TextDirection.ltr;
    }
  }
  return null;
}

/// [text]'s own direction, else [fallback].
TextDirection directionOf(
  String text,
  TextDirection fallback, {
  bool subject = false,
}) => firstStrongDirection(text, subject: subject) ?? fallback;

/// [text] with its own direction controls made harmless, for any string
/// that comes from outside: a sender's name or address, a subject, a
/// link's text, an attachment's or a server folder's name.
///
/// Embeddings, overrides and isolates (U+202A–U+202E, U+2066–U+2069)
/// become a visible U+FFFD, so "Bank\u202Egro.evil" can't show as
/// "Bank live.org" and a stray POP DIRECTIONAL ISOLATE can't close the
/// isolate [isolate] puts around it. The marks (LRM, RLM, ALM) become an
/// invisible WORD JOINER, which the bidi algorithm ignores. Every
/// replacement is one UTF-16 unit, like what it replaces, so offsets into
/// the text still hold. The core does the same (`core/src/bidi.rs`).
String safeBidi(String text) {
  if (!_hasBidiControl(text)) return text;
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    out.writeCharCode(switch (unit) {
      0x200E || 0x200F || 0x061C => 0x2060,
      >= 0x202A && <= 0x202E || >= 0x2066 && <= 0x2069 => 0xFFFD,
      _ => unit,
    });
  }
  return out.toString();
}

bool _hasBidiControl(String text) {
  for (final unit in text.codeUnits) {
    if (unit == 0x061C ||
        unit == 0x200E ||
        unit == 0x200F ||
        (unit >= 0x202A && unit <= 0x202E) ||
        (unit >= 0x2066 && unit <= 0x2069)) {
      return true;
    }
  }
  return false;
}

/// [text], made safe by [safeBidi], wrapped in FIRST STRONG ISOLATE …
/// POP DIRECTIONAL ISOLATE, so a name or subject written the other way
/// stays in one piece inside a sentence of the interface ("From {name}")
/// and doesn't pull its punctuation across. Empty text stays empty.
String isolate(String text) =>
    text.isEmpty ? text : '\u2068${safeBidi(text)}\u2069';

/// Opens the isolate the reader puts around a link's text: FIRST STRONG
/// ISOLATE and a WORD JOINER, which the bidi algorithm ignores. The joiner
/// tells it from an isolate the email itself holds, so [stripLinkIsolates]
/// takes out only the reader's when the text is copied or quoted.
const linkIsolateStart = '\u2068\u2060';

/// Closes what [linkIsolateStart] opened.
const linkIsolateEnd = '\u2060\u2069';

/// [text], selected in the reader, without the isolates it put around
/// links ([linkIsolateStart], [linkIsolateEnd]): the email's own text,
/// direction controls included, stays as written.
String stripLinkIsolates(String text) =>
    text.replaceAll(linkIsolateStart, '').replaceAll(linkIsolateEnd, '');

/// [text] made safe by [safeBidi], and isolated where it could scramble
/// the sentence it goes into: when it holds right-to-left letters, or the
/// interface reads right to left. Left-to-right text in a left-to-right
/// interface is left as it is.
String bidiArg(BuildContext context, String text) =>
    isRtl(context) || _hasRtl(text) ? isolate(text) : safeBidi(text);

bool _hasRtl(String text) {
  for (final r in text.runes) {
    if (r >= 0x0590 && _strength(r) == 0x52) return true;
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
    final text = safeBidi(data);
    final own = directionOf(text, around, subject: subject);
    return Text(
      text,
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

/// Whether [r] is strong for the bidi algorithm: `L`, `R` (for R and AL)
/// or `N` for everything else (digits of any kind, separators, combining
/// marks, format characters, neutrals), as a code unit. From the table
/// `tools/gen_bidi_table.py` writes out of Unicode's Bidi_Class.
int _strength(int r) {
  if (r < 0x80) {
    return (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) ? 0x4C : 0x4E;
  }
  var lo = 0;
  var hi = bidiRunStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (bidiRunStarts[mid] <= r) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return bidiStrongKinds.codeUnitAt(lo);
}
