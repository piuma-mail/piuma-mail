import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// The sidebar's Groups, as on `GroupsSidebar`: All groups (the unified
/// inbox), then each group with its own Inbox; a chevron folds a group
/// open to its addresses, each with what is unread there.
class SidebarGroups extends StatefulWidget {
  const SidebarGroups({
    super.key,
    required this.groups,
    required this.unread,
    this.current,
    this.onGroup,
    this.onNewGroup,
  });

  /// The groups with a Separate Inbox, in order.
  final List<MailGroup> groups;
  final Map<int, GroupUnread> unread;

  /// The group or address the list shows, if one is.
  final GroupScope? current;

  /// Shows a group, an address of one, or every account's mail (null).
  final ValueChanged<GroupScope?>? onGroup;
  final VoidCallback? onNewGroup;

  @override
  State<SidebarGroups> createState() => _SidebarGroupsState();
}

class _SidebarGroupsState extends State<SidebarGroups> {
  /// Groups folded open to their addresses.
  final _open = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.current case final g?) _open.add(g.group);
  }

  @override
  void didUpdateWidget(SidebarGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The group of the address shown keeps its addresses open.
    if (widget.current case GroupScope(:final group, address: _?)) {
      _open.add(group);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final onGroup = widget.onGroup;
    final current = widget.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.groupsTitle.toUpperCase(),
                  style: PiumaType.label.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.onNewGroup case final add?)
                PiumaPressable(
                  onTap: add,
                  semanticLabel: l.groupNew,
                  child: SizedBox.square(
                    dimension: 28,
                    child: Center(
                      child: PiumaIconView(
                        PiumaIcon.plus,
                        size: 15,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _AllGroups(
          colors: [for (final g in widget.groups) g.color],
          onTap: onGroup == null ? null : () => onGroup(null),
        ),
        for (final g in widget.groups) ...[
          _GroupItem(
            group: g,
            unread: widget.unread[g.id]?.unread ?? 0,
            current: current == GroupScope(g.id),
            within: current?.group == g.id,
            open: _open.contains(g.id),
            onOpen: () => setState(
              () => _open.contains(g.id) ? _open.remove(g.id) : _open.add(g.id),
            ),
            onTap: onGroup == null ? null : () => onGroup(GroupScope(g.id)),
          ),
          if (_open.contains(g.id) && g.addresses.isNotEmpty)
            PiumaEnter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(28, 2, 0, 6),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, a) in g.addresses.indexed)
                      _AddressItem(
                        email: a.email,
                        unread: switch (widget.unread[g.id]?.addresses) {
                          final n? when i < n.length => n[i],
                          _ => 0,
                        },
                        current: current == GroupScope(g.id, a.email),
                        onTap: onGroup == null
                            ? null
                            : () => onGroup(GroupScope(g.id, a.email)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// All groups: the unified inbox, under the groups' dots.
class _AllGroups extends StatelessWidget {
  const _AllGroups({required this.colors, this.onTap});
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final dots = colors.take(4).toList();
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${l.groupsAll}, ${l.unifiedInbox}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 8.0 + 5 * (dots.length - 1).clamp(0, 3),
                height: 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (i, color) in dots.indexed)
                      Positioned(
                        left: 5.0 * i,
                        child: _Dot(color: color, size: 8),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.groupsAll,
                      style: TextStyle(fontSize: 14, height: 1.3, color: c.fg),
                    ),
                    Text(
                      l.unifiedInbox,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupItem extends StatelessWidget {
  const _GroupItem({
    required this.group,
    required this.unread,
    required this.current,
    required this.within,
    required this.open,
    required this.onOpen,
    this.onTap,
  });

  final MailGroup group;
  final int unread;

  /// The group's whole Inbox shows.
  final bool current;

  /// The group, or one of its addresses, shows.
  final bool within;
  final bool open;
  final VoidCallback onOpen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      height: 36,
      decoration: BoxDecoration(
        color: current ? c.sel : null,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const SizedBox(width: 2),
          Semantics(
            container: true,
            expanded: open,
            button: true,
            label: open
                ? l.groupCollapse(group.name)
                : l.groupExpand(group.name),
            child: PiumaPressable(
              onTap: onOpen,
              child: SizedBox(
                width: 26,
                height: 36,
                child: Center(
                  child: AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: instant ? Duration.zero : PiumaMotion.press,
                    curve: PiumaMotion.curve,
                    child: PiumaIconView(
                      PiumaIcon.chevronRight,
                      size: 14,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              selected: current,
              button: true,
              child: PiumaPressable(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 10),
                  child: Row(
                    children: [
                      _Dot(color: group.color, size: 10),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: c.fg,
                            fontWeight: within
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread > 0)
                        Text(
                          '$unread',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                    ],
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

class _AddressItem extends StatelessWidget {
  const _AddressItem({
    required this.email,
    required this.unread,
    required this.current,
    this.onTap,
  });
  final String email;
  final int unread;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      selected: current,
      button: true,
      child: PiumaPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 30,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: current ? c.sel : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: current ? c.fg : c.muted,
                  ),
                ),
              ),
              if (unread > 0)
                Text('$unread', style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
