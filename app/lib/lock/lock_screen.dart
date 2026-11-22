import 'dart:async';

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/brand.dart';
import '../widgets/button.dart';
import '../widgets/text_field.dart';
import 'app_lock.dart';

/// Gives the screens below the [AppLock], for Settings.
class AppLockScope extends InheritedNotifier<AppLock> {
  const AppLockScope({super.key, required AppLock lock, required super.child})
    : super(notifier: lock);

  static AppLock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLockScope>()?.notifier;
}

/// Around the whole app (`PiumaApp`'s builder): while locked, the app
/// stays as it was underneath but isn't drawn, focused or read out, and
/// the lock screen covers it. Follows the app going to the background
/// and back.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.lock,
    required this.child,
    this.autoPrompt = true,
  });

  final AppLock lock;
  final Widget child;

  /// Asks for the device's unlock as soon as the lock screen is in front.
  final bool autoPrompt;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  late final AppLifecycleListener _life;

  /// Bumped to ask the lock screen for the device's unlock.
  int _prompt = 0;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onHide: widget.lock.left,
      onPause: widget.lock.left,
      onShow: _back,
      onResume: _back,
    );
    widget.lock.addListener(_changed);
    if (widget.lock.locked && widget.autoPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askDevice());
    }
  }

  void _back() {
    widget.lock.back();
    // Locked just now, or while away: asked again in front, unless this
    // is the app coming back from the system's own unlock sheet.
    if (widget.autoPrompt &&
        widget.lock.locked &&
        !widget.lock.justPrompted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _askDevice();
    }
  }

  void _askDevice() {
    if (!mounted || !widget.lock.deviceUnlock) return;
    setState(() => _prompt++);
  }

  void _changed() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Android's background service writes notices in the app's language.
    widget.lock.noticeText(AppLocalizations.of(context).noticeLocked).ignore();
  }

  @override
  void dispose() {
    widget.lock.removeListener(_changed);
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.lock.locked;
    return AppLockScope(
      lock: widget.lock,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: locked,
            child: TickerMode(
              enabled: !locked,
              child: ExcludeFocus(
                excluding: locked,
                child: ExcludeSemantics(excluding: locked, child: widget.child),
              ),
            ),
          ),
          if (locked)
            // An overlay of its own: the app's navigator is underneath.
            Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) =>
                      LockScreen(lock: widget.lock, prompt: _prompt),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "Piuma is locked": the logo, Unlock (the device's own unlock, where
/// there is one) and the PIN.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock, this.prompt = 0});

  final AppLock lock;

  /// A new value asks for the device's unlock.
  final int prompt;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  late bool _usePin = !widget.lock.deviceUnlock;
  bool _busy = false;
  bool _wrong = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _watchWait();
    if (widget.prompt > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _device());
    }
  }

  @override
  void didUpdateWidget(LockScreen old) {
    super.didUpdateWidget(old);
    if (widget.prompt != old.prompt && widget.prompt > 0) _device();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pin.dispose();
    super.dispose();
  }

  /// A second-by-second countdown while a wait is on.
  void _watchWait() {
    _tick?.cancel();
    if (widget.lock.waitLeft == Duration.zero) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (widget.lock.waitLeft == Duration.zero) _tick?.cancel();
    });
  }

  Future<void> _device() async {
    if (_busy || !widget.lock.deviceUnlock) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    await widget.lock.tryDevice(l.lockReason);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    if (_busy || pin.isEmpty || widget.lock.waitLeft > Duration.zero) return;
    setState(() => _busy = true);
    final result = await widget.lock.tryPin(pin);
    if (!mounted) return;
    _pin.clear();
    setState(() {
      _busy = false;
      _wrong = result is PinWrong;
    });
    if (result is! PinRight) _watchWait();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final lock = widget.lock;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final size = phone ? PiumaButtonSize.large : PiumaButtonSize.touch;
    final wait = lock.waitLeft;
    final usePin = (_usePin || !lock.deviceUnlock) && !lock.pinUnreadable;

    final String? problem = lock.pinUnreadable
        ? l.lockPinUnreadable
        : wait > Duration.zero
        ? l.lockWait(_clock(wait))
        : _wrong
        ? l.lockWrongPin
        : null;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: PiumaBrand(size: 22, stacked: true)),
        const SizedBox(height: PiumaSpace.s32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PiumaIconView(PiumaIcon.lock, size: 18, color: c.muted),
            const SizedBox(width: PiumaSpace.s8),
            Flexible(
              child: Text(
                l.lockTitle,
                textAlign: TextAlign.center,
                style: PiumaType.subtitle.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s8),
        Text(
          usePin ? l.lockPinPrompt : l.lockDevicePrompt,
          textAlign: TextAlign.center,
          style: PiumaType.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: PiumaSpace.s24),
        if (usePin) ...[
          PiumaTextField(
            key: const ValueKey('lock-pin'),
            label: l.lockPinLabel,
            controller: _pin,
            obscure: true,
            mono: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: PiumaSpace.s16),
        ],
        AnimatedSize(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          child: problem == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: PiumaSpace.s16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      problem,
                      textAlign: TextAlign.center,
                      style: PiumaType.small.copyWith(
                        color: lock.pinUnreadable ? c.muted : c.danger,
                      ),
                    ),
                  ),
                ),
        ),
        if (usePin)
          PiumaButton(
            label: l.lockUnlock,
            size: size,
            onPressed: _busy || wait > Duration.zero ? null : _submit,
          )
        else
          PiumaButton(
            label: l.lockUnlock,
            size: size,
            onPressed: _busy ? null : _device,
          ),
        if (lock.deviceUnlock && !lock.pinUnreadable) ...[
          const SizedBox(height: PiumaSpace.s8),
          PiumaButton(
            label: usePin ? l.lockUseDevice : l.lockUsePin,
            kind: PiumaButtonKind.tertiary,
            size: size,
            onPressed: _busy
                ? null
                : () {
                    setState(() => _usePin = !usePin);
                    if (usePin) _device();
                  },
          ),
        ],
        if (usePin) ...[
          const SizedBox(height: PiumaSpace.s24),
          Text(
            lock.deviceAvailable ? l.lockForgotDevice : l.lockForgot,
            textAlign: TextAlign.center,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ],
      ],
    );

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(PiumaSpace.s24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: l.lockTitle,
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 0:30, 14:59, 1:00:00.
String _clock(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
