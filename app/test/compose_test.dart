import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/phone_parts.dart' show ComposeFab;
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compose'));
  await tester.pumpAndSettle();
  return source;
}

/// Compose on the phone, as `PhoneCompose`, from Work.
Future<void> _pumpPhone(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ComposeFab));
  await tester.pumpAndSettle();
  await _fromWork(tester);
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

/// Sends from the Work account.
Future<void> _fromWork(WidgetTester tester) async {
  await tester.tap(find.text('Personal · matteo@posta.it'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('matteo@studio.it').last);
  await tester.pumpAndSettle();
}

Future<Draft> _sendNow(WidgetTester tester, DemoMailSource source) async {
  await tester.tap(find.text('Send'));
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
  return source.sent.single;
}

Future<void> _write(WidgetTester tester, {String to = 'luca@studio.it'}) async {
  await tester.enterText(_field(0), '$to,');
  await tester.enterText(_field(1), 'Mockups approved');
  await tester.enterText(_field(2), 'We start Monday.');
  await tester.pump();
}

void main() {
  test('addresses', () {
    expect(isEmailAddress('luca@studio.it'), isTrue);
    expect(isEmailAddress('Luca Bianchi <luca@studio.it>'), isTrue);
    expect(isEmailAddress('luca'), isFalse);
    expect(isEmailAddress('luca@studio'), isFalse);
    expect(isEmailAddress('a b@studio.it'), isFalse);
  });

  testWidgets('Compose opens in place of the reader', (tester) async {
    await _pump(tester);
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Matteo · matteo@posta.it'), findsNothing);
    expect(find.text('Personal · matteo@posta.it'), findsOneWidget);
    expect(find.text('You can undo send for 10 seconds'), findsOneWidget);
  });

  testWidgets('a typed address becomes a chip', (tester) async {
    await _pump(tester);
    await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>;');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Luca Bianchi'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('typing in To suggests people, Enter picks the first', (
    tester,
  ) async {
    await _pump(tester);
    await tester.showKeyboard(_field(0));
    await tester.enterText(_field(0), 'gi');
    await tester.pumpAndSettle();
    expect(find.text('giulia.romano@posta.it'), findsOneWidget);
    expect(find.text('g.bassi@studio.it'), findsOneWidget);
    expect(find.text('sara@studio.it'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('g.bassi@studio.it'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Giorgio Bassi'),
      ),
      findsOneWidget,
    );
    // Someone already there is not offered again.
    await tester.enterText(_field(0), 'g');
    await tester.pumpAndSettle();
    expect(find.text('giulia.romano@posta.it'), findsOneWidget);
    expect(find.text('g.bassi@studio.it'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('giulia.romano@posta.it'), findsNothing);
  });

  testWidgets('on the phone the list takes the place of the form', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await tester.showKeyboard(_field(0));
    await tester.enterText(_field(0), 'gi');
    await tester.pumpAndSettle();
    expect(find.text('Subject'), findsNothing);
    expect(find.text('Wrote to'), findsNothing);
    await tester.tap(find.text('Giorgio Bassi'));
    await tester.pumpAndSettle();
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('g.bassi@studio.it'), findsNothing);
  });

  testWidgets('a tap on a suggestion adds that person', (tester) async {
    final source = await _pump(tester);
    await _fromWork(tester);
    await tester.showKeyboard(_field(0));
    await tester.enterText(_field(0), 'sar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('sara@studio.it'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(1), 'Hello');
    await tester.enterText(_field(2), 'Hi Sara');
    await tester.pump();
    expect((await _sendNow(tester, source)).to, [
      'Sara Conti <sara@studio.it>',
    ]);
  });

  testWidgets('the message leaves after the Undo window', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.text('Sending…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(source.sent, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(source.sent, hasLength(1));
    final d = source.sent.single;
    expect(d.accountId, 1);
    expect(d.to, ['luca@studio.it']);
    expect(d.subject, 'Mockups approved');
    expect(d.body, 'We start Monday.');
    await tester.pumpAndSettle();
  });

  testWidgets('Undo brings the message back', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.text('Mockups approved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(source.sent, isEmpty);
  });

  testWidgets('a wrong address stops the send', (tester) async {
    final source = await _pump(tester);
    await _write(tester, to: 'luca');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('“luca” is not an email address.'), findsOneWidget);
    expect(find.byType(ComposePane), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(source.sent, isEmpty);
  });

  testWidgets('a failed send reopens the message with the reason', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.failNextSend = const SendException(SendError.unreachable);
    await _write(tester);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(find.textContaining("Couldn't reach the outgoing server"), findsOne);
    expect(find.text('Mockups approved'), findsOneWidget);
  });

  testWidgets('closing a written message keeps it in Drafts', (tester) async {
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsNothing);
    expect(find.text('Draft saved'), findsOneWidget);
    expect(source.drafts.single.subject, 'Mockups approved');
  });

  testWidgets('the From account brings its signature for new emails', (
    tester,
  ) async {
    final source = await _pump(tester);
    // Personal has a signature for replies only.
    expect(find.text('Signature · No signature'), findsOneWidget);
    await _fromWork(tester);
    expect(find.text('Signature · Work'), findsOneWidget);
    expect(find.text('Matteo Neri'), findsOneWidget);
    expect(find.text('+39 333 000 0000 · studiolumen.it'), findsOneWidget);
    await _write(tester);
    final sent = await _sendNow(tester, source);
    expect(sent.signatureId, 1);
  });

  testWidgets('the chip switches signature, or leaves it out', (tester) async {
    final source = await _pump(tester);
    await _fromWork(tester);
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    expect(find.text('Manage signatures…'), findsOneWidget);
    expect(find.text('Replies'), findsOneWidget);
    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · Short'), findsOneWidget);
    expect(find.text('Matteo Neri'), findsNothing);

    await tester.tap(find.text('Signature · Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No signature'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · No signature'), findsOneWidget);
    await _write(tester);
    final sent = await _sendNow(tester, source);
    expect(sent.signatureId, isNull);
  });

  testWidgets('changing account goes back to its own signature', (
    tester,
  ) async {
    await _pump(tester);
    await _fromWork(tester);
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work · matteo@studio.it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('teo@icloud.com').last);
    await tester.pumpAndSettle();
    // iCloud has none: nothing to pick, nothing added.
    expect(find.textContaining('Signature ·'), findsNothing);
    expect(find.textContaining('The signature follows'), findsNothing);
  });

  testWidgets('Manage signatures opens Settings on the one in use', (
    tester,
  ) async {
    await _pump(tester);
    await _fromWork(tester);
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage signatures…'));
    await tester.pumpAndSettle();
    final settings = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(settings.section, SettingsSection.writing);
    expect(settings.signature, 1);
  });

  testWidgets('on the phone the chip opens the signature sheet', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    expect(find.text('Manage'), findsOneWidget);
    expect(
      find.text(
        'The signature switches automatically when you change the “From” '
        'account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Manage signatures…'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Short'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · Short'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);

    await tester.tap(find.text('Signature · Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('No signature'));
    await tester.pumpAndSettle();
    expect(find.text('Signature · No signature'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone signature sheet golden $name', (tester) async {
      await _pumpPhone(tester, dark: dark);
      await tester.tap(find.text('Signature · Work'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_signature_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('compose golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _fromWork(tester);
      await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>,');
      await tester.enterText(_field(0), 'Sara Conti <sara@studio.it>,');
      await tester.enterText(_field(1), 'Mockups approved: let’s go');
      await tester.enterText(
        _field(2),
        'Hi Luca, hi Sara,\n\n'
        'I went through v3 and I think we’re there. One request: let’s keep '
        'the two-line preview in the list on desktop too, it reads much '
        'better.\n\nWe start on the prototype Monday.',
      );
      // Leave no caret blinking in the screenshot.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compose_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('recipient suggestions golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _fromWork(tester);
      await tester.showKeyboard(_field(0));
      await tester.enterText(_field(0), 'Luca Bianchi <luca@studio.it>,');
      await tester.enterText(_field(0), 'gi');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compose_suggest_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone recipient suggestions golden', (tester) async {
    await _pumpPhone(tester);
    await tester.showKeyboard(_field(0));
    await tester.enterText(_field(0), 'gi');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_compose_suggest_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('signature list golden', (tester) async {
    await _pump(tester);
    await _fromWork(tester);
    await tester.enterText(
      _field(2),
      'Hi Luca,\nthe final files are attached.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.text('Signature · Work'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/compose_signature_light.png'),
    );
  }, tags: ['golden']);
}
