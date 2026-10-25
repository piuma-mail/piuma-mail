import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/api/engine.dart' as engine;
import 'readable.dart';

/// Whether a language pair can be translated on this device.
enum PairStatus {
  /// Ready: translating starts at once.
  ready,

  /// Supported, but the languages are downloaded first (once).
  download,

  /// Not on this device.
  unsupported,
}

/// What translates on this device. Nothing leaves it: Apple's own
/// translation on Mac, iPad and iPhone (`Translate.swift`), Firefox's
/// open-source models elsewhere.
abstract class TranslateEngine {
  const TranslateEngine();

  Future<PairStatus> status(String from, String to);

  /// About how many bytes the first translation of a pair downloads, for
  /// "Getting German–Italian · 28 MB"; null when the system shows its own.
  Future<int?> downloadSize(String from, String to) async => null;

  /// The language pairs downloaded on this device, for Settings.
  Future<List<DownloadedPair>> downloaded() async => const [];

  /// Deletes a downloaded pair; it downloads again when used.
  Future<void> remove(DownloadedPair pair) async {}

  /// [texts] in [to], one for one. [progress] hears of a download, 0 to 1.
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  });
}

/// The pair's languages were not downloaded (the system's sheet was
/// closed without downloading).
class TranslateNeedsDownload implements Exception {
  const TranslateNeedsDownload();
}

/// A language pair downloaded for translation: "de-en", 24 MB.
class DownloadedPair {
  const DownloadedPair(this.from, this.to, this.bytes);

  final String from;
  final String to;
  final int bytes;

  @override
  bool operator ==(Object other) =>
      other is DownloadedPair && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The device's translation, swapped in tests.
class Translator {
  Translator._();

  static TranslateEngine engine = _platform();

  /// Translate is offered on this device at all (Settings › Appearance
  /// shows "Translate into").
  static bool get offered => engine is! NoTranslation;

  /// The languages the engine finds (`core/src/language.rs`), as
  /// two-letter codes.
  static const languages = [
    'ar', 'bg', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'et', 'fi', 'fr', //
    'he', 'hi', 'hr', 'hu', 'id', 'it', 'ja', 'ko', 'lt', 'lv', 'nb', 'nl', //
    'pl', 'pt', 'ro', 'ru', 'sk', 'sl', 'sr', 'sv', 'th', 'tr', 'uk', 'vi', //
    'zh',
  ];

  static TranslateEngine _platform() {
    if (kIsWeb) return const NoTranslation();
    if (Platform.isMacOS || Platform.isIOS) return const AppleTranslation();
    // Tests swap in their own; the engine isn't there.
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return const NoTranslation();
    }
    return MozillaTranslation();
  }

  /// The two-letter code of [locale]'s language ("pt-BR" → "pt").
  static String languageOf(String locale) =>
      locale.split(RegExp('[-_]')).first.toLowerCase();

  static final _address = RegExp(
    r'(?:https?://|www\.)[^\s<>"]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+',
    caseSensitive: false,
  );

  /// [translated] with the email addresses and links of [original] put
  /// back as they were: a translator may turn "info@sportfits.de" into
  /// "Info@sportfits.it". Left as it is when it lost or gained some.
  static String keepAddresses(String original, String translated) {
    final was = [for (final m in _address.allMatches(original)) m[0]!];
    if (was.isEmpty) return translated;
    if (_address.allMatches(translated).length != was.length) {
      return translated;
    }
    var i = 0;
    return translated.replaceAllMapped(_address, (_) => was[i++]);
  }

  /// [r] with its words in [to], laid out as before: each block keeps its
  /// kind, quote and marker; a block that was all bold, italic or one link
  /// stays so. Code, pictures and rules are left alone, and days found in
  /// the original are dropped, as their places in the text are gone.
  /// [subject] goes in the same pass and comes back with it.
  static Future<(Readable, String?)> readable(
    Readable r, {
    required String from,
    required String to,
    String? subject,
    TranslateEngine? using,
    ValueChanged<double>? progress,
  }) async {
    final indexes = <int>[];
    final texts = <String>[];
    for (final (i, b) in r.blocks.indexed) {
      if (b.kind == BlockKind.code || b.kind == BlockKind.image) continue;
      final text = b.text.trim();
      if (text.isEmpty || !text.contains(RegExp(r'\p{L}', unicode: true))) {
        continue;
      }
      indexes.add(i);
      texts.add(text);
    }
    final title = subject?.trim() ?? '';
    final hasTitle = title.contains(RegExp(r'\p{L}', unicode: true));
    if (texts.isEmpty && !hasTitle) return (r.copyWith(dates: const []), null);
    final all = await (using ?? engine).translate(
      [if (hasTitle) title, ...texts],
      from: from,
      to: to,
      progress: progress,
    );
    final String? translatedSubject;
    final List<String> out;
    if (hasTitle && all.isNotEmpty) {
      translatedSubject = keepAddresses(title, all.first);
      out = all.sublist(1);
    } else {
      translatedSubject = null;
      out = all;
    }
    if (out.length != texts.length) {
      throw StateError('Translation lost some text');
    }
    final blocks = [...r.blocks];
    for (final (n, i) in indexes.indexed) {
      final b = blocks[i];
      final spans = b.spans;
      bool all(bool Function(BodySpan s) test) =>
          spans.where((s) => s.text.trim().isNotEmpty).every(test);
      final link = spans.length == 1 ? spans.first.link : null;
      blocks[i] = BodyBlock(
        kind: b.kind,
        level: b.level,
        quote: b.quote,
        marker: b.marker,
        spans: [
          BodySpan(
            keepAddresses(texts[n], out[n]),
            bold: all((s) => s.bold),
            italic: all((s) => s.italic),
            link: link,
            suspicious: link != null && spans.first.suspicious,
          ),
        ],
      );
    }
    return (r.copyWith(blocks: blocks, dates: const []), translatedSubject);
  }
}

/// No translation on this device (yet): no pill is shown.
class NoTranslation extends TranslateEngine {
  const NoTranslation();

  @override
  Future<PairStatus> status(String from, String to) async =>
      PairStatus.unsupported;

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  }) => throw UnsupportedError('No translation on this device');
}

/// Apple's Translation framework (macOS 15, iOS 18 and later). The system
/// downloads a missing language itself, asking first.
class AppleTranslation extends TranslateEngine {
  const AppleTranslation();

  static const _channel = MethodChannel('mail.piuma/translate');

  @override
  Future<PairStatus> status(String from, String to) async {
    try {
      final s = await _channel.invokeMethod<String>('status', {
        'from': from,
        'to': to,
      });
      return switch (s) {
        'installed' => PairStatus.ready,
        'supported' => PairStatus.download,
        _ => PairStatus.unsupported,
      };
    } on MissingPluginException {
      return PairStatus.unsupported;
    } on PlatformException {
      return PairStatus.unsupported;
    }
  }

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  }) async {
    try {
      final out = await _channel.invokeListMethod<String>('translate', {
        'from': from,
        'to': to,
        'texts': texts,
      });
      return out ?? const [];
    } on PlatformException catch (e) {
      if (e.code == 'download') throw const TranslateNeedsDownload();
      rethrow;
    }
  }
}

/// Firefox's open translation models, run by the engine
/// (`core/src/translate.rs`) on Windows, Linux and Android. A pair is
/// downloaded once, the first time it is used.
class MozillaTranslation extends TranslateEngine {
  MozillaTranslation();

  StreamSubscription<double>? _watch;
  ValueChanged<double>? _progress;

  @override
  Future<PairStatus> status(String from, String to) async {
    try {
      return switch (await engine.translateStatus(from: from, to: to)) {
        'installed' => PairStatus.ready,
        'supported' => PairStatus.download,
        _ => PairStatus.unsupported,
      };
    } catch (_) {
      return PairStatus.unsupported;
    }
  }

  @override
  Future<int?> downloadSize(String from, String to) async {
    try {
      return (await engine.translateDownloadSize(from: from, to: to))?.toInt();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DownloadedPair>> downloaded() async {
    try {
      return [
        for (final p in await engine.translatePairs())
          if (p.name.split('-') case [final from, final to])
            DownloadedPair(from, to, p.bytes.toInt()),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> remove(DownloadedPair pair) =>
      engine.removeTranslatePair(name: '${pair.from}-${pair.to}');

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  }) async {
    _watch ??= engine.watchTranslateProgress().listen(
      (p) => _progress?.call(p),
    );
    _progress = progress;
    try {
      return await engine.translateTexts(texts: texts, from: from, to: to);
    } finally {
      _progress = null;
    }
  }
}
