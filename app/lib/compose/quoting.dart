import 'package:flutter/foundation.dart';

/// The words selected in the reader right now, for a reply that quotes
/// only them; null when nothing is selected.
final readerSelection = ValueNotifier<String?>(null);

final _space = RegExp(r'\s+');

/// What a reply to [body] quotes: the [selection] when [trim] is on and
/// the words are part of [body] (so a selection left in another message
/// never counts), else the whole of it.
String quoteSource(String body, String? selection, {required bool trim}) {
  final whole = withoutPlaceholders(body);
  final picked = withoutPlaceholders(selection ?? '').trim();
  if (!trim || picked.isEmpty) return whole;
  String flat(String t) => t.replaceAll(_space, ' ').trim();
  return flat(whole).contains(flat(picked)) ? picked : whole;
}

/// [text] without the object replacement character, which compose keeps
/// for its own pictures: some mailers (Apple Mail's plain text) leave it
/// where a picture was, and in a quote it would take a picture's place.
String withoutPlaceholders(String text) => text.replaceAll('\uFFFC', '');

/// [text] as quoted lines, each starting with "> ".
String quoteLines(String text) =>
    withoutPlaceholders(text)
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
