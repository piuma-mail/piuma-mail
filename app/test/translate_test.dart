import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/design/look.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/translate_parts.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/readable.dart';
import 'package:piuma_mail/mail/translator.dart';
import 'package:piuma_mail/main.dart';

import 'support/settle.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

/// Klaus Weber's email, in English, as a device would translate it.
const _english = {
  'Hallo Matteo,': 'Hi Matteo,',
  'die Lampen für das Studio kommen nächste Woche. Passt dir Dienstag um 10 '
          'Uhr? Ich bringe auch die Muster für den Flur mit.':
      'the lamps for the studio arrive next week. Does Tuesday at 10 work '
      'for you? I’ll also bring the samples for the hallway.',
  'Viele Grüße,\nKlaus': 'Best regards,\nKlaus',
  DemoMailSource.foreignSubject: 'Delivery next week',
};

class _Engine extends TranslateEngine {
  PairStatus pair = PairStatus.ready;
  final asked = <String>[];
  final translated = <List<String>>[];
  bool skipDownload = false;

  /// Holds the translation back, after the download, until completed.
  Completer<void>? hold;

  @override
  Future<PairStatus> status(String from, String to) async {
    asked.add('$from>$to');
    return pair;
  }

  @override
  Future<int?> downloadSize(String from, String to) async => 28 * 1000 * 1000;

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  }) async {
    if (skipDownload) throw const TranslateNeedsDownload();
    if (hold case final h?) {
      progress?.call(1);
      progress?.call(-1);
      await h.future;
    }
    translated.add(texts);
    return [for (final t in texts) _english[t] ?? t];
  }
}

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  Appearance appearance = const Appearance(),
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, foreign: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      appearance: appearance,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text(DemoMailSource.foreignSubject),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  late _Engine engine;
  setUp(() => Translator.engine = engine = _Engine());
  tearDown(() => Translator.engine = const NoTranslation());

  test('addresses and links come back as they were', () {
    expect(
      Translator.keepAddresses(
        'Schreib an info@sportfits.de oder https://sportfits.de/hilfe.',
        'Scrivi a Info@sportfits.it o https://sportfits.it/aiuto.',
      ),
      'Scrivi a info@sportfits.de o https://sportfits.de/hilfe.',
    );
    expect(
      Translator.keepAddresses('Mail info@a.de', 'Scrivi una mail'),
      'Scrivi una mail',
      reason: 'lost on the way: left as it is',
    );
  });

  testWidgets('a German email offers Translate, then Show original', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);
    expect(engine.asked, isNotEmpty);
    expect(engine.asked, everyElement('de>en'));
    expect(find.text('Written in German'), findsOneWidget);
    expect(engine.translated, isEmpty, reason: 'never automatic');

    await tester.tap(find.byType(TranslatePill));
    await _settle(tester);
    expect(
      find.text('Translated from German · on this device'),
      findsOneWidget,
    );
    expect(find.textContaining('the lamps for the studio'), findsOneWidget);
    expect(find.textContaining('Passt dir Dienstag'), findsNothing);
    expect(find.byType(TranslatePill), findsNothing);
    expect(
      find.text('Delivery next week'),
      findsOneWidget,
      reason: 'the subject is translated too',
    );

    await tester.tap(find.text('Show original'));
    await _settle(tester);
    expect(find.textContaining('Passt dir Dienstag'), findsOneWidget);
    expect(find.text('Delivery next week'), findsNothing);
    expect(find.byType(TranslatePill), findsOneWidget);
  });

  testWidgets('once downloaded, the pill says Translating', (tester) async {
    final hold = Completer<void>();
    engine
      ..pair = PairStatus.download
      ..hold = hold;
    await _pump(tester);
    await _open(tester);
    await tester.tap(find.byType(TranslatePill));
    await tester.pump();
    await tester.pump();
    expect(find.text('Translating…'), findsOneWidget);
    expect(find.textContaining('Getting German'), findsNothing);
    hold.complete();
    await _settle(tester);
    expect(find.textContaining('the lamps for the studio'), findsOneWidget);
  });

  testWidgets('closing the download without downloading says so', (
    tester,
  ) async {
    engine
      ..pair = PairStatus.download
      ..skipDownload = true;
    await _pump(tester);
    await _open(tester);
    await tester.tap(find.byType(TranslatePill));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('To translate, download German and English first.'),
      findsOneWidget,
    );
    expect(find.byType(TranslatePill), findsOneWidget);
  });

  testWidgets('no pill where the pair is not on this device', (tester) async {
    engine.pair = PairStatus.unsupported;
    await _pump(tester);
    await _open(tester);
    expect(find.byType(TranslatePill), findsNothing);
  });

  testWidgets('no pill for an email already in the target language', (
    tester,
  ) async {
    await _pump(tester, appearance: const Appearance(translateInto: 'de'));
    await _open(tester);
    expect(engine.asked, isEmpty);
    expect(find.byType(TranslatePill), findsNothing);
  });

  test('a translation keeps the layout and drops found days', () async {
    const r = Readable(
      blocks: [
        BodyBlock(
          kind: BlockKind.heading,
          level: 1,
          spans: [BodySpan('Hallo Matteo,', bold: true)],
        ),
        BodyBlock(kind: BlockKind.code, spans: [BodySpan('ls -la')]),
        BodyBlock(kind: BlockKind.rule),
        BodyBlock(
          kind: BlockKind.listItem,
          marker: '•',
          spans: [BodySpan('Viele Grüße,\nKlaus', link: 'https://x.example')],
        ),
      ],
      language: 'de',
      dates: [],
    );
    final (t, subject) = await Translator.readable(
      r,
      from: 'de',
      to: 'en',
      using: _Engine(),
    );
    expect(t.blocks.map((b) => b.text), [
      'Hi Matteo,',
      'ls -la',
      '',
      'Best regards,\nKlaus',
    ]);
    expect(t.blocks[0].kind, BlockKind.heading);
    expect(t.blocks[0].spans.single.bold, isTrue);
    expect(t.blocks[3].marker, '•');
    expect(t.blocks[3].spans.single.link, 'https://x.example');
    expect(t.language, 'de');
    expect(subject, isNull, reason: 'none asked for');
  });

  group('goldens', () {
    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('reader with Translate, $name', (tester) async {
        await _pump(tester, dark: dark);
        await _open(tester);
        await expectLater(
          find.byType(InboxScreen),
          matchesGoldenFile('goldens/translate_offer_$name.png'),
        );
        await tester.tap(find.byType(TranslatePill));
        await _settle(tester);
        await expectLater(
          find.byType(InboxScreen),
          matchesGoldenFile('goldens/translate_done_$name.png'),
        );
      });
      testWidgets('phone reader with Translate, $name', (tester) async {
        await _pump(tester, dark: dark, phone: true);
        await _open(tester);
        await expectLater(
          find.byType(InboxScreen),
          matchesGoldenFile('goldens/phone_translate_offer_$name.png'),
        );
        await tester.tap(find.byType(TranslatePill));
        await _settle(tester);
        await expectLater(
          find.byType(InboxScreen),
          matchesGoldenFile('goldens/phone_translate_done_$name.png'),
        );
      });
    }
    testWidgets('first time for a pair: Getting German–English', (
      tester,
    ) async {
      engine.pair = PairStatus.download;
      await _pump(tester);
      await _open(tester);
      expect(find.text('Written in German'), findsOneWidget);
      await tester.pumpWidget(
        PiumaApp(
          home: (_, _) => Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const Key('pill'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TranslatePill(
                    from: 'de',
                    to: 'en',
                    busy: true,
                    download: true,
                    bytes: 28 * 1000 * 1000,
                    progress: .4,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.settleBesideWaves();
      expect(find.text('Getting German–English · 28 MB'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('pill')),
        matchesGoldenFile('goldens/translate_getting_light.png'),
      );
    });
  });
}
