import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// Storage, in an account's settings: how full its mailbox is when the
/// server says (IMAP QUOTA, JMAP Quota), with a bar, and a gentle word
/// when it is nearly full. Nothing when the server never said.
class QuotaCard extends StatefulWidget {
  const QuotaCard({super.key, required this.source, required this.accountId});

  final MailSource source;
  final int accountId;

  @override
  State<QuotaCard> createState() => _QuotaCardState();
}

class _QuotaCardState extends State<QuotaCard> {
  late MailQuota? _quota = widget.source.quota(widget.accountId);

  @override
  void initState() {
    super.initState();
    // What it said last at once, then asked again.
    widget.source
        .refreshQuota(widget.accountId)
        .then((q) {
          if (mounted && q != null) setState(() => _quota = q);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final quota = _quota;
    if (quota == null) return const SizedBox.shrink();
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final used = l.quotaUsed(
      fileSize(quota.used, locale: locale),
      fileSize(quota.limit, locale: locale),
    );
    final full = quota.nearlyFull;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        container: true,
        label: '${l.quotaLabel}: $used',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: full ? c.warnSoft : c.surface,
            border: Border.all(color: full ? c.warnLine : c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      l.quotaLabel,
                      style: PiumaType.body.copyWith(color: c.fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        used,
                        textAlign: TextAlign.end,
                        style: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  child: Container(
                    height: 6,
                    color: c.chip,
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: reduceMotion(context)
                          ? Duration.zero
                          : PiumaMotion.move,
                      curve: PiumaMotion.curve,
                      widthFactor: quota.share,
                      heightFactor: 1,
                      child: ColoredBox(color: full ? c.warn : c.accent),
                    ),
                  ),
                ),
                if (full) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.quotaNearlyFull,
                    style: PiumaType.small.copyWith(color: c.fg),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
