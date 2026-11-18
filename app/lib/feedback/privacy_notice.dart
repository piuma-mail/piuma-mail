import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';

/// "Reports and privacy": what a report carries, where it goes, who sees
/// it, how long it stays and how to have it erased, with who handles it as
/// this build names them (`ReportPrivacy`), and a link to the full notice.
/// Opened from the report sheet and from Settings › Help & feedback. A
/// dialog on the desktop, a sheet on the phone.
Future<void> showPrivacyNotice(BuildContext context, MailSource source) {
  final l = AppLocalizations.of(context);
  final phone = MediaQuery.sizeOf(context).width < 600;
  Widget panel(BuildContext context) => PrivacyNotice(
    privacy: source.reportPrivacy,
    byRelay: source.reportsByRelay,
  );
  return phone
      ? showPiumaSheet<void>(context, label: l.privacyTitle, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: l.privacyTitle,
          width: 480,
          builder: panel,
        );
}

class PrivacyNotice extends StatelessWidget {
  const PrivacyNotice({
    super.key,
    required this.privacy,
    required this.byRelay,
  });

  final ReportPrivacy privacy;

  /// Whether reports go through the relay; otherwise only by email.
  final bool byRelay;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final text = PiumaType.body.copyWith(color: c.fg);
    final paragraphs = [
      l.privacyWhat,
      if (byRelay && privacy.relayHost.isNotEmpty)
        l.privacyWhere(privacy.relayHost, privacy.filesDays)
      else
        l.privacyWhereEmail(privacy.contact),
      l.privacyWho(privacy.controller),
      l.privacyKeep,
      l.privacyErase(privacy.contact),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.soft,
                borderRadius: BorderRadius.circular(PiumaRadius.button),
              ),
              alignment: Alignment.center,
              child: PiumaIconView(
                PiumaIcon.lock,
                size: 18,
                color: c.accentText,
              ),
            ),
            const SizedBox(width: PiumaSpace.s12),
            Expanded(
              child: Text(
                l.privacyTitle,
                style: PiumaType.subtitle.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s16),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in paragraphs.indexed) ...[
                  if (i > 0) const SizedBox(height: PiumaSpace.s12),
                  Text(p, style: text),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s24),
        Row(
          children: [
            if (privacy.url.isNotEmpty)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PiumaPressable(
                    onTap: () => openExternalLink(Uri.parse(privacy.url)),
                    semanticLabel: l.privacyFull,
                    child: Text(
                      l.privacyFull,
                      style: PiumaType.small.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ),
              )
            else
              const Spacer(),
            PiumaButton(
              label: l.close,
              kind: PiumaButtonKind.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

/// What "Delete" on a report already sent should do.
enum DeleteSent { here, andErase }

/// "Delete this report?" for a report that opened an issue: deleting it on
/// the device leaves the issue with the maintainers, so the dialog says so
/// and offers to ask them to erase it too.
Future<DeleteSent?> askDeleteSent(BuildContext context, int issue) {
  final l = AppLocalizations.of(context);
  final phone = MediaQuery.sizeOf(context).width < 600;
  Widget panel(BuildContext context) => _DeleteSent(issue: issue, phone: phone);
  return phone
      ? showPiumaSheet<DeleteSent>(
          context,
          label: l.reportDeleteTitle,
          builder: panel,
        )
      : showPiumaDialog<DeleteSent>(
          context,
          label: l.reportDeleteTitle,
          builder: panel,
        );
}

class _DeleteSent extends StatelessWidget {
  const _DeleteSent({required this.issue, required this.phone});

  final int issue;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final here = PiumaButton(
      label: l.reportDeleteHere,
      kind: PiumaButtonKind.danger,
      onPressed: () => Navigator.of(context).pop(DeleteSent.here),
    );
    final erase = PiumaButton(
      label: l.reportDeleteAndErase,
      kind: PiumaButtonKind.secondary,
      onPressed: () => Navigator.of(context).pop(DeleteSent.andErase),
    );
    final cancel = PiumaButton(
      label: l.cancel,
      kind: PiumaButtonKind.tertiary,
      onPressed: () => Navigator.of(context).pop(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.reportDeleteTitle,
          style: PiumaType.subtitle.copyWith(color: c.fg),
        ),
        const SizedBox(height: PiumaSpace.s12),
        Text(
          l.reportDeleteSent(issue),
          style: PiumaType.body.copyWith(color: c.fg),
        ),
        const SizedBox(height: PiumaSpace.s24),
        if (phone) ...[
          here,
          const SizedBox(height: PiumaSpace.s8),
          erase,
          const SizedBox(height: PiumaSpace.s8),
          cancel,
        ] else
          Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [cancel, erase, here],
          ),
      ],
    );
  }
}
