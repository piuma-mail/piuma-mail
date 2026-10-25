import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// "Add Friday 10:00 to calendar" under the words that name it, as in
/// `PhoneInvite`: found on this device, never added without a tap.
class FoundDateChip extends StatefulWidget {
  const FoundDateChip({
    super.key,
    required this.date,
    required this.source,
    required this.row,
    required this.now,
  });

  final FoundDate date;
  final MailSource source;
  final MailRow row;
  final DateTime Function() now;

  /// "Friday 10:00" within the week, "Oct 24 10:00" after it.
  static String when(DateTime at, DateTime now, String locale) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final ahead = day.difference(today).inHours / 24;
    final date = ahead < 7
        ? DateFormat.EEEE(locale).format(at)
        : DateFormat.MMMd(locale).format(at);
    return '$date ${DateFormat('H:mm', locale).format(at)}';
  }

  @override
  State<FoundDateChip> createState() => _FoundDateChipState();
}

class _FoundDateChipState extends State<FoundDateChip> {
  late FoundDate _date = widget.date;
  bool _busy = false;

  @override
  void didUpdateWidget(FoundDateChip old) {
    super.didUpdateWidget(old);
    if (old.date.uid != widget.date.uid) _date = widget.date;
  }

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final calendar = await widget.source.addFoundDate(widget.row, _date);
      if (mounted) setState(() => _date = _date.added(calendar));
    } catch (_) {
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.foundDateNotAdded),
            behavior: SnackBarBehavior.floating,
            width: 360,
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = FoundDateChip.when(_date.at, widget.now(), locale);
    final added = _date.addedTo;
    final label = added == null
        ? l.foundDateAdd(when)
        : l.foundDateAdded(added);
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Tooltip(
        message: l.foundOnDevice,
        child: PiumaPressable(
          onTap: added == null && !_busy ? _add : null,
          semanticLabel: added == null
              ? l.foundDateAddLabel(when)
              : l.foundDateAddedLabel(when, added),
          child: SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: AnimatedContainer(
                duration: reduceMotion(context)
                    ? Duration.zero
                    : PiumaMotion.theme,
                curve: PiumaMotion.curve,
                height: 30,
                padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                decoration: BoxDecoration(
                  color: added == null ? c.surface : c.soft,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(PiumaRadius.pill),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PiumaIconView(
                        added == null ? PiumaIcon.spark : PiumaIcon.check,
                        size: 14,
                        color: added == null ? c.muted : c.accentText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          color: added == null ? c.muted : c.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
