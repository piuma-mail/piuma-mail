import 'package:flutter/foundation.dart';

/// The words selected in the reader right now, for a reply that quotes
/// only them; null when nothing is selected.
final readerSelection = ValueNotifier<String?>(null);

final _space = RegExp(r'\s+');

/// What a reply to [body] quotes: the [selection] when [trim] is on and
/// the words are part of [body] (so a selection left in another message
/// never counts), else the whole of it.
String quoteSource(String body, String? selection, {required bool trim}) {
  final picked = selection?.trim() ?? '';
  if (!trim || picked.isEmpty) return body;
  String flat(String t) => t.replaceAll(_space, ' ').trim();
  return flat(body).contains(flat(picked)) ? picked : body;
}

/// [text] as quoted lines, each starting with "> ".
String quoteLines(String text) => text
    .replaceAll('\r\n', '\n')
    .trimRight()
    .split('\n')
    .map((line) => line.isEmpty ? '>' : '> $line')
    .join('\n');

/// The body of a reply: [text] above the [header] and its [quoted] lines,
/// or, with [below], under them.
String replyBody({
  required String text,
  required String header,
  required String quoted,
  required bool below,
}) => below ? '$header\n$quoted\n\n$text' : '$text\n\n$header\n$quoted';

/// Where the caret starts in a reply's [body]: under a quote that opens
/// it, else above the quote, after any words carried over.
int replyCaret(String body) {
  final lines = body.split('\n');
  if (lines.length > 1 &&
      lines.first.trimRight().endsWith(':') &&
      lines[1].startsWith('>')) {
    return body.length;
  }
  final i = body.indexOf('\n\n');
  return i > 0 ? i : 0;
}
