import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../inbox/inbox_screen.dart' show phoneWidth;
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';
import 'arrivals.dart';

/// Asks which account to use when there are several: a link or a share
/// never picks one by itself. The only one when there is one; null when
/// there is none or the person closes the question.
Future<MailAccount?> pickAccount(
  BuildContext context,
  List<MailAccount> accounts, {
  required String title,
}) async {
  if (accounts.isEmpty) return null;
  if (accounts.length == 1) return accounts.first;
  final phone = MediaQuery.sizeOf(context).width < phoneWidth;
  Widget list(BuildContext context) =>
      _AccountList(title: title, accounts: accounts, phone: phone);
  return phone
      ? showPiumaSheet<MailAccount>(context, label: title, builder: list)
      : showPiumaDialog<MailAccount>(
          context,
          label: title,
          width: 360,
          builder: list,
        );
}

class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.title,
    required this.accounts,
    required this.phone,
  });

  final String title;
  final List<MailAccount> accounts;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final pad = phone ? 20.0 : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, PiumaSpace.s12),
          child: Text(title, style: PiumaType.subtitle.copyWith(color: c.fg)),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(horizontal: pad),
            children: [
              for (final a in accounts)
                PiumaPressable(
                  onTap: () => Navigator.of(context).pop(a),
                  semanticLabel: '${a.name}, ${a.email}',
                  child: SizedBox(
                    height: phone ? 56 : 48,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: PiumaSpace.s12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PiumaType.body.copyWith(color: c.fg),
                              ),
                              Text(
                                a.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PiumaType.small.copyWith(color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The message an arrival asks for, from [account]: what its link fills
/// in, and its files read in, up to what a message can carry. Also says
/// how many files were left out.
Future<(Draft, int)> draftFor(
  ComposeArrival arrival,
  MailAccount account, {
  Future<int> Function(String path)? sizeOf,
  Future<List<int>> Function(String path)? read,
}) async {
  final size = sizeOf ?? (p) => File(p).length();
  final bytes = read ?? (p) => File(p).readAsBytes();
  final files = <DraftFile>[];
  var left = arrival.tooLarge;
  var total = 0;
  for (final f in arrival.files) {
    try {
      final n = await size(f.path);
      if (n > maxDraftFilesSize - total) {
        left++;
        continue;
      }
      final data = await bytes(f.path);
      // The file can grow between the two looks.
      if (data.length > maxDraftFilesSize - total) {
        left++;
        continue;
      }
      total += data.length;
      files.add(DraftFile(safeFileName(f.name), Uint8List.fromList(data)));
    } catch (_) {
      left++;
    }
  }
  final l = arrival.link;
  return (
    Draft(
      accountId: account.id,
      to: l.to,
      cc: l.cc,
      bcc: l.bcc,
      subject: l.subject,
      body: l.body,
      inReplyTo: l.inReplyTo,
      references: [?l.inReplyTo],
      files: files,
    ),
    left,
  );
}
