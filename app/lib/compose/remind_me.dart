import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/snooze.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/date_time_picker.dart';
import '../widgets/dialog.dart';
import 'send_later.dart';

/// The times of "Remind me if nobody replies" (`RemindAwayPrintToApprove`).
enum RemindChoice { tomorrow, inThreeDays, nextWeek }

/// When [choice] is, seen from [now], always at 8:00: tomorrow, three days
/// on (as snooze's "If nobody replies"), and the Monday after tomorrow
/// (as Send later's).
DateTime remindTime(RemindChoice choice, DateTime now) => switch (choice) {
  RemindChoice.tomorrow => snoozeTime(SnoozeChoice.tomorrow, now),
  RemindChoice.inThreeDays => snoozeNoReplyTime(now),
  RemindChoice.nextWeek => sendLaterTimes(now)[2],
};

int _days(DateTime t, DateTime now) => DateTime(
  t.year,
  t.month,
  t.day,
).difference(DateTime(now.year, now.month, now.day)).inDays;

/// What the chip says: "Remind me", or once picked "Remind me in 3 days",
/// "Remind me tomorrow", "Remind me on Oct 30".
String remindChipLabel(
  DateTime? at,
  DateTime now,
  AppLocalizations l,
  String locale,
) {
  if (at == null) return l.remindMe;
  return switch (_days(at, now)) {
    <= 0 => l.remindChipToday(DateFormat('H:mm', locale).format(at)),
    1 => l.remindChipTomorrow,
    final days when days <= 7 => l.remindChipInDays(days),
    _ => l.remindChipOn(DateFormat.MMMd(locale).format(at)),
  };
}

/// Who sent mail waits on, by first name: "Luca" for "Luca Bianchi,
/// Sara Conti"; the address when that is all there is.
String waitsOn(String to) {
  final first = to.split(',').first.trim();
  if (first.contains('@')) return first;
  return first.split(RegExp(r'\s+')).first;
}

/// The line of a reminded row, in place of its preview: "No reply from
/// Luca · sent 3 days ago".
String noReplyLine(MailRow row, DateTime now, AppLocalizations l) =>
    '${l.remindNoReply(waitsOn(row.to))} · '
    '${remindSent(waitingDays(row.receivedAt, now), l)}';

/// "sent today", "sent yesterday", "sent 3 days ago".
String remindSent(int days, AppLocalizations l) => switch (days) {
  <= 0 => l.remindSentToday,
  1 => l.remindSentYesterday,
  _ => l.remindSentDaysAgo(days),
};

/// What the choices gave: a time, or none ("Don't remind me"). Null from
/// [showRemindMe] when nothing was picked.
typedef RemindPick = ({DateTime? at});

/// "Remind me": the choices under [anchor] on the desktop, the same as a
/// sheet on the phone. [current] is the time set, if any.
Future<RemindPick?> showRemindMe(
  BuildContext context, {
  required DateTime now,
  DateTime? current,
  Rect? anchor,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final picker = RemindPicker(now: now, current: current, phone: phone);
  if (phone) {
    return showPiumaSheet<RemindPick>(
      context,
      label: l.remindTitle,
      builder: (_) => picker,
    );
  }
  if (anchor == null) {
    return showPiumaDialog<RemindPick>(
      context,
      label: l.remindTitle,
      width: 380,
      builder: (_) => picker,
    );
  }
  return _remindPopover(context, now, current, anchor);
}

/// Asked by the small menu for "Pick a date…", and by the month for Back.
const Object _pickDate = Object();
const Object _back = Object();

/// The desktop's menu under [anchor]; "Pick a date…" opens the month in
/// a wider panel at the same place, whose Back comes back to the menu.
Future<RemindPick?> _remindPopover(
  BuildContext context,
  DateTime now,
  DateTime? current,
  Rect anchor,
) async {
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  while (true) {
    final picked = await showPiumaPopover<Object>(
      context,
      label: l.remindTitle,
      anchor: anchor,
      width: 236,
      builder: (_) => RemindPicker(now: now, current: current, dateApart: true),
    );
    if (!identical(picked, _pickDate) || !context.mounted) {
      return picked as RemindPick?;
    }
    final day = await showPiumaPopover<Object>(
      context,
      label: l.remindPickDate,
      anchor: anchor,
      width: 384,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(PiumaSpace.s8),
        child: PickDateTime(
          now: now,
          title: l.remindPickDate,
          button: (at) => l.remindAt(pickWhen(at, locale)),
          onBack: () => Navigator.of(context).pop(_back),
          onPick: (at) => Navigator.of(context).pop<Object>((at: at)),
        ),
      ),
    );
    if (!identical(day, _back) || !context.mounted) return day as RemindPick?;
  }
}

class RemindPicker extends StatefulWidget {
  const RemindPicker({
    super.key,
    required this.now,
    this.current,
    this.phone = false,
    this.dateApart = false,
  });

  final DateTime now;
  final DateTime? current;
  final bool phone;

  /// "Pick a date…" closes the list and asks for the month apart (the
  /// desktop's small menu has no room for it).
  final bool dateApart;

  @override
  State<RemindPicker> createState() => _RemindPickerState();
}

class _RemindPickerState extends State<RemindPicker> {
  /// Showing "Pick a date…" (`PickDateTime`) in place of the list.
  var _custom = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now;
    final phone = widget.phone;
    final pad = phone ? PiumaSpace.s20 : 0.0;
    void pick(DateTime? at) => Navigator.of(context).pop<Object>((at: at));
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
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phone) ...[handle, const SizedBox(height: 12)],
            PickDateTime(
              now: now,
              phone: phone,
              title: l.remindPickDate,
              button: (at) => l.remindAt(pickWhen(at, locale)),
              onBack: () => setState(() => _custom = false),
              onPick: pick,
            ),
          ],
        ),
      );
    }
    final hm = DateFormat('H:mm', locale);
    String when(DateTime t) =>
        '${DateFormat.E(locale).format(t)} ${hm.format(t)}';
    final rows = [
      for (final choice in RemindChoice.values)
        (
          label: switch (choice) {
            RemindChoice.tomorrow => l.remindTomorrow,
            RemindChoice.inThreeDays => l.remindInDays(3),
            RemindChoice.nextWeek => l.remindNextWeek,
          },
          at: remindTime(choice, now),
        ),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (phone) ...[
            handle,
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                l.remindTitle,
                style: PiumaType.title.copyWith(fontSize: 20, color: c.fg),
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final r in rows)
            _Choice(
              label: r.label,
              when: when(r.at),
              on: r.at == widget.current,
              phone: phone,
              onTap: () => pick(r.at),
            ),
          _Choice(
            label: l.remindPickDate,
            phone: phone,
            onTap: widget.dateApart
                ? () => Navigator.of(context).pop(_pickDate)
                : () => setState(() => _custom = true),
          ),
          _Choice(label: l.remindNever, phone: phone, onTap: () => pick(null)),
        ],
      ),
    );
  }
}

/// One choice: its words, and when in mono ("Thu 8:00"). The one set
/// sits on the chip color, as on the board.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.onTap,
    this.when,
    this.on = false,
    this.phone = false,
  });

  final String label;
  final String? when;
  final bool on;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final when = this.when;
    return Semantics(
      selected: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: when == null ? label : '$label, $when',
        child: ExcludeSemantics(
          child: Container(
            height: phone ? 52 : 34,
            padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 10),
            decoration: BoxDecoration(
              color: on ? c.chip : null,
              borderRadius: BorderRadius.circular(
                phone ? PiumaRadius.row : PiumaRadius.button,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: phone ? 16 : 13, color: c.fg),
                  ),
                ),
                if (when != null)
                  Text(
                    when,
                    style: PiumaType.mono.copyWith(
                      fontSize: phone ? 13 : 12,
                      color: c.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Remind me" chip, next to Send later and Write again: quiet with a
/// border until a time is set, then on the soft accent ("Remind me in 3
/// days"). [onTap] gets where the chip is, for the menu under it.
class RemindChip extends StatelessWidget {
  const RemindChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.height = 30,
    this.fontSize = 12.5,
  });

  final String label;
  final bool on;
  final ValueChanged<Rect> onTap;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final ink = on ? c.accentText : c.muted;
    return PiumaPressable(
      onTap: () {
        final box = context.findRenderObject()! as RenderBox;
        onTap(box.localToGlobal(Offset.zero) & box.size);
      },
      semanticLabel: label,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.theme,
          curve: PiumaMotion.curve,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? c.soft : c.surface.withValues(alpha: 0),
            border: Border.all(color: on ? c.soft : c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.hourglass, size: 13, color: ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: ink,
                  fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
