import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/sections.dart';
import 'package:piuma_mail/l10n/app_localizations_en.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pumpInbox(
  WidgetTester tester, {
  bool dark = false,
  int extraRows = 0,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, extraRows: extraRows);
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      locale: locale,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: first,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('the inbox shows sections, rows and the open message', (
    tester,
  ) async {
    await _pumpInbox(tester);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    expect(find.text('3 accounts · 2 unread'), findsOneWidget);
    expect(find.text('to you · today at 10:42'), findsNothing);
    expect(find.text('to you · today at 09:42'), findsOneWidget);
    expect(find.textContaining('bring the new board game'), findsOneWidget);
  });

  testWidgets('tapping a row opens it', (tester) async {
    await _pumpInbox(tester);
    await tester.tap(find.text('Cellar keys'));
    await tester.pumpAndSettle();
    // In the list, and on the reader's sender line.
    expect(find.text('Elena Ferri'), findsNWidgets(2));
    expect(find.textContaining('to you · Mon, Oct 12, 2026'), findsOneWidget);
  });

  testWidgets('a 50,000-message inbox scrolls to the end', (tester) async {
    final source = await _pumpInbox(tester, extraRows: 50000);
    final count = await source.inboxCount();
    final oldest = (await source.page(count - 1, 1)).single;
    final list = find.descendant(
      of: find.byType(MessageList),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(list).position;
    // The extent of far-away rows is only known once laid out.
    for (var i = 0; i < 5; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(find.text(oldest.subject), findsOneWidget);
  });

  testWidgets('Italian inbox', (tester) async {
    await _pumpInbox(tester, locale: const Locale('it'));
    expect(find.text('OGGI'), findsOneWidget);
    expect(find.text('3 account · 2 da leggere'), findsOneWidget);
    expect(find.text('Scrivi'), findsOneWidget);
  });

  test('initials', () {
    expect(initials('Giulia Romano'), 'GR');
    expect(initials('Dad'), 'D');
    expect(initials('elena.ferri@icloud.com'), 'E');
    expect(initials(''), '?');
    expect(initials('SportFits (TouriSpo GmbH & Co. KG)'), 'ST');
    expect(initials('"Ålesund" Tours'), 'ÅT');
    expect(initials('(•‿•)'), '?');
  });

  test('sections never overlap', () {
    // On a Monday "this week" is empty: it starts today.
    final plan = SectionPlan(
      DateTime(2026, 10, 12, 9),
      AppLocalizationsEn(),
      'en',
    );
    final edges = plan.edges;
    for (var i = 0; i + 1 < edges.length; i++) {
      expect(edges[i + 1].isAfter(edges[i]), isFalse);
    }
    expect(plan.labels.take(4), [
      'Today',
      'Yesterday',
      'This week',
      'Earlier this month',
    ]);
    expect(plan.labels[4], 'September 2026');
  });

  // Golden screenshots of the real screens, next to the mockups on the canvas.
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('inbox golden $name', (tester) async {
      await _pumpInbox(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/inbox_$name.png'),
      );
    }, tags: ['golden']);
  }
}
