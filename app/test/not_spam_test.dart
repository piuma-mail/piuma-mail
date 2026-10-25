import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
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

/// Personal's spam folder, as the last of its folders.
Future<void> _openSpam(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Personal folders'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Spam'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the spam folder is the last of an account’s folders', (
    tester,
  ) async {
    await _pump(tester);
    await _openSpam(tester);
    expect(find.byType(InboxRowTile), findsOneWidget);
    expect(find.text('Your table for Saturday'), findsOneWidget);
  });

  testWidgets('Not spam takes an email back to the inbox, with Undo', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openSpam(tester);
    await tester.tap(find.text('Your table for Saturday'));
    await tester.pumpAndSettle();
    // In its place there is no Report spam to offer.
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Report spam'), findsNothing);
    expect(find.text('Not spam'), findsNWidgets(2));
    // The one in More.
    await tester.tap(find.text('Not spam').last);
    // The row folds away first.
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Moved to Inbox'), findsOneWidget);
    expect(find.byType(InboxRowTile), findsNothing);
    // The server hears of it once Undo has gone.
    expect(source.applied, isEmpty);
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied.single.$2, MessageAction.notJunk);
    await tester.pumpAndSettle();
  });

  testWidgets('outside the spam folder, Report spam and no Not spam', (
    tester,
  ) async {
    await _pump(tester);
    final first = tester
        .widgetList<InboxRowTile>(find.byType(InboxRowTile))
        .first
        .row
        .subject;
    await tester.tap(find.text(first).first);
    await tester.pumpAndSettle();
    expect(find.text('Not spam'), findsNothing);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Report spam'), findsOneWidget);
    expect(find.text('Not spam'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('not spam golden ${dark ? 'dark' : 'light'}', (tester) async {
      await _pump(tester, dark: dark);
      await _openSpam(tester);
      await tester.tap(find.text('Your table for Saturday'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(InboxScreen),
        matchesGoldenFile('goldens/not_spam_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
