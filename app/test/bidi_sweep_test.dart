import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A lint for right-to-left safety: text that comes from outside (a
/// subject, a sender's name or address, a snippet, a file or folder name)
/// may carry Unicode direction controls that reorder what's shown
/// (`Fattura U+202E txt.exe` reads "Fattura exe.txt"). Wherever such a
/// field is shown it goes through `safeBidi`, `bidiArg`, `isolate` or a
/// `BidiText`. This walks `lib/` and fails on a `Text(`,
/// `SelectableText(`, `TextSpan(text: …)`, localized sentence
/// (`l.someMessage(…)`) or notification (`SystemNotice(title: …)`) fed
/// one of those fields bare, each occurrence on its own.
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
Text('\${safeBidi(row.sender)} \${row.subject}')
Text('\${safeBidi(row.sender)} \${safeBidi(row.subject)}')
l.from(isolate(row.sender), row.subject)
l.from(isolate(row.sender), bidiArg(context, row.subject))
Text('(\${row.subject}')
Text(safeBidi('\${row.sender} ') + row.subject)
Text(initials(row.sender))
Text(row.subject.isEmpty ? l.noSubject : safeBidi(row.subject))
Text(row.subject.isEmpty ? l.noSubject : row.subject)
SystemNotice(id: 1, title: n.sender, subject: safeBidi(n.subject), preview: n.preview, payload: n.subject)
SystemNotice(id: 1, title: safeBidi(n.sender), subject: safeBidi(n.subject), preview: safeBidi(n.preview), payload: n.subject)
''';
    final hits = bidiSweep('x.dart', src);
    expect(hits.map((h) => h.split(':')[1]), [
      '1',
      '3',
      '4',
      '6',
      '13',
      '15',
      '17',
      '18',
      '21',
      '22',
    ]);
  });
}

/// Field names whose values come from outside.
final _untrusted = RegExp(
  r'(?<!widget|RuleAction)\.(subject|sender|fromEmail|fromName|preview|snippet|fileName|folderName|label)\b',
);

/// Wrappers that clean it; `initials` keeps only letters and digits.
const _safe = {'safeBidi', 'bidiArg', 'isolate', 'initials'};

final _test = RegExp(r'^(\.(isEmpty|isNotEmpty|length)\b|\s*[=!]=)');

/// Whether some occurrence of an untrusted field in [expr] is outside
/// every [_safe] wrapper. Each occurrence is checked on its own: one
/// wrapped field doesn't vouch for another next to it
/// (`'${safeBidi(row.sender)} ${row.subject}'`). Literal text in strings
/// is skipped; their `${…}` interpolations are code.
bool _hasBareField(String expr) {
  final fields = {
    for (final m in _untrusted.allMatches(expr))
      // A test on the field (`row.subject.isEmpty ? … : …`) shows nothing.
      if (!_test.hasMatch(expr.substring(m.end))) m.start,
  };
  if (fields.isEmpty) return false;
  // Open brackets, each with the name called (or '' for none), and open
  // strings, as their closing quote.
  final stack = <({String? call, String? quote})>[];
  var i = 0;
  while (i < expr.length) {
    final quote = stack.isEmpty ? null : stack.last.quote;
    if (quote != null) {
      if (expr[i] == r'\') {
        i += 2;
      } else if (expr.startsWith(quote, i)) {
        stack.removeLast();
        i += quote.length;
      } else if (expr.startsWith(r'${', i)) {
        stack.add((call: '', quote: null));
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (fields.contains(i) && !stack.any((s) => _safe.contains(s.call))) {
      return true;
    }
    final ch = expr[i];
    final triple = expr.startsWith("'''", i) || expr.startsWith('"""', i);
    if (triple || ch == "'" || ch == '"') {
      final raw = i > 0 && expr[i - 1] == 'r';
      final q = triple ? expr.substring(i, i + 3) : ch;
      i += q.length;
      if (raw) {
        final end = expr.indexOf(q, i);
        i = end < 0 ? expr.length : end + q.length;
      } else {
        stack.add((call: null, quote: q));
      }
      continue;
    }
    if (ch == '(' || ch == '[' || ch == '{') {
      final name = RegExp(r'[A-Za-z0-9_]+$').firstMatch(expr.substring(0, i));
      stack.add((call: ch == '(' ? (name?.group(0) ?? '') : '', quote: null));
    } else if ((ch == ')' || ch == ']' || ch == '}') &&
        stack.isNotEmpty &&
        stack.last.quote == null) {
      stack.removeLast();
    }
    i++;
  }
  return false;
}

final _calls = RegExp(
  r'(?<![A-Za-z0-9_])(Text|SelectableText|TextSpan|SystemNotice)\(|(?<![A-Za-z0-9_.])l\.\w+\(',
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
    } else if (m.group(1) == 'SystemNotice') {
      // What the system shows: it draws it as it is.
      expr = args
          .where((a) => RegExp(r'^(title|subject|preview):').hasMatch(a))
          .join(', ');
    } else if (m.group(1) != null) {
      // Text and SelectableText: the positional text.
      expr = args.firstOrNull;
    } else {
      // A localized sentence: every argument.
      expr = args.join(', ');
    }
    if (expr == null || !_hasBareField(expr)) continue;
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
