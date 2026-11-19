import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';

/// What went wrong signing in, in words: the same everywhere an account is
/// added or signs in again.
String accountErrorText(AppLocalizations l, AddAccountError error) =>
    switch (error) {
      AddAccountError.wrongPassword => l.errorWrongPassword,
      AddAccountError.unreachable => l.errorUnreachable,
      AddAccountError.insecure => l.errorInsecure,
      AddAccountError.keychain => l.errorKeychain,
      AddAccountError.noKeyring => l.errorNoKeyring,
      AddAccountError.certificate => l.errorCertificate,
      AddAccountError.signInUnavailable => l.errorSignInUnavailable,
      AddAccountError.signInCancelled => l.errorSignInCancelled,
      AddAccountError.signInDenied => l.errorSignInDenied,
      AddAccountError.oauthServers => l.errorOAuthServers,
      AddAccountError.other => l.errorOther,
    };

/// Whether a port typed by hand is one: 1 to 65535, spaces aside.
int? validPort(String text) {
  final port = int.tryParse(text.trim());
  return port != null && port >= 1 && port <= 65535 ? port : null;
}

/// A server certificate that was refused: why, what it says, and, when it
/// can be, a button to trust exactly this certificate for this account.
/// Looks like the warning bands elsewhere in the app.
class CertificateCard extends StatelessWidget {
  const CertificateCard({super.key, required this.problem, this.onTrust});

  final CertificateProblem problem;

  /// Trusts it and tries again; none while busy.
  final VoidCallback? onTrust;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final p = problem;
    final why = switch (p.issue) {
      CertificateIssue.untrusted => l.certUntrusted,
      CertificateIssue.expired => l.certExpired,
      CertificateIssue.nameMismatch => l.certNameMismatch,
      CertificateIssue.changed => l.certChanged,
      CertificateIssue.invalid => l.certInvalid,
      CertificateIssue.provider => l.certProvider,
    };
    final label = TextStyle(fontSize: 12, color: c.muted);
    final value = TextStyle(fontSize: 13, height: 1.35, color: c.fg);
    Widget row(String name, String text, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(top: PiumaSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: label),
          const SizedBox(height: 2),
          SelectableText(
            text,
            style: mono
                ? value.copyWith(fontFamily: PiumaFonts.mono, fontSize: 12)
                : value,
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: '${l.errorCertificate} ${p.host}',
      child: Container(
        padding: const EdgeInsets.all(PiumaSpace.s16),
        decoration: BoxDecoration(
          color: c.warnSoft,
          border: Border.all(color: c.warnLine),
          borderRadius: BorderRadius.circular(PiumaRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: PiumaIconView(PiumaIcon.lock, size: 15, color: c.warn),
                ),
                const SizedBox(width: PiumaSpace.s8),
                Expanded(
                  child: Text(
                    p.host,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(why, style: TextStyle(fontSize: 13, height: 1.4, color: c.fg)),
            if (p.subject.isNotEmpty) row(l.certIssuedTo, p.subject),
            if (p.issuer.isNotEmpty && p.issuer != p.subject)
              row(l.certIssuedBy, p.issuer),
            if (p.notAfter.isNotEmpty) row(l.certValidUntil, p.notAfter),
            row(l.certFingerprint, p.fingerprint, mono: true),
            if (p.canTrust) ...[
              const SizedBox(height: PiumaSpace.s12),
              Text(
                l.certTrustHint,
                style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
              ),
              const SizedBox(height: PiumaSpace.s12),
              Wrap(
                spacing: PiumaSpace.s8,
                runSpacing: PiumaSpace.s8,
                children: [
                  PiumaButton(
                    label: p.issue == CertificateIssue.changed
                        ? l.certTrustNew
                        : l.certTrust,
                    kind: PiumaButtonKind.secondary,
                    size: PiumaButtonSize.standard,
                    onPressed: onTrust,
                  ),
                  PiumaButton(
                    label: l.certCopyFingerprint,
                    kind: PiumaButtonKind.tertiary,
                    size: PiumaButtonSize.standard,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: p.fingerprint)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The error under a sign-in form: the words, and the certificate when
/// that was the trouble.
class AccountErrorView extends StatelessWidget {
  const AccountErrorView({
    super.key,
    required this.error,
    this.certificate,
    this.onTrust,
  });

  final AddAccountError error;
  final CertificateProblem? certificate;
  final VoidCallback? onTrust;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final cert = certificate;
    return PiumaEnter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Said as soon as it appears, wherever the focus is.
          Semantics(
            liveRegion: true,
            child: Text(
              accountErrorText(l, error),
              style: TextStyle(fontSize: 14, color: c.danger),
            ),
          ),
          if (error == AddAccountError.certificate && cert != null) ...[
            const SizedBox(height: PiumaSpace.s12),
            CertificateCard(problem: cert, onTrust: onTrust),
          ],
        ],
      ),
    );
  }
}
