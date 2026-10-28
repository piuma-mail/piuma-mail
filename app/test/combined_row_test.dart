import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/engine/api/engine.dart' as engine;
import 'package:piuma_mail/engine/frb_generated.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/mail/engine_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

class _Api implements RustLibApi {
  final seenCalls = <List<engine.MessageRef>>[];
  final pushedCalls = <List<engine.MessageRef>>[];
  @override
  List<engine.AccountInfo> crateApiEngineAccounts() => [];
  @override
  engine.FeatureSettings crateApiEngineFeatureSettings() =>
      const engine.FeatureSettings(
        newsletters: false,
        vault: false,
        attachments: false,
        inShort: false,
        translate: false,
        foundDates: false,
      );
  @override
  Future<void> crateApiEngineSetMessagesSeen({
    required List<engine.MessageRef> messages,
    required bool seen,
  }) async {
    seenCalls.add(messages);
  }

  @override
  Future<void> crateApiEnginePushMessagesSeen({
    required List<engine.MessageRef> messages,
    required bool seen,
  }) async {
    pushedCalls.add(messages);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final row = MailRow(
  accountId: 1,
  mailbox: 'INBOX',
  uid: 10,
  fromName: 'Client Studio',
  fromEmail: 'client@example.org',
  subject: 'Quote request',
  preview: 'Please send us a quote for the shoot.',
  receivedAt: DateTime(2026, 10, 28),
  seen: false,
  copies: const [
    (accountId: 1, mailbox: 'INBOX', uid: 10),
    (accountId: 2, mailbox: 'Inbox/Clients', uid: 42),
  ],
);

Future<void> pumpRow(
  WidgetTester tester, {
  required bool dark,
  VoidCallback? onTap,
}) async {
  tester.view.physicalSize = const Size(420, 160);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => Scaffold(
        body: InboxRowTile(
          row: row,
          account: null,
          accountColors: const [Color(0xff2f8f83), Color(0xffe0782f)],
          time: '10:30',
          selected: false,
          phone: true,
          onTap: onTap ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a combined row action marks every server copy read once', (
    tester,
  ) async {
    final api = _Api();
    RustLib.initMock(api: api);
    final source = EngineMailSource();
    await pumpRow(
      tester,
      dark: false,
      onTap: () => source.setSeen([row, row], true),
    );
    await tester.tap(find.text('Quote request'));
    await tester.pumpAndSettle();
    for (final calls in [api.seenCalls, api.pushedCalls]) {
      expect(
        calls.single.map((m) => (m.accountId, m.mailbox, m.uid)).toList(),
        [(1, 'INBOX', 10), (2, 'Inbox/Clients', 42)],
      );
    }
    expect(row.withSeen(true).copies, row.copies);
  });
  for (final dark in [false, true]) {
    testWidgets('combined row golden ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      await pumpRow(tester, dark: dark);
      expect(find.byKey(const ValueKey('account-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('account-dot-1')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/combined_row_${dark ? 'dark' : 'light'}.png',
        ),
      );
    }, tags: ['golden']);
  }
}
