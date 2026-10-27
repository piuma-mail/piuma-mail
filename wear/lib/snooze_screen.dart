import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'done_screen.dart';
import 'l10n/app_localizations.dart';
import 'link.dart';
import 'round.dart';
import 'summary.dart';

/// Snooze until… (`WatchWearOS` 5): the phone's choices.
class SnoozeScreen extends StatelessWidget {
  const SnoozeScreen({super.key, required this.row});

  final WatchRow row;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final link = LinkScope.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = watchNow();
    const c = watchColors;
    return Scaffold(
      backgroundColor: c.darkroom,
      body: RoundScroll(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PiumaIconView(PiumaIcon.clock, size: 15, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  l.snoozeUntil,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                  ),
                ),
              ],
            ),
          ),
          for (final choice in snoozeChoices(now))
            Builder(
              builder: (context) {
                final at = snoozeTime(choice, now);
                final when =
                    choice == SnoozeChoice.evening ||
                        choice == SnoozeChoice.tomorrow
                    ? DateFormat('H:mm', locale).format(at)
                    : DateFormat.E(locale).format(at);
                return Pill(
                  label: switch (choice) {
                    SnoozeChoice.evening => l.snoozeEvening,
                    SnoozeChoice.tomorrow => l.snoozeMorning,
                    SnoozeChoice.weekend => l.snoozeWeekend,
                    SnoozeChoice.nextWeek => l.snoozeNextWeek,
                  },
                  trailing: when,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    GrowRoute<void>(
                      instant: reduceMotion(context),
                      builder: (context) => DoneScreen(
                        title: AppLocalizations.of(context).snoozed,
                        detail: row.subject,
                        then: () => link.snooze(row.payload, at),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
