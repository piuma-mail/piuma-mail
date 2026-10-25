import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:piuma_mail/feedback/report_sheet.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';

import 'support/settle.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Remembers which kind of account the screen asked for.
class _Recording extends DemoMailSource {
  _Recording() : super(now: _now);
  String? jmapUrl;
  bool? apiToken;

  @override
  Future<MailAccount> addJmapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String sessionUrl,
    required String password,
    bool apiToken = false,
  }) {
    jmapUrl = sessionUrl;
    this.apiToken = apiToken;
    return super.addJmapAccount(
      name: name,
      email: email,
      color: color,
      sessionUrl: sessionUrl,
      password: password,
    );
  }
}

/// A lookup that fails, as when DNS or the network breaks.
class _BrokenLookup extends DemoMailSource {
  _BrokenLookup() : super(now: _now);

  @override
  Future<FoundSettings?> discoverSettings(String email) =>
      Future.error(StateError('lookup failed'));
}

/// Connects anything, then starts its first download.
class _Connecting extends DemoMailSource {
  _Connecting() : super(now: _now);

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
    status.value = const SyncStatus(
      SyncPhase.downloading,
      done: 1340,
      total: 3200,
      downloading: 9,
    );
    return MailAccount(id: 9, name: name, email: email, color: color);
  }
}

/// A server that turns the password down.
class _Refusing extends DemoMailSource {
  _Refusing() : super(now: _now);

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
  }) async => throw const AddAccountException(AddAccountError.wrongPassword);
}

Future<void> _pump(
  WidgetTester tester, {
  bool dark = false,
  DemoMailSource? source,
  ValueChanged<MailAccount>? onDone,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  source ??= DemoMailSource(now: _now);
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) =>
          AddAccountScreen(source: source!, onDone: onDone ?? (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _continueWith(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.descendant(
  of: find.bySemanticsLabel(label),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('the address comes first', (tester) async {
    await _pump(tester);
    expect(find.text('What’s your email?'), findsOneWidget);
    expect(find.text('Add an account · 1 of 3'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('found settings are shown, ready to connect', (tester) async {
    await _pump(tester);
    await _continueWith(tester, 'matteo@studio.it');
    expect(find.text('We found your settings'), findsOneWidget);
    expect(find.text('imap.studio.it'), findsOneWidget);
    expect(find.text('smtp.studio.it'), findsOneWidget);
    expect(find.text('Your name'), findsOneWidget);
  });

  testWidgets('found settings fit an iPad held upright', (tester) async {
    // iPad Pro 11": the card is narrow enough that the actions' row
    // overflowed with "↵ to connect" at its end.
    await _pump(tester, size: const Size(834, 1194));
    await _continueWith(tester, 'matteo@studio.it');
    expect(find.text('We found your settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without settings the manual form opens, prefilled', (
    tester,
  ) async {
    await _pump(tester);
    await _continueWith(tester, 'anna@example.org');
    expect(find.text('Set up manually'), findsOneWidget);
    expect(find.textContaining('couldn’t find the settings'), findsOneWidget);
    expect(find.text('imap.example.org'), findsOneWidget);
    expect(find.text('smtp.example.org'), findsOneWidget);
    expect(find.text('anna@example.org'), findsOneWidget);
  });

  testWidgets('a failed lookup opens the manual form', (tester) async {
    await _pump(tester, source: _BrokenLookup());
    await _continueWith(tester, 'anna@example.org');
    expect(find.text('Set up manually'), findsOneWidget);
    expect(find.text('imap.example.org'), findsOneWidget);
  });

  testWidgets('a JMAP domain shows one server and connects over JMAP', (
    tester,
  ) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await _continueWith(tester, 'matteo@mail.example.org');
    expect(find.text('We found your settings'), findsOneWidget);
    expect(find.text('JMAP'), findsOneWidget);
    expect(find.text('jmap.mail.example.org'), findsOneWidget);
    expect(find.text('Incoming and outgoing · HTTPS'), findsOneWidget);
    expect(find.text('imap.mail.example.org'), findsNothing);
    await tester.enterText(_field('Password'), 'carta-120-opaca');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(source.jmapUrl, 'https://jmap.mail.example.org/jmap/session');

    // Set up manually starts on JMAP, and still offers IMAP and SMTP.
    await tester.tap(find.text('Set up manually'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://jmap.mail.example.org/jmap/session'),
      findsOneWidget,
    );
    await tester.tap(find.text('IMAP and SMTP'));
    await tester.pumpAndSettle();
    expect(find.text('imap.mail.example.org'), findsOneWidget);
  });

  testWidgets('the manual form sets up a JMAP server', (tester) async {
    final source = _Recording();
    await _pump(tester, source: source);
    await _continueWith(tester, 'anna@example.org');
    expect(find.text('Server type'), findsOneWidget);
    await tester.tap(find.text('JMAP'));
    await tester.pumpAndSettle();
    expect(find.text('jmap.example.org'), findsOneWidget);
    expect(find.text('imap.example.org'), findsNothing);
    expect(find.text('Username'), findsNothing);
    await tester.enterText(_field('Password'), 'carta-120-opaca');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/add_account_manual_jmap_light.png'),
    );
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(source.jmapUrl, 'https://jmap.example.org/.well-known/jmap');
  });

  test('a JMAP server becomes its session address', () {
    expect(
      jmapSessionUrl(' jmap.example.org '),
      'https://jmap.example.org/.well-known/jmap',
    );
    expect(
      jmapSessionUrl('https://api.example.org/jmap/session'),
      'https://api.example.org/jmap/session',
    );
  });

  testWidgets('connected, it shows the account and its download', (
    tester,
  ) async {
    MailAccount? done;
    await _pump(tester, source: _Connecting(), onDone: (a) => done = a);
    await _continueWith(tester, 'matteo@studio.it');
    await tester.enterText(_field('Password'), 'carta-120-opaca');
    await tester.enterText(_field('Account name'), 'Work');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.settleBesideWaves();
    expect(find.text('Account connected'), findsOneWidget);
    expect(find.text('Add an account · 3 of 3'), findsOneWidget);
    expect(find.text('Downloading, newest first…'), findsOneWidget);
    expect(find.text('1,340 / 3,200'), findsOneWidget);
    expect(done, isNull);
    await tester.tap(find.text('Go to inbox'));
    expect(done?.email, 'matteo@studio.it');
  });

  testWidgets('an error offers to report it, with the title filled in', (
    tester,
  ) async {
    await _pump(tester, source: _Refusing());
    expect(find.text('Report this problem'), findsNothing);
    await _continueWith(tester, 'matteo@studio.it');
    await tester.enterText(_field('Password'), 'wrong');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not accept'), findsOneWidget);
    await tester.tap(find.text('Report this problem'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReportSheet),
        matching: find.text('Can’t add my account'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Back returns to the address', (tester) async {
    await _pump(tester);
    await _continueWith(tester, 'matteo@studio.it');
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('What’s your email?'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('add account golden $name', (tester) async {
      await _pump(tester, dark: dark);
      await _continueWith(tester, 'matteo@studio.it');
      await tester.enterText(_field('Password'), 'carta-120-opaca');
      await tester.enterText(_field('Account name'), 'Work');
      await tester.enterText(_field('Your name'), 'Matteo Neri');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_account_found_$name.png'),
      );
    }, tags: ['golden']);
  }

  testWidgets('add account JMAP golden', (tester) async {
    await _pump(tester);
    await _continueWith(tester, 'matteo@mail.example.org');
    await tester.enterText(_field('Password'), 'carta-120-opaca');
    await tester.enterText(_field('Account name'), 'Home');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/add_account_jmap_light.png'),
    );
  }, tags: ['golden']);

  group('phone', () {
    Future<void> pumpPhone(
      WidgetTester tester, {
      bool dark = false,
      bool firstRun = true,
      DemoMailSource? using,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = using ?? DemoMailSource(now: _now);
      await tester.pumpWidget(
        PiumaApp(
          initialDark: dark,
          home: (_, _) => AddAccountScreen(
            source: source,
            onDone: (_) {},
            onCancel: firstRun ? null : () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> continuePhone(WidgetTester tester, String email) async {
      await tester.tap(find.text('Add an account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, email);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    testWidgets('first run starts with the welcome page', (tester) async {
      await pumpPhone(tester);
      expect(find.text('Mail, made light.'), findsOneWidget);
      expect(find.text('Your email stays on your device'), findsOneWidget);
      await tester.tap(find.text('Add an account'));
      await tester.pumpAndSettle();
      expect(find.text('What’s your email?'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      // Back returns to the welcome page.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Mail, made light.'), findsOneWidget);
    });

    testWidgets('adding another account skips the welcome', (tester) async {
      await pumpPhone(tester, firstRun: false);
      expect(find.text('What’s your email?'), findsOneWidget);
    });

    testWidgets('found settings, then connect', (tester) async {
      await pumpPhone(tester);
      await continuePhone(tester, 'matteo@studio.it');
      expect(find.text('We found your settings'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('imap.studio.it'), findsOneWidget);
      await tester.enterText(_field('Password'), 'carta-120-opaca');
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      // The demo can't connect: the error shows on the page.
      expect(find.textContaining('went wrong'), findsOneWidget);

      // Edit opens the manual form, already filled in.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Set up manually'), findsOneWidget);
      expect(find.text('imap.studio.it'), findsOneWidget);
      expect(find.text('Verify and connect'), findsOneWidget);
    });

    testWidgets('without settings the manual form opens', (tester) async {
      await pumpPhone(tester);
      await continuePhone(tester, 'anna@example.org');
      expect(find.text('Set up manually'), findsOneWidget);
      expect(find.text('imap.example.org'), findsOneWidget);
      expect(find.text('smtp.example.org'), findsOneWidget);
      // System Back goes to the address first.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('What’s your email?'), findsOneWidget);
    });

    Future<void> connectPhone(WidgetTester tester, {bool dark = false}) async {
      await pumpPhone(tester, dark: dark, using: _Connecting());
      await continuePhone(tester, 'matteo@studio.it');
      await tester.enterText(_field('Password'), 'carta-120-opaca');
      await tester.enterText(_field('Account name'), 'Work');
      await tester.pump();
      await tester.tap(find.text('Connect'));
      await tester.settleBesideWaves();
    }

    testWidgets('connected, Add another account starts again', (tester) async {
      await connectPhone(tester);
      expect(find.text('Account connected'), findsOneWidget);
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.tap(find.text('Add another account'));
      await tester.pumpAndSettle();
      expect(find.text('What’s your email?'), findsOneWidget);
      expect(find.text('matteo@studio.it'), findsNothing);
    });

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      testWidgets('phone connected golden $name', (tester) async {
        await connectPhone(tester, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_add_done_$name.png'),
        );
      }, tags: ['golden']);
      testWidgets('phone welcome golden $name', (tester) async {
        await pumpPhone(tester, dark: dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_welcome_$name.png'),
        );
      }, tags: ['golden']);
      testWidgets('phone found golden $name', (tester) async {
        await pumpPhone(tester, dark: dark);
        await continuePhone(tester, 'matteo@studio.it');
        await tester.enterText(_field('Password'), 'carta-120-opaca');
        await tester.enterText(_field('Account name'), 'Work');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phone_add_found_$name.png'),
        );
      }, tags: ['golden']);
    }
    testWidgets('phone JMAP golden', (tester) async {
      await pumpPhone(tester);
      await continuePhone(tester, 'matteo@mail.example.org');
      await tester.enterText(_field('Password'), 'carta-120-opaca');
      await tester.enterText(_field('Account name'), 'Home');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_add_jmap_light.png'),
      );
    }, tags: ['golden']);
    testWidgets('phone manual golden', (tester) async {
      await pumpPhone(tester);
      await continuePhone(tester, 'anna@example.org');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_add_manual_light.png'),
      );
    }, tags: ['golden']);
    testWidgets('phone manual JMAP golden', (tester) async {
      await pumpPhone(tester);
      await continuePhone(tester, 'anna@example.org');
      await tester.tap(find.text('JMAP'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('jmap.example.org'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_add_manual_jmap_light.png'),
      );
    }, tags: ['golden']);
  });
}
