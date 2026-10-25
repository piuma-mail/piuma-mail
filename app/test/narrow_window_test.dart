import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool dark = false,
  bool open = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // No spam folders: Personal has no folders of its own.
  final source = DemoMailSource(now: _now, newsletter: true)
    ..junkFolders = false;
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: open ? first : null,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wide window keeps the full sidebar', (tester) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.text('Unified inbox'), findsOneWidget);
    expect(find.byTooltip('Unified inbox'), findsNothing);
  });

  testWidgets('under 1100px the sidebar is a rail of icons', (tester) async {
    await _pump(tester, const Size(1024, 700));
    expect(find.text('Unified inbox'), findsNothing);
    expect(find.byTooltip('Unified inbox'), findsOneWidget);
    // The list and the message still sit side by side.
    expect(find.text('Dinner on Friday?'), findsOneWidget);
    expect(find.text('New autumn arrivals'), findsNWidgets(2));

    // An account dot filters, as the full sidebar does.
    await tester.tap(find.byTooltip('Work'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Work only', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Dinner on Friday?'), findsNothing);

    // Work has folders of its own: they open beside the rail.
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Studio Nord'), findsOneWidget);
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();
    expect(find.text('Studio Nord'), findsNothing);
    expect(find.text('Invoices'), findsWidgets);

    // An account without folders only filters.
    await tester.tap(find.byTooltip('Personal'));
    await tester.pumpAndSettle();
    expect(find.text('Clients'), findsNothing);

    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsOneWidget);
  });

  testWidgets('under 900px a message covers the list', (tester) async {
    await _pump(tester, const Size(860, 640));
    // At start the list fills the window, with nothing marked open.
    expect(find.text('Dinner on Friday?'), findsOneWidget);
    expect(find.text('No conversation selected'), findsNothing);

    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.text('New autumn arrivals'), findsNothing);
    expect(
      find.textContaining('I booked Osteria del Ponte', findRichText: true),
      findsOneWidget,
    );

    // "‹ Inbox" goes back to the list.
    await tester.tap(find.bySemanticsLabel('Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('New autumn arrivals'), findsOneWidget);

    // So does Esc.
    await tester.tap(find.text('Mockup v3 review'));
    await tester.pumpAndSettle();
    expect(find.text('New autumn arrivals'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('New autumn arrivals'), findsOneWidget);

    // Compose covers the list too, and closing it brings the list back.
    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('New autumn arrivals'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('New autumn arrivals'), findsOneWidget);
  });

  testWidgets('every width from phone to desktop lays out cleanly', (
    tester,
  ) async {
    for (final w in <double>[600, 700, 899, 900, 1000, 1099, 1100, 1440]) {
      await _pump(tester, Size(w, 720));
      await tester.tap(find.text('Dinner on Friday?').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${w}px');
    }
  });

  // Golden screenshots, next to `NarrowWindow` on the canvas.
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('rail golden $name', (tester) async {
      await _pump(tester, const Size(1000, 680), dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/narrow_rail_$name.png'),
      );
    }, tags: ['golden']);
    testWidgets('rail folders golden $name', (tester) async {
      await _pump(tester, const Size(1000, 680), dark: dark);
      await tester.tap(find.byTooltip('Work'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/narrow_rail_folders_$name.png'),
      );
    }, tags: ['golden']);
    testWidgets('stacked golden $name', (tester) async {
      await _pump(tester, const Size(760, 640), dark: dark);
      await tester.tap(find.text('Dinner on Friday?'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/narrow_stacked_$name.png'),
      );
    }, tags: ['golden']);
  }
}
