import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'done_screen.dart';
import 'l10n/app_localizations.dart';
import 'link.dart';
import 'reply_screen.dart';
import 'round.dart';
import 'snooze_screen.dart';
import 'summary.dart';

/// One email (`WatchWearOS` 3): plain words, no pictures; Archive and
/// Snooze under it, Reply on the edge button.
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key, required this.row, required this.color});

  final WatchRow row;
  final Color? color;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LinkScope.of(context).open(widget.row.payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final link = LinkScope.of(context);
    final row = widget.row;
    final text = link.text(row.payload);
    final locale = Localizations.localeOf(context).toLanguageTag();
    const c = watchColors;
    return Scaffold(
      backgroundColor: c.darkroom,
      body: Stack(
        children: [
          RoundScroll(
            bottom: 40,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.color != null) ...[
                    AccountDot(widget.color!, size: 6),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      '${row.sender} · ${DateFormat('H:mm', locale).format(row.time)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.label.copyWith(
                        letterSpacing: 0,
                        color: c.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                row.subject,
                textAlign: TextAlign.center,
                style: PiumaType.subtitle.copyWith(fontSize: 16, color: c.fg),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: reduceMotion(context)
                    ? Duration.zero
                    : PiumaMotion.enter,
                switchInCurve: PiumaMotion.curve,
                switchOutCurve: PiumaMotion.curve,
                child: Text(
                  text ?? row.preview,
                  key: ValueKey(text != null),
                  style: PiumaType.small.copyWith(
                    height: 1.45,
                    color: text == null ? c.muted : c.fg,
                  ),
                ),
              ),
              if (text != null && text.endsWith('…'))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PiumaIconView(PiumaIcon.phone, size: 13, color: c.muted),
                      const SizedBox(width: 6),
                      Text(
                        l.restOnPhone,
                        style: PiumaType.label.copyWith(
                          letterSpacing: 0,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RoundButton(
                    icon: PiumaIcon.archive,
                    label: l.archive,
                    onPressed: () => _archive(context),
                  ),
                  const SizedBox(width: 10),
                  RoundButton(
                    icon: PiumaIcon.clock,
                    label: l.snooze,
                    onPressed: () => _snooze(context),
                  ),
                ],
              ),
            ],
          ),
          EdgeButton(
            label: l.reply,
            icon: PiumaIcon.reply,
            onPressed: () => Navigator.of(context).push(
              GrowRoute<void>(
                instant: reduceMotion(context),
                builder: (_) => ReplyScreen(row: row),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _archive(BuildContext context) {
    final link = LinkScope.of(context);
    final payload = widget.row.payload;
    Navigator.of(context).pushReplacement(
      GrowRoute<void>(
        instant: reduceMotion(context),
        builder: (context) => DoneScreen(
          title: AppLocalizations.of(context).archived,
          detail: widget.row.subject,
          then: () => link.archive(payload),
        ),
      ),
    );
  }

  void _snooze(BuildContext context) {
    Navigator.of(context).pushReplacement(
      GrowRoute<void>(
        instant: reduceMotion(context),
        builder: (_) => SnoozeScreen(row: widget.row),
      ),
    );
  }
}
