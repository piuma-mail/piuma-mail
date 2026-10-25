import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/date_time_picker.dart';
import '../widgets/dialog.dart';

/// The times of `FeatureSnooze`.
enum SnoozeChoice { evening, tomorrow, weekend, nextWeek }

/// When [choice] is, seen from [now]: this evening at 18:00, tomorrow at
/// 8:00, Saturday at 9:00 and Monday at 8:00, always ahead.
DateTime snoozeTime(SnoozeChoice choice, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime next(int weekday, int hour) {
    var days = (weekday - today.weekday) % 7;
    if (days == 0) days = 7;
    return DateTime(today.year, today.month, today.day + days, hour);
  }

  return switch (choice) {
    SnoozeChoice.evening => DateTime(today.year, today.month, today.day, 18),
    SnoozeChoice.tomorrow => DateTime(
      today.year,
      today.month,
      today.day + 1,
      8,
    ),
    SnoozeChoice.weekend => next(DateTime.saturday, 9),
    SnoozeChoice.nextWeek => next(DateTime.monday, 8),
  };
}

/// What "Snooze until…" gave: when, and whether a reply in the thread
/// brings the mail back sooner ("If nobody replies").
typedef SnoozePick = ({DateTime at, bool unlessReply});

/// "If nobody replies": three days from [now], at 8:00.
DateTime snoozeNoReplyTime(DateTime now) =>
    DateTime(now.year, now.month, now.day + 3, 8);

/// The choices that make sense at [now]: "This evening" goes once it is
/// less than an hour away.
List<SnoozeChoice> snoozeChoices(DateTime now) => [
  for (final c in SnoozeChoice.values)
    if (c != SnoozeChoice.evening || now.hour < 17) c,
];

/// "tomorrow, 08:00", "today, 18:00", "Sat, 09:00", "Oct 30, 08:00": for
/// "Snoozed until …".
String snoozeWhen(
  DateTime until,
  DateTime now,
  AppLocalizations l,
  String locale,
) {
  final time = DateFormat.Hm(locale).format(until);
  return switch (_days(until, now)) {
    0 => l.snoozeToday(time),
    1 => l.snoozeTomorrow(time),
    < 7 && > 0 => '${DateFormat.E(locale).format(until)}, $time',
    _ => '${DateFormat.MMMd(locale).format(until)}, $time',
  };
}

/// When a snoozed row comes back, as `States` lists it: "18:00",
/// "tomorrow 9:00", "Mon", "Oct 30".
String snoozedRowTime(
  DateTime? until,
  DateTime now,
  AppLocalizations l,
  String locale,
) {
  if (until == null) return '';
  final time = DateFormat('H:mm', locale).format(until);
  return switch (_days(until, now)) {
    <= 0 => time,
    1 => l.snoozeTomorrowShort(time),
    < 7 => DateFormat.E(locale).format(until),
    _ => DateFormat.MMMd(locale).format(until),
  };
}

int _days(DateTime t, DateTime now) => DateTime(
  t.year,
  t.month,
  t.day,
).difference(DateTime(now.year, now.month, now.day)).inDays;

/// "Snooze until…": the sheet of `FeatureSnooze` on the phone, the same
/// tiles in a popover under [anchor] on the desktop (`DesktopSnooze`).
/// Returns what was picked, or null.
Future<SnoozePick?> showSnooze(
  BuildContext context, {
  required DateTime now,
  Rect? anchor,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final picker = SnoozePicker(now: now, phone: phone);
  if (phone) {
    return showPiumaSheet<SnoozePick>(
      context,
      label: l.snoozeUntilTitle,
      builder: (_) => picker,
    );
  }
  if (anchor == null) {
    return showPiumaDialog<SnoozePick>(
      context,
      label: l.snoozeUntilTitle,
      width: 380,
      builder: (_) => picker,
    );
  }
  return showPiumaPopover<SnoozePick>(
    context,
    label: l.snoozeUntilTitle,
    anchor: anchor,
    width: 384,
    builder: (_) => picker,
  );
}

class SnoozePicker extends StatefulWidget {
  const SnoozePicker({super.key, required this.now, this.phone = false});

  final DateTime now;
  final bool phone;

  @override
  State<SnoozePicker> createState() => _SnoozePickerState();
}

class _SnoozePickerState extends State<SnoozePicker> {
  /// Showing "Pick date & time" (`PickDateTime`) in place of the tiles.
  var _custom = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now;
    final phone = widget.phone;
    final pad = phone ? PiumaSpace.s20 : PiumaSpace.s8;
    final handle = Center(
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: c.line,
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
      ),
    );
    if (_custom) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone) handle,
          Padding(
            padding: EdgeInsets.fromLTRB(pad, phone ? 12 : 0, pad, 0),
            child: PickDateTime(
              now: now,
              phone: phone,
              title: l.pickDateTime,
              button: (at) => l.snoozeUntilAt(pickWhen(at, locale)),
              onBack: () => setState(() => _custom = false),
              onPick: (at) =>
                  Navigator.of(context)
                      .pop<SnoozePick>((at: at, unlessReply: false)),
            ),
          ),
        ],
      );
    }
    final choices = snoozeChoices(now);
    final tiles = [
      for (final choice in choices)
        _Tile(
          choice: choice,
          at: snoozeTime(choice, now),
          now: now,
          locale: locale,
          // Tomorrow morning is what a swipe does: the usual pick.
          strong: choice == SnoozeChoice.tomorrow,
        ),
    ];
    final pick = _Row(
      icon: PiumaIcon.clock,
      title: l.pickDateTime,
      chevron: true,
      onTap: () => setState(() => _custom = true),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone) handle,
        Padding(
          padding: EdgeInsets.fromLTRB(pad, phone ? 16 : 6, pad, 16),
          child: Semantics(
            header: true,
            child: Text(
              l.snoozeUntilTitle,
              style: (phone ? PiumaType.title : PiumaType.subtitle).copyWith(
                fontSize: phone ? 20 : null,
                color: c.fg,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: tiles[i]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: i + 1 < tiles.length
                            ? tiles[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // The list under the tiles of `FeatureSnooze`: "If nobody replies"
        // on the phone, and "Pick date & time" everywhere.
        Padding(
          padding: EdgeInsets.fromLTRB(
            pad,
            phone ? 16 : 10,
            pad,
            phone ? 0 : 6,
          ),
          child: _Group(
            rows: [
              if (phone) _NoReplyRow(at: snoozeNoReplyTime(now)),
              pick,
            ],
          ),
        ),
      ],
    );
  }
}

/// Rows in one bordered box, a line between them.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Container(height: 1, color: c.line),
            row,
          ],
        ],
      ),
    );
  }
}

/// A row of the list under the tiles: an icon, a title, maybe a line
/// under it and a chevron.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.hint,
    this.chevron = false,
  });

  final PiumaIcon icon;
  final String title;
  final String? hint;
  final bool chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final hint = this.hint;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: hint == null ? title : '$title, $hint',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              PiumaIconView(icon, size: 20, color: c.fg),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint,
                        style: PiumaType.small.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              if (chevron)
                PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoReplyRow extends StatelessWidget {
  const _NoReplyRow({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Row(
      icon: PiumaIcon.reply,
      title: l.snoozeNoReply,
      hint: l.snoozeNoReplyHint,
      onTap: () =>
          Navigator.of(context).pop<SnoozePick>((at: at, unlessReply: true)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.choice,
    required this.at,
    required this.now,
    required this.locale,
    this.strong = false,
  });

  final SnoozeChoice choice;
  final DateTime at;
  final DateTime now;
  final String locale;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final (icon, label) = switch (choice) {
      SnoozeChoice.evening => (PiumaIcon.moon, l.snoozeEvening),
      SnoozeChoice.tomorrow => (PiumaIcon.sun, l.snoozeMorning),
      SnoozeChoice.weekend => (PiumaIcon.sunrise, l.snoozeWeekend),
      SnoozeChoice.nextWeek => (PiumaIcon.calendar, l.snoozeNextWeek),
    };
    final time = DateFormat('H:mm', locale).format(at);
    final when = choice == SnoozeChoice.evening
        ? l.snoozeTileToday(time)
        : '${DateFormat.E(locale).format(at)} $time';
    return PiumaPressable(
      onTap: () =>
          Navigator.of(context).pop<SnoozePick>((at: at, unlessReply: false)),
      semanticLabel: '$label, $when',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: strong ? c.soft : c.surface,
            border: Border.all(color: strong ? c.soft : c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PiumaIconView(icon, size: 20, color: c.accentText),
              const SizedBox(height: 6),
              Text(
                label,
                style: PiumaType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(when, style: PiumaType.small.copyWith(color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
