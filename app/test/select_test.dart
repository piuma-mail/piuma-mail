import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/selection_panel.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
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

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

/// Clicks a row with Cmd held.
Future<void> _cmdTap(WidgetTester tester, String subject) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.tap(_row(subject));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

Future<void> _pickThree(WidgetTester tester) async {
  await _cmdTap(tester, 'Dinner on Friday?');
  // Once something is picked, a plain click picks too.
  await tester.tap(_row('Re: Print quote'));
  await tester.pumpAndSettle();
  await tester.tap(_row('Trip photos'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cmd+click picks, a plain click adds, Esc lets go', (
    tester,
  ) async {
    await _pump(tester);
    await _cmdTap(tester, 'Dinner on Friday?');
    expect(find.byType(SelectionPanel), findsOneWidget);
    expect(find.text('1 of 5 selected'), findsOneWidget);
    expect(find.text('conversation selected'), findsOneWidget);
    expect(find.text('from Giulia'), findsOneWidget);
    // One account's mail can move, and the hints say so.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('move'), findsOneWidget);

    await tester.tap(_row('Re: Print quote'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_row('Trip photos'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 5 selected'), findsOneWidget);
    expect(find.text('conversations selected'), findsOneWidget);
    expect(find.text('from Giulia, Sara and Dad'), findsOneWidget);

    // A second click lets one go.
    await tester.tap(_row('Trip photos'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 5 selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SelectionPanel), findsNothing);
    expect(find.text('No conversation selected'), findsOneWidget);
  });

  testWidgets('Shift+click picks a range from the open message', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(_row('Mockup v3 review'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(_row('Cellar keys'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('4 of 5 selected'), findsOneWidget);
    expect(find.text('from Luca, Sara and 2 more'), findsOneWidget);
  });

  testWidgets('Cmd+A picks them all, the header box lets them go', (
    tester,
  ) async {
    await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('5 of 5 selected'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Select all'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionPanel), findsNothing);
  });

  testWidgets('a click on the avatar picks without opening', (tester) async {
    await _pump(tester);
    // The checkbox sits where the avatar is, shown on hover.
    await tester.tap(find.byType(PickBox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 5 selected'), findsOneWidget);
    expect(find.byType(SelectionPanel), findsOneWidget);
  });

  testWidgets('Archive moves every picked conversation in one go', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _pickThree(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SelectionPanel),
        matching: find.text('Archive'),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(InboxRowTile), findsNWidgets(2));
    expect(find.text('3 conversations archived'), findsOneWidget);
    expect(find.byType(SelectionPanel), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    // The conversation's earlier inbox message goes with it.
    expect(
      source.applied.map((a) => a.$1.subject),
      containsAll(['Dinner on Friday?', 'Re: Print quote', 'Trip photos']),
    );
    expect(source.applied.every((a) => a.$2 == MessageAction.archive), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('Undo brings the conversations back, still picked', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _pickThree(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('3 conversations moved to Trash'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    expect(find.text('3 of 5 selected'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(source.applied, isEmpty);
  });

  testWidgets('E archives the picked ones', (tester) async {
    final source = await _pump(tester);
    await _pickThree(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('3 conversations archived'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied, isNotEmpty);
    await tester.pumpAndSettle();
  });

  testWidgets('Mark as read, then Shift+U for unread', (tester) async {
    final source = await _pump(tester);
    await _cmdTap(tester, 'Dinner on Friday?');
    await tester.tap(_row('Mockup v3 review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(source.seenSet.map((s) => s.$2), everyElement(isTrue));
    expect(source.seenSet, hasLength(2));
    expect(await source.inboxUnread(), 0);
    expect(find.text('Mark as unread'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(await source.inboxUnread(), 2);
    expect(find.text('Mark as read'), findsOneWidget);
  });

  testWidgets('opening a message reads it', (tester) async {
    final source = await _pump(tester);
    expect(await source.inboxUnread(), 2);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(source.seenSet.single.$1.subject, 'Dinner on Friday?');
    expect(await source.inboxUnread(), 1);
    // Already read: nothing to tell the server.
    await tester.tap(_row('Trip photos'));
    await tester.pumpAndSettle();
    expect(source.seenSet, hasLength(1));
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('select golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _pickThree(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/select_$name.png'),
      );
    }, tags: ['golden']);
  }
}
