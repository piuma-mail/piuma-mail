import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/date_time_picker.dart';
import '../widgets/dialog.dart';

/// The times of `FeatureSchedule`, seen from [now]: tomorrow at 8:00 and
/// at 14:00, and the next Monday at 8:00.
List<DateTime> sendLaterTimes(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  // On a Sunday, tomorrow is Monday already: the one after, then.
  var toMonday = (DateTime.monday - today.weekday) % 7;
  if (toMonday <= 1) toMonday += 7;
  return [
    DateTime(today.year, today.month, today.day + 1, 8),
    DateTime(today.year, today.month, today.day + 1, 14),
    DateTime(today.year, today.month, today.day + toMonday, 8),
  ];
}

/// "Send later": the sheet of `FeatureSchedule` on the phone, the same in
/// a dialog on the desktop. [to] names who it goes to. Returns the time
/// picked, or null.
Future<DateTime?> showSendLater(
  BuildContext context, {
  required DateTime now,
  required String to,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final picker = SendLaterPicker(now: now, to: to, phone: phone);
  if (phone) {
    return showPiumaSheet<DateTime>(
      context,
      label: l.sendLater,
      builder: (_) => picker,
    );
  }
  return showPiumaDialog<DateTime>(
    context,
    label: l.sendLater,
    width: 420,
    builder: (_) => picker,
  );
}

class SendLaterPicker extends StatefulWidget {
  const SendLaterPicker({
    super.key,
    required this.now,
    required this.to,
    this.phone = false,
  });

  final DateTime now;
  final String to;
  final bool phone;

  @override
  State<SendLaterPicker> createState() => _SendLaterPickerState();
}

class _SendLaterPickerState extends State<SendLaterPicker> {
  late final _times = sendLaterTimes(widget.now);
  late DateTime _picked = _times.first;

  /// Showing "Pick date and time" (`PickDateTime`) in place of the list.
  var _custom = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final hm = DateFormat('H:mm', locale);
    String label(int i) => [
      l.sendLaterTomorrowMorning,
      l.sendLaterTomorrowAfternoon,
      l.sendLaterMondayMorning,
    ][i];
    final picked = _picked;
    final button = picked.difference(today).inDays == 1
        ? l.scheduleTomorrow(hm.format(picked))
        : l.scheduleOn(
            DateFormat.EEEE(locale).format(picked),
            hm.format(picked),
          );
    final pad = widget.phone ? PiumaSpace.s20 : 0.0;
    final handle = Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 14),
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
            if (widget.phone) handle,
            PickDateTime(
              now: widget.now,
              phone: widget.phone,
              title: l.pickDateTime,
              button: (at) => l.scheduleAt(pickWhen(at, locale)),
              onBack: () => setState(() => _custom = false),
              onPick: (at) => Navigator.of(context).pop(at),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.phone) handle,
          Semantics(
            header: true,
            child: Text(
              l.sendLater,
              style: PiumaType.title.copyWith(fontSize: 20, color: c.fg),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.outboxTo(widget.to),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: c.muted),
          ),
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            // On top, so the rows don't paint over its rounded corners.
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Column(
              children: [
                for (final (i, t) in _times.indexed)
                  Semantics(
                    selected: t == picked,
                    child: PiumaPressable(
                      onTap: () => setState(() => _picked = t),
                      semanticLabel: label(i),
                      child: ExcludeSemantics(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: t == picked ? c.soft : c.surface,
                            border: Border(bottom: BorderSide(color: c.line)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label(i),
                                      style: PiumaType.body.copyWith(
                                        color: c.fg,
                                        fontWeight: t == picked
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${DateFormat.MMMMEEEEd(locale).format(t)}, ${hm.format(t)}',
                                      style: PiumaType.small.copyWith(
                                        color: c.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (t == picked)
                                PiumaIconView(
                                  PiumaIcon.check,
                                  size: 18,
                                  color: c.accentText,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                PiumaPressable(
                  onTap: () => setState(() => _custom = true),
                  semanticLabel: l.pickDateTime,
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      color: c.surface,
                      child: Row(
                        children: [
                          PiumaIconView(
                            PiumaIcon.calendar,
                            size: 18,
                            color: c.fg,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l.pickDateTime,
                              style: PiumaType.body.copyWith(
                                color: c.fg,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          PiumaIconView(
                            PiumaIcon.chevronRight,
                            size: 16,
                            color: c.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.row),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: PiumaIconView(PiumaIcon.phone, color: c.muted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.sendLaterNote,
                    style: PiumaType.small.copyWith(color: c.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PiumaPressable(
            onTap: () => Navigator.of(context).pop(picked),
            semanticLabel: button,
            child: ExcludeSemantics(
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(PiumaRadius.card),
                ),
                child: Text(
                  button,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.onAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
