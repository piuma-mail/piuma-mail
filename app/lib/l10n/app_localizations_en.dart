// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get catalogSubtitle => 'Component catalog · Phase 0';

  @override
  String get sectionColors => 'Colors';

  @override
  String get sectionTypography => 'Typography';

  @override
  String get sectionButtons => 'Buttons';

  @override
  String get sectionFilters => 'Filters';

  @override
  String get sectionMessageRows => 'Message rows';

  @override
  String get colorBackground => 'Background';

  @override
  String get colorSurface => 'Surface';

  @override
  String get colorText => 'Text';

  @override
  String get colorSecondary => 'Secondary';

  @override
  String get colorAccent => 'Accent';

  @override
  String get colorSoft => 'Soft';

  @override
  String get colorSuccess => 'Success';

  @override
  String get colorWarning => 'Warning';

  @override
  String get colorDanger => 'Danger';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Title';

  @override
  String get typeSubtitle => 'Subtitle';

  @override
  String get typeBody => 'Body';

  @override
  String get typeSmall => 'Small';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Send';

  @override
  String get actionSnooze => 'Snooze';

  @override
  String get actionReply => 'Reply';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDisabled => 'Disabled';

  @override
  String get filterUnread => 'Unread';

  @override
  String get filterAttachments => 'With attachments';

  @override
  String get filterPeople => 'People only';

  @override
  String get messageUnread => 'Unread';

  @override
  String get compose => 'Compose';

  @override
  String get unifiedInbox => 'Unified inbox';

  @override
  String get accounts => 'Accounts';

  @override
  String get addAccount => 'Add an account';

  @override
  String get inbox => 'Inbox';

  @override
  String downloading(String done, String total) {
    return 'Downloading $done of $total';
  }

  @override
  String get offline => 'Offline · retrying';

  @override
  String get signInFailed => 'An account needs its password again';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts accounts',
      one: '1 account',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread unread',
      zero: 'all read',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Pick a message to read it.';

  @override
  String get noSubject => '(no subject)';

  @override
  String get couldNotLoadMessage =>
      'This message could not be downloaded. Check the connection and try again.';

  @override
  String get loading => 'Loading…';

  @override
  String toYouToday(String time) {
    return 'to you · today at $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'to you · yesterday at $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'to you · $date at $time';
  }

  @override
  String get sectionToday => 'Today';

  @override
  String get sectionYesterday => 'Yesterday';

  @override
  String get sectionThisWeek => 'This week';

  @override
  String get sectionThisMonth => 'Earlier this month';

  @override
  String get sectionOlder => 'Older';

  @override
  String get defaultAccountName => 'Mail';

  @override
  String get emailAddress => 'Email address';

  @override
  String get password => 'Password';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get imapServer => 'IMAP server';

  @override
  String get port => 'Port';

  @override
  String get security => 'Security';

  @override
  String get accountName => 'Account name';

  @override
  String get accountColor => 'Account color';

  @override
  String get color => 'Color';

  @override
  String get connect => 'Connect';

  @override
  String get connecting => 'Connecting…';

  @override
  String get notNow => 'Not now';

  @override
  String get enterToConnect => 'to connect';

  @override
  String get errorWrongPassword =>
      'The server did not accept this address and password. If your provider uses app passwords, create one and use it here.';

  @override
  String get errorUnreachable =>
      'The server could not be reached. Check the server name, the port and your connection.';

  @override
  String get errorInsecure =>
      'A secure connection to the server could not be made. Check the server name and the security setting.';

  @override
  String get errorKeychain =>
      'The password could not be saved in the system keychain.';

  @override
  String get errorOther => 'Something went wrong while connecting. Try again.';

  @override
  String get yourAccounts => 'Your accounts';

  @override
  String get noAccountsYet => 'Your first account will appear here.';

  @override
  String get connected => 'Connected';

  @override
  String get privacyNote =>
      'Your email stays on this device. We connect straight to your servers, with nobody in between.';

  @override
  String get newMessage => 'New message';

  @override
  String get close => 'Close';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get cc => 'Cc';

  @override
  String get bcc => 'Bcc';

  @override
  String get ccBcc => 'Cc  Bcc';

  @override
  String get subject => 'Subject';

  @override
  String get messageBody => 'Message';

  @override
  String get addRecipient => 'Add';

  @override
  String removeRecipient(String name) {
    return 'Remove $name';
  }

  @override
  String undoSendHint(int seconds) {
    return 'You can undo send for $seconds seconds';
  }

  @override
  String get sendNoRecipients => 'Add at least one recipient.';

  @override
  String sendBadAddress(String address) {
    return '“$address” is not an email address.';
  }

  @override
  String get sending => 'Sending…';

  @override
  String get sent => 'Sent';

  @override
  String get undo => 'Undo';

  @override
  String get draftDiscarded => 'Draft discarded';

  @override
  String get sendErrorPassword =>
      'The outgoing server didn\'t accept the password. Your message is still here.';

  @override
  String get sendErrorUnreachable =>
      'Couldn\'t reach the outgoing server. Your message is still here.';

  @override
  String get sendErrorRejected =>
      'The outgoing server refused the message. Your message is still here.';

  @override
  String get sendErrorOther =>
      'The message couldn\'t be sent. Your message is still here.';

  @override
  String stepOf(int step, int total) {
    return '$step of $total';
  }

  @override
  String get whatsYourEmail => 'What’s your email?';

  @override
  String get findSettingsHint => 'We’ll find the server settings for you.';

  @override
  String get continueAction => 'Continue';

  @override
  String get lookingUp => 'Looking…';

  @override
  String get setUpManually => 'Set up manually';

  @override
  String get back => 'Back';

  @override
  String get weFoundSettings => 'We found your settings';

  @override
  String get incoming => 'Incoming';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get incomingAndOutgoing => 'Incoming and outgoing';

  @override
  String get guessedSettings =>
      'These are the usual settings for your domain. If connecting fails, check them.';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNameHint => 'Shown to the people you write to. Optional.';

  @override
  String get settingsNotFound =>
      'We couldn’t find the settings for this address. Your provider’s help pages list them.';

  @override
  String get smtpServer => 'SMTP server';

  @override
  String get username => 'Username';

  @override
  String get usedForBoth => 'Used for both incoming and outgoing mail.';

  @override
  String get verifyAndConnect => 'Verify and connect';

  @override
  String get archive => 'Archive';

  @override
  String get archived => 'Archived';

  @override
  String get movedToTrash => 'Moved to Trash';

  @override
  String get actionFailed =>
      'The message couldn’t be moved. It’s back in the inbox.';

  @override
  String get replyTitle => 'Reply';

  @override
  String quoteHeader(String date, String name) {
    return 'On $date, $name wrote:';
  }

  @override
  String get search => 'Search…';

  @override
  String get searchAllAccounts => 'Search all accounts';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
      zero: 'No results',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filters';

  @override
  String get filterLastMonth => 'Last month';

  @override
  String get filterAccount => 'Account';

  @override
  String get searchOperators => 'Operators';

  @override
  String get operatorNameHint => 'name';

  @override
  String get operatorDateHint => 'date';

  @override
  String get searchPeople => 'People';

  @override
  String get searchEmail => 'Email';

  @override
  String personEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String get searchNoResults => 'Nothing found';

  @override
  String get searchNoResultsHint => 'Try fewer words or another spelling.';

  @override
  String get searchNoResultsFilters => 'No results with these filters';

  @override
  String get searchNoResultsFiltersHint =>
      'Remove a filter or operator to widen the search.';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get searchEmptyHint =>
      'Search every account by word, sender or date, even offline.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matches',
      one: '1 match',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Open conversation';

  @override
  String get noMessageToShow => 'No message to show';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts accounts',
      one: '1 account',
    );
    return 'Searched $_temp0 · $emails emails · $seconds s · local index, works offline';
  }

  @override
  String get keyMove => 'move';

  @override
  String get keyOpen => 'open';

  @override
  String get privacyImagesBlocked => 'Images blocked';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trackers stopped',
      one: '1 tracker stopped',
    );
    return 'Images blocked · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Loading images…';

  @override
  String get privacyImagesLoaded => 'Images loaded';

  @override
  String get privacyImagesLoadedStopped =>
      'Images loaded · trackers still stopped';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trackers stopped',
      one: '1 tracker stopped',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count links cleaned',
      one: '1 link cleaned',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Privacy for this message';

  @override
  String get privacySheetSubtitle =>
      'The sender can’t tell if or when you opened it.';

  @override
  String get trackerPixel => 'Open pixel';

  @override
  String get trackerFont => 'Remote font';

  @override
  String get trackerStyle => 'Remote style';

  @override
  String get trackerLinks => 'Tracked links';

  @override
  String get trackerStopped => 'Stopped';

  @override
  String get loadImagesOnce => 'Load images once';

  @override
  String get imagesAlreadyLoaded => 'Images already loaded';

  @override
  String trustSender(String name) {
    return 'Always trust $name';
  }

  @override
  String senderTrusted(String name) {
    return '$name is trusted';
  }

  @override
  String get alwaysBlockImages => 'Always block remote images';

  @override
  String get alwaysBlockImagesHint => 'Applies to all untrusted senders';

  @override
  String get imageNotLoaded => 'Image not loaded';

  @override
  String get suspiciousLinkTitle => 'Check this link';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'The text shows $shown, but the link goes to $real.';
  }

  @override
  String get openAnyway => 'Open anyway';

  @override
  String get dontOpen => 'Don’t open';

  @override
  String get riskProgram => 'A program that can run';

  @override
  String riskDisguised(String kind) {
    return 'A program, named like a $kind';
  }

  @override
  String get riskMacros => 'Has macros that can run';

  @override
  String get riskLocked => 'Locked with a password';

  @override
  String get riskOpenProgram => 'Open this program?';

  @override
  String get riskOpenFile => 'Open this file?';

  @override
  String get riskOpenArchive => 'Open this archive?';

  @override
  String riskBodyProgram(String name) {
    return '$name is a program. Programs from email can take over your device. Open it only if you were expecting it.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name looks like a $kind, but it is a program. Programs from email can take over your device. Open it only if you were expecting it.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name has macros, which can run when it opens. Open it only if you were expecting it.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name is locked with a password, so nothing can look inside it. Open it only if you were expecting it.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · from $email';
  }

  @override
  String get settings => 'Settings';

  @override
  String get backToMail => 'Back to mail';

  @override
  String get settingsAccountsTitle => 'Accounts';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count IMAP mailboxes, one Inbox.',
      one: 'One IMAP mailbox.',
    );
    return '$_temp0 Color shows where each email comes from.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Add account';

  @override
  String get addAccountNote =>
      'IMAP and SMTP. Gmail, iCloud and Fastmail set themselves up.';

  @override
  String get privacyTitle => 'Privacy & security';

  @override
  String get privacySubtitle =>
      'Everything happens on this device. No data leaves your mailbox.';

  @override
  String get blockImagesSetting => 'Block remote images';

  @override
  String get blockImagesSettingHint => 'Images load only when you ask.';

  @override
  String get stopPixelsSetting => 'Stop tracking pixels';

  @override
  String get stopPixelsSettingHint =>
      'Senders can’t tell if or when you open a message.';

  @override
  String get cleanLinksSetting => 'Clean links';

  @override
  String get cleanLinksSettingHint =>
      'Strips utm and tracking parameters before opening.';

  @override
  String get warnLinksSetting => 'Warn about suspicious links';

  @override
  String get warnLinksSettingHint =>
      'Asks before opening a link that shows one address and goes to another.';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get trackersStoppedLabel => 'trackers stopped';

  @override
  String get linksCleanedLabel => 'links cleaned';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious suspicious links flagged',
      one: '1 suspicious link flagged',
    );
    return 'Open pixels $pixels · remote fonts and styles $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Trusted senders';

  @override
  String get trustedSendersHint => 'images always load';

  @override
  String trustedSince(String email, String date) {
    return '$email · since $date';
  }

  @override
  String get removeTrusted => 'Remove';

  @override
  String get noTrustedSenders =>
      'No trusted senders. Images stay blocked for everyone.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Attach file';

  @override
  String removeAttachment(String name) {
    return 'Remove $name';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name saved in Downloads';
  }

  @override
  String attachmentNotSaved(String name) {
    return 'Couldn’t download $name. Check the connection and try again.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Attachments can be up to $max in all. Remove some and try again.';
  }

  @override
  String fileNotRead(String name) {
    return 'Couldn’t read $name.';
  }

  @override
  String get folderSent => 'Sent';

  @override
  String get folderArchive => 'Archive';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: 'One account',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'to $people · today at $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'to $people · yesterday at $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'to $people · $date at $time';
  }

  @override
  String get emptyFolder => 'Nothing here yet.';

  @override
  String threadMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String conversationSummary(int count, String people) {
    return '$count messages · $people';
  }

  @override
  String readMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count read messages',
      one: '1 read message',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count new';
  }

  @override
  String get you => 'you';

  @override
  String get quotedTextHidden => '··· quoted text hidden';

  @override
  String get showQuotedText => 'Show quoted text';

  @override
  String get youName => 'You';

  @override
  String yesterdayAt(String time) {
    return 'Yesterday $time';
  }

  @override
  String get pickMessage => 'Select';

  @override
  String get unpickMessage => 'Selected';

  @override
  String get selectAll => 'Select all';

  @override
  String pickedOf(int count, int total) {
    return '$count of $total selected';
  }

  @override
  String get deselect => 'Deselect';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversations selected',
      one: 'conversation selected',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'from $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'from $names and $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'from $names and $count more';
  }

  @override
  String andMore(String name, int count) {
    return '$name and $count more';
  }

  @override
  String get markRead => 'Mark as read';

  @override
  String get markUnread => 'Mark as unread';

  @override
  String get hintArchive => 'archive';

  @override
  String get hintUnread => 'unread';

  @override
  String get hintDeselect => 'deselect';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations archived',
      one: 'Archived',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations moved to Trash',
      one: 'Moved to Trash',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'Couldn’t reach the server. Read and unread are back as they were.';

  @override
  String get signaturesTitle => 'Signatures';

  @override
  String get newSignature => 'New signature';

  @override
  String get newSignatureLabel => 'New signature';

  @override
  String get noSignatures => 'No signatures yet. Make one with New signature.';

  @override
  String get signatureTemplate => 'Template';

  @override
  String get signatureLogo => 'Logo';

  @override
  String get signatureLabelField => 'Signature name';

  @override
  String get signatureAccount => 'Account';

  @override
  String get signatureName => 'Name';

  @override
  String get signatureRole => 'Role';

  @override
  String get signatureCompany => 'Company';

  @override
  String get signaturePhone => 'Phone';

  @override
  String get signatureWebsite => 'Website';

  @override
  String get signatureAccent => 'Accent color';

  @override
  String get accentBlue => 'Accent blue';

  @override
  String get accentBlack => 'Accent black';

  @override
  String get accentTerracotta => 'Accent terracotta';

  @override
  String get signatureWhen => 'When to use it';

  @override
  String signatureForNew(String email) {
    return 'New emails from $email';
  }

  @override
  String get signatureForReplies => 'Replies and forwards';

  @override
  String get signatureNone => 'None';

  @override
  String get deleteSignature => 'Delete signature';

  @override
  String get signatureDeleteHint => 'Emails already sent keep it.';

  @override
  String get signaturePreview => 'Preview';

  @override
  String get previewLight => 'Light';

  @override
  String get previewDark => 'Dark';

  @override
  String get previewText => 'Text';

  @override
  String get signatureSampleText =>
      'Hi Luca,\nthe final files are attached. Let me know if you need anything else.\n\nTalk soon,';

  @override
  String get signatureNote =>
      'No images: the signature arrives clean even where images are blocked, and the plain-text version is created for you.';

  @override
  String get signatureNoteLogo =>
      'The logo travels inside the email (max 40 KB) with alt text, so it never asks to “load images” and tracks no one. The plain-text version is created for you.';

  @override
  String get signatureUseAll => 'all';

  @override
  String get signatureUseNew => 'new emails';

  @override
  String get signatureUseReplies => 'replies and forwards';

  @override
  String get signatureUseNone => 'not in use';

  @override
  String get templateMinimal => 'Minimal';

  @override
  String get templateClassic => 'Classic';

  @override
  String get templateMonogram => 'Monogram';

  @override
  String get templateLogo => 'With logo';

  @override
  String get noLogo => 'NO LOGO';

  @override
  String get logoHint => 'PNG or JPEG, shrunk to 40 KB automatically';

  @override
  String get removeLogo => 'Remove';

  @override
  String get uploadLogo => 'Upload';

  @override
  String get logoTooBig =>
      'This logo stays over 40 KB even when shrunk. Try a simpler one.';

  @override
  String get logoNotImage => 'Pick a PNG or JPEG image.';

  @override
  String signatureChip(String label) {
    return 'Signature · $label';
  }

  @override
  String get noSignature => 'No signature';

  @override
  String get manageSignatures => 'Manage signatures…';

  @override
  String get signatureUsedNew => 'New emails';

  @override
  String get signatureUsedReplies => 'Replies';

  @override
  String get composeSignatureNote =>
      'The signature follows the From account: its signature for new emails, its short one for replies and forwards.';

  @override
  String get noticeOpen => 'Open';

  @override
  String get noticeChannel => 'New mail';

  @override
  String noticeTitleMany(String sender, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$sender · $_temp0';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsLead => 'Few, and only when they matter.';

  @override
  String get notifyAbout => 'Notify me about';

  @override
  String get notifyPeople => 'People only';

  @override
  String get notifyPeopleHint =>
      'Email written by people. No newsletters, receipts or automated messages.';

  @override
  String get notifyRecommended => 'Recommended';

  @override
  String get notifyAll => 'All';

  @override
  String get notifyAllHint => 'Every new email that lands in the Inbox.';

  @override
  String get notifyOff => 'None';

  @override
  String get notifyOffHint => 'Check whenever you like. No badges, no sounds.';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get quietTitle => 'Every night';

  @override
  String get quietHint => 'Email still arrives, quietly.';

  @override
  String get quietFrom => 'From';

  @override
  String get quietTo => 'to';

  @override
  String quietFromLabel(String time) {
    return 'Quiet hours start at $time';
  }

  @override
  String quietToLabel(String time) {
    return 'Quiet hours end at $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return 'Search $_temp0';
  }

  @override
  String get phoneAccountsAll => 'All';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return 'Showing all $_temp0';
  }

  @override
  String get composeMessage => 'Compose a message';

  @override
  String get moreActions => 'More actions';

  @override
  String quickReplyHint(String name) {
    return 'Reply to $name…';
  }

  @override
  String get sendReply => 'Send reply';

  @override
  String get cancel => 'Cancel';

  @override
  String get pickAll => 'All';

  @override
  String get pickNone => 'None';

  @override
  String get pickRead => 'Read';

  @override
  String get pickUnread => 'Unread';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'selected',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'of $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count of $total selected';
  }

  @override
  String get phoneSelectActions => 'Actions on selected';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsMail => 'Mail';

  @override
  String get settingsApp => 'App';

  @override
  String get writingTitle => 'Writing';

  @override
  String get readingTitle => 'Reading';

  @override
  String get readingSubtitle => 'How the list looks, and what helps you read.';

  @override
  String get organizingTitle => 'Organizing';

  @override
  String get organizingSubtitle => 'Zones, rules, folders and labels.';

  @override
  String signaturesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signatures',
      one: '1 signature',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLine => 'Open source · GPL-3.0';

  @override
  String get motto => 'Mail, made light.';

  @override
  String get appName => 'Piuma Mail';

  @override
  String phoneAccountsMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0, accounts and Settings';
  }

  @override
  String get allAccounts => 'All accounts';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count inboxes together',
      one: '1 inbox',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return '$name only, accounts and Settings';
  }

  @override
  String accountOnly(String name) {
    return '$name only';
  }

  @override
  String get showAllAccounts => 'Show all';

  @override
  String get phoneFolders => 'Folders';

  @override
  String phoneSearchOne(String name) {
    return 'Search $name';
  }

  @override
  String get welcomeLead =>
      'Connect your IMAP accounts and read everything in one inbox, without the noise.';

  @override
  String get staysOnDevice => 'Your email stays on your device';

  @override
  String get editServers => 'Edit';

  @override
  String get serverHost => 'Server';

  @override
  String get offlineTitle => 'You’re offline';

  @override
  String get offlineDetail => 'outgoing email sends once you’re back online';

  @override
  String downloadingAccount(String name) {
    return 'Downloading $name';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done of $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'The $name account can’t connect';
  }

  @override
  String passwordChanged(String email) {
    return 'Did the password change? Email for $email has stopped arriving.';
  }

  @override
  String get signInAgain => 'Sign in again';

  @override
  String get later => 'Later';

  @override
  String signInTo(String name) {
    return 'Sign in to $name';
  }

  @override
  String get signIn => 'Sign in';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get allCaughtUp => 'All caught up';

  @override
  String get allCaughtUpDetail =>
      'Nobody is waiting on you. The rest of the day is yours.';

  @override
  String get countOf => 'of';

  @override
  String get draftSaved => 'Draft saved';

  @override
  String get draftNotSaved => 'Not saved';

  @override
  String get draftNotSavedToast => 'Draft not saved';

  @override
  String get reopen => 'Reopen';

  @override
  String get discard => 'Discard';

  @override
  String get noRecipients => 'No recipients';

  @override
  String get folderDrafts => 'Drafts';

  @override
  String accountFolders(String name) {
    return '$name folders';
  }

  @override
  String get moveShort => 'Move';

  @override
  String get moveTo => 'Move to…';

  @override
  String moveToIn(String name) {
    return 'Move to folder in $name';
  }

  @override
  String get noFoldersMatch => 'No folder by that name';

  @override
  String noOtherFolders(String name) {
    return '$name has no other folders yet';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations moved to $folder',
      one: 'Moved to $folder',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'Outbox · $count';
  }

  @override
  String outboxTo(String names) {
    return 'To $names';
  }

  @override
  String get outboxWaiting => 'Waiting';

  @override
  String get outboxNotSent => 'Not sent';

  @override
  String outboxRefused(String reason) {
    return 'The server refused it: $reason';
  }

  @override
  String get inOutbox => 'In the Outbox · it goes once you’re back online';

  @override
  String get editAction => 'Edit';

  @override
  String get backgroundTitle => 'New mail as it arrives';

  @override
  String get backgroundBody =>
      'Piuma stays connected to your accounts, with no server in between. Android will ask two things: to show notifications, and to let Piuma run in the background.';

  @override
  String get newMailHeading => 'New mail';

  @override
  String get deliveryInstant => 'As it arrives';

  @override
  String get deliveryInstantHint => 'Keeps a silent notice in the shade';

  @override
  String get deliveryPeriodic => 'Every 15 minutes';

  @override
  String get deliveryPeriodicHint => 'No notice; Android may wait longer';

  @override
  String get folderNewsletters => 'Newsletters';

  @override
  String newslettersTileLabel(int count) {
    return 'Newsletters, $count unread';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes min · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes min read · arrived at $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Arrived at $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Arrived on $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes min read · arrived on $date';
  }

  @override
  String get dayToday => 'today';

  @override
  String get dayYesterday => 'yesterday';

  @override
  String get readLater => 'Read later';

  @override
  String get readLaterDone => 'Kept as unread';

  @override
  String get unsubscribe => 'Unsubscribe';

  @override
  String unsubscribeTitle(String sender) {
    return 'Unsubscribe from $sender?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender gets one request to stop. Nothing opens, and what already came stays here.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'A message goes from your account to $address to ask. What already came stays here.';
  }

  @override
  String get unsubscribePage => 'Their unsubscribe page opens in the browser.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender gives no way to unsubscribe. Move it to the Inbox, or archive what comes.';
  }

  @override
  String get unsubscribeConfirm => 'Unsubscribe';

  @override
  String get unsubscribeOpen => 'Open page';

  @override
  String unsubscribeDone(String sender) {
    return 'Unsubscribed from $sender';
  }

  @override
  String get unsubscribeFailed =>
      'Couldn’t unsubscribe. Check the connection and try again.';

  @override
  String get alwaysInInbox => 'Always in Inbox';

  @override
  String alwaysInInboxDone(String sender) {
    return 'Mail from $sender now goes to the Inbox';
  }

  @override
  String get newslettersArchiveNote =>
      'Read more than 7 days ago? They archive themselves';

  @override
  String get newslettersEmpty => 'No newsletters';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reads',
      one: '1 read',
      zero: 'All read',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes minutes in all';
  }

  @override
  String newslettersNew(int count) {
    return '$count new';
  }

  @override
  String get folderVault => 'Vault';

  @override
  String vaultTileLabel(String status) {
    return 'Vault, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Vault, $count waiting';
  }

  @override
  String vaultDue(String when) {
    return 'Due $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Due $when';
  }

  @override
  String get vaultAllClear => 'All clear';

  @override
  String get vaultToday => 'Today';

  @override
  String get vaultTomorrow => 'Tomorrow';

  @override
  String get dayTomorrow => 'tomorrow';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'in $days days',
      one: 'tomorrow',
      zero: 'today',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Ordered';

  @override
  String get parcelShipped => 'Shipped';

  @override
  String get parcelTransit => 'In transit';

  @override
  String get parcelDelivered => 'Delivered';

  @override
  String vaultDeliveredOn(String day) {
    return 'Delivered $day';
  }

  @override
  String vaultCarrierFrom(String carrier, String merchant) {
    return '$carrier · from $merchant';
  }

  @override
  String vaultFrom(String merchant) {
    return 'From $merchant';
  }

  @override
  String vaultLastScan(String place) {
    return 'Last scan: $place';
  }

  @override
  String get vaultDueLabel => 'Due';

  @override
  String get vaultPaid => 'Paid';

  @override
  String get vaultDownloadPdf => 'Download PDF';

  @override
  String get vaultMarkPaid => 'Mark as paid';

  @override
  String get vaultPaidFailed => 'Couldn’t save that. Try again.';

  @override
  String vaultFlight(String number, String date) {
    return 'Flight $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Seat';

  @override
  String get vaultCode => 'Code';

  @override
  String get vaultBoardingPass => 'Boarding pass';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'confirmed';

  @override
  String get vaultPending => 'to confirm';

  @override
  String get vaultCancelled => 'cancelled';

  @override
  String get vaultDirections => 'Directions';

  @override
  String get vaultNotePhone =>
      'Read on-device from the original email · tap a card to open it';

  @override
  String get vaultEmpty =>
      'Parcels, spending, trips and more show up here, read on this device from their emails.';

  @override
  String get folderAttachments => 'Attachments';

  @override
  String get attachmentsSubtitle =>
      'Every file you’ve received, no need to open the email';

  @override
  String get attachmentsAll => 'All';

  @override
  String get attachmentsMedia => 'Photos & media';

  @override
  String get attachmentsDocuments => 'Documents';

  @override
  String get attachmentsSheets => 'Sheets';

  @override
  String get attachmentsFilter => 'Filter by type';

  @override
  String get attachmentsSearch => 'Search files or senders';

  @override
  String get attachmentsSearchLabel => 'Search attachments';

  @override
  String get attachmentsRecent => 'Recent';

  @override
  String get attachmentsLargest => 'Largest';

  @override
  String attachmentsSortLabel(String sort) {
    return 'Sort by: $sort';
  }

  @override
  String get attachmentsThisWeek => 'This week';

  @override
  String get attachmentsEarlier => 'Earlier';

  @override
  String attachmentsMeta(String name, String size, String when) {
    return 'From: $name · $size · $when';
  }

  @override
  String get attachmentsDownload => 'Download';

  @override
  String get attachmentsOpenEmail => 'Open email';

  @override
  String get attachmentsEmail => 'Email';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, from $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return 'Download $name';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'Open email from $from';
  }

  @override
  String get attachmentsNoneNew => 'Nothing new';

  @override
  String attachmentsTileLabel(String status) {
    return 'Attachments, $status';
  }

  @override
  String get attachmentsEmpty =>
      'Files you receive show up here, from every account.';

  @override
  String attachmentsNoMatch(String query) {
    return 'No files match “$query”';
  }

  @override
  String attachmentsNew(int count) {
    return '$count new';
  }

  @override
  String get folderSnoozed => 'Snoozed';

  @override
  String get snoozeUntilTitle => 'Snooze until…';

  @override
  String get snoozeEvening => 'This evening';

  @override
  String get snoozeMorning => 'Tomorrow morning';

  @override
  String get snoozeWeekend => 'Weekend';

  @override
  String get snoozeNextWeek => 'Next week';

  @override
  String snoozeTileToday(String time) {
    return 'today $time';
  }

  @override
  String snoozeToday(String time) {
    return 'today, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'tomorrow, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'tomorrow $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations snoozed until $when',
      one: 'Snoozed until $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Back to inbox';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations back in the inbox',
      one: 'Back in the inbox',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Tomorrow';

  @override
  String get sectionLater => 'Later';

  @override
  String get sendLater => 'Send later';

  @override
  String get sendLaterTomorrowMorning => 'Tomorrow morning';

  @override
  String get sendLaterTomorrowAfternoon => 'Tomorrow afternoon';

  @override
  String get sendLaterMondayMorning => 'Monday morning';

  @override
  String scheduleTomorrow(String time) {
    return 'Schedule for tomorrow at $time';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Schedule for $day at $time';
  }

  @override
  String get sendLaterNote =>
      'Sent from this device at that time. If it’s off then, it goes as soon as it’s back on.';

  @override
  String scheduledToast(String when) {
    return 'Scheduled for $when';
  }

  @override
  String get paletteLabel => 'Command palette';

  @override
  String get paletteHint => 'Search or run a command';

  @override
  String get paletteActions => 'Actions';

  @override
  String get paletteMessages => 'Messages';

  @override
  String paletteWriteTo(String name) {
    return 'Write to $name';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Show only messages from $name';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Attachments from $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Search all mail for “$query”';
  }

  @override
  String paletteGoTo(String place) {
    return 'Go to $place';
  }

  @override
  String get paletteMove => 'move';

  @override
  String get paletteRun => 'run';

  @override
  String get paletteAnywhere => 'from any screen';

  @override
  String senderCardLabel(String name) {
    return '$name’s card';
  }

  @override
  String get senderKind => 'Sender';

  @override
  String get senderClose => 'Close card';

  @override
  String get senderWrite => 'Write';

  @override
  String get senderAll => 'All emails';

  @override
  String get senderMute => 'Mute';

  @override
  String get senderMuted => 'Muted';

  @override
  String senderArrivesIn(String account) {
    return 'Arrives in $account';
  }

  @override
  String get senderConversations => 'Conversations';

  @override
  String get senderNoMail => 'No emails from them on this device yet.';

  @override
  String senderMutedToast(String name) {
    return 'No more notifications from $name';
  }

  @override
  String get rulesTitle => 'Rules & folders';

  @override
  String get rulesSubtitle =>
      'Sorts your mail the way you would. Every rule reads like a sentence.';

  @override
  String get rulesWhere => 'Rules run on this device, on new mail in the inbox';

  @override
  String get rulesHeading => 'Rules';

  @override
  String get rulesNew => 'New rule';

  @override
  String get rulesEdit => 'Edit rule';

  @override
  String get rulesNone =>
      'No rules of your own yet. A rule sorts new mail as it lands, the way you would.';

  @override
  String get ruleWhen => 'When';

  @override
  String get ruleThen => 'then';

  @override
  String get ruleFieldSender => 'the sender';

  @override
  String get ruleFieldSubject => 'the subject';

  @override
  String get ruleFieldRecipient => 'the recipient';

  @override
  String get ruleOpContains => 'contains';

  @override
  String get ruleOpIs => 'is';

  @override
  String get ruleOpStarts => 'starts with';

  @override
  String get ruleOpNotContains => 'doesn’t contain';

  @override
  String get ruleDoMove => 'move to';

  @override
  String get ruleDoArchive => 'archive';

  @override
  String get ruleDoRead => 'mark as read';

  @override
  String get ruleText => 'Text to match';

  @override
  String get ruleTextHint => 'text';

  @override
  String get ruleTrayField => 'Field';

  @override
  String get ruleTrayOp => 'Condition';

  @override
  String get ruleTrayAction => 'Action';

  @override
  String get ruleTrayFolder => 'Folder';

  @override
  String get rulePickFolder => 'a folder';

  @override
  String get ruleNoFolders => 'Your accounts have no folders of their own yet.';

  @override
  String get ruleApplyToo => 'Apply to those too';

  @override
  String get ruleSave => 'Save rule';

  @override
  String get ruleDelete => 'Delete rule';

  @override
  String get rulePaused => 'Paused';

  @override
  String get ruleFresh => 'Active from now';

  @override
  String get foldersHeading => 'Folders';

  @override
  String get foldersNone => 'No folders of its own';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Applies to $count existing emails',
      one: 'Applies to $count existing email',
      zero: 'No existing emails match',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails sorted',
      one: '1 email sorted',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'last today $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'last $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Rule on: $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Invite';

  @override
  String get inviteYes => 'Yes';

  @override
  String get inviteMaybe => 'Maybe';

  @override
  String get inviteNo => 'No';

  @override
  String get inviteRespond => 'Respond to invite';

  @override
  String get inviteAllDay => 'All day';

  @override
  String get inviteRepeats => 'repeats';

  @override
  String get inviteYouAccepted => 'You accepted';

  @override
  String get inviteYouTentative => 'You replied maybe';

  @override
  String get inviteYouDeclined => 'You declined';

  @override
  String get inviteNotSent => 'Your reply couldn’t be sent. Try again.';

  @override
  String get inviteCancelled => 'This event was cancelled';

  @override
  String get inviteYours => 'You sent this invite';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attendees',
      one: '1 attendee',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name will get your reply';
  }

  @override
  String inviteQueued(String name) {
    return 'goes to $name when you’re back online';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name accepted';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name replied maybe';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name declined';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Accepted: $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Maybe: $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Declined: $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name accepted this invitation.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name might come.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name declined this invitation.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Invite: $summary, $when';
  }

  @override
  String get inviteFree => 'Free · no conflicts';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Overlaps $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Availability: $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'added to $name';
  }

  @override
  String get settingsCalendars => 'Calendars';

  @override
  String get calIntro =>
      'Piuma has no calendar of its own: connect the ones you already use. Events stay there.';

  @override
  String get calConnected => 'Connected calendars';

  @override
  String calSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '1 source',
    );
    return '$_temp0';
  }

  @override
  String calCalendars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calendars',
      one: '1 calendar',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Connect a calendar';

  @override
  String get calChoose => 'Choose where to connect from';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Server, email and app password';

  @override
  String get calIcs => 'Subscribe to an .ics URL';

  @override
  String get calIcsSub => 'Read-only, updates on its own';

  @override
  String get calCalDavLabel => 'Email address or CalDAV server';

  @override
  String get calCalDavHint =>
      'iCloud needs an app password; it stays encrypted in the system keychain.';

  @override
  String get calIcsLabel => '.ics calendar URL';

  @override
  String get calIcsHint =>
      '.ics calendars are read-only: handy for holidays, sports, shifts.';

  @override
  String get calUsername => 'User name (if not the email)';

  @override
  String get calPassword => 'Password';

  @override
  String get calConnectButton => 'Connect';

  @override
  String get calSubscribe => 'Subscribe';

  @override
  String get calSuggested =>
      'Email accounts you’ve added that offer a calendar are suggested automatically';

  @override
  String get calHasCalendar => 'has a calendar too';

  @override
  String get calDone => 'Connected';

  @override
  String get calDisconnect => 'Disconnect';

  @override
  String calDisconnectLabel(String name) {
    return 'Disconnect $name';
  }

  @override
  String get calReadOnly => 'read-only';

  @override
  String get calInvitesTag => 'invites';

  @override
  String get calShowAvailability => 'Show availability';

  @override
  String get calAvailabilityShort => 'availability';

  @override
  String calAvailabilityFor(String name) {
    return 'Show availability for $name';
  }

  @override
  String get calNone =>
      'No calendars connected. Invites still work, via email.';

  @override
  String get calWhenInvite => 'When an invite arrives';

  @override
  String get calAddTo => 'Add to';

  @override
  String get calAddToSub => 'Where invites you accept go';

  @override
  String get calAddInvitesTo => 'Add invites to';

  @override
  String get calNoWritable => 'None';

  @override
  String get calConflicts =>
      'Check for conflicts across all connected calendars';

  @override
  String get calConflictsSub =>
      'Invites show right away if you’re already busy then.';

  @override
  String get calFooter =>
      'Without connected calendars you can still answer invites by email and open the .ics file.';

  @override
  String get calStaysHere =>
      'Connections stay on this device; passwords are kept in the system keychain.';

  @override
  String get calWrongPassword => 'Wrong user name or password.';

  @override
  String get calUnreachable => 'No calendar found there. Check the address.';

  @override
  String get calFailed => 'Couldn’t connect. Try again.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => '.ics URL, read-only';

  @override
  String get calFromAccount => 'from the email account';

  @override
  String foundDateAdd(String when) {
    return 'Add $when to calendar';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Added to $calendar';
  }

  @override
  String foundDateAddLabel(String when) {
    return 'Add $when to calendar, found on this device';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when added to $calendar';
  }

  @override
  String get foundOnDevice => 'Found on this device';

  @override
  String get foundDateNotAdded =>
      'Couldn’t add it to the calendar. Try again in a moment.';

  @override
  String get calFindDates => 'Suggest adding dates found in emails';

  @override
  String get calFindDatesSub =>
      'A small suggestion next to the sentence, never automatic.';

  @override
  String get calOnDevice => 'on-device';

  @override
  String get inShort => 'In short';

  @override
  String get generatedOnDevice => 'Generated on device';

  @override
  String get yourTurn => 'Your turn:';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name writes “$words”';
  }

  @override
  String get inShortColon => 'In short:';

  @override
  String get onDevice => 'on device';

  @override
  String senderBriefTopic(String topic) {
    return 'mostly about “$topic”';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails this month',
      one: '1 email this month',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'the latest is waiting on your reply';

  @override
  String get searchByType => 'Search by type';

  @override
  String get frequentContacts => 'Frequent contacts';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearRecent => 'Clear';

  @override
  String get clearRecentSearches => 'Clear recent searches';

  @override
  String get noRecentSearches => 'No recent searches.';

  @override
  String get searchOperatorsHint => 'You can also type operators';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted emails indexed on this device · works offline',
      one: '1 email indexed on this device · works offline',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'With attachments';

  @override
  String get searchFromPeople => 'From people';

  @override
  String searchMailFrom(String name) {
    return 'Search mail from $name';
  }

  @override
  String removeRecentSearch(String query) {
    return 'Remove $query';
  }

  @override
  String get searchAddWords => 'Add words…';

  @override
  String rowPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String rowAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Block';

  @override
  String get senderBlocked => 'Blocked';

  @override
  String showSnoozed(int count) {
    return 'Show Snoozed ($count)';
  }

  @override
  String get hideSnoozed => 'Hide Snoozed';

  @override
  String get snoozeNoReply => 'If nobody replies';

  @override
  String get snoozeNoReplyHint => 'Comes back in 3 days if there’s no reply';

  @override
  String get previewClose => 'Close preview';

  @override
  String previewMeta(String size, String name) {
    return '$size · from $name';
  }

  @override
  String previewPage(int page, int count) {
    return 'Page $page of $count';
  }

  @override
  String get previewPrevPage => 'Previous page';

  @override
  String get previewNextPage => 'Next page';

  @override
  String previewOpenEmail(String name) {
    return 'Open $name’s email';
  }

  @override
  String get previewDownloadAll => 'Download all';

  @override
  String previewPhoto(int index, int count) {
    return 'Photo $index of $count · from the same email';
  }

  @override
  String get previewPhotos => 'Photos in the email';

  @override
  String get previewCantShow =>
      'This file can’t be shown here. You can still download it.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Page $page of $name';
  }

  @override
  String get vaultParcelsTitle => 'Package deliveries';

  @override
  String get vaultParcelsHint => 'On delivery day, just once.';

  @override
  String get vaultDueTitle => 'Due dates';

  @override
  String get vaultDueHint => 'Bills and renewals, three days ahead.';

  @override
  String get vaultNoticeParcel => 'Your package arrives today';

  @override
  String get vaultNoticeDueToday => 'Due today';

  @override
  String get vaultNoticeDueTomorrow => 'Due tomorrow';

  @override
  String vaultNoticeDueIn(int days) {
    return 'Due in $days days';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'around $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count certified emails',
      one: '1 certified email',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not delivered',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Sent';

  @override
  String get pecAccepted => 'Accepted';

  @override
  String get pecDelivered => 'Delivered';

  @override
  String get pecFailed => 'Not delivered';

  @override
  String pecTo(String who) {
    return 'To $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'To $count recipients · $delivered of $count delivered';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Accepted $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Delivered $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'Not delivered · $when';
  }

  @override
  String pecReasonAt(String reason, String when) {
    return '$reason · $when';
  }

  @override
  String get pecOpen => 'Open';

  @override
  String pecReceipt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Receipts',
      one: 'Receipt',
    );
    return '$_temp0';
  }

  @override
  String pecSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts saved in Downloads',
      one: 'Receipt saved in Downloads',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'Couldn’t save the receipt';

  @override
  String get pecNote =>
      'Receipts stay out of the inbox and gather on the message they belong to. Receipt saves the signed proof as a file.';

  @override
  String get pickDateTime => 'Pick date & time';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get pickTime => 'Time';

  @override
  String get pickOtherTime => 'Other time';

  @override
  String get pickTimeGone => 'That time has already gone by';

  @override
  String snoozeUntilAt(String when) {
    return 'Snooze until $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Schedule for $when';
  }

  @override
  String get senderNewsletterKind => 'Newsletter';

  @override
  String newsletterPerWeek(int count) {
    return 'about $count a week';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'about $count a month';
  }

  @override
  String newsletterOpened(int percent) {
    return 'you open $percent%';
  }

  @override
  String get newsletterUnsubscribed => 'Unsubscribed';

  @override
  String get newsletterClearAsk => 'clear old emails too?';

  @override
  String get newsletterClearYes => 'Yes, clear';

  @override
  String get newsletterClearNo => 'No';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unsubscribed · $count emails moved to Trash',
      one: 'Unsubscribed · 1 email moved to Trash',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept => 'Unsubscribed · old emails stay as they are';

  @override
  String get newsletterPageOpened =>
      'Their unsubscribe page is open in the browser';

  @override
  String get moveToNewsletters => 'Move to Newsletters';

  @override
  String get movedToNewsletters => 'Moved to Newsletters';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Has attachment';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceSubtitle => 'How you want your mail to look.';

  @override
  String get appearanceTheme => 'Theme';

  @override
  String get themeAutomatic => 'Automatic';

  @override
  String get appearanceDensity => 'Density';

  @override
  String get densityComfortable => 'Comfortable';

  @override
  String get densityCompact => 'Compact';

  @override
  String get appearancePreview => 'Preview';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get appearanceExample => 'Example';

  @override
  String get previewDrawnHere => 'Drawn on this device';

  @override
  String get previewKeysPages => '← → pages';

  @override
  String get previewKeysPhotos => '← → photos';

  @override
  String get meInitials => 'ME';

  @override
  String get threadSummary => 'Summary';

  @override
  String get signatureSheetTitle => 'Signature';

  @override
  String get signatureManage => 'Manage';

  @override
  String get signatureSheetNote =>
      'The signature switches automatically when you change the “From” account.';

  @override
  String get readerEmptyTitle => 'No conversation selected';

  @override
  String readerEmptyHint(String keys) {
    return 'Click a message to select it, or press $keys to select them all.';
  }

  @override
  String get hintMove => 'move';

  @override
  String get accountConnected => 'Account connected';

  @override
  String get accountConnectedLead =>
      'You can start reading now: the rest arrives while you use Piuma.';

  @override
  String get connectedDownloading => 'Downloading, newest first…';

  @override
  String get connectedUpToDate => 'Up to date';

  @override
  String get goToInbox => 'Go to inbox';

  @override
  String get addAnotherAccount => 'Add another account';

  @override
  String filterFrom(String name) {
    return 'From: $name';
  }

  @override
  String get syncLeftUnderMinute => 'under a minute';

  @override
  String syncLeftMinutes(int n) {
    return 'about $n min';
  }

  @override
  String syncLeftHours(int n) {
    return 'about $n h';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · $name syncing';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Send tomorrow $time';
  }

  @override
  String get sendOptions => 'Send options';

  @override
  String get inboxSections => 'Inbox sections';

  @override
  String get tabPeople => 'People';

  @override
  String get tabNotifications => 'Notifications';

  @override
  String get zoneNothingNew => 'Nothing new';

  @override
  String get tabAll => 'All';

  @override
  String get filterUnreadHint => 'Only emails with something unread';

  @override
  String get moveToPeople => 'Move to People';

  @override
  String movedToPeople(String sender) {
    return '$sender goes to People from now on';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender goes to Notifications from now on';
  }

  @override
  String get moveToNotifications => 'Move to Notifications';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count unread';
  }

  @override
  String get templatesTitle => 'Templates';

  @override
  String get templatesSearch => 'Search templates';

  @override
  String templatesFound(int found, int total) {
    return '$found of $total';
  }

  @override
  String get templatesNone => 'No templates yet. Save what you write as one.';

  @override
  String templatesNoMatch(String query) {
    return 'No template called “$query”';
  }

  @override
  String get templateSaveThis => 'Save as template';

  @override
  String get templatesManage => 'Manage';

  @override
  String get templateUntitled => 'Untitled template';

  @override
  String templateSavedNote(String name) {
    return 'Saved as template “$name”';
  }

  @override
  String get templatesSubtitle => 'On this device, for every account';

  @override
  String get templatesNew => 'New template';

  @override
  String get templateNameLabel => 'Name';

  @override
  String get templateTextLabel => 'Text';

  @override
  String templateSubjectLine(String subject) {
    return 'Subject: $subject';
  }

  @override
  String get templateNoSubject => 'No subject';

  @override
  String get templateSavedAsYouType => 'Saved as you type';

  @override
  String get templateNotSaved => 'The template could not be saved';

  @override
  String get accountNameLabel => 'Name';

  @override
  String get accountDisplayName => 'Display name';

  @override
  String get accountDisplayNameNone => 'Not set';

  @override
  String get accountDefaultSignature => 'Default signature';

  @override
  String get accountConnection => 'Connection';

  @override
  String accountWorkingAgo(String ago) {
    return 'Working · checked $ago';
  }

  @override
  String get accountJustNow => 'just now';

  @override
  String accountMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String accountAtTime(String time) {
    return 'at $time';
  }

  @override
  String get accountConnecting => 'Connecting…';

  @override
  String accountCantSignInSince(String time) {
    return 'Can\'t sign in since $time';
  }

  @override
  String get accountPasswordRefused =>
      'The server refused the password. Did it change?';

  @override
  String get accountEditServers => 'Edit servers';

  @override
  String get accountSignInAlert => 'Tell me when it can\'t sign in';

  @override
  String get accountSignInAlertNote =>
      'One notice, the first time the password is refused';

  @override
  String get accountRemove => 'Remove account';

  @override
  String accountRemoveTitle(String name) {
    return 'Remove $name from this device?';
  }

  @override
  String get accountRemoveNote =>
      'Its mail here is deleted. On the server everything stays as it is.';

  @override
  String get accountRemoveConfirm => 'Remove';

  @override
  String get accountServersTitle => 'Servers';

  @override
  String get accountServersSave => 'Save';

  @override
  String get accountServersChecking => 'Checking…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name can\'t sign in';
  }

  @override
  String get orStartFrom => 'Or start from';

  @override
  String needsAppPassword(String provider) {
    return '$provider needs an app password';
  }

  @override
  String get fastmailNeedsToken => 'Fastmail needs an API token';

  @override
  String get gmailStep1 =>
      'Turn on 2-Step Verification in your Google Account.';

  @override
  String get gmailStep2 => 'Open App passwords and create one named “Piuma”.';

  @override
  String get gmailStep3 => 'Paste the 16 letters here.';

  @override
  String get openAppPasswords => 'Open App passwords';

  @override
  String get icloudStep1 =>
      'Turn on two-factor authentication for your Apple Account.';

  @override
  String get icloudStep2 =>
      'In Sign-In and Security, open App-Specific Passwords and create one named “Piuma”.';

  @override
  String get icloudStep3 => 'Paste it here.';

  @override
  String get openAppleAccount => 'Open Apple Account';

  @override
  String get fastmailStep1 =>
      'In Settings, open Privacy & Security, then Manage API tokens.';

  @override
  String get fastmailStep2 =>
      'Create a token named “Piuma” with access to Email and Email submission.';

  @override
  String get fastmailStep3 => 'Paste it here.';

  @override
  String get openApiTokens => 'Open API tokens';

  @override
  String get appPassword => 'App password';

  @override
  String get apiToken => 'API token';

  @override
  String get pecWhichProvider => 'Who runs your PEC?';

  @override
  String get pecWhichProviderHint =>
      'Certified mail comes with the servers of its provider.';

  @override
  String signInToPec(String provider) {
    return 'Sign in to $provider';
  }

  @override
  String get pecStep1 => 'Use the full PEC address.';

  @override
  String get pecStep2 =>
      'Use the mailbox password, the one you use for webmail.';

  @override
  String get verifiedSenderSetting => 'Show verified sender';

  @override
  String get verifiedSenderSettingHint =>
      'Marks senders your mail server checked with DKIM, SPF and DMARC.';

  @override
  String get verifiedBadge => 'Verified';

  @override
  String get verifiedSenderLabel => 'Verified sender';

  @override
  String get ruleFieldBody => 'the body';

  @override
  String get newFolder => 'New folder';

  @override
  String get newFolderName => 'New folder name';

  @override
  String get create => 'Create';

  @override
  String get newFolderFailed =>
      'The server didn\'t make the folder. Try another name.';

  @override
  String get groupsTitle => 'Groups';

  @override
  String get groupsSubtitle =>
      'Bring together addresses from different accounts and domains. Each group has its own color, its own signature and, if you like, its own Inbox.';

  @override
  String get groupsNone =>
      'No groups yet. A group gathers addresses, even from different accounts, under one color and one signature.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count addresses',
      one: '1 address',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Signature';

  @override
  String get groupSendFromShort => 'Send from';

  @override
  String get groupNoSignature => 'None';

  @override
  String get groupName => 'Group name';

  @override
  String get groupColor => 'Group color';

  @override
  String get groupAddressesHeading => 'Addresses';

  @override
  String get groupAccount => 'Account';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return '$name account';
  }

  @override
  String groupAliasNote(String email) {
    return 'on $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return 'Remove $email from the group';
  }

  @override
  String get groupAddAddress => 'Add address';

  @override
  String get groupDefaultSignature => 'Default signature';

  @override
  String get groupSendFrom => 'Send new emails from';

  @override
  String get groupSeparateInbox => 'Separate Inbox';

  @override
  String get groupSeparateOn =>
      'Gets its own item in the sidebar. Also stays in the Unified inbox.';

  @override
  String get groupSeparateOff => 'Its emails live only in the Unified inbox.';

  @override
  String get groupNotifyOn => 'Follows your Notifications rules.';

  @override
  String get groupNotifyOff => 'No alerts for this group.';

  @override
  String get groupReplyAsWritten =>
      'Always reply from the address they wrote to';

  @override
  String groupReplyOn(String email) {
    return 'If someone writes to $email, your reply goes from $email, with that group\'s signature.';
  }

  @override
  String get groupReplyOnAny =>
      'If someone writes to one of your aliases, your reply goes from it, with its group\'s signature.';

  @override
  String get groupReplyOff => 'Replies go from the group\'s default address.';

  @override
  String get groupNew => 'New group';

  @override
  String get groupNewName => 'New group';

  @override
  String get groupDelete => 'Delete group';

  @override
  String groupDeleteAsk(String name) {
    return 'Delete $name?';
  }

  @override
  String get groupDeleteNote =>
      'Its addresses stay on their accounts; only the group goes.';

  @override
  String get groupYourAddresses => 'Your addresses';

  @override
  String get groupMovesHere => 'In another group: moves here';

  @override
  String get groupFoundInSent => 'Found in your sent mail';

  @override
  String get groupNewAlias => 'New alias';

  @override
  String get groupNewAliasHint => 'name@domain.com';

  @override
  String get groupAliasOn => 'on';

  @override
  String get groupAddAlias => 'Add';

  @override
  String get groupAliasInvalid => 'That doesn\'t look like an email address.';

  @override
  String get fromAutomatic => 'Automatic';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Chosen because $name wrote to $email';
  }

  @override
  String rowWrittenTo(String email) {
    return 'to $email';
  }

  @override
  String get groupsAll => 'All groups';

  @override
  String groupExpand(String name) {
    return 'Expand $name';
  }

  @override
  String groupCollapse(String name) {
    return 'Collapse $name';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses addresses',
      one: '1 address',
    );
    return '$_temp0 · $unread unread';
  }

  @override
  String groupsAllLine(int groups, int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groups',
      one: '1 group',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses addresses',
      one: '1 address',
    );
    return '$_temp0 · $_temp1 · $unread unread';
  }

  @override
  String groupOnly(String email) {
    return 'Only $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Only $email. Show the whole group';
  }

  @override
  String get groupSheetTitle => 'Show';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses addresses',
      one: '1 address',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groups',
      one: '1 group',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get groupSheetLabel => 'Choose group';

  @override
  String get groupManage => 'Manage groups';

  @override
  String get groupTitleAll => 'Group: all. Change group';

  @override
  String groupTitleOne(String name) {
    return 'Group: $name. Change group';
  }

  @override
  String get syncTitle => 'Devices & sync';

  @override
  String get syncSubtitle =>
      'Your settings on every device, end-to-end encrypted';

  @override
  String get syncOff => 'Off · this device only';

  @override
  String get syncOffBody =>
      'Keep your accounts, groups, signatures and settings on every device. They are encrypted here and stored in a hidden folder of one of your mailboxes. No server.';

  @override
  String get syncOffNote => 'Passwords travel only inside the encrypted copy.';

  @override
  String get syncStoreIn => 'Store it in';

  @override
  String get syncMailbox => 'Sync mailbox';

  @override
  String get syncMoving => 'Moving…';

  @override
  String get syncFailTaken => 'That mailbox already holds another sync space.';

  @override
  String get syncTurnOn => 'Turn on sync';

  @override
  String get syncAllSynced => 'All synced';

  @override
  String get syncNotYet => 'Not synced yet';

  @override
  String syncOnBody(String name) {
    return 'Accounts, groups, signatures and settings are encrypted and stored in your $name mailbox. No server.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · hidden folder · end-to-end encrypted';
  }

  @override
  String get syncDevices => 'Linked devices';

  @override
  String get syncThisDevice => 'This device';

  @override
  String get syncActiveNow => 'Active now';

  @override
  String syncActive(String ago) {
    return 'Active $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'yesterday';

  @override
  String syncDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get syncUnlink => 'Unlink';

  @override
  String syncUnlinkName(String name) {
    return 'Unlink $name';
  }

  @override
  String syncUnlinkAsk(String name) {
    return 'Unlink $name?';
  }

  @override
  String get syncUnlinkNote =>
      'It keeps what it has now but won\'t get changes any more. Your recovery phrase changes too: you\'ll write down the new one.';

  @override
  String get syncLinkNew => 'Link a new device';

  @override
  String syncLinkBody(String email) {
    return 'On the new device, open Piuma, choose “I already use Piuma on another device” and sign in to $email. It shows 6 digits, and this device asks for them.';
  }

  @override
  String get syncLinkWaiting => 'Waiting for the new device…';

  @override
  String get syncLinkScan =>
      'On the new phone, open Piuma, choose “I already use Piuma on another device” and scan this code.';

  @override
  String get syncLinkQrLabel => 'QR code to link a new device';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · new code in $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return 'No camera? Sign in to $email on the new device: it shows 6 digits, and this device asks for them.';
  }

  @override
  String syncLinked(String name) {
    return '$name linked';
  }

  @override
  String get syncPhraseRow => 'Recovery phrase';

  @override
  String get syncPhraseRowLine => 'Opens your space if every device is lost';

  @override
  String get syncShow => 'Show';

  @override
  String get syncPhraseTitle => 'Your recovery phrase';

  @override
  String get syncPhraseBody =>
      'If you lose every device, these 24 words are the only way back into your space. Write them on paper and keep them safe. Piuma can\'t recover them for you.';

  @override
  String get syncPhraseNewTitle => 'Your new recovery phrase';

  @override
  String syncPhraseNewBody(String name) {
    return '$name can\'t open your space any more, and the old phrase no longer works. Write these 24 words on paper instead.';
  }

  @override
  String get syncPhraseWarn => 'Anyone with these words can read your space.';

  @override
  String get syncPhraseDone => 'I wrote them down';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'New phone wants to connect',
      'tablet': 'New tablet wants to connect',
      'other': 'New computer wants to connect',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · asked $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Enter the 6 digits the phone shows.',
      'tablet': 'Enter the 6 digits the tablet shows.',
      'other': 'Enter the 6 digits the computer shows.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'The 6 digits';

  @override
  String get syncNotMe => 'Not me';

  @override
  String get syncApprove => 'Approve';

  @override
  String get syncApproving => 'Approving…';

  @override
  String syncFailOffline(String email) {
    return 'Couldn\'t reach $email. Try again when you\'re online.';
  }

  @override
  String get syncFailExpired =>
      'The request expired. Ask again from the new device.';

  @override
  String get syncFailOther => 'Something went wrong. Try again.';

  @override
  String get syncRowOn => 'On';

  @override
  String get syncRowOff => 'Off';

  @override
  String get pairAlready => 'I already use Piuma on another device';

  @override
  String get pairAlreadyOn =>
      'Sign in to one of your mailboxes. If it holds your space, you\'ll link this device next.';

  @override
  String get pairLinkTitle => 'Link this phone';

  @override
  String get pairLinkBody =>
      'On your computer, open Settings › Devices & sync › Link a new device, then scan the code it shows.';

  @override
  String get pairScan => 'Scan code';

  @override
  String get pairSignInInstead => 'Sign in instead';

  @override
  String get pairScanHint => 'Point at the code on your computer';

  @override
  String get pairScanWhere => 'Settings › Devices & sync › Link a new device';

  @override
  String get pairNoCamera =>
      'Piuma can\'t use the camera. Allow it in the system settings, or sign in instead.';

  @override
  String get pairLastStep => 'One last step';

  @override
  String get pairLastStepBody =>
      'Sign in to the mailbox that holds your space. The other accounts come over on their own.';

  @override
  String get pairConfirmsOwn =>
      'Your computer confirms on its own: it showed you the code.';

  @override
  String get pairLink => 'Link';

  @override
  String get pairLinking => 'Linking…';

  @override
  String get pairFoundTitle => 'We found your space';

  @override
  String pairFoundBody(String email) {
    return 'The $email mailbox holds an encrypted copy of your settings. Only your devices can read it.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'accounts',
      one: 'account',
    );
    return '$_temp0';
  }

  @override
  String pairGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'groups',
      one: 'group',
    );
    return '$_temp0';
  }

  @override
  String pairSignatures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'signatures',
      one: 'signature',
    );
    return '$_temp0';
  }

  @override
  String pairEncrypted(String when) {
    return 'End-to-end encrypted · updated $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'For security, confirm from a device that\'s already paired: $name, active $ago.';
  }

  @override
  String get pairShowCode => 'Show code';

  @override
  String get pairUsePhrase => 'Use recovery phrase';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Confirm on your phone',
      'tablet': 'Confirm on your tablet',
      'other': 'Confirm on your computer',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Open Piuma on $name and enter the code.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Code $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Expires in $time';
  }

  @override
  String pairWaiting(String name) {
    return 'Waiting for $name to confirm…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name will show “$title”';
  }

  @override
  String get pairStep2 => 'Enter the 6 digits and tap Approve';

  @override
  String get pairExpired => 'The code expired.';

  @override
  String pairRefused(String name) {
    return '$name said this wasn\'t you.';
  }

  @override
  String get pairWrongCode => 'The code typed there wasn\'t this one.';

  @override
  String get pairNewCode => 'Show a new code';

  @override
  String get pairPhraseTitle => 'Recovery phrase';

  @override
  String get pairPhraseBody =>
      'Type the 24 words you wrote down, in order, with spaces between them.';

  @override
  String pairPhraseCount(int count) {
    return '$count of 24 words';
  }

  @override
  String get pairPhraseWrong =>
      'These words don\'t open your space. Check them and try again.';

  @override
  String get pairContinue => 'Continue';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Phone paired',
      'tablet': 'Tablet paired',
      'other': 'Computer paired',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody =>
      'Here\'s what came over from your encrypted space.';

  @override
  String get pairDoneAccounts => 'Accounts';

  @override
  String get pairDoneGroups => 'Groups';

  @override
  String get pairDoneSettings => 'Signatures and settings synced';

  @override
  String get pairSynced => 'Synced';

  @override
  String pairStepOf(int step) {
    return 'Step $step of 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'today at $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'yesterday at $time';
  }

  @override
  String pairOnDay(String day) {
    return 'on $day';
  }

  @override
  String get keyOpenWindow => 'open in new window';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synced on $count devices',
      one: 'Synced on 1 device',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters =>
      'When a newsletter was read more than 7 days ago';

  @override
  String get ruleBuiltIn => 'Built in · every account';

  @override
  String get syncTurnOff => 'Turn off sync on this device';

  @override
  String get syncTurnOffAsk => 'Turn off sync on this device?';

  @override
  String syncTurnOffOne(String name) {
    return 'This device leaves your space and stops getting changes. Its accounts and mail stay here. $name keeps syncing.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'This device leaves your space and stops getting changes. Its accounts and mail stay here. $names keep syncing.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'This device leaves your space and stops getting changes. Its accounts and mail stay here. This is your only device: the encrypted copy in $email is deleted too.';
  }

  @override
  String get syncTurnOffButton => 'Turn off sync';

  @override
  String get listAnd => 'and';

  @override
  String get composeDropFiles => 'Drop to attach';

  @override
  String get serverType => 'Server type';

  @override
  String get imapAndSmtp => 'IMAP and SMTP';

  @override
  String get jmapServer => 'JMAP server';

  @override
  String get jmapServerHint =>
      'The server\'s name, or the full address of its JMAP session.';

  @override
  String get jmapSignsIn =>
      'One server reads, sends and brings new mail at once. You sign in with your address.';

  @override
  String get shortcutsTitle => 'Shortcuts';

  @override
  String shortcutsLine(String keys) {
    return 'Just the essentials. Everything else is in $keys.';
  }

  @override
  String get shortcutsTable => 'Keyboard shortcuts';

  @override
  String get shortcutPalette => 'Command palette';

  @override
  String ruleSuggest(String name, String folder) {
    return 'You often move emails from $name to $folder. Create a rule?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Suggested on-device · $count moves in the last month',
      one: 'Suggested on-device · 1 move in the last month',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Forward';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Forwarded message ----------\nFrom: $from\nDate: $date\nTo: $to\nSubject: $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date at $time';
  }

  @override
  String get folderWaiting => 'Waiting';

  @override
  String waitingSummary(int count) {
    return '$count sent · no reply yet';
  }

  @override
  String get waitingNoReply => 'No reply yet';

  @override
  String get waitingTo => 'To ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'today';

  @override
  String get waitingYesterday => 'yesterday';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sent emails waiting for a reply',
      one: '1 sent email waiting for a reply',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Write again';

  @override
  String get stopWaiting => 'Stop waiting';

  @override
  String get stoppedWaiting => 'Out of Waiting. It stays in Sent.';

  @override
  String get remindMe => 'Remind me';

  @override
  String get remindTitle => 'Remind me if nobody replies';

  @override
  String get remindTomorrow => 'Tomorrow';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count days',
      one: 'In 1 day',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'Next week';

  @override
  String get remindPickDate => 'Pick a date…';

  @override
  String get remindNever => 'Don’t remind me';

  @override
  String remindChipToday(String time) {
    return 'Remind me at $time';
  }

  @override
  String get remindChipTomorrow => 'Remind me tomorrow';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remind me in $count days',
      one: 'Remind me in 1 day',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Remind me on $date';
  }

  @override
  String remindAt(String when) {
    return 'Remind me $when';
  }

  @override
  String remindNoReply(String name) {
    return 'No reply from $name';
  }

  @override
  String get remindSentToday => 'sent today';

  @override
  String get remindSentYesterday => 'sent yesterday';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sent $count days ago',
      one: 'sent 1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Shared attachments';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments',
      one: '1 attachment',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles => 'No attachments from them yet.';

  @override
  String get senderAddresses => 'Addresses';

  @override
  String senderAddressNote(String account, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$account · $_temp0';
  }

  @override
  String get senderCopyAddress => 'Copy address';

  @override
  String get senderRules => 'Rules & folders';

  @override
  String get senderContent => 'Sender content';

  @override
  String folderReorder(String name) {
    return 'Drag to reorder $name';
  }

  @override
  String get folderMoveUp => 'Move up';

  @override
  String get folderMoveDown => 'Move down';

  @override
  String get ruleUnopenedNewsletters => 'Newsletters';

  @override
  String get ruleUnopenedFor => ' unopened for ';

  @override
  String get ruleUnopenedDays => '30 days';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails archived',
      one: '1 email archived',
      zero: 'every account',
    );
    return 'Nightly · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'Rules run on this device and sync across all your devices';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'Rules run on this device and sync across all your devices · updated $ago';
  }

  @override
  String get calSynced =>
      'Connections sync across all your devices; passwords travel encrypted and stay in the system keychain.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'updates every $count hours',
      one: 'updates every hour',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'updates every $count days',
      one: 'updates daily',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'updates weekly';

  @override
  String get showOriginalLayout => 'Show original layout';

  @override
  String get originalLayout => 'Original layout';

  @override
  String get originalLayoutBar =>
      'Original layout · images and links follow your privacy settings';

  @override
  String get backToReadingView => 'Back to reading view';

  @override
  String get readingView => 'Reading view';

  @override
  String get replyFromLabel => 'Reply from';

  @override
  String replyFromSignature(String name) {
    return 'signature $name';
  }

  @override
  String get noticeReplyHint => 'Write a reply…';

  @override
  String get labelsHeading => 'Labels';

  @override
  String get labelsSection => 'LABELS';

  @override
  String get labelAction => 'Label';

  @override
  String get labelAdd => '+ Label';

  @override
  String get labelNew => 'New label';

  @override
  String get labelFind => 'Find or create a label';

  @override
  String labelCreate(String name) {
    return 'Create “$name”';
  }

  @override
  String labelRemove(String name) {
    return 'Remove the label $name';
  }

  @override
  String labelEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String labelAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account keeps no labels on the server, so its labels stay on this device.';
  }

  @override
  String get hintLabel => 'label';

  @override
  String get labelName => 'Label name';

  @override
  String get labelEdit => 'Edit label';

  @override
  String get labelSave => 'Save';

  @override
  String get labelCreateButton => 'Create';

  @override
  String get labelDelete => 'Delete label';

  @override
  String get labelDeleteNote =>
      'It comes off every email; the emails stay where they are.';

  @override
  String get labelColorAmber => 'Amber';

  @override
  String get labelColorTeal => 'Teal';

  @override
  String get labelColorCoral => 'Coral';

  @override
  String get labelColorBlue => 'Blue';

  @override
  String get labelColorViolet => 'Violet';

  @override
  String get labelMenu => 'Label…';

  @override
  String get ruleDoLabel => 'label';

  @override
  String get ruleTrayLabel => 'Label';

  @override
  String get rulePickLabel => 'a label';

  @override
  String get ruleNoLabels =>
      'No labels yet: make one with + Label under Folders & labels.';

  @override
  String get foldersAndLabelsHeading => 'Folders & labels';

  @override
  String get labelsCardTitle => 'Labels';

  @override
  String get labelsCardDetail => 'shared across all accounts';

  @override
  String get labelsNone => 'No labels yet.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count labels',
      one: '1 label',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Sender pictures';

  @override
  String get senderPicturesSettingHint =>
      'Photos from your contacts and verified company logos in place of the letters.';

  @override
  String get websiteIconsSetting => 'Website icons';

  @override
  String get websiteIconsSettingHint =>
      'For companies without a logo. Each website sees your IP address once.';

  @override
  String tabletInboxUnread(int count) {
    return 'Inbox, $count unread';
  }

  @override
  String tabletAccount(String name, String email) {
    return '$name account, $email';
  }

  @override
  String get tabletSearch => 'Search mail';

  @override
  String get tabletSearchHint => 'Search or run a command';

  @override
  String get vaultTrackParcel => 'Track parcel';

  @override
  String get vaultTrackingCopied => 'Tracking number copied';

  @override
  String get vaultNeedsYou => 'Needs you';

  @override
  String get vaultNext => 'Next';

  @override
  String get vaultOnTheWay => 'On the way';

  @override
  String get vaultEverything => 'Everything';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count things need you',
      one: '1 thing needs you',
    );
    return '$_temp0';
  }

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'a flight today',
      'train': 'a train today',
      'ferry': 'a ferry today',
      'bus': 'a bus today',
      'stay': 'a check-in today',
      'parking': 'parking today',
      'car': 'a hired car today',
      'event': 'an event today',
      'table': 'a table today',
      'other': 'a booking today',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Flight',
      'train': 'Train',
      'ferry': 'Ferry',
      'bus': 'Bus',
      'stay': 'Check-in',
      'parking': 'Parking',
      'car': 'Car hire',
      'event': 'Event',
      'table': 'Table',
      'other': 'Booking',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Parcels';

  @override
  String get vaultCatSpending => 'Spending';

  @override
  String get vaultCatTrips => 'Trips';

  @override
  String get vaultCatSales => 'Sales';

  @override
  String get vaultCatSubscriptions => 'Subscriptions';

  @override
  String get vaultCatReturns => 'Returns & warranty';

  @override
  String get vaultCatDeadlines => 'Deadlines';

  @override
  String get vaultCatBookings => 'Bookings';

  @override
  String get vaultCatVouchers => 'Gift cards & codes';

  @override
  String get vaultCatDocuments => 'Documents';

  @override
  String get vaultCatCertified => 'Certified mail';

  @override
  String vaultOnWayCount(int count) {
    return '$count on the way';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count to pick up';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count delivered',
      one: '1 delivered',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'On a trip now';

  @override
  String vaultNextWhen(String when) {
    return 'Next: $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count past trips',
      one: '1 past trip',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count to ship';
  }

  @override
  String vaultSoldCount(int count) {
    return '$count sold';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money a month';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plans',
      one: '1 plan',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count returns, first until $day',
      one: '1 return until $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count under warranty';
  }

  @override
  String vaultCodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes',
      one: '1 code',
    );
    return '$_temp0';
  }

  @override
  String vaultCountMoney(int count, String money) {
    return '$count · $money';
  }

  @override
  String vaultCertDelivered(int count) {
    return '$count delivered';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Payment failed · $who';
  }

  @override
  String get vaultPaymentFailed => 'Payment failed';

  @override
  String vaultWasDue(String when) {
    return 'Was due $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'Ship by $when';
  }

  @override
  String get vaultToShip => 'To ship';

  @override
  String get vaultYouSend => 'You send';

  @override
  String vaultSoldOn(String where) {
    return 'sold on $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'Pick up by $when';
  }

  @override
  String get vaultReadyPickup => 'Ready to pick up';

  @override
  String vaultRenewsWhen(String when) {
    return 'Renews $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Ends $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money a week',
      'month': '$money a month',
      'year': '$money a year',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'since $day';
  }

  @override
  String get vaultUpdatePayment => 'Update payment';

  @override
  String get vaultCoach => 'Coach';

  @override
  String get vaultTicket => 'Ticket';

  @override
  String vaultInHours(int hours) {
    return 'in $hours h';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'in $minutes min';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parcels delivered this week',
      one: '1 parcel delivered this week',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Spent in $month';
  }

  @override
  String vaultReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts',
      one: '1 receipt',
    );
    return '$_temp0';
  }

  @override
  String get vaultExportMonth => 'Export month';

  @override
  String vaultSpentTab(String money) {
    return 'Spent · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Money in · $money';
  }

  @override
  String vaultVia(String service) {
    return 'via $service';
  }

  @override
  String get vaultSpendingNote => 'Read on-device from receipts and invoices';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file and $count PDFs saved in Downloads',
      one: '$file and 1 PDF saved in Downloads',
      zero: '$file saved in Downloads',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'Couldn’t export the month';

  @override
  String get vaultPrevMonth => 'Previous month';

  @override
  String get vaultNextMonth => 'Next month';

  @override
  String get vaultNothingThisMonth => 'No receipts this month.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Subscriptions · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Date,Who,What,Amount,Currency,Paid via,File,VAT number';

  @override
  String vaultComingUp(int count) {
    return '$count coming up';
  }

  @override
  String get vaultNoTrips => 'No trips ahead';

  @override
  String get vaultPastTrips => 'Past trips';

  @override
  String vaultThisYear(int count) {
    return '$count this year';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'Now · back $when';
  }

  @override
  String get vaultLegDone => 'Done';

  @override
  String vaultUntilTime(String time) {
    return 'Until $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Until $day';
  }

  @override
  String get vaultTripsNote =>
      'Trains, ferries, flights, stays, parking and tickets';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nights',
      one: '1 night',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'from $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'coach $coach, seat $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'seat $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'code $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Flight $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Sold on $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Sold on $who';
  }

  @override
  String get vaultSaleOnWay => 'On its way';

  @override
  String get vaultSaleReceived => 'Received';

  @override
  String get vaultPaidOut => 'Paid out';

  @override
  String get vaultCanGoBack => 'Can still go back';

  @override
  String get vaultUnderWarranty => 'Under warranty';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days days to return';
  }

  @override
  String vaultBought(String day) {
    return 'bought $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Warranty $month';
  }

  @override
  String get vaultCodeCopied => 'Code copied';

  @override
  String get vaultCopyCode => 'Copy code';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Payslip',
      'statement': 'Statement',
      'tax': 'Tax form',
      'contract': 'Contract',
      'other': 'Document',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Open file';

  @override
  String vaultBookingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bookings',
      one: '1 booking',
    );
    return '$_temp0';
  }

  @override
  String vaultDocumentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documents',
      one: '1 document',
    );
    return '$_temp0';
  }

  @override
  String get vaultCategoryEmpty => 'Nothing here right now.';

  @override
  String get vaultFlagged => 'needs you';

  @override
  String get suggestWroteTo => 'Wrote to';

  @override
  String get suggestWroteToYou => 'Wrote to you';

  @override
  String get readerEmptyTap => 'Tap a message to read it.';

  @override
  String get noticeAwayTitle => 'While you were away';

  @override
  String noticeAwayEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String noticeAwayPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count from people',
      one: '1 from a person',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Weekends, all day';

  @override
  String get quietWeekendsHint => 'Saturday and Sunday';

  @override
  String get quietWhile => 'While quiet';

  @override
  String get quietWhileHint => 'No notices sums up at the end';

  @override
  String get quietNoSound => 'No sound';

  @override
  String get quietNoNotices => 'No notices';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · rings as usual';
  }

  @override
  String get quietAccountsHint =>
      'Accounts switched off ring as usual in the quiet hours.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'Arabic',
      'bg': 'Bulgarian',
      'ca': 'Catalan',
      'cs': 'Czech',
      'zh': 'Chinese',
      'da': 'Danish',
      'de': 'German',
      'el': 'Greek',
      'en': 'English',
      'et': 'Estonian',
      'fi': 'Finnish',
      'fr': 'French',
      'he': 'Hebrew',
      'hi': 'Hindi',
      'hr': 'Croatian',
      'hu': 'Hungarian',
      'id': 'Indonesian',
      'it': 'Italian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'lt': 'Lithuanian',
      'lv': 'Latvian',
      'nl': 'Dutch',
      'nb': 'Norwegian',
      'pl': 'Polish',
      'pt': 'Portuguese',
      'ro': 'Romanian',
      'ru': 'Russian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'es': 'Spanish',
      'sr': 'Serbian',
      'sv': 'Swedish',
      'th': 'Thai',
      'tr': 'Turkish',
      'uk': 'Ukrainian',
      'vi': 'Vietnamese',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Written in $language';
  }

  @override
  String get translateAction => 'Translate';

  @override
  String translateGetting(String from, String to) {
    return 'Getting $from–$to';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return 'Getting $from–$to · $size';
  }

  @override
  String get translating => 'Translating…';

  @override
  String translatedFrom(String language) {
    return 'Translated from $language · on this device';
  }

  @override
  String get translatedShort => 'Translated';

  @override
  String get translateShowOriginal => 'Show original';

  @override
  String get translateOriginalShort => 'Original';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'To translate, download $from and $to first.';
  }

  @override
  String get translateFailed => 'Couldn’t translate this email. Try again.';

  @override
  String get appearanceTranslateInto => 'Translate into';

  @override
  String get translateIntoApp => 'App language';

  @override
  String get translateIntoHint =>
      'Emails in other languages offer Translate. It happens on this device.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Remove';

  @override
  String translateRemovePair(String pair) {
    return 'Remove $pair';
  }

  @override
  String get printEmail => 'Print…';

  @override
  String printTooltip(String keys) {
    return 'Print… $keys';
  }

  @override
  String get printOrSavePdf => 'Print or save as PDF';

  @override
  String get reportSpam => 'Report spam';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations reported as spam',
      one: 'Reported as spam',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'Not spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations moved to Inbox',
      one: 'Moved to Inbox',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Date';

  @override
  String printAttachments(String files) {
    return 'Attachments: $files';
  }

  @override
  String get helpTitle => 'Help & feedback';

  @override
  String get helpSubtitle =>
      'Report a problem or suggest an idea. Nothing is sent without you.';

  @override
  String get reportProblem => 'Report a problem';

  @override
  String get reportThisProblem => 'Report this problem';

  @override
  String get reportCantAddAccount => 'Can’t add my account';

  @override
  String get suggestIdea => 'Suggest an idea';

  @override
  String get shakeToReport => 'Shake to report';

  @override
  String get shakeToReportHint => 'Shake the phone on any screen';

  @override
  String get yourReports => 'Your reports';

  @override
  String get reportNone => 'No reports yet.';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportKindProblem => 'Problem';

  @override
  String get reportKindIdea => 'Idea';

  @override
  String get reportTitleField => 'Title';

  @override
  String get reportTitleHint => 'In a few words';

  @override
  String get reportProblemField => 'What happened';

  @override
  String get reportIdeaField => 'What and why';

  @override
  String get reportDescriptionHint => 'What you did, and what you expected';

  @override
  String get reportScreenshot => 'Screenshot of this screen';

  @override
  String get reportScreenshotWindow => 'Screenshot of this window';

  @override
  String get reportScreenshotOff => 'Off: it may show your mail';

  @override
  String get reportScreenshotOn => 'Tap the picture to hide parts';

  @override
  String get reportLog => 'App log';

  @override
  String get reportLogHint => 'No addresses or subjects';

  @override
  String get reportDevice => 'Device and app info';

  @override
  String get reportDeviceHint => 'Version, model, language';

  @override
  String get reportAlways => 'Always';

  @override
  String get reportSeeSent => 'See what\'s sent';

  @override
  String get reportSend => 'Send';

  @override
  String get reportQueued => 'Report queued';

  @override
  String get reportNotKept => 'Couldn\'t keep the report';

  @override
  String get reportWhatsSent => 'What\'s sent';

  @override
  String get reportSectionReport => 'Report';

  @override
  String get reportSectionDevice => 'Device';

  @override
  String get reportSectionScreenshot => 'Screenshot';

  @override
  String get reportHideParts => 'Hide parts';

  @override
  String get reportDragToBlur => 'Drag to blur';

  @override
  String get reportDone => 'Done';

  @override
  String get reportStatusQueued => 'Queued';

  @override
  String get reportStatusSending => 'Sending';

  @override
  String get reportStatusFailed => 'Failed';

  @override
  String get reportStatusEmailed => 'Emailed';

  @override
  String get reportWaitOffline => 'waiting for a network';

  @override
  String get reportWaitTurn => 'goes in a moment';

  @override
  String reportWaitAt(String time) {
    return 'goes at $time';
  }

  @override
  String get reportWaitPaused => 'goes later today or tomorrow';

  @override
  String get reportTapRetry => 'tap to try again';

  @override
  String get reportTryAgain => 'Try again';

  @override
  String get reportByEmail => 'Send by email instead';

  @override
  String get reportDelete => 'Delete';

  @override
  String get reportOptions => 'Report options';

  @override
  String get crashLine => 'Piuma closed unexpectedly. Send a report?';

  @override
  String get crashReport => 'Report';

  @override
  String get crashDismiss => 'Dismiss';

  @override
  String reportStatusSent(int number) {
    return 'Sent #$number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines lines',
      one: '1 line',
    );
    return 'App log · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Help';

  @override
  String get awayTitle => 'Away message';

  @override
  String get awayNote => 'Replies for you, even with the app closed';

  @override
  String get awayFrom => 'From';

  @override
  String get awayToInline => 'to';

  @override
  String get awayTo => 'To';

  @override
  String get awaySubject => 'Subject';

  @override
  String get awayMessage => 'Message';

  @override
  String get awayEndsNote =>
      'Ends by itself after the last day. Leave \"to\" empty to keep it on until you turn it off.';

  @override
  String awaySubjectUntil(String date) {
    return 'Away until $date';
  }

  @override
  String get awaySubjectPlain => 'Away';

  @override
  String awayBodyUntil(String date) {
    return 'Hi, I\'m away until $date and will reply when I\'m back.';
  }

  @override
  String get awayBodyPlain => 'Hi, I\'m away and will reply when I\'m back.';

  @override
  String get awayToday => 'Today';

  @override
  String get awayNoEnd => 'No end';

  @override
  String get awayPickFrom => 'First day';

  @override
  String get awayPickTo => 'Last day';

  @override
  String get awayKeepOn => 'Keep it on until I turn it off';

  @override
  String get awayOtherFilters =>
      'Can\'t turn on alongside your existing filters. Turn them off on the server first.';

  @override
  String get awayUnsupported => 'This server no longer takes an away message.';

  @override
  String get awayOffline =>
      'Couldn\'t reach the server. Try again in a moment.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Away message on for $account until $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Away message on for $account';
  }

  @override
  String get awayTurnOff => 'Turn off';

  @override
  String get awayRowOff => 'Off';

  @override
  String get awayRowOn => 'On';

  @override
  String awayRowUntil(String date) {
    return 'On until $date';
  }

  @override
  String get featuresSubtitle =>
      'Turn off what you don\'t use. It goes away everywhere, and nothing is deleted.';

  @override
  String get featuresZones => 'Zones';

  @override
  String get featuresOnDevice => 'On this device';

  @override
  String get featuresOnDeviceNote => 'Nothing here ever leaves the device.';

  @override
  String get featureNewslettersHint =>
      'Newsletters in their own list, to read like a magazine';

  @override
  String get featureNewslettersOff =>
      'Off · newsletters arrive in the inbox like any email';

  @override
  String get featureVaultHint =>
      'Payments, parcels, trips and deadlines as cards';

  @override
  String get featureVaultOff =>
      'Off · these emails stay as they are, with no cards or notices';

  @override
  String get featureAttachmentsHint => 'Every file you received, in one place';

  @override
  String get featureAttachmentsOff =>
      'Off · files stay in their emails, and search still finds them';

  @override
  String get featureInShortHint =>
      'The gist of long conversations, above the first email';

  @override
  String get featureInShortOff =>
      'Off · conversations open without the summary';

  @override
  String get featureTranslate => 'Translate';

  @override
  String get featureTranslateHint =>
      'Offers to translate emails written in other languages';

  @override
  String get featureTranslateOff =>
      'Off · no offer to translate, and no language is downloaded';

  @override
  String get featureFoundDates => 'Dates in emails';

  @override
  String get featureFoundDatesHint =>
      'Add to calendar for dates and times found in the text';

  @override
  String get featureFoundDatesOff => 'Off · invites still show their card';

  @override
  String get nextEmail => 'Next email';

  @override
  String get previousEmail => 'Previous email';

  @override
  String get appearanceLanguage => 'Language';

  @override
  String get languageDevice => 'Device language';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain looks like $like, but it\'s a different address.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'The name says $brand, but the address is at $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'This email says it\'s from $domain, but $domain didn\'t send it.';
  }

  @override
  String get senderDetails => 'Details';

  @override
  String get senderDetailsTitle => 'What was checked';

  @override
  String get senderSentBy => 'Sent by';

  @override
  String get senderNotKnown => 'Not known';

  @override
  String get senderSignature => 'Signature';

  @override
  String get senderSignatureNone => 'None';

  @override
  String get senderDomainCheck => 'Domain check';

  @override
  String get senderDomainCheckFailed => 'Failed (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Looks like';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails from it',
      one: '1 email from it',
      zero: 'no emails from it',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'Name says';

  @override
  String get senderDetailsNote =>
      'Worked out on this device from what your mail server wrote. Links in this email ask before they open.';

  @override
  String impostorLinkBody(String real) {
    return 'This email may not be from who it says. The link goes to $real.';
  }

  @override
  String get updates => 'Updates';

  @override
  String get updatesVersion => 'Version';

  @override
  String get upToDate => 'Up to date';

  @override
  String get updatesAuto => 'Piuma looks for new versions on its own';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get checkedJustNow => 'Checked just now';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Checked $count minutes ago',
      one: 'Checked 1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Checked $count hours ago',
      one: 'Checked 1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Checked $count days ago',
      one: 'Checked yesterday',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Downloading $version · $percent%';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done of $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Ready · $version';
  }

  @override
  String get updateGoesInOnRestart => 'Goes in when Piuma restarts';

  @override
  String get restart => 'Restart';

  @override
  String get updateCouldntCheck => 'Couldn\'t check';

  @override
  String get tryAgain => 'Try again';

  @override
  String get seeWhatsNew => 'See what\'s new';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'Your mail and drafts are kept. Piuma closes and opens again in a few seconds.';

  @override
  String get restartNow => 'Restart now';

  @override
  String updateReadyLine(String version) {
    return 'Update ready · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Updated to $version';
  }

  @override
  String get swipeHintArchiveSnooze => 'Swipe right to archive, left to snooze';

  @override
  String get swipeHintArchive => 'Swipe right to archive';

  @override
  String get formatting => 'Formatting';

  @override
  String get formatBold => 'Bold';

  @override
  String get formatItalic => 'Italic';

  @override
  String get formatLink => 'Link';

  @override
  String get formatBullets => 'Bulleted list';

  @override
  String get formatNumbers => 'Numbered list';

  @override
  String get formatQuote => 'Quote';

  @override
  String get linkAddressHint => 'Paste or type an address';

  @override
  String get linkAdd => 'Add';

  @override
  String get linkRemove => 'Remove link';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images are off, so $sender can’t see when you open this.',
      one: '1 image is off, so $sender can’t see when you open this.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Load images';

  @override
  String get alwaysForSender => 'Always for this sender';

  @override
  String get cleanView => 'Clean view';

  @override
  String get viewOriginal => 'Original';

  @override
  String get viewClean => 'Clean';

  @override
  String get calGoogle => 'Google Calendar';

  @override
  String get calGoogleSub => 'Read events and availability with an iCal link';

  @override
  String get calGoogleLabel => 'Google Calendar iCal address';

  @override
  String get calGoogleHint =>
      'In Google Calendar on a computer: Settings › your calendar › Integrate calendar › Secret address in iCal format. Read-only; connects directly.';

  @override
  String get bundledReleaseNotes =>
      '## Mail, made light\n- Original email layouts with single-page scrolling and image controls\n- Formatting bar and full-editor switch in replies\n- Deliberate horizontal mail swipes\n- Sender warnings for brand impersonation and look-alike domains\n- Vault monthly CSV export with merchant VAT numbers';
}
