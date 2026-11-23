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

  /// The phones (Data Layer nodes) connected now: mail is shown only
  /// from one of them.
  Set<String> _phones = {};

  /// What was seen from each phone, by node ([_take]).
  final _seen = <String, _Seen>{};

  /// Reads what the watch kept, then asks the phone for a fresh summary.
  Future<void> start() async {
    await _askPhones();
    final kept = _unpack(await _call<Object>('summary'));
    _take(Summary.parse(kept.json), kept.node, kept: true);
    notifyListeners();
    await refresh();
  }

  /// Shows [s], from the phone [node], unless it must not be:
  /// - a locked summary is always taken, from any phone, whatever its
  ///   epoch or generation: it only hides, and the words of emails read
  ///   here go with it;
  /// - one with mail only from a phone connected now ([_phones]), and
  ///   only when it is newer than every locked one seen from that phone
  ///   (its generation is higher; generations start from the time in
  ///   milliseconds, so this holds across installs too), and not from an
  ///   epoch that phone has already left behind (an older install of the
  ///   app, arriving late);
  /// - within one epoch, not when an older generation than one seen;
  /// - what the watch [kept] (read at start, maybe made long ago, maybe
  ///   with no phone connected) only while nothing else is shown.
  bool _take(Summary? s, String? node, {bool kept = false}) {
    if (s == null) return false;
    final seen = _seen.putIfAbsent(node ?? '', _Seen.new);
    if (!s.locked) {
      if (seen.left.contains(s.epoch)) return false;
      if (seen.locked case final gen? when s.gen <= gen) return false;
      if (s.epoch == seen.epoch && s.gen < seen.newest) return false;
      if (kept) {
        if (_summary != null) return false;
      } else if (node == null || !_phones.contains(node)) {
        return false;
      }
    }
    seen.add(s);
    _summary = s;
    if (s.locked) _texts.clear();
    return true;
  }

  /// Asks which phones are connected now.
  Future<void> _askPhones() async {
    final phones = await _call<List<Object?>>('phones');
    _phones = {...?phones?.whereType<String>()};
  }

  /// A summary as `WatchChannel.kt` hands it over: `{"node", "json"}`.
  static ({String? node, String? json}) _unpack(Object? m) => switch (m) {
    {'node': final String? node, 'json': final String? json} => (
      node: node,
      json: json,
    ),
    final String json => (node: null, json: json),
    _ => (node: null, json: null),
  };

  Future<void> refresh() async {
    await _askPhones();
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

  /// Answers [payload] with [text], to everyone it went to.
  Future<void> replyAll(String payload, String text) =>
      _act(payload, 'replyAll', text: text);

  /// The system's input (voice, keyboard, handwriting); null when the
  /// person went back.
  Future<String?> speak(String label) => _call<String>('speak', label);

  Future<void> _act(
    String payload,
    String action, {
    DateTime? until,
    String text = '',
  }) async {
    if (action != 'reply' && action != 'replyAll') {
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
        final m = _unpack(call.arguments);
        final s = Summary.parse(m.json);
        // Mail from a phone not known to be connected: maybe one just
        // paired. Asked again before it is turned down.
        if (s != null && !s.locked && m.node != null) {
          if (!_phones.contains(m.node)) await _askPhones();
        }
        if (_take(s, m.node)) notifyListeners();
      case 'text':
        // Nothing is kept while the phone is locked.
        if (_summary?.locked ?? false) return;
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

/// What [PhoneLink] saw from one phone.
class _Seen {
  /// The epoch of the phone app's install seen last ([Summary.epoch]),
  /// and the newest generation seen in it.
  String? epoch;
  int newest = -1;

  /// Epochs this phone has moved on from.
  final left = <String>{};

  /// The highest generation of a locked summary seen from this phone.
  int? locked;

  void add(Summary s) {
    if (s.locked) locked = s.gen > (locked ?? -1) ? s.gen : locked;
    if (left.contains(s.epoch)) return;
    if (s.epoch != epoch) {
      if (epoch case final e?) left.add(e);
      epoch = s.epoch;
      newest = s.gen;
    } else if (s.gen > newest) {
      newest = s.gen;
    }
  }
}

/// Hands the link down the tree.
class LinkScope extends InheritedNotifier<PhoneLink> {
  const LinkScope({super.key, required PhoneLink link, required super.child})
    : super(notifier: link);

  static PhoneLink of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinkScope>()!.notifier!;
}
