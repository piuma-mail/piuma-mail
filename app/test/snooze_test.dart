import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/snooze.dart';
import 'package:piuma_mail/l10n/app_localizations_en.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/date_time_picker.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  bool snoozed = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, snoozedMail: snoozed);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

/// Goldens draw real soft shadows, as the phone shows them.
Future<void> _softShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  test('the times are always ahead', () {
    expect(snoozeTime(SnoozeChoice.evening, _now), DateTime(2026, 10, 15, 18));
    expect(snoozeTime(SnoozeChoice.tomorrow, _now), DateTime(2026, 10, 16, 8));
    expect(snoozeTime(SnoozeChoice.weekend, _now), DateTime(2026, 10, 17, 9));
    expect(snoozeTime(SnoozeChoice.nextWeek, _now), DateTime(2026, 10, 19, 8));
    // On a Saturday the weekend is the next one, and on a Monday so is
    // next week.
    final saturday = DateTime(2026, 10, 17, 10);
    expect(
      snoozeTime(SnoozeChoice.weekend, saturday),
      DateTime(2026, 10, 24, 9),
    );
    expect(
      snoozeTime(SnoozeChoice.nextWeek, DateTime(2026, 10, 19, 7)),
      DateTime(2026, 10, 26, 8),
    );
    // The evening goes once it is close.
    expect(snoozeChoices(_now), SnoozeChoice.values);
    expect(
      snoozeChoices(DateTime(2026, 10, 15, 17, 5)),
      isNot(contains(SnoozeChoice.evening)),
    );
  });

  test('when it comes back reads plainly', () {
    final l = AppLocalizationsEn();
    expect(
      snoozeWhen(DateTime(2026, 10, 16, 8), _now, l, 'en'),
      'tomorrow, 08:00',
    );
    expect(
      snoozeWhen(DateTime(2026, 10, 15, 18), _now, l, 'en'),
      'today, 18:00',
    );
    expect(snoozeWhen(DateTime(2026, 10, 17, 9), _now, l, 'en'), 'Sat, 09:00');
    expect(
      snoozedRowTime(DateTime(2026, 10, 16, 9), _now, l, 'en'),
      'tomorrow 9:00',
    );
    expect(snoozedRowTime(DateTime(2026, 10, 19, 8), _now, l, 'en'), 'Mon');
    expect(snoozedRowTime(null, _now, l, 'en'), '');
  });

  testWidgets('snoozing from the reader, then back to the inbox', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Snooze'));
    await tester.pumpAndSettle();
    expect(find.text('Snooze until…'), findsOneWidget);
    expect(find.text('today 18:00'), findsOneWidget);
    expect(find.text('Fri 8:00'), findsOneWidget);
    expect(find.text('Sat 9:00'), findsOneWidget);
    expect(find.text('Mon 8:00'), findsOneWidget);

    await tester.tap(find.text('Tomorrow morning'));
    await tester.pumpAndSettle();
    expect(find.text('Snoozed until tomorrow, 08:00'), findsOneWidget);
    expect(_row('Dinner on Friday?'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.snoozes.single.$2, DateTime(2026, 10, 16, 8));

    // It waits in Snoozed, with when it comes back.
    await tester.tap(find.text('Snoozed'));
    await _settle(tester);
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.text('tomorrow 8:00'), findsOneWidget);

    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Back to inbox'));
    await tester.pumpAndSettle();
    expect(find.text('Back in the inbox'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.woken.single.subject, 'Dinner on Friday?');
    // Nothing is snoozed any more: Snoozed stays while it is open.
    await tester.tap(find.text('Unified inbox'));
    await _settle(tester);
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(find.text('Snoozed'), findsNothing);
  });

  testWidgets('Undo keeps it in the inbox', (tester) async {
    final source = await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next week'));
    await tester.pumpAndSettle();
    expect(find.text('Snoozed until Mon, 08:00'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
    expect(source.snoozes, isEmpty);
  });

  testWidgets('sent mail has no Snooze', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Sent'));
    await _settle(tester);
    await tester.tap(find.byType(InboxRowTile).first);
    await _settle(tester);
    expect(find.byTooltip('Snooze'), findsNothing);
  });

  testWidgets('on the phone a swipe to the left snoozes until tomorrow', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await tester.drag(_row('Dinner on Friday?'), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsNothing);
    expect(find.text('Snoozed until tomorrow, 08:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.snoozes.single.$2, DateTime(2026, 10, 16, 8));
  });

  testWidgets('on the phone the reader opens the sheet', (tester) async {
    final source = await _pump(tester, phone: true);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend'));
    await tester.pumpAndSettle();
    expect(find.text('Snoozed until Sat, 09:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.snoozes.single.$2, DateTime(2026, 10, 17, 9));
  });

  testWidgets('on the phone "If nobody replies" waits three days for one', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Snooze'));
    await tester.pumpAndSettle();
    expect(
      find.text('Comes back in 3 days if there’s no reply'),
      findsOneWidget,
    );
    await tester.tap(find.text('If nobody replies'));
    await tester.pumpAndSettle();
    expect(find.text('Snoozed until Sun, 08:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final (_, until, unlessReply) = source.snoozes.single;
    expect((until, unlessReply), (DateTime(2026, 10, 18, 8), true));
  });

  test('pick date & time: times typed and the first day', () {
    expect(parseTime('9'), (9, 0));
    expect(parseTime('9:30'), (9, 30));
    expect(parseTime('09.05'), (9, 5));
    expect(parseTime('1745'), (17, 45));
    expect(parseTime('24:00'), isNull);
    expect(parseTime('9:75'), isNull);
    expect(parseTime('soon'), isNull);
    // It starts at 9:00: today before then, else tomorrow.
    expect(pickFirstDay(DateTime(2026, 10, 15, 7)), DateTime(2026, 10, 15));
    expect(pickFirstDay(_now), DateTime(2026, 10, 16));
  });

  testWidgets('on the phone "Pick date & time" snoozes until any day', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick date & time'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    // Days gone by can't be picked.
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(find.text('Snooze until Fri, Oct 16, 9:00'), findsOneWidget);
    await tester.tap(find.text('23'));
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snooze until Fri, Oct 23, 18:00'));
    await tester.pumpAndSettle();
    expect(find.text('Snoozed until Oct 23, 18:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final (_, until, unlessReply) = source.snoozes.single;
    expect((until, unlessReply), (DateTime(2026, 10, 23, 18), false));
  });

  testWidgets('on the desktop a time can be typed, and Back goes back', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick date & time'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Snooze until…'), findsOneWidget);
    await tester.tap(find.text('Pick date & time'));
    await tester.pumpAndSettle();
    // 8:00 today is gone: nothing to snooze until.
    await tester.tap(find.bySemanticsLabel('Thursday, October 15'));
    await tester.tap(find.text('8:00'));
    await tester.pumpAndSettle();
    expect(find.text('That time has already gone by'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '7:45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.bySemanticsLabel('Friday, October 16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snooze until Fri, Oct 16, 7:45'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.snoozes.single.$2, DateTime(2026, 10, 16, 7, 45));
  });

  testWidgets('the desktop popover keeps to its four times', (tester) async {
    await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Snooze'));
    await tester.pumpAndSettle();
    expect(find.text('If nobody replies'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('snooze golden $name', (tester) async {
      await _pump(tester, dark: dark, snoozed: true);
      await tester.tap(_row('Dinner on Friday?'));
      await _settle(tester);
      await tester.tap(find.byTooltip('Snooze'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/snooze_popover_$name.png'),
      );
      await tester.tapAt(const Offset(5, 895));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snoozed'));
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/snoozed_list_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone snooze golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await tester.tap(_row('Dinner on Friday?'));
        await _settle(tester);
        await tester.tap(find.bySemanticsLabel('Snooze'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_snooze_$name.png'),
        );
        await tester.tap(find.text('Pick date & time'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('23'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_pick_date_time_$name.png'),
        );
      });
    }, tags: ['golden']);
  }
}
