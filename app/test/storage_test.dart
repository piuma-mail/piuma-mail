import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/updating.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool backup = false,
  bool noRoom = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, backup: backup, noRoom: noRoom);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (phone) {
    await tester.scrollUntilVisible(
      find.text('Storage'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Storage'));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('Settings › Storage shows the room each account takes', (
    tester,
  ) async {
    final source = await _settings(tester);
    expect(find.byType(StoragePage), findsOneWidget);
    final use = await source.storage();
    expect(use.accounts, isNotEmpty);
    expect(find.textContaining(RegExp(r'B on this device$')), findsOneWidget);
    expect(
      find.textContaining('kept for reading offline'),
      findsNWidgets(use.accounts.length),
    );
    // Three months is the default.
    expect(use.keepDays, 90);
    await tester.tap(find.text('1 year'));
    await tester.pumpAndSettle();
    expect((await source.storage()).keepDays, 365);
    await tester.tap(find.text('Always'));
    await tester.pumpAndSettle();
    expect((await source.storage()).keepDays, isNull);
  });

  testWidgets('Clearing an account\'s cached mail asks first', (tester) async {
    final source = await _settings(tester);
    final first = source.accounts.first;
    await tester.tap(find.text('Clear cached mail').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Clear the cached mail of ${first.name}?'),
      findsOneWidget,
    );
    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      (await source.storage()).accounts
          .firstWhere((a) => a.accountId == first.id)
          .cachedBytes,
      greaterThan(0),
    );
    await tester.tap(find.text('Clear cached mail').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear cached mail').last);
    await tester.pumpAndSettle();
    expect(
      (await source.storage()).accounts
          .firstWhere((a) => a.accountId == first.id)
          .cachedBytes,
      0,
    );
    expect(find.textContaining('0 B kept for reading offline'), findsOneWidget);
  });

  testWidgets('The copy kept from before an update is counted', (tester) async {
    await _settings(tester, backup: true);
    expect(
      find.textContaining('kept from before the last update'),
      findsOneWidget,
    );
  });

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';
    testWidgets('$where: no room to shrink the file is said, not hidden', (
      tester,
    ) async {
      final source = await _settings(tester, phone: phone, noRoom: true);
      await tester.tap(find.text('Clear cached mail').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear cached mail').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Cached mail cleared.'), findsOneWidget);
      // The cache went all the same, and the page shows it.
      expect((await source.storage()).accounts.first.cachedBytes, 0);
      expect(find.text('Clearing…'), findsNothing);
    });

    testWidgets('$where: the page says search still finds old mail', (
      tester,
    ) async {
      await _settings(tester, phone: phone);
      expect(
        find.textContaining('Search still finds their words'),
        findsOneWidget,
      );
    });

    for (final dark in [false, true]) {
      final name = '${where}_${dark ? 'dark' : 'light'}';
      testWidgets('storage_$name golden', (tester) async {
        await _settings(tester, phone: phone, dark: dark, backup: true);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/storage_$name.png'),
        );
      }, tags: ['golden']);

      testWidgets('storage_clear_$name golden', (tester) async {
        await _settings(tester, phone: phone, dark: dark);
        await tester.tap(find.text('Clear cached mail').first);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/storage_clear_$name.png'),
        );
      }, tags: ['golden']);

      testWidgets('updating_$name golden', (tester) async {
        tester.view.physicalSize = phone
            ? const Size(390, 844)
            : const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          PiumaApp(initialDark: dark, home: (_, _) => const UpdatingMail()),
        );
        // The bar keeps moving: one frame, not settled.
        await tester.pump(const Duration(milliseconds: 300));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/updating_$name.png'),
        );
      }, tags: ['golden']);
    }
  }

  testWidgets('Updating your mail says what is going on', (tester) async {
    await tester.pumpWidget(PiumaApp(home: (_, _) => const UpdatingMail()));
    await tester.pump();
    expect(find.text('Updating your mail'), findsOneWidget);
    expect(find.textContaining('It only happens once'), findsOneWidget);
  });
}
