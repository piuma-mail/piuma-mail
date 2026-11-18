import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/onboarding/account_errors.dart';
import 'package:piuma_mail/onboarding/add_account_screen.dart';
import 'package:piuma_mail/settings/account_page.dart';
import 'package:piuma_mail/settings/settings_screen.dart';

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

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

Future<void> _pump(
  WidgetTester tester,
  MailSource source, {
  Size size = _desktop,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
      // Not the first run: the phone skips its welcome page.
      home: (_, _) => AddAccountScreen(
        source: source,
        onDone: (_) {},
        onCancel: size == _phone ? () {} : null,
      ),
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
  _layouts();

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

const _microsoft = OAuthProviderInfo(
  id: 'microsoft',
  name: 'Microsoft',
  builtIn: true,
  appPasswords: false,
  hasTenant: true,
);

/// The demo's Work account (id 2) signs in with Microsoft's page.
class _OAuthAccount extends DemoMailSource {
  _OAuthAccount({this.failWith}) : super(now: _now);

  /// Thrown by signing in again, when set.
  final AddAccountException? failWith;
  int signIns = 0;

  @override
  List<OAuthProviderInfo> get oauthProviders => const [_microsoft];

  @override
  String? accountOAuth(int accountId) => accountId == 2 ? 'microsoft' : null;

  @override
  Future<void> signInAgainOAuth(
    int accountId, {
    OAuthClientConfig? client,
  }) async {
    signIns++;
    if (failWith case final e?) throw e;
    status.value = SyncStatus.idle;
  }
}

/// Signing in again meets a certificate nobody vouches for, until it is
/// trusted.
class _SignInCert extends DemoMailSource {
  _SignInCert() : super(now: _now);

  final certs = <TrustedCertificate>[];

  @override
  Future<void> signInAgain(int accountId, String password) async {
    if (certs.isEmpty) {
      throw const AddAccountException(
        AddAccountError.certificate,
        '',
        _selfSigned,
      );
    }
    status.value = SyncStatus.idle;
  }

  @override
  Future<void> trustCertificate(int accountId, TrustedCertificate cert) async {
    certs.add(cert);
  }
}

/// Edit servers: the first save meets a certificate nobody vouches for.
class _ServersCert extends DemoMailSource {
  _ServersCert({this.thenFail = false}) : super(now: _now);

  /// After trusting it, the check still fails (the server is down).
  final bool thenFail;
  final saves = <List<TrustedCertificate>>[];
  int trustedDirectly = 0;

  @override
  Future<void> setAccountServers(
    int accountId,
    AccountServers servers, {
    List<TrustedCertificate> trusted = const [],
  }) async {
    saves.add(trusted);
    if (trusted.isEmpty) {
      throw const AddAccountException(
        AddAccountError.certificate,
        '',
        _selfSigned,
      );
    }
    if (thenFail) {
      throw const AddAccountException(AddAccountError.unreachable);
    }
    await super.setAccountServers(accountId, servers, trusted: trusted);
  }

  @override
  Future<void> trustCertificate(int accountId, TrustedCertificate cert) async {
    trustedDirectly++;
  }
}

/// Closes the account page, whose "checked 2 min ago" clock ticks.
Future<void> _closePage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// The Work account's details, on a phone or a desktop.
Future<void> _accountPage(
  WidgetTester tester,
  DemoMailSource source, {
  Size size = _desktop,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    PiumaApp(
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
  expect(find.byType(AccountPage), findsOneWidget);
}

void _layouts() {
  for (final (where, size) in [('phone', _phone), ('desktop', _desktop)]) {
    group(where, () {
      testWidgets('Outlook signs in on Microsoft’s page', (tester) async {
        final source = _Scripted(oauthProviders: const [_microsoft]);
        await _pump(tester, source, size: size);
        await tester.tap(find.text('Outlook'));
        await tester.pumpAndSettle();
        expect(find.text('Password'), findsNothing);
        await tester.enterText(_field('Email address'), 'anna@outlook.com');
        await tester.pump();
        await _tap(tester, 'Sign in with Microsoft', last: true);
        expect(source.oauthProvider, 'microsoft');
        expect(find.text('Account connected'), findsOneWidget);
      });

      testWidgets('Gmail offers Google’s page and the app password', (
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
              ownClient: false,
            ),
          ],
        );
        await _pump(tester, source, size: size);
        await tester.tap(find.text('Gmail'));
        await tester.pumpAndSettle();
        expect(find.text('Sign in with Google'), findsWidgets);
        expect(
          find.textContaining('the client it was built with'),
          findsOneWidget,
        );
        await _tap(tester, 'Use an app password instead');
        expect(find.text('Gmail needs an app password'), findsOneWidget);
      });

      for (final (error, says) in [
        (AddAccountError.signInCancelled, 'was closed before it finished'),
        (AddAccountError.signInDenied, 'didn’t allow the sign-in'),
      ]) {
        testWidgets('a failed sign-in on the provider’s page is said: $error', (
          tester,
        ) async {
          final source = _Scripted(
            fail: AddAccountException(error),
            oauthProviders: const [_microsoft],
          );
          await _pump(tester, source, size: size);
          await tester.tap(find.text('Outlook'));
          await tester.pumpAndSettle();
          await tester.enterText(_field('Email address'), 'anna@outlook.com');
          await tester.pump();
          await _tap(tester, 'Sign in with Microsoft', last: true);
          // The error comes in after its stagger.
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(source.adds, 1);
          expect(find.textContaining(says), findsOneWidget);
        });
      }

      testWidgets('a self-signed certificate is shown and trusted', (
        tester,
      ) async {
        final source = _Scripted(
          fail: const AddAccountException(
            AddAccountError.certificate,
            '',
            _selfSigned,
          ),
        );
        await _pump(tester, source, size: size);
        await _manual(tester, 'anna@example.org');
        await _tap(tester, 'Verify and connect');
        expect(find.text(_selfSigned.fingerprint), findsOneWidget);
        await _tap(tester, 'Trust this certificate');
        expect(source.gotTrusted.single.fingerprint, _selfSigned.fingerprint);
        expect(find.text('Account connected'), findsOneWidget);
      });

      testWidgets('a big provider’s certificate is refused for good', (
        tester,
      ) async {
        final source = _Scripted(
          fail: const AddAccountException(
            AddAccountError.certificate,
            '',
            CertificateProblem(
              host: 'outlook.office365.com',
              issue: CertificateIssue.provider,
              fingerprint: 'AB:CD',
              subject: 'CN=outlook.office365.com',
            ),
          ),
        );
        await _pump(tester, source, size: size);
        await _manual(tester, 'anna@example.org');
        await _tap(tester, 'Verify and connect');
        expect(
          find.textContaining('Someone may be in the way'),
          findsOneWidget,
        );
        expect(find.text('Trust this certificate'), findsNothing);
        expect(find.text('Trust the new certificate'), findsNothing);
      });

      testWidgets('an OAuth account signs in again on the provider’s page', (
        tester,
      ) async {
        final source = _OAuthAccount()
          ..status.value = const SyncStatus(
            SyncPhase.signInFailed,
            failed: [2],
          );
        await _accountPage(tester, source, size: size);
        await _tap(tester, 'Sign in again');
        expect(find.text('Password'), findsNothing);
        await _tap(tester, 'Sign in with Microsoft', last: true);
        expect(source.signIns, 1);
        expect(find.text('Sign in to Work'), findsNothing);
        await _closePage(tester);
      });

      testWidgets('a refused OAuth sign-in says so', (tester) async {
        final source = _OAuthAccount(
          failWith: const AddAccountException(AddAccountError.signInDenied),
        )..status.value = const SyncStatus(SyncPhase.signInFailed, failed: [2]);
        await _accountPage(tester, source, size: size);
        await _tap(tester, 'Sign in again');
        await _tap(tester, 'Sign in with Microsoft', last: true);
        expect(find.textContaining('didn’t allow the sign-in'), findsOneWidget);
        await _closePage(tester);
      });

      testWidgets('signing in again shows a refused certificate', (
        tester,
      ) async {
        final source = _SignInCert()
          ..status.value = const SyncStatus(
            SyncPhase.signInFailed,
            failed: [2],
          );
        await _accountPage(tester, source, size: size);
        await _tap(tester, 'Sign in again');
        await tester.enterText(_field('Password'), 'carta-120-opaca');
        await tester.pump();
        await _tap(tester, 'Sign in', last: true);
        expect(find.text(_selfSigned.fingerprint), findsOneWidget);
        await _tap(tester, 'Trust this certificate');
        expect(source.certs.single.host, 'mail.studio.it');
        await _closePage(tester);
      });

      testWidgets('an OAuth account has no Edit servers', (tester) async {
        await _accountPage(tester, _OAuthAccount(), size: size);
        expect(find.text('Edit servers'), findsNothing);
        await _closePage(tester);
      });

      testWidgets('a refused certificate is not called a password', (
        tester,
      ) async {
        final source = DemoMailSource(now: _now)
          ..certificateFailed.add(2)
          ..status.value = const SyncStatus(
            SyncPhase.signInFailed,
            failed: [2],
          );
        await _accountPage(tester, source, size: size);
        expect(
          find.text(
            'The server’s certificate was refused. Sign in again to look at it.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('The server refused the password. Did it change?'),
          findsNothing,
        );
        await _closePage(tester);
      });

      testWidgets('Edit servers keeps a trusted certificate only on success', (
        tester,
      ) async {
        final source = _ServersCert(thenFail: true);
        await _accountPage(tester, source, size: size);
        await _tap(tester, 'Edit servers');
        await tester.enterText(
          find.widgetWithText(TextField, 'imap.studio.it'),
          'mail.studio.it',
        );
        await _tap(tester, 'Save');
        expect(find.text(_selfSigned.fingerprint), findsOneWidget);
        await _tap(tester, 'Trust this certificate');
        // Given with the servers, for the engine to keep once they check
        // out; never trusted on its own beforehand.
        expect(source.saves.length, 2);
        expect(source.saves.last.single.host, 'mail.studio.it');
        expect(source.trustedDirectly, 0);
        expect(
          find.textContaining('The server could not be reached'),
          findsOneWidget,
        );
        expect(find.text('Save'), findsOneWidget, reason: 'still open');
        await _closePage(tester);
      });
    });
  }
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
