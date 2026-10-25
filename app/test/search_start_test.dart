import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/search/search_panel.dart';
import 'package:piuma_mail/search/search_start.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Search opened on a 390×844 phone, before anything is typed
/// (`SearchEmpty`).
Future<DemoMailSource> _pump(WidgetTester tester, {bool dark = false}) async {
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
  await tester.tap(find.text('Search 3 accounts'));
  await tester.pumpAndSettle();
  return source;
}

Finder _inSearch(Finder f) =>
    find.descendant(of: find.byType(SearchPanel), matching: f);

Finder get _field => _inSearch(find.byType(TextField));

void main() {
  testWidgets('an empty search shows types, people and recent searches', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(SearchStartView), findsOneWidget);
    expect(find.text('Search by type'), findsOneWidget);
    for (final label in [
      'With attachments',
      'From people',
      'Vault',
      'Newsletters',
    ]) {
      expect(_inSearch(find.text(label)), findsOneWidget);
    }
    expect(find.text('Frequent contacts'), findsOneWidget);
    expect(find.bySemanticsLabel('Search mail from Sara Conti'), findsOne);
    expect(find.text('cellar keys'), findsOneWidget);
    expect(
      find.text('12,480 emails indexed on this device · works offline'),
      findsOneWidget,
    );
    // No filters yet.
    expect(_inSearch(find.text('Last month')), findsNothing);
  });

  testWidgets('a type is a filter, shown in the field', (tester) async {
    await _pump(tester);
    await tester.tap(_inSearch(find.text('With attachments')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchStartView), findsNothing);
    expect(find.text('has:attachment'), findsOneWidget);
    expect(find.text('Add words…'), findsOneWidget);
    expect(
      _inSearch(find.text('Mockup v3 review', findRichText: true)),
      findsWidgets,
    );
    expect(
      _inSearch(find.text('Dinner on Friday?', findRichText: true)),
      findsNothing,
    );
  });

  testWidgets('a recent search runs again; the cross forgets it', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Remove cellar keys'));
    await tester.pumpAndSettle();
    expect(find.text('cellar keys'), findsNothing);
    expect(source.recentSearches, isNot(contains('cellar keys')));

    await tester.tap(find.text('lease agreement'));
    await tester.pumpAndSettle();
    expect(find.text('has:attachment'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'lease agreement',
    );
  });

  testWidgets('Clear forgets every recent search', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Clear recent searches'));
    await tester.pumpAndSettle();
    expect(find.text('No recent searches.'), findsOneWidget);
    expect(source.recentSearches, isEmpty);
  });

  testWidgets('a person searches their mail; opening one keeps the search', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Search mail from Giulia Romano'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field).controller!.text,
      'from:giulia.romano@posta.it',
    );
    await tester.tap(
      _inSearch(find.text('Dinner on Friday?', findRichText: true)).first,
    );
    await tester.pumpAndSettle();
    expect(source.recentSearches.first, 'from:giulia.romano@posta.it');
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('search start golden $name', (tester) async {
      await _pump(tester, dark: dark);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/search_start_$name.png'),
      );
    }, tags: ['golden']);
  }
}
