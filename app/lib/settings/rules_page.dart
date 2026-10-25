import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/labels.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/switch.dart';
import '../widgets/route.dart';
import 'settings_screen.dart' show PhoneBack, SettingsHeader;
import 'sync_page.dart' show syncAgo;

/// Settings › Rules & folders, as in `Rules` (desktop) and `RulesPhone`:
/// rules that read like sentences, each with its switch, the sentence
/// editor, and every account's own folders. On the phone the editor is a
/// sheet.
class RulesPage extends StatefulWidget {
  const RulesPage({
    super.key,
    required this.source,
    this.phone = false,
    this.now = DateTime.now,
    this.zones,
  });

  final MailSource source;
  final bool phone;
  final DateTime Function() now;

  /// Settings › Organizing: the zone switches, above the rules. Without
  /// them the page is Rules & folders alone.
  final Widget? zones;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  List<MailRule>? _rules;
  Map<int, List<AccountFolder>> _folders = const {};

  /// Every label, for the Label action and the labels card.
  List<MailLabel> _labels = const [];

  /// The built-in rule: read newsletters a week old leave for Archive.
  bool? _archiveNewsletters;

  /// The nightly one: newsletters unopened for 30 days, and how many it
  /// archived.
  ({bool on, int archived})? _unopened;

  /// The rule open in the editor on the desktop; null when it is closed.
  MailRule? _editing;

  /// The rule just saved, outlined in the list.
  int? _fresh;

  /// "You often move emails from…": the rule the engine suggests.
  RuleSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _load();
    _loadSuggestion();
  }

  Future<void> _load() async {
    try {
      final rules = await widget.source.rules();
      final archive = await widget.source.archiveReadNewsletters();
      final unopened = await widget.source.unopenedNewsletters();
      final folders = {
        for (final a in widget.source.accounts)
          a.id: await widget.source.folders(a.id),
      };
      final labels = await widget.source.labels();
      if (!mounted) return;
      setState(() {
        _labels = labels;
        _rules = rules;
        _folders = folders;
        _archiveNewsletters = archive;
        _unopened = unopened;
      });
    } catch (_) {
      if (mounted) setState(() => _rules = const []);
    }
  }

  Future<void> _loadSuggestion() async {
    try {
      final suggestion = await widget.source.ruleSuggestion();
      if (mounted) setState(() => _suggestion = suggestion);
    } catch (_) {
      // No suggestion is no loss.
    }
  }

  /// Create: the suggested rule, saved as it reads, outlined in the list.
  Future<void> _takeSuggestion(RuleSuggestion s) async {
    setState(() => _suggestion = null);
    final id = await widget.source.saveRule(s.rule);
    if (mounted) _done(id);
  }

  Future<void> _dismissSuggestion(RuleSuggestion s) async {
    setState(() => _suggestion = null);
    await widget.source.dismissRuleSuggestion(s);
  }

  Future<void> _open(MailRule rule) async {
    if (!widget.phone) {
      setState(() => _editing = rule);
      return;
    }
    final l = AppLocalizations.of(context);
    await showPiumaSheet<void>(
      context,
      label: rule.id == 0 ? l.rulesNew : l.rulesEdit,
      builder: (context) => RuleEditor(
        source: widget.source,
        initial: rule,
        folders: _folders,
        labels: _labels,
        phone: true,
        onDone: (saved) {
          Navigator.of(context).pop();
          _done(saved);
        },
      ),
    );
  }

  void _done(int? saved) {
    setState(() {
      _editing = null;
      _fresh = saved;
    });
    _load();
  }

  Future<void> _toggle(MailRule rule, bool on) async {
    setState(() {
      _rules = [
        for (final r in _rules ?? const <MailRule>[])
          r.id == rule.id ? r.copyWith(enabled: on) : r,
      ];
    });
    await widget.source.setRuleEnabled(rule.id, on);
  }

  Future<void> _toggleNewsletters(bool on) async {
    setState(() => _archiveNewsletters = on);
    await widget.source.setArchiveReadNewsletters(on);
  }

  Future<void> _toggleUnopened(bool on) async {
    setState(() => _unopened = (on: on, archived: _unopened?.archived ?? 0));
    await widget.source.setUnopenedNewsletters(on);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final rules = _rules;
    final editing = _editing;
    final sync = widget.source.syncState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.zones == null)
          SettingsHeader(title: l.rulesTitle, subtitle: l.rulesSubtitle)
        else
          SettingsHeader(
            title: l.organizingTitle,
            subtitle: l.organizingSubtitle,
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            PiumaIconView(
              sync.on ? PiumaIcon.sync : PiumaIcon.phone,
              size: 14,
              color: c.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(switch ((sync.on, sync.syncedAt)) {
                (false, _) => l.rulesWhere,
                (true, null) => l.rulesWhereSynced,
                (true, final at?) => l.rulesWhereSyncedAt(
                  syncAgo(l, at, widget.now()),
                ),
              }, style: PiumaType.small.copyWith(color: c.muted)),
            ),
          ],
        ),
        if (widget.zones case final zones?) ...[
          const SizedBox(height: 28),
          zones,
        ],
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: l.rulesHeading,
                    children: [
                      if (rules != null && rules.isNotEmpty)
                        TextSpan(
                          text: '  ${rules.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: c.muted,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.34,
                    color: c.fg,
                  ),
                ),
              ),
            ),
            PiumaButton(
              label: l.rulesNew,
              size: widget.phone
                  ? PiumaButtonSize.touch
                  : PiumaButtonSize.standard,
              onPressed: rules == null || editing != null
                  ? null
                  : () => _open(const MailRule()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSize(
          duration: reduceMotion(context)
              ? Duration.zero
              : PiumaMotion.collapse,
          curve: PiumaMotion.curve,
          alignment: Alignment.topCenter,
          child: switch (_suggestion) {
            final s? when editing == null && rules != null => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Suggestion(
                suggestion: s,
                folder: _folderName(s.rule),
                phone: widget.phone,
                onCreate: () => _takeSuggestion(s),
                onNotNow: () => _dismissSuggestion(s),
              ),
            ),
            _ => const SizedBox(width: double.infinity),
          },
        ),
        if (editing != null) ...[
          RuleEditor(
            key: ValueKey(editing.id),
            source: widget.source,
            initial: editing,
            folders: _folders,
            labels: _labels,
            onDone: _done,
          ),
          const SizedBox(height: 12),
        ],
        if (rules != null && rules.isEmpty && editing == null)
          Text(l.rulesNone, style: PiumaType.body.copyWith(color: c.muted)),
        if (rules != null)
          for (final (i, r) in rules.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            _RuleCard(
              pieces: ruleSentence(l, r, _folderName(r)),
              enabled: r.enabled,
              meta: _meta(context, r),
              fresh: r.id == _fresh,
              editing: r.id == editing?.id,
              onTap: editing == null ? () => _open(r) : null,
              onToggle: (on) => _toggle(r, on),
            ),
          ],
        if (_archiveNewsletters case final on?) ...[
          const SizedBox(height: 10),
          _RuleCard(
            pieces: [
              (l.ruleNewsletters, false),
              ('  →  ', false),
              (l.ruleDoArchive, true),
            ],
            enabled: on,
            meta: l.ruleBuiltIn,
            fresh: false,
            editing: false,
            onTap: null,
            onToggle: _toggleNewsletters,
          ),
        ],
        if (_unopened case final u?) ...[
          const SizedBox(height: 10),
          _RuleCard(
            pieces: [
              (l.ruleUnopenedNewsletters, true),
              (l.ruleUnopenedFor, false),
              (l.ruleUnopenedDays, true),
              ('  →  ', false),
              (l.ruleDoArchive, true),
            ],
            enabled: u.on,
            meta: l.ruleNightly(u.archived),
            fresh: false,
            editing: false,
            onTap: null,
            onToggle: _toggleUnopened,
          ),
        ],
        if (widget.phone) ...[
          const SizedBox(height: 16),
          _FoldersRow(
            folders: _folders.values.fold(0, (n, f) => n + f.length),
            labels: _labels.length,
            onTap: _openFolders,
          ),
        ] else ...[
          const SizedBox(height: 40),
          FoldersAndLabels(
            source: widget.source,
            folders: _folders,
            labels: _labels,
            onChanged: _load,
          ),
        ],
      ],
    );
  }

  /// The phone's "Folders & labels" row: the same list on its own page,
  /// with "‹ Rules & folders" back.
  Future<void> _openFolders() async {
    final l = AppLocalizations.of(context);
    await Navigator.of(context).push(
      PiumaRoute.of<void>(context, (context) {
        final c = PiumaTheme.of(context);
        return Scaffold(
          backgroundColor: c.surface,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhoneBack(
                  label: widget.zones == null
                      ? l.rulesTitle
                      : l.organizingTitle,
                  onTap: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    child: FoldersAndLabels(
                      source: widget.source,
                      folders: _folders,
                      labels: _labels,
                      onChanged: _load,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    _load();
  }

  String _folderName(MailRule r) {
    if (r.action == RuleAction.label) {
      return _labels.where((x) => x.keyword == r.target).firstOrNull?.name ??
          r.target;
    }
    if (r.action != RuleAction.moveTo) return '';
    final folder = (_folders[r.accountId] ?? const <AccountFolder>[])
        .where((f) => f.mailbox == r.target)
        .firstOrNull;
    return folder?.name ?? r.target.split('/').last;
  }

  String _meta(BuildContext context, MailRule r) {
    final l = AppLocalizations.of(context);
    if (!r.enabled) return l.rulePaused;
    final account = widget.source.accounts
        .where((a) => a.id == r.accountId)
        .firstOrNull;
    final parts = [
      ?account?.name,
      if (r.matched == 0) l.ruleFresh else l.ruleSorted(r.matched),
      if (r.lastRun case final at? when r.matched > 0) _last(context, at),
    ];
    return parts.join(' · ');
  }

  String _last(BuildContext context, DateTime at) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = widget.now();
    if (DateUtils.isSameDay(at, now)) {
      return l.ruleLastToday(DateFormat('H:mm', locale).format(at));
    }
    return l.ruleLastOn(DateFormat.MMMd(locale).format(at));
  }
}

/// How a rule's sentence reads, piece by piece: plain words, and the
/// person's own words and folders as chips.
List<(String, bool)> ruleSentence(
  AppLocalizations l,
  MailRule r,
  String target,
) => [
  ('${l.ruleWhen} ${_field(l, r.field)} ${_op(l, r.op)} ', false),
  (r.value.trim(), true),
  ('  →  ', false),
  if (r.action == RuleAction.moveTo) ...[
    ('${l.ruleDoMove} ', false),
    (target, true),
  ] else if (r.action == RuleAction.label) ...[
    ('${l.ruleDoLabel} ', false),
    (target, true),
  ] else if (r.action == RuleAction.vault) ...[
    ('${l.ruleDoMove} ', false),
    (l.folderVault, true),
  ] else
    (_action(l, r.action), true),
];

String _field(AppLocalizations l, RuleField f) => switch (f) {
  RuleField.sender => l.ruleFieldSender,
  RuleField.subject => l.ruleFieldSubject,
  RuleField.recipient => l.ruleFieldRecipient,
  RuleField.body => l.ruleFieldBody,
};

String _op(AppLocalizations l, RuleOp o) => switch (o) {
  RuleOp.contains => l.ruleOpContains,
  RuleOp.exactly => l.ruleOpIs,
  RuleOp.startsWith => l.ruleOpStarts,
  RuleOp.notContains => l.ruleOpNotContains,
};

/// Whether two actions are one choice: the Vault is a "move to".
bool _same(RuleAction a, RuleAction b) =>
    a == b || {a, b}.containsAll({RuleAction.moveTo, RuleAction.vault});

String _action(AppLocalizations l, RuleAction a) => switch (a) {
  RuleAction.moveTo || RuleAction.vault => l.ruleDoMove,
  RuleAction.archive => l.ruleDoArchive,
  RuleAction.markRead => l.ruleDoRead,
  RuleAction.label => l.ruleDoLabel,
};

/// The suggested rule, in a dashed card above the rules, as on `Rules`
/// and `RulesPhone`: what the person keeps doing by hand, Create and
/// Not now. The phone has no count line and wide buttons.
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.suggestion,
    required this.folder,
    required this.phone,
    required this.onCreate,
    required this.onNotNow,
  });

  final RuleSuggestion suggestion;
  final String folder;
  final bool phone;
  final VoidCallback onCreate;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = suggestion.name.trim().isEmpty
        ? suggestion.sender
        : suggestion.name.trim();
    final words = l.ruleSuggest('\u0000', folder).split('\u0000');
    final size = phone ? PiumaButtonSize.touch : PiumaButtonSize.compact;
    Widget button(PiumaButton b) => phone ? Expanded(child: b) : b;
    return CustomPaint(
      painter: _Dashed(c.track),
      child: Padding(
        padding: EdgeInsets.fromLTRB(phone ? 16 : 18, 16, phone ? 16 : 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: PiumaIconView(PiumaIcon.spark, size: 16, color: c.muted),
            ),
            SizedBox(width: phone ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: words.first),
                        TextSpan(
                          text: name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: words.last),
                      ],
                    ),
                    style: PiumaType.body.copyWith(fontSize: 14.5, color: c.fg),
                  ),
                  if (!phone) ...[
                    const SizedBox(height: 10),
                    Text(
                      l.ruleSuggestMeta(suggestion.moves),
                      style: PiumaType.small.copyWith(
                        fontSize: 12.5,
                        color: c.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      button(
                        PiumaButton(
                          label: l.create,
                          size: size,
                          onPressed: onCreate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      button(
                        PiumaButton(
                          label: l.notNow,
                          kind: PiumaButtonKind.secondary,
                          size: size,
                          onPressed: onNotNow,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dashed outline with the cards' corners.
class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ).deflate(0.75),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dashed old) => old.color != color;
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.pieces,
    required this.enabled,
    required this.meta,
    required this.fresh,
    required this.editing,
    required this.onTap,
    required this.onToggle,
  });

  /// The sentence, as [ruleSentence] gives it.
  final List<(String, bool)> pieces;
  final bool enabled;
  final String meta;
  final bool fresh;
  final bool editing;
  final VoidCallback? onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    final sentence = pieces.map((p) => p.$1).join();
    return AnimatedOpacity(
      duration: instant ? Duration.zero : PiumaMotion.theme,
      curve: PiumaMotion.curve,
      opacity: editing ? 0.4 : 1,
      child: AnimatedContainer(
        duration: instant ? Duration.zero : PiumaMotion.theme,
        curve: PiumaMotion.curve,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fresh ? c.accent : c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PiumaPressable(
                onTap: onTap,
                semanticLabel: '$sentence. $meta',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                    child: AnimatedOpacity(
                      duration: instant ? Duration.zero : PiumaMotion.theme,
                      curve: PiumaMotion.curve,
                      opacity: enabled ? 1 : 0.55,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                for (final (text, chip) in pieces)
                                  chip
                                      ? WidgetSpan(
                                          alignment:
                                              PlaceholderAlignment.middle,
                                          child: _Chip(text),
                                        )
                                      : TextSpan(
                                          text: text,
                                          style: text.contains('→')
                                              ? TextStyle(color: c.muted)
                                              : null,
                                        ),
                              ],
                            ),
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 15,
                              height: 1.9,
                              color: c.fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 12.5,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 18, 0),
              child: PiumaSwitch(
                value: enabled,
                label: l.ruleSwitch(sentence),
                onChanged: onToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The person's words in a rule's sentence.
class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 15,
          height: 1.3,
          fontWeight: FontWeight.w500,
          color: c.fg,
        ),
      ),
    );
  }
}

enum _Menu { field, op, action, target }

/// The sentence editor: "When [the sender] [contains] ___ then [move to]
/// [folder]", what it would sort among the mail already here, and Save.
class RuleEditor extends StatefulWidget {
  const RuleEditor({
    super.key,
    required this.source,
    required this.initial,
    required this.folders,
    required this.onDone,
    this.labels = const [],
    this.phone = false,
  });

  final MailSource source;
  final MailRule initial;
  final Map<int, List<AccountFolder>> folders;

  /// The labels the Label action can put on.
  final List<MailLabel> labels;

  /// Closes the editor, with the id of the rule saved (null when
  /// cancelled or deleted).
  final ValueChanged<int?> onDone;
  final bool phone;

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  late MailRule _rule = widget.initial;
  late final _text = TextEditingController(text: widget.initial.value);
  _Menu? _menu;
  List<MailRow>? _matching;
  bool _applyToo = true;
  bool _busy = false;
  Timer? _wait;
  int _asked = 0;

  bool get _editing => widget.initial.id != 0;

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (_text.text == _rule.value) return;
      _change(_rule.copyWith(value: _text.text), soon: true);
    });
    _preview();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _change(MailRule next, {bool soon = false}) {
    setState(() => _rule = next);
    _wait?.cancel();
    _wait = Timer(
      soon ? const Duration(milliseconds: 250) : Duration.zero,
      _preview,
    );
  }

  Future<void> _preview() async {
    final rule = _rule;
    final asked = ++_asked;
    if (!rule.complete) {
      setState(() => _matching = null);
      return;
    }
    final rows = await widget.source.rulePreview(rule);
    if (!mounted || asked != _asked) return;
    setState(() => _matching = rows);
  }

  void _pick(_Menu menu) => setState(() => _menu = _menu == menu ? null : menu);

  Future<void> _save() async {
    final rule = _rule.copyWith(
      value: _rule.value.trim(),
      // Archive and Mark as read sort every account's mail.
      accountId: _rule.action == RuleAction.moveTo ? null : () => null,
    );
    setState(() => _busy = true);
    try {
      final id = await widget.source.saveRule(rule);
      final rows = _matching;
      if (_applyToo && rows != null && rows.isNotEmpty) {
        await widget.source.applyRule(rule.copyWith(id: id), rows);
      }
      widget.onDone(id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    await widget.source.deleteRule(widget.initial.id);
    widget.onDone(null);
  }

  /// Every account's own folders, as (account, folder).
  List<(MailAccount, AccountFolder)> get _targets => [
    for (final a in widget.source.accounts)
      for (final f in widget.folders[a.id] ?? const <AccountFolder>[])
        if (f.selectable) (a, f),
  ];

  String _targetLabel(MailAccount a, AccountFolder f) {
    final several =
        widget.folders.values.where((list) => list.isNotEmpty).length > 1;
    final path = f.mailbox.contains('/') ? f.mailbox : f.name;
    return several ? '${a.name} · $path' : path;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final r = _rule;
    final phone = widget.phone;
    final targets = _targets;
    final target = targets
        .where((t) => t.$1.id == r.accountId && t.$2.mailbox == r.target)
        .firstOrNull;
    final label = widget.labels
        .where((x) => r.action == RuleAction.label && x.keyword == r.target)
        .firstOrNull;
    final words = PiumaType.body.copyWith(fontSize: 15, color: c.fg);

    Widget chip(_Menu menu, String label) => _EditorChip(
      label: label,
      open: _menu == menu,
      onTap: () => _pick(menu),
    );

    final field = SizedBox(
      width: phone ? double.infinity : 180,
      child: TextField(
        controller: _text,
        autofocus: !_editing && !phone,
        style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
        cursorColor: c.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: l.ruleTextHint,
          hintStyle: PiumaType.body.copyWith(
            fontSize: 14,
            color: c.placeholder,
          ),
          filled: true,
          fillColor: c.bg,
          // 32 high beside the chips, 44 to touch on the phone.
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: phone ? 12 : 6,
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
    );
    final then = [
      Text(l.ruleThen, style: words),
      chip(_Menu.action, _action(l, r.action)),
      if (r.action == RuleAction.moveTo)
        chip(
          _Menu.target,
          target == null
              ? l.rulePickFolder
              : _targetLabel(target.$1, target.$2),
        ),
      if (r.action == RuleAction.vault) chip(_Menu.target, l.folderVault),
      if (r.action == RuleAction.label)
        chip(_Menu.target, label?.name ?? l.rulePickLabel),
    ];
    final sentence = phone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l.ruleWhen, style: words),
                  chip(_Menu.field, _field(l, r.field)),
                  chip(_Menu.op, _op(l, r.op)),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(label: l.ruleText, child: field),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: then,
              ),
            ],
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(l.ruleWhen, style: words),
              chip(_Menu.field, _field(l, r.field)),
              chip(_Menu.op, _op(l, r.op)),
              Semantics(label: l.ruleText, child: field),
              ...then,
            ],
          );

    final menu = _menu;
    final List<(String, bool, VoidCallback)> options = switch (menu) {
      null => const [],
      _Menu.field => [
        for (final f in RuleField.values)
          (_field(l, f), f == r.field, () => _change(r.copyWith(field: f))),
      ],
      _Menu.op => [
        for (final o in RuleOp.values)
          (_op(l, o), o == r.op, () => _change(r.copyWith(op: o))),
      ],
      _Menu.action => [
        // The Vault is picked among the folders, after "move to".
        for (final a in RuleAction.values)
          if (a != RuleAction.vault)
            (
              _action(l, a),
              _same(a, r.action),
              () => _change(
                _same(a, r.action)
                    ? r
                    // A folder is not a label: the new action picks its own.
                    : r.copyWith(action: a, target: '', accountId: () => null),
              ),
            ),
      ],
      _Menu.target when r.action == RuleAction.label => [
        for (final x in widget.labels)
          (
            x.name,
            x.keyword == r.target,
            () => _change(r.copyWith(target: x.keyword)),
          ),
      ],
      _Menu.target => [
        (
          l.folderVault,
          r.action == RuleAction.vault,
          () => _change(
            r.copyWith(
              action: RuleAction.vault,
              target: '',
              accountId: () => null,
            ),
          ),
        ),
        for (final (a, f) in targets)
          (
            _targetLabel(a, f),
            target?.$2.mailbox == f.mailbox && target?.$1.id == a.id,
            () => _change(
              r.copyWith(
                action: RuleAction.moveTo,
                accountId: () => a.id,
                target: f.mailbox,
              ),
            ),
          ),
      ],
    };
    final tray = menu == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(PiumaRadius.row),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      switch (menu) {
                        _Menu.field => l.ruleTrayField,
                        _Menu.op => l.ruleTrayOp,
                        _Menu.action => l.ruleTrayAction,
                        _Menu.target when r.action == RuleAction.label =>
                          l.ruleTrayLabel,
                        _Menu.target => l.ruleTrayFolder,
                      },
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 12.5,
                        color: c.muted,
                      ),
                    ),
                  ),
                  if (options.isEmpty)
                    Text(
                      r.action == RuleAction.label
                          ? l.ruleNoLabels
                          : l.ruleNoFolders,
                      style: PiumaType.small.copyWith(color: c.fg),
                    ),
                  for (final (label, selected, pick) in options)
                    _TrayOption(
                      label: label,
                      selected: selected,
                      onTap: () {
                        pick();
                        setState(() => _menu = null);
                      },
                    ),
                ],
              ),
            ),
          );

    final matching = _matching;
    final count = matching?.length;
    final applies = count == null
        ? const SizedBox.shrink()
        : _Applies(text: l.ruleApplies(count), count: count);
    final applyToo = count == null || count == 0
        ? null
        : _Check(
            label: l.ruleApplyToo,
            value: _applyToo,
            onChanged: (v) => setState(() => _applyToo = v),
          );
    final save = PiumaButton(
      label: l.ruleSave,
      size: phone ? PiumaButtonSize.large : PiumaButtonSize.standard,
      onPressed: r.complete && !_busy ? _save : null,
    );
    final cancel = PiumaButton(
      label: l.cancel,
      kind: PiumaButtonKind.secondary,
      size: phone ? PiumaButtonSize.compact : PiumaButtonSize.standard,
      onPressed: () => widget.onDone(null),
    );
    final delete = _editing
        ? PiumaButton(
            label: l.ruleDelete,
            kind: PiumaButtonKind.tertiary,
            size: phone ? PiumaButtonSize.touch : PiumaButtonSize.standard,
            onPressed: _busy ? null : _delete,
          )
        : null;

    if (phone) {
      // The sheet has no Material of its own, and the text field needs one.
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? l.rulesEdit : l.rulesNew,
                      style: PiumaType.title.copyWith(color: c.fg),
                    ),
                  ),
                  cancel,
                ],
              ),
              const SizedBox(height: 18),
              sentence,
              tray,
              const SizedBox(height: 18),
              Container(height: 1, color: c.line),
              const SizedBox(height: 12),
              applies,
              ?applyToo,
              const SizedBox(height: 16),
              save,
              if (delete != null) ...[const SizedBox(height: 4), delete],
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.accent),
        boxShadow: [BoxShadow(color: c.soft, spreadRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sentence,
          tray,
          const SizedBox(height: 14),
          Container(height: 1, color: c.line),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(child: applies),
              if (applyToo != null) ...[const SizedBox(width: 14), applyToo],
              const Spacer(),
              ?delete,
              const SizedBox(width: 8),
              cancel,
              const SizedBox(width: 8),
              save,
            ],
          ),
        ],
      ),
    );
  }
}

/// "Applies to 23 existing emails", the number set apart.
class _Applies extends StatelessWidget {
  const _Applies({required this.text, required this.count});
  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final style = PiumaType.body.copyWith(fontSize: 14, color: c.muted);
    final n = '$count';
    final at = count == 0 ? -1 : text.indexOf(n);
    if (at < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: n,
            style: TextStyle(color: c.fg, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text.substring(at + n.length)),
        ],
      ),
      style: style,
    );
  }
}

class _EditorChip extends StatelessWidget {
  const _EditorChip({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      button: true,
      expanded: open,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 32,
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          decoration: BoxDecoration(
            color: open ? c.soft : c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
            border: Border.all(color: open ? c.accent : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.accentText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PiumaIconView(
                PiumaIcon.chevronDown,
                size: 14,
                color: c.accentText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayOption extends StatelessWidget {
  const _TrayOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
            border: Border.all(color: selected ? c.accent : c.line),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? c.onAccent : c.fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      checked: value,
      child: PiumaPressable(
        onTap: () => onChanged(!value),
        semanticLabel: label,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: instant ? Duration.zero : PiumaMotion.press,
                curve: PiumaMotion.curve,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: value ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: value ? c.accent : c.muted,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? PiumaIconView(
                        PiumaIcon.check,
                        size: 12,
                        color: c.onAccent,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One account's own folders, as on the board's right column, each with
/// how many emails it holds, and New folder to make one on the server.
/// "Folders & labels": every account's own folders, then the labels card.
/// Inline on the desktop; its own page on the phone.
class FoldersAndLabels extends StatefulWidget {
  const FoldersAndLabels({
    super.key,
    required this.source,
    required this.folders,
    required this.labels,
    required this.onChanged,
  });

  final MailSource source;
  final Map<int, List<AccountFolder>> folders;
  final List<MailLabel> labels;

  /// After a folder or label changed, so the rules read the new names.
  final VoidCallback onChanged;

  @override
  State<FoldersAndLabels> createState() => _FoldersAndLabelsState();
}

class _FoldersAndLabelsState extends State<FoldersAndLabels> {
  late Map<int, List<AccountFolder>> _folders = widget.folders;
  late List<MailLabel> _labels = widget.labels;

  @override
  void didUpdateWidget(FoldersAndLabels old) {
    super.didUpdateWidget(old);
    if (widget.folders != old.folders) _folders = widget.folders;
    if (widget.labels != old.labels) _labels = widget.labels;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.foldersAndLabelsHeading,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.34,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final (i, a) in widget.source.accounts.indexed) ...[
          if (i > 0) const SizedBox(height: 14),
          _AccountFolders(
            account: a,
            folders: _folders[a.id],
            create: (name) => _createFolder(a, name),
            reorder: (order) => _reorderFolders(a, order),
          ),
        ],
        const SizedBox(height: 14),
        _LabelsCard(
          labels: _labels,
          onNew: () => _editLabel(null),
          onLabel: _editLabel,
        ),
      ],
    );
  }

  /// + Label, or a click on one: its name and color, or Delete.
  Future<void> _editLabel(MailLabel? label) async {
    await showLabelEditor(context, source: widget.source, label: label);
    final labels = await widget.source.labels();
    if (mounted) setState(() => _labels = labels);
    widget.onChanged();
  }

  /// Makes the folder on the account's server and lists it at once.
  Future<void> _createFolder(MailAccount a, String name) async {
    await widget.source.createFolder(a.id, name);
    final folders = await widget.source.folders(a.id);
    if (mounted) setState(() => _folders = {..._folders, a.id: folders});
    widget.onChanged();
  }

  /// Puts some sibling folders in the order they were dragged into, at
  /// once, and keeps it in the engine.
  Future<void> _reorderFolders(MailAccount a, List<String> order) async {
    final list = _folders[a.id];
    if (list == null) return;
    setState(
      () => _folders = {..._folders, a.id: withFolderOrder(list, order)},
    );
    await widget.source.setFolderOrder(a.id, order);
    widget.onChanged();
  }
}

/// The row of `RulesPhone` under the rules: "Folders & labels", how many
/// of each, and a chevron to their page.
class _FoldersRow extends StatelessWidget {
  const _FoldersRow({
    required this.folders,
    required this.labels,
    required this.onTap,
  });

  final int folders;
  final int labels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final count = [
      l.rulesFoldersCount(folders),
      if (labels > 0) l.rulesLabelsCount(labels),
    ].join(' · ');
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: '${l.foldersAndLabelsHeading}, $count',
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              PiumaIconView(PiumaIcon.folder, size: 18, color: c.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.foldersAndLabelsHeading,
                  style: PiumaType.body.copyWith(color: c.fg),
                ),
              ),
              Text(count, style: PiumaType.small.copyWith(color: c.muted)),
              const SizedBox(width: 12),
              PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountFolders extends StatefulWidget {
  const _AccountFolders({
    required this.account,
    required this.folders,
    required this.create,
    required this.reorder,
  });
  final MailAccount account;
  final List<AccountFolder>? folders;
  final Future<void> Function(String name) create;

  /// Some sibling folders, in their new order.
  final Future<void> Function(List<String> order) reorder;

  @override
  State<_AccountFolders> createState() => _AccountFoldersState();
}

class _AccountFoldersState extends State<_AccountFolders> {
  final _name = TextEditingController();
  bool _adding = false;
  bool _busy = false;
  bool _failed = false;

  /// The folder being dragged, and the list as it would be if dropped now.
  AccountFolder? _moving;
  List<AccountFolder>? _preview;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
    _adding = !_adding;
    _failed = false;
    _name.clear();
  });

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.create(name);
      if (mounted) setState(() => _adding = false);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final account = widget.account;
    final list = _preview ?? widget.folders;
    final text = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      color: c.fg,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.bg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: account.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  account.name,
                  style: text.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    account.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.copyWith(fontSize: 13, color: c.muted),
                  ),
                ),
                const SizedBox(width: 6),
                _NewFolder(label: l.newFolder, onTap: _toggle),
              ],
            ),
          ),
          if (list != null && list.isEmpty)
            _line(c, Text(l.foldersNone, style: text.copyWith(color: c.muted))),
          for (final f in list ?? const <AccountFolder>[])
            _folderLine(c, l, text, f, list!),
          if (_adding)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: l.newFolderName,
                          textField: true,
                          child: TextField(
                            controller: _name,
                            autofocus: true,
                            onSubmitted: (_) => _create(),
                            style: text,
                            cursorColor: c.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: c.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  PiumaRadius.field,
                                ),
                                borderSide: BorderSide(color: c.accent),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  PiumaRadius.field,
                                ),
                                borderSide: BorderSide(color: c.accent),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PiumaButton(
                        label: l.create,
                        size: PiumaButtonSize.compact,
                        onPressed: _busy ? null : _create,
                      ),
                      const SizedBox(width: 8),
                      PiumaButton(
                        label: l.cancel,
                        kind: PiumaButtonKind.tertiary,
                        size: PiumaButtonSize.compact,
                        onPressed: _toggle,
                      ),
                    ],
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.newFolderFailed,
                      style: PiumaType.body.copyWith(
                        fontSize: 13,
                        color: c.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One step up or down among its siblings, for assistive technology.
  void _step(AccountFolder f, List<AccountFolder> list, int by) {
    final order = [for (final s in folderSiblings(list, f)) s.mailbox];
    final i = order.indexOf(f.mailbox) + by;
    if (i < 0 || i >= order.length) return;
    order
      ..remove(f.mailbox)
      ..insert(i, f.mailbox);
    widget.reorder(order);
  }

  /// Whether [f] is [_moving] or one of its subfolders.
  bool _inMoving(AccountFolder f, List<AccountFolder> list) {
    final moving = _moving;
    if (moving == null) return false;
    final at = list.indexOf(moving);
    final i = list.indexOf(f);
    if (at < 0 || i < at) return false;
    for (var j = at + 1; j <= i; j++) {
      if (list[j].depth <= moving.depth) return false;
    }
    return true;
  }

  /// A folder's line: the grip to drag it among its siblings (with its
  /// subfolders), its name and how many emails it holds.
  Widget _folderLine(
    PiumaColors c,
    AppLocalizations l,
    TextStyle text,
    AccountFolder f,
    List<AccountFolder> list,
  ) {
    final key = GlobalObjectKey(f);
    final siblings = folderSiblings(list, f);
    final i = siblings.indexOf(f);
    Widget content(bool grabbed) => Row(
      children: [
        SizedBox(width: 16.0 * f.depth),
        Container(
          width: 24,
          height: 32,
          alignment: Alignment.center,
          child: PiumaIconView(
            PiumaIcon.grip,
            size: 14,
            color: grabbed ? c.fg : c.muted,
          ),
        ),
        const SizedBox(width: 8),
        PiumaIconView(PiumaIcon.folder, size: 15, color: c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            f.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.copyWith(color: f.selectable ? c.fg : c.muted),
          ),
        ),
        if (f.selectable)
          Text(
            '${f.total}',
            style: PiumaType.mono.copyWith(fontSize: 12, color: c.muted),
          ),
      ],
    );
    final moving = _moving;
    Offset anchor(Draggable<Object> _, BuildContext _, Offset position) =>
        (key.currentContext!.findRenderObject()! as RenderBox).globalToLocal(
          position,
        );
    void started() => setState(() {
      _moving = f;
      _preview = widget.folders;
    });
    // Wherever it is let go, it stays where the list already shows it.
    void ended(DraggableDetails _) {
      if (!mounted) return;
      final moved = _moving;
      final shown = _preview;
      setState(() {
        _moving = null;
        _preview = null;
      });
      final was = widget.folders;
      if (moved == null || shown == null || was == null) return;
      final order = [for (final s in folderSiblings(shown, moved)) s.mailbox];
      final before = [for (final s in folderSiblings(was, moved)) s.mailbox];
      if (order.join('\n') != before.join('\n')) widget.reorder(order);
    }

    final feedback = Builder(
      builder: (_) {
        final box = key.currentContext?.findRenderObject() as RenderBox?;
        return Container(
          width: box?.size.width,
          height: 40,
          padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: DefaultTextStyle(style: text, child: content(true)),
        );
      },
    );
    final gap = SizedBox(width: 24 + 16.0 * f.depth, height: 32);
    // The scroll takes a touch that moves at once, so a finger holds the
    // grip first; a mouse drags it straight away.
    final drag = LongPressDraggable<AccountFolder>(
      data: f,
      axis: Axis.vertical,
      dragAnchorStrategy: anchor,
      hitTestBehavior: HitTestBehavior.opaque,
      onDragStarted: started,
      onDragEnd: ended,
      feedback: feedback,
      childWhenDragging: gap,
      child: Draggable<AccountFolder>(
        data: f,
        axis: Axis.vertical,
        dragAnchorStrategy: anchor,
        hitTestBehavior: HitTestBehavior.opaque,
        onDragStarted: started,
        onDragEnd: ended,
        feedback: feedback,
        childWhenDragging: gap,
        child: gap,
      ),
    );
    final grip = Semantics(
      label: l.folderReorder(f.name),
      customSemanticsActions: {
        if (i > 0)
          CustomSemanticsAction(label: l.folderMoveUp): () =>
              _step(f, list, -1),
        if (i < siblings.length - 1)
          CustomSemanticsAction(label: l.folderMoveDown): () =>
              _step(f, list, 1),
      },
      child: MouseRegion(
        cursor: moving == null
            ? SystemMouseCursors.grab
            : SystemMouseCursors.grabbing,
        child: drag,
      ),
    );
    // Over a sibling, the dragged folder takes its place at once, so the
    // list always shows where it will land.
    return DragTarget<AccountFolder>(
      key: ValueKey(f.mailbox),
      onWillAcceptWithDetails: (d) => siblings.contains(d.data),
      onMove: (d) {
        if (d.data == f || !siblings.contains(d.data)) return;
        final order = [for (final s in siblings) s.mailbox]
          ..remove(d.data.mailbox)
          ..insert(siblings.indexOf(f), d.data.mailbox);
        setState(() => _preview = withFolderOrder(list, order));
      },
      builder: (context, _, _) => Container(
        key: key,
        height: 40,
        padding: const EdgeInsets.fromLTRB(6, 0, 14, 0),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Opacity(
          opacity: _inMoving(f, list) ? 0.4 : 1,
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              content(false),
              Positioned(left: 0, top: 4, bottom: 4, child: grip),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(PiumaColors c, Widget child) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: c.line)),
    ),
    alignment: Alignment.centerLeft,
    child: child,
  );
}

/// The labels card under the accounts' folders (`LabelsToApprove`,
/// section 3): "Labels · shared across all accounts" and + Label; a
/// click on a label renames it, changes its color or deletes it.
class _LabelsCard extends StatelessWidget {
  const _LabelsCard({
    required this.labels,
    required this.onNew,
    required this.onLabel,
  });

  final List<MailLabel> labels;
  final VoidCallback onNew;
  final ValueChanged<MailLabel> onLabel;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final text = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      color: c.fg,
    );
    Widget line(Widget child) => Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.bg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.tag, size: 15, color: c.fg),
                const SizedBox(width: 10),
                Text(
                  l.labelsCardTitle,
                  style: text.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.labelsCardDetail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.copyWith(fontSize: 13, color: c.muted),
                  ),
                ),
                const SizedBox(width: 6),
                _NewFolder(label: l.labelAction, onTap: onNew),
              ],
            ),
          ),
          if (labels.isEmpty)
            line(Text(l.labelsNone, style: text.copyWith(color: c.muted))),
          for (final x in labels)
            PiumaPressable(
              onTap: () => onLabel(x),
              semanticLabel: x.name,
              child: line(
                Row(
                  children: [
                    LabelPill(label: x),
                    const Spacer(),
                    if (x.count > 0)
                      Text(
                        l.labelEmails(x.count),
                        style: text.copyWith(fontSize: 13, color: c.muted),
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

/// "+ New folder" in the account's header: accent text, no fill.
class _NewFolder extends StatelessWidget {
  const _NewFolder({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PiumaIconView(PiumaIcon.plus, size: 14, color: c.accentText),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: PiumaType.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.accentText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
