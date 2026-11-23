import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_screen.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/segments.dart';
import '../widgets/text_field.dart';
import 'app_lock.dart';

/// Settings › Privacy & security › Lock Piuma: off by default; once on,
/// when it locks, the device's own unlock and the PIN.
class LockSection extends StatefulWidget {
  const LockSection({super.key, required this.lock});
  final AppLock lock;

  @override
  State<LockSection> createState() => _LockSectionState();
}

class _LockSectionState extends State<LockSection> {
  /// Turning on failed: the keychain couldn't keep the PIN.
  bool _failed = false;

  AppLock get lock => widget.lock;

  Future<void> _turnOn() async {
    final l = AppLocalizations.of(context);
    final pin = await askNewPin(context, title: l.lockChoosePin);
    if (pin == null || !mounted) return;
    try {
      await lock.enable(
        pin,
        settings: LockSettings(
          device: lock.deviceAvailable,
          notice: l.noticeLocked,
        ),
      );
      setState(() => _failed = false);
    } on Object {
      setState(() => _failed = true);
    }
  }

  Future<void> _changePin() async {
    final l = AppLocalizations.of(context);
    final pin = await askNewPin(context, title: l.lockChangePin);
    if (pin == null || !mounted) return;
    try {
      await lock.changePin(pin);
      setState(() => _failed = false);
    } on Object {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final s = lock.settings;
    String afterLabel(LockAfter a) => switch (a) {
      LockAfter.immediately => l.lockAfterNow,
      LockAfter.oneMinute => l.lockAfterMinutes(1),
      LockAfter.fiveMinutes => l.lockAfterMinutes(5),
      LockAfter.fifteenMinutes => l.lockAfterMinutes(15),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsCard(
          children: [
            SettingsSwitchRow(
              icon: PiumaIcon.lock,
              label: l.lockSetting,
              hint: l.lockSettingHint,
              value: s != null,
              onChanged: (on) => on ? _turnOn() : lock.disable(),
            ),
            if (s != null) ...[
              _Row(
                icon: PiumaIcon.clock,
                label: l.lockAfter,
                below: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PiumaSegments(
                    label: l.lockAfter,
                    items: [
                      for (final a in LockAfter.values)
                        (
                          afterLabel(a),
                          s.after == a,
                          () => lock.update(s.copyWith(after: a)),
                        ),
                    ],
                  ),
                ),
              ),
              if (lock.deviceAvailable)
                SettingsSwitchRow(
                  icon: PiumaIcon.fingerprint,
                  label: l.lockDeviceSetting,
                  hint: _deviceHint(l),
                  value: s.device,
                  onChanged: (v) => lock.update(s.copyWith(device: v)),
                ),
              _Row(
                icon: PiumaIcon.keyboard,
                label: l.lockPinLabel,
                hint: l.lockPinHint,
                trailing: PiumaButton(
                  label: l.lockChangePin,
                  kind: PiumaButtonKind.secondary,
                  size: PiumaButtonSize.compact,
                  onPressed: _changePin,
                ),
              ),
            ],
          ],
        ),
        if (_failed) ...[
          const SizedBox(height: PiumaSpace.s12),
          Text(
            l.lockNoKeychain,
            style: PiumaType.small.copyWith(color: c.danger),
          ),
        ],
        if (s != null) ...[
          const SizedBox(height: PiumaSpace.s12),
          Text(
            l.lockSettingNote,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ],
      ],
    );
  }

  String _deviceHint(AppLocalizations l) {
    if (Platform.isWindows) return l.lockDeviceHintWindows;
    if (Platform.isMacOS || Platform.isIOS) return l.lockDeviceHintApple;
    return l.lockDeviceHint;
  }
}

/// A settings row with its icon, as [SettingsSwitchRow], and a control
/// beside or below the label.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.hint,
    this.trailing,
    this.below,
  });

  final PiumaIcon icon;
  final String label;
  final String? hint;
  final Widget? trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final head = Row(
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
              if (hint case final h?)
                Text(
                  h,
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
        if (trailing case final t?) ...[const SizedBox(width: 16), t],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: below == null
          ? head
          // Below the icon too, so four choices fit a phone's width.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [head, const SizedBox(height: 12), below!],
            ),
    );
  }
}

/// Asks for a new PIN twice; null when cancelled.
Future<String?> askNewPin(BuildContext context, {required String title}) {
  return showPiumaDialog<String>(
    context,
    label: title,
    width: 380,
    builder: (_) => _NewPin(title: title),
  );
}

class _NewPin extends StatefulWidget {
  const _NewPin({required this.title});
  final String title;

  @override
  State<_NewPin> createState() => _NewPinState();
}

class _NewPinState extends State<_NewPin> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final pin = _pin.text.trim();
    if (!RegExp(r'^[0-9]{4,12}$').hasMatch(pin)) {
      setState(() => _problem = l.lockPinRule);
      return;
    }
    if (_again.text.trim() != pin) {
      setState(() => _problem = l.lockPinMismatch);
      return;
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: PiumaType.subtitle.copyWith(color: c.fg)),
          const SizedBox(height: PiumaSpace.s8),
          Text(
            l.lockPinWarning,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
          const SizedBox(height: PiumaSpace.s20),
          PiumaTextField(
            key: const ValueKey('new-pin'),
            label: l.lockNewPin,
            controller: _pin,
            obscure: true,
            mono: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: PiumaSpace.s12),
          PiumaTextField(
            key: const ValueKey('new-pin-again'),
            label: l.lockPinAgain,
            controller: _again,
            obscure: true,
            mono: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _save(),
          ),
          if (_problem case final p?) ...[
            const SizedBox(height: PiumaSpace.s12),
            Text(p, style: PiumaType.small.copyWith(color: c.danger)),
          ],
          const SizedBox(height: PiumaSpace.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PiumaButton(
                label: l.cancel,
                kind: PiumaButtonKind.tertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: PiumaSpace.s8),
              PiumaButton(label: l.lockSavePin, onPressed: _save),
            ],
          ),
        ],
      ),
    );
  }
}
