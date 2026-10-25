import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'message_list.dart' show initials;

/// The invite a message carries, as in `PhoneInvite`: the date tile, what
/// and when, who is invited, and Yes, Maybe and No. The answer goes to the
/// organizer by email; Piuma keeps no calendar of its own.
class InviteCard extends StatefulWidget {
  const InviteCard({
    super.key,
    required this.invite,
    required this.source,
    required this.row,
  });

  final MailInvite invite;
  final MailSource source;

  /// The message it came in.
  final MailRow row;

  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
  late InviteAnswer? _answer = widget.invite.answer;

  /// Answered while the card was open: the line under says who gets it.
  bool _answeredHere = false;

  /// The answer waits in the outbox.
  bool _queued = false;
  bool _failed = false;

  /// The calendar the accepted event went in.
  String? _addedTo;

  /// What else is in your calendars around it; null without connected
  /// calendars, or with conflict checks off.
  List<BusyTime>? _busy;

  @override
  void initState() {
    super.initState();
    _loadBusy();
  }

  Future<void> _loadBusy() async {
    final i = widget.invite;
    if (i.allDay || !i.answerable) return;
    try {
      final prefs = await widget.source.calendarPrefs();
      if (!prefs.checkConflicts) return;
      final sources = await widget.source.calendarSources();
      if (!sources.any((s) => s.calendars.any((c) => c.availability))) return;
      final (from, to) = _Timeline.window(i);
      final busy = await widget.source.busyBetween(from, to);
      if (mounted) {
        setState(
          () => _busy = [
            for (final b in busy)
              if (b.uid.isEmpty || b.uid != i.uid)
                if (!b.allDay) b,
          ],
        );
      }
    } catch (_) {
      // No availability then: the invite still works by email.
    }
  }

  Future<void> _pick(InviteAnswer answer) async {
    if (answer == _answer) return;
    final l = AppLocalizations.of(context);
    final before = _answer;
    setState(() {
      _answer = answer;
      _answeredHere = true;
      _failed = false;
    });
    final invite = widget.invite;
    final account = widget.source.accounts
        .where((a) => a.id == widget.row.accountId)
        .firstOrNull;
    final me = account == null
        ? ''
        : account.senderName.isNotEmpty
        ? account.senderName
        : account.email;
    final summary = invite.summary;
    try {
      final sent = await widget.source.answerInvite(
        widget.row,
        answer,
        subject: switch (answer) {
          InviteAnswer.accepted => l.inviteSubjectAccepted(summary),
          InviteAnswer.tentative => l.inviteSubjectTentative(summary),
          InviteAnswer.declined => l.inviteSubjectDeclined(summary),
        },
        text: switch (answer) {
          InviteAnswer.accepted => l.inviteTextAccepted(me),
          InviteAnswer.tentative => l.inviteTextTentative(me),
          InviteAnswer.declined => l.inviteTextDeclined(me),
        },
      );
      if (mounted) {
        setState(() {
          _queued = sent.queued;
          _addedTo = sent.addedTo;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _answer = before;
        _answeredHere = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final i = widget.invite;
    final when = _when(context, i);
    final cancelled = i.method == InviteMethod.cancel;
    final where = [
      when,
      if (i.location.isNotEmpty) i.location,
      if (i.repeats) l.inviteRepeats,
    ].join(' · ');
    final people = i.attendees.isNotEmpty ? i.attendees : [?i.organizer];
    final status = _status(context, i);
    return Semantics(
      container: true,
      label: l.inviteCard(i.summary, when),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DateTile(day: i.start, locale: locale, faded: cancelled),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.summary,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.16,
                          color: cancelled ? c.muted : c.fg,
                          decoration: cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        where,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 14,
                          height: 1.35,
                          color: c.muted,
                        ),
                      ),
                      if (people.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _People(people: people),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_busy case final busy?) ...[
              const SizedBox(height: 12),
              _Timeline(invite: i, busy: busy),
            ],
            if (i.answerable) ...[
              SizedBox(height: _busy == null ? 14 : 10),
              _Answers(answer: _answer, onPick: _pick),
            ],
            if (status != null) ...[const SizedBox(height: 12), status],
          ],
        ),
      ),
    );
  }

  /// "Fri 20:30–22:30", "All day", "Oct 24 – 26".
  String _when(BuildContext context, MailInvite i) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final hm = DateFormat('H:mm', locale);
    final day = DateFormat.MMMd(locale);
    final sameDay = DateUtils.isSameDay(i.start, i.end);
    if (i.allDay) {
      final last = i.end.subtract(const Duration(days: 1));
      if (!last.isAfter(i.start) || DateUtils.isSameDay(i.start, last)) {
        return l.inviteAllDay;
      }
      return '${day.format(i.start)} – ${day.format(last)}';
    }
    if (sameDay) return '${hm.format(i.start)}–${hm.format(i.end)}';
    return '${hm.format(i.start)} – ${day.format(i.end)} ${hm.format(i.end)}';
  }

  Widget? _status(BuildContext context, MailInvite i) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final organizer = i.organizer?.label ?? '';
    if (i.method == InviteMethod.cancel) {
      return _Status(
        icon: PiumaIcon.close,
        color: c.danger,
        title: l.inviteCancelled,
      );
    }
    if (i.method == InviteMethod.reply) {
      final who = i.attendees.where((a) => a.answer != null).firstOrNull;
      if (who == null) return null;
      return _Status(
        icon: who.answer == InviteAnswer.declined
            ? PiumaIcon.close
            : PiumaIcon.check,
        color: switch (who.answer!) {
          InviteAnswer.accepted => c.ok,
          InviteAnswer.tentative => c.warn,
          InviteAnswer.declined => c.muted,
        },
        title: switch (who.answer!) {
          InviteAnswer.accepted => l.inviteTheyAccepted(who.label),
          InviteAnswer.tentative => l.inviteTheyTentative(who.label),
          InviteAnswer.declined => l.inviteTheyDeclined(who.label),
        },
      );
    }
    if (i.yours && i.method == InviteMethod.request) {
      return _Status(
        icon: PiumaIcon.calendar,
        color: c.muted,
        title: l.inviteYours,
      );
    }
    if (_failed) {
      return _Status(
        icon: PiumaIcon.warning,
        color: c.danger,
        title: l.inviteNotSent,
      );
    }
    final answer = _answer;
    if (answer == null || !i.answerable) return null;
    return _Status(
      key: ValueKey(answer),
      icon: answer == InviteAnswer.declined ? PiumaIcon.close : PiumaIcon.check,
      color: switch (answer) {
        InviteAnswer.accepted => c.ok,
        InviteAnswer.tentative => c.warn,
        InviteAnswer.declined => c.muted,
      },
      title: switch (answer) {
        InviteAnswer.accepted => l.inviteYouAccepted,
        InviteAnswer.tentative => l.inviteYouTentative,
        InviteAnswer.declined => l.inviteYouDeclined,
      },
      detail: !_answeredHere || organizer.isEmpty
          ? null
          : _queued
          ? l.inviteQueued(organizer)
          : _addedTo != null && answer != InviteAnswer.declined
          ? l.inviteAddedTo(_addedTo!)
          : l.inviteWillGet(organizer),
    );
  }
}

/// The hours around the event, as in `PhoneInvite`: what else is in your
/// calendars as grey blocks, the event in the accent, and whether you are
/// free then.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.invite, required this.busy});

  final MailInvite invite;

  /// Everything around the window; those overlapping the event are
  /// conflicts.
  final List<BusyTime> busy;

  static const _hours = 10;

  /// Ten hours that hold the event, starting a few hours before it.
  static (DateTime, DateTime) window(MailInvite i) {
    final first = (i.start.hour - 4).clamp(0, 24 - _hours);
    final from = DateTime(i.start.year, i.start.month, i.start.day, first);
    return (from, from.add(const Duration(hours: _hours)));
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final (from, to) = window(invite);
    final span = to.difference(from).inSeconds;
    double at(DateTime t) =>
        (t.difference(from).inSeconds / span).clamp(0.0, 1.0);
    final clash = busy
        .where((b) => b.overlaps(invite.start, invite.end))
        .firstOrNull;
    final note = clash == null
        ? l.inviteFree
        : l.inviteOverlaps(
            clash.summary,
            DateFormat('H:mm', locale).format(clash.start),
          );
    final mono = TextStyle(
      fontFamily: PiumaFonts.mono,
      fontSize: 10,
      color: c.muted,
    );
    return Semantics(
      container: true,
      label: l.inviteAvailability(note),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              Widget block(
                DateTime start,
                DateTime end, {
                required bool event,
                String label = '',
              }) {
                final left = at(start) * w;
                final width = ((at(end) - at(start)) * w).clamp(4.0, w - left);
                return Positioned(
                  left: left,
                  top: 3,
                  width: width,
                  height: 16,
                  child: Container(
                    padding: const EdgeInsets.only(left: 5),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: event ? c.accent.withValues(alpha: 0.92) : c.busy,
                      borderRadius: BorderRadius.circular(5),
                      border: event
                          ? Border.all(color: c.surface, width: 2)
                          : null,
                    ),
                    child: event
                        ? null
                        : Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 10,
                              color: c.muted,
                            ),
                          ),
                  ),
                );
              }

              final marks = [
                for (var h = from.hour; h < from.hour + _Timeline._hours; h++)
                  if (h % 3 == 0) h,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 22,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 10,
                          height: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.line,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        for (final b in busy)
                          if (b.overlaps(from, to))
                            block(
                              b.start,
                              b.end,
                              event: false,
                              label: b.summary,
                            ),
                        block(invite.start, invite.end, event: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 12,
                    child: Stack(
                      children: [
                        for (final h in marks)
                          Positioned(
                            left: (h - from.hour) / _Timeline._hours * w,
                            child: Text('${h % 24}', style: mono),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: clash == null ? c.ok : c.warn,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 12,
                            color: clash == null ? c.ok : c.warn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// THU · 23 · OCT.
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.day,
    required this.locale,
    this.faded = false,
  });
  final DateTime day;
  final String locale;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 50,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PiumaRadius.row),
          border: Border.all(color: c.line),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 3),
              color: faded ? c.muted : c.accent,
              child: Text(
                DateFormat.E(locale).format(day).toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: c.onAccent,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 1),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: c.fg,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                DateFormat.MMM(locale).format(day).toUpperCase(),
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.6,
                  color: c.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to three initials, then "+2", and how many are invited.
class _People extends StatelessWidget {
  const _People({required this.people});
  final List<InvitePerson> people;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final shown = people.take(3).toList();
    final more = people.length - shown.length;
    Widget dot(String text, {bool count = false}) => Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.chip,
        shape: BoxShape.circle,
        border: Border.all(color: c.bg, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: count ? c.muted : c.fg,
        ),
      ),
    );
    final dots = [
      for (final p in shown) dot(initials(p.label)),
      if (more > 0) dot('+$more', count: true),
    ];
    return Row(
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 26.0 + 21 * (dots.length - 1),
            height: 26,
            child: Stack(
              children: [
                for (final (i, d) in dots.indexed)
                  Positioned(left: 21.0 * i, child: d),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          l.inviteAttendees(people.length),
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 12,
            color: c.muted,
          ),
        ),
      ],
    );
  }
}

/// Yes, Maybe, No: one control, the answer's pill sliding under it.
class _Answers extends StatelessWidget {
  const _Answers({required this.answer, required this.onPick});
  final InviteAnswer? answer;
  final ValueChanged<InviteAnswer> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    const answers = InviteAnswer.values;
    final at = answer == null ? -1 : answers.indexOf(answer!);
    return Semantics(
      container: true,
      label: l.inviteRespond,
      child: Container(
        height: 46,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final third = box.maxWidth / 3;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: instant ? Duration.zero : PiumaMotion.move,
                  curve: PiumaMotion.curve,
                  left: third * (at < 0 ? 0 : at),
                  top: 0,
                  bottom: 0,
                  width: third,
                  child: AnimatedOpacity(
                    duration: instant ? Duration.zero : PiumaMotion.press,
                    curve: PiumaMotion.curve,
                    opacity: at < 0 ? 0 : 1,
                    child: AnimatedContainer(
                      duration: instant ? Duration.zero : PiumaMotion.press,
                      curve: PiumaMotion.curve,
                      decoration: BoxDecoration(
                        color: answer == InviteAnswer.accepted
                            ? c.accent
                            : c.surface,
                        borderRadius: BorderRadius.circular(PiumaRadius.button),
                        boxShadow: [
                          BoxShadow(
                            color: c.shadow,
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final a in answers)
                      Expanded(
                        child: Semantics(
                          selected: a == answer,
                          child: PiumaPressable(
                            onTap: () => onPick(a),
                            semanticLabel: switch (a) {
                              InviteAnswer.accepted => l.inviteYes,
                              InviteAnswer.tentative => l.inviteMaybe,
                              InviteAnswer.declined => l.inviteNo,
                            },
                            child: Center(
                              child: Text(
                                switch (a) {
                                  InviteAnswer.accepted => l.inviteYes,
                                  InviteAnswer.tentative => l.inviteMaybe,
                                  InviteAnswer.declined => l.inviteNo,
                                },
                                style: TextStyle(
                                  fontFamily: PiumaFonts.sans,
                                  fontSize: 15,
                                  fontWeight: a == answer
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: a != answer
                                      ? c.muted
                                      : a == InviteAnswer.accepted
                                      ? c.onAccent
                                      : c.fg,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "✓ You accepted · Giulia will get your reply".
class _Status extends StatelessWidget {
  const _Status({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
  });

  final PiumaIcon icon;
  final Color color;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: PiumaEnter(
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: PiumaIconView(icon, size: 13, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (detail != null)
                      TextSpan(
                        text: ' · $detail',
                        style: TextStyle(color: c.muted),
                      ),
                  ],
                ),
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 14,
                  height: 1.3,
                  color: c.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
