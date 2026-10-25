// End to end: the Dart side, the Rust engine and a real IMAP server.
//
//   tools/test-imap-server.sh &
//   cargo build -p piuma_bridge
//   PIUMA_TEST_IMAP=127.0.0.1:31143 PIUMA_TEST_MEMORY_KEYCHAIN=1 \
//     flutter test test/engine_e2e_test.dart
//
// Skipped unless PIUMA_TEST_IMAP is set.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/engine/api/engine.dart' as engine;
import 'package:piuma_mail/engine/frb_generated.dart';
import 'package:piuma_mail/mail/engine_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';

final _server = Platform.environment['PIUMA_TEST_IMAP'];

/// Puts a message in a mailbox, like a mail server receiving it.
Future<void> deliver(String user, String subject, {String? raw}) async {
  final (host, port) = _hostPort();
  final socket = await Socket.connect(host, port);
  final lines = socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  Future<void> until(String prefix) =>
      lines.firstWhere((l) => l.startsWith(prefix));
  await until('* OK');
  socket.write('a LOGIN $user test\r\n');
  await until('a OK');
  raw ??=
      'From: Julia Reed <julia@example.org>\r\n'
      'Subject: $subject\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n\r\n'
      'Body of $subject.\r\n';
  socket.write('b APPEND INBOX {${utf8.encode(raw).length}+}\r\n$raw\r\n');
  await until('b OK');
  socket.write('c LOGOUT\r\n');
  await socket.close();
}

/// A tiny SMTP server that keeps what it receives.
Future<(int, List<String>)> smtpSink() async {
  final server = await ServerSocket.bind('127.0.0.1', 0);
  final received = <String>[];
  server.listen((socket) {
    final data = StringBuffer();
    var inData = false;
    socket.write('220 sink\r\n');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (inData) {
            if (line == '.') {
              inData = false;
              received.add(data.toString());
              socket.write('250 queued\r\n');
            } else {
              data.writeln(line);
            }
            return;
          }
          final cmd = line.toUpperCase();
          if (cmd.startsWith('EHLO')) {
            socket.write('250-sink\r\n250 AUTH PLAIN\r\n');
          } else if (cmd.startsWith('AUTH')) {
            socket.write('235 ok\r\n');
          } else if (cmd == 'DATA') {
            inData = true;
            socket.write('354 go on\r\n');
          } else if (cmd == 'QUIT') {
            socket.write('221 bye\r\n');
            socket.close();
          } else {
            socket.write('250 ok\r\n');
          }
        });
  });
  return (server.port, received);
}

/// How many messages a folder holds.
Future<int> countIn(String user, String folder) async {
  final (host, port) = _hostPort();
  final socket = await Socket.connect(host, port);
  final lines = socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  await lines.firstWhere((l) => l.startsWith('* OK'));
  socket.write('a LOGIN $user test\r\nb SELECT $folder\r\n');
  final exists = await lines.firstWhere((l) => l.endsWith(' EXISTS'));
  socket.write('c LOGOUT\r\n');
  await socket.close();
  return int.parse(exists.split(' ')[1]);
}

/// How many messages of a folder are unread on the server.
Future<int> unseenIn(String user, String folder) async {
  final (host, port) = _hostPort();
  final socket = await Socket.connect(host, port);
  final lines = socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  await lines.firstWhere((l) => l.startsWith('* OK'));
  socket.write('a LOGIN $user test\r\nb STATUS $folder (UNSEEN)\r\n');
  final status = await lines.firstWhere((l) => l.startsWith('* STATUS'));
  socket.write('c LOGOUT\r\n');
  await socket.close();
  return int.parse(RegExp(r'UNSEEN (\d+)').firstMatch(status)!.group(1)!);
}

(String, int) _hostPort() {
  final parts = _server!.split(':');
  return (parts[0], int.parse(parts[1]));
}

void main() {
  test('add an account, sync it, read, get new mail, send', () async {
    final root = Directory.current.parent.path;
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '$root/target/debug/libpiuma_bridge.so',
      ),
    );
    final dir = await Directory.systemTemp.createTemp('piuma-e2e');
    addTearDown(() => dir.delete(recursive: true));
    engine.openEngine(dbPath: '${dir.path}/piuma.db');

    final user = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
    await deliver(user, 'First');
    await deliver(user, 'Second');

    final source = EngineMailSource();
    expect(source.accounts, isEmpty);
    final (host, port) = _hostPort();

    await expectLater(
      source.addImapAccount(
        name: 'Test',
        email: '$user@example.org',
        color: const Color(0xFF2F8F83),
        host: host,
        port: port,
        security: ServerSecurity.none,
        username: user,
        password: 'wrong',
      ),
      throwsA(
        isA<AddAccountException>().having(
          (e) => e.error,
          'error',
          AddAccountError.wrongPassword,
        ),
      ),
    );

    final (smtpPort, outbox) = await smtpSink();
    final account = await source.addImapAccount(
      name: 'Test',
      email: '$user@example.org',
      color: const Color(0xFF2F8F83),
      host: host,
      port: port,
      security: ServerSecurity.none,
      username: user,
      password: 'test',
      senderName: 'Test Person',
      smtp: MailServer('127.0.0.1', smtpPort, ServerSecurity.none),
    );
    expect(source.accounts.single.id, account.id);

    Future<void> waitForCount(int n) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (await source.inboxCount() != n) {
        if (DateTime.now().isAfter(deadline)) {
          fail('inbox never reached $n messages');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await waitForCount(2);
    final rows = await source.page(0, 10);
    expect(rows.map((r) => r.subject), ['Second', 'First']);
    expect(rows.first.sender, 'Julia Reed');
    expect(await source.body(rows.first), 'Body of Second.');

    final noticed = source.notices.first;
    final sent = DateTime.now();
    await deliver(user, 'Third');
    await waitForCount(3);
    expect(
      DateTime.now().difference(sent),
      lessThan(const Duration(seconds: 2)),
    );
    expect((await source.page(0, 1)).single.subject, 'Third');

    // New mail from a person is worth a notification, and opens from it.
    final notice = (await noticed.timeout(const Duration(seconds: 5))).single;
    expect((notice.sender, notice.subject), ('Julia Reed', 'Third'));
    final opened = await source.messageRow(
      notice.accountId,
      notice.mailbox,
      notice.uid,
    );
    expect(opened?.subject, 'Third');
    final settings = await source.notifySettings();
    expect(settings.mode, NotifyMode.people);
    await source.setNotifySettings(
      settings.copyWith(quietFrom: 0, quietTo: 60),
    );
    expect(source.quietAt(30), isTrue);
    expect(source.quietAt(60), isFalse);

    // Search: words anywhere, the body once it has been read, operators.
    final found = await source.search('secon');
    expect(found.hits.map((h) => h.row.subject), ['Second']);
    expect(found.hits.single.snippet, 'Body of \u0002Second\u0003.');
    expect(found.searched, 3);
    expect((await source.search('from:julia')).total, 3);
    expect((await source.search('third is:unread')).total, 1);
    expect((await source.search('julia account:nobody')).total, 0);

    await source.send(
      Draft(
        accountId: account.id,
        to: const ['Julia Reed <julia@example.org>'],
        subject: 'Re: Third',
        body: 'Got it, thanks.',
      ),
    );
    expect(outbox, hasLength(1));
    expect(outbox.single, contains('Subject: Re: Third'));
    expect(outbox.single, contains('From: "Test Person" <$user@example.org>'));
    expect(await countIn(user, 'Sent'), 1);

    // A signature goes out as text and HTML, with the lines the app shows.
    final work = MailSignature(
      accountId: account.id,
      label: 'Work',
      name: 'Test Person',
      role: 'Designer',
      company: 'Studio',
      phone: '+39 333',
      website: 'studio.example',
      forNew: true,
    );
    final signatureId = await source.saveSignature(work);
    expect((await source.signatures()).single.forNew, isTrue);
    for (final template in SignatureTemplate.values) {
      final s = work.copyWith(template: template);
      expect(
        engine.signatureLines(
          signature: engine.SignatureInfo(
            id: 0,
            accountId: s.accountId,
            label: s.label,
            template: engine.SignatureTemplate.values.byName(template.name),
            name: s.name,
            role: s.role,
            company: s.company,
            phone: s.phone,
            website: s.website,
            accent: engine.SignatureAccent.blue,
            forNew: false,
            forReplies: false,
          ),
        ),
        s.lines,
        reason: template.name,
      );
    }
    await source.send(
      Draft(
        accountId: account.id,
        to: const ['julia@example.org'],
        subject: 'Signed',
        body: 'Hello.',
        signatureId: signatureId,
      ),
    );
    expect(outbox, hasLength(2));
    expect(outbox.last, contains('multipart/alternative'));
    expect(outbox.last, contains('studio.example'));
    expect(await countIn(user, 'Sent'), 2);

    // Send later: it waits in the Outbox with its time, then goes on its
    // own, dated when it went.
    final at = DateTime.fromMillisecondsSinceEpoch(
      (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2) * 1000,
    );
    await source.schedule(
      Draft(
        accountId: account.id,
        to: const ['julia@example.org'],
        subject: 'Later',
        body: 'In a moment.',
      ),
      at,
    );
    expect((await source.outbox(null)).single.sendAt, at);
    expect(outbox, hasLength(2));
    for (var i = 0; i < 50 && outbox.length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(outbox, hasLength(3));
    expect(outbox.last, contains('Subject: Later'));
    expect(await source.outbox(null), isEmpty);

    // Mute: kept by sender, whatever the case of the address.
    expect(await source.isMuted('julia@example.org'), isFalse);
    await source.setMuted('Julia@Example.org', true);
    expect(await source.isMuted('julia@example.org'), isTrue);
    await source.setMuted('julia@example.org', false);
    expect(await source.isMuted('julia@example.org'), isFalse);

    // Snooze the newest message: it waits in Snoozed with its time, then
    // comes back to the inbox, unread.
    final later = DateTime.now().add(const Duration(hours: 1));
    final until = DateTime.fromMillisecondsSinceEpoch(
      later.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    await source.snooze([(await source.page(0, 1)).single], until);
    expect(await countIn(user, 'Snoozed'), 1);
    expect(await source.inboxCount(), 2);
    final snoozed = await source.page(0, 10, folder: MailFolder.snoozed);
    expect(snoozed.single.subject, 'Third');
    expect(snoozed.single.snoozedUntil, until);
    expect(await source.snoozedCount(), 1);
    await source.wake(snoozed);
    expect(await countIn(user, 'Snoozed'), 0);
    await waitForCount(3);
    expect(await source.snoozedCount(), 0);
    expect((await source.page(0, 1)).single.seen, isFalse);

    // Archive the newest message: hidden at once, moved on the server.
    final third = (await source.page(0, 1)).single;
    source.setHidden(third, true);
    expect(await source.inboxCount(), 2);
    await source.apply([third], MessageAction.archive);
    expect(await countIn(user, 'Archive'), 1);
    expect(await countIn(user, 'INBOX'), 2);
    expect(await source.inboxCount(), 2);

    // Read and unread, then archive, for both at once.
    final both = await source.page(0, 2);
    await source.setSeen(both, false);
    expect(await unseenIn(user, 'INBOX'), 2);
    expect(await source.inboxUnread(), 2);
    await source.setSeen(both, true);
    expect(await unseenIn(user, 'INBOX'), 0);
    expect(await source.inboxUnread(), 0);
    for (final r in both) {
      source.setHidden(r, true);
    }
    await source.apply(both, MessageAction.archive);
    expect(await countIn(user, 'Archive'), 3);
    expect(await countIn(user, 'INBOX'), 0);
    expect(await source.inboxCount(), 0);

    // A rule: new mail it matches is archived as it lands, with no notice;
    // what was here before is only counted.
    final ruleId = await source.saveRule(
      const MailRule(
        field: RuleField.subject,
        value: 'receipt',
        action: RuleAction.archive,
      ),
    );
    expect(
      await source.rulePreview(
        const MailRule(
          field: RuleField.subject,
          value: 'third',
          action: RuleAction.archive,
        ),
      ),
      isEmpty,
    );
    final quiet = source.notices.first;
    await deliver(user, 'Receipt 42');
    await deliver(user, 'Hello again');
    await waitForCount(1);
    expect((await source.page(0, 1)).single.subject, 'Hello again');
    for (var i = 0; await countIn(user, 'Archive') != 4; i++) {
      if (i > 100) fail('the rule did not archive');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final ran = (await source.rules()).single;
    expect((ran.id, ran.matched), (ruleId, 1));
    expect(ran.lastRun, isNotNull);
    final told = await quiet.timeout(const Duration(seconds: 5));
    expect(told.map((n) => n.subject), ['Hello again']);
    await source.deleteRule(ruleId);
    expect(await source.rules(), isEmpty);

    // An invite: its card comes from the calendar part, and the answer goes
    // back to the organizer as an iTIP REPLY.
    await deliver(
      user,
      'Lunch',
      raw:
          'From: Julia Reed <julia@example.org>\r\n'
          'Subject: Lunch\r\n'
          'Message-ID: <lunch@example.org>\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: multipart/alternative; boundary=b\r\n\r\n'
          '--b\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n\r\n'
          'Lunch on Monday?\r\n'
          '--b\r\n'
          'Content-Type: text/calendar; charset=utf-8; method=REQUEST\r\n\r\n'
          'BEGIN:VCALENDAR\r\n'
          'VERSION:2.0\r\n'
          'METHOD:REQUEST\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:lunch-1@example.org\r\n'
          'DTSTAMP:20261018T080000Z\r\n'
          'DTSTART:20261019T110000Z\r\n'
          'DTEND:20261019T120000Z\r\n'
          'SUMMARY:Lunch\r\n'
          'LOCATION:Corner café\r\n'
          'ORGANIZER;CN=Julia Reed:mailto:julia@example.org\r\n'
          'ATTENDEE;PARTSTAT=NEEDS-ACTION;CN=Test Person:mailto:$user@example.org\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n'
          '--b--\r\n',
    );
    await waitForCount(2);
    final lunch = (await source.page(0, 1)).single;
    expect(lunch.subject, 'Lunch');
    final invite = (await source.readable(lunch)).invite!;
    expect(invite.summary, 'Lunch');
    expect(invite.location, 'Corner café');
    expect(invite.start, DateTime.utc(2026, 10, 19, 11).toLocal());
    expect(invite.organizer?.email, 'julia@example.org');
    expect(invite.answer, isNull);
    expect(invite.answerable, isTrue);
    final before = outbox.length;
    await source.answerInvite(
      lunch,
      InviteAnswer.accepted,
      subject: 'Accepted: Lunch',
      text: 'Test Person accepted.',
    );
    expect(outbox, hasLength(before + 1));
    expect(outbox.last, contains('Subject: Accepted: Lunch'));
    expect(outbox.last, contains('In-Reply-To: <lunch@example.org>'));
    expect(outbox.last, contains('method=REPLY'));
    expect(outbox.last, contains('PARTSTAT=ACCEPTED'));
    expect(
      (await source.readable(lunch)).invite!.answer,
      InviteAnswer.accepted,
    );

    // A calendar feed: subscribed read-only, it counts for availability
    // once switched on, and goes when disconnected.
    final feed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(feed.close);
    feed.listen((request) {
      request.response
        ..headers.contentType = ContentType('text', 'calendar')
        ..write(
          'BEGIN:VCALENDAR\r\nX-WR-CALNAME:Shifts\r\nBEGIN:VEVENT\r\n'
          'UID:shift-1\r\nDTSTART:20261019T080000Z\r\n'
          'DTEND:20261019T120000Z\r\nSUMMARY:Morning shift\r\n'
          'END:VEVENT\r\nEND:VCALENDAR\r\n',
        )
        ..close();
    });
    final shifts = await source.subscribeCalendar(
      'http://127.0.0.1:${feed.port}/shifts.ics',
    );
    expect(shifts.name, 'Shifts');
    expect(shifts.kind, CalendarKind.ics);
    expect(shifts.calendars.single.readOnly, isTrue);
    final monday = (
      DateTime.utc(2026, 10, 19, 7),
      DateTime.utc(2026, 10, 19, 13),
    );
    expect(await source.busyBetween(monday.$1, monday.$2), isEmpty);
    await source.setCalendarAvailability(shifts.calendars.single.id, true);
    final busy = await source.busyBetween(monday.$1, monday.$2);
    expect(busy.single.summary, 'Morning shift');
    expect(busy.single.start, DateTime.utc(2026, 10, 19, 8).toLocal());
    // Read-only: invites can't go there.
    expect((await source.calendarPrefs()).defaultCalendar, isNull);
    await source.disconnectCalendar(shifts.id);
    expect(await source.calendarSources(), isEmpty);

    await expectLater(
      source.send(Draft(accountId: account.id, to: const ['julia'])),
      throwsA(
        isA<SendException>()
            .having((e) => e.error, 'error', SendError.badAddress)
            .having((e) => e.detail, 'detail', 'julia'),
      ),
    );
    source.dispose();
  }, skip: _server == null ? 'set PIUMA_TEST_IMAP to run' : false);
}
