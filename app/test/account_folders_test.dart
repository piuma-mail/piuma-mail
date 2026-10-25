import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/move_menu.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The `AccountFolders` mockup: own folders under each account.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
  bool junk = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now)..junkFolders = junk;
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

Iterable<String> _subjects(WidgetTester tester) => tester
    .widgetList<InboxRowTile>(find.byType(InboxRowTile))
    .map((t) => t.row.subject);

/// Shows Work's mail and opens its first message.
Future<String> _openWorkMessage(WidgetTester tester) async {
  await tester.tap(find.text('Work').first);
  await tester.pumpAndSettle();
  final subject = _subjects(tester).first;
  await tester.tap(find.text(subject).first);
  await tester.pumpAndSettle();
  return subject;
}

Future<void> _pickTarget(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(MoveMenu), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the chevron opens an account’s folders', (tester) async {
    await _pump(tester);
    expect(find.text('Acme'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    for (final name in ['Clients', 'Acme', 'Studio Nord', 'Invoices']) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Acme'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxRowTile), findsNothing);
    expect(find.text('Acme'), findsNWidgets(2));
    // Back to the inbox, the folders stay open.
    await tester.tap(find.text('Unified inbox'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxRowTile), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsNothing);
  });

  testWidgets('Move to files a message in a folder, Undo keeps it', (
    tester,
  ) async {
    final source = await _pump(tester);
    final subject = await _openWorkMessage(tester);

    await tester.tap(find.byTooltip('Move to…'));
    await tester.pumpAndSettle();
    expect(find.byType(MoveMenu), findsOneWidget);
    // Typing narrows the list.
    await tester.enterText(
      find.descendant(
        of: find.byType(MoveMenu),
        matching: find.byType(TextField),
      ),
      'nord',
    );
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsNothing);
    await _pickTarget(tester, 'Studio Nord');
    expect(find.text('Moved to Studio Nord'), findsOneWidget);
    expect(_subjects(tester), isNot(contains(subject)));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_subjects(tester), contains(subject));
    await tester.pump(const Duration(seconds: 11));
    expect(source.moved, isEmpty);

    await tester.tap(find.text(subject).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to…'));
    await tester.pumpAndSettle();
    await _pickTarget(tester, 'Acme');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.moved.map((m) => (m.$1.subject, m.$2)), [
      (subject, 'Clients/Acme'),
    ]);
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme'));
    await tester.pumpAndSettle();
    expect(_subjects(tester), [subject]);
  });

  testWidgets('M opens Move to and Enter takes the first match', (
    tester,
  ) async {
    final source = await _pump(tester);
    final subject = await _openWorkMessage(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.byType(MoveMenu), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(MoveMenu),
        matching: find.byType(TextField),
      ),
      'inv',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // The row folds away first.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.moved.map((m) => (m.$1.subject, m.$2)), [
      (subject, 'Invoices'),
    ]);
  });

  testWidgets('Move to on an account without folders says so', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Personal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(_subjects(tester).first).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move to…'));
    await tester.pumpAndSettle();
    expect(find.text('Personal has no other folders yet'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(MoveMenu),
        matching: find.byType(TextField),
      ),
      'x',
    );
    await tester.pumpAndSettle();
    expect(find.text('No folder by that name'), findsOneWidget);
  });

  testWidgets('an account without folders has no chevron', (tester) async {
    await _pump(tester, junk: false);
    expect(find.bySemanticsLabel('Work folders'), findsOneWidget);
    expect(find.bySemanticsLabel('Personal folders'), findsNothing);
  });

  testWidgets('on the phone the folders sit in the accounts sheet', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Work folders'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Work, matteo@studio.it'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Work only, accounts and Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    await _pickTarget(tester, 'Projects');
    expect(find.text('Projects'), findsOneWidget);
    expect(find.byType(InboxRowTile), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('account folders golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openWorkMessage(tester);
      await tester.tap(find.bySemanticsLabel('Work folders'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_folders_$name.png'),
      );
      await tester.tap(find.byTooltip('Move to…'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/move_to_$name.png'),
      );
    }, tags: ['golden']);
  }
}
