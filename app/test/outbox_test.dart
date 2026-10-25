import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _offline = SyncStatus(SyncPhase.offline, offline: true);

/// Offline, as in `Outbox`.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now)
    ..offline = true
    ..status.value = _offline;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

/// Writes to Luca and sends, past the Undo window.
Future<void> _send(
  WidgetTester tester, {
  String subject = 'Re: Mockup v3',
}) async {
  await tester.tap(find.text('Compose'));
  await tester.pumpAndSettle();
  await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>,');
  await tester.enterText(_field(1), subject);
  await tester.enterText(_field(2), 'Fine on the comments.');
  await tester.pump();
  await tester.tap(find.text('Send'));
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mail sent offline waits in the Outbox, then goes', (
    tester,
  ) async {
    final source = await _pump(tester);
    expect(find.byType(OutboxTile), findsNothing);
    expect(
      find.textContaining('outgoing email sends', findRichText: true),
      findsOneWidget,
    );
    await _send(tester);
    expect(source.sent, isEmpty);
    expect(
      find.text('In the Outbox · it goes once you’re back online'),
      findsOneWidget,
    );
    expect(find.text('OUTBOX · 1'), findsOneWidget);
    expect(find.text('To Luca Bianchi'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);

    source.goOnline();
    await tester.pumpAndSettle();
    expect(find.byType(OutboxTile), findsNothing);
    expect(source.sent.single.subject, 'Re: Mockup v3');
  });

  testWidgets('a click opens it again, and Send puts it back', (tester) async {
    final source = await _pump(tester);
    await _send(tester);
    await tester.tap(find.byType(OutboxTile));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.byType(OutboxTile), findsNothing);
    expect(find.text('Re: Mockup v3'), findsWidgets);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(OutboxTile), findsOneWidget);
    expect(source.sent, isEmpty);
  });

  testWidgets('Edit on the toast opens it again', (tester) async {
    await _pump(tester);
    await _send(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.byType(OutboxTile), findsNothing);
  });

  testWidgets('a refused message says Not sent and why, and stays', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _send(tester);
    final id = (await source.outbox(null)).single.id;
    source.refuse(id, '550 no such user');
    await tester.pumpAndSettle();
    expect(find.text('Not sent'), findsOneWidget);
    expect(
      find.text('The server refused it: 550 no such user'),
      findsOneWidget,
    );
    source.goOnline();
    await tester.pumpAndSettle();
    expect(find.byType(OutboxTile), findsOneWidget);
    expect(source.sent, isEmpty);
  });

  testWidgets('the Outbox follows the account picked', (tester) async {
    await _pump(tester);
    await _send(tester);
    await tester.tap(find.text('Work').first);
    await tester.pumpAndSettle();
    expect(find.byType(OutboxTile), findsNothing);
    await tester.tap(find.text('Personal').first);
    await tester.pumpAndSettle();
    expect(find.byType(OutboxTile), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('outbox golden $name', (tester) async {
      final source = await _pump(tester, dark: dark);
      await _send(tester);
      await _send(tester, subject: 'Building meeting');
      final last = (await source.outbox(null)).last.id;
      source.refuse(last, 'no such address');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/outbox_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('outbox phone golden', (tester) async {
    debugDisableShadows = false;
    try {
      await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.bySemanticsLabel('Compose a message'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>,');
      await tester.enterText(_field(1), 'Re: Mockup v3');
      await tester.enterText(_field(2), 'Fine on the comments.');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send'));
      await tester.pump(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/outbox_phone_light.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }, tags: ['golden']);
}
