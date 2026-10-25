import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';

/// The band's one line: what is wrong, in plain words.
String senderWarningLine(AppLocalizations l, SenderWarning w) =>
    switch (w.kind) {
      SenderWarningKind.looksLike => l.senderLooksLike(w.domain, w.like ?? ''),
      SenderWarningKind.brand => l.senderBrand(w.brand ?? '', w.domain),
      SenderWarningKind.dmarcFailed => l.senderDmarcFailed(w.domain),
    };

/// A calm band under the sender when they aren't who they say
/// (`ProtectionToApprove` section 2): one line, Details and Report spam.
/// On the phone the two actions sit under the line.
class SenderWarningBand extends StatelessWidget {
  const SenderWarningBand({
    super.key,
    required this.warning,
    required this.phone,
    this.onReportSpam,
  });

  final SenderWarning warning;
  final bool phone;
  final VoidCallback? onReportSpam;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final line = Text(
      senderWarningLine(l, warning),
      style: TextStyle(
        fontFamily: PiumaFonts.sans,
        fontSize: phone ? 14 : 13.5,
        height: 1.5,
        color: c.fg,
      ),
    );
    final details = Builder(
      builder: (context) => _Action(
        label: l.senderDetails,
        phone: phone,
        onTap: () => _showDetails(context, warning, phone),
      ),
    );
    final spam = onReportSpam == null
        ? null
        : _Action(label: l.reportSpam, phone: phone, onTap: onReportSpam!);
    final sign = Padding(
      padding: EdgeInsets.only(top: phone ? 2 : 1),
      child: PiumaIconView(PiumaIcon.warning, size: 16, color: c.warn),
    );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.warnSoft,
          borderRadius: BorderRadius.circular(
            phone ? PiumaRadius.card : PiumaRadius.row,
          ),
          border: Border.all(color: c.warnLine),
        ),
        child: phone
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sign,
                      const SizedBox(width: 10),
                      Expanded(child: line),
                    ],
                  ),
                  const SizedBox(height: PiumaSpace.s8),
                  Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: Row(
                      children: [
                        details,
                        if (spam != null) ...[const SizedBox(width: 18), spam],
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sign,
                  const SizedBox(width: 10),
                  Expanded(child: line),
                  const SizedBox(width: 10),
                  details,
                  if (spam != null) ...[const SizedBox(width: 10), spam],
                ],
              ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.phone,
    required this.onTap,
  });

  final String label;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: phone ? 13.5 : 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: c.accentText,
            ),
          ),
        ),
      ),
    );
  }
}

/// What was checked: a small panel by Details on the desktop, a sheet on
/// the phone.
void _showDetails(BuildContext context, SenderWarning w, bool phone) {
  final l = AppLocalizations.of(context);
  Widget panel(BuildContext context) => _Details(warning: w, phone: phone);
  if (phone) {
    showPiumaSheet<void>(context, label: l.senderDetailsTitle, builder: panel);
    return;
  }
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  showPiumaPopover<void>(
    context,
    label: l.senderDetailsTitle,
    anchor: anchor,
    width: 320,
    end: true,
    grow: true,
    builder: panel,
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.warning, required this.phone});

  final SenderWarning warning;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final w = warning;
    final rows = <(String, String)>[
      (l.senderSentBy, w.sentBy ?? l.senderNotKnown),
      (l.senderSignature, w.signedBy ?? l.senderSignatureNone),
      if (w.dmarcFailed) (l.senderDomainCheck, l.senderDomainCheckFailed),
      if (w.like case final like?)
        (l.senderLooksLikeLabel, l.senderLooksLikeValue(like, w.likeCount)),
      if (w.brand case final brand?) (l.senderNameSays, brand),
    ];
    return Padding(
      padding: phone ? EdgeInsets.zero : const EdgeInsets.all(PiumaSpace.s8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.senderDetailsTitle,
            style: PiumaType.subtitle.copyWith(color: c.fg),
          ),
          const SizedBox(height: PiumaSpace.s12),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(top: PiumaSpace.s8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: PiumaType.small.copyWith(color: c.fg),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: PiumaSpace.s12),
          Text(
            l.senderDetailsNote,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
