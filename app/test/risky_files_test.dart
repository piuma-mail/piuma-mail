import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/attachment_chip.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Luca's review, carrying a disguised program, a sheet with macros, a
/// locked archive and a plain document.
Future<List<String>> _pump(
  WidgetTester tester, {
  bool dark = false,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <String>[];
  final before = openLocalFile;
  openLocalFile = (path) async => opened.add(path);
  addTearDown(() => openLocalFile = before);
  final source = DemoMailSource(now: _now, riskyFiles: true);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mockup v3 review'));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return opened;
}

Future<void> _tapFile(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('risky files say so on their chips', (tester) async {
    await _pump(tester);
    expect(find.byType(AttachmentChip), findsNWidgets(4));
    expect(find.text('A program, named like a PDF'), findsOneWidget);
    expect(find.text('Has macros that can run'), findsOneWidget);
    expect(find.text('documents.zip'), findsOneWidget);
  });

  testWidgets('a disguised program asks, and Don’t open keeps it shut', (
    tester,
  ) async {
    final opened = await _pump(tester);
    await _tapFile(tester, 'invoice.pdf.exe');
    expect(find.text('Open this program?'), findsOneWidget);
    expect(
      find.textContaining('looks like a PDF, but it is a program'),
      findsOneWidget,
    );
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(find.text('Open this program?'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('Open anyway opens a file with macros', (tester) async {
    final opened = await _pump(tester);
    await _tapFile(tester, 'Budget 2027.xlsm');
    expect(find.text('Open this file?'), findsOneWidget);
    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();
    expect(opened.single, endsWith('Budget 2027.xlsm'));
  });

  testWidgets('a locked archive asks once it is saved', (tester) async {
    final opened = await _pump(tester);
    await _tapFile(tester, 'documents.zip');
    expect(find.text('Open this archive?'), findsOneWidget);
    await tester.tap(find.text('Don’t open'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
  });

  testWidgets('a safe file opens without asking', (tester) async {
    final opened = await _pump(tester);
    await _tapFile(tester, 'Quote Acme.docx');
    expect(find.text('Open anyway'), findsNothing);
    expect(opened.single, endsWith('Quote Acme.docx'));
  });

  testWidgets('on the phone the question is a sheet', (tester) async {
    final opened = await _pump(tester, size: const Size(390, 844));
    await _tapFile(tester, 'invoice.pdf.exe');
    expect(find.text('Open this program?'), findsOneWidget);
    // Don't open comes first, above Open anyway.
    expect(
      tester.getTopLeft(find.text('Don’t open')).dy,
      lessThan(tester.getTopLeft(find.text('Open anyway')).dy),
    );
    await tester.tap(find.text('Open anyway'));
    await tester.pumpAndSettle();
    expect(opened.single, endsWith('invoice.pdf.exe'));
  });

  for (final dark in [false, true]) {
    testWidgets('risky file golden ${dark ? 'dark' : 'light'}', (tester) async {
      await _pump(tester, dark: dark);
      await _tapFile(tester, 'invoice.pdf.exe');
      await expectLater(
        find.byType(PiumaApp),
        matchesGoldenFile('goldens/risky_file_${dark ? 'dark' : 'light'}.png'),
      );
    });
  }
}
