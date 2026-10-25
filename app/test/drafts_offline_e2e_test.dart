// End to end: a draft saved with the server out of reach waits on the
// device and reaches the Drafts folder once the server is back.
//
//   tools/test-imap-server.sh &
//   cargo build -p piuma_bridge
//   PIUMA_TEST_IMAP=127.0.0.1:31143 PIUMA_TEST_MEMORY_KEYCHAIN=1 \
//     flutter test test/drafts_offline_e2e_test.dart
//
// Skipped unless PIUMA_TEST_IMAP is set.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/engine/api/engine.dart' as engine;
import 'package:piuma_mail/engine/frb_generated.dart';
import 'package:piuma_mail/mail/engine_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';

final _server = Platform.environment['PIUMA_TEST_IMAP'];

(String, int) _hostPort() {
  final parts = _server!.split(':');
  return (parts[0], int.parse(parts[1]));
}

/// Stands between the engine and the server, and can drop out like a
/// lost network.
class _Link {
  _Link(this.port);

  final int port;
  ServerSocket? _listening;
  final _open = <Socket>[];

  Future<void> up() async {
    final (host, serverPort) = _hostPort();
    final listening = await ServerSocket.bind('127.0.0.1', port);
    _listening = listening;
    listening.listen((client) async {
      final Socket server;
      try {
        server = await Socket.connect(host, serverPort);
      } catch (_) {
        client.destroy();
        return;
      }
      _open.addAll([client, server]);
      client.listen(server.add, onDone: server.destroy, onError: (_) {});
      server.listen(client.add, onDone: client.destroy, onError: (_) {});
    });
  }

  Future<void> down() async {
    await _listening?.close();
    _listening = null;
    for (final s in _open) {
      s.destroy();
    }
    _open.clear();
  }
}

/// The subjects in a folder on the server; none when it isn't there yet.
Future<List<String>> subjectsIn(String user, String folder) async {
  final (host, port) = _hostPort();
  final socket = await Socket.connect(host, port);
  final lines = socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  await lines.firstWhere((l) => l.startsWith('* OK'));
  socket.write('a LOGIN $user test\r\n');
  await lines.firstWhere((l) => l.startsWith('a '));
  socket.write('b SELECT $folder\r\n');
  final subjects = <String>[];
  if ((await lines.firstWhere((l) => l.startsWith('b '))).startsWith('b OK')) {
    socket.write('c FETCH 1:* (BODY.PEEK[HEADER.FIELDS (SUBJECT)])\r\n');
    await for (final l in lines) {
      if (l.startsWith('Subject: ')) subjects.add(l.substring(9));
      if (l.startsWith('c ')) break;
    }
  }
  socket.write('d LOGOUT\r\n');
  await socket.close();
  return subjects;
}

void main() {
  test('a draft saved offline goes up when the server is back', () async {
    final root = Directory.current.parent.path;
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '$root/target/debug/libpiuma_bridge.so',
      ),
    );
    final dir = await Directory.systemTemp.createTemp('piuma-e2e');
    addTearDown(() => dir.delete(recursive: true));
    engine.openEngine(dbPath: '${dir.path}/piuma.db');

    final free = await ServerSocket.bind('127.0.0.1', 0);
    final link = _Link(free.port);
    await free.close();
    await link.up();
    addTearDown(link.down);

    final user = 'drafts-${DateTime.now().millisecondsSinceEpoch}';
    final source = EngineMailSource();
    addTearDown(source.dispose);
    final account = await source.addImapAccount(
      name: 'Test',
      email: '$user@example.org',
      color: const Color(0xFF2F8F83),
      host: '127.0.0.1',
      port: link.port,
      security: ServerSecurity.none,
      username: user,
      password: 'test',
    );

    // Saved once while online, then edited with the server gone.
    final online = await source.saveDraft(
      Draft(accountId: account.id, subject: 'Plan v1'),
    );
    expect(online.mailbox, isNotEmpty);
    expect(await subjectsIn(user, 'Drafts'), ['Plan v1']);

    await link.down();
    final first = await source.saveDraft(
      Draft(accountId: account.id, subject: 'Plan v2', copy: online),
    );
    expect(first.mailbox, isEmpty);
    final again = await source.saveDraft(
      Draft(accountId: account.id, subject: 'Plan v3', copy: first),
    );
    expect(again.uid, first.uid, reason: 'one draft waits, kept up to date');
    // Written and thrown away offline: nothing of it reaches the server.
    final dropped = await source.saveDraft(
      Draft(accountId: account.id, subject: 'Scrap'),
    );
    await source.discardDraft(dropped);
    expect(await subjectsIn(user, 'Drafts'), ['Plan v1']);

    await link.up();
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!_same(await subjectsIn(user, 'Drafts'), ['Plan v3'])) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Drafts holds ${await subjectsIn(user, 'Drafts')}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }, skip: _server == null ? 'set PIUMA_TEST_IMAP to run' : false);
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
