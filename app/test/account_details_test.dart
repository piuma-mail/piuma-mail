import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/notify/notifier.dart';
import 'package:piuma_mail/settings/account_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/settings/signatures_page.dart';
import 'package:piuma_mail/widgets/switch.dart';

import 'support/fake_notifier.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

const _work = 2;
const _failed = SyncStatus(SyncPhase.signInFailed, failed: [_work]);

FakeNotifier get _fake => notifier as FakeNotifier;

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool unsent = false,
  SyncStatus status = SyncStatus.idle,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, unsent: unsent)
    ..status.value = status;
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Work'));
  await tester.pumpAndSettle();
  return source;
}

Finder _field(int i) => find
    .descendant(of: find.byType(AccountPage), matching: find.byType(TextField))
    .at(i);

void main() {
  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';
    testWidgets('$where: an account opens on its details', (tester) async {
      await _settings(tester, phone: phone);
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.text('matteo@studio.it'), findsOneWidget);
      expect(find.text('Working · checked 2 min ago'), findsOneWidget);
      expect(
        find.text(
          'IMAP imap.studio.it:993 · SSL\nSMTP smtp.studio.it:465 · SSL',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(phone ? 'Settings' : 'Accounts').first);
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('name, From name and color are kept as they change', (
    tester,
  ) async {
    final source = await _settings(tester);
    await tester.enterText(_field(0), 'Studio');
    await tester.enterText(_field(1), 'Matteo Rossi');
    await tester.pump(const Duration(seconds: 1));
    final work = source.accounts.firstWhere((a) => a.id == _work);
    expect((work.name, work.senderName), ('Studio', 'Matteo Rossi'));

    await tester.tap(
      find.bySemanticsLabel('Account color'),
      warnIfMissed: false,
    );
    final dots = find.descendant(
      of: find.bySemanticsLabel('Account color'),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(dots.last);
    await tester.pumpAndSettle();
    expect(
      source.accounts.firstWhere((a) => a.id == _work).color,
      isNot(work.color),
    );
  });

  testWidgets('the sign-in alert switches off', (tester) async {
    final source = await _settings(tester);
    expect(await source.signInAlert(_work), isTrue);
    await tester.tap(find.byType(PiumaSwitch));
    await tester.pumpAndSettle();
    expect(await source.signInAlert(_work), isFalse);
  });

  testWidgets('a refused password turns the connection amber', (tester) async {
    await _settings(tester, status: _failed);
    expect(find.text('Can\'t sign in since 09:12'), findsOneWidget);
    expect(
      find.text('The server refused the password. Did it change?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsWidgets);
  });

  testWidgets('Edit servers checks and keeps new servers', (tester) async {
    final source = await _settings(tester);
    await tester.tap(find.text('Edit servers'));
    await tester.pumpAndSettle();
    final host = find.widgetWithText(TextField, 'imap.studio.it');
    await tester.enterText(host, 'mail.studio.it');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await source.accountServers(_work)).imap.host, 'mail.studio.it');
    expect(find.textContaining('IMAP mail.studio.it:993'), findsOneWidget);
  });

  testWidgets('Remove account asks, then takes it off this device', (
    tester,
  ) async {
    final source = await _settings(tester);
    await tester.ensureVisible(find.text('Remove account'));
    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Work from this device?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(source.accounts.map((a) => a.name), ['Personal', 'iCloud']);
    expect(find.byType(AccountPage), findsNothing);
    expect(find.text('Work'), findsNothing);
  });

  for (final phone in [false, true]) {
    final where = phone ? 'phone' : 'desktop';
    testWidgets('$where: an account with unsent mail is removed only once '
        'each message is sent or deleted', (tester) async {
      final source = await _settings(tester, phone: phone, unsent: true);
      await tester.ensureVisible(find.text('Remove account'));
      await tester.tap(find.text('Remove account'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoveAccountPanel), findsOneWidget);
      expect(
        find.textContaining("3 messages written here haven't gone yet"),
        findsOneWidget,
      );
      expect(find.text('Quote for the Rossi kitchen'), findsOneWidget);
      expect(find.textContaining('Not sent · To Luca Ferri'), findsOneWidget);
      expect(
        find.textContaining('Waiting · To Sara Conti, giulia@studio.it'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Draft kept on this device · To Anna Bianchi'),
        findsOneWidget,
      );
      expect(find.text('Save now'), findsOneWidget);
      // Remove is off: tapping it changes nothing.
      Finder remove() => find.descendant(
        of: find.byType(RemoveAccountPanel),
        matching: find.text('Remove'),
      );
      await tester.tap(remove());
      await tester.pumpAndSettle();
      expect(find.byType(RemoveAccountPanel), findsOneWidget);
      expect(source.accounts.map((a) => a.name), contains('Work'));
      // Each one sent, saved or deleted leaves the list.
      await tester.tap(find.text('Send now').first);
      await tester.pumpAndSettle();
      expect(find.text('Quote for the Rossi kitchen'), findsNothing);
      expect(
        find.textContaining("2 messages written here haven't gone yet"),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save now'));
      await tester.pumpAndSettle();
      expect(await source.unsentMail(_work), isEmpty);
      expect(find.textContaining("haven't gone yet"), findsNothing);
      await tester.tap(remove());
      await tester.pumpAndSettle();
      expect(source.accounts.map((a) => a.name), ['Personal', 'iCloud']);
      expect(find.byType(AccountPage), findsNothing);
    });

    testWidgets('$where: Cancel keeps an account with unsent mail', (
      tester,
    ) async {
      final source = await _settings(tester, phone: phone, unsent: true);
      await tester.ensureVisible(find.text('Remove account'));
      await tester.tap(find.text('Remove account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoveAccountPanel), findsNothing);
      expect(source.accounts.map((a) => a.name), contains('Work'));
      expect(await source.unsentMail(_work), hasLength(3));
      // And the check holds without the dialog too.
      await expectLater(
        source.removeAccount(_work),
        throwsA(isA<UnsentMailLeft>()),
      );
    });

    for (final dark in [false, true]) {
      final name = '${where}_${dark ? 'dark' : 'light'}';
      testWidgets('account_remove_unsent_$name golden', (tester) async {
        await _settings(tester, phone: phone, dark: dark, unsent: true);
        await tester.ensureVisible(find.text('Remove account'));
        await tester.tap(find.text('Remove account'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/account_remove_unsent_$name.png'),
        );
      }, tags: ['golden']);
    }
  }

  testWidgets('Default signature opens Signatures', (tester) async {
    await _settings(tester);
    await tester.tap(find.text('Default signature'));
    await tester.pumpAndSettle();
    expect(find.byType(SignaturesPage), findsOneWidget);
  });

  testWidgets('one notice the first time the password is refused', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _fake.shown.clear();
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    source.status.value = _failed;
    await tester.pumpAndSettle();
    expect(_fake.shown.map((n) => n.title), ['Work can\'t sign in']);
    // Still failing: no second notice.
    source.status.value = const SyncStatus(
      SyncPhase.signInFailed,
      failed: [_work],
    );
    await tester.pumpAndSettle();
    expect(_fake.shown, hasLength(1));

    _fake.click(_fake.shown.single);
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
  });

  testWidgets('with the alert off, no notice', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _fake.shown.clear();
    final source = DemoMailSource(now: _now);
    await source.setSignInAlert(_work, false);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    source.status.value = _failed;
    await tester.pumpAndSettle();
    expect(_fake.shown, isEmpty);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('account_details_$name golden', (tester) async {
      await _settings(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_details_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('account_details_failed golden', (tester) async {
    await _settings(tester, status: _failed);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/account_details_failed.png'),
    );
  }, tags: ['golden']);

  testWidgets('phone_account_details golden', (tester) async {
    await _settings(tester, phone: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_account_details.png'),
    );
  }, tags: ['golden']);
}
