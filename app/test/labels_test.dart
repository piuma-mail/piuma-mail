import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/labels.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/phone_parts.dart';
import 'package:piuma_mail/inbox/selection_panel.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool labels = true,
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, labels: labels);
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

Finder _inSidebar(Finder f) =>
    find.descendant(of: find.byType(Sidebar), matching: f);

Finder _inRows(Finder f) =>
    find.descendant(of: find.byType(InboxRowTile), matching: f);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _openLabel(WidgetTester tester, String name) async {
  await tester.tap(_inSidebar(find.text(name)));
  await _settle(tester);
}

Future<void> _openFirst(WidgetTester tester) async {
  await tester.tap(find.byType(InboxRowTile).first);
  await _settle(tester);
}

void main() {
  testWidgets('the sidebar lists the labels under the groups', (tester) async {
    await _pump(tester);
    expect(_inSidebar(find.text('LABELS')), findsOneWidget);
    for (final name in ['Worksite', 'Invoices', 'Family', 'Travel']) {
      expect(_inSidebar(find.text(name)), findsOneWidget);
    }
    // Worksite is on two emails.
    final item = find.ancestor(
      of: _inSidebar(find.text('Worksite')),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: item.first, matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('without labels there is no LABELS', (tester) async {
    await _pump(tester, labels: false);
    expect(_inSidebar(find.text('LABELS')), findsNothing);
    expect(find.byType(LabelPill), findsNothing);
  });

  testWidgets('rows show two labels, then +1', (tester) async {
    await _pump(tester);
    expect(_inRows(find.text('Worksite')), findsNWidgets(2));
    expect(_inRows(find.text('Invoices')), findsOneWidget);
    expect(_inRows(find.text('Family')), findsOneWidget);
    expect(_inRows(find.text('Travel')), findsOneWidget);
    // To read is the third on its row.
    expect(_inRows(find.text('To read')), findsNothing);
    expect(_inRows(find.text('+1')), findsOneWidget);
  });

  testWidgets('a label shows its emails from every account', (tester) async {
    await _pump(tester);
    await _openLabel(tester, 'Worksite');
    expect(find.byType(InboxRowTile), findsNWidgets(2));
    expect(find.textContaining('2 emails'), findsOneWidget);
  });

  testWidgets('the reader takes a label off with its ×', (tester) async {
    final source = await _pump(tester);
    await _openFirst(tester);
    final reader = find.byType(ReaderLabels);
    expect(
      find.descendant(of: reader, matching: find.text('Worksite')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reader, matching: find.text('+ Label')),
      findsOneWidget,
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is LabelPill && w.onRemove != null && w.label.name == 'Worksite',
      ),
    );
    await _settle(tester);
    expect(
      find.descendant(of: reader, matching: find.text('Worksite')),
      findsNothing,
    );
    final counts = {for (final l in await source.labels()) l.name: l.count};
    expect(counts['Worksite'], 1);
  });

  testWidgets('L opens the picker; a new name is created and put on', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openFirst(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(find.byType(LabelPicker), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(LabelPicker),
        matching: find.byType(TextField),
      ),
      'Site visits',
    );
    await tester.pump();
    expect(find.text('Create “Site visits”'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final made = (await source.labels()).singleWhere(
      (l) => l.name == 'Site visits',
    );
    expect(made.count, 1);
    expect(made.color, isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byType(ReaderLabels),
        matching: find.text('Site visits'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('picked rows get Label in the panel', (tester) async {
    final source = await _pump(tester);
    final rows = find.byType(InboxRowTile);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(rows.at(3));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await tester.tap(rows.at(4));
    await tester.pumpAndSettle();
    final panel = find.byType(SelectionPanel);
    expect(panel, findsOneWidget);
    await tester.tap(find.descendant(of: panel, matching: find.text('Label')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(LabelPicker),
        matching: find.text('Travel'),
      ),
    );
    await tester.pumpAndSettle();
    final travel = (await source.labels()).singleWhere(
      (l) => l.name == 'Travel',
    );
    expect(travel.count, 3);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('labels goldens ($name)', (tester) async {
      await _pump(tester, dark: dark);
      await _openLabel(tester, 'Worksite');
      await _openFirst(tester);
      await tester.tap(find.text('+ Label'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/labels_desktop_$name.png'),
      );
    }, tags: ['golden']);
  }

  group('on the phone', () {
    const phone = Size(390, 844);

    Future<void> openAccounts(WidgetTester tester) async {
      await tester.tap(
        find.bySemanticsLabel('3 accounts, accounts and Settings'),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('rows carry the pills', (tester) async {
      await _pump(tester, size: phone);
      expect(_inRows(find.text('Worksite')), findsNWidgets(2));
      expect(_inRows(find.text('+1')), findsOneWidget);
    });

    testWidgets('the account sheet lists the labels', (tester) async {
      await _pump(tester, size: phone);
      await openAccounts(tester);
      final sheet = find.byType(PhoneAccountsSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('LABELS')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Worksite')),
      );
      await _settle(tester);
      expect(find.byType(PhoneAccountsSheet), findsNothing);
      expect(find.byType(InboxRowTile), findsNWidgets(2));
      expect(find.text('Worksite'), findsWidgets);
    });

    testWidgets('More has Label…, a sheet with checks and New label', (
      tester,
    ) async {
      final source = await _pump(tester, size: phone);
      await _openFirst(tester);
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Label…'));
      await tester.pumpAndSettle();
      final sheet = find.byType(LabelPicker);
      expect(sheet, findsOneWidget);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Travel')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('New label')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: sheet, matching: find.byType(TextField)),
        'Site visits',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final counts = {for (final l in await source.labels()) l.name: l.count};
      expect(counts['Travel'], 2);
      expect(counts['Site visits'], 1);
    });

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('phone labels goldens ($name)', (tester) async {
        await _pump(tester, size: phone, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/labels_phone_list_$name.png'),
        );
        await _openFirst(tester);
        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Label…'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/labels_phone_sheet_$name.png'),
        );
      }, tags: ['golden']);
    }
  });
}
