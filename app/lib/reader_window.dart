import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design/theme.dart';
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
Future<void> listenToReaderWindows({
  required VoidCallback onChanged,
  required ValueChanged<WindowMessage> onReply,
}) async {
  final self = await WindowController.fromCurrentEngine();
  await _inbox.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'changed':
        onChanged();
      case 'reply':
        if (WindowMessage.fromMap(call.arguments) case final m?) {
          onReply(m);
          await self.show();
        }
    }
    return null;
  });
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

  /// After Archive or Delete, so the inbox shows it.
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
        onDelete: (row) => _apply(row, MessageAction.delete),
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
}
