import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// What a notice opens is named by its payload (an account, a folder, a
/// message). On Android the app's activity can be started by any other
/// app, with any payload, so every payload a notice carries is sealed
/// with a key of this installation (`NoticeSeal.kt`) and nothing opens
/// unless its seal checks. Elsewhere payloads pass as they are.
abstract class NoticeSeal {
  const NoticeSeal();

  /// [payload], sealed to travel in a notice.
  Future<String> seal(String payload);

  /// The payload [sealed] carries, or null when its seal doesn't check.
  Future<String?> open(String sealed);
}

class _NoSeal extends NoticeSeal {
  const _NoSeal();

  @override
  Future<String> seal(String payload) async => payload;

  @override
  Future<String?> open(String sealed) async => sealed;
}

class _AndroidSeal extends NoticeSeal {
  const _AndroidSeal();

  static const _channel = MethodChannel('mail.piuma/notices');

  @override
  Future<String> seal(String payload) async =>
      await _channel.invokeMethod<String>('seal', payload) ?? payload;

  @override
  Future<String?> open(String sealed) async {
    try {
      return await _channel.invokeMethod<String>('unseal', sealed);
    } on PlatformException {
      return null;
    }
  }
}

/// The seal notices use here. Tests replace it.
NoticeSeal noticeSeal = !kIsWeb && Platform.isAndroid
    ? const _AndroidSeal()
    : const _NoSeal();
