import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/compose_pane.dart';
import 'package:piuma_mail/compose/templates.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/settings/templates_page.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
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
  return source;
}

Future<DemoMailSource> _settings(
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
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: phone ? SettingsSection.accounts : SettingsSection.templates,
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (phone) {
    // Writing: the signatures, then the templates below them.
    await tester.tap(find.text('Writing'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('New template'));
    await tester.pumpAndSettle();
  }
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(ComposePane), matching: find.byType(TextField))
    .at(i);

String _text(int i) =>
    (_field(i).evaluate().single.widget as TextField).controller!.text;

Future<void> _compose(WidgetTester tester, {bool phone = false}) async {
  if (phone) {
    await tester.tap(find.bySemanticsLabel('Compose a message'));
  } else {
    await tester.tap(find.text('Compose'));
  }
  await tester.pumpAndSettle();
  await tester.enterText(_field(0), 'Marta <marta@lume.it>,');
  await tester.enterText(_field(2), 'Hi Marta,\n');
  await tester.pumpAndSettle();
}

/// "/" typed at the start of the second line, then "inv" in the list.
Future<void> _typeSlash(WidgetTester tester) async {
  await tester.enterText(_field(2), 'Hi Marta,\n/');
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(TemplatePicker),
      matching: find.byType(TextField),
    ),
    'inv',
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a template is named by its subject, else its first line', () {
    expect(templateName(' Quote ', 'Hello', 'Untitled'), 'Quote');
    expect(
      templateName('', '\nThanks, got it.\nBye', 'Untitled'),
      'Thanks, got it.',
    );
    expect(templateName('', '  ', 'Untitled'), 'Untitled');
  });

  testWidgets('"/" in the foot puts a template where the caret is', (
    tester,
  ) async {
    final source = await _pump(tester);
    await _compose(tester);
    await tester.tap(find.byTooltip('Templates'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePicker), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);

    await tester.tap(find.text('Thanks, received'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePicker), findsNothing);
    expect(_text(2), startsWith('Hi Marta,\nThanks, I got it.'));
    // Used last, it lists first next time.
    expect((await source.templates()).first.name, 'Thanks, received');
  });

  testWidgets('"/" typed at the start of a line narrows, Enter takes it', (
    tester,
  ) async {
    await _pump(tester);
    await _compose(tester);
    await _typeSlash(tester);
    expect(find.text('2 of 3'), findsOneWidget);
    expect(_text(2), 'Hi Marta,\n');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_text(2), startsWith('Hi Marta,\nPlease find'));
    // The subject was empty, so the template's goes in.
    expect(_text(1), 'Invoice for October');
  });

  testWidgets('dismissed, the "/" and what was searched go back', (
    tester,
  ) async {
    await _pump(tester);
    await _compose(tester);
    await _typeSlash(tester);
    await tester.tapAt(const Offset(1400, 880));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePicker), findsNothing);
    expect(_text(2), 'Hi Marta,\n/inv');
  });

  testWidgets('"/" in the middle of a line is just a slash', (tester) async {
    await _pump(tester);
    await _compose(tester);
    await tester.enterText(_field(2), 'Hi Marta,\n');
    await tester.enterText(_field(2), 'Hi Marta,\nand/');
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePicker), findsNothing);
  });

  testWidgets('Save as template keeps what is written', (tester) async {
    final source = await _pump(tester);
    await _compose(tester);
    await tester.enterText(_field(1), 'Quote for catalogs');
    await tester.enterText(_field(2), 'Here is the quote you asked for.');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as template'));
    await tester.pumpAndSettle();
    expect(find.text('Saved as template “Quote for catalogs”'), findsOneWidget);
    final saved = (await source.templates()).firstWhere(
      (t) => t.name == 'Quote for catalogs',
    );
    expect(saved.subject, 'Quote for catalogs');
    expect(saved.body, 'Here is the quote you asked for.');
  });

  testWidgets('Manage opens Settings › Templates', (tester) async {
    await _pump(tester);
    await _compose(tester);
    await tester.tap(find.byTooltip('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatesPage), findsOneWidget);
    expect(find.text('On this device, for every account'), findsOneWidget);
  });

  testWidgets('the phone opens the templates as a sheet', (tester) async {
    await _pump(tester, phone: true);
    await _compose(tester, phone: true);
    await tester.tap(find.byTooltip('Templates'));
    await tester.pumpAndSettle();
    expect(find.byType(TemplatePicker), findsOneWidget);
    await tester.tap(find.text('Invitation to review'));
    await tester.pumpAndSettle();
    expect(_text(2), contains('The new mockups are ready'));
  });

  testWidgets('the phone sheet stays above the keyboard', (tester) async {
    await _pump(tester, phone: true);
    await _compose(tester, phone: true);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.byTooltip('Templates'));
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final sheet = tester.getRect(find.byType(TemplatePicker));
    expect(sheet.bottom, lessThanOrEqualTo(screen.height - 300));
    expect(find.text('Invitation to review').hitTestable(), findsOneWidget);
  });

  testWidgets('Settings › Templates saves as you type, adds and deletes', (
    tester,
  ) async {
    final source = await _settings(tester);
    expect(find.text('Subject: Invoice for October'), findsOneWidget);
    expect(find.text('No subject'), findsNWidgets(2));

    final page = find.byType(TemplatesPage);
    Finder field(int i) =>
        find.descendant(of: page, matching: find.byType(TextField)).at(i);
    await tester.enterText(field(0), 'Monthly invoice');
    await tester.pump(const Duration(seconds: 1));
    expect(
      (await source.templates()).map((t) => t.name),
      contains('Monthly invoice'),
    );

    await tester.tap(find.text('New template'));
    await tester.pumpAndSettle();
    expect(find.text('Untitled template'), findsWidgets);
    expect(await source.templates(), hasLength(4));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await source.templates(), hasLength(3));
    expect(find.text('Untitled template'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('templates_popover_$name golden', (tester) async {
      debugDisableShadows = false;
      try {
        await _pump(tester, dark: dark);
        await _compose(tester);
        await _typeSlash(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/templates_popover_$name.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    }, tags: ['golden']);

    testWidgets('templates_settings_$name golden', (tester) async {
      await _settings(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/templates_settings_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone_templates_sheet golden', (tester) async {
    debugDisableShadows = false;
    try {
      await _pump(tester, phone: true);
      await _compose(tester, phone: true);
      await tester.tap(find.byTooltip('Templates'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_templates_sheet.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }, tags: ['golden']);

  testWidgets('phone_templates_settings golden', (tester) async {
    await _settings(tester, phone: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_templates_settings.png'),
    );
  }, tags: ['golden']);
}
