import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';
import 'package:piuma_mail/onboarding/providers.dart';
import 'package:piuma_mail/widgets/links.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Remembers what the screen connected with, and connects it.
class _Recording extends DemoMailSource {
  _Recording() : super(now: _now);
  String? host, username, password, sessionUrl;
  MailServer? smtp;
  bool? apiToken;
  String? name;

  @override
  Future<MailAccount> addImapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String host,
    required int port,
    required ServerSecurity security,
    required String username,
    required String password,
    MailServer? smtp,
  }) async {
    this.name = name;
    this.host = host;
    this.username = username;
    this.password = password;
    this.smtp = smtp;
    return MailAccount(id: 9, name: name, email: email, color: color);
  }

  @override
  Future<MailAccount> addJmapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String sessionUrl,
    required String password,
    bool apiToken = false,
  }) async {
    this.name = name;
    this.sessionUrl = sessionUrl;
    this.password = password;
    this.apiToken = apiToken;
    return MailAccount(id: 9, name: name, email: email, color: color);
  }
}

Finder _field(String label) => find.descendant(
  // A hint joins the label in semantics.
  of: find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
  matching: find.byType(TextField),
);

Future<void> _pump(
  WidgetTester tester, {
  bool phone = false,
  bool dark = false,
  DemoMailSource? source,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => AddAccountScreen(
        source: source ?? DemoMailSource(now: _now),
        onDone: (_) {},
        onCancel: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tile(String label) =>
    find.descendant(of: find.byType(ProviderGrid), matching: find.text(label));

Future<void> _start(WidgetTester tester, String provider) async {
  await tester.tap(_tile(provider));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the address step offers four providers', (tester) async {
    await _pump(tester);
    expect(find.text('Or start from'), findsOneWidget);
    for (final p in ['Gmail', 'iCloud', 'Fastmail', 'PEC']) {
      expect(_tile(p), findsOneWidget);
    }
  });

  testWidgets('Gmail asks for an app password and connects over IMAP', (
    tester,
  ) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await tester.enterText(find.byType(TextField).first, 'matteo@gmail.com');
    await _start(tester, 'Gmail');
    expect(find.text('Gmail needs an app password'), findsOneWidget);
    expect(find.text('Add an account · 2 of 3'), findsOneWidget);
    expect(
      find.text('Turn on 2-Step Verification in your Google Account.'),
      findsOneWidget,
    );
    expect(find.text('Paste the 16 letters here.'), findsOneWidget);
    // The address typed first is kept.
    expect(find.text('matteo@gmail.com'), findsOneWidget);
    expect(find.text('Set up manually'), findsNothing);

    await tester.enterText(_field('App password'), 'abcd efgh ijkl mnop');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Account connected'), findsOneWidget);
    expect(source.host, 'imap.gmail.com');
    expect(source.smtp?.host, 'smtp.gmail.com');
    expect(source.username, 'matteo@gmail.com');
    expect(source.password, 'abcdefghijklmnop');
    expect(source.name, 'Gmail');
  });

  testWidgets('Open App passwords opens Google’s page', (tester) async {
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    await _pump(tester);
    await _start(tester, 'Gmail');
    await tester.tap(find.text('Open App passwords'));
    expect(
      opened.single.toString(),
      'https://myaccount.google.com/apppasswords',
    );
  });

  testWidgets('iCloud sends with STARTTLS on 587', (tester) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await _start(tester, 'iCloud');
    expect(find.text('iCloud needs an app password'), findsOneWidget);
    await tester.enterText(_field('Email address'), 'matteo@icloud.com');
    await tester.enterText(_field('App password'), 'abcd-efgh-ijkl-mnop');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(source.host, 'imap.mail.me.com');
    expect(
      (source.smtp?.host, source.smtp?.port, source.smtp?.security),
      ('smtp.mail.me.com', 587, ServerSecurity.startTls),
    );
    expect(source.password, 'abcd-efgh-ijkl-mnop');
  });

  testWidgets('Fastmail connects over JMAP with an API token', (tester) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await _start(tester, 'Fastmail');
    expect(find.text('Fastmail needs an API token'), findsOneWidget);
    await tester.enterText(_field('Email address'), 'matteo@fastmail.com');
    await tester.enterText(_field('API token'), ' fmu1-abc ');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(source.sessionUrl, 'https://api.fastmail.com/jmap/session');
    expect(source.apiToken, isTrue);
    expect(source.password, 'fmu1-abc');
    expect(source.host, isNull);
  });

  testWidgets('PEC asks for the provider first, and Back returns to it', (
    tester,
  ) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await _start(tester, 'PEC');
    expect(find.text('Who runs your PEC?'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    for (final p in ['Aruba', 'Legalmail', 'Poste', 'Register']) {
      expect(_tile(p), findsOneWidget);
    }
    await _start(tester, 'Legalmail');
    expect(find.text('Sign in to Legalmail'), findsOneWidget);
    expect(find.text('Open App passwords'), findsNothing);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Who runs your PEC?'), findsOneWidget);

    await _start(tester, 'Aruba');
    await tester.enterText(_field('Email address'), 'studio@pec.it');
    await tester.enterText(_field('Password'), 'carta 120');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(source.host, 'imaps.pec.aruba.it');
    expect(source.smtp?.host, 'smtps.pec.aruba.it');
    // A mailbox password is kept as typed.
    expect(source.password, 'carta 120');
    expect(source.name, 'PEC');
  });

  testWidgets('phone: providers under Continue, PEC two by two', (
    tester,
  ) async {
    await _pump(tester, phone: true);
    expect(find.text('Or start from'), findsOneWidget);
    await _start(tester, 'PEC');
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Who runs your PEC?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('What’s your email?'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('add_account_gmail_$name golden', (tester) async {
      await _pump(tester, dark: dark);
      await tester.enterText(
        find.byType(TextField).first,
        'matteo.rossi@gmail.com',
      );
      await _start(tester, 'Gmail');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_account_gmail_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('add_account_start golden', (tester) async {
    await _pump(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/add_account_start_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('phone_add_start golden', (tester) async {
    await _pump(tester, phone: true);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_add_start_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('phone_add_gmail golden', (tester) async {
    await _pump(tester, phone: true);
    await tester.enterText(
      find.byType(TextField).first,
      'matteo.rossi@gmail.com',
    );
    await _start(tester, 'Gmail');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_add_gmail_light.png'),
    );
  }, tags: ['golden']);

  testWidgets('phone_add_pec golden', (tester) async {
    await _pump(tester, phone: true);
    await _start(tester, 'PEC');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_add_pec_light.png'),
    );
  }, tags: ['golden']);
}
