import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/remind_me.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/labels.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/original_view.dart';
import 'package:piuma_mail/inbox/print.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/inbox/message_body.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// The desktop inbox with its first email opened from the list ("Dinner
/// on Friday?", or "New autumn arrivals" with [newsletter]).
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  bool dark = false,
  bool newsletter = false,
  bool junk = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RemoteImages.clear();
  final source = DemoMailSource(now: _now, newsletter: newsletter)
    ..junkFolders = junk;
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
  // Opened from the list, so it is read now.
  await tester.tap(
    find
        .descendant(
          of: find.byType(InboxRowTile),
          matching: find.text(first.subject),
        )
        .first,
  );
  await tester.pumpAndSettle();
  return source;
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
}

Future<bool> _seen(DemoMailSource source, String subject) async =>
    (await source.page(0, 50)).firstWhere((r) => r.subject == subject).seen;

void main() {
  testWidgets('More holds what applies, with the keys in mono', (tester) async {
    await _pump(tester);
    await _openMore(tester);
    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Ctrl Shift U'), findsOneWidget);
    expect(find.text('Label…'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('Report spam'), findsOneWidget);
    // A plain email has no original layout; Print has its own button.
    expect(find.text('Original layout'), findsNothing);
    expect(find.text('Print…'), findsNothing);
    expect(find.bySemanticsLabel('Print…'), findsOneWidget);
  });

  testWidgets('the Mac shows ⇧⌘U', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await _pump(tester);
    await _openMore(tester);
    expect(find.text('⇧⌘U'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Mark as unread, then Mark as read', (tester) async {
    final source = await _pump(tester);
    expect(await _seen(source, 'Dinner on Friday?'), isTrue);
    await _openMore(tester);
    await tester.tap(find.text('Mark as unread'));
    await tester.pumpAndSettle();
    expect(await _seen(source, 'Dinner on Friday?'), isFalse);
    // The message stays open, and More now offers the opposite.
    expect(find.text('Dinner on Friday?'), findsWidgets);
    await _openMore(tester);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(await _seen(source, 'Dinner on Friday?'), isTrue);
  });

  testWidgets('Ctrl+Shift+U marks the open email unread, and read again', (
    tester,
  ) async {
    final source = await _pump(tester);
    Future<void> press() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await press();
    expect(await _seen(source, 'Dinner on Friday?'), isFalse);
    await press();
    expect(await _seen(source, 'Dinner on Friday?'), isTrue);
  });

  testWidgets('⇧⌘U does it on the Mac', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final source = await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(await _seen(source, 'Dinner on Friday?'), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Label… opens the labels under More', (tester) async {
    await _pump(tester);
    await _openMore(tester);
    await tester.tap(find.text('Label…'));
    await tester.pumpAndSettle();
    expect(find.byType(LabelPicker), findsOneWidget);
    final more = tester.getRect(find.byTooltip('More actions'));
    final picker = tester.getRect(find.byType(LabelPicker));
    expect(picker.top, greaterThan(more.bottom));
  });

  testWidgets('Report spam moves it to Junk after the Undo window', (
    tester,
  ) async {
    final source = await _pump(tester);
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    await _openMore(tester);
    await tester.tap(find.text('Report spam'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(InboxRowTile), findsNWidgets(4));
    expect(find.text('Reported as spam'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(source.applied, isEmpty);
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied.single.$1.subject, 'Dinner on Friday?');
    expect(source.applied.single.$2, MessageAction.junk);
    await tester.pumpAndSettle();
  });

  testWidgets('Undo keeps a reported email', (tester) async {
    final source = await _pump(tester);
    await _openMore(tester);
    await tester.tap(find.text('Report spam'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    await tester.pump(const Duration(seconds: 15));
    expect(source.applied, isEmpty);
  });

  testWidgets('no spam folder, no Report spam', (tester) async {
    await _pump(tester, junk: false);
    await _openMore(tester);
    expect(find.text('Mark as unread'), findsOneWidget);
    expect(find.text('Report spam'), findsNothing);
  });

  group('original layout', () {
    setUp(() {
      originalPaper = (html, onLink) => Text('${html.length} chars of HTML');
    });
    tearDown(() => originalPaper = null);

    testWidgets('More shows it only while the clean view shows', (
      tester,
    ) async {
      await _pump(tester, newsletter: true);
      // A designed email opens as sent.
      expect(find.byType(OriginalView), findsOneWidget);
      await _openMore(tester);
      expect(find.text('Original layout'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clean'));
      await tester.pumpAndSettle();
      expect(find.byType(OriginalView), findsNothing);
      await _openMore(tester);
      await tester.tap(find.text('Original layout'));
      await tester.pumpAndSettle();
      expect(find.byType(OriginalView), findsOneWidget);
      expect(find.textContaining('chars of HTML'), findsOneWidget);
    });

    testWidgets('without a web view there is none', (tester) async {
      originalPaper = null;
      await _pump(tester, newsletter: true);
      await _openMore(tester);
      expect(find.text('Original layout'), findsNothing);
    });
  });

  testWidgets('in a narrow reader, Print and Forward move into More', (
    tester,
  ) async {
    // The reader is 460 wide beside the sidebar and the list.
    await _pump(tester, size: const Size(1100, 800));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Print…'), findsNothing);
    expect(find.bySemanticsLabel('Forward'), findsNothing);
    await _openMore(tester);
    expect(find.text('Print…'), findsOneWidget);
    expect(find.text('Ctrl P'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
  });

  /// The Waiting folder with "Quote for the Acme site" open, reminded.
  Future<void> pumpWaiting(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now, waiting: true, reminded: true);
    await tester.pumpWidget(
      PiumaApp(
        initialDark: false,
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Sidebar), matching: find.text('Waiting')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(InboxRowTile),
            matching: find.text('Quote for the Acme site'),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Finder inReader(Finder f) =>
      find.descendant(of: find.byType(Reader), matching: f);

  testWidgets('in a 460 Waiting reader, Remind me moves into More', (
    tester,
  ) async {
    // The reader is 460 wide beside the sidebar and the list.
    await pumpWaiting(tester, const Size(1100, 800));
    expect(tester.takeException(), isNull);
    expect(inReader(find.byType(RemindChip)), findsNothing);
    expect(inReader(find.text('Write again')), findsOneWidget);
    await _openMore(tester);
    final remind = find.textContaining('Remind me');
    expect(remind, findsOneWidget);
    // Remind me in More opens the same choices as the chip.
    await tester.tap(remind);
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);
  });

  testWidgets('in a narrower Waiting reader, Write again follows it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now, waiting: true, reminded: true);
    final row = (await source.page(
      0,
      50,
      folder: MailFolder.waiting,
    )).firstWhere((r) => r.subject == 'Quote for the Acme site');
    final wrote = <MailRow>[];
    await tester.pumpWidget(
      PiumaApp(
        initialDark: false,
        // A reader 250 wide, in a window with room for More's menu.
        home: (_, _) => Material(
          child: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 250,
              child: Reader(
                source: source,
                row: row,
                now: () => _now,
                onDelete: (_) {},
                onForward: (_) {},
                onStopWaiting: (_) {},
                onRemind: (_, _) {},
                onWriteAgain: (r, _) => wrote.add(r),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inReader(find.byType(RemindChip)), findsNothing);
    expect(inReader(find.text('Write again')), findsNothing);
    await _openMore(tester);
    expect(find.textContaining('Remind me'), findsOneWidget);
    await tester.tap(find.text('Write again'));
    await tester.pumpAndSettle();
    expect(wrote.single.subject, row.subject);
  });

  testWidgets('Print in More prints', (tester) async {
    tester.view.physicalSize = const Size(520, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now);
    final row = (await source.page(0, 1)).first;
    final printed = <PrintEmail>[];
    await tester.pumpWidget(
      PiumaApp(
        initialDark: false,
        home: (_, _) => Material(
          child: Reader(
            source: source,
            row: row,
            now: () => _now,
            onDelete: (_) {},
            printer: (email) async => printed.add(email),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await _openMore(tester);
    await tester.tap(find.text('Print…'));
    await tester.pumpAndSettle();
    expect(printed.single.subject, row.subject);
  });

  // Golden screenshots, next to `RemindAwayPrintToApprove` on the canvas.
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('more menu golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openMore(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/more_menu_$name.png'),
      );
    }, tags: ['golden']);
  }
}
