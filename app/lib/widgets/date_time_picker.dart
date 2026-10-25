import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';

/// The quick times under the month of `PickDateTime`.
const pickTimes = [(8, 0), (9, 0), (18, 0)];

/// The day [PickDateTime] starts on, seen from [now]: today while 9:00,
/// the time it starts with, is still ahead, else tomorrow.
DateTime pickFirstDay(DateTime now) =>
    DateTime(now.year, now.month, now.day + (now.hour < 9 ? 0 : 1));

/// "9:00", "09:30", "930" or "9" as hours and minutes, or null.
(int, int)? parseTime(String text) {
  final t = text.trim().replaceAll('.', ':');
  final m =
      RegExp(r'^(\d{1,2}):?(\d{2})?$').firstMatch(t) ??
      RegExp(r'^(\d{1,2})(\d{2})$').firstMatch(t);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  if (h > 23 || min > 59) return null;
  return (h, min);
}

/// "Pick date & time" (`PickDateTime`): a month to pick a day, quick times
/// and a field for any other, and a button that says what will happen at
/// the time picked. Days before today can't be picked, nor a time already
/// gone. [onBack] goes back to the quick choices; [onPick] takes the time.
class PickDateTime extends StatefulWidget {
  const PickDateTime({
    super.key,
    required this.now,
    required this.title,
    required this.button,
    required this.onBack,
    required this.onPick,
    this.phone = false,
  });

  final DateTime now;
  final String title;

  /// The button's words for a time: "Snooze until Fri, Oct 23, 9:00".
  final String Function(DateTime at) button;
  final VoidCallback onBack;
  final ValueChanged<DateTime> onPick;
  final bool phone;

  @override
  State<PickDateTime> createState() => _PickDateTimeState();
}

class _PickDateTimeState extends State<PickDateTime> {
  late DateTime _day = pickFirstDay(widget.now);
  late DateTime _month = DateTime(_day.year, _day.month);
  var _time = (9, 0);
  final _field = TextEditingController(text: '09:00');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  DateTime get _at =>
      DateTime(_day.year, _day.month, _day.day, _time.$1, _time.$2);

  void _setTime((int, int) t) => setState(() {
    _time = t;
    _field.text =
        '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';
  });

  void _typed(String text) {
    final t = parseTime(text);
    if (t != null) _setTime(t);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final at = _at;
    final ahead = at.isAfter(widget.now);
    final first = DateTime(_today.year, _today.month);
    final last = DateTime(_today.year + 1, _today.month);
    final label = widget.button(at);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Transform.translate(
              offset: const Offset(-10, 0),
              child: _Round(
                icon: PiumaIcon.chevronLeft,
                label: l.back,
                onTap: widget.onBack,
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: (widget.phone ? PiumaType.title : PiumaType.subtitle)
                      .copyWith(
                        fontSize: widget.phone ? 20 : null,
                        color: c.fg,
                      ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(_month),
                style: PiumaType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
            _Round(
              icon: PiumaIcon.chevronLeft,
              label: l.previousMonth,
              size: 36,
              onTap: _month.isAfter(first)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
            ),
            _Round(
              icon: PiumaIcon.chevronRight,
              label: l.nextMonth,
              size: 36,
              onTap: _month.isBefore(last)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Month(
          month: _month,
          today: _today,
          picked: _day,
          locale: locale,
          onPick: (d) => setState(() => _day = d),
        ),
        const SizedBox(height: 16),
        Text(
          l.pickTime,
          style: PiumaType.small.copyWith(
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final t in pickTimes) ...[
              _TimeChip(
                text: '${t.$1}:${t.$2.toString().padLeft(2, '0')}',
                on: t == _time,
                onTap: () => _setTime(t),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            _TimeField(
              controller: _field,
              label: l.pickOtherTime,
              onChanged: _typed,
            ),
          ],
        ),
        const SizedBox(height: 16),
        PiumaPressable(
          onTap: ahead ? () => widget.onPick(at) : null,
          semanticLabel: label,
          child: ExcludeSemantics(
            child: Container(
              height: 50,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: ahead ? c.accent : c.chip,
                borderRadius: BorderRadius.circular(PiumaRadius.card),
              ),
              child: Text(
                ahead ? label : l.pickTimeGone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ahead ? c.onAccent : c.muted,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A month to pick one day, as the away message's From and To ask
/// (`RemindAwayPrintToApprove`): days before [first] can't be picked. A
/// tap picks at once. With [clearLabel], a line under the month picks no
/// day ([onClear]).
class PickDay extends StatefulWidget {
  const PickDay({
    super.key,
    required this.today,
    required this.title,
    required this.onPick,
    this.initial,
    this.first,
    this.clearLabel,
    this.onClear,
    this.phone = false,
  });

  final DateTime today;
  final String title;
  final ValueChanged<DateTime> onPick;
  final DateTime? initial;

  /// The first day that can be picked; today unless given.
  final DateTime? first;
  final String? clearLabel;
  final VoidCallback? onClear;
  final bool phone;

  @override
  State<PickDay> createState() => _PickDayState();
}

class _PickDayState extends State<PickDay> {
  DateTime get _today =>
      DateTime(widget.today.year, widget.today.month, widget.today.day);
  DateTime get _first => widget.first ?? _today;
  late DateTime _month = () {
    final d = widget.initial ?? _first;
    return DateTime(d.year, d.month);
  }();

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final first = DateTime(_first.year, _first.month);
    final last = DateTime(_today.year + 1, _today.month);
    final clear = widget.clearLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.title,
            style: (widget.phone ? PiumaType.title : PiumaType.subtitle)
                .copyWith(fontSize: widget.phone ? 20 : null, color: c.fg),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat.yMMMM(locale).format(_month),
                style: PiumaType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
            _Round(
              icon: PiumaIcon.chevronLeft,
              label: l.previousMonth,
              size: 36,
              onTap: _month.isAfter(first)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    )
                  : null,
            ),
            _Round(
              icon: PiumaIcon.chevronRight,
              label: l.nextMonth,
              size: 36,
              onTap: _month.isBefore(last)
                  ? () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Month(
          month: _month,
          today: _today,
          first: _first,
          picked: widget.initial,
          locale: locale,
          onPick: widget.onPick,
        ),
        if (clear != null) ...[
          const SizedBox(height: 8),
          PiumaPressable(
            onTap: widget.onClear,
            semanticLabel: clear,
            child: ExcludeSemantics(
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(PiumaRadius.button),
                ),
                child: Text(clear, style: PiumaType.body.copyWith(color: c.fg)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.today,
    required this.picked,
    required this.locale,
    required this.onPick,
    this.first,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? picked;
  final String locale;
  final ValueChanged<DateTime> onPick;

  /// Days before it can't be picked; today unless given.
  final DateTime? first;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    // Weeks start on Monday, as on the board.
    final lead = DateTime(month.year, month.month).weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final letters = [
      for (var i = 0; i < 7; i++)
        DateFormat.EEEEE(locale).format(DateTime(2026, 10, 19 + i)),
    ];
    return Column(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (final w in letters)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: PiumaType.small.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < cells.length; r += 7)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (final d in cells.sublist(r, r + 7))
                  Expanded(
                    child: d == null
                        ? const SizedBox(height: 40)
                        : _Day(
                            day: d,
                            past: d.isBefore(first ?? today),
                            today: d == today,
                            picked: d == picked,
                            locale: locale,
                            onTap: () => onPick(d),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.past,
    required this.today,
    required this.picked,
    required this.locale,
    required this.onTap,
  });

  final DateTime day;
  final bool past;
  final bool today;
  final bool picked;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final color = picked
        ? c.onAccent
        : past
        ? c.placeholder
        : today
        ? c.accentText
        : c.fg;
    return Semantics(
      selected: picked,
      enabled: !past,
      child: PiumaPressable(
        onTap: past ? null : onTap,
        semanticLabel: DateFormat.MMMMEEEEd(locale).format(day),
        child: ExcludeSemantics(
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: picked ? c.accent : null,
                shape: BoxShape.circle,
                border: today && !picked ? Border.all(color: c.accent) : null,
              ),
              child: Text(
                '${day.day}',
                style: PiumaType.body.copyWith(
                  color: color,
                  fontWeight: picked || today
                      ? FontWeight.w600
                      : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.text, required this.on, required this.onTap});

  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: on,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: text,
        child: ExcludeSemantics(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.soft : c.surface,
              border: Border.all(color: on ? c.soft : c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.pill),
            ),
            child: Text(
              text,
              style: PiumaType.body.copyWith(
                color: on ? c.accentText : c.fg,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      width: 72,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: Semantics(
        label: label,
        textField: true,
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            onSubmitted: onChanged,
            onChanged: (t) {
              if (RegExp(r'^\d{1,2}[:.]\d{2}$').hasMatch(t.trim())) {
                onChanged(t);
              }
            },
            keyboardType: TextInputType.datetime,
            textAlign: TextAlign.center,
            cursorColor: c.accent,
            style: PiumaType.mono.copyWith(fontSize: 14, color: c.fg),
            decoration: const InputDecoration.collapsed(hintText: ''),
          ),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 40,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: PiumaIconView(
            icon,
            size: size == 40 ? 20 : 18,
            color: onTap == null ? c.placeholder : c.fg,
          ),
        ),
      ),
    );
  }
}

/// A picked time in the button's words: "Fri, Oct 23, 9:00".
String pickWhen(DateTime at, String locale) =>
    '${DateFormat.MMMEd(locale).format(at)}, ${DateFormat('H:mm', locale).format(at)}';
