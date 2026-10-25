import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../mail/mail_source.dart';

/// A list or a quote, kept as the start of each of its lines
/// (`FormattingToApprove`).
enum LineBlock { bullets, numbers, quote }

/// The start of a bulleted line.
const bulletPrefix = '• ';

/// The start of a quoted line: a bar while writing, "> " once sent.
const quotePrefix = '│ ';

final _number = RegExp(r'^(\d{1,3})\. ');
final _quote = RegExp(r'^│ ?');
final _link = RegExp(r'^(https?://|mailto:)\S+$', caseSensitive: false);

/// The block a line starts with, and how long its start is.
(LineBlock?, int) blockOf(String line) {
  if (line.startsWith(bulletPrefix)) {
    return (LineBlock.bullets, bulletPrefix.length);
  }
  if (_number.firstMatch(line) case final m?) {
    return (LineBlock.numbers, m.end);
  }
  if (_quote.firstMatch(line) case final m?) return (LineBlock.quote, m.end);
  return (null, 0);
}

/// The body of compose with its formatting: bold, italic and links as
/// [marks] over the text, lists and quotes as the starts of their lines.
/// Every edit moves the marks with the words under them; typing at the
/// end of a bold word goes on in bold.
class RichBodyController extends TextEditingController {
  RichBodyController({super.text, List<BodyMark> marks = const []})
    : _marks = [...marks];

  List<BodyMark> _marks;

  /// Bold or italic turned on or off at the caret, for what is typed next.
  final _pending = <BodyMarkKind, bool>{};

  /// Set while the controller changes its own text.
  bool _internal = false;

  List<BodyMark> get marks => List.unmodifiable(_marks);

  set marks(List<BodyMark> marks) {
    _marks = _normal(marks, text.length);
    notifyListeners();
  }

  @override
  set value(TextEditingValue next) {
    final old = super.value;
    if (_internal || next.text == old.text) {
      if (!_internal && next.selection != old.selection) _pending.clear();
      super.value = next;
      return;
    }
    super.value = _shape(old, next);
  }

  /// [next] as typed over [old], with the marks moved along, a list or a
  /// quote carried on (or ended) by Enter, "- " and "> " turned into a
  /// list and a quote, and a pasted address over words made a link.
  TextEditingValue _shape(TextEditingValue old, TextEditingValue next) {
    final a = old.text, b = next.text;
    var p = 0;
    final most = a.length < b.length ? a.length : b.length;
    while (p < most && a.codeUnitAt(p) == b.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < most - p &&
        a.codeUnitAt(a.length - 1 - s) == b.codeUnitAt(b.length - 1 - s)) {
      s++;
    }
    final removedEnd = a.length - s;
    final inserted = b.substring(p, b.length - s);
    final sel = old.selection;
    // An address pasted over words links them.
    if (sel.isValid &&
        !sel.isCollapsed &&
        sel.start == p &&
        sel.end == removedEnd &&
        _link.hasMatch(inserted.trim()) &&
        !_link.hasMatch(a.substring(sel.start, sel.end).trim())) {
      _setLink(sel.start, sel.end, inserted.trim());
      return old.copyWith(
        selection: TextSelection.collapsed(offset: sel.end),
        composing: TextRange.empty,
      );
    }
    final lineStart = _lineStart(a, p);
    final typed = removedEnd == p && inserted.length == 1;
    if (typed && inserted == '\n' && !next.composing.isValid) {
      final lineEnd = a.indexOf('\n', p) < 0 ? a.length : a.indexOf('\n', p);
      final line = a.substring(lineStart, lineEnd);
      final (block, length) = blockOf(line);
      if (block != null && p >= lineStart + length) {
        if (line.substring(length).trim().isEmpty) {
          // Enter on an empty item ends the list.
          return _apply(old, lineStart, lineStart + length, '', lineStart);
        }
        final more = switch (block) {
          LineBlock.bullets => bulletPrefix,
          LineBlock.quote => quotePrefix,
          LineBlock.numbers =>
            '${int.parse(_number.firstMatch(line)!.group(1)!) + 1}. ',
        };
        final add = '\n$more';
        return _apply(old, p, p, add, p + add.length);
      }
    }
    if (typed && inserted == ' ') {
      final head = a.substring(lineStart, p);
      final into = switch (head) {
        '-' || '*' => bulletPrefix,
        '>' => quotePrefix,
        _ => null,
      };
      if (into != null) {
        return _apply(old, lineStart, p, into, lineStart + into.length);
      }
    }
    // Backspace into the start of an item takes the whole start away.
    if (inserted.isEmpty && removedEnd == p + 1) {
      final (block, length) = blockOf(a.substring(lineStart));
      if (block != null && removedEnd == lineStart + length) {
        return _apply(old, lineStart, lineStart + length, '', lineStart);
      }
    }
    _move(p, removedEnd, inserted.length);
    if (inserted.isNotEmpty && _pending.isNotEmpty) {
      for (final MapEntry(key: kind, value: on) in _pending.entries) {
        _marks = _without(_marks, kind, p, p + inserted.length);
        if (on) _marks.add(BodyMark(kind, p, p + inserted.length));
      }
    }
    _marks = _normal(_marks, b.length);
    return next;
  }

  /// [old] with `start..end` replaced by [text] and the caret at [caret].
  TextEditingValue _apply(
    TextEditingValue old,
    int start,
    int end,
    String text,
    int caret,
  ) {
    _move(start, end, text.length);
    final now = old.text.replaceRange(start, end, text);
    _marks = _normal(_marks, now.length);
    return TextEditingValue(
      text: now,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  /// Moves the marks for `start..end` replaced by [length] new characters.
  /// What is typed at the end of a bold or italic run joins it; a link
  /// grows only from inside.
  void _move(int start, int end, int length) {
    final gone = end - start;
    int map(int x) => x <= start ? x : (x >= end ? x - gone : start);
    _marks = [
      for (final m in _marks)
        () {
          var a = map(m.start), b = map(m.end);
          if (length == 0) return m.copyWith(start: a, end: b);
          if (gone > 0 && a == start && b == start && m.start < end) {
            // Typed over the whole run: the new words take its style.
            b = start + length;
          } else if (a >= start && b > start) {
            a += length;
            b += length;
          } else if (a < start &&
              (b > start || (b == start && m.kind != BodyMarkKind.link))) {
            b += length;
          }
          return m.copyWith(start: a, end: b);
        }(),
    ];
  }

  /// Whether [kind] is on for the selection: over all of it, or at the
  /// caret for what is typed next.
  bool isOn(BodyMarkKind kind) {
    final sel = selection;
    if (!sel.isValid) return false;
    if (sel.isCollapsed) {
      if (_pending[kind] case final on?) return on;
      final at = sel.baseOffset;
      return _marks.any(
        (m) =>
            m.kind == kind &&
            m.start < at &&
            (kind == BodyMarkKind.link ? at < m.end : at <= m.end),
      );
    }
    return _covered(kind, sel.start, sel.end);
  }

  bool _covered(BodyMarkKind kind, int start, int end) {
    var at = start;
    final runs = [
      for (final m in _marks)
        if (m.kind == kind && m.end > start && m.start < end) m,
    ]..sort((x, y) => x.start.compareTo(y.start));
    for (final m in runs) {
      if (m.start > at) return false;
      if (m.end > at) at = m.end;
    }
    return at >= end;
  }

  /// Bold or italic on or off: over the selection, or for what is typed
  /// next at the caret.
  void toggle(BodyMarkKind kind) {
    final sel = selection;
    if (!sel.isValid) return;
    final on = isOn(kind);
    if (sel.isCollapsed) {
      _pending[kind] = !on;
    } else {
      _marks = _without(_marks, kind, sel.start, sel.end);
      if (!on) _marks.add(BodyMark(kind, sel.start, sel.end));
      _marks = _normal(_marks, text.length);
    }
    notifyListeners();
  }

  /// The address of the link under the selection, if there is one.
  String? linkAt() {
    final sel = selection;
    if (!sel.isValid) return null;
    for (final m in _marks) {
      if (m.kind == BodyMarkKind.link &&
          m.start <= sel.start &&
          (sel.isCollapsed ? sel.start < m.end : sel.end <= m.end)) {
        return m.url;
      }
    }
    return null;
  }

  /// Links the selected words to [url]; an empty one takes the link away.
  void link(String url) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _setLink(sel.start, sel.end, url.trim());
    notifyListeners();
  }

  void _setLink(int start, int end, String url) {
    _marks = _without(_marks, BodyMarkKind.link, start, end);
    if (url.isNotEmpty) {
      _marks.add(BodyMark(BodyMarkKind.link, start, end, url));
    }
    _marks = _normal(_marks, text.length);
  }

  /// The block every selected line has, if they all have the same one.
  LineBlock? blockHere() {
    final lines = _lines();
    if (lines.isEmpty) return null;
    final first = blockOf(text.substring(lines.first)).$1;
    for (final at in lines) {
      if (blockOf(text.substring(at)).$1 != first) return null;
    }
    return first;
  }

  /// Turns the selected lines into [block], or back into plain lines when
  /// they all are one already.
  void toggleBlock(LineBlock block) {
    final lines = _lines();
    if (lines.isEmpty) return;
    final off = blockHere() == block;
    var sel = selection;
    var now = text;
    var n = lines.length;
    // From the last line up, so the earlier starts stay where they are.
    for (final at in lines.reversed) {
      final (_, length) = blockOf(now.substring(at));
      final start = switch (block) {
        _ when off => '',
        LineBlock.bullets => bulletPrefix,
        LineBlock.quote => quotePrefix,
        LineBlock.numbers => '$n. ',
      };
      n--;
      _move(at, at + length, start.length);
      int shift(int x) => x < at
          ? x
          : x < at + length
          ? at + start.length
          : x - length + start.length;
      sel = TextSelection(
        baseOffset: shift(sel.baseOffset),
        extentOffset: shift(sel.extentOffset),
      );
      now = now.replaceRange(at, at + length, start);
    }
    _marks = _normal(_marks, now.length);
    _internal = true;
    try {
      value = TextEditingValue(text: now, selection: sel);
    } finally {
      _internal = false;
    }
  }

  /// Where each line the selection touches starts.
  List<int> _lines() {
    final sel = selection;
    if (!sel.isValid) return const [];
    final t = text;
    var end = sel.end;
    // A selection that ends at the start of a line leaves that line out.
    if (end > sel.start && end > 0 && t[end - 1] == '\n') end--;
    final out = <int>[_lineStart(t, sel.start)];
    for (var i = sel.start; i < end; i++) {
      if (t[i] == '\n') out.add(i + 1);
    }
    return out;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final c = PiumaTheme.of(context);
    final t = text;
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    // Where the quoted lines and their bars are.
    final quoted = <(int, int)>[];
    final bars = <int>[];
    var at = 0;
    for (final line in t.split('\n')) {
      if (blockOf(line).$1 == LineBlock.quote) {
        quoted.add((at, at + line.length));
        bars.add(at);
      }
      at += line.length + 1;
    }
    if (_marks.isEmpty && quoted.isEmpty && !composing.isValid) {
      return TextSpan(style: style, text: t);
    }
    final cuts = <int>{0, t.length};
    for (final m in _marks) {
      cuts
        ..add(m.start.clamp(0, t.length))
        ..add(m.end.clamp(0, t.length));
    }
    for (final (a, b) in quoted) {
      cuts
        ..add(a)
        ..add(b);
    }
    for (final b in bars) {
      cuts
        ..add(b)
        ..add((b + 1).clamp(0, t.length));
    }
    if (composing.isValid) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final sorted = cuts.toList()..sort();
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i], b = sorted[i + 1];
      if (a >= b) continue;
      bool on(BodyMarkKind kind) =>
          _marks.any((m) => m.kind == kind && m.start <= a && m.end >= b);
      final inQuote = quoted.any((q) => q.$1 <= a && q.$2 >= b);
      final bar = bars.contains(a) && b == a + 1;
      final link = on(BodyMarkKind.link);
      children.add(
        TextSpan(
          text: t.substring(a, b),
          style: TextStyle(
            fontWeight: on(BodyMarkKind.bold) ? FontWeight.w600 : null,
            fontStyle: on(BodyMarkKind.italic) ? FontStyle.italic : null,
            color: bar
                ? c.line
                : link
                ? c.accentText
                : inQuote
                ? c.muted
                : null,
            decoration:
                link ||
                    (composing.isValid &&
                        composing.start <= a &&
                        composing.end >= b)
                ? TextDecoration.underline
                : null,
            decorationColor: link ? c.accentText : null,
          ),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }
}

/// Where the line holding [at] starts in [text].
int _lineStart(String text, int at) =>
    at <= 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

/// [marks] without [kind] over `start..end`; the rest of a run stays.
List<BodyMark> _without(
  List<BodyMark> marks,
  BodyMarkKind kind,
  int start,
  int end,
) => [
  for (final m in marks)
    if (m.kind != kind || m.end <= start || m.start >= end)
      m
    else ...[
      if (m.start < start) m.copyWith(end: start),
      if (m.end > end) m.copyWith(start: end),
    ],
];

/// [marks] inside the text, none empty, touching runs of the same kind
/// (and the same address) joined.
List<BodyMark> _normal(List<BodyMark> marks, int length) {
  final sorted = [
    for (final m in marks)
      if (m.start.clamp(0, length) < m.end.clamp(0, length))
        m.copyWith(
          start: m.start.clamp(0, length),
          end: m.end.clamp(0, length),
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final out = <BodyMark>[];
  for (final m in sorted) {
    final i = out.lastIndexWhere((o) => o.kind == m.kind && o.url == m.url);
    if (i >= 0 && out[i].end >= m.start) {
      if (m.end > out[i].end) out[i] = out[i].copyWith(end: m.end);
    } else {
      out.add(m);
    }
  }
  return out;
}
