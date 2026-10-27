import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'l10n/app_localizations.dart';
import 'link.dart';
import 'read_screen.dart';
import 'round.dart';
import 'summary.dart';

/// The inbox at a glance (`WatchWearOS` 2): newest first, each row with
/// its account's dot. Tapping one grows it into the email.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final link = LinkScope.of(context);
    final summary = link.summary;
    const c = watchColors;
    return Scaffold(
      backgroundColor: c.darkroom,
      body: summary == null
          ? _Waiting(asked: link.asked)
          : RoundScroll(
              children: [
                _Title(unread: summary.unread),
                if (summary.rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      l.nothingHere,
                      textAlign: TextAlign.center,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ),
                for (final row in summary.rows)
                  _Row(row: row, color: summary.account(row.account)?.color),
              ],
            ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const c = watchColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            l.inbox,
            style: PiumaType.subtitle.copyWith(fontSize: 16, color: c.fg),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Text(
              l.newCount(unread),
              style: PiumaType.label.copyWith(
                letterSpacing: 0,
                fontWeight: FontWeight.w600,
                color: c.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.color});

  final WatchRow row;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    const c = watchColors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = watchNow();
    final t = row.time;
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final when = today
        ? DateFormat('H:mm', locale).format(t)
        : DateFormat.MMMd(locale).format(t);
    final weight = row.seen ? FontWeight.w500 : FontWeight.w600;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            PiumaOrigin.from(context);
            Navigator.of(context).push(
              GrowRoute<void>(
                instant: reduceMotion(context),
                builder: (_) => ReadScreen(row: row, color: color),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (color != null) ...[
                      AccountDot(color!),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        row.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.small.copyWith(
                          fontSize: 14,
                          fontWeight: weight,
                          color: c.fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      when,
                      style: PiumaType.mono.copyWith(
                        fontSize: 11,
                        color: row.seen ? c.muted : c.accentText,
                      ),
                    ),
                  ],
                ),
                Text(
                  row.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Before the phone answered: what to do if it never does.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.asked});

  final bool asked;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const c = watchColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(PiumaIcon.phone, size: 22, color: c.muted),
            const SizedBox(height: 10),
            Text(
              asked ? l.openOnPhone : l.reaching,
              textAlign: TextAlign.center,
              style: PiumaType.small.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
