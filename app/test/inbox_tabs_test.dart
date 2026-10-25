import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/inbox_tabs.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool notifications = true,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, notifications: notifications);
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

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

void main() {
  test('the demo splits people from machines', () async {
    final source = DemoMailSource(now: _now, notifications: true);
    final counts = await source.tabCounts();
    expect((counts.people, counts.notifications), (5, 4));
    expect((counts.peopleUnread, counts.notificationsUnread), (2, 4));
    final machines = await source.page(0, 10, tab: InboxTab.notifications);
    expect(machines.first.subject, 'Your parcel is out for delivery');
  });

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';
    testWidgets('$where: the inbox shows people first, machines a tap away', (
      tester,
    ) async {
      await _pump(tester, phone: phone);
      expect(find.byType(InboxTabs), findsOneWidget);
      expect(_row('Dinner on Friday?'), findsOneWidget);
      expect(_row('Your parcel is out for delivery'), findsNothing);

      await tester.tap(find.textContaining('Notifications'));
      await tester.pumpAndSettle();
      expect(_row('Your parcel is out for delivery'), findsOneWidget);
      expect(_row('Card payment of €42.00'), findsOneWidget);
      expect(_row('Dinner on Friday?'), findsNothing);

      await tester.tap(find.textContaining('People'));
      await tester.pumpAndSettle();
      expect(_row('Dinner on Friday?'), findsOneWidget);
    });
  }

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';
    testWidgets('$where: All shows everything, Unread only what is unread', (
      tester,
    ) async {
      final source = await _pump(tester, phone: phone);
      await tester.tap(
        find.descendant(of: find.byType(InboxTabs), matching: find.text('All')),
      );
      await tester.pumpAndSettle();
      expect(_row('Dinner on Friday?'), findsOneWidget);
      expect(_row('Your parcel is out for delivery'), findsOneWidget);

      await tester.tap(find.textContaining('People'));
      await tester.pumpAndSettle();
      final people = await source.page(0, 20, tab: InboxTab.people);
      final read = people.firstWhere((r) => r.seen).subject;
      final unread = people.firstWhere((r) => !r.seen).subject;
      expect(_row(read), findsOneWidget);
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(_row(read), findsNothing);
      expect(_row(unread), findsOneWidget);
      expect(_row('Your parcel is out for delivery'), findsNothing);

      // The switch stays on across the chips.
      await tester.tap(find.textContaining('Notifications'));
      await tester.pumpAndSettle();
      expect(_row('Your parcel is out for delivery'), findsOneWidget);
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(_row('Dinner on Friday?'), findsNothing);
    });
  }

  testWidgets('More moves a sender to Notifications, and Undo back', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Notifications'));
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsNothing);
    final row = (await source.page(
      0,
      20,
      tab: InboxTab.notifications,
    )).firstWhere((r) => r.subject == 'Dinner on Friday?');
    expect(source.byPerson(row), isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_row('Dinner on Friday?'), findsOneWidget);
  });

  testWidgets('a screen reader hears Unread as a switch', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, phone: true);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Unread')),
      matchesSemantics(
        label: 'Unread',
        hint: 'Only emails with something unread',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('no tabs while no machine has written', (tester) async {
    await _pump(tester, notifications: false);
    expect(find.byType(InboxTabs), findsNothing);
    expect(_row('Dinner on Friday?'), findsOneWidget);
  });

  testWidgets('a screen reader hears each tab and what is unread', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('People, 2 unread'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications, 4 unread'), findsOneWidget);
    semantics.dispose();
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    for (final phone in [false, true]) {
      final file = phone ? 'phone_inbox_tabs_$name' : 'inbox_tabs_$name';
      testWidgets('$file golden', (tester) async {
        debugDisableShadows = false;
        try {
          await _pump(tester, phone: phone, dark: dark);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/$file.png'),
          );
        } finally {
          debugDisableShadows = true;
        }
      }, tags: ['golden']);
    }
  }
}
