import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A lint for right-to-left safety: text that comes from outside (a
/// subject, a sender's name or address, a snippet, a file or folder name)
/// may carry Unicode direction controls that reorder what's shown
/// (`Fattura U+202E txt.exe` reads "Fattura exe.txt"). Wherever such a
/// field is shown it goes through `safeBidi`, `bidiArg`, `isolate` or a
/// `BidiText`. This walks `lib/` and fails on a `Text(`,
/// `SelectableText(`, `TextSpan(text: …)` or localized sentence
/// (`l.someMessage(…)`) fed one of those fields bare.
///
/// A line that is safe for another reason (the value was cleaned a few
/// lines up, or the field isn't what its name suggests) can say so with
/// a `// bidi-ok` comment on the call's line or the line above.
void main() {
  test('untrusted fields are never shown without bidi safety', () {
    final hits = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('.g.dart'))
            .where((f) => !f.path.contains('/l10n/'))) {
      hits.addAll(bidiSweep(file.path, file.readAsStringSync()));
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the sweep finds what it should', () {
    const src = '''
Text(row.subject)
Text(safeBidi(row.subject))
SelectableText('\${row.sender} · \${row.fromEmail}', style: s)
TextSpan(style: s, text: m.preview)
TextSpan(text: bidiArg(context, m.preview))
onToast(l.alwaysInInboxDone(row.sender));
onToast(l.alwaysInInboxDone(bidiArg(context, row.sender)));
BidiText(row.subject)
Text(row.subject) // bidi-ok
// bidi-ok: the reply's own text.
Text(row.subject)
Text(l.noSubject)
''';
    final hits = bidiSweep('x.dart', src);
    expect(hits.map((h) => h.split(':')[1]), ['1', '3', '4', '6']);
  });
}

/// Field names whose values come from outside.
final _untrusted = RegExp(
  r'(?<!widget|RuleAction)\.(subject|sender|fromEmail|fromName|preview|snippet|fileName|folderName|label)\b',
);

/// Wrappers that clean it; `initials` keeps only letters and digits.
const _safe = ['safeBidi(', 'bidiArg(', 'isolate(', 'initials('];

final _calls = RegExp(
  r'(?<![A-Za-z0-9_])(Text|SelectableText|TextSpan)\(|(?<![A-Za-z0-9_.])l\.\w+\(',
);

/// The places in [src] (file [path]) where an untrusted field reaches the
/// screen bare, as `path:line: snippet`.
List<String> bidiSweep(String path, String src) {
  final hits = <String>[];
  for (final m in _calls.allMatches(src)) {
    final lineStart = src.lastIndexOf('\n', m.start) + 1;
    var lineEnd = src.indexOf('\n', m.start);
    if (lineEnd < 0) lineEnd = src.length;
    final line = src.substring(lineStart, lineEnd);
    final above = lineStart == 0
        ? ''
        : src.substring(src.lastIndexOf('\n', lineStart - 2) + 1, lineStart);
    if (line.trimLeft().startsWith('//') ||
        line.contains('bidi-ok') ||
        above.trimLeft().startsWith('// bidi-ok')) {
      continue;
    }
    final args = _args(src, m.end);
    final String? expr;
    if (m.group(1) == 'TextSpan') {
      expr = args.where((a) => a.startsWith('text:')).firstOrNull;
    } else if (m.group(1) != null) {
      // Text and SelectableText: the positional text.
      expr = args.firstOrNull;
    } else {
      // A localized sentence: every argument.
      expr = args.join(', ');
    }
    if (expr == null || !_untrusted.hasMatch(expr)) continue;
    if (_safe.any(expr.contains)) continue;
    final lineNo = '\n'.allMatches(src.substring(0, m.start)).length + 1;
    hits.add('$path:$lineNo: ${line.trim()}');
  }
  return hits;
}

/// The top-level arguments of the call whose `(` ends just before [from],
/// trimmed. Strings are kept whole (their interpolations count).
List<String> _args(String src, int from) {
  final out = <String>[];
  var depth = 0;
  var start = from;
  var i = from;
  String? quote;
  while (i < src.length) {
    final ch = src[i];
    if (quote != null) {
      if (ch == r'\') {
        i += 2;
        continue;
      }
      if (src.startsWith(quote, i)) {
        i += quote.length;
        quote = null;
        continue;
      }
      i++;
      continue;
    }
    if (src.startsWith("'''", i) || src.startsWith('"""', i)) {
      quote = src.substring(i, i + 3);
      i += 3;
      continue;
    }
    if (ch == "'" || ch == '"') {
      quote = ch;
      i++;
      continue;
    }
    if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
      continue;
    }
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0) {
        out.add(src.substring(start, i).trim());
        break;
      }
      depth--;
    }
    if (ch == ',' && depth == 0) {
      out.add(src.substring(start, i).trim());
      start = i + 1;
    }
    i++;
  }
  return out.where((a) => a.isNotEmpty).toList();
}
