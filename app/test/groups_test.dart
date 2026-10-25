import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/groups_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// Thursday, October 15, 2026, 10:30: the day of the mockup.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  bool groups = true,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, groups: groups);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: phone ? SettingsSection.accounts : SettingsSection.groups,
        now: () => _now,
      ),
    ),
  );
  await _settle(tester);
  if (phone) {
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Groups')));
    await _settle(tester);
  }
  return source;
}

Future<DemoMailSource> _inbox(WidgetTester tester, {bool phone = false}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, groups: true);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) =>
          InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
  return source;
}

/// Lets what enters (each opened card) run its timer and finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a group folds open to its addresses and switches', (
    tester,
  ) async {
    final source = await _settings(tester);
    expect(find.byType(GroupsPage), findsOneWidget);
    // Work is open at first, as on the board.
    expect(find.text('3 addresses'), findsOneWidget);
    expect(find.text('fatture@studio.it'), findsOneWidget);
    expect(find.text('on matteo@studio.it'), findsNWidgets(2));
    expect(find.text('Work account'), findsOneWidget);
    expect(find.text('Separate Inbox'), findsOneWidget);
    expect(
      find.text(
        'If someone writes to info@studio.it, your reply goes from '
        'info@studio.it, with that group\'s signature.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(PiumaSwitch).first);
    await _settle(tester);
    expect(
      find.text('Its emails live only in the Unified inbox.'),
      findsWidgets,
    );
    expect((await source.groups()).first.separateInbox, isFalse);

    // Personal folds open in its place.
    await tester.tap(find.text('Personal'));
    await _settle(tester);
    expect(find.text('fatture@studio.it'), findsNothing);
    expect(find.text('teo@icloud.com'), findsWidgets);
  });

  testWidgets('the signature and the sending address are picked', (
    tester,
  ) async {
    final source = await _settings(tester);
    await tester.tap(
      find.bySemanticsLabel('Send new emails from, matteo@studio.it'),
    );
    await _settle(tester);
    await tester.tap(find.text('info@studio.it').last);
    await _settle(tester);
    expect((await source.groups()).first.sendFrom, 'info@studio.it');

    await tester.tap(find.bySemanticsLabel('Default signature, Work'));
    await _settle(tester);
    await tester.tap(find.text('No signature'));
    await _settle(tester);
    expect((await source.groups()).first.signatureId, isNull);
    expect(find.text('None'), findsWidgets);
  });

  testWidgets('Add address: a suggestion from Sent, or a new alias', (
    tester,
  ) async {
    final source = await _settings(tester);
    await tester.tap(find.text('Add address'));
    await _settle(tester);
    expect(find.text('Found in your sent mail'), findsOneWidget);
    await tester.tap(find.text('ordini@studio.it'));
    await _settle(tester);
    expect(await source.aliases(2), contains('ordini@studio.it'));
    expect(find.text('4 addresses'), findsOneWidget);

    await tester.tap(find.text('Add address'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'not an address');
    await tester.tap(find.text('Add').last);
    await _settle(tester);
    expect(
      find.text("That doesn't look like an email address."),
      findsOneWidget,
    );
    await tester.tap(find.text('Work').last);
    await tester.enterText(find.byType(TextField).last, 'Hello@studio.it');
    await tester.tap(find.text('Add').last);
    await _settle(tester);
    expect(await source.aliases(2), contains('hello@studio.it'));
    expect(find.text('5 addresses'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Remove hello@studio.it from the group'),
    );
    await _settle(tester);
    expect(find.text('4 addresses'), findsOneWidget);
  });

  testWidgets('New group, renamed, then deleted', (tester) async {
    final source = await _settings(tester);
    await tester.tap(find.text('New group'));
    await _settle(tester);
    final groups = await source.groups();
    expect(groups, hasLength(3));
    expect(groups.last.addresses, isEmpty);
    await tester.enterText(find.byType(TextField).first, 'Projects');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect((await source.groups()).last.name, 'Projects');

    await tester.ensureVisible(find.text('Delete group'));
    await tester.tap(find.text('Delete group'));
    await _settle(tester);
    expect(find.text('Delete Projects?'), findsOneWidget);
    await tester.tap(find.text('Delete group').last);
    await _settle(tester);
    expect(await source.groups(), hasLength(2));
  });

  testWidgets('without groups the page says what one is', (tester) async {
    await _settings(tester, groups: false);
    expect(find.textContaining('No groups yet.'), findsOneWidget);
    expect(
      find.text(
        'If someone writes to one of your aliases, your reply goes from it, '
        'with its group\'s signature.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a reply goes from the address it was written to', (
    tester,
  ) async {
    final source = await _inbox(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Re: Print quote'),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Reply'));
    await _settle(tester);
    expect(find.text('Work · fatture@studio.it'), findsOneWidget);
    // Work's signature comes with Work's address.
    expect(find.text('Signature · Work'), findsOneWidget);
    await tester.tap(find.text('Work · fatture@studio.it'));
    await _settle(tester);
    expect(find.text('Automatic'), findsOneWidget);
    expect(
      find.text('Chosen because Sara wrote to fatture@studio.it'),
      findsOneWidget,
    );
    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('PERSONAL'), findsOneWidget);
    await tester.tap(find.text('info@studio.it').last);
    await _settle(tester);
    expect(find.text('Work · info@studio.it'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await tester.pump(const Duration(seconds: 11));
    await _settle(tester);
    expect(source.sent.single.fromEmail, 'info@studio.it');
  });

  testWidgets('the reply box says which address and signature reply', (
    tester,
  ) async {
    final source = await _inbox(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Re: Print quote'),
      ),
    );
    await _settle(tester);
    final line = find.text(
      'Reply from fatture@studio.it · signature Work',
      findRichText: true,
    );
    expect(line, findsOneWidget);
    await tester.ensureVisible(line);
    await _settle(tester);
    await expectLater(
      find.byType(Reader),
      matchesGoldenFile('goldens/reader_reply_from_light.png'),
    );

    // A few words go out with ⌘↩, from that address, with Undo.
    await tester.enterText(find.byType(TextField).last, 'Sending it today.');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(find.text('Sending…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await _settle(tester);
    final sent = source.sent.single;
    expect(sent.fromEmail, 'fatture@studio.it');
    expect(sent.body, startsWith('Sending it today.'));

    // Mail written to the account's own address needs no line.
    await source.setReplyAsWritten(false);
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Re: Print quote'),
      ),
    );
    await _settle(tester);
    expect(line, findsNothing);
  });

  testWidgets('with the switch off a reply goes from the account', (
    tester,
  ) async {
    final source = await _inbox(tester);
    await source.setReplyAsWritten(false);
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Re: Print quote'),
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('Reply'));
    await _settle(tester);
    expect(find.text('Work · matteo@studio.it'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('groups golden $name', (tester) async {
      await _settings(tester, dark: dark);
      tester.view.physicalSize = const Size(1440, 900);
      await _settle(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/groups_$name.png'),
      );
    });
  }

  testWidgets('phone groups golden', (tester) async {
    await _settings(tester, phone: true);
    expect(find.byType(PiumaSwitch), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_groups_light.png'),
    );
  });

  testWidgets('the sidebar shows a group, then one of its addresses', (
    tester,
  ) async {
    await _inbox(tester);
    expect(find.text('GROUPS'), findsOneWidget);
    expect(find.bySemanticsLabel('All groups, Unified inbox'), findsOneWidget);
    // Personal lives only in the unified inbox: just its account shows.
    expect(find.text('Personal'), findsOneWidget);
    await tester.tap(find.text('Work').first);
    await _settle(tester);
    expect(find.text('3 addresses · 1 unread'), findsOneWidget);
    expect(find.text('Mockup v3 review'), findsOneWidget);
    expect(find.text('Trip photos'), findsNothing);
    expect(find.text('to fatture@studio.it'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Expand Work'));
    await _settle(tester);
    await tester.tap(find.text('fatture@studio.it'));
    await _settle(tester);
    expect(find.text('Only fatture@studio.it'), findsOneWidget);
    expect(find.text('Mockup v3 review'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Re: Print quote'),
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/groups_sidebar_light.png'),
    );

    await tester.tap(
      find.bySemanticsLabel('Only fatture@studio.it. Show the whole group'),
    );
    await _settle(tester);
    expect(find.text('Mockup v3 review'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('All groups, Unified inbox'));
    await _settle(tester);
    expect(find.text('Trip photos'), findsOneWidget);
  });

  testWidgets('on the phone the title picks a group', (tester) async {
    await _inbox(tester, phone: true);
    await tester.tap(find.bySemanticsLabel('Group: all. Change group'));
    await _settle(tester);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('3 addresses · 1 group'), findsOneWidget);
    expect(
      find.text('matteo@studio.it · info@studio.it · fatture@studio.it'),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_group_sheet_light.png'),
    );
    await tester.tap(find.bySemanticsLabel('Work'));
    await _settle(tester);
    expect(find.text('Show'), findsNothing);
    expect(find.text('3 addresses'), findsOneWidget);
    expect(find.text('Mockup v3 review'), findsOneWidget);
    expect(find.text('Trip photos'), findsNothing);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_group_inbox_light.png'),
    );

    await tester.tap(find.bySemanticsLabel('Group: Work. Change group').first);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('All groups'));
    await _settle(tester);
    expect(find.text('Trip photos'), findsOneWidget);
  });

  testWidgets('a group on the phone says where rows went; search keeps to it', (
    tester,
  ) async {
    await _inbox(tester, phone: true);
    await tester.tap(find.bySemanticsLabel('Group: all. Change group'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Work'));
    await _settle(tester);
    expect(find.text('Search Work'), findsOneWidget);
    expect(find.text('to matteo@studio.it'), findsWidgets);

    await tester.tap(find.text('Search Work'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'trip');
    await _settle(tester);
    expect(find.text('Trip photos'), findsNothing);
    await tester.tap(find.text('Work').last);
    await _settle(tester);
    expect(find.text('Trip photos'), findsWidgets);
  });

  test('a group sends from its chosen address while it has it', () {
    const g = MailGroup(
      name: 'Work',
      color: Color(0xFF2F8F83),
      sendFrom: 'INFO@studio.it',
      addresses: [
        GroupAddress(2, 'matteo@studio.it'),
        GroupAddress(2, 'info@studio.it'),
      ],
    );
    expect(g.sender?.email, 'info@studio.it');
    expect(g.copyWith(sendFrom: 'x@y.z').sender?.email, 'matteo@studio.it');
  });
}
