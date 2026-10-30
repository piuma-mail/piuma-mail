import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  DemoMailSource? using,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = using ?? DemoMailSource(now: _now);
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
  return source;
}

Future<void> _openPrintQuote(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(InboxRowTile),
      matching: find.text('Re: Print quote'),
    ),
  );
  await tester.pumpAndSettle();
}

/// A device with its own model, which words the brief its way.
class _WithModel extends DemoMailSource {
  _WithModel() : super(now: _now);

  @override
  Future<ThreadBrief?> rewriteBrief(ThreadBrief brief) async => ThreadBrief(
    points: const ['Matteo chose the 120 g paper: €640, delivered Oct 28.'],
    yourTurn: brief.yourTurn,
    askedBy: brief.askedBy,
    byModel: true,
  );
}

/// A conversation of [n] messages, read except the last [unread].
class _LongThread extends DemoMailSource {
  _LongThread(this.n, this.unread) : super(now: _now);
  final int n;
  final int unread;

  MailRow message(int i) => MailRow(
    accountId: 2,
    mailbox: 'INBOX',
    uid: i + 1,
    fromName: i.isEven ? 'Sara Conti' : 'Luca Bianchi',
    fromEmail: i.isEven ? 'sara@studio.it' : 'luca@studio.it',
    subject: 'Re: Print quote',
    preview: 'Message number ${i + 1}',
    receivedAt: _now.subtract(Duration(hours: n - i)),
    seen: i < n - unread,
    messageId: '<long-$i@x>',
    thread: '<long-0@x>',
    messages: n,
  );

  @override
  Future<List<MailRow>> conversation(MailRow row) async => [
    for (var i = 0; i < n; i++) message(i),
  ];
}

/// The print quote on the phone, as `FeatureThread`: your messages, and
/// files in two of them.
class _PhoneThread extends _LongThread {
  _PhoneThread() : super(12, 2);

  @override
  Future<ThreadBrief?> threadBrief(MailRow row) async => const ThreadBrief(
    points: ['Let’s go with the 120 g paper.'],
    yourTurn: 'I just need the final file by Friday.',
    askedBy: 'Sara',
  );

  @override
  MailRow message(int i) {
    final m = super.message(i);
    final mine = i % 3 == 0;
    return MailRow(
      accountId: m.accountId,
      mailbox: m.mailbox,
      uid: m.uid,
      fromName: mine ? 'Matteo' : m.fromName,
      fromEmail: mine ? 'matteo@studio.it' : m.fromEmail,
      subject: m.subject,
      preview: m.preview,
      receivedAt: m.receivedAt,
      seen: m.seen,
      messageId: m.messageId,
      thread: m.thread,
      messages: m.messages,
      files: i == 10 ? 2 : (i == 1 ? 1 : 0),
    );
  }
}

Future<void> _pumpReader(
  WidgetTester tester,
  _LongThread source, {
  bool phone = false,
  bool dark = false,
  double width = 900,
}) async {
  tester.view.physicalSize = phone ? const Size(390, 844) : Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => Scaffold(
        body: Reader(
          source: source,
          row: source.message(source.n - 1),
          now: () => _now,
          phone: phone,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SingleBrief extends _LongThread {
  _SingleBrief() : super(1, 1);

  @override
  Future<ThreadBrief?> threadBrief(MailRow row) async => const ThreadBrief(
    points: ['The season budget is €2500.'],
    yourTurn: 'Please send a quote.',
    askedBy: 'Sara',
  );
}

void main() {
  for (final width in [1299.0, 1300.0, 1600.0]) {
    testWidgets('reading follows pane width $width', (tester) async {
      await _pumpReader(tester, _SingleBrief(), width: width);
      // From 1300 points the column is centered and 920 wide.
      expect(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 920,
        ),
        width >= 1300 ? findsOneWidget : findsNothing,
      );
    });
  }
  for (final dark in [false, true]) {
    testWidgets('wide reader golden, dark=$dark', (tester) async {
      await _pumpReader(tester, _SingleBrief(), width: 1400, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/wide_reader_${dark ? 'dark' : 'light'}.png',
        ),
      );
    }, tags: ['golden']);
  }

  for (final phone in [false, true]) {
    testWidgets('single email summary, phone=$phone', (tester) async {
      await _pumpReader(tester, _SingleBrief(), phone: phone);
      expect(find.byType(InShort), phone ? findsNothing : findsOneWidget);
      if (phone) {
        await tester.tap(find.text('Summary'));
        await tester.pumpAndSettle();
        expect(find.byType(InShort), findsOneWidget);
      }
    });
  }

  testWidgets('a conversation is one row, with how many messages it has', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(InboxRowTile), findsNWidgets(5));
    expect(find.text('4 messages'), findsOneWidget);
  });

  testWidgets('the reader shows the whole conversation', (tester) async {
    await _pump(tester);
    await _openPrintQuote(tester);
    expect(find.text('4 messages · Sara, you'), findsOneWidget);
    // Earlier messages are closed, showing their first words.
    expect(
      find.text(
        'Could I get a quote for 500 catalogs, A5, 32 pages? Samples of '
        'the 120 g and 150 g paper would help.',
      ),
      findsOneWidget,
    );
    // The last one is open, its quote folded away.
    expect(find.textContaining('perfect, let’s go with'), findsOneWidget);
    expect(find.text('··· quoted text hidden'), findsOneWidget);
    await tester.tap(find.text('··· quoted text hidden'));
    await tester.pumpAndSettle();
    expect(find.text('··· quoted text hidden'), findsNothing);
    expect(find.textContaining('Matteo wrote:'), findsOneWidget);

    // Opening one of mine says who it went to.
    await tester.tap(
      find.text('The 120 g feels great, let’s go with it.').first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('to Sara Conti · yesterday at 16:45'),
      findsOneWidget,
    );
  });

  testWidgets('an earlier message opened, as from search, starts open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now);
    final latest = (await source.page(
      0,
      20,
    )).firstWhere((r) => r.subject == 'Re: Print quote');
    final first = (await source.conversation(latest)).first;
    await tester.pumpWidget(
      PiumaApp(
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
    expect(find.text('4 messages · Sara, you'), findsOneWidget);
    // Open, so it says who it went to; the last one is open too.
    expect(find.textContaining('to Sara Conti ·'), findsOneWidget);
    expect(find.textContaining('perfect, let’s go with'), findsOneWidget);
  });

  testWidgets('archiving a conversation takes all of it in the inbox', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _openPrintQuote(tester);
    await tester.tap(find.byTooltip('Archive'));
    // The row folds away first.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('4 messages'), findsNothing);
    expect(source.applied.map((a) => (a.$1.uid, a.$2)), [
      (98, MessageAction.archive),
      (92, MessageAction.archive),
    ]);
  });

  testWidgets('a long conversation opens with In short', (tester) async {
    await _pump(tester);
    await _openPrintQuote(tester);
    expect(find.byType(InShort), findsOneWidget);
    expect(find.text('Generated on device'), findsOneWidget);
    expect(find.text('Let’s go with the 120 g paper.'), findsOneWidget);
    expect(
      find.textContaining(
        'Your turn: Sara writes “I just need the final file by Friday.”',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the device model\'s words replace the rules\'', (tester) async {
    await _pump(tester, using: _WithModel());
    await _openPrintQuote(tester);
    expect(
      find.text('Matteo chose the 120 g paper: €640, delivered Oct 28.'),
      findsOneWidget,
    );
    expect(find.text('Let’s go with the 120 g paper.'), findsNothing);
    expect(
      find.textContaining('Your turn: Sara writes', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a long conversation folds its read middle', (tester) async {
    await _pumpReader(tester, _LongThread(12, 2));
    expect(find.text('12 messages · Sara, Luca'), findsOneWidget);
    expect(find.text('7 read messages'), findsOneWidget);
    expect(find.text('2 NEW'), findsOneWidget);
    expect(find.text('Message number 5'), findsNothing);
    await tester.tap(find.text('7 read messages'));
    await tester.pumpAndSettle();
    expect(find.text('Message number 5'), findsOneWidget);
    expect(find.text('7 read messages'), findsNothing);
  });

  testWidgets('on the phone, Summary and the files are buttons', (
    tester,
  ) async {
    await _pumpReader(tester, _PhoneThread(), phone: true);
    expect(find.text('ME'), findsWidgets);
    expect(find.byType(InShort), findsNothing);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.byType(InShort), findsOneWidget);
    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.byType(InShort), findsNothing);

    await tester.tap(find.text('3 attachments'));
    await tester.pumpAndSettle();
    // The messages with files open, the folded ones among them.
    expect(find.textContaining('read messages'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone conversation golden $name', (tester) async {
      await _pumpReader(tester, _PhoneThread(), phone: true, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_conversation_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('conversation golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _openPrintQuote(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conversation_$name.png'),
      );
    }, tags: ['golden']);
  }
}
