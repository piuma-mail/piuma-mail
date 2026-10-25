import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/text_field.dart';

/// Asks the person for a logo. Tests replace it.
Future<XFile?> Function() pickLogo = () => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
  ],
);

/// Settings → Signatures, as the `Signatures` mockup: the list of
/// signatures, the one being edited (template, logo, fields, accent, when
/// to use it) and its preview in light, dark and plain text.
class SignaturesPage extends StatefulWidget {
  const SignaturesPage({
    super.key,
    required this.source,
    this.initial,
    this.phone = false,
    this.onBack,
    this.templates,
    this.openTemplates = false,
  });

  final MailSource source;

  /// Settings › Writing: the templates, as the page's second part. Without
  /// them the page is Signatures alone.
  final Widget? templates;

  /// Opens on the templates rather than a signature.
  final bool openTemplates;

  /// The signature to open first; else the first one.
  final int? initial;

  /// On the phone the list and the editor each fill the screen, with
  /// "‹ Settings" and "‹ Signatures" to go back.
  final bool phone;
  final VoidCallback? onBack;

  @override
  State<SignaturesPage> createState() => SignaturesPageState();
}

enum _Preview { light, dark, text }

class SignaturesPageState extends State<SignaturesPage> {
  /// On the phone, the editor is open over the list.
  late bool _editing = widget.initial != null;

  /// Back on the phone: from the editor to the list. False when there
  /// was nothing to go back from here.
  bool back() {
    if (!widget.phone || !_editing) return false;
    setState(() => _editing = false);
    return true;
  }

  List<MailSignature>? _all;
  late int? _openId = widget.initial;

  /// On the desktop, the templates fill the right side instead of a
  /// signature.
  late bool _templatesOpen = widget.templates != null && widget.openTemplates;

  /// Where the phone scrolls to when it opens on the templates.
  final _templatesKey = GlobalKey();

  /// Starts in the app's own theme.
  _Preview? _picked;
  _Preview get _preview =>
      _picked ??
      (PiumaTheme.of(context).bg == PiumaColors.dark.bg
          ? _Preview.dark
          : _Preview.light);
  String? _logoError;

  // One controller per field of the open signature.
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  List<TextEditingController> get _fields => [
    _label,
    _name,
    _role,
    _company,
    _phone,
    _website,
  ];

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      f.addListener(_typed);
    }
    _load();
  }

  String get _title {
    final l = AppLocalizations.of(context);
    return widget.templates == null ? l.signaturesTitle : l.writingTitle;
  }

  /// "Signatures" and "Templates" over the two parts of Writing.
  Widget _partHeading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: PiumaTheme.of(context).muted,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load({int? open}) async {
    final all = await widget.source.signatures();
    if (!mounted) return;
    setState(() {
      _all = all;
      final want = open ?? _openId;
      _openId = all.any((s) => s.id == want) ? want : all.firstOrNull?.id;
    });
    _fill();
    if (widget.phone && widget.openTemplates && open == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final there = _templatesKey.currentContext;
        if (there != null && there.mounted) {
          Scrollable.ensureVisible(there);
        }
      });
    }
  }

  MailSignature? get _open {
    for (final s in _all ?? const <MailSignature>[]) {
      if (s.id == _openId) return s;
    }
    return null;
  }

  bool _filling = false;

  /// Puts the open signature's text into the fields.
  void _fill() {
    final s = _open;
    _filling = true;
    _label.text = s?.label ?? '';
    _name.text = s?.name ?? '';
    _role.text = s?.role ?? '';
    _company.text = s?.company ?? '';
    _phone.text = s?.phone ?? '';
    _website.text = s?.website ?? '';
    _filling = false;
  }

  void _typed() {
    if (_filling) return;
    final s = _open;
    if (s == null) return;
    _save(
      s.copyWith(
        label: _label.text,
        name: _name.text,
        role: _role.text,
        company: _company.text,
        phone: _phone.text,
        website: _website.text,
      ),
    );
  }

  /// Saves at once: there is no Save button, as in the mockup.
  Future<void> _save(MailSignature s) async {
    setState(() {
      _all = [for (final x in _all!) x.id == s.id ? s : x];
    });
    await widget.source.saveSignature(s);
    // Jobs taken from another signature show at once.
    if (s.forNew || s.forReplies) await _load();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final accounts = widget.source.accounts;
    if (accounts.isEmpty) return;
    final account = _open?.accountId ?? accounts.first.id;
    final taken = (_all ?? const <MailSignature>[]).where(
      (s) => s.accountId == account,
    );
    final first = taken.isEmpty;
    final mine = accounts.firstWhere((a) => a.id == account);
    final id = await widget.source.saveSignature(
      MailSignature(
        accountId: account,
        label: l.newSignatureLabel,
        name: mine.senderName,
        forNew: first,
        forReplies: first,
      ),
    );
    await _load(open: id);
    if (mounted) {
      setState(() {
        _editing = true;
        _templatesOpen = false;
      });
    }
  }

  Future<void> _delete(MailSignature s) async {
    await widget.source.deleteSignature(s.id);
    _openId = null;
    _editing = false;
    await _load();
  }

  Future<void> _upload(MailSignature s) async {
    final file = await pickLogo();
    if (file == null) return;
    try {
      final logo = await widget.source.shrinkLogo(await file.readAsBytes());
      if (!mounted) return;
      setState(() => _logoError = null);
      _save(s.copyWith(logo: logo));
    } on LogoException catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(
        () => _logoError = e.error == LogoError.tooBig
            ? l.logoTooBig
            : l.logoNotImage,
      );
    }
  }

  void _openOne(MailSignature s) {
    setState(() {
      _openId = s.id;
      _logoError = null;
      _editing = true;
      _templatesOpen = false;
    });
    _fill();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final all = _all;
    if (all == null) return const SizedBox.shrink();
    final open = _open;
    if (widget.phone) return _phoneBody(context, all, open);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 280,
          padding: const EdgeInsets.fromLTRB(14, 40, 14, 24),
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: c.line)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                  child: Text(
                    _title,
                    style: PiumaType.display.copyWith(
                      fontSize: 28,
                      letterSpacing: -0.84,
                      color: c.fg,
                    ),
                  ),
                ),
                if (widget.templates != null) _partHeading(l.signaturesTitle),
                for (final s in all)
                  _ListItem(
                    signature: s,
                    account: _account(s.accountId),
                    current: !_templatesOpen && s.id == _openId,
                    onTap: () => _openOne(s),
                  ),
                const SizedBox(height: 6),
                _NewButton(label: l.newSignature, onTap: _create),
                if (widget.templates != null) ...[
                  const SizedBox(height: 20),
                  _TemplatesItem(
                    current: _templatesOpen,
                    onTap: () => setState(() => _templatesOpen = true),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: _templatesOpen
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(56, 44, 56, 56),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: widget.templates,
                    ),
                  ),
                )
              : open == null
              ? Center(
                  child: Text(
                    l.noSignatures,
                    style: PiumaType.small.copyWith(color: c.muted),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(36, 44, 36, 40),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 32, child: _editor(context, open)),
                      const SizedBox(width: 32),
                      Expanded(flex: 34, child: _previewColumn(context, open)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _phoneBody(
    BuildContext context,
    List<MailSignature> all,
    MailSignature? open,
  ) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    if (_editing && open != null) {
      return Column(
        key: const ValueKey('editor'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhoneBack(label: _title, onTap: back),
          Expanded(
            child: SingleChildScrollView(
              // Scrolling puts the keyboard away and lets go of the field.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _editor(context, open),
                  const SizedBox(height: 32),
                  _previewColumn(context, open),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      key: const ValueKey('list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PhoneBack(label: l.settings, onTap: widget.onBack ?? () {}),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                  child: Text(
                    _title,
                    style: PiumaType.display.copyWith(
                      fontSize: 30,
                      letterSpacing: -0.9,
                      color: c.fg,
                    ),
                  ),
                ),
                if (widget.templates != null) _partHeading(l.signaturesTitle),
                for (final s in all)
                  _ListItem(
                    signature: s,
                    account: _account(s.accountId),
                    current: false,
                    onTap: () => _openOne(s),
                  ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _NewButton(label: l.newSignature, onTap: _create),
                ),
                if (widget.templates case final templates?) ...[
                  const SizedBox(height: 32),
                  Padding(
                    key: _templatesKey,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: templates,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  MailAccount? _account(int id) {
    for (final a in widget.source.accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Widget _editor(BuildContext context, MailSignature s) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final account = _account(s.accountId);
    final others = (_all ?? const <MailSignature>[]).where(
      (x) => x.accountId == s.accountId && x.id != s.id,
    );
    String? holder(bool Function(MailSignature) job) =>
        job(s) ? s.label : others.where(job).firstOrNull?.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(l.signatureTemplate),
        const SizedBox(height: 10),
        _TemplateGrid(
          selected: s.template,
          onPick: (t) => _save(s.copyWith(template: t)),
        ),
        if (s.template == SignatureTemplate.logo) ...[
          const SizedBox(height: 22),
          _Label(l.signatureLogo),
          const SizedBox(height: 10),
          _LogoBox(
            logo: s.logo,
            error: _logoError,
            onUpload: () => _upload(s),
            onRemove: s.logo == null
                ? null
                : () => _save(s.copyWith(clearLogo: true)),
          ),
        ],
        const SizedBox(height: 22),
        _Pair(
          PiumaTextField(label: l.signatureLabelField, controller: _label),
          _AccountPicker(
            accounts: widget.source.accounts,
            selected: s.accountId,
            onPick: (id) => _save(
              s.copyWith(accountId: id, forNew: false, forReplies: false),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Pair(
          PiumaTextField(label: l.signatureName, controller: _name),
          PiumaTextField(label: l.signatureRole, controller: _role),
        ),
        const SizedBox(height: 12),
        _Pair(
          PiumaTextField(label: l.signatureCompany, controller: _company),
          PiumaTextField(
            label: l.signaturePhone,
            controller: _phone,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 12),
        PiumaTextField(
          label: l.signatureWebsite,
          controller: _website,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 22),
        _Label(l.signatureAccent),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final a in SignatureAccent.values) ...[
              _AccentSwatch(
                accent: a,
                selected: a == s.accent,
                label: switch (a) {
                  SignatureAccent.blue => l.accentBlue,
                  SignatureAccent.black => l.accentBlack,
                  SignatureAccent.terracotta => l.accentTerracotta,
                },
                onTap: () => _save(s.copyWith(accent: a)),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 22),
        _Label(l.signatureWhen),
        const SizedBox(height: 10),
        _Jobs(
          rows: [
            (
              l.signatureForNew(account?.email ?? ''),
              holder((x) => x.forNew),
              s.forNew,
              () => _save(s.copyWith(forNew: !s.forNew)),
            ),
            (
              l.signatureForReplies,
              holder((x) => x.forReplies),
              s.forReplies,
              () => _save(s.copyWith(forReplies: !s.forReplies)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        // Its label lines up with the fields, not its padding.
        Align(
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: const Offset(-12, 0),
            child: PiumaButton(
              label: l.deleteSignature,
              kind: PiumaButtonKind.tertiary,
              size: PiumaButtonSize.compact,
              onPressed: () => _delete(s),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.signatureDeleteHint,
          style: PiumaType.small.copyWith(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }

  Widget _previewColumn(BuildContext context, MailSignature s) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final dark = _preview == _Preview.dark;
    final p = dark ? PiumaColors.dark : PiumaColors.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Label(l.signaturePreview)),
            _Tabs(
              labels: [l.previewLight, l.previewDark, l.previewText],
              selected: _preview.index,
              onPick: (i) => setState(() => _picked = _Preview.values[i]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.theme,
          curve: PiumaMotion.curve,
          constraints: const BoxConstraints(minHeight: 320),
          padding: const EdgeInsets.all(PiumaSpace.s24),
          decoration: BoxDecoration(
            color: _preview == _Preview.text
                ? PiumaColors.light.surface
                : p.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _preview == _Preview.text
              ? Text(
                  '${l.signatureSampleText}\n\n${s.text}',
                  style: PiumaType.mono.copyWith(
                    height: 1.6,
                    color: PiumaColors.light.fg,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.signatureSampleText,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 15,
                        height: 1.6,
                        color: p.fg,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SignatureView(signature: s, colors: p, dark: dark),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: PiumaIconView(PiumaIcon.check, color: c.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.template == SignatureTemplate.logo
                      ? l.signatureNoteLogo
                      : l.signatureNote,
                  style: PiumaType.small.copyWith(color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A signature drawn as the email shows it, in [colors] (light or dark).
class SignatureView extends StatelessWidget {
  const SignatureView({
    super.key,
    required this.signature,
    required this.colors,
    this.dark = false,
  });

  final MailSignature signature;
  final PiumaColors colors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final s = signature;
    final p = colors;
    final accents = dark
        ? PiumaSignatureColors.dark
        : PiumaSignatureColors.light;
    final accent = accents[s.accent.name]!;
    final link = s.accent == SignatureAccent.black ? p.fg : accent;
    final lines = s.lines;
    if (lines.isEmpty) return const SizedBox.shrink();
    const base = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 14,
      height: 1.45,
    );
    final website = s.website.trim();
    Widget line(String text) {
      final at = website.isEmpty ? -1 : text.lastIndexOf(website);
      return Text.rich(
        TextSpan(
          style: base.copyWith(color: p.muted),
          children: [
            TextSpan(text: at < 0 ? text : text.substring(0, at)),
            if (at >= 0)
              TextSpan(
                text: website,
                style: TextStyle(color: link, fontWeight: FontWeight.w500),
              ),
          ],
        ),
      );
    }

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lines.first,
          style: base.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: p.fg,
          ),
        ),
        for (final l in lines.skip(1)) line(l),
      ],
    );
    return switch (s.template) {
      SignatureTemplate.minimal => text,
      SignatureTemplate.classic => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 28, height: 2, color: accent),
          const SizedBox(height: 8),
          text,
        ],
      ),
      SignatureTemplate.monogram => Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              s.monogram,
              style: base.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.onAccent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(child: text),
        ],
      ),
      SignatureTemplate.logo => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.logo case final logo?) ...[
            Image.memory(logo, height: 36, gaplessPlayback: true),
            const SizedBox(height: 10),
          ],
          text,
        ],
      ),
    };
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Text(
      text,
      style: PiumaType.small.copyWith(
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );
}

class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.signature,
    required this.account,
    required this.current,
    required this.onTap,
  });

  final MailSignature signature;
  final MailAccount? account;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final s = signature;
    final use = switch ((s.forNew, s.forReplies)) {
      (true, true) => l.signatureUseAll,
      (true, false) => l.signatureUseNew,
      (false, true) => l.signatureUseReplies,
      (false, false) => l.signatureUseNone,
    };
    return Semantics(
      selected: current,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: s.label,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: current ? c.sel : c.sel.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: account?.color ?? c.muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        s.label.isEmpty ? l.newSignatureLabel : s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 14,
                          fontWeight: current
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${account?.email ?? ''} · $use',
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

/// Writing on the desktop: Templates under the signatures, opening them
/// on the right.
class _TemplatesItem extends StatelessWidget {
  const _TemplatesItem({required this.current, required this.onTap});
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Semantics(
      selected: current,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: l.templatesTitle,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: current ? c.sel : c.sel.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.template, size: 16, color: c.muted),
                const SizedBox(width: 8),
                Text(
                  l.templatesTitle,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                    color: c.fg,
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

class _NewButton extends StatelessWidget {
  const _NewButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: CustomPaint(
        painter: _Dashed(c.ring),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.plus, color: c.muted),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      color: c.muted,
                    ),
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

/// A dashed rounded border, as the mockup's "New signature".
class _Dashed extends CustomPainter {
  _Dashed(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(PiumaRadius.row),
        ).deflate(0.5),
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

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.selected, required this.onPick});
  final SignatureTemplate selected;
  final ValueChanged<SignatureTemplate> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cards = [
      for (final t in SignatureTemplate.values)
        _TemplateCard(
          template: t,
          label: switch (t) {
            SignatureTemplate.minimal => l.templateMinimal,
            SignatureTemplate.classic => l.templateClassic,
            SignatureTemplate.monogram => l.templateMonogram,
            SignatureTemplate.logo => l.templateLogo,
          },
          selected: t == selected,
          onTap: () => onPick(t),
        ),
    ];
    return Column(
      children: [
        _Pair(cards[0], cards[1]),
        const SizedBox(height: 10),
        _Pair(cards[2], cards[3]),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SignatureTemplate template;
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
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          padding: EdgeInsets.all(selected ? 11 : 12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(PiumaRadius.field),
                  ),
                  child: Row(
                    children: [
                      if (template == SignatureTemplate.monogram) ...[
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (template == SignatureTemplate.logo) ...[
                        Container(
                          width: 26,
                          height: 14,
                          decoration: BoxDecoration(
                            border: Border.all(color: c.fg, width: 1.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (template == SignatureTemplate.classic) ...[
                              Container(width: 14, height: 2, color: c.accent),
                              const SizedBox(height: 4),
                            ],
                            FractionallySizedBox(
                              widthFactor: 0.7,
                              child: _Bar(height: 5, color: c.fg),
                            ),
                            const SizedBox(height: 4),
                            FractionallySizedBox(
                              widthFactor: 0.9,
                              child: _Bar(height: 4, color: c.ring),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: c.fg,
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

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _LogoBox extends StatelessWidget {
  const _LogoBox({
    required this.logo,
    required this.error,
    required this.onUpload,
    this.onRemove,
  });

  final Uint8List? logo;
  final String? error;
  final VoidCallback onUpload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return CustomPaint(
      painter: _Dashed(c.ring),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 96,
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.bg,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(PiumaRadius.field),
              ),
              child: logo == null
                  ? Text(
                      l.noLogo,
                      style: PiumaType.label.copyWith(color: c.muted),
                    )
                  : Image.memory(logo!, fit: BoxFit.contain),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                error ?? l.logoHint,
                style: PiumaType.small.copyWith(
                  color: error == null ? c.muted : c.danger,
                ),
              ),
            ),
            if (onRemove != null) ...[
              PiumaButton(
                label: l.removeLogo,
                kind: PiumaButtonKind.tertiary,
                size: PiumaButtonSize.compact,
                onPressed: onRemove,
              ),
              const SizedBox(width: 4),
            ],
            PiumaButton(
              label: l.uploadLogo,
              kind: PiumaButtonKind.secondary,
              size: PiumaButtonSize.compact,
              onPressed: onUpload,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selected,
    required this.onPick,
  });

  final List<MailAccount> accounts;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    MailAccount? current;
    for (final a in accounts) {
      if (a.id == selected) current = a;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(l.signatureAccount),
        const SizedBox(height: 6),
        PopupMenuButton<int>(
          tooltip: l.signatureAccount,
          onSelected: onPick,
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PiumaRadius.row),
            side: BorderSide(color: c.line),
          ),
          itemBuilder: (_) => [
            for (final a in accounts)
              PopupMenuItem(
                value: a.id,
                child: Row(
                  children: [
                    _Dot(a.color),
                    const SizedBox(width: 8),
                    Text(
                      '${a.name} · ${a.email}',
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 14,
                        color: c.fg,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: Row(
              children: [
                if (current != null) ...[
                  _Dot(current.color),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    current?.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 15,
                      color: c.fg,
                    ),
                  ),
                ),
                PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final SignatureAccent accent;
  final bool selected;
  final String label;
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
          width: 44,
          height: 44,
          padding: EdgeInsets.all(selected ? 3 : 4),
          decoration: BoxDecoration(
            color: c.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? c.fg : c.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: (c.bg == PiumaColors.dark.bg
                  ? PiumaSignatureColors.dark
                  : PiumaSignatureColors.light)[accent.name],
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// "When to use it": each job, who has it, and a tap to take it.
class _Jobs extends StatelessWidget {
  const _Jobs({required this.rows});
  final List<(String, String?, bool, VoidCallback)> rows;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: Column(
        children: [
          for (final (i, (label, holder, mine, onTap)) in rows.indexed)
            Semantics(
              checked: mine,
              child: PiumaPressable(
                onTap: onTap,
                semanticLabel: label,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: c.line)),
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 14,
                              color: c.fg,
                            ),
                          ),
                        ),
                        Text(
                          holder ?? l.signatureNone,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 14,
                            fontWeight: holder == null
                                ? FontWeight.w400
                                : FontWeight.w600,
                            color: mine ? c.accentText : c.muted,
                          ),
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

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onPick,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(PiumaRadius.button),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, label) in labels.indexed)
            Semantics(
              selected: i == selected,
              child: PiumaPressable(
                onTap: () => onPick(i),
                semanticLabel: label,
                child: AnimatedContainer(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : PiumaMotion.press,
                  curve: PiumaMotion.curve,
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected
                        ? c.surface
                        : c.surface.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(PiumaRadius.field),
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 13,
                        fontWeight: i == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: c.fg,
                      ),
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

/// "‹ Settings", "‹ Signatures": back, at the top of a phone page.
class _PhoneBack extends StatelessWidget {
  const _PhoneBack({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(
                    PiumaIcon.chevronLeft,
                    size: 22,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 2),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: PiumaType.body.copyWith(
                        fontSize: 16,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
