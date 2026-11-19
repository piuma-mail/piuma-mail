import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'arrivals.dart';

/// Whether Piuma handles `mailto:` links on this device.
enum DefaultMail {
  /// Piuma opens them.
  piuma,

  /// Another app does; [Shell.makeDefault] lets the person change it.
  other,

  /// None is set: the system asks, and Piuma is offered.
  none,

  /// The system doesn't say (Windows, a Linux build without its desktop
  /// file): [Shell.makeDefault] still opens where to choose.
  unknown,

  /// Nothing to offer here (a Linux build from source that isn't
  /// installed): the help explains how.
  unavailable,
}

/// What the app asks of the system it runs on, around its window: keep
/// running in the tray when closed, start at sign-in, be the default mail
/// app, show the unread count where the desktop shows one. Its platform
/// side shares [Arrivals.channel]. Where a platform lacks one of these,
/// it quietly does nothing.
class Shell {
  Shell._();

  static const _channel = Arrivals.channel;

  /// Whether this platform can keep running with its window closed (a
  /// tray icon, or the launcher bringing it back).
  static bool get canKeepRunning =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  /// Whether it can start on its own at sign-in.
  static bool get canStartAtLogin => canKeepRunning;

  /// Whether Settings can offer "Make Piuma your default mail app".
  static bool get canBeDefault =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('shell $method: ${e.message}');
      return null;
    }
  }

  /// Closing the window leaves the app running, with a tray icon whose
  /// menu says [open], [compose] and [quit].
  static Future<void> keepRunning(
    bool on, {
    required String open,
    required String compose,
    required String quit,
  }) => _call<void>('keepRunning', {
    'on': on,
    'open': open,
    'compose': compose,
    'quit': quit,
  });

  /// Starts the app at sign-in, without its window.
  static Future<void> startAtLogin(bool on) =>
      _call<void>('startAtLogin', {'on': on});

  /// How many emails are unread, for the tray's tooltip ([tooltip]) and
  /// the Linux launcher's count.
  static int? _unread;
  static Future<void> unread(int count, {required String tooltip}) async {
    if (_unread == count) return;
    _unread = count;
    await _call<void>('unread', {'count': count, 'tooltip': tooltip});
  }

  static Future<DefaultMail> defaultMail() async {
    final state = await _call<String>('defaultMail');
    return DefaultMail.values.asNameMap()[state] ?? DefaultMail.unavailable;
  }

  /// Asks the system to make Piuma the default mail app: its own question
  /// on macOS, the Default apps page on Windows, the app that holds
  /// `mailto:` on Android. Returns the state afterwards, where it is
  /// known at once.
  static Future<DefaultMail> makeDefault() async {
    final state = await _call<String>('makeDefault');
    return DefaultMail.values.asNameMap()[state] ?? DefaultMail.unknown;
  }

  /// Quits for good, even while it keeps running in the tray.
  static Future<void> quit() {
    quitting();
    return _call<void>('quit');
  }

  static VoidCallback? _onQuitting;

  /// Tells the platform side where the running session's [marker] is, so
  /// it can remove it on the ways out that never reach Dart in time
  /// (signing out, shutting down), and what to do when it quits on its
  /// own (the tray's Quit): [onQuitting], before it goes.
  static Future<void> watchSession({
    required String marker,
    required VoidCallback onQuitting,
  }) {
    _onQuitting = onQuitting;
    if (marker.isEmpty) return Future.value();
    return _call<void>('session', {'marker': marker});
  }

  /// The app is about to quit: the platform side asks before it goes, and
  /// waits (briefly) for the answer.
  static void quitting() {
    try {
      _onQuitting?.call();
    } catch (e) {
      debugPrint('shell quitting: $e');
    }
  }

  /// Forgets what was sent, for tests.
  @visibleForTesting
  static void reset() {
    _unread = null;
    _onQuitting = null;
  }
}
