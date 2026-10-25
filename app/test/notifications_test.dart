import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/notify/notifier.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

import 'support/fake_notifier.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

FakeNotifier get _fake => notifier as FakeNotifier;

Future<DemoMailSource> _inbox(WidgetTester tester, {DateTime? at}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _fake.shown.clear();
  final source = DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => InboxScreen(
        source: source,
        onAddAccount: () {},
        now: () => at ?? _now,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return source;
}

Future<DemoMailSource> _settings(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
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
        section: SettingsSection.notifications,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return source;
}

const _giulia = MailNotice(
  accountId: 1,
  mailbox: 'INBOX',
  uid: 101,
  sender: 'Giulia Romano',
  senderEmail: 'giulia.romano@posta.it',
  subject: 'Dinner on Friday?',
  preview: 'I booked Osteria del Ponte for 20:30.',
);

const _sara = MailNotice(
  accountId: 2,
  mailbox: 'INBOX',
  uid: 40,
  sender: 'Sara Conti',
  senderEmail: 'sara@studio.it',
  subject: 'Re: Print quote',
  preview: 'I need the file by Friday',
  count: 2,
);

void main() {
  testWidgets('new mail becomes one notice per sender', (tester) async {
    final source = await _inbox(tester);
    source.arrive([_giulia, _sara]);
    await tester.pump();
    expect(_fake.shown.map((n) => n.title), [
      'Giulia Romano',
      'Sara Conti · 2 emails',
    ]);
    final giulia = _fake.shown.first;
    expect(giulia.subject, 'Dinner on Friday?');
    expect(giulia.preview, 'I booked Osteria del Ponte for 20:30.');
    expect(giulia.silent, isFalse);
    // A later notice from the same sender takes the place of this one.
    expect(_fake.shown.last.id, isNot(giulia.id));
    source.arrive([_giulia]);
    await tester.pump();
    expect(_fake.shown.last.id, giulia.id);
  });

  testWidgets('at night they come without a sound', (tester) async {
    final source = await _inbox(tester, at: DateTime(2026, 10, 15, 23, 10));
    source.arrive([_giulia]);
    await tester.pump();
    expect(_fake.shown.single.silent, isTrue);
  });

  testWidgets('with No notices they wait for the summary', (tester) async {
    final source = await _inbox(tester, at: DateTime(2026, 10, 15, 23, 10));
    source.notify = const NotifySettings(hold: true);
    source.arrive([_giulia, _sara]);
    await tester.pump();
    expect(_fake.shown, isEmpty);
    expect(source.held.map((n) => n.sender), ['Giulia Romano', 'Sara Conti']);
  });

  testWidgets('an account switched off rings as usual', (tester) async {
    final source = await _inbox(tester, at: DateTime(2026, 10, 15, 23, 10));
    source.setQuietCovers(2, false);
    source.arrive([_giulia, _sara]);
    await tester.pump();
    expect(_fake.shown.map((n) => (n.title, n.silent)), [
      ('Giulia Romano', true),
      ('Sara Conti · 2 emails', false),
    ]);
  });

  testWidgets('weekends ring as usual unless chosen', (tester) async {
    final source = await _inbox(tester, at: DateTime(2026, 10, 17, 12));
    source.arrive([_giulia]);
    await tester.pump();
    expect(_fake.shown.single.silent, isFalse);
  });

  testWidgets('quiet weekends last all day', (tester) async {
    // Saturday at noon.
    final source = await _inbox(tester, at: DateTime(2026, 10, 17, 12));
    source.notify = const NotifySettings(weekends: true);
    source.arrive([_giulia]);
    await tester.pump();
    expect(_fake.shown.single.silent, isTrue);
  });

  testWidgets('"While you were away" sums up who wrote', (tester) async {
    final source = await _inbox(tester);
    source.reminders = const [
      MailNotice(
        accountId: 0,
        mailbox: 'INBOX',
        uid: 0,
        sender: '',
        count: 12,
        away: AwayNotice(
          emails: 12,
          people: 3,
          names: ['Sara Conti', 'Luca Bianchi', 'Dad'],
        ),
      ),
    ];
    await tester.pump(const Duration(minutes: 10));
    final away = _fake.shown.single;
    expect(away.title, 'While you were away');
    expect(
      away.subject,
      '12 emails, 3 from people: Sara Conti, Luca Bianchi, Dad',
    );
    expect(away.payload, 'inbox');
    expect(away.buttons, isFalse);
  });

  testWidgets('a click opens the message, wherever the app was', (
    tester,
  ) async {
    final source = await _inbox(tester);
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    final dinner = (await source.page(
      0,
      10,
    )).firstWhere((r) => r.subject == 'Dinner on Friday?');
    source.arrive([
      MailNotice(
        accountId: dinner.accountId,
        mailbox: dinner.mailbox,
        uid: dinner.uid,
        sender: 'Giulia Romano',
        senderEmail: dinner.fromEmail,
        subject: dinner.subject,
      ),
    ]);
    await tester.pump();
    _fake.click(_fake.shown.single);
    await tester.pumpAndSettle();
    final reader = tester.widget<Reader>(find.byType(Reader));
    expect(reader.row?.key, dinner.key);
    expect(source.seenSet.single.$1.subject, 'Dinner on Friday?');
  });

  testWidgets('a notice for one email has Reply, Archive and Snooze', (
    tester,
  ) async {
    final source = await _inbox(tester);
    Future<(MailRow, SystemNotice)> notice(String subject) async {
      final row = (await source.page(
        0,
        10,
      )).firstWhere((r) => r.subject == subject);
      source.arrive([
        MailNotice(
          accountId: row.accountId,
          mailbox: row.mailbox,
          uid: row.uid,
          sender: row.fromName,
          senderEmail: row.fromEmail,
          subject: row.subject,
        ),
      ]);
      await tester.pump();
      return (row, _fake.shown.last);
    }

    // Several emails from one sender: buttons would touch only one.
    source.arrive([_sara]);
    await tester.pump();
    expect(_fake.shown.single.buttons, isFalse);

    // Reply sends what was typed in the notice, from the message's account.
    final (dinner, giulia) = await notice('Dinner on Friday?');
    expect(giulia.buttons, isTrue);
    _fake.press(giulia, 'reply', "I'm in!");
    await tester.pumpAndSettle();
    expect(find.text('Sending…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    final reply = source.sent.single;
    expect(reply.accountId, dinner.accountId);
    expect(reply.subject, 'Re: Dinner on Friday?');
    expect(reply.body, "I'm in!");
    expect(source.seenSet.last.$1.key, dinner.key);

    // Archive does what swiping does.
    final (review, luca) = await notice('Mockup v3 review');
    _fake.press(luca, 'archive');
    await tester.pumpAndSettle();
    expect(find.text('Archived'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(source.applied.last, (review, MessageAction.archive));

    // Snooze puts it away until tomorrow morning.
    final (_, dad) = await notice('Trip photos');
    _fake.press(dad, 'snooze');
    await tester.pumpAndSettle();
    expect(find.textContaining('Snoozed until tomorrow'), findsOneWidget);
  });

  testWidgets('Settings › Notifications changes what comes', (tester) async {
    final source = await _settings(tester);
    expect(find.text('Few, and only when they matter.'), findsOneWidget);
    expect(find.text('Recommended'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(source.notify.mode, NotifyMode.all);

    await tester.tap(find.bySemanticsLabel('Quiet hours start at 22:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('23:30'));
    await tester.pumpAndSettle();
    expect(source.notify.quietFrom, 23 * 60 + 30);
    expect(source.quietAt(23 * 60), isFalse);
    expect(source.quietAt(23 * 60 + 45), isTrue);

    // The list opens at the time set, in clock order.
    await tester.tap(find.bySemanticsLabel('Quiet hours end at 8:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7:30'));
    await tester.pumpAndSettle();
    expect(source.notify.quietTo, 7 * 60 + 30);

    await tester.tap(find.byType(PiumaSwitch).first);
    await tester.pumpAndSettle();
    expect(source.notify.quiet, isFalse);
    expect(source.quietAt(23 * 60 + 45), isFalse);

    await tester.tap(find.bySemanticsLabel('Weekends, all day').last);
    await tester.pumpAndSettle();
    expect(source.notify.weekends, isTrue);
    // Saturday at noon.
    expect(source.quietAt(5 * 24 * 60 + 12 * 60), isTrue);

    await tester.tap(find.text('No notices'));
    await tester.pumpAndSettle();
    expect(source.notify.hold, isTrue);

    await tester.ensureVisible(find.text('Work'));
    await tester.tap(find.bySemanticsLabel('Work').last);
    await tester.pumpAndSettle();
    expect(source.quietCovers(2), isFalse);
    expect(find.text('matteo@studio.it · rings as usual'), findsOneWidget);

    expect(find.text('On delivery day, just once.'), findsOneWidget);
    await tester.ensureVisible(find.text('Due dates'));
    await tester.tap(find.bySemanticsLabel('Due dates').last);
    await tester.pumpAndSettle();
    expect(source.notify.due, isFalse);
    expect(source.notify.parcels, isTrue);
  });

  testWidgets('the Vault gives a notice on the day, in words', (tester) async {
    final source = await _inbox(tester);
    source.reminders = const [
      MailNotice(
        accountId: 1,
        mailbox: 'INBOX',
        uid: 7,
        sender: 'Corriere Rapido',
        vault: VaultNotice(
          merchant: 'Corriere Rapido',
          title: 'Desk lamp',
          time: '10:00',
        ),
      ),
      MailNotice(
        accountId: 1,
        mailbox: 'INBOX',
        uid: 8,
        sender: 'Enel Energia',
        vault: VaultNotice(
          dueIn: 3,
          merchant: 'Enel Energia',
          title: 'Electricity bill',
          amount: 6240,
          currency: 'EUR',
        ),
      ),
    ];
    await tester.pump(const Duration(minutes: 10));
    expect(_fake.shown.map((n) => (n.title, n.subject)), [
      (
        'Your package arrives today · Corriere Rapido',
        'Desk lamp · around 10:00',
      ),
      ('Due in 3 days · Enel Energia', '€62.40 · Electricity bill'),
    ]);
    expect(_fake.shown.first.payload, '1\nINBOX\n7');
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('notifications golden $name', (tester) async {
      await _settings(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/settings_notifications_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('phone quiet hours golden', (tester) async {
    final source = await _settings(tester, phone: true);
    source.notify = const NotifySettings(weekends: true, hold: true);
    source.setQuietCovers(1, false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      PiumaApp(
        initialDark: false,
        home: (_, _) => SettingsScreen(
          source: source,
          onBack: () {},
          onAddAccount: () {},
          section: SettingsSection.notifications,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('teo@icloud.com'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('matteo@posta.it · rings as usual'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_settings_quiet_light.png'),
    );
  }, tags: ['golden']);
}
