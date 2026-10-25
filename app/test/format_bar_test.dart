import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/format_bar.dart';
import 'package:piuma_mail/compose/rich_body.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/phone_parts.dart' show ComposeFab;
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _text =
    'Hi Giulia,\n\nFriday works. Before we book, three things to check:\n'
    'the table on the terrace\nwhether Marco comes\nthe time, 8 or 8:30\n\nA.';

Future<DemoMailSource> _compose(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
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
  await tester.tap(phone ? find.byType(ComposeFab) : find.text('Compose'));
  await tester.pumpAndSettle();
  await tester.enterText(_field(0), 'giulia@example.it,');
  await tester.enterText(_field(1), 'Friday dinner');
  await tester.enterText(_field(2), _text);
  await tester.pumpAndSettle();
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

RichBodyController _body(WidgetTester tester) =>
    tester.widget<TextField>(_field(2)).controller! as RichBodyController;

/// Selects [words] in the body, as a drag or a double tap would.
Future<void> _select(WidgetTester tester, String words) async {
  final c = _body(tester);
  final at = c.text.indexOf(words);
  c.selection = TextSelection(baseOffset: at, extentOffset: at + words.length);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the pill shows only while words are selected', (tester) async {
    await _compose(tester);
    expect(find.byType(FormatBar), findsNothing);
    await _select(tester, 'three things to check');
    expect(find.byType(FormatBar), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Bold'));
    await tester.pumpAndSettle();
    expect(_body(tester).marks, [
      BodyMark(
        BodyMarkKind.bold,
        _text.indexOf('three'),
        _text.indexOf('three') + 'three things to check'.length,
      ),
    ]);
    // Still selected, still showing: the tap kept the text's focus.
    expect(find.byType(FormatBar), findsOneWidget);
    _body(tester).selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();
    expect(find.byType(FormatBar), findsNothing);
  });

  testWidgets('lines become a list, and the formatting goes out', (
    tester,
  ) async {
    final source = await _compose(tester);
    await _select(tester, 'terrace\nwhether Marco comes\nthe time');
    await tester.tap(find.bySemanticsLabel('Bulleted list'));
    await tester.pumpAndSettle();
    expect(
      _body(tester).text,
      contains('• the table on the terrace\n• whether Marco comes\n• the time'),
    );
    await _select(tester, 'Friday');
    await tester.tap(find.bySemanticsLabel('Italic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final sent = source.sent.single;
    expect(sent.body, contains('• whether Marco comes'));
    expect(sent.marks.single.kind, BodyMarkKind.italic);
  });

  testWidgets('Link asks for the address', (tester) async {
    await _compose(tester);
    await _select(tester, 'Friday');
    await tester.tap(find.bySemanticsLabel('Link'));
    await tester.pumpAndSettle();
    expect(find.text('Paste or type an address'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(FormatBar),
        matching: find.byType(TextField),
      ),
      'https://trattoriavalentina.it/menu',
    );
    await tester.tap(
      find.descendant(of: find.byType(FormatBar), matching: find.text('Add')),
    );
    await tester.pumpAndSettle();
    expect(
      _body(tester).marks.single,
      BodyMark(
        BodyMarkKind.link,
        _text.indexOf('Friday'),
        _text.indexOf('Friday') + 6,
        'https://trattoriavalentina.it/menu',
      ),
    );
  });

  testWidgets('on the phone the bar takes the foot\'s place', (tester) async {
    await _compose(tester, phone: true);
    expect(find.bySemanticsLabel('Attach file'), findsOneWidget);
    await tester.tap(_field(2));
    await _select(tester, 'three things to check');
    expect(find.byType(FormatBar), findsOneWidget);
    expect(find.bySemanticsLabel('Attach file'), findsNothing);
    _body(tester).selection = const TextSelection.collapsed(offset: 3);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Attach file'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('formatting golden $name', (tester) async {
      await _compose(tester, dark: dark);
      await _select(tester, 'the table on the terrace\nwhether Marco comes');
      await tester.tap(find.bySemanticsLabel('Bulleted list'));
      await tester.pumpAndSettle();
      await _select(tester, 'the time');
      await tester.tap(find.bySemanticsLabel('Bold'));
      await tester.pumpAndSettle();
      await _select(tester, 'three things to check');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compose_format_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone formatting golden', (tester) async {
    await _compose(tester, phone: true);
    await tester.tap(_field(2));
    await _select(tester, 'three things to check');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_compose_format_light.png'),
    );
  }, tags: ['golden']);
}
