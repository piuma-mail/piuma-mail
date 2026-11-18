import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/account_errors.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

const _selfSigned = CertificateProblem(
  host: 'mail.studio.it',
  issue: CertificateIssue.untrusted,
  fingerprint:
      'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
      'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89',
  subject: 'CN=mail.studio.it, O=Studio',
  issuer: 'CN=mail.studio.it, O=Studio',
  notAfter: '2027-01-31',
);

/// A source whose adding does what the test says, and remembers how it
/// was asked.
class _Scripted extends DemoMailSource {
  _Scripted({this.fail, this.oauthProviders = const [], this.found})
    : super(now: _now);

  /// Thrown by the first add; later ones succeed.
  final Object? fail;
  @override
  final List<OAuthProviderInfo> oauthProviders;
  final FoundSettings? found;

  int adds = 0;
  List<TrustedCertificate> gotTrusted = const [];
  int? imapPort;
  String? host;
  String? oauthProvider;
  OAuthClientConfig? oauthClient;

  @override
  Future<FoundSettings?> discoverSettings(String email) async =>
      found ?? await super.discoverSettings(email);

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
    List<TrustedCertificate> trusted = const [],
  }) async {
    adds++;
    gotTrusted = trusted;
    imapPort = port;
    this.host = host;
    if (adds == 1 && fail != null) throw fail!;
    return MailAccount(id: 9, name: name, email: email, color: color);
  }

  @override
  Future<MailAccount> addOAuthAccount({
    required String provider,
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    OAuthClientConfig? client,
  }) async {
    adds++;
    oauthProvider = provider;
    oauthClient = client;
    if (adds == 1 && fail != null) throw fail!;
    return MailAccount(id: 9, name: name, email: email, color: color);
  }
}

Future<void> _pump(WidgetTester tester, MailSource source) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      home: (_, _) => AddAccountScreen(source: source, onDone: (_) {}),
    ),
  );
  await tester.pumpAndSettle();
}

/// The text field labelled [label] (a hint may follow the label).
Finder _field(String label) => find.descendant(
  of: find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
  matching: find.byType(TextField),
);

/// Taps what shows [text], scrolled into view first.
Future<void> _tap(WidgetTester tester, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _manual(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextField).first, email);
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('Password'), 'carta-120-opaca');
  await tester.pump();
}

void main() {
  test('ports go from 1 to 65535, spaces aside', () {
    expect(validPort(' 993 '), 993);
    expect(validPort('1'), 1);
    expect(validPort('65535'), 65535);
    expect(validPort('0'), isNull);
    expect(validPort('65536'), isNull);
    expect(validPort('-1'), isNull);
    expect(validPort('99a'), isNull);
    expect(validPort(''), isNull);
  });

  test('a refused certificate is read from the engine', () {
    final p = CertificateProblem.fromJson(
      '{"host":"mail.studio.it","problem":"changed","fingerprint":"AB:CD",'
      '"subject":"CN=mail.studio.it","issuer":"CN=Studio CA","notAfter":"2027-01-31"}',
    )!;
    expect(p.issue, CertificateIssue.changed);
    expect(p.canTrust, isTrue);
    expect(p.trusted.host, 'mail.studio.it');
    expect(CertificateProblem.fromJson('not json'), isNull);
    expect(
      CertificateProblem.fromJson(
        '{"host":"h","problem":"invalid","fingerprint":"AB"}',
      )!.canTrust,
      isFalse,
    );
  });

  testWidgets('a port out of range is said, and nothing is sent', (
    tester,
  ) async {
    final source = _Scripted();
    await _pump(tester, source);
    await _manual(tester, 'anna@example.org');
    expect(find.text('A port is a number from 1 to 65535.'), findsNothing);
    await tester.enterText(_field('Port').first, '99999');
    await tester.pump();
    expect(find.text('A port is a number from 1 to 65535.'), findsOneWidget);
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(source.adds, 0);
    // Spaces around a good port are fine.
    await tester.enterText(_field('Port').first, ' 993 ');
    await tester.pump();
    expect(find.text('A port is a number from 1 to 65535.'), findsNothing);
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(source.adds, 1);
    expect(source.imapPort, 993);
  });

  testWidgets('an unexpected failure is still shown', (tester) async {
    // As a PlatformException from the Android Keystore would be.
    final source = _Scripted(
      fail: PlatformException(code: 'passwords', message: 'Keystore'),
    );
    await _pump(tester, source);
    await _manual(tester, 'anna@example.org');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(
      find.text('Something went wrong while connecting. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Verify and connect'), findsOneWidget);
  });

  testWidgets('no keyring on Linux says what to install', (tester) async {
    final source = _Scripted(
      fail: const AddAccountException(AddAccountError.noKeyring),
    );
    await _pump(tester, source);
    await _manual(tester, 'anna@example.org');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GNOME Keyring or KWallet'), findsOneWidget);
  });

  testWidgets('a self-signed certificate is shown, and trusted on request', (
    tester,
  ) async {
    final source = _Scripted(
      fail: const AddAccountException(
        AddAccountError.certificate,
        '',
        _selfSigned,
      ),
    );
    await _pump(tester, source);
    await _manual(tester, 'anna@example.org');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(source.gotTrusted, isEmpty);
    expect(
      find.text('The server’s certificate can’t be trusted.'),
      findsOneWidget,
    );
    expect(find.text(_selfSigned.fingerprint), findsOneWidget);
    expect(find.text('CN=mail.studio.it, O=Studio'), findsOneWidget);
    expect(find.text('2027-01-31'), findsOneWidget);
    // Nothing is trusted until the person says so.
    await _tap(tester, 'Trust this certificate');
    expect(source.adds, 2);
    expect(source.gotTrusted.single.host, 'mail.studio.it');
    expect(source.gotTrusted.single.fingerprint, _selfSigned.fingerprint);
    expect(find.text('Account connected'), findsOneWidget);
  });

  testWidgets('a revoked certificate cannot be trusted', (tester) async {
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => const _CardOnly(
          CertificateProblem(
            host: 'mail.studio.it',
            issue: CertificateIssue.invalid,
            fingerprint: 'AB:CD',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trust this certificate'), findsNothing);
    expect(find.text('Trust the new certificate'), findsNothing);
  });

  testWidgets('a changed certificate asks to trust the new one', (
    tester,
  ) async {
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => const _CardOnly(
          CertificateProblem(
            host: 'mail.studio.it',
            issue: CertificateIssue.changed,
            fingerprint: 'AB:CD',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('isn’t the certificate you trusted'),
      findsOneWidget,
    );
    expect(find.text('Trust the new certificate'), findsOneWidget);
  });

  testWidgets('Outlook signs in on Microsoft’s page', (tester) async {
    final source = _Scripted(
      oauthProviders: const [
        OAuthProviderInfo(
          id: 'microsoft',
          name: 'Microsoft',
          builtIn: true,
          appPasswords: false,
          hasTenant: true,
        ),
      ],
    );
    await _pump(tester, source);
    await tester.tap(find.text('Outlook'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Microsoft'), findsWidgets);
    expect(
      find.textContaining('your password stays with Microsoft'),
      findsOneWidget,
    );
    expect(find.text('Password'), findsNothing);
    await tester.enterText(_field('Email address'), 'anna@outlook.com');
    await tester.pump();
    await _tap(tester, 'Sign in with Microsoft', last: true);
    expect(source.oauthProvider, 'microsoft');
    expect(source.oauthClient, isNull);
    expect(find.text('Account connected'), findsOneWidget);
  });

  testWidgets('without a Microsoft client it says why, and takes one', (
    tester,
  ) async {
    final source = _Scripted();
    await _pump(tester, source);
    await tester.tap(find.text('Outlook'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no Microsoft sign-in set up'), findsOneWidget);
    await tester.enterText(_field('Email address'), 'anna@outlook.com');
    await tester.pump();
    await _tap(tester, 'Sign in with Microsoft', last: true);
    expect(source.adds, 0, reason: 'no client: nothing to sign in with');

    await _tap(tester, 'Advanced: your own client ID');
    await tester.enterText(_field('Client ID'), ' my-client ');
    await tester.enterText(_field('Tenant (optional)'), 'organizations');
    await tester.pump();
    await _tap(tester, 'Sign in with Microsoft', last: true);
    expect(source.oauthClient?.clientId, 'my-client');
    expect(source.oauthClient?.tenant, 'organizations');
    expect(source.oauthClient?.clientSecret, isNull);
  });

  testWidgets('a lookup that finds Microsoft goes to its sign-in', (
    tester,
  ) async {
    final source = _Scripted(
      found: const FoundSettings(
        imap: MailServer('outlook.office365.com', 993, ServerSecurity.tls),
        smtp: MailServer('smtp.office365.com', 587, ServerSecurity.startTls),
        username: 'anna@studio.it',
        source: SettingsSource.known,
        oauth: 'microsoft',
      ),
    );
    await _pump(tester, source);
    await tester.enterText(find.byType(TextField).first, 'anna@studio.it');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Microsoft'), findsWidgets);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('Gmail without Google sign-in keeps the app password', (
    tester,
  ) async {
    await _pump(tester, _Scripted());
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    expect(find.text('Gmail needs an app password'), findsOneWidget);
  });

  testWidgets('Gmail with Google sign-in offers it, and the app password', (
    tester,
  ) async {
    final source = _Scripted(
      oauthProviders: const [
        OAuthProviderInfo(
          id: 'google',
          name: 'Google',
          builtIn: true,
          appPasswords: true,
          hasTenant: false,
        ),
      ],
    );
    await _pump(tester, source);
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsWidgets);
    await _tap(tester, 'Use an app password instead');
    expect(find.text('Gmail needs an app password'), findsOneWidget);
  });

  testWidgets(
    'a Google client of one’s own is not offered where it can’t work',
    (tester) async {
      // Google on Android: the redirect comes from the client ID, which the
      // app can't answer for another client.
      final source = _Scripted(
        oauthProviders: const [
          OAuthProviderInfo(
            id: 'google',
            name: 'Google',
            builtIn: true,
            appPasswords: true,
            hasTenant: false,
            ownClient: false,
          ),
        ],
      );
      await _pump(tester, source);
      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced: your own client ID'), findsNothing);
      expect(
        find.textContaining('the client it was built with'),
        findsOneWidget,
      );
      await tester.enterText(_field('Email address'), 'anna@gmail.com');
      await tester.pump();
      await _tap(tester, 'Sign in with Google', last: true);
      expect(source.oauthProvider, 'google');
      expect(source.oauthClient, isNull);
    },
  );

  testWidgets('a cancelled sign-in is said', (tester) async {
    final source = _Scripted(
      fail: const AddAccountException(AddAccountError.signInCancelled),
      oauthProviders: const [
        OAuthProviderInfo(
          id: 'microsoft',
          name: 'Microsoft',
          builtIn: true,
          appPasswords: false,
          hasTenant: true,
        ),
      ],
    );
    await _pump(tester, source);
    await tester.tap(find.text('Outlook'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Email address'), 'anna@outlook.com');
    await tester.pump();
    await _tap(tester, 'Sign in with Microsoft', last: true);
    expect(
      find.textContaining('was closed before it finished'),
      findsOneWidget,
    );
  });
}

class _CardOnly extends StatelessWidget {
  const _CardOnly(this.problem);
  final CertificateProblem problem;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: CertificateCard(problem: problem, onTrust: () {}),
    ),
  );
}
