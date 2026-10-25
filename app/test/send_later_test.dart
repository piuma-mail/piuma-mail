import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/send_later.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
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
  await tester.enterText(_field(1), 'Mockups approved');
  await tester.enterText(_field(2), 'Let’s go with v3.');
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

  test('the times are always ahead', () {
    expect(sendLaterTimes(_now), [
      DateTime(2026, 10, 16, 8),
      DateTime(2026, 10, 16, 14),
      DateTime(2026, 10, 19, 8),
    ]);
    // On a Sunday tomorrow is Monday: the Monday after, then.
    expect(
      sendLaterTimes(DateTime(2026, 10, 18, 20)).last,
      DateTime(2026, 10, 26, 8),
    );
  });

  testWidgets('send later waits in the Outbox, with Undo', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byTooltip('Send later'));
    await tester.pumpAndSettle();
    expect(find.text('To Luca Bianchi'), findsOneWidget);
    expect(find.text('Thursday, October 15, 8:00'), findsNothing);
    expect(find.text('Friday, October 16, 8:00'), findsOneWidget);
    expect(find.text('Schedule for tomorrow at 8:00'), findsOneWidget);

    await tester.tap(find.text('Monday morning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule for Monday at 8:00'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.text('Scheduled for Mon, 08:00'), findsOneWidget);
    expect(source.scheduled.single.$1.subject, 'Mockups approved');
    expect(source.scheduled.single.$2, DateTime(2026, 10, 19, 8));
    expect(source.sent, isEmpty);
    // It waits in the Outbox, saying when it goes.
    expect(find.byType(OutboxTile), findsOneWidget);
    expect(find.text('Mon, 08:00'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.byType(OutboxTile), findsNothing);
  });

  testWidgets('send later on a day picked in the month', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byTooltip('Send later'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick date & time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('22'));
    await tester.tap(find.text('9:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule for Thu, Oct 22, 9:00'));
    await tester.pumpAndSettle();
    expect(source.scheduled.single.$2, DateTime(2026, 10, 22, 9));
  });

  testWidgets('without recipients nothing is scheduled', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send later'));
    await tester.pumpAndSettle();
    expect(find.text('Send later'), findsNothing);
    expect(find.text('Add at least one recipient.'), findsOneWidget);
    expect(source.scheduled, isEmpty);
  });

  testWidgets('the phone names the first time at the foot', (tester) async {
    final source = await _pump(tester, phone: true);
    await _write(tester, phone: true);
    expect(find.textContaining('You can undo send'), findsNothing);
    await tester.tap(find.text('Send tomorrow 8:00'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule for tomorrow at 8:00'), findsOneWidget);
    await tester.tap(find.text('Schedule for tomorrow at 8:00'));
    await tester.pumpAndSettle();
    expect(source.scheduled.single.$2, DateTime(2026, 10, 16, 8));
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('send later golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _write(tester);
      await tester.tap(find.byTooltip('Send later'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/send_later_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone send later golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await _write(tester, phone: true);
        await tester.tap(find.text('Send tomorrow 8:00'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_send_later_$name.png'),
        );
      });
    }, tags: ['golden']);
  }
}
