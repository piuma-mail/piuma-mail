import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// How long a row of Waiting has waited: "today", "yesterday", "5 days".
String waitingRowTime(DateTime sent, DateTime now, AppLocalizations l) =>
    switch (waitingDays(sent, now)) {
      <= 0 => l.waitingToday,
      1 => l.waitingYesterday,
      final days => l.waitingDays(days),
    };

/// The phone's quiet line under the tiles, as on `WaitingToApprove`:
/// "3 sent emails waiting for a reply ›". It opens Waiting.
class WaitingLine extends StatelessWidget {
  const WaitingLine({super.key, required this.count, required this.onTap});

  /// Sent emails that have waited [waitingLongDays] or more.
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final text = l.waitingLine(count);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              PiumaIconView(PiumaIcon.hourglass, size: 17, color: c.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.fg),
                ),
              ),
              PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "‹ Inbox" above the title of Waiting on the phone.
class WaitingBack extends StatelessWidget {
  const WaitingBack({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PiumaPressable(
          onTap: onBack,
          semanticLabel: l.inbox,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(
                    PiumaIcon.chevronLeft,
                    size: 22,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 2),
                  ExcludeSemantics(
                    child: Text(
                      l.inbox,
                      style: TextStyle(fontSize: 16, color: c.accentText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
