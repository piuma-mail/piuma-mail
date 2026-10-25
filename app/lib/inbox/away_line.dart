import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../settings/away_page.dart' show awayDay;

/// The quiet line at the top of the inbox while an away message answers
/// (`RemindAwayPrintToApprove`, section 2): the account's dot, "Away
/// message on for Work until Sun 2 Nov", and Turn off. One per account
/// at most, in the unified inbox and in that account's.
class AwayLineView extends StatelessWidget {
  const AwayLineView({
    super.key,
    required this.account,
    required this.end,
    required this.onTurnOff,
  });

  final MailAccount account;
  final DateTime? end;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final text = switch (end) {
      final e? => l.awayLineUntil(account.name, awayDay(e, locale)),
      null => l.awayLineOn(account.name),
    };
    final style = PiumaType.small.copyWith(color: c.accentText);
    return Semantics(
      container: true,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: account.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            PiumaPressable(
              onTap: onTurnOff,
              semanticLabel: '${l.awayTurnOff}, ${account.name}',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        l.awayTurnOff,
                        style: style.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
