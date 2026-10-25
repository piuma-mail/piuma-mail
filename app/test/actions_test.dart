import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
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
  testWidgets('Archive takes the row away, then tells the server', (
    tester,
  ) async {
    final source = await _pump(tester);
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(InboxRowTile), findsNWidgets(4));
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('No conversation selected'), findsOneWidget);
    expect(source.applied, isEmpty);
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied.single.$1.subject, 'Dinner on Friday?');
    expect(source.applied.single.$2, MessageAction.archive);
    await tester.pumpAndSettle();
    // Undo goes with its window: too late now.
    expect(find.text('Archived'), findsNothing);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Undo brings a deleted message back', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Moved to Trash'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    await tester.pump(const Duration(seconds: 15));
    expect(source.applied, isEmpty);
  });

  testWidgets('Reply answers the sender with the message quoted', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Reply'),
      ),
      findsOneWidget,
    );
    expect(find.text('Re: Dinner on Friday?'), findsOneWidget);
    expect(find.textContaining('> I booked Osteria del Ponte'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.to.single, 'Giulia Romano <giulia.romano@posta.it>');
    expect(sent.inReplyTo, isNotEmpty);
    expect(sent.references, [sent.inReplyTo]);
    expect(sent.body, startsWith('\n\nOn Oct 15, 2026'));
    // The account's signature for replies.
    expect(sent.signatureId, 3);
  });
}
