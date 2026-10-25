/// Finding a search's words in text, to mark them.
library;

/// Operators the engine understands; their values are not words to mark.
const _operators = {
  'from',
  'account',
  'group',
  'is',
  'after',
  'before',
  'has',
  'in',
};

/// The words and "quoted phrases" of a search, operators left out.
List<String> searchWords(String query) {
  final words = <String>[];
  final current = StringBuffer();
  var quoted = false;
  void flush() {
    final token = current.toString().trim();
    current.clear();
    if (token.isEmpty) return;
    final colon = token.indexOf(':');
    if (colon > 0 &&
        _operators.contains(token.substring(0, colon).toLowerCase())) {
      return;
    }
    if (_letter.hasMatch(token)) words.add(token);
  }

  for (final ch in query.split('')) {
    if (ch == '"') {
      quoted = !quoted;
      if (!quoted && !current.toString().contains(':')) flush();
    } else if (ch.trim().isEmpty && !quoted) {
      flush();
    } else {
      current.write(ch);
    }
  }
  flush();
  return words;
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

const _plain = {
  'àáâãäåā': 'a',
  'çćč': 'c',
  'èéêëēė': 'e',
  'ìíîïī': 'i',
  'ñń': 'n',
  'òóôõöøō': 'o',
  'ùúûüū': 'u',
  'ýÿ': 'y',
  'šś': 's',
  'žźż': 'z',
};

final _fold = {
  for (final MapEntry(:key, :value) in _plain.entries)
    for (final ch in key.split('')) ch: value,
};

/// Lowercase without accents, one character for one, so positions match
/// the original text.
String fold(String text) => text.split('').map((c) {
  final lower = c.toLowerCase();
  return lower.length == 1 ? _fold[lower] ?? lower : c;
}).join();

/// [text] cut into runs, `true` where a word of the search starts a word of
/// the text. The whole word is marked: "quot" marks "quotes".
List<(String, bool)> highlight(String text, List<String> words) {
  final folded = fold(text);
  final needles = [for (final w in words) fold(w)]
      .where((w) => w.isNotEmpty)
      .toList();
  if (needles.isEmpty || text.isEmpty) return [(text, false)];
  final runs = <(String, bool)>[];
  var plainFrom = 0;
  var i = 0;
  while (i < text.length) {
    final atWordStart = i == 0 || !_letter.hasMatch(text[i - 1]);
    final hit = atWordStart
        ? needles
              .where((n) => folded.startsWith(n, i))
              .fold<int>(
                0,
                (longest, n) => n.length > longest ? n.length : longest,
              )
        : 0;
    if (hit == 0) {
      i++;
      continue;
    }
    var end = i + hit;
    while (end < text.length && _letter.hasMatch(text[end])) {
      end++;
    }
    if (i > plainFrom) runs.add((text.substring(plainFrom, i), false));
    runs.add((text.substring(i, end), true));
    i = plainFrom = end;
  }
  if (plainFrom < text.length) runs.add((text.substring(plainFrom), false));
  return runs;
}

/// How many times the search's words appear in [text].
int countMatches(String text, List<String> words) =>
    highlight(text, words).where((r) => r.$2).length;

/// A snippet from the engine, its matches between U+0002 and U+0003.
List<(String, bool)> markedRuns(String snippet) {
  final runs = <(String, bool)>[];
  for (final (i, part) in snippet.split('\u0002').indexed) {
    if (i == 0) {
      if (part.isNotEmpty) runs.add((part, false));
      continue;
    }
    final end = part.indexOf('\u0003');
    if (end < 0) {
      runs.add((part, true));
      continue;
    }
    runs.add((part.substring(0, end), true));
    if (end + 1 < part.length) runs.add((part.substring(end + 1), false));
  }
  return runs;
}
