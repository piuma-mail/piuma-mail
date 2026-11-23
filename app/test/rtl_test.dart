import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/attach_preview.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/mail_pager.dart';
import 'package:piuma_mail/inbox/message_body.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/phone_parts.dart' show ComposeFab;
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/readable.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/bidi.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);

/// The inbox at [size], laid out right to left unless [rtl] is false,
/// with the demo's Arabic and Hebrew emails.
Future<DemoMailSource> _pump(
  WidgetTester tester, {
  Size size = _phone,
  bool rtl = true,
  bool dark = false,
  bool rtlMail = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, rightToLeft: rtlMail);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      textDirection: rtl ? TextDirection.rtl : null,
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

Rect _rowRect(WidgetTester tester, String subject) => tester.getRect(
  find.ancestor(of: _row(subject), matching: find.byType(InboxRowTile)),
);

/// The direction [text] is laid out in, wherever it is drawn.
TextDirection _drawnDirection(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  return paragraph.textDirection;
}

/// The body's paragraph holding [part].
Finder _richTextContaining(String part) => find.descendant(
  of: find.byType(MessageBody),
  matching: find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(part),
  ),
);

void main() {
  group('which way text reads', () {
    test('by its first strong letter', () {
      expect(firstStrongDirection('مرحبا Matteo'), TextDirection.rtl);
      expect(firstStrongDirection('שלום'), TextDirection.rtl);
      expect(firstStrongDirection('Hello مرحبا'), TextDirection.ltr);
      expect(firstStrongDirection('12:30 — مرحبا'), TextDirection.rtl);
      expect(firstStrongDirection('Ελληνικά'), TextDirection.ltr);
      expect(firstStrongDirection('日本語'), TextDirection.ltr);
      expect(firstStrongDirection('١٢٣ 456 !?'), isNull);
      expect(firstStrongDirection(''), isNull);
    });

    test('only L, R and AL letters are strong', () {
      // Arabic digits with the Arabic decimal and thousands separators
      // (AN), percent sign (ET), European digits and separators (EN, ES,
      // CS) don't decide.
      expect(firstStrongDirection('١٢٫٥ Hello'), TextDirection.ltr);
      expect(firstStrongDirection('١٬٠٠٠ Hello'), TextDirection.ltr);
      expect(firstStrongDirection('٪٥٠ off'), TextDirection.ltr);
      expect(
        firstStrongDirection('\u0600\u06DD 1.5 + 2 Go'),
        TextDirection.ltr,
      );
      expect(firstStrongDirection('\u{10D30}\u{10D39} ok'), TextDirection.ltr);
      // Punctuation goes by its own class: the Arabic comma (CS) and per
      // mille sign (ET) are neutral, the Arabic question mark (AL) and
      // Hebrew maqaf and geresh (R) are right to left.
      expect(firstStrongDirection('\u060C\u0609 Hello'), TextDirection.ltr);
      expect(firstStrongDirection('\u061F Hello'), TextDirection.rtl);
      expect(firstStrongDirection('\u05BE Hello'), TextDirection.rtl);
      expect(firstStrongDirection('\u05F3 Hello'), TextDirection.rtl);
      // A leading combining mark (NSM) or format character (BN) is skipped.
      expect(firstStrongDirection('\u064B\u0651 Hi'), TextDirection.ltr);
      expect(firstStrongDirection('\u0301\u200B مرحبا'), TextDirection.rtl);
      expect(firstStrongDirection('\u05B0Abc'), TextDirection.ltr);
      // Letters elsewhere: Syriac and Thaana are right to left, a
      // Devanagari spacing mark (L, not a letter) left to right.
      expect(firstStrongDirection('ܐܒ'), TextDirection.rtl);
      expect(firstStrongDirection('ހށ'), TextDirection.rtl);
      expect(firstStrongDirection('\u0903'), TextDirection.ltr);
      // A modifier letter that is ON, not L.
      expect(firstStrongDirection('\u02B9 مرحبا'), TextDirection.rtl);
    });

    test('marks decide, isolates do not', () {
      expect(firstStrongDirection('\u200F123 abc'), TextDirection.rtl);
      expect(firstStrongDirection('\u2068Anna\u2069 مرحبا'), TextDirection.rtl);
    });

    test('a subject skips its reply prefixes', () {
      expect(
        firstStrongDirection('Re: Fwd: مرحبا', subject: true),
        TextDirection.rtl,
      );
      expect(firstStrongDirection('Re: مرحبا'), TextDirection.ltr);
      expect(firstStrongDirection('Reunion', subject: true), TextDirection.ltr);
    });

    test('an email reads as its markup says, else as its text', () {
      Readable mail(List<BodyBlock> blocks) => Readable(blocks: blocks);
      const arabic = BodyBlock.text([BodySpan('مرحباً ماتيو')]);
      const english = BodyBlock.text([BodySpan('Hi Matteo')]);
      const marked = BodyBlock.text([BodySpan('Hi Matteo')], rtl: true);
      expect(readingDirection(mail([arabic, english])), TextDirection.rtl);
      expect(readingDirection(mail([english, arabic])), TextDirection.ltr);
      expect(readingDirection(mail([marked])), TextDirection.rtl);
      expect(
        readingDirection(
          mail([
            const BodyBlock.text([BodySpan('2026')]),
          ]),
        ),
        isNull,
      );
      expect(blockDirection(english, TextDirection.rtl), TextDirection.ltr);
      expect(blockDirection(marked, TextDirection.ltr), TextDirection.rtl);
      expect(
        blockDirection(
          const BodyBlock.text([BodySpan('—')]),
          TextDirection.rtl,
        ),
        TextDirection.rtl,
      );
    });

    testWidgets('names are isolated only where they could scramble', (
      tester,
    ) async {
      late String latinInLtr, arabicInLtr, latinInRtl;
      Widget probe(TextDirection d, void Function(BuildContext) read) =>
          Directionality(
            textDirection: d,
            child: Builder(
              builder: (context) {
                read(context);
                return const SizedBox();
              },
            ),
          );
      await tester.pumpWidget(
        probe(TextDirection.ltr, (c) {
          latinInLtr = bidiArg(c, 'Anna (work)');
          arabicInLtr = bidiArg(c, 'ليلى');
        }),
      );
      await tester.pumpWidget(
        probe(TextDirection.rtl, (c) => latinInRtl = bidiArg(c, 'Anna')),
      );
      expect(latinInLtr, 'Anna (work)');
      expect(arabicInLtr, '\u2068ليلى\u2069');
      expect(latinInRtl, '\u2068Anna\u2069');
      expect(isolate(''), '');
    });
  });

  group('direction controls in what senders wrote', () {
    test('are made harmless, one unit for one', () {
      expect(safeBidi('Bank\u202Egro.evil'), 'Bank\uFFFDgro.evil');
      expect(
        safeBidi('a\u202A\u202B\u202C\u202D b'),
        'a\uFFFD\uFFFD\uFFFD\uFFFD b',
      );
      expect(safeBidi('\u2066\u2067\u2068\u2069'), '\uFFFD\uFFFD\uFFFD\uFFFD');
      expect(safeBidi('\u200Ex\u200F\u061C'), '\u2060x\u2060\u2060');
      expect(safeBidi('שלום Anna'), 'שלום Anna');
      const s = '\u202Dab\u200F';
      expect(safeBidi(s).length, s.length);
    });

    testWidgets('a pop in a name cannot close its isolate early', (
      tester,
    ) async {
      late String ltr, rtl;
      Widget probe(TextDirection d, void Function(BuildContext) read) =>
          Directionality(
            textDirection: d,
            child: Builder(
              builder: (context) {
                read(context);
                return const SizedBox();
              },
            ),
          );
      const name = 'ليلى\u2069 \u202Eevil';
      await tester.pumpWidget(
        probe(TextDirection.ltr, (c) => ltr = bidiArg(c, name)),
      );
      await tester.pumpWidget(
        probe(TextDirection.rtl, (c) => rtl = bidiArg(c, 'Anna\u2069x')),
      );
      expect(ltr, '\u2068ليلى\uFFFD \uFFFDevil\u2069');
      expect(rtl, '\u2068Anna\uFFFDx\u2069');
      // Even left as is, Latin in a left-to-right sentence loses them.
      await tester.pumpWidget(
        probe(TextDirection.ltr, (c) => ltr = bidiArg(c, 'Ann\u202Ea')),
      );
      expect(ltr, 'Ann\uFFFDa');
      expect(isolate('a\u2069'), '\u2068a\uFFFD\u2069');
    });

    testWidgets('an override in a display name does not reorder it', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: BidiText('Bank\u202Egro.evil'),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, 'Bank\uFFFDgro.evil');
      expect(text.textDirection, TextDirection.ltr);
    });

    testWidgets('a link\'s text keeps no override and is isolated', (
      tester,
    ) async {
      await tester.pumpWidget(
        PiumaApp(
          home: (_, _) => Material(
            child: MessageBody(
              readable: const Readable(
                blocks: [
                  BodyBlock.text([
                    BodySpan('\u202EPay at '),
                    BodySpan(
                      'bank\u202Emoc.\u2069x',
                      link: 'https://evil.example/',
                      suspicious: true,
                    ),
                    BodySpan(' today'),
                  ]),
                ],
              ),
              images: RemoteImages(DemoMailSource(now: _now)),
              showRemote: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final body = _richTextContaining('today');
      final plain = tester.widget<RichText>(body).text.toPlainText();
      expect(plain, '\u202EPay at \u2068bank\uFFFDmoc.\uFFFDx\u2069 today');
    });

    testWidgets('the trust confirmation shows the name as it is', (
      tester,
    ) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PiumaApp(
          textDirection: TextDirection.rtl,
          home: (_, _) => Material(
            child: SingleChildScrollView(
              child: PrivacySheet(
                readable: const Readable(blocks: [], remoteImages: 1),
                sender: 'PayPal\u2069\u202E moc.liame',
                imagesShown: false,
                onLoadOnce: () {},
                onTrust: (_) {},
                onBlockImages: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.textContaining('Always trust');
      expect(label, findsOneWidget);
      final shown = tester.widget<Text>(label).data!;
      expect(shown, 'Always trust \u2068PayPal\uFFFD\uFFFD moc.liame\u2069');
    });
  });

  group('a right-to-left layout', () {
    testWidgets('mirrors the phone inbox', (tester) async {
      await _pump(tester, rtlMail: false);
      final row = _rowRect(tester, 'Dinner on Friday?');
      final subject = tester.getRect(_row('Dinner on Friday?'));
      // The text starts on the right, after the picture.
      expect(subject.right, greaterThan(row.center.dx));
      expect(subject.right, lessThan(row.right - 50));
      // The time sits at the left end of the name's line.
      final time = tester.getRect(
        find
            .descendant(
              of: find.ancestor(
                of: _row('Dinner on Friday?'),
                matching: find.byType(InboxRowTile),
              ),
              matching: find.text('09:42'),
            )
            .first,
      );
      expect(time.left, lessThan(row.center.dx));
      // Compose floats at the bottom left.
      expect(
        tester.getCenter(find.byType(ComposeFab)).dx,
        lessThan(_phone.width / 2),
      );
    });

    testWidgets('a swipe toward the reading end (left) archives', (
      tester,
    ) async {
      await _pump(tester, rtlMail: false);
      await tester.drag(_row('Dinner on Friday?'), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(_row('Dinner on Friday?'), findsNothing);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('a swipe to the right does not archive', (tester) async {
      await _pump(tester, rtlMail: false);
      await tester.drag(_row('Dinner on Friday?'), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(find.text('Archived'), findsNothing);
    });

    testWidgets('an open email turns to the next with a swipe right', (
      tester,
    ) async {
      await _pump(tester, rtlMail: false);
      final subjects = [
        for (final t in tester.widgetList<InboxRowTile>(
          find.byType(InboxRowTile),
        ))
          t.row.subject,
      ];
      await tester.tap(_row(subjects[1]));
      await tester.pumpAndSettle();
      String showing() =>
          tester.widget<MailPager>(find.byType(MailPager)).row.subject;
      expect(showing(), subjects[1]);
      await tester.fling(find.byType(MailPager), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(showing(), subjects[2]);
      await tester.fling(find.byType(MailPager), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(showing(), subjects[1]);
    });

    testWidgets('the phone reader puts Back on the right', (tester) async {
      await _pump(tester, rtlMail: false);
      await tester.tap(_row('Dinner on Friday?'));
      await tester.pumpAndSettle();
      final back = find.bySemanticsLabel('Inbox').first;
      expect(tester.getCenter(back).dx, greaterThan(_phone.width / 2));
    });

    testWidgets('mirrors the desktop: sidebar on the right, reader on the '
        'left', (tester) async {
      await _pump(tester, size: _desktop, rtlMail: false);
      final list = tester.getRect(find.byType(MessageList));
      final compose = tester.getCenter(find.text('Compose'));
      expect(compose.dx, greaterThan(list.right));
      await tester.tap(_row('Dinner on Friday?'));
      await tester.pumpAndSettle();
      final body = tester.getRect(find.byType(MessageBody));
      expect(body.right, lessThan(list.left + 1));
    });

    testWidgets('settings rows start on the right', (tester) async {
      await _pump(tester, size: _desktop, rtlMail: false);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('Appearance').last);
      expect(title.center.dx, greaterThan(_desktop.width / 2));
    });
  });

  group('mail reads its own way', () {
    testWidgets('Arabic and Hebrew rows in an English inbox', (tester) async {
      await _pump(tester, rtl: false);
      expect(
        _drawnDirection(tester, _row(DemoMailSource.arabicSubject)),
        TextDirection.rtl,
      );
      expect(
        _drawnDirection(tester, _row(DemoMailSource.hebrewSubject)),
        TextDirection.rtl,
      );
      expect(
        _drawnDirection(tester, _row('Dinner on Friday?')),
        TextDirection.ltr,
      );
      // Lined up with the other rows all the same.
      final row = _rowRect(tester, DemoMailSource.arabicSubject);
      final subject = tester.getRect(_row(DemoMailSource.arabicSubject));
      expect(subject.left, lessThan(row.center.dx));
    });

    testWidgets('an Arabic email opens right to left in an English app', (
      tester,
    ) async {
      await _pump(tester, size: _desktop, rtl: false);
      await tester.tap(_row(DemoMailSource.arabicSubject));
      await tester.pumpAndSettle();
      final body = _richTextContaining('هل يناسبك');
      expect(body, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(body).textDirection,
        TextDirection.rtl,
      );
      // The paragraph starts at the body's right edge.
      final column = tester.getRect(find.byType(MessageBody));
      expect(tester.getRect(body).right, closeTo(column.right, 2));
      // The quote's bar is on its right too.
      final quote = _richTextContaining('شكراً على الملفات');
      expect(tester.getRect(quote).right, lessThan(column.right - 10));
    });

    testWidgets('a Hebrew email keeps its English line left to right', (
      tester,
    ) async {
      await _pump(tester, size: _desktop, rtl: false);
      await tester.tap(_row(DemoMailSource.hebrewSubject));
      await tester.pumpAndSettle();
      final hebrew = _richTextContaining('הסדנה מתחילה');
      final english = _richTextContaining('Thanks for the files');
      expect(
        tester.renderObject<RenderParagraph>(hebrew).textDirection,
        TextDirection.rtl,
      );
      expect(
        tester.renderObject<RenderParagraph>(english).textDirection,
        TextDirection.ltr,
      );
      final column = tester.getRect(find.byType(MessageBody));
      expect(tester.getRect(english).left, closeTo(column.left, 2));
    });

    testWidgets('an English email reads left to right in an RTL app', (
      tester,
    ) async {
      await _pump(tester, size: _desktop, rtlMail: false);
      await tester.tap(_row('Dinner on Friday?'));
      await tester.pumpAndSettle();
      final body = _richTextContaining('Osteria del Ponte');
      expect(
        tester.renderObject<RenderParagraph>(body).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('what is typed in compose reads its own way', (tester) async {
      await _pump(tester, rtl: false, rtlMail: false);
      await tester.tap(find.byType(ComposeFab));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(ComposePane),
        matching: find.byType(TextField),
      );
      final subject = fields.at(1);
      final body = fields.at(2);
      TextDirection? dir(Finder f) => tester.widget<TextField>(f).textDirection;
      expect(dir(body), TextDirection.ltr);
      await tester.enterText(body, 'مرحباً، أراك يوم الخميس');
      await tester.pump();
      expect(dir(body), TextDirection.rtl);
      await tester.enterText(subject, 'Re: موعد');
      await tester.pump();
      expect(dir(subject), TextDirection.rtl);
      await tester.enterText(body, 'Hello, مرحباً');
      await tester.pump();
      expect(dir(body), TextDirection.ltr);
    });
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('rtl phone inbox golden $name', (tester) async {
      await _pump(tester, dark: dark, rtlMail: false);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rtl_phone_inbox_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('rtl desktop reader golden $name', (tester) async {
      await _pump(tester, size: _desktop, dark: dark, rtlMail: false);
      await tester.tap(_row('Dinner on Friday?'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rtl_desktop_reader_$name.png'),
      );
    }, tags: ['golden']);
  }

  for (final (kind, size) in [('desktop', _desktop), ('phone', _phone)]) {
    testWidgets('$kind PDF pages turn the same way by button and key', (
      tester,
    ) async {
      await _pump(tester, size: size, rtlMail: false);
      await tester.tap(find.text('Mockup v3 review').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('mockup-v3.pdf').first);
      await tester.pumpAndSettle();
      expect(find.byType(AttachPreview), findsOneWidget);
      final prev = find.bySemanticsLabel('Previous page');
      final next = find.bySemanticsLabel('Next page');
      // Physical, like the swipe and the arrow keys: previous on the
      // left pointing left, next on the right pointing right.
      expect(tester.getCenter(prev).dx, lessThan(tester.getCenter(next).dx));
      for (final button in [prev, next]) {
        final flipped = find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (w) => w is Transform && w.transform.storage[0] < 0,
          ),
        );
        expect(flipped, findsNothing);
      }
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      if (kind == 'desktop') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('Page 1 of 2'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 2'), findsOneWidget);
      }
      await tester.tap(prev);
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });
  }

  testWidgets('rtl phone compose golden', (tester) async {
    await _pump(tester, rtlMail: false);
    await tester.tap(find.byType(ComposeFab));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/rtl_phone_compose_light.png'),
    );
  }, tags: ['golden']);
}
