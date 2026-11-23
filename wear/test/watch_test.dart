import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_wear/done_screen.dart';
import 'package:piuma_wear/link.dart';
import 'package:piuma_wear/main.dart';
import 'package:piuma_wear/summary.dart';

const _channel = MethodChannel('mail.piuma.wear/link');

/// What the phone sends (`app/rust/src/watch.rs`), at 10:09 on Oct 23.
final _now = DateTime(2026, 10, 23, 10, 9);
int _at(int h, int m) =>
    DateTime(2026, 10, 23, h, m).millisecondsSinceEpoch ~/ 1000;

String _summary() => jsonEncode({
  'at': _at(10, 9),
  'accounts': [
    {'id': 1, 'name': 'Personal', 'color': '#E0782F', 'unread': 2},
    {'id': 2, 'name': 'Work', 'color': '#2F8F83', 'unread': 1},
  ],
  'rows': [
    {
      'payload': '1\nINBOX\n41',
      'account': 1,
      'sender': 'Giulia Romano',
      'subject': 'Dinner on Friday?',
      'preview': 'I booked Osteria del Ponte for 20:30',
      'at': _at(10, 2),
      'seen': false,
      'messages': 1,
      'others': 2,
    },
    {
      'payload': '2\nINBOX\n7',
      'account': 2,
      'sender': 'Sara Conti',
      'subject': 'Re: Print quote',
      'preview': 'I need the file by Friday',
      'at': _at(9, 51),
      'seen': false,
      'messages': 2,
    },
    {
      'payload': '1\nINBOX\n40',
      'account': 1,
      'sender': 'Corriere Rapido',
      'subject': 'Your package arrives today',
      'preview': 'Desk lamp, between 10 and 14',
      'at': _at(7, 5),
      'seen': true,
      'messages': 1,
    },
  ],
  'templates': [
    {'name': 'On my way', 'body': "I'm on my way"},
    {'name': 'Thanks', 'body': 'Thanks, got it'},
  ],
});

Future<void> _fromPhone(String method, Object? arguments) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );

/// The app on a Pixel Watch-sized round screen, with what it asked the
/// phone in [asked].
Future<PhoneLink> _pump(WidgetTester tester, List<MethodCall> asked) async {
  tester.view.physicalSize = const Size(456, 456);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        asked.add(call);
        return null;
      });
  final link = PhoneLink();
  await tester.pumpWidget(ClipOval(child: WatchApp(link: link)));
  await _fromPhone('summary', _summary());
  await tester.pumpAndSettle();
  return link;
}

/// Turns the crown to the end of the list on screen.
Future<void> _toEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -400));
  await tester.pumpAndSettle();
}

void main() {
  // The snooze choices and the inbox's times depend on the hour.
  setUp(() => watchNow = () => _now);
  tearDown(() => watchNow = DateTime.now);

  test('the summary reads what the phone sends', () {
    final s = Summary.parse(_summary())!;
    expect(s.unread, 3);
    expect(s.rows.first.sender, 'Giulia Romano');
    expect(s.rows.first.others, 2);
    expect(s.rows[1].others, 0);
    expect(s.account(2)!.color, const Color(0xFF2F8F83));
    expect(s.without('1\nINBOX\n41').rows.length, 2);
    expect(s.templates.first.label, "I'm on my way");
    expect(Summary.parse('not json'), isNull);
    expect(Summary.parse(null), isNull);
  });

  test('snooze times match the phone', () {
    // Friday, Oct 23 2026.
    expect(snoozeTime(SnoozeChoice.evening, _now), DateTime(2026, 10, 23, 18));
    expect(snoozeTime(SnoozeChoice.tomorrow, _now), DateTime(2026, 10, 24, 8));
    expect(snoozeTime(SnoozeChoice.weekend, _now), DateTime(2026, 10, 24, 9));
    expect(snoozeTime(SnoozeChoice.nextWeek, _now), DateTime(2026, 10, 26, 8));
    expect(
      snoozeChoices(DateTime(2026, 10, 23, 17, 30)),
      isNot(contains(SnoozeChoice.evening)),
    );
  });

  testWidgets('waits for the phone, then lists the inbox', (tester) async {
    final asked = <MethodCall>[];
    tester.view.physicalSize = const Size(456, 456);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final link = PhoneLink();
    await tester.pumpWidget(WatchApp(link: link));
    expect(find.text('Reaching your phone…'), findsOneWidget);
    asked.clear();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the app lock on the phone, no mail shows', (tester) async {
    final asked = <MethodCall>[];
    await _pump(tester, asked);
    expect(find.text('Giulia Romano'), findsOneWidget);
    // What `WatchLink.kt` sends while Lock Piuma is on.
    await _fromPhone(
      'summary',
      jsonEncode({
        'at': _at(10, 9),
        'locked': true,
        'accounts': [],
        'rows': [],
        'templates': [],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Giulia Romano'), findsNothing);
    expect(find.text('Inbox'), findsNothing);
    expect(
      find.text(
        'Piuma is locked on your phone. Unlock it there to see your mail '
        'here.',
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_locked.png'),
    );
    expect(Summary.parse(_summary())!.locked, isFalse);
  });

  testWidgets('a summary with mail older than the locked one is dropped', (
    tester,
  ) async {
    final asked = <MethodCall>[];
    final link = await _pump(tester, asked);
    String stamped(int gen, {bool locked = false}) {
      final m = jsonDecode(_summary()) as Map<String, dynamic>;
      m['gen'] = gen;
      if (locked) {
        m
          ..['locked'] = true
          ..['accounts'] = []
          ..['rows'] = []
          ..['templates'] = [];
      }
      return jsonEncode(m);
    }

    await _fromPhone('summary', stamped(10));
    await tester.pumpAndSettle();
    expect(link.summary!.gen, 10);
    await _fromPhone('summary', stamped(12, locked: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Piuma is locked on your phone'), findsOne);
    // Made before the lock closed, it arrives late: not shown.
    await _fromPhone('summary', stamped(11));
    await tester.pumpAndSettle();
    expect(link.summary!.locked, isTrue);
    expect(find.text('Giulia Romano'), findsNothing);
    // Unlocked on the phone: the next one comes after.
    await _fromPhone('summary', stamped(13));
    await tester.pumpAndSettle();
    expect(find.text('Giulia Romano'), findsOneWidget);
    // A locked one is always taken, even out of order: it only hides.
    await _fromPhone('summary', stamped(5, locked: true));
    await tester.pumpAndSettle();
    expect(link.summary!.locked, isTrue);
    expect(find.text('Giulia Romano'), findsNothing);
  });

  testWidgets('what the watch kept is not shown over a newer summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(456, 456);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final kept = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'summary') return kept.future;
          return null;
        });
    final link = PhoneLink();
    final started = link.start();
    // The phone's locked summary arrives first.
    await _fromPhone(
      'summary',
      jsonEncode({
        'gen': 8,
        'at': _at(10, 9),
        'locked': true,
        'accounts': [],
        'rows': [],
        'templates': [],
      }),
    );
    // Then the Data Layer's older copy, with mail.
    final old = jsonDecode(_summary()) as Map<String, dynamic>;
    kept.complete(jsonEncode(old..['gen'] = 7));
    await started;
    expect(link.summary!.locked, isTrue);
    expect(link.summary!.rows, isEmpty);
  });

  testWidgets('an email open when the phone locks closes, and its words go', (
    tester,
  ) async {
    final asked = <MethodCall>[];
    final link = await _pump(tester, asked);
    await tester.tap(find.text('Giulia Romano'));
    await tester.pumpAndSettle();
    await _fromPhone(
      'text',
      jsonEncode({'payload': '1\nINBOX\n41', 'text': 'Bring the board game'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bring the board game'), findsOneWidget);
    await _fromPhone(
      'summary',
      jsonEncode({
        'at': _at(10, 9),
        'locked': true,
        'accounts': [],
        'rows': [],
        'templates': [],
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bring the board game'), findsNothing);
    expect(find.text('Dinner on Friday?'), findsNothing);
    expect(find.textContaining('Piuma is locked on your phone'), findsOne);
    expect(link.text('1\nINBOX\n41'), isNull);
    // A late answer to the open is not kept either.
    await _fromPhone(
      'text',
      jsonEncode({'payload': '1\nINBOX\n41', 'text': 'Bring the board game'}),
    );
    expect(link.text('1\nINBOX\n41'), isNull);
  });

  testWidgets('inbox, reading and archive with Undo', (tester) async {
    final asked = <MethodCall>[];
    await _pump(tester, asked);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('3 new'), findsOneWidget);
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_inbox.png'),
    );

    await tester.tap(find.text('Giulia Romano'));
    await tester.pumpAndSettle();
    expect(asked.last.method, 'open');
    expect(asked.last.arguments, '1\nINBOX\n41');
    await _fromPhone(
      'text',
      jsonEncode({
        'payload': '1\nINBOX\n41',
        'text':
            'I booked Osteria del Ponte for Friday at 20:30, four of us '
            'with Luca and Sara. Bring the new board game if you can!',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('board game'), findsOneWidget);
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_read.png'),
    );

    // Undo: nothing reaches the phone.
    await _toEnd(tester);
    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_done.png'),
    );
    await tester.tap(find.bySemanticsLabel('Undo'));
    await tester.pumpAndSettle();
    expect(asked.where((c) => c.method == 'act'), isEmpty);
    expect(find.text('Giulia Romano'), findsOneWidget);

    // Without Undo, it is archived once the time is up.
    await tester.tap(find.text('Giulia Romano'));
    await tester.pumpAndSettle();
    await _toEnd(tester);
    await tester.tap(find.bySemanticsLabel('Archive'));
    await tester.pumpAndSettle();
    await tester.pump(DoneScreen.undoFor);
    await tester.pumpAndSettle();
    final act = asked.where((c) => c.method == 'act').single;
    final sent = jsonDecode(act.arguments as String) as Map<String, dynamic>;
    expect(sent['payload'], '1\nINBOX\n41');
    expect(sent['action'], 'archive');
    expect(find.text('Giulia Romano'), findsNothing);
  });

  testWidgets('the crown turns only the screen on top', (tester) async {
    await _pump(tester, <MethodCall>[]);
    final inbox = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    await tester.tap(find.text('Giulia Romano'));
    await tester.pumpAndSettle();
    await _fromPhone('rotary', 300.0);
    await tester.pumpAndSettle();
    // The inbox under the email waits for its turn: back on it, it is
    // still at the top.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(inbox.maxScrollExtent, greaterThan(0));
    expect(inbox.pixels, 0);
  });

  testWidgets('reply with a template, and snooze', (tester) async {
    final asked = <MethodCall>[];
    await _pump(tester, asked);
    await tester.tap(find.text('Sara Conti'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to Sara Conti'), findsOneWidget);
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_reply.png'),
    );
    await tester.tap(find.text("I'm on my way"));
    await tester.pumpAndSettle();
    expect(find.text('Sent'), findsOneWidget);
    await tester.pump(DoneScreen.undoFor);
    await tester.pumpAndSettle();
    final reply = jsonDecode(
      asked.lastWhere((c) => c.method == 'act').arguments as String,
    ) as Map<String, dynamic>;
    expect(reply['action'], 'reply');
    expect(reply['text'], "I'm on my way");
    expect(reply['payload'], '2\nINBOX\n7');

    await tester.tap(find.text('Sara Conti'));
    await tester.pumpAndSettle();
    await _toEnd(tester);
    await tester.tap(find.bySemanticsLabel('Snooze'));
    await tester.pumpAndSettle();
    expect(find.text('Snooze until…'), findsOneWidget);
    await expectLater(
      find.byType(ClipOval),
      matchesGoldenFile('goldens/watch_snooze.png'),
    );
    await _toEnd(tester);
    await tester.tap(find.text('Next week'));
    await tester.pumpAndSettle();
    await tester.pump(DoneScreen.undoFor);
    await tester.pumpAndSettle();
    final snooze = jsonDecode(
      asked.lastWhere((c) => c.method == 'act').arguments as String,
    ) as Map<String, dynamic>;
    expect(snooze['action'], 'snooze');
    final until = DateTime.fromMillisecondsSinceEpoch(
      (snooze['until'] as int) * 1000,
    );
    expect(until.weekday, DateTime.monday);
    expect(until.hour, 8);
  });

  testWidgets('reply all, when others got the email too', (tester) async {
    final asked = <MethodCall>[];
    await _pump(tester, asked);
    // Sara's email went to the person alone: no Reply all.
    await tester.tap(find.text('Sara Conti'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Reply'));
    await tester.pumpAndSettle();
    expect(find.text('Reply all'), findsNothing);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Giulia Romano'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Reply'));
    await tester.pumpAndSettle();
    // Reply stays the default; Reply all is one tap away.
    expect(find.text('Reply to Giulia Romano'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    await tester.tap(find.text('Reply all'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to Giulia Romano and 2 others'), findsOneWidget);
    // The templates are further down the round screen.
    await _toEnd(tester);
    await tester.tap(find.text('Thanks, got it'));
    await tester.pumpAndSettle();
    await tester.pump(DoneScreen.undoFor);
    await tester.pumpAndSettle();
    final reply = jsonDecode(
      asked.lastWhere((c) => c.method == 'act').arguments as String,
    ) as Map<String, dynamic>;
    expect(reply['action'], 'replyAll');
    expect(reply['text'], 'Thanks, got it');
    expect(reply['payload'], '1\nINBOX\n41');
  });
}
