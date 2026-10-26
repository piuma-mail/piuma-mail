import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'summary.dart';

/// The watch's side of the link with the phone (`WatchChannel.kt` here,
/// `WatchLink.kt` on the phone). The phone keeps the mail; the watch
/// shows its summary and asks it to act.
class PhoneLink extends ChangeNotifier {
  PhoneLink({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('mail.piuma.wear/link') {
    _channel.setMethodCallHandler(_heard);
  }

  final MethodChannel _channel;
  final _texts = <String, String>{};
  final _rotary = StreamController<double>.broadcast();

  Summary? _summary;
  bool _asked = false;

  /// What the phone sent last; null until it sends something.
  Summary? get summary => _summary;

  /// True once the watch asked the phone at least once.
  bool get asked => _asked;

  /// How far the crown or bezel turned, in pixels, as it turns.
  Stream<double> get rotary => _rotary.stream;

  /// The words of the email [payload] names, once the phone sent them.
  String? text(String payload) => _texts[payload];

  /// Reads what the watch kept, then asks the phone for a fresh summary.
  Future<void> start() async {
    _summary = Summary.parse(await _call<String>('summary')) ?? _summary;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    await _call<void>('refresh');
    _asked = true;
    notifyListeners();
  }

  /// Asks the phone for the words of [payload]; [text] has them once
  /// they come.
  Future<void> open(String payload) => _call<void>('open', payload);

  /// Archives [payload] on the phone.
  Future<void> archive(String payload) => _act(payload, 'archive');

  /// Snoozes [payload] until [until].
  Future<void> snooze(String payload, DateTime until) =>
      _act(payload, 'snooze', until: until);

  /// Answers [payload] with [text], from its own account.
  Future<void> reply(String payload, String text) =>
      _act(payload, 'reply', text: text);

  /// The system's input (voice, keyboard, handwriting); null when the
  /// person went back.
  Future<String?> speak(String label) => _call<String>('speak', label);

  Future<void> _act(
    String payload,
    String action, {
    DateTime? until,
    String text = '',
  }) async {
    if (action != 'reply') {
      _summary = _summary?.without(payload);
      notifyListeners();
    }
    await _call<void>(
      'act',
      jsonEncode({
        'payload': payload,
        'action': action,
        'until': (until ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
        'text': text,
      }),
    );
  }

  Future<dynamic> _heard(MethodCall call) async {
    switch (call.method) {
      case 'summary':
        final s = Summary.parse(call.arguments as String?);
        if (s != null) {
          _summary = s;
          notifyListeners();
        }
      case 'text':
        try {
          final m =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          _texts[m['payload'] as String] = m['text'] as String;
          notifyListeners();
        } on Object {
          // Not an answer the watch understands.
        }
      case 'rotary':
        _rotary.add((call.arguments as num).toDouble());
    }
  }

  /// A call to the Kotlin side; nothing when there is none (tests).
  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  void dispose() {
    _rotary.close();
    super.dispose();
  }
}

/// Hands the link down the tree.
class LinkScope extends InheritedNotifier<PhoneLink> {
  const LinkScope({super.key, required PhoneLink link, required super.child})
    : super(notifier: link);

  static PhoneLink of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinkScope>()!.notifier!;
}
