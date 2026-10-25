import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/newsletters.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/inbox/tablet_parts.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

/// The inbox on a touch screen of [size]: `Tablet` is 1180 × 820.
Future<DemoMailSource> _inbox(
  WidgetTester tester, {
  Size size = const Size(1180, 820),
  bool touch = true,
  bool dark = false,
}) async {
  touchDevice = touch;
  addTearDown(() => touchDevice = false);
  tester.view.physicalSize = size;
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
  await _settle(tester);
  return source;
}

/// Lets what enters (each opened card) run its timer and finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tablet held sideways takes the rail and the floating bar', (
    tester,
  ) async {
    await _inbox(tester);
    expect(find.byType(TabletRail), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.text('Search or run a command'), findsOneWidget);
    // Under the rows, what the swipes do.
    await tester.scrollUntilVisible(
      find.text('Swipe right to archive, left to snooze'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    for (final action in ['Reply', 'Archive', 'Snooze']) {
      expect(find.bySemanticsLabel(action), findsOneWidget);
    }
    // The rest waits under More.
    await tester.tap(find.bySemanticsLabel('More actions'));
    await _settle(tester);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the rail goes to the sections', (tester) async {
    await _inbox(tester);
    await tester.tap(find.bySemanticsLabel('Newsletters'));
    await _settle(tester);
    expect(find.byType(NewsletterList), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Inbox, 2 unread'));
    await _settle(tester);
    expect(find.text('Dinner on Friday?'), findsOneWidget);
  });

  testWidgets('a phone on its side keeps the phone layout', (tester) async {
    await _inbox(tester, size: const Size(844, 390));
    expect(find.byType(TabletRail), findsNothing);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.textContaining('Swipe right to archive'), findsNothing);
    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    expect(find.text('Reply to Giulia…'), findsOneWidget);
  });

  testWidgets('a desktop keeps the sidebar', (tester) async {
    await _inbox(tester, size: const Size(1440, 900), touch: false);
    expect(find.byType(TabletRail), findsNothing);
    expect(find.byType(Sidebar), findsOneWidget);
  });

  testWidgets('upright, the sections are pills and the message a panel', (
    tester,
  ) async {
    await _inbox(tester, size: const Size(820, 1180));
    expect(find.byType(TabletRail), findsNothing);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(TabletSections), findsOneWidget);
    expect(find.byType(Reader), findsNothing);

    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    expect(find.byType(TabletPanel), findsOneWidget);
    // The list stays under the panel.
    expect(find.text('Cellar keys'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _settle(tester);
    expect(find.byType(TabletPanel), findsNothing);

    await tester.tap(find.bySemanticsLabel(RegExp('^Newsletters')));
    await _settle(tester);
    expect(find.byType(NewsletterList), findsOneWidget);
    expect(find.byType(TabletSections), findsOneWidget);
  });

  testWidgets('tablet goldens', (tester) async {
    await _inbox(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tablet_light.png'),
    );
    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tablet_reader_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('dark tablet golden', (tester) async {
    await _inbox(tester, dark: true);
    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tablet_reader_dark.png'),
    );
  }, tags: ['golden']);

  testWidgets('upright tablet goldens', (tester) async {
    await _inbox(tester, size: const Size(820, 1180));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tablet_portrait_light.png'),
    );
    await tester.tap(find.text('Dinner on Friday?').first);
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tablet_portrait_reader_light.png'),
    );
  }, tags: ['golden']);
}
