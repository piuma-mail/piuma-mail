import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// "Shake to report" (`FeedbackToApprove`): on a phone with an
/// accelerometer, shaking it opens the report sheet. Android only for now
/// (`Shake.kt`); elsewhere the setting is not offered.
abstract final class Shake {
  static const _sensors = MethodChannel('mail.piuma/sensors');
  static const _events = EventChannel('mail.piuma/shake');

  static Future<bool>? _available;

  /// Whether this device can tell a shake: an Android phone or tablet with
  /// an accelerometer. Asked once.
  static Future<bool> available() =>
      _available ??= availableOverride != null ? availableOverride!() : _ask();

  static Future<bool> _ask() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _sensors.invokeMethod<bool>('accelerometer') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// An event each time the device is shaken. The sensor is on only while
  /// this is listened to.
  static Stream<void> shakes() =>
      shakesOverride?.call() ?? _events.receiveBroadcastStream();

  /// For tests: stands in for the sensor.
  @visibleForTesting
  static Future<bool> Function()? availableOverride;

  /// For tests: stands in for the shakes.
  @visibleForTesting
  static Stream<void> Function()? shakesOverride;

  @visibleForTesting
  static void reset() {
    _available = null;
    availableOverride = null;
    shakesOverride = null;
  }
}

/// Listens for shakes while [enabled] is on and the app is in front, and
/// calls [onShake] for each.
class ShakeWatch with WidgetsBindingObserver {
  ShakeWatch({required this.enabled, required this.onShake}) {
    enabled.addListener(_update);
    WidgetsBinding.instance.addObserver(this);
    _update();
  }

  final ValueListenable<bool> enabled;
  final VoidCallback onShake;
  StreamSubscription<void>? _sub;
  bool _disposed = false;

  bool get _wanted {
    final state = WidgetsBinding.instance.lifecycleState;
    return !_disposed &&
        enabled.value &&
        (state == null || state == AppLifecycleState.resumed);
  }

  Future<void> _update() async {
    if (!_wanted) {
      final sub = _sub;
      _sub = null;
      await sub?.cancel();
      return;
    }
    if (_sub != null || !await Shake.available()) return;
    // Things may have changed while asking.
    if (!_wanted || _sub != null) return;
    _sub = Shake.shakes().listen((_) => onShake(), onError: (Object _) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _update();

  void dispose() {
    _disposed = true;
    enabled.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _sub = null;
  }
}
