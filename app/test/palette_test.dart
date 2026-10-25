import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/inbox/attachments.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/command_palette.dart';
import 'package:piuma_mail/search/search_panel.dart';

/// A Thursday morning.
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
  return source;
}

Future<void> _palette(WidgetTester tester, [String typed = '']) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
  if (typed.isEmpty) return;
  await tester.enterText(_inPalette(find.byType(TextField)), typed);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Finder _inPalette(Finder f) =>
    find.descendant(of: find.byType(CommandPalette), matching: f);

Finder _label(String text) => _inPalette(find.text(text, findRichText: true));

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  test('words match the start of a word, accents aside', () {
    expect(paletteMatches('Go to Sent', ['se']), isTrue);
    expect(paletteMatches('Go to Sent', ['ent']), isFalse);
    expect(paletteMatches('Go to Archivio', ['go', 'arch']), isTrue);
    expect(paletteMatches('Vai a Più tardi', ['piu']), isTrue);
    expect(paletteMatches('New message', []), isTrue);
  });

  testWidgets('Ctrl+K opens the palette with its commands; Esc closes it', (
    tester,
  ) async {
    await _pump(tester);
    await _palette(tester);
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.byType(SearchPanel), findsNothing);
    expect(_label('New message'), findsOneWidget);
    expect(_label('Go to Sent'), findsOneWidget);
    expect(_label('Settings'), findsOneWidget);
    expect(_inPalette(find.text('from any screen')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
  });

  testWidgets('typing narrows the commands, Enter runs the first', (
    tester,
  ) async {
    await _pump(tester);
    await _palette(tester, 'sent');
    expect(_label('Go to Sent'), findsOneWidget);
    expect(_label('New message'), findsNothing);
    expect(_label('Search all mail for “sent”'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.text('Sent'), findsWidgets);
  });

  testWidgets('a person: write to them, their mail, their files', (
    tester,
  ) async {
    await _pump(tester);
    await _palette(tester, 'giulia');
    expect(_label('Write to Giulia Romano'), findsOneWidget);
    expect(_label('Show only messages from Giulia'), findsOneWidget);
    expect(_label('Attachments from Giulia'), findsOneWidget);
    expect(_inPalette(find.text('MESSAGES')), findsOneWidget);
    expect(_inPalette(find.text('Dinner on Friday?')), findsOneWidget);

    // The first is picked: Enter writes to her.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ComposePane), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposePane),
        matching: find.text('Giulia Romano'),
      ),
      findsOneWidget,
    );

    // Down twice and Enter: her files, on the board.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await _palette(tester, 'giulia');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentBoard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AttachmentBoard),
        matching: find.text('giulia.romano@posta.it'),
      ),
      findsOneWidget,
    );

    // Her mail only: search, filtered by her address.
    await _palette(tester, 'giulia');
    await tester.tap(_label('Show only messages from Giulia'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
    expect(find.text('from:giulia.romano@posta.it'), findsOneWidget);
  });

  testWidgets('a message found opens in the reader', (tester) async {
    await _pump(tester);
    await _palette(tester, 'osteria');
    await tester.tap(_inPalette(find.text('Dinner on Friday?')));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.byType(Reader), findsOneWidget);
  });

  testWidgets('Search all mail opens search with the words', (tester) async {
    await _pump(tester);
    await _palette(tester, 'quote');
    await tester.tap(_label('Search all mail for “quote”'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
    expect(find.text('4 results'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('palette golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _palette(tester, 'giulia');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/palette_$name.png'),
      );
    }, tags: ['golden']);
  }
}
