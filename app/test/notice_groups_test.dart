import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/inbox_tabs.dart';
import 'package:piuma_mail/inbox/swipe.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 28, 10);
MailRow _notice(
  int uid, {
  String sender = 'updates@site.example',
  String subject = 'Plugins updated',
  int account = 1,
  bool seen = false,
}) => MailRow(
  accountId: account,
  mailbox: 'INBOX',
  uid: uid,
  fromName: 'WordPress',
  fromEmail: sender,
  subject: subject,
  preview: 'Automatic plugin update completed ($uid).',
  receivedAt: _now.subtract(Duration(hours: uid * 8)),
  seen: seen,
);

class _Notices extends DemoMailSource {
  _Notices(this.rows) : super(now: _now);
  List<MailRow> rows;
  final events = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => events.stream;
  @override
  bool byPerson(MailRow row) => row.fromEmail == 'person@example.org';
  @override
  Future<List<MailRow>> page(
    int offset,
    int limit, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async => rows.skip(offset).take(limit).toList();
  @override
  Future<List<int>> countsBetween(
    List<DateTime> edges, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async => [
    for (var i = 0; i < edges.length - 1; i++)
      rows
          .where(
            (r) =>
                r.receivedAt.isBefore(edges[i]) &&
                !r.receivedAt.isBefore(edges[i + 1]),
          )
          .length,
  ];
}

Future<void> _pump(
  WidgetTester tester,
  _Notices source, {
  bool dark = false,
  InboxTab tab = InboxTab.notifications,
  void Function(List<MailRow>, bool)? pick,
  ValueChanged<MailRow>? open,
  ValueChanged<List<MailRow>>? archive,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(source.events.close);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => Scaffold(
        body: MessageList(
          source: source,
          selected: null,
          onSelect: open ?? (_) {},
          now: () => _now,
          phone: true,
          tab: tab,
          onPick: pick,
          onNoticeArchive: archive,
          onSwipe: (_) {},
          top: [
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: InboxTabs(
                  phone: true,
                  tab: tab,
                  counts: TabCounts(
                    notificationsUnread: source.rows
                        .where((r) => !r.seen)
                        .length,
                  ),
                  onTab: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('notice key normalizes case and whitespace but preserves account, sender and subject words', () {
    expect(
      sameNotice(_notice(1), _notice(2, subject: '  PLUGINS   updated ')),
      isTrue,
    );
    expect(sameNotice(_notice(1), _notice(2, account: 2)), isFalse);
    expect(
      sameNotice(_notice(1), _notice(2, sender: 'other@site.example')),
      isFalse,
    );
    expect(
      sameNotice(_notice(1), _notice(2, subject: 'Another update')),
      isFalse,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('notice group collapsed and expanded golden $dark', (
      tester,
    ) async {
      final source = _Notices([
        _notice(1, seen: true),
        _notice(2),
        _notice(3),
        _notice(4, sender: 'other@example.org'),
      ]);
      MailRow? opened;
      await _pump(tester, source, dark: dark, open: (row) => opened = row);
      expect(find.text('WordPress · 3 notices'), findsOneWidget);
      expect(find.byType(InboxRowTile), findsNWidgets(2));
      final summary = tester
          .widgetList<InboxRowTile>(find.byType(InboxRowTile))
          .first;
      expect(summary.row.seen, isFalse);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/notice_group_${dark ? 'dark' : 'light'}.png',
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.byType(InboxRowTile), findsNWidgets(5));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/notice_group_expanded_${dark ? 'dark' : 'light'}.png',
        ),
      );
      await tester.tap(find.text('Automatic plugin update completed (2).'));
      expect(opened?.uid, 2);
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.byType(InboxRowTile), findsNWidgets(2));
    });
  }

  for (final tab in [InboxTab.people, InboxTab.all]) {
    testWidgets('no grouping in $tab', (tester) async {
      await _pump(tester, _Notices([_notice(1), _notice(2)]), tab: tab);
      expect(find.byType(InboxRowTile), findsNWidgets(2));
      expect(find.text('Show'), findsNothing);
    });
  }

  testWidgets('a different notice breaks a run; People mail never groups', (
    tester,
  ) async {
    await _pump(
      tester,
      _Notices([
        _notice(1),
        _notice(2, sender: 'other@example.org'),
        _notice(3),
        _notice(4, sender: 'person@example.org'),
        _notice(5, sender: 'person@example.org'),
      ]),
    );
    expect(find.byType(InboxRowTile), findsNWidgets(5));
  });

  testWidgets('picking and archiving the collapsed row pass every member', (
    tester,
  ) async {
    List<MailRow> picked = [], archived = [];
    await _pump(
      tester,
      _Notices([_notice(1), _notice(2), _notice(3)]),
      pick: (rows, on) {
        picked = rows;
      },
      archive: (rows) {
        archived = rows;
      },
    );
    final tile = tester.widget<InboxRowTile>(find.byType(InboxRowTile));
    tile.onPick!();
    expect(picked.map((r) => r.uid), [1, 2, 3]);
    tester.widget<SwipeToArchive>(find.byType(SwipeToArchive)).onArchive();
    expect(archived.map((r) => r.uid), [1, 2, 3]);
  });

  testWidgets('a notice run continues over a loaded page boundary', (
    tester,
  ) async {
    await _pump(tester, _Notices([for (var i = 1; i <= 105; i++) _notice(i)]));
    expect(find.text('WordPress · 105 notices'), findsOneWidget);
    expect(find.byType(InboxRowTile), findsOneWidget);
  });

  testWidgets('all-read group loses its unread state after reload', (
    tester,
  ) async {
    final source = _Notices([_notice(1), _notice(2)]);
    await _pump(tester, source);
    expect(
      tester.widget<InboxRowTile>(find.byType(InboxRowTile)).row.seen,
      isFalse,
    );
    source.rows = [for (final row in source.rows) row.withSeen(true)];
    source.events.add(null);
    await tester.pumpAndSettle();
    expect(
      tester.widget<InboxRowTile>(find.byType(InboxRowTile)).row.seen,
      isTrue,
    );
  });
}
