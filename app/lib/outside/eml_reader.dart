import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/images_bar.dart';
import '../inbox/message_body.dart';
import '../inbox/move_menu.dart';
import '../inbox/risky_file.dart';
import '../l10n/app_localizations.dart';
import '../inbox/inbox_screen.dart' show phoneWidth;
import '../mail/mail_source.dart';
import '../widgets/attachment_chip.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';
import 'arrive.dart';

/// An email file opened from outside the app (`.eml`): read only, apart
/// from the mailbox. The engine read it with the same parser as synced
/// mail; its remote images wait for "Load images" (never "always for this
/// sender": a file can claim any sender), its links ask before they open,
/// and "Import to a folder" puts it in an account's folder on the server.
class EmlReader extends StatefulWidget {
  const EmlReader({
    super.key,
    required this.source,
    required this.message,
    required this.onClose,
  });

  final MailSource source;
  final EmlMessage message;
  final VoidCallback onClose;

  @override
  State<EmlReader> createState() => _EmlReaderState();
}

class _EmlReaderState extends State<EmlReader> {
  bool _showRemote = false;
  final _saving = <int>{};

  EmlMessage get _m => widget.message;

  /// The file as a row, for what asks about a file's sender.
  MailRow get _row => MailRow(
    accountId: -1,
    mailbox: '',
    uid: 0,
    fromName: _m.fromName,
    fromEmail: _m.fromEmail,
    subject: _m.subject,
    preview: '',
    receivedAt: _m.date ?? DateTime.fromMillisecondsSinceEpoch(0),
    seen: true,
  );

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          width: MediaQuery.sizeOf(context).width < phoneWidth ? null : 360,
        ),
      );
  }

  Future<void> _open(MailAttachment a) async {
    final l = AppLocalizations.of(context);
    setState(() => _saving.add(a.part));
    try {
      final path = await widget.source.saveEmlAttachment(_m, a);
      _toast(l.attachmentSaved(a.name));
      if (!mounted ||
          !await mayOpenFile(context, widget.source, _row, a, path)) {
        return;
      }
      await openLocalFile(path);
    } catch (_) {
      _toast(l.attachmentNotSaved(a.name));
    } finally {
      if (mounted) setState(() => _saving.remove(a.part));
    }
  }

  /// "Import to a folder": the account (asked when there are several),
  /// then one of its folders.
  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    final account = await pickAccount(
      context,
      widget.source.accounts,
      title: l.emlImportWhichAccount,
    );
    if (account == null || !mounted) return;
    final own = await widget.source.folders(account.id);
    if (!mounted) return;
    final menu = MoveMenu(
      account: account,
      targets: [
        AccountFolder(mailbox: 'INBOX', name: l.inbox),
        ...own,
      ],
      hint: l.emlImportIn(account.name),
      phone: phone,
    );
    final folder = phone
        ? await showPiumaSheet<AccountFolder>(
            context,
            label: l.emlImport,
            builder: (_) => menu,
          )
        : await showPiumaDialog<AccountFolder>(
            context,
            label: l.emlImport,
            width: 340,
            builder: (_) => menu,
          );
    if (folder == null || !mounted) return;
    try {
      await widget.source.importEml(_m, account.id, folder.mailbox);
      _toast(l.emlImported(folder.name));
    } catch (_) {
      _toast(l.emlNotImported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    final r = _m.readable;
    final locale = Localizations.localeOf(context).toString();
    final sender = _m.fromName.isNotEmpty ? _m.fromName : _m.fromEmail;
    final pad = phone ? PiumaSpace.s16 : PiumaSpace.s32;
    final details = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 13,
      height: 1.4,
      color: c.muted,
    );
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad - 8, 8, pad, 0),
              child: Row(
                children: [
                  PiumaPressable(
                    onTap: widget.onClose,
                    semanticLabel: l.back,
                    child: SizedBox(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PiumaIconView(
                              PiumaIcon.chevronLeft,
                              size: 22,
                              color: c.accentText,
                            ),
                            const SizedBox(width: 2),
                            ExcludeSemantics(
                              child: Text(
                                l.inbox,
                                style: TextStyle(
                                  fontFamily: PiumaFonts.sans,
                                  fontSize: 16,
                                  color: c.accentText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (widget.source.accounts.isNotEmpty)
                    PiumaButton(
                      label: l.emlImport,
                      kind: PiumaButtonKind.secondary,
                      size: phone
                          ? PiumaButtonSize.touch
                          : PiumaButtonSize.compact,
                      onPressed: _import,
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, PiumaSpace.s16, pad, pad),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Where it came from, before anything it says.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.bg,
                            borderRadius: BorderRadius.circular(
                              PiumaRadius.pill,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PiumaIconView(
                                PiumaIcon.file,
                                size: 14,
                                color: c.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(l.emlFromFile, style: details),
                            ],
                          ),
                        ),
                        const SizedBox(height: PiumaSpace.s12),
                        SelectableText(
                          _m.subject.isEmpty ? l.noSubject : _m.subject,
                          style: PiumaType.title.copyWith(color: c.fg),
                        ),
                        const SizedBox(height: PiumaSpace.s12),
                        Text(
                          _m.fromName.isNotEmpty
                              ? '${_m.fromName} <${_m.fromEmail}>'
                              : _m.fromEmail,
                          style: PiumaType.body.copyWith(
                            color: c.fg,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_m.to.isNotEmpty)
                          Text('${l.to}: ${_m.to.join(', ')}', style: details),
                        if (_m.cc.isNotEmpty)
                          Text('${l.cc}: ${_m.cc.join(', ')}', style: details),
                        if (_m.date case final d?)
                          Text(
                            DateFormat.yMMMMd(locale).add_jm().format(d),
                            style: details,
                          ),
                        const SizedBox(height: PiumaSpace.s20),
                        if (r.remoteImages > 0 && !_showRemote) ...[
                          ImagesBar(
                            count: r.remoteImages,
                            sender: sender,
                            phone: phone,
                            onLoad: () => setState(() => _showRemote = true),
                          ),
                          const SizedBox(height: PiumaSpace.s20),
                        ],
                        // Every link of a file asks before it opens.
                        LinksAskFirst(
                          ask: true,
                          child: MessageBody(
                            readable: r,
                            images: RemoteImages(widget.source),
                            showRemote: _showRemote,
                          ),
                        ),
                        if (r.attachments.isNotEmpty) ...[
                          const SizedBox(height: PiumaSpace.s24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final a in r.attachments)
                                AttachmentChip(
                                  name: a.name,
                                  mime: a.mime,
                                  busy: _saving.contains(a.part),
                                  semanticLabel: l.attachmentLabel(
                                    a.name,
                                    fileSize(a.size, locale: locale),
                                  ),
                                  risk: riskNote(l, a),
                                  onTap: () => _open(a),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
