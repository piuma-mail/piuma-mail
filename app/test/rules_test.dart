import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/settings/rules_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';
import 'package:piuma_mail/widgets/switch.dart';

/// The grip that drags a folder.
Finder _grip(String name) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Drag to reorder $name',
);

/// A Thursday morning.
final _now = DateTime(2026, 10, 15, 10, 30);

Future<DemoMailSource> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool phone = false,
  RuleSuggestion? suggestion,
  bool synced = false,
  bool labels = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = DemoMailSource(now: _now, labels: labels)
    ..suggestedRule = suggestion;
  if (synced) await source.turnOnSync(source.accounts.first.id);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => SettingsScreen(
        source: source,
        onBack: () {},
        onAddAccount: () {},
        section: phone ? SettingsSection.accounts : SettingsSection.organizing,
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (phone) {
    await tester.ensureVisible(find.text('Organizing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organizing'));
    await tester.pumpAndSettle();
  }
  return source;
}

/// The phone's "Folders & labels" row, to its own page.
Future<void> _openFolders(WidgetTester tester) async {
  final row = find.bySemanticsLabel(RegExp(r'^Folders & labels, '));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder _rule(String start) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(start)}'));

Finder _edit(String text) => find
    .descendant(of: find.byType(RuleEditor), matching: find.text(text))
    .last;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(RuleEditor),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _softShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

MailRow _mail({
  String from = 'luca@studio.it',
  String name = 'Luca Bianchi',
  String subject = 'Invoice no. 214',
  String to = 'Matteo, sara@studio.it',
  String preview = '',
  int account = 2,
  bool seen = false,
}) => MailRow(
  accountId: account,
  mailbox: 'INBOX',
  uid: 1,
  fromName: name,
  fromEmail: from,
  subject: subject,
  preview: preview,
  receivedAt: _now,
  seen: seen,
  to: to,
);

const _acme = RuleSuggestion(
  accountId: 2,
  sender: 'orders@acme.example',
  name: 'Acme Orders',
  target: 'Clients/Acme',
  moves: 9,
);

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  test('a rule reads its field as the engine does', () {
    bool by(RuleField f, RuleOp o, String v) =>
        MailRule(field: f, op: o, value: v).matches(_mail());
    expect(by(RuleField.sender, RuleOp.contains, '@STUDIO.it'), isTrue);
    expect(by(RuleField.sender, RuleOp.contains, 'bianchi'), isTrue);
    expect(by(RuleField.sender, RuleOp.exactly, 'luca'), isFalse);
    expect(by(RuleField.subject, RuleOp.startsWith, 'invoice'), isTrue);
    expect(by(RuleField.subject, RuleOp.notContains, 'quote'), isTrue);
    expect(by(RuleField.recipient, RuleOp.exactly, 'sara@studio.it'), isTrue);
    expect(
      const MailRule(
        field: RuleField.body,
        value: 'payment due',
      ).matches(_mail(preview: 'Hi Matteo, payment due on Friday')),
      isTrue,
    );
    expect(
      const MailRule(accountId: 1, value: 'luca').matches(_mail()),
      isFalse,
    );
    expect(
      const MailRule(
        value: 'x',
        action: RuleAction.markRead,
      ).changes(_mail(seen: true)),
      isFalse,
    );
    expect(const MailRule(value: 'x').complete, isFalse);
    expect(
      const MailRule(accountId: 2, value: 'x', target: 'Projects').complete,
      isTrue,
    );
  });

  testWidgets('rules read as sentences, each with its switch', (tester) async {
    final source = await _pump(tester);
    expect(find.text('Organizing'), findsWidgets);
    expect(
      _rule(
        'When the sender contains @studio.it  →  move to Projects. '
        'Work · 14 emails sorted · last today 9:15',
      ),
      findsOneWidget,
    );
    expect(
      _rule('When the subject contains receipt  →  mark as read. 32 emails'),
      findsOneWidget,
    );
    expect(_rule('When the sender contains noreply@'), findsOneWidget);
    expect(find.textContaining('Paused'), findsOneWidget);

    // The first rule's switch, after the three zones'.
    await tester.tap(find.byType(PiumaSwitch).at(3));
    await tester.pumpAndSettle();
    expect(source.savedRules.first.enabled, isFalse);
    expect(find.text('Paused'), findsNWidgets(2));

    // Every account's own folders, below.
    expect(find.text('Folders & labels'), findsOneWidget);
    expect(find.text('Studio Nord'), findsOneWidget);
    expect(find.text('No folders of its own'), findsNWidgets(2));
  });

  testWidgets('read newsletters archive themselves, with a switch', (
    tester,
  ) async {
    final source = await _pump(tester);
    final card = _rule(
      'When a newsletter was read more than 7 days ago  →  archive. '
      'Built in · every account',
    );
    expect(card, findsOneWidget);
    final toggle = find.bySemanticsLabel(
      'Rule on: When a newsletter was read more than 7 days ago  →  archive',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(source.archivesReadNewsletters, isFalse);
  });

  testWidgets('unopened newsletters archive nightly, with a switch', (
    tester,
  ) async {
    final source = await _pump(tester);
    const sentence = 'Newsletters unopened for 30 days  →  archive';
    expect(_rule('$sentence. Nightly · 318 emails archived'), findsOneWidget);
    final toggle = find.bySemanticsLabel('Rule on: $sentence');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(source.archivesUnopenedNewsletters, isFalse);
  });

  testWidgets('with sync on, rules say they sync', (tester) async {
    await _pump(tester);
    expect(
      find.text('Rules run on this device, on new mail in the inbox'),
      findsOneWidget,
    );
    await _pump(tester, synced: true);
    expect(
      find.text(
        'Rules run on this device and sync across all your devices · '
        'updated 2 min ago',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a new rule: the sentence, what it would sort, Save', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsOneWidget);
    expect(find.text('Save rule'), findsOneWidget);
    await _type(tester, 'luca');

    // A move needs a folder first.
    await tester.tap(_edit('a folder'));
    await tester.pumpAndSettle();
    expect(find.text('Folder'), findsOneWidget);
    await tester.tap(_edit('Invoices'));
    await tester.pumpAndSettle();
    expect(find.text('Folder'), findsNothing);
    expect(find.text('Applies to 1 existing email'), findsOneWidget);
    expect(find.text('Apply to those too'), findsOneWidget);

    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsNothing);
    final saved = source.savedRules.last;
    expect(saved.value, 'luca');
    expect(saved.target, 'Invoices');
    expect(saved.accountId, 2);
    expect(source.moved.map((m) => (m.$1.fromName, m.$2)), [
      ('Luca Bianchi', 'Invoices'),
    ]);
    expect(_rule('When the sender contains luca'), findsOneWidget);
  });

  testWidgets('another field and action; old mail left as it is', (
    tester,
  ) async {
    final source = await _pump(tester);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the sender'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the subject'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('move to'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('archive'));
    await tester.pumpAndSettle();
    expect(find.text('a folder'), findsNothing);
    await _type(tester, 'dinner');
    expect(find.text('Applies to 1 existing email'), findsOneWidget);
    await tester.tap(find.text('Apply to those too'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(source.applied, isEmpty);
    expect(source.savedRules.last.field, RuleField.subject);
    expect(source.savedRules.last.action, RuleAction.archive);
    expect(
      _rule('When the subject contains dinner  →  archive. Active from now'),
      findsOneWidget,
    );
  });

  testWidgets('a rule can move mail to the Vault', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the sender'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the subject'));
    await tester.pumpAndSettle();
    await _type(tester, 'dinner');
    await tester.tap(_edit('a folder'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('Vault'));
    await tester.pumpAndSettle();
    expect(find.text('a folder'), findsNothing);
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    final saved = source.savedRules.last;
    expect(saved.action, RuleAction.vault);
    expect(saved.accountId, isNull);
    expect(source.applied.map((a) => a.$2), [MessageAction.archive]);
    expect(
      _rule('When the subject contains dinner  →  move to Vault'),
      findsOneWidget,
    );
  });

  testWidgets('a rule can put a label on', (tester) async {
    final source = await _pump(tester, labels: true);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    await _type(tester, 'luca');
    await tester.tap(_edit('move to'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('label'));
    await tester.pumpAndSettle();
    expect(find.text('a folder'), findsNothing);
    await tester.tap(_edit('a label'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('Travel'));
    await tester.pumpAndSettle();
    expect(find.text('Applies to 1 existing email'), findsOneWidget);
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    final saved = source.savedRules.last;
    expect((saved.action, saved.target), (RuleAction.label, 'travel'));
    expect(saved.accountId, isNull);
    final travel = (await source.labels()).singleWhere(
      (x) => x.name == 'Travel',
    );
    expect(travel.count, 2);
    expect(_rule('When the sender contains luca  →  label Travel'), findsOne);
  });

  testWidgets('Folders & labels: the labels card renames a label', (
    tester,
  ) async {
    final source = await _pump(tester, labels: true);
    expect(find.text('Folders & labels'), findsOneWidget);
    final card = find.text('shared across all accounts');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(find.text('To read'));
    await tester.pumpAndSettle();
    expect(find.text('Edit label'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Later');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await source.labels()).map((x) => x.name), contains('Later'));
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('the body is a field too', (tester) async {
    final source = await _pump(tester);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the sender'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('the body'));
    await tester.pumpAndSettle();
    await _type(tester, 'unsubscribe');
    await tester.tap(_edit('move to'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(source.savedRules.last.field, RuleField.body);
    expect(_rule('When the body contains unsubscribe'), findsOneWidget);
  });

  testWidgets('folders show how many emails they hold', (tester) async {
    await _pump(tester);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('112'), findsOneWidget);
    expect(find.text('46'), findsOneWidget);
  });

  testWidgets('New folder makes one on the account and lists it', (
    tester,
  ) async {
    final source = await _pump(tester);
    source.refusedFolders.add('Trash');
    // Personal, Work, iCloud: Work is the second.
    await tester.ensureVisible(find.text('New folder').at(1));
    await tester.tap(find.text('New folder').at(1));
    await tester.pumpAndSettle();
    final name = find.bySemanticsLabel('New folder name');
    expect(name, findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Trash');
    await tester.ensureVisible(find.text('Create'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(
      find.text("The server didn't make the folder. Try another name."),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'Quotes 2026');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Quotes 2026'), findsOneWidget);
    expect(find.text('Create'), findsNothing);
    expect((await source.folders(2)).last.name, 'Quotes 2026');
  });

  testWidgets('folders drag into a new order among their siblings', (
    tester,
  ) async {
    final source = await _pump(tester);
    Future<void> drag(String name, double dy) async {
      final grip = _grip(name);
      await tester.ensureVisible(grip);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(grip),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(0, dy / 8));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Future<List<String>> names() async => [
      for (final f in await source.folders(2)) f.name,
    ];

    // A subfolder only moves among its own siblings: past the last one
    // it stays last.
    await drag('Acme', 80);
    expect(await names(), [
      'Clients',
      'Studio Nord',
      'Acme',
      'Invoices',
      'Projects',
    ]);
    // A folder takes its subfolders along.
    await drag('Projects', -160);
    expect(await names(), [
      'Projects',
      'Clients',
      'Studio Nord',
      'Acme',
      'Invoices',
    ]);
    expect(
      tester.getTopLeft(_grip('Projects')).dy,
      lessThan(tester.getTopLeft(_grip('Clients')).dy),
    );
  });

  testWidgets('on the phone a finger holds the grip, then drags', (
    tester,
  ) async {
    final source = await _pump(tester, phone: true);
    await _openFolders(tester);
    final grip = _grip('Projects');
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      [for (final f in await source.folders(2)) f.name],
      ['Clients', 'Acme', 'Studio Nord', 'Projects', 'Invoices'],
    );
  });

  testWidgets('a rule opens to be changed or deleted', (tester) async {
    final source = await _pump(tester);
    await tester.tap(_rule('When the sender contains noreply@'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsOneWidget);
    await tester.tap(find.text('Delete rule'));
    await tester.pumpAndSettle();
    expect(source.savedRules.map((r) => r.id), [1, 2]);
    expect(_rule('When the sender contains noreply@'), findsNothing);
  });

  testWidgets('on the phone Folders & labels is a row to its own page', (
    tester,
  ) async {
    await _pump(tester, phone: true, labels: true);
    expect(find.byType(FoldersAndLabels), findsNothing);
    final folders = [
      for (final a in DemoMailSource(now: _now).accounts)
        ...await DemoMailSource(now: _now).folders(a.id),
    ].length;
    expect(
      find.bySemanticsLabel('Folders & labels, $folders folders · 5 labels'),
      findsOneWidget,
    );
    await _openFolders(tester);
    expect(find.byType(FoldersAndLabels), findsOneWidget);
    expect(find.text('shared across all accounts'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Organizing'));
    await tester.pumpAndSettle();
    expect(find.byType(FoldersAndLabels), findsNothing);
    expect(find.text('New rule'), findsOneWidget);
  });

  testWidgets('on the phone the editor is a sheet', (tester) async {
    final source = await _pump(tester, phone: true);
    expect(find.byType(RulesPage), findsOneWidget);
    await tester.tap(find.text('New rule'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsOneWidget);
    await _type(tester, 'receipt');
    await tester.tap(_edit('move to'));
    await tester.pumpAndSettle();
    await tester.tap(_edit('mark as read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditor), findsNothing);
    expect(source.savedRules, hasLength(4));
  });

  testWidgets('a sender moved often suggests a rule: Create', (tester) async {
    final source = await _pump(tester, suggestion: _acme);
    expect(
      find.text(
        'You often move emails from Acme Orders to Acme. Create a rule?',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Suggested on-device · 9 moves in the last month'),
      findsOneWidget,
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You often move'), findsNothing);
    final saved = source.savedRules.last;
    expect(
      (saved.accountId, saved.field, saved.op, saved.value, saved.target),
      (
        2,
        RuleField.sender,
        RuleOp.contains,
        'orders@acme.example',
        'Clients/Acme',
      ),
    );
    expect(
      _rule('When the sender contains orders@acme.example'),
      findsOneWidget,
    );
  });

  testWidgets('Not now lets the suggestion go', (tester) async {
    final source = await _pump(tester, suggestion: _acme);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You often move'), findsNothing);
    expect(source.suggestedRule, isNull);
    expect(source.savedRules, hasLength(3));
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('rules labels golden $name', (tester) async {
      await _pump(tester, dark: dark, labels: true);
      await tester.ensureVisible(find.text('shared across all accounts'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rules_labels_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone folders golden $name', (tester) async {
      await _pump(tester, dark: dark, phone: true, labels: true);
      await _openFolders(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_folders_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('rules golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await tester.tap(find.text('New rule'));
      await tester.pumpAndSettle();
      await _type(tester, '@studio.it');
      await tester.tap(_edit('a folder'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rules_$name.png'),
      );
    }, tags: ['golden']);

    testWidgets('phone rules golden $name', (tester) async {
      await _softShadows(() async {
        await _pump(tester, dark: dark, phone: true);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_rules_$name.png'),
        );
        await tester.tap(find.text('New rule'));
        await tester.pumpAndSettle();
        await _type(tester, '@studio.it');
        await tester.tap(_edit('move to'));
        await tester.pumpAndSettle();
        await tester.tap(_edit('mark as read'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_rule_sheet_$name.png'),
        );
      });
    }, tags: ['golden']);
  }

  for (final phone in [false, true]) {
    final kind = phone ? 'phone' : 'desktop';
    testWidgets('$kind rule suggestion golden', (tester) async {
      await _pump(tester, phone: phone, suggestion: _acme);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/rule_suggestion_${kind}_light.png'),
      );
    }, tags: ['golden']);
  }
}
