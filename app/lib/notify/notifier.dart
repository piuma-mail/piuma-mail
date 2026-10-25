import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../dev_copy.dart';

/// One notification as the system shows it.
class SystemNotice {
  const SystemNotice({
    required this.id,
    required this.title,
    required this.subject,
    required this.preview,
    required this.payload,
    this.silent = false,
    this.buttons = false,
  });

  /// The same id replaces the notice already shown, so one sender keeps
  /// one notification.
  final int id;
  final String title;
  final String subject;
  final String preview;

  /// Given back when the notice is clicked.
  final String payload;

  /// Shown without a sound (quiet hours).
  final bool silent;

  /// Reply, Archive and Snooze, as on `Notifications`: for one email.
  final bool buttons;
}

/// The words on a notice's buttons, and what to do when one is pressed:
/// [onAction] gets the notice's payload, the button ("reply", "archive"
/// or "snooze") and, for Reply, the text typed into the notice, when the
/// system has a field for it.
class NoticeButtons {
  const NoticeButtons({
    required this.reply,
    required this.archive,
    required this.snooze,
    required this.send,
    required this.replyHint,
    required this.onAction,
  });

  final String reply;
  final String archive;
  final String snooze;
  final String send;
  final String replyHint;
  final void Function(String payload, String action, String? text) onAction;
}

/// The buttons, as the system hands them back.
const noticeActions = ['reply', 'archive', 'snooze'];

/// Splits a system response into payload, button and typed text. Windows
/// hands back the button's own arguments in place of the payload, so
/// those carry the payload after a tab.
({String payload, String? action, String? text})? readNoticeResponse(
  NotificationResponse r,
) {
  var payload = r.payload;
  var action = r.actionId;
  if (action != null && action.contains('\t')) {
    final at = action.indexOf('\t');
    payload = action.substring(at + 1);
    action = action.substring(0, at);
  }
  if (payload == null) return null;
  if (!noticeActions.contains(action)) action = null;
  final typed = r.input ?? r.data['reply'];
  final text = typed is String && typed.trim().isNotEmpty ? typed.trim() : null;
  return (payload: payload, action: action, text: text);
}

/// Shows notices through the operating system. Tests replace [notifier].
abstract class Notifier {
  /// [onOpen] gets the payload of a clicked notice. [openLabel] names the
  /// click and [channelLabel] the kind of notice, where the system shows
  /// them.
  Future<void> init(
    void Function(String payload) onOpen, {
    required String openLabel,
    required String channelLabel,
    NoticeButtons? buttons,
  });
  Future<void> show(SystemNotice notice);
}

Notifier notifier = SystemNotifier();

/// Asks Android 13 and later to allow notices; elsewhere nothing to ask.
/// Tests replace it.
Future<void> Function() askNoticePermission = () async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  } catch (_) {
    // Asked another time from Android's own settings.
  }
};

/// The app's icon, installed next to the program (`windows/CMakeLists.txt`).
String? _windowsIcon() {
  if (kIsWeb || !Platform.isWindows) return null;
  final dir = File(Platform.resolvedExecutable).parent.path;
  final icon = File('$dir\\data\\app_icon.ico');
  return icon.existsSync() ? icon.path : null;
}

class SystemNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _channel = '';
  NoticeButtons? _buttons;

  @override
  Future<void> init(
    void Function(String payload) onOpen, {
    required String openLabel,
    required String channelLabel,
    NoticeButtons? buttons,
  }) async {
    _channel = channelLabel;
    _buttons = buttons;
    if (kIsWeb || _ready) return;
    void respond(NotificationResponse r) {
      final read = readNoticeResponse(r);
      if (read == null) return;
      final action = read.action;
      if (action != null && buttons != null) {
        buttons.onAction(read.payload, action, read.text);
      } else {
        onOpen(read.payload);
      }
    }

    final darwin = DarwinInitializationSettings(
      notificationCategories: [
        if (buttons != null)
          DarwinNotificationCategory(
            'mail',
            actions: [
              DarwinNotificationAction.text(
                'reply',
                buttons.reply,
                buttonTitle: buttons.send,
                placeholder: buttons.replyHint,
              ),
              DarwinNotificationAction.plain('archive', buttons.archive),
              DarwinNotificationAction.plain('snooze', buttons.snooze),
            ],
          ),
      ],
    );
    try {
      _ready =
          await _plugin.initialize(
            settings: InitializationSettings(
              macOS: darwin,
              iOS: darwin,
              android: const AndroidInitializationSettings(
                '@drawable/ic_notification',
              ),
              linux: LinuxInitializationSettings(defaultActionName: openLabel),
              windows: WindowsInitializationSettings(
                // A dev copy's notices are its own (`dev_copy.dart`), as
                // is the Start menu shortcut the runner makes for them.
                appName: devCopy ? 'Piuma Mail (dev)' : 'Piuma Mail',
                appUserModelId: devCopy
                    ? 'Piuma.PiumaMail.Dev'
                    : 'Piuma.PiumaMail',
                guid: devCopy
                    ? 'c4e9a7b2-3d61-4f0e-8b5a-9e2d7f1c6a83'
                    : '6a3f0d6e-5b8f-4c55-9a3e-2f1b7c9d4e21',
                iconPath: _windowsIcon(),
              ),
            ),
            onDidReceiveNotificationResponse: respond,
          ) ??
          false;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        respond(response);
      }
    } catch (_) {
      // No notification service (a bare Linux session, say): mail still
      // arrives, just without notices.
      _ready = false;
    }
  }

  @override
  Future<void> show(SystemNotice n) async {
    if (!_ready) return;
    // Where there is no subtitle line, the subject leads the body. Windows
    // puts its extra line under the body, so there the subject is the body
    // and the preview goes under it.
    final apple = Platform.isMacOS || Platform.isIOS;
    final windows = Platform.isWindows && n.subject.isNotEmpty;
    final body = apple || n.subject.isEmpty
        ? n.preview
        : windows
        ? n.subject
        : [n.subject, if (n.preview.isNotEmpty) n.preview].join('\n');
    final buttons = n.buttons ? _buttons : null;
    try {
      await _plugin.show(
        id: n.id,
        title: n.title,
        body: body,
        payload: n.payload,
        notificationDetails: NotificationDetails(
          macOS: DarwinNotificationDetails(
            subtitle: n.subject,
            presentSound: !n.silent,
            threadIdentifier: 'mail',
            categoryIdentifier: buttons == null ? null : 'mail',
          ),
          iOS: DarwinNotificationDetails(
            subtitle: n.subject,
            presentSound: !n.silent,
            threadIdentifier: 'mail',
            categoryIdentifier: buttons == null ? null : 'mail',
          ),
          android: AndroidNotificationDetails(
            'mail',
            _channel,
            silent: n.silent,
            category: AndroidNotificationCategory.email,
          ),
          linux: LinuxNotificationDetails(
            suppressSound: n.silent,
            category: LinuxNotificationCategory.emailArrived,
            // No field here: Reply opens the reply in the app.
            actions: [
              if (buttons != null) ...[
                LinuxNotificationAction(key: 'reply', label: buttons.reply),
                LinuxNotificationAction(key: 'archive', label: buttons.archive),
                LinuxNotificationAction(key: 'snooze', label: buttons.snooze),
              ],
            ],
          ),
          windows: WindowsNotificationDetails(
            subtitle: windows && n.preview.isNotEmpty ? n.preview : null,
            audio: n.silent ? WindowsNotificationAudio.silent() : null,
            inputs: [
              if (buttons != null)
                WindowsTextInput(
                  id: 'reply',
                  placeHolderContent: buttons.replyHint,
                ),
            ],
            actions: [
              if (buttons != null) ...[
                WindowsAction(
                  content: buttons.send,
                  arguments: 'reply\t${n.payload}',
                  inputId: 'reply',
                ),
                WindowsAction(
                  content: buttons.archive,
                  arguments: 'archive\t${n.payload}',
                ),
                WindowsAction(
                  content: buttons.snooze,
                  arguments: 'snooze\t${n.payload}',
                ),
              ],
            ],
          ),
        ),
      );
    } catch (_) {
      // A notice that cannot be shown is not worth an error.
    }
  }
}
