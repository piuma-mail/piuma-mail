// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get catalogSubtitle => 'Catalogo componenti · Fase 0';

  @override
  String get sectionColors => 'Colori';

  @override
  String get sectionTypography => 'Tipografia';

  @override
  String get sectionButtons => 'Bottoni';

  @override
  String get sectionFilters => 'Filtri';

  @override
  String get sectionMessageRows => 'Righe messaggio';

  @override
  String get colorBackground => 'Sfondo';

  @override
  String get colorSurface => 'Superficie';

  @override
  String get colorText => 'Testo';

  @override
  String get colorSecondary => 'Secondario';

  @override
  String get colorAccent => 'Accento';

  @override
  String get colorSoft => 'Tenue';

  @override
  String get colorSuccess => 'Successo';

  @override
  String get colorWarning => 'Avviso';

  @override
  String get colorDanger => 'Pericolo';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Titolo';

  @override
  String get typeSubtitle => 'Sottotitolo';

  @override
  String get typeBody => 'Corpo';

  @override
  String get typeSmall => 'Piccolo';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Invia';

  @override
  String get actionSnooze => 'Posticipa';

  @override
  String get actionReply => 'Rispondi';

  @override
  String get actionDelete => 'Elimina';

  @override
  String get actionDisabled => 'Disattivo';

  @override
  String get filterUnread => 'Non lette';

  @override
  String get filterAttachments => 'Con allegati';

  @override
  String get filterPeople => 'Solo persone';

  @override
  String get messageUnread => 'Non letta';

  @override
  String get compose => 'Scrivi';

  @override
  String get unifiedInbox => 'Inbox unificata';

  @override
  String get accounts => 'Account';

  @override
  String get addAccount => 'Aggiungi un account';

  @override
  String get inbox => 'Inbox';

  @override
  String downloading(String done, String total) {
    return 'Scarico $done di $total';
  }

  @override
  String get offline => 'Offline · riprovo';

  @override
  String get signInFailed => 'Un account chiede di nuovo la password';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts account',
      one: '1 account',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread da leggere',
      zero: 'tutto letto',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Scegli un messaggio per leggerlo.';

  @override
  String get noSubject => '(senza oggetto)';

  @override
  String get couldNotLoadMessage =>
      'Non sono riuscito a scaricare questo messaggio. Controlla la connessione e riprova.';

  @override
  String get loading => 'Carico…';

  @override
  String toYouToday(String time) {
    return 'a te · oggi alle $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'a te · ieri alle $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'a te · $date alle $time';
  }

  @override
  String get sectionToday => 'Oggi';

  @override
  String get sectionYesterday => 'Ieri';

  @override
  String get sectionThisWeek => 'Questa settimana';

  @override
  String get sectionThisMonth => 'Prima, questo mese';

  @override
  String get sectionOlder => 'Più vecchi';

  @override
  String get defaultAccountName => 'Posta';

  @override
  String get emailAddress => 'Indirizzo email';

  @override
  String get password => 'Password';

  @override
  String get show => 'Mostra';

  @override
  String get hide => 'Nascondi';

  @override
  String get imapServer => 'Server IMAP';

  @override
  String get port => 'Porta';

  @override
  String get security => 'Sicurezza';

  @override
  String get accountName => 'Nome dell’account';

  @override
  String get accountColor => 'Colore dell’account';

  @override
  String get color => 'Colore';

  @override
  String get connect => 'Collega';

  @override
  String get connecting => 'Collego…';

  @override
  String get notNow => 'Non ora';

  @override
  String get enterToConnect => 'per collegare';

  @override
  String get errorWrongPassword =>
      'Il server non ha accettato indirizzo e password. Se il tuo provider usa le password per app, creane una e usala qui.';

  @override
  String get errorUnreachable =>
      'Non riesco a raggiungere il server. Controlla nome del server, porta e connessione.';

  @override
  String get errorInsecure =>
      'Non riesco a creare una connessione sicura. Controlla nome del server e sicurezza.';

  @override
  String get errorKeychain =>
      'Non riesco a salvare la password nel portachiavi di sistema.';

  @override
  String get errorOther =>
      'Qualcosa è andato storto nel collegamento. Riprova.';

  @override
  String get yourAccounts => 'I tuoi account';

  @override
  String get noAccountsYet => 'Il tuo primo account comparirà qui.';

  @override
  String get connected => 'Collegato';

  @override
  String get privacyNote =>
      'Le tue email restano sul dispositivo. Ci colleghiamo direttamente ai tuoi server, senza intermediari.';

  @override
  String get newMessage => 'Nuovo messaggio';

  @override
  String get close => 'Chiudi';

  @override
  String get from => 'Da';

  @override
  String get to => 'A';

  @override
  String get cc => 'Cc';

  @override
  String get bcc => 'Ccn';

  @override
  String get ccBcc => 'Cc  Ccn';

  @override
  String get subject => 'Oggetto';

  @override
  String get messageBody => 'Messaggio';

  @override
  String get addRecipient => 'Aggiungi';

  @override
  String removeRecipient(String name) {
    return 'Rimuovi $name';
  }

  @override
  String undoSendHint(int seconds) {
    return 'Puoi annullare l\'invio per $seconds secondi';
  }

  @override
  String get sendNoRecipients => 'Aggiungi almeno un destinatario.';

  @override
  String sendBadAddress(String address) {
    return '“$address” non è un indirizzo email.';
  }

  @override
  String get sending => 'Invio in corso…';

  @override
  String get sent => 'Inviato';

  @override
  String get undo => 'Annulla';

  @override
  String get draftDiscarded => 'Bozza eliminata';

  @override
  String get sendErrorPassword =>
      'Il server di posta in uscita non ha accettato la password. Il messaggio è ancora qui.';

  @override
  String get sendErrorUnreachable =>
      'Non riesco a raggiungere il server di posta in uscita. Il messaggio è ancora qui.';

  @override
  String get sendErrorRejected =>
      'Il server di posta in uscita ha rifiutato il messaggio. Il messaggio è ancora qui.';

  @override
  String get sendErrorOther =>
      'Non è stato possibile inviare il messaggio. Il messaggio è ancora qui.';

  @override
  String stepOf(int step, int total) {
    return '$step di $total';
  }

  @override
  String get whatsYourEmail => 'Qual è la tua email?';

  @override
  String get findSettingsHint => 'Troviamo noi le impostazioni del server.';

  @override
  String get continueAction => 'Continua';

  @override
  String get lookingUp => 'Cerco…';

  @override
  String get setUpManually => 'Configura a mano';

  @override
  String get back => 'Indietro';

  @override
  String get weFoundSettings => 'Abbiamo trovato le impostazioni';

  @override
  String get incoming => 'In arrivo';

  @override
  String get outgoing => 'In uscita';

  @override
  String get incomingAndOutgoing => 'In arrivo e in uscita';

  @override
  String get guessedSettings =>
      'Sono le impostazioni abituali per il tuo dominio. Se la connessione non riesce, controllale.';

  @override
  String get yourName => 'Il tuo nome';

  @override
  String get yourNameHint => 'Lo vede chi riceve le tue email. Facoltativo.';

  @override
  String get settingsNotFound =>
      'Non abbiamo trovato le impostazioni per questo indirizzo. Le trovi nelle pagine di aiuto del tuo provider.';

  @override
  String get smtpServer => 'Server SMTP';

  @override
  String get username => 'Nome utente';

  @override
  String get usedForBoth =>
      'Vale sia per la posta in arrivo sia per quella in uscita.';

  @override
  String get verifyAndConnect => 'Verifica e collega';

  @override
  String get archive => 'Archivia';

  @override
  String get archived => 'Archiviato';

  @override
  String get movedToTrash => 'Spostato nel cestino';

  @override
  String get actionFailed =>
      'Non è stato possibile spostare il messaggio. È di nuovo nella posta in arrivo.';

  @override
  String get replyTitle => 'Rispondi';

  @override
  String quoteHeader(String date, String name) {
    return 'Il $date, $name ha scritto:';
  }

  @override
  String get search => 'Cerca…';

  @override
  String get searchAllAccounts => 'Cerca in tutti gli account';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count risultati',
      one: '1 risultato',
      zero: 'Nessun risultato',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filtri';

  @override
  String get filterLastMonth => 'Ultimo mese';

  @override
  String get filterAccount => 'Account';

  @override
  String get searchOperators => 'Operatori';

  @override
  String get operatorNameHint => 'nome';

  @override
  String get operatorDateHint => 'data';

  @override
  String get searchPeople => 'Persone';

  @override
  String get searchEmail => 'Email';

  @override
  String personEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String get searchNoResults => 'Nessun risultato';

  @override
  String get searchNoResultsHint => 'Prova con meno parole o un’altra grafia.';

  @override
  String get searchNoResultsFilters => 'Nessun risultato con questi filtri';

  @override
  String get searchNoResultsFiltersHint =>
      'Togli un filtro o un operatore per allargare la ricerca.';

  @override
  String get clearFilters => 'Togli i filtri';

  @override
  String get searchEmptyHint =>
      'Cerca in tutti gli account per parola, mittente o data, anche offline.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count corrispondenze',
      one: '1 corrispondenza',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Apri la conversazione';

  @override
  String get noMessageToShow => 'Nessun messaggio da mostrare';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: 'Cercato in $accounts account',
      one: 'Cercato in 1 account',
    );
    return '$_temp0 · $emails email · $seconds s · indice locale, funziona offline';
  }

  @override
  String get keyMove => 'sposta';

  @override
  String get keyOpen => 'apri';

  @override
  String get privacyImagesBlocked => 'Immagini bloccate';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracker fermati',
      one: '1 tracker fermato',
    );
    return 'Immagini bloccate · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Carico le immagini…';

  @override
  String get privacyImagesLoaded => 'Immagini caricate';

  @override
  String get privacyImagesLoadedStopped =>
      'Immagini caricate · tracker sempre fermi';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracker fermati',
      one: '1 tracker fermato',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count link ripuliti',
      one: '1 link ripulito',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Privacy di questo messaggio';

  @override
  String get privacySheetSubtitle =>
      'Il mittente non può sapere se o quando l’hai aperto.';

  @override
  String get trackerPixel => 'Pixel di apertura';

  @override
  String get trackerFont => 'Font remoto';

  @override
  String get trackerStyle => 'Stile remoto';

  @override
  String get trackerLinks => 'Link tracciati';

  @override
  String get trackerStopped => 'Fermato';

  @override
  String get loadImagesOnce => 'Carica immagini una volta';

  @override
  String get imagesAlreadyLoaded => 'Immagini già caricate';

  @override
  String trustSender(String name) {
    return 'Fidati sempre di $name';
  }

  @override
  String senderTrusted(String name) {
    return '$name è fidato';
  }

  @override
  String get alwaysBlockImages => 'Blocca sempre le immagini remote';

  @override
  String get alwaysBlockImagesHint => 'Vale per tutti i mittenti non fidati';

  @override
  String get imageNotLoaded => 'Immagine non caricata';

  @override
  String get suspiciousLinkTitle => 'Controlla questo link';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'Il testo mostra $shown, ma il link porta a $real.';
  }

  @override
  String get openAnyway => 'Apri comunque';

  @override
  String get dontOpen => 'Non aprire';

  @override
  String get riskProgram => 'Un programma che può avviarsi';

  @override
  String riskDisguised(String kind) {
    return 'Un programma, con il nome di un $kind';
  }

  @override
  String get riskMacros => 'Ha macro che possono avviarsi';

  @override
  String get riskLocked => 'Protetto da password';

  @override
  String get riskOpenProgram => 'Aprire questo programma?';

  @override
  String get riskOpenFile => 'Aprire questo file?';

  @override
  String get riskOpenArchive => 'Aprire questo archivio?';

  @override
  String riskBodyProgram(String name) {
    return '$name è un programma. I programmi arrivati per email possono prendere il controllo del dispositivo. Aprilo solo se lo aspettavi.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name sembra un $kind, ma è un programma. I programmi arrivati per email possono prendere il controllo del dispositivo. Aprilo solo se lo aspettavi.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name ha delle macro, che possono avviarsi quando lo apri. Aprilo solo se lo aspettavi.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name è protetto da password, quindi nessuno può guardarci dentro. Aprilo solo se lo aspettavi.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · da $email';
  }

  @override
  String get settings => 'Impostazioni';

  @override
  String get backToMail => 'Torna alla posta';

  @override
  String get settingsAccountsTitle => 'Account';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count caselle IMAP, una sola Inbox.',
      one: 'Una casella IMAP.',
    );
    return '$_temp0 Il colore mostra da dove arriva ogni email.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Aggiungi account';

  @override
  String get addAccountNote =>
      'IMAP e SMTP. Gmail, iCloud e Fastmail si configurano da soli.';

  @override
  String get privacyTitle => 'Privacy e sicurezza';

  @override
  String get privacySubtitle =>
      'Tutto avviene su questo dispositivo. Nessun dato lascia la tua casella.';

  @override
  String get blockImagesSetting => 'Blocca le immagini remote';

  @override
  String get blockImagesSettingHint =>
      'Le immagini si caricano solo quando lo chiedi.';

  @override
  String get stopPixelsSetting => 'Ferma i pixel traccianti';

  @override
  String get stopPixelsSettingHint =>
      'I mittenti non sanno se o quando apri un messaggio.';

  @override
  String get cleanLinksSetting => 'Ripulisci i link';

  @override
  String get cleanLinksSettingHint =>
      'Toglie utm e parametri di tracciamento prima di aprire.';

  @override
  String get warnLinksSetting => 'Avvisa dei link sospetti';

  @override
  String get warnLinksSettingHint =>
      'Chiede prima di aprire un link che mostra un indirizzo e porta a un altro.';

  @override
  String get last30Days => 'Ultimi 30 giorni';

  @override
  String get trackersStoppedLabel => 'tracker fermati';

  @override
  String get linksCleanedLabel => 'link ripuliti';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious link sospetti segnalati',
      one: '1 link sospetto segnalato',
    );
    return 'Pixel di apertura $pixels · font e stili remoti $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Mittenti fidati';

  @override
  String get trustedSendersHint => 'le immagini si caricano sempre';

  @override
  String trustedSince(String email, String date) {
    return '$email · dal $date';
  }

  @override
  String get removeTrusted => 'Rimuovi';

  @override
  String get noTrustedSenders =>
      'Nessun mittente fidato. Le immagini restano bloccate per tutti.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Allega file';

  @override
  String removeAttachment(String name) {
    return 'Rimuovi $name';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name salvato in Download';
  }

  @override
  String attachmentNotSaved(String name) {
    return 'Non sono riuscito a scaricare $name. Controlla la connessione e riprova.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Gli allegati possono arrivare a $max in tutto. Togline qualcuno e riprova.';
  }

  @override
  String fileNotRead(String name) {
    return 'Non sono riuscito a leggere $name.';
  }

  @override
  String get folderSent => 'Inviati';

  @override
  String get folderArchive => 'Archivio';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count account',
      one: 'Un account',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'a $people · oggi alle $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'a $people · ieri alle $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'a $people · $date alle $time';
  }

  @override
  String get emptyFolder => 'Ancora niente qui.';

  @override
  String threadMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messaggi',
      one: '1 messaggio',
    );
    return '$_temp0';
  }

  @override
  String conversationSummary(int count, String people) {
    return '$count messaggi · $people';
  }

  @override
  String readMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messaggi letti',
      one: '1 messaggio letto',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count nuovi';
  }

  @override
  String get you => 'io';

  @override
  String get quotedTextHidden => '··· testo citato nascosto';

  @override
  String get showQuotedText => 'Mostra il testo citato';

  @override
  String get youName => 'Io';

  @override
  String yesterdayAt(String time) {
    return 'Ieri $time';
  }

  @override
  String get pickMessage => 'Seleziona';

  @override
  String get unpickMessage => 'Selezionato';

  @override
  String get selectAll => 'Seleziona tutto';

  @override
  String pickedOf(int count, int total) {
    return '$count di $total selezionate';
  }

  @override
  String get deselect => 'Deseleziona';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversazioni selezionate',
      one: 'conversazione selezionata',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'da $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'da $names e $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'da $names e altri $count';
  }

  @override
  String andMore(String name, int count) {
    return '$name e altre $count';
  }

  @override
  String get markRead => 'Segna come letta';

  @override
  String get markUnread => 'Segna come da leggere';

  @override
  String get hintArchive => 'archivia';

  @override
  String get hintUnread => 'da leggere';

  @override
  String get hintDeselect => 'deseleziona';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni archiviate',
      one: 'Archiviato',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni spostate nel cestino',
      one: 'Spostato nel cestino',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'Il server non risponde. Letti e da leggere sono tornati com’erano.';

  @override
  String get signaturesTitle => 'Firme';

  @override
  String get newSignature => 'Nuova firma';

  @override
  String get newSignatureLabel => 'Nuova firma';

  @override
  String get noSignatures =>
      'Ancora nessuna firma. Creane una con Nuova firma.';

  @override
  String get signatureTemplate => 'Modello';

  @override
  String get signatureLogo => 'Logo';

  @override
  String get signatureLabelField => 'Nome della firma';

  @override
  String get signatureAccount => 'Account';

  @override
  String get signatureName => 'Nome';

  @override
  String get signatureRole => 'Ruolo';

  @override
  String get signatureCompany => 'Azienda';

  @override
  String get signaturePhone => 'Telefono';

  @override
  String get signatureWebsite => 'Sito web';

  @override
  String get signatureAccent => 'Colore d’accento';

  @override
  String get accentBlue => 'Accento blu';

  @override
  String get accentBlack => 'Accento nero';

  @override
  String get accentTerracotta => 'Accento terracotta';

  @override
  String get signatureWhen => 'Quando usarla';

  @override
  String signatureForNew(String email) {
    return 'Nuove email da $email';
  }

  @override
  String get signatureForReplies => 'Risposte e inoltri';

  @override
  String get signatureNone => 'Nessuna';

  @override
  String get deleteSignature => 'Elimina firma';

  @override
  String get signatureDeleteHint => 'Le email già inviate la conservano.';

  @override
  String get signaturePreview => 'Anteprima';

  @override
  String get previewLight => 'Chiaro';

  @override
  String get previewDark => 'Scuro';

  @override
  String get previewText => 'Testo';

  @override
  String get signatureSampleText =>
      'Ciao Luca,\nti allego i file definitivi. Fammi sapere se ti serve altro.\n\nA presto,';

  @override
  String get signatureNote =>
      'Nessuna immagine: la firma arriva pulita anche dove le immagini sono bloccate, e la versione solo testo è creata per te.';

  @override
  String get signatureNoteLogo =>
      'Il logo viaggia dentro l’email (massimo 40 KB) con un testo alternativo, così non chiede mai di “caricare le immagini” e non traccia nessuno. La versione solo testo è creata per te.';

  @override
  String get signatureUseAll => 'tutte';

  @override
  String get signatureUseNew => 'nuove email';

  @override
  String get signatureUseReplies => 'risposte e inoltri';

  @override
  String get signatureUseNone => 'non in uso';

  @override
  String get templateMinimal => 'Minimale';

  @override
  String get templateClassic => 'Classica';

  @override
  String get templateMonogram => 'Monogramma';

  @override
  String get templateLogo => 'Con logo';

  @override
  String get noLogo => 'NESSUN LOGO';

  @override
  String get logoHint => 'PNG o JPEG, ridotto a 40 KB in automatico';

  @override
  String get removeLogo => 'Rimuovi';

  @override
  String get uploadLogo => 'Carica';

  @override
  String get logoTooBig =>
      'Questo logo resta sopra i 40 KB anche ridotto. Prova con uno più semplice.';

  @override
  String get logoNotImage => 'Scegli un’immagine PNG o JPEG.';

  @override
  String signatureChip(String label) {
    return 'Firma · $label';
  }

  @override
  String get noSignature => 'Nessuna firma';

  @override
  String get manageSignatures => 'Gestisci firme…';

  @override
  String get signatureUsedNew => 'Nuove email';

  @override
  String get signatureUsedReplies => 'Risposte';

  @override
  String get composeSignatureNote =>
      'La firma segue l’account del Da: la sua firma per le nuove email, quella breve per risposte e inoltri.';

  @override
  String get noticeOpen => 'Apri';

  @override
  String get noticeChannel => 'Nuova posta';

  @override
  String noticeTitleMany(String sender, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email',
      one: '1 email',
    );
    return '$sender · $_temp0';
  }

  @override
  String get notificationsTitle => 'Notifiche';

  @override
  String get notificationsLead => 'Poche, e solo quando contano.';

  @override
  String get notifyAbout => 'Avvisami per';

  @override
  String get notifyPeople => 'Solo persone';

  @override
  String get notifyPeopleHint =>
      'Email scritte da persone. Niente newsletter, ricevute o messaggi automatici.';

  @override
  String get notifyRecommended => 'Consigliato';

  @override
  String get notifyAll => 'Tutte';

  @override
  String get notifyAllHint => 'Ogni nuova email che arriva in Posta in arrivo.';

  @override
  String get notifyOff => 'Nessuna';

  @override
  String get notifyOffHint =>
      'Controlli quando vuoi. Niente badge, niente suoni.';

  @override
  String get quietHours => 'Ore di silenzio';

  @override
  String get quietTitle => 'Ogni notte';

  @override
  String get quietHint => 'La posta arriva lo stesso, in silenzio.';

  @override
  String get quietFrom => 'Dalle';

  @override
  String get quietTo => 'alle';

  @override
  String quietFromLabel(String time) {
    return 'Il silenzio inizia alle $time';
  }

  @override
  String quietToLabel(String time) {
    return 'Il silenzio finisce alle $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count account',
      one: '1 account',
    );
    return 'Cerca in $_temp0';
  }

  @override
  String get phoneAccountsAll => 'Tutti';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'i $count account',
      one: 'l\'account',
    );
    return 'Mostra tutti $_temp0';
  }

  @override
  String get composeMessage => 'Scrivi un messaggio';

  @override
  String get moreActions => 'Altre azioni';

  @override
  String quickReplyHint(String name) {
    return 'Rispondi a $name…';
  }

  @override
  String get sendReply => 'Invia risposta';

  @override
  String get cancel => 'Annulla';

  @override
  String get pickAll => 'Tutte';

  @override
  String get pickNone => 'Nessuna';

  @override
  String get pickRead => 'Letta';

  @override
  String get pickUnread => 'Da leggere';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'selezionate',
      one: 'selezionata',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'di $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count di $total selezionate';
  }

  @override
  String get phoneSelectActions => 'Azioni sulle selezionate';

  @override
  String get clearSearch => 'Cancella ricerca';

  @override
  String get settingsAbout => 'Informazioni';

  @override
  String get settingsMail => 'Posta';

  @override
  String get settingsApp => 'App';

  @override
  String get writingTitle => 'Scrittura';

  @override
  String get readingTitle => 'Lettura';

  @override
  String get readingSubtitle =>
      'Come appare l\'elenco, e cosa ti aiuta a leggere.';

  @override
  String get organizingTitle => 'Organizzazione';

  @override
  String get organizingSubtitle => 'Zone, regole, cartelle ed etichette.';

  @override
  String signaturesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count firme',
      one: '1 firma',
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
      other: '$count account',
      one: '1 account',
    );
    return '$_temp0, account e Impostazioni';
  }

  @override
  String get allAccounts => 'Tutti gli account';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count caselle insieme',
      one: '1 casella',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return 'Solo $name, account e Impostazioni';
  }

  @override
  String accountOnly(String name) {
    return 'Solo $name';
  }

  @override
  String get showAllAccounts => 'Mostra tutti';

  @override
  String get phoneFolders => 'Cartelle';

  @override
  String phoneSearchOne(String name) {
    return 'Cerca in $name';
  }

  @override
  String get welcomeLead =>
      'Collega i tuoi account IMAP e leggi tutto in una sola inbox, senza rumore.';

  @override
  String get staysOnDevice => 'La tua posta resta sul tuo dispositivo';

  @override
  String get editServers => 'Modifica';

  @override
  String get serverHost => 'Server';

  @override
  String get offlineTitle => 'Sei offline';

  @override
  String get offlineDetail => 'la posta in uscita parte quando torni online';

  @override
  String downloadingAccount(String name) {
    return 'Scarico $name';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done di $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'L’account $name non si collega';
  }

  @override
  String passwordChanged(String email) {
    return 'È cambiata la password? La posta di $email non arriva più.';
  }

  @override
  String get signInAgain => 'Accedi di nuovo';

  @override
  String get later => 'Più tardi';

  @override
  String signInTo(String name) {
    return 'Accedi a $name';
  }

  @override
  String get signIn => 'Accedi';

  @override
  String get signingIn => 'Accesso…';

  @override
  String get allCaughtUp => 'Tutto in pari';

  @override
  String get allCaughtUpDetail =>
      'Nessuno ti sta aspettando. Il resto della giornata è tuo.';

  @override
  String get countOf => 'di';

  @override
  String get draftSaved => 'Bozza salvata';

  @override
  String get draftNotSaved => 'Non salvata';

  @override
  String get draftNotSavedToast => 'Bozza non salvata';

  @override
  String get reopen => 'Riapri';

  @override
  String get discard => 'Elimina';

  @override
  String get noRecipients => 'Nessun destinatario';

  @override
  String get folderDrafts => 'Bozze';

  @override
  String accountFolders(String name) {
    return 'Cartelle di $name';
  }

  @override
  String get moveShort => 'Sposta';

  @override
  String get moveTo => 'Sposta in…';

  @override
  String moveToIn(String name) {
    return 'Sposta in una cartella di $name';
  }

  @override
  String get noFoldersMatch => 'Nessuna cartella con questo nome';

  @override
  String noOtherFolders(String name) {
    return '$name non ha ancora altre cartelle';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni spostate in $folder',
      one: 'Spostato in $folder',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'In uscita · $count';
  }

  @override
  String outboxTo(String names) {
    return 'A $names';
  }

  @override
  String get outboxWaiting => 'In attesa';

  @override
  String get outboxNotSent => 'Non inviato';

  @override
  String outboxRefused(String reason) {
    return 'Il server l’ha rifiutato: $reason';
  }

  @override
  String get inOutbox => 'In uscita · parte appena torni online';

  @override
  String get editAction => 'Modifica';

  @override
  String get backgroundTitle => 'La posta nuova appena arriva';

  @override
  String get backgroundBody =>
      'Piuma resta collegato ai tuoi account, senza server di mezzo. Android ti chiederà due cose: di mostrare le notifiche e di lasciare Piuma attivo in background.';

  @override
  String get newMailHeading => 'Posta nuova';

  @override
  String get deliveryInstant => 'Appena arriva';

  @override
  String get deliveryInstantHint => 'Lascia un avviso silenzioso nella tendina';

  @override
  String get deliveryPeriodic => 'Ogni 15 minuti';

  @override
  String get deliveryPeriodicHint =>
      'Nessun avviso; Android può aspettare di più';

  @override
  String get folderNewsletters => 'Newsletter';

  @override
  String newslettersTileLabel(int count) {
    return 'Newsletter, $count da leggere';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes min · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes min di lettura · arrivata alle $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Arrivata alle $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Arrivata il $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes min di lettura · arrivata il $date';
  }

  @override
  String get dayToday => 'oggi';

  @override
  String get dayYesterday => 'ieri';

  @override
  String get readLater => 'Leggi dopo';

  @override
  String get readLaterDone => 'Tenuta come da leggere';

  @override
  String get unsubscribe => 'Disiscriviti';

  @override
  String unsubscribeTitle(String sender) {
    return 'Disiscriversi da $sender?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender riceve una sola richiesta di smettere. Non si apre nulla, e quello che è già arrivato resta qui.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'Un messaggio parte dal tuo account verso $address per chiederlo. Quello che è già arrivato resta qui.';
  }

  @override
  String get unsubscribePage =>
      'La loro pagina per disiscriversi si apre nel browser.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender non offre un modo per disiscriversi. Spostala in Inbox, o archivia quello che arriva.';
  }

  @override
  String get unsubscribeConfirm => 'Disiscriviti';

  @override
  String get unsubscribeOpen => 'Apri la pagina';

  @override
  String unsubscribeDone(String sender) {
    return 'Disiscritto da $sender';
  }

  @override
  String get unsubscribeFailed =>
      'Non è stato possibile disiscriversi. Controlla la connessione e riprova.';

  @override
  String get alwaysInInbox => 'Sempre in Inbox';

  @override
  String alwaysInInboxDone(String sender) {
    return 'La posta di $sender ora arriva in Inbox';
  }

  @override
  String get newslettersArchiveNote =>
      'Lette da più di 7 giorni? Si archiviano da sole';

  @override
  String get newslettersEmpty => 'Nessuna newsletter';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count da leggere',
      one: '1 da leggere',
      zero: 'Tutto letto',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes minuti in tutto';
  }

  @override
  String newslettersNew(int count) {
    return '$count nuove';
  }

  @override
  String get folderVault => 'Caveau';

  @override
  String vaultTileLabel(String status) {
    return 'Caveau, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Caveau, $count in attesa';
  }

  @override
  String vaultDue(String when) {
    return 'Scade $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Arriva $when';
  }

  @override
  String get vaultNothingDue => 'Niente in sospeso';

  @override
  String get vaultToday => 'Oggi';

  @override
  String get vaultTomorrow => 'Domani';

  @override
  String get dayTomorrow => 'domani';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'tra $days giorni',
      one: 'domani',
      zero: 'oggi',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Ordinato';

  @override
  String get parcelShipped => 'Spedito';

  @override
  String get parcelTransit => 'In viaggio';

  @override
  String get parcelDelivered => 'Consegnato';

  @override
  String vaultDeliveredOn(String day) {
    return 'Consegnato $day';
  }

  @override
  String vaultCarrierFrom(String carrier, String merchant) {
    return '$carrier · da $merchant';
  }

  @override
  String vaultFrom(String merchant) {
    return 'Da $merchant';
  }

  @override
  String vaultLastScan(String place) {
    return 'Ultima scansione: $place';
  }

  @override
  String get vaultDueLabel => 'Scadenza';

  @override
  String get vaultPaid => 'Pagato';

  @override
  String get vaultDownloadPdf => 'Scarica PDF';

  @override
  String get vaultMarkPaid => 'Segna pagato';

  @override
  String get vaultPaidFailed => 'Non sono riuscito a salvarlo. Riprova.';

  @override
  String vaultFlight(String number, String date) {
    return 'Volo $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Posto';

  @override
  String get vaultCode => 'Codice';

  @override
  String get vaultBoardingPass => 'Carta d’imbarco';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count persone',
      one: '1 persona',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'confermato';

  @override
  String get vaultPending => 'da confermare';

  @override
  String get vaultCancelled => 'annullato';

  @override
  String get vaultDirections => 'Indicazioni';

  @override
  String get vaultNotePhone =>
      'Letto sul dispositivo dall’email originale · tocca una scheda per aprirla';

  @override
  String get vaultEmpty =>
      'Pacchi, spese, viaggi e altro compaiono qui, letti su questo dispositivo dalle loro email.';

  @override
  String get folderAttachments => 'Allegati';

  @override
  String get attachmentsSubtitle =>
      'Ogni file che hai ricevuto, senza aprire l’email';

  @override
  String get attachmentsAll => 'Tutti';

  @override
  String get attachmentsMedia => 'Foto e media';

  @override
  String get attachmentsDocuments => 'Documenti';

  @override
  String get attachmentsSheets => 'Fogli';

  @override
  String get attachmentsFilter => 'Filtra per tipo';

  @override
  String get attachmentsSearch => 'Cerca file o mittenti';

  @override
  String get attachmentsSearchLabel => 'Cerca negli allegati';

  @override
  String get attachmentsRecent => 'Recenti';

  @override
  String get attachmentsLargest => 'Più grandi';

  @override
  String attachmentsSortLabel(String sort) {
    return 'Ordina per: $sort';
  }

  @override
  String get attachmentsThisWeek => 'Questa settimana';

  @override
  String get attachmentsEarlier => 'Prima';

  @override
  String attachmentsMeta(String name, String size, String when) {
    return 'Da: $name · $size · $when';
  }

  @override
  String get attachmentsDownload => 'Scarica';

  @override
  String get attachmentsOpenEmail => 'Apri email';

  @override
  String get attachmentsEmail => 'Email';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, da $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return 'Scarica $name';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'Apri l’email di $from';
  }

  @override
  String get attachmentsNoneNew => 'Niente di nuovo';

  @override
  String attachmentsTileLabel(String status) {
    return 'Allegati, $status';
  }

  @override
  String get attachmentsEmpty =>
      'I file che ricevi compaiono qui, da tutti gli account.';

  @override
  String attachmentsNoMatch(String query) {
    return 'Nessun file corrisponde a “$query”';
  }

  @override
  String attachmentsNew(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuovi',
      one: '1 nuovo',
    );
    return '$_temp0';
  }

  @override
  String get folderSnoozed => 'Posticipate';

  @override
  String get snoozeUntilTitle => 'Posticipa a…';

  @override
  String get snoozeEvening => 'Stasera';

  @override
  String get snoozeMorning => 'Domani mattina';

  @override
  String get snoozeWeekend => 'Weekend';

  @override
  String get snoozeNextWeek => 'Settimana prossima';

  @override
  String snoozeTileToday(String time) {
    return 'oggi $time';
  }

  @override
  String snoozeToday(String time) {
    return 'oggi, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'domani, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'domani $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni posticipate a $when',
      one: 'Posticipata a $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Torna in Inbox';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni di nuovo in Inbox',
      one: 'Di nuovo in Inbox',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Domani';

  @override
  String get sectionLater => 'Più avanti';

  @override
  String get sendLater => 'Invia più tardi';

  @override
  String get sendLaterTomorrowMorning => 'Domani mattina';

  @override
  String get sendLaterTomorrowAfternoon => 'Domani pomeriggio';

  @override
  String get sendLaterMondayMorning => 'Lunedì mattina';

  @override
  String scheduleTomorrow(String time) {
    return 'Programma per domani alle $time';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Programma per $day alle $time';
  }

  @override
  String get sendLaterNote =>
      'La invia questo dispositivo a quell’ora. Se è spento, parte appena si riaccende.';

  @override
  String scheduledToast(String when) {
    return 'Programmata per $when';
  }

  @override
  String get paletteLabel => 'Palette comandi';

  @override
  String get paletteHint => 'Cerca o esegui un comando';

  @override
  String get paletteActions => 'Azioni';

  @override
  String get paletteMessages => 'Messaggi';

  @override
  String paletteWriteTo(String name) {
    return 'Scrivi a $name';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Mostra solo i messaggi di $name';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Allegati di $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Cerca “$query” in tutta la posta';
  }

  @override
  String paletteGoTo(String place) {
    return 'Apri $place';
  }

  @override
  String get paletteMove => 'sposta';

  @override
  String get paletteRun => 'esegui';

  @override
  String get paletteAnywhere => 'da qualsiasi schermata';

  @override
  String senderCardLabel(String name) {
    return 'Scheda di $name';
  }

  @override
  String get senderKind => 'Mittente';

  @override
  String get senderClose => 'Chiudi scheda';

  @override
  String get senderWrite => 'Scrivi';

  @override
  String get senderAll => 'Tutte le email';

  @override
  String get senderMute => 'Silenzia';

  @override
  String get senderMuted => 'Silenziato';

  @override
  String senderArrivesIn(String account) {
    return 'Arriva in $account';
  }

  @override
  String get senderConversations => 'Conversazioni';

  @override
  String get senderNoMail => 'Ancora nessuna sua email su questo dispositivo.';

  @override
  String senderMutedToast(String name) {
    return 'Niente più notifiche da $name';
  }

  @override
  String get rulesTitle => 'Regole e cartelle';

  @override
  String get rulesSubtitle =>
      'Ordina la posta come faresti tu. Ogni regola si legge come una frase.';

  @override
  String get rulesWhere =>
      'Le regole lavorano su questo dispositivo, sulla posta nuova in arrivo';

  @override
  String get rulesHeading => 'Regole';

  @override
  String get rulesNew => 'Nuova regola';

  @override
  String get rulesEdit => 'Modifica regola';

  @override
  String get rulesNone =>
      'Ancora nessuna regola tua. Una regola ordina la posta nuova appena arriva, come faresti tu.';

  @override
  String get ruleWhen => 'Quando';

  @override
  String get ruleThen => 'allora';

  @override
  String get ruleFieldSender => 'il mittente';

  @override
  String get ruleFieldSubject => 'l’oggetto';

  @override
  String get ruleFieldRecipient => 'il destinatario';

  @override
  String get ruleOpContains => 'contiene';

  @override
  String get ruleOpIs => 'è';

  @override
  String get ruleOpStarts => 'inizia con';

  @override
  String get ruleOpNotContains => 'non contiene';

  @override
  String get ruleDoMove => 'sposta in';

  @override
  String get ruleDoArchive => 'archivia';

  @override
  String get ruleDoRead => 'segna come letta';

  @override
  String get ruleText => 'Testo da cercare';

  @override
  String get ruleTextHint => 'testo';

  @override
  String get ruleTrayField => 'Campo';

  @override
  String get ruleTrayOp => 'Condizione';

  @override
  String get ruleTrayAction => 'Azione';

  @override
  String get ruleTrayFolder => 'Cartella';

  @override
  String get rulePickFolder => 'una cartella';

  @override
  String get ruleNoFolders =>
      'I tuoi account non hanno ancora cartelle proprie.';

  @override
  String get ruleApplyToo => 'Applica anche a quelle';

  @override
  String get ruleSave => 'Salva regola';

  @override
  String get ruleDelete => 'Elimina regola';

  @override
  String get rulePaused => 'In pausa';

  @override
  String get ruleFresh => 'Attiva da ora';

  @override
  String get foldersHeading => 'Cartelle';

  @override
  String get foldersNone => 'Nessuna cartella propria';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vale per $count mail già arrivate',
      one: 'Vale per $count mail già arrivata',
      zero: 'Nessuna mail già arrivata corrisponde',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mail ordinate',
      one: '1 mail ordinata',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'ultima oggi alle $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'ultima il $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Regola attiva: $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Nessuna',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Invito';

  @override
  String get inviteYes => 'Sì';

  @override
  String get inviteMaybe => 'Forse';

  @override
  String get inviteNo => 'No';

  @override
  String get inviteRespond => 'Rispondi all’invito';

  @override
  String get inviteAllDay => 'Tutto il giorno';

  @override
  String get inviteRepeats => 'si ripete';

  @override
  String get inviteYouAccepted => 'Hai accettato';

  @override
  String get inviteYouTentative => 'Hai risposto forse';

  @override
  String get inviteYouDeclined => 'Hai rifiutato';

  @override
  String get inviteNotSent =>
      'Non è stato possibile inviare la risposta. Riprova.';

  @override
  String get inviteCancelled => 'Questo evento è stato annullato';

  @override
  String get inviteYours => 'Questo invito l’hai mandato tu';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count partecipanti',
      one: '1 partecipante',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name riceverà la tua risposta';
  }

  @override
  String inviteQueued(String name) {
    return 'arriverà a $name appena torni online';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name ha accettato';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name ha risposto forse';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name ha rifiutato';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Accettato: $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Forse: $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Rifiutato: $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name ha accettato l’invito.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name forse ci sarà.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name ha rifiutato l’invito.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Invito: $summary, $when';
  }

  @override
  String get inviteFree => 'Libero · nessun conflitto';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Si sovrappone a $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Disponibilità: $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'aggiunto a $name';
  }

  @override
  String get settingsCalendars => 'Calendari';

  @override
  String get calIntro =>
      'Piuma non ha un calendario suo: collega quelli che usi già. Gli eventi restano lì.';

  @override
  String get calConnected => 'Calendari collegati';

  @override
  String calSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count origini',
      one: '1 origine',
    );
    return '$_temp0';
  }

  @override
  String calCalendars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calendari',
      one: '1 calendario',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Collega un calendario';

  @override
  String get calChoose => 'Scegli da dove collegarlo';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Server, email e password per app';

  @override
  String get calIcs => 'Iscriviti a un URL .ics';

  @override
  String get calIcsSub => 'Sola lettura, si aggiorna da sé';

  @override
  String get calCalDavLabel => 'Indirizzo email o server CalDAV';

  @override
  String get calCalDavHint =>
      'iCloud vuole una password per app; resta cifrata nel portachiavi di sistema.';

  @override
  String get calIcsLabel => 'URL del calendario .ics';

  @override
  String get calIcsHint =>
      'I calendari .ics sono in sola lettura: comodi per festività, sport, turni.';

  @override
  String get calUsername => 'Nome utente (se non è l’email)';

  @override
  String get calPassword => 'Password';

  @override
  String get calConnectButton => 'Collega';

  @override
  String get calSubscribe => 'Iscriviti';

  @override
  String get calSuggested =>
      'Gli account email che hai aggiunto e che offrono un calendario vengono proposti da soli';

  @override
  String get calHasCalendar => 'ha anche un calendario';

  @override
  String get calDone => 'Collegato';

  @override
  String get calDisconnect => 'Scollega';

  @override
  String calDisconnectLabel(String name) {
    return 'Scollega $name';
  }

  @override
  String get calReadOnly => 'sola lettura';

  @override
  String get calInvitesTag => 'inviti';

  @override
  String get calShowAvailability => 'Mostra disponibilità';

  @override
  String get calAvailabilityShort => 'disponibilità';

  @override
  String calAvailabilityFor(String name) {
    return 'Mostra disponibilità per $name';
  }

  @override
  String get calNone =>
      'Nessun calendario collegato. Gli inviti funzionano lo stesso, via email.';

  @override
  String get calWhenInvite => 'Quando arriva un invito';

  @override
  String get calAddTo => 'Aggiungi a';

  @override
  String get calAddToSub => 'Dove vanno gli inviti che accetti';

  @override
  String get calAddInvitesTo => 'Aggiungi gli inviti a';

  @override
  String get calNoWritable => 'Nessuno';

  @override
  String get calConflicts =>
      'Controlla i conflitti in tutti i calendari collegati';

  @override
  String get calConflictsSub =>
      'Gli inviti mostrano subito se a quell’ora sei già impegnato.';

  @override
  String get calFooter =>
      'Anche senza calendari collegati puoi rispondere agli inviti via email e aprire il file .ics.';

  @override
  String get calStaysHere =>
      'I collegamenti restano su questo dispositivo; le password stanno nel portachiavi di sistema.';

  @override
  String get calWrongPassword => 'Nome utente o password errati.';

  @override
  String get calUnreachable =>
      'Nessun calendario trovato lì. Controlla l’indirizzo.';

  @override
  String get calFailed => 'Collegamento non riuscito. Riprova.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => 'URL .ics, sola lettura';

  @override
  String get calFromAccount => 'dall’account email';

  @override
  String foundDateAdd(String when) {
    return 'Aggiungi $when al calendario';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Aggiunto a $calendar';
  }

  @override
  String foundDateAddLabel(String when) {
    return 'Aggiungi $when al calendario, trovato su questo dispositivo';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when aggiunto a $calendar';
  }

  @override
  String get foundOnDevice => 'Trovato su questo dispositivo';

  @override
  String get foundDateNotAdded =>
      'Non è stato possibile aggiungerlo al calendario. Riprova tra poco.';

  @override
  String get calFindDates =>
      'Suggerisci di aggiungere le date trovate nelle email';

  @override
  String get calFindDatesSub =>
      'Un piccolo suggerimento accanto alla frase, mai automatico.';

  @override
  String get calOnDevice => 'sul dispositivo';

  @override
  String get inShort => 'In breve';

  @override
  String get generatedOnDevice => 'Generato sul dispositivo';

  @override
  String get yourTurn => 'Tocca a te:';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name scrive “$words”';
  }

  @override
  String get inShortColon => 'In breve:';

  @override
  String get onDevice => 'sul dispositivo';

  @override
  String senderBriefTopic(String topic) {
    return 'soprattutto su “$topic”';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email questo mese',
      one: '1 email questo mese',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'l’ultima aspetta una tua risposta';

  @override
  String get searchByType => 'Cerca per tipo';

  @override
  String get frequentContacts => 'Contatti frequenti';

  @override
  String get recentSearches => 'Ricerche recenti';

  @override
  String get clearRecent => 'Cancella';

  @override
  String get clearRecentSearches => 'Cancella le ricerche recenti';

  @override
  String get noRecentSearches => 'Nessuna ricerca recente.';

  @override
  String get searchOperatorsHint => 'Puoi anche scrivere gli operatori';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$formatted email indicizzate su questo dispositivo · funziona offline',
      one: '1 email indicizzata su questo dispositivo · funziona offline',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'Con allegati';

  @override
  String get searchFromPeople => 'Da persone';

  @override
  String searchMailFrom(String name) {
    return 'Cerca la posta di $name';
  }

  @override
  String removeRecentSearch(String query) {
    return 'Rimuovi $query';
  }

  @override
  String get searchAddWords => 'Aggiungi parole…';

  @override
  String rowPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count foto',
      one: '1 foto',
    );
    return '$_temp0';
  }

  @override
  String rowAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count allegati',
      one: '1 allegato',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Blocca';

  @override
  String get senderBlocked => 'Bloccato';

  @override
  String showSnoozed(int count) {
    return 'Mostra Posticipate ($count)';
  }

  @override
  String get hideSnoozed => 'Nascondi Posticipate';

  @override
  String get snoozeNoReply => 'Se nessuno risponde';

  @override
  String get snoozeNoReplyHint => 'Torna tra 3 giorni se nessuno risponde';

  @override
  String get previewClose => 'Chiudi anteprima';

  @override
  String previewMeta(String size, String name) {
    return '$size · da $name';
  }

  @override
  String previewPage(int page, int count) {
    return 'Pagina $page di $count';
  }

  @override
  String get previewPrevPage => 'Pagina precedente';

  @override
  String get previewNextPage => 'Pagina successiva';

  @override
  String previewOpenEmail(String name) {
    return 'Apri l’email di $name';
  }

  @override
  String get previewDownloadAll => 'Scarica tutte';

  @override
  String previewPhoto(int index, int count) {
    return 'Foto $index di $count · dalla stessa email';
  }

  @override
  String get previewPhotos => 'Foto nell’email';

  @override
  String get previewCantShow =>
      'Questo file non si può mostrare qui. Puoi comunque scaricarlo.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Pagina $page di $name';
  }

  @override
  String get vaultParcelsTitle => 'Consegne dei pacchi';

  @override
  String get vaultParcelsHint => 'Il giorno della consegna, una volta sola.';

  @override
  String get vaultDueTitle => 'Scadenze';

  @override
  String get vaultDueHint => 'Bollette e rinnovi, tre giorni prima.';

  @override
  String get vaultNoticeParcel => 'Il tuo pacco arriva oggi';

  @override
  String get vaultNoticeDueToday => 'Scade oggi';

  @override
  String get vaultNoticeDueTomorrow => 'Scade domani';

  @override
  String vaultNoticeDueIn(int days) {
    return 'Scade tra $days giorni';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'verso le $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PEC',
      one: '1 PEC',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count non consegnate',
      one: '1 non consegnata',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Inviata';

  @override
  String get pecAccepted => 'Accettata';

  @override
  String get pecDelivered => 'Consegnata';

  @override
  String get pecFailed => 'Non consegnata';

  @override
  String pecTo(String who) {
    return 'A $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'A $count destinatari · $delivered su $count consegnate';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Accettata $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Consegnata $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'Non consegnata · $when';
  }

  @override
  String pecReasonAt(String reason, String when) {
    return '$reason · $when';
  }

  @override
  String get pecOpen => 'Apri';

  @override
  String pecReceipt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ricevute',
      one: 'Ricevuta',
    );
    return '$_temp0';
  }

  @override
  String pecSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ricevute salvate in Download',
      one: 'Ricevuta salvata in Download',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'Impossibile salvare la ricevuta';

  @override
  String get pecNote =>
      'Le ricevute restano fuori dalla posta in arrivo e si raccolgono sul messaggio a cui si riferiscono. Ricevuta salva la prova firmata come file.';

  @override
  String get pickDateTime => 'Scegli data e ora';

  @override
  String get previousMonth => 'Mese precedente';

  @override
  String get nextMonth => 'Mese successivo';

  @override
  String get pickTime => 'Ora';

  @override
  String get pickOtherTime => 'Altra ora';

  @override
  String get pickTimeGone => 'Quell’ora è già passata';

  @override
  String snoozeUntilAt(String when) {
    return 'Posticipa fino a $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Programma per $when';
  }

  @override
  String get senderNewsletterKind => 'Newsletter';

  @override
  String newsletterPerWeek(int count) {
    return 'circa $count a settimana';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'circa $count al mese';
  }

  @override
  String newsletterOpened(int percent) {
    return 'ne apri il $percent%';
  }

  @override
  String get newsletterUnsubscribed => 'Disiscritto';

  @override
  String get newsletterClearAsk => 'elimino anche le vecchie email?';

  @override
  String get newsletterClearYes => 'Sì, elimina';

  @override
  String get newsletterClearNo => 'No';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Disiscritto · $count email spostate nel Cestino',
      one: 'Disiscritto · 1 email spostata nel Cestino',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept =>
      'Disiscritto · le vecchie email restano dove sono';

  @override
  String get newsletterPageOpened =>
      'La pagina per disiscriversi è aperta nel browser';

  @override
  String get moveToNewsletters => 'Sposta in Newsletter';

  @override
  String get movedToNewsletters => 'Spostata in Newsletter';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Con allegati';

  @override
  String get appearanceTitle => 'Aspetto';

  @override
  String get appearanceSubtitle => 'Come vuoi vedere la tua posta.';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeAutomatic => 'Automatico';

  @override
  String get appearanceDensity => 'Densità';

  @override
  String get densityComfortable => 'Comoda';

  @override
  String get densityCompact => 'Compatta';

  @override
  String get appearancePreview => 'Anteprima';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count righe',
      one: '1 riga',
    );
    return '$_temp0';
  }

  @override
  String get appearanceExample => 'Esempio';

  @override
  String get previewDrawnHere => 'Disegnato su questo dispositivo';

  @override
  String get previewKeysPages => '← → pagine';

  @override
  String get previewKeysPhotos => '← → foto';

  @override
  String get meInitials => 'IO';

  @override
  String get threadSummary => 'Riassunto';

  @override
  String get signatureSheetTitle => 'Firma';

  @override
  String get signatureManage => 'Gestisci';

  @override
  String get signatureSheetNote =>
      'La firma cambia da sola quando cambi l’account in “Da”.';

  @override
  String get readerEmptyTitle => 'Nessuna conversazione selezionata';

  @override
  String readerEmptyHint(String keys) {
    return 'Fai clic su un messaggio per selezionarlo, oppure premi $keys per selezionarli tutti.';
  }

  @override
  String get hintMove => 'sposta';

  @override
  String get accountConnected => 'Account collegato';

  @override
  String get accountConnectedLead =>
      'Puoi già iniziare a leggere: il resto arriva mentre usi Piuma.';

  @override
  String get connectedDownloading => 'Download in corso, dai più recenti…';

  @override
  String get connectedUpToDate => 'Aggiornato';

  @override
  String get goToInbox => 'Vai alla posta in arrivo';

  @override
  String get addAnotherAccount => 'Aggiungi un altro account';

  @override
  String filterFrom(String name) {
    return 'Da: $name';
  }

  @override
  String get syncLeftUnderMinute => 'meno di un minuto';

  @override
  String syncLeftMinutes(int n) {
    return 'circa $n min';
  }

  @override
  String syncLeftHours(int n) {
    return 'circa $n h';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · $name in sincronizzazione';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Invia domani $time';
  }

  @override
  String get inboxSections => 'Sezioni della posta in arrivo';

  @override
  String get tabPeople => 'Persone';

  @override
  String get tabNotifications => 'Notifiche';

  @override
  String get zoneNothingNew => 'Niente di nuovo';

  @override
  String get tabAll => 'Tutte';

  @override
  String get filterUnreadHint => 'Solo le email con qualcosa da leggere';

  @override
  String get moveToPeople => 'Sposta in Persone';

  @override
  String movedToPeople(String sender) {
    return '$sender va in Persone da ora in poi';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender va in Notifiche da ora in poi';
  }

  @override
  String get moveToNotifications => 'Sposta in Notifiche';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count da leggere';
  }

  @override
  String get templatesTitle => 'Modelli';

  @override
  String get templatesSearch => 'Cerca nei modelli';

  @override
  String templatesFound(int found, int total) {
    return '$found di $total';
  }

  @override
  String get templatesNone =>
      'Ancora nessun modello. Salva quello che scrivi come modello.';

  @override
  String templatesNoMatch(String query) {
    return 'Nessun modello “$query”';
  }

  @override
  String get templateSaveThis => 'Salva come modello';

  @override
  String get templatesManage => 'Gestisci';

  @override
  String get templateUntitled => 'Modello senza nome';

  @override
  String templateSavedNote(String name) {
    return 'Salvato come modello “$name”';
  }

  @override
  String get templatesSubtitle =>
      'Su questo dispositivo, per tutti gli account';

  @override
  String get templatesNew => 'Nuovo modello';

  @override
  String get templateNameLabel => 'Nome';

  @override
  String get templateTextLabel => 'Testo';

  @override
  String templateSubjectLine(String subject) {
    return 'Oggetto: $subject';
  }

  @override
  String get templateNoSubject => 'Nessun oggetto';

  @override
  String get templateSavedAsYouType => 'Salvato mentre scrivi';

  @override
  String get templateNotSaved => 'Non è stato possibile salvare il modello';

  @override
  String get accountNameLabel => 'Nome';

  @override
  String get accountDisplayName => 'Nome visualizzato';

  @override
  String get accountDisplayNameNone => 'Non impostato';

  @override
  String get accountDefaultSignature => 'Firma predefinita';

  @override
  String get accountConnection => 'Connessione';

  @override
  String accountWorkingAgo(String ago) {
    return 'Funziona · controllato $ago';
  }

  @override
  String get accountJustNow => 'ora';

  @override
  String accountMinutesAgo(int count) {
    return '$count min fa';
  }

  @override
  String accountAtTime(String time) {
    return 'alle $time';
  }

  @override
  String get accountConnecting => 'Connessione in corso…';

  @override
  String accountCantSignInSince(String time) {
    return 'Accesso non riuscito dalle $time';
  }

  @override
  String get accountPasswordRefused =>
      'Il server ha rifiutato la password. È cambiata?';

  @override
  String get accountEditServers => 'Modifica server';

  @override
  String get accountSignInAlert => 'Avvisami quando non riesce ad accedere';

  @override
  String get accountSignInAlertNote =>
      'Un solo avviso, la prima volta che la password viene rifiutata';

  @override
  String get accountRemove => 'Rimuovi account';

  @override
  String accountRemoveTitle(String name) {
    return 'Rimuovere $name da questo dispositivo?';
  }

  @override
  String get accountRemoveNote =>
      'La sua posta su questo dispositivo viene eliminata. Sul server resta tutto com\'è.';

  @override
  String get accountRemoveConfirm => 'Rimuovi';

  @override
  String get accountServersTitle => 'Server';

  @override
  String get accountServersSave => 'Salva';

  @override
  String get accountServersChecking => 'Controllo…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name non riesce ad accedere';
  }

  @override
  String get orStartFrom => 'Oppure parti da';

  @override
  String needsAppPassword(String provider) {
    return '$provider vuole una password per le app';
  }

  @override
  String get fastmailNeedsToken => 'Fastmail vuole un token API';

  @override
  String get gmailStep1 =>
      'Attiva la verifica in due passaggi nel tuo Account Google.';

  @override
  String get gmailStep2 =>
      'Apri Password per le app e creane una di nome “Piuma”.';

  @override
  String get gmailStep3 => 'Incolla qui le 16 lettere.';

  @override
  String get openAppPasswords => 'Apri Password per le app';

  @override
  String get icloudStep1 =>
      'Attiva l’autenticazione a due fattori per il tuo Account Apple.';

  @override
  String get icloudStep2 =>
      'In Accesso e sicurezza, apri Password specifiche per le app e creane una di nome “Piuma”.';

  @override
  String get icloudStep3 => 'Incollala qui.';

  @override
  String get openAppleAccount => 'Apri Account Apple';

  @override
  String get fastmailStep1 =>
      'In Impostazioni, apri Privacy e sicurezza, poi Gestisci token API.';

  @override
  String get fastmailStep2 =>
      'Crea un token di nome “Piuma” con accesso a Email e Invio email.';

  @override
  String get fastmailStep3 => 'Incollalo qui.';

  @override
  String get openApiTokens => 'Apri Token API';

  @override
  String get appPassword => 'Password per le app';

  @override
  String get apiToken => 'Token API';

  @override
  String get pecWhichProvider => 'Chi gestisce la tua PEC?';

  @override
  String get pecWhichProviderHint =>
      'La posta certificata arriva con i server del suo gestore.';

  @override
  String signInToPec(String provider) {
    return 'Accedi a $provider';
  }

  @override
  String get pecStep1 => 'Usa l’indirizzo PEC completo.';

  @override
  String get pecStep2 => 'Usa la password della casella, quella della webmail.';

  @override
  String get verifiedSenderSetting => 'Mostra mittente verificato';

  @override
  String get verifiedSenderSettingHint =>
      'Segna i mittenti che il tuo server di posta ha controllato con DKIM, SPF e DMARC.';

  @override
  String get verifiedBadge => 'Verificato';

  @override
  String get verifiedSenderLabel => 'Mittente verificato';

  @override
  String get ruleFieldBody => 'il testo';

  @override
  String get newFolder => 'Nuova cartella';

  @override
  String get newFolderName => 'Nome della nuova cartella';

  @override
  String get create => 'Crea';

  @override
  String get newFolderFailed =>
      'Il server non ha creato la cartella. Prova un altro nome.';

  @override
  String get groupsTitle => 'Gruppi';

  @override
  String get groupsSubtitle =>
      'Riunisci indirizzi di account e domini diversi. Ogni gruppo ha il suo colore, la sua firma e, se vuoi, la sua Posta in arrivo.';

  @override
  String get groupsNone =>
      'Ancora nessun gruppo. Un gruppo riunisce indirizzi, anche di account diversi, sotto un colore e una firma.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Nessuno',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count indirizzi',
      one: '1 indirizzo',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Firma';

  @override
  String get groupSendFromShort => 'Invia da';

  @override
  String get groupNoSignature => 'Nessuna';

  @override
  String get groupName => 'Nome del gruppo';

  @override
  String get groupColor => 'Colore del gruppo';

  @override
  String get groupAddressesHeading => 'Indirizzi';

  @override
  String get groupAccount => 'Account';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return 'Account $name';
  }

  @override
  String groupAliasNote(String email) {
    return 'su $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return 'Togli $email dal gruppo';
  }

  @override
  String get groupAddAddress => 'Aggiungi indirizzo';

  @override
  String get groupDefaultSignature => 'Firma predefinita';

  @override
  String get groupSendFrom => 'Invia le nuove email da';

  @override
  String get groupSeparateInbox => 'Posta in arrivo separata';

  @override
  String get groupSeparateOn =>
      'Ha una sua voce nella barra laterale. Resta anche nella Posta unificata.';

  @override
  String get groupSeparateOff =>
      'Le sue email stanno solo nella Posta unificata.';

  @override
  String get groupNotifyOn => 'Segue le tue regole delle notifiche.';

  @override
  String get groupNotifyOff => 'Nessun avviso per questo gruppo.';

  @override
  String get groupReplyAsWritten =>
      'Rispondi sempre dall\'indirizzo a cui ti hanno scritto';

  @override
  String groupReplyOn(String email) {
    return 'Se qualcuno scrive a $email, la tua risposta parte da $email, con la firma di quel gruppo.';
  }

  @override
  String get groupReplyOnAny =>
      'Se qualcuno scrive a un tuo alias, la risposta parte da lì, con la firma del suo gruppo.';

  @override
  String get groupReplyOff =>
      'Le risposte partono dall\'indirizzo predefinito del gruppo.';

  @override
  String get groupNew => 'Nuovo gruppo';

  @override
  String get groupNewName => 'Nuovo gruppo';

  @override
  String get groupDelete => 'Elimina gruppo';

  @override
  String groupDeleteAsk(String name) {
    return 'Eliminare $name?';
  }

  @override
  String get groupDeleteNote =>
      'Gli indirizzi restano ai loro account; se ne va solo il gruppo.';

  @override
  String get groupYourAddresses => 'I tuoi indirizzi';

  @override
  String get groupMovesHere => 'In un altro gruppo: passa qui';

  @override
  String get groupFoundInSent => 'Trovati nella posta inviata';

  @override
  String get groupNewAlias => 'Nuovo alias';

  @override
  String get groupNewAliasHint => 'nome@dominio.it';

  @override
  String get groupAliasOn => 'su';

  @override
  String get groupAddAlias => 'Aggiungi';

  @override
  String get groupAliasInvalid => 'Non sembra un indirizzo email.';

  @override
  String get fromAutomatic => 'Automatico';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Scelto perché $name ha scritto a $email';
  }

  @override
  String rowWrittenTo(String email) {
    return 'a $email';
  }

  @override
  String get groupsAll => 'Tutti i gruppi';

  @override
  String groupExpand(String name) {
    return 'Apri $name';
  }

  @override
  String groupCollapse(String name) {
    return 'Chiudi $name';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses indirizzi',
      one: '1 indirizzo',
    );
    return '$_temp0 · $unread da leggere';
  }

  @override
  String groupsAllLine(int groups, int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups gruppi',
      one: '1 gruppo',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses indirizzi',
      one: '1 indirizzo',
    );
    return '$_temp0 · $_temp1 · $unread da leggere';
  }

  @override
  String groupOnly(String email) {
    return 'Solo $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Solo $email. Mostra tutto il gruppo';
  }

  @override
  String get groupSheetTitle => 'Mostra';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses indirizzi',
      one: '1 indirizzo',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups gruppi',
      one: '1 gruppo',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get groupSheetLabel => 'Scegli il gruppo';

  @override
  String get groupManage => 'Gestisci i gruppi';

  @override
  String get groupTitleAll => 'Gruppo: tutti. Cambia gruppo';

  @override
  String groupTitleOne(String name) {
    return 'Gruppo: $name. Cambia gruppo';
  }

  @override
  String get syncTitle => 'Dispositivi e sync';

  @override
  String get syncSubtitle =>
      'Le tue impostazioni su ogni dispositivo, cifrate end-to-end';

  @override
  String get syncOff => 'Disattivata · solo questo dispositivo';

  @override
  String get syncOffBody =>
      'Tieni account, gruppi, firme e impostazioni su ogni dispositivo. Vengono cifrati qui e salvati in una cartella nascosta di una delle tue caselle. Nessun server.';

  @override
  String get syncOffNote =>
      'Le password viaggiano solo dentro la copia cifrata.';

  @override
  String get syncStoreIn => 'Salvala in';

  @override
  String get syncMailbox => 'Casella della sync';

  @override
  String get syncMoving => 'Spostamento…';

  @override
  String get syncFailTaken =>
      'Quella casella contiene già un altro spazio di sincronizzazione.';

  @override
  String get syncTurnOn => 'Attiva la sincronizzazione';

  @override
  String get syncAllSynced => 'Tutto sincronizzato';

  @override
  String get syncNotYet => 'Non ancora sincronizzato';

  @override
  String syncOnBody(String name) {
    return 'Account, gruppi, firme e impostazioni sono cifrati e salvati nella casella $name. Nessun server.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · cartella nascosta · cifrata end-to-end';
  }

  @override
  String get syncDevices => 'Dispositivi collegati';

  @override
  String get syncThisDevice => 'Questo dispositivo';

  @override
  String get syncActiveNow => 'Attivo ora';

  @override
  String syncActive(String ago) {
    return 'Attivo $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ore fa',
      one: '1 ora fa',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'ieri';

  @override
  String syncDaysAgo(int count) {
    return '$count giorni fa';
  }

  @override
  String get syncUnlink => 'Scollega';

  @override
  String syncUnlinkName(String name) {
    return 'Scollega $name';
  }

  @override
  String syncUnlinkAsk(String name) {
    return 'Scollegare $name?';
  }

  @override
  String get syncUnlinkNote =>
      'Tiene quello che ha adesso ma non riceve più modifiche. Cambia anche la frase di recupero: scriverai quella nuova.';

  @override
  String get syncLinkNew => 'Collega un nuovo dispositivo';

  @override
  String syncLinkBody(String email) {
    return 'Sul nuovo dispositivo apri Piuma, scegli “Uso già Piuma su un altro dispositivo” e accedi a $email. Ti mostra 6 cifre, e questo dispositivo te le chiede.';
  }

  @override
  String get syncLinkWaiting => 'In attesa del nuovo dispositivo…';

  @override
  String get syncLinkScan =>
      'Sul nuovo telefono apri Piuma, scegli “Uso già Piuma su un altro dispositivo” e inquadra questo codice.';

  @override
  String get syncLinkQrLabel => 'Codice QR per collegare un nuovo dispositivo';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · nuovo codice tra $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return 'Niente fotocamera? Sul nuovo dispositivo accedi a $email: ti mostra 6 cifre, e questo dispositivo te le chiede.';
  }

  @override
  String syncLinked(String name) {
    return '$name collegato';
  }

  @override
  String get syncPhraseRow => 'Frase di recupero';

  @override
  String get syncPhraseRowLine =>
      'Apre il tuo spazio se perdi tutti i dispositivi';

  @override
  String get syncShow => 'Mostra';

  @override
  String get syncPhraseTitle => 'La tua frase di recupero';

  @override
  String get syncPhraseBody =>
      'Se perdi tutti i dispositivi, queste 24 parole sono l\'unico modo per rientrare nel tuo spazio. Scrivile su carta e tienile al sicuro. Piuma non può recuperarle per te.';

  @override
  String get syncPhraseNewTitle => 'La tua nuova frase di recupero';

  @override
  String syncPhraseNewBody(String name) {
    return '$name non può più aprire il tuo spazio e la vecchia frase non funziona più. Scrivi invece queste 24 parole su carta.';
  }

  @override
  String get syncPhraseWarn =>
      'Chi ha queste parole può leggere il tuo spazio.';

  @override
  String get syncPhraseDone => 'Le ho scritte';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Un nuovo telefono vuole collegarsi',
      'tablet': 'Un nuovo tablet vuole collegarsi',
      'other': 'Un nuovo computer vuole collegarsi',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · ha chiesto $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Scrivi le 6 cifre che mostra il telefono.',
      'tablet': 'Scrivi le 6 cifre che mostra il tablet.',
      'other': 'Scrivi le 6 cifre che mostra il computer.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'Le 6 cifre';

  @override
  String get syncNotMe => 'Non sono io';

  @override
  String get syncApprove => 'Approva';

  @override
  String get syncApproving => 'Approvazione…';

  @override
  String syncFailOffline(String email) {
    return 'Non riesco a raggiungere $email. Riprova quando sei online.';
  }

  @override
  String get syncFailExpired =>
      'La richiesta è scaduta. Richiedi di nuovo dal nuovo dispositivo.';

  @override
  String get syncFailOther => 'Qualcosa è andato storto. Riprova.';

  @override
  String get syncRowOn => 'Attiva';

  @override
  String get syncRowOff => 'Disattivata';

  @override
  String get pairAlready => 'Uso già Piuma su un altro dispositivo';

  @override
  String get pairAlreadyOn =>
      'Accedi a una delle tue caselle. Se contiene il tuo spazio, poi colleghi questo dispositivo.';

  @override
  String get pairLinkTitle => 'Collega questo telefono';

  @override
  String get pairLinkBody =>
      'Sul computer apri Impostazioni › Dispositivi e sync › Collega un nuovo dispositivo, poi inquadra il codice che mostra.';

  @override
  String get pairScan => 'Scansiona codice';

  @override
  String get pairSignInInstead => 'Accedi invece';

  @override
  String get pairScanHint => 'Inquadra il codice sul computer';

  @override
  String get pairScanWhere =>
      'Impostazioni › Dispositivi e sync › Collega un nuovo dispositivo';

  @override
  String get pairNoCamera =>
      'Piuma non può usare la fotocamera. Consentilo nelle impostazioni di sistema, oppure accedi invece.';

  @override
  String get pairLastStep => 'Un ultimo passo';

  @override
  String get pairLastStepBody =>
      'Accedi alla casella che custodisce il tuo spazio. Gli altri account arrivano da soli.';

  @override
  String get pairConfirmsOwn =>
      'Il computer conferma da solo: è lui che ti ha mostrato il codice.';

  @override
  String get pairLink => 'Collega';

  @override
  String get pairLinking => 'Collegamento…';

  @override
  String get pairFoundTitle => 'Abbiamo trovato il tuo spazio';

  @override
  String pairFoundBody(String email) {
    return 'La casella $email contiene una copia cifrata delle tue impostazioni. Solo i tuoi dispositivi possono leggerla.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'account',
      one: 'account',
    );
    return '$_temp0';
  }

  @override
  String pairGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'gruppi',
      one: 'gruppo',
    );
    return '$_temp0';
  }

  @override
  String pairSignatures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'firme',
      one: 'firma',
    );
    return '$_temp0';
  }

  @override
  String pairEncrypted(String when) {
    return 'Cifrato end-to-end · aggiornato $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'Per sicurezza, conferma da un dispositivo già collegato: $name, attivo $ago.';
  }

  @override
  String get pairShowCode => 'Mostra il codice';

  @override
  String get pairUsePhrase => 'Usa la frase di recupero';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Conferma sul telefono',
      'tablet': 'Conferma sul tablet',
      'other': 'Conferma sul computer',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Apri Piuma su $name e scrivi il codice.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Codice $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Scade tra $time';
  }

  @override
  String pairWaiting(String name) {
    return 'In attesa della conferma di $name…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name mostrerà “$title”';
  }

  @override
  String get pairStep2 => 'Scrivi le 6 cifre e tocca Approva';

  @override
  String get pairExpired => 'Il codice è scaduto.';

  @override
  String pairRefused(String name) {
    return '$name ha detto che non eri tu.';
  }

  @override
  String get pairWrongCode => 'Il codice scritto là non era questo.';

  @override
  String get pairNewCode => 'Mostra un nuovo codice';

  @override
  String get pairPhraseTitle => 'Frase di recupero';

  @override
  String get pairPhraseBody =>
      'Scrivi le 24 parole che hai annotato, in ordine, separate da spazi.';

  @override
  String pairPhraseCount(int count) {
    return '$count di 24 parole';
  }

  @override
  String get pairPhraseWrong =>
      'Queste parole non aprono il tuo spazio. Controllale e riprova.';

  @override
  String get pairContinue => 'Continua';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Telefono collegato',
      'tablet': 'Tablet collegato',
      'other': 'Computer collegato',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody => 'Ecco cosa è arrivato dal tuo spazio cifrato.';

  @override
  String get pairDoneAccounts => 'Account';

  @override
  String get pairDoneGroups => 'Gruppi';

  @override
  String get pairDoneSettings => 'Firme e impostazioni sincronizzate';

  @override
  String get pairSynced => 'Sincronizzato';

  @override
  String pairStepOf(int step) {
    return 'Passo $step di 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'oggi alle $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'ieri alle $time';
  }

  @override
  String pairOnDay(String day) {
    return 'il $day';
  }

  @override
  String get keyOpenWindow => 'apri in una nuova finestra';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizzato su $count dispositivi',
      one: 'Sincronizzato su 1 dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters =>
      'Quando una newsletter è stata letta più di 7 giorni fa';

  @override
  String get ruleBuiltIn => 'Inclusa · tutti gli account';

  @override
  String get syncTurnOff =>
      'Disattiva la sincronizzazione su questo dispositivo';

  @override
  String get syncTurnOffAsk =>
      'Disattivare la sincronizzazione su questo dispositivo?';

  @override
  String syncTurnOffOne(String name) {
    return 'Questo dispositivo lascia il tuo spazio e non riceve più modifiche. Account e posta restano qui. $name continua a sincronizzarsi.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'Questo dispositivo lascia il tuo spazio e non riceve più modifiche. Account e posta restano qui. $names continuano a sincronizzarsi.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'Questo dispositivo lascia il tuo spazio e non riceve più modifiche. Account e posta restano qui. È il tuo unico dispositivo: viene eliminata anche la copia cifrata in $email.';
  }

  @override
  String get syncTurnOffButton => 'Disattiva';

  @override
  String get listAnd => 'e';

  @override
  String get composeDropFiles => 'Rilascia per allegare';

  @override
  String get serverType => 'Tipo di server';

  @override
  String get imapAndSmtp => 'IMAP e SMTP';

  @override
  String get jmapServer => 'Server JMAP';

  @override
  String get jmapServerHint =>
      'Il nome del server, o l\'indirizzo completo della sua sessione JMAP.';

  @override
  String get jmapSignsIn =>
      'Un solo server legge, invia e porta subito la nuova posta. Accedi con il tuo indirizzo.';

  @override
  String get shortcutsTitle => 'Scorciatoie';

  @override
  String shortcutsLine(String keys) {
    return 'Solo l’essenziale. Tutto il resto è in $keys.';
  }

  @override
  String get shortcutsTable => 'Scorciatoie da tastiera';

  @override
  String get shortcutPalette => 'Palette dei comandi';

  @override
  String ruleSuggest(String name, String folder) {
    return 'Sposti spesso le email di $name in $folder. Creo una regola?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Suggerita sul dispositivo · $count spostamenti nell’ultimo mese',
      one: 'Suggerita sul dispositivo · 1 spostamento nell’ultimo mese',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Inoltra';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Messaggio inoltrato ----------\nDa: $from\nData: $date\nA: $to\nOggetto: $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date alle $time';
  }

  @override
  String get folderWaiting => 'In attesa';

  @override
  String waitingSummary(int count) {
    return '$count inviate · ancora nessuna risposta';
  }

  @override
  String get waitingNoReply => 'Ancora nessuna risposta';

  @override
  String get waitingTo => 'A ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '1 giorno',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'oggi';

  @override
  String get waitingYesterday => 'ieri';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email inviate in attesa di risposta',
      one: '1 email inviata in attesa di risposta',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Scrivi di nuovo';

  @override
  String get stopWaiting => 'Smetti di aspettare';

  @override
  String get stoppedWaiting => 'Tolta da In attesa. Resta in Inviate.';

  @override
  String get remindMe => 'Ricordamelo';

  @override
  String get remindTitle => 'Ricordamelo se nessuno risponde';

  @override
  String get remindTomorrow => 'Domani';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tra $count giorni',
      one: 'Tra 1 giorno',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'Settimana prossima';

  @override
  String get remindPickDate => 'Scegli una data…';

  @override
  String get remindNever => 'Non ricordarmelo';

  @override
  String remindChipToday(String time) {
    return 'Ricordamelo alle $time';
  }

  @override
  String get remindChipTomorrow => 'Ricordamelo domani';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ricordamelo tra $count giorni',
      one: 'Ricordamelo tra 1 giorno',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Ricordamelo il $date';
  }

  @override
  String remindAt(String when) {
    return 'Ricordamelo $when';
  }

  @override
  String remindNoReply(String name) {
    return 'Nessuna risposta da $name';
  }

  @override
  String get remindSentToday => 'inviata oggi';

  @override
  String get remindSentYesterday => 'inviata ieri';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'inviata $count giorni fa',
      one: 'inviata 1 giorno fa',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Allegati condivisi';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count allegati',
      one: '1 allegato',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles => 'Ancora nessun allegato da questo mittente.';

  @override
  String get senderAddresses => 'Indirizzi';

  @override
  String senderAddressNote(String account, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email',
      one: '1 email',
    );
    return '$account · $_temp0';
  }

  @override
  String get senderCopyAddress => 'Copia indirizzo';

  @override
  String get senderRules => 'Regole e cartelle';

  @override
  String get senderContent => 'Contenuti del mittente';

  @override
  String folderReorder(String name) {
    return 'Trascina per riordinare $name';
  }

  @override
  String get folderMoveUp => 'Sposta su';

  @override
  String get folderMoveDown => 'Sposta giù';

  @override
  String get ruleUnopenedNewsletters => 'Newsletter';

  @override
  String get ruleUnopenedFor => ' non aperte da ';

  @override
  String get ruleUnopenedDays => '30 giorni';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email archiviate',
      one: '1 email archiviata',
      zero: 'tutti gli account',
    );
    return 'Ogni notte · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'Le regole lavorano su questo dispositivo e si sincronizzano su tutti i tuoi dispositivi';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'Le regole lavorano su questo dispositivo e si sincronizzano su tutti i tuoi dispositivi · aggiornate $ago';
  }

  @override
  String get calSynced =>
      'I collegamenti si sincronizzano su tutti i tuoi dispositivi; le password viaggiano cifrate e stanno nel portachiavi di sistema.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'si aggiorna ogni $count ore',
      one: 'si aggiorna ogni ora',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'si aggiorna ogni $count giorni',
      one: 'si aggiorna ogni giorno',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'si aggiorna ogni settimana';

  @override
  String get showOriginalLayout => 'Mostra impaginazione originale';

  @override
  String get originalLayout => 'Impaginazione originale';

  @override
  String get originalLayoutBar =>
      'Impaginazione originale · immagini e link seguono le tue impostazioni privacy';

  @override
  String get backToReadingView => 'Torna alla vista di lettura';

  @override
  String get readingView => 'Vista di lettura';

  @override
  String get replyFromLabel => 'Rispondi da';

  @override
  String get senderReadsNoReplies => 'Questo mittente non legge le risposte';

  @override
  String replyFromSignature(String name) {
    return 'firma $name';
  }

  @override
  String get noticeReplyHint => 'Scrivi una risposta…';

  @override
  String get labelsHeading => 'Etichette';

  @override
  String get labelsSection => 'ETICHETTE';

  @override
  String get labelAction => 'Etichetta';

  @override
  String get labelAdd => '+ Etichetta';

  @override
  String get labelNew => 'Nuova etichetta';

  @override
  String get labelFind => 'Trova o crea un\'etichetta';

  @override
  String labelCreate(String name) {
    return 'Crea «$name»';
  }

  @override
  String labelRemove(String name) {
    return 'Togli l\'etichetta $name';
  }

  @override
  String labelEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String labelAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count account',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account non salva le etichette sul server: le sue restano su questo dispositivo.';
  }

  @override
  String get hintLabel => 'etichetta';

  @override
  String get labelName => 'Nome dell\'etichetta';

  @override
  String get labelEdit => 'Modifica etichetta';

  @override
  String get labelSave => 'Salva';

  @override
  String get labelCreateButton => 'Crea';

  @override
  String get labelDelete => 'Elimina etichetta';

  @override
  String get labelDeleteNote =>
      'Viene tolta da tutte le email; le email restano dove sono.';

  @override
  String get labelColorAmber => 'Ambra';

  @override
  String get labelColorTeal => 'Verde acqua';

  @override
  String get labelColorCoral => 'Corallo';

  @override
  String get labelColorBlue => 'Blu';

  @override
  String get labelColorViolet => 'Viola';

  @override
  String get labelMenu => 'Etichetta…';

  @override
  String get ruleDoLabel => 'etichetta';

  @override
  String get ruleTrayLabel => 'Etichetta';

  @override
  String get rulePickLabel => 'un\'etichetta';

  @override
  String get ruleNoLabels =>
      'Ancora nessuna etichetta: creane una con + Etichetta in Cartelle ed etichette.';

  @override
  String get foldersAndLabelsHeading => 'Cartelle ed etichette';

  @override
  String get labelsCardTitle => 'Etichette';

  @override
  String get labelsCardDetail => 'comuni a tutti gli account';

  @override
  String get labelsNone => 'Ancora nessuna etichetta.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cartelle',
      one: '1 cartella',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etichette',
      one: '1 etichetta',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Immagini dei mittenti';

  @override
  String get senderPicturesSettingHint =>
      'Foto dei tuoi contatti e loghi verificati delle aziende al posto delle lettere.';

  @override
  String get websiteIconsSetting => 'Icone dei siti';

  @override
  String get websiteIconsSettingHint =>
      'Per le aziende senza logo. Ogni sito vede il tuo indirizzo IP una volta.';

  @override
  String tabletInboxUnread(int count) {
    return 'Inbox, $count da leggere';
  }

  @override
  String tabletAccount(String name, String email) {
    return 'Account $name, $email';
  }

  @override
  String get tabletSearch => 'Cerca nella posta';

  @override
  String get tabletSearchHint => 'Cerca o esegui un comando';

  @override
  String get vaultTrackParcel => 'Traccia il pacco';

  @override
  String get vaultTrackingCopied => 'Numero di spedizione copiato';

  @override
  String get vaultNeedsYou => 'Da fare';

  @override
  String get vaultNext => 'Prossimo';

  @override
  String get vaultOnTheWay => 'In arrivo';

  @override
  String get vaultEverything => 'Tutto';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cose da fare',
      one: '1 cosa da fare',
    );
    return '$_temp0';
  }

  @override
  String get vaultNothingNeeds => 'Niente da fare';

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'un volo oggi',
      'train': 'un treno oggi',
      'ferry': 'un traghetto oggi',
      'bus': 'un pullman oggi',
      'stay': 'un check-in oggi',
      'parking': 'un parcheggio oggi',
      'car': 'un\'auto a noleggio oggi',
      'event': 'un evento oggi',
      'table': 'un tavolo oggi',
      'other': 'una prenotazione oggi',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Volo',
      'train': 'Treno',
      'ferry': 'Traghetto',
      'bus': 'Pullman',
      'stay': 'Check-in',
      'parking': 'Parcheggio',
      'car': 'Noleggio auto',
      'event': 'Evento',
      'table': 'Tavolo',
      'other': 'Prenotazione',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Pacchi';

  @override
  String get vaultCatSpending => 'Spese';

  @override
  String get vaultCatTrips => 'Viaggi';

  @override
  String get vaultCatSales => 'Vendite';

  @override
  String get vaultCatSubscriptions => 'Abbonamenti';

  @override
  String get vaultCatReturns => 'Resi e garanzia';

  @override
  String get vaultCatDeadlines => 'Scadenze';

  @override
  String get vaultCatBookings => 'Prenotazioni';

  @override
  String get vaultCatVouchers => 'Buoni e carte regalo';

  @override
  String get vaultCatDocuments => 'Documenti';

  @override
  String get vaultCatCertified => 'PEC';

  @override
  String vaultOnWayCount(int count) {
    return '$count in arrivo';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count da ritirare';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count consegnati',
      one: '1 consegnato',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'In viaggio ora';

  @override
  String vaultNextWhen(String when) {
    return 'Prossimo: $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viaggi passati',
      one: '1 viaggio passato',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count da spedire';
  }

  @override
  String vaultSoldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count venduti',
      one: '1 venduto',
    );
    return '$_temp0';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money al mese';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abbonamenti',
      one: '1 abbonamento',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resi, il primo entro il $day',
      one: '1 reso entro il $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count in garanzia';
  }

  @override
  String vaultCodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codici',
      one: '1 codice',
    );
    return '$_temp0';
  }

  @override
  String vaultCountMoney(int count, String money) {
    return '$count · $money';
  }

  @override
  String vaultCertDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count consegnate',
      one: '1 consegnata',
    );
    return '$_temp0';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Pagamento non riuscito · $who';
  }

  @override
  String get vaultPaymentFailed => 'Pagamento non riuscito';

  @override
  String vaultWasDue(String when) {
    return 'Scaduto $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'Da spedire entro $when';
  }

  @override
  String get vaultToShip => 'Da spedire';

  @override
  String get vaultYouSend => 'Spedisci tu';

  @override
  String vaultSoldOn(String where) {
    return 'venduto su $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'Da ritirare entro $when';
  }

  @override
  String get vaultReadyPickup => 'Pronto da ritirare';

  @override
  String vaultRenewsWhen(String when) {
    return 'Si rinnova $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Finisce $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money a settimana',
      'month': '$money al mese',
      'year': '$money all\'anno',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'dal $day';
  }

  @override
  String get vaultUpdatePayment => 'Aggiorna il pagamento';

  @override
  String get vaultCoach => 'Carrozza';

  @override
  String get vaultTicket => 'Biglietto';

  @override
  String vaultInHours(int hours) {
    return 'tra $hours h';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'tra $minutes min';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pacchi consegnati questa settimana',
      one: '1 pacco consegnato questa settimana',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Speso a $month';
  }

  @override
  String vaultReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ricevute',
      one: '1 ricevuta',
    );
    return '$_temp0';
  }

  @override
  String get vaultExportMonth => 'Esporta il mese';

  @override
  String vaultSpentTab(String money) {
    return 'Uscite · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Entrate · $money';
  }

  @override
  String vaultVia(String service) {
    return 'con $service';
  }

  @override
  String get vaultSpendingNote => 'Letto sul dispositivo da ricevute e fatture';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file e $count PDF salvati in Download',
      one: '$file e 1 PDF salvati in Download',
      zero: '$file salvato in Download',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'Non sono riuscito a esportare il mese';

  @override
  String get vaultPrevMonth => 'Mese precedente';

  @override
  String get vaultNextMonth => 'Mese successivo';

  @override
  String get vaultNothingThisMonth => 'Nessuna ricevuta questo mese.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Abbonamenti · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Data,Chi,Cosa,Importo,Valuta,Pagato con,File,Partita IVA';

  @override
  String vaultComingUp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count in arrivo',
      one: '1 in arrivo',
    );
    return '$_temp0';
  }

  @override
  String get vaultNoTrips => 'Nessun viaggio in programma';

  @override
  String get vaultPastTrips => 'Viaggi passati';

  @override
  String vaultThisYear(int count) {
    return '$count quest\'anno';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'Ora · ritorno $when';
  }

  @override
  String get vaultLegDone => 'Fatto';

  @override
  String vaultUntilTime(String time) {
    return 'Fino alle $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Fino al $day';
  }

  @override
  String get vaultTripsNote =>
      'Treni, traghetti, voli, alloggi, parcheggi e biglietti';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notti',
      one: '1 notte',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'dalle $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'carrozza $coach, posto $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'posto $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'codice $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Volo $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Venduto su $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Venduto su $who';
  }

  @override
  String get vaultSaleOnWay => 'In viaggio';

  @override
  String get vaultSaleReceived => 'Ricevuto';

  @override
  String get vaultPaidOut => 'Pagato';

  @override
  String get vaultCanGoBack => 'Si può ancora rendere';

  @override
  String get vaultUnderWarranty => 'In garanzia';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days giorni per il reso';
  }

  @override
  String vaultBought(String day) {
    return 'comprato il $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Garanzia $month';
  }

  @override
  String get vaultCodeCopied => 'Codice copiato';

  @override
  String get vaultCopyCode => 'Copia il codice';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Busta paga',
      'statement': 'Estratto conto',
      'tax': 'Modulo fiscale',
      'contract': 'Contratto',
      'other': 'Documento',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Apri il file';

  @override
  String vaultBookingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count prenotazioni',
      one: '1 prenotazione',
    );
    return '$_temp0';
  }

  @override
  String vaultDocumentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documenti',
      one: '1 documento',
    );
    return '$_temp0';
  }

  @override
  String get vaultCategoryEmpty => 'Niente qui per ora.';

  @override
  String get vaultFlagged => 'da fare';

  @override
  String get suggestWroteTo => 'Hai scritto';

  @override
  String get suggestWroteToYou => 'Ti ha scritto';

  @override
  String get readerEmptyTap => 'Tocca un messaggio per leggerlo.';

  @override
  String get noticeAwayTitle => 'Mentre eri via';

  @override
  String noticeAwayEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email',
      one: '1 email',
    );
    return '$_temp0';
  }

  @override
  String noticeAwayPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count da persone',
      one: '1 da una persona',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Weekend, tutto il giorno';

  @override
  String get quietWeekendsHint => 'Sabato e domenica';

  @override
  String get quietWhile => 'Durante il silenzio';

  @override
  String get quietWhileHint => 'Nessun avviso riassume tutto alla fine';

  @override
  String get quietNoSound => 'Senza suono';

  @override
  String get quietNoNotices => 'Nessun avviso';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · suona come sempre';
  }

  @override
  String get quietAccountsHint =>
      'Gli account spenti suonano come sempre durante il silenzio.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'arabo',
      'bg': 'bulgaro',
      'ca': 'catalano',
      'cs': 'ceco',
      'zh': 'cinese',
      'da': 'danese',
      'de': 'tedesco',
      'el': 'greco',
      'en': 'inglese',
      'et': 'estone',
      'fi': 'finlandese',
      'fr': 'francese',
      'he': 'ebraico',
      'hi': 'hindi',
      'hr': 'croato',
      'hu': 'ungherese',
      'id': 'indonesiano',
      'it': 'italiano',
      'ja': 'giapponese',
      'ko': 'coreano',
      'lt': 'lituano',
      'lv': 'lettone',
      'nl': 'olandese',
      'nb': 'norvegese',
      'pl': 'polacco',
      'pt': 'portoghese',
      'ro': 'rumeno',
      'ru': 'russo',
      'sk': 'slovacco',
      'sl': 'sloveno',
      'es': 'spagnolo',
      'sr': 'serbo',
      'sv': 'svedese',
      'th': 'thailandese',
      'tr': 'turco',
      'uk': 'ucraino',
      'vi': 'vietnamita',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Scritto in $language';
  }

  @override
  String get translateAction => 'Traduci';

  @override
  String translateGetting(String from, String to) {
    return 'Scarico $from–$to';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return 'Scarico $from–$to · $size';
  }

  @override
  String get translating => 'Traduco…';

  @override
  String translatedFrom(String language) {
    return 'Originale in $language · tradotto su questo dispositivo';
  }

  @override
  String get translatedShort => 'Tradotto';

  @override
  String get translateShowOriginal => 'Mostra originale';

  @override
  String get translateOriginalShort => 'Originale';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'Per tradurre, scarica prima $from e $to.';
  }

  @override
  String get translateFailed =>
      'Non sono riuscito a tradurre questa email. Riprova.';

  @override
  String get appearanceTranslateInto => 'Traduci in';

  @override
  String get translateIntoApp => 'Lingua dell’app';

  @override
  String get translateIntoHint =>
      'Le email in altre lingue offrono Traduci. Avviene su questo dispositivo.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Rimuovi';

  @override
  String translateRemovePair(String pair) {
    return 'Rimuovi $pair';
  }

  @override
  String get printEmail => 'Stampa…';

  @override
  String printTooltip(String keys) {
    return 'Stampa… $keys';
  }

  @override
  String get printOrSavePdf => 'Stampa o salva come PDF';

  @override
  String get reportSpam => 'Segnala come spam';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni segnalate come spam',
      one: 'Segnalato come spam',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'Non è spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni spostate in Inbox',
      one: 'Spostato in Inbox',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Data';

  @override
  String printAttachments(String files) {
    return 'Allegati: $files';
  }

  @override
  String get helpTitle => 'Aiuto e feedback';

  @override
  String get helpSubtitle =>
      'Segnala un problema o suggerisci un\'idea. Non parte niente senza di te.';

  @override
  String get reportProblem => 'Segnala un problema';

  @override
  String get reportThisProblem => 'Segnala questo problema';

  @override
  String get reportCantAddAccount => 'Non riesco ad aggiungere l’account';

  @override
  String get suggestIdea => 'Suggerisci un\'idea';

  @override
  String get shakeToReport => 'Scuoti per segnalare';

  @override
  String get shakeToReportHint => 'Scuoti il telefono su qualsiasi schermata';

  @override
  String get yourReports => 'I tuoi report';

  @override
  String get reportNone => 'Ancora nessun report.';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportKindProblem => 'Problema';

  @override
  String get reportKindIdea => 'Idea';

  @override
  String get reportTitleField => 'Titolo';

  @override
  String get reportTitleHint => 'In poche parole';

  @override
  String get reportProblemField => 'Cosa è successo';

  @override
  String get reportIdeaField => 'Cosa e perché';

  @override
  String get reportDescriptionHint => 'Cosa hai fatto e cosa ti aspettavi';

  @override
  String get reportScreenshot => 'Screenshot di questa schermata';

  @override
  String get reportScreenshotWindow => 'Screenshot di questa finestra';

  @override
  String get reportScreenshotOff => 'Spento: potrebbe mostrare la tua posta';

  @override
  String get reportScreenshotOn =>
      'Tocca l\'immagine per nascondere delle parti';

  @override
  String get reportLog => 'Log dell\'app';

  @override
  String get reportLogHint => 'Senza indirizzi né oggetti';

  @override
  String get reportDevice => 'Info su dispositivo e app';

  @override
  String get reportDeviceHint => 'Versione, modello, lingua';

  @override
  String get reportAlways => 'Sempre';

  @override
  String get reportSeeSent => 'Vedi cosa viene inviato';

  @override
  String get reportSend => 'Invia';

  @override
  String get reportQueued => 'Report in coda';

  @override
  String get reportNotKept => 'Impossibile salvare il report';

  @override
  String get reportWhatsSent => 'Cosa viene inviato';

  @override
  String get reportSectionReport => 'Report';

  @override
  String get reportSectionDevice => 'Dispositivo';

  @override
  String get reportSectionScreenshot => 'Screenshot';

  @override
  String get reportHideParts => 'Nascondi parti';

  @override
  String get reportDragToBlur => 'Trascina per sfocare';

  @override
  String get reportDone => 'Fatto';

  @override
  String get reportStatusQueued => 'In coda';

  @override
  String get reportStatusSending => 'Invio';

  @override
  String get reportStatusFailed => 'Non riuscito';

  @override
  String get reportStatusEmailed => 'Via email';

  @override
  String get reportWaitOffline => 'in attesa di rete';

  @override
  String get reportWaitTurn => 'parte tra poco';

  @override
  String reportWaitAt(String time) {
    return 'parte alle $time';
  }

  @override
  String get reportWaitPaused => 'parte più tardi o domani';

  @override
  String get reportTapRetry => 'tocca per riprovare';

  @override
  String get reportTryAgain => 'Riprova';

  @override
  String get reportByEmail => 'Invia via email';

  @override
  String get reportDelete => 'Elimina';

  @override
  String get reportOptions => 'Opzioni del report';

  @override
  String get crashLine => 'Piuma si è chiusa all\'improvviso. Mandi un report?';

  @override
  String get crashReport => 'Segnala';

  @override
  String get crashDismiss => 'Ignora';

  @override
  String reportStatusSent(int number) {
    return 'Inviato #$number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines righe',
      one: '1 riga',
    );
    return 'Log dell\'app · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Aiuto';

  @override
  String get awayTitle => 'Risposta automatica';

  @override
  String get awayNote => 'Risponde per te, anche con l\'app chiusa';

  @override
  String get awayFrom => 'Dal';

  @override
  String get awayToInline => 'al';

  @override
  String get awayTo => 'Al';

  @override
  String get awaySubject => 'Oggetto';

  @override
  String get awayMessage => 'Messaggio';

  @override
  String get awayEndsNote =>
      'Si spegne da sola dopo l\'ultimo giorno. Lascia vuoto \"al\" per tenerla attiva finché non la spegni.';

  @override
  String awaySubjectUntil(String date) {
    return 'Assente fino al $date';
  }

  @override
  String get awaySubjectPlain => 'Assente';

  @override
  String awayBodyUntil(String date) {
    return 'Ciao, sono assente fino al $date e ti risponderò al mio rientro.';
  }

  @override
  String get awayBodyPlain =>
      'Ciao, sono assente e ti risponderò al mio rientro.';

  @override
  String get awayToday => 'Oggi';

  @override
  String get awayNoEnd => 'Nessuna fine';

  @override
  String get awayPickFrom => 'Primo giorno';

  @override
  String get awayPickTo => 'Ultimo giorno';

  @override
  String get awayKeepOn => 'Tienila attiva finché non la spengo';

  @override
  String get awayOtherFilters =>
      'Non si può attivare insieme ai filtri che hai già. Disattivali prima sul server.';

  @override
  String get awayUnsupported =>
      'Questo server non accetta più una risposta automatica.';

  @override
  String get awayOffline => 'Server non raggiungibile. Riprova tra poco.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Risposta automatica attiva per $account fino a $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Risposta automatica attiva per $account';
  }

  @override
  String get awayTurnOff => 'Disattiva';

  @override
  String get awayRowOff => 'Disattivata';

  @override
  String get awayRowOn => 'Attiva';

  @override
  String awayRowUntil(String date) {
    return 'Attiva fino a $date';
  }

  @override
  String get featuresSubtitle =>
      'Spegni quello che non usi. Sparisce dappertutto, e non si cancella niente.';

  @override
  String get featuresZones => 'Zone';

  @override
  String get featuresOnDevice => 'Sul dispositivo';

  @override
  String get featuresOnDeviceNote =>
      'Niente di tutto questo lascia il dispositivo.';

  @override
  String get featureNewslettersHint =>
      'Le newsletter in una lista a parte, da leggere come una rivista';

  @override
  String get featureNewslettersOff =>
      'Spenta · le newsletter arrivano nella inbox come le altre email';

  @override
  String get featureVaultHint =>
      'Pagamenti, pacchi, viaggi e scadenze come schede';

  @override
  String get featureVaultOff =>
      'Spento · queste email restano come sono, senza schede né avvisi';

  @override
  String get featureAttachmentsHint =>
      'Tutti i file ricevuti, in un posto solo';

  @override
  String get featureAttachmentsOff =>
      'Spenti · i file restano nelle loro email, e la ricerca li trova';

  @override
  String get featureInShortHint =>
      'Il succo delle conversazioni lunghe, sopra la prima email';

  @override
  String get featureInShortOff =>
      'Spento · le conversazioni si aprono senza riassunto';

  @override
  String get featureTranslate => 'Traduci';

  @override
  String get featureTranslateHint =>
      'Propone di tradurre le email scritte in altre lingue';

  @override
  String get featureTranslateOff =>
      'Spento · nessuna proposta di traduzione, e nessuna lingua scaricata';

  @override
  String get featureFoundDates => 'Date nelle email';

  @override
  String get featureFoundDatesHint =>
      'Aggiungi al calendario per date e orari trovati nel testo';

  @override
  String get featureFoundDatesOff =>
      'Spento · gli inviti mostrano comunque la loro scheda';

  @override
  String get nextEmail => 'Email successiva';

  @override
  String get previousEmail => 'Email precedente';

  @override
  String get appearanceLanguage => 'Lingua';

  @override
  String get languageDevice => 'Lingua del dispositivo';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain sembra $like, ma è un indirizzo diverso.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'Il nome dice $brand, ma l’indirizzo è su $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'Questa email dice di venire da $domain, ma $domain non l’ha inviata.';
  }

  @override
  String get senderDetails => 'Dettagli';

  @override
  String get senderDetailsTitle => 'Cosa è stato controllato';

  @override
  String get senderSentBy => 'Inviata da';

  @override
  String get senderNotKnown => 'Non noto';

  @override
  String get senderSignature => 'Firma';

  @override
  String get senderSignatureNone => 'Nessuna';

  @override
  String get senderDomainCheck => 'Controllo del dominio';

  @override
  String get senderDomainCheckFailed => 'Non superato (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Sembra';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count email da lì',
      one: '1 email da lì',
      zero: 'nessuna email da lì',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'Il nome dice';

  @override
  String get senderDetailsNote =>
      'Ricavato su questo dispositivo da ciò che ha scritto il tuo server di posta. I link in questa email chiedono prima di aprirsi.';

  @override
  String impostorLinkBody(String real) {
    return 'Questa email potrebbe non venire da chi dice. Il link porta a $real.';
  }

  @override
  String get updates => 'Aggiornamenti';

  @override
  String get updatesVersion => 'Versione';

  @override
  String get upToDate => 'Aggiornata';

  @override
  String get updatesAuto => 'Piuma cerca da sola le nuove versioni';

  @override
  String get checkForUpdates => 'Cerca aggiornamenti';

  @override
  String get updateChecking => 'Controllo…';

  @override
  String get checkedJustNow => 'Controllato ora';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Controllato $count minuti fa',
      one: 'Controllato 1 minuto fa',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Controllato $count ore fa',
      one: 'Controllato 1 ora fa',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Controllato $count giorni fa',
      one: 'Controllato ieri',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Download di $version · $percent%';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done di $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Pronta · $version';
  }

  @override
  String get updateGoesInOnRestart => 'Si installa quando Piuma si riavvia';

  @override
  String get restart => 'Riavvia';

  @override
  String get updateCouldntCheck => 'Controllo non riuscito';

  @override
  String get tryAgain => 'Riprova';

  @override
  String get seeWhatsNew => 'Novità di questa versione';

  @override
  String get whatsNew => 'Novità';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'Posta e bozze restano. Piuma si chiude e si riapre in pochi secondi.';

  @override
  String get restartNow => 'Riavvia ora';

  @override
  String updateReadyLine(String version) {
    return 'Aggiornamento pronto · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Aggiornata a $version';
  }

  @override
  String get swipeHintArchiveSnooze =>
      'Scorri a destra per archiviare, a sinistra per posticipare';

  @override
  String get swipeHintArchive => 'Scorri a destra per archiviare';

  @override
  String get formatting => 'Formattazione';

  @override
  String get formatBold => 'Grassetto';

  @override
  String get formatItalic => 'Corsivo';

  @override
  String get formatLink => 'Link';

  @override
  String get formatBullets => 'Elenco puntato';

  @override
  String get formatNumbers => 'Elenco numerato';

  @override
  String get formatQuote => 'Citazione';

  @override
  String get linkAddressHint => 'Incolla o scrivi un indirizzo';

  @override
  String get linkAdd => 'Aggiungi';

  @override
  String get linkRemove => 'Togli link';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count immagini sono spente, così $sender non vede quando la apri.',
      one: '1 immagine è spenta, così $sender non vede quando la apri.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Carica immagini';

  @override
  String get alwaysForSender => 'Sempre per questo mittente';

  @override
  String get cleanView => 'Vista pulita';

  @override
  String get viewOriginal => 'Originale';

  @override
  String get viewClean => 'Pulita';

  @override
  String get calGoogle => 'Google Calendar';

  @override
  String get calGoogleSub => 'Leggi eventi e disponibilità con un link iCal';

  @override
  String get calGoogleLabel => 'Indirizzo iCal di Google Calendar';

  @override
  String get calGoogleHint =>
      'In Google Calendar da computer: Impostazioni › il tuo calendario › Integra calendario › Indirizzo segreto in formato iCal. Sola lettura; connessione diretta.';

  @override
  String get bundledReleaseNotes =>
      '## La posta, resa leggera\n- Layout originali delle email con scorrimento unico e controllo immagini\n- Barra di formattazione e apertura dell’editor completo nelle risposte\n- Gesti di scorrimento orizzontale più precisi\n- Avvisi mittente per marchi imitati e domini simili\n- Esportazione CSV mensile del Caveau con partita IVA del venditore';
}
