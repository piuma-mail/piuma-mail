import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/switch.dart';
import 'settings_screen.dart' show SettingsHeader;

/// Settings › Groups, as on `Groups`: each group folds open to its
/// addresses, its default signature and sending address, and its two
/// switches; under them "Always reply from the address they wrote to" and
/// New group. On the phone the same cards fill the width.
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key, required this.source, this.phone = false});

  final MailSource source;
  final bool phone;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  List<MailGroup>? _groups;
  List<MailSignature> _signatures = const [];
  Map<int, List<String>> _aliases = const {};
  Map<int, List<String>> _hints = const {};
  late bool _replyAsWritten = widget.source.replyAsWritten;

  /// The group folded open; the first one at first.
  int? _open;

  /// A group just made, whose name field takes the focus.
  int? _fresh;

  List<MailAccount> get _accounts => widget.source.accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = widget.source;
    final groups = await source.groups();
    final signatures = await source.signatures();
    final aliases = {
      for (final a in _accounts) a.id: await source.aliases(a.id),
    };
    final hints = {
      for (final a in _accounts) a.id: await source.aliasSuggestions(a.id),
    };
    if (!mounted) return;
    setState(() {
      _open ??= groups.firstOrNull?.id;
      _groups = groups;
      _signatures = signatures;
      _aliases = aliases;
      _hints = hints;
    });
  }

  Future<void> _save(MailGroup g) async {
    setState(() {
      _groups = [
        for (final o in _groups ?? const <MailGroup>[]) o.id == g.id ? g : o,
      ];
    });
    await widget.source.saveGroup(g);
    await _load();
  }

  Future<void> _newGroup() async {
    final l = AppLocalizations.of(context);
    final used = {for (final g in _groups ?? const <MailGroup>[]) g.color};
    final color = PiumaAccountColors.all
        .where((c) => !used.contains(c))
        .followedBy(PiumaAccountColors.all)
        .first;
    final id = await widget.source.saveGroup(
      MailGroup(name: l.groupNewName, color: color),
    );
    _open = id;
    _fresh = id;
    await _load();
  }

  Future<void> _delete(MailGroup g) async {
    final l = AppLocalizations.of(context);
    final yes = await showPiumaDialog<bool>(
      context,
      label: l.groupDeleteAsk(g.name),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.groupDeleteAsk(g.name),
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: PiumaTheme.of(context).fg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.groupDeleteNote,
            style: PiumaType.body.copyWith(color: PiumaTheme.of(context).muted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: 8),
              PiumaButton(
                label: l.groupDelete,
                kind: PiumaButtonKind.danger,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.source.deleteGroup(g.id);
    await _load();
  }

  /// "Add address": a free address of any account, an alias Sent mail
  /// suggests, or a new alias typed in.
  Future<void> _addAddress(MailGroup g, Rect anchor) async {
    final l = AppLocalizations.of(context);
    final mine = {for (final a in g.addresses) a.email.toLowerCase()};
    final grouped = {
      for (final o in _groups ?? const <MailGroup>[])
        for (final a in o.addresses) a.email.toLowerCase(),
    };
    final free = [
      for (final a in _accounts)
        for (final e in [a.email, ...?_aliases[a.id]])
          if (!mine.contains(e.toLowerCase()))
            (GroupAddress(a.id, e), grouped.contains(e.toLowerCase())),
    ];
    final hints = [
      for (final a in _accounts)
        for (final e in _hints[a.id] ?? const <String>[]) GroupAddress(a.id, e),
    ];
    Widget panel(BuildContext context) => _AddAddress(
      accounts: _accounts,
      free: free,
      hints: hints,
      phone: widget.phone,
      onAlias: (accountId, email) async {
        await widget.source.addAlias(accountId, email);
      },
    );
    final picked = widget.phone
        ? await showPiumaSheet<GroupAddress>(
            context,
            label: l.groupAddAddress,
            builder: panel,
          )
        : await showPiumaPopover<GroupAddress>(
            context,
            label: l.groupAddAddress,
            anchor: anchor,
            width: 360,
            builder: panel,
          );
    if (picked == null) {
      await _load();
      return;
    }
    final known = _aliases[picked.accountId] ?? const <String>[];
    final own = _accounts
        .where((a) => a.id == picked.accountId)
        .any((a) => a.email.toLowerCase() == picked.email.toLowerCase());
    if (!own && !known.contains(picked.email.toLowerCase())) {
      await widget.source.addAlias(picked.accountId, picked.email);
    }
    await _save(g.copyWith(addresses: [...g.addresses, picked]));
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final groups = _groups;
    final example = [
      for (final g in groups ?? const <MailGroup>[])
        for (final a in g.addresses)
          if (!_accounts.any((x) => x.email.toLowerCase() == a.email)) a.email,
    ].firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(title: l.groupsTitle, subtitle: l.groupsSubtitle),
        const SizedBox(height: 24),
        if (groups != null && groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              l.groupsNone,
              style: PiumaType.body.copyWith(color: c.muted),
            ),
          ),
        for (final (i, g) in (groups ?? const <MailGroup>[]).indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _GroupCard(
            key: ValueKey(g.id),
            group: g,
            accounts: _accounts,
            aliases: _aliases,
            signatures: _signatures,
            open: _open == g.id,
            fresh: _fresh == g.id,
            phone: widget.phone,
            onToggle: () => setState(() {
              _open = _open == g.id ? null : g.id;
              _fresh = null;
            }),
            onChange: _save,
            onAdd: (anchor) => _addAddress(g, anchor),
            onDelete: () => _delete(g),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              PiumaIconView(PiumaIcon.reply, size: 18, color: c.muted),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.groupReplyAsWritten,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      !_replyAsWritten
                          ? l.groupReplyOff
                          : example != null
                          ? l.groupReplyOn(example)
                          : l.groupReplyOnAny,
                      style: PiumaType.body.copyWith(
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              PiumaSwitch(
                value: _replyAsWritten,
                label: l.groupReplyAsWritten,
                onChanged: (on) {
                  setState(() => _replyAsWritten = on);
                  widget.source.setReplyAsWritten(on);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: _OutlineButton(
            icon: PiumaIcon.plus,
            label: l.groupNew,
            onTap: _newGroup,
          ),
        ),
      ],
    );
  }
}

/// One group: the folded line, and open, everything about it.
class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.accounts,
    required this.aliases,
    required this.signatures,
    required this.open,
    required this.fresh,
    required this.phone,
    required this.onToggle,
    required this.onChange,
    required this.onAdd,
    required this.onDelete,
  });

  final MailGroup group;
  final List<MailAccount> accounts;
  final Map<int, List<String>> aliases;
  final List<MailSignature> signatures;
  final bool open;
  final bool fresh;
  final bool phone;
  final VoidCallback onToggle;
  final ValueChanged<MailGroup> onChange;
  final ValueChanged<Rect> onAdd;
  final VoidCallback onDelete;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late final _name = TextEditingController(text: widget.group.name);
  final _addKey = GlobalKey();
  final _sigKey = GlobalKey();
  final _fromKey = GlobalKey();

  @override
  void didUpdateWidget(_GroupCard old) {
    super.didUpdateWidget(old);
    if (old.group.name != widget.group.name &&
        _name.text.trim() != widget.group.name) {
      _name.text = widget.group.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Rect _rect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _rename() {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.group.name) return;
    widget.onChange(widget.group.copyWith(name: name));
  }

  Future<void> _pickSignature() async {
    final l = AppLocalizations.of(context);
    final g = widget.group;
    final byAccount = {for (final a in widget.accounts) a.id: a};
    final several =
        widget.signatures.map((s) => s.accountId).toSet().length > 1;
    final picked = await showPiumaPopover<int>(
      context,
      label: l.groupDefaultSignature,
      anchor: _rect(_sigKey),
      builder: (context) => _Choices(
        choices: [
          (-1, l.noSignature, g.signatureId == null),
          for (final s in widget.signatures)
            (
              s.id,
              several
                  ? '${s.label} · ${byAccount[s.accountId]?.name ?? ''}'
                  : s.label,
              s.id == g.signatureId,
            ),
        ],
      ),
    );
    if (picked == null) return;
    widget.onChange(g.copyWith(signatureId: () => picked < 0 ? null : picked));
  }

  Future<void> _pickSender() async {
    final l = AppLocalizations.of(context);
    final g = widget.group;
    if (g.addresses.isEmpty) return;
    final current = g.sender?.email;
    final picked = await showPiumaPopover<int>(
      context,
      label: l.groupSendFrom,
      anchor: _rect(_fromKey),
      builder: (context) => _Choices(
        choices: [
          for (final (i, a) in g.addresses.indexed)
            (i, a.email, a.email == current),
        ],
      ),
    );
    if (picked == null) return;
    widget.onChange(g.copyWith(sendFrom: g.addresses[picked].email));
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final g = widget.group;
    final instant = reduceMotion(context);
    final signature = widget.signatures
        .where((s) => s.id == g.signatureId)
        .firstOrNull;
    final sigLabel = signature?.label ?? l.groupNoSignature;
    final from = g.sender?.email ?? '—';
    final small = PiumaType.body.copyWith(fontSize: 13, color: c.muted);
    final byAccount = {for (final a in widget.accounts) a.id: a};

    final head = Semantics(
      button: true,
      expanded: widget.open,
      child: PiumaPressable(
        onTap: widget.onToggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: g.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          g.name,
                          style: PiumaType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.fg,
                          ),
                        ),
                        Text(
                          l.groupAddresses(g.addresses.length),
                          style: small,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 14,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: '${l.groupSignatureShort} ',
                            children: [
                              TextSpan(
                                text: sigLabel,
                                style: TextStyle(color: c.fg),
                              ),
                            ],
                          ),
                          style: small,
                        ),
                        Text.rich(
                          TextSpan(
                            text: '${l.groupSendFromShort} ',
                            children: [
                              TextSpan(
                                text: from,
                                style: TextStyle(color: c.fg),
                              ),
                            ],
                          ),
                          style: small,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              AnimatedRotation(
                turns: widget.open ? 0.5 : 0,
                duration: instant ? Duration.zero : PiumaMotion.move,
                curve: PiumaMotion.curve,
                child: PiumaIconView(
                  PiumaIcon.chevronDown,
                  size: 18,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget select(GlobalKey key, String label, String value, VoidCallback on) =>
        Semantics(
          button: true,
          label: '$label, $value',
          child: ExcludeSemantics(
            child: PiumaPressable(
              key: key,
              onTap: on,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(PiumaRadius.row),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: PiumaType.body.copyWith(
                              fontSize: 12,
                              color: c.muted,
                            ),
                          ),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PiumaType.body.copyWith(
                              fontSize: 14,
                              color: c.fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    PiumaIconView(PiumaIcon.upDown, size: 16, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
        );

    Widget switchRow(
      String title,
      String note,
      bool on,
      ValueChanged<bool> changed, {
      bool top = false,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: top ? Border(top: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PiumaType.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Text(note, style: small),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PiumaSwitch(value: on, label: title, onChanged: changed),
        ],
      ),
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(widget.phone ? 18 : 44, 2, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: l.groupName,
                  textField: true,
                  child: TextField(
                    controller: _name,
                    autofocus: widget.fresh,
                    onSubmitted: (_) => _rename(),
                    onTapOutside: (_) => _rename(),
                    style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
                    cursorColor: c.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PiumaRadius.field),
                        borderSide: BorderSide(color: c.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PiumaRadius.field),
                        borderSide: BorderSide(color: c.accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              for (final color in PiumaAccountColors.all)
                _ColorDot(
                  color: color,
                  selected: color == g.color,
                  label: l.groupColor,
                  onTap: () => widget.onChange(g.copyWith(color: color)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            l.groupAddressesHeading,
            style: PiumaType.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in g.addresses)
                _AddressChip(
                  email: a.email,
                  note: switch (byAccount[a.accountId]) {
                    final acc? when acc.email.toLowerCase() == a.email =>
                      l.groupAccountNote(acc.name),
                    final acc? => l.groupAliasNote(acc.email),
                    null => '',
                  },
                  alias: byAccount[a.accountId]?.email.toLowerCase() != a.email,
                  onRemove: () => widget.onChange(
                    g.copyWith(
                      addresses: [
                        for (final o in g.addresses)
                          if (o != a) o,
                      ],
                    ),
                  ),
                ),
              _DashedButton(
                key: _addKey,
                label: l.groupAddAddress,
                onTap: () => widget.onAdd(_rect(_addKey)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (widget.phone) ...[
            select(_sigKey, l.groupDefaultSignature, sigLabel, _pickSignature),
            const SizedBox(height: 12),
            select(_fromKey, l.groupSendFrom, from, _pickSender),
          ] else
            Row(
              children: [
                Expanded(
                  child: select(
                    _sigKey,
                    l.groupDefaultSignature,
                    sigLabel,
                    _pickSignature,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: select(_fromKey, l.groupSendFrom, from, _pickSender),
                ),
              ],
            ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PiumaRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                switchRow(
                  l.groupSeparateInbox,
                  g.separateInbox ? l.groupSeparateOn : l.groupSeparateOff,
                  g.separateInbox,
                  (on) => widget.onChange(g.copyWith(separateInbox: on)),
                ),
                switchRow(
                  l.notificationsTitle,
                  g.notify ? l.groupNotifyOn : l.groupNotifyOff,
                  g.notify,
                  (on) => widget.onChange(g.copyWith(notify: on)),
                  top: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: PiumaButton(
              label: l.groupDelete,
              kind: PiumaButtonKind.tertiary,
              size: PiumaButtonSize.compact,
              onPressed: widget.onDelete,
            ),
          ),
        ],
      ),
    );

    return AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.theme,
      curve: PiumaMotion.curve,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.open ? c.track : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          AnimatedSize(
            duration: instant ? Duration.zero : PiumaMotion.collapse,
            curve: PiumaMotion.curve,
            alignment: Alignment.topCenter,
            child: widget.open
                ? PiumaEnter(child: body)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// An address in a group: the address, whose it is, and Account or Alias.
class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.email,
    required this.note,
    required this.alias,
    required this.onRemove,
  });

  final String email;
  final String note;
  final bool alias;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(PiumaRadius.pill),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(
                    fontSize: 14,
                    height: 1.25,
                    color: c.fg,
                  ),
                ),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(
                    fontSize: 12,
                    height: 1.25,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: alias ? c.chip : c.soft,
              borderRadius: BorderRadius.circular(PiumaRadius.pill),
            ),
            child: Text(
              alias ? l.groupAlias : l.groupAccount,
              style: PiumaType.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: alias ? c.muted : c.accentText,
              ),
            ),
          ),
          Tooltip(
            message: l.groupRemoveAddress(email),
            child: PiumaPressable(
              onTap: onRemove,
              semanticLabel: l.groupRemoveAddress(email),
              child: SizedBox.square(
                dimension: 28,
                child: Center(
                  child: PiumaIconView(
                    PiumaIcon.close,
                    size: 14,
                    color: c.muted,
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

/// "+ Add address", a dashed pill as tall as the address chips.
class _DashedButton extends StatelessWidget {
  const _DashedButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: CustomPaint(
        painter: _Dashes(c.track),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.plus, size: 15, color: c.muted),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: PiumaType.body.copyWith(fontSize: 14, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  _Dashes(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      Radius.circular(size.height / 2),
    );
    for (final m in (Path()..addRRect(r)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: PiumaPressable(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? c.ring : const Color(0x00000000),
              width: 2,
            ),
          ),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// "New group": a bordered button with its plus.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.button + 1),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(icon, size: 16, color: c.fg),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                label,
                style: PiumaType.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
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

/// A short list of choices, the current one checked; pops its id.
class _Choices extends StatelessWidget {
  const _Choices({required this.choices});
  final List<(int, String, bool)> choices;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (id, label, on) in choices)
            _ChoiceRow(
              label: label,
              selected: on,
              onTap: () => Navigator.of(context).pop(id),
              color: c,
            ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
    this.note,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final PiumaColors color;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Semantics(
      button: true,
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? c.sel : const Color(0x00000000),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: c.fg,
                      ),
                    ),
                    if (note case final n?)
                      Text(
                        n,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(
                          fontSize: 12,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                PiumaIconView(PiumaIcon.check, size: 16, color: c.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

/// What "Add address" offers: free addresses of every account, aliases
/// found in Sent, and a new alias on one of the accounts.
class _AddAddress extends StatefulWidget {
  const _AddAddress({
    required this.accounts,
    required this.free,
    required this.hints,
    required this.phone,
    required this.onAlias,
  });

  final List<MailAccount> accounts;

  /// Addresses not in this group, each with whether another group has it.
  final List<(GroupAddress, bool)> free;
  final List<GroupAddress> hints;
  final bool phone;
  final Future<void> Function(int accountId, String email) onAlias;

  @override
  State<_AddAddress> createState() => _AddAddressState();
}

class _AddAddressState extends State<_AddAddress> {
  final _email = TextEditingController();
  late int _account = widget.accounts.first.id;
  bool _failed = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _addNew() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) return;
    try {
      await widget.onAlias(_account, email);
      if (mounted) Navigator.of(context).pop(GroupAddress(_account, email));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final byId = {for (final a in widget.accounts) a.id: a};
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text(
        text,
        style: PiumaType.body.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: c.muted,
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: widget.phone
            ? const EdgeInsets.symmetric(horizontal: 16)
            : EdgeInsets.zero,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.free.isNotEmpty) heading(l.groupYourAddresses),
              for (final (a, elsewhere) in widget.free)
                _ChoiceRow(
                  label: a.email,
                  note: elsewhere ? l.groupMovesHere : byId[a.accountId]?.name,
                  selected: false,
                  color: c,
                  onTap: () => Navigator.of(context).pop(a),
                ),
              if (widget.hints.isNotEmpty) heading(l.groupFoundInSent),
              for (final a in widget.hints)
                _ChoiceRow(
                  label: a.email,
                  note: l.groupAliasNote(byId[a.accountId]?.email ?? ''),
                  selected: false,
                  color: c,
                  onTap: () => Navigator.of(context).pop(a),
                ),
              heading(l.groupNewAlias),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Semantics(
                  label: l.groupNewAlias,
                  textField: true,
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _addNew(),
                    onChanged: (_) {
                      if (_failed) setState(() => _failed = false);
                    },
                    style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
                    cursorColor: c.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l.groupNewAliasHint,
                      hintStyle: PiumaType.body.copyWith(
                        fontSize: 14,
                        color: c.muted,
                      ),
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PiumaRadius.field),
                        borderSide: BorderSide(color: c.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PiumaRadius.field),
                        borderSide: BorderSide(color: c.accent),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.accounts.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l.groupAliasOn,
                        style: PiumaType.body.copyWith(
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                      for (final a in widget.accounts)
                        Semantics(
                          button: true,
                          selected: a.id == _account,
                          child: PiumaPressable(
                            onTap: () => setState(() => _account = a.id),
                            child: Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: a.id == _account ? c.sel : c.chip,
                                borderRadius: BorderRadius.circular(
                                  PiumaRadius.pill,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: a.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    a.name,
                                    style: PiumaType.body.copyWith(
                                      fontSize: 13,
                                      color: a.id == _account
                                          ? c.accentText
                                          : c.fg,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Text(
                    l.groupAliasInvalid,
                    style: PiumaType.body.copyWith(
                      fontSize: 13,
                      color: c.danger,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PiumaButton(
                    label: l.groupAddAlias,
                    size: PiumaButtonSize.compact,
                    onPressed: _addNew,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
