import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// The inbox's filters (`FiltersToApprove`, variant 2): All, People and
/// Notifications, one at a time, People and Notifications with their
/// unread counts, and Unread, a switch that adds to them. A segmented
/// control with the switch at its end on the desktop (`Main`), pills on
/// the phone (`Phone`), first in the row of chips the zones share
/// (`HomeToApprove`, variant 2).
class InboxTabs extends StatelessWidget {
  const InboxTabs({
    super.key,
    required this.tab,
    required this.counts,
    required this.onTab,
    this.unread = false,
    this.onUnread,
    this.phone = false,
  });

  final InboxTab tab;
  final TabCounts counts;
  final ValueChanged<InboxTab> onTab;

  /// Whether Unread is on, and its switch; no switch when null.
  final bool unread;
  final ValueChanged<bool>? onUnread;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      (InboxTab.all, l.tabAll, 0),
      (InboxTab.people, l.tabPeople, counts.peopleUnread),
      (InboxTab.notifications, l.tabNotifications, counts.notificationsUnread),
    ];
    final onUnread = this.onUnread;
    final toggle = onUnread == null
        ? null
        : _UnreadSwitch(
            on: unread,
            phone: phone,
            onTap: () => onUnread(!unread),
          );
    return Semantics(
      container: true,
      label: l.inboxSections,
      child: phone
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, (t, label, count)) in items.indexed) ...[
                  if (i > 0) const SizedBox(width: PiumaSpace.s8),
                  _Pill(
                    label: label,
                    unread: count,
                    on: t == tab,
                    onTap: () => onTab(t),
                  ),
                ],
                if (toggle != null) ...[
                  const SizedBox(width: PiumaSpace.s8),
                  toggle,
                ],
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _Segments(
                    children: [
                      for (final (t, label, count) in items)
                        Expanded(
                          flex: switch (t) {
                            InboxTab.all => 2,
                            InboxTab.people => 3,
                            InboxTab.notifications => 4,
                          },
                          child: _Segment(
                            label: label,
                            unread: count,
                            on: t == tab,
                            onTap: () => onTab(t),
                          ),
                        ),
                    ],
                  ),
                ),
                if (toggle != null) ...[
                  const SizedBox(width: PiumaSpace.s8),
                  toggle,
                ],
              ],
            ),
    );
  }
}

/// Unread: on the phone a pill, soft blue with a tick when on; on the
/// desktop a bordered button with a blue dot, filled soft when on.
class _UnreadSwitch extends StatelessWidget {
  const _UnreadSwitch({
    required this.on,
    required this.phone,
    required this.onTap,
  });

  final bool on;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    final duration = instant ? Duration.zero : PiumaMotion.press;
    final ink = on ? c.accentText : c.fg;
    final style = PiumaType.body.copyWith(
      fontSize: 14,
      height: 1.2,
      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
      color: phone ? ink : (on ? c.accentText : c.muted),
    );
    return Semantics(
      toggled: on,
      hint: l.filterUnreadHint,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: l.filterUnread,
        child: AnimatedContainer(
          duration: duration,
          curve: PiumaMotion.curve,
          height: phone ? 36 : 42,
          padding: EdgeInsets.fromLTRB(
            phone && on ? 10 : 12,
            0,
            phone ? 14 : 12,
            0,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.soft : c.soft.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(
              phone ? PiumaRadius.pill : PiumaRadius.row,
            ),
            border: Border.all(color: on ? c.soft : c.line),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (phone)
                  AnimatedSize(
                    duration: duration,
                    curve: PiumaMotion.curve,
                    child: on
                        ? Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: PiumaIconView(
                              PiumaIcon.check,
                              size: 15,
                              color: ink,
                            ),
                          )
                        : const SizedBox.shrink(),
                  )
                else ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(l.filterUnread, maxLines: 1, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a screen reader says for a tab: its name, and what is unread.
String _spoken(AppLocalizations l, String label, int unread) =>
    unread > 0 ? l.tabUnread(label, unread) : label;

class _Segments extends StatelessWidget {
  const _Segments({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(PiumaSpace.s4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: Row(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) const SizedBox(width: PiumaSpace.s4),
            child,
          ],
        ],
      ),
    );
  }
}

/// One side of the desktop control: raised on the surface when on, with
/// its count muted beside the name.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.unread,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int unread;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      selected: on,
      inMutuallyExclusiveGroup: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: _spoken(l, label, unread),
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.surface : c.surface.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: on ? 0.08 : 0),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label),
                  if (unread > 0)
                    TextSpan(
                      text: ' $unread',
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PiumaType.body.copyWith(
                fontSize: 14,
                height: 1.2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? c.fg : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One phone pill: filled with the text color when on, outlined when off.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.unread,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int unread;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      selected: on,
      inMutuallyExclusiveGroup: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: _spoken(l, label, unread),
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.fg : c.fg.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
            border: Border.all(color: on ? c.fg : c.line),
          ),
          child: ExcludeSemantics(
            child: Text(
              unread > 0 ? '$label $unread' : label,
              maxLines: 1,
              style: PiumaType.body.copyWith(
                fontSize: 14,
                height: 1.2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? c.surface : c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
