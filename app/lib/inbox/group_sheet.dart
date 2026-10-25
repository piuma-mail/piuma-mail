import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// The phone's group sheet, as on `GroupsPhone`: Show all groups or one
/// group's Inbox, each with what is unread, and Manage groups.
class PhoneGroupSheet extends StatelessWidget {
  const PhoneGroupSheet({
    super.key,
    required this.groups,
    required this.unread,
    required this.allUnread,
    this.current,
    required this.onGroup,
    required this.onManage,
  });

  /// The groups with a Separate Inbox, in order.
  final List<MailGroup> groups;
  final Map<int, GroupUnread> unread;

  /// What is unread in the unified inbox.
  final int allUnread;

  /// The group shown; null for all of them.
  final int? current;
  final ValueChanged<int?> onGroup;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final addresses = groups.fold(0, (n, g) => n + g.addresses.length);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l.groupSheetTitle,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: c.fg,
                      ),
                    ),
                  ),
                ),
                Text(
                  l.groupSheetLine(addresses, groups.length),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
          _Choice(
            on: current == null,
            onTap: () => onGroup(null),
            label: l.groupsAll,
            unread: allUnread,
            lead: SizedBox(
              width: 22,
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [for (final g in groups.take(4)) _Dot(g.color, 10)],
              ),
            ),
          ),
          for (final g in groups)
            _Choice(
              on: current == g.id,
              onTap: () => onGroup(g.id),
              label: g.name,
              line: [for (final a in g.addresses) a.email].join(' · '),
              unread: unread[g.id]?.unread ?? 0,
              lead: SizedBox(
                width: 22,
                child: Center(child: _Dot(g.color, 12)),
              ),
            ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: c.line,
          ),
          PiumaPressable(
            onTap: onManage,
            semanticLabel: l.groupManage,
            child: ExcludeSemantics(
              child: SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Center(
                          child: PiumaIconView(
                            PiumaIcon.sliders,
                            size: 18,
                            color: c.accentText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l.groupManage,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// One row of the sheet: checked while it shows.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.on,
    required this.onTap,
    required this.label,
    required this.unread,
    required this.lead,
    this.line,
  });

  final bool on;
  final VoidCallback onTap;
  final String label;
  final String? line;
  final int unread;
  final Widget lead;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      selected: on,
      button: true,
      label: label,
      child: PiumaPressable(
        onTap: onTap,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            constraints: BoxConstraints(minHeight: line == null ? 56 : 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.sel : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                lead,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.fg,
                        ),
                      ),
                      if (line case final line?)
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Text(
                    '$unread',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                SizedBox(
                  width: 32,
                  child: on
                      ? Center(
                          child: PiumaIconView(
                            PiumaIcon.check,
                            size: 18,
                            color: c.accentText,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color, this.size);
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
