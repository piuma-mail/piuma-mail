import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/settings/transfer_page.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Opens Settings › Import and export, with the file windows replaced.
Future<DemoMailSource> openTransfer(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  List<String>? saved,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  pickTransferSaveLocation = (name, label, extensions) async {
    saved?.add(name);
    return '/tmp/piuma-test/$name';
  };
  phoneStagingPath = (name) async => '/tmp/piuma-test/$name';
  pickMailFiles = (label) async => ['/tmp/Takeout.mbox', '/tmp/loose.eml'];
  pickSettingsFile = (label) async => '/tmp/Piuma settings.json';
  final source = DemoMailSource(now: _now);
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
  if (phone) {
    await tester.scrollUntilVisible(
      find.text('Import and export'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Import and export'));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('Exporting a folder shows its progress, then a summary', (
    tester,
  ) async {
    final names = <String>[];
    final source = await openTransfer(tester, saved: names);
    expect(find.byType(TransferPage), findsOneWidget);
    final work = source.accounts.first;
    // The first account's inbox is picked from the start.
    expect(find.text('${work.name} › Inbox'), findsNWidgets(2));
    await tester.tap(find.text('ZIP of .eml'));
    await tester.pump();
    await tester.tap(find.text('Export…').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Exporting ${work.name} › Inbox'), findsOneWidget);
    expect(find.textContaining('496 messages'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(names.single, '${work.name} Inbox.zip');
    expect(find.text('Exported 1,238 messages'), findsOneWidget);
    expect(find.textContaining('only mail downloaded'), findsOneWidget);
    expect(
      find.textContaining('Quarterly report — never downloaded'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Exported 1,238 messages'), findsNothing);
  });

  testWidgets('Importing lists what was already there and what was skipped', (
    tester,
  ) async {
    await openTransfer(tester);
    await tester.tap(find.text('Choose files…'));
    await tester.pumpAndSettle();
    expect(find.text('Imported 1,180 messages'), findsOneWidget);
    expect(find.text('57 were already in the folder.'), findsOneWidget);
    expect(find.text('3 skipped:'), findsOneWidget);
    expect(
      find.textContaining('Takeout.mbox #214 — not an email'),
      findsOneWidget,
    );
    expect(
      find.textContaining('scan.eml — refused by the server'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel stops an import and says it can carry on', (
    tester,
  ) async {
    await openTransfer(tester);
    await tester.tap(find.text('Choose files…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Import stopped.'), findsOneWidget);
  });

  testWidgets('The folder to import into is picked from the account', (
    tester,
  ) async {
    final source = await openTransfer(tester);
    final first = source.accounts.first;
    // An account with folders of its own.
    late MailAccount work;
    late AccountFolder target;
    for (final a in source.accounts) {
      final own = (await source.folders(a.id))
          .where((f) => f.mailbox != 'INBOX' && f.selectable);
      if (own.isNotEmpty) {
        work = a;
        target = own.first;
        break;
      }
    }
    await tester.tap(find.text('${first.name} › Inbox').last);
    await tester.pumpAndSettle();
    // More than one account: the account first, then its folder.
    await tester.tap(find.text(work.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(target.name).last);
    await tester.pumpAndSettle();
    expect(find.text('${work.name} › ${target.name}'), findsOneWidget);
  });

  testWidgets('A settings file fills in accounts and brings signatures', (
    tester,
  ) async {
    await openTransfer(tester);
    await tester.ensureVisible(find.text('Import…'));
    await tester.tap(find.text('Import…'));
    await tester.pumpAndSettle();
    expect(find.text('In this file'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('2 signatures'), findsOneWidget);
    await tester.ensureVisible(find.text('Apply signatures and appearance'));
    await tester.tap(find.text('Apply signatures and appearance'));
    await tester.pumpAndSettle();
    expect(find.text('1 signature added.'), findsOneWidget);
    expect(find.textContaining('waits for its account'), findsOneWidget);
    // Add opens the form filled in, waiting for the password.
    await tester.ensureVisible(find.text('Add'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byType(AddAccountScreen), findsOneWidget);
    expect(
      find.text('https://api.fastmail.example/jmap/session'),
      findsOneWidget,
    );
  });

  testWidgets('A folder is exported from its More menu', (tester) async {
    final source = DemoMailSource(now: _now);
    pickTransferSaveLocation = (name, label, extensions) async => '/tmp/$name';
    final account = source.accounts.first;
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExportFolder(
                context,
                source: source,
                account: account,
                folder: const AccountFolderForTest(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Export “Receipts”'), findsOneWidget);
    expect(find.text('1,240 emails, fetched whole from the server.'), findsOne);
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(find.text('Exported 1,238 messages'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Exported 1,238 messages'), findsNothing);
  });

  testWidgets('On the phone the page opens from the list', (tester) async {
    await openTransfer(tester, phone: true);
    expect(find.byType(TransferPage), findsOneWidget);
    await tester.tap(find.text('Export…').first);
    await tester.pumpAndSettle();
    expect(find.text('Exported 1,238 messages'), findsOneWidget);
  });

  for (final phone in [false, true]) {
    for (final dark in [false, true]) {
      final name =
          'transfer_${phone ? 'phone' : 'desktop'}_${dark ? 'dark' : 'light'}';
      testWidgets('$name golden', (tester) async {
        await openTransfer(tester, phone: phone, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$name.png'),
        );
      });
    }
  }

  test('File names never carry a path', () {
    expect(transferFileName('Work ../../etc', 'mbox'), 'Work etc.mbox');
    expect(transferFileName('A/B\\C', 'zip'), 'A B C.zip');
    expect(transferFileName('', 'mbox'), 'Mail.mbox');
    expect(transferFileName('Caffè', 'mbox'), 'Caffè.mbox');
  });
}

/// A folder of the demo's first account.
class AccountFolderForTest extends AccountFolder {
  const AccountFolderForTest() : super(mailbox: 'Receipts', name: 'Receipts');
}
