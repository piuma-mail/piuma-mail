import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/home.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Connects anything; the mailbox holds a space.
class _Joining extends DemoMailSource {
  _Joining() : super(now: _now, spaceToFind: true);

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
  }) async => MailAccount(id: 1, name: name, email: email, color: color);
}

/// A first run for real: no accounts until one is added, which says so.
class _FirstRun extends _Joining {
  _FirstRun() {
    accounts = const [];
  }

  final _added = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _added.stream;

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
    final a = MailAccount(id: 1, name: name, email: email, color: color);
    accounts = [a];
    _added.add(null);
    return a;
  }
}

Finder _field(String label) => find.descendant(
  of: find.bySemanticsLabel(label),
  matching: find.byType(TextField),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Lets the code step enter while its arc turns (it never settles).
Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// First run up to "We found your space".
Future<_Joining> _found(
  WidgetTester tester, {
  bool phone = true,
  bool dark = false,
  ValueChanged<MailAccount>? onDone,
  bool home = false,
}) async {
  tester.view.physicalSize = phone
      ? const Size(390, 844)
      : const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = home ? _FirstRun() : _Joining();
  await tester.pumpWidget(
    PiumaApp(
      initialDark: dark,
      home: (_, _) => home
          ? MailHome(source: source)
          : AddAccountScreen(
              source: source,
              onDone: onDone ?? (_) {},
              now: () => _now,
            ),
    ),
  );
  await tester.pumpAndSettle();
  if (phone) {
    await tester.tap(find.text('Add an account'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('I already use Piuma on another device'));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('If it holds your space, you\'ll link this device'),
    findsOneWidget,
  );
  await tester.enterText(find.byType(TextField).first, 'matteo@studio.it');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('Password'), 'carta-120-opaca');
  await tester.pump();
  await tester.tap(find.text('Connect'));
  await _settle(tester);
  return source;
}

void main() {
  _scanTests();

  testWidgets('a new phone shows its code and is approved', (tester) async {
    MailAccount? done;
    final source = await _found(tester, onDone: (a) => done = a);
    expect(find.text('We found your space'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('accounts'), findsOneWidget);
    expect(
      find.text('End-to-end encrypted · updated yesterday at 18:30'),
      findsOneWidget,
    );
    expect(
      find.text(
        'For security, confirm from a device that\'s already paired: '
        'Matteo’s MacBook, active 2 hours ago.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Show code'));
    await _wait(tester);
    expect(find.text('Confirm on your computer'), findsOneWidget);
    expect(find.text('482 615'), findsOneWidget);
    expect(find.text('Expires in 5:00'), findsOneWidget);
    expect(
      find.text('Matteo’s MacBook will show “New phone wants to connect”'),
      findsOneWidget,
    );

    source.answerJoin();
    await _settle(tester);
    expect(find.text('Phone paired'), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
    await tester.tap(find.text('Go to inbox'));
    expect(done?.email, 'matteo@studio.it');
    expect(source.syncState().on, isTrue);
  });

  testWidgets('Not me on the Mac stops the request', (tester) async {
    final source = await _found(tester);
    await tester.tap(find.text('Show code'));
    await _wait(tester);
    source.answerJoin(SyncProblem.refused);
    await _wait(tester);
    expect(
      find.text('Matteo’s MacBook said this wasn\'t you.'),
      findsOneWidget,
    );
    expect(find.text('Show a new code'), findsOneWidget);
    // Back returns to the space.
    await tester.tap(find.text('Back'));
    await _settle(tester);
    expect(find.text('We found your space'), findsOneWidget);
  });

  testWidgets('the recovery phrase opens the space', (tester) async {
    final source = await _found(tester);
    await tester.tap(find.text('Use recovery phrase'));
    await _settle(tester);
    expect(find.text('0 of 24 words'), findsOneWidget);
    final wrong = DemoMailSource.demoPhrase.split(' ').reversed.join(' ');
    await tester.enterText(find.byType(TextField), wrong);
    await tester.pump();
    expect(find.text('24 of 24 words'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(
      find.text(
        'These words don\'t open your space. Check them and try again.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), DemoMailSource.demoPhrase);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('Phone paired'), findsOneWidget);
    expect(source.syncState().on, isTrue);
  });

  testWidgets('on first run, the new account doesn\'t cut pairing short', (
    tester,
  ) async {
    final source = await _found(tester, home: true);
    expect(source.accounts, hasLength(1));
    expect(find.text('We found your space'), findsOneWidget);
    await tester.tap(find.text('Show code'));
    await _wait(tester);
    expect(find.text('Confirm on your computer'), findsOneWidget);
    source.answerJoin();
    await _settle(tester);
    expect(find.text('Phone paired'), findsOneWidget);
    await tester.tap(find.text('Go to inbox'));
    await _settle(tester);
    expect(find.byType(AddAccountScreen), findsNothing);
  });

  testWidgets('Back from the space goes on alone', (tester) async {
    await _found(tester);
    await tester.tap(find.text('Back'));
    await _settle(tester);
    expect(find.text('Account connected'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'dark' : 'light';
    testWidgets('phone pair found golden $name', (tester) async {
      await _found(tester, dark: dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/phone_pair_found_$name.png'),
      );
    });
  }

  testWidgets('phone pair code golden', (tester) async {
    await _found(tester);
    await tester.tap(find.text('Show code'));
    await _wait(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_code_light.png'),
    );
    await tester.tap(find.text('Back'));
    await _settle(tester);
  });

  testWidgets('phone pair phrase golden', (tester) async {
    await _found(tester);
    await tester.tap(find.text('Use recovery phrase'));
    await _settle(tester);
    await tester.enterText(
      find.byType(TextField),
      DemoMailSource.demoPhrase.split(' ').take(10).join(' '),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_phrase_light.png'),
    );
  });

  testWidgets('phone pair done golden', (tester) async {
    final source = await _found(tester);
    await tester.tap(find.text('Show code'));
    await tester.pump();
    source.answerJoin();
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_done_light.png'),
    );
  });

  testWidgets('desktop pair found golden', (tester) async {
    await _found(tester, phone: false);
    expect(find.text('We found your space'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pair_found_light.png'),
    );
  });

  testWidgets('first run golden with the pairing line', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => AddAccountScreen(source: _Joining(), onDone: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add an account'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_first_run_pair_light.png'),
    );
  });
}

/// First run on a phone with a camera, up to "Link this phone".
Future<_Joining> _scan(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = _Joining()..scans = true;
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => AddAccountScreen(
        source: source,
        onDone: (_) {},
        now: () => _now,
        // The camera reads the Mac's code as soon as it opens.
        scanner: (context, onCode) => _FakeCamera(onCode: onCode),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add an account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('I already use Piuma on another device'));
  await _settle(tester);
  return source;
}

class _FakeCamera extends StatelessWidget {
  const _FakeCamera({required this.onCode});
  final ValueChanged<ScannedPair> onCode;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onCode(DemoMailSource.demoScan),
    child: const ColoredBox(key: ValueKey('camera'), color: Color(0xFF2A2C31)),
  );
}

void _scanTests() {
  testWidgets('a phone links itself by scanning the Mac\'s code', (
    tester,
  ) async {
    final source = await _scan(tester);
    expect(find.text('Link this phone'), findsOneWidget);
    await tester.tap(find.text('Scan code'));
    await _settle(tester);
    expect(find.text('Point at the code on your computer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('camera')));
    await _settle(tester);
    expect(find.text('One last step'), findsOneWidget);
    expect(find.text('matteo@posta.it'), findsOneWidget);
    await tester.enterText(_field('Password'), 'carta-120-opaca');
    await tester.pump();
    await tester.tap(find.text('Link'));
    await tester.pump();
    expect(find.text('Linking…'), findsOneWidget);
    source.answerJoin();
    await _settle(tester);
    expect(find.text('Phone paired'), findsOneWidget);
    expect(source.syncState().on, isTrue);
  });

  testWidgets('Sign in instead goes back to the form, to pair with digits', (
    tester,
  ) async {
    await _scan(tester);
    await tester.tap(find.text('Sign in instead'));
    await _settle(tester);
    expect(
      find.textContaining('If it holds your space, you\'ll link this device'),
      findsOneWidget,
    );
  });

  testWidgets('phone link this phone golden', (tester) async {
    await _scan(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_scan_light.png'),
    );
  });

  testWidgets('phone scanning golden', (tester) async {
    await _scan(tester);
    await tester.tap(find.text('Scan code'));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_camera_light.png'),
    );
  });

  testWidgets('phone one last step golden', (tester) async {
    await _scan(tester);
    await tester.tap(find.text('Scan code'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('camera')));
    await _settle(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/phone_pair_last_step_light.png'),
    );
  });
}
