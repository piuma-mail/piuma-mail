import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_options.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/quoting.dart';
import 'package:piuma_mail/compose/rich_body.dart';
import 'package:piuma_mail/compose/send_checks.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_asks.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// A tiny PNG, as a clipboard or a dropped file would hand one.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// The demo with a picture on the clipboard.
class _Clipboard extends DemoMailSource {
  _Clipboard() : super(now: _now);

  @override
  Future<DraftImage?> clipboardImage() async =>
      DraftImage('image.png', 'image/png', _png);
}

/// The demo, with a message quoted from a mailer that leaves U+FFFC
/// where its pictures were.
class _Placeholders extends _Clipboard {
  @override
  Future<String> body(MailRow row) async =>
      'Look at this:\n\uFFFC\nand this \uFFFC too';

  /// Forward takes the plain text, where the placeholders are.
  @override
  Future<Readable> readable(MailRow row) async => throw StateError('no blocks');
}

/// A 2 GB photo, dropped with others.
class _HugePicture extends XFile {
  _HugePicture() : super('/photos/panorama.png');

  @override
  Future<int> length() async => 2 * 1000 * 1000 * 1000;

  @override
  Future<Uint8List> readAsBytes() async => throw StateError('read');
}

/// The clipboard holds a HEIC photo, which the engine can't draw.
class _HeicClipboard extends DemoMailSource {
  _HeicClipboard() : super(now: _now);

  @override
  Future<DraftImage?> clipboardImage() => androidClipboardPicture({
    'data': Uint8List.fromList(List.filled(64, 1)),
    'mime': 'image/heic',
  }, prepareImage);
}

/// A 2 GB video: its size is known, reading it is a failure.
class _HugeFile extends XFile {
  _HugeFile() : super('/videos/holiday.mov');

  static bool read = false;

  @override
  Future<int> length() async => 2 * 1000 * 1000 * 1000;

  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    throw StateError('a 2 GB file was read');
  }
}

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  DemoMailSource? demo,
  bool compose = true,
  MailRow? open,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = demo ?? DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => _now,
        initialSelection: open,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  if (compose) {
    await tester.tap(find.text('Compose'));
    await tester.pumpAndSettle();
  }
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

/// To, Subject and the text, in that order.
Future<void> _write(
  WidgetTester tester, {
  String subject = 'Mockups approved',
  String body = 'We start Monday.',
}) async {
  await tester.enterText(_field(0), 'luca@studio.it,');
  await tester.enterText(_field(1), subject);
  await tester.enterText(_field(2), body);
  await tester.pump();
}

/// Send, then past the Undo window.
Future<void> _sendAndWait(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

RichBodyController _body(WidgetTester tester) =>
    tester.widget<TextField>(_field(2)).controller! as RichBodyController;

void main() {
  group('forgotten attachment', () {
    test('words in the six languages, not in the quote', () {
      for (final words in [
        'The contract is attached.',
        'Ti mando in allegato il preventivo',
        'Siehe Anhang',
        'Voir la pièce jointe',
        'Te adjunto la factura',
        'Segue em anexo o recibo',
      ]) {
        expect(mentionsAttachment('', words), isTrue, reason: words);
      }
      expect(mentionsAttachment('Allegato: preventivo', 'Ciao'), isTrue);
      expect(mentionsAttachment('', 'See you on Friday'), isFalse);
      expect(
        mentionsAttachment(
          '',
          'Sounds good.\n\nOn Oct 12, Luca wrote:\n> the file is attached',
        ),
        isFalse,
      );
      // A reply written under the quote is still read.
      expect(
        mentionsAttachment('', 'On Oct 12, Luca wrote:\n> Hi\n\nAttached!'),
        isTrue,
      );
    });

    testWidgets('asks before sending without the file, then sends anyway', (
      tester,
    ) async {
      final source = await _pump(tester);
      await _write(tester, body: 'Here is the quote, attached.');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Forgot the attachment?'), findsOneWidget);
      await tester.tap(find.text('Send anyway'));
      await _sendAndWait(tester);
      expect(source.sent.single.body, 'Here is the quote, attached.');
    });

    testWidgets('"Attach file" goes back to compose and opens the picker', (
      tester,
    ) async {
      var picked = 0;
      final before = pickFiles;
      pickFiles = () async {
        picked++;
        return const [];
      };
      addTearDown(() => pickFiles = before);
      final source = await _pump(tester);
      await _write(tester, body: 'Ti mando il preventivo in allegato.');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attach file').last);
      await tester.pumpAndSettle();
      expect(picked, 1);
      expect(find.byType(ComposePane), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      expect(source.sent, isEmpty);
    });
  });

  group('empty subject', () {
    testWidgets('"Add a subject" keeps the message and goes to Subject', (
      tester,
    ) async {
      final source = await _pump(tester);
      await _write(tester, subject: '  ');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Send without a subject?'), findsOneWidget);
      await tester.tap(find.text('Add a subject'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposePane), findsOneWidget);
      final subject = tester.widget<TextField>(_field(1));
      expect(subject.focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 15));
      expect(source.sent, isEmpty);
    });

    testWidgets('"Send anyway" sends it', (tester) async {
      final source = await _pump(tester);
      await _write(tester, subject: '');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send anyway'));
      await _sendAndWait(tester);
      expect(source.sent.single.subject, '');
    });
  });

  testWidgets('a file too big is refused before it is read', (tester) async {
    _HugeFile.read = false;
    final before = pickFiles;
    pickFiles = () async => [_HugeFile()];
    addTearDown(() => pickFiles = before);
    await _pump(tester);
    await tester.tap(find.byTooltip('Attach file'));
    await tester.pumpAndSettle();
    expect(_HugeFile.read, isFalse);
    expect(
      find.text(
        'holiday.mov is too big: attachments can be up to 18 MB in all.',
      ),
      findsOneWidget,
    );
  });

  group('read receipts', () {
    Future<(DemoMailSource, MailRow)> open(WidgetTester tester) async {
      final demo = DemoMailSource(now: _now, asks: true);
      final first = (await demo.page(0, 1)).first;
      await _pump(tester, demo: demo, compose: false, open: first);
      return (demo, first);
    }

    testWidgets('the reader asks, and Send sends one', (tester) async {
      final (demo, first) = await open(tester);
      expect(find.byType(ReadReceiptBand), findsOneWidget);
      expect(
        find.text('${first.sender} asked to be told when you read this.'),
        findsOneWidget,
      );
      expect(find.text('High priority'), findsOneWidget);
      expect(demo.receiptAnswers, isEmpty);
      await tester.tap(find.text('Send receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadReceiptBand), findsNothing);
      expect(find.text('Receipt sent'), findsOneWidget);
      expect(demo.receiptAnswers.single.$2, isTrue);
    });

    testWidgets('"Never for this sender" declines and remembers', (
      tester,
    ) async {
      final (demo, first) = await open(tester);
      await tester.tap(find.text('Never for this sender'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadReceiptBand), findsNothing);
      final (row, send, never) = demo.receiptAnswers.single;
      expect(row.key, first.key);
      expect(send, isFalse);
      expect(never, isTrue);
    });

    testWidgets('nothing is asked without a request', (tester) async {
      final demo = DemoMailSource(now: _now);
      final first = (await demo.page(0, 1)).first;
      await _pump(tester, demo: demo, compose: false, open: first);
      expect(find.byType(ReadReceiptBand), findsNothing);
      expect(find.byType(HighPriorityPill), findsNothing);
    });
  });

  group('quoting', () {
    test('above, below, and only the selected words', () {
      const body = 'First line.\nSecond line here.';
      expect(quoteSource(body, 'Second line', trim: true), 'Second line');
      expect(quoteSource(body, 'Second line', trim: false), body);
      // A selection from another message counts for nothing.
      expect(quoteSource(body, 'elsewhere', trim: true), body);
      final above = replyBody(
        text: 'Hi',
        header: 'On Oct 1, Luca wrote:',
        quoted: quoteLines(body),
        below: false,
      );
      expect(
        above,
        'Hi\n\nOn Oct 1, Luca wrote:\n> First line.\n> Second '
        'line here.',
      );
      expect(replyCaret(above), 2);
      final below = replyBody(
        text: '',
        header: 'On Oct 1, Luca wrote:',
        quoted: quoteLines(body),
        below: true,
      );
      expect(below, startsWith('On Oct 1, Luca wrote:\n> First line.'));
      expect(replyCaret(below), below.length);
    });

    testWidgets('Reply writes under the quote when set so', (tester) async {
      final demo = DemoMailSource(now: _now);
      await demo.setComposeSettings(const ComposeSettings(replyBelow: true));
      final first = (await demo.page(0, 1)).first;
      await _pump(tester, demo: demo, compose: false, open: first);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      final body = _body(tester);
      expect(body.text, startsWith('On Oct 15, 2026'));
      expect(body.selection.baseOffset, body.text.length);
    });

    testWidgets('Reply quotes only the words selected in the reader', (
      tester,
    ) async {
      final demo = DemoMailSource(now: _now);
      final first = (await demo.page(0, 1)).first;
      await _pump(tester, demo: demo, compose: false, open: first);
      readerSelection.value = 'I booked Osteria del Ponte';
      addTearDown(() => readerSelection.value = null);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      final quoted = _body(tester).text
          .split('\n')
          .where((l) => l.startsWith('>'))
          .toList();
      expect(quoted, ['> I booked Osteria del Ponte']);
    });
  });

  group('contact groups', () {
    testWidgets('a group typed in To brings every address', (tester) async {
      await _pump(tester, demo: DemoMailSource(now: _now, contactGroups: true));
      await tester.enterText(_field(0), 'book club,');
      await tester.pumpAndSettle();
      final to = tester.widget<TextField>(_field(0));
      expect(to.controller!.text, isEmpty);
      for (final name in ['Giulia Romano', 'Sara Conti', 'Luca Bianchi']) {
        expect(
          find.descendant(
            of: find.byType(ComposePane),
            matching: find.textContaining(name),
          ),
          findsWidgets,
        );
      }
    });

    testWidgets('a group with a comma in its name stays one', (tester) async {
      final demo = DemoMailSource(now: _now, contactGroups: true);
      await demo.saveContactGroup(
        const ContactGroup(
          name: 'Smith, family',
          addresses: ['ann@smith.it', 'bo@smith.it'],
        ),
      );
      await _pump(tester, demo: demo);
      // The comma after "Smith" doesn't end it: no such address or group.
      await tester.enterText(_field(0), 'Smith,');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_field(0)).controller!.text, 'Smith,');
      await tester.enterText(_field(0), 'Smith, family; book club,');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_field(0)).controller!.text, isEmpty);
      for (final a in ['ann@smith.it', 'bo@smith.it', 'Sara Conti']) {
        expect(
          find.descendant(
            of: find.byType(ComposePane),
            matching: find.textContaining(a),
          ),
          findsWidgets,
        );
      }
    });

    test('what was typed, cut into recipients', () {
      List<String>? expand(String t) => switch (t.toLowerCase()) {
        'smith' => ['s@x.it'],
        'smith, family' => ['a@x.it', 'b@x.it'],
        _ => null,
      };
      String show(List<({String text, List<String>? group})> r) =>
          r.map((p) => p.group == null ? p.text : '[${p.text}]').join(' | ');
      expect(
        show(typedRecipients('Smith, family, l@x.it', expand)),
        '[Smith, family] | l@x.it',
      );
      expect(
        show(typedRecipients('Smith; l@x.it', expand)),
        '[Smith] | l@x.it',
      );
      expect(
        show(typedRecipients('Rossi, Mario <m@x.it>, luca', expand)),
        'Rossi, Mario <m@x.it> | luca',
      );
      expect(show(typedRecipients('luca,', null)), 'luca');
      expect(typedRecipients(' , ;', expand), isEmpty);
    });

    testWidgets('a group is suggested by its name', (tester) async {
      await _pump(tester, demo: DemoMailSource(now: _now, contactGroups: true));
      await tester.enterText(_field(0), 'boo');
      await tester.pumpAndSettle();
      expect(find.text('Book club'), findsOneWidget);
      expect(find.text('3 addresses'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Book club'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ComposePane),
          matching: find.textContaining('Sara Conti'),
        ),
        findsWidgets,
      );
    });
  });

  group('plain text', () {
    test('links written out, quotes as "> ", pictures attached', () {
      const text = 'See the menu\n│ as you said\n￼';
      final plain = toPlainBody(
        text,
        const [BodyMark(BodyMarkKind.link, 8, 12, 'https://x.it/m')],
        [DraftImage('photo.jpg', 'image/jpeg', _png)],
      );
      expect(plain.text, 'See the menu (https://x.it/m)\n> as you said');
      expect(plain.files.single.name, 'photo.jpg');
    });

    testWidgets('switching asks before formatting is lost, and sends plain', (
      tester,
    ) async {
      final source = await _pump(tester);
      await _write(tester, body: 'We start Monday.');
      final body = _body(tester);
      body.selection = const TextSelection(baseOffset: 3, extentOffset: 8);
      body.toggle(BodyMarkKind.bold);
      await tester.pump();
      await tester.tap(find.byType(ComposeOptionsButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plain text'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to plain text?'), findsOneWidget);
      await tester.tap(find.text('Switch to plain text'));
      await tester.pumpAndSettle();
      expect(_body(tester).marks, isEmpty);
      await tester.tap(find.byType(ComposeOptionsButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ComposeOptionsButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask for a read receipt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await _sendAndWait(tester);
      final d = source.sent.single;
      expect(d.plainText, isTrue);
      expect(d.highPriority, isTrue);
      expect(d.readReceipt, isTrue);
      expect(d.marks, isEmpty);
    });

    testWidgets('an account set to plain text starts new mail so', (
      tester,
    ) async {
      final demo = DemoMailSource(now: _now);
      await demo.setComposeSettings(
        const ComposeSettings(plainTextAccounts: {'matteo@posta.it'}),
      );
      final source = await _pump(tester, demo: demo);
      await _write(tester);
      await tester.tap(find.text('Send'));
      await _sendAndWait(tester);
      expect(source.sent.single.plainText, isTrue);
    });
  });

  testWidgets('a reply from a plain-text account goes as plain text', (
    tester,
  ) async {
    final demo = DemoMailSource(now: _now);
    final first = (await demo.page(0, 1)).first;
    final email = demo.accounts
        .firstWhere((a) => a.id == first.accountId)
        .email;
    await demo.setComposeSettings(ComposeSettings(plainTextAccounts: {email}));
    await _pump(tester, demo: demo, compose: false, open: first);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    expect(_body(tester).text, contains('> '));
    await tester.tap(find.text('Send'));
    await _sendAndWait(tester);
    expect(demo.sent.single.plainText, isTrue);
  });

  testWidgets('a picture too big, dropped with others, still says so', (
    tester,
  ) async {
    final before = pickPictures;
    pickPictures = (_) async => [
      _HugePicture(),
      XFile.fromData(_png, path: '/photos/terrace.png', name: 'terrace.png'),
    ];
    addTearDown(() => pickPictures = before);
    await _pump(tester);
    await _write(tester);
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InlinePicture), findsOneWidget);
    expect(
      find.text(
        'Attachments can be up to 18 MB in all. Remove some and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a HEIC photo pasted is attached as it is', (tester) async {
    final source = await _pump(tester, demo: _HeicClipboard());
    await _write(tester);
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InlinePicture), findsNothing);
    expect(find.text('image.heic'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await _sendAndWait(tester);
    expect(source.sent.single.files.single.name, 'image.heic');
  });

  testWidgets('Insert picture in the options puts one in the text', (
    tester,
  ) async {
    final before = pickPictures;
    pickPictures = (_) async => [
      XFile.fromData(_png, path: '/photos/terrace.png', name: 'terrace.png'),
    ];
    addTearDown(() => pickPictures = before);
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InlinePicture), findsOneWidget);
    await tester.tap(find.text('Send'));
    await _sendAndWait(tester);
    expect(source.sent.single.images.single.name, 'terrace.png');
  });

  testWidgets('a pasted picture goes inside the text and out with it', (
    tester,
  ) async {
    // A clipboard with a picture and no text.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.hasStrings' ? {'value': false} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final source = await _pump(tester, demo: _Clipboard());
    await _write(tester, body: 'Look:');
    await tester.tap(_field(2));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(_body(tester).text, 'Look:\n$imagePlaceholder');
    expect(find.byType(InlinePicture), findsOneWidget);
    // Deleting its place takes the picture away too.
    final body = _body(tester);
    body.value = const TextEditingValue(
      text: 'Look:\n',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(body.images, isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await _sendAndWait(tester);
    final d = source.sent.single;
    expect(d.images.single.name, 'image.png');
    expect(d.body, contains(imagePlaceholder));
  });

  testWidgets('a quote with U+FFFC under the reply takes no picture place', (
    tester,
  ) async {
    final demo = _Placeholders();
    await demo.setComposeSettings(const ComposeSettings(replyBelow: true));
    final first = (await demo.page(0, 1)).first;
    await _pump(tester, demo: demo, compose: false, open: first);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    final body = _body(tester);
    expect(body.text, isNot(contains(imagePlaceholder)));
    // A picture pasted under the quote is the only one, and nothing breaks.
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste picture'));
    await tester.pumpAndSettle();
    expect(imagePlaceholder.allMatches(_body(tester).text).length, 1);
    expect(_body(tester).images, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Forward leaves the picture placeholders out', (tester) async {
    final demo = _Placeholders();
    final first = (await demo.page(0, 1)).first;
    await _pump(tester, demo: demo, compose: false, open: first);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    final body = _body(tester);
    expect(body.text, contains('Look at this:'));
    expect(body.text, isNot(contains(imagePlaceholder)));
    expect(body.images, isEmpty);
  });

  test('stray picture places in a body go when it opens', () {
    final body = RichBodyController(
      text: 'a￼b￼',
      marks: const [BodyMark(BodyMarkKind.bold, 2, 3)],
      images: [DraftImage('x.png', 'image/png', _png)],
    );
    expect(body.text, 'a￼b');
    expect(body.marks.single, const BodyMark(BodyMarkKind.bold, 2, 3));
    body.selection = const TextSelection.collapsed(offset: 3);
    body.insertImages([DraftImage('y.png', 'image/png', _png)]);
    expect(body.images.map((i) => i.name), ['x.png', 'y.png']);
  });

  testWidgets('Ctrl+V pastes the text when the clipboard has some', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.hasStrings' => {'value': true},
        'Clipboard.getData' => {'text': 'Q3 totals'},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, demo: _Clipboard());
    await _write(tester, body: 'Numbers: ');
    await tester.tap(_field(2));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(_body(tester).text, 'Numbers: Q3 totals');
    expect(_body(tester).images, isEmpty);
  });

  testWidgets('a picture the engine cannot read is attached as it is', (
    tester,
  ) async {
    final before = pickPictures;
    pickPictures = (_) async => [
      XFile.fromData(
        Uint8List.fromList(List.filled(40, 7)),
        path: '/photos/scan.webp',
        name: 'scan.webp',
      ),
    ];
    addTearDown(() => pickPictures = before);
    final source = await _pump(tester);
    await _write(tester);
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insert picture'));
    await tester.pumpAndSettle();
    expect(find.byType(InlinePicture), findsNothing);
    expect(find.text('scan.webp'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await _sendAndWait(tester);
    expect(source.sent.single.files.single.name, 'scan.webp');
  });

  testWidgets('the options on are said in words over the foot', (tester) async {
    await _pump(tester);
    expect(find.byType(ComposeOptionsLine), findsNothing);
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High priority'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ComposeOptionsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask for a read receipt'));
    await tester.pumpAndSettle();
    expect(find.text('High priority · Read receipt asked for'), findsOneWidget);
  });

  group('Android clipboard', () {
    Future<DraftImage> prepare(String name, Uint8List data) =>
        DemoMailSource(now: _now).prepareImage(name, data);

    test('a picture, none, one too big, one the engine can\'t draw', () async {
      expect(await androidClipboardPicture(null, prepare), isNull);
      final png = await androidClipboardPicture({
        'data': _png,
        'mime': 'image/png',
      }, prepare);
      expect(png!.name, 'image.png');
      await expectLater(
        androidClipboardPicture({'tooBig': true}, prepare),
        throwsA(
          isA<ImageException>()
              .having((e) => e.problem, 'problem', ImageProblem.tooBig)
              .having((e) => e.file, 'file', isNull),
        ),
      );
      await expectLater(
        androidClipboardPicture({
          'data': Uint8List.fromList([1, 2, 3]),
          'mime': 'image/heic',
        }, prepare),
        throwsA(
          isA<ImageException>().having(
            (e) => e.file?.name,
            'file',
            'image.heic',
          ),
        ),
      );
    });
  });

  group('read receipt results', () {
    Future<MailRow> open(WidgetTester tester, DemoMailSource demo) async {
      final first = (await demo.page(0, 1)).first;
      await _pump(tester, demo: demo, compose: false, open: first);
      return first;
    }

    testWidgets('offline it waits in the outbox, and says so', (tester) async {
      final demo = DemoMailSource(now: _now, asks: true)..offline = true;
      await open(tester, demo);
      await tester.tap(find.text('Send receipt'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The receipt is waiting in the Outbox and goes as soon as it can.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('refused, it waits in the Outbox and isn’t asked again', (
      tester,
    ) async {
      final demo = DemoMailSource(now: _now, asks: true)
        ..refuseNextReceipt = '550 not allowed';
      final first = await open(tester, demo);
      await tester.tap(find.text('Send receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadReceiptBand), findsNothing);
      expect(
        find.text(
          'The receipt is waiting in the Outbox and goes as soon as it can.',
        ),
        findsOneWidget,
      );
      final waiting = (await demo.outbox(null)).single;
      expect(waiting.subject, 'Read: ${first.subject}');
      expect(waiting.error, '550 not allowed');
      expect((await demo.messageAsks(first)).readReceiptTo, isNull);
      // Deleted there, it is not sent: the answer is taken back.
      await demo.cancelOutgoing(waiting.id);
      expect(demo.receiptAnswers.single.$2, isFalse);
    });

    test('"Don’t send" takes back a receipt waiting in the outbox', () async {
      final demo = DemoMailSource(now: _now, asks: true)..offline = true;
      final first = (await demo.page(0, 1)).first;
      expect(await demo.answerReadReceipt(first, send: true), isTrue);
      expect(await demo.outbox(null), hasLength(1));
      await demo.answerReadReceipt(first, send: false);
      expect(await demo.outbox(null), isEmpty);
      expect(demo.receiptAnswers.single.$2, isFalse);
    });

    testWidgets('deleted from the Outbox before it went, it says nothing', (
      tester,
    ) async {
      final demo = DemoMailSource(now: _now, asks: true)
        ..goneNextReceipt = true;
      await open(tester, demo);
      await tester.tap(find.text('Send receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadReceiptBand), findsNothing);
      expect(find.textContaining('waiting in the Outbox'), findsNothing);
      expect(find.text('Receipt sent'), findsNothing);
    });

    testWidgets('a failure keeps the band, with the reason', (tester) async {
      final demo = DemoMailSource(now: _now, asks: true)
        ..failNextReceipt = StateError('refused');
      await open(tester, demo);
      await tester.tap(find.text('Send receipt'));
      await tester.pumpAndSettle();
      expect(find.byType(ReadReceiptBand), findsOneWidget);
      expect(
        find.text('The receipt couldn’t be sent. Try again later.'),
        findsOneWidget,
      );
    });
  });
}
