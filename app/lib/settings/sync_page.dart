import 'dart:async';

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';

/// Settings › Devices & sync, as on `SyncToApprove` (sync off) and
/// `Groups` (sync on): where the encrypted space lives, the devices that
/// read it, the recovery phrase and linking a new device.
class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    required this.source,
    this.phone = false,
    this.now = DateTime.now,
  });

  final MailSource source;
  final bool phone;
  final DateTime Function() now;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late SyncState _state = widget.source.syncState();
  late int? _home = widget.source.syncHomes().firstOrNull;
  bool _busy = false;
  bool _linking = false;
  String? _error;
  StreamSubscription<void>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.source.changes.listen((_) => _reload());
  }

  @override
  void dispose() {
    _changes?.cancel();
    if (_linking) widget.source.watchPairing(false);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _state = widget.source.syncState());
    // A phone that scanned the code is in: the panel has done its job.
    if (!_linking) return;
    final added = _state.devices
        .where((d) => !_linkedFrom.contains(d.id))
        .firstOrNull;
    if (added != null) {
      _toggleLink();
      setState(() => _linked = added.name);
    }
  }

  MailAccount? get _homeAccount =>
      widget.source.accounts.where((a) => a.id == _home).firstOrNull;

  String _failure(Object e) {
    final l = AppLocalizations.of(context);
    return switch (e) {
      SyncFailure(problem: SyncProblem.offline) => l.syncFailOffline(
        _state.home ?? _homeAccount?.email ?? '',
      ),
      SyncFailure(problem: SyncProblem.expired) => l.syncFailExpired,
      SyncFailure(problem: SyncProblem.taken) => l.syncFailTaken,
      _ => l.syncFailOther,
    };
  }

  Future<void> _turnOn() async {
    final home = _home;
    if (home == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phrase = await widget.source.turnOnSync(home);
      _reload();
      if (!mounted) return;
      await showRecoveryPhrase(context, phrase, phone: widget.phone);
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickHome(Rect anchor) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final homes = widget.source.syncHomes();
    final accounts = [
      for (final a in widget.source.accounts)
        if (homes.contains(a.id)) a,
    ];
    final on = _state.on;
    final current = on ? _storedIn?.id : _home;
    final label = on ? l.syncMailbox : l.syncStoreIn;
    Widget panel(BuildContext context) => _AccountChoices(
      accounts: accounts,
      current: current,
      phone: widget.phone,
    );
    final picked = widget.phone
        ? await showPiumaSheet<int>(context, label: label, builder: panel)
        : await showPiumaPopover<int>(
            context,
            label: label,
            anchor: anchor,
            width: 300,
            builder: panel,
          );
    if (picked == null || picked == current) return;
    if (on) {
      await _move(picked);
    } else {
      setState(() => _home = picked);
    }
  }

  /// The account whose mailbox holds the space while sync is on.
  MailAccount? get _storedIn => widget.source.accounts
      .where((a) => a.email.toLowerCase() == _state.home?.toLowerCase())
      .firstOrNull;

  Future<void> _move(int to) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.moveSync(to);
      _reload();
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPhrase() async {
    try {
      final phrase = await widget.source.recoveryPhrase();
      if (!mounted) return;
      await showRecoveryPhrase(context, phrase, phone: widget.phone);
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  Future<void> _unlink(SyncDevice d) async {
    final l = AppLocalizations.of(context);
    final yes = await showPiumaDialog<bool>(
      context,
      label: l.syncUnlinkAsk(d.name),
      builder: (context) {
        final c = PiumaTheme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.syncUnlinkAsk(d.name),
              style: PiumaType.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.syncUnlinkNote,
              style: PiumaType.body.copyWith(color: c.muted),
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
                  label: l.syncUnlink,
                  kind: PiumaButtonKind.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (yes != true) return;
    try {
      final phrase = await widget.source.unlinkDevice(d.id);
      _reload();
      if (mounted) {
        await showRecoveryPhrase(
          context,
          phrase,
          phone: widget.phone,
          unlinked: d.name,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  Future<void> _turnOff() async {
    final l = AppLocalizations.of(context);
    final s = _state;
    final others = [
      for (final d in s.devices)
        if (!d.thisDevice) d.name,
    ];
    final body = switch (others) {
      [] => l.syncTurnOffLast(s.home ?? ''),
      [final one] => l.syncTurnOffOne(one),
      [...final rest, final last] => l.syncTurnOffMany(
        '${rest.join(', ')} ${l.listAnd} $last',
      ),
    };
    final yes = await showPiumaDialog<bool>(
      context,
      label: l.syncTurnOffAsk,
      builder: (context) {
        final c = PiumaTheme.of(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.syncTurnOffAsk,
              style: PiumaType.body.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.fg,
              ),
            ),
            const SizedBox(height: 8),
            Text(body, style: PiumaType.body.copyWith(color: c.muted)),
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
                  label: l.syncTurnOffButton,
                  kind: PiumaButtonKind.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (yes != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.turnOffSync();
      _reload();
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleLink() {
    if (_linking) widget.source.endPairInvite();
    setState(() {
      _linking = !_linking;
      _linkedFrom = {for (final d in _state.devices) d.id};
      _linked = null;
    });
    widget.source.watchPairing(_linking);
  }

  /// The devices linked when "Link a new device" opened, to see a new one.
  Set<String> _linkedFrom = {};

  /// The device just linked while the panel showed: "Pixel 8 linked".
  String? _linked;

  String _ago(DateTime t) =>
      syncAgo(AppLocalizations.of(context), t, widget.now());

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final s = _state;
    final home = s.home;
    final homeName = widget.source.accounts
        .where((a) => a.email.toLowerCase() == home?.toLowerCase())
        .firstOrNull
        ?.name;
    final status = home == null
        ? _Status(dot: c.line, text: l.syncOff)
        : switch (s.syncedAt) {
            final at? => _Status(
              dot: c.ok,
              strong: l.syncAllSynced,
              text: _ago(at),
            ),
            null => _Status(dot: c.line, text: l.syncNotYet),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l.syncTitle, status: status),
        const SizedBox(height: 28),
        _Note(
          ok: home != null,
          text: home == null ? l.syncOffBody : l.syncOnBody(homeName ?? home),
          line: home == null ? l.syncOffNote : l.syncOnLine(home),
        ),
        if (home == null) ...[
          const SizedBox(height: 22),
          if (_homeAccount case final a?)
            _StoreIn(account: a, label: l.syncStoreIn, onTap: _pickHome),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: PiumaButton(
              label: l.syncTurnOn,
              size: widget.phone
                  ? PiumaButtonSize.touch
                  : PiumaButtonSize.standard,
              onPressed: _home == null || _busy ? null : _turnOn,
            ),
          ),
        ] else ...[
          if (_storedIn case final a?) ...[
            const SizedBox(height: 22),
            _StoreIn(
              account: a,
              label: l.syncMailbox,
              moving: _busy,
              onTap: _pickHome,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            l.syncDevices,
            style: PiumaType.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
          const SizedBox(height: 10),
          _Rows(
            children: [
              for (final d in s.devices)
                _DeviceRow(
                  device: d,
                  meta: d.thisDevice
                      ? l.syncThisDevice
                      : widget.now().difference(d.lastSeen).inMinutes < 5
                      ? l.syncActiveNow
                      : l.syncActive(_ago(d.lastSeen)),
                  live:
                      !d.thisDevice &&
                      widget.now().difference(d.lastSeen).inMinutes < 5,
                  onUnlink: d.thisDevice ? null : () => _unlink(d),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Rows(children: [_PhraseRow(onShow: _showPhrase)]),
          const SizedBox(height: 28),
          if (_linking)
            PiumaEnter(
              child: _LinkPanel(
                source: widget.source,
                email: home,
                now: widget.now,
                onCancel: _toggleLink,
              ),
            )
          else ...[
            if (_linked case final name?) ...[
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    PiumaIconView(PiumaIcon.check, size: 18, color: c.ok),
                    const SizedBox(width: 8),
                    Text(
                      l.syncLinked(name),
                      style: PiumaType.body.copyWith(color: c.ok),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Flex(
              direction: widget.phone ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: widget.phone
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                PiumaButton(
                  label: l.syncLinkNew,
                  size: widget.phone
                      ? PiumaButtonSize.touch
                      : PiumaButtonSize.standard,
                  onPressed: _toggleLink,
                ),
                if (widget.phone)
                  const SizedBox(height: 12)
                else
                  const Spacer(),
                _QuietDanger(
                  label: l.syncTurnOff,
                  onTap: _busy ? null : _turnOff,
                  flush: widget.phone,
                ),
              ],
            ),
          ],
        ],
        if (_error case final e?) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              e,
              style: PiumaType.body.copyWith(fontSize: 13, color: c.danger),
            ),
          ),
        ],
      ],
    );
  }
}

/// "2 min ago", "3 hours ago", "yesterday".
String syncAgo(AppLocalizations l, DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return l.accountJustNow;
  if (d.inMinutes < 60) return l.accountMinutesAgo(d.inMinutes);
  if (d.inHours < 24) return l.syncHoursAgo(d.inHours);
  if (d.inDays < 2) return l.syncYesterday;
  return l.syncDaysAgo(d.inDays);
}

class _Status {
  const _Status({required this.dot, required this.text, this.strong});
  final Color dot;
  final String text;

  /// Said first, in the dot's color: "All synced".
  final String? strong;
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.status});
  final String title;
  final _Status status;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final style = PiumaType.body.copyWith(color: c.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
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
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: status.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (status.strong case final s?) ...[
                      TextSpan(
                        text: s,
                        style: style.copyWith(
                          color: status.dot,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(text: ' · '),
                    ],
                    TextSpan(text: status.text),
                  ],
                ),
                style: style,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The lock and what sync does, on the page's soft ground.
class _Note extends StatelessWidget {
  const _Note({required this.ok, required this.text, required this.line});
  final bool ok;
  final String text;
  final String line;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PiumaIconView(
              PiumaIcon.lock,
              size: 20,
              color: ok ? c.ok : c.muted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
                ),
                const SizedBox(height: 4),
                Text(
                  line,
                  style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Store it in" (sync off) or "Sync mailbox" (on) and the account
/// picked; [moving] while the space goes to another mailbox.
class _StoreIn extends StatelessWidget {
  const _StoreIn({
    required this.account,
    required this.label,
    required this.onTap,
    this.moving = false,
  });
  final MailAccount account;
  final String label;
  final void Function(Rect anchor) onTap;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: PiumaType.body.copyWith(color: c.fg)),
          ),
          Builder(
            builder: (context) => PiumaPressable(
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                onTap(box.localToGlobal(Offset.zero) & box.size);
              },
              semanticLabel: '$label: ${moving ? l.syncMoving : account.email}',
              child: ExcludeSemantics(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      Flexible(
                        child: Text(
                          moving ? l.syncMoving : account.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PiumaType.body.copyWith(
                            color: moving ? c.muted : c.fg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PiumaIconView(PiumaIcon.upDown, size: 14, color: c.muted),
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

/// The accounts the space can live in; pops the one picked.
class _AccountChoices extends StatelessWidget {
  const _AccountChoices({
    required this.accounts,
    required this.current,
    required this.phone,
  });
  final List<MailAccount> accounts;
  final int? current;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: EdgeInsets.all(phone ? 12 : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in accounts)
            Semantics(
              selected: a.id == current,
              button: true,
              label: a.email,
              child: PiumaPressable(
                onTap: () => Navigator.of(context).pop(a.id),
                child: ExcludeSemantics(
                  child: Container(
                    height: phone ? 52 : 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: a.id == current ? c.sel : null,
                      borderRadius: BorderRadius.circular(PiumaRadius.row),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            a.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PiumaType.body.copyWith(color: c.fg),
                          ),
                        ),
                        if (a.id == current)
                          PiumaIconView(
                            PiumaIcon.check,
                            size: 16,
                            color: c.accentText,
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

/// A bordered group of rows with lines between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.children});
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

PiumaIcon deviceIcon(SyncDeviceKind kind) => switch (kind) {
  SyncDeviceKind.laptop => PiumaIcon.laptop,
  SyncDeviceKind.phone => PiumaIcon.phone,
  SyncDeviceKind.tablet => PiumaIcon.tablet,
};

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.meta,
    required this.live,
    this.onUnlink,
  });
  final SyncDevice device;
  final String meta;
  final bool live;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: PiumaIconView(
                deviceIcon(device.kind),
                size: 18,
                color: c.muted,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Row(
                  children: [
                    if (live) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: c.ok,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        meta,
                        style: PiumaType.body.copyWith(
                          fontSize: 13,
                          color: live ? c.ok : c.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onUnlink case final unlink?)
            PiumaPressable(
              onTap: unlink,
              semanticLabel: l.syncUnlinkName(device.name),
              child: ExcludeSemantics(
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l.syncUnlink,
                    style: PiumaType.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.danger,
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

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({required this.onShow});
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.syncPhraseRow,
                  style: PiumaType.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
                Text(
                  l.syncPhraseRowLine,
                  style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ),
          PiumaButton(
            label: l.syncShow,
            kind: PiumaButtonKind.secondary,
            size: PiumaButtonSize.compact,
            onPressed: onShow,
          ),
        ],
      ),
    );
  }
}

/// "Link a new device": what to do on the new one, while this device
/// listens for its request.
/// "Link a new device", as on `QrPairToApprove`: a QR code a phone scans,
/// a new one every five minutes, and the six digits for devices without
/// a camera.
class _LinkPanel extends StatefulWidget {
  const _LinkPanel({
    required this.source,
    required this.email,
    required this.now,
    required this.onCancel,
  });
  final MailSource source;
  final String email;
  final DateTime Function() now;
  final VoidCallback onCancel;

  @override
  State<_LinkPanel> createState() => _LinkPanelState();
}

class _LinkPanelState extends State<_LinkPanel> {
  PairInvite? _invite;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _invite = widget.source.pairInvite();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_invite case final i? when !widget.now().isBefore(i.expiresAt)) {
          _invite = widget.source.pairInvite();
        }
      });
    });
  }

  // The codes shown stay answered until the panel is closed on purpose
  // (see [_SyncPageState._toggleLink]): built anew, as when the window
  // changes size, this panel shows a new code while a phone may still be
  // asking with the one before.
  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final invite = _invite;
    final left = invite?.expiresAt.difference(widget.now());
    final time = left == null
        ? ''
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final body = Text(
      invite == null ? l.syncLinkBody(widget.email) : l.syncLinkScan,
      style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.syncLinkNew,
            style: PiumaType.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.34,
              color: c.fg,
            ),
          ),
          const SizedBox(height: 14),
          if (invite == null)
            body
          else
            Row(
              children: [
                _QrCode(invite: invite, label: l.syncLinkQrLabel),
                const SizedBox(width: 18),
                Expanded(child: body),
              ],
            ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              invite == null
                  ? l.syncLinkWaiting
                  : l.syncLinkNewCode(l.syncLinkWaiting, time),
              style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
            ),
          ),
          if (invite != null) ...[
            const SizedBox(height: 6),
            Text(
              l.syncLinkNoCamera(widget.email),
              style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
            ),
          ],
          const SizedBox(height: 14),
          PiumaButton(
            label: l.cancel,
            kind: PiumaButtonKind.secondary,
            size: PiumaButtonSize.standard,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

/// The invite's QR code, dark on paper in both themes, as cameras read it
/// best.
class _QrCode extends StatelessWidget {
  const _QrCode({required this.invite, required this.label});
  final PairInvite invite;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final paper = PiumaColors.light;
    return Semantics(
      image: true,
      label: label,
      child: Container(
        width: 168,
        height: 168,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: paper.page,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: CustomPaint(painter: _QrPainter(invite, paper.fg)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.invite, this.ink);
  final PairInvite invite;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final n = invite.width;
    final m = size.shortestSide / n;
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (invite.modules[y * n + x]) {
          path.addRect(Rect.fromLTWH(x * m, y * m, m + 0.01, m + 0.01));
        }
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.invite != invite;
}

/// "Your recovery phrase": the 24 words, numbered, once after turning
/// sync on, again from Devices & sync, and a new one after Unlink. A
/// dialog on the desktop, a sheet on the phone.
Future<void> showRecoveryPhrase(
  BuildContext context,
  String phrase, {
  bool phone = false,
  String? unlinked,
}) {
  final l = AppLocalizations.of(context);
  final title = unlinked == null ? l.syncPhraseTitle : l.syncPhraseNewTitle;
  Widget panel(BuildContext context) => _PhrasePanel(
    title: title,
    body: unlinked == null ? l.syncPhraseBody : l.syncPhraseNewBody(unlinked),
    words: phrase.split(' '),
    phone: phone,
  );
  return phone
      ? showPiumaSheet<void>(context, label: title, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: title,
          width: 620,
          builder: panel,
        );
}

class _PhrasePanel extends StatelessWidget {
  const _PhrasePanel({
    required this.title,
    required this.body,
    required this.words,
    required this.phone,
  });
  final String title;
  final String body;
  final List<String> words;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final columns = phone ? 3 : 4;
    final done = PiumaButton(
      label: l.syncPhraseDone,
      size: phone ? PiumaButtonSize.large : PiumaButtonSize.standard,
      onPressed: () => Navigator.of(context).pop(),
    );
    final warn = Text(
      l.syncPhraseWarn,
      style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
    );
    return Padding(
      padding: phone
          ? const EdgeInsets.fromLTRB(20, 8, 20, 4)
          : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: PiumaType.body.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: c.fg,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(body, style: PiumaType.body.copyWith(color: c.muted)),
          const SizedBox(height: 18),
          Semantics(
            label: l.syncPhraseRow,
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 6.0;
                final width = (box.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final (i, w) in words.indexed)
                      Semantics(
                        label: l.syncPhraseWord(i + 1, w),
                        child: ExcludeSemantics(
                          child: Container(
                            width: width,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: c.bg,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  child: Text(
                                    '${i + 1}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontFamily: PiumaFonts.mono,
                                      fontSize: 12,
                                      color: c.muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    w,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: PiumaFonts.mono,
                                      fontSize: 14,
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
              },
            ),
          ),
          const SizedBox(height: 18),
          if (phone) ...[
            warn,
            const SizedBox(height: 14),
            done,
          ] else
            Row(
              children: [
                Expanded(child: warn),
                const SizedBox(width: 10),
                done,
              ],
            ),
        ],
      ),
    );
  }
}

/// "Turn off sync on this device": a quiet line in the danger color, no
/// fill, at the foot of the page.
class _QuietDanger extends StatelessWidget {
  const _QuietDanger({
    required this.label,
    required this.onTap,
    this.flush = false,
  });

  final String label;
  final VoidCallback? onTap;

  /// Lined up with the button above it (on the phone), not padded.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 36,
        padding: EdgeInsets.symmetric(horizontal: flush ? 0 : 12),
        child: Center(
          widthFactor: 1,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: PiumaType.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.danger,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
