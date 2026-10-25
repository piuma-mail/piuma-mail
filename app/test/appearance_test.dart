import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/look.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/translator.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The app with Settings › Appearance kept in [saved].
Future<void> _pump(
  WidgetTester tester, {
  bool phone = false,
  Appearance appearance = const Appearance(theme: ThemeChoice.light),
  List<Appearance>? saved,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      appearance: appearance,
      onAppearance: saved?.add,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

Future<void> _openDesktop(
  WidgetTester tester, [
  String section = 'Appearance',
]) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(section));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _openPhone(WidgetTester tester, String row) async {
  await tester.tap(find.bySemanticsLabel('3 accounts, accounts and Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings').last);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(row));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Brightness _brightness(WidgetTester tester) =>
    Theme.of(tester.element(find.text('Theme'))).brightness;

void main() {
  testWidgets('the theme is kept', (tester) async {
    final saved = <Appearance>[];
    await _pump(tester, saved: saved);
    await _openDesktop(tester);
    expect(find.text('How you want your mail to look.'), findsOneWidget);
    expect(_brightness(tester), Brightness.light);

    await tester.tap(find.bySemanticsLabel('Dark'));
    await tester.pumpAndSettle();
    expect(_brightness(tester), Brightness.dark);
    expect(saved.last.theme, ThemeChoice.dark);

    await tester.tap(find.bySemanticsLabel('Automatic'));
    await tester.pumpAndSettle();
    // The test window is light.
    expect(_brightness(tester), Brightness.light);
    expect(saved.last.theme, ThemeChoice.automatic);
  });

  testWidgets('Reading keeps the density and the preview lines', (
    tester,
  ) async {
    final saved = <Appearance>[];
    await _pump(tester, saved: saved);
    await _openDesktop(tester, 'Reading');
    expect(
      find.text('How the list looks, and what helps you read.'),
      findsOneWidget,
    );

    // The example rows follow Density and Preview.
    final example = find.byType(InboxRowTile);
    expect(example, findsNWidgets(2));
    final tall = tester.getSize(example.first).height;
    await tester.tap(find.bySemanticsLabel('Compact'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('1 line'));
    await tester.pumpAndSettle();
    expect(
      saved.last,
      const Appearance(
        theme: ThemeChoice.light,
        compact: true,
        previewLines: 1,
      ),
    );
    expect(tester.getSize(example.first).height, lessThan(tall));
  });

  testWidgets('compact rows with one line of preview in the inbox', (
    tester,
  ) async {
    await _pump(
      tester,
      appearance: const Appearance(
        theme: ThemeChoice.light,
        compact: true,
        previewLines: 1,
      ),
    );
    final rows = find.byType(InboxRowTile);
    expect(rows, findsWidgets);
    // The first row, Giulia's dinner, has the Invite chip.
    expect(
      tester.getSize(rows.first).height,
      rowExtent(const Appearance(compact: true, previewLines: 1), chip: true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('on the phone, Appearance is in the list with its theme', (
    tester,
  ) async {
    final saved = <Appearance>[];
    await _pump(tester, phone: true, saved: saved);
    await _openPhone(tester, 'Appearance, Light');
    expect(find.text('Theme'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Dark'));
    await tester.pumpAndSettle();
    expect(saved.last.theme, ThemeChoice.dark);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Appearance, Dark'), findsOneWidget);
  });

  testWidgets('the language follows the device until one is picked', (
    tester,
  ) async {
    final saved = <Appearance>[];
    await _pump(tester, saved: saved);
    await _openDesktop(tester);
    expect(find.text('Device language'), findsOneWidget);

    await tester.tap(find.text('Device language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Italiano').last);
    await tester.pumpAndSettle();
    expect(saved.last.language, 'it');
    expect(find.text('Come vuoi vedere la tua posta.'), findsOneWidget);

    await tester.tap(find.text('Italiano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lingua del dispositivo').last);
    await tester.pumpAndSettle();
    expect(saved.last.language, isNull);
    expect(find.text('How you want your mail to look.'), findsOneWidget);
  });

  test('the app speaks the device language, else English', () {
    expect(appLocale(null, const [Locale('de', 'AT')]), const Locale('de'));
    expect(
      appLocale(null, const [Locale('pl'), Locale('fr', 'CA')]),
      const Locale('fr'),
    );
    expect(appLocale(null, const [Locale('ja')]), const Locale('en'));
    expect(appLocale('pt', const [Locale('it')]), const Locale('pt'));
    expect(appLocale('xx', const [Locale('es')]), const Locale('es'));
  });

  for (final code in appLanguages.keys) {
    testWidgets('inbox and Appearance draw in $code', (tester) async {
      final l = lookupAppLocalizations(Locale(code));
      await _pump(tester, appearance: Appearance(language: code));
      expect(find.text(l.settings), findsWidgets);
      await tester.tap(find.text(l.settings).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.appearanceTitle).first);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(l.appearanceSubtitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    final theme = dark ? ThemeChoice.dark : ThemeChoice.light;
    testWidgets('appearance golden $name', (tester) async {
      await _pump(tester, appearance: Appearance(theme: theme));
      await _openDesktop(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_appearance_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone appearance golden $name', (tester) async {
      await _pump(tester, phone: true, appearance: Appearance(theme: theme));
      await _openPhone(tester, 'Appearance, ${dark ? 'Dark' : 'Light'}');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_appearance_$name.png'),
      );
    }, tags: ['golden']);
  }

  group('where the device translates', () {
    setUp(() => Translator.engine = const AppleTranslation());
    tearDown(() => Translator.engine = const NoTranslation());

    testWidgets('Translate into is kept', (tester) async {
      final saved = <Appearance>[];
      await _pump(tester, saved: saved);
      await _openDesktop(tester, 'Reading');
      await tester.ensureVisible(find.text('App language'));
      await tester.pumpAndSettle();
      expect(find.text('Translate into'), findsOneWidget);
      expect(find.text('App language'), findsOneWidget);
      await tester.tap(find.text('App language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catalan').last);
      await tester.pumpAndSettle();
      expect(saved.last.translateInto, 'ca');
      expect(find.text('Catalan'), findsOneWidget);
    });

    testWidgets('reading with Translate into golden', (tester) async {
      await _pump(tester);
      await _openDesktop(tester, 'Reading');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_reading_translate_light.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone reading with Translate into golden', (tester) async {
      await _pump(tester, phone: true);
      await _openPhone(tester, 'Reading, Comfortable');
      await tester.ensureVisible(find.text('App language'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_reading_translate_light.png'),
      );
    }, tags: ['golden']);
  });

  group('with Firefox\'s models downloaded', () {
    late _Pairs pairs;
    setUp(() => Translator.engine = pairs = _Pairs());
    tearDown(() => Translator.engine = const NoTranslation());

    testWidgets('a downloaded pair can be removed', (tester) async {
      await _pump(tester);
      await _openDesktop(tester, 'Reading');
      expect(find.text('German → English'), findsOneWidget);
      expect(find.text('English → Italian'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove').first);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      expect(pairs.removed, [const DownloadedPair('de', 'en', 0)]);
      expect(find.text('German → English'), findsNothing);
      expect(find.text('English → Italian'), findsOneWidget);
    });

    testWidgets('reading with downloaded pairs golden', (tester) async {
      await _pump(tester);
      await _openDesktop(tester, 'Reading');
      await tester.ensureVisible(find.text('German → English'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_reading_pairs_light.png'),
      );
    }, tags: ['golden']);
  });

  testWidgets('compact inbox golden', (tester) async {
    await _pump(
      tester,
      appearance: const Appearance(
        theme: ThemeChoice.light,
        compact: true,
        previewLines: 1,
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/inbox_compact_light.png'),
    );
  }, tags: ['golden']);
}

/// Firefox's models, with two pairs downloaded.
class _Pairs extends TranslateEngine {
  final removed = <DownloadedPair>[];
  var _pairs = const [
    DownloadedPair('de', 'en', 23917889),
    DownloadedPair('en', 'it', 21480112),
  ];

  @override
  Future<PairStatus> status(String from, String to) async => PairStatus.ready;

  @override
  Future<List<DownloadedPair>> downloaded() async => _pairs;

  @override
  Future<void> remove(DownloadedPair pair) async {
    removed.add(pair);
    _pairs = [..._pairs]..remove(pair);
  }

  @override
  Future<List<String>> translate(
    List<String> texts, {
    required String from,
    required String to,
    ValueChanged<double>? progress,
  }) async => texts;
}
