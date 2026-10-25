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
import '../widgets/text_field.dart';
import 'settings_screen.dart' show SettingsHeader;

enum _Way { calDav, google, ics }

/// Settings › Calendars, as in `Calendars` (desktop) and `CalendarsPhone`:
/// Piuma has no calendar of its own, so this connects the ones you use.
/// Each calendar can count for availability, and one takes the invites
/// you accept.
class CalendarsPage extends StatefulWidget {
  const CalendarsPage({super.key, required this.source, this.phone = false});

  final MailSource source;
  final bool phone;

  @override
  State<CalendarsPage> createState() => _CalendarsPageState();
}

class _CalendarsPageState extends State<CalendarsPage> {
  List<CalendarSource>? _sources;
  List<CalendarSuggestion> _suggestions = const [];
  CalendarPrefs _prefs = const CalendarPrefs();

  /// Accounts connected from a suggestion while the page is open.
  final Set<int> _linked = {};

  bool _adding = false;
  _Way? _way;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sources = await widget.source.calendarSources();
      final suggestions = await widget.source.calendarSuggestions();
      final prefs = await widget.source.calendarPrefs();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _suggestions = [
          ..._suggestions.where((s) => _linked.contains(s.accountId)),
          ...suggestions.where(
            (s) => !_suggestions.any((o) => o.accountId == s.accountId),
          ),
        ];
        _prefs = prefs;
      });
    } catch (_) {
      if (mounted) setState(() => _sources = const []);
    }
  }

  Future<void> _added() async {
    setState(() => _way = null);
    await _load();
  }

  Future<void> _disconnect(CalendarSource s) async {
    await widget.source.disconnectCalendar(s.id);
    await _load();
  }

  Future<void> _availability(MailCalendar c, bool on) async {
    setState(() {
      _sources = [
        for (final s in _sources ?? const <CalendarSource>[])
          s.copyWith(
            calendars: [
              for (final x in s.calendars)
                x.id == c.id ? x.copyWith(availability: on) : x,
            ],
          ),
      ];
    });
    await widget.source.setCalendarAvailability(c.id, on);
  }

  Future<void> _link(CalendarSuggestion s) async {
    try {
      await widget.source.connectAccountCalendar(s.accountId);
      _linked.add(s.accountId);
    } on AddAccountException {
      // It stays offered: nothing changed.
    }
    await _load();
  }

  Future<void> _conflicts(bool on) async {
    setState(() => _prefs = _prefs.copyWith(checkConflicts: on));
    await widget.source.setCheckConflicts(on);
  }

  Future<void> _findDates(bool on) async {
    setState(() => _prefs = _prefs.copyWith(findDates: on));
    await widget.source.setFindDates(on);
  }

  Future<void> _pickDefault(Rect? anchor) async {
    final l = AppLocalizations.of(context);
    final writable = [
      for (final s in _sources ?? const <CalendarSource>[])
        for (final c in s.calendars)
          if (!c.readOnly) (c, s),
    ];
    if (writable.isEmpty) return;
    Widget menu(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (c, s) in writable)
          _MenuOption(
            calendar: c,
            source: s.name,
            selected: c.id == _prefs.defaultCalendar,
            onTap: () => Navigator.of(context).pop(c),
          ),
      ],
    );
    final picked = widget.phone || anchor == null
        ? await showPiumaSheet<MailCalendar>(
            context,
            label: l.calAddInvitesTo,
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: menu(context),
            ),
          )
        : await showPiumaPopover<MailCalendar>(
            context,
            label: l.calAddInvitesTo,
            anchor: anchor,
            width: 260,
            builder: menu,
          );
    if (picked == null || !mounted) return;
    setState(() => _prefs = _prefs.copyWith(defaultCalendar: picked.id));
    await widget.source.setDefaultCalendar(picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final sources = _sources;
    final calendars = [
      for (final s in sources ?? const <CalendarSource>[]) ...s.calendars,
    ];
    final chosen = calendars
        .where((x) => x.id == _prefs.defaultCalendar)
        .firstOrNull;
    final accountColors = {
      for (final a in widget.source.accounts) a.id: a.color,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(title: l.settingsCalendars, subtitle: l.calIntro),
        const SizedBox(height: 32),
        Row(
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  l.calConnected,
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
            if (sources != null && sources.isNotEmpty && !widget.phone) ...[
              const SizedBox(width: 12),
              Text(
                '${l.calSources(sources.length)} · '
                '${l.calCalendars(calendars.length)}',
                style: PiumaType.small.copyWith(color: c.muted),
              ),
            ],
            const Spacer(),
            if (!widget.phone)
              _AddButton(
                open: _adding,
                onTap: () => setState(() {
                  _adding = !_adding;
                  _way = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.move,
          curve: PiumaMotion.curve,
          alignment: Alignment.topCenter,
          child: !_adding || widget.phone
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _Connect(
                    source: widget.source,
                    way: _way,
                    phone: false,
                    suggestions: _suggestions,
                    linked: _linked,
                    accountColors: accountColors,
                    onWay: (w) => setState(() => _way = _way == w ? null : w),
                    onClose: () => setState(() {
                      _adding = false;
                      _way = null;
                    }),
                    onAdded: _added,
                    onLink: _link,
                  ),
                ),
        ),
        _Box(
          children: [
            if (sources != null && sources.isEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  l.calNone,
                  style: PiumaType.body.copyWith(color: c.muted),
                ),
              ),
            for (final s in sources ?? const <CalendarSource>[])
              _SourceRow(
                source: s,
                defaultCalendar: _prefs.defaultCalendar,
                phone: widget.phone,
                onDisconnect: () => _disconnect(s),
                onAvailability: _availability,
              ),
          ],
        ),
        if (widget.phone) ...[
          const SizedBox(height: 12),
          PiumaButton(
            label: l.calConnect,
            kind: PiumaButtonKind.secondary,
            size: PiumaButtonSize.touch,
            onPressed: () => showPiumaSheet<void>(
              context,
              label: l.calConnect,
              builder: (sheet) => StatefulBuilder(
                builder: (sheet, setSheet) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _Connect(
                    source: widget.source,
                    way: _way,
                    phone: true,
                    suggestions: _suggestions,
                    linked: _linked,
                    accountColors: accountColors,
                    onWay: (w) => setSheet(() => _way = _way == w ? null : w),
                    onClose: () => Navigator.of(sheet).pop(),
                    onAdded: () {
                      Navigator.of(sheet).pop();
                      _added();
                    },
                    onLink: (s) async {
                      await _link(s);
                      setSheet(() {});
                    },
                  ),
                ),
              ),
            ).then((_) => _way = null),
          ),
        ],
        const SizedBox(height: 32),
        Semantics(
          header: true,
          child: Text(
            l.calWhenInvite,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.34,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Box(
          children: [
            _Row(
              icon: PiumaIcon.calendar,
              label: widget.phone ? l.calAddInvitesTo : l.calAddTo,
              hint: l.calAddToSub,
              trailing: Builder(
                builder: (button) => _Pill(
                  calendar: chosen,
                  label: l.calAddInvitesTo,
                  onTap: () {
                    final box = button.findRenderObject() as RenderBox?;
                    final rect = box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size;
                    _pickDefault(rect);
                  },
                ),
              ),
            ),
            _Row(
              icon: PiumaIcon.clash,
              label: l.calConflicts,
              hint: l.calConflictsSub,
              trailing: PiumaSwitch(
                value: _prefs.checkConflicts,
                label: l.calConflicts,
                onChanged: _conflicts,
              ),
            ),
            _Row(
              icon: PiumaIcon.spark,
              label: l.calFindDates,
              tag: l.calOnDevice,
              hint: l.calFindDatesSub,
              trailing: PiumaSwitch(
                value: _prefs.findDates,
                label: l.calFindDates,
                onChanged: _findDates,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final (icon, text) in [
          (PiumaIcon.mail, l.calFooter),
          (
            PiumaIcon.lock,
            widget.source.syncState().on ? l.calSynced : l.calStaysHere,
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: PiumaIconView(icon, size: 14, color: c.muted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
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

/// "+ Connect a calendar"; it turns into × while the panel is open.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      button: true,
      expanded: open,
      label: l.calConnect,
      child: ExcludeSemantics(
        child: PiumaPressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: 34,
            padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
            decoration: BoxDecoration(
              color: open ? c.sel : c.surface,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
              border: Border.all(color: open ? c.sel : c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: open ? 0.125 : 0,
                  duration: instant ? Duration.zero : PiumaMotion.move,
                  curve: PiumaMotion.curve,
                  child: PiumaIconView(
                    PiumaIcon.plus,
                    size: 16,
                    color: open ? c.accentText : c.fg,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l.calConnect,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: open ? c.accentText : c.fg,
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

/// Choose CalDAV or an .ics feed, fill in where, and the suggested
/// accounts under.
class _Connect extends StatelessWidget {
  const _Connect({
    required this.source,
    required this.way,
    required this.phone,
    required this.suggestions,
    required this.linked,
    required this.accountColors,
    required this.onWay,
    required this.onClose,
    required this.onAdded,
    required this.onLink,
  });

  final MailSource source;
  final _Way? way;
  final bool phone;
  final List<CalendarSuggestion> suggestions;
  final Set<int> linked;
  final Map<int, Color> accountColors;
  final ValueChanged<_Way> onWay;
  final VoidCallback onClose;
  final VoidCallback onAdded;
  final ValueChanged<CalendarSuggestion> onLink;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final options = [
      _Option(
        icon: PiumaIcon.server,
        title: l.calCalDav,
        paren: l.calCalDavParen,
        sub: l.calCalDavSub,
        selected: way == _Way.calDav,
        onTap: () => onWay(_Way.calDav),
      ),
      _Option(
        icon: PiumaIcon.calendar,
        title: l.calGoogle,
        sub: l.calGoogleSub,
        selected: way == _Way.google,
        onTap: () => onWay(_Way.google),
      ),
      _Option(
        icon: PiumaIcon.link,
        title: l.calIcs,
        sub: l.calIcsSub,
        selected: way == _Way.ics,
        onTap: () => onWay(_Way.ics),
      ),
    ];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                phone ? l.calConnect : l.calChoose,
                style: phone
                    ? PiumaType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      )
                    : PiumaType.small.copyWith(color: c.muted),
              ),
            ),
            if (!phone)
              PiumaPressable(
                onTap: onClose,
                semanticLabel: MaterialLocalizations.of(context)
                    .closeButtonLabel,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: PiumaIconView(
                      PiumaIcon.close,
                      size: 15,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (phone)
          for (final o in options) ...[o, const SizedBox(height: 8)]
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: options[0]),
              const SizedBox(width: 8),
              Expanded(child: options[1]),
              const SizedBox(width: 8),
              Expanded(child: options[2]),
            ],
          ),
        if (way case final way?) ...[
          SizedBox(height: phone ? 6 : 14),
          _Form(key: ValueKey(way), source: source, way: way, onAdded: onAdded),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: PiumaIconView(
                        PiumaIcon.mail,
                        size: 14,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.calSuggested,
                        style: PiumaType.small.copyWith(color: c.muted),
                      ),
                    ),
                  ],
                ),
                for (final s in suggestions) ...[
                  const SizedBox(height: 8),
                  _Suggestion(
                    suggestion: s,
                    color: accountColors[s.accountId] ?? c.muted,
                    done: linked.contains(s.accountId),
                    onConnect: () => onLink(s),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
    if (phone) return body;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: body,
    );
  }
}

/// A kind of calendar to connect, as a tile.
class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    this.paren = '',
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String title;
  final String paren;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title $paren, $sub',
      child: ExcludeSemantics(
        child: PiumaPressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? c.soft : c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? c.accent : c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: instant ? Duration.zero : PiumaMotion.press,
                  curve: PiumaMotion.curve,
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? c.accent : c.bg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: PiumaIconView(
                    icon,
                    size: 16,
                    color: selected ? c.onAccent : c.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (paren.isNotEmpty)
                        TextSpan(
                          text: ' $paren',
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 14,
                    height: 1.35,
                    color: c.fg,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 12,
                    height: 1.35,
                    color: c.muted,
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

/// Where to connect: the address, then the password (CalDAV), or the
/// feed's address (.ics).
class _Form extends StatefulWidget {
  const _Form({
    super.key,
    required this.source,
    required this.way,
    required this.onAdded,
  });

  final MailSource source;
  final _Way way;
  final VoidCallback onAdded;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// CalDAV: the address is in, the password is asked next.
  bool _asking = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _url => _address.text.trim().contains('://');

  Future<void> _go() async {
    final l = AppLocalizations.of(context);
    final address = _address.text.trim();
    if (address.isEmpty) return;
    if (widget.way == _Way.calDav && !_asking) {
      setState(() => _asking = true);
      return;
    }
    if (widget.way == _Way.calDav && _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.way == _Way.calDav) {
        await widget.source.connectCalDav(
          address,
          username: _username.text.trim(),
          password: _password.text,
        );
      } else {
        await widget.source.subscribeCalendar(address);
      }
      if (mounted) widget.onAdded();
    } on AddAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.error) {
          AddAccountError.wrongPassword => l.calWrongPassword,
          AddAccountError.unreachable => l.calUnreachable,
          _ => l.calFailed,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l.calFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final calDav = widget.way == _Way.calDav;
    final google = widget.way == _Way.google;
    final cta = !calDav
        ? l.calSubscribe
        : _asking
        ? l.calConnectButton
        : MaterialLocalizations.of(context).continueButtonLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PiumaTextField(
          label: calDav
              ? l.calCalDavLabel
              : google
              ? l.calGoogleLabel
              : l.calIcsLabel,
          controller: _address,
          autofocus: true,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _go(),
        ),
        if (_asking) ...[
          if (_url) ...[
            const SizedBox(height: 10),
            PiumaTextField(
              label: l.calUsername,
              controller: _username,
              autofillHints: const [AutofillHints.username],
            ),
          ],
          const SizedBox(height: 10),
          PiumaTextField(
            label: l.calPassword,
            controller: _password,
            obscure: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _go(),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _error ??
                    (calDav
                        ? l.calCalDavHint
                        : google
                        ? l.calGoogleHint
                        : l.calIcsHint),
                style: PiumaType.small.copyWith(
                  color: _error == null ? c.muted : c.danger,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PiumaButton(label: cta, onPressed: _busy ? null : _go),
          ],
        ),
      ],
    );
  }
}

/// "matteo@studio.it has a calendar too   Connect".
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.suggestion,
    required this.color,
    required this.done,
    required this.onConnect,
  });

  final CalendarSuggestion suggestion;
  final Color color;
  final bool done;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: suggestion.email,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' ${l.calHasCalendar}',
                    style: TextStyle(color: c.muted),
                  ),
                ],
              ),
              style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
            ),
          ),
          const SizedBox(width: 10),
          if (done)
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  PiumaIconView(PiumaIcon.check, size: 14, color: c.ok),
                  const SizedBox(width: 4),
                  Text(l.calDone, style: PiumaType.small.copyWith(color: c.ok)),
                ],
              ),
            )
          else
            PiumaPressable(
              onTap: onConnect,
              semanticLabel: '${l.calConnectButton} ${suggestion.email}',
              child: ExcludeSemantics(
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l.calConnectButton,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.accentText,
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

/// A bordered group with lines between its rows.
class _Box extends StatelessWidget {
  const _Box({required this.children});
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

/// A connected source and its calendars, each with its availability
/// switch.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.defaultCalendar,
    required this.phone,
    required this.onDisconnect,
    required this.onAvailability,
  });

  final CalendarSource source;
  final int? defaultCalendar;
  final bool phone;
  final VoidCallback onDisconnect;
  final void Function(MailCalendar, bool) onAvailability;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final ics = source.kind == CalendarKind.ics;
    final icon = ics
        ? PiumaIcon.link
        : source.name == 'iCloud'
        ? PiumaIcon.cloud
        : source.accountId != null
        ? PiumaIcon.mail
        : PiumaIcon.server;
    final every = source.updatesEvery;
    final detail = source.accountId != null && !ics
        ? '${source.detail} · ${l.calFromAccount}'
        : every != null
        ? updatesEvery(l, every)
        : source.detail;
    final side = phone ? 14.0 : 18.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 10, side - 8, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: PiumaIconView(icon, size: 16, color: c.muted),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: source.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text:
                                  ' · ${ics ? l.calTypeIcs : l.calTypeCalDav}',
                              style: TextStyle(color: c.muted),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(
                          fontSize: 15,
                          height: 1.35,
                          color: c.fg,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.small.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                PiumaPressable(
                  onTap: onDisconnect,
                  semanticLabel: l.calDisconnectLabel(source.name),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        l.calDisconnect,
                        style: PiumaType.small.copyWith(
                          color: c.muted,
                          decoration: TextDecoration.underline,
                          decorationColor: c.line,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final cal in source.calendars)
            Padding(
              padding: EdgeInsets.fromLTRB(phone ? 60 : 64, 2, side, 2),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cal.color ?? c.ring,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              cal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PiumaType.body.copyWith(
                                fontSize: 14,
                                color: c.fg,
                              ),
                            ),
                          ),
                          if (cal.readOnly) ...[
                            const SizedBox(width: 8),
                            _Tag(text: l.calReadOnly, soft: false),
                          ],
                          if (cal.id == defaultCalendar) ...[
                            const SizedBox(width: 8),
                            _Tag(text: l.calInvitesTag, soft: true),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!phone) ...[
                      ExcludeSemantics(
                        child: Text(
                          l.calShowAvailability,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 12,
                            color: c.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    PiumaSwitch(
                      value: cal.availability,
                      label: l.calAvailabilityFor(cal.name),
                      onChanged: (on) => onAvailability(cal, on),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.soft});
  final String text;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: soft ? c.soft : c.chip,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: 11,
          color: soft ? c.accentText : c.muted,
        ),
      ),
    );
  }
}

/// A row of "When an invite arrives": icon tile, label and hint, and what
/// changes it.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.hint,
    required this.trailing,
    this.tag,
  });

  final PiumaIcon icon;
  final String label;
  final String hint;
  final Widget trailing;

  /// A small tag after the label ("on-device").
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: PiumaIconView(icon, size: 16, color: c.muted),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (tag case final tag?)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [_Tag(text: tag, soft: false)],
                            ),
                          ),
                        ),
                    ],
                  ),
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
          trailing,
        ],
      ),
    );
  }
}

/// The calendar invites go to, as a pill that opens the choice.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.calendar,
    required this.label,
    required this.onTap,
  });

  final MailCalendar? calendar;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = calendar?.name ?? l.calNoWritable;
    return Semantics(
      button: true,
      label: '$label: $name',
      child: ExcludeSemantics(
        child: PiumaPressable(
          onTap: calendar == null ? null : onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: calendar?.color ?? c.line,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
                  ),
                ),
                const SizedBox(width: 6),
                PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A calendar in the "Add to" choice.
class _MenuOption extends StatelessWidget {
  const _MenuOption({
    required this.calendar,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final MailCalendar calendar;
  final String source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${calendar.name}, $source',
      child: ExcludeSemantics(
        child: PiumaPressable(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? c.sel : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: calendar.color ?? c.ring,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    calendar.name,
                    style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
                  ),
                ),
                Text(source, style: PiumaType.small.copyWith(color: c.muted)),
                const SizedBox(width: 8),
                Opacity(
                  opacity: selected ? 1 : 0,
                  child: PiumaIconView(
                    PiumaIcon.check,
                    size: 14,
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

/// "updates daily", "updates every 6 hours": how often a feed is read.
String updatesEvery(AppLocalizations l, Duration every) =>
    every.inHours < 24 || every.inHours % 24 != 0
    ? l.calUpdatesHours(every.inHours.clamp(1, 1 << 20))
    : every.inDays == 7
    ? l.calUpdatesWeekly
    : l.calUpdatesDays(every.inDays);
