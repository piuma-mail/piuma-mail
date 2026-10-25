import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'message_list.dart' show initials;

/// The reading pane while several conversations are picked, as in the
/// `DesktopSelect` mockup: a small stack of what is picked, how many and
/// from whom, and the actions that work on all of them at once.
class SelectionPanel extends StatelessWidget {
  const SelectionPanel({
    super.key,
    required this.rows,
    this.onArchive,
    this.onNotSpam,
    required this.onDelete,
    this.onMove,
    this.onLabel,
    this.onSnooze,
    required this.onSeen,
  });

  /// "Find or create a label", opened under its button.
  final ValueChanged<Rect>? onLabel;

  /// "Snooze until…", opened under its button; null where snoozing makes
  /// no sense (Sent, Drafts).
  final ValueChanged<Rect>? onSnooze;

  /// The picked rows, in the order they were picked.
  final List<MailRow> rows;

  /// Null where archiving makes no sense (Archive itself).
  final VoidCallback? onArchive;

  /// In the spam folder, in Archive's place: back to the inbox.
  final VoidCallback? onNotSpam;
  final VoidCallback onDelete;

  /// "Move to…", opened under its button; null when the rows are of
  /// several accounts.
  final ValueChanged<Rect>? onMove;

  /// Marks them all read (true) or unread (false).
  final ValueChanged<bool> onSeen;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final count = rows.length;
    final allRead = rows.every((r) => r.seen);
    final lead = rows.first;
    return ColoredBox(
      color: c.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: _Stack(rows: rows, lead: lead),
                ),
                const SizedBox(height: 28),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      RollingCount(count),
                      const SizedBox(width: 6),
                      Text(
                        l.conversationsPicked(count),
                        style: PiumaType.title.copyWith(color: c.fg),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _senders(l),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: PiumaSpace.s8,
                  runSpacing: PiumaSpace.s8,
                  children: [
                    if (onArchive != null)
                      _ActionButton(
                        icon: PiumaIcon.archive,
                        label: l.archive,
                        primary: true,
                        onTap: onArchive!,
                      ),
                    if (onNotSpam case final notSpam?)
                      _ActionButton(
                        icon: PiumaIcon.inbox,
                        label: l.notSpam,
                        primary: true,
                        onTap: notSpam,
                      ),
                    _ActionButton(
                      icon: allRead ? PiumaIcon.mail : PiumaIcon.mailOpen,
                      label: allRead ? l.markUnread : l.markRead,
                      onTap: () => onSeen(!allRead),
                    ),
                    if (onMove case final move?)
                      Builder(
                        builder: (button) => _ActionButton(
                          icon: PiumaIcon.folder,
                          label: l.moveTo,
                          onTap: () {
                            final box = button.findRenderObject()! as RenderBox;
                            move(box.localToGlobal(Offset.zero) & box.size);
                          },
                        ),
                      ),
                    if (onLabel case final label?)
                      Builder(
                        builder: (button) => _ActionButton(
                          icon: PiumaIcon.tag,
                          label: l.labelAction,
                          onTap: () {
                            final box = button.findRenderObject()! as RenderBox;
                            label(box.localToGlobal(Offset.zero) & box.size);
                          },
                        ),
                      ),
                    if (onSnooze case final snooze?)
                      Builder(
                        builder: (button) => _ActionButton(
                          icon: PiumaIcon.clock,
                          label: l.actionSnooze,
                          onTap: () {
                            final box = button.findRenderObject()! as RenderBox;
                            snooze(box.localToGlobal(Offset.zero) & box.size);
                          },
                        ),
                      ),
                    _ActionButton(
                      icon: PiumaIcon.trash,
                      label: l.actionDelete,
                      color: c.danger,
                      onTap: onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _Hints(
                  archive: onArchive != null,
                  move: onMove != null,
                  label: onLabel != null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "from Giulia", "from Giulia and Sara", "from Giulia, Dad and Andrea",
  /// "from Giulia, Sara and 2 more": first names, each person once.
  String _senders(AppLocalizations l) {
    final names = <String>[];
    for (final r in rows) {
      final name = r.listName.split(RegExp(r'\s+')).first;
      if (!names.contains(name)) names.add(name);
    }
    if (names.length == 1) return l.pickedFromOne(names.first);
    if (names.length <= 3) {
      return l.pickedFromList(
        names.sublist(0, names.length - 1).join(', '),
        names.last,
      );
    }
    return l.pickedFromMore(names.take(2).join(', '), names.length - 2);
  }
}

/// Up to three cards stacked: the front one shows faces and the first
/// subject, the two behind appear as more are picked.
class _Stack extends StatelessWidget {
  const _Stack({required this.rows, required this.lead});
  final List<MailRow> rows;
  final MailRow lead;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final count = rows.length;
    final faces = rows.take(3).toList();
    final fade = reduceMotion(context) ? Duration.zero : PiumaMotion.enter;
    Widget back(double dy, double scale, bool shown) => Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 100,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: fade,
        curve: PiumaMotion.curve,
        child: Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: 300,
      height: 128,
      child: Stack(
        children: [
          back(24, 0.9, count >= 3),
          back(12, 0.95, count >= 2),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: c.shadow.a / 6),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34.0 + 24 * (faces.length - 1),
                    height: 34,
                    child: Stack(
                      children: [
                        for (final (i, r) in faces.indexed)
                          Positioned(
                            left: 24.0 * i,
                            child: _Face(initials(r.listName)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: c.fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          count > 1
                              ? l.andMore(lead.listName, count - 1)
                              : lead.listName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.small.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.chip,
        shape: BoxShape.circle,
        border: Border.all(color: c.surface, width: 2),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.fg,
        ),
      ),
    );
  }
}

/// The count rolls up when it grows and down when it shrinks.
class RollingCount extends StatefulWidget {
  const RollingCount(this.count, {super.key, this.style});
  final int count;

  /// The title style unless given.
  final TextStyle? style;

  @override
  State<RollingCount> createState() => _RollingCountState();
}

class _RollingCountState extends State<RollingCount> {
  bool _up = true;

  @override
  void didUpdateWidget(RollingCount old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _up = widget.count > old.count;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final style = (widget.style ?? PiumaType.title).copyWith(
      color: c.fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduceMotion(context) ? Duration.zero : PiumaMotion.move,
        switchInCurve: PiumaMotion.curve,
        switchOutCurve: PiumaMotion.curve,
        layoutBuilder: (current, previous) =>
            Stack(children: [...previous, ?current]),
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(widget.count);
          final from = Offset(0, _up ? 1 : -1);
          final to = Offset(0, _up ? -1 : 1);
          return SlideTransition(
            position: incoming
                ? Tween(begin: from, end: Offset.zero).animate(animation)
                : Tween(begin: to, end: Offset.zero).animate(animation),
            child: child,
          );
        },
        child: Text(
          '${widget.count}',
          key: ValueKey(widget.count),
          style: style,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.color,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final fg = primary ? c.onAccent : color ?? c.fg;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: primary ? 16 : 14),
        decoration: BoxDecoration(
          color: primary ? c.accent : c.surface,
          border: primary ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(icon, color: fg),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "E archive · M move · ⇧U unread · Esc deselect".
class _Hints extends StatelessWidget {
  const _Hints({
    required this.archive,
    required this.move,
    required this.label,
  });
  final bool archive;
  final bool move;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final style = PiumaType.mono.copyWith(
      fontSize: 12,
      height: 1.3,
      color: c.muted,
    );
    Widget key(String k) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(k, style: style),
    );
    final items = [
      if (archive) (key('E'), l.hintArchive),
      if (move) (key('M'), l.hintMove),
      if (label) (key('L'), l.hintLabel),
      (key('⇧U'), l.hintUnread),
      (key('Esc'), l.hintDeselect),
    ];
    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, (k, text)) in items.indexed) ...[
            if (i > 0) Text('·', style: style),
            k,
            Text(text, style: style),
          ],
        ],
      ),
    );
  }
}
