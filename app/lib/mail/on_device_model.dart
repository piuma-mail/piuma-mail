import 'dart:io';

import 'package:flutter/services.dart';

import 'readable.dart';

/// The system's own language model, where the device has one: Gemini Nano
/// through AICore on Android (`Model.kt`), Apple Intelligence on macOS and
/// iOS 26 (`OnDeviceModel.swift`). Nothing leaves the device, and where
/// there is no model "In short" keeps the rules' words.
class OnDeviceModel {
  OnDeviceModel._();

  static final instance = OnDeviceModel._();

  static const _channel = MethodChannel('mail.piuma/model');

  // The real system, not the one tests pretend to be.
  static bool get _on =>
      Platform.isAndroid || Platform.isMacOS || Platform.isIOS;

  /// "available" or "unavailable" for good; anything else (downloading,
  /// not enabled yet) is asked again next time.
  String? _status;

  final _rewritten = <int, ThreadBrief?>{};

  Future<bool> _ready() async {
    if (!_on) return false;
    if (_status case final s? when s == 'available' || s == 'unavailable') {
      return s == 'available';
    }
    try {
      _status = await _channel.invokeMethod<String>('status');
    } on MissingPluginException {
      _status = 'unavailable';
    } on PlatformException {
      return false;
    }
    return _status == 'available';
  }

  /// [brief] with points in the model's words; null when there is no model
  /// or its answer doesn't hold up (see [parse]).
  Future<ThreadBrief?> rewrite(ThreadBrief brief) async {
    if (brief.transcript.isEmpty || !await _ready()) return null;
    final key = Object.hash(brief.transcript, brief.points.join('\n'));
    if (_rewritten.containsKey(key)) return _rewritten[key];
    String? answer;
    try {
      answer = await _channel
          .invokeMethod<String>('generate', {'prompt': prompt(brief)})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Busy, out of quota or gone: the rules' words stay, and it is
      // tried again next time.
      return null;
    }
    final points = answer == null ? null : parse(answer, brief.transcript);
    final result = points == null
        ? null
        : ThreadBrief(
            points: points,
            yourTurn: brief.yourTurn,
            askedBy: brief.askedBy,
            transcript: brief.transcript,
            byModel: true,
          );
    if (_rewritten.length > 50) _rewritten.clear();
    _rewritten[key] = result;
    return result;
  }

  /// What the model is asked: the conversation, and the rules' points as
  /// what matters in it.
  static String prompt(ThreadBrief brief) =>
      '''
Summarize this email or conversation in at most 3 short bullet points of under 20 words each.
Cover requests, decisions, amounts and dates, and what is still open. Keep names, numbers, amounts and dates exactly as written. Add nothing that is not in the conversation.
Write in the same language as the conversation. Reply with the bullet points only, one per line, each starting with "- ".

Points that stand out:
${brief.points.map((p) => '- $p').join('\n')}

Conversation, oldest first:
${brief.transcript}''';

  static final _bullet = RegExp(r'^\s*(?:[-•*]|\d+[.)])\s*');
  static final _number = RegExp(r'\d+(?:[.,]\d+)*');

  /// The model's points, or null when its answer is empty, too long, or
  /// names a number the conversation doesn't: then the rules' stay.
  static List<String>? parse(String answer, String transcript) {
    final points = [
      for (final line in answer.split('\n'))
        if (line.trim().isNotEmpty)
          line.replaceFirst(_bullet, '').replaceAll('**', '').trim(),
    ].where((p) => p.isNotEmpty).toList();
    if (points.isEmpty || points.length > 3) return null;
    if (points.any((p) => p.length > 200)) return null;
    final known = _number.allMatches(transcript).map((m) => m[0]).toSet();
    // Only months named with a day count: "may" alone is mostly a verb.
    final months = _dated(transcript).toSet();
    final invented = points.any(
      (p) =>
          _number.allMatches(p).any((m) => !known.contains(m[0])) ||
          _dated(p).any((month) => !months.contains(month)),
    );
    return invented ? null : points;
  }

  static const _months =
      'january|february|march|april|may|june|july|august|september|'
      'october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|'
      'nov|dec|gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|'
      'settembre|ottobre|novembre|dicembre|gen|giu|lug|ago|set|ott|dic';
  static final _datedMonth = RegExp(
    '\\b($_months)\\.?\\s+\\d|\\d(?:st|nd|rd|th)?\\s+(?:of\\s+)?($_months)\\b',
  );

  /// The months a point names next to a day ("May 7th", "7 maggio"): a
  /// date moved to another month has numbers the conversation has, so
  /// its month must be there too.
  static Iterable<String> _dated(String point) =>
      _datedMonth.allMatches(point.toLowerCase()).map((m) => (m[1] ?? m[2])!);
}
