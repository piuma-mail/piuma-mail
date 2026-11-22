import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
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
