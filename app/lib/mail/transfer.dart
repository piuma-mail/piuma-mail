import 'dart:async';

import 'package:flutter/foundation.dart';

/// Mail to and from other mail apps, and settings in a file: what
/// Settings › Import and export, a folder's "Export folder…" and the
/// selection's Export do. The defaults pretend, for the demo and tests;
/// the engine's source does it for real (`engine_transfer.dart`).

/// What an export writes.
enum MailFileFormat {
  /// One `.mbox` file, as Thunderbird, Apple Mail and Gmail use.
  mbox,

  /// A ZIP holding one `.eml` file per message.
  emlZip,
}

/// Why a message, or a file, was left out.
enum TransferSkip {
  notMail,
  tooLarge,
  notDownloaded,
  gone,
  notAFile,
  unreadable,
  refused,
}

@immutable
class TransferSkipped {
  const TransferSkipped(this.item, this.kind, [this.detail = '']);

  /// A file name, `name.mbox #12`, or a message's subject.
  final String item;
  final TransferSkip kind;

  /// What the server said, for [TransferSkip.refused].
  final String detail;
}

/// How a finished import or export went.
@immutable
class TransferResult {
  const TransferResult({
    required this.export,
    this.done = 0,
    this.rebuilt = 0,
    this.duplicates = 0,
    this.skipped = const [],
    this.skippedCount = 0,
    this.cancelled = false,
    this.offline = false,
    this.error,
    this.path,
    this.busy = false,
  });

  /// An export (else an import).
  final bool export;

  /// Messages exported, or imported.
  final int done;

  /// Exported from the local copy, without attachments: the server could
  /// not be reached.
  final int rebuilt;

  /// Imported messages the folder already had.
  final int duplicates;

  /// The first ones left out; [skippedCount] counts them all.
  final List<TransferSkipped> skipped;
  final int skippedCount;
  final bool cancelled;

  /// A server could not be reached: only downloaded mail was exported.
  final bool offline;

  /// Why it stopped, or could not start.
  final String? error;

  /// Where an export was written.
  final String? path;

  /// It did not start: another import or export is running.
  final bool busy;
}

/// What a running import or export says: how far it is, then once how
/// it ended.
@immutable
class TransferUpdate {
  const TransferUpdate({this.fraction = 0, this.messages = 0, this.result});

  /// 0 to 1.
  final double fraction;

  /// Messages handled so far.
  final int messages;
  final TransferResult? result;
}

/// An account from a settings file: it fills the add-account form, and
/// the password is asked for there.
@immutable
class AccountPreset {
  const AccountPreset({
    required this.email,
    this.name = '',
    this.senderName = '',
    this.color = '',
    this.jmap = false,
    this.username = '',
    this.imapHost = '',
    this.imapPort = 993,
    this.imapStartTls = false,
    this.smtpHost = '',
    this.smtpPort = 465,
    this.smtpStartTls = false,
    this.jmapUrl = '',
    this.added = false,
  });

  final String email;
  final String name;
  final String senderName;

  /// `#RRGGBB`, or empty.
  final String color;
  final bool jmap;
  final String username;
  final String imapHost;
  final int imapPort;
  final bool imapStartTls;
  final String smtpHost;
  final int smtpPort;
  final bool smtpStartTls;
  final String jmapUrl;

  /// This device has an account with this address already.
  final bool added;
}

/// What a settings file holds.
@immutable
class SettingsFileSummary {
  const SettingsFileSummary({
    this.accounts = const [],
    this.signatures = 0,
    this.appearance = false,
  });

  final List<AccountPreset> accounts;
  final int signatures;
  final bool appearance;
}

/// What applying a settings file did.
@immutable
class SettingsApplied {
  const SettingsApplied({this.signaturesAdded = 0, this.signaturesWaiting = 0});

  final int signaturesAdded;

  /// Of accounts not added yet: applying again once they are brings them.
  final int signaturesWaiting;
}

/// Why a settings file was not read.
enum SettingsFileProblem { notSettings, newer }

class SettingsFileException implements Exception {
  const SettingsFileException(this.problem);
  final SettingsFileProblem problem;
}

/// The import and export a source offers. The defaults pretend, in
/// memory: a few steps of progress, then a summary.
mixin TransferExtras {
  bool _cancelled = false;

  /// Each step the pretend jobs take.
  @visibleForTesting
  static Duration demoStep = const Duration(milliseconds: 400);

  Stream<TransferUpdate> _pretend(TransferResult Function(bool) end) async* {
    _cancelled = false;
    const steps = 5;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(demoStep);
      if (_cancelled) {
        yield TransferUpdate(result: end(true));
        return;
      }
      yield TransferUpdate(fraction: i / steps, messages: i * 248);
    }
    yield TransferUpdate(fraction: 1, messages: 1240, result: end(false));
  }

  /// Exports a folder into [path].
  Stream<TransferUpdate> exportFolder(
    int accountId,
    String mailbox,
    MailFileFormat format,
    String path,
  ) => _pretend(
    (cancelled) => TransferResult(
      export: true,
      done: cancelled ? 0 : 1238,
      skipped: const [
        TransferSkipped('Quarterly report', TransferSkip.notDownloaded),
        TransferSkipped('Photos from Sunday', TransferSkip.notDownloaded),
      ],
      skippedCount: 2,
      rebuilt: 12,
      offline: true,
      cancelled: cancelled,
      path: path,
    ),
  );

  /// Exports chosen messages (account, folder, uid) into [path].
  Stream<TransferUpdate> exportMessages(
    List<({int accountId, String mailbox, int uid})> messages,
    MailFileFormat format,
    String path,
  ) => _pretend(
    (cancelled) => TransferResult(
      export: true,
      done: cancelled ? 0 : messages.length,
      cancelled: cancelled,
      path: path,
    ),
  );

  /// How many messages a folder export writes.
  int exportFolderSize(int accountId, String mailbox) => 1240;

  /// Imports `.eml` and `.mbox` files into a folder.
  Stream<TransferUpdate> importMail(
    int accountId,
    String mailbox,
    List<String> paths,
  ) => _pretend(
    (cancelled) => TransferResult(
      export: false,
      done: cancelled ? 0 : 1180,
      duplicates: 57,
      skipped: const [
        TransferSkipped('Takeout.mbox #214', TransferSkip.notMail),
        TransferSkipped('Takeout.mbox #988', TransferSkip.tooLarge),
        TransferSkipped('scan.eml', TransferSkip.refused, 'Message too big'),
      ],
      skippedCount: 3,
      cancelled: cancelled,
    ),
  );

  /// Stops the running import or export between two messages.
  void cancelTransfer() => _cancelled = true;

  /// An import or export is running (one started from a page since left).
  bool get transferRunning => false;

  /// Writes the settings file (no passwords) at [path].
  Future<void> exportSettings(String path) async {}

  /// What the settings file at [path] holds. Throws
  /// [SettingsFileException].
  Future<SettingsFileSummary> readSettingsFile(String path) async =>
      const SettingsFileSummary(
        accounts: [
          AccountPreset(
            email: 'matteo@studio.example',
            name: 'Studio',
            imapHost: 'imap.studio.example',
            smtpHost: 'smtp.studio.example',
            added: true,
          ),
          AccountPreset(
            email: 'matteo@fastmail.example',
            name: 'Personal',
            jmap: true,
            jmapUrl: 'https://api.fastmail.example/jmap/session',
          ),
        ],
        signatures: 2,
        appearance: true,
      );

  /// Applies the file's signatures and, with [appearance], its look.
  Future<SettingsApplied> applySettingsFile(
    String path, {
    required bool appearance,
  }) async => const SettingsApplied(signaturesAdded: 1, signaturesWaiting: 1);
}
