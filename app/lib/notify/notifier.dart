import 'dart:async' show unawaited;
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../dev_copy.dart';
import '../lock/app_lock.dart';
import 'notice_seal.dart';
import 'unread_badge.dart';

export 'notice_seal.dart' show NoticeSeal, noticeSeal;

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

  /// Reply, Archive and Snooze, as on `Notifications`, then Delete and
  /// Mark read: for one email.
  final bool buttons;
}

/// The words on a notice's buttons, and what to do when one is pressed:
/// [onAction] gets the notice's payload, the button ("reply", "archive",
/// "snooze", "delete" or "read") and, for Reply, the text typed into the
/// notice, when the system has a field for it.
class NoticeButtons {
  const NoticeButtons({
    required this.reply,
    required this.archive,
    required this.snooze,
    required this.delete,
    required this.markRead,
    required this.send,
    required this.replyHint,
    required this.onAction,
  });

  final String reply;
  final String archive;
  final String snooze;
  final String delete;
  final String markRead;
  final String send;
  final String replyHint;
  final void Function(String payload, String action, String? text) onAction;
}

/// The buttons, as the system hands them back.
const noticeActions = ['reply', 'archive', 'snooze', 'delete', 'read'];

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

/// Acts on a clicked notice or one of its buttons, once its payload's
/// seal checks ([NoticeSeal]): a payload made up by another app opens
/// nothing. While the app is locked ([locked], [AppLock.lockedNow]) a
/// button does nothing to the mail: the notice opens the app instead, at
/// its lock screen. A notice shown before the lock was turned on can
/// still have buttons.
Future<void> handleNoticeResponse(
  NotificationResponse r, {
  required void Function(String payload) onOpen,
  NoticeButtons? buttons,
  NoticeSeal? seal,
  bool Function()? locked,
}) async {
  final read = readNoticeResponse(r);
  if (read == null) return;
  final payload = await (seal ?? noticeSeal).open(read.payload);
  if (payload == null) return;
  final action = read.action;
  final isLocked = (locked ?? () => AppLock.lockedNow)();
  if (action != null && buttons != null && !isLocked) {
    buttons.onAction(payload, action, read.text);
  } else {
    onOpen(payload);
  }
}

/// While the app lock is on, what every notice says instead of its sender,
/// subject and preview ("New message"), and it has no buttons: nothing of
/// the mail shows on the screen, the lock screen or a paired watch, and
/// nothing is done to it without unlocking. Null while the lock is off.
/// Android's background service does the same from `app-lock.json`.
String? lockedNoticeTitle;

/// [n] as the system may show it now ([lockedNoticeTitle]).
SystemNotice privateNotice(SystemNotice n) {
  final title = lockedNoticeTitle;
  if (title == null) return n;
  return SystemNotice(
    id: n.id,
    title: title,
    subject: '',
    preview: '',
    payload: n.payload,
    silent: n.silent,
  );
}

/// Seals [notice]'s payload, then decides what it may show
/// ([privateNotice]) and hands it to [post] at once. The decision comes
/// after the wait for the seal, never before it: the lock turned on
/// meanwhile, and its blanking already done, the notice goes out blank
/// rather than with its sender and subject.
Future<void> postNotice(
  SystemNotice notice, {
  required NoticeSeal seal,
  required Future<void> Function(SystemNotice n, String sealed) post,
}) async {
  final sealed = await seal.seal(notice.payload);
  // Nothing may wait between this and [post].
  return post(privateNotice(notice), sealed);
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

  /// The lock was turned on or closed: the notices already shown, which
  /// may name a sender and have buttons, go. On Android they fold into one
  /// "New messages" instead (`LockPlatform.engaged`, `LockedNotices.kt`).
  Future<void> hideShown();
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

  /// The ids shown by this run, for [hideShown].
  final _shown = <int>{};
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
    void respond(NotificationResponse r) =>
        unawaited(handleNoticeResponse(r, onOpen: onOpen, buttons: buttons));

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
              DarwinNotificationAction.plain('read', buttons.markRead),
              DarwinNotificationAction.plain(
                'delete',
                buttons.delete,
                options: {DarwinNotificationActionOption.destructive},
              ),
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
  Future<void> hideShown() async {
    // Android blanks its notices natively, the plugin's among them.
    if (!_ready || Platform.isAndroid) return;
    final ids = {..._shown};
    _shown.clear();
    try {
      // Also what an earlier run left in the notification centre, where
      // the system can list it.
      for (final a in await _plugin.getActiveNotifications()) {
        if (a.id case final id?) ids.add(id);
      }
    } catch (_) {
      // Not listed here: this run's own go.
    }
    for (final id in ids) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  @override
  Future<void> show(SystemNotice notice) async {
    if (!_ready) return;
    await postNotice(notice, seal: noticeSeal, post: _post);
  }

  /// Hands [n] to the system; nothing here waits before it goes.
  Future<void> _post(SystemNotice n, String sealed) async {
    _shown.add(n.id);
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
        payload: sealed,
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
            // Launchers that show a count on the icon read it here.
            number: UnreadBadge.count > 0 ? UnreadBadge.count : null,
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
                LinuxNotificationAction(key: 'read', label: buttons.markRead),
                LinuxNotificationAction(key: 'delete', label: buttons.delete),
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
                // Windows shows five buttons at most: Send, Archive, Snooze,
                // Mark read and Delete.
                WindowsAction(
                  content: buttons.markRead,
                  arguments: 'read\t${n.payload}',
                ),
                WindowsAction(
                  content: buttons.delete,
                  arguments: 'delete\t${n.payload}',
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
