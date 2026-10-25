import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../updates/updates.dart';
import '../updates/whats_new.dart';
import '../widgets/dialog.dart';
import 'labels.dart';
import 'sidebar_groups.dart';

/// Left column of the desktop layout: Compose, folders and accounts.
/// A chevron by an account opens its own folders under it
/// (`AccountFolders`, option A).
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.accounts,
    required this.unread,
    required this.onCompose,
    required this.onAddAccount,
    required this.onSearch,
    required this.onSettings,
    this.folder = MailFolder.inbox,
    this.onFolder,
    this.account,
    this.onAccount,
    this.rail = false,
    this.drafts = 0,
    this.folders = const {},
    this.mailbox,
    this.onMailbox,
    this.newsletters,
    this.vault,
    this.attachments,
    this.syncedDevices,
    this.snoozed,
    this.waiting,
    this.groups = const [],
    this.groupUnread = const {},
    this.group,
    this.onGroup,
    this.onNewGroup,
    this.labels = const [],
    this.label,
    this.onLabel,
    this.onNewLabel,
  });

  /// The labels, under the groups (`LabelsToApprove`); the section shows
  /// once there is one.
  final List<MailLabel> labels;

  /// The keyword of the label whose mail the list shows, if one is.
  final String? label;
  final ValueChanged<MailLabel>? onLabel;
  final VoidCallback? onNewLabel;

  /// Groups with a Separate Inbox get their own section above the
  /// accounts (`GroupsSidebar`).
  final List<MailGroup> groups;
  final Map<int, GroupUnread> groupUnread;

  /// The group, or address of one, the list shows.
  final GroupScope? group;
  final ValueChanged<GroupScope?>? onGroup;
  final VoidCallback? onNewGroup;

  /// Snoozed conversations; null hides Snoozed, while there are none.
  final int? snoozed;

  /// Sent emails waiting 3 days or more for a reply, as on
  /// `WaitingToApprove`; null hides Waiting, while nothing waits.
  final int? waiting;

  /// Unread newsletters; null hides Newsletters, while there are none.
  final int? newsletters;

  /// Parcels on the way and bills to pay; null hides the Vault, while it
  /// has no cards.
  final int? vault;

  /// Files received this week; null hides Attachments, while there are
  /// no files.
  final int? attachments;

  /// "Synced on 3 devices" at the foot, as on `GroupsSidebar`; null while
  /// sync is off.
  final int? syncedDevices;

  /// Width of the sidebar as a column of icons, in a narrow window.
  static const double railWidth = 64;

  /// Icons only, with tooltips: the same items in [railWidth].
  final bool rail;

  /// The list shown, and how to show another.
  final MailFolder folder;
  final ValueChanged<MailFolder>? onFolder;

  /// The one account whose mail the list shows; every account's when null.
  /// A click on an account shows only its mail, a second click all again.
  final int? account;
  final ValueChanged<int?>? onAccount;

  final List<MailAccount> accounts;
  final int unread;

  /// How many drafts there are; Drafts shows only when there are some.
  final int drafts;

  /// Each account's own folders, by account id.
  final Map<int, List<AccountFolder>> folders;

  /// The own folder of [account] the list shows, if one is.
  final String? mailbox;
  final void Function(int account, String mailbox)? onMailbox;

  List<(MailFolder, PiumaIcon, String)> _folders(AppLocalizations l) => [
    (MailFolder.inbox, PiumaIcon.inbox, l.unifiedInbox),
    if (waiting != null || folder == MailFolder.waiting)
      (MailFolder.waiting, PiumaIcon.hourglass, l.folderWaiting),
    if (snoozed != null || folder == MailFolder.snoozed)
      (MailFolder.snoozed, PiumaIcon.clock, l.folderSnoozed),
    if (drafts > 0 || folder == MailFolder.drafts)
      (MailFolder.drafts, PiumaIcon.pen, l.folderDrafts),
    (MailFolder.sent, PiumaIcon.send, l.folderSent),
    (MailFolder.archive, PiumaIcon.archive, l.folderArchive),
  ];

  /// The special zones, in their own group under the folders.
  List<(MailFolder, PiumaIcon, String)> _zones(AppLocalizations l) => [
    if (newsletters != null || folder == MailFolder.newsletters)
      (MailFolder.newsletters, PiumaIcon.newsletter, l.folderNewsletters),
    if (vault != null || folder == MailFolder.vault)
      (MailFolder.vault, PiumaIcon.vault, l.folderVault),
    if (attachments != null || folder == MailFolder.attachments)
      (MailFolder.attachments, PiumaIcon.paperclip, l.folderAttachments),
  ];
  final VoidCallback onCompose;
  final VoidCallback onAddAccount;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  /// Accounts whose folders are open under them.
  final _open = <int>{};

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The account of the folder shown keeps its folders open.
    if (widget.mailbox != null && widget.account != null) {
      _open.add(widget.account!);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.mailbox != null && widget.account != null) {
      _open.add(widget.account!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rail = widget.rail;
    final folder = widget.folder;
    final onFolder = widget.onFolder;
    final accounts = widget.accounts;
    final unread = widget.unread;
    final drafts = widget.drafts;
    final onCompose = widget.onCompose;
    final onSearch = widget.onSearch;
    final onSettings = widget.onSettings;
    final onAddAccount = widget.onAddAccount;
    final own = widget.mailbox != null;
    if (rail) return _rail(context);
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SearchButton(onTap: onSearch),
          const SizedBox(height: 20),
          PiumaPressable(
            onTap: onCompose,
            semanticLabel: l.compose,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PiumaIconView(PiumaIcon.compose, color: c.onAccent),
                  const SizedBox(width: 8),
                  Text(
                    l.compose,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final (f, icon, label) in widget._folders(l))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _NavItem(
                icon: icon,
                label: label,
                count: switch (f) {
                  MailFolder.inbox => unread,
                  MailFolder.drafts => drafts,
                  MailFolder.snoozed => widget.snoozed ?? 0,
                  MailFolder.waiting => widget.waiting ?? 0,
                  _ => 0,
                },
                // Mail waiting on others is a call to act: a pill.
                pill: f == MailFolder.waiting,
                current:
                    !own &&
                    folder == f &&
                    (f != MailFolder.inbox || widget.group == null),
                onTap: onFolder == null ? null : () => onFolder(f),
              ),
            ),
          if (widget._zones(l) case final zones when zones.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final (f, icon, label) in zones)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _NavItem(
                  icon: icon,
                  label: label,
                  count: switch (f) {
                    MailFolder.vault => widget.vault ?? 0,
                    MailFolder.attachments => widget.attachments ?? 0,
                    _ => widget.newsletters ?? 0,
                  },
                  // What is waiting in the Vault is a call to act, as
                  // on the canvas: a pill.
                  pill: f == MailFolder.vault,
                  current: !own && folder == f,
                  onTap: onFolder == null ? null : () => onFolder(f),
                ),
              ),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_separate case final groups when groups.isNotEmpty) ...[
                    SidebarGroups(
                      groups: groups,
                      unread: widget.groupUnread,
                      current: widget.group,
                      onGroup: widget.onGroup,
                      onNewGroup: widget.onNewGroup,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (widget.labels.isNotEmpty) ...[
                    SidebarLabels(
                      labels: widget.labels,
                      current: widget.label,
                      onLabel: widget.onLabel,
                      onNewLabel: widget.onNewLabel,
                    ),
                    const SizedBox(height: 20),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text(
                      l.accounts.toUpperCase(),
                      style: PiumaType.label.copyWith(
                        color: c.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  for (final a in accounts) ..._account(a),
                  _AddAccountItem(onTap: onAddAccount),
                ],
              ),
            ),
          ),
          if (widget.syncedDevices case final n?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: c.ok,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.syncedOnDevices(n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(
                        fontSize: 12,
                        color: c.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const _UpdateLine(),
          _SettingsItem(onTap: onSettings),
        ],
      ),
    );
  }

  /// The groups with their own Inbox in the sidebar.
  List<MailGroup> get _separate => [
    for (final g in widget.groups)
      if (g.separateInbox && g.addresses.isNotEmpty) g,
  ];

  /// An account, and its folders when they are open.
  List<Widget> _account(MailAccount a) {
    final folders = widget.folders[a.id] ?? const <AccountFolder>[];
    final open = folders.isNotEmpty && _open.contains(a.id);
    final onAccount = widget.onAccount;
    final onMailbox = widget.onMailbox;
    final account = widget.account;
    return [
      _AccountItem(
        account: a,
        current: account == a.id && widget.mailbox == null,
        onTap: onAccount == null
            ? null
            : () => onAccount(account == a.id ? null : a.id),
        open: folders.isEmpty ? null : open,
        onOpen: () => setState(
          () => _open.contains(a.id) ? _open.remove(a.id) : _open.add(a.id),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: PiumaEnter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in folders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _FolderItem(
                      folder: f,
                      current: account == a.id && widget.mailbox == f.mailbox,
                      onTap: onMailbox == null || !f.selectable
                          ? null
                          : () => onMailbox(a.id, f.mailbox),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Opens [a]'s own folders beside its dot, when it has some.
  void _railFolders(BuildContext dot, MailAccount a) {
    final folders = widget.folders[a.id] ?? const <AccountFolder>[];
    final box = dot.findRenderObject() as RenderBox?;
    if (folders.isEmpty || box == null) return;
    final at = box.localToGlobal(Offset(Sidebar.railWidth - 4, -12));
    final onMailbox = widget.onMailbox;
    showPiumaPopover<void>(
      dot,
      label: AppLocalizations.of(dot).accountFolders(a.name),
      // Beside the rail, level with the dot.
      anchor: Rect.fromLTWH(at.dx, at.dy, 0, 0),
      width: 240,
      builder: (_) => _RailFolders(
        account: a,
        folders: folders,
        mailbox: widget.account == a.id ? widget.mailbox : null,
        onMailbox: onMailbox == null ? null : (m) => onMailbox(a.id, m),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final folder = widget.folder;
    final onFolder = widget.onFolder;
    final account = widget.account;
    final onAccount = widget.onAccount;
    final own = widget.mailbox != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          _RailItem(
            label: l.search,
            onTap: widget.onSearch,
            border: true,
            child: PiumaIconView(PiumaIcon.search, color: c.muted),
          ),
          const SizedBox(height: 12),
          _RailItem(
            label: l.compose,
            onTap: widget.onCompose,
            fill: c.accent,
            child: PiumaIconView(PiumaIcon.compose, color: c.onAccent),
          ),
          const SizedBox(height: 20),
          for (final (f, icon, label) in [
            ...widget._folders(l),
            ...widget._zones(l),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _RailItem(
                label: label,
                current: !own && folder == f,
                height: 36,
                onTap: onFolder == null ? null : () => onFolder(f),
                child: PiumaIconView(icon, size: 17, color: c.fg),
              ),
            ),
          Container(
            width: 28,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 12),
            color: c.line,
          ),
          for (final a in widget.accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Builder(
                builder: (context) => _RailItem(
                  label: a.name,
                  current: account == a.id,
                  height: 36,
                  onTap: onAccount == null
                      ? null
                      : () {
                          final picked = account != a.id;
                          onAccount(picked ? a.id : null);
                          if (picked) _railFolders(context, a);
                        },
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: a.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          _RailItem(
            label: l.addAccount,
            onTap: widget.onAddAccount,
            height: 36,
            child: PiumaIconView(PiumaIcon.plus, size: 14, color: c.muted),
          ),
          const Spacer(),
          const _UpdateLine(rail: true),
          _RailItem(
            label: l.settings,
            onTap: widget.onSettings,
            height: 36,
            child: PiumaIconView(PiumaIcon.settings, size: 16, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// An account's own folders in a popover beside its dot on the rail
/// (`DetailsToApprove`), as they open under it in the full sidebar.
class _RailFolders extends StatelessWidget {
  const _RailFolders({
    required this.account,
    required this.folders,
    required this.mailbox,
    required this.onMailbox,
  });

  final MailAccount account;
  final List<AccountFolder> folders;

  /// The folder of this account the list shows, if one is.
  final String? mailbox;
  final ValueChanged<String>? onMailbox;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: account.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in folders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _FolderItem(
                      folder: f,
                      indent: 10,
                      current: mailbox == f.mailbox,
                      onTap: onMailbox == null || !f.selectable
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              onMailbox!(f.mailbox);
                            },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One square of the rail: an icon or a dot, named by its tooltip.
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.child,
    this.onTap,
    this.current = false,
    this.height = 40,
    this.border = false,
    this.fill,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool current;
  final double height;
  final bool border;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Tooltip(
      message: label,
      child: Semantics(
        selected: current,
        button: true,
        child: PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            width: 40,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill ?? (current ? c.sel : (border ? c.surface : null)),
              borderRadius: BorderRadius.circular(
                border || fill != null ? PiumaRadius.button : 9,
              ),
              border: border ? Border.all(color: c.line) : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.current,
    this.onTap,
    this.pill = false,
  });

  final PiumaIcon icon;
  final String label;
  final int count;
  final bool current;
  final VoidCallback? onTap;

  /// The count in an accent pill rather than plain.
  final bool pill;

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
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: current ? c.sel : null,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              PiumaIconView(icon, size: 17, color: c.fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: c.fg,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (count > 0 && pill)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: current ? c.surface : c.soft,
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.accentText,
                    ),
                  ),
                )
              else if (count > 0)
                Text('$count', style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountItem extends StatelessWidget {
  const _AccountItem({
    required this.account,
    this.current = false,
    this.onTap,
    this.open,
    this.onOpen,
  });
  final MailAccount account;
  final bool current;
  final VoidCallback? onTap;

  /// Whether its folders show; null when it has none, so no chevron.
  final bool? open;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final item = AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: current ? c.sel : null,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: account.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: c.fg,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                Text(
                  '${account.email} · IMAP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 1.3, color: c.muted),
                ),
              ],
            ),
          ),
          if (open case final isOpen?)
            _Chevron(
              open: isOpen,
              label: AppLocalizations.of(context).accountFolders(account.name),
              onTap: onOpen,
            ),
        ],
      ),
    );
    if (onTap == null) return item;
    return Semantics(
      selected: current,
      button: true,
      child: PiumaPressable(onTap: onTap, child: item),
    );
  }
}

/// Opens or closes an account's folders.
class _Chevron extends StatelessWidget {
  const _Chevron({required this.open, required this.label, this.onTap});
  final bool open;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      container: true,
      expanded: open,
      button: true,
      label: label,
      child: PiumaPressable(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 32,
          child: Center(
            child: AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: instant ? Duration.zero : PiumaMotion.press,
              curve: PiumaMotion.curve,
              child: PiumaIconView(
                PiumaIcon.chevronRight,
                size: 16,
                color: c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of an account's own folders, indented by its depth.
class _FolderItem extends StatelessWidget {
  const _FolderItem({
    required this.folder,
    this.current = false,
    this.onTap,
    this.indent = 30,
  });
  final AccountFolder folder;

  /// Room before a top folder: under its account's name in the sidebar.
  final double indent;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final item = AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      height: 34,
      padding: EdgeInsets.only(left: indent + folder.depth * 18, right: 10),
      decoration: BoxDecoration(
        color: current ? c.sel : null,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          PiumaIconView(PiumaIcon.folder, size: 16, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: folder.selectable ? c.fg : c.muted,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (folder.unread > 0)
            Text(
              '${folder.unread}',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
        ],
      ),
    );
    if (onTap == null) return item;
    return Semantics(
      selected: current,
      button: true,
      child: PiumaPressable(onTap: onTap, child: item),
    );
  }
}

class _AddAccountItem extends StatelessWidget {
  const _AddAccountItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.addAccount,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            PiumaIconView(PiumaIcon.plus, size: 14, color: c.muted),
            const SizedBox(width: 8),
            Text(l.addAccount, style: TextStyle(fontSize: 13, color: c.muted)),
          ],
        ),
      ),
    );
  }
}

/// "Update ready · 0.1.0 (612)" above Settings, in the accent color,
/// once a downloaded update waits (`UpdatesToApprove` section 1); on the
/// rail just its icon. It grows into What's new.
class _UpdateLine extends StatelessWidget {
  const _UpdateLine({this.rail = false});

  final bool rail;

  Future<void> _open(BuildContext context, UpdateRelease release) {
    final box = context.findRenderObject() as RenderBox?;
    final from = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    return showWhatsNew(context, release: release, ready: true, from: from);
  }

  @override
  Widget build(BuildContext context) {
    final updates = Updates.instance;
    if (!updates.available) return const SizedBox.shrink();
    return ValueListenableBuilder<UpdateState>(
      valueListenable: updates.state,
      builder: (context, state, _) {
        if (state is! UpdateReady) return const SizedBox.shrink();
        final c = PiumaTheme.of(context);
        final l = AppLocalizations.of(context);
        final text = l.updateReadyLine(shownVersion(state.release.version));
        if (rail) {
          return Builder(
            builder: (context) => _RailItem(
              label: text,
              onTap: () => _open(context, state.release),
              height: 36,
              child: PiumaIconView(
                PiumaIcon.update,
                size: 16,
                color: c.accentText,
              ),
            ),
          );
        }
        return Builder(
          builder: (context) => PiumaPressable(
            onTap: () => _open(context, state.release),
            semanticLabel: text,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  PiumaIconView(
                    PiumaIcon.update,
                    size: 16,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Settings, at the foot of the sidebar.
class _SettingsItem extends StatelessWidget {
  const _SettingsItem({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.settings,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            PiumaIconView(PiumaIcon.settings, size: 16, color: c.muted),
            const SizedBox(width: 10),
            Text(l.settings, style: TextStyle(fontSize: 14, color: c.muted)),
          ],
        ),
      ),
    );
  }
}

/// "Search…" with its shortcut, above Compose as in `Main`.
class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.search,
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.button),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            PiumaIconView(PiumaIcon.search, color: c.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.search,
                style: PiumaType.body.copyWith(color: c.muted),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                apple ? '⌘K' : 'Ctrl K',
                style: PiumaType.mono.copyWith(fontSize: 12, color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
