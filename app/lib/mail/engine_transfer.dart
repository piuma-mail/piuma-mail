import '../engine/api/engine.dart' as engine;
import '../engine/api/transfer.dart' as t;
import 'mail_source.dart';

/// [TransferExtras] done by the engine (`app/rust/src/api/transfer.rs`).
mixin EngineTransfer on MailSource {
  static t.MailExportFormat _format(MailFileFormat f) => switch (f) {
    MailFileFormat.mbox => t.MailExportFormat.mbox,
    MailFileFormat.emlZip => t.MailExportFormat.emlZip,
  };

  static TransferSkip _skip(t.SkipKind k) => switch (k) {
    t.SkipKind.notMail => TransferSkip.notMail,
    t.SkipKind.tooLarge => TransferSkip.tooLarge,
    t.SkipKind.notDownloaded => TransferSkip.notDownloaded,
    t.SkipKind.gone => TransferSkip.gone,
    t.SkipKind.notAFile => TransferSkip.notAFile,
    t.SkipKind.unreadable => TransferSkip.unreadable,
    t.SkipKind.refused => TransferSkip.refused,
  };

  static List<TransferSkipped> _skipped(List<t.SkippedItem> items) => [
    for (final s in items) TransferSkipped(s.item, _skip(s.kind), s.detail),
  ];

  static TransferUpdate _update(t.TransferEvent e) {
    final exported = e.exported;
    final imported = e.imported;
    final failed = e.failed;
    return TransferUpdate(
      fraction: e.fraction,
      messages: e.messages,
      result: exported != null
          ? TransferResult(
              export: true,
              done: exported.exported,
              rebuilt: exported.rebuilt,
              skipped: _skipped(exported.skipped),
              skippedCount: exported.skippedCount,
              cancelled: exported.cancelled,
              offline: exported.offline,
              path: exported.path,
            )
          : imported != null
          ? TransferResult(
              export: false,
              done: imported.imported,
              duplicates: imported.duplicates,
              skipped: _skipped(imported.skipped),
              skippedCount: imported.skippedCount,
              cancelled: imported.cancelled,
              error: imported.error,
            )
          : failed != null
          ? TransferResult(export: false, error: failed)
          : null,
    );
  }

  /// The engine's stream, ending with the summary; an error that stops it
  /// from starting becomes a summary that says so.
  static Stream<TransferUpdate> _run(
    bool export,
    Stream<t.TransferEvent> Function() start,
  ) async* {
    if (t.transferRunning()) {
      yield TransferUpdate(result: TransferResult(export: export, busy: true));
      return;
    }
    Stream<t.TransferEvent> events;
    try {
      events = start();
    } catch (e) {
      yield TransferUpdate(
        result: TransferResult(export: export, error: '$e'),
      );
      return;
    }
    try {
      await for (final e in events) {
        final u = _update(e);
        final r = u.result;
        yield r != null && r.error != null && r.export != export
            ? TransferUpdate(
                result: TransferResult(export: export, error: r.error),
              )
            : u;
        if (r != null) return;
      }
    } catch (e) {
      yield TransferUpdate(
        result: TransferResult(export: export, error: '$e'),
      );
    }
  }

  @override
  Stream<TransferUpdate> exportFolder(
    int accountId,
    String mailbox,
    MailFileFormat format,
    String path,
  ) => _run(
    true,
    () => t.exportFolder(
      accountId: accountId,
      mailbox: mailbox,
      format: _format(format),
      path: path,
    ),
  );

  @override
  Stream<TransferUpdate> exportMessages(
    List<({int accountId, String mailbox, int uid})> messages,
    MailFileFormat format,
    String path,
  ) => _run(
    true,
    () => t.exportMessages(
      messages: [
        for (final m in messages)
          engine.MessageRef(
            accountId: m.accountId,
            mailbox: m.mailbox,
            uid: m.uid,
          ),
      ],
      format: _format(format),
      path: path,
    ),
  );

  @override
  int exportFolderSize(int accountId, String mailbox) {
    try {
      return t.exportFolderSize(accountId: accountId, mailbox: mailbox);
    } catch (_) {
      return 0;
    }
  }

  @override
  Stream<TransferUpdate> importMail(
    int accountId,
    String mailbox,
    List<String> paths,
  ) => _run(
    false,
    () => t.importMail(accountId: accountId, mailbox: mailbox, paths: paths),
  );

  @override
  void cancelTransfer() => t.cancelTransfer();

  @override
  bool get transferRunning => t.transferRunning();

  @override
  Future<void> exportSettings(String path) => t.exportSettings(path: path);

  @override
  Future<SettingsFileSummary> readSettingsFile(String path) async {
    final t.SettingsFileInfo info;
    try {
      info = await t.readSettingsFile(path: path);
    } on engine.EngineError catch (e) {
      throw SettingsFileException(
        e.kind == engine.ErrorKind.outdated
            ? SettingsFileProblem.newer
            : SettingsFileProblem.notSettings,
      );
    }
    return SettingsFileSummary(
      accounts: [
        for (final a in info.accounts)
          AccountPreset(
            email: a.email,
            name: a.name,
            senderName: a.senderName,
            color: a.color,
            jmap: a.jmap,
            username: a.username,
            imapHost: a.imapHost,
            imapPort: a.imapPort,
            imapStartTls: a.imapStarttls,
            smtpHost: a.smtpHost,
            smtpPort: a.smtpPort,
            smtpStartTls: a.smtpStarttls,
            jmapUrl: a.jmapUrl,
            added: a.added,
          ),
      ],
      signatures: info.signatures,
      appearance: info.appearance,
    );
  }

  @override
  Future<SettingsApplied> applySettingsFile(
    String path, {
    required bool appearance,
  }) async {
    final a = await t.applySettingsFile(path: path, appearance: appearance);
    return SettingsApplied(
      signaturesAdded: a.signaturesAdded,
      signaturesWaiting: a.signaturesWaiting,
    );
  }
}
