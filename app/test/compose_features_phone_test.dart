import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_options.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/format_bar.dart';
import 'package:piuma_mail/compose/quoting.dart';
import 'package:piuma_mail/compose/rich_body.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_asks.dart';
import 'package:piuma_mail/inbox/phone_parts.dart' show ComposeFab;
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

/// The same flows as `compose_features_test.dart`, on the phone layout
/// (`PhoneCompose`, the phone reader): every feature works on both.

final _now = DateTime(2026, 10, 15, 10, 30);

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _Clipboard extends DemoMailSource {
  _Clipboard() : super(now: _now);

  @override
  Future<DraftImage?> clipboardImage() async =>
      DraftImage('image.png', 'image/png', _png);
}

/// A message whose plain text keeps a mailer's picture placeholders.
class _Placeholders extends DemoMailSource {
  _Placeholders() : super(now: _now);

  @override
  Future<String> body(MailRow row) async =>
      'Look at this:\n\uFFFC\nand this \uFFFC too';

  /// Forward takes the plain text, where the placeholders are.
  @override
  Future<Readable> readable(MailRow row) async => throw StateError('no blocks');
}

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  DemoMailSource? demo,
  bool compose = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = demo ?? DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  if (compose) {
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
  }
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

RichBodyController _body(WidgetTester tester) =>
    tester.widget<TextField>(_field(2)).controller! as RichBodyController;

Future<void> _write(
  WidgetTester tester, {
  String subject = 'Hello',
  String body = 'See you Friday.',
}) async {
  await tester.enterText(_field(0), 'luca@studio.it,');
  await tester.enterText(_field(1), subject);
  await tester.enterText(_field(2), body);
  await tester.pump();
}

Future<void> _option(WidgetTester tester, String name) async {
  await tester.tap(find.byType(ComposeOptionsButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Send'));
  await tester.pumpAndSettle();
}

Future<void> _past(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

Finder _row(String subject) => find.text(subject).first;

void main() {
  testWidgets('the formatting bar rises over the keyboard, not in plain text', (
    tester,
  ) async {
    await _pump(tester);
    await _write(tester);
    await tester.tap(_field(2));
    _body(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    await tester.pumpAndSettle();
    expect(find.byType(FormatBar), findsOneWidget);
    _body(tester).selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    await _option(tester, 'Plain text');
    await tester.tap(_field(2));
    _body(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    await tester.pumpAndSettle();
    expect(find.byType(FormatBar), findsNothing);
  });

  testWidgets('Insert picture puts it inside the text, and it goes out', (
    tester,
  ) async {
    final before = pickPictures;
    pickPictures = () async => [
      XFile.fromData(_png, path: '/photos/terrace.png', name: 'terrace.png'),
    ];
    addTearDown(() => pickPictures = before);
    final source = await _pump(tester);
    await _write(tester);
    await _option(tester, 'Insert picture');
    expect(find.byType(InlinePicture), findsOneWidget);
    await _send(tester);
    await _past(tester);
    expect(source.sent.single.images, hasLength(1));
  });

  testWidgets('Paste picture, and a picture from the keyboard', (tester) async {
    final source = await _pump(tester, demo: _Clipboard());
    await _write(tester);
    await _option(tester, 'Paste picture');
    expect(find.byType(InlinePicture), findsOneWidget);
    // Gboard's clipboard, a GIF or a sticker comes through the field.
    final field = tester.widget<TextField>(_field(2));
    field.contentInsertionConfiguration!.onContentInserted(
      KeyboardInsertedContent(
        mimeType: 'image/png',
        uri: 'content://keyboard/1',
        data: _png,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlinePicture), findsNWidgets(2));
    await _send(tester);
    await _past(tester);
    expect(source.sent.single.images, hasLength(2));
  });

  testWidgets('Paste picture with none on the clipboard says so', (
    tester,
  ) async {
    await _pump(tester);
    await _option(tester, 'Paste picture');
    expect(find.text('There’s no picture on the clipboard.'), findsOneWidget);
  });

  testWidgets('plain text, priority and a receipt from the options sheet', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _write(tester);
    final body = _body(tester);
    body.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    body.toggle(BodyMarkKind.italic);
    body.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    await _option(tester, 'Plain text');
    expect(find.text('Switch to plain text?'), findsOneWidget);
    await tester.tap(find.text('Switch to plain text'));
    await tester.pumpAndSettle();
    await _option(tester, 'High priority');
    await _option(tester, 'Ask for a read receipt');
    await _send(tester);
    await _past(tester);
    final d = source.sent.single;
    expect((d.plainText, d.highPriority, d.readReceipt), (true, true, true));
    expect(d.marks, isEmpty);
  });

  testWidgets('the forgotten file and the empty subject ask in a sheet', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _write(tester, subject: '', body: 'The plan is attached.');
    await _send(tester);
    expect(find.text('Forgot the attachment?'), findsOneWidget);
    await tester.tap(find.text('Send anyway'));
    await tester.pumpAndSettle();
    expect(find.text('Send without a subject?'), findsOneWidget);
    await tester.tap(find.text('Send anyway'));
    await tester.pumpAndSettle();
    await _past(tester);
    expect(source.sent, hasLength(1));
  });

  testWidgets('a contact group in the phone recipient list', (tester) async {
    await _pump(tester, demo: DemoMailSource(now: _now, contactGroups: true));
    await tester.enterText(_field(0), 'book');
    await tester.pumpAndSettle();
    expect(find.text('Group'), findsOneWidget);
    await tester.tap(find.text('Book club'));
    await tester.pumpAndSettle();
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

  testWidgets('the phone reader asks about the read receipt', (tester) async {
    final demo = await _pump(
      tester,
      demo: DemoMailSource(now: _now, asks: true),
      compose: false,
    );
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptBand), findsOneWidget);
    expect(find.byType(HighPriorityPill), findsOneWidget);
    await tester.tap(find.text('Don’t send'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptBand), findsNothing);
    expect(demo.receiptAnswers.single.$2, isFalse);
  });

  testWidgets('Reply on the phone writes under the quote when set so', (
    tester,
  ) async {
    final demo = DemoMailSource(now: _now);
    await demo.setComposeSettings(const ComposeSettings(replyBelow: true));
    await _pump(tester, demo: demo, compose: false);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    final body = _body(tester);
    expect(body.text, startsWith('On Oct 15, 2026'));
    expect(body.selection.baseOffset, body.text.length);
  });

  testWidgets('Reply on the phone quotes only the selected words', (
    tester,
  ) async {
    await _pump(tester, compose: false);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    readerSelection.value = 'I booked Osteria del Ponte';
    addTearDown(() => readerSelection.value = null);
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    final quoted = _body(tester).text
        .split('\n')
        .where((l) => l.startsWith('>'))
        .toList();
    expect(quoted, ['> I booked Osteria del Ponte']);
  });

  testWidgets('a phone reply from a plain-text account is plain text', (
    tester,
  ) async {
    final demo = DemoMailSource(now: _now);
    final row = (await demo.page(
      0,
      50,
    )).firstWhere((r) => r.subject == 'Dinner on Friday?');
    final email = demo.accounts.firstWhere((a) => a.id == row.accountId).email;
    await demo.setComposeSettings(ComposeSettings(plainTextAccounts: {email}));
    await _pump(tester, demo: demo, compose: false);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    // Said over the foot, and no formatting bar over selected words.
    expect(
      tester
          .widget<ComposeOptionsLine>(find.byType(ComposeOptionsLine))
          .plainText,
      isTrue,
    );
    await tester.tap(_field(2));
    _body(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
    await tester.pumpAndSettle();
    expect(find.byType(FormatBar), findsNothing);
  });

  testWidgets('Forward on the phone leaves the picture placeholders out', (
    tester,
  ) async {
    await _pump(tester, demo: _Placeholders(), compose: false);
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    final body = _body(tester);
    expect(body.text, contains('Look at this:'));
    expect(body.text, isNot(contains(imagePlaceholder)));
  });

  testWidgets('a refused receipt waits in the phone’s Outbox', (tester) async {
    final demo = await _pump(
      tester,
      demo: DemoMailSource(now: _now, asks: true)
        ..refuseNextReceipt = '550 not allowed',
      compose: false,
    );
    await tester.tap(_row('Dinner on Friday?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send receipt'));
    await tester.pumpAndSettle();
    expect(find.byType(ReadReceiptBand), findsNothing);
    expect(
      find.text(
        'The receipt is waiting in the Outbox and goes as soon as it can.',
      ),
      findsOneWidget,
    );
    expect((await demo.outbox(null)).single.subject, 'Read: Dinner on Friday?');
  });
}
