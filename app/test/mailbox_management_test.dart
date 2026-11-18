import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/mailbox_actions.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/swipe.dart';
import 'package:piuma_mail/l10n/app_localizations.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/notify/unread_badge.dart';
import 'package:piuma_mail/settings/list_options.dart';
import 'package:piuma_mail/settings/quota_card.dart';
import 'package:piuma_mail/settings/rules_page.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  source ??= DemoMailSource(now: _now, mailbox: true);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source!, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Iterable<MailRow> _rows(WidgetTester tester) => tester
    .widgetList<InboxRowTile>(find.byType(InboxRowTile))
    .map((t) => t.row);

Future<void> _openRow(WidgetTester tester, String subject) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text(subject),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Shows one of Work's folders from the sidebar.
Future<void> _openWorkFolder(WidgetTester tester, String name) async {
  if (find.text(name).evaluate().isEmpty) {
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starred rows show a star and Starred lists them', (
    tester,
  ) async {
    final source = await _pump(tester);
    final starred = _rows(tester).where((r) => r.starred).toList();
    expect(starred, hasLength(2));
    expect(
      find.bySemanticsLabel(RegExp('Starred')),
      findsWidgets,
      reason: 'a starred row says so',
    );
    await tester.tap(find.text('Starred').first);
    await tester.pumpAndSettle();
    expect(_rows(tester).map((r) => r.subject).toSet(), {
      for (final r in starred) r.subject,
    });
    expect(source.starredSet, isEmpty);
  });

  testWidgets('More stars the open email, S takes the star off', (
    tester,
  ) async {
    final source = await _pump(tester);
    final row = _rows(tester).firstWhere((r) => !r.starred);
    await _openRow(tester, row.subject);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    expect(source.starredSet.last.$1.key, row.key);
    expect(source.starredSet.last.$2, isTrue);
    expect(_rows(tester).firstWhere((r) => r.key == row.key).starred, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(source.starredSet.last.$2, isFalse);
  });

  testWidgets('picked rows are starred together', (tester) async {
    final source = await _pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final picked = _rows(tester).length;
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    expect(source.starredSet.where((s) => s.$2), hasLength(picked));
  });

  testWidgets('Empty Trash says how many go, then empties it', (tester) async {
    final source = await _pump(tester);
    await _openWorkFolder(tester, 'Trash');
    expect(_rows(tester), hasLength(2));
    await tester.tap(find.text('Empty Trash'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all 2 emails in Trash for good?'), findsOneWidget);
    // Cancel keeps them.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(source.emptied, isEmpty);
    await tester.tap(find.text('Empty Trash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    expect(source.emptied, ['Trash']);
    expect(_rows(tester), isEmpty);
  });

  testWidgets('Delete in Trash asks and deletes for good, without Undo', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openWorkFolder(tester, 'Trash');
    final row = _rows(tester).first;
    await _openRow(tester, row.subject);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this email for good?'), findsOneWidget);
    await tester.tap(find.text('Delete for good'));
    await tester.pumpAndSettle();
    expect(source.erased.map((r) => r.key), [row.key]);
    // Nothing went to Trash, and there is no Undo.
    expect(source.applied, isEmpty);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('the folder tree opens and closes, hidden folders on demand', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('Archive 2019'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Hide the folders in Clients'));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsNothing);
    expect(find.text('Clients'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Show the folders in Clients'));
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsOneWidget);
    await tester.ensureVisible(find.text('Show 1 hidden folder'));
    await tester.tap(find.text('Show 1 hidden folder'));
    await tester.pumpAndSettle();
    expect(find.text('Archive 2019'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget);
    await tester.ensureVisible(find.text('Hide hidden folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide hidden folders'));
    await tester.pumpAndSettle();
    expect(find.text('Archive 2019'), findsNothing);
  });

  testWidgets('a row dragged onto a folder moves there, with Undo', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Work').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    final row = _rows(tester).first;
    final from = tester.getCenter(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text(row.subject),
      ),
    );
    final to = tester.getCenter(find.text('Invoices'));
    final drag = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await drag.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('Moved to Invoices'), findsOneWidget);
    // Sent after the Undo window.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.moved.map((m) => (m.$1.key, m.$2)), [(row.key, 'Invoices')]);
  });

  testWidgets('sorting and conversations follow Settings › Reading', (
    tester,
  ) async {
    final source = DemoMailSource(now: _now, mailbox: true);
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: SingleChildScrollView(child: ListOptions(source: source)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.listPrefs.value, const ListPrefs());
    await tester.tap(find.text('Oldest first'));
    await tester.pumpAndSettle();
    expect(source.listPrefs.value.order, ListOrder.oldest);
    await tester.tap(find.bySemanticsLabel('Group into conversations'));
    await tester.pumpAndSettle();
    expect(source.listPrefs.value.threads, isFalse);
    expect(find.text('Off, every email is a row of its own.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Swipe left: Snooze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(source.listPrefs.value.swipeLeft, SwipeChoice.delete);

    // The inbox follows: oldest first, no date headers.
    await _pump(tester, source: source);
    final shown = _rows(tester).map((r) => r.receivedAt).toList();
    expect(shown, [...shown]..sort());
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('the swipes do what they were set to', (tester) async {
    final source = DemoMailSource(now: _now, mailbox: true);
    await source.setListPrefs(
      const ListPrefs(
        swipeRight: SwipeChoice.star,
        swipeLeft: SwipeChoice.nothing,
      ),
    );
    await _pump(tester, size: const Size(390, 844), source: source);
    final swipe = tester.widget<SwipeToArchive>(
      find.byType(SwipeToArchive).first,
    );
    expect(swipe.label, 'Star');
    expect(swipe.archiveStays, isTrue);
    expect(swipe.onSnooze, isNull);
    final row = _rows(tester).first;
    swipe.onArchive();
    await tester.pumpAndSettle();
    expect(source.starredSet.last.$1.key, row.key);
    expect(source.starredSet.last.$2, !row.starred);
  });

  testWidgets('folders are renamed and deleted from Folders & labels', (
    tester,
  ) async {
    final source = DemoMailSource(now: _now, mailbox: true);
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final folders = {
      for (final a in source.accounts) a.id: await source.folders(a.id),
    };
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: FoldersAndLabels(
              source: source,
              folders: folders,
              labels: const [],
              onChanged: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More for “Invoices”'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Bills');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    expect(find.text('Bills'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More for “Clients”'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete folder'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Clients”?'), findsOneWidget);
    expect(find.textContaining('Its 64 emails go to Trash.'), findsOneWidget);
    expect(find.textContaining('Its 2 subfolders go with it.'), findsOneWidget);
    await tester.tap(find.text('Delete folder').last);
    await tester.pumpAndSettle();
    expect(find.text('Clients'), findsNothing);
    expect(find.text('Acme'), findsNothing);
  });

  testWidgets('a folder of the person’s choice does a job', (tester) async {
    final source = DemoMailSource(now: _now, mailbox: true);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final work = source.accounts.firstWhere((a) => a.name == 'Work');
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: SpecialFolders(source: source, account: work),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Trash: Trash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Invoices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();
    final trash = source
        .specialFolders(work.id)
        .firstWhere((f) => f.role == SpecialRole.trash);
    expect(trash.mailbox, 'Invoices');
    expect(trash.chosen, isTrue);
    expect(find.text('Chosen by you'), findsOneWidget);
  });

  testWidgets('storage shows, with a word when nearly full', (tester) async {
    final source = DemoMailSource(now: _now, mailbox: true);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: Column(
            children: [
              QuotaCard(source: source, accountId: 2),
              QuotaCard(source: source, accountId: 1),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Storage'), findsNWidgets(2));
    expect(find.text('15 GB of 16 GB'), findsOneWidget);
    expect(find.textContaining('Nearly full.'), findsOneWidget);
  });

  testWidgets('the unread count goes to the app’s icon', (tester) async {
    UnreadBadge.reset();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      UnreadBadge.channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        UnreadBadge.channel,
        null,
      ),
    );
    final source = await _pump(tester);
    final unread = await source.inboxUnread();
    expect(calls, isNotEmpty);
    final args = calls.last.arguments as Map;
    expect(args['count'], unread);
    expect(args['title'], 'Piuma Mail ($unread)');
    expect(UnreadBadge.count, unread);
  });

  test('hidden folders and closed parents leave the sidebar', () {
    const list = [
      AccountFolder(mailbox: 'A', name: 'A'),
      AccountFolder(mailbox: 'A/B', name: 'B', depth: 1, subscribed: false),
      AccountFolder(mailbox: 'A/B/C', name: 'C', depth: 2),
      AccountFolder(mailbox: 'D', name: 'D', subscribed: false),
    ];
    List<String> names(List<AccountFolder> l) => [for (final f in l) f.name];
    // B is hidden but holds C, which shows: B shows as its parent.
    expect(names(shownFolders(list)), ['A', 'B', 'C']);
    expect(names(shownFolders(list, hidden: true)), ['A', 'B', 'C', 'D']);
    expect(names(shownFolders(list, closed: {'A'})), ['A']);
    expect(hasSubfolders(list, 0), isTrue);
    expect(hasSubfolders(list, 3), isFalse);
  });

  test('every language has the new words', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      expect(l.emptyTitle(2, 'X'), contains('2'));
      expect(l.folderDeleteEmails(3), contains('3'));
      expect(l.starredMany(1), isNotEmpty);
    }
  });
}
