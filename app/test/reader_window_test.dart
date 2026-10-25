import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/reader_window.dart';
import 'package:piuma_mail/search/search_panel.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _inbox(
  WidgetTester tester, {
  ValueChanged<MailRow>? onOpenWindow,
  Stream<MailRow>? replies,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        onOpenWindow: onOpenWindow,
        replies: replies,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(find.text('Search…'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(SearchPanel),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<MailRow> _row(DemoMailSource source, String subject) async =>
    (await source.page(0, 50)).firstWhere((r) => r.subject == subject);

void main() {
  test('a window is told which message to read', () {
    const m = WindowMessage(3, 'INBOX', 812);
    final back = WindowMessage.decode(m.encode())!;
    expect((back.accountId, back.mailbox, back.uid), (3, 'INBOX', 812));
    final map = WindowMessage.fromMap(m.toMap())!;
    expect((map.accountId, map.mailbox, map.uid), (3, 'INBOX', 812));
    expect(WindowMessage.decode(''), isNull);
    expect(WindowMessage.decode('{"read":[1]}'), isNull);
    expect(WindowMessage.fromMap({'a': 1}), isNull);
  });

  testWidgets('⌘↵ in search opens the result in a new window', (tester) async {
    final opened = <MailRow>[];
    await _inbox(tester, onOpenWindow: opened.add);
    await _search(tester, 'quote');
    expect(find.text('Ctrl ↵'), findsOneWidget);
    expect(find.text(' open in new window'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    // Search stays open, for the next one.
    expect(find.byType(SearchPanel), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
  });

  testWidgets('one window only: no hint, ⌘↵ does nothing', (tester) async {
    await _inbox(tester);
    await _search(tester, 'quote');
    expect(find.text(' open in new window'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
  });

  testWidgets('Reply from a reader window is written in the inbox', (
    tester,
  ) async {
    final replies = StreamController<MailRow>();
    addTearDown(replies.close);
    final source = await _inbox(tester, replies: replies.stream);
    replies.add(await _row(source, 'Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('Re: Dinner on Friday?'), findsWidgets);
  });

  Future<DemoMailSource> window(
    WidgetTester tester, {
    VoidCallback? onChanged,
    ValueChanged<MailRow>? onReply,
    VoidCallback? onDone,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now);
    final row = await _row(source, 'Dinner on Friday?');
    await tester.pumpWidget(
      PiumaApp(
        initialDark: dark,
        home: (_, _) => ReaderWindow(
          source: source,
          row: row,
          now: () => _now,
          onChanged: onChanged,
          onReply: onReply,
          onDone: onDone,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return source;
  }

  testWidgets('the window reads, archives and asks for a reply', (
    tester,
  ) async {
    var changed = 0;
    var done = 0;
    final replies = <MailRow>[];
    final source = await window(
      tester,
      onChanged: () => changed++,
      onReply: replies.add,
      onDone: () => done++,
    );
    expect(find.text('Dinner on Friday?'), findsWidgets);
    expect(find.textContaining('bring the new board game'), findsOneWidget);

    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(replies.single.subject, 'Dinner on Friday?');

    await tester.tap(find.bySemanticsLabel('Archive').first);
    await tester.pumpAndSettle();
    expect((changed, done), (1, 1));
    expect(source.applied.single.$2, MessageAction.archive);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('reader window golden $name', (tester) async {
      await window(tester, dark: dark, onReply: (_) {});
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/reader_window_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('search with the new window hint golden', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await _inbox(tester, onOpenWindow: (_) {});
    await _search(tester, 'quote');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('⌘↵'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/search_window_light.png'),
    );
    debugDefaultTargetPlatformOverride = null;
  }, tags: ['golden']);
}
