import 'dart:async';

/// Keeps listening to a stream that should never end, such as the
/// engine's sync events: when it fails or closes, it is opened again after
/// [first], then twice as long each time in a row, up to [most]. An event
/// that comes through starts the waits over. Without this, a stream that
/// ended left the app showing what it last knew until it was restarted.
class Resubscriber<T> {
  Resubscriber(
    this._open,
    this._onData, {
    this.first = const Duration(seconds: 1),
    this.most = const Duration(minutes: 1),
  });

  final Stream<T> Function() _open;
  final void Function(T) _onData;
  final Duration first;
  final Duration most;

  StreamSubscription<T>? _subscription;
  Timer? _again;
  Duration? _wait;
  bool _cancelled = false;

  /// Opens the stream, afresh when it was open.
  void start() {
    _cancelled = false;
    _again?.cancel();
    _again = null;
    _subscription?.cancel();
    _subscription = null;
    final Stream<T> stream;
    try {
      stream = _open();
    } catch (_) {
      _retry();
      return;
    }
    _subscription = stream.listen(
      (event) {
        _wait = null;
        _onData(event);
      },
      onError: (Object _) => _lost(),
      onDone: _lost,
      cancelOnError: true,
    );
  }

  void _lost() {
    _subscription = null;
    if (!_cancelled) _retry();
  }

  void _retry() {
    final last = _wait;
    final wait = last == null ? first : (last * 2 > most ? most : last * 2);
    _wait = wait;
    _again = Timer(wait, start);
  }

  /// Stops listening for good.
  void cancel() {
    _cancelled = true;
    _again?.cancel();
    _again = null;
    _subscription?.cancel();
    _subscription = null;
  }
}
