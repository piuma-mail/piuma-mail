import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/saved_searches.dart';
import 'package:piuma_mail/search/search_panel.dart';
import 'package:piuma_mail/search/suggestions.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

Future<T> _pump<T extends DemoMailSource>(
  WidgetTester tester,
  T source, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Finder _inPanel(Finder f) =>
    find.descendant(of: find.byType(SearchPanel), matching: f);

Finder get _field => _inPanel(find.byType(TextField));

String _text(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Search…'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

/// A server that answers only when told, and counts the stops.
class _SlowServer extends DemoMailSource {
  _SlowServer() : super(now: _now);

  Completer<ServerResults>? pending;
  int cancels = 0;

  @override
  Future<ServerResults> searchServer(String query, {int limit = 50}) {
    pending = Completer();
    return pending!.future;
  }

  @override
  void cancelServerSearch() {
    cancels++;
    if (pending case final p? when !p.isCompleted) {
      p.completeError(StateError('cancelled'));
    }
  }
}

void main() {
  group('suggestions', () {
    const data = SuggestionData(
      folders: ['Clients/Acme', 'Clients/Studio Nord', 'Invoices'],
      labels: ['To read', 'Worksite'],
      accounts: ['Work', 'Personal'],
      people: [
        Contact(name: 'Sara Conti', email: 'sara@studio.it'),
        Contact(name: 'Luca Bianchi', email: 'luca@studio.it'),
      ],
    );
    List<String> inserts(String typed) => [
      for (final s in searchSuggestions(typed, data, now: _now)) s.insert,
    ];

    test('operators as they are typed, negated too', () {
      expect(inserts('fr'), ['from:']);
      expect(inserts('s'), ['subject:', 'smaller:']);
      expect(inserts('-su'), ['-subject:']);
      expect(inserts('IS'), ['is:']);
      expect(inserts('quote'), isEmpty);
      expect(inserts('from:'), ['from:sara@studio.it', 'from:luca@studio.it']);
    });

    test('values: jobs, folders, labels, accounts, people, sizes, dates', () {
      expect(inserts('in:ac'), ['in:Clients/Acme']);
      expect(inserts('in:nord'), ['in:"Clients/Studio Nord"']);
      expect(inserts('in:a'), ['in:archive', 'in:Clients/Acme']);
      expect(inserts('in:').length, 6);
      expect(inserts('is:u'), ['is:unread']);
      expect(inserts('is:unread'), isEmpty);
      expect(inserts('has:'), ['has:attachment']);
      expect(inserts('label:to'), ['label:"To read"']);
      expect(inserts('account:p'), ['account:Personal']);
      expect(inserts('larger:'), [
        'larger:1M',
        'larger:5M',
        'larger:10M',
        'larger:25M',
      ]);
      expect(inserts('after:'), [
        'after:2026-10-08',
        'after:2026-09-15',
        'after:2025-10-15',
      ]);
      expect(searchSuggestions('to:conti', data, now: _now), [
        const SearchSuggestion('to:sara@studio.it', label: 'Sara Conti'),
      ]);
      expect(inserts('-from:lu'), ['-from:luca@studio.it']);
      expect(inserts('foo:'), isEmpty);
      expect(inserts('in:"cli'), [
        'in:Clients/Acme',
        'in:"Clients/Studio Nord"',
      ]);
    });

    test('the token at the caret, quotes and all', () {
      expect(typedToken('quote fr', 8), (start: 6, typed: 'fr'));
      expect(typedToken('quote ', 6), isNull);
      expect(typedToken('"print qu', 9), isNull);
      expect(typedToken('from:"Sara Co', 13), (
        start: 0,
        typed: 'from:"Sara Co',
      ));
      expect(typedToken('a b', 1), (start: 0, typed: 'a'));
      expect(typedToken('', 0), isNull);
      expect(typedToken('abc', 9), isNull);
      expect(personTyped('-cc:"Sa'), ('cc', 'Sa'));
      expect(personTyped('in:sent'), isNull);
    });

    test('a suggestion replaces the whole token', () {
      TextEditingValue at(String text, int caret) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
      var v = applySuggestion(
        at('quote fr', 8),
        6,
        const SearchSuggestion('from:'),
      );
      expect(v.text, 'quote from:');
      expect(v.selection.baseOffset, 11);
      v = applySuggestion(
        at('in:inb rest', 6),
        0,
        const SearchSuggestion('in:inbox'),
      );
      expect(v.text, 'in:inbox rest');
      expect(v.selection.baseOffset, 9);
      v = applySuggestion(
        at('is:u', 2),
        0,
        const SearchSuggestion('is:unread'),
      );
      expect(v.text, 'is:unread ');
      expect(
        folderPaths(const [
          AccountFolder(mailbox: 'C', name: 'Clients', selectable: false),
          AccountFolder(mailbox: 'C/A', name: 'Acme', depth: 1),
          AccountFolder(mailbox: 'I', name: 'Invoices'),
        ]),
        ['Clients/Acme', 'Invoices'],
      );
    });
  });

  testWidgets('the field suggests folders and people; Tab takes one', (
    tester,
  ) async {
    await _pump(tester, DemoMailSource(now: _now));
    await _open(tester);
    await _type(tester, 'quote in:acm');
    expect(_inPanel(find.text('Suggestions')), findsOneWidget);
    expect(_inPanel(find.text('in:Clients/Acme')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_text(tester), 'quote in:Clients/Acme ');
    expect(_inPanel(find.text('Suggestions')), findsNothing);

    // People, from what is typed.
    await _type(tester, 'from:sa');
    expect(
      _inPanel(find.textContaining('from:sara@studio.it')),
      findsOneWidget,
    );
    await tester.tap(_inPanel(find.textContaining('from:sara@studio.it')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_text(tester), 'from:sara@studio.it ');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('nothing here: the server is asked, its mail shown and opened', (
    tester,
  ) async {
    await _pump(tester, DemoMailSource(now: _now));
    await _open(tester);
    await _type(tester, 'spring catalog');
    expect(_inPanel(find.text('No results')), findsWidgets);
    // A pause first, so a word still being typed isn't sent.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('On the server')), findsOneWidget);
    expect(
      _inPanel(find.text('Print quote for the spring catalog')),
      findsWidgets,
    );
    expect(
      _inPanel(find.bySemanticsLabel(RegExp('Found on the server'))),
      findsWidgets,
    );
    expect(
      _inPanel(
        find.text('1 more email found on the server, now on this device.'),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing);
    expect(find.text('Print quote for the spring catalog'), findsWidgets);

    // Now on this device: found here.
    await _open(tester);
    await _type(tester, 'spring catalog');
    expect(_inPanel(find.text('1 result')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('with results here, the server is asked on request', (
    tester,
  ) async {
    await _pump(tester, DemoMailSource(now: _now));
    await _open(tester);
    await _type(tester, 'quote');
    expect(_inPanel(find.text('4 results')), findsOneWidget);
    expect(_inPanel(find.text('On the server')), findsNothing);
    // ⇧ Ctrl ↵ asks, as the button does.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('On the server')), findsOneWidget);
    expect(
      _inPanel(find.text('Print quote for the spring catalog')),
      findsWidgets,
    );
    // ↓ goes on into the server's results, which the preview shows.
    final subject = _inPanel(find.text('Print quote for the spring catalog'));
    expect(subject, findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(tester.widgetList(subject).length, greaterThan(1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a new query stops the server search running', (tester) async {
    final source = await _pump(tester, _SlowServer());
    await _open(tester);
    await _type(tester, 'quote');
    await tester.tap(_inPanel(find.text('Search on server')));
    await tester.pump();
    expect(_inPanel(find.text('Searching on the server…')), findsOneWidget);
    await tester.enterText(_field, 'quotes');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(source.cancels, greaterThanOrEqualTo(1));
    expect(_inPanel(find.text('Searching on the server…')), findsNothing);
    expect(_inPanel(find.text('Couldn’t search on the server.')), findsNothing);
    expect(_inPanel(find.text('Search on server')), findsOneWidget);

    // Closing search stops it too.
    await tester.tap(_inPanel(find.text('Search on server')));
    await tester.pump();
    final before = source.cancels;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(source.cancels, before + 1);
  });

  testWidgets('a server that fails says so, with Try again', (tester) async {
    final source = await _pump(tester, _SlowServer());
    await _open(tester);
    await _type(tester, 'quote');
    await tester.tap(_inPanel(find.text('Search on server')));
    await tester.pump();
    source.pending!.completeError(StateError('offline'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('Couldn’t search on the server.')), findsOne);
    await tester.tap(_inPanel(find.text('Try again')));
    await tester.pump();
    source.pending!.complete(const ServerResults(failed: 2, partial: true));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('Nothing more on the server.')), findsOne);
    expect(
      _inPanel(find.text('2 accounts’ servers couldn’t be reached.')),
      findsOne,
    );
    expect(
      _inPanel(find.text('Some folders couldn’t be searched in full.')),
      findsOne,
    );
  });

  testWidgets('a search is saved, shown, opened, renamed and deleted', (
    tester,
  ) async {
    final source = await _pump(tester, DemoMailSource(now: _now));
    await _open(tester);
    await _type(tester, 'quote from:sara');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SavedSearchEditor), findsOneWidget);
    final name = find.descendant(
      of: find.byType(SavedSearchEditor),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'Sara quotes');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.savedSearchList.single.name, 'Sara quotes');
    expect(source.savedSearchList.single.query, 'quote from:sara');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // In the sidebar, under the labels; a click searches again.
    expect(find.text('SAVED SEARCHES'), findsOneWidget);
    await tester.tap(find.text('Sara quotes'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_text(tester), 'quote from:sara');
    expect(_inPanel(find.text('2 results')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Right-click renames; a name taken by another one is refused.
    await source.saveSearch('Unread', 'is:unread');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sara quotes'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit saved search'), findsWidgets);
    await tester.enterText(name, 'unread');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Another saved search has this name.'), findsOneWidget);
    await tester.enterText(name, 'Quotes');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Quotes'), findsOneWidget);

    // From the keyboard: F2 on the focused row, then delete.
    Focus.of(tester.element(find.text('Quotes'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete search'));
    await tester.pumpAndSettle();
    expect(
      find.text('Only the saved search goes: the emails stay where they are.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete search').last);
    await tester.pumpAndSettle();
    expect(source.savedSearchList.map((s) => s.name), ['Unread']);
    expect(find.text('Quotes'), findsNothing);
  });

  testWidgets('phone: saved searches above the recent ones', (tester) async {
    final source = DemoMailSource(now: _now)
      ..savedSearchList.add(
        const SavedSearch(id: 1, name: 'Sara quotes', query: 'quote from:sara'),
      );
    await _pump(tester, source, size: const Size(390, 844));
    await tester.tap(find.text('Search 3 accounts'));
    await tester.pumpAndSettle();
    expect(_inPanel(find.text('Saved searches')), findsOneWidget);
    expect(_inPanel(find.text('Sara quotes')), findsOneWidget);
    await tester.tap(
      _inPanel(find.bySemanticsLabel('Rename or delete Sara quotes')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedSearchEditor), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(_inPanel(find.text('Sara quotes')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_text(tester), 'quote from:sara');
    // Saving from the phone: the chip at the end of the filters.
    await tester.dragUntilVisible(
      _inPanel(find.text('Save search')),
      _inPanel(find.text('Unread')),
      const Offset(-200, 0),
    );
    await tester.tap(_inPanel(find.text('Save search')));
    await tester.pumpAndSettle();
    expect(find.byType(SavedSearchEditor), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.savedSearchList.map((s) => s.name), [
      'Sara quotes',
      'quote from:sara',
    ]);
    await tester.pump(const Duration(seconds: 1));
  });

  group('phone, as on the desktop', () {
    const phone = Size(390, 844);

    Future<void> openPhone(WidgetTester tester) async {
      await tester.tap(find.text('Search 3 accounts'));
      await tester.pumpAndSettle();
    }

    testWidgets('suggestions are a row of buttons under the field', (
      tester,
    ) async {
      await _pump(tester, DemoMailSource(now: _now), size: phone);
      await openPhone(tester);
      await _type(tester, 'quote in:acm');
      expect(_inPanel(find.bySemanticsLabel('Suggestions')), findsWidgets);
      final pick = _inPanel(find.text('in:Clients/Acme'));
      expect(pick, findsOneWidget);
      // A finger's size.
      expect(tester.getSize(pick).height, lessThanOrEqualTo(44));
      await tester.tap(pick);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_text(tester), 'quote in:Clients/Acme ');
      await _type(tester, 'from:sa');
      await tester.tap(_inPanel(find.textContaining('from:sara@studio.it')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_text(tester), 'from:sara@studio.it ');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('nothing here: the server is asked; a tap opens its mail', (
      tester,
    ) async {
      await _pump(tester, DemoMailSource(now: _now), size: phone);
      await openPhone(tester);
      await _type(tester, 'spring catalog');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('On the server')), findsOneWidget);
      expect(
        _inPanel(find.bySemanticsLabel(RegExp('Found on the server'))),
        findsWidgets,
      );
      await tester.tap(
        _inPanel(find.text('Print quote for the spring catalog')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Print quote for the spring catalog'), findsWidgets);
    });

    testWidgets('with results here, Search on server asks', (tester) async {
      await _pump(tester, DemoMailSource(now: _now), size: phone);
      await openPhone(tester);
      await _type(tester, 'quote');
      final button = _inPanel(find.text('Search on server'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: _inPanel(find.byType(Scrollable)).last,
      );
      await tester.tap(button);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_inPanel(find.text('On the server')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('desktop, as on the phone', () {
    for (final (name, size) in [
      ('wide', const Size(1440, 900)),
      // The sidebar is a rail of icons here: no saved searches in it.
      ('narrow', const Size(1000, 800)),
    ]) {
      testWidgets('saved searches in the empty search ($name window)', (
        tester,
      ) async {
        final source = DemoMailSource(now: _now)
          ..savedSearchList.add(
            const SavedSearch(
              id: 1,
              name: 'Sara quotes',
              query: 'quote from:sara',
            ),
          );
        await _pump(tester, source, size: size);
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Search')).first);
        await tester.pumpAndSettle();
        expect(_inPanel(find.text('Saved searches')), findsOneWidget);
        // ⋯ renames or deletes, as on the phone.
        await tester.tap(
          _inPanel(find.bySemanticsLabel('Rename or delete Sara quotes')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SavedSearchEditor), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(SavedSearchEditor),
            matching: find.byType(TextField),
          ),
          'Quotes',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(_inPanel(find.text('Quotes')), findsOneWidget);
        await tester.tap(_inPanel(find.text('Quotes')));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(_text(tester), 'quote from:sara');
        expect(_inPanel(find.text('2 results')), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}
