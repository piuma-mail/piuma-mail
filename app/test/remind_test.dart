import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/remind_me.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/l10n/app_localizations_en.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

/// A Wednesday morning, as on `RemindAwayPrintToApprove`.
final _now = DateTime(2026, 10, 21, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  bool reminded = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, waiting: true, reminded: reminded);
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

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

Future<void> _write(WidgetTester tester, {bool phone = false}) async {
  if (phone) {
    await tester.tap(find.bySemanticsLabel('Compose a message'));
  } else {
    await tester.tap(find.text('Compose'));
  }
  await tester.pumpAndSettle();
  await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>,');
  await tester.enterText(_field(1), 'Quote for the Acme site');
  await tester.enterText(_field(2), 'Hi Luca, here is the quote.');
  await tester.pumpAndSettle();
}

Finder _chip(String label) =>
    find.descendant(of: find.byType(RemindChip), matching: find.text(label));

Future<void> _openWaiting(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(Sidebar), matching: find.text('Waiting')),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

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

  test('the times are at 8:00, always ahead', () {
    expect(remindTime(RemindChoice.tomorrow, _now), DateTime(2026, 10, 22, 8));
    expect(
      remindTime(RemindChoice.inThreeDays, _now),
      DateTime(2026, 10, 24, 8),
    );
    expect(remindTime(RemindChoice.nextWeek, _now), DateTime(2026, 10, 26, 8));
    // On a Sunday, next week is not tomorrow.
    expect(
      remindTime(RemindChoice.nextWeek, DateTime(2026, 10, 25, 20)),
      DateTime(2026, 11, 2, 8),
    );
  });

  test('the chip and the row say it in words', () {
    final l = AppLocalizationsEn();
    expect(remindChipLabel(null, _now, l, 'en'), 'Remind me');
    expect(
      remindChipLabel(DateTime(2026, 10, 22, 8), _now, l, 'en'),
      'Remind me tomorrow',
    );
    expect(
      remindChipLabel(DateTime(2026, 10, 24, 8), _now, l, 'en'),
      'Remind me in 3 days',
    );
    expect(
      remindChipLabel(DateTime(2026, 11, 30, 9), _now, l, 'en'),
      'Remind me on Nov 30',
    );
    expect(waitsOn('Luca Bianchi, Sara Conti'), 'Luca');
    expect(waitsOn('orders@acme.example'), 'orders@acme.example');
    final row = MailRow(
      accountId: 2,
      mailbox: 'Sent',
      uid: 1,
      fromName: 'Matteo',
      fromEmail: 'matteo@studio.it',
      subject: 'Quote for the Acme site',
      preview: '',
      receivedAt: DateTime(2026, 10, 18, 10, 12),
      seen: true,
      to: 'Luca Bianchi',
      folder: MailFolder.sent,
    );
    expect(noReplyLine(row, _now, l), 'No reply from Luca · sent 3 days ago');
  });

  testWidgets('the compose chip asks when, and the email keeps it', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _write(tester);
    expect(_chip('Remind me'), findsOneWidget);
    await tester.tap(_chip('Remind me'));
    await tester.pumpAndSettle();
    for (final (label, time) in [
      ('Tomorrow', 'Thu 8:00'),
      ('In 3 days', 'Sat 8:00'),
      ('Next week', 'Mon 8:00'),
    ]) {
      expect(find.text(label), findsOneWidget);
      expect(find.text(time), findsOneWidget);
    }
    expect(find.text('Pick a date…'), findsOneWidget);
    expect(find.text('Don’t remind me'), findsOneWidget);
    await tester.tap(find.text('In 3 days'));
    await tester.pumpAndSettle();
    expect(_chip('Remind me in 3 days'), findsOneWidget);

    // Don't remind me takes it back.
    await tester.tap(_chip('Remind me in 3 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Don’t remind me'));
    await tester.pumpAndSettle();
    expect(_chip('Remind me'), findsOneWidget);

    await tester.tap(_chip('Remind me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In 3 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.remindAt, DateTime(2026, 10, 24, 8));
  });

  testWidgets('a picked day reminds then', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(_chip('Remind me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick a date…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me Fri, Oct 30, 9:00'));
    await tester.pumpAndSettle();
    expect(_chip('Remind me in 9 days'), findsNothing);
    expect(_chip('Remind me on Oct 30'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.remindAt, DateTime(2026, 10, 30, 9));
  });

  testWidgets('on the phone the chip opens the same choices as a sheet', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await _write(tester, phone: true);
    await tester.tap(_chip('Remind me'));
    await tester.pumpAndSettle();
    expect(find.text('Remind me if nobody replies'), findsOneWidget);
    expect(find.text('Sat 8:00'), findsOneWidget);
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    expect(_chip('Remind me tomorrow'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.remindAt, DateTime(2026, 10, 22, 8));
  });

  testWidgets('in Waiting the choice sits next to Write again', (tester) async {
    final source = await _pump(tester);
    await _openWaiting(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Quote for the Acme site'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Write again'), findsOneWidget);
    await tester.tap(_chip('Remind me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next week'));
    await tester.pumpAndSettle();
    expect(_chip('Remind me in 5 days'), findsOneWidget);
    final rows = await source.page(0, 10, folder: MailFolder.waiting);
    expect(
      rows.firstWhere((r) => r.subject == 'Quote for the Acme site').remindAt,
      DateTime(2026, 10, 26, 8),
    );
  });

  testWidgets('a Waiting row swiped left on the phone gives Remind me', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await tester.tap(find.text('3 sent emails waiting for a reply'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final row = find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text('Photos from Saturday'),
    );
    await tester.drag(row, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remind me if nobody replies'), findsOneWidget);
    await tester.tap(find.text('In 3 days'));
    await tester.pumpAndSettle();
    // The row stays where it is.
    expect(row, findsOneWidget);
    final rows = await source.page(0, 10, folder: MailFolder.waiting);
    expect(
      rows.firstWhere((r) => r.subject == 'Photos from Saturday').remindAt,
      DateTime(2026, 10, 24, 8),
    );
  });

  testWidgets('when the day comes the email is back on top of the inbox', (
    tester,
  ) async {
    await _pump(tester, reminded: true);
    final line = find.text('No reply from Luca · sent 5 days ago');
    expect(line, findsOneWidget);
    final tile = find.ancestor(of: line, matching: find.byType(InboxRowTile));
    expect(
      find.descendant(of: tile, matching: find.text('08:00')),
      findsOneWidget,
    );
    // Above everything else, under one Today.
    final first = tester.getTopLeft(find.byType(InboxRowTile).first);
    expect(tester.getTopLeft(tile), first);
    expect(find.text('TODAY'), findsOneWidget);

    await tester.tap(line);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Write again'), findsOneWidget);
    expect(find.bySemanticsLabel('Stop waiting'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Stop waiting'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(line, findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('remind menu golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _write(tester);
      await tester.tap(_chip('Remind me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In 3 days'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('Remind me in 3 days'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/remind_menu_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone remind sheet golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await _write(tester, phone: true);
        await tester.tap(_chip('Remind me'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_remind_sheet_$name.png'),
        );
      });
    }, tags: ['golden']);

    testWidgets('inbox reminded golden $name', (tester) async {
      await _pump(tester, dark: dark, reminded: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/inbox_reminded_$name.png'),
      );
    }, tags: ['golden']);
  }
}
