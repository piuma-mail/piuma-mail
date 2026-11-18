import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/compose/writing_settings.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// Settings › Writing past the signatures: Replies, plain text by account
/// and contact groups, on the desktop and on the phone.

final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _open(WidgetTester tester, {required bool phone}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, contactGroups: true);
  await tester.pumpWidget(
    PiumaApp(
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
    await tester.tap(find.text('Writing'));
    await tester.pumpAndSettle();
  }
  return source;
}

/// The switch of the Replies row titled [title].
Finder _switchOf(String title) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byType(RepliesSettings),
          matching: find.text(title),
        ),
        matching: find.byType(Row),
      )
      .first,
  matching: find.byType(PiumaSwitch),
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _groupField(int i) => find
    .descendant(
      of: find.byType(ContactGroupsSettings),
      matching: find.byType(TextField),
    )
    .at(i);

void main() {
  for (final phone in [false, true]) {
    final on = phone ? 'phone' : 'desktop';

    testWidgets('$on: replies and plain text by account are kept', (
      tester,
    ) async {
      final source = await _open(tester, phone: phone);
      await _tap(tester, _switchOf('Reply below the quote'));
      await _tap(tester, _switchOf('Quote only the selected words'));
      await _tap(tester, _switchOf('Work'));
      final s = await source.composeSettings();
      expect(s.replyBelow, isTrue);
      expect(s.quoteSelection, isFalse);
      expect(s.plainTextAccounts, {'matteo@studio.it'});
      expect(
        find.text('matteo@studio.it · new messages start as plain text'),
        findsOneWidget,
      );
    });

    testWidgets('$on: a contact group is made, edited and deleted', (
      tester,
    ) async {
      final source = await _open(tester, phone: phone);
      await _tap(tester, find.text('New group'));
      expect(find.text('Untitled group'), findsWidgets);
      await tester.enterText(_groupField(0), 'Accountants');
      await tester.enterText(
        _groupField(1),
        '"Rossi, Mario" <mario@studio.it>\nanna@studio.it',
      );
      await tester.pump(const Duration(seconds: 1));
      var groups = await source.contactGroups();
      final made = groups.firstWhere((g) => g.name == 'Accountants');
      expect(made.addresses, [
        '"Rossi, Mario" <mario@studio.it>',
        'anna@studio.it',
      ]);
      expect(find.text('2 addresses'), findsWidgets);

      // The demo's Book club, edited.
      await _tap(tester, find.text('Book club'));
      await tester.enterText(_groupField(0), 'Book club (Thursdays)');
      await tester.pump(const Duration(seconds: 1));
      groups = await source.contactGroups();
      expect(groups.map((g) => g.name), contains('Book club (Thursdays)'));

      await _tap(tester, find.bySemanticsLabel('Delete Book club (Thursdays)'));
      groups = await source.contactGroups();
      expect(groups.map((g) => g.name), ['Accountants']);
    });
  }
}
