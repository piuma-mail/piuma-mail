import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/notify/notifier.dart';

/// Seals as Android does, with a key the test knows: a payload passes only
/// with its own seal.
class _Seal extends NoticeSeal {
  const _Seal();

  @override
  Future<String> seal(String payload) async => '$payload\n#seal:ok-$payload';

  @override
  Future<String?> open(String sealed) async {
    final at = sealed.lastIndexOf('\n#seal:');
    if (at < 0) return null;
    final payload = sealed.substring(0, at);
    return sealed.substring(at + 7) == 'ok-$payload' ? payload : null;
  }
}

void main() {
  NotificationResponse tap(String payload, {String? action}) =>
      NotificationResponse(
        notificationResponseType: action == null
            ? NotificationResponseType.selectedNotification
            : NotificationResponseType.selectedNotificationAction,
        payload: payload,
        actionId: action,
      );

  test('a notice opens only what this app sealed', () async {
    final opened = <String>[];
    final acted = <(String, String)>[];
    final buttons = NoticeButtons(
      reply: 'Reply',
      archive: 'Archive',
      snooze: 'Snooze',
      send: 'Send',
      replyHint: 'Reply',
      onAction: (payload, action, _) => acted.add((payload, action)),
    );
    const seal = _Seal();
    final sealed = await seal.seal('1\nINBOX\n42');

    await handleNoticeResponse(
      tap(sealed),
      onOpen: opened.add,
      buttons: buttons,
      seal: seal,
    );
    expect(opened, ['1\nINBOX\n42']);

    // Another app's intent: a payload of its own choosing, unsealed or
    // with a seal it made up.
    for (final forged in [
      'account\n1',
      '1\nINBOX\n7',
      '1\nINBOX\n7\n#seal:ok-1\nINBOX\n42',
    ]) {
      await handleNoticeResponse(
        tap(forged),
        onOpen: opened.add,
        buttons: buttons,
        seal: seal,
      );
      await handleNoticeResponse(
        tap(forged, action: 'archive'),
        onOpen: opened.add,
        buttons: buttons,
        seal: seal,
      );
    }
    expect(opened, ['1\nINBOX\n42']);
    expect(acted, isEmpty);

    await handleNoticeResponse(
      tap(sealed, action: 'archive'),
      onOpen: opened.add,
      buttons: buttons,
      seal: seal,
    );
    expect(acted, [('1\nINBOX\n42', 'archive')]);
  });
}
