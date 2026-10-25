import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';

/// "Piuma closed unexpectedly. Send a report?" under the inbox title, once,
/// after a crash (`FeedbackToApprove`). Nothing goes on its own: Report
/// opens the sheet, ✕ forgets it.
class CrashLine extends StatelessWidget {
  const CrashLine({super.key, required this.onReport, required this.onDismiss});

  final VoidCallback onReport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final style = PiumaType.body.copyWith(
      fontSize: 13,
      height: 1.35,
      color: c.accentText,
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.crashLine, style: style),
              ),
            ),
            PiumaPressable(
              onTap: onReport,
              semanticLabel: l.crashReport,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Text(
                  l.crashReport,
                  style: style.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            PiumaPressable(
              onTap: onDismiss,
              semanticLabel: l.crashDismiss,
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: PiumaIconView(
                    PiumaIcon.close,
                    size: 15,
                    color: c.accentText,
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
