import 'package:piuma_mail/notify/notifier.dart';

/// Keeps what would have been shown, and lets tests click a notice.
class FakeNotifier implements Notifier {
  final shown = <SystemNotice>[];
  void Function(String payload)? _onOpen;
  NoticeButtons? _buttons;

  @override
  Future<void> init(
    void Function(String payload) onOpen, {
    required String openLabel,
    required String channelLabel,
    NoticeButtons? buttons,
  }) async {
    _onOpen = onOpen;
    _buttons = buttons;
  }

  @override
  Future<void> show(SystemNotice notice) async => shown.add(notice);

  void click(SystemNotice notice) => _onOpen?.call(notice.payload);

  /// Presses one of the notice's buttons, with [text] typed for Reply.
  void press(SystemNotice notice, String action, [String? text]) =>
      _buttons?.onAction(notice.payload, action, text);
}
