import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/switch.dart';
import '../widgets/text_field.dart';

/// Settings › Writing past the signatures: the templates, then Replies
/// (above or below the quote, quoting the selected words, plain text by
/// account) and the contact groups typed in To, Cc and Bcc.
class WritingExtras extends StatelessWidget {
  const WritingExtras({
    super.key,
    required this.source,
    required this.templates,
    this.phone = false,
  });

  final MailSource source;
  final Widget templates;
  final bool phone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      templates,
      RepliesSettings(source: source),
      const SizedBox(height: PiumaSpace.s32),
      ContactGroupsSettings(source: source, phone: phone),
    ],
  );
}

/// A small heading over a part of the page, as Templates has under the
/// signatures.
class _PartHeading extends StatelessWidget {
  const _PartHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

/// A bordered group of rows with lines between them, as Settings' cards.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// A title, a line under it and a switch; with [dot], an account's color
/// before them.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.dot,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          if (dot case final color?) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Text(
                  hint,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    height: 1.35,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PiumaSwitch(value: value, label: title, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Replies: where they are written, what they quote, and which accounts
/// write new messages as plain text.
class RepliesSettings extends StatefulWidget {
  const RepliesSettings({super.key, required this.source});

  final MailSource source;

  @override
  State<RepliesSettings> createState() => _RepliesSettingsState();
}

class _RepliesSettingsState extends State<RepliesSettings> {
  ComposeSettings? _settings;

  @override
  void initState() {
    super.initState();
    widget.source.composeSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    }, onError: (Object _) {});
  }

  void _change(ComposeSettings next) {
    setState(() => _settings = next);
    unawaited(widget.source.setComposeSettings(next).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _settings;
    if (s == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: PiumaSpace.s32),
        _PartHeading(l.repliesTitle),
        _Card(
          children: [
            _SwitchRow(
              title: l.replyBelowQuote,
              hint: l.replyBelowQuoteHint,
              value: s.replyBelow,
              onChanged: (on) => _change(s.copyWith(replyBelow: on)),
            ),
            _SwitchRow(
              title: l.quoteSelection,
              hint: l.quoteSelectionHint,
              value: s.quoteSelection,
              onChanged: (on) => _change(s.copyWith(quoteSelection: on)),
            ),
          ],
        ),
        if (widget.source.accounts.isNotEmpty) ...[
          const SizedBox(height: PiumaSpace.s32),
          _PartHeading(l.plainTextTitle),
          _Card(
            children: [
              for (final a in widget.source.accounts)
                _SwitchRow(
                  dot: a.color,
                  title: a.name,
                  hint: s.plainTextFor(a.email)
                      ? l.plainTextOn(a.email)
                      : a.email,
                  value: s.plainTextFor(a.email),
                  onChanged: (on) => _change(
                    s.copyWith(
                      plainTextAccounts: {
                        for (final x in s.plainTextAccounts)
                          if (x != a.email.toLowerCase()) x,
                        if (on) a.email.toLowerCase(),
                      },
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Contact groups, as the templates are kept: the list, New group, and
/// the one picked open under it, saved as it is typed.
class ContactGroupsSettings extends StatefulWidget {
  const ContactGroupsSettings({
    super.key,
    required this.source,
    this.phone = false,
  });

  final MailSource source;
  final bool phone;

  @override
  State<ContactGroupsSettings> createState() => _ContactGroupsSettingsState();
}

class _ContactGroupsSettingsState extends State<ContactGroupsSettings> {
  List<ContactGroup>? _groups;
  String? _open;
  final _name = TextEditingController();
  final _addresses = TextEditingController();
  Timer? _saveTimer;
  bool _filling = false;

  static const _saveDelay = Duration(milliseconds: 500);

  ContactGroup? get _current =>
      _groups?.where((g) => g.uid == _open).firstOrNull;

  @override
  void initState() {
    super.initState();
    _name.addListener(_typed);
    _addresses.addListener(_typed);
    _load();
  }

  @override
  void dispose() {
    _flush();
    _name.dispose();
    _addresses.dispose();
    super.dispose();
  }

  Future<void> _load({String? open}) async {
    List<ContactGroup> groups;
    try {
      groups = await widget.source.contactGroups();
    } catch (_) {
      groups = const [];
    }
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _pick(open ?? _open);
    });
  }

  void _pick(String? uid) {
    _flush();
    _open = uid;
    final g = _current;
    _filling = true;
    _name.text = g?.name ?? '';
    _addresses.text = g?.addresses.join('\n') ?? '';
    _filling = false;
  }

  List<String> get _typedAddresses => [
    for (final a in _addresses.text.split(RegExp(r'[\n,;]')))
      if (a.trim().isNotEmpty) a.trim(),
  ];

  void _typed() {
    final g = _current;
    if (_filling || g == null) return;
    final edited = g.copyWith(name: _name.text, addresses: _typedAddresses);
    setState(() {
      _groups = [for (final x in _groups!) x.uid == g.uid ? edited : x];
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveNow);
  }

  void _flush() {
    if (!(_saveTimer?.isActive ?? false)) return;
    _saveTimer!.cancel();
    _saveNow();
  }

  void _saveNow() {
    final g = _current;
    if (g == null) return;
    unawaited(widget.source.saveContactGroup(g).catchError((_) => ''));
  }

  Future<void> _new() async {
    final l = AppLocalizations.of(context);
    _flush();
    try {
      final uid = await widget.source.saveContactGroup(
        ContactGroup(name: l.contactGroupUntitled),
      );
      await _load(open: uid);
    } catch (_) {
      // Nothing was added.
    }
  }

  Future<void> _delete(ContactGroup g) async {
    _saveTimer?.cancel();
    try {
      await widget.source.deleteContactGroup(g.uid);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _open = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final groups = _groups;
    final current = _current;
    if (groups == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PartHeading(l.contactGroupsTitle),
        Text(
          l.contactGroupsHint,
          style: PiumaType.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final g in groups)
                _GroupRow(
                  group: g,
                  open: g.uid == _open,
                  phone: widget.phone,
                  onTap: () => setState(() => _pick(g.uid)),
                ),
              PiumaPressable(
                onTap: _new,
                semanticLabel: l.contactGroupNew,
                child: Container(
                  height: widget.phone ? 52 : 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Text(
                      l.contactGroupNew,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 20),
          PiumaTextField(
            key: ValueKey('group-name-${current.uid}'),
            label: l.contactGroupName,
            controller: _name,
          ),
          const SizedBox(height: 14),
          _AddressesBox(
            key: ValueKey('group-addresses-${current.uid}'),
            label: l.contactGroupAddresses,
            hint: l.contactGroupAddressesHint,
            controller: _addresses,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.templateSavedAsYouType,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ),
              PiumaPressable(
                onTap: () => _delete(current),
                semanticLabel: l.contactGroupDelete(current.name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      l.actionDelete,
                      style: PiumaType.body.copyWith(color: c.danger),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }
}

/// One group in the list: its name, and how many addresses it has.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.open,
    required this.phone,
    required this.onTap,
  });

  final ContactGroup group;
  final bool open;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final count = l.contactGroupCount(group.addresses.length);
    final instant = reduceMotion(context);
    return Semantics(
      selected: open,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: '${group.name}, $count',
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: phone ? 14 : 12,
          ),
          decoration: BoxDecoration(
            color: open ? c.soft : c.soft.withValues(alpha: 0),
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                  ),
                ),
                Text(
                  count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The addresses of a group, one per line, bordered like
/// [PiumaTextField], with a line under it on how to write them.
class _AddressesBox extends StatefulWidget {
  const _AddressesBox({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
  });

  final String label;
  final String hint;
  final TextEditingController controller;

  @override
  State<_AddressesBox> createState() => _AddressesBoxState();
}

class _AddressesBoxState extends State<_AddressesBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            border: Border.all(color: _focus.hasFocus ? c.accent : c.line),
          ),
          child: Semantics(
            label: widget.label,
            hint: widget.hint,
            textField: true,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              minLines: 3,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              cursorColor: c.accent,
              style: PiumaType.body.copyWith(height: 1.5, color: c.fg),
              decoration: const InputDecoration.collapsed(hintText: null),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(widget.hint, style: PiumaType.small.copyWith(color: c.muted)),
      ],
    );
  }
}
