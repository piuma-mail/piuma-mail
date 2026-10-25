import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/sidebar.dart';
import 'package:piuma_mail/inbox/waiting.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  bool waiting = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, waiting: waiting);
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

Finder _row(String subject) => find.descendant(
  of: find.byType(InboxRowTile),
  matching: find.text(subject),
);

Finder _inSidebar(Finder f) =>
    find.descendant(of: find.byType(Sidebar), matching: f);

Future<void> _openWaiting(WidgetTester tester) async {
  await tester.tap(_inSidebar(find.text('Waiting')));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  test('rows say how long they have waited', () async {
    final source = DemoMailSource(now: _now, waiting: true);
    final count = await source.waitingCount(_now);
    expect((count.all, count.long), (4, 3));
    expect(waitingDays(DateTime(2026, 10, 14, 23), _now), 1);
  });

  testWidgets('Waiting lists sent mail nobody answered', (tester) async {
    await _pump(tester);
    // Three have waited 3 days or more.
    expect(_inSidebar(find.text('Waiting')), findsOneWidget);
    final item = find.ancestor(
      of: _inSidebar(find.text('Waiting')),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: item.first, matching: find.text('3')),
      findsOneWidget,
    );
    await _openWaiting(tester);
    expect(find.text('4 sent · no reply yet'), findsOneWidget);
    expect(_row('Quote for the Acme site'), findsOneWidget);
    expect(find.text('No reply yet'), findsNWidgets(4));
    expect(find.text('5 days'), findsOneWidget);
    expect(find.text('yesterday'), findsOneWidget);
  });

  testWidgets('without waiting mail there is no Waiting', (tester) async {
    await _pump(tester, waiting: false);
    expect(_inSidebar(find.text('Waiting')), findsNothing);
  });

  testWidgets('Write again replies to your own email, to them', (tester) async {
    final source = await _pump(tester);
    await _openWaiting(tester);
    await tester.tap(_row('Quote for the Acme site'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Write again'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    final body = tester
        .widget<TextField>(
          find
              .descendant(
                of: find.byType(ComposePane),
                matching: find.byType(TextField),
              )
              .at(2),
        )
        .controller!
        .text;
    expect(body, contains('> Hi Luca, here is the quote'));
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.to, ['Luca Bianchi <luca.bianchi@example.org>']);
    expect(sent.subject, 'Re: Quote for the Acme site');
    expect(sent.inReplyTo, '<demo-w557@piuma.mail>');
  });

  testWidgets('Stop waiting takes it out; Undo brings it back', (tester) async {
    final source = await _pump(tester);
    await _openWaiting(tester);
    await tester.tap(_row('Quote for the Acme site'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Stop waiting'));
    await tester.pumpAndSettle();
    expect(_row('Quote for the Acme site'), findsNothing);
    expect(find.text('Out of Waiting. It stays in Sent.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_row('Quote for the Acme site'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Stop waiting'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final left = await source.page(0, 10, folder: MailFolder.waiting);
    expect(
      left.map((r) => r.subject),
      isNot(contains('Quote for the Acme site')),
    );
    expect(left, hasLength(3));
  });

  testWidgets('the phone line opens Waiting; a swipe stops waiting', (
    tester,
  ) async {
    final source = await _pump(tester, size: const Size(390, 844));
    expect(find.text('3 sent emails waiting for a reply'), findsOneWidget);
    await tester.tap(find.byType(WaitingLine));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingBack), findsOneWidget);
    await tester.drag(_row('Photos from Saturday'), const Offset(220, 0));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(_row('Photos from Saturday'), findsNothing);
    expect(await source.page(0, 10, folder: MailFolder.waiting), hasLength(3));
    await tester.tap(
      find.descendant(
        of: find.byType(WaitingBack),
        matching: find.text('Inbox'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 sent emails waiting for a reply'), findsOneWidget);
  });

  testWidgets('with one account its own inbox keeps the Waiting line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now, waiting: true);
    source.accounts = [source.accounts.first];
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(WaitingLine), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('accounts and Settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Personal, matteo@posta.it'));
    await tester.pumpAndSettle();
    expect(find.text('Search Personal'), findsOneWidget);
    expect(find.byType(WaitingLine), findsOneWidget);
  });

  testWidgets('Waiting goldens', (tester) async {
    await _pump(tester);
    await _openWaiting(tester);
    await tester.tap(_row('Quote for the Acme site'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/waiting_desktop_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('Waiting phone goldens', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/waiting_phone_line_light.png'),
    );
    await tester.tap(find.byType(WaitingLine));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/waiting_phone_list_light.png'),
    );
  }, tags: ['golden']);
}
