import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/invite_card.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/readable.dart';
import 'package:piuma_mail/main.dart';

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  bool busy = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, busyFriday: busy);
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

Finder _inCard(Finder f) =>
    find.descendant(of: find.byType(InviteCard), matching: f);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_row('Dinner on Friday?'));
  await _settle(tester);
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

  testWidgets('an invite shows its card; Yes sends the reply', (tester) async {
    final source = await _pump(tester);
    await _open(tester);
    expect(find.byType(InviteCard), findsOneWidget);
    expect(_inCard(find.text('Dinner at Osteria del Ponte')), findsOneWidget);
    expect(_inCard(find.text('4 attendees')), findsOneWidget);
    expect(
      _inCard(
        find.textContaining('20:30–22:30 · Osteria del Ponte, via Garibaldi 8'),
      ),
      findsOneWidget,
    );

    await tester.tap(_inCard(find.text('Yes')));
    await _settle(tester);
    expect(
      _inCard(find.textContaining('You accepted', findRichText: true)),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.textContaining(
          'You accepted · added to Personal',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(source.invitesAnswered, hasLength(1));
    final (row, answer, subject, _) = source.invitesAnswered.single;
    expect(row.subject, 'Dinner on Friday?');
    expect(answer, InviteAnswer.accepted);
    expect(subject, 'Accepted: Dinner at Osteria del Ponte');
  });

  testWidgets('the timeline says when you are free, or what overlaps', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester);
    expect(_inCard(find.text('Free · no conflicts')), findsOneWidget);
    expect(_inCard(find.text('Yoga')), findsOneWidget);
  });

  testWidgets('something already at that time shows as a conflict', (
    tester,
  ) async {
    await _pump(tester, busy: true);
    await _open(tester);
    expect(_inCard(find.text('Overlaps School play 20:00')), findsOneWidget);
  });

  testWidgets('without conflict checks there is no timeline', (tester) async {
    final source = await _pump(tester);
    await source.setCheckConflicts(false);
    await _open(tester);
    expect(find.byType(InviteCard), findsOneWidget);
    expect(_inCard(find.text('Free · no conflicts')), findsNothing);
  });

  testWidgets('on the phone the card sits above the message', (tester) async {
    final source = await _pump(tester, phone: true);
    await _open(tester);
    expect(find.byType(InviteCard), findsOneWidget);
    await tester.tap(_inCard(find.text('No')));
    await _settle(tester);
    expect(
      _inCard(find.textContaining('You declined', findRichText: true)),
      findsOneWidget,
    );
    expect(source.invitesAnswered.single.$2, InviteAnswer.declined);
  });

  testWidgets('a day in the words can go in the calendar', (tester) async {
    final source = await _pump(tester);
    await _open(tester);
    final chip = find.text('Add Saturday 16:00 to calendar');
    expect(chip, findsOneWidget);
    // Friday at 20:30 is the invite itself: nothing to add.
    expect(find.textContaining('Friday 20:30'), findsNothing);

    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await _settle(tester);
    expect(find.text('Added to Personal'), findsOneWidget);
    expect(source.datesAdded, [
      ('Dinner on Friday?', DateTime(2026, 10, 17, 16)),
    ]);
  });

  testWidgets('no suggestion when it is turned off', (tester) async {
    final source = await _pump(tester);
    await source.setFindDates(false);
    await _open(tester);
    expect(find.text('Add Saturday 16:00 to calendar'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('invite golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _open(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/invite_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone invite golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await _open(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_invite_$name.png'),
        );
      });
    }, tags: ['golden']);
  }
}
