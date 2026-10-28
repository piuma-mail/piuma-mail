// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get catalogSubtitle => 'Komponentenkatalog · Phase 0';

  @override
  String get sectionColors => 'Farben';

  @override
  String get sectionTypography => 'Typografie';

  @override
  String get sectionButtons => 'Schaltflächen';

  @override
  String get sectionFilters => 'Filter';

  @override
  String get sectionMessageRows => 'Nachrichtenzeilen';

  @override
  String get colorBackground => 'Hintergrund';

  @override
  String get colorSurface => 'Fläche';

  @override
  String get colorText => 'Text';

  @override
  String get colorSecondary => 'Sekundär';

  @override
  String get colorAccent => 'Akzent';

  @override
  String get colorSoft => 'Sanft';

  @override
  String get colorSuccess => 'Erfolg';

  @override
  String get colorWarning => 'Warnung';

  @override
  String get colorDanger => 'Gefahr';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Titel';

  @override
  String get typeSubtitle => 'Untertitel';

  @override
  String get typeBody => 'Fließtext';

  @override
  String get typeSmall => 'Klein';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Senden';

  @override
  String get actionSnooze => 'Zurückstellen';

  @override
  String get actionReply => 'Antworten';

  @override
  String get actionDelete => 'Löschen';

  @override
  String get actionDisabled => 'Deaktiviert';

  @override
  String get filterUnread => 'Ungelesen';

  @override
  String get filterAttachments => 'Mit Anhängen';

  @override
  String get filterPeople => 'Nur Personen';

  @override
  String get messageUnread => 'Ungelesen';

  @override
  String get compose => 'Verfassen';

  @override
  String get unifiedInbox => 'Gemeinsamer Posteingang';

  @override
  String get accounts => 'Konten';

  @override
  String get addAccount => 'Konto hinzufügen';

  @override
  String get inbox => 'Posteingang';

  @override
  String downloading(String done, String total) {
    return '$done von $total werden geladen';
  }

  @override
  String get offline => 'Offline · neuer Versuch läuft';

  @override
  String get signInFailed => 'Ein Konto braucht erneut sein Passwort';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts Konten',
      one: '1 Konto',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread ungelesen',
      zero: 'alles gelesen',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Wähle eine Nachricht aus, um sie zu lesen.';

  @override
  String get noSubject => '(kein Betreff)';

  @override
  String get couldNotLoadMessage =>
      'Diese Nachricht konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut.';

  @override
  String get loading => 'Wird geladen…';

  @override
  String toYouToday(String time) {
    return 'an dich · heute um $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'an dich · gestern um $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'an dich · $date um $time';
  }

  @override
  String get sectionToday => 'Heute';

  @override
  String get sectionYesterday => 'Gestern';

  @override
  String get sectionThisWeek => 'Diese Woche';

  @override
  String get sectionThisMonth => 'Früher in diesem Monat';

  @override
  String get sectionOlder => 'Älter';

  @override
  String get defaultAccountName => 'Mail';

  @override
  String get emailAddress => 'E-Mail-Adresse';

  @override
  String get password => 'Passwort';

  @override
  String notificationNotices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hinweise',
      one: '1 Hinweis',
    );
    return '$_temp0';
  }

  @override
  String get show => 'Anzeigen';

  @override
  String get hide => 'Ausblenden';

  @override
  String get imapServer => 'IMAP-Server';

  @override
  String get port => 'Port';

  @override
  String get security => 'Sicherheit';

  @override
  String get accountName => 'Kontoname';

  @override
  String get accountColor => 'Kontofarbe';

  @override
  String get color => 'Farbe';

  @override
  String get connect => 'Verbinden';

  @override
  String get connecting => 'Verbindung wird hergestellt…';

  @override
  String get notNow => 'Nicht jetzt';

  @override
  String get enterToConnect => 'zum Verbinden';

  @override
  String get errorWrongPassword =>
      'Der Server hat diese Adresse und dieses Passwort nicht akzeptiert. Wenn dein Anbieter App-Passwörter nutzt, erstelle eines und verwende es hier.';

  @override
  String get errorUnreachable =>
      'Der Server war nicht erreichbar. Prüfe den Servernamen, den Port und deine Verbindung.';

  @override
  String get errorInsecure =>
      'Es konnte keine sichere Verbindung zum Server hergestellt werden. Prüfe den Servernamen und die Sicherheitseinstellung.';

  @override
  String get errorKeychain =>
      'Das Passwort konnte nicht im Schlüsselbund des Systems gespeichert werden.';

  @override
  String get errorOther =>
      'Beim Verbinden ist etwas schiefgelaufen. Versuche es erneut.';

  @override
  String get yourAccounts => 'Deine Konten';

  @override
  String get noAccountsYet => 'Dein erstes Konto erscheint hier.';

  @override
  String get connected => 'Verbunden';

  @override
  String get privacyNote =>
      'Deine E-Mails bleiben auf diesem Gerät. Wir verbinden uns direkt mit deinen Servern, ohne jemanden dazwischen.';

  @override
  String get newMessage => 'Neue Nachricht';

  @override
  String get close => 'Schließen';

  @override
  String get from => 'Von';

  @override
  String get to => 'An';

  @override
  String get cc => 'Cc';

  @override
  String get bcc => 'Bcc';

  @override
  String get ccBcc => 'Cc  Bcc';

  @override
  String get subject => 'Betreff';

  @override
  String get messageBody => 'Nachricht';

  @override
  String get addRecipient => 'Hinzufügen';

  @override
  String removeRecipient(String name) {
    return '$name entfernen';
  }

  @override
  String undoSendHint(int seconds) {
    return 'Du kannst das Senden $seconds Sekunden lang rückgängig machen';
  }

  @override
  String get sendNoRecipients => 'Füge mindestens einen Empfänger hinzu.';

  @override
  String sendBadAddress(String address) {
    return '„$address“ ist keine E-Mail-Adresse.';
  }

  @override
  String get sending => 'Wird gesendet…';

  @override
  String get sent => 'Gesendet';

  @override
  String get undo => 'Rückgängig';

  @override
  String get draftDiscarded => 'Entwurf verworfen';

  @override
  String get sendErrorPassword =>
      'Der Postausgangsserver hat das Passwort nicht akzeptiert. Deine Nachricht ist noch da.';

  @override
  String get sendErrorUnreachable =>
      'Der Postausgangsserver war nicht erreichbar. Deine Nachricht ist noch da.';

  @override
  String get sendErrorRejected =>
      'Der Postausgangsserver hat die Nachricht abgelehnt. Deine Nachricht ist noch da.';

  @override
  String get sendErrorOther =>
      'Die Nachricht konnte nicht gesendet werden. Deine Nachricht ist noch da.';

  @override
  String stepOf(int step, int total) {
    return '$step von $total';
  }

  @override
  String get whatsYourEmail => 'Wie lautet deine E-Mail-Adresse?';

  @override
  String get findSettingsHint => 'Wir suchen die Servereinstellungen für dich.';

  @override
  String get continueAction => 'Weiter';

  @override
  String get lookingUp => 'Wird gesucht…';

  @override
  String get setUpManually => 'Manuell einrichten';

  @override
  String get back => 'Zurück';

  @override
  String get weFoundSettings => 'Wir haben deine Einstellungen gefunden';

  @override
  String get incoming => 'Eingehend';

  @override
  String get outgoing => 'Ausgehend';

  @override
  String get incomingAndOutgoing => 'Eingehend und ausgehend';

  @override
  String get guessedSettings =>
      'Das sind die üblichen Einstellungen für deine Domain. Wenn die Verbindung fehlschlägt, prüfe sie.';

  @override
  String get yourName => 'Dein Name';

  @override
  String get yourNameHint =>
      'Sichtbar für die Personen, denen du schreibst. Optional.';

  @override
  String get settingsNotFound =>
      'Wir haben die Einstellungen für diese Adresse nicht gefunden. Die Hilfeseiten deines Anbieters nennen sie.';

  @override
  String get smtpServer => 'SMTP-Server';

  @override
  String get username => 'Benutzername';

  @override
  String get usedForBoth =>
      'Wird für eingehende und ausgehende E-Mails verwendet.';

  @override
  String get verifyAndConnect => 'Prüfen und verbinden';

  @override
  String get archive => 'Archivieren';

  @override
  String get archived => 'Archiviert';

  @override
  String get movedToTrash => 'In den Papierkorb verschoben';

  @override
  String get actionFailed =>
      'Die Nachricht konnte nicht verschoben werden. Sie ist wieder im Posteingang.';

  @override
  String get replyTitle => 'Antworten';

  @override
  String quoteHeader(String date, String name) {
    return 'Am $date schrieb $name:';
  }

  @override
  String get search => 'Suchen…';

  @override
  String get searchAllAccounts => 'Alle Konten durchsuchen';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ergebnisse',
      one: '1 Ergebnis',
      zero: 'Keine Ergebnisse',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filter';

  @override
  String get filterLastMonth => 'Letzter Monat';

  @override
  String get filterAccount => 'Konto';

  @override
  String get searchOperators => 'Operatoren';

  @override
  String get operatorNameHint => 'name';

  @override
  String get operatorDateHint => 'datum';

  @override
  String get searchPeople => 'Personen';

  @override
  String get searchEmail => 'E-Mail';

  @override
  String personEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails',
      one: '1 E-Mail',
    );
    return '$_temp0';
  }

  @override
  String get searchNoResults => 'Nichts gefunden';

  @override
  String get searchNoResultsHint =>
      'Versuche es mit weniger Wörtern oder einer anderen Schreibweise.';

  @override
  String get searchNoResultsFilters => 'Keine Ergebnisse mit diesen Filtern';

  @override
  String get searchNoResultsFiltersHint =>
      'Entferne einen Filter oder Operator, um die Suche zu erweitern.';

  @override
  String get clearFilters => 'Filter löschen';

  @override
  String get searchEmptyHint =>
      'Durchsuche alle Konten nach Wort, Absender oder Datum, auch offline.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Treffer',
      one: '1 Treffer',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Unterhaltung öffnen';

  @override
  String get noMessageToShow => 'Keine Nachricht anzuzeigen';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts Konten',
      one: '1 Konto',
    );
    return '$_temp0 durchsucht · $emails E-Mails · $seconds s · lokaler Index, funktioniert offline';
  }

  @override
  String get keyMove => 'bewegen';

  @override
  String get keyOpen => 'öffnen';

  @override
  String get privacyImagesBlocked => 'Bilder blockiert';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tracker gestoppt',
      one: '1 Tracker gestoppt',
    );
    return 'Bilder blockiert · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Bilder werden geladen…';

  @override
  String get privacyImagesLoaded => 'Bilder geladen';

  @override
  String get privacyImagesLoadedStopped =>
      'Bilder geladen · Tracker weiterhin gestoppt';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tracker gestoppt',
      one: '1 Tracker gestoppt',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Links bereinigt',
      one: '1 Link bereinigt',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Datenschutz für diese Nachricht';

  @override
  String get privacySheetSubtitle =>
      'Der Absender kann nicht erkennen, ob oder wann du sie geöffnet hast.';

  @override
  String get trackerPixel => 'Öffnungspixel';

  @override
  String get trackerFont => 'Externe Schrift';

  @override
  String get trackerStyle => 'Externer Stil';

  @override
  String get trackerLinks => 'Verfolgte Links';

  @override
  String get trackerStopped => 'Gestoppt';

  @override
  String get loadImagesOnce => 'Bilder einmal laden';

  @override
  String get imagesAlreadyLoaded => 'Bilder bereits geladen';

  @override
  String trustSender(String name) {
    return '$name immer vertrauen';
  }

  @override
  String senderTrusted(String name) {
    return '$name ist vertrauenswürdig';
  }

  @override
  String get alwaysBlockImages => 'Externe Bilder immer blockieren';

  @override
  String get alwaysBlockImagesHint =>
      'Gilt für alle nicht vertrauenswürdigen Absender';

  @override
  String get imageNotLoaded => 'Bild nicht geladen';

  @override
  String get suspiciousLinkTitle => 'Prüfe diesen Link';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'Der Text zeigt $shown, aber der Link führt zu $real.';
  }

  @override
  String get openAnyway => 'Trotzdem öffnen';

  @override
  String get dontOpen => 'Nicht öffnen';

  @override
  String get riskProgram => 'Ein Programm, das starten kann';

  @override
  String riskDisguised(String kind) {
    return 'Ein Programm, benannt wie ein $kind';
  }

  @override
  String get riskMacros => 'Enthält Makros, die starten können';

  @override
  String get riskLocked => 'Mit Passwort gesperrt';

  @override
  String get riskOpenProgram => 'Dieses Programm öffnen?';

  @override
  String get riskOpenFile => 'Diese Datei öffnen?';

  @override
  String get riskOpenArchive => 'Dieses Archiv öffnen?';

  @override
  String riskBodyProgram(String name) {
    return '$name ist ein Programm. Programme aus E-Mails können dein Gerät übernehmen. Öffne es nur, wenn du es erwartet hast.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name sieht aus wie ein $kind, ist aber ein Programm. Programme aus E-Mails können dein Gerät übernehmen. Öffne es nur, wenn du es erwartet hast.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name enthält Makros, die beim Öffnen starten können. Öffne es nur, wenn du es erwartet hast.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name ist mit einem Passwort gesperrt, niemand kann hineinsehen. Öffne es nur, wenn du es erwartet hast.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · von $email';
  }

  @override
  String get settings => 'Einstellungen';

  @override
  String get backToMail => 'Zurück zu den E-Mails';

  @override
  String get settingsAccountsTitle => 'Konten';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count IMAP-Postfächer, ein Posteingang.',
      one: 'Ein IMAP-Postfach.',
    );
    return '$_temp0 Die Farbe zeigt, woher jede E-Mail kommt.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Konto hinzufügen';

  @override
  String get addAccountNote =>
      'IMAP und SMTP. Gmail, iCloud und Fastmail richten sich selbst ein.';

  @override
  String get privacyTitle => 'Datenschutz und Sicherheit';

  @override
  String get privacySubtitle =>
      'Alles passiert auf diesem Gerät. Keine Daten verlassen dein Postfach.';

  @override
  String get blockImagesSetting => 'Externe Bilder blockieren';

  @override
  String get blockImagesSettingHint =>
      'Bilder werden nur geladen, wenn du es möchtest.';

  @override
  String get stopPixelsSetting => 'Tracking-Pixel stoppen';

  @override
  String get stopPixelsSettingHint =>
      'Absender können nicht erkennen, ob oder wann du eine Nachricht öffnest.';

  @override
  String get cleanLinksSetting => 'Links bereinigen';

  @override
  String get cleanLinksSettingHint =>
      'Entfernt utm- und Tracking-Parameter vor dem Öffnen.';

  @override
  String get warnLinksSetting => 'Vor verdächtigen Links warnen';

  @override
  String get warnLinksSettingHint =>
      'Fragt nach, bevor ein Link geöffnet wird, der eine Adresse zeigt und zu einer anderen führt.';

  @override
  String get last30Days => 'Letzte 30 Tage';

  @override
  String get trackersStoppedLabel => 'Tracker gestoppt';

  @override
  String get linksCleanedLabel => 'Links bereinigt';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious verdächtige Links markiert',
      one: '1 verdächtiger Link markiert',
    );
    return 'Öffnungspixel $pixels · externe Schriften und Stile $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Vertrauenswürdige Absender';

  @override
  String get trustedSendersHint => 'Bilder werden immer geladen';

  @override
  String trustedSince(String email, String date) {
    return '$email · seit $date';
  }

  @override
  String get removeTrusted => 'Entfernen';

  @override
  String get noTrustedSenders =>
      'Keine vertrauenswürdigen Absender. Bilder bleiben für alle blockiert.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Datei anhängen';

  @override
  String removeAttachment(String name) {
    return '$name entfernen';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name in Downloads gespeichert';
  }

  @override
  String attachmentNotSaved(String name) {
    return '$name konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Anhänge dürfen insgesamt höchstens $max groß sein. Entferne einige und versuche es erneut.';
  }

  @override
  String fileNotRead(String name) {
    return '$name konnte nicht gelesen werden.';
  }

  @override
  String get folderSent => 'Gesendet';

  @override
  String get folderArchive => 'Archiv';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten',
      one: 'Ein Konto',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'an $people · heute um $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'an $people · gestern um $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'an $people · $date um $time';
  }

  @override
  String get emptyFolder => 'Hier ist noch nichts.';

  @override
  String threadMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten',
      one: '1 Nachricht',
    );
    return '$_temp0';
  }

  @override
  String conversationSummary(int count, String people) {
    return '$count Nachrichten · $people';
  }

  @override
  String readMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gelesene Nachrichten',
      one: '1 gelesene Nachricht',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count neu';
  }

  @override
  String get you => 'du';

  @override
  String get quotedTextHidden => '··· zitierter Text ausgeblendet';

  @override
  String get showQuotedText => 'Zitierten Text anzeigen';

  @override
  String get youName => 'Du';

  @override
  String yesterdayAt(String time) {
    return 'Gestern $time';
  }

  @override
  String get pickMessage => 'Auswählen';

  @override
  String get unpickMessage => 'Ausgewählt';

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String pickedOf(int count, int total) {
    return '$count von $total ausgewählt';
  }

  @override
  String get deselect => 'Auswahl aufheben';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unterhaltungen ausgewählt',
      one: 'Unterhaltung ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'von $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'von $names und $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'von $names und $count weiteren';
  }

  @override
  String andMore(String name, int count) {
    return '$name und $count weitere';
  }

  @override
  String get markRead => 'Als gelesen markieren';

  @override
  String get markUnread => 'Als ungelesen markieren';

  @override
  String get hintArchive => 'archivieren';

  @override
  String get hintUnread => 'ungelesen';

  @override
  String get hintDeselect => 'Auswahl aufheben';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen archiviert',
      one: 'Archiviert',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen in den Papierkorb verschoben',
      one: 'In den Papierkorb verschoben',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'Der Server war nicht erreichbar. Gelesen und ungelesen sind wieder wie vorher.';

  @override
  String get signaturesTitle => 'Signaturen';

  @override
  String get newSignature => 'Neue Signatur';

  @override
  String get newSignatureLabel => 'Neue Signatur';

  @override
  String get noSignatures =>
      'Noch keine Signaturen. Erstelle eine mit Neue Signatur.';

  @override
  String get signatureTemplate => 'Vorlage';

  @override
  String get signatureLogo => 'Logo';

  @override
  String get signatureLabelField => 'Name der Signatur';

  @override
  String get signatureAccount => 'Konto';

  @override
  String get signatureName => 'Name';

  @override
  String get signatureRole => 'Position';

  @override
  String get signatureCompany => 'Firma';

  @override
  String get signaturePhone => 'Telefon';

  @override
  String get signatureWebsite => 'Website';

  @override
  String get signatureAccent => 'Akzentfarbe';

  @override
  String get accentBlue => 'Akzent Blau';

  @override
  String get accentBlack => 'Akzent Schwarz';

  @override
  String get accentTerracotta => 'Akzent Terrakotta';

  @override
  String get signatureWhen => 'Wann sie verwendet wird';

  @override
  String signatureForNew(String email) {
    return 'Neue E-Mails von $email';
  }

  @override
  String get signatureForReplies => 'Antworten und Weiterleitungen';

  @override
  String get signatureNone => 'Keine';

  @override
  String get deleteSignature => 'Signatur löschen';

  @override
  String get signatureDeleteHint => 'Bereits gesendete E-Mails behalten sie.';

  @override
  String get signaturePreview => 'Vorschau';

  @override
  String get previewLight => 'Hell';

  @override
  String get previewDark => 'Dunkel';

  @override
  String get previewText => 'Text';

  @override
  String get signatureSampleText =>
      'Hallo Luca,\nanbei die finalen Dateien. Sag Bescheid, wenn du noch etwas brauchst.\n\nBis bald,';

  @override
  String get signatureNote =>
      'Keine Bilder: Die Signatur kommt sauber an, auch wo Bilder blockiert sind, und die Nur-Text-Version wird für dich erstellt.';

  @override
  String get signatureNoteLogo =>
      'Das Logo reist in der E-Mail mit (max. 40 KB) und hat einen Alternativtext, fragt also nie nach „Bilder laden“ und verfolgt niemanden. Die Nur-Text-Version wird für dich erstellt.';

  @override
  String get signatureUseAll => 'alle';

  @override
  String get signatureUseNew => 'neue E-Mails';

  @override
  String get signatureUseReplies => 'Antworten und Weiterleitungen';

  @override
  String get signatureUseNone => 'nicht verwendet';

  @override
  String get templateMinimal => 'Minimal';

  @override
  String get templateClassic => 'Klassisch';

  @override
  String get templateMonogram => 'Monogramm';

  @override
  String get templateLogo => 'Mit Logo';

  @override
  String get noLogo => 'KEIN LOGO';

  @override
  String get logoHint => 'PNG oder JPEG, automatisch auf 40 KB verkleinert';

  @override
  String get removeLogo => 'Entfernen';

  @override
  String get uploadLogo => 'Hochladen';

  @override
  String get logoTooBig =>
      'Dieses Logo bleibt auch verkleinert über 40 KB. Versuche ein einfacheres.';

  @override
  String get logoNotImage => 'Wähle ein PNG- oder JPEG-Bild.';

  @override
  String signatureChip(String label) {
    return 'Signatur · $label';
  }

  @override
  String get noSignature => 'Keine Signatur';

  @override
  String get manageSignatures => 'Signaturen verwalten…';

  @override
  String get signatureUsedNew => 'Neue E-Mails';

  @override
  String get signatureUsedReplies => 'Antworten';

  @override
  String get composeSignatureNote =>
      'Die Signatur folgt dem Von-Konto: seine Signatur für neue E-Mails, die kurze für Antworten und Weiterleitungen.';

  @override
  String get noticeOpen => 'Öffnen';

  @override
  String get noticeChannel => 'Neue E-Mails';

  @override
  String noticeTitleMany(String sender, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails',
      one: '1 E-Mail',
    );
    return '$sender · $_temp0';
  }

  @override
  String get notificationsTitle => 'Mitteilungen';

  @override
  String get notificationsLead => 'Wenige, und nur wenn es wichtig ist.';

  @override
  String get notifyAbout => 'Benachrichtigen bei';

  @override
  String get notifyPeople => 'Nur Personen';

  @override
  String get notifyPeopleHint =>
      'E-Mails, die Menschen geschrieben haben. Keine Newsletter, Belege oder automatischen Nachrichten.';

  @override
  String get notifyRecommended => 'Empfohlen';

  @override
  String get notifyAll => 'Alle';

  @override
  String get notifyAllHint => 'Jede neue E-Mail, die im Posteingang landet.';

  @override
  String get notifyOff => 'Keine';

  @override
  String get notifyOffHint =>
      'Schau nach, wann du willst. Keine Kennzeichen, keine Töne.';

  @override
  String get quietHours => 'Ruhezeiten';

  @override
  String get quietTitle => 'Jede Nacht';

  @override
  String get quietHint => 'E-Mails kommen weiterhin an, leise.';

  @override
  String get quietFrom => 'Von';

  @override
  String get quietTo => 'bis';

  @override
  String quietFromLabel(String time) {
    return 'Ruhezeit beginnt um $time';
  }

  @override
  String quietToLabel(String time) {
    return 'Ruhezeit endet um $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten',
      one: '1 Konto',
    );
    return '$_temp0 durchsuchen';
  }

  @override
  String get phoneAccountsAll => 'Alle';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alle $count Konten werden angezeigt',
      one: '1 Konto wird angezeigt',
    );
    return '$_temp0';
  }

  @override
  String get composeMessage => 'Nachricht verfassen';

  @override
  String get moreActions => 'Weitere Aktionen';

  @override
  String quickReplyHint(String name) {
    return '$name antworten…';
  }

  @override
  String get sendReply => 'Antwort senden';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get pickAll => 'Alle';

  @override
  String get pickNone => 'Keine';

  @override
  String get pickRead => 'Gelesen';

  @override
  String get pickUnread => 'Ungelesen';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'von $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count von $total ausgewählt';
  }

  @override
  String get phoneSelectActions => 'Aktionen für die Auswahl';

  @override
  String get clearSearch => 'Suche löschen';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsMail => 'E-Mail';

  @override
  String get settingsApp => 'App';

  @override
  String get writingTitle => 'Schreiben';

  @override
  String get readingTitle => 'Lesen';

  @override
  String get readingSubtitle =>
      'Wie die Liste aussieht, und was dir beim Lesen hilft.';

  @override
  String get organizingTitle => 'Ordnen';

  @override
  String get organizingSubtitle => 'Bereiche, Regeln, Ordner und Labels.';

  @override
  String signaturesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Signaturen',
      one: '1 Signatur',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLine => 'Open Source · GPL-3.0';

  @override
  String get motto => 'E-Mail, ganz leicht.';

  @override
  String get appName => 'Piuma Mail';

  @override
  String phoneAccountsMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten',
      one: '1 Konto',
    );
    return '$_temp0, Konten und Einstellungen';
  }

  @override
  String get allAccounts => 'Alle Konten';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Posteingänge zusammen',
      one: '1 Posteingang',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return 'Nur $name, Konten und Einstellungen';
  }

  @override
  String accountOnly(String name) {
    return 'Nur $name';
  }

  @override
  String get showAllAccounts => 'Alle anzeigen';

  @override
  String get phoneFolders => 'Ordner';

  @override
  String phoneSearchOne(String name) {
    return '$name durchsuchen';
  }

  @override
  String get welcomeLead =>
      'Verbinde deine IMAP-Konten und lies alles in einem Posteingang, ohne Lärm.';

  @override
  String get staysOnDevice => 'Deine E-Mails bleiben auf deinem Gerät';

  @override
  String get editServers => 'Bearbeiten';

  @override
  String get serverHost => 'Server';

  @override
  String get offlineTitle => 'Du bist offline';

  @override
  String get offlineDetail =>
      'ausgehende E-Mails werden gesendet, sobald du wieder online bist';

  @override
  String downloadingAccount(String name) {
    return '$name wird geladen';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done von $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'Das Konto $name kann sich nicht verbinden';
  }

  @override
  String passwordChanged(String email) {
    return 'Hat sich das Passwort geändert? E-Mails für $email kommen nicht mehr an.';
  }

  @override
  String get signInAgain => 'Erneut anmelden';

  @override
  String get later => 'Später';

  @override
  String signInTo(String name) {
    return 'Bei $name anmelden';
  }

  @override
  String get signIn => 'Anmelden';

  @override
  String get signingIn => 'Anmeldung läuft…';

  @override
  String get allCaughtUp => 'Alles erledigt';

  @override
  String get allCaughtUpDetail =>
      'Niemand wartet auf dich. Der Rest des Tages gehört dir.';

  @override
  String get countOf => 'von';

  @override
  String get draftSaved => 'Entwurf gespeichert';

  @override
  String get draftNotSaved => 'Nicht gespeichert';

  @override
  String get draftNotSavedToast => 'Entwurf nicht gespeichert';

  @override
  String get reopen => 'Wieder öffnen';

  @override
  String get discard => 'Verwerfen';

  @override
  String get noRecipients => 'Keine Empfänger';

  @override
  String get folderDrafts => 'Entwürfe';

  @override
  String accountFolders(String name) {
    return 'Ordner von $name';
  }

  @override
  String get moveShort => 'Verschieben';

  @override
  String get moveTo => 'Verschieben nach…';

  @override
  String moveToIn(String name) {
    return 'In einen Ordner von $name verschieben';
  }

  @override
  String get noFoldersMatch => 'Kein Ordner mit diesem Namen';

  @override
  String noOtherFolders(String name) {
    return '$name hat noch keine anderen Ordner';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen nach $folder verschoben',
      one: 'Nach $folder verschoben',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'Postausgang · $count';
  }

  @override
  String outboxTo(String names) {
    return 'An $names';
  }

  @override
  String get outboxWaiting => 'Wartet';

  @override
  String get outboxNotSent => 'Nicht gesendet';

  @override
  String outboxRefused(String reason) {
    return 'Der Server hat sie abgelehnt: $reason';
  }

  @override
  String get inOutbox =>
      'Im Postausgang · wird gesendet, sobald du wieder online bist';

  @override
  String get editAction => 'Bearbeiten';

  @override
  String get backgroundTitle => 'Neue E-Mails sofort bei Eingang';

  @override
  String get backgroundBody =>
      'Piuma bleibt mit deinen Konten verbunden, ohne Server dazwischen. Android fragt dich zwei Dinge: ob Mitteilungen angezeigt werden dürfen und ob Piuma im Hintergrund laufen darf.';

  @override
  String get newMailHeading => 'Neue E-Mails';

  @override
  String get deliveryInstant => 'Sofort bei Eingang';

  @override
  String get deliveryInstantHint =>
      'Behält eine stille Mitteilung in der Leiste';

  @override
  String get deliveryPeriodic => 'Alle 15 Minuten';

  @override
  String get deliveryPeriodicHint =>
      'Keine Mitteilung; Android wartet eventuell länger';

  @override
  String get folderNewsletters => 'Newsletter';

  @override
  String newslettersTileLabel(int count) {
    return 'Newsletter, $count ungelesen';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes Min. · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes Min. Lesezeit · eingegangen um $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Eingegangen um $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Eingegangen am $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes Min. Lesezeit · eingegangen am $date';
  }

  @override
  String get dayToday => 'heute';

  @override
  String get dayYesterday => 'gestern';

  @override
  String get readLater => 'Später lesen';

  @override
  String get readLaterDone => 'Bleibt ungelesen';

  @override
  String get unsubscribe => 'Abbestellen';

  @override
  String unsubscribeTitle(String sender) {
    return '$sender abbestellen?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender erhält eine einzige Bitte, aufzuhören. Nichts wird geöffnet, und was schon da ist, bleibt hier.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'Eine Nachricht geht von deinem Konto an $address, um darum zu bitten. Was schon da ist, bleibt hier.';
  }

  @override
  String get unsubscribePage => 'Die Abmeldeseite öffnet sich im Browser.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender bietet keine Möglichkeit zum Abbestellen. Verschiebe ihn in den Posteingang oder archiviere, was kommt.';
  }

  @override
  String get unsubscribeConfirm => 'Abbestellen';

  @override
  String get unsubscribeOpen => 'Seite öffnen';

  @override
  String unsubscribeDone(String sender) {
    return '$sender abbestellt';
  }

  @override
  String get unsubscribeFailed =>
      'Abbestellen nicht möglich. Prüfe die Verbindung und versuche es erneut.';

  @override
  String get alwaysInInbox => 'Immer im Posteingang';

  @override
  String alwaysInInboxDone(String sender) {
    return 'E-Mails von $sender landen jetzt im Posteingang';
  }

  @override
  String get newslettersArchiveNote =>
      'Vor mehr als 7 Tagen gelesen? Sie archivieren sich selbst';

  @override
  String get newslettersEmpty => 'Keine Newsletter';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zu lesen',
      one: '1 zu lesen',
      zero: 'Alles gelesen',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes Minuten insgesamt';
  }

  @override
  String newslettersNew(int count) {
    return '$count neu';
  }

  @override
  String get folderVault => 'Tresor';

  @override
  String vaultTileLabel(String status) {
    return 'Tresor, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Tresor, $count offen';
  }

  @override
  String vaultDue(String when) {
    return 'Fällig $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Kommt $when';
  }

  @override
  String get vaultAllClear => 'Alles gut';

  @override
  String get vaultToday => 'Heute';

  @override
  String get vaultTomorrow => 'Morgen';

  @override
  String get dayTomorrow => 'morgen';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'in $days Tagen',
      one: 'morgen',
      zero: 'heute',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Bestellt';

  @override
  String get parcelShipped => 'Versandt';

  @override
  String get parcelTransit => 'Unterwegs';

  @override
  String get parcelDelivered => 'Zugestellt';

  @override
  String vaultDeliveredOn(String day) {
    return 'Zugestellt $day';
  }

  @override
  String vaultCarrierFrom(String carrier, String merchant) {
    return '$carrier · von $merchant';
  }

  @override
  String vaultFrom(String merchant) {
    return 'Von $merchant';
  }

  @override
  String vaultLastScan(String place) {
    return 'Letzter Scan: $place';
  }

  @override
  String get vaultDueLabel => 'Fällig';

  @override
  String get vaultPaid => 'Bezahlt';

  @override
  String get vaultDownloadPdf => 'PDF laden';

  @override
  String get vaultMarkPaid => 'Als bezahlt markieren';

  @override
  String get vaultPaidFailed =>
      'Das konnte nicht gespeichert werden. Versuche es erneut.';

  @override
  String vaultFlight(String number, String date) {
    return 'Flug $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Sitz';

  @override
  String get vaultCode => 'Code';

  @override
  String get vaultBoardingPass => 'Bordkarte';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Personen',
      one: '1 Person',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'bestätigt';

  @override
  String get vaultPending => 'zu bestätigen';

  @override
  String get vaultCancelled => 'storniert';

  @override
  String get vaultDirections => 'Route';

  @override
  String get vaultNotePhone =>
      'Auf dem Gerät aus der Original-E-Mail gelesen · tippe auf eine Karte, um sie zu öffnen';

  @override
  String get vaultEmpty =>
      'Pakete, Ausgaben, Reisen und mehr erscheinen hier, auf diesem Gerät aus ihren E-Mails gelesen.';

  @override
  String get folderAttachments => 'Anhänge';

  @override
  String get attachmentsSubtitle =>
      'Jede Datei, die du bekommen hast, ohne die E-Mail zu öffnen';

  @override
  String get attachmentsAll => 'Alle';

  @override
  String get attachmentsMedia => 'Fotos und Medien';

  @override
  String get attachmentsDocuments => 'Dokumente';

  @override
  String get attachmentsSheets => 'Tabellen';

  @override
  String get attachmentsFilter => 'Nach Typ filtern';

  @override
  String get attachmentsSearch => 'Dateien oder Absender suchen';

  @override
  String get attachmentsSearchLabel => 'Anhänge durchsuchen';

  @override
  String get attachmentsRecent => 'Neueste';

  @override
  String get attachmentsLargest => 'Größte';

  @override
  String attachmentsSortLabel(String sort) {
    return 'Sortieren nach: $sort';
  }

  @override
  String get attachmentsThisWeek => 'Diese Woche';

  @override
  String get attachmentsEarlier => 'Früher';

  @override
  String attachmentsMeta(String name, String size, String when) {
    return 'Von: $name · $size · $when';
  }

  @override
  String get attachmentsDownload => 'Laden';

  @override
  String get attachmentsOpenEmail => 'E-Mail öffnen';

  @override
  String get attachmentsEmail => 'E-Mail';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, von $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return '$name laden';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'E-Mail von $from öffnen';
  }

  @override
  String get attachmentsNoneNew => 'Nichts Neues';

  @override
  String attachmentsTileLabel(String status) {
    return 'Anhänge, $status';
  }

  @override
  String get attachmentsEmpty =>
      'Dateien, die du bekommst, erscheinen hier, aus allen Konten.';

  @override
  String attachmentsNoMatch(String query) {
    return 'Keine Dateien passen zu „$query“';
  }

  @override
  String attachmentsNew(int count) {
    return '$count neu';
  }

  @override
  String get folderSnoozed => 'Zurückgestellt';

  @override
  String get snoozeUntilTitle => 'Zurückstellen bis…';

  @override
  String get snoozeEvening => 'Heute Abend';

  @override
  String get snoozeMorning => 'Morgen früh';

  @override
  String get snoozeWeekend => 'Am Wochenende';

  @override
  String get snoozeNextWeek => 'Nächste Woche';

  @override
  String snoozeTileToday(String time) {
    return 'heute $time';
  }

  @override
  String snoozeToday(String time) {
    return 'heute, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'morgen, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'morgen $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen zurückgestellt bis $when',
      one: 'Zurückgestellt bis $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Zurück in den Posteingang';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen wieder im Posteingang',
      one: 'Wieder im Posteingang',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Morgen';

  @override
  String get sectionLater => 'Später';

  @override
  String get sendLater => 'Später senden';

  @override
  String get sendLaterTomorrowMorning => 'Morgen früh';

  @override
  String get sendLaterTomorrowAfternoon => 'Morgen Nachmittag';

  @override
  String get sendLaterMondayMorning => 'Montag früh';

  @override
  String scheduleTomorrow(String time) {
    return 'Für morgen um $time planen';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Für $day um $time planen';
  }

  @override
  String get sendLaterNote =>
      'Wird zu dieser Zeit von diesem Gerät gesendet. Ist es dann aus, geht sie raus, sobald es wieder an ist.';

  @override
  String scheduledToast(String when) {
    return 'Geplant für $when';
  }

  @override
  String get paletteLabel => 'Befehlspalette';

  @override
  String get paletteHint => 'Suchen oder Befehl ausführen';

  @override
  String get paletteActions => 'Aktionen';

  @override
  String get paletteMessages => 'Nachrichten';

  @override
  String paletteWriteTo(String name) {
    return '$name schreiben';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Nur Nachrichten von $name anzeigen';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Anhänge von $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Alle E-Mails nach „$query“ durchsuchen';
  }

  @override
  String paletteGoTo(String place) {
    return 'Gehe zu $place';
  }

  @override
  String get paletteMove => 'bewegen';

  @override
  String get paletteRun => 'ausführen';

  @override
  String get paletteAnywhere => 'von jedem Bildschirm aus';

  @override
  String senderCardLabel(String name) {
    return 'Karte von $name';
  }

  @override
  String get senderKind => 'Absender';

  @override
  String get senderClose => 'Karte schließen';

  @override
  String get senderWrite => 'Schreiben';

  @override
  String get senderAll => 'Alle E-Mails';

  @override
  String get senderMute => 'Stummschalten';

  @override
  String get senderMuted => 'Stummgeschaltet';

  @override
  String senderArrivesIn(String account) {
    return 'Kommt in $account an';
  }

  @override
  String get senderConversations => 'Unterhaltungen';

  @override
  String get senderNoMail =>
      'Noch keine E-Mails von dieser Person auf diesem Gerät.';

  @override
  String senderMutedToast(String name) {
    return 'Keine Mitteilungen mehr von $name';
  }

  @override
  String get rulesTitle => 'Regeln und Ordner';

  @override
  String get rulesSubtitle =>
      'Sortiert deine E-Mails so, wie du es tun würdest. Jede Regel liest sich wie ein Satz.';

  @override
  String get rulesWhere =>
      'Regeln laufen auf diesem Gerät, für neue E-Mails im Posteingang';

  @override
  String get rulesHeading => 'Regeln';

  @override
  String get rulesNew => 'Neue Regel';

  @override
  String get rulesEdit => 'Regel bearbeiten';

  @override
  String get rulesNone =>
      'Noch keine eigenen Regeln. Eine Regel sortiert neue E-Mails beim Eingang, so wie du es tun würdest.';

  @override
  String get ruleWhen => 'Wenn';

  @override
  String get ruleThen => 'dann';

  @override
  String get ruleFieldSender => 'der Absender';

  @override
  String get ruleFieldSubject => 'der Betreff';

  @override
  String get ruleFieldRecipient => 'der Empfänger';

  @override
  String get ruleOpContains => 'enthält';

  @override
  String get ruleOpIs => 'ist';

  @override
  String get ruleOpStarts => 'beginnt mit';

  @override
  String get ruleOpNotContains => 'enthält nicht';

  @override
  String get ruleDoMove => 'verschieben nach';

  @override
  String get ruleDoArchive => 'archivieren';

  @override
  String get ruleDoRead => 'als gelesen markieren';

  @override
  String get ruleText => 'Gesuchter Text';

  @override
  String get ruleTextHint => 'text';

  @override
  String get ruleTrayField => 'Feld';

  @override
  String get ruleTrayOp => 'Bedingung';

  @override
  String get ruleTrayAction => 'Aktion';

  @override
  String get ruleTrayFolder => 'Ordner';

  @override
  String get rulePickFolder => 'einen Ordner';

  @override
  String get ruleNoFolders => 'Deine Konten haben noch keine eigenen Ordner.';

  @override
  String get ruleApplyToo => 'Auch auf diese anwenden';

  @override
  String get ruleSave => 'Regel speichern';

  @override
  String get ruleDelete => 'Regel löschen';

  @override
  String get rulePaused => 'Pausiert';

  @override
  String get ruleFresh => 'Ab jetzt aktiv';

  @override
  String get foldersHeading => 'Ordner';

  @override
  String get foldersNone => 'Keine eigenen Ordner';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gilt für $count vorhandene E-Mails',
      one: 'Gilt für $count vorhandene E-Mail',
      zero: 'Keine vorhandenen E-Mails passen',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails sortiert',
      one: '1 E-Mail sortiert',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'zuletzt heute $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'zuletzt $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Regel aktiv: $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Keine',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Einladung';

  @override
  String get inviteYes => 'Ja';

  @override
  String get inviteMaybe => 'Vielleicht';

  @override
  String get inviteNo => 'Nein';

  @override
  String get inviteRespond => 'Auf Einladung antworten';

  @override
  String get inviteAllDay => 'Ganztägig';

  @override
  String get inviteRepeats => 'wiederholt sich';

  @override
  String get inviteYouAccepted => 'Du hast zugesagt';

  @override
  String get inviteYouTentative => 'Du hast mit Vielleicht geantwortet';

  @override
  String get inviteYouDeclined => 'Du hast abgesagt';

  @override
  String get inviteNotSent =>
      'Deine Antwort konnte nicht gesendet werden. Versuche es erneut.';

  @override
  String get inviteCancelled => 'Dieser Termin wurde abgesagt';

  @override
  String get inviteYours => 'Du hast diese Einladung gesendet';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Teilnehmer',
      one: '1 Teilnehmer',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name erhält deine Antwort';
  }

  @override
  String inviteQueued(String name) {
    return 'geht an $name, sobald du wieder online bist';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name hat zugesagt';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name hat mit Vielleicht geantwortet';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name hat abgesagt';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Zugesagt: $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Vielleicht: $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Abgesagt: $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name hat diese Einladung angenommen.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name kommt vielleicht.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name hat diese Einladung abgelehnt.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Einladung: $summary, $when';
  }

  @override
  String get inviteFree => 'Frei · keine Überschneidungen';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Überschneidet sich mit $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Verfügbarkeit: $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'zu $name hinzugefügt';
  }

  @override
  String get settingsCalendars => 'Kalender';

  @override
  String get calIntro =>
      'Piuma hat keinen eigenen Kalender: Verbinde die, die du schon nutzt. Die Termine bleiben dort.';

  @override
  String get calConnected => 'Verbundene Kalender';

  @override
  String calSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Quellen',
      one: '1 Quelle',
    );
    return '$_temp0';
  }

  @override
  String calCalendars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kalender',
      one: '1 Kalender',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Kalender verbinden';

  @override
  String get calChoose => 'Wähle, womit du dich verbindest';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Server, E-Mail und App-Passwort';

  @override
  String get calIcs => '.ics-URL abonnieren';

  @override
  String get calIcsSub => 'Nur lesen, aktualisiert sich selbst';

  @override
  String get calCalDavLabel => 'E-Mail-Adresse oder CalDAV-Server';

  @override
  String get calCalDavHint =>
      'iCloud braucht ein App-Passwort; es bleibt verschlüsselt im Schlüsselbund des Systems.';

  @override
  String get calIcsLabel => 'URL des .ics-Kalenders';

  @override
  String get calIcsHint =>
      '.ics-Kalender sind schreibgeschützt: praktisch für Feiertage, Sport, Schichten.';

  @override
  String get calUsername => 'Benutzername (falls nicht die E-Mail)';

  @override
  String get calPassword => 'Passwort';

  @override
  String get calConnectButton => 'Verbinden';

  @override
  String get calSubscribe => 'Abonnieren';

  @override
  String get calSuggested =>
      'Hinzugefügte E-Mail-Konten mit Kalender werden automatisch vorgeschlagen';

  @override
  String get calHasCalendar => 'hat auch einen Kalender';

  @override
  String get calDone => 'Verbunden';

  @override
  String get calDisconnect => 'Trennen';

  @override
  String calDisconnectLabel(String name) {
    return '$name trennen';
  }

  @override
  String get calReadOnly => 'nur lesen';

  @override
  String get calInvitesTag => 'Einladungen';

  @override
  String get calShowAvailability => 'Verfügbarkeit anzeigen';

  @override
  String get calAvailabilityShort => 'Verfügbarkeit';

  @override
  String calAvailabilityFor(String name) {
    return 'Verfügbarkeit für $name anzeigen';
  }

  @override
  String get calNone =>
      'Keine Kalender verbunden. Einladungen funktionieren trotzdem, per E-Mail.';

  @override
  String get calWhenInvite => 'Wenn eine Einladung kommt';

  @override
  String get calAddTo => 'Hinzufügen zu';

  @override
  String get calAddToSub => 'Wohin angenommene Einladungen kommen';

  @override
  String get calAddInvitesTo => 'Einladungen hinzufügen zu';

  @override
  String get calNoWritable => 'Keiner';

  @override
  String get calConflicts =>
      'Überschneidungen in allen verbundenen Kalendern prüfen';

  @override
  String get calConflictsSub =>
      'Einladungen zeigen sofort, ob du dann schon verplant bist.';

  @override
  String get calFooter =>
      'Ohne verbundene Kalender kannst du Einladungen trotzdem per E-Mail beantworten und die .ics-Datei öffnen.';

  @override
  String get calStaysHere =>
      'Verbindungen bleiben auf diesem Gerät; Passwörter liegen im Schlüsselbund des Systems.';

  @override
  String get calWrongPassword =>
      'Falscher Benutzername oder falsches Passwort.';

  @override
  String get calUnreachable =>
      'Dort wurde kein Kalender gefunden. Prüfe die Adresse.';

  @override
  String get calFailed => 'Verbindung nicht möglich. Versuche es erneut.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => '.ics-URL, nur lesen';

  @override
  String get calFromAccount => 'vom E-Mail-Konto';

  @override
  String foundDateAdd(String when) {
    return '$when zum Kalender hinzufügen';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Zu $calendar hinzugefügt';
  }

  @override
  String foundDateAddLabel(String when) {
    return '$when zum Kalender hinzufügen, auf diesem Gerät gefunden';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when zu $calendar hinzugefügt';
  }

  @override
  String get foundOnDevice => 'Auf diesem Gerät gefunden';

  @override
  String get foundDateNotAdded =>
      'Konnte nicht zum Kalender hinzugefügt werden. Versuche es gleich noch einmal.';

  @override
  String get calFindDates =>
      'Vorschlagen, in E-Mails gefundene Termine hinzuzufügen';

  @override
  String get calFindDatesSub =>
      'Ein kleiner Vorschlag neben dem Satz, nie automatisch.';

  @override
  String get calOnDevice => 'auf dem Gerät';

  @override
  String get inShort => 'Kurz gesagt';

  @override
  String get generatedOnDevice => 'Auf dem Gerät erstellt';

  @override
  String get yourTurn => 'Du bist dran:';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name schreibt „$words“';
  }

  @override
  String get inShortColon => 'Kurz gesagt:';

  @override
  String get onDevice => 'auf dem Gerät';

  @override
  String senderBriefTopic(String topic) {
    return 'meist über „$topic“';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails diesen Monat',
      one: '1 E-Mail diesen Monat',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'die letzte wartet auf deine Antwort';

  @override
  String get searchByType => 'Nach Typ suchen';

  @override
  String get frequentContacts => 'Häufige Kontakte';

  @override
  String get recentSearches => 'Letzte Suchen';

  @override
  String get clearRecent => 'Löschen';

  @override
  String get clearRecentSearches => 'Letzte Suchen löschen';

  @override
  String get noRecentSearches => 'Keine letzten Suchen.';

  @override
  String get searchOperatorsHint => 'Du kannst auch Operatoren eingeben';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$formatted E-Mails auf diesem Gerät indexiert · funktioniert offline',
      one: '1 E-Mail auf diesem Gerät indexiert · funktioniert offline',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'Mit Anhängen';

  @override
  String get searchFromPeople => 'Von Personen';

  @override
  String searchMailFrom(String name) {
    return 'E-Mails von $name suchen';
  }

  @override
  String removeRecentSearch(String query) {
    return '$query entfernen';
  }

  @override
  String get searchAddWords => 'Wörter hinzufügen…';

  @override
  String rowPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Fotos',
      one: '1 Foto',
    );
    return '$_temp0';
  }

  @override
  String rowAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge',
      one: '1 Anhang',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Blockieren';

  @override
  String get senderBlocked => 'Blockiert';

  @override
  String showSnoozed(int count) {
    return 'Zurückgestellte anzeigen ($count)';
  }

  @override
  String get hideSnoozed => 'Zurückgestellte ausblenden';

  @override
  String get snoozeNoReply => 'Wenn niemand antwortet';

  @override
  String get snoozeNoReplyHint =>
      'Kommt nach 3 Tagen zurück, wenn keine Antwort kommt';

  @override
  String get previewClose => 'Vorschau schließen';

  @override
  String previewMeta(String size, String name) {
    return '$size · von $name';
  }

  @override
  String previewPage(int page, int count) {
    return 'Seite $page von $count';
  }

  @override
  String get previewPrevPage => 'Vorherige Seite';

  @override
  String get previewNextPage => 'Nächste Seite';

  @override
  String previewOpenEmail(String name) {
    return 'E-Mail von $name öffnen';
  }

  @override
  String get previewDownloadAll => 'Alle laden';

  @override
  String previewPhoto(int index, int count) {
    return 'Foto $index von $count · aus derselben E-Mail';
  }

  @override
  String get previewPhotos => 'Fotos in der E-Mail';

  @override
  String get previewCantShow =>
      'Diese Datei kann hier nicht angezeigt werden. Du kannst sie trotzdem laden.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Seite $page von $name';
  }

  @override
  String get vaultParcelsTitle => 'Paketzustellungen';

  @override
  String get vaultParcelsHint => 'Am Zustelltag, nur einmal.';

  @override
  String get vaultDueTitle => 'Fälligkeiten';

  @override
  String get vaultDueHint => 'Rechnungen und Verlängerungen, drei Tage vorher.';

  @override
  String get vaultNoticeParcel => 'Dein Paket kommt heute';

  @override
  String get vaultNoticeDueToday => 'Heute fällig';

  @override
  String get vaultNoticeDueTomorrow => 'Morgen fällig';

  @override
  String vaultNoticeDueIn(int days) {
    return 'In $days Tagen fällig';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'gegen $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zertifizierte E-Mails',
      one: '1 zertifizierte E-Mail',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nicht zugestellt',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Gesendet';

  @override
  String get pecAccepted => 'Angenommen';

  @override
  String get pecDelivered => 'Zugestellt';

  @override
  String get pecFailed => 'Nicht zugestellt';

  @override
  String pecTo(String who) {
    return 'An $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'An $count Empfänger · $delivered von $count zugestellt';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Angenommen $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Zugestellt $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'Nicht zugestellt · $when';
  }

  @override
  String pecReasonAt(String reason, String when) {
    return '$reason · $when';
  }

  @override
  String get pecOpen => 'Öffnen';

  @override
  String pecReceipt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Quittungen',
      one: 'Quittung',
    );
    return '$_temp0';
  }

  @override
  String pecSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Quittungen in Downloads gespeichert',
      one: 'Quittung in Downloads gespeichert',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'Quittung konnte nicht gespeichert werden';

  @override
  String get pecNote =>
      'Quittungen bleiben aus dem Posteingang heraus und sammeln sich bei der Nachricht, zu der sie gehören. Quittung speichert den signierten Nachweis als Datei.';

  @override
  String get pickDateTime => 'Datum und Uhrzeit wählen';

  @override
  String get previousMonth => 'Vorheriger Monat';

  @override
  String get nextMonth => 'Nächster Monat';

  @override
  String get pickTime => 'Uhrzeit';

  @override
  String get pickOtherTime => 'Andere Uhrzeit';

  @override
  String get pickTimeGone => 'Diese Uhrzeit ist schon vorbei';

  @override
  String snoozeUntilAt(String when) {
    return 'Zurückstellen bis $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Planen für $when';
  }

  @override
  String get senderNewsletterKind => 'Newsletter';

  @override
  String newsletterPerWeek(int count) {
    return 'etwa $count pro Woche';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'etwa $count pro Monat';
  }

  @override
  String newsletterOpened(int percent) {
    return 'du öffnest $percent %';
  }

  @override
  String get newsletterUnsubscribed => 'Abbestellt';

  @override
  String get newsletterClearAsk => 'auch alte E-Mails löschen?';

  @override
  String get newsletterClearYes => 'Ja, löschen';

  @override
  String get newsletterClearNo => 'Nein';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Abbestellt · $count E-Mails in den Papierkorb verschoben',
      one: 'Abbestellt · 1 E-Mail in den Papierkorb verschoben',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept =>
      'Abbestellt · alte E-Mails bleiben, wie sie sind';

  @override
  String get newsletterPageOpened => 'Die Abmeldeseite ist im Browser geöffnet';

  @override
  String get moveToNewsletters => 'Zu Newsletter verschieben';

  @override
  String get movedToNewsletters => 'Zu Newsletter verschoben';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Mit Anhang';

  @override
  String get appearanceTitle => 'Darstellung';

  @override
  String get appearanceSubtitle => 'Wie deine E-Mails aussehen sollen.';

  @override
  String get appearanceTheme => 'Design';

  @override
  String get themeAutomatic => 'Automatisch';

  @override
  String get appearanceDensity => 'Dichte';

  @override
  String get densityComfortable => 'Bequem';

  @override
  String get densityCompact => 'Kompakt';

  @override
  String get appearancePreview => 'Vorschau';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen',
      one: '1 Zeile',
    );
    return '$_temp0';
  }

  @override
  String get appearanceExample => 'Beispiel';

  @override
  String get previewDrawnHere => 'Auf diesem Gerät dargestellt';

  @override
  String get previewKeysPages => '← → Seiten';

  @override
  String get previewKeysPhotos => '← → Fotos';

  @override
  String get meInitials => 'ICH';

  @override
  String get threadSummary => 'Zusammenfassung';

  @override
  String get signatureSheetTitle => 'Signatur';

  @override
  String get signatureManage => 'Verwalten';

  @override
  String get signatureSheetNote =>
      'Die Signatur wechselt automatisch, wenn du das „Von“-Konto änderst.';

  @override
  String get readerEmptyTitle => 'Keine Unterhaltung ausgewählt';

  @override
  String readerEmptyHint(String keys) {
    return 'Klicke auf eine Nachricht, um sie auszuwählen, oder drücke $keys, um alle auszuwählen.';
  }

  @override
  String get hintMove => 'bewegen';

  @override
  String get accountConnected => 'Konto verbunden';

  @override
  String get accountConnectedLead =>
      'Du kannst jetzt mit dem Lesen beginnen: Der Rest kommt, während du Piuma nutzt.';

  @override
  String get connectedDownloading => 'Wird geladen, die neuesten zuerst…';

  @override
  String get connectedUpToDate => 'Aktuell';

  @override
  String get goToInbox => 'Zum Posteingang';

  @override
  String get addAnotherAccount => 'Weiteres Konto hinzufügen';

  @override
  String filterFrom(String name) {
    return 'Von: $name';
  }

  @override
  String get syncLeftUnderMinute => 'unter einer Minute';

  @override
  String syncLeftMinutes(int n) {
    return 'etwa $n Min.';
  }

  @override
  String syncLeftHours(int n) {
    return 'etwa $n Std.';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · $name wird synchronisiert';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Morgen $time senden';
  }

  @override
  String get inboxSections => 'Bereiche des Posteingangs';

  @override
  String get tabPeople => 'Personen';

  @override
  String get tabNotifications => 'Benachrichtigungen';

  @override
  String get zoneNothingNew => 'Nichts Neues';

  @override
  String get tabAll => 'Alle';

  @override
  String get filterUnreadHint => 'Nur E-Mails mit Ungelesenem';

  @override
  String get moveToPeople => 'Zu Personen verschieben';

  @override
  String movedToPeople(String sender) {
    return '$sender kommt ab jetzt zu Personen';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender kommt ab jetzt zu Benachrichtigungen';
  }

  @override
  String get moveToNotifications => 'Zu Benachrichtigungen verschieben';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count ungelesen';
  }

  @override
  String get templatesTitle => 'Vorlagen';

  @override
  String get templatesSearch => 'Vorlagen suchen';

  @override
  String templatesFound(int found, int total) {
    return '$found von $total';
  }

  @override
  String get templatesNone =>
      'Noch keine Vorlagen. Speichere, was du schreibst, als Vorlage.';

  @override
  String templatesNoMatch(String query) {
    return 'Keine Vorlage namens „$query“';
  }

  @override
  String get templateSaveThis => 'Als Vorlage speichern';

  @override
  String get templatesManage => 'Verwalten';

  @override
  String get templateUntitled => 'Unbenannte Vorlage';

  @override
  String templateSavedNote(String name) {
    return 'Als Vorlage „$name“ gespeichert';
  }

  @override
  String get templatesSubtitle => 'Auf diesem Gerät, für alle Konten';

  @override
  String get templatesNew => 'Neue Vorlage';

  @override
  String get templateNameLabel => 'Name';

  @override
  String get templateTextLabel => 'Text';

  @override
  String templateSubjectLine(String subject) {
    return 'Betreff: $subject';
  }

  @override
  String get templateNoSubject => 'Kein Betreff';

  @override
  String get templateSavedAsYouType => 'Wird beim Tippen gespeichert';

  @override
  String get templateNotSaved => 'Die Vorlage konnte nicht gespeichert werden';

  @override
  String get accountNameLabel => 'Name';

  @override
  String get accountDisplayName => 'Anzeigename';

  @override
  String get accountDisplayNameNone => 'Nicht festgelegt';

  @override
  String get accountDefaultSignature => 'Standardsignatur';

  @override
  String get accountConnection => 'Verbindung';

  @override
  String accountWorkingAgo(String ago) {
    return 'Funktioniert · geprüft $ago';
  }

  @override
  String get accountJustNow => 'gerade eben';

  @override
  String accountMinutesAgo(int count) {
    return 'vor $count Min.';
  }

  @override
  String accountAtTime(String time) {
    return 'um $time';
  }

  @override
  String get accountConnecting => 'Verbindung wird hergestellt…';

  @override
  String accountCantSignInSince(String time) {
    return 'Anmeldung seit $time nicht möglich';
  }

  @override
  String get accountPasswordRefused =>
      'Der Server hat das Passwort abgelehnt. Hat es sich geändert?';

  @override
  String get accountEditServers => 'Server bearbeiten';

  @override
  String get accountSignInAlert =>
      'Mich benachrichtigen, wenn die Anmeldung fehlschlägt';

  @override
  String get accountSignInAlertNote =>
      'Eine Mitteilung, beim ersten abgelehnten Passwort';

  @override
  String get accountRemove => 'Konto entfernen';

  @override
  String accountRemoveTitle(String name) {
    return '$name von diesem Gerät entfernen?';
  }

  @override
  String get accountRemoveNote =>
      'Seine E-Mails hier werden gelöscht. Auf dem Server bleibt alles, wie es ist.';

  @override
  String get accountRemoveConfirm => 'Entfernen';

  @override
  String get accountServersTitle => 'Server';

  @override
  String get accountServersSave => 'Speichern';

  @override
  String get accountServersChecking => 'Wird geprüft…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name kann sich nicht anmelden';
  }

  @override
  String get orStartFrom => 'Oder beginne mit';

  @override
  String needsAppPassword(String provider) {
    return '$provider braucht ein App-Passwort';
  }

  @override
  String get fastmailNeedsToken => 'Fastmail braucht ein API-Token';

  @override
  String get gmailStep1 =>
      'Aktiviere die Bestätigung in zwei Schritten in deinem Google-Konto.';

  @override
  String get gmailStep2 =>
      'Öffne App-Passwörter und erstelle eines namens „Piuma“.';

  @override
  String get gmailStep3 => 'Füge die 16 Buchstaben hier ein.';

  @override
  String get openAppPasswords => 'App-Passwörter öffnen';

  @override
  String get icloudStep1 =>
      'Aktiviere die Zwei-Faktor-Authentifizierung für deinen Apple Account.';

  @override
  String get icloudStep2 =>
      'Öffne unter Anmeldung und Sicherheit die App-spezifischen Passwörter und erstelle eines namens „Piuma“.';

  @override
  String get icloudStep3 => 'Füge es hier ein.';

  @override
  String get openAppleAccount => 'Apple Account öffnen';

  @override
  String get fastmailStep1 =>
      'Öffne in Settings den Bereich Privacy & Security und dann Manage API tokens.';

  @override
  String get fastmailStep2 =>
      'Erstelle ein Token namens „Piuma“ mit Zugriff auf Email und Email submission.';

  @override
  String get fastmailStep3 => 'Füge es hier ein.';

  @override
  String get openApiTokens => 'API-Tokens öffnen';

  @override
  String get appPassword => 'App-Passwort';

  @override
  String get apiToken => 'API-Token';

  @override
  String get pecWhichProvider => 'Wer betreibt deine PEC?';

  @override
  String get pecWhichProviderHint =>
      'Zertifizierte E-Mail kommt mit den Servern ihres Anbieters.';

  @override
  String signInToPec(String provider) {
    return 'Bei $provider anmelden';
  }

  @override
  String get pecStep1 => 'Verwende die vollständige PEC-Adresse.';

  @override
  String get pecStep2 =>
      'Verwende das Postfach-Passwort, das du auch fürs Webmail nutzt.';

  @override
  String get verifiedSenderSetting => 'Verifizierten Absender anzeigen';

  @override
  String get verifiedSenderSettingHint =>
      'Markiert Absender, die dein Mailserver mit DKIM, SPF und DMARC geprüft hat.';

  @override
  String get verifiedBadge => 'Verifiziert';

  @override
  String get verifiedSenderLabel => 'Verifizierter Absender';

  @override
  String get ruleFieldBody => 'der Text';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get newFolderName => 'Name des neuen Ordners';

  @override
  String get create => 'Erstellen';

  @override
  String get newFolderFailed =>
      'Der Server hat den Ordner nicht angelegt. Versuche einen anderen Namen.';

  @override
  String get groupsTitle => 'Gruppen';

  @override
  String get groupsSubtitle =>
      'Fasse Adressen aus verschiedenen Konten und Domains zusammen. Jede Gruppe hat ihre eigene Farbe, ihre eigene Signatur und, wenn du willst, ihren eigenen Posteingang.';

  @override
  String get groupsNone =>
      'Noch keine Gruppen. Eine Gruppe fasst Adressen, auch aus verschiedenen Konten, unter einer Farbe und einer Signatur zusammen.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Keine',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Adressen',
      one: '1 Adresse',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Signatur';

  @override
  String get groupSendFromShort => 'Senden von';

  @override
  String get groupNoSignature => 'Keine';

  @override
  String get groupName => 'Gruppenname';

  @override
  String get groupColor => 'Gruppenfarbe';

  @override
  String get groupAddressesHeading => 'Adressen';

  @override
  String get groupAccount => 'Konto';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return 'Konto $name';
  }

  @override
  String groupAliasNote(String email) {
    return 'über $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return '$email aus der Gruppe entfernen';
  }

  @override
  String get groupAddAddress => 'Adresse hinzufügen';

  @override
  String get groupDefaultSignature => 'Standardsignatur';

  @override
  String get groupSendFrom => 'Neue E-Mails senden von';

  @override
  String get groupSeparateInbox => 'Eigener Posteingang';

  @override
  String get groupSeparateOn =>
      'Bekommt einen eigenen Eintrag in der Seitenleiste. Bleibt auch im gemeinsamen Posteingang.';

  @override
  String get groupSeparateOff =>
      'Ihre E-Mails sind nur im gemeinsamen Posteingang.';

  @override
  String get groupNotifyOn => 'Folgt deinen Regeln für Mitteilungen.';

  @override
  String get groupNotifyOff => 'Keine Hinweise für diese Gruppe.';

  @override
  String get groupReplyAsWritten =>
      'Immer von der Adresse antworten, an die geschrieben wurde';

  @override
  String groupReplyOn(String email) {
    return 'Schreibt jemand an $email, geht deine Antwort von $email raus, mit der Signatur dieser Gruppe.';
  }

  @override
  String get groupReplyOnAny =>
      'Schreibt jemand an einen deiner Aliasse, geht deine Antwort von dort raus, mit der Signatur seiner Gruppe.';

  @override
  String get groupReplyOff =>
      'Antworten gehen von der Standardadresse der Gruppe raus.';

  @override
  String get groupNew => 'Neue Gruppe';

  @override
  String get groupNewName => 'Neue Gruppe';

  @override
  String get groupDelete => 'Gruppe löschen';

  @override
  String groupDeleteAsk(String name) {
    return '$name löschen?';
  }

  @override
  String get groupDeleteNote =>
      'Ihre Adressen bleiben in ihren Konten; nur die Gruppe verschwindet.';

  @override
  String get groupYourAddresses => 'Deine Adressen';

  @override
  String get groupMovesHere => 'In einer anderen Gruppe: wechselt hierher';

  @override
  String get groupFoundInSent => 'In deinen gesendeten E-Mails gefunden';

  @override
  String get groupNewAlias => 'Neuer Alias';

  @override
  String get groupNewAliasHint => 'name@domain.de';

  @override
  String get groupAliasOn => 'über';

  @override
  String get groupAddAlias => 'Hinzufügen';

  @override
  String get groupAliasInvalid =>
      'Das sieht nicht nach einer E-Mail-Adresse aus.';

  @override
  String get fromAutomatic => 'Automatisch';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Gewählt, weil $name an $email geschrieben hat';
  }

  @override
  String rowWrittenTo(String email) {
    return 'an $email';
  }

  @override
  String get groupsAll => 'Alle Gruppen';

  @override
  String groupExpand(String name) {
    return '$name aufklappen';
  }

  @override
  String groupCollapse(String name) {
    return '$name zuklappen';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses Adressen',
      one: '1 Adresse',
    );
    return '$_temp0 · $unread ungelesen';
  }

  @override
  String groupsAllLine(int groups, int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups Gruppen',
      one: '1 Gruppe',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses Adressen',
      one: '1 Adresse',
    );
    return '$_temp0 · $_temp1 · $unread ungelesen';
  }

  @override
  String groupOnly(String email) {
    return 'Nur $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Nur $email. Ganze Gruppe anzeigen';
  }

  @override
  String get groupSheetTitle => 'Anzeigen';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses Adressen',
      one: '1 Adresse',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups Gruppen',
      one: '1 Gruppe',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get groupSheetLabel => 'Gruppe wählen';

  @override
  String get groupManage => 'Gruppen verwalten';

  @override
  String get groupTitleAll => 'Gruppe: alle. Gruppe wechseln';

  @override
  String groupTitleOne(String name) {
    return 'Gruppe: $name. Gruppe wechseln';
  }

  @override
  String get syncTitle => 'Geräte und Synchronisierung';

  @override
  String get syncSubtitle =>
      'Deine Einstellungen auf jedem Gerät, Ende-zu-Ende-verschlüsselt';

  @override
  String get syncOff => 'Aus · nur dieses Gerät';

  @override
  String get syncOffBody =>
      'Hab deine Konten, Gruppen, Signaturen und Einstellungen auf jedem Gerät. Sie werden hier verschlüsselt und in einem versteckten Ordner eines deiner Postfächer gespeichert. Kein Server.';

  @override
  String get syncOffNote =>
      'Passwörter reisen nur in der verschlüsselten Kopie.';

  @override
  String get syncStoreIn => 'Speichern in';

  @override
  String get syncMailbox => 'Sync-Postfach';

  @override
  String get syncMoving => 'Wird verschoben…';

  @override
  String get syncFailTaken =>
      'Dieses Postfach enthält bereits einen anderen Sync-Bereich.';

  @override
  String get syncTurnOn => 'Synchronisierung einschalten';

  @override
  String get syncAllSynced => 'Alles synchronisiert';

  @override
  String get syncNotYet => 'Noch nicht synchronisiert';

  @override
  String syncOnBody(String name) {
    return 'Konten, Gruppen, Signaturen und Einstellungen werden verschlüsselt und in deinem Postfach $name gespeichert. Kein Server.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · versteckter Ordner · Ende-zu-Ende-verschlüsselt';
  }

  @override
  String get syncDevices => 'Verknüpfte Geräte';

  @override
  String get syncThisDevice => 'Dieses Gerät';

  @override
  String get syncActiveNow => 'Jetzt aktiv';

  @override
  String syncActive(String ago) {
    return 'Aktiv $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor 1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'gestern';

  @override
  String syncDaysAgo(int count) {
    return 'vor $count Tagen';
  }

  @override
  String get syncUnlink => 'Trennen';

  @override
  String syncUnlinkName(String name) {
    return '$name trennen';
  }

  @override
  String syncUnlinkAsk(String name) {
    return '$name trennen?';
  }

  @override
  String get syncUnlinkNote =>
      'Es behält, was es jetzt hat, bekommt aber keine Änderungen mehr. Deine Wiederherstellungsphrase ändert sich ebenfalls: Du notierst die neue.';

  @override
  String get syncLinkNew => 'Neues Gerät verknüpfen';

  @override
  String syncLinkBody(String email) {
    return 'Öffne Piuma auf dem neuen Gerät, wähle „Ich nutze Piuma schon auf einem anderen Gerät“ und melde dich bei $email an. Es zeigt 6 Ziffern, nach denen dieses Gerät fragt.';
  }

  @override
  String get syncLinkWaiting => 'Warte auf das neue Gerät…';

  @override
  String get syncLinkScan =>
      'Öffne Piuma auf dem neuen Telefon, wähle „Ich nutze Piuma schon auf einem anderen Gerät“ und scanne diesen Code.';

  @override
  String get syncLinkQrLabel => 'QR-Code zum Verknüpfen eines neuen Geräts';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · neuer Code in $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return 'Keine Kamera? Melde dich auf dem neuen Gerät bei $email an: Es zeigt 6 Ziffern, nach denen dieses Gerät fragt.';
  }

  @override
  String syncLinked(String name) {
    return '$name verknüpft';
  }

  @override
  String get syncPhraseRow => 'Wiederherstellungsphrase';

  @override
  String get syncPhraseRowLine =>
      'Öffnet deinen Bereich, wenn alle Geräte verloren sind';

  @override
  String get syncShow => 'Anzeigen';

  @override
  String get syncPhraseTitle => 'Deine Wiederherstellungsphrase';

  @override
  String get syncPhraseBody =>
      'Wenn du alle Geräte verlierst, sind diese 24 Wörter der einzige Weg zurück in deinen Bereich. Schreib sie auf Papier und bewahre sie sicher auf. Piuma kann sie nicht für dich wiederherstellen.';

  @override
  String get syncPhraseNewTitle => 'Deine neue Wiederherstellungsphrase';

  @override
  String syncPhraseNewBody(String name) {
    return '$name kann deinen Bereich nicht mehr öffnen, und die alte Phrase funktioniert nicht mehr. Schreib stattdessen diese 24 Wörter auf Papier.';
  }

  @override
  String get syncPhraseWarn =>
      'Wer diese Wörter hat, kann deinen Bereich lesen.';

  @override
  String get syncPhraseDone => 'Ich habe sie notiert';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Neues Telefon möchte sich verbinden',
      'tablet': 'Neues Tablet möchte sich verbinden',
      'other': 'Neuer Computer möchte sich verbinden',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · angefragt $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Gib die 6 Ziffern ein, die das Telefon zeigt.',
      'tablet': 'Gib die 6 Ziffern ein, die das Tablet zeigt.',
      'other': 'Gib die 6 Ziffern ein, die der Computer zeigt.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'Die 6 Ziffern';

  @override
  String get syncNotMe => 'Nicht ich';

  @override
  String get syncApprove => 'Bestätigen';

  @override
  String get syncApproving => 'Wird bestätigt…';

  @override
  String syncFailOffline(String email) {
    return '$email war nicht erreichbar. Versuche es erneut, wenn du online bist.';
  }

  @override
  String get syncFailExpired =>
      'Die Anfrage ist abgelaufen. Frage erneut vom neuen Gerät aus an.';

  @override
  String get syncFailOther => 'Etwas ist schiefgelaufen. Versuche es erneut.';

  @override
  String get syncRowOn => 'An';

  @override
  String get syncRowOff => 'Aus';

  @override
  String get pairAlready => 'Ich nutze Piuma schon auf einem anderen Gerät';

  @override
  String get pairAlreadyOn =>
      'Melde dich bei einem deiner Postfächer an. Wenn es deinen Bereich enthält, verknüpfst du als Nächstes dieses Gerät.';

  @override
  String get pairLinkTitle => 'Dieses Telefon verknüpfen';

  @override
  String get pairLinkBody =>
      'Öffne am Computer Einstellungen › Geräte und Synchronisierung › Neues Gerät verknüpfen und scanne den angezeigten Code.';

  @override
  String get pairScan => 'Code scannen';

  @override
  String get pairSignInInstead => 'Stattdessen anmelden';

  @override
  String get pairScanHint => 'Richte die Kamera auf den Code am Computer';

  @override
  String get pairScanWhere =>
      'Einstellungen › Geräte und Synchronisierung › Neues Gerät verknüpfen';

  @override
  String get pairNoCamera =>
      'Piuma darf die Kamera nicht nutzen. Erlaube es in den Systemeinstellungen oder melde dich stattdessen an.';

  @override
  String get pairLastStep => 'Ein letzter Schritt';

  @override
  String get pairLastStepBody =>
      'Melde dich bei dem Postfach an, das deinen Bereich enthält. Die anderen Konten kommen von allein.';

  @override
  String get pairConfirmsOwn =>
      'Dein Computer bestätigt von selbst: Er hat dir den Code gezeigt.';

  @override
  String get pairLink => 'Verknüpfen';

  @override
  String get pairLinking => 'Wird verknüpft…';

  @override
  String get pairFoundTitle => 'Wir haben deinen Bereich gefunden';

  @override
  String pairFoundBody(String email) {
    return 'Das Postfach $email enthält eine verschlüsselte Kopie deiner Einstellungen. Nur deine Geräte können sie lesen.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Konten',
      one: 'Konto',
    );
    return '$_temp0';
  }

  @override
  String pairGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gruppen',
      one: 'Gruppe',
    );
    return '$_temp0';
  }

  @override
  String pairSignatures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Signaturen',
      one: 'Signatur',
    );
    return '$_temp0';
  }

  @override
  String pairEncrypted(String when) {
    return 'Ende-zu-Ende-verschlüsselt · aktualisiert $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'Bestätige zur Sicherheit auf einem bereits verknüpften Gerät: $name, aktiv $ago.';
  }

  @override
  String get pairShowCode => 'Code anzeigen';

  @override
  String get pairUsePhrase => 'Wiederherstellungsphrase verwenden';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Auf deinem Telefon bestätigen',
      'tablet': 'Auf deinem Tablet bestätigen',
      'other': 'Auf deinem Computer bestätigen',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Öffne Piuma auf $name und gib den Code ein.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Code $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Läuft ab in $time';
  }

  @override
  String pairWaiting(String name) {
    return 'Warte auf die Bestätigung von $name…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name zeigt „$title“';
  }

  @override
  String get pairStep2 => 'Gib die 6 Ziffern ein und tippe auf Bestätigen';

  @override
  String get pairExpired => 'Der Code ist abgelaufen.';

  @override
  String pairRefused(String name) {
    return '$name hat angegeben, dass du das nicht warst.';
  }

  @override
  String get pairWrongCode => 'Der dort eingegebene Code war nicht dieser.';

  @override
  String get pairNewCode => 'Neuen Code anzeigen';

  @override
  String get pairPhraseTitle => 'Wiederherstellungsphrase';

  @override
  String get pairPhraseBody =>
      'Gib die 24 notierten Wörter in der richtigen Reihenfolge ein, getrennt durch Leerzeichen.';

  @override
  String pairPhraseCount(int count) {
    return '$count von 24 Wörtern';
  }

  @override
  String get pairPhraseWrong =>
      'Diese Wörter öffnen deinen Bereich nicht. Prüfe sie und versuche es erneut.';

  @override
  String get pairContinue => 'Weiter';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Telefon verknüpft',
      'tablet': 'Tablet verknüpft',
      'other': 'Computer verknüpft',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody =>
      'Das kam aus deinem verschlüsselten Bereich herüber.';

  @override
  String get pairDoneAccounts => 'Konten';

  @override
  String get pairDoneGroups => 'Gruppen';

  @override
  String get pairDoneSettings => 'Signaturen und Einstellungen synchronisiert';

  @override
  String get pairSynced => 'Synchronisiert';

  @override
  String pairStepOf(int step) {
    return 'Schritt $step von 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'heute um $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'gestern um $time';
  }

  @override
  String pairOnDay(String day) {
    return 'am $day';
  }

  @override
  String get keyOpenWindow => 'in neuem Fenster öffnen';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Auf $count Geräten synchronisiert',
      one: 'Auf 1 Gerät synchronisiert',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters =>
      'Wenn ein Newsletter vor mehr als 7 Tagen gelesen wurde';

  @override
  String get ruleBuiltIn => 'Eingebaut · alle Konten';

  @override
  String get syncTurnOff => 'Synchronisierung auf diesem Gerät ausschalten';

  @override
  String get syncTurnOffAsk => 'Synchronisierung auf diesem Gerät ausschalten?';

  @override
  String syncTurnOffOne(String name) {
    return 'Dieses Gerät verlässt deinen Bereich und bekommt keine Änderungen mehr. Seine Konten und E-Mails bleiben hier. $name synchronisiert weiter.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'Dieses Gerät verlässt deinen Bereich und bekommt keine Änderungen mehr. Seine Konten und E-Mails bleiben hier. $names synchronisieren weiter.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'Dieses Gerät verlässt deinen Bereich und bekommt keine Änderungen mehr. Seine Konten und E-Mails bleiben hier. Es ist dein einziges Gerät: Die verschlüsselte Kopie in $email wird ebenfalls gelöscht.';
  }

  @override
  String get syncTurnOffButton => 'Synchronisierung ausschalten';

  @override
  String get listAnd => 'und';

  @override
  String get composeDropFiles => 'Zum Anhängen loslassen';

  @override
  String get serverType => 'Servertyp';

  @override
  String get imapAndSmtp => 'IMAP und SMTP';

  @override
  String get jmapServer => 'JMAP-Server';

  @override
  String get jmapServerHint =>
      'Der Name des Servers oder die vollständige Adresse seiner JMAP-Sitzung.';

  @override
  String get jmapSignsIn =>
      'Ein Server liest, sendet und holt neue E-Mails auf einmal. Du meldest dich mit deiner Adresse an.';

  @override
  String get shortcutsTitle => 'Tastenkürzel';

  @override
  String shortcutsLine(String keys) {
    return 'Nur das Wichtigste. Alles andere findest du unter $keys.';
  }

  @override
  String get shortcutsTable => 'Tastaturkürzel';

  @override
  String get shortcutPalette => 'Befehlspalette';

  @override
  String ruleSuggest(String name, String folder) {
    return 'Du verschiebst E-Mails von $name oft nach $folder. Regel erstellen?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Auf dem Gerät vorgeschlagen · $count Verschiebungen im letzten Monat',
      one: 'Auf dem Gerät vorgeschlagen · 1 Verschiebung im letzten Monat',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Weiterleiten';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Weitergeleitete Nachricht ----------\nVon: $from\nDatum: $date\nAn: $to\nBetreff: $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date um $time';
  }

  @override
  String get folderWaiting => 'Wartend';

  @override
  String waitingSummary(int count) {
    return '$count gesendet · noch keine Antwort';
  }

  @override
  String get waitingNoReply => 'Noch keine Antwort';

  @override
  String get waitingTo => 'An ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'heute';

  @override
  String get waitingYesterday => 'gestern';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gesendete E-Mails warten auf Antwort',
      one: '1 gesendete E-Mail wartet auf Antwort',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Erneut schreiben';

  @override
  String get stopWaiting => 'Nicht mehr warten';

  @override
  String get stoppedWaiting => 'Aus Wartend entfernt. Sie bleibt in Gesendet.';

  @override
  String get remindMe => 'Erinnern';

  @override
  String get remindTitle => 'Erinnern, wenn niemand antwortet';

  @override
  String get remindTomorrow => 'Morgen';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count Tagen',
      one: 'In 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'Nächste Woche';

  @override
  String get remindPickDate => 'Datum wählen…';

  @override
  String get remindNever => 'Nicht erinnern';

  @override
  String remindChipToday(String time) {
    return 'Erinnern um $time';
  }

  @override
  String get remindChipTomorrow => 'Morgen erinnern';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count Tagen erinnern',
      one: 'In 1 Tag erinnern',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Am $date erinnern';
  }

  @override
  String remindAt(String when) {
    return 'Erinnern $when';
  }

  @override
  String remindNoReply(String name) {
    return 'Keine Antwort von $name';
  }

  @override
  String get remindSentToday => 'heute gesendet';

  @override
  String get remindSentYesterday => 'gestern gesendet';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen gesendet',
      one: 'vor 1 Tag gesendet',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Geteilte Anhänge';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge',
      one: '1 Anhang',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles => 'Noch keine Anhänge von dieser Person.';

  @override
  String get senderAddresses => 'Adressen';

  @override
  String senderAddressNote(String account, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails',
      one: '1 E-Mail',
    );
    return '$account · $_temp0';
  }

  @override
  String get senderCopyAddress => 'Adresse kopieren';

  @override
  String get senderRules => 'Regeln und Ordner';

  @override
  String get senderContent => 'Inhalte des Absenders';

  @override
  String folderReorder(String name) {
    return 'Ziehen, um $name neu anzuordnen';
  }

  @override
  String get folderMoveUp => 'Nach oben';

  @override
  String get folderMoveDown => 'Nach unten';

  @override
  String get ruleUnopenedNewsletters => 'Newsletter';

  @override
  String get ruleUnopenedFor => ' ungeöffnet seit ';

  @override
  String get ruleUnopenedDays => '30 Tagen';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails archiviert',
      one: '1 E-Mail archiviert',
      zero: 'alle Konten',
    );
    return 'Jede Nacht · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'Regeln laufen auf diesem Gerät und werden auf all deinen Geräten synchronisiert';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'Regeln laufen auf diesem Gerät und werden auf all deinen Geräten synchronisiert · aktualisiert $ago';
  }

  @override
  String get calSynced =>
      'Verbindungen werden auf all deinen Geräten synchronisiert; Passwörter reisen verschlüsselt und bleiben im Schlüsselbund des Systems.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aktualisiert alle $count Stunden',
      one: 'aktualisiert stündlich',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'aktualisiert alle $count Tage',
      one: 'aktualisiert täglich',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'aktualisiert wöchentlich';

  @override
  String get showOriginalLayout => 'Originallayout anzeigen';

  @override
  String get originalLayout => 'Originallayout';

  @override
  String get originalLayoutBar =>
      'Originallayout · Bilder und Links folgen deinen Datenschutzeinstellungen';

  @override
  String get backToReadingView => 'Zurück zur Leseansicht';

  @override
  String get readingView => 'Leseansicht';

  @override
  String get replyFromLabel => 'Antworten von';

  @override
  String replyFromSignature(String name) {
    return 'Signatur $name';
  }

  @override
  String get noticeReplyHint => 'Antwort schreiben…';

  @override
  String get labelsHeading => 'Labels';

  @override
  String get labelsSection => 'LABELS';

  @override
  String get labelAction => 'Label';

  @override
  String get labelAdd => '+ Label';

  @override
  String get labelNew => 'Neues Label';

  @override
  String get labelFind => 'Label suchen oder erstellen';

  @override
  String labelCreate(String name) {
    return '„$name“ erstellen';
  }

  @override
  String labelRemove(String name) {
    return 'Label $name entfernen';
  }

  @override
  String labelEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails',
      one: '1 E-Mail',
    );
    return '$_temp0';
  }

  @override
  String labelAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Konten',
      one: '1 Konto',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account speichert keine Labels auf dem Server, daher bleiben seine Labels auf diesem Gerät.';
  }

  @override
  String get hintLabel => 'Label';

  @override
  String get labelName => 'Name des Labels';

  @override
  String get labelEdit => 'Label bearbeiten';

  @override
  String get labelSave => 'Speichern';

  @override
  String get labelCreateButton => 'Erstellen';

  @override
  String get labelDelete => 'Label löschen';

  @override
  String get labelDeleteNote =>
      'Es wird von allen E-Mails entfernt; die E-Mails bleiben, wo sie sind.';

  @override
  String get labelColorAmber => 'Bernstein';

  @override
  String get labelColorTeal => 'Petrol';

  @override
  String get labelColorCoral => 'Koralle';

  @override
  String get labelColorBlue => 'Blau';

  @override
  String get labelColorViolet => 'Violett';

  @override
  String get labelMenu => 'Label…';

  @override
  String get ruleDoLabel => 'Label vergeben';

  @override
  String get ruleTrayLabel => 'Label';

  @override
  String get rulePickLabel => 'ein Label';

  @override
  String get ruleNoLabels =>
      'Noch keine Labels: Erstelle eines mit + Label unter Ordner und Labels.';

  @override
  String get foldersAndLabelsHeading => 'Ordner und Labels';

  @override
  String get labelsCardTitle => 'Labels';

  @override
  String get labelsCardDetail => 'für alle Konten gemeinsam';

  @override
  String get labelsNone => 'Noch keine Labels.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ordner',
      one: '1 Ordner',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Labels',
      one: '1 Label',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Absenderbilder';

  @override
  String get senderPicturesSettingHint =>
      'Fotos deiner Kontakte und verifizierte Firmenlogos statt der Buchstaben.';

  @override
  String get websiteIconsSetting => 'Website-Symbole';

  @override
  String get websiteIconsSettingHint =>
      'Für Firmen ohne Logo. Jede Website sieht einmal deine IP-Adresse.';

  @override
  String tabletInboxUnread(int count) {
    return 'Posteingang, $count ungelesen';
  }

  @override
  String tabletAccount(String name, String email) {
    return 'Konto $name, $email';
  }

  @override
  String get tabletSearch => 'E-Mails durchsuchen';

  @override
  String get tabletSearchHint => 'Suchen oder Befehl ausführen';

  @override
  String get vaultTrackParcel => 'Paket verfolgen';

  @override
  String get vaultTrackingCopied => 'Sendungsnummer kopiert';

  @override
  String get vaultNeedsYou => 'Braucht dich';

  @override
  String get vaultNext => 'Als Nächstes';

  @override
  String get vaultOnTheWay => 'Unterwegs';

  @override
  String get vaultEverything => 'Alles';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sachen brauchen dich',
      one: '1 Sache braucht dich',
    );
    return '$_temp0';
  }

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'heute ein Flug',
      'train': 'heute ein Zug',
      'ferry': 'heute eine Fähre',
      'bus': 'heute ein Bus',
      'stay': 'heute ein Check-in',
      'parking': 'heute Parken',
      'car': 'heute ein Mietwagen',
      'event': 'heute ein Event',
      'table': 'heute ein Tisch',
      'other': 'heute eine Buchung',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Flug',
      'train': 'Zug',
      'ferry': 'Fähre',
      'bus': 'Bus',
      'stay': 'Check-in',
      'parking': 'Parken',
      'car': 'Mietwagen',
      'event': 'Event',
      'table': 'Tisch',
      'other': 'Buchung',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Pakete';

  @override
  String get vaultCatSpending => 'Ausgaben';

  @override
  String get vaultCatTrips => 'Reisen';

  @override
  String get vaultCatSales => 'Verkäufe';

  @override
  String get vaultCatSubscriptions => 'Abos';

  @override
  String get vaultCatReturns => 'Rücksendungen und Garantie';

  @override
  String get vaultCatDeadlines => 'Fristen';

  @override
  String get vaultCatBookings => 'Buchungen';

  @override
  String get vaultCatVouchers => 'Gutscheine und Codes';

  @override
  String get vaultCatDocuments => 'Dokumente';

  @override
  String get vaultCatCertified => 'Zertifizierte E-Mail';

  @override
  String vaultOnWayCount(int count) {
    return '$count unterwegs';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count abzuholen';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zugestellt',
      one: '1 zugestellt',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'Gerade auf Reisen';

  @override
  String vaultNextWhen(String when) {
    return 'Als Nächstes: $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vergangene Reisen',
      one: '1 vergangene Reise',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count zu versenden';
  }

  @override
  String vaultSoldCount(int count) {
    return '$count verkauft';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money pro Monat';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abos',
      one: '1 Abo',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Rücksendungen, die erste bis $day',
      one: '1 Rücksendung bis $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count mit Garantie';
  }

  @override
  String vaultCodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Codes',
      one: '1 Code',
    );
    return '$_temp0';
  }

  @override
  String vaultCountMoney(int count, String money) {
    return '$count · $money';
  }

  @override
  String vaultCertDelivered(int count) {
    return '$count zugestellt';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Zahlung fehlgeschlagen · $who';
  }

  @override
  String get vaultPaymentFailed => 'Zahlung fehlgeschlagen';

  @override
  String vaultWasDue(String when) {
    return 'War fällig $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'Versenden bis $when';
  }

  @override
  String get vaultToShip => 'Zu versenden';

  @override
  String get vaultYouSend => 'Du versendest';

  @override
  String vaultSoldOn(String where) {
    return 'verkauft auf $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'Abholen bis $when';
  }

  @override
  String get vaultReadyPickup => 'Abholbereit';

  @override
  String vaultRenewsWhen(String when) {
    return 'Verlängert sich $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Endet $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money pro Woche',
      'month': '$money pro Monat',
      'year': '$money pro Jahr',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'seit $day';
  }

  @override
  String get vaultUpdatePayment => 'Zahlung aktualisieren';

  @override
  String get vaultCoach => 'Wagen';

  @override
  String get vaultTicket => 'Ticket';

  @override
  String vaultInHours(int hours) {
    return 'in $hours Std.';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'in $minutes Min.';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Pakete diese Woche zugestellt',
      one: '1 Paket diese Woche zugestellt',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Ausgegeben im $month';
  }

  @override
  String vaultReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Belege',
      one: '1 Beleg',
    );
    return '$_temp0';
  }

  @override
  String get vaultExportMonth => 'Monat exportieren';

  @override
  String vaultSpentTab(String money) {
    return 'Ausgaben · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Einnahmen · $money';
  }

  @override
  String vaultVia(String service) {
    return 'über $service';
  }

  @override
  String get vaultSpendingNote =>
      'Auf dem Gerät aus Belegen und Rechnungen gelesen';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file und $count PDFs in Downloads gespeichert',
      one: '$file und 1 PDF in Downloads gespeichert',
      zero: '$file in Downloads gespeichert',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'Der Monat konnte nicht exportiert werden';

  @override
  String get vaultPrevMonth => 'Vorheriger Monat';

  @override
  String get vaultNextMonth => 'Nächster Monat';

  @override
  String get vaultNothingThisMonth => 'Keine Belege in diesem Monat.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Abos · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Datum,Wer,Was,Betrag,Währung,Bezahlt mit,Datei,USt-IdNr.';

  @override
  String vaultComingUp(int count) {
    return '$count anstehend';
  }

  @override
  String get vaultNoTrips => 'Keine Reisen geplant';

  @override
  String get vaultPastTrips => 'Vergangene Reisen';

  @override
  String vaultThisYear(int count) {
    return '$count in diesem Jahr';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'Jetzt · zurück $when';
  }

  @override
  String get vaultLegDone => 'Erledigt';

  @override
  String vaultUntilTime(String time) {
    return 'Bis $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Bis $day';
  }

  @override
  String get vaultTripsNote =>
      'Züge, Fähren, Flüge, Unterkünfte, Parken und Tickets';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nächte',
      one: '1 Nacht',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'ab $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'Wagen $coach, Platz $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'Platz $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'Code $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Flug $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Verkauft auf $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Verkauft auf $who';
  }

  @override
  String get vaultSaleOnWay => 'Unterwegs';

  @override
  String get vaultSaleReceived => 'Angekommen';

  @override
  String get vaultPaidOut => 'Ausgezahlt';

  @override
  String get vaultCanGoBack => 'Kann noch zurück';

  @override
  String get vaultUnderWarranty => 'Mit Garantie';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days Tage für die Rücksendung';
  }

  @override
  String vaultBought(String day) {
    return 'gekauft $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Garantie $month';
  }

  @override
  String get vaultCodeCopied => 'Code kopiert';

  @override
  String get vaultCopyCode => 'Code kopieren';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Gehaltsabrechnung',
      'statement': 'Kontoauszug',
      'tax': 'Steuerformular',
      'contract': 'Vertrag',
      'other': 'Dokument',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Datei öffnen';

  @override
  String vaultBookingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Buchungen',
      one: '1 Buchung',
    );
    return '$_temp0';
  }

  @override
  String vaultDocumentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dokumente',
      one: '1 Dokument',
    );
    return '$_temp0';
  }

  @override
  String get vaultCategoryEmpty => 'Gerade ist hier nichts.';

  @override
  String get vaultFlagged => 'braucht dich';

  @override
  String get suggestWroteTo => 'Geschrieben an';

  @override
  String get suggestWroteToYou => 'Hat dir geschrieben';

  @override
  String get readerEmptyTap => 'Tippe auf eine Nachricht, um sie zu lesen.';

  @override
  String get noticeAwayTitle => 'Während du weg warst';

  @override
  String noticeAwayEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails',
      one: '1 E-Mail',
    );
    return '$_temp0';
  }

  @override
  String noticeAwayPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count von Personen',
      one: '1 von einer Person',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Wochenenden, ganztägig';

  @override
  String get quietWeekendsHint => 'Samstag und Sonntag';

  @override
  String get quietWhile => 'Während der Ruhezeit';

  @override
  String get quietWhileHint =>
      'Keine Mitteilungen fasst am Ende alles zusammen';

  @override
  String get quietNoSound => 'Ohne Ton';

  @override
  String get quietNoNotices => 'Keine Mitteilungen';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · klingelt wie gewohnt';
  }

  @override
  String get quietAccountsHint =>
      'Ausgeschaltete Konten klingeln während der Ruhezeiten wie gewohnt.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'Arabisch',
      'bg': 'Bulgarisch',
      'ca': 'Katalanisch',
      'cs': 'Tschechisch',
      'zh': 'Chinesisch',
      'da': 'Dänisch',
      'de': 'Deutsch',
      'el': 'Griechisch',
      'en': 'Englisch',
      'et': 'Estnisch',
      'fi': 'Finnisch',
      'fr': 'Französisch',
      'he': 'Hebräisch',
      'hi': 'Hindi',
      'hr': 'Kroatisch',
      'hu': 'Ungarisch',
      'id': 'Indonesisch',
      'it': 'Italienisch',
      'ja': 'Japanisch',
      'ko': 'Koreanisch',
      'lt': 'Litauisch',
      'lv': 'Lettisch',
      'nl': 'Niederländisch',
      'nb': 'Norwegisch',
      'pl': 'Polnisch',
      'pt': 'Portugiesisch',
      'ro': 'Rumänisch',
      'ru': 'Russisch',
      'sk': 'Slowakisch',
      'sl': 'Slowenisch',
      'es': 'Spanisch',
      'sr': 'Serbisch',
      'sv': 'Schwedisch',
      'th': 'Thailändisch',
      'tr': 'Türkisch',
      'uk': 'Ukrainisch',
      'vi': 'Vietnamesisch',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Auf $language geschrieben';
  }

  @override
  String get translateAction => 'Übersetzen';

  @override
  String translateGetting(String from, String to) {
    return '$from–$to wird geladen';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return '$from–$to wird geladen · $size';
  }

  @override
  String get translating => 'Wird übersetzt…';

  @override
  String translatedFrom(String language) {
    return 'Übersetzt aus: $language · auf diesem Gerät';
  }

  @override
  String get translatedShort => 'Übersetzt';

  @override
  String get translateShowOriginal => 'Original anzeigen';

  @override
  String get translateOriginalShort => 'Original';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'Lade zum Übersetzen zuerst $from und $to.';
  }

  @override
  String get translateFailed =>
      'Diese E-Mail konnte nicht übersetzt werden. Versuche es erneut.';

  @override
  String get appearanceTranslateInto => 'Übersetzen in';

  @override
  String get translateIntoApp => 'App-Sprache';

  @override
  String get translateIntoHint =>
      'E-Mails in anderen Sprachen bieten Übersetzen an. Das passiert auf diesem Gerät.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Entfernen';

  @override
  String translateRemovePair(String pair) {
    return '$pair entfernen';
  }

  @override
  String get printEmail => 'Drucken…';

  @override
  String printTooltip(String keys) {
    return 'Drucken… $keys';
  }

  @override
  String get printOrSavePdf => 'Drucken oder als PDF sichern';

  @override
  String get reportSpam => 'Als Spam melden';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen als Spam gemeldet',
      one: 'Als Spam gemeldet',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'Kein Spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen in den Posteingang verschoben',
      one: 'In den Posteingang verschoben',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Datum';

  @override
  String printAttachments(String files) {
    return 'Anhänge: $files';
  }

  @override
  String get helpTitle => 'Hilfe und Feedback';

  @override
  String get helpSubtitle =>
      'Melde ein Problem oder schlage eine Idee vor. Nichts wird ohne dich gesendet.';

  @override
  String get reportProblem => 'Problem melden';

  @override
  String get reportThisProblem => 'Dieses Problem melden';

  @override
  String get reportCantAddAccount => 'Ich kann mein Konto nicht hinzufügen';

  @override
  String get suggestIdea => 'Idee vorschlagen';

  @override
  String get shakeToReport => 'Schütteln zum Melden';

  @override
  String get shakeToReportHint =>
      'Schüttle das Telefon auf einem beliebigen Bildschirm';

  @override
  String get yourReports => 'Deine Meldungen';

  @override
  String get reportNone => 'Noch keine Meldungen.';

  @override
  String get reportTitle => 'Meldung';

  @override
  String get reportKindProblem => 'Problem';

  @override
  String get reportKindIdea => 'Idee';

  @override
  String get reportTitleField => 'Titel';

  @override
  String get reportTitleHint => 'In wenigen Worten';

  @override
  String get reportProblemField => 'Was passiert ist';

  @override
  String get reportIdeaField => 'Was und warum';

  @override
  String get reportDescriptionHint =>
      'Was du getan hast und was du erwartet hast';

  @override
  String get reportScreenshot => 'Bildschirmfoto dieses Bildschirms';

  @override
  String get reportScreenshotWindow => 'Bildschirmfoto dieses Fensters';

  @override
  String get reportScreenshotOff => 'Aus: es könnte deine E-Mails zeigen';

  @override
  String get reportScreenshotOn => 'Tippe auf das Bild, um Teile auszublenden';

  @override
  String get reportLog => 'App-Protokoll';

  @override
  String get reportLogHint => 'Keine Adressen oder Betreffzeilen';

  @override
  String get reportDevice => 'Geräte- und App-Infos';

  @override
  String get reportDeviceHint => 'Version, Modell, Sprache';

  @override
  String get reportAlways => 'Immer';

  @override
  String get reportSeeSent => 'Ansehen, was gesendet wird';

  @override
  String get reportSend => 'Senden';

  @override
  String get reportQueued => 'Meldung in der Warteschlange';

  @override
  String get reportNotKept => 'Die Meldung konnte nicht gespeichert werden';

  @override
  String get reportWhatsSent => 'Was gesendet wird';

  @override
  String get reportSectionReport => 'Meldung';

  @override
  String get reportSectionDevice => 'Gerät';

  @override
  String get reportSectionScreenshot => 'Bildschirmfoto';

  @override
  String get reportHideParts => 'Teile ausblenden';

  @override
  String get reportDragToBlur => 'Ziehen zum Verwischen';

  @override
  String get reportDone => 'Fertig';

  @override
  String get reportStatusQueued => 'In der Warteschlange';

  @override
  String get reportStatusSending => 'Wird gesendet';

  @override
  String get reportStatusFailed => 'Fehlgeschlagen';

  @override
  String get reportStatusEmailed => 'Per E-Mail gesendet';

  @override
  String get reportWaitOffline => 'wartet auf ein Netzwerk';

  @override
  String get reportWaitTurn => 'geht gleich raus';

  @override
  String reportWaitAt(String time) {
    return 'geht um $time raus';
  }

  @override
  String get reportWaitPaused => 'geht später heute oder morgen raus';

  @override
  String get reportTapRetry => 'tippen für neuen Versuch';

  @override
  String get reportTryAgain => 'Erneut versuchen';

  @override
  String get reportByEmail => 'Stattdessen per E-Mail senden';

  @override
  String get reportDelete => 'Löschen';

  @override
  String get reportOptions => 'Optionen der Meldung';

  @override
  String get crashLine => 'Piuma wurde unerwartet beendet. Meldung senden?';

  @override
  String get crashReport => 'Melden';

  @override
  String get crashDismiss => 'Schließen';

  @override
  String reportStatusSent(int number) {
    return 'Gesendet #$number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines Zeilen',
      one: '1 Zeile',
    );
    return 'App-Protokoll · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Hilfe';

  @override
  String get awayTitle => 'Abwesenheitsnotiz';

  @override
  String get awayNote =>
      'Antwortet für dich, auch wenn die App geschlossen ist';

  @override
  String get awayFrom => 'Von';

  @override
  String get awayToInline => 'bis';

  @override
  String get awayTo => 'Bis';

  @override
  String get awaySubject => 'Betreff';

  @override
  String get awayMessage => 'Nachricht';

  @override
  String get awayEndsNote =>
      'Endet von selbst nach dem letzten Tag. Lass \"bis\" leer, damit sie aktiv bleibt, bis du sie ausschaltest.';

  @override
  String awaySubjectUntil(String date) {
    return 'Abwesend bis $date';
  }

  @override
  String get awaySubjectPlain => 'Abwesend';

  @override
  String awayBodyUntil(String date) {
    return 'Hallo, ich bin bis $date nicht da und antworte, sobald ich zurück bin.';
  }

  @override
  String get awayBodyPlain =>
      'Hallo, ich bin nicht da und antworte, sobald ich zurück bin.';

  @override
  String get awayToday => 'Heute';

  @override
  String get awayNoEnd => 'Kein Ende';

  @override
  String get awayPickFrom => 'Erster Tag';

  @override
  String get awayPickTo => 'Letzter Tag';

  @override
  String get awayKeepOn => 'Aktiv lassen, bis ich sie ausschalte';

  @override
  String get awayOtherFilters =>
      'Kann nicht zusammen mit deinen bestehenden Filtern eingeschaltet werden. Schalte sie zuerst auf dem Server aus.';

  @override
  String get awayUnsupported =>
      'Dieser Server nimmt keine Abwesenheitsnotiz mehr an.';

  @override
  String get awayOffline =>
      'Der Server war nicht erreichbar. Versuche es gleich noch einmal.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Abwesenheitsnotiz für $account aktiv bis $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Abwesenheitsnotiz für $account aktiv';
  }

  @override
  String get awayTurnOff => 'Ausschalten';

  @override
  String get awayRowOff => 'Aus';

  @override
  String get awayRowOn => 'An';

  @override
  String awayRowUntil(String date) {
    return 'An bis $date';
  }

  @override
  String get featuresSubtitle =>
      'Schalte aus, was du nicht nutzt. Es verschwindet überall, und nichts wird gelöscht.';

  @override
  String get featuresZones => 'Bereiche';

  @override
  String get featuresOnDevice => 'Auf diesem Gerät';

  @override
  String get featuresOnDeviceNote =>
      'Nichts hiervon verlässt jemals das Gerät.';

  @override
  String get featureNewslettersHint =>
      'Newsletter in einer eigenen Liste, zu lesen wie ein Magazin';

  @override
  String get featureNewslettersOff =>
      'Aus · Newsletter landen im Posteingang wie jede E-Mail';

  @override
  String get featureVaultHint =>
      'Zahlungen, Pakete, Reisen und Fristen als Karten';

  @override
  String get featureVaultOff =>
      'Aus · diese E-Mails bleiben, wie sie sind, ohne Karten oder Mitteilungen';

  @override
  String get featureAttachmentsHint =>
      'Jede Datei, die du bekommen hast, an einem Ort';

  @override
  String get featureAttachmentsOff =>
      'Aus · Dateien bleiben in ihren E-Mails, und die Suche findet sie weiterhin';

  @override
  String get featureInShortHint =>
      'Das Wichtigste langer Unterhaltungen, über der ersten E-Mail';

  @override
  String get featureInShortOff =>
      'Aus · Unterhaltungen öffnen sich ohne Zusammenfassung';

  @override
  String get featureTranslate => 'Übersetzen';

  @override
  String get featureTranslateHint =>
      'Bietet an, E-Mails in anderen Sprachen zu übersetzen';

  @override
  String get featureTranslateOff =>
      'Aus · kein Übersetzungsangebot, und keine Sprache wird geladen';

  @override
  String get featureFoundDates => 'Termine in E-Mails';

  @override
  String get featureFoundDatesHint =>
      'Im Text gefundene Daten und Uhrzeiten zum Kalender hinzufügen';

  @override
  String get featureFoundDatesOff =>
      'Aus · Einladungen zeigen weiterhin ihre Karte';

  @override
  String get nextEmail => 'Nächste E-Mail';

  @override
  String get previousEmail => 'Vorherige E-Mail';

  @override
  String get appearanceLanguage => 'Sprache';

  @override
  String get languageDevice => 'Gerätesprache';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain sieht aus wie $like, ist aber eine andere Adresse.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'Der Name sagt $brand, aber die Adresse ist bei $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'Diese E-Mail gibt sich als von $domain aus, aber $domain hat sie nicht gesendet.';
  }

  @override
  String get senderDetails => 'Details';

  @override
  String get senderDetailsTitle => 'Was geprüft wurde';

  @override
  String get senderSentBy => 'Gesendet von';

  @override
  String get senderNotKnown => 'Unbekannt';

  @override
  String get senderSignature => 'Signatur';

  @override
  String get senderSignatureNone => 'Keine';

  @override
  String get senderDomainCheck => 'Domainprüfung';

  @override
  String get senderDomainCheckFailed => 'Nicht bestanden (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Sieht aus wie';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count E-Mails von dort',
      one: '1 E-Mail von dort',
      zero: 'keine E-Mails von dort',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'Name sagt';

  @override
  String get senderDetailsNote =>
      'Auf diesem Gerät aus dem ermittelt, was dein Mailserver geschrieben hat. Links in dieser E-Mail fragen, bevor sie sich öffnen.';

  @override
  String impostorLinkBody(String real) {
    return 'Diese E-Mail ist vielleicht nicht von dem, der sie zu sein vorgibt. Der Link führt zu $real.';
  }

  @override
  String get updates => 'Updates';

  @override
  String get updatesVersion => 'Version';

  @override
  String get upToDate => 'Aktuell';

  @override
  String get updatesAuto => 'Piuma sucht selbst nach neuen Versionen';

  @override
  String get checkForUpdates => 'Nach Updates suchen';

  @override
  String get updateChecking => 'Wird geprüft…';

  @override
  String get checkedJustNow => 'Gerade geprüft';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vor $count Minuten geprüft',
      one: 'Vor 1 Minute geprüft',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vor $count Stunden geprüft',
      one: 'Vor 1 Stunde geprüft',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vor $count Tagen geprüft',
      one: 'Gestern geprüft',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return '$version wird geladen · $percent %';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done von $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Bereit · $version';
  }

  @override
  String get updateGoesInOnRestart =>
      'Wird beim Neustart von Piuma installiert';

  @override
  String get restart => 'Neu starten';

  @override
  String get updateCouldntCheck => 'Prüfung fehlgeschlagen';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get seeWhatsNew => 'Neuigkeiten ansehen';

  @override
  String get whatsNew => 'Neuigkeiten';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'Mails und Entwürfe bleiben erhalten. Piuma schließt sich und öffnet sich in wenigen Sekunden wieder.';

  @override
  String get restartNow => 'Jetzt neu starten';

  @override
  String updateReadyLine(String version) {
    return 'Update bereit · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Aktualisiert auf $version';
  }

  @override
  String get swipeHintArchiveSnooze =>
      'Nach rechts wischen zum Archivieren, nach links zum Zurückstellen';

  @override
  String get swipeHintArchive => 'Nach rechts wischen zum Archivieren';

  @override
  String get formatting => 'Formatierung';

  @override
  String get formatBold => 'Fett';

  @override
  String get formatItalic => 'Kursiv';

  @override
  String get formatLink => 'Link';

  @override
  String get formatBullets => 'Aufzählung';

  @override
  String get formatNumbers => 'Nummerierte Liste';

  @override
  String get formatQuote => 'Zitat';

  @override
  String get linkAddressHint => 'Adresse einfügen oder eingeben';

  @override
  String get linkAdd => 'Hinzufügen';

  @override
  String get linkRemove => 'Link entfernen';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Bilder sind aus, so sieht $sender nicht, wann du sie öffnest.',
      one: '1 Bild ist aus, so sieht $sender nicht, wann du sie öffnest.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Bilder laden';

  @override
  String get alwaysForSender => 'Immer für diesen Absender';

  @override
  String get cleanView => 'Schlichte Ansicht';

  @override
  String get viewOriginal => 'Original';

  @override
  String get viewClean => 'Schlicht';

  @override
  String get calGoogle => 'Google Kalender';

  @override
  String get calGoogleSub =>
      'Termine und Verfügbarkeit über einen iCal-Link lesen';

  @override
  String get calGoogleLabel => 'iCal-Adresse von Google Kalender';

  @override
  String get calGoogleHint =>
      'In Google Kalender am Computer: Einstellungen › dein Kalender › Kalender integrieren › Privatadresse im iCal-Format. Schreibgeschützt; verbindet sich direkt.';

  @override
  String get bundledReleaseNotes =>
      '## E-Mail, leicht gemacht\n- Original-Layouts mit durchgehendem Scrollen und Bildsteuerung\n- Formatierungsleiste und Wechsel zum vollständigen Editor beim Antworten\n- Bewusstere horizontale Wischgesten\n- Absenderwarnungen bei Markenimitation und ähnlichen Domains\n- Monatlicher Tresor-CSV-Export mit USt-IdNr. des Händlers';
}
