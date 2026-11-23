import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/text_field.dart';
import '../widgets/bidi.dart';

/// The pieces of managing the mailbox that several screens share: the
/// questions asked before what can't be undone (deleting for good,
/// emptying Trash or spam, deleting a folder), renaming a folder, rows
/// dragged onto a folder, and which folder does which job. Built from the
/// existing dialog, sheet, button and field components.

/// A question before something that can't be undone: [title], [note]
/// under it, Cancel and [confirm] in danger red. A sheet on the phone, a
/// dialog elsewhere. True when confirmed. Without [confirm] it only says
/// why something can't be done, with Close.
Future<bool> askToConfirm(
  BuildContext context, {
  required String title,
  required String note,
  String? confirm,
  bool phone = false,
}) async {
  final c = PiumaTheme.of(context);
  final l = AppLocalizations.of(context);
  Widget panel(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s8),
        Text(note, style: PiumaType.body.copyWith(color: c.muted)),
        const SizedBox(height: 20),
        // Full width, so the buttons sit at the end.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [
              if (confirm == null)
                PiumaButton(
                  label: l.close,
                  kind: PiumaButtonKind.secondary,
                  onPressed: () => Navigator.of(context).pop(false),
                )
              else ...[
                PiumaButton(
                  label: l.cancel,
                  kind: PiumaButtonKind.tertiary,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                PiumaButton(
                  label: confirm,
                  kind: PiumaButtonKind.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  final yes = phone
      ? await showPiumaSheet<bool>(context, label: title, builder: panel)
      : await showPiumaDialog<bool>(context, label: title, builder: panel);
  return yes ?? false;
}

/// "Delete for good?" for [count] emails in Trash or spam.
Future<bool> confirmDeleteForever(
  BuildContext context, {
  required int count,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  return askToConfirm(
    context,
    title: l.deleteForeverTitle(count),
    note: l.deleteForeverNote,
    confirm: l.deleteForever,
    phone: phone,
  );
}

/// "Empty Trash" or "Empty spam": how many go, then Empty.
Future<bool> confirmEmpty(
  BuildContext context, {
  required String folder,
  required int count,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  return askToConfirm(
    context,
    title: l.emptyTitle(count, bidiArg(context, folder)),
    note: l.deleteForeverNote,
    confirm: l.emptyConfirm,
    phone: phone,
  );
}

/// "Delete “Clients”?": where its emails go, whether its subfolders go
/// too, and that the folder can't come back. A folder that holds the
/// inbox or a folder with a job ([protected]) is not deleted: that is
/// said instead, and this returns false.
Future<bool> confirmDeleteFolder(
  BuildContext context, {
  required String name,
  required int emails,
  required int subfolders,
  String? protected,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  if (protected != null) {
    return askToConfirm(
      context,
      title: l.folderDeleteTitle(bidiArg(context, name)),
      note: l.folderDeleteProtected(bidiArg(context, name), protected),
      phone: phone,
    ).then((_) => false);
  }
  return askToConfirm(
    context,
    title: l.folderDeleteTitle(bidiArg(context, name)),
    note: [
      l.folderDeleteEmails(emails),
      if (subfolders > 0) l.folderDeleteSubfolders(subfolders),
      l.folderDeleteEnd,
    ].join(' '),
    confirm: l.folderDelete,
    phone: phone,
  );
}

/// "Rename “Clients”": the name in a field, Rename. Returns the new name,
/// or null when nothing changed.
Future<String?> askFolderName(
  BuildContext context, {
  required String name,
  bool phone = false,
}) {
  final title = AppLocalizations.of(context).folderRenameTitle(name);
  // The field is a Material text field: it needs a Material under it.
  Widget panel(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: _FolderName(name: name, title: title, phone: phone),
  );
  return phone
      ? showPiumaSheet<String>(context, label: title, builder: panel)
      : showPiumaDialog<String>(context, label: title, builder: panel);
}

/// The panel of [askFolderName], which keeps its field.
class _FolderName extends StatefulWidget {
  const _FolderName({
    required this.name,
    required this.title,
    required this.phone,
  });

  final String name;
  final String title;
  final bool phone;

  @override
  State<_FolderName> createState() => _FolderNameState();
}

class _FolderNameState extends State<_FolderName> {
  late final _field = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _done() {
    final text = _field.text.trim();
    Navigator.of(context)
        .pop(text.isEmpty || text == widget.name ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.phone ? 20 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.title,
              style: PiumaType.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          ),
          const SizedBox(height: PiumaSpace.s16),
          PiumaTextField(
            label: l.folderNewName,
            controller: _field,
            autofocus: true,
            onSubmitted: (_) => _done(),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: PiumaSpace.s8,
            runSpacing: PiumaSpace.s8,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              PiumaButton(label: l.folderRename, onPressed: _done),
            ],
          ),
        ],
      ),
    );
  }
}

/// Emails dragged from the list onto a folder of the sidebar.
class MailDrag {
  const MailDrag(this.rows);
  final List<MailRow> rows;

  /// The one account they all belong to; null when they are of several,
  /// which no single folder can take.
  int? get account {
    final ids = {for (final r in rows) r.accountId};
    return ids.length == 1 ? ids.single : null;
  }
}

/// A desktop row that can be dragged onto a folder of the sidebar: a
/// small chip saying how many emails follows the pointer.
class DraggableRows extends StatelessWidget {
  const DraggableRows({super.key, required this.rows, required this.child});

  /// What the drag carries, read when it starts: the picked rows when
  /// the row is one of them.
  final List<MailRow> Function() rows;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Builder(
      builder: (context) {
        final carried = rows();
        return _PointerDraggable<MailDrag>(
          data: MailDrag(carried),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            type: MaterialType.transparency,
            child: Container(
              margin: const EdgeInsetsDirectional.only(start: 14, top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
                border: Border.all(color: c.line),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: 0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(PiumaIcon.mail, size: 14, color: c.muted),
                  const SizedBox(width: 8),
                  Text(
                    l.draggedEmails(carried.length),
                    style: PiumaType.small.copyWith(color: c.fg),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.5, child: child),
          child: child,
        );
      },
    );
  }
}

/// A [Draggable] that a mouse or trackpad starts: a finger on a touch
/// screen keeps scrolling the list under it.
class _PointerDraggable<T extends Object> extends Draggable<T> {
  const _PointerDraggable({
    required super.data,
    required super.feedback,
    required super.child,
    super.childWhenDragging,
    super.dragAnchorStrategy,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    },
  )..onStart = onStart;
}

/// A folder of the sidebar that takes emails dragged onto it: [builder]
/// draws it, told whether a drag it would take is over it.
class FolderDropTarget extends StatelessWidget {
  const FolderDropTarget({
    super.key,
    required this.account,
    required this.mailbox,
    required this.onDrop,
    required this.builder,
  });

  final int account;
  final String mailbox;
  final void Function(List<MailRow> rows) onDrop;
  final Widget Function(BuildContext context, bool over) builder;

  @override
  Widget build(BuildContext context) => DragTarget<MailDrag>(
    // Only the account's own emails, and not into where they already are.
    onWillAcceptWithDetails: (d) =>
        d.data.account == account &&
        d.data.rows.any((r) => r.mailbox != mailbox),
    onAcceptWithDetails: (d) => onDrop([
      for (final r in d.data.rows)
        if (r.mailbox != mailbox) r,
    ]),
    builder: (context, candidates, _) =>
        builder(context, candidates.isNotEmpty),
  );
}

/// "Special folders" of one account: Sent, Drafts, Trash, spam and
/// Archive, each with the folder doing it and a menu to pick another
/// (or go back to what the server says).
Future<void> showSpecialFolders(
  BuildContext context, {
  required MailSource source,
  required MailAccount account,
  bool phone = false,
}) {
  final l = AppLocalizations.of(context);
  final title = l.specialFoldersOf(bidiArg(context, account.name));
  Widget panel(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: phone ? 20 : 0),
    child: SpecialFolders(source: source, account: account, phone: phone),
  );
  return phone
      ? showPiumaSheet<void>(context, label: title, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: title,
          width: 460,
          builder: panel,
        );
}

/// The rows of [showSpecialFolders].
class SpecialFolders extends StatefulWidget {
  const SpecialFolders({
    super.key,
    required this.source,
    required this.account,
    this.phone = false,
  });

  final MailSource source;
  final MailAccount account;

  /// On the phone, what can't be done is said in a sheet.
  final bool phone;

  @override
  State<SpecialFolders> createState() => _SpecialFoldersState();
}

class _SpecialFoldersState extends State<SpecialFolders> {
  late List<SpecialFolder> _roles = widget.source.specialFolders(
    widget.account.id,
  );

  String _roleName(AppLocalizations l, SpecialRole role) => switch (role) {
    SpecialRole.sent => l.folderSent,
    SpecialRole.drafts => l.folderDrafts,
    SpecialRole.trash => l.trashFolder,
    SpecialRole.junk => l.spamFolder,
    SpecialRole.archive => l.folderArchive,
  };

  Future<void> _pick(BuildContext button, SpecialFolder role) async {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final box = button.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    // Never the inbox, nor a folder whose other job would delete mail.
    final folders = widget.source.specialFolderOptions(
      widget.account.id,
      role.role,
    );
    // Null: back to the server's; a record: that folder.
    final picked = await showPiumaPopover<({String? mailbox})>(
      button,
      label: _roleName(l, role.role),
      anchor: at,
      width: 280,
      builder: (menu) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (mailbox, name) in [
                (null, l.specialAutomatic),
                for (final f in folders) (f.mailbox, f.name),
              ])
                PiumaPressable(
                  onTap: () => Navigator.of(menu).pop((mailbox: mailbox)),
                  semanticLabel: name,
                  child: ExcludeSemantics(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: PiumaType.body.copyWith(
                                fontSize: 14,
                                color: mailbox == null ? c.muted : c.fg,
                              ),
                            ),
                          ),
                          if ((mailbox == null && !role.chosen) ||
                              (mailbox != null &&
                                  role.chosen &&
                                  mailbox == role.mailbox))
                            PiumaIconView(
                              PiumaIcon.check,
                              size: 14,
                              color: c.accentText,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.source.setSpecialFolder(
        widget.account.id,
        role.role,
        picked.mailbox,
      );
    } catch (_) {
      if (mounted) {
        await askToConfirm(
          context,
          title: _roleName(l, role.role),
          note: l.specialRefused,
          phone: widget.phone,
        );
      }
    }
    if (mounted) {
      setState(() => _roles = widget.source.specialFolders(widget.account.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final names = {
      for (final f in widget.source.serverFolders(widget.account.id))
        f.mailbox: f.name,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.specialFoldersOf(bidiArg(context, widget.account.name)),
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: PiumaSpace.s8),
        Text(
          l.specialFoldersNote,
          style: PiumaType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s16),
        for (final role in _roles)
          Builder(
            builder: (button) {
              final shown = role.mailbox == null
                  ? l.specialNone
                  : names[role.mailbox] ?? role.mailbox!;
              return PiumaPressable(
                onTap: () => _pick(button, role),
                semanticLabel: '${_roleName(l, role.role)}: $shown',
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 46),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _roleName(l, role.role),
                          style: PiumaType.body.copyWith(color: c.fg),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                shown,
                                textAlign: TextAlign.end,
                                style: PiumaType.body.copyWith(
                                  color: role.mailbox == null ? c.muted : c.fg,
                                ),
                              ),
                              if (role.chosen)
                                Text(
                                  l.specialChosen,
                                  style: PiumaType.small.copyWith(
                                    color: c.accentText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        PiumaIconView(
                          PiumaIcon.chevronDown,
                          size: 14,
                          color: c.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// A folder's line in the sidebar, with an arrow to open or close its
/// subfolders when it has some.
class FolderChevron extends StatelessWidget {
  const FolderChevron({
    super.key,
    required this.open,
    required this.name,
    required this.onTap,
  });

  final bool open;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: open
          ? l.folderCollapse(bidiArg(context, name))
          : l.folderExpand(bidiArg(context, name)),
      child: SizedBox.square(
        dimension: 24,
        child: Center(
          child: AnimatedRotation(
            turns: open ? 0 : -0.25,
            duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            child: PiumaIconView(
              PiumaIcon.chevronDown,
              size: 13,
              color: c.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The folders of [list] the sidebar shows: the subscribed ones, hidden
/// ones only with [hidden] (or holding one that shows, or [keep]), and
/// none under a folder in [closed].
List<AccountFolder> shownFolders(
  List<AccountFolder> list, {
  bool hidden = false,
  Set<String> closed = const {},
  String? keep,
}) {
  final visible = <bool>[
    for (final f in list) hidden || f.subscribed || f.mailbox == keep,
  ];
  // A hidden folder that holds a shown one shows, as its parent.
  for (var i = list.length - 1; i >= 0; i--) {
    if (!visible[i]) continue;
    final depth = list[i].depth;
    for (var j = i - 1; j >= 0 && depth > 0; j--) {
      if (list[j].depth < depth) {
        visible[j] = true;
        break;
      }
    }
  }
  final out = <AccountFolder>[];
  int? under;
  for (final (i, f) in list.indexed) {
    if (under != null && f.depth > under) continue;
    under = null;
    if (!visible[i]) continue;
    out.add(f);
    if (closed.contains(f.mailbox)) under = f.depth;
  }
  return out;
}

/// Whether [list] has folders inside the one at [i].
bool hasSubfolders(List<AccountFolder> list, int i) =>
    i + 1 < list.length && list[i + 1].depth > list[i].depth;

/// Lines of a phone sheet, an icon and words each: what [onPick] gets is
/// the index of the line tapped.
class PhoneActionList extends StatelessWidget {
  const PhoneActionList({super.key, required this.items, required this.onPick});

  final List<(PiumaIcon, String)> items;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (icon, label)) in items.indexed)
          PiumaPressable(
            onTap: () => onPick(i),
            semanticLabel: label,
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    PiumaIconView(icon, size: 18, color: c.fg),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: PiumaType.body.copyWith(
                          fontSize: 16,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// An account's folders on the phone, as the desktop's sidebar has them:
/// a tree whose folders open and close, hidden folders on demand. A tap
/// on a folder returns it.
class PhoneFolderTree extends StatefulWidget {
  const PhoneFolderTree({
    super.key,
    required this.account,
    required this.folders,
    this.current,
  });

  final MailAccount account;
  final List<AccountFolder> folders;

  /// The folder the list shows, kept in sight.
  final String? current;

  @override
  State<PhoneFolderTree> createState() => _PhoneFolderTreeState();
}

class _PhoneFolderTreeState extends State<PhoneFolderTree> {
  final _closed = <String>{};
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final all = widget.folders;
    final shown = shownFolders(
      all,
      hidden: _hidden,
      closed: _closed,
      keep: widget.current,
    );
    final hidden = all.where((f) => !f.subscribed).length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Semantics(
              header: true,
              child: Text(
                l.accountFolders(bidiArg(context, widget.account.name)),
                style: PiumaType.body.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final f in shown)
                    _line(context, f, hasSubfolders(all, all.indexOf(f))),
                  if (hidden > 0)
                    PiumaPressable(
                      onTap: () => setState(() => _hidden = !_hidden),
                      semanticLabel: _hidden
                          ? l.hiddenFoldersHide
                          : l.hiddenFoldersShow(hidden),
                      child: ExcludeSemantics(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            _hidden
                                ? l.hiddenFoldersHide
                                : l.hiddenFoldersShow(hidden),
                            style: PiumaType.body.copyWith(color: c.accentText),
                          ),
                        ),
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

  Widget _line(BuildContext context, AccountFolder f, bool parent) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final current = f.mailbox == widget.current;
    final open = !_closed.contains(f.mailbox);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsetsDirectional.only(start: 12.0 + f.depth * 20, end: 24),
      color: current ? c.sel : null,
      child: Row(
        children: [
          if (parent)
            FolderChevron(
              open: open,
              name: f.name,
              onTap: () => setState(
                () => open ? _closed.add(f.mailbox) : _closed.remove(f.mailbox),
              ),
            )
          else
            const SizedBox(width: 24),
          const SizedBox(width: 6),
          PiumaIconView(PiumaIcon.folder, size: 18, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              safeBidi(f.name),
              style: PiumaType.body.copyWith(
                fontSize: 16,
                color: f.selectable ? c.fg : c.muted,
                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (!f.subscribed)
            Text(
              l.folderHidden,
              style: PiumaType.small.copyWith(color: c.muted),
            )
          else if (f.unread > 0)
            Text(
              '${f.unread}',
              style: PiumaType.small.copyWith(color: c.muted),
            ),
        ],
      ),
    );
    if (!f.selectable) return row;
    return Semantics(
      button: true,
      selected: current,
      child: PiumaPressable(
        onTap: () => Navigator.of(context).pop(f),
        semanticLabel: f.name,
        child: row,
      ),
    );
  }
}
