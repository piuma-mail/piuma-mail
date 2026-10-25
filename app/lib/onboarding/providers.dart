import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/links.dart';

/// The providers "Or start from" sets up without a lookup: their servers,
/// and the page of the provider's account where the password is made.
enum MailProvider {
  gmail(
    'Gmail',
    imap: MailServer('imap.gmail.com', 993, ServerSecurity.tls),
    smtp: MailServer('smtp.gmail.com', 465, ServerSecurity.tls),
    page: 'https://myaccount.google.com/apppasswords',
  ),
  icloud(
    'iCloud',
    imap: MailServer('imap.mail.me.com', 993, ServerSecurity.tls),
    smtp: MailServer('smtp.mail.me.com', 587, ServerSecurity.startTls),
    page: 'https://account.apple.com/account/manage',
  ),

  /// JMAP, with an API token: Fastmail's JMAP takes no passwords.
  fastmail(
    'Fastmail',
    jmapUrl: 'https://api.fastmail.com/jmap/session',
    page: 'https://app.fastmail.com/settings/security/tokens',
  ),

  // Certified mail (PEC): the mailbox password, nothing to make.
  aruba(
    'Aruba PEC',
    imap: MailServer('imaps.pec.aruba.it', 993, ServerSecurity.tls),
    smtp: MailServer('smtps.pec.aruba.it', 465, ServerSecurity.tls),
  ),
  legalmail(
    'Legalmail',
    imap: MailServer('mbox.cert.legalmail.it', 993, ServerSecurity.tls),
    smtp: MailServer('sendm.cert.legalmail.it', 465, ServerSecurity.tls),
  ),
  poste(
    'Poste PEC',
    imap: MailServer('mail.postecert.it', 993, ServerSecurity.tls),
    smtp: MailServer('mail.postecert.it', 465, ServerSecurity.tls),
  ),
  register(
    'Register PEC',
    imap: MailServer('mx.pec-email.com', 993, ServerSecurity.tls),
    smtp: MailServer('mx.pec-email.com', 465, ServerSecurity.tls),
  );

  const MailProvider(
    this.label, {
    this.imap,
    this.smtp,
    this.jmapUrl,
    this.page,
  });
  final String label;
  final MailServer? imap;
  final MailServer? smtp;
  final String? jmapUrl;

  /// Where the app password or token is made; none for PEC.
  final String? page;

  static const pec = [aruba, legalmail, poste, register];

  bool get isPec => pec.contains(this);

  /// The PEC picker's short names.
  String get shortLabel => switch (this) {
    aruba => 'Aruba',
    poste => 'Poste',
    register => 'Register',
    _ => label,
  };

  /// An app password or a token never has spaces: Google shows its 16
  /// letters in groups of four.
  String password(String typed) =>
      isPec ? typed : typed.replaceAll(RegExp(r'\s'), '');

  String title(AppLocalizations l) => switch (this) {
    fastmail => l.fastmailNeedsToken,
    gmail || icloud => l.needsAppPassword(label),
    _ => l.signInToPec(label),
  };

  List<String> steps(AppLocalizations l) => switch (this) {
    gmail => [l.gmailStep1, l.gmailStep2, l.gmailStep3],
    icloud => [l.icloudStep1, l.icloudStep2, l.icloudStep3],
    fastmail => [l.fastmailStep1, l.fastmailStep2, l.fastmailStep3],
    _ => [l.pecStep1, l.pecStep2],
  };

  String? pageLabel(AppLocalizations l) => switch (this) {
    gmail => l.openAppPasswords,
    icloud => l.openAppleAccount,
    fastmail => l.openApiTokens,
    _ => null,
  };

  String passwordLabel(AppLocalizations l) => switch (this) {
    fastmail => l.apiToken,
    gmail || icloud => l.appPassword,
    _ => l.password,
  };

  /// What Google's app passwords look like, as the field's hint.
  String? get example => this == gmail ? 'abcd efgh ijkl mnop' : null;
}

/// A grid of choices under "Or start from" and for the PEC provider: one
/// row of four on the desktop, two by two on the phone.
class ProviderGrid extends StatelessWidget {
  const ProviderGrid({
    super.key,
    required this.labels,
    required this.onPick,
    this.phone = false,
  });

  final List<String> labels;
  final ValueChanged<int> onPick;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final perRow = phone ? 2 : 4;
    final rows = <Widget>[];
    for (var i = 0; i < labels.length; i += perRow) {
      rows.add(
        Row(
          children: [
            for (var j = i; j < i + perRow; j++) ...[
              if (j > i) const SizedBox(width: PiumaSpace.s8),
              Expanded(
                child: j < labels.length
                    ? _Tile(
                        label: labels[j],
                        height: phone ? 48 : 40,
                        onTap: () => onPick(j),
                      )
                    : const SizedBox(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: PiumaSpace.s8),
          rows[i],
        ],
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.label, required this.height, required this.onTap});
  final String label;
  final double height;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PiumaPressable(
        onTap: widget.onTap,
        semanticLabel: widget.label,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: widget.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? c.chip : c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.button),
          ),
          child: ExcludeSemantics(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The numbered steps to make an app password, and the button that opens
/// the provider's page for it.
class ProviderSteps extends StatelessWidget {
  const ProviderSteps({super.key, required this.provider});
  final MailProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final steps = provider.steps(l);
    final page = provider.page;
    final pageLabel = provider.pageLabel(l);
    final style = TextStyle(fontSize: 15, height: 1.45, color: c.fg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: PiumaSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: style.copyWith(color: c.muted),
                  ),
                ),
                Expanded(child: Text(steps[i], style: style)),
              ],
            ),
          ),
        if (page != null && pageLabel != null) ...[
          const SizedBox(height: 10),
          _PageButton(
            label: pageLabel,
            onTap: () => openExternalLink(Uri.parse(page)),
          ),
        ],
      ],
    );
  }
}

/// "Open App passwords ↗": a secondary button with the arrow out.
class _PageButton extends StatefulWidget {
  const _PageButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_PageButton> createState() => _PageButtonState();
}

class _PageButtonState extends State<_PageButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PiumaPressable(
        onTap: widget.onTap,
        semanticLabel: widget.label,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? c.chip : c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.button),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                const SizedBox(width: PiumaSpace.s8),
                PiumaIconView(PiumaIcon.external, size: 14, color: c.fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
