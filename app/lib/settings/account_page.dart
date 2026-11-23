import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/service_states.dart' show showSignInAgain;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../onboarding/account_errors.dart';
import '../onboarding/add_account_screen.dart' show SecurityPicker;
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/switch.dart';
import '../widgets/text_field.dart';
import 'quota_card.dart';
import '../widgets/bidi.dart';

/// An account's details, as on `FeaturesToApprove` (section 2): its name,
/// color, From name and default signature, how its connection is going,
/// the sign-in alert, and Remove account. Changes are kept as they are
/// typed.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.source,
    required this.account,
    required this.onBack,
    required this.backLabel,
    this.onSignature,
    this.onAway,
    this.phone = false,
    this.now = DateTime.now,
  });

  final MailSource source;
  final MailAccount account;
  final VoidCallback onBack;
  final String backLabel;

  /// Opens Signatures on the account's default one, or on none.
  final ValueChanged<int?>? onSignature;

  /// Opens the account's away message; its row shows only when the
  /// server takes one.
  final VoidCallback? onAway;
  final bool phone;
  final DateTime Function() now;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late MailAccount _account = widget.account;
  late final _name = TextEditingController(text: _account.name);
  late final _senderName = TextEditingController(text: _account.senderName);
  AccountServers? _servers;
  MailSignature? _signature;
  bool _alert = true;

  /// The away message, once the server says it takes one.
  AwayMessage? _away;
  Timer? _saveTimer;
  Timer? _clock;

  static const _saveDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _name.addListener(_typed);
    _senderName.addListener(_typed);
    widget.source.status.addListener(_statusChanged);
    // "checked 2 min ago" moves on.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _load();
    _loadAway();
  }

  @override
  void dispose() {
    widget.source.status.removeListener(_statusChanged);
    _clock?.cancel();
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    _name.dispose();
    _senderName.dispose();
    super.dispose();
  }

  void _statusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final id = _account.id;
    try {
      final servers = await widget.source.accountServers(id);
      final alert = await widget.source.signInAlert(id);
      final signatures = await widget.source.signatures();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _alert = alert;
        _signature = signatures
            .where((s) => s.accountId == id && s.forNew)
            .firstOrNull;
      });
    } catch (_) {
      // The page shows what it has.
    }
  }

  /// Asked on its own: the server may take a moment to answer.
  Future<void> _loadAway() async {
    if (widget.onAway == null) return;
    try {
      final away = await widget.source.awayMessage(_account.id);
      if (mounted) setState(() => _away = away);
    } catch (_) {
      // No row, then.
    }
  }

  void _typed() {
    if (_name.text == _account.name &&
        _senderName.text == _account.senderName) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
  }

  void _save() {
    final name = _name.text.trim();
    _account = MailAccount(
      id: _account.id,
      // An account always has a name: an empty one keeps the last.
      name: name.isEmpty ? _account.name : name,
      email: _account.email,
      color: _account.color,
      senderName: _senderName.text.trim(),
    );
    unawaited(
      widget.source.updateAccount(_account).catchError((_) => _account),
    );
    if (mounted) setState(() {});
  }

  void _pickColor(Color color) {
    _saveTimer?.cancel();
    setState(() {
      _account = MailAccount(
        id: _account.id,
        name: _account.name,
        email: _account.email,
        color: color,
        senderName: _account.senderName,
      );
    });
    _save();
  }

  Future<void> _setAlert(bool on) async {
    setState(() => _alert = on);
    await widget.source.setSignInAlert(_account.id, on);
  }

  Future<void> _editServers() async {
    final servers = _servers;
    if (servers == null) return;
    final l = AppLocalizations.of(context);
    Widget form(BuildContext context) => Material(
      type: MaterialType.transparency,
      child: _ServersForm(
        source: widget.source,
        accountId: _account.id,
        initial: servers,
        phone: widget.phone,
      ),
    );
    final saved = widget.phone
        ? await showPiumaSheet<AccountServers>(
            context,
            label: l.accountServersTitle,
            builder: form,
          )
        : await showPiumaDialog<AccountServers>(
            context,
            label: l.accountServersTitle,
            width: 560,
            builder: form,
          );
    if (saved != null && mounted) setState(() => _servers = saved);
  }

  Future<void> _remove() async {
    final l = AppLocalizations.of(context);
    final title = l.accountRemoveTitle(bidiArg(context, _account.name));
    Widget panel(BuildContext context) => RemoveAccountPanel(
      source: widget.source,
      account: _account,
      title: title,
      phone: widget.phone,
    );
    final yes = widget.phone
        ? await showPiumaSheet<bool>(context, label: title, builder: panel)
        : await showPiumaDialog<bool>(
            context,
            label: title,
            width: 480,
            builder: panel,
          );
    if (yes != true || !mounted) return;
    _saveTimer?.cancel();
    try {
      await widget.source.removeAccount(_account.id);
    } on UnsentMailLeft {
      // Written meanwhile (another window, the background): asked again,
      // with the list.
      if (mounted) await _remove();
      return;
    }
    if (mounted) widget.onBack();
  }

  String _ago(AppLocalizations l, DateTime at, String locale) {
    final minutes = widget.now().difference(at).inMinutes;
    if (minutes < 1) return l.accountJustNow;
    if (minutes < 60) return l.accountMinutesAgo(minutes);
    return l.accountAtTime(DateFormat.Hm(locale).format(at));
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final phone = widget.phone;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final health = widget.source.accountHealth(_account.id);
    final failed =
        widget.source.status.value.failed.contains(_account.id) ||
        health.failedSince != null;
    final rowHeight = phone ? 52.0 : 46.0;

    Widget row(String label, Widget value, {VoidCallback? onTap}) {
      final content = ConstrainedBox(
        constraints: BoxConstraints(minHeight: rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(label, style: PiumaType.body.copyWith(color: c.fg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: value,
                ),
              ),
            ],
          ),
        ),
      );
      return onTap == null
          ? content
          : PiumaPressable(onTap: onTap, child: content);
    }

    Widget field(
      TextEditingController controller,
      String label, {
      String? hint,
    }) => Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.end,
        cursorColor: c.accent,
        style: PiumaType.body.copyWith(color: c.muted),
        decoration: InputDecoration.collapsed(
          hintText: hint,
          hintStyle: PiumaType.body.copyWith(color: c.muted),
        ),
      ),
    );

    final signature = _signature;
    final details = _Card(
      children: [
        row(l.accountNameLabel, field(_name, l.accountNameLabel)),
        row(
          l.color,
          Semantics(
            label: l.accountColor,
            // Eight dots share a narrow row: their targets shrink to fit.
            child: LayoutBuilder(
              builder: (context, box) {
                final fit = box.maxWidth / PiumaAccountColors.all.length;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final col in PiumaAccountColors.all)
                      _ColorDot(
                        color: col,
                        selected: col == _account.color,
                        target: min(phone ? 40 : 28, fit),
                        onTap: () => _pickColor(col),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        row(
          l.accountDisplayName,
          field(
            _senderName,
            l.accountDisplayName,
            hint: l.accountDisplayNameNone,
          ),
        ),
        row(
          l.accountDefaultSignature,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  signature == null ? l.noSignature : signature.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.body.copyWith(color: c.muted),
                ),
              ),
              if (widget.onSignature != null) ...[
                const SizedBox(width: 6),
                PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
              ],
            ],
          ),
          onTap: widget.onSignature == null
              ? null
              : () => widget.onSignature!(signature?.id),
        ),
      ],
    );

    final servers = _servers;
    final serverLines = servers == null
        ? ''
        : servers.jmapUrl != null
        ? 'JMAP ${servers.imap.host} · HTTPS'
        : '${_line('IMAP', servers.imap)}\n${_line('SMTP', servers.smtp)}';
    final since = health.failedSince ?? widget.now();
    final connection = _ConnectionCard(
      failed: failed,
      label: l.accountConnection,
      state: failed
          ? l.accountCantSignInSince(DateFormat.Hm(locale).format(since))
          : switch (health.checkedAt) {
              final at? => l.accountWorkingAgo(_ago(l, at, locale)),
              null => l.accountConnecting,
            },
      servers: failed ? null : serverLines,
      note: failed
          ? (health.certificate
                ? l.accountCertificateRefused
                : l.accountPasswordRefused)
          : null,
      action: failed
          ? PiumaButton(
              label: l.signInAgain,
              size: PiumaButtonSize.compact,
              onPressed: () => showSignInAgain(
                context,
                source: widget.source,
                account: _account,
                phone: phone,
              ),
            )
          // An account that signs in with a provider's page keeps the
          // provider's servers: its sign-in goes nowhere else.
          : servers != null &&
                servers.jmapUrl == null &&
                widget.source.accountOAuth(_account.id) == null
          ? _TextLink(label: l.accountEditServers, onTap: _editServers)
          : null,
    );

    final alert = _Card(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.accountSignInAlert,
                          style: PiumaType.body.copyWith(color: c.fg),
                        ),
                        Text(
                          l.accountSignInAlertNote,
                          style: PiumaType.small.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PiumaSwitch(
                  value: _alert,
                  label: l.accountSignInAlert,
                  onChanged: _setAlert,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final away = _away;
    final awayCard = away == null || widget.onAway == null
        ? null
        : _Card(
            children: [
              row(
                l.awayTitle,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        !away.on
                            ? l.awayRowOff
                            : switch (away.end) {
                                final e? => l.awayRowUntil(
                                  DateFormat('EEE d MMM', locale).format(e),
                                ),
                                null => l.awayRowOn,
                              },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PiumaIconView(
                      PiumaIcon.chevronRight,
                      size: 16,
                      color: c.muted,
                    ),
                  ],
                ),
                onTap: widget.onAway,
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!phone) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SettingsBackLink(
              label: widget.backLabel,
              onTap: widget.onBack,
            ),
          ),
          const SizedBox(height: 18),
        ],
        Semantics(
          header: true,
          label: l.accountDetailsLabel(
            bidiArg(context, _account.name),
            bidiArg(context, _account.email),
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: reduceMotion(context)
                      ? Duration.zero
                      : PiumaMotion.press,
                  curve: PiumaMotion.curve,
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _account.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: c.fg,
                        ),
                      ),
                      Text(
                        _account.email,
                        style: PiumaType.body.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        details,
        const SizedBox(height: 14),
        connection,
        QuotaCard(source: widget.source, accountId: _account.id),
        if (awayCard != null) ...[const SizedBox(height: 14), awayCard],
        const SizedBox(height: 14),
        alert,
        const SizedBox(height: 18),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _TextLink(
            label: l.accountRemove,
            color: c.danger,
            onTap: _remove,
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  static String _line(String kind, MailServer s) =>
      '$kind ${s.host}:${s.port} · ${switch (s.security) {
        ServerSecurity.tls => 'SSL',
        ServerSecurity.startTls => 'STARTTLS',
        ServerSecurity.none => '—',
      }}';
}

/// Connection: working, with the servers and Edit servers, or amber when
/// the password is refused, with Sign in again.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.failed,
    required this.label,
    required this.state,
    this.servers,
    this.note,
    this.action,
  });

  final bool failed;
  final String label;
  final String state;
  final String? servers;
  final String? note;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return AnimatedContainer(
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: failed ? c.warnSoft : c.surface,
        border: Border.all(color: failed ? c.warnLine : c.line),
        borderRadius: BorderRadius.circular(PiumaRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              label.toUpperCase(),
              style: PiumaType.small.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.72,
                color: failed ? c.warn : c.muted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: failed ? c.warn : c.ok,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state,
                    style: PiumaType.body.copyWith(color: c.fg),
                  ),
                ),
              ],
            ),
          ),
          if (servers case final s? when s.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              s,
              style: PiumaType.mono.copyWith(
                fontSize: 12,
                height: 1.5,
                color: c.muted,
              ),
            ),
          ],
          if (note case final n?) ...[
            const SizedBox(height: 6),
            Text(n, style: PiumaType.small.copyWith(color: c.muted)),
          ],
          if (action case final a?) ...[const SizedBox(height: 8), a],
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.target,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final double target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: PiumaPressable(
        onTap: onTap,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: AnimatedContainer(
              duration: reduceMotion(context)
                  ? Duration.zero
                  : PiumaMotion.press,
              curve: PiumaMotion.curve,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [
                        // Painted in order: outer ring, then gap.
                        BoxShadow(color: color, spreadRadius: 4),
                        BoxShadow(color: c.surface, spreadRadius: 2),
                      ]
                    : const [],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bordered group of rows with lines between them.
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

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: PiumaType.body.copyWith(color: color ?? c.accentText),
          ),
        ),
      ),
    );
  }
}

/// "‹ Accounts", "‹ Work": back a level, on the desktop.
class SettingsBackLink extends StatelessWidget {
  const SettingsBackLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.chevronLeft, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Text(label, style: PiumaType.body.copyWith(color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit servers: the manual form's servers and user name, checked with
/// the account's password before they are kept.
class _ServersForm extends StatefulWidget {
  const _ServersForm({
    required this.source,
    required this.accountId,
    required this.initial,
    required this.phone,
  });

  final MailSource source;
  final int accountId;
  final AccountServers initial;
  final bool phone;

  @override
  State<_ServersForm> createState() => _ServersFormState();
}

class _ServersFormState extends State<_ServersForm> {
  late final _imapHost = TextEditingController(text: widget.initial.imap.host);
  late final _imapPort = TextEditingController(
    text: '${widget.initial.imap.port}',
  );
  late ServerSecurity _imapSecurity = widget.initial.imap.security;
  late final _smtpHost = TextEditingController(text: widget.initial.smtp.host);
  late final _smtpPort = TextEditingController(
    text: '${widget.initial.smtp.port}',
  );
  late ServerSecurity _smtpSecurity = widget.initial.smtp.security;
  late final _username = TextEditingController(text: widget.initial.username);
  bool _checking = false;
  String? _error;

  /// The certificate a server showed, refused, for the person to trust.
  CertificateProblem? _certificate;

  /// Certificates the person trusted for the new servers: kept by the
  /// engine only once they check out.
  final _trusted = <TrustedCertificate>[];

  @override
  void dispose() {
    for (final t in [_imapHost, _imapPort, _smtpHost, _smtpPort, _username]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final imapPort = validPort(_imapPort.text);
    final smtpPort = validPort(_smtpPort.text);
    if (imapPort == null || smtpPort == null) {
      setState(() {
        _error = l.errorPort;
        _certificate = null;
      });
      return;
    }
    final servers = AccountServers(
      imap: MailServer(_imapHost.text.trim(), imapPort, _imapSecurity),
      smtp: MailServer(_smtpHost.text.trim(), smtpPort, _smtpSecurity),
      username: _username.text.trim(),
    );
    setState(() {
      _checking = true;
      _error = null;
      _certificate = null;
    });
    try {
      await widget.source.setAccountServers(
        widget.accountId,
        servers,
        trusted: List.of(_trusted),
      );
      if (mounted) Navigator.of(context).pop(servers);
    } on AddAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = accountErrorText(l, e.error);
        _certificate = e.certificate;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = l.errorOther;
      });
    }
  }

  /// Saves again trusting the refused certificate too. It is kept for
  /// the account only if the new servers check out with it.
  Future<void> _trust() async {
    final cert = _certificate;
    if (cert == null || !cert.canTrust || _checking) return;
    _trusted
      ..removeWhere((t) => t.host.toLowerCase() == cert.host.toLowerCase())
      ..add(cert.trusted);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget server(
      String label,
      TextEditingController host,
      TextEditingController port,
      ServerSecurity security,
      ValueChanged<ServerSecurity> onSecurity,
    ) {
      final hostField = PiumaTextField(label: label, controller: host);
      final portField = SizedBox(
        width: 84,
        child: PiumaTextField(
          label: l.port,
          controller: port,
          mono: true,
          keyboardType: TextInputType.number,
        ),
      );
      if (widget.phone) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hostField,
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                portField,
                const SizedBox(width: 12),
                Expanded(
                  child: SecurityPicker(
                    value: security,
                    onChanged: onSecurity,
                    phone: true,
                  ),
                ),
              ],
            ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: hostField),
          const SizedBox(width: 12),
          portField,
          const SizedBox(width: 12),
          SecurityPicker(value: security, onChanged: onSecurity),
        ],
      );
    }

    final error = _error;
    // Scrolls when a refused certificate makes it taller than the screen.
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: widget.phone ? 20 : 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.accountServersTitle,
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 18),
          server(
            l.imapServer,
            _imapHost,
            _imapPort,
            _imapSecurity,
            (s) => setState(() {
              _imapSecurity = s;
              _imapPort.text = s == ServerSecurity.tls ? '993' : '143';
            }),
          ),
          const SizedBox(height: 14),
          server(
            l.smtpServer,
            _smtpHost,
            _smtpPort,
            _smtpSecurity,
            (s) => setState(() {
              _smtpSecurity = s;
              _smtpPort.text = s == ServerSecurity.tls ? '465' : '587';
            }),
          ),
          const SizedBox(height: 14),
          PiumaTextField(label: l.username, controller: _username),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error, style: PiumaType.small.copyWith(color: c.danger)),
          ],
          if (_certificate case final cert?) ...[
            const SizedBox(height: 12),
            CertificateCard(problem: cert, onTrust: _checking ? null : _trust),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              PiumaButton(
                label: _checking
                    ? l.accountServersChecking
                    : l.accountServersSave,
                onPressed: _checking ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The question before an account is removed, on the phone in a sheet and
/// on the desktop in a dialog. While mail written in it hasn't gone (the
/// outbox, drafts kept on this device) Remove stays off and each message
/// is listed with Send now (Save now for a draft) and Delete: nothing
/// unsent is ever removed with the account.
class RemoveAccountPanel extends StatefulWidget {
  const RemoveAccountPanel({
    super.key,
    required this.source,
    required this.account,
    required this.title,
    this.phone = false,
  });

  final MailSource source;
  final MailAccount account;
  final String title;
  final bool phone;

  @override
  State<RemoveAccountPanel> createState() => _RemoveAccountPanelState();
}

class _RemoveAccountPanelState extends State<RemoveAccountPanel> {
  /// Null until read.
  List<UnsentMessage>? _unsent;

  /// The messages whose Send now or Delete is under way.
  final _busy = <(int, bool)>{};

  /// The last Send now or Delete failed.
  bool _failed = false;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _load();
    // A message that went (or a draft that was saved) leaves the list.
    _changes = widget.source.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final unsent = await widget.source.unsentMail(widget.account.id);
      if (mounted) setState(() => _unsent = unsent);
    } catch (_) {
      // What was read last stays; Remove stays off until it is read.
    }
  }

  Future<void> _act(
    UnsentMessage m,
    Future<void> Function(UnsentMessage) action,
  ) async {
    final key = (m.id, m.draft);
    setState(() => _busy.add(key));
    var failed = false;
    try {
      await action(m);
    } catch (_) {
      failed = true;
    }
    await _load();
    if (mounted) {
      setState(() {
        _busy.remove(key);
        _failed = failed;
      });
    }
  }

  static String _names(List<String> to) => to
      .map((a) {
        final named = RegExp(r'^\s*"?([^"<]*?)"?\s*<[^>]*>\s*$').firstMatch(a);
        final name = named?.group(1)?.trim() ?? '';
        return name.isEmpty ? a.replaceAll(RegExp('[<>]'), '').trim() : name;
      })
      .join(', ');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final unsent = _unsent;
    final blocked = unsent == null || unsent.isNotEmpty;
    final hint = PiumaType.small.copyWith(color: c.muted);

    Widget item(UnsentMessage m) {
      final busy = _busy.contains((m.id, m.draft));
      final state = m.draft
          ? l.accountUnsentDraft
          : m.sending
          ? l.sending
          : m.refused
          ? l.outboxNotSent
          : l.outboxWaiting;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PiumaSpace.s12,
          vertical: PiumaSpace.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              safeBidi(m.subject.isEmpty ? l.noSubject : m.subject),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PiumaType.body.copyWith(
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            Text(
              [
                state,
                if (m.to.isNotEmpty) l.outboxTo(bidiArg(context, _names(m.to))),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: hint.copyWith(color: m.refused ? c.danger : c.muted),
            ),
            const SizedBox(height: PiumaSpace.s8),
            Wrap(
              spacing: PiumaSpace.s8,
              runSpacing: PiumaSpace.s8,
              children: [
                PiumaButton(
                  label: m.draft
                      ? l.accountUnsentSaveNow
                      : l.accountUnsentSendNow,
                  kind: PiumaButtonKind.secondary,
                  size: PiumaButtonSize.compact,
                  onPressed: busy || m.sending
                      ? null
                      : () => _act(m, widget.source.sendUnsent),
                ),
                PiumaButton(
                  label: l.actionDelete,
                  kind: PiumaButtonKind.tertiary,
                  size: PiumaButtonSize.compact,
                  onPressed: busy || m.sending
                      ? null
                      : () => _act(m, widget.source.deleteUnsent),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final list = unsent ?? const <UnsentMessage>[];
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.phone ? PiumaSpace.s20 : 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: PiumaType.subtitle.copyWith(
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
          const SizedBox(height: PiumaSpace.s8),
          Text(
            l.accountRemoveNote,
            style: PiumaType.body.copyWith(color: c.muted),
          ),
          if (list.isNotEmpty) ...[
            const SizedBox(height: PiumaSpace.s12),
            Text(
              l.accountRemoveBlocked(list.length),
              style: PiumaType.body.copyWith(color: c.danger),
            ),
            const SizedBox(height: PiumaSpace.s12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(PiumaRadius.card),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, m) in list.indexed)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: i == 0
                                ? null
                                : Border(top: BorderSide(color: c.line)),
                          ),
                          child: item(m),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_failed) ...[
            const SizedBox(height: PiumaSpace.s8),
            Text(l.accountUnsentFailed, style: hint.copyWith(color: c.danger)),
          ],
          const SizedBox(height: PiumaSpace.s20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
              const SizedBox(width: PiumaSpace.s8),
              PiumaButton(
                label: l.accountRemoveConfirm,
                kind: PiumaButtonKind.danger,
                onPressed: blocked
                    ? null
                    : () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
