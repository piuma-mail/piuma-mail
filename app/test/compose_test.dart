import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
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

  testWidgets('on the phone suggestions sit inline above Subject', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await tester.showKeyboard(_field(0));
    await tester.enterText(_field(0), 'gi');
    await tester.pumpAndSettle();
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Wrote to'), findsNothing);
    await tester.tap(find.text('Giorgio Bassi'));
    await tester.pumpAndSettle();
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('g.bassi@studio.it'), findsNothing);
  });

  for (final phone in [false, true]) {
    for (final dark in [false, true]) {
      for (final field in [0, 1, 2]) {
        testWidgets(
          'own address suggestions ${phone ? 'phone' : 'desktop'} ${dark ? 'dark' : 'light'} field $field',
          (tester) async {
            phone
                ? await _pumpPhone(tester, dark: dark)
                : await _pump(tester, dark: dark);
            if (field > 0) {
              await tester.tap(find.text('Cc  Bcc'));
              await tester.pumpAndSettle();
            }
            await tester.showKeyboard(_field(field));
            await tester.enterText(_field(field), 'matteo@');
            await tester.pumpAndSettle();
            expect(find.text('matteo@studio.it'), findsOneWidget);
            expect(find.text('Subject'), findsOneWidget);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                'goldens/compose_own_${phone ? 'phone' : 'desktop'}_${['to', 'cc', 'bcc'][field]}_${dark ? 'dark' : 'light'}.png',
              ),
            );
            if (phone) {
              await tester.tap(find.text('matteo@studio.it'));
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            }
            await tester.pumpAndSettle();
            expect(find.text('matteo@studio.it'), findsNothing);
            // The suggestion becomes a chip in the field being edited.
            final input = tester.widget<TextField>(_field(field));
            expect(input.controller!.text, isEmpty);
            expect(input.focusNode!.hasFocus, isTrue);
            final subject = field == 0 ? 1 : 3;
            await tester.tap(find.text('Subject'));
            await tester.pumpAndSettle();
            tester.testTextInput.enterText('Focus stays in Subject');
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(_field(subject)).controller!.text,
              'Focus stays in Subject',
            );
          },
        );
      }
    }
  }

  testWidgets('inline Bcc suggestions fit above the phone keyboard', (
    tester,
  ) async {
    await _pumpPhone(tester);
    await tester.tap(find.text('Cc  Bcc'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.showKeyboard(_field(2));
    await tester.enterText(_field(2), 'matteo@');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Personal').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_field(2)).controller!.text, isEmpty);
    await tester.ensureVisible(find.text('Subject'));
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('Typing after Bcc');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field(3)).controller!.text,
      'Typing after Bcc',
    );
  });

  // A tap on another field turns what is typed into a chip and moves there,
  // even though the new chip pushes that field down (issue #9).
  for (final phone in [true, false]) {
    for (final (from, to) in [
      ('To', 'Subject'),
      ('To', 'body'),
      ('Cc', 'Subject'),
      ('Bcc', 'body'),
    ]) {
      testWidgets('${phone ? 'phone: ' : ''}a tap on $to after typing in '
          '$from keeps the address and writes in $to', (tester) async {
        phone ? await _pumpPhone(tester) : await _pump(tester);
        if (from != 'To') {
          await tester.tap(find.text('Cc  Bcc'));
          await tester.pumpAndSettle();
        }
        final input = from == 'To' ? 0 : (from == 'Cc' ? 1 : 2);
        final subject = from == 'To' ? 1 : 3;
        await tester.showKeyboard(_field(input));
        await tester.pumpAndSettle();
        tester.testTextInput.enterText('someone.with.a.long.name@example.com');
        await tester.pumpAndSettle();
        EditableTextState editing() => tester.state(
          find.descendant(
            of: _field(input),
            matching: find.byType(EditableText),
          ),
        );
        final before = editing();
        tester.testTextInput.log.clear();
        // A finger (a mouse on the desktop) rests for a moment: frames pass
        // between down and up, and the chip may move the field meanwhile.
        final finger = await tester.startGesture(
          tester.getCenter(_field(to == 'Subject' ? subject : subject + 1)),
          kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 80));
        await finger.up();
        await tester.pumpAndSettle();
        // The keyboard is handed over before the typed text leaves the
        // field: no edit for the old field reaches it while it switches.
        final calls = [for (final c in tester.testTextInput.log) c.method];
        expect(calls, contains('TextInput.setClient'));
        expect(
          calls.takeWhile((m) => m != 'TextInput.setClient'),
          isNot(contains('TextInput.setEditingState')),
        );
        tester.testTextInput.enterText('My subject');
        await tester.pumpAndSettle();
        expect(find.text('someone.with.a.long.name@example.com'), findsOne);
        final fields = tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(ComposePane),
                matching: find.byType(TextField),
              ),
            )
            .toList();
        expect(fields[input].controller!.text, isEmpty);
        // The chip didn't rebuild the field it was typed in.
        expect(editing(), same(before));
        expect(
          fields[to == 'Subject' ? subject : subject + 1].controller!.text,
          startsWith('My subject'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  // A tap on a row's label, not just on its field, moves there; what was
  // typed in a recipient field still becomes a chip (issue #9).
  for (final phone in [true, false]) {
    for (final (from, to) in [
      ('To', 'Subject'),
      ('Subject', 'To'),
      ('To', 'Cc'),
      ('Cc', 'Bcc'),
      ('Bcc', 'Subject'),
    ]) {
      testWidgets('${phone ? 'phone: ' : ''}a tap on the $to label after '
          'typing in $from writes in $to', (tester) async {
        phone ? await _pumpPhone(tester) : await _pump(tester);
        final copies = {from, to}.any((f) => f == 'Cc' || f == 'Bcc');
        if (copies) {
          await tester.tap(find.text('Cc  Bcc'));
          await tester.pumpAndSettle();
        }
        final rows = copies
            ? ['To', 'Cc', 'Bcc', 'Subject']
            : ['To', 'Subject'];
        const address = 'someone@example.com';
        await tester.showKeyboard(_field(rows.indexOf(from)));
        await tester.pumpAndSettle();
        tester.testTextInput.enterText(
          from == 'Subject' ? 'My subject' : address,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ComposePane),
            matching: find.text(to),
          ),
          kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        tester.testTextInput.enterText(
          to == 'Subject' ? 'My subject' : 'next@example.com',
        );
        await tester.pumpAndSettle();
        String text(String row) => tester
            .widget<TextField>(_field(rows.indexOf(row)))
            .controller!
            .text;
        if (from == 'Subject') {
          expect(text('Subject'), 'My subject');
        } else {
          expect(find.text(address), findsOne);
          expect(text(from), isEmpty);
        }
        expect(text(to), to == 'Subject' ? 'My subject' : 'next@example.com');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('phone: a long chip ends in an ellipsis before Cc Bcc', (
    tester,
  ) async {
    await _pumpPhone(tester);
    const long = 'someone.with.a.really.long.name@example.com,';
    await tester.enterText(_field(0), long);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final chip = find.text(long.substring(0, long.length - 1));
    final text = tester.renderObject<RenderParagraph>(chip);
    expect(text.didExceedMaxLines, isTrue);
    expect(
      tester.getRect(chip).right,
      lessThan(tester.getRect(find.text('Cc  Bcc')).left),
    );
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
