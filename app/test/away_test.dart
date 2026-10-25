import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/inbox/away_line.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/account_page.dart';
import 'package:piuma_mail/settings/away_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/date_time_picker.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// A Wednesday, as on `RemindAwayPrintToApprove`, before the time away.
final _before = DateTime(2026, 10, 21, 10, 30);

/// The Wednesday after, while away.
final _away = DateTime(2026, 10, 28, 9, 15);

const _work = 2;

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool on = false,
  String account = 'Work',
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = source ?? DemoMailSource(now: _before, away: on);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: s,
        onBack: () {},
        onAddAccount: () {},
        now: () => _before,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(account));
  await tester.pumpAndSettle();
  return s;
}

Future<void> _openAway(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AccountPage),
      matching: find.text('Away message'),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AwayPage), findsOneWidget);
}

Finder _awayField(int i) => find
    .descendant(of: find.byType(AwayPage), matching: find.byType(TextField))
    .at(i);

Future<DemoMailSource> _inbox(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  DateTime? now,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final at = now ?? _away;
  final source = DemoMailSource(now: at, away: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => at),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

/// Lets the page's pending change go, and the page itself.
Future<void> _leave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';

    testWidgets('$where: the row shows only where the server takes it', (
      tester,
    ) async {
      final source = await _settings(tester, phone: phone);
      expect(
        find.descendant(
          of: find.byType(AccountPage),
          matching: find.text('Away message'),
        ),
        findsOneWidget,
      );
      expect(find.text('Off'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _settings(tester, phone: phone, account: 'iCloud', source: source);
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.text('Away message'), findsNothing);
      await _leave(tester);
    });

    testWidgets('$where: turning it on sends it to the server', (tester) async {
      final source = await _settings(tester, phone: phone);
      await _openAway(tester);
      // Made for the person until they write their own.
      expect(find.text('Away'), findsOneWidget);
      expect(
        find.text("Hi, I'm away and will reply when I'm back."),
        findsOneWidget,
      );
      await tester.tap(find.byType(PiumaSwitch));
      await tester.pumpAndSettle();
      expect(source.awaySets.last.$1, _work);
      expect(source.awaySets.last.$2.on, isTrue);
      expect(source.awaySets.last.$2.subject, 'Away');

      // The last day writes the subject and message, back the day after.
      await tester.tap(find.text('No end'));
      await tester.pumpAndSettle();
      expect(find.byType(PickDay), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(PickDay), matching: find.text('30')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fri 30 Oct'), findsOneWidget);
      expect(find.text('Away until 31 October'), findsOneWidget);
      expect(source.awaySets.last.$2.end, DateTime(2026, 10, 30));
      expect(source.awaySets.last.$2.subject, 'Away until 31 October');
      expect(
        source.awaySets.last.$2.body,
        "Hi, I'm away until Saturday 31 October and will reply when I'm back.",
      );

      // What the person writes stays theirs.
      await tester.enterText(_awayField(0), 'Out of the studio');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(source.awaySets.last.$2.subject, 'Out of the studio');

      // Back to the account: the row says until when.
      if (phone) {
        await tester.tap(find.text('Work').first);
      } else {
        await tester.tap(
          find.descendant(
            of: find.byType(AwayPage),
            matching: find.text('Work'),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.text('On until Fri 30 Oct'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('$where: beside the person\'s own filters it stays off', (
      tester,
    ) async {
      final source = DemoMailSource(now: _before)..awayFilters.add(_work);
      await _settings(tester, phone: phone, source: source);
      await _openAway(tester);
      await tester.tap(find.byType(PiumaSwitch));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Can't turn on alongside your existing filters. "
          'Turn them off on the server first.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<PiumaSwitch>(find.byType(PiumaSwitch)).value,
        isFalse,
      );
      await _leave(tester);
    });
  }

  testWidgets('"Keep it on" clears the last day', (tester) async {
    final source = await _settings(tester, on: true);
    await _openAway(tester);
    expect(find.text('Tue 27 Oct'), findsOneWidget);
    expect(find.text('Mon 2 Nov'), findsOneWidget);
    await tester.tap(find.text('Mon 2 Nov'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it on until I turn it off'));
    await tester.pumpAndSettle();
    expect(find.text('No end'), findsOneWidget);
    expect(source.awaySets.last.$2.end, isNull);
    // The subject was the person's: it stays.
    expect(find.text('Away until 3 November'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('the inbox says it is on, and Turn off turns it off', (
    tester,
  ) async {
    final source = await _inbox(tester);
    expect(find.byType(AwayLineView), findsOneWidget);
    expect(
      find.text('Away message on for Work until Mon 2 Nov'),
      findsOneWidget,
    );
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.byType(AwayLineView), findsNothing);
    expect(source.awaySets.last.$1, _work);
    expect(source.awaySets.last.$2.on, isFalse);
  });

  testWidgets('before the first day the inbox says nothing', (tester) async {
    await _inbox(tester, now: _before);
    expect(find.byType(AwayLineView), findsNothing);
  });

  testWidgets('another account\'s inbox has no line', (tester) async {
    await _inbox(tester);
    await tester.tap(find.text('Personal').first);
    await tester.pumpAndSettle();
    expect(find.byType(AwayLineView), findsNothing);
    await tester.tap(find.text('Work').first);
    await tester.pumpAndSettle();
    expect(find.byType(AwayLineView), findsOneWidget);
  });

  testWidgets('phone: the line sits at the top of the inbox', (tester) async {
    await _inbox(tester, phone: true);
    expect(
      find.text('Away message on for Work until Mon 2 Nov'),
      findsOneWidget,
    );
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('away settings golden $name', (tester) async {
      await _settings(tester, dark: dark, on: true);
      await _openAway(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/away_settings_$name.png'),
      );
      await _leave(tester);
    }, tags: ['golden']);

    testWidgets('phone away settings golden $name', (tester) async {
      await _settings(tester, dark: dark, on: true, phone: true);
      await _openAway(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_away_settings_$name.png'),
      );
      await _leave(tester);
    }, tags: ['golden']);

    testWidgets('inbox away golden $name', (tester) async {
      await _inbox(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/inbox_away_$name.png'),
      );
    }, tags: ['golden']);
  }
}
