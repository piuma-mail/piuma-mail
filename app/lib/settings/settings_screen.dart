import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/look.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/message_list.dart' show initials;
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../version.dart';
import '../widgets/button.dart';
import '../widgets/segments.dart';
import '../widgets/switch.dart';
import '../widgets/verified.dart';
import '../feedback/help_page.dart';
import 'account_page.dart';
import 'appearance_page.dart';
import 'away_page.dart';
import 'calendars_page.dart';
import 'rules_page.dart';
import 'shortcuts_page.dart';
import 'signatures_page.dart';
import 'groups_page.dart';
import 'sync_page.dart';
import 'templates_page.dart';

/// Settings' sections, in the order of `SettingsOrderToApprove` (B):
/// the accounts, then Mail, App and About.
enum SettingsSection {
  accounts,

  /// Groups of addresses: opened from the accounts.
  groups,

  /// Signatures, then templates.
  writing,

  /// Writing, opened on its templates.
  templates,

  /// Density, preview lines and the on-device helpers.
  reading,

  /// The zone switches, rules, folders and labels.
  organizing,
  calendars,
  appearance,
  notifications,
  privacy,
  sync,

  /// Desktop only: phones have no keyboard to speak of.
  shortcuts,

  /// Report a problem, suggest an idea, the reports made, updates.
  help,
}

/// Settings, as in `DesktopPrivacy` sorted as `SettingsOrderToApprove`
/// (B): sections on the left under Mail, App and About, the chosen one on
/// the right.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.source,
    required this.onBack,
    required this.onAddAccount,
    this.section = SettingsSection.accounts,
    this.onWrite,
    this.signature,
    this.account,
    this.now = DateTime.now,
  });

  final MailSource source;
  final VoidCallback onBack;
  final VoidCallback onAddAccount;
  final SettingsSection section;

  /// Leaves Settings for compose with this draft (a report sent by
  /// email instead).
  final ValueChanged<Draft>? onWrite;

  /// With [SettingsSection.writing], the signature to open.
  final int? signature;

  /// With [SettingsSection.accounts], the account whose details open.
  final int? account;
  final DateTime Function() now;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsSection _section = widget.section;
  StreamSubscription<void>? _changes;

  /// On the phone, the section open over the list; null shows the list.
  /// Settings opened on a section (from compose) start there.
  late SettingsSection? _open = widget.section == SettingsSection.accounts
      ? null
      : widget.section;

  final _signatures = GlobalKey<SignaturesPageState>();

  /// The account whose details are open, over the accounts.
  late MailAccount? _account = widget.source.accounts
      .where((a) => a.id == widget.account)
      .firstOrNull;

  /// The open account's away message is open over its details.
  bool _away = false;

  /// The signature Signatures opens on.
  late int? _signature = widget.signature;

  /// From an account's details to its default signature.
  void _openSignature(int? id) => setState(() {
    _account = null;
    _away = false;
    _signature = id;
    _section = SettingsSection.writing;
    _open = SettingsSection.writing;
  });

  /// What the phone list shows beside Signatures and Notifications.
  int? _signatureCount;
  int? _groupCount;
  NotifyMode? _notifyMode;
  int? _ruleCount;
  int? _calendarCount;

  @override
  void initState() {
    super.initState();
    _changes = widget.source.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final signatures = await widget.source.signatures();
      final groups = await widget.source.groups();
      final notify = await widget.source.notifySettings();
      final rules = await widget.source.rules();
      final calendars = await widget.source.calendarSources();
      if (!mounted) return;
      setState(() {
        _signatureCount = signatures.length;
        _groupCount = groups.length;
        _notifyMode = notify.mode;
        _ruleCount = rules.length;
        _calendarCount = calendars.fold<int>(
          0,
          (n, s) => n + s.calendars.length,
        );
      });
    } catch (_) {
      // The list shows no values then.
    }
  }

  /// The sidebar item lit for [_section]: Groups open from Accounts, and
  /// the templates are part of Writing.
  SettingsSection get _navSection => switch (_section) {
    SettingsSection.groups => SettingsSection.accounts,
    SettingsSection.templates => SettingsSection.writing,
    final s => s,
  };

  void _close() {
    setState(() => _open = null);
    _loadSummary();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        box.maxWidth < 600 ? _phone(context) : _desktop(context),
  );

  /// `SettingsPhone`: the list of sections, each opening full screen.
  Widget _phone(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final open = _open;
    final mode = _notifyMode;
    final Widget page;
    final account = _account;
    if (open == null && account != null && _away) {
      page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneBack(
            label: account.name,
            onTap: () => setState(() => _away = false),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: PiumaEnter(
                child: AwayPage(
                  key: ValueKey(('away', account.id)),
                  source: widget.source,
                  account: account,
                  phone: true,
                  onBack: () => setState(() => _away = false),
                  now: widget.now,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (open == null && account != null) {
      page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneBack(
            label: l.settings,
            onTap: () => setState(() => _account = null),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: AccountPage(
                key: ValueKey(account.id),
                source: widget.source,
                account: account,
                phone: true,
                backLabel: l.settings,
                onBack: () => setState(() => _account = null),
                onSignature: _openSignature,
                onAway: () => setState(() => _away = true),
                now: widget.now,
              ),
            ),
          ),
        ],
      );
    } else if (open == null) {
      page = _PhoneList(
        onAccount: (a) => setState(() => _account = a),
        accounts: widget.source.accounts,
        onBack: widget.onBack,
        onAddAccount: widget.onAddAccount,
        onOpen: (s) => setState(() => _open = s),
        signatures: _signatureCount,
        density: PiumaLook.of(context).compact
            ? l.densityCompact
            : l.densityComfortable,
        groups: _groupCount,
        sync: widget.source.syncState().on ? l.syncRowOn : l.syncRowOff,
        notify: switch (mode) {
          NotifyMode.people => l.notifyPeople,
          NotifyMode.all => l.notifyAll,
          NotifyMode.off => l.notifyOff,
          null => null,
        },
        rules: switch (_ruleCount) {
          final n? => l.rulesCount(n),
          null => null,
        },
        calendars: _calendarCount?.toString(),
        appearance: switch (PiumaLook.of(context).theme) {
          ThemeChoice.light => l.themeLight,
          ThemeChoice.dark => l.themeDark,
          ThemeChoice.automatic => l.themeAutomatic,
        },
      );
    } else if (open == SettingsSection.writing ||
        open == SettingsSection.templates) {
      page = SignaturesPage(
        key: _signatures,
        source: widget.source,
        initial: _signature,
        phone: true,
        onBack: _close,
        openTemplates: open == SettingsSection.templates,
        templates: TemplatesPage(
          source: widget.source,
          phone: true,
          embedded: true,
        ),
      );
    } else {
      page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneBack(label: l.settings, onTap: _close),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: switch (open) {
                SettingsSection.notifications => NotificationsPage(
                  source: widget.source,
                ),
                SettingsSection.sync => SyncPage(
                  source: widget.source,
                  phone: true,
                  now: widget.now,
                ),
                SettingsSection.groups => GroupsPage(
                  source: widget.source,
                  phone: true,
                ),
                SettingsSection.privacy => PrivacyPage(source: widget.source),
                SettingsSection.help => HelpPage(
                  source: widget.source,
                  now: widget.now,
                  onWrite: widget.onWrite,
                ),
                SettingsSection.appearance => AppearancePage(
                  source: widget.source,
                  phone: true,
                ),
                SettingsSection.reading => ReadingPage(
                  source: widget.source,
                  phone: true,
                  now: widget.now,
                ),
                SettingsSection.calendars => CalendarsPage(
                  source: widget.source,
                  phone: true,
                ),
                SettingsSection.organizing => RulesPage(
                  source: widget.source,
                  phone: true,
                  now: widget.now,
                  zones: ZoneSwitches(source: widget.source),
                ),
                _ => const SizedBox.shrink(),
              },
            ),
          ),
        ],
      );
    }
    return PopScope(
      canPop: open == null && account == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || (_signatures.currentState?.back() ?? false)) return;
        if (account != null && _away) {
          setState(() => _away = false);
          return;
        }
        if (account != null) {
          setState(() => _account = null);
          return;
        }
        _close();
      },
      // A Scaffold, so the page shrinks above the keyboard and a focused
      // field scrolls into view.
      child: Scaffold(
        backgroundColor: c.surface,
        body: SafeArea(child: page),
      ),
    );
  }

  Widget _desktop(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onBack,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: c.surface,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 240,
                padding: const EdgeInsets.fromLTRB(14, 24, 14, 20),
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border(right: BorderSide(color: c.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BackButton(onTap: widget.onBack),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Text(
                        l.settings,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                          color: c.fg,
                        ),
                      ),
                    ),
                    for (final (head, s, icon, label) in [
                      (
                        null,
                        SettingsSection.accounts,
                        PiumaIcon.user,
                        l.settingsAccountsTitle,
                      ),
                      (
                        l.settingsMail,
                        SettingsSection.writing,
                        PiumaIcon.pen,
                        l.writingTitle,
                      ),
                      (
                        null,
                        SettingsSection.reading,
                        PiumaIcon.mailOpen,
                        l.readingTitle,
                      ),
                      (
                        null,
                        SettingsSection.organizing,
                        PiumaIcon.folder,
                        l.organizingTitle,
                      ),
                      (
                        null,
                        SettingsSection.calendars,
                        PiumaIcon.calendar,
                        l.settingsCalendars,
                      ),
                      (
                        l.settingsApp,
                        SettingsSection.appearance,
                        PiumaIcon.appearance,
                        l.appearanceTitle,
                      ),
                      (
                        null,
                        SettingsSection.notifications,
                        PiumaIcon.bell,
                        l.notificationsTitle,
                      ),
                      (
                        null,
                        SettingsSection.privacy,
                        PiumaIcon.shield,
                        l.privacyTitle,
                      ),
                      (null, SettingsSection.sync, PiumaIcon.sync, l.syncTitle),
                      (
                        null,
                        SettingsSection.shortcuts,
                        PiumaIcon.keyboard,
                        l.shortcutsTitle,
                      ),
                      (
                        l.settingsAbout,
                        SettingsSection.help,
                        PiumaIcon.help,
                        l.helpTitle,
                      ),
                    ]) ...[
                      if (head != null) _NavHeading(head),
                      _NavItem(
                        icon: icon,
                        label: label,
                        current: s == _navSection,
                        onTap: () => setState(() {
                          _section = s;
                          _account = null;
                          _away = false;
                        }),
                      ),
                    ],
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        l.appVersionLine(appVersionShown),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 12,
                          color: c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_section == SettingsSection.writing ||
                  _section == SettingsSection.templates)
                Expanded(
                  child: PiumaEnter(
                    child: SignaturesPage(
                      key: ValueKey((_signature, _section)),
                      source: widget.source,
                      initial: _signature,
                      openTemplates: _section == SettingsSection.templates,
                      templates: TemplatesPage(source: widget.source),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey(_section),
                    padding: const EdgeInsets.fromLTRB(56, 44, 56, 56),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: PiumaEnter(
                          child: switch (_section) {
                            SettingsSection.accounts => switch (_account) {
                              final a? when _away => AwayPage(
                                key: ValueKey(('away', a.id)),
                                source: widget.source,
                                account: a,
                                onBack: () => setState(() => _away = false),
                                now: widget.now,
                              ),
                              final a? => AccountPage(
                                key: ValueKey(a.id),
                                source: widget.source,
                                account: a,
                                backLabel: l.settingsAccountsTitle,
                                onBack: () => setState(() => _account = null),
                                onSignature: _openSignature,
                                onAway: () => setState(() => _away = true),
                                now: widget.now,
                              ),
                              null => _AccountsPage(
                                accounts: widget.source.accounts,
                                onAddAccount: widget.onAddAccount,
                                onAccount: (a) => setState(() => _account = a),
                                groups: _groupCount,
                                onGroups: () => setState(
                                  () => _section = SettingsSection.groups,
                                ),
                              ),
                            },
                            SettingsSection.notifications => NotificationsPage(
                              source: widget.source,
                            ),
                            SettingsSection.sync => SyncPage(
                              source: widget.source,
                              now: widget.now,
                            ),
                            SettingsSection.groups => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SettingsBackLink(
                                    label: l.settingsAccountsTitle,
                                    onTap: () => setState(
                                      () => _section = SettingsSection.accounts,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                GroupsPage(source: widget.source),
                              ],
                            ),
                            SettingsSection.appearance => AppearancePage(
                              source: widget.source,
                            ),
                            SettingsSection.reading => ReadingPage(
                              source: widget.source,
                              now: widget.now,
                            ),
                            SettingsSection.calendars => CalendarsPage(
                              source: widget.source,
                            ),
                            SettingsSection.organizing => RulesPage(
                              source: widget.source,
                              now: widget.now,
                              zones: ZoneSwitches(source: widget.source),
                            ),
                            SettingsSection.privacy => PrivacyPage(
                              source: widget.source,
                            ),
                            SettingsSection.shortcuts => const ShortcutsPage(),
                            SettingsSection.help => HelpPage(
                              source: widget.source,
                              now: widget.now,
                              onWrite: widget.onWrite,
                            ),
                            SettingsSection.writing ||
                            SettingsSection.templates =>
                              const SizedBox.shrink(),
                          },
                        ),
                      ),
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

/// "‹ Inbox", "‹ Settings": back, at the top of a phone page.
class PhoneBack extends StatelessWidget {
  const PhoneBack({super.key, required this.label, required this.onTap});
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
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
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

/// The list of `SettingsPhone`: Accounts, General and About.
class _PhoneList extends StatelessWidget {
  const _PhoneList({
    required this.accounts,
    required this.onBack,
    required this.onAddAccount,
    required this.onOpen,
    required this.onAccount,
    this.signatures,
    this.density,
    this.groups,
    this.sync,
    this.notify,
    this.rules,
    this.calendars,
    this.appearance,
  });

  final List<MailAccount> accounts;
  final VoidCallback onBack;
  final VoidCallback onAddAccount;
  final ValueChanged<SettingsSection> onOpen;
  final ValueChanged<MailAccount> onAccount;
  final int? signatures;

  /// Comfortable or Compact, beside Reading.
  final String? density;
  final int? groups;
  final String? sync;
  final String? notify;
  final String? rules;
  final String? calendars;
  final String? appearance;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    TextStyle text({double size = 15, Color? color, FontWeight? weight}) =>
        TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: size,
          fontWeight: weight,
          color: color ?? c.fg,
        );
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: text(size: 13, color: c.muted, weight: FontWeight.w500),
        ),
      ),
    );
    Widget card(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _Card(children: children),
    );
    Widget row(String label, String? value, VoidCallback onTap) =>
        PiumaPressable(
          onTap: onTap,
          semanticLabel: value == null ? label : '$label, $value',
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: text())),
                    if (value != null)
                      Text(value, style: text(size: 14, color: c.muted)),
                    const SizedBox(width: 8),
                    PiumaIconView(
                      PiumaIcon.chevronRight,
                      size: 16,
                      color: c.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(-10, 0),
                child: PiumaPressable(
                  onTap: onBack,
                  semanticLabel: l.inbox,
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
                              l.inbox,
                              style: text(size: 16, color: c.accentText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(
                  l.settings,
                  style: text(
                    size: 30,
                    weight: FontWeight.w600,
                  ).copyWith(height: 1.15, letterSpacing: -0.9),
                ),
              ),
            ],
          ),
        ),
        heading(l.settingsAccountsTitle),
        card([
          for (final a in accounts)
            PiumaPressable(
              onTap: () => onAccount(a),
              semanticLabel: l.accountDetailsLabel(a.name, a.email),
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name,
                                style: text(weight: FontWeight.w500),
                              ),
                              Text(
                                a.email,
                                style: text(size: 13, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        PiumaIconView(
                          PiumaIcon.chevronRight,
                          size: 16,
                          color: c.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          row(
            l.groupsTitle,
            groups?.toString(),
            () => onOpen(SettingsSection.groups),
          ),
          PiumaPressable(
            onTap: onAddAccount,
            semanticLabel: l.addAccountShort,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    PiumaIconView(
                      PiumaIcon.plus,
                      size: 18,
                      color: c.accentText,
                    ),
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                      child: Text(
                        l.addAccountShort,
                        style: text(
                          color: c.accentText,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
        heading(l.settingsMail),
        card([
          row(l.writingTitle, switch (signatures) {
            final n? => l.signaturesCount(n),
            null => null,
          }, () => onOpen(SettingsSection.writing)),
          row(l.readingTitle, density, () => onOpen(SettingsSection.reading)),
          row(
            l.organizingTitle,
            rules,
            () => onOpen(SettingsSection.organizing),
          ),
          row(
            l.settingsCalendars,
            calendars,
            () => onOpen(SettingsSection.calendars),
          ),
        ]),
        heading(l.settingsApp),
        card([
          row(
            l.appearanceTitle,
            appearance,
            () => onOpen(SettingsSection.appearance),
          ),
          row(
            l.notificationsTitle,
            notify,
            () => onOpen(SettingsSection.notifications),
          ),
          row(l.privacyTitle, null, () => onOpen(SettingsSection.privacy)),
          row(l.syncTitle, sync, () => onOpen(SettingsSection.sync)),
        ]),
        heading(l.settingsAbout),
        card([
          row(l.helpTitle, null, () => onOpen(SettingsSection.help)),
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: PiumaIconView(
                      PiumaIcon.compose,
                      size: 18,
                      color: c.onAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.appName,
                      style: text(weight: FontWeight.w500),
                    ),
                  ),
                  Text(
                    appVersionShown,
                    style: PiumaType.mono.copyWith(
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(l.openSourceLine, style: text()),
              ),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Text(
            l.motto,
            textAlign: TextAlign.center,
            style: text(size: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.backToMail,
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.chevronLeft, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Text(
                l.backToMail,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mail, App, About: a small muted heading over sidebar items.
class _NavHeading extends StatelessWidget {
  const _NavHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: PiumaTheme.of(context).muted,
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final color = current ? c.accentText : c.fg;
    return Semantics(
      selected: current,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 36,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: current ? c.sel : c.sel.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(
              PiumaButtonSize.standard.radius,
            ),
          ),
          child: Row(
            children: [
              PiumaIconView(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: color,
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

/// "Privacy & security" and friends: the page's title and its line.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.84,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 14,
            color: c.muted,
          ),
        ),
      ],
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
        borderRadius: BorderRadius.circular(16),
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

class _AccountsPage extends StatelessWidget {
  const _AccountsPage({
    required this.accounts,
    required this.onAddAccount,
    required this.onAccount,
    required this.onGroups,
    this.groups,
  });

  final List<MailAccount> accounts;
  final VoidCallback onAddAccount;
  final ValueChanged<MailAccount> onAccount;
  final VoidCallback onGroups;

  /// How many groups there are, beside Groups.
  final int? groups;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(
          title: l.settingsAccountsTitle,
          subtitle: l.settingsAccountsSubtitle(accounts.length),
        ),
        const SizedBox(height: 28),
        _Card(
          children: [
            for (final a in accounts)
              PiumaPressable(
                onTap: () => onAccount(a),
                semanticLabel: l.accountDetailsLabel(a.name, a.email),
                child: ExcludeSemantics(child: _AccountRow(account: a)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          children: [
            PiumaPressable(
              onTap: onGroups,
              semanticLabel: groups == null
                  ? l.groupsTitle
                  : '${l.groupsTitle}, $groups',
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        PiumaIconView(
                          PiumaIcon.layers,
                          size: 16,
                          color: c.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l.groupsTitle,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 15,
                              color: c.fg,
                            ),
                          ),
                        ),
                        if (groups != null)
                          Text(
                            '$groups',
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 14,
                              color: c.muted,
                            ),
                          ),
                        const SizedBox(width: 8),
                        PiumaIconView(
                          PiumaIcon.chevronRight,
                          size: 16,
                          color: c.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        PiumaButton(
          label: l.addAccountShort,
          kind: PiumaButtonKind.secondary,
          onPressed: onAddAccount,
        ),
        const SizedBox(height: 12),
        Text(
          l.addAccountNote,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 13,
            color: c.muted,
          ),
        ),
      ],
    );
  }
}

/// One account in Settings › Accounts: its dot, name and address.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});
  final MailAccount account;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final a = account;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: a.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                    ),
                  ),
                  Text(
                    l.accountKindImap(a.email),
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
            PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}

/// Privacy & security, as `DesktopPrivacy`.
/// Settings › Notifications, as in the `Settings` mockup: what to be told
/// about, and quiet hours. The Vault switches arrive with the Vault.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.source});
  final MailSource source;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  NotifySettings? _settings;
  BackgroundDelivery? _delivery;

  @override
  void initState() {
    super.initState();
    widget.source.notifySettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    if (widget.source.backgroundChoice) {
      widget.source.backgroundDelivery().then((d) {
        if (mounted) setState(() => _delivery = d);
      });
    }
  }

  void _deliver(BackgroundDelivery d) {
    setState(() => _delivery = d);
    widget.source.setBackgroundDelivery(d);
  }

  void _set(NotifySettings next) {
    setState(() => _settings = next);
    widget.source.setNotifySettings(next);
  }

  /// Accounts switched on or off for the quiet hours here.
  final _covers = <int, bool>{};

  bool _covered(int account) {
    try {
      return _covers[account] ??= widget.source.quietCovers(account);
    } catch (_) {
      return true;
    }
  }

  void _cover(int account, bool covered) {
    setState(() => _covers[account] = covered);
    widget.source.setQuietCovers(account, covered);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final s = _settings;
    final heading = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: c.muted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(
          title: l.notificationsTitle,
          subtitle: l.notificationsLead,
        ),
        if (s != null) ...[
          // Android: how new mail arrives with the app closed
          // (`AndroidBackground`, 3).
          if (widget.source.backgroundChoice) ...[
            const SizedBox(height: 32),
            Text(l.newMailHeading, style: heading),
            const SizedBox(height: 10),
            Semantics(
              label: l.newMailHeading,
              container: true,
              child: Column(
                children: [
                  for (final (i, (d, label, hint)) in [
                    (
                      BackgroundDelivery.instant,
                      l.deliveryInstant,
                      l.deliveryInstantHint,
                    ),
                    (
                      BackgroundDelivery.periodic,
                      l.deliveryPeriodic,
                      l.deliveryPeriodicHint,
                    ),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _ModeCard(
                      label: label,
                      hint: hint,
                      recommended: d == BackgroundDelivery.instant,
                      selected: _delivery == d,
                      onTap: () => _deliver(d),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text(l.notifyAbout, style: heading),
          const SizedBox(height: 10),
          Semantics(
            label: l.notifyAbout,
            container: true,
            child: Column(
              children: [
                for (final (i, (mode, label, hint)) in [
                  (NotifyMode.people, l.notifyPeople, l.notifyPeopleHint),
                  (NotifyMode.all, l.notifyAll, l.notifyAllHint),
                  (NotifyMode.off, l.notifyOff, l.notifyOffHint),
                ].indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ModeCard(
                    label: label,
                    hint: hint,
                    recommended: mode == NotifyMode.people,
                    selected: s.mode == mode,
                    onTap: () => _set(s.copyWith(mode: mode)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(l.quietHours, style: heading),
          const SizedBox(height: 10),
          _Card(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.quietTitle,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 15,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: c.fg,
                            ),
                          ),
                          Text(
                            l.quietHint,
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
                    PiumaSwitch(
                      value: s.quiet,
                      label: l.quietTitle,
                      onChanged: (v) => _set(s.copyWith(quiet: v)),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: s.quiet ? 1 : 0.45,
                duration: reduceMotion(context)
                    ? Duration.zero
                    : PiumaMotion.theme,
                curve: PiumaMotion.curve,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  child: Row(
                    children: [
                      Text(l.quietFrom, style: _quietText(c)),
                      const SizedBox(width: 10),
                      _TimeChip(
                        minute: s.quietFrom,
                        label: l.quietFromLabel,
                        enabled: s.quiet,
                        onPick: (m) => _set(s.copyWith(quietFrom: m)),
                      ),
                      const SizedBox(width: 10),
                      Text(l.quietTo, style: _quietText(c)),
                      const SizedBox(width: 10),
                      _TimeChip(
                        minute: s.quietTo,
                        label: l.quietToLabel,
                        enabled: s.quiet,
                        onPick: (m) => _set(s.copyWith(quietTo: m)),
                      ),
                    ],
                  ),
                ),
              ),
              _ToggleRow(
                title: l.quietWeekends,
                hint: l.quietWeekendsHint,
                value: s.weekends,
                onChanged: (v) => _set(s.copyWith(weekends: v)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final title = _Titled(
                      title: l.quietWhile,
                      hint: l.quietWhileHint,
                    );
                    final choice = PiumaSegments(
                      label: l.quietWhile,
                      items: [
                        (
                          l.quietNoSound,
                          !s.hold,
                          () => _set(s.copyWith(hold: false)),
                        ),
                        (
                          l.quietNoNotices,
                          s.hold,
                          () => _set(s.copyWith(hold: true)),
                        ),
                      ],
                    );
                    // On a phone the choice goes under its title.
                    if (box.maxWidth < 480) {
                      return SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 10), choice],
                        ),
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        choice,
                      ],
                    );
                  },
                ),
              ),
              for (final a in widget.source.accounts)
                _AccountQuietRow(
                  account: a,
                  covered: _covered(a.id),
                  onChanged: (v) => _cover(a.id, v),
                ),
            ],
          ),
          // With the Vault off (Settings › Features) it makes no notices.
          if (widget.source.features.value.vault) ...[
            const SizedBox(height: 32),
            Text(l.folderVault, style: heading),
            const SizedBox(height: 10),
            _Card(
              children: [
                _ToggleRow(
                  title: l.vaultParcelsTitle,
                  hint: l.vaultParcelsHint,
                  value: s.parcels,
                  onChanged: (v) => _set(s.copyWith(parcels: v)),
                ),
                _ToggleRow(
                  title: l.vaultDueTitle,
                  hint: l.vaultDueHint,
                  value: s.due,
                  onChanged: (v) => _set(s.copyWith(due: v)),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  static TextStyle _quietText(PiumaColors c) =>
      TextStyle(fontFamily: PiumaFonts.sans, fontSize: 14, color: c.muted);
}

/// A row's title and the line under it.
class _Titled extends StatelessWidget {
  const _Titled({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
    );
  }
}

/// An account in the quiet hours card: its dot, name and address, and
/// whether the quiet hours cover it ("rings as usual" when not).
class _AccountQuietRow extends StatelessWidget {
  const _AccountQuietRow({
    required this.account,
    required this.covered,
    required this.onChanged,
  });

  final MailAccount account;
  final bool covered;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
          const SizedBox(width: 12),
          Expanded(
            child: _Titled(
              title: account.name,
              hint: covered
                  ? account.email
                  : l.quietRingsAsUsual(account.email),
            ),
          ),
          const SizedBox(width: 16),
          PiumaSwitch(
            value: covered,
            label: account.name,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A title, a line under it and a switch, as in the Vault card.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
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

/// One choice of "Notify me about": a card with a radio ring.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.hint,
    required this.recommended,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final duration = reduceMotion(context) ? Duration.zero : PiumaMotion.theme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: duration,
          curve: PiumaMotion.curve,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? c.soft : c.surface,
            border: Border.all(color: selected ? c.accent : c.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AnimatedContainer(
                  duration: duration,
                  curve: PiumaMotion.curve,
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? c.accent : c.ring,
                      width: selected ? 2 : 1.5,
                    ),
                  ),
                  child: AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: duration,
                    curve: PiumaMotion.curve,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                              color: c.fg,
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.chip,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                l.notifyRecommended,
                                style: TextStyle(
                                  fontFamily: PiumaFonts.sans,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: c.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 14,
                          height: 1.45,
                          color: c.muted,
                        ),
                      ),
                    ],
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

/// "22:00": a time of day, picked from a short list in half hours, in
/// clock order and opened at the time set.
class _TimeChip extends StatefulWidget {
  const _TimeChip({
    required this.minute,
    required this.label,
    required this.enabled,
    required this.onPick,
  });

  final int minute;
  final String Function(String time) label;
  final bool enabled;
  final ValueChanged<int> onPick;

  static String format(int minute) =>
      '${minute ~/ 60}:${(minute % 60).toString().padLeft(2, '0')}';

  @override
  State<_TimeChip> createState() => _TimeChipState();
}

class _TimeChipState extends State<_TimeChip> {
  final _set = GlobalKey();

  /// Scrolls the list to the time set, near its middle.
  void _showSet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _set.currentContext;
      if (at != null && at.mounted) {
        Scrollable.ensureVisible(at, alignment: 0.4);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final minute = widget.minute;
    final format = _TimeChip.format;
    final c = PiumaTheme.of(context);
    final style = PiumaType.mono.copyWith(fontSize: 14, color: c.fg);
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        maximumSize: const WidgetStatePropertyAll(Size(140, 280)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.line),
          ),
        ),
      ),
      alignmentOffset: const Offset(0, 6),
      onOpen: _showSet,
      menuChildren: [
        for (var m = 0; m < 24 * 60; m += 30)
          MenuItemButton(
            key: m == minute ~/ 30 * 30 ? _set : null,
            onPressed: () => widget.onPick(m),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(120, 36)),
              backgroundColor: WidgetStatePropertyAll(
                m == minute ? c.sel : Colors.transparent,
              ),
              overlayColor: WidgetStatePropertyAll(c.chip),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            child: Text(
              format(m),
              style: style.copyWith(
                fontWeight: m == minute ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => PiumaPressable(
        onTap: widget.enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
        semanticLabel: widget.label(format(minute)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExcludeSemantics(child: Text(format(minute), style: style)),
        ),
      ),
    );
  }
}

/// Settings › Features (`OptionalFeaturesToApprove`): the zones, and the
/// helpers that run on this device, each on unless turned off. A switch
/// that is off says what happens instead.
/// One feature switch: the hint says what it does, or what goes when off.
Widget _featureRow(
  MailSource source,
  PiumaIcon icon,
  String label,
  bool on,
  String hint,
  String off,
  FeatureSettings Function(bool) turn,
) => _SwitchRow(
  icon: icon,
  label: label,
  hint: on ? hint : off,
  value: on,
  onChanged: (v) => source.setFeatureSettings(turn(v)),
);

TextStyle _featureHeading(PiumaColors c) => TextStyle(
  fontFamily: PiumaFonts.sans,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: c.muted,
);

/// Settings › Organizing › Zones: Newsletters, Vault and Attachments turned
/// on or off (`OptionalFeaturesToApprove`).
class ZoneSwitches extends StatelessWidget {
  const ZoneSwitches({super.key, required this.source});
  final MailSource source;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: source.features,
      builder: (context, s, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.featuresZones, style: _featureHeading(c)),
          ),
          const SizedBox(height: 10),
          _Card(
            children: [
              _featureRow(
                source,
                PiumaIcon.newsletter,
                l.folderNewsletters,
                s.newsletters,
                l.featureNewslettersHint,
                l.featureNewslettersOff,
                (v) => s.copyWith(newsletters: v),
              ),
              _featureRow(
                source,
                PiumaIcon.vault,
                l.folderVault,
                s.vault,
                l.featureVaultHint,
                l.featureVaultOff,
                (v) => s.copyWith(vault: v),
              ),
              _featureRow(
                source,
                PiumaIcon.paperclip,
                l.folderAttachments,
                s.attachments,
                l.featureAttachmentsHint,
                l.featureAttachmentsOff,
                (v) => s.copyWith(attachments: v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l.featuresSubtitle,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 13,
              height: 1.4,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings › Reading › On this device: In short, Translate and Dates in
/// emails turned on or off (`OptionalFeaturesToApprove`).
class HelperSwitches extends StatelessWidget {
  const HelperSwitches({super.key, required this.source});
  final MailSource source;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: source.features,
      builder: (context, s, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.spark, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Text(l.featuresOnDevice, style: _featureHeading(c)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Card(
            children: [
              _featureRow(
                source,
                PiumaIcon.spark,
                l.inShort,
                s.inShort,
                l.featureInShortHint,
                l.featureInShortOff,
                (v) => s.copyWith(inShort: v),
              ),
              _featureRow(
                source,
                PiumaIcon.translate,
                l.featureTranslate,
                s.translate,
                l.featureTranslateHint,
                l.featureTranslateOff,
                (v) => s.copyWith(translate: v),
              ),
              _featureRow(
                source,
                PiumaIcon.calendar,
                l.featureFoundDates,
                s.foundDates,
                l.featureFoundDatesHint,
                l.featureFoundDatesOff,
                (v) => s.copyWith(foundDates: v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l.featuresOnDeviceNote,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 13,
              height: 1.4,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key, required this.source});
  final MailSource source;

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  PrivacySettings? _settings;
  PrivacyStats? _stats;
  List<TrustedSender>? _trusted;

  /// Removed while their row folds away.
  final _removing = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.source;
    final (settings, stats, trusted) = await (
      s.privacySettings(),
      s.privacyStats(),
      s.trustedSenders(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _stats = stats;
      _trusted = trusted;
    });
  }

  void _set(PrivacySettings next) {
    setState(() => _settings = next);
    widget.source.setPrivacySettings(next);
  }

  Future<void> _remove(TrustedSender t) async {
    final wait = reduceMotion(context) ? Duration.zero : PiumaMotion.collapse;
    setState(() => _removing.add(t.email));
    await widget.source.setTrusted(t.email, false);
    await Future<void>.delayed(wait);
    if (!mounted) return;
    setState(() {
      _removing.remove(t.email);
      _trusted = [
        for (final x in _trusted ?? <TrustedSender>[])
          if (x.email != t.email) x,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final s = _settings;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = NumberFormat.decimalPattern(locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeader(title: l.privacyTitle, subtitle: l.privacySubtitle),
        const SizedBox(height: 28),
        if (s != null)
          _Card(
            children: [
              _SwitchRow(
                icon: PiumaIcon.image,
                label: l.blockImagesSetting,
                hint: l.blockImagesSettingHint,
                value: s.blockImages,
                onChanged: (v) => _set(s.copyWith(blockImages: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.blocked,
                label: l.stopPixelsSetting,
                hint: l.stopPixelsSettingHint,
                value: s.stopPixels,
                onChanged: (v) => _set(s.copyWith(stopPixels: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.link,
                label: l.cleanLinksSetting,
                hint: l.cleanLinksSettingHint,
                value: s.cleanLinks,
                onChanged: (v) => _set(s.copyWith(cleanLinks: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.warning,
                label: l.warnLinksSetting,
                hint: l.warnLinksSettingHint,
                value: s.warnLinks,
                onChanged: (v) => _set(s.copyWith(warnLinks: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.shield,
                label: l.verifiedSenderSetting,
                hint: l.verifiedSenderSettingHint,
                value: s.verifiedSender,
                badge: ExcludeSemantics(
                  child: VerifiedPill(
                    label: l.verifiedBadge,
                    dimmed: !s.verifiedSender,
                  ),
                ),
                onChanged: (v) => _set(s.copyWith(verifiedSender: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.user,
                label: l.senderPicturesSetting,
                hint: l.senderPicturesSettingHint,
                value: s.senderPictures,
                onChanged: (v) => _set(s.copyWith(senderPictures: v)),
              ),
              _SwitchRow(
                icon: PiumaIcon.external,
                label: l.websiteIconsSetting,
                hint: l.websiteIconsSettingHint,
                value: s.websiteIcons,
                onChanged: (v) => _set(s.copyWith(websiteIcons: v)),
              ),
            ],
          ),
        if (_stats case final st?) ...[
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.last30Days,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 48,
                  runSpacing: 20,
                  children: [
                    _Stat(
                      value: number.format(st.trackers),
                      label: l.trackersStoppedLabel,
                    ),
                    _Stat(
                      value: number.format(st.linksCleaned),
                      label: l.linksCleanedLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  l.privacyStatsDetail(
                    number.format(st.pixels),
                    number.format(st.remoteStyles),
                    st.suspiciousLinks,
                  ),
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_trusted case final trusted?) ...[
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l.trustedSenders,
                style: PiumaType.subtitle.copyWith(color: c.fg),
              ),
              const SizedBox(width: 8),
              Text(
                l.trustedSendersHint,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  color: c.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Card(
            children: [
              for (final t in trusted)
                _TrustedRow(
                  sender: t,
                  removing: _removing.contains(t.email),
                  onRemove: () => _remove(t),
                ),
              if (trusted.every((t) => _removing.contains(t.email)))
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      l.noTrustedSenders,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 14,
                        color: c.muted,
                      ),
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.badge,
  });

  final PiumaIcon icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Beside the label, e.g. the "Verified" a sender gets.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            alignment: Alignment.center,
            child: PiumaIconView(icon, size: 17, color: c.muted),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                    ?badge,
                  ],
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
          PiumaSwitch(value: value, label: label, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A big number and what it counts; the digits roll into place.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RollingNumber(
          text: value,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 34,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            color: c.fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 14,
            color: c.muted,
          ),
        ),
      ],
    );
  }
}

/// Digits that roll up from 0 to their value, one after the other, on the
/// single curve. Separators stay put. Instant with reduce motion.
class RollingNumber extends StatefulWidget {
  const RollingNumber({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final _digits = widget.text.runes
      .where((r) => r >= 0x30 && r <= 0x39)
      .length;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PiumaMotion.reveal * 2 + PiumaMotion.stagger * 2 * _digits,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final h = (style.fontSize ?? 14) * (style.height ?? 1.2);
    final total = _c.duration!.inMicroseconds;
    final step = (PiumaMotion.stagger * 2).inMicroseconds / total;
    var k = 0;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final ch in widget.text.split(''))
              if (int.tryParse(ch) case final d?)
                _Digit(
                  digit: d,
                  height: h,
                  style: style,
                  progress: CurvedAnimation(
                    parent: _c,
                    curve: Interval(
                      (k++ * step).clamp(0, 1),
                      1,
                      curve: PiumaMotion.curve,
                    ),
                  ),
                )
              else
                Text(ch, style: style),
          ],
        ),
      ),
    );
  }
}

class _Digit extends StatelessWidget {
  const _Digit({
    required this.digit,
    required this.height,
    required this.style,
    required this.progress,
  });

  final int digit;
  final double height;
  final TextStyle style;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, column) => Stack(
            clipBehavior: Clip.none,
            children: [
              // Tabular figures: every digit is as wide as "0".
              Opacity(opacity: 0, child: Text('0', style: style)),
              Positioned(
                left: 0,
                right: 0,
                top: -height * digit * progress.value,
                child: column!,
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < 10; i++)
                SizedBox(
                  height: height,
                  child: Text('$i', style: style),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustedRow extends StatelessWidget {
  const _TrustedRow({
    required this.sender,
    required this.removing,
    required this.onRemove,
  });

  final TrustedSender sender;
  final bool removing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final instant = reduceMotion(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials(sender.label),
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender.label,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Text(
                  l.trustedSince(
                    sender.email,
                    DateFormat.MMMd(locale).format(sender.since),
                  ),
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          PiumaButton(
            label: l.removeTrusted,
            kind: PiumaButtonKind.secondary,
            size: PiumaButtonSize.compact,
            onPressed: removing ? null : onRemove,
          ),
        ],
      ),
    );
    return AnimatedSize(
      duration: instant ? Duration.zero : PiumaMotion.collapse,
      curve: PiumaMotion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: instant ? Duration.zero : PiumaMotion.collapse,
        curve: PiumaMotion.curve,
        opacity: removing ? 0 : 1,
        child: removing ? const SizedBox(width: double.infinity) : row,
      ),
    );
  }
}
