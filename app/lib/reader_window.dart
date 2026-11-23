import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
import 'inbox/mailbox_actions.dart';
import 'inbox/reader.dart';
import 'mail/mail_source.dart';

/// "Open in new window" (⌘↵ in search): a message read in a window of its
/// own, next to the inbox. Each window runs its own Flutter engine over
/// the one Rust engine of the app, so it reads the same database.
bool get canOpenWindows =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// The inbox's side: what a reader window asks of it.
const _inbox = WindowMethodChannel(
  'mail.piuma/inbox',
  mode: ChannelMode.unidirectional,
);

/// What a reader window was opened for, passed as its argument.
@immutable
class WindowMessage {
  const WindowMessage(this.accountId, this.mailbox, this.uid);

  WindowMessage.of(MailRow row) : this(row.accountId, row.mailbox, row.uid);

  final int accountId;
  final String mailbox;
  final int uid;

  String encode() => jsonEncode({
    'read': [accountId, mailbox, uid],
  });

  /// Null for anything that isn't a message to read.
  static WindowMessage? decode(String arguments) {
    try {
      final read = (jsonDecode(arguments) as Map<String, dynamic>)['read'];
      if (read case [final int a, final String m, final int u]) {
        return WindowMessage(a, m, u);
      }
    } catch (_) {}
    return null;
  }

  Future<MailRow?> find(MailSource source) =>
      source.messageRow(accountId, mailbox, uid);

  Map<String, Object> toMap() => {'a': accountId, 'm': mailbox, 'u': uid};

  static WindowMessage? fromMap(Object? map) => switch (map) {
    {'a': final int a, 'm': final String m, 'u': final int u} => WindowMessage(
      a,
      m,
      u,
    ),
    _ => null,
  };
}

/// Opens [row] in a window of its own. The window shows itself once it
/// has drawn, so it never flashes empty.
Future<void> openReaderWindow(MailRow row) async {
  await WindowController.create(
    WindowConfiguration(arguments: WindowMessage.of(row).encode()),
  );
}

/// In the inbox's window: a reader window changed something, or wants a
/// reply written. Replies are written in the inbox, where compose lives.
/// With [windows], the app lock decides when reader windows show
/// (`show`), knows which one is in front (`front`) and which went
/// (`done`).
Future<void> listenToReaderWindows({
  required VoidCallback onChanged,
  required ValueChanged<WindowMessage> onReply,
  ReaderWindows? windows,
}) async {
  final self = await WindowController.fromCurrentEngine();
  await _inbox.setMethodCallHandler((call) async {
    final id = switch (call.arguments) {
      {'id': final String id} => id,
      _ => null,
    };
    switch (call.method) {
      case 'changed':
        onChanged();
      case 'reply':
        // Nothing comes from a window while the app is locked.
        if (windows?.isLocked() ?? false) return null;
        if (WindowMessage.fromMap(call.arguments) case final m?) {
          onReply(m);
          await self.show();
        }
      case 'show' when id != null:
        if (windows != null) return windows.mayShow(id);
        await WindowController.fromWindowId(id).show();
        return true;
      case 'front' when id != null:
        final front = switch (call.arguments) {
          {'front': true} => true,
          _ => false,
        };
        windows?.inFront(id, front);
      case 'done' when id != null:
        windows?.done(id);
    }
    return null;
  });
}

/// The reader windows as the inbox's window sees them, for the app lock:
/// a new one shows only while the app is unlocked, all of them hide the
/// moment it locks, and those that were on screen come back once it
/// opens. Which one is in front counts as the app being in use.
class ReaderWindows {
  ReaderWindows({
    required this.isLocked,
    required this.show,
    required this.hide,
    required this.all,
    this.onFront,
  });

  final bool Function() isLocked;
  final Future<void> Function(String id) show;
  final Future<void> Function(String id) hide;

  /// Every window but the inbox's, as the system has them now.
  final Future<List<String>> Function() all;
  final void Function(String id, bool front)? onFront;

  final _onScreen = <String>{};
  final _back = <String>{};

  /// A reader window has drawn and asks to show: true when it did.
  Future<bool> mayShow(String id) async {
    if (isLocked()) {
      _back.add(id);
      return false;
    }
    _onScreen.add(id);
    await show(id);
    return true;
  }

  void inFront(String id, bool front) {
    // A window that isn't shown can't be in use.
    onFront?.call(id, front && _onScreen.contains(id) && !isLocked());
  }

  /// Closed with Done, after archiving it or the like.
  void done(String id) {
    _onScreen.remove(id);
    _back.remove(id);
    onFront?.call(id, false);
  }

  /// The lock closed: every reader window hides, the ones known to be on
  /// screen first, without waiting to list the others.
  Future<void> locked() async {
    final shown = {..._onScreen};
    _back.addAll(shown);
    _onScreen.clear();
    for (final id in shown) {
      onFront?.call(id, false);
    }
    await Future.wait([for (final id in shown) _quietly(hide(id))]);
    try {
      final rest = await all();
      await Future.wait([
        for (final id in rest)
          if (!shown.contains(id)) _quietly(hide(id)),
      ]);
    } catch (_) {}
  }

  /// The lock opened: the windows it hid come back.
  Future<void> unlocked() async {
    final ids = {..._back};
    _back.clear();
    for (final id in ids) {
      if (isLocked()) {
        _back.add(id);
        continue;
      }
      _onScreen.add(id);
      await _quietly(show(id));
    }
  }

  static Future<void> _quietly(Future<void> f) async {
    try {
      await f;
    } catch (_) {
      // A window that has gone.
    }
  }
}

/// The reader window's own app: the message, full size, with what can be
/// done to it there.
class ReaderWindow extends StatelessWidget {
  const ReaderWindow({
    super.key,
    required this.source,
    required this.row,
    this.now = DateTime.now,
    this.onChanged,
    this.onReply,
    this.onDone,
  });

  final MailSource source;

  /// Null when the message is no longer on this device.
  final MailRow? row;
  final DateTime Function() now;

  /// After Archive or Delete (or Delete for good), so the inbox shows it.
  final VoidCallback? onChanged;
  final ValueChanged<MailRow>? onReply;

  /// The message left: the window goes away.
  final VoidCallback? onDone;

  Future<void> _apply(MailRow row, MessageAction action) async {
    try {
      await source.apply([row], action);
    } catch (_) {
      return;
    }
    onChanged?.call();
    onDone?.call();
  }

  /// Delete: to Trash, or, in Trash and spam, for good once confirmed,
  /// as everywhere else in the app. Cancelled, the window stays.
  Future<void> _delete(BuildContext context, MailRow row) async {
    if (!source.deletesForGood(row.accountId, row.mailbox)) {
      return _apply(row, MessageAction.delete);
    }
    if (!await confirmDeleteForever(context, count: 1)) return;
    try {
      await source.deleteForever([row]);
    } catch (_) {
      return;
    }
    onChanged?.call();
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final row = this.row;
    final archived = row?.folder == MailFolder.archive;
    final sent = row?.folder == MailFolder.sent;
    return Material(
      color: c.surface,
      child: Reader(
        source: source,
        row: row,
        now: now,
        onArchive: archived || row?.folder == MailFolder.drafts
            ? null
            : (row) => _apply(row, MessageAction.archive),
        onDelete: (row) => _delete(context, row),
        onReply: sent || onReply == null
            ? null
            : (row, _, [text = '']) => onReply!(row),
      ),
    );
  }
}

/// The reader window's side of [listenToReaderWindows].
class InboxWindow {
  const InboxWindow._();

  static Future<void> changed() async {
    try {
      await _inbox.invokeMethod<void>('changed');
    } catch (_) {
      // The inbox window has closed; nothing to tell.
    }
  }

  static Future<void> reply(MailRow row) async {
    try {
      await _inbox.invokeMethod<void>('reply', WindowMessage.of(row).toMap());
    } catch (_) {}
  }

  /// Asks the inbox's window to show this one ([ReaderWindows.mayShow]):
  /// it doesn't while the app is locked, and then shows it once unlocked.
  /// A window that can't ask stays hidden.
  static Future<void> show(String id) async {
    try {
      await _inbox.invokeMethod<bool>('show', {'id': id});
    } catch (_) {}
  }

  /// This window came in front, or left it.
  static Future<void> front(String id, bool front) async {
    try {
      await _inbox.invokeMethod<void>('front', {'id': id, 'front': front});
    } catch (_) {}
  }

  /// This window was closed with Done (hidden, as windows are kept).
  static Future<void> done(String id) async {
    try {
      await _inbox.invokeMethod<void>('done', {'id': id});
    } catch (_) {}
  }
}
