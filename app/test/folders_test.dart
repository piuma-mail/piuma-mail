import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  final first = (await source.page(0, 1)).first;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
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

Future<void> _open(WidgetTester tester, String folder) async {
  await tester.tap(find.text(folder).first);
  await tester.pumpAndSettle();
}

Iterable<String> _subjects(WidgetTester tester) => tester
    .widgetList<InboxRowTile>(find.byType(InboxRowTile))
    .map((t) => t.row.subject);

void main() {
  testWidgets('Sent lists what went out, named by its recipients', (
    tester,
  ) async {
    await _pump(tester);
    await _open(tester, 'Sent');
    expect(_subjects(tester), [
      'Mockups approved: let’s go',
      'Re: Dinner on Friday?',
      'Re: Print quote',
      'Autumn catalog print quote',
    ]);
    expect(find.text('Luca Bianchi, Sara Conti'), findsOneWidget);
    expect(find.text('No conversation selected'), findsOneWidget);
    await tester.tap(find.text('Mockups approved: let’s go'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('to Luca Bianchi, Sara Conti · today at 08:40'),
      findsOneWidget,
    );
    expect(find.text('Reply'), findsNothing);
  });

  testWidgets('an archived message shows up in Archive', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Archive'));
    // The row folds away first.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await _open(tester, 'Archive');
    expect(_subjects(tester), contains('Dinner on Friday?'));
    expect(find.byType(InboxRowTile), findsNWidgets(4));
    await tester.tap(find.text('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Archive'), findsNothing);
    await _open(tester, 'Unified inbox');
    expect(find.byType(InboxRowTile), findsNWidgets(4));
  });

  testWidgets('a sent message shows up in Sent', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await _open(tester, 'Sent');
    expect(_subjects(tester).first, 'Re: Dinner on Friday?');
    expect(find.byType(InboxRowTile), findsNWidgets(5));
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('folders golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _open(tester, 'Sent');
      await tester.tap(find.text('Mockups approved: let’s go'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/folders_sent_$name.png'),
      );
      await _open(tester, 'Archive');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/folders_archive_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('an account in the sidebar shows only its mail', (tester) async {
    await _pump(tester);
    Iterable<int> accounts() => tester
        .widgetList<InboxRowTile>(find.byType(InboxRowTile))
        .map((t) => t.row.accountId)
        .toSet();
    expect(accounts(), {1, 2, 3});
    await _open(tester, 'Work');
    expect(accounts(), {2});
    expect(
      find.textContaining('Work only', findRichText: true),
      findsOneWidget,
    );
    // Sent keeps the account.
    await _open(tester, 'Sent');
    expect(accounts(), {2});
    // Show all brings every account back.
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(accounts().length, greaterThan(1));
    // A second click on the account, or Unified inbox, also lets go.
    await _open(tester, 'Personal');
    expect(accounts(), {1});
    await _open(tester, 'Unified inbox');
    expect(accounts(), {1, 2, 3});
  });

  testWidgets('sidebar account filter golden', (tester) async {
    await _pump(tester);
    await _open(tester, 'Work');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_filter_light.png'),
    );
  }, tags: ['golden']);
}
