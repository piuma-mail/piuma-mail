import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = _desktop,
  bool dark = false,
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = source ?? DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: s, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return s;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

Future<void> _write(
  WidgetTester tester, {
  String to = 'luca@studio.it',
  String subject = 'Mockups approved',
}) async {
  await tester.tap(find.text('Compose'));
  await tester.pumpAndSettle();
  await tester.enterText(_field(0), '$to,');
  await tester.enterText(_field(1), subject);
  await tester.enterText(_field(2), 'We start Monday.');
  await tester.pump();
}

/// Two drafts, as if written earlier.
Future<DemoMailSource> _withDrafts() async {
  final source = DemoMailSource(now: _now);
  await source.saveDraft(
    const Draft(
      accountId: 2,
      to: ['Luca Bianchi <luca@studio.it>'],
      subject: 'Mockups approved',
      body: 'We start Monday with the inbox and the reader.',
    ),
  );
  await source.saveDraft(
    const Draft(
      accountId: 1,
      subject: 'Ideas for the trip',
      body: 'Lisbon in March? Flights are cheap the first week.',
    ),
  );
  return source;
}

void main() {
  testWidgets('writing saves the draft after a pause', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    expect(find.text('Draft saved'), findsNothing);
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    expect(find.text('Draft saved'), findsOneWidget);
    expect(source.drafts.single.subject, 'Mockups approved');

    // More writing replaces the copy rather than adding one.
    await tester.enterText(_field(2), 'We start Tuesday.');
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    expect(source.drafts.single.body, 'We start Tuesday.');
  });

  testWidgets('Drafts shows in the sidebar only when there are some', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Drafts'), findsNothing);
    await _write(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Drafts'), findsOneWidget);
  });

  testWidgets('a row without a subject says so', (tester) async {
    final source = DemoMailSource(now: _now);
    await source.saveDraft(
      const Draft(accountId: 1, to: ['luca@studio.it'], body: 'See you then.'),
    );
    await _pump(tester, source: source);
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    expect(find.text('(no subject)'), findsOneWidget);
  });

  testWidgets('a draft opens in compose and goes once sent', (tester) async {
    final source = await _pump(tester, source: await _withDrafts());
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    expect(find.text('No recipients'), findsOneWidget);
    await tester.tap(find.text('Mockups approved'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('Luca Bianchi'), findsWidgets);

    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.sent.single.subject, 'Mockups approved');
    expect(source.drafts.map((d) => d.subject), ['Ideas for the trip']);
  });

  testWidgets('a signature picked by hand comes back with the draft', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.text('Personal · matteo@posta.it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matteo@studio.it').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(source.drafts.single.signaturePicked, isTrue);

    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mockups approved'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · Short'), findsOneWidget);
  });

  testWidgets('a draft left without a signature stays without', (tester) async {
    final source = DemoMailSource(now: _now);
    await source.saveDraft(
      const Draft(
        accountId: 2,
        subject: 'No sign-off',
        body: 'Just a line.',
        signaturePicked: true,
      ),
    );
    await _pump(tester, source: source);
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No sign-off'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · No signature'), findsOneWidget);
  });

  testWidgets('Discard throws the closed draft away', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(source.drafts, isEmpty);
  });

  testWidgets('a draft that can’t be saved can be reopened', (tester) async {
    final source = await _pump(tester);
    source.failDraftSaves = true;
    await _write(tester);
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Draft not saved'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(find.text('Mockups approved'), findsWidgets);
  });

  testWidgets('clearing a saved draft deletes it', (tester) async {
    final source = await _pump(tester, source: await _withDrafts());
    await tester.tap(find.text('Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ideas for the trip'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(1), '');
    await tester.enterText(_field(2), '');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(source.drafts.map((d) => d.subject), ['Mockups approved']);
  });

  testWidgets('an address typed, saved and deleted leaves no draft', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(0), 'luca');
    await tester.tap(_field(1));
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    await tester.tap(_field(0));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(autosaveDelay);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(source.drafts, isEmpty);
  });

  testWidgets('the phone sheet has a Drafts tile', (tester) async {
    await _pump(tester, size: _phone, source: await _withDrafts());
    await tester.tap(
      find.bySemanticsLabel('3 accounts, accounts and Settings'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Drafts'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('drafts golden $name', (tester) async {
      await _pump(tester, dark: dark, source: await _withDrafts());
      await tester.tap(find.text('Drafts'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/drafts_$name.png'),
      );
    }, tags: ['golden']);
  }
}
