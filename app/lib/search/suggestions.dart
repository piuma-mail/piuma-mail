/// What the search field suggests while an operator or its value is typed.
library;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../mail/mail_source.dart';
import 'highlight.dart' show fold;

/// The operators the engine reads (`core/src/search.rs`), as suggested.
const searchOperators = [
  'from:',
  'to:',
  'cc:',
  'bcc:',
  'subject:',
  'in:',
  'is:',
  'has:attachment',
  'label:',
  'filename:',
  'after:',
  'before:',
  'larger:',
  'smaller:',
  'account:',
];

/// Folders every account has, by the names `in:` takes.
const searchFolderJobs = [
  'inbox',
  'sent',
  'archive',
  'drafts',
  'snoozed',
  'trash',
  'spam',
  'vault',
  'newsletter',
];

/// The operators whose value is a person.
const _people = {'from', 'to', 'cc', 'bcc'};

/// One suggestion: the token it puts in place of the one being typed, and
/// what to show after it (a person's name).
class SearchSuggestion {
  const SearchSuggestion(this.insert, {this.label = ''});
  final String insert;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SearchSuggestion &&
      other.insert == insert &&
      other.label == label;

  @override
  int get hashCode => Object.hash(insert, label);

  @override
  String toString() => 'SearchSuggestion($insert, $label)';
}

/// What values are suggested from.
class SuggestionData {
  const SuggestionData({
    this.folders = const [],
    this.labels = const [],
    this.accounts = const [],
    this.people = const [],
  });

  /// Own folders, as paths ("Clients/Acme").
  final List<String> folders;
  final List<String> labels;

  /// Account names.
  final List<String> accounts;

  /// People for `from:`, `to:`, `cc:`, `bcc:`, the likeliest first.
  final List<Contact> people;
}

/// The token the caret is in or after: where it starts and what is typed
/// of it up to the caret. Null outside a token, or inside quotes that
/// belong to no operator.
({int start, String typed})? typedToken(String text, int caret) {
  if (caret < 0 || caret > text.length) return null;
  var start = 0;
  var quoted = false;
  for (var i = 0; i < caret; i++) {
    final ch = text[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (!quoted && ch.trim().isEmpty) {
      start = i + 1;
    }
  }
  final typed = text.substring(start, caret);
  if (typed.isEmpty) return null;
  if (quoted && !typed.contains(':')) return null;
  return (start: start, typed: typed);
}

/// The person-operator being typed, as (`from`, what is typed of the
/// value), to look people up; null for any other token.
(String, String)? personTyped(String typed) {
  final t = typed.startsWith('-') ? typed.substring(1) : typed;
  final colon = t.indexOf(':');
  if (colon <= 0) return null;
  final key = t.substring(0, colon).toLowerCase();
  if (!_people.contains(key)) return null;
  return (key, t.substring(colon + 1).replaceAll('"', ''));
}

/// What to suggest for [typed] (from [typedToken]), at most [limit].
List<SearchSuggestion> searchSuggestions(
  String typed,
  SuggestionData data, {
  required DateTime now,
  int limit = 6,
}) {
  final not = typed.startsWith('-') ? '-' : '';
  final t = typed.substring(not.length);
  final colon = t.indexOf(':');
  if (colon < 0) {
    if (t.isEmpty) return const [];
    final lower = t.toLowerCase();
    return [
      for (final op in searchOperators)
        if (op.startsWith(lower) && op != lower) SearchSuggestion('$not$op'),
    ].take(limit).toList();
  }
  final key = t.substring(0, colon).toLowerCase();
  final value = fold(t.substring(colon + 1).replaceAll('"', ''));
  final day = DateFormat('yyyy-MM-dd');
  final List<(String, String)> values = switch (key) {
    'in' => [
      for (final v in [...searchFolderJobs, ...data.folders]) (v, ''),
    ],
    'is' => [('unread', ''), ('read', ''), ('starred', '')],
    'has' => [('attachment', '')],
    'label' => [for (final v in data.labels) (v, '')],
    'account' => [for (final v in data.accounts) (v, '')],
    'larger' || 'smaller' => [('1M', ''), ('5M', ''), ('10M', ''), ('25M', '')],
    'after' || 'before' => [
      for (final days in [7, 30, 365])
        (day.format(now.subtract(Duration(days: days))), ''),
    ],
    'from' || 'to' || 'cc' || 'bcc' => [
      for (final p in data.people) (p.email, p.name),
    ],
    _ => const [],
  };
  bool fits((String, String) v) {
    if (value.isEmpty) return true;
    final words = [
      fold(v.$1),
      ...fold(v.$2).split(RegExp(r'\s+')),
      ...fold(v.$1).split(RegExp(r'[/@.\s_-]+')),
    ];
    return words.any((w) => w.startsWith(value)) && fold(v.$1) != value;
  }

  final seen = <String>{};
  return [
    for (final v in values)
      if (fits(v) && seen.add(v.$1.toLowerCase()))
        SearchSuggestion('$not$key:${_quoted(v.$1)}', label: v.$2),
  ].take(limit).toList();
}

String _quoted(String value) =>
    value.contains(RegExp(r'\s')) ? '"${value.replaceAll('"', '')}"' : value;

/// [value] with the token from [start] (through the caret and to the end
/// of the word) replaced by [s], and a space after unless the operator
/// still wants its value.
TextEditingValue applySuggestion(
  TextEditingValue value,
  int start,
  SearchSuggestion s,
) {
  final text = value.text;
  final caret = value.selection.baseOffset.clamp(start, text.length);
  var end = caret;
  while (end < text.length && text[end].trim().isNotEmpty) {
    end++;
  }
  final open = s.insert.endsWith(':');
  final after = text.substring(end);
  final glue = open || after.startsWith(' ') ? '' : ' ';
  final next = '${text.substring(0, start)}${s.insert}$glue$after';
  final offset = start + s.insert.length + (open ? 0 : 1);
  return TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: offset.clamp(0, next.length)),
  );
}

/// Paths of an account's own folders, from their tree order and depth.
List<String> folderPaths(List<AccountFolder> folders) {
  final path = <String>[];
  final out = <String>[];
  for (final f in folders) {
    if (path.length > f.depth) path.removeRange(f.depth, path.length);
    path.add(f.name);
    if (f.selectable) out.add(path.join('/'));
  }
  return out;
}
