import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/icons.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/highlight.dart';
import 'package:piuma_mail/search/search_panel.dart';

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

Future<void> _search(WidgetTester tester, String query) async {
  await tester.tap(find.text('Search…'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(SearchPanel),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// Mail still downloading: changes come faster than a search answers.
class _Busy extends DemoMailSource {
  _Busy() : super(now: _now);

  final _ticks = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _ticks.stream;

  @override
  Future<SearchResults> search(String query, {int limit = 50}) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.search(query, limit: limit);
  }
}

Finder _inPanel(Finder f) =>
    find.descendant(of: find.byType(SearchPanel), matching: f);

void main() {
  group('highlight', () {
    test('words and phrases, operators left out', () {
      expect(searchWords('print quote from:sara is:unread'), [
        'print',
        'quote',
      ]);
      expect(searchWords('"print quote" — x'), ['print quote', 'x']);
    });

    test('marks whole words a search word starts', () {
      expect(highlight('Print quotes, unquoted', ['quot']), [
        ('Print ', false),
        ('quotes', true),
        (', unquoted', false),
      ]);
      expect(highlight('Perché così', ['perche']), [
        ('Perché', true),
        (' così', false),
      ]);
      expect(highlight('nothing', []), [('nothing', false)]);
      expect(countMatches('Quote, quote and QUOTE', ['quote']), 3);
    });

    test('reads the engine snippet markers', () {
      expect(markedRuns('bring the \u0002quotes\u0003.'), [
        ('bring the ', false),
        ('quotes', true),
        ('.', false),
      ]);
      expect(markedRuns('plain'), [('plain', false)]);
    });
  });

  testWidgets('the Search field opens search and Esc closes it', (
    tester,
  ) async {
    await _pump(tester);
    // Ctrl+K opens the palette now (palette_test.dart).
    await tester.tap(find.text('Search…'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
    expect(find.text('Search 3 accounts'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
  });

  testWidgets('finds messages in every account, newest first', (tester) async {
    await _pump(tester);
    await _search(tester, 'quote');
    expect(_inPanel(find.text('4 results')), findsOneWidget);
    expect(
      _inPanel(find.textContaining('Searched 3 accounts · 14 emails')),
      findsOneWidget,
    );
    // The newest is selected and shown with its matches.
    expect(_inPanel(find.text('Personal · matteo@posta.it')), findsNothing);
    expect(_inPanel(find.text('Work · matteo@studio.it')), findsOneWidget);
    expect(_inPanel(find.text('2 matches')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('iCloud · teo@icloud.com')), findsOneWidget);
  });

  testWidgets('results keep up while mail downloads', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = _Busy();
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search…'));
    await tester.pumpAndSettle();
    await tester.enterText(_inPanel(find.byType(TextField)), 'quote');
    // A change every 100 ms, each one asking for the search again.
    for (var i = 0; i < 20; i++) {
      source._ticks.add(null);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_inPanel(find.text('4 results')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('Enter opens the message in the reader', (tester) async {
    await _pump(tester);
    await _search(tester, 'osteria');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.textContaining('four of us with Luca'), findsOneWidget);
  });

  testWidgets('the search key opens the first result, even typed fast', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Search…'));
    await tester.pumpAndSettle();
    await tester.enterText(_inPanel(find.byType(TextField)), 'osteria');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.textContaining('four of us with Luca'), findsOneWidget);
  });

  testWidgets('an archived result opens as archived', (tester) async {
    await _pump(tester);
    await _search(tester, 'osteria');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    Finder archive() => find.descendant(
      of: find.byType(Reader),
      matching: find.bySemanticsLabel('Archive'),
    );
    expect(archive(), findsOneWidget);

    await _search(tester, 'insurance');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('The Casa Serena team'), findsWidgets);
    expect(archive(), findsNothing);
  });

  testWidgets('filters narrow, and can be cleared', (tester) async {
    await _pump(tester);
    await _search(tester, 'quote');
    await tester.tap(_inPanel(find.text('Unread')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('is:unread')), findsWidgets);
    expect(_inPanel(find.text('1 result')), findsOneWidget);

    // The account chip opens a picker.
    await tester.tap(_inPanel(find.text('Account')));
    await tester.pumpAndSettle();
    expect(find.text('All accounts'), findsOneWidget);
    await tester.tap(find.text('Personal').last);
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('Personal')), findsOneWidget);
    expect(_inPanel(find.text('No results with these filters')), findsOne);
    await tester.tap(_inPanel(find.text('Clear filters')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('4 results')), findsOneWidget);
  });

  testWidgets('people match by name or address', (tester) async {
    await _pump(tester);
    await _search(tester, 'sara');
    expect(_inPanel(find.text('People')), findsOneWidget);
    expect(_inPanel(find.text('sara@studio.it')), findsOneWidget);
    await tester.tap(_inPanel(find.text('sara@studio.it')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(_inPanel(find.byType(TextField)));
    expect(field.controller!.text, 'sara from:sara@studio.it');
  });

  testWidgets('From narrows to the first person found', (tester) async {
    await _pump(tester);
    await _search(tester, 'print');
    expect(_inPanel(find.text('From: Sara')), findsNothing);
    await tester.enterText(_inPanel(find.byType(TextField)), 'sara');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(_inPanel(find.text('From: Sara')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('from:sara@studio.it')), findsWidgets);
    expect(_inPanel(find.text('2 results')), findsOneWidget);
    // Another tap lets it go.
    await tester.tap(_inPanel(find.text('From: Sara')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('from:sara@studio.it')), findsNothing);
  });

  testWidgets('archive from a result, with Undo', (tester) async {
    final source = await _pump(tester);
    await _search(tester, 'service');
    expect(_inPanel(find.text('1 result')), findsOneWidget);
    await tester.tap(_inPanel(find.text('Archive')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('No message to show')), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(source.applied.single.$2, MessageAction.archive);
    await tester.pumpAndSettle();
  });

  testWidgets('Attachments: the files of what was found, and the chip', (
    tester,
  ) async {
    await _pump(tester);
    await _search(tester, 'mockup');
    // The email with files has the paperclip; its file is listed.
    expect(
      _inPanel(
        find.byWidgetPredicate(
          (w) => w is PiumaIconView && w.icon == PiumaIcon.paperclip,
        ),
      ),
      findsOneWidget,
    );
    expect(_inPanel(find.text('Attachments')), findsWidgets);
    expect(_inPanel(find.text('Mockup-review-v3.png')), findsOneWidget);
    expect(
      _inPanel(find.text('2.1 MB · Luca Bianchi · today')),
      findsOneWidget,
    );
    await tester.tap(_inPanel(find.text('Mockup-review-v3.png')));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('Work · matteo@studio.it')), findsOneWidget);
    // The preview names its files, the match marked.
    expect(_inPanel(find.text('mockup-v3.pdf')), findsOneWidget);
    expect(_inPanel(find.text('2.4 MB')), findsOneWidget);

    // The chip keeps only mail with files.
    await _search(tester, 'quote');
    expect(_inPanel(find.text('4 results')), findsOneWidget);
    expect(_inPanel(find.text('Catalog-quote.pdf')), findsNothing);
    await tester.tap(_inPanel(find.text('Attachments')).first);
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('1 result')), findsOneWidget);
    expect(_inPanel(find.text('Catalog-quote.pdf')), findsOneWidget);
  });

  testWidgets('search with files golden', (tester) async {
    await _pump(tester);
    await _search(tester, 'mockup');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/search_files_light.png'),
    );
  }, tags: ['golden']);

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('search golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _search(tester, 'quote');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/search_$name.png'),
      );
    }, tags: ['golden']);
  }
}
