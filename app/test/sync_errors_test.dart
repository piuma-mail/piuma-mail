import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/mail/resubscribe.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// A source whose reads and folder refreshes fail on demand, and that
/// reports changes the server gave up on.
class _Failing extends DemoMailSource {
  _Failing() : super(now: _now);

  int failingReads = 0;
  bool refreshFails = false;
  int refreshes = 0;
  final dropped = StreamController<int>.broadcast();

  @override
  Stream<int> get changesDropped => dropped.stream;

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
    if (failingReads > 0) {
      failingReads--;
      throw StateError('database is locked');
    }
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

  @override
  Future<void> refreshFolder(int accountId, String mailbox) async {
    refreshes++;
    if (refreshFails) throw StateError('the server stopped answering');
  }
}

Future<void> _pump(WidgetTester tester, _Failing source) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a list that can’t be read says so, and Try again reads it', (
    tester,
  ) async {
    final source = _Failing()..failingReads = 1;
    await _pump(tester, source);
    expect(find.text('Couldn’t show these emails.'), findsOneWidget);
    expect(find.byType(InboxRowTile), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t show these emails.'), findsNothing);
    expect(find.byType(InboxRowTile), findsWidgets);
  });

  testWidgets('a folder the server didn’t refresh says so, with Try again', (
    tester,
  ) async {
    final source = _Failing()..refreshFails = true;
    await _pump(tester, source);
    await tester.tap(find.bySemanticsLabel('Work folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme'));
    await tester.pump();
    // The toast slides in.
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text('Couldn’t refresh this folder from the server.'),
      findsOneWidget,
    );
    expect(source.refreshes, 1);
    source.refreshFails = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(source.refreshes, 2);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('changes the server gave up on are told', (tester) async {
    final source = _Failing();
    await _pump(tester, source);
    source.dropped.add(2);
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'The server didn’t take 2 changes you made, so those emails are '
        'back as they were.',
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('a sync stream that ends or fails is opened again', (
    tester,
  ) async {
    final opened = <StreamController<int>>[];
    final events = <int>[];
    final sync = Resubscriber<int>(() {
      final c = StreamController<int>();
      opened.add(c);
      return c.stream;
    }, events.add);
    sync.start();
    expect(opened, hasLength(1));
    opened[0].add(1);
    await tester.pump();
    expect(events, [1]);

    // Fails: open again after a second.
    opened[0].addError(StateError('bridge closed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(opened, hasLength(1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, hasLength(2));

    // Ends before any event came: the wait doubles.
    await opened[1].close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(opened, hasLength(2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(opened, hasLength(3));

    // Events flow again: the next wait is short again.
    opened[2].add(2);
    await tester.pump();
    await opened[2].close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(opened, hasLength(4));
    expect(events, [1, 2]);
    sync.cancel();
    await tester.pump(const Duration(minutes: 2));
    expect(opened, hasLength(4));
  });
}
