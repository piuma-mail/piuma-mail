import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../inbox/inbox_screen.dart' show phoneWidth;
import '../l10n/app_localizations.dart';
import '../mail/contact_photos.dart';
import '../mail/mail_source.dart';
import '../widgets/dialog.dart';
import 'background_sheet.dart';

/// Once, the first time a message is opened with sender pictures on and
/// the contacts book never asked for: why Piuma would read it, then the
/// system's question on Continue. Not now, or closing the sheet, is the
/// answer for good; Settings › Privacy offers it again.
Future<void> askContactPhotos(BuildContext context, MailSource source) async {
  final permission = ContactsPermission.current;
  if (_asking) return;
  _asking = true;
  try {
    if (await permission.status() != ContactsAccess.notAsked) return;
    if (!(await source.privacySettings()).senderPictures) return;
    if (!context.mounted) return;
    await permission.markAsked();
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    // A sheet on the phone, a dialog on the desktop (macOS).
    final phone = MediaQuery.sizeOf(context).width < phoneWidth;
    Widget intro(BuildContext _) => IntroSheet(
      icon: PiumaIcon.user,
      title: l.contactsIntroTitle,
      body: l.contactsIntroBody,
      sheet: phone,
    );
    final go = phone
        ? await showPiumaSheet<bool>(
            context,
            label: l.contactsIntroTitle,
            builder: intro,
          )
        : await showPiumaDialog<bool>(
            context,
            label: l.contactsIntroTitle,
            builder: intro,
          );
    if ((go ?? false) && await permission.request()) source.contactsChanged();
  } finally {
    _asking = false;
  }
}

bool _asking = false;
