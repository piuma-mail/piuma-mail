import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/catalog/catalog_page.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/chip.dart';
import 'package:piuma_mail/widgets/message_row.dart';

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required bool dark,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(720, 1040);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      locale: locale,
      home: (dark, toggle) => CatalogPage(dark: dark, onToggleTheme: toggle),
    ),
  );
  // Let the staggered entrances finish.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the catalog shows the design system components', (tester) async {
    await _pumpCatalog(tester, dark: false);
    expect(find.text('Piuma Mail'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.byType(MessageRow), findsNWidgets(3));
  });

  testWidgets('a chip toggles on tap', (tester) async {
    await _pumpCatalog(tester, dark: false);
    PiumaChip chip() => tester.widget<PiumaChip>(
      find.widgetWithText(PiumaChip, 'With attachments'),
    );
    expect(chip().selected, isFalse);
    await tester.tap(find.text('With attachments'));
    await tester.pumpAndSettle();
    expect(chip().selected, isTrue);
  });

  testWidgets('the button switches theme', (tester) async {
    await _pumpCatalog(tester, dark: false);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
  });

  testWidgets('Italian is available as a translation', (tester) async {
    await _pumpCatalog(tester, dark: false, locale: const Locale('it'));
    expect(find.text('Invia'), findsOneWidget);
    expect(find.text('Scuro'), findsOneWidget);
  });

  // Golden screenshots: at the end of each phase they go next to the mockup
  // on the canvas. Regenerate them with `flutter test --update-goldens`.
  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('catalog golden $name', (tester) async {
      await _pumpCatalog(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/catalog_$name.png'),
      );
    }, tags: ['golden']);
  }
}
