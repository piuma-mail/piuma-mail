import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Counts how often the inbox list is read, each read taking a while.
class _Counting extends DemoMailSource {
  _Counting() : super(now: _now);

  final ticks = StreamController<void>.broadcast();
  int reads = 0;

  @override
  Stream<void> get changes => ticks.stream;

  @override
  Future<List<int>> countsBetween(
    List<DateTime> edges, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async {
    if (folder == MailFolder.inbox && mailbox == null) reads++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.countsBetween(
      edges,
      folder: folder,
      account: account,
      mailbox: mailbox,
      tab: tab,
      unread: unread,
      group: group,
    );
  }
}

Future<_Counting> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = _Counting();
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('one change reads the list once', (tester) async {
    final source = await _pump(tester);
    final before = source.reads;
    source.ticks.add(null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // The labels read again with it are the same: no second read.
    expect(source.reads - before, 1);
  });

  testWidgets('changes during a read fold into one more', (tester) async {
    final source = await _pump(tester);
    final before = source.reads;
    for (var i = 0; i < 10; i++) {
      source.ticks.add(null);
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(source.reads - before, lessThanOrEqualTo(3));
  });

  testWidgets('back to the Inbox, its rows show at once', (tester) async {
    await _pump(tester);
    Finder rows() => find.byType(InboxRowTile);
    expect(rows(), findsWidgets);
    Finder side(String t) =>
        find.descendant(of: find.byType(Sidebar), matching: find.text(t));
    await tester.tap(side('Archive'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(side('Unified inbox'));
    // One frame: the read takes longer, the rows are there already.
    await tester.pump();
    expect(rows(), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
