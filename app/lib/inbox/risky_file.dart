import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';

/// The document a disguised program pretends to be: "PDF" for
/// "invoice.pdf.exe".
String _posesAs(String name) {
  final parts = name.trim().split('.');
  return parts.length >= 3 ? parts[parts.length - 2].trim().toUpperCase() : '';
}

/// What a risky file's chip says under its name (`ProtectionToApprove`
/// section 3), or null for a file that opens as any other.
String? riskNote(AppLocalizations l, MailAttachment a) => switch (a.risk) {
  null => null,
  FileRisk.program => l.riskProgram,
  FileRisk.disguised => l.riskDisguised(_posesAs(a.name)),
  FileRisk.macros => l.riskMacros,
  FileRisk.locked => l.riskLocked,
};

/// Whether the file saved at [path] may open: a program, a file with
/// macros or a locked archive asks first, with "Don't open" as the main
/// button, as Check this link does. A dialog on the desktop, a sheet on
/// the phone.
Future<bool> mayOpenFile(
  BuildContext context,
  MailSource source,
  MailRow row,
  MailAttachment a,
  String path,
) async {
  var risk = a.risk;
  if (risk == null && _archive(a)) {
    if (await source.lockedArchive(path)) risk = FileRisk.locked;
  }
  if (risk == null) return true;
  if (!context.mounted) return false;
  final l = AppLocalizations.of(context);
  final title = switch (risk) {
    FileRisk.program || FileRisk.disguised => l.riskOpenProgram,
    FileRisk.macros => l.riskOpenFile,
    FileRisk.locked => l.riskOpenArchive,
  };
  final phone = MediaQuery.sizeOf(context).width < 600;
  Widget panel(BuildContext context) => _RiskyFile(
    file: a,
    from: row.fromEmail,
    risk: risk!,
    title: title,
    phone: phone,
  );
  final open = phone
      ? await showPiumaSheet<bool>(context, label: title, builder: panel)
      : await showPiumaDialog<bool>(context, label: title, builder: panel);
  return open == true;
}

bool _archive(MailAttachment a) =>
    a.mime == 'application/zip' || a.name.toLowerCase().endsWith('.zip');

class _RiskyFile extends StatelessWidget {
  const _RiskyFile({
    required this.file,
    required this.from,
    required this.risk,
    required this.title,
    required this.phone,
  });

  final MailAttachment file;
  final String from;
  final FileRisk risk;
  final String title;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final body = switch (risk) {
      FileRisk.program => l.riskBodyProgram(file.name),
      FileRisk.disguised => l.riskBodyDisguised(file.name, _posesAs(file.name)),
      FileRisk.macros => l.riskBodyMacros(file.name),
      FileRisk.locked => l.riskBodyLocked(file.name),
    };
    final open = PiumaButton(
      label: l.openAnyway,
      kind: PiumaButtonKind.tertiary,
      onPressed: () => Navigator.of(context).pop(true),
    );
    final keep = PiumaButton(
      label: l.dontOpen,
      onPressed: () => Navigator.of(context).pop(false),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.warnSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: PiumaIconView(PiumaIcon.warning, size: 18, color: c.warn),
            ),
            const SizedBox(width: PiumaSpace.s12),
            Expanded(
              child: Text(
                title,
                style: PiumaType.subtitle.copyWith(color: c.fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s16),
        Text(body, style: PiumaType.body.copyWith(color: c.fg)),
        if (!phone) ...[
          const SizedBox(height: PiumaSpace.s12),
          Text(
            l.riskFileFrom(
              file.name,
              fileSize(
                file.size,
                locale: Localizations.localeOf(context).toLanguageTag(),
              ),
              from,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PiumaType.small.copyWith(color: c.muted),
          ),
        ],
        const SizedBox(height: PiumaSpace.s24),
        if (phone) ...[
          keep,
          const SizedBox(height: PiumaSpace.s8),
          open,
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              open,
              const SizedBox(width: PiumaSpace.s8),
              keep,
            ],
          ),
      ],
    );
  }
}
