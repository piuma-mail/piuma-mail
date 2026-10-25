import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/shortcuts_page.dart';

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

Future<void> _open(WidgetTester tester, String subject) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text(subject),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('C writes a new email', (tester) async {
    await _pump(tester);
    await _key(tester, LogicalKeyboardKey.keyC);
    expect(find.byType(ComposePane), findsOneWidget);
    // Typing in compose types, it doesn't open another one.
    await _key(tester, LogicalKeyboardKey.keyC);
    expect(find.byType(ComposePane), findsOneWidget);
  });

  testWidgets('R replies to the open message', (tester) async {
    await _pump(tester);
    await _open(tester, 'Dinner on Friday?');
    await _key(tester, LogicalKeyboardKey.keyR);
    expect(find.byType(ComposePane), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Re: Dinner on Friday?'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('H snoozes and E archives the open message', (tester) async {
    final source = await _pump(tester);
    await _open(tester, 'Dinner on Friday?');
    await _key(tester, LogicalKeyboardKey.keyH);
    expect(find.text('Snooze until…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Snooze until…'), findsNothing);

    await _key(tester, LogicalKeyboardKey.keyE);
    expect(find.text('Archived'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.applied, isNotEmpty);
  });

  testWidgets('Settings › Shortcuts lists the keys', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shortcuts'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutsPage), findsOneWidget);
    for (final key in ['C', 'E', 'H', 'Ctrl K', 'R']) {
      expect(find.text(key), findsOneWidget);
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/settings_shortcuts_light.png'),
    );
  }, tags: ['golden']);
}
