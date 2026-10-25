import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../feedback/report_sheet.dart';
import '../inbox/inbox_screen.dart' show phoneWidth;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/brand.dart';
import '../widgets/button.dart';
import '../widgets/progress.dart';
import '../widgets/text_field.dart';
import 'pair_screen.dart';
import 'providers.dart';
import 'scan_pair.dart';

/// The address; the settings found, or typed in; or, from "Or start
/// from", the PEC provider and a provider's app password.
enum _Step { email, found, manual, pec, provider }

/// Adding an IMAP account, laid out like the desktop `OnboardingDesktop`
/// mockup and following the steps of the phone `Onboarding` flow: the
/// address first, then the settings the engine found (or a manual form).
/// Below [phoneWidth] it takes the phone `Onboarding` pages, starting with
/// the welcome page on first run.
class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({
    super.key,
    required this.source,
    required this.onDone,
    this.onCancel,
    this.now = DateTime.now,
    this.scanner,
  });

  final MailSource source;
  final ValueChanged<MailAccount> onDone;
  final VoidCallback? onCancel;
  final DateTime Function() now;

  /// Reads QR codes when linking with one; left out, the camera.
  final PairScanner? scanner;

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  _Step _step = _Step.email;

  /// First run: nothing to go back to, so the phone starts with a welcome.
  bool get _firstRun => widget.onCancel == null;
  late bool _welcome = _firstRun;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '465');
  final _name = TextEditingController();
  final _sender = TextEditingController();
  ServerSecurity _imapSecurity = ServerSecurity.tls;
  ServerSecurity _smtpSecurity = ServerSecurity.tls;

  /// The manual form sets up one JMAP server instead of IMAP and SMTP.
  bool _jmap = false;
  final _jmapServer = TextEditingController();
  FoundSettings? _found;
  MailProvider? _provider;
  bool _notFound = false;
  bool _showPassword = false;
  bool _busy = false;
  AddAccountError? _error;

  /// The account just connected: "Account connected" shows it until Go to
  /// inbox or Add another account.
  MailAccount? _added;

  /// First run: "I already use Piuma on another device" was tapped, so a
  /// space in the mailbox signed in to leads to pairing.
  bool _joining = false;

  /// The space found in [_added]'s mailbox: `PairPhone` takes over.
  SpaceFound? _space;

  /// "I already use Piuma" on a phone with a camera: `QrPairToApprove`'s
  /// "Link this phone" shows, to scan a linked device's code.
  bool _scanning = false;

  /// Linked with a scanned code: "Phone paired" shows for [_added].
  bool _pairedByCode = false;

  /// After signing in, while joining: the space in the mailbox, if any.
  Future<SpaceFound?> _lookForSpace(MailAccount account) async {
    if (!_joining) return null;
    try {
      return await widget.source.findSpace(account.id);
    } catch (_) {
      return null; // No space reachable: the account works on its own.
    }
  }

  late Color _color = _freeColor();

  /// The first color no account has yet, else round again.
  Color _freeColor() {
    final used = {for (final a in widget.source.accounts) a.color};
    return PiumaAccountColors.all
        .where((c) => !used.contains(c))
        .followedBy(PiumaAccountColors.all)
        .first;
  }

  List<TextEditingController> get _controllers => [
    _email,
    _password,
    _username,
    _imapHost,
    _imapPort,
    _smtpHost,
    _smtpPort,
    _name,
    _sender,
    _jmapServer,
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get _domain {
    final at = _email.text.lastIndexOf('@');
    return at < 0 ? '' : _email.text.substring(at + 1).trim().toLowerCase();
  }

  bool get _emailReady {
    final e = _email.text.trim();
    final at = e.lastIndexOf('@');
    return at > 0 && e.substring(at + 1).contains('.');
  }

  bool get _ready => switch (_step) {
    _Step.email => _emailReady,
    _Step.found => _password.text.isNotEmpty,
    _Step.provider => _emailReady && _password.text.trim().isNotEmpty,
    _Step.pec => false,
    _Step.manual when _jmap =>
      _password.text.isNotEmpty && _jmapServer.text.trim().isNotEmpty,
    _Step.manual =>
      _password.text.isNotEmpty &&
          _username.text.trim().isNotEmpty &&
          _imapHost.text.trim().isNotEmpty &&
          _smtpHost.text.trim().isNotEmpty &&
          int.tryParse(_imapPort.text) != null &&
          int.tryParse(_smtpPort.text) != null,
  };

  void _go(_Step step) => setState(() {
    _step = step;
    _welcome = false;
    _error = null;
  });

  /// Step 1: look the address up.
  Future<void> _lookUp() async {
    if (!_emailReady || _busy) return;
    setState(() => _busy = true);
    FoundSettings? found;
    try {
      found = await widget.source.discoverSettings(_email.text.trim());
    } catch (_) {
      // Looking up is only a shortcut: if it fails, the servers are typed in.
      found = null;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = found;
      _notFound = found == null;
      _fillServers(found);
      _step = found == null ? _Step.manual : _Step.found;
      _error = null;
    });
  }

  void _fillServers(FoundSettings? s) {
    _username.text = s?.username ?? _email.text.trim();
    _imapHost.text = s?.imap.host ?? 'imap.$_domain';
    _imapPort.text = '${s?.imap.port ?? 993}';
    _imapSecurity = s?.imap.security ?? ServerSecurity.tls;
    _smtpHost.text = s?.smtp.host ?? 'smtp.$_domain';
    _smtpPort.text = '${s?.smtp.port ?? 465}';
    _smtpSecurity = s?.smtp.security ?? ServerSecurity.tls;
    _jmapServer.text = s?.jmapUrl ?? 'jmap.$_domain';
    _jmap = s?.jmapUrl != null;
  }

  /// "Or start from": Gmail, iCloud and Fastmail ask for their app
  /// password right away, PEC first for its provider.
  void _startFrom(int i) {
    if (i == 3) return _go(_Step.pec);
    _pick([MailProvider.gmail, MailProvider.icloud, MailProvider.fastmail][i]);
  }

  void _pick(MailProvider provider) {
    _provider = provider;
    _password.clear();
    _go(_Step.provider);
  }

  /// One step back: a PEC provider's password goes back to the providers.
  void _back() => _go(
    _step == _Step.provider && _provider!.isPec ? _Step.pec : _Step.email,
  );

  void _manual() {
    if (_imapHost.text.isEmpty) _fillServers(_found);
    _go(_Step.manual);
  }

  void _submit() => switch (_step) {
    _Step.email => _lookUp(),
    _Step.pec => null,
    _ => _connect(),
  };

  /// From "Account connected" back to an empty address, for the next one.
  void _another() {
    for (final c in [_email, _password, _username, _name, _sender]) {
      c.clear();
    }
    setState(() {
      _added = null;
      _found = null;
      _provider = null;
      _notFound = false;
      _color = _freeColor();
    });
    _go(_Step.email);
  }

  Future<void> _connect() async {
    if (!_ready || _busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final provider = _step == _Step.provider ? _provider : null;
    if (provider != null) return _connectProvider(provider);
    final jmapUrl = switch (_step) {
      _Step.found => _found?.jmapUrl,
      _Step.manual when _jmap => jmapSessionUrl(_jmapServer.text),
      _ => null,
    };
    try {
      final account = jmapUrl != null
          ? await widget.source.addJmapAccount(
              name: _name.text.trim().isEmpty
                  ? l.defaultAccountName
                  : _name.text.trim(),
              email: _email.text.trim(),
              senderName: _sender.text.trim(),
              color: _color,
              sessionUrl: jmapUrl,
              password: _password.text,
            )
          : await widget.source.addImapAccount(
              name: _name.text.trim().isEmpty
                  ? l.defaultAccountName
                  : _name.text.trim(),
              email: _email.text.trim(),
              senderName: _sender.text.trim(),
              color: _color,
              host: _imapHost.text.trim(),
              port: int.parse(_imapPort.text),
              security: _imapSecurity,
              username: _username.text.trim(),
              password: _password.text,
              smtp: MailServer(
                _smtpHost.text.trim(),
                int.parse(_smtpPort.text),
                _smtpSecurity,
              ),
            );
      final found = await _lookForSpace(account);
      if (mounted) {
        setState(() {
          _added = account;
          _space = found;
          _password.clear();
        });
      }
    } on AddAccountException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Connects with a provider's own servers and its app password.
  Future<void> _connectProvider(MailProvider p) async {
    final name = _name.text.trim().isEmpty
        ? (p.isPec ? 'PEC' : p.label)
        : _name.text.trim();
    final email = _email.text.trim();
    final password = p.password(_password.text);
    try {
      final account = p.jmapUrl != null
          ? await widget.source.addJmapAccount(
              name: name,
              email: email,
              color: _color,
              sessionUrl: p.jmapUrl!,
              password: password,
              apiToken: true,
            )
          : await widget.source.addImapAccount(
              name: name,
              email: email,
              color: _color,
              host: p.imap!.host,
              port: p.imap!.port,
              security: p.imap!.security,
              username: email,
              password: password,
              smtp: p.smtp,
            );
      final found = await _lookForSpace(account);
      if (mounted) {
        setState(() {
          _added = account;
          _space = found;
          _password.clear();
        });
      }
    } on AddAccountException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final phone = box.maxWidth < phoneWidth;
      if (_scanning) {
        return ScanPairScreen(
          source: widget.source,
          scanner: widget.scanner,
          onSignIn: () => setState(() {
            _scanning = false;
            _joining = true;
          }),
          onJoined: (account) => setState(() {
            _scanning = false;
            _added = account;
            _pairedByCode = true;
          }),
        );
      }
      if (_pairedByCode && _added != null) {
        return PairScreen(
          source: widget.source,
          account: _added!,
          found: null,
          paired: true,
          phone: phone,
          now: widget.now,
          onDone: () => widget.onDone(_added!),
          onSkip: () {},
        );
      }
      if ((_added, _space) case (final account?, final found?)) {
        return PairScreen(
          source: widget.source,
          account: account,
          found: found,
          phone: phone,
          now: widget.now,
          onDone: () => widget.onDone(account),
          onSkip: () => setState(() {
            _space = null;
            _joining = false;
          }),
        );
      }
      return phone ? _phone(context) : _desktop(context);
    },
  );

  Widget _desktop(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PiumaBrand(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: PiumaEnter(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(
                            PiumaRadius.panel,
                          ),
                        ),
                        // In front, so the accounts panel can't cover it.
                        foregroundDecoration: BoxDecoration(
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(
                            PiumaRadius.panel,
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: CallbackShortcuts(
                                  bindings: {
                                    const SingleActivator(
                                      LogicalKeyboardKey.escape,
                                    ): () {
                                      if (_step != _Step.email) _back();
                                    },
                                  },
                                  child: PiumaEnter(
                                    key: ValueKey(_added?.id ?? _step),
                                    child: _added == null
                                        ? _form(context)
                                        : _desktopConnected(context, _added!),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 340,
                                child: _AccountsPanel(
                                  accounts: widget.source.accounts,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final (step, title) = switch (_step) {
      _Step.email => (1, l.whatsYourEmail),
      _Step.found => (2, l.weFoundSettings),
      _Step.manual => (2, l.setUpManually),
      _Step.pec => (2, l.pecWhichProvider),
      _Step.provider => (2, _provider!.title(l)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_step != _Step.email) ...[
                _TextLink(label: l.back, onTap: _back),
                Text(' · ', style: TextStyle(fontSize: 13, color: c.muted)),
              ],
              Text(
                '${l.addAccount} · ${l.stepOf(step, 3)}',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.9,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 8),
          ...switch (_step) {
            _Step.email => _emailStep(context),
            _Step.found => _foundStep(context),
            _Step.manual => _manualStep(context),
            _Step.pec => _pecStep(context),
            _Step.provider => _providerStep(context),
          },
          if (_step != _Step.pec) ...[
            const SizedBox(height: 24),
            _actions(context),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            PiumaEnter(
              child: Text(switch (_error!) {
                AddAccountError.wrongPassword => l.errorWrongPassword,
                AddAccountError.unreachable => l.errorUnreachable,
                AddAccountError.insecure => l.errorInsecure,
                AddAccountError.keychain => l.errorKeychain,
                AddAccountError.other => l.errorOther,
              }, style: TextStyle(fontSize: 14, color: c.danger)),
            ),
            _reportLink(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _emailStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      Text(l.findSettingsHint, style: TextStyle(fontSize: 15, color: c.muted)),
      const SizedBox(height: 24),
      PiumaTextField(
        label: l.emailAddress,
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _submit(),
      ),
      ..._startFromGrid(context),
    ];
  }

  List<Widget> _startFromGrid(BuildContext context, {bool phone = false}) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      SizedBox(height: phone ? 28 : 20),
      Text(l.orStartFrom, style: TextStyle(fontSize: 13, color: c.muted)),
      const SizedBox(height: 10),
      ProviderGrid(
        labels: const ['Gmail', 'iCloud', 'Fastmail', 'PEC'],
        phone: phone,
        onPick: _busy ? (_) {} : _startFrom,
      ),
      if (_firstRun) ...[
        SizedBox(height: phone ? 22 : 18),
        if (_joining)
          Text(
            l.pairAlreadyOn,
            textAlign: phone ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: 13, color: c.muted),
          )
        else
          Align(
            alignment: phone ? Alignment.center : Alignment.centerLeft,
            child: _TextLink(
              label: l.pairAlready,
              onTap: () => setState(() {
                if (widget.source.canScan) {
                  _scanning = true;
                } else {
                  _joining = true;
                }
              }),
            ),
          ),
      ],
    ];
  }

  /// Which provider runs the PEC mailbox.
  List<Widget> _pecStep(BuildContext context, {bool phone = false}) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      Text(
        l.pecWhichProviderHint,
        style: TextStyle(fontSize: 15, color: c.muted),
      ),
      const SizedBox(height: 24),
      ProviderGrid(
        labels: [for (final p in MailProvider.pec) p.shortLabel],
        phone: phone,
        onPick: (i) => _pick(MailProvider.pec[i]),
      ),
    ];
  }

  /// A provider's steps for its app password, the address and the
  /// password.
  List<Widget> _providerStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = _provider!;
    return [
      const SizedBox(height: 4),
      ProviderSteps(provider: p),
      const SizedBox(height: 20),
      PiumaTextField(
        label: l.emailAddress,
        controller: _email,
        autofocus: !_emailReady,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      _passwordField(
        context,
        autofocus: _emailReady,
        label: p.passwordLabel(l),
        mono: !p.isPec,
        hint: p.example,
      ),
    ];
  }

  List<Widget> _foundStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final found = _found!;
    return [
      Row(
        children: [
          PiumaIconView(PiumaIcon.check, size: 15, color: c.ok),
          const SizedBox(width: 6),
          Text(_email.text.trim(), style: TextStyle(fontSize: 14, color: c.ok)),
        ],
      ),
      if (found.source == SettingsSource.guessed) ...[
        const SizedBox(height: 6),
        Text(l.guessedSettings, style: TextStyle(fontSize: 13, color: c.muted)),
      ],
      const SizedBox(height: 24),
      _ServerSummary(found: found),
      const SizedBox(height: 24),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 11, child: _passwordField(context, autofocus: true)),
          const SizedBox(width: 16),
          Expanded(flex: 9, child: _accountNameField(context)),
        ],
      ),
      const SizedBox(height: 16),
      _senderField(context),
      const SizedBox(height: 14),
      _ColorPicker(
        value: _color,
        onChanged: (col) => setState(() => _color = col),
      ),
    ];
  }

  List<Widget> _manualStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    const gap = SizedBox(height: 16);
    Widget serverRow(
      String label,
      TextEditingController host,
      TextEditingController port,
      ServerSecurity security,
      ValueChanged<ServerSecurity> onSecurity,
    ) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: PiumaTextField(
            label: label,
            controller: host,
            mono: true,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 84,
          child: PiumaTextField(
            label: l.port,
            controller: port,
            mono: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 12),
        SecurityPicker(value: security, onChanged: onSecurity),
      ],
    );
    final head = [
      Text(
        _notFound ? l.settingsNotFound : _email.text.trim(),
        style: TextStyle(fontSize: 14, color: c.muted),
      ),
      const SizedBox(height: 24),
      ProtocolPicker(jmap: _jmap, onChanged: _pickProtocol),
      gap,
    ];
    final names = [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _accountNameField(context)),
          const SizedBox(width: 16),
          Expanded(child: _senderField(context)),
        ],
      ),
      const SizedBox(height: 14),
      _ColorPicker(
        value: _color,
        onChanged: (col) => setState(() => _color = col),
      ),
    ];
    if (_jmap) {
      return [
        ...head,
        PiumaTextField(
          label: l.jmapServer,
          controller: _jmapServer,
          mono: true,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 6),
        Text(l.jmapServerHint, style: TextStyle(fontSize: 12, color: c.muted)),
        gap,
        _passwordField(context),
        const SizedBox(height: 6),
        Text(l.jmapSignsIn, style: TextStyle(fontSize: 12, color: c.muted)),
        gap,
        ...names,
      ];
    }
    return [
      ...head,
      serverRow(
        l.imapServer,
        _imapHost,
        _imapPort,
        _imapSecurity,
        (s) => setState(() {
          _imapSecurity = s;
          _imapPort.text = s == ServerSecurity.tls ? '993' : '143';
        }),
      ),
      gap,
      serverRow(
        l.smtpServer,
        _smtpHost,
        _smtpPort,
        _smtpSecurity,
        (s) => setState(() {
          _smtpSecurity = s;
          _smtpPort.text = s == ServerSecurity.tls ? '465' : '587';
        }),
      ),
      gap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PiumaTextField(
              label: l.username,
              controller: _username,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _passwordField(context)),
        ],
      ),
      const SizedBox(height: 6),
      Text(l.usedForBoth, style: TextStyle(fontSize: 12, color: c.muted)),
      gap,
      ...names,
    ];
  }

  void _pickProtocol(bool jmap) => setState(() {
    _jmap = jmap;
    _error = null;
  });

  Widget _passwordField(
    BuildContext context, {
    bool autofocus = false,
    String? label,
    bool mono = false,
    String? hint,
  }) {
    final l = AppLocalizations.of(context);
    return PiumaTextField(
      label: label ?? l.password,
      controller: _password,
      obscure: !_showPassword,
      autofocus: autofocus,
      mono: mono,
      hint: hint,
      autofillHints: const [AutofillHints.password],
      onSubmitted: (_) => _submit(),
      trailing: PiumaButton(
        label: _showPassword ? l.hide : l.show,
        kind: PiumaButtonKind.tertiary,
        size: PiumaButtonSize.compact,
        onPressed: () => setState(() => _showPassword = !_showPassword),
      ),
    );
  }

  Widget _accountNameField(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PiumaTextField(
      label: l.accountName,
      controller: _name,
      onSubmitted: (_) => _submit(),
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _senderField(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PiumaTextField(
          label: l.yourName,
          controller: _sender,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 6),
        Text(l.yourNameHint, style: TextStyle(fontSize: 12, color: c.muted)),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final (label, busyLabel) = switch (_step) {
      _Step.email => (l.continueAction, l.lookingUp),
      _Step.found => (l.connect, l.connecting),
      _Step.manual => (l.verifyAndConnect, l.connecting),
      _Step.pec || _Step.provider => (l.connect, l.connecting),
    };
    return Row(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge(_controllers),
          builder: (context, _) => PiumaButton(
            label: _busy ? busyLabel : label,
            size: PiumaButtonSize.touch,
            onPressed: _ready && !_busy ? _submit : null,
          ),
        ),
        if (_step == _Step.email || _step == _Step.found) ...[
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: _email,
            builder: (context, _) => PiumaButton(
              label: l.setUpManually,
              kind: PiumaButtonKind.tertiary,
              size: PiumaButtonSize.touch,
              onPressed: _emailReady && !_busy ? _manual : null,
            ),
          ),
        ],
        if (widget.onCancel != null && _step == _Step.email) ...[
          const SizedBox(width: 4),
          PiumaButton(
            label: l.notNow,
            kind: PiumaButtonKind.tertiary,
            size: PiumaButtonSize.touch,
            onPressed: widget.onCancel,
          ),
        ],
        const SizedBox(width: 12),
        // The key's hint gives way first in a narrow card (an iPad held
        // upright).
        if (_step != _Step.email)
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '↵ ',
                    style: TextStyle(fontFamily: PiumaFonts.mono),
                  ),
                  TextSpan(text: l.enterToConnect),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }

  /// The phone `Onboarding` pages: one step per screen, "‹ Back" and the
  /// step on top, the main action at the foot.
  Widget _phone(BuildContext context) {
    final c = PiumaTheme.of(context);
    final VoidCallback? back = _welcome
        ? null
        : switch (_step) {
            _Step.email =>
              _firstRun
                  ? () => setState(() => _welcome = true)
                  : widget.onCancel,
            _ => _back,
          };
    return PopScope(
      // System Back walks the steps back; from the address it leaves.
      // Once connected there is nothing to go back to.
      canPop:
          _added == null &&
          (back == null || (_step == _Step.email && !_firstRun)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(
          child: PiumaEnter(
            key: ValueKey(_added?.id ?? (_welcome ? null : _step)),
            child: _added != null
                ? _phoneConnected(context, _added!)
                : _welcome
                ? _phoneWelcome(context)
                : _phoneStep(context, back),
          ),
        ),
      ),
    );
  }

  /// Step 3 on the desktop: "Account connected" in the form's place.
  Widget _desktopConnected(BuildContext context, MailAccount account) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 40, 48, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l.addAccount} · ${l.stepOf(3, 3)}',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
          const SizedBox(height: 18),
          _Connected(source: widget.source, account: account),
          const SizedBox(height: 28),
          Row(
            children: [
              PiumaButton(
                label: l.goToInbox,
                size: PiumaButtonSize.touch,
                onPressed: () => widget.onDone(account),
              ),
              const SizedBox(width: 12),
              PiumaButton(
                label: l.addAnotherAccount,
                kind: PiumaButtonKind.tertiary,
                size: PiumaButtonSize.touch,
                onPressed: _another,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Step 3 on the phone, as `OnboardingDone`: the account and its first
  /// download in the middle, Go to inbox at the foot.
  Widget _phoneConnected(BuildContext context, MailAccount account) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                l.stepOf(3, 3),
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 30),
                child: _Connected(source: widget.source, account: account),
              ),
            ),
          ),
          PiumaButton(
            label: l.goToInbox,
            size: PiumaButtonSize.large,
            onPressed: () => widget.onDone(account),
          ),
          const SizedBox(height: 8),
          PiumaButton(
            label: l.addAnotherAccount,
            kind: PiumaButtonKind.tertiary,
            size: PiumaButtonSize.large,
            onPressed: _another,
          ),
        ],
      ),
    );
  }

  Widget _phoneWelcome(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PiumaBrand(size: 44, stacked: true),
                const SizedBox(height: 14),
                Text(
                  l.motto,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.44,
                    color: c.fg,
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    l.welcomeLead,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: c.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          PiumaButton(
            label: l.addAccount,
            size: PiumaButtonSize.large,
            onPressed: () => _go(_Step.email),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiumaIconView(PiumaIcon.lock, size: 14, color: c.muted),
              const SizedBox(width: 7),
              Text(
                l.staysOnDevice,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _phoneStep(BuildContext context, VoidCallback? back) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final (step, title) = switch (_step) {
      _Step.email => (1, l.whatsYourEmail),
      _Step.found => (2, l.weFoundSettings),
      _Step.manual => (2, l.setUpManually),
      _Step.pec => (2, l.pecWhichProvider),
      _Step.provider => (2, _provider!.title(l)),
    };
    final (label, busyLabel) = switch (_step) {
      _Step.email => (l.continueAction, l.lookingUp),
      _Step.found => (l.connect, l.connecting),
      _Step.manual => (l.verifyAndConnect, l.connecting),
      _Step.pec || _Step.provider => (l.connect, l.connecting),
    };
    final action = ListenableBuilder(
      listenable: Listenable.merge(_controllers),
      builder: (context, _) => PiumaButton(
        label: _busy ? busyLabel : label,
        size: PiumaButtonSize.large,
        onPressed: _ready && !_busy ? _submit : null,
      ),
    );
    final titleStyle = TextStyle(
      fontSize: _step == _Step.email ? 28 : 26,
      height: 1.12,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      color: c.fg,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              if (back != null)
                PiumaPressable(
                  onTap: back,
                  semanticLabel: l.back,
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
                              l.back,
                              style: TextStyle(
                                fontSize: 16,
                                color: c.accentText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 44),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  l.stepOf(step, 3),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step == _Step.found) ...[
                  Row(
                    children: [
                      PiumaIconView(PiumaIcon.check, size: 15, color: c.ok),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _email.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: c.ok,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                Text(title, style: titleStyle),
                const SizedBox(height: 6),
                ...switch (_step) {
                  _Step.email => _phoneEmail(context, action),
                  _Step.found => _phoneFound(context),
                  _Step.manual => _phoneManual(context),
                  _Step.pec => _pecStep(context, phone: true),
                  _Step.provider => _providerStep(context),
                },
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  PiumaEnter(
                    child: Text(
                      _errorText(l),
                      style: TextStyle(fontSize: 14, color: c.danger),
                    ),
                  ),
                  _reportLink(context),
                ],
              ],
            ),
          ),
        ),
        if (_step == _Step.email)
          Center(
            child: ListenableBuilder(
              listenable: _email,
              builder: (context, _) => PiumaButton(
                label: l.setUpManually,
                kind: PiumaButtonKind.tertiary,
                size: PiumaButtonSize.touch,
                onPressed: _emailReady && !_busy ? _manual : null,
              ),
            ),
          )
        else if (_step != _Step.pec)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: action,
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  List<Widget> _phoneEmail(BuildContext context, Widget action) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return [
      Text(l.findSettingsHint, style: TextStyle(fontSize: 15, color: c.muted)),
      const SizedBox(height: 24),
      PiumaTextField(
        label: l.emailAddress,
        controller: _email,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 12),
      action,
      ..._startFromGrid(context, phone: true),
    ];
  }

  List<Widget> _phoneFound(BuildContext context) {
    const gap = SizedBox(height: 16);
    return [
      const SizedBox(height: 12),
      _ServerSummary(found: _found!, onEdit: _manual),
      const SizedBox(height: 20),
      _passwordField(context, autofocus: true),
      gap,
      _accountNameField(context),
      gap,
      _senderField(context),
      const SizedBox(height: 12),
      _ColorPicker(
        value: _color,
        phone: true,
        onChanged: (col) => setState(() => _color = col),
      ),
    ];
  }

  List<Widget> _phoneManual(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    const gap = SizedBox(height: 16);
    Widget server(
      String kind,
      String role,
      TextEditingController host,
      TextEditingController port,
      ServerSecurity security,
      ValueChanged<ServerSecurity> onSecurity,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$kind  ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.48,
                    color: c.fg,
                  ),
                ),
                TextSpan(
                  text: role,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
        ),
        _PhoneCard(
          rows: [
            _PhoneField(
              label: l.serverHost,
              controller: host,
              mono: true,
              onSubmitted: (_) => _submit(),
            ),
            _PhoneField(
              label: l.port,
              controller: port,
              mono: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
            ),
            _PhoneRow(
              label: l.security,
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
    final head = [
      Text(
        _notFound ? l.settingsNotFound : _email.text.trim(),
        style: TextStyle(fontSize: 14, color: c.muted),
      ),
      const SizedBox(height: 18),
      ProtocolPicker(jmap: _jmap, onChanged: _pickProtocol, phone: true),
    ];
    final names = [
      const SizedBox(height: 20),
      _accountNameField(context),
      gap,
      _senderField(context),
      const SizedBox(height: 12),
      _ColorPicker(
        value: _color,
        phone: true,
        onChanged: (col) => setState(() => _color = col),
      ),
    ];
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
    );
    if (_jmap) {
      return [
        ...head,
        const SizedBox(height: 18),
        _PhoneCard(
          rows: [
            _PhoneField(
              label: l.serverHost,
              controller: _jmapServer,
              mono: true,
              onSubmitted: (_) => _submit(),
            ),
            _PhoneField(
              label: l.password,
              controller: _password,
              obscure: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        note(l.jmapSignsIn),
        ...names,
      ];
    }
    return [
      ...head,
      server(
        'IMAP',
        l.incoming,
        _imapHost,
        _imapPort,
        _imapSecurity,
        (s) => setState(() {
          _imapSecurity = s;
          _imapPort.text = s == ServerSecurity.tls ? '993' : '143';
        }),
      ),
      server(
        'SMTP',
        l.outgoing,
        _smtpHost,
        _smtpPort,
        _smtpSecurity,
        (s) => setState(() {
          _smtpSecurity = s;
          _smtpPort.text = s == ServerSecurity.tls ? '465' : '587';
        }),
      ),
      const SizedBox(height: 18),
      _PhoneCard(
        rows: [
          _PhoneField(
            label: l.username,
            controller: _username,
            onSubmitted: (_) => _submit(),
          ),
          _PhoneField(
            label: l.password,
            controller: _password,
            obscure: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      note(l.usedForBoth),
      ...names,
    ];
  }

  /// Under an error: the report sheet, with Problem picked and a title.
  /// What was typed stays out of it; the log hides addresses and servers.
  Widget _reportLink(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PiumaEnter(
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _TextLink(
              label: l.reportThisProblem,
              onTap: () => openReport(
                context,
                source: widget.source,
                title: l.reportCantAddAccount,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(AppLocalizations l) => switch (_error!) {
    AddAccountError.wrongPassword => l.errorWrongPassword,
    AddAccountError.unreachable => l.errorUnreachable,
    AddAccountError.insecure => l.errorInsecure,
    AddAccountError.keychain => l.errorKeychain,
    AddAccountError.other => l.errorOther,
  };
}

/// A grouped card of the phone's manual form: one setting per row.
/// "Account connected": the check, the title, and a card with the account
/// and how its first download goes (`OnboardingDone`).
class _Connected extends StatelessWidget {
  const _Connected({required this.source, required this.account});

  final MailSource source;
  final MailAccount account;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final name = account.name.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
          child: Center(
            child: PiumaIconView(
              PiumaIcon.check,
              size: 24,
              color: c.accentText,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          l.accountConnected,
          style: TextStyle(
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.9,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.accountConnectedLead,
          style: TextStyle(fontSize: 15, height: 1.4, color: c.muted),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(PiumaSpace.s16),
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.card + 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: account.color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          name.isEmpty ? '' : name.characters.first,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            // White on the account's color in both themes.
                            color: PiumaColors.light.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: PiumaSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: c.fg,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: account.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          account.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<SyncStatus>(
                valueListenable: source.status,
                builder: (context, s, _) {
                  final mine = s.downloading == account.id && s.total > 0;
                  final waiting = s.phase == SyncPhase.downloading && !mine;
                  final part = mine ? (s.done / s.total).clamp(0.0, 1.0) : 1.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PiumaProgress(
                        // Waiting for another account: not known yet.
                        value: waiting ? null : part,
                        color: account.color,
                        track: c.chip,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              mine || waiting
                                  ? l.connectedDownloading
                                  : l.connectedUpToDate,
                              style: TextStyle(fontSize: 13, color: c.muted),
                            ),
                          ),
                          if (mine)
                            Text(
                              '${number.format(s.done)} / '
                              '${number.format(s.total)}',
                              style: TextStyle(
                                fontFamily: PiumaFonts.mono,
                                fontSize: 12,
                                color: c.muted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.rows});
  final List<Widget> rows;

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
          for (final (i, row) in rows.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.line)),
              ),
              child: row,
            ),
        ],
      ),
    );
  }
}

/// A label on the left and its control on the right.
class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A borderless field inside a [_PhoneCard].
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.label,
    required this.controller,
    this.mono = false,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool mono;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return _PhoneRow(
      label: label,
      child: Semantics(
        label: label,
        textField: true,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          cursorColor: c.accent,
          style: TextStyle(
            fontFamily: mono ? PiumaFonts.mono : PiumaFonts.sans,
            fontSize: mono ? 14 : 15,
            color: c.fg,
          ),
          decoration: const InputDecoration.collapsed(hintText: ''),
        ),
      ),
    );
  }
}

/// The found servers, as in the mockup: kind, host, role · port · TLS. A
/// JMAP account has one row for both directions.
class _ServerSummary extends StatelessWidget {
  const _ServerSummary({required this.found, this.onEdit});
  final FoundSettings found;

  /// On the phone: host over "role · port · TLS", and Edit on the last row.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    // "Incoming · 993 · SSL", the port in mono.
    List<InlineSpan> detail(String role, MailServer s) => [
      TextSpan(text: '$role · '),
      TextSpan(
        text: '${s.port}',
        style: TextStyle(fontFamily: PiumaFonts.mono),
      ),
      TextSpan(
        text:
            ' · ${switch (s.security) {
              ServerSecurity.tls => 'SSL',
              ServerSecurity.startTls => 'STARTTLS',
              ServerSecurity.none => '—',
            }}',
      ),
    ];
    Widget row(
      String kind,
      String host,
      List<InlineSpan> detail, {
      bool last = false,
    }) {
      if (onEdit != null) {
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  kind,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.48,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: PiumaFonts.mono,
                        fontSize: 14,
                        color: c.fg,
                      ),
                    ),
                    Text.rich(
                      TextSpan(children: detail),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
              if (last)
                PiumaButton(
                  label: l.editServers,
                  kind: PiumaButtonKind.tertiary,
                  size: PiumaButtonSize.compact,
                  onPressed: onEdit,
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                kind,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.48,
                  color: c.muted,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: PiumaFonts.mono,
                  fontSize: 14,
                  color: c.fg,
                ),
              ),
            ),
            Text.rich(
              TextSpan(children: detail),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (found.jmapHost case final host?)
            row('JMAP', host, [
              TextSpan(text: '${l.incomingAndOutgoing} · HTTPS'),
            ], last: true)
          else ...[
            row('IMAP', found.imap.host, detail(l.incoming, found.imap)),
            row(
              'SMTP',
              found.smtp.host,
              detail(l.outgoing, found.smtp),
              last: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: c.accentText,
        ),
      ),
    );
  }
}

/// SSL/TLS or STARTTLS, as a segmented control; also in an account's
/// servers.
class SecurityPicker extends StatelessWidget {
  const SecurityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.phone = false,
  });
  final ServerSecurity value;
  final ValueChanged<ServerSecurity> onChanged;

  /// Inside a phone card row: no label, the options share the width.
  final bool phone;

  @override
  Widget build(BuildContext context) => _Segments(
    label: phone ? null : AppLocalizations.of(context).security,
    value: value,
    options: const {
      ServerSecurity.tls: 'SSL/TLS',
      ServerSecurity.startTls: 'STARTTLS',
    },
    onChanged: onChanged,
    phone: phone,
  );
}

/// The manual form's choice: IMAP and SMTP, or one JMAP server.
class ProtocolPicker extends StatelessWidget {
  const ProtocolPicker({
    super.key,
    required this.jmap,
    required this.onChanged,
    this.phone = false,
  });
  final bool jmap;
  final ValueChanged<bool> onChanged;

  /// Full width, as the phone's cards are.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Segments(
      label: l.serverType,
      value: jmap,
      options: {false: l.imapAndSmtp, true: 'JMAP'},
      onChanged: onChanged,
      phone: phone,
    );
  }
}

/// A row of options on a soft track; the one picked is raised.
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.phone,
  });
  final String? label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    Widget option(T v, String label) {
      final on = value == v;
      return Semantics(
        selected: on,
        button: true,
        child: PiumaPressable(
          onTap: () => onChanged(v),
          semanticLabel: label,
          child: AnimatedContainer(
            duration: PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.surface : null,
              borderRadius: BorderRadius.circular(7),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : const [],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? c.fg : c.muted,
              ),
            ),
          ),
        ),
      );
    }

    final track = phone
        ? Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: Row(
              children: [
                for (final MapEntry(:key, :value) in options.entries)
                  Expanded(child: option(key, value)),
              ],
            ),
          )
        : Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final MapEntry(:key, :value) in options.entries)
                  option(key, value),
              ],
            ),
          );
    if (label == null) return track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label!,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        track,
      ],
    );
  }
}

/// Where a JMAP session lives: a full URL as typed, or the server's
/// well-known address.
String jmapSessionUrl(String server) {
  final s = server.trim();
  if (s.startsWith('https://') || s.startsWith('http://')) return s;
  return 'https://$s/.well-known/jmap';
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.value,
    required this.onChanged,
    this.phone = false,
  });
  final Color value;
  final ValueChanged<Color> onChanged;

  /// The label above and larger dots, each a finger-sized target.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final label = Text(
      l.color,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );
    final dot = phone ? 24.0 : 20.0;
    List<Widget> dotsIn(double target) => [
      for (final col in PiumaAccountColors.all)
        Semantics(
          selected: col == value,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(col),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox.square(
                dimension: target,
                child: Center(
                  child: AnimatedContainer(
                    duration: PiumaMotion.press,
                    curve: PiumaMotion.curve,
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      boxShadow: col == value
                          ? [
                              // Painted in order: outer ring, then gap.
                              BoxShadow(color: col, spreadRadius: 4),
                              BoxShadow(color: c.surface, spreadRadius: 2),
                            ]
                          : const [],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    return Semantics(
      label: l.accountColor,
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 4),
                // Eight dots share a narrow phone: their targets shrink to
                // fit, down from 44.
                LayoutBuilder(
                  builder: (context, box) => Transform.translate(
                    offset: const Offset(-10, 0),
                    child: Row(
                      children: dotsIn(
                        min(44, box.maxWidth / PiumaAccountColors.all.length),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                SizedBox(width: 56, child: label),
                ...dotsIn(32),
              ],
            ),
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  const _AccountsPanel({required this.accounts});
  final List<MailAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 36),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.yourAccounts.toUpperCase(),
            style: PiumaType.label.copyWith(
              color: c.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (accounts.isEmpty)
            Text(
              l.noAccountsYet,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
            ),
          for (final a in accounts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: a.color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      a.name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: c.fg,
                          ),
                        ),
                        Text(
                          a.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  PiumaIconView(PiumaIcon.check, size: 13, color: c.ok),
                  const SizedBox(width: 5),
                  Text(
                    l.connected,
                    style: TextStyle(fontSize: 12, color: c.ok),
                  ),
                ],
              ),
            ),
          const Spacer(),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: PiumaIconView(PiumaIcon.lock, size: 15, color: c.muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.privacyNote,
                  style: TextStyle(fontSize: 13, height: 1.5, color: c.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
