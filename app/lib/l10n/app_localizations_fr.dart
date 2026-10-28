// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get catalogSubtitle => 'Catalogue des composants · Phase 0';

  @override
  String get sectionColors => 'Couleurs';

  @override
  String get sectionTypography => 'Typographie';

  @override
  String get sectionButtons => 'Boutons';

  @override
  String get sectionFilters => 'Filtres';

  @override
  String get sectionMessageRows => 'Lignes de message';

  @override
  String get colorBackground => 'Fond';

  @override
  String get colorSurface => 'Surface';

  @override
  String get colorText => 'Texte';

  @override
  String get colorSecondary => 'Secondaire';

  @override
  String get colorAccent => 'Accent';

  @override
  String get colorSoft => 'Doux';

  @override
  String get colorSuccess => 'Succès';

  @override
  String get colorWarning => 'Avertissement';

  @override
  String get colorDanger => 'Danger';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Titre';

  @override
  String get typeSubtitle => 'Sous-titre';

  @override
  String get typeBody => 'Corps';

  @override
  String get typeSmall => 'Petit';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Envoyer';

  @override
  String get actionSnooze => 'Reporter';

  @override
  String get actionReply => 'Répondre';

  @override
  String get actionDelete => 'Supprimer';

  @override
  String get actionDisabled => 'Désactivé';

  @override
  String get filterUnread => 'Non lus';

  @override
  String get filterAttachments => 'Avec pièces jointes';

  @override
  String get filterPeople => 'Personnes uniquement';

  @override
  String get messageUnread => 'Non lu';

  @override
  String get compose => 'Écrire';

  @override
  String get unifiedInbox => 'Boîte unifiée';

  @override
  String get accounts => 'Comptes';

  @override
  String get addAccount => 'Ajouter un compte';

  @override
  String get inbox => 'Boîte de réception';

  @override
  String downloading(String done, String total) {
    return 'Téléchargement de $done sur $total';
  }

  @override
  String get offline => 'Hors ligne · nouvelle tentative';

  @override
  String get signInFailed =>
      'Un compte a de nouveau besoin de son mot de passe';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts comptes',
      one: '1 compte',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread non lus',
      zero: 'tout est lu',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Choisissez un message pour le lire.';

  @override
  String get noSubject => '(sans objet)';

  @override
  String get couldNotLoadMessage =>
      'Impossible de télécharger ce message. Vérifiez la connexion et réessayez.';

  @override
  String get loading => 'Chargement…';

  @override
  String toYouToday(String time) {
    return 'à vous · aujourd’hui à $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'à vous · hier à $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'à vous · $date à $time';
  }

  @override
  String get sectionToday => 'Aujourd’hui';

  @override
  String get sectionYesterday => 'Hier';

  @override
  String get sectionThisWeek => 'Cette semaine';

  @override
  String get sectionThisMonth => 'Plus tôt ce mois-ci';

  @override
  String get sectionOlder => 'Plus ancien';

  @override
  String get defaultAccountName => 'Mail';

  @override
  String get emailAddress => 'Adresse e-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get show => 'Afficher';

  @override
  String get hide => 'Masquer';

  @override
  String get imapServer => 'Serveur IMAP';

  @override
  String get port => 'Port';

  @override
  String get security => 'Sécurité';

  @override
  String get accountName => 'Nom du compte';

  @override
  String get accountColor => 'Couleur du compte';

  @override
  String get color => 'Couleur';

  @override
  String get connect => 'Se connecter';

  @override
  String get connecting => 'Connexion…';

  @override
  String get notNow => 'Plus tard';

  @override
  String get enterToConnect => 'pour se connecter';

  @override
  String get errorWrongPassword =>
      'Le serveur n’a pas accepté cette adresse et ce mot de passe. Si votre fournisseur utilise des mots de passe d’application, créez-en un et utilisez-le ici.';

  @override
  String get errorUnreachable =>
      'Impossible de joindre le serveur. Vérifiez le nom du serveur, le port et votre connexion.';

  @override
  String get errorInsecure =>
      'Impossible d’établir une connexion sécurisée avec le serveur. Vérifiez le nom du serveur et le réglage de sécurité.';

  @override
  String get errorKeychain =>
      'Impossible d’enregistrer le mot de passe dans le trousseau du système.';

  @override
  String get errorOther =>
      'Un problème est survenu pendant la connexion. Réessayez.';

  @override
  String get yourAccounts => 'Vos comptes';

  @override
  String get noAccountsYet => 'Votre premier compte apparaîtra ici.';

  @override
  String get connected => 'Connecté';

  @override
  String get privacyNote =>
      'Vos e-mails restent sur cet appareil. Nous nous connectons directement à vos serveurs, sans intermédiaire.';

  @override
  String get newMessage => 'Nouveau message';

  @override
  String get close => 'Fermer';

  @override
  String get from => 'De';

  @override
  String get to => 'À';

  @override
  String get cc => 'Cc';

  @override
  String get bcc => 'Cci';

  @override
  String get ccBcc => 'Cc  Cci';

  @override
  String get subject => 'Objet';

  @override
  String get messageBody => 'Message';

  @override
  String get addRecipient => 'Ajouter';

  @override
  String removeRecipient(String name) {
    return 'Retirer $name';
  }

  @override
  String undoSendHint(int seconds) {
    return 'Vous pouvez annuler l’envoi pendant $seconds secondes';
  }

  @override
  String get sendNoRecipients => 'Ajoutez au moins un destinataire.';

  @override
  String sendBadAddress(String address) {
    return '« $address » n’est pas une adresse e-mail.';
  }

  @override
  String get sending => 'Envoi…';

  @override
  String get sent => 'Envoyé';

  @override
  String get undo => 'Annuler';

  @override
  String get draftDiscarded => 'Brouillon supprimé';

  @override
  String get sendErrorPassword =>
      'Le serveur d’envoi n’a pas accepté le mot de passe. Votre message est toujours là.';

  @override
  String get sendErrorUnreachable =>
      'Impossible de joindre le serveur d’envoi. Votre message est toujours là.';

  @override
  String get sendErrorRejected =>
      'Le serveur d’envoi a refusé le message. Votre message est toujours là.';

  @override
  String get sendErrorOther =>
      'Le message n’a pas pu être envoyé. Votre message est toujours là.';

  @override
  String stepOf(int step, int total) {
    return '$step sur $total';
  }

  @override
  String get whatsYourEmail => 'Quelle est votre adresse e-mail ?';

  @override
  String get findSettingsHint =>
      'Nous trouverons les réglages du serveur pour vous.';

  @override
  String get continueAction => 'Continuer';

  @override
  String get lookingUp => 'Recherche…';

  @override
  String get setUpManually => 'Configurer manuellement';

  @override
  String get back => 'Retour';

  @override
  String get weFoundSettings => 'Nous avons trouvé vos réglages';

  @override
  String get incoming => 'Entrant';

  @override
  String get outgoing => 'Sortant';

  @override
  String get incomingAndOutgoing => 'Entrant et sortant';

  @override
  String get guessedSettings =>
      'Ce sont les réglages habituels pour votre domaine. Si la connexion échoue, vérifiez-les.';

  @override
  String get yourName => 'Votre nom';

  @override
  String get yourNameHint =>
      'Visible par les personnes à qui vous écrivez. Facultatif.';

  @override
  String get settingsNotFound =>
      'Nous n’avons pas trouvé les réglages de cette adresse. Les pages d’aide de votre fournisseur les indiquent.';

  @override
  String get smtpServer => 'Serveur SMTP';

  @override
  String get username => 'Nom d’utilisateur';

  @override
  String get usedForBoth => 'Utilisé pour le courrier entrant et sortant.';

  @override
  String get verifyAndConnect => 'Vérifier et se connecter';

  @override
  String get archive => 'Archiver';

  @override
  String get archived => 'Archivé';

  @override
  String get movedToTrash => 'Placé dans la corbeille';

  @override
  String get actionFailed =>
      'Le message n’a pas pu être déplacé. Il est de retour dans la boîte de réception.';

  @override
  String get replyTitle => 'Répondre';

  @override
  String quoteHeader(String date, String name) {
    return 'Le $date, $name a écrit :';
  }

  @override
  String get search => 'Rechercher…';

  @override
  String get searchAllAccounts => 'Rechercher dans tous les comptes';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count résultats',
      one: '1 résultat',
      zero: 'Aucun résultat',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filtres';

  @override
  String get filterLastMonth => 'Le mois dernier';

  @override
  String get filterAccount => 'Compte';

  @override
  String get searchOperators => 'Opérateurs';

  @override
  String get operatorNameHint => 'nom';

  @override
  String get operatorDateHint => 'date';

  @override
  String get searchPeople => 'Personnes';

  @override
  String get searchEmail => 'E-mail';

  @override
  String personEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$_temp0';
  }

  @override
  String get searchNoResults => 'Aucun résultat';

  @override
  String get searchNoResultsHint =>
      'Essayez avec moins de mots ou une autre orthographe.';

  @override
  String get searchNoResultsFilters => 'Aucun résultat avec ces filtres';

  @override
  String get searchNoResultsFiltersHint =>
      'Retirez un filtre ou un opérateur pour élargir la recherche.';

  @override
  String get clearFilters => 'Effacer les filtres';

  @override
  String get searchEmptyHint =>
      'Cherchez dans tous les comptes par mot, expéditeur ou date, même hors ligne.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correspondances',
      one: '1 correspondance',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Ouvrir la conversation';

  @override
  String get noMessageToShow => 'Aucun message à afficher';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts comptes parcourus',
      one: '1 compte parcouru',
    );
    return '$_temp0 · $emails e-mails · $seconds s · index local, fonctionne hors ligne';
  }

  @override
  String get keyMove => 'déplacer';

  @override
  String get keyOpen => 'ouvrir';

  @override
  String get privacyImagesBlocked => 'Images bloquées';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count traqueurs arrêtés',
      one: '1 traqueur arrêté',
    );
    return 'Images bloquées · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Chargement des images…';

  @override
  String get privacyImagesLoaded => 'Images chargées';

  @override
  String get privacyImagesLoadedStopped =>
      'Images chargées · traqueurs toujours arrêtés';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count traqueurs arrêtés',
      one: '1 traqueur arrêté',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count liens nettoyés',
      one: '1 lien nettoyé',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Confidentialité de ce message';

  @override
  String get privacySheetSubtitle =>
      'L’expéditeur ne peut pas savoir si ni quand vous l’avez ouvert.';

  @override
  String get trackerPixel => 'Pixel d’ouverture';

  @override
  String get trackerFont => 'Police distante';

  @override
  String get trackerStyle => 'Style distant';

  @override
  String get trackerLinks => 'Liens traqués';

  @override
  String get trackerStopped => 'Arrêté';

  @override
  String get loadImagesOnce => 'Charger les images une fois';

  @override
  String get imagesAlreadyLoaded => 'Images déjà chargées';

  @override
  String trustSender(String name) {
    return 'Toujours faire confiance à $name';
  }

  @override
  String senderTrusted(String name) {
    return '$name est de confiance';
  }

  @override
  String get alwaysBlockImages => 'Toujours bloquer les images distantes';

  @override
  String get alwaysBlockImagesHint =>
      'S’applique à tous les expéditeurs non approuvés';

  @override
  String get imageNotLoaded => 'Image non chargée';

  @override
  String get suspiciousLinkTitle => 'Vérifiez ce lien';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'Le texte affiche $shown, mais le lien mène à $real.';
  }

  @override
  String get openAnyway => 'Ouvrir quand même';

  @override
  String get dontOpen => 'Ne pas ouvrir';

  @override
  String get riskProgram => 'Un programme qui peut se lancer';

  @override
  String riskDisguised(String kind) {
    return 'Un programme, nommé comme un $kind';
  }

  @override
  String get riskMacros => 'Contient des macros qui peuvent se lancer';

  @override
  String get riskLocked => 'Protégé par mot de passe';

  @override
  String get riskOpenProgram => 'Ouvrir ce programme ?';

  @override
  String get riskOpenFile => 'Ouvrir ce fichier ?';

  @override
  String get riskOpenArchive => 'Ouvrir cette archive ?';

  @override
  String riskBodyProgram(String name) {
    return '$name est un programme. Les programmes reçus par e-mail peuvent prendre le contrôle de votre appareil. Ouvrez-le seulement si vous l’attendiez.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name ressemble à un $kind, mais c’est un programme. Les programmes reçus par e-mail peuvent prendre le contrôle de votre appareil. Ouvrez-le seulement si vous l’attendiez.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name contient des macros, qui peuvent se lancer à l’ouverture. Ouvrez-le seulement si vous l’attendiez.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name est protégé par mot de passe, personne ne peut regarder à l’intérieur. Ouvrez-le seulement si vous l’attendiez.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · de $email';
  }

  @override
  String get settings => 'Réglages';

  @override
  String get backToMail => 'Retour au courrier';

  @override
  String get settingsAccountsTitle => 'Comptes';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count boîtes IMAP, une seule boîte de réception.',
      one: 'Une boîte IMAP.',
    );
    return '$_temp0 La couleur indique d’où vient chaque e-mail.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Ajouter un compte';

  @override
  String get addAccountNote =>
      'IMAP et SMTP. Gmail, iCloud et Fastmail se configurent tout seuls.';

  @override
  String get privacyTitle => 'Confidentialité et sécurité';

  @override
  String get privacySubtitle =>
      'Tout se passe sur cet appareil. Aucune donnée ne quitte votre boîte.';

  @override
  String get blockImagesSetting => 'Bloquer les images distantes';

  @override
  String get blockImagesSettingHint =>
      'Les images ne se chargent que si vous le demandez.';

  @override
  String get stopPixelsSetting => 'Arrêter les pixels de suivi';

  @override
  String get stopPixelsSettingHint =>
      'Les expéditeurs ne peuvent pas savoir si ni quand vous ouvrez un message.';

  @override
  String get cleanLinksSetting => 'Nettoyer les liens';

  @override
  String get cleanLinksSettingHint =>
      'Retire utm et les paramètres de suivi avant l’ouverture.';

  @override
  String get warnLinksSetting => 'Signaler les liens suspects';

  @override
  String get warnLinksSettingHint =>
      'Demande avant d’ouvrir un lien qui affiche une adresse et mène à une autre.';

  @override
  String get last30Days => '30 derniers jours';

  @override
  String get trackersStoppedLabel => 'traqueurs arrêtés';

  @override
  String get linksCleanedLabel => 'liens nettoyés';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious liens suspects signalés',
      one: '1 lien suspect signalé',
    );
    return 'Pixels d’ouverture $pixels · polices et styles distants $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Expéditeurs de confiance';

  @override
  String get trustedSendersHint => 'les images se chargent toujours';

  @override
  String trustedSince(String email, String date) {
    return '$email · depuis le $date';
  }

  @override
  String get removeTrusted => 'Retirer';

  @override
  String get noTrustedSenders =>
      'Aucun expéditeur de confiance. Les images restent bloquées pour tous.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Joindre un fichier';

  @override
  String removeAttachment(String name) {
    return 'Retirer $name';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name enregistré dans Téléchargements';
  }

  @override
  String attachmentNotSaved(String name) {
    return 'Impossible de télécharger $name. Vérifiez la connexion et réessayez.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Les pièces jointes peuvent faire $max au total. Retirez-en et réessayez.';
  }

  @override
  String fileNotRead(String name) {
    return 'Impossible de lire $name.';
  }

  @override
  String get folderSent => 'Envoyés';

  @override
  String get folderArchive => 'Archives';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: 'Un compte',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'à $people · aujourd’hui à $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'à $people · hier à $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'à $people · $date à $time';
  }

  @override
  String get emptyFolder => 'Rien ici pour l’instant.';

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
      other: '$count messages lus',
      one: '1 message lu',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count nouveaux';
  }

  @override
  String get you => 'vous';

  @override
  String get quotedTextHidden => '··· texte cité masqué';

  @override
  String get showQuotedText => 'Afficher le texte cité';

  @override
  String get youName => 'Vous';

  @override
  String yesterdayAt(String time) {
    return 'Hier $time';
  }

  @override
  String get pickMessage => 'Sélectionner';

  @override
  String get unpickMessage => 'Sélectionné';

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String pickedOf(int count, int total) {
    return '$count sur $total sélectionnés';
  }

  @override
  String get deselect => 'Désélectionner';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversations sélectionnées',
      one: 'conversation sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'de $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'de $names et $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'de $names et $count autres';
  }

  @override
  String andMore(String name, int count) {
    return '$name et $count autres';
  }

  @override
  String get markRead => 'Marquer comme lu';

  @override
  String get markUnread => 'Marquer comme non lu';

  @override
  String get hintArchive => 'archiver';

  @override
  String get hintUnread => 'non lu';

  @override
  String get hintDeselect => 'désélectionner';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations archivées',
      one: 'Archivé',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations placées dans la corbeille',
      one: 'Placé dans la corbeille',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'Impossible de joindre le serveur. Lu et non lu sont revenus à leur état précédent.';

  @override
  String get signaturesTitle => 'Signatures';

  @override
  String get newSignature => 'Nouvelle signature';

  @override
  String get newSignatureLabel => 'Nouvelle signature';

  @override
  String get noSignatures =>
      'Aucune signature pour l’instant. Créez-en une avec Nouvelle signature.';

  @override
  String get signatureTemplate => 'Modèle';

  @override
  String get signatureLogo => 'Logo';

  @override
  String get signatureLabelField => 'Nom de la signature';

  @override
  String get signatureAccount => 'Compte';

  @override
  String get signatureName => 'Nom';

  @override
  String get signatureRole => 'Fonction';

  @override
  String get signatureCompany => 'Entreprise';

  @override
  String get signaturePhone => 'Téléphone';

  @override
  String get signatureWebsite => 'Site web';

  @override
  String get signatureAccent => 'Couleur d’accent';

  @override
  String get accentBlue => 'Accent bleu';

  @override
  String get accentBlack => 'Accent noir';

  @override
  String get accentTerracotta => 'Accent terre cuite';

  @override
  String get signatureWhen => 'Quand l’utiliser';

  @override
  String signatureForNew(String email) {
    return 'Nouveaux e-mails de $email';
  }

  @override
  String get signatureForReplies => 'Réponses et transferts';

  @override
  String get signatureNone => 'Aucune';

  @override
  String get deleteSignature => 'Supprimer la signature';

  @override
  String get signatureDeleteHint => 'Les e-mails déjà envoyés la conservent.';

  @override
  String get signaturePreview => 'Aperçu';

  @override
  String get previewLight => 'Clair';

  @override
  String get previewDark => 'Sombre';

  @override
  String get previewText => 'Texte';

  @override
  String get signatureSampleText =>
      'Bonjour Luca,\nvoici les fichiers définitifs en pièce jointe. Dites-moi si vous avez besoin d’autre chose.\n\nÀ bientôt,';

  @override
  String get signatureNote =>
      'Pas d’images : la signature arrive propre même là où les images sont bloquées, et la version texte brut est créée pour vous.';

  @override
  String get signatureNoteLogo =>
      'Le logo voyage dans l’e-mail (40 Ko max.) avec un texte alternatif : il ne demande jamais de « charger les images » et ne suit personne. La version texte brut est créée pour vous.';

  @override
  String get signatureUseAll => 'tout';

  @override
  String get signatureUseNew => 'nouveaux e-mails';

  @override
  String get signatureUseReplies => 'réponses et transferts';

  @override
  String get signatureUseNone => 'non utilisée';

  @override
  String get templateMinimal => 'Minimale';

  @override
  String get templateClassic => 'Classique';

  @override
  String get templateMonogram => 'Monogramme';

  @override
  String get templateLogo => 'Avec logo';

  @override
  String get noLogo => 'PAS DE LOGO';

  @override
  String get logoHint => 'PNG ou JPEG, réduit à 40 Ko automatiquement';

  @override
  String get removeLogo => 'Retirer';

  @override
  String get uploadLogo => 'Importer';

  @override
  String get logoTooBig =>
      'Ce logo dépasse 40 Ko même réduit. Essayez-en un plus simple.';

  @override
  String get logoNotImage => 'Choisissez une image PNG ou JPEG.';

  @override
  String signatureChip(String label) {
    return 'Signature · $label';
  }

  @override
  String get noSignature => 'Sans signature';

  @override
  String get manageSignatures => 'Gérer les signatures…';

  @override
  String get signatureUsedNew => 'Nouveaux e-mails';

  @override
  String get signatureUsedReplies => 'Réponses';

  @override
  String get composeSignatureNote =>
      'La signature suit le compte De : sa signature pour les nouveaux e-mails, la courte pour les réponses et transferts.';

  @override
  String get noticeOpen => 'Ouvrir';

  @override
  String get noticeChannel => 'Nouveau courrier';

  @override
  String noticeTitleMany(String sender, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$sender · $_temp0';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsLead =>
      'Peu nombreuses, et seulement quand elles comptent.';

  @override
  String get notifyAbout => 'Me prévenir pour';

  @override
  String get notifyPeople => 'Personnes uniquement';

  @override
  String get notifyPeopleHint =>
      'Les e-mails écrits par des personnes. Pas de newsletters, de reçus ni de messages automatiques.';

  @override
  String get notifyRecommended => 'Recommandé';

  @override
  String get notifyAll => 'Tout';

  @override
  String get notifyAllHint =>
      'Chaque nouvel e-mail qui arrive dans la boîte de réception.';

  @override
  String get notifyOff => 'Rien';

  @override
  String get notifyOffHint =>
      'Consultez quand vous voulez. Pas de pastilles, pas de sons.';

  @override
  String get quietHours => 'Heures calmes';

  @override
  String get quietTitle => 'Chaque nuit';

  @override
  String get quietHint => 'Les e-mails arrivent toujours, en silence.';

  @override
  String get quietFrom => 'De';

  @override
  String get quietTo => 'à';

  @override
  String quietFromLabel(String time) {
    return 'Les heures calmes commencent à $time';
  }

  @override
  String quietToLabel(String time) {
    return 'Les heures calmes se terminent à $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: '1 compte',
    );
    return 'Rechercher dans $_temp0';
  }

  @override
  String get phoneAccountsAll => 'Tous';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Les $count comptes affichés',
      one: '1 compte affiché',
    );
    return '$_temp0';
  }

  @override
  String get composeMessage => 'Écrire un message';

  @override
  String get moreActions => 'Plus d’actions';

  @override
  String quickReplyHint(String name) {
    return 'Répondre à $name…';
  }

  @override
  String get sendReply => 'Envoyer la réponse';

  @override
  String get cancel => 'Annuler';

  @override
  String get pickAll => 'Tous';

  @override
  String get pickNone => 'Aucun';

  @override
  String get pickRead => 'Lus';

  @override
  String get pickUnread => 'Non lus';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sélectionnés',
      one: 'sélectionné',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'sur $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count sur $total sélectionnés';
  }

  @override
  String get phoneSelectActions => 'Actions sur la sélection';

  @override
  String get clearSearch => 'Effacer la recherche';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get settingsMail => 'Courrier';

  @override
  String get settingsApp => 'Application';

  @override
  String get writingTitle => 'Rédaction';

  @override
  String get readingTitle => 'Lecture';

  @override
  String get readingSubtitle =>
      'L’aspect de la liste, et ce qui vous aide à lire.';

  @override
  String get organizingTitle => 'Organisation';

  @override
  String get organizingSubtitle => 'Espaces, règles, dossiers et libellés.';

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
  String get motto => 'Le courrier, plus léger.';

  @override
  String get appName => 'Piuma Mail';

  @override
  String phoneAccountsMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: '1 compte',
    );
    return '$_temp0, comptes et Réglages';
  }

  @override
  String get allAccounts => 'Tous les comptes';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count boîtes réunies',
      one: '1 boîte',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return '$name uniquement, comptes et Réglages';
  }

  @override
  String accountOnly(String name) {
    return '$name uniquement';
  }

  @override
  String get showAllAccounts => 'Tout afficher';

  @override
  String get phoneFolders => 'Dossiers';

  @override
  String phoneSearchOne(String name) {
    return 'Rechercher dans $name';
  }

  @override
  String get welcomeLead =>
      'Connectez vos comptes IMAP et lisez tout dans une seule boîte, sans le bruit.';

  @override
  String get staysOnDevice => 'Vos e-mails restent sur votre appareil';

  @override
  String get editServers => 'Modifier';

  @override
  String get serverHost => 'Serveur';

  @override
  String get offlineTitle => 'Vous êtes hors ligne';

  @override
  String get offlineDetail =>
      'les e-mails sortants partiront dès que vous serez en ligne';

  @override
  String downloadingAccount(String name) {
    return 'Téléchargement de $name';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done sur $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'Le compte $name ne peut pas se connecter';
  }

  @override
  String passwordChanged(String email) {
    return 'Le mot de passe a-t-il changé ? Les e-mails de $email n’arrivent plus.';
  }

  @override
  String get signInAgain => 'Se reconnecter';

  @override
  String get later => 'Plus tard';

  @override
  String signInTo(String name) {
    return 'Se connecter à $name';
  }

  @override
  String get signIn => 'Se connecter';

  @override
  String get signingIn => 'Connexion…';

  @override
  String get allCaughtUp => 'Tout est à jour';

  @override
  String get allCaughtUpDetail =>
      'Personne ne vous attend. Le reste de la journée est à vous.';

  @override
  String get countOf => 'sur';

  @override
  String get draftSaved => 'Brouillon enregistré';

  @override
  String get draftNotSaved => 'Non enregistré';

  @override
  String get draftNotSavedToast => 'Brouillon non enregistré';

  @override
  String get reopen => 'Rouvrir';

  @override
  String get discard => 'Supprimer';

  @override
  String get noRecipients => 'Aucun destinataire';

  @override
  String get folderDrafts => 'Brouillons';

  @override
  String accountFolders(String name) {
    return 'Dossiers de $name';
  }

  @override
  String get moveShort => 'Déplacer';

  @override
  String get moveTo => 'Déplacer vers…';

  @override
  String moveToIn(String name) {
    return 'Déplacer vers un dossier de $name';
  }

  @override
  String get noFoldersMatch => 'Aucun dossier de ce nom';

  @override
  String noOtherFolders(String name) {
    return '$name n’a pas encore d’autres dossiers';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations déplacées vers $folder',
      one: 'Déplacé vers $folder',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'Boîte d’envoi · $count';
  }

  @override
  String outboxTo(String names) {
    return 'À $names';
  }

  @override
  String get outboxWaiting => 'En attente';

  @override
  String get outboxNotSent => 'Non envoyé';

  @override
  String outboxRefused(String reason) {
    return 'Le serveur l’a refusé : $reason';
  }

  @override
  String get inOutbox =>
      'Dans la boîte d’envoi · part dès que vous êtes en ligne';

  @override
  String get editAction => 'Modifier';

  @override
  String get backgroundTitle => 'Les nouveaux e-mails dès leur arrivée';

  @override
  String get backgroundBody =>
      'Piuma reste connectée à vos comptes, sans serveur intermédiaire. Android vous demandera deux choses : afficher des notifications et laisser Piuma fonctionner en arrière-plan.';

  @override
  String get newMailHeading => 'Nouveaux e-mails';

  @override
  String get deliveryInstant => 'Dès leur arrivée';

  @override
  String get deliveryInstantHint =>
      'Garde une notification silencieuse dans le volet';

  @override
  String get deliveryPeriodic => 'Toutes les 15 minutes';

  @override
  String get deliveryPeriodicHint =>
      'Pas de notification ; Android peut attendre plus longtemps';

  @override
  String get folderNewsletters => 'Newsletters';

  @override
  String newslettersTileLabel(int count) {
    return 'Newsletters, $count non lues';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes min · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes min de lecture · arrivée à $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Arrivée à $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Arrivée le $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes min de lecture · arrivée le $date';
  }

  @override
  String get dayToday => 'aujourd’hui';

  @override
  String get dayYesterday => 'hier';

  @override
  String get readLater => 'Lire plus tard';

  @override
  String get readLaterDone => 'Gardée comme non lue';

  @override
  String get unsubscribe => 'Se désabonner';

  @override
  String unsubscribeTitle(String sender) {
    return 'Se désabonner de $sender ?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender reçoit une seule demande d’arrêt. Rien ne s’ouvre, et ce qui est déjà arrivé reste ici.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'Un message part de votre compte vers $address pour le demander. Ce qui est déjà arrivé reste ici.';
  }

  @override
  String get unsubscribePage =>
      'Leur page de désabonnement s’ouvre dans le navigateur.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender ne propose aucun moyen de se désabonner. Déplacez-la dans la boîte de réception, ou archivez ce qui arrive.';
  }

  @override
  String get unsubscribeConfirm => 'Se désabonner';

  @override
  String get unsubscribeOpen => 'Ouvrir la page';

  @override
  String unsubscribeDone(String sender) {
    return 'Désabonné de $sender';
  }

  @override
  String get unsubscribeFailed =>
      'Désabonnement impossible. Vérifiez la connexion et réessayez.';

  @override
  String get alwaysInInbox => 'Toujours dans la boîte de réception';

  @override
  String alwaysInInboxDone(String sender) {
    return 'Les e-mails de $sender vont désormais dans la boîte de réception';
  }

  @override
  String get newslettersArchiveNote =>
      'Lues il y a plus de 7 jours ? Elles s’archivent toutes seules';

  @override
  String get newslettersEmpty => 'Aucune newsletter';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count à lire',
      one: '1 à lire',
      zero: 'Tout est lu',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes minutes au total';
  }

  @override
  String newslettersNew(int count) {
    return '$count nouvelles';
  }

  @override
  String get folderVault => 'Coffre';

  @override
  String vaultTileLabel(String status) {
    return 'Coffre, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Coffre, $count en attente';
  }

  @override
  String vaultDue(String when) {
    return 'Échéance $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Arrive $when';
  }

  @override
  String get vaultAllClear => 'À jour';

  @override
  String get vaultToday => 'Aujourd’hui';

  @override
  String get vaultTomorrow => 'Demain';

  @override
  String get dayTomorrow => 'demain';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'dans $days jours',
      one: 'demain',
      zero: 'aujourd’hui',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Commandé';

  @override
  String get parcelShipped => 'Expédié';

  @override
  String get parcelTransit => 'En transit';

  @override
  String get parcelDelivered => 'Livré';

  @override
  String vaultDeliveredOn(String day) {
    return 'Livré $day';
  }

  @override
  String vaultCarrierFrom(String carrier, String merchant) {
    return '$carrier · de $merchant';
  }

  @override
  String vaultFrom(String merchant) {
    return 'De $merchant';
  }

  @override
  String vaultLastScan(String place) {
    return 'Dernier scan : $place';
  }

  @override
  String get vaultDueLabel => 'Échéance';

  @override
  String get vaultPaid => 'Payé';

  @override
  String get vaultDownloadPdf => 'Télécharger le PDF';

  @override
  String get vaultMarkPaid => 'Marquer comme payé';

  @override
  String get vaultPaidFailed => 'Impossible d’enregistrer. Réessayez.';

  @override
  String vaultFlight(String number, String date) {
    return 'Vol $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Siège';

  @override
  String get vaultCode => 'Code';

  @override
  String get vaultBoardingPass => 'Carte d’embarquement';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes',
      one: '1 personne',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'confirmé';

  @override
  String get vaultPending => 'à confirmer';

  @override
  String get vaultCancelled => 'annulé';

  @override
  String get vaultDirections => 'Itinéraire';

  @override
  String get vaultNotePhone =>
      'Lu sur l’appareil depuis l’e-mail d’origine · touchez une carte pour l’ouvrir';

  @override
  String get vaultEmpty =>
      'Colis, dépenses, voyages et plus apparaissent ici, lus sur cet appareil depuis leurs e-mails.';

  @override
  String get folderAttachments => 'Pièces jointes';

  @override
  String get attachmentsSubtitle =>
      'Tous les fichiers reçus, sans ouvrir l’e-mail';

  @override
  String get attachmentsAll => 'Tout';

  @override
  String get attachmentsMedia => 'Photos et médias';

  @override
  String get attachmentsDocuments => 'Documents';

  @override
  String get attachmentsSheets => 'Tableurs';

  @override
  String get attachmentsFilter => 'Filtrer par type';

  @override
  String get attachmentsSearch => 'Rechercher des fichiers ou des expéditeurs';

  @override
  String get attachmentsSearchLabel => 'Rechercher dans les pièces jointes';

  @override
  String get attachmentsRecent => 'Récents';

  @override
  String get attachmentsLargest => 'Les plus lourds';

  @override
  String attachmentsSortLabel(String sort) {
    return 'Trier par : $sort';
  }

  @override
  String get attachmentsThisWeek => 'Cette semaine';

  @override
  String get attachmentsEarlier => 'Plus tôt';

  @override
  String attachmentsMeta(String name, String size, String when) {
    return 'De : $name · $size · $when';
  }

  @override
  String get attachmentsDownload => 'Télécharger';

  @override
  String get attachmentsOpenEmail => 'Ouvrir l’e-mail';

  @override
  String get attachmentsEmail => 'E-mail';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, de $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return 'Télécharger $name';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'Ouvrir l’e-mail de $from';
  }

  @override
  String get attachmentsNoneNew => 'Rien de nouveau';

  @override
  String attachmentsTileLabel(String status) {
    return 'Pièces jointes, $status';
  }

  @override
  String get attachmentsEmpty =>
      'Les fichiers que vous recevez apparaissent ici, de tous les comptes.';

  @override
  String attachmentsNoMatch(String query) {
    return 'Aucun fichier ne correspond à « $query »';
  }

  @override
  String attachmentsNew(int count) {
    return '$count nouveaux';
  }

  @override
  String get folderSnoozed => 'Reportés';

  @override
  String get snoozeUntilTitle => 'Reporter jusqu’à…';

  @override
  String get snoozeEvening => 'Ce soir';

  @override
  String get snoozeMorning => 'Demain matin';

  @override
  String get snoozeWeekend => 'Ce week-end';

  @override
  String get snoozeNextWeek => 'La semaine prochaine';

  @override
  String snoozeTileToday(String time) {
    return 'aujourd’hui $time';
  }

  @override
  String snoozeToday(String time) {
    return 'aujourd’hui, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'demain, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'demain $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations reportées jusqu’à $when',
      one: 'Reporté jusqu’à $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Remettre dans la boîte';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations de retour dans la boîte',
      one: 'De retour dans la boîte',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Demain';

  @override
  String get sectionLater => 'Plus tard';

  @override
  String get sendLater => 'Envoyer plus tard';

  @override
  String get sendLaterTomorrowMorning => 'Demain matin';

  @override
  String get sendLaterTomorrowAfternoon => 'Demain après-midi';

  @override
  String get sendLaterMondayMorning => 'Lundi matin';

  @override
  String scheduleTomorrow(String time) {
    return 'Programmer pour demain à $time';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Programmer pour $day à $time';
  }

  @override
  String get sendLaterNote =>
      'Envoyé depuis cet appareil à cette heure-là. S’il est éteint, l’envoi part dès qu’il se rallume.';

  @override
  String scheduledToast(String when) {
    return 'Programmé pour $when';
  }

  @override
  String get paletteLabel => 'Palette de commandes';

  @override
  String get paletteHint => 'Rechercher ou lancer une commande';

  @override
  String get paletteActions => 'Actions';

  @override
  String get paletteMessages => 'Messages';

  @override
  String paletteWriteTo(String name) {
    return 'Écrire à $name';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Afficher seulement les messages de $name';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Pièces jointes de $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Rechercher « $query » dans tout le courrier';
  }

  @override
  String paletteGoTo(String place) {
    return 'Aller à $place';
  }

  @override
  String get paletteMove => 'déplacer';

  @override
  String get paletteRun => 'lancer';

  @override
  String get paletteAnywhere => 'depuis n’importe quel écran';

  @override
  String senderCardLabel(String name) {
    return 'Fiche de $name';
  }

  @override
  String get senderKind => 'Expéditeur';

  @override
  String get senderClose => 'Fermer la fiche';

  @override
  String get senderWrite => 'Écrire';

  @override
  String get senderAll => 'Tous les e-mails';

  @override
  String get senderMute => 'Couper';

  @override
  String get senderMuted => 'Coupé';

  @override
  String senderArrivesIn(String account) {
    return 'Arrive dans $account';
  }

  @override
  String get senderConversations => 'Conversations';

  @override
  String get senderNoMail =>
      'Aucun e-mail de cette personne sur cet appareil pour l’instant.';

  @override
  String senderMutedToast(String name) {
    return 'Plus de notifications de $name';
  }

  @override
  String get rulesTitle => 'Règles et dossiers';

  @override
  String get rulesSubtitle =>
      'Trie votre courrier comme vous le feriez. Chaque règle se lit comme une phrase.';

  @override
  String get rulesWhere =>
      'Les règles s’exécutent sur cet appareil, sur les nouveaux e-mails de la boîte de réception';

  @override
  String get rulesHeading => 'Règles';

  @override
  String get rulesNew => 'Nouvelle règle';

  @override
  String get rulesEdit => 'Modifier la règle';

  @override
  String get rulesNone =>
      'Pas encore de règles à vous. Une règle trie les nouveaux e-mails dès leur arrivée, comme vous le feriez.';

  @override
  String get ruleWhen => 'Quand';

  @override
  String get ruleThen => 'alors';

  @override
  String get ruleFieldSender => 'l’expéditeur';

  @override
  String get ruleFieldSubject => 'l’objet';

  @override
  String get ruleFieldRecipient => 'le destinataire';

  @override
  String get ruleOpContains => 'contient';

  @override
  String get ruleOpIs => 'est';

  @override
  String get ruleOpStarts => 'commence par';

  @override
  String get ruleOpNotContains => 'ne contient pas';

  @override
  String get ruleDoMove => 'déplacer vers';

  @override
  String get ruleDoArchive => 'archiver';

  @override
  String get ruleDoRead => 'marquer comme lu';

  @override
  String get ruleText => 'Texte à chercher';

  @override
  String get ruleTextHint => 'texte';

  @override
  String get ruleTrayField => 'Champ';

  @override
  String get ruleTrayOp => 'Condition';

  @override
  String get ruleTrayAction => 'Action';

  @override
  String get ruleTrayFolder => 'Dossier';

  @override
  String get rulePickFolder => 'un dossier';

  @override
  String get ruleNoFolders => 'Vos comptes n’ont pas encore de dossiers à eux.';

  @override
  String get ruleApplyToo => 'Appliquer aussi à ceux-ci';

  @override
  String get ruleSave => 'Enregistrer la règle';

  @override
  String get ruleDelete => 'Supprimer la règle';

  @override
  String get rulePaused => 'En pause';

  @override
  String get ruleFresh => 'Active dès maintenant';

  @override
  String get foldersHeading => 'Dossiers';

  @override
  String get foldersNone => 'Aucun dossier à lui';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'S’applique à $count e-mails existants',
      one: 'S’applique à $count e-mail existant',
      zero: 'Aucun e-mail existant ne correspond',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails triés',
      one: '1 e-mail trié',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'dernier aujourd’hui $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'dernier le $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Règle active : $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Aucune',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Invitation';

  @override
  String get inviteYes => 'Oui';

  @override
  String get inviteMaybe => 'Peut-être';

  @override
  String get inviteNo => 'Non';

  @override
  String get inviteRespond => 'Répondre à l’invitation';

  @override
  String get inviteAllDay => 'Toute la journée';

  @override
  String get inviteRepeats => 'se répète';

  @override
  String get inviteYouAccepted => 'Vous avez accepté';

  @override
  String get inviteYouTentative => 'Vous avez répondu peut-être';

  @override
  String get inviteYouDeclined => 'Vous avez refusé';

  @override
  String get inviteNotSent =>
      'Votre réponse n’a pas pu être envoyée. Réessayez.';

  @override
  String get inviteCancelled => 'Cet événement a été annulé';

  @override
  String get inviteYours => 'Vous avez envoyé cette invitation';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count participants',
      one: '1 participant',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name recevra votre réponse';
  }

  @override
  String inviteQueued(String name) {
    return 'part à $name dès que vous êtes en ligne';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name a accepté';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name a répondu peut-être';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name a refusé';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Accepté : $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Peut-être : $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Refusé : $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name a accepté cette invitation.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name viendra peut-être.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name a refusé cette invitation.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Invitation : $summary, $when';
  }

  @override
  String get inviteFree => 'Libre · aucun conflit';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Chevauche $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Disponibilité : $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'ajouté à $name';
  }

  @override
  String get settingsCalendars => 'Calendriers';

  @override
  String get calIntro =>
      'Piuma n’a pas de calendrier à elle : connectez ceux que vous utilisez déjà. Les événements y restent.';

  @override
  String get calConnected => 'Calendriers connectés';

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
      other: '$count calendriers',
      one: '1 calendrier',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Connecter un calendrier';

  @override
  String get calChoose => 'Choisissez d’où vous connecter';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Serveur, e-mail et mot de passe d’application';

  @override
  String get calIcs => 'S’abonner à une URL .ics';

  @override
  String get calIcsSub => 'Lecture seule, se met à jour tout seul';

  @override
  String get calCalDavLabel => 'Adresse e-mail ou serveur CalDAV';

  @override
  String get calCalDavHint =>
      'iCloud demande un mot de passe d’application ; il reste chiffré dans le trousseau du système.';

  @override
  String get calIcsLabel => 'URL du calendrier .ics';

  @override
  String get calIcsHint =>
      'Les calendriers .ics sont en lecture seule : pratiques pour les jours fériés, le sport, les plannings.';

  @override
  String get calUsername => 'Nom d’utilisateur (si ce n’est pas l’e-mail)';

  @override
  String get calPassword => 'Mot de passe';

  @override
  String get calConnectButton => 'Connecter';

  @override
  String get calSubscribe => 'S’abonner';

  @override
  String get calSuggested =>
      'Les comptes e-mail ajoutés qui proposent un calendrier sont suggérés automatiquement';

  @override
  String get calHasCalendar => 'a aussi un calendrier';

  @override
  String get calDone => 'Connecté';

  @override
  String get calDisconnect => 'Déconnecter';

  @override
  String calDisconnectLabel(String name) {
    return 'Déconnecter $name';
  }

  @override
  String get calReadOnly => 'lecture seule';

  @override
  String get calInvitesTag => 'invitations';

  @override
  String get calShowAvailability => 'Afficher la disponibilité';

  @override
  String get calAvailabilityShort => 'disponibilité';

  @override
  String calAvailabilityFor(String name) {
    return 'Afficher la disponibilité pour $name';
  }

  @override
  String get calNone =>
      'Aucun calendrier connecté. Les invitations fonctionnent toujours, par e-mail.';

  @override
  String get calWhenInvite => 'Quand une invitation arrive';

  @override
  String get calAddTo => 'Ajouter à';

  @override
  String get calAddToSub => 'Où vont les invitations que vous acceptez';

  @override
  String get calAddInvitesTo => 'Ajouter les invitations à';

  @override
  String get calNoWritable => 'Aucun';

  @override
  String get calConflicts =>
      'Vérifier les conflits dans tous les calendriers connectés';

  @override
  String get calConflictsSub =>
      'Les invitations indiquent tout de suite si vous êtes déjà pris à ce moment-là.';

  @override
  String get calFooter =>
      'Sans calendrier connecté, vous pouvez toujours répondre aux invitations par e-mail et ouvrir le fichier .ics.';

  @override
  String get calStaysHere =>
      'Les connexions restent sur cet appareil ; les mots de passe sont gardés dans le trousseau du système.';

  @override
  String get calWrongPassword => 'Nom d’utilisateur ou mot de passe incorrect.';

  @override
  String get calUnreachable =>
      'Aucun calendrier trouvé à cet endroit. Vérifiez l’adresse.';

  @override
  String get calFailed => 'Connexion impossible. Réessayez.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => 'URL .ics, lecture seule';

  @override
  String get calFromAccount => 'depuis le compte e-mail';

  @override
  String foundDateAdd(String when) {
    return 'Ajouter $when au calendrier';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Ajouté à $calendar';
  }

  @override
  String foundDateAddLabel(String when) {
    return 'Ajouter $when au calendrier, trouvé sur cet appareil';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when ajouté à $calendar';
  }

  @override
  String get foundOnDevice => 'Trouvé sur cet appareil';

  @override
  String get foundDateNotAdded =>
      'Impossible de l’ajouter au calendrier. Réessayez dans un instant.';

  @override
  String get calFindDates =>
      'Proposer d’ajouter les dates trouvées dans les e-mails';

  @override
  String get calFindDatesSub =>
      'Une petite suggestion à côté de la phrase, jamais automatique.';

  @override
  String get calOnDevice => 'sur l’appareil';

  @override
  String get inShort => 'En bref';

  @override
  String get generatedOnDevice => 'Généré sur l’appareil';

  @override
  String get yourTurn => 'À vous :';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name écrit « $words »';
  }

  @override
  String get inShortColon => 'En bref :';

  @override
  String get onDevice => 'sur l’appareil';

  @override
  String senderBriefTopic(String topic) {
    return 'surtout à propos de « $topic »';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails ce mois-ci',
      one: '1 e-mail ce mois-ci',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'le dernier attend votre réponse';

  @override
  String get searchByType => 'Rechercher par type';

  @override
  String get frequentContacts => 'Contacts fréquents';

  @override
  String get recentSearches => 'Recherches récentes';

  @override
  String get clearRecent => 'Effacer';

  @override
  String get clearRecentSearches => 'Effacer les recherches récentes';

  @override
  String get noRecentSearches => 'Aucune recherche récente.';

  @override
  String get searchOperatorsHint => 'Vous pouvez aussi taper des opérateurs';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$formatted e-mails indexés sur cet appareil · fonctionne hors ligne',
      one: '1 e-mail indexé sur cet appareil · fonctionne hors ligne',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'Avec pièces jointes';

  @override
  String get searchFromPeople => 'De personnes';

  @override
  String searchMailFrom(String name) {
    return 'Rechercher les e-mails de $name';
  }

  @override
  String removeRecentSearch(String query) {
    return 'Retirer $query';
  }

  @override
  String get searchAddWords => 'Ajouter des mots…';

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
      other: '$count pièces jointes',
      one: '1 pièce jointe',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Bloquer';

  @override
  String get senderBlocked => 'Bloqué';

  @override
  String showSnoozed(int count) {
    return 'Afficher les reportés ($count)';
  }

  @override
  String get hideSnoozed => 'Masquer les reportés';

  @override
  String get snoozeNoReply => 'Si personne ne répond';

  @override
  String get snoozeNoReplyHint => 'Revient dans 3 jours sans réponse';

  @override
  String get previewClose => 'Fermer l’aperçu';

  @override
  String previewMeta(String size, String name) {
    return '$size · de $name';
  }

  @override
  String previewPage(int page, int count) {
    return 'Page $page sur $count';
  }

  @override
  String get previewPrevPage => 'Page précédente';

  @override
  String get previewNextPage => 'Page suivante';

  @override
  String previewOpenEmail(String name) {
    return 'Ouvrir l’e-mail de $name';
  }

  @override
  String get previewDownloadAll => 'Tout télécharger';

  @override
  String previewPhoto(int index, int count) {
    return 'Photo $index sur $count · du même e-mail';
  }

  @override
  String get previewPhotos => 'Photos de l’e-mail';

  @override
  String get previewCantShow =>
      'Ce fichier ne peut pas être affiché ici. Vous pouvez quand même le télécharger.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Page $page de $name';
  }

  @override
  String get vaultParcelsTitle => 'Livraisons de colis';

  @override
  String get vaultParcelsHint => 'Le jour de la livraison, une seule fois.';

  @override
  String get vaultDueTitle => 'Échéances';

  @override
  String get vaultDueHint => 'Factures et renouvellements, trois jours avant.';

  @override
  String get vaultNoticeParcel => 'Votre colis arrive aujourd’hui';

  @override
  String get vaultNoticeDueToday => 'Échéance aujourd’hui';

  @override
  String get vaultNoticeDueTomorrow => 'Échéance demain';

  @override
  String vaultNoticeDueIn(int days) {
    return 'Échéance dans $days jours';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'vers $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails certifiés',
      one: '1 e-mail certifié',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count non remis',
      one: '$count non remis',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Envoyé';

  @override
  String get pecAccepted => 'Accepté';

  @override
  String get pecDelivered => 'Remis';

  @override
  String get pecFailed => 'Non remis';

  @override
  String pecTo(String who) {
    return 'À $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'À $count destinataires · $delivered sur $count remis';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Accepté $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Remis $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'Non remis · $when';
  }

  @override
  String pecReasonAt(String reason, String when) {
    return '$reason · $when';
  }

  @override
  String get pecOpen => 'Ouvrir';

  @override
  String pecReceipt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Accusés',
      one: 'Accusé',
    );
    return '$_temp0';
  }

  @override
  String pecSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accusés enregistrés dans Téléchargements',
      one: 'Accusé enregistré dans Téléchargements',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'Impossible d’enregistrer l’accusé';

  @override
  String get pecNote =>
      'Les accusés restent hors de la boîte de réception et se regroupent sur le message auquel ils appartiennent. Accusé enregistre la preuve signée dans un fichier.';

  @override
  String get pickDateTime => 'Choisir la date et l’heure';

  @override
  String get previousMonth => 'Mois précédent';

  @override
  String get nextMonth => 'Mois suivant';

  @override
  String get pickTime => 'Heure';

  @override
  String get pickOtherTime => 'Autre heure';

  @override
  String get pickTimeGone => 'Cette heure est déjà passée';

  @override
  String snoozeUntilAt(String when) {
    return 'Reporter jusqu’à $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Programmer pour $when';
  }

  @override
  String get senderNewsletterKind => 'Newsletter';

  @override
  String newsletterPerWeek(int count) {
    return 'environ $count par semaine';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'environ $count par mois';
  }

  @override
  String newsletterOpened(int percent) {
    return 'vous en ouvrez $percent %';
  }

  @override
  String get newsletterUnsubscribed => 'Désabonné';

  @override
  String get newsletterClearAsk => 'effacer aussi les anciens e-mails ?';

  @override
  String get newsletterClearYes => 'Oui, effacer';

  @override
  String get newsletterClearNo => 'Non';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Désabonné · $count e-mails placés dans la corbeille',
      one: 'Désabonné · 1 e-mail placé dans la corbeille',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept =>
      'Désabonné · les anciens e-mails restent tels quels';

  @override
  String get newsletterPageOpened =>
      'Leur page de désabonnement est ouverte dans le navigateur';

  @override
  String get moveToNewsletters => 'Déplacer vers Newsletters';

  @override
  String get movedToNewsletters => 'Déplacé vers Newsletters';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Avec pièce jointe';

  @override
  String get appearanceTitle => 'Apparence';

  @override
  String get appearanceSubtitle =>
      'L’allure que vous voulez pour votre courrier.';

  @override
  String get appearanceTheme => 'Thème';

  @override
  String get themeAutomatic => 'Automatique';

  @override
  String get appearanceDensity => 'Densité';

  @override
  String get densityComfortable => 'Confortable';

  @override
  String get densityCompact => 'Compacte';

  @override
  String get appearancePreview => 'Aperçu';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes',
      one: '1 ligne',
    );
    return '$_temp0';
  }

  @override
  String get appearanceExample => 'Exemple';

  @override
  String get previewDrawnHere => 'Affiché sur cet appareil';

  @override
  String get previewKeysPages => '← → pages';

  @override
  String get previewKeysPhotos => '← → photos';

  @override
  String get meInitials => 'MOI';

  @override
  String get threadSummary => 'Résumé';

  @override
  String get signatureSheetTitle => 'Signature';

  @override
  String get signatureManage => 'Gérer';

  @override
  String get signatureSheetNote =>
      'La signature change automatiquement quand vous changez le compte « De ».';

  @override
  String get readerEmptyTitle => 'Aucune conversation sélectionnée';

  @override
  String readerEmptyHint(String keys) {
    return 'Cliquez sur un message pour le sélectionner, ou appuyez sur $keys pour tous les sélectionner.';
  }

  @override
  String get hintMove => 'déplacer';

  @override
  String get accountConnected => 'Compte connecté';

  @override
  String get accountConnectedLead =>
      'Vous pouvez commencer à lire : le reste arrive pendant que vous utilisez Piuma.';

  @override
  String get connectedDownloading =>
      'Téléchargement, les plus récents d’abord…';

  @override
  String get connectedUpToDate => 'À jour';

  @override
  String get goToInbox => 'Aller à la boîte de réception';

  @override
  String get addAnotherAccount => 'Ajouter un autre compte';

  @override
  String filterFrom(String name) {
    return 'De : $name';
  }

  @override
  String get syncLeftUnderMinute => 'moins d’une minute';

  @override
  String syncLeftMinutes(int n) {
    return 'environ $n min';
  }

  @override
  String syncLeftHours(int n) {
    return 'environ $n h';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · synchronisation de $name';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Envoyer demain $time';
  }

  @override
  String get sendOptions => 'Options d’envoi';

  @override
  String get inboxSections => 'Sections de la boîte';

  @override
  String get tabPeople => 'Personnes';

  @override
  String get tabNotifications => 'Notifications';

  @override
  String get zoneNothingNew => 'Rien de nouveau';

  @override
  String get tabAll => 'Tous';

  @override
  String get filterUnreadHint => 'Seulement les e-mails avec du non lu';

  @override
  String get moveToPeople => 'Déplacer vers Personnes';

  @override
  String movedToPeople(String sender) {
    return '$sender ira dans Personnes désormais';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender ira dans Notifications désormais';
  }

  @override
  String get moveToNotifications => 'Déplacer vers Notifications';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count non lus';
  }

  @override
  String get templatesTitle => 'Modèles';

  @override
  String get templatesSearch => 'Rechercher des modèles';

  @override
  String templatesFound(int found, int total) {
    return '$found sur $total';
  }

  @override
  String get templatesNone =>
      'Aucun modèle pour l’instant. Enregistrez ce que vous écrivez comme modèle.';

  @override
  String templatesNoMatch(String query) {
    return 'Aucun modèle nommé « $query »';
  }

  @override
  String get templateSaveThis => 'Enregistrer comme modèle';

  @override
  String get templatesManage => 'Gérer';

  @override
  String get templateUntitled => 'Modèle sans titre';

  @override
  String templateSavedNote(String name) {
    return 'Enregistré comme modèle « $name »';
  }

  @override
  String get templatesSubtitle => 'Sur cet appareil, pour tous les comptes';

  @override
  String get templatesNew => 'Nouveau modèle';

  @override
  String get templateNameLabel => 'Nom';

  @override
  String get templateTextLabel => 'Texte';

  @override
  String templateSubjectLine(String subject) {
    return 'Objet : $subject';
  }

  @override
  String get templateNoSubject => 'Sans objet';

  @override
  String get templateSavedAsYouType => 'Enregistré au fil de la saisie';

  @override
  String get templateNotSaved => 'Le modèle n’a pas pu être enregistré';

  @override
  String get accountNameLabel => 'Nom';

  @override
  String get accountDisplayName => 'Nom affiché';

  @override
  String get accountDisplayNameNone => 'Non défini';

  @override
  String get accountDefaultSignature => 'Signature par défaut';

  @override
  String get accountConnection => 'Connexion';

  @override
  String accountWorkingAgo(String ago) {
    return 'Fonctionne · vérifié $ago';
  }

  @override
  String get accountJustNow => 'à l’instant';

  @override
  String accountMinutesAgo(int count) {
    return 'il y a $count min';
  }

  @override
  String accountAtTime(String time) {
    return 'à $time';
  }

  @override
  String get accountConnecting => 'Connexion…';

  @override
  String accountCantSignInSince(String time) {
    return 'Connexion impossible depuis $time';
  }

  @override
  String get accountPasswordRefused =>
      'Le serveur a refusé le mot de passe. A-t-il changé ?';

  @override
  String get accountEditServers => 'Modifier les serveurs';

  @override
  String get accountSignInAlert => 'Me prévenir quand la connexion échoue';

  @override
  String get accountSignInAlertNote =>
      'Une seule notification, la première fois que le mot de passe est refusé';

  @override
  String get accountRemove => 'Retirer le compte';

  @override
  String accountRemoveTitle(String name) {
    return 'Retirer $name de cet appareil ?';
  }

  @override
  String get accountRemoveNote =>
      'Ses e-mails sont supprimés ici. Sur le serveur, tout reste tel quel.';

  @override
  String get accountRemoveConfirm => 'Retirer';

  @override
  String get accountServersTitle => 'Serveurs';

  @override
  String get accountServersSave => 'Enregistrer';

  @override
  String get accountServersChecking => 'Vérification…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name ne peut pas se connecter';
  }

  @override
  String get orStartFrom => 'Ou commencez par';

  @override
  String needsAppPassword(String provider) {
    return '$provider demande un mot de passe d’application';
  }

  @override
  String get fastmailNeedsToken => 'Fastmail demande un jeton d’API';

  @override
  String get gmailStep1 =>
      'Activez la validation en deux étapes dans votre compte Google.';

  @override
  String get gmailStep2 =>
      'Ouvrez Mots de passe des applications et créez-en un nommé « Piuma ».';

  @override
  String get gmailStep3 => 'Collez les 16 lettres ici.';

  @override
  String get openAppPasswords => 'Ouvrir Mots de passe des applications';

  @override
  String get icloudStep1 =>
      'Activez l’identification à deux facteurs pour votre compte Apple.';

  @override
  String get icloudStep2 =>
      'Dans Connexion et sécurité, ouvrez Mots de passe pour app et créez-en un nommé « Piuma ».';

  @override
  String get icloudStep3 => 'Collez-le ici.';

  @override
  String get openAppleAccount => 'Ouvrir le compte Apple';

  @override
  String get fastmailStep1 =>
      'Dans Settings, ouvrez Privacy & Security, puis Manage API tokens.';

  @override
  String get fastmailStep2 =>
      'Créez un jeton nommé « Piuma » avec accès à Email et Email submission.';

  @override
  String get fastmailStep3 => 'Collez-le ici.';

  @override
  String get openApiTokens => 'Ouvrir les jetons d’API';

  @override
  String get appPassword => 'Mot de passe d’application';

  @override
  String get apiToken => 'Jeton d’API';

  @override
  String get pecWhichProvider => 'Qui gère votre PEC ?';

  @override
  String get pecWhichProviderHint =>
      'Le courrier certifié utilise les serveurs de son fournisseur.';

  @override
  String signInToPec(String provider) {
    return 'Se connecter à $provider';
  }

  @override
  String get pecStep1 => 'Utilisez l’adresse PEC complète.';

  @override
  String get pecStep2 =>
      'Utilisez le mot de passe de la boîte, celui du webmail.';

  @override
  String get verifiedSenderSetting => 'Afficher l’expéditeur vérifié';

  @override
  String get verifiedSenderSettingHint =>
      'Signale les expéditeurs que votre serveur a vérifiés avec DKIM, SPF et DMARC.';

  @override
  String get verifiedBadge => 'Vérifié';

  @override
  String get verifiedSenderLabel => 'Expéditeur vérifié';

  @override
  String get ruleFieldBody => 'le corps';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get newFolderName => 'Nom du nouveau dossier';

  @override
  String get create => 'Créer';

  @override
  String get newFolderFailed =>
      'Le serveur n’a pas créé le dossier. Essayez un autre nom.';

  @override
  String get groupsTitle => 'Groupes';

  @override
  String get groupsSubtitle =>
      'Réunissez des adresses de comptes et de domaines différents. Chaque groupe a sa couleur, sa signature et, si vous le souhaitez, sa propre boîte de réception.';

  @override
  String get groupsNone =>
      'Aucun groupe pour l’instant. Un groupe réunit des adresses, même de comptes différents, sous une couleur et une signature.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Aucun',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count adresses',
      one: '1 adresse',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Signature';

  @override
  String get groupSendFromShort => 'Envoyer depuis';

  @override
  String get groupNoSignature => 'Aucune';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get groupColor => 'Couleur du groupe';

  @override
  String get groupAddressesHeading => 'Adresses';

  @override
  String get groupAccount => 'Compte';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return 'Compte $name';
  }

  @override
  String groupAliasNote(String email) {
    return 'sur $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return 'Retirer $email du groupe';
  }

  @override
  String get groupAddAddress => 'Ajouter une adresse';

  @override
  String get groupDefaultSignature => 'Signature par défaut';

  @override
  String get groupSendFrom => 'Envoyer les nouveaux e-mails depuis';

  @override
  String get groupSeparateInbox => 'Boîte séparée';

  @override
  String get groupSeparateOn =>
      'A sa propre entrée dans la barre latérale. Reste aussi dans la boîte unifiée.';

  @override
  String get groupSeparateOff =>
      'Ses e-mails sont seulement dans la boîte unifiée.';

  @override
  String get groupNotifyOn => 'Suit vos règles de notifications.';

  @override
  String get groupNotifyOff => 'Aucune alerte pour ce groupe.';

  @override
  String get groupReplyAsWritten =>
      'Toujours répondre depuis l’adresse à laquelle on a écrit';

  @override
  String groupReplyOn(String email) {
    return 'Si quelqu’un écrit à $email, votre réponse part de $email, avec la signature de ce groupe.';
  }

  @override
  String get groupReplyOnAny =>
      'Si quelqu’un écrit à l’un de vos alias, votre réponse part de cet alias, avec la signature de son groupe.';

  @override
  String get groupReplyOff =>
      'Les réponses partent de l’adresse par défaut du groupe.';

  @override
  String get groupNew => 'Nouveau groupe';

  @override
  String get groupNewName => 'Nouveau groupe';

  @override
  String get groupDelete => 'Supprimer le groupe';

  @override
  String groupDeleteAsk(String name) {
    return 'Supprimer $name ?';
  }

  @override
  String get groupDeleteNote =>
      'Ses adresses restent sur leurs comptes ; seul le groupe disparaît.';

  @override
  String get groupYourAddresses => 'Vos adresses';

  @override
  String get groupMovesHere => 'Dans un autre groupe : passe ici';

  @override
  String get groupFoundInSent => 'Trouvée dans vos e-mails envoyés';

  @override
  String get groupNewAlias => 'Nouvel alias';

  @override
  String get groupNewAliasHint => 'nom@domaine.com';

  @override
  String get groupAliasOn => 'sur';

  @override
  String get groupAddAlias => 'Ajouter';

  @override
  String get groupAliasInvalid => 'Cela ne ressemble pas à une adresse e-mail.';

  @override
  String get fromAutomatic => 'Automatique';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Choisie parce que $name a écrit à $email';
  }

  @override
  String rowWrittenTo(String email) {
    return 'à $email';
  }

  @override
  String get groupsAll => 'Tous les groupes';

  @override
  String groupExpand(String name) {
    return 'Déplier $name';
  }

  @override
  String groupCollapse(String name) {
    return 'Replier $name';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses adresses',
      one: '1 adresse',
    );
    return '$_temp0 · $unread non lus';
  }

  @override
  String groupsAllLine(int groups, int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groupes',
      one: '1 groupe',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses adresses',
      one: '1 adresse',
    );
    return '$_temp0 · $_temp1 · $unread non lus';
  }

  @override
  String groupOnly(String email) {
    return 'Seulement $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Seulement $email. Afficher tout le groupe';
  }

  @override
  String get groupSheetTitle => 'Afficher';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses adresses',
      one: '1 adresse',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups groupes',
      one: '1 groupe',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get groupSheetLabel => 'Choisir le groupe';

  @override
  String get groupManage => 'Gérer les groupes';

  @override
  String get groupTitleAll => 'Groupe : tous. Changer de groupe';

  @override
  String groupTitleOne(String name) {
    return 'Groupe : $name. Changer de groupe';
  }

  @override
  String get syncTitle => 'Appareils et synchronisation';

  @override
  String get syncSubtitle =>
      'Vos réglages sur tous vos appareils, chiffrés de bout en bout';

  @override
  String get syncOff => 'Désactivée · cet appareil seulement';

  @override
  String get syncOffBody =>
      'Retrouvez vos comptes, groupes, signatures et réglages sur tous vos appareils. Ils sont chiffrés ici et stockés dans un dossier caché de l’une de vos boîtes. Aucun serveur.';

  @override
  String get syncOffNote =>
      'Les mots de passe ne voyagent que dans la copie chiffrée.';

  @override
  String get syncStoreIn => 'La stocker dans';

  @override
  String get syncMailbox => 'Boîte de synchronisation';

  @override
  String get syncMoving => 'Déplacement…';

  @override
  String get syncFailTaken =>
      'Cette boîte contient déjà un autre espace de synchronisation.';

  @override
  String get syncTurnOn => 'Activer la synchronisation';

  @override
  String get syncAllSynced => 'Tout est synchronisé';

  @override
  String get syncNotYet => 'Pas encore synchronisé';

  @override
  String syncOnBody(String name) {
    return 'Comptes, groupes, signatures et réglages sont chiffrés et stockés dans votre boîte $name. Aucun serveur.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · dossier caché · chiffré de bout en bout';
  }

  @override
  String get syncDevices => 'Appareils associés';

  @override
  String get syncThisDevice => 'Cet appareil';

  @override
  String get syncActiveNow => 'Actif maintenant';

  @override
  String syncActive(String ago) {
    return 'Actif $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'hier';

  @override
  String syncDaysAgo(int count) {
    return 'il y a $count jours';
  }

  @override
  String get syncUnlink => 'Dissocier';

  @override
  String syncUnlinkName(String name) {
    return 'Dissocier $name';
  }

  @override
  String syncUnlinkAsk(String name) {
    return 'Dissocier $name ?';
  }

  @override
  String get syncUnlinkNote =>
      'Il garde ce qu’il a maintenant mais ne recevra plus de modifications. Votre phrase de récupération change aussi : vous noterez la nouvelle.';

  @override
  String get syncLinkNew => 'Associer un nouvel appareil';

  @override
  String syncLinkBody(String email) {
    return 'Sur le nouvel appareil, ouvrez Piuma, choisissez « J’utilise déjà Piuma sur un autre appareil » et connectez-vous à $email. Il affiche 6 chiffres, que cet appareil vous demandera.';
  }

  @override
  String get syncLinkWaiting => 'En attente du nouvel appareil…';

  @override
  String get syncLinkScan =>
      'Sur le nouveau téléphone, ouvrez Piuma, choisissez « J’utilise déjà Piuma sur un autre appareil » et scannez ce code.';

  @override
  String get syncLinkQrLabel => 'Code QR pour associer un nouvel appareil';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · nouveau code dans $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return 'Pas de caméra ? Connectez-vous à $email sur le nouvel appareil : il affiche 6 chiffres, que cet appareil vous demandera.';
  }

  @override
  String syncLinked(String name) {
    return '$name associé';
  }

  @override
  String get syncPhraseRow => 'Phrase de récupération';

  @override
  String get syncPhraseRowLine =>
      'Ouvre votre espace si tous les appareils sont perdus';

  @override
  String get syncShow => 'Afficher';

  @override
  String get syncPhraseTitle => 'Votre phrase de récupération';

  @override
  String get syncPhraseBody =>
      'Si vous perdez tous vos appareils, ces 24 mots sont le seul moyen de retrouver votre espace. Écrivez-les sur papier et gardez-les en lieu sûr. Piuma ne peut pas les récupérer pour vous.';

  @override
  String get syncPhraseNewTitle => 'Votre nouvelle phrase de récupération';

  @override
  String syncPhraseNewBody(String name) {
    return '$name ne peut plus ouvrir votre espace, et l’ancienne phrase ne fonctionne plus. Écrivez plutôt ces 24 mots sur papier.';
  }

  @override
  String get syncPhraseWarn =>
      'Toute personne qui a ces mots peut lire votre espace.';

  @override
  String get syncPhraseDone => 'Je les ai notés';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Un nouveau téléphone veut se connecter',
      'tablet': 'Une nouvelle tablette veut se connecter',
      'other': 'Un nouvel ordinateur veut se connecter',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · demandé $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Saisissez les 6 chiffres affichés par le téléphone.',
      'tablet': 'Saisissez les 6 chiffres affichés par la tablette.',
      'other': 'Saisissez les 6 chiffres affichés par l’ordinateur.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'Les 6 chiffres';

  @override
  String get syncNotMe => 'Ce n’est pas moi';

  @override
  String get syncApprove => 'Approuver';

  @override
  String get syncApproving => 'Approbation…';

  @override
  String syncFailOffline(String email) {
    return 'Impossible de joindre $email. Réessayez quand vous serez en ligne.';
  }

  @override
  String get syncFailExpired =>
      'La demande a expiré. Redemandez depuis le nouvel appareil.';

  @override
  String get syncFailOther => 'Un problème est survenu. Réessayez.';

  @override
  String get syncRowOn => 'Activée';

  @override
  String get syncRowOff => 'Désactivée';

  @override
  String get pairAlready => 'J’utilise déjà Piuma sur un autre appareil';

  @override
  String get pairAlreadyOn =>
      'Connectez-vous à l’une de vos boîtes. Si elle contient votre espace, vous associerez ensuite cet appareil.';

  @override
  String get pairLinkTitle => 'Associer ce téléphone';

  @override
  String get pairLinkBody =>
      'Sur l’ordinateur, ouvrez Réglages › Appareils et synchronisation › Associer un nouvel appareil, puis scannez le code affiché.';

  @override
  String get pairScan => 'Scanner le code';

  @override
  String get pairSignInInstead => 'Se connecter plutôt';

  @override
  String get pairScanHint => 'Visez le code affiché sur l’ordinateur';

  @override
  String get pairScanWhere =>
      'Réglages › Appareils et synchronisation › Associer un nouvel appareil';

  @override
  String get pairNoCamera =>
      'Piuma ne peut pas utiliser la caméra. Autorisez-la dans les réglages du système, ou connectez-vous plutôt.';

  @override
  String get pairLastStep => 'Une dernière étape';

  @override
  String get pairLastStepBody =>
      'Connectez-vous à la boîte qui contient votre espace. Les autres comptes arrivent seuls.';

  @override
  String get pairConfirmsOwn =>
      'L’ordinateur confirme seul : c’est lui qui vous a montré le code.';

  @override
  String get pairLink => 'Associer';

  @override
  String get pairLinking => 'Association…';

  @override
  String get pairFoundTitle => 'Nous avons trouvé votre espace';

  @override
  String pairFoundBody(String email) {
    return 'La boîte $email contient une copie chiffrée de vos réglages. Seuls vos appareils peuvent la lire.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'comptes',
      one: 'compte',
    );
    return '$_temp0';
  }

  @override
  String pairGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'groupes',
      one: 'groupe',
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
    return 'Chiffré de bout en bout · mis à jour $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'Par sécurité, confirmez depuis un appareil déjà associé : $name, actif $ago.';
  }

  @override
  String get pairShowCode => 'Afficher le code';

  @override
  String get pairUsePhrase => 'Utiliser la phrase de récupération';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Confirmez sur votre téléphone',
      'tablet': 'Confirmez sur votre tablette',
      'other': 'Confirmez sur votre ordinateur',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Ouvrez Piuma sur $name et saisissez le code.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Code $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Expire dans $time';
  }

  @override
  String pairWaiting(String name) {
    return 'En attente de la confirmation de $name…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name affichera « $title »';
  }

  @override
  String get pairStep2 => 'Saisissez les 6 chiffres et touchez Approuver';

  @override
  String get pairExpired => 'Le code a expiré.';

  @override
  String pairRefused(String name) {
    return '$name a indiqué que ce n’était pas vous.';
  }

  @override
  String get pairWrongCode => 'Le code saisi là-bas n’était pas celui-ci.';

  @override
  String get pairNewCode => 'Afficher un nouveau code';

  @override
  String get pairPhraseTitle => 'Phrase de récupération';

  @override
  String get pairPhraseBody =>
      'Saisissez les 24 mots notés, dans l’ordre, séparés par des espaces.';

  @override
  String pairPhraseCount(int count) {
    return '$count mots sur 24';
  }

  @override
  String get pairPhraseWrong =>
      'Ces mots n’ouvrent pas votre espace. Vérifiez-les et réessayez.';

  @override
  String get pairContinue => 'Continuer';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Téléphone associé',
      'tablet': 'Tablette associée',
      'other': 'Ordinateur associé',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody => 'Voici ce qui est arrivé de votre espace chiffré.';

  @override
  String get pairDoneAccounts => 'Comptes';

  @override
  String get pairDoneGroups => 'Groupes';

  @override
  String get pairDoneSettings => 'Signatures et réglages synchronisés';

  @override
  String get pairSynced => 'Synchronisé';

  @override
  String pairStepOf(int step) {
    return 'Étape $step sur 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'aujourd’hui à $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'hier à $time';
  }

  @override
  String pairOnDay(String day) {
    return 'le $day';
  }

  @override
  String get keyOpenWindow => 'ouvrir dans une nouvelle fenêtre';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synchronisé sur $count appareils',
      one: 'Synchronisé sur 1 appareil',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters =>
      'Quand une newsletter a été lue il y a plus de 7 jours';

  @override
  String get ruleBuiltIn => 'Intégrée · tous les comptes';

  @override
  String get syncTurnOff => 'Désactiver la synchronisation sur cet appareil';

  @override
  String get syncTurnOffAsk =>
      'Désactiver la synchronisation sur cet appareil ?';

  @override
  String syncTurnOffOne(String name) {
    return 'Cet appareil quitte votre espace et ne reçoit plus de modifications. Ses comptes et ses e-mails restent ici. $name continue de se synchroniser.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'Cet appareil quitte votre espace et ne reçoit plus de modifications. Ses comptes et ses e-mails restent ici. $names continuent de se synchroniser.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'Cet appareil quitte votre espace et ne reçoit plus de modifications. Ses comptes et ses e-mails restent ici. C’est votre seul appareil : la copie chiffrée dans $email est aussi supprimée.';
  }

  @override
  String get syncTurnOffButton => 'Désactiver la synchronisation';

  @override
  String get listAnd => 'et';

  @override
  String get composeDropFiles => 'Déposer pour joindre';

  @override
  String get serverType => 'Type de serveur';

  @override
  String get imapAndSmtp => 'IMAP et SMTP';

  @override
  String get jmapServer => 'Serveur JMAP';

  @override
  String get jmapServerHint =>
      'Le nom du serveur, ou l’adresse complète de sa session JMAP.';

  @override
  String get jmapSignsIn =>
      'Un seul serveur lit, envoie et apporte les nouveaux e-mails. Vous vous connectez avec votre adresse.';

  @override
  String get shortcutsTitle => 'Raccourcis';

  @override
  String shortcutsLine(String keys) {
    return 'Juste l’essentiel. Tout le reste est dans $keys.';
  }

  @override
  String get shortcutsTable => 'Raccourcis clavier';

  @override
  String get shortcutPalette => 'Palette de commandes';

  @override
  String ruleSuggest(String name, String folder) {
    return 'Vous déplacez souvent les e-mails de $name vers $folder. Créer une règle ?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Suggéré sur l’appareil · $count déplacements le mois dernier',
      one: 'Suggéré sur l’appareil · 1 déplacement le mois dernier',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Transférer';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Message transféré ----------\nDe : $from\nDate : $date\nÀ : $to\nObjet : $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date à $time';
  }

  @override
  String get folderWaiting => 'En attente';

  @override
  String waitingSummary(int count) {
    return '$count envoyés · pas encore de réponse';
  }

  @override
  String get waitingNoReply => 'Pas encore de réponse';

  @override
  String get waitingTo => 'À ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'aujourd’hui';

  @override
  String get waitingYesterday => 'hier';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails envoyés attendent une réponse',
      one: '1 e-mail envoyé attend une réponse',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Relancer';

  @override
  String get stopWaiting => 'Ne plus attendre';

  @override
  String get stoppedWaiting => 'Retiré de En attente. Il reste dans Envoyés.';

  @override
  String get remindMe => 'Me le rappeler';

  @override
  String get remindTitle => 'Me le rappeler si personne ne répond';

  @override
  String get remindTomorrow => 'Demain';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dans $count jours',
      one: 'Dans 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'La semaine prochaine';

  @override
  String get remindPickDate => 'Choisir une date…';

  @override
  String get remindNever => 'Ne pas me le rappeler';

  @override
  String remindChipToday(String time) {
    return 'Me le rappeler à $time';
  }

  @override
  String get remindChipTomorrow => 'Me le rappeler demain';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Me le rappeler dans $count jours',
      one: 'Me le rappeler dans 1 jour',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Me le rappeler le $date';
  }

  @override
  String remindAt(String when) {
    return 'Me le rappeler $when';
  }

  @override
  String remindNoReply(String name) {
    return 'Pas de réponse de $name';
  }

  @override
  String get remindSentToday => 'envoyé aujourd’hui';

  @override
  String get remindSentYesterday => 'envoyé hier';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'envoyé il y a $count jours',
      one: 'envoyé il y a 1 jour',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Pièces jointes partagées';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pièces jointes',
      one: '1 pièce jointe',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles =>
      'Aucune pièce jointe de cette personne pour l’instant.';

  @override
  String get senderAddresses => 'Adresses';

  @override
  String senderAddressNote(String account, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$account · $_temp0';
  }

  @override
  String get senderCopyAddress => 'Copier l’adresse';

  @override
  String get senderRules => 'Règles et dossiers';

  @override
  String get senderContent => 'Contenu de l’expéditeur';

  @override
  String folderReorder(String name) {
    return 'Faire glisser pour réordonner $name';
  }

  @override
  String get folderMoveUp => 'Monter';

  @override
  String get folderMoveDown => 'Descendre';

  @override
  String get ruleUnopenedNewsletters => 'Newsletters';

  @override
  String get ruleUnopenedFor => ' non ouvertes depuis ';

  @override
  String get ruleUnopenedDays => '30 jours';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails archivés',
      one: '1 e-mail archivé',
      zero: 'tous les comptes',
    );
    return 'Chaque nuit · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'Les règles s’exécutent sur cet appareil et se synchronisent sur tous vos appareils';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'Les règles s’exécutent sur cet appareil et se synchronisent sur tous vos appareils · mis à jour $ago';
  }

  @override
  String get calSynced =>
      'Les connexions se synchronisent sur tous vos appareils ; les mots de passe voyagent chiffrés et restent dans le trousseau du système.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mis à jour toutes les $count heures',
      one: 'mis à jour toutes les heures',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mis à jour tous les $count jours',
      one: 'mis à jour chaque jour',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'mis à jour chaque semaine';

  @override
  String get showOriginalLayout => 'Afficher la mise en page d’origine';

  @override
  String get originalLayout => 'Mise en page d’origine';

  @override
  String get originalLayoutBar =>
      'Mise en page d’origine · images et liens suivent vos réglages de confidentialité';

  @override
  String get backToReadingView => 'Revenir à la vue lecture';

  @override
  String get readingView => 'Vue lecture';

  @override
  String get replyFromLabel => 'Répondre depuis';

  @override
  String replyFromSignature(String name) {
    return 'signature $name';
  }

  @override
  String get noticeReplyHint => 'Écrire une réponse…';

  @override
  String get labelsHeading => 'Libellés';

  @override
  String get labelsSection => 'LIBELLÉS';

  @override
  String get labelAction => 'Libellé';

  @override
  String get labelAdd => '+ Libellé';

  @override
  String get labelNew => 'Nouveau libellé';

  @override
  String get labelFind => 'Trouver ou créer un libellé';

  @override
  String labelCreate(String name) {
    return 'Créer « $name »';
  }

  @override
  String labelRemove(String name) {
    return 'Retirer le libellé $name';
  }

  @override
  String labelEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$_temp0';
  }

  @override
  String labelAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: '1 compte',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account ne garde pas de libellés sur le serveur, ses libellés restent donc sur cet appareil.';
  }

  @override
  String get hintLabel => 'libellé';

  @override
  String get labelName => 'Nom du libellé';

  @override
  String get labelEdit => 'Modifier le libellé';

  @override
  String get labelSave => 'Enregistrer';

  @override
  String get labelCreateButton => 'Créer';

  @override
  String get labelDelete => 'Supprimer le libellé';

  @override
  String get labelDeleteNote =>
      'Il est retiré de tous les e-mails ; les e-mails restent où ils sont.';

  @override
  String get labelColorAmber => 'Ambre';

  @override
  String get labelColorTeal => 'Bleu canard';

  @override
  String get labelColorCoral => 'Corail';

  @override
  String get labelColorBlue => 'Bleu';

  @override
  String get labelColorViolet => 'Violet';

  @override
  String get labelMenu => 'Libellé…';

  @override
  String get ruleDoLabel => 'ajouter le libellé';

  @override
  String get ruleTrayLabel => 'Libellé';

  @override
  String get rulePickLabel => 'un libellé';

  @override
  String get ruleNoLabels =>
      'Aucun libellé pour l’instant : créez-en un avec + Libellé sous Dossiers et libellés.';

  @override
  String get foldersAndLabelsHeading => 'Dossiers et libellés';

  @override
  String get labelsCardTitle => 'Libellés';

  @override
  String get labelsCardDetail => 'partagés entre tous les comptes';

  @override
  String get labelsNone => 'Aucun libellé pour l’instant.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dossiers',
      one: '1 dossier',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libellés',
      one: '1 libellé',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Photos des expéditeurs';

  @override
  String get senderPicturesSettingHint =>
      'Les photos de vos contacts et les logos vérifiés des entreprises à la place des lettres.';

  @override
  String get websiteIconsSetting => 'Icônes des sites web';

  @override
  String get websiteIconsSettingHint =>
      'Pour les entreprises sans logo. Chaque site voit votre adresse IP une fois.';

  @override
  String tabletInboxUnread(int count) {
    return 'Boîte de réception, $count non lus';
  }

  @override
  String tabletAccount(String name, String email) {
    return 'Compte $name, $email';
  }

  @override
  String get tabletSearch => 'Rechercher dans le courrier';

  @override
  String get tabletSearchHint => 'Rechercher ou lancer une commande';

  @override
  String get vaultTrackParcel => 'Suivre le colis';

  @override
  String get vaultTrackingCopied => 'Numéro de suivi copié';

  @override
  String get vaultNeedsYou => 'À traiter';

  @override
  String get vaultNext => 'À venir';

  @override
  String get vaultOnTheWay => 'En route';

  @override
  String get vaultEverything => 'Tout';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count choses à traiter',
      one: '1 chose à traiter',
    );
    return '$_temp0';
  }

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'un vol aujourd’hui',
      'train': 'un train aujourd’hui',
      'ferry': 'un ferry aujourd’hui',
      'bus': 'un car aujourd’hui',
      'stay': 'un check-in aujourd’hui',
      'parking': 'un parking aujourd’hui',
      'car': 'une voiture de location aujourd’hui',
      'event': 'un événement aujourd’hui',
      'table': 'une table aujourd’hui',
      'other': 'une réservation aujourd’hui',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Vol',
      'train': 'Train',
      'ferry': 'Ferry',
      'bus': 'Car',
      'stay': 'Check-in',
      'parking': 'Parking',
      'car': 'Location de voiture',
      'event': 'Événement',
      'table': 'Table',
      'other': 'Réservation',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Colis';

  @override
  String get vaultCatSpending => 'Dépenses';

  @override
  String get vaultCatTrips => 'Voyages';

  @override
  String get vaultCatSales => 'Ventes';

  @override
  String get vaultCatSubscriptions => 'Abonnements';

  @override
  String get vaultCatReturns => 'Retours et garantie';

  @override
  String get vaultCatDeadlines => 'Échéances';

  @override
  String get vaultCatBookings => 'Réservations';

  @override
  String get vaultCatVouchers => 'Cartes cadeaux et codes';

  @override
  String get vaultCatDocuments => 'Documents';

  @override
  String get vaultCatCertified => 'Courrier certifié';

  @override
  String vaultOnWayCount(int count) {
    return '$count en route';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count à retirer';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count livrés',
      one: '1 livré',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'En voyage';

  @override
  String vaultNextWhen(String when) {
    return 'Prochain : $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voyages passés',
      one: '1 voyage passé',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count à expédier';
  }

  @override
  String vaultSoldCount(int count) {
    return '$count vendus';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money par mois';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abonnements',
      one: '1 abonnement',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count retours, le premier jusqu’au $day',
      one: '1 retour jusqu’au $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count sous garantie';
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
    return '$count remis';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Paiement échoué · $who';
  }

  @override
  String get vaultPaymentFailed => 'Paiement échoué';

  @override
  String vaultWasDue(String when) {
    return 'Échéance $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'À expédier avant $when';
  }

  @override
  String get vaultToShip => 'À expédier';

  @override
  String get vaultYouSend => 'Vous expédiez';

  @override
  String vaultSoldOn(String where) {
    return 'vendu sur $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'À retirer avant $when';
  }

  @override
  String get vaultReadyPickup => 'Prêt à retirer';

  @override
  String vaultRenewsWhen(String when) {
    return 'Renouvellement $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Se termine $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money par semaine',
      'month': '$money par mois',
      'year': '$money par an',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'depuis $day';
  }

  @override
  String get vaultUpdatePayment => 'Mettre à jour le paiement';

  @override
  String get vaultCoach => 'Voiture';

  @override
  String get vaultTicket => 'Billet';

  @override
  String vaultInHours(int hours) {
    return 'dans $hours h';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'dans $minutes min';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count colis livrés cette semaine',
      one: '1 colis livré cette semaine',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Dépensé en $month';
  }

  @override
  String vaultReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reçus',
      one: '1 reçu',
    );
    return '$_temp0';
  }

  @override
  String get vaultExportMonth => 'Exporter le mois';

  @override
  String vaultSpentTab(String money) {
    return 'Dépensé · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Encaissé · $money';
  }

  @override
  String vaultVia(String service) {
    return 'via $service';
  }

  @override
  String get vaultSpendingNote =>
      'Lu sur l’appareil depuis les reçus et factures';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file et $count PDF enregistrés dans Téléchargements',
      one: '$file et 1 PDF enregistrés dans Téléchargements',
      zero: '$file enregistré dans Téléchargements',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'Impossible d’exporter le mois';

  @override
  String get vaultPrevMonth => 'Mois précédent';

  @override
  String get vaultNextMonth => 'Mois suivant';

  @override
  String get vaultNothingThisMonth => 'Aucun reçu ce mois-ci.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Abonnements · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Date,Qui,Quoi,Montant,Devise,Payé via,Fichier,Numéro de TVA';

  @override
  String vaultComingUp(int count) {
    return '$count à venir';
  }

  @override
  String get vaultNoTrips => 'Aucun voyage prévu';

  @override
  String get vaultPastTrips => 'Voyages passés';

  @override
  String vaultThisYear(int count) {
    return '$count cette année';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'En cours · retour $when';
  }

  @override
  String get vaultLegDone => 'Terminé';

  @override
  String vaultUntilTime(String time) {
    return 'Jusqu’à $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Jusqu’au $day';
  }

  @override
  String get vaultTripsNote =>
      'Trains, ferries, vols, séjours, parkings et billets';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuits',
      one: '1 nuit',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'à partir de $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'voiture $coach, place $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'place $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'code $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Vol $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Vendu sur $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Vendu sur $who';
  }

  @override
  String get vaultSaleOnWay => 'En route';

  @override
  String get vaultSaleReceived => 'Reçu';

  @override
  String get vaultPaidOut => 'Versé';

  @override
  String get vaultCanGoBack => 'Peut encore être retourné';

  @override
  String get vaultUnderWarranty => 'Sous garantie';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days jours pour retourner';
  }

  @override
  String vaultBought(String day) {
    return 'acheté $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Garantie $month';
  }

  @override
  String get vaultCodeCopied => 'Code copié';

  @override
  String get vaultCopyCode => 'Copier le code';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Fiche de paie',
      'statement': 'Relevé',
      'tax': 'Document fiscal',
      'contract': 'Contrat',
      'other': 'Document',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Ouvrir le fichier';

  @override
  String vaultBookingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count réservations',
      one: '1 réservation',
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
  String get vaultCategoryEmpty => 'Rien ici pour le moment.';

  @override
  String get vaultFlagged => 'à traiter';

  @override
  String get suggestWroteTo => 'Vous avez écrit à';

  @override
  String get suggestWroteToYou => 'Vous a écrit';

  @override
  String get readerEmptyTap => 'Touchez un message pour le lire.';

  @override
  String get noticeAwayTitle => 'Pendant votre absence';

  @override
  String noticeAwayEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$_temp0';
  }

  @override
  String noticeAwayPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de personnes',
      one: '1 d’une personne',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Week-ends, toute la journée';

  @override
  String get quietWeekendsHint => 'Samedi et dimanche';

  @override
  String get quietWhile => 'Pendant le calme';

  @override
  String get quietWhileHint => 'Aucune notification résume tout à la fin';

  @override
  String get quietNoSound => 'Sans son';

  @override
  String get quietNoNotices => 'Aucune notification';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · sonne comme d’habitude';
  }

  @override
  String get quietAccountsHint =>
      'Les comptes désactivés sonnent comme d’habitude pendant les heures calmes.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'arabe',
      'bg': 'bulgare',
      'ca': 'catalan',
      'cs': 'tchèque',
      'zh': 'chinois',
      'da': 'danois',
      'de': 'allemand',
      'el': 'grec',
      'en': 'anglais',
      'et': 'estonien',
      'fi': 'finnois',
      'fr': 'français',
      'he': 'hébreu',
      'hi': 'hindi',
      'hr': 'croate',
      'hu': 'hongrois',
      'id': 'indonésien',
      'it': 'italien',
      'ja': 'japonais',
      'ko': 'coréen',
      'lt': 'lituanien',
      'lv': 'letton',
      'nl': 'néerlandais',
      'nb': 'norvégien',
      'pl': 'polonais',
      'pt': 'portugais',
      'ro': 'roumain',
      'ru': 'russe',
      'sk': 'slovaque',
      'sl': 'slovène',
      'es': 'espagnol',
      'sr': 'serbe',
      'sv': 'suédois',
      'th': 'thaï',
      'tr': 'turc',
      'uk': 'ukrainien',
      'vi': 'vietnamien',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Écrit en $language';
  }

  @override
  String get translateAction => 'Traduire';

  @override
  String translateGetting(String from, String to) {
    return 'Récupération $from–$to';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return 'Récupération $from–$to · $size';
  }

  @override
  String get translating => 'Traduction…';

  @override
  String translatedFrom(String language) {
    return 'Traduit depuis : $language · sur cet appareil';
  }

  @override
  String get translatedShort => 'Traduit';

  @override
  String get translateShowOriginal => 'Afficher l’original';

  @override
  String get translateOriginalShort => 'Original';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'Pour traduire, téléchargez d’abord $from et $to.';
  }

  @override
  String get translateFailed => 'Impossible de traduire cet e-mail. Réessayez.';

  @override
  String get appearanceTranslateInto => 'Traduire en';

  @override
  String get translateIntoApp => 'Langue de l’app';

  @override
  String get translateIntoHint =>
      'Les e-mails dans d’autres langues proposent Traduire. Tout se passe sur cet appareil.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Retirer';

  @override
  String translateRemovePair(String pair) {
    return 'Retirer $pair';
  }

  @override
  String get printEmail => 'Imprimer…';

  @override
  String printTooltip(String keys) {
    return 'Imprimer… $keys';
  }

  @override
  String get printOrSavePdf => 'Imprimer ou enregistrer en PDF';

  @override
  String get reportSpam => 'Signaler comme spam';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations signalées comme spam',
      one: 'Signalé comme spam',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'Pas un spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations déplacées vers Boîte de réception',
      one: 'Déplacé vers Boîte de réception',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Date';

  @override
  String printAttachments(String files) {
    return 'Pièces jointes : $files';
  }

  @override
  String get helpTitle => 'Aide et commentaires';

  @override
  String get helpSubtitle =>
      'Signalez un problème ou proposez une idée. Rien n’est envoyé sans vous.';

  @override
  String get reportProblem => 'Signaler un problème';

  @override
  String get reportThisProblem => 'Signaler ce problème';

  @override
  String get reportCantAddAccount => 'Je n’arrive pas à ajouter mon compte';

  @override
  String get suggestIdea => 'Proposer une idée';

  @override
  String get shakeToReport => 'Secouer pour signaler';

  @override
  String get shakeToReportHint =>
      'Secouez le téléphone sur n’importe quel écran';

  @override
  String get yourReports => 'Vos signalements';

  @override
  String get reportNone => 'Aucun signalement pour l’instant.';

  @override
  String get reportTitle => 'Signalement';

  @override
  String get reportKindProblem => 'Problème';

  @override
  String get reportKindIdea => 'Idée';

  @override
  String get reportTitleField => 'Titre';

  @override
  String get reportTitleHint => 'En quelques mots';

  @override
  String get reportProblemField => 'Ce qui s’est passé';

  @override
  String get reportIdeaField => 'Quoi et pourquoi';

  @override
  String get reportDescriptionHint =>
      'Ce que vous avez fait, et ce que vous attendiez';

  @override
  String get reportScreenshot => 'Capture de cet écran';

  @override
  String get reportScreenshotWindow => 'Capture de cette fenêtre';

  @override
  String get reportScreenshotOff =>
      'Désactivée : elle peut montrer vos e-mails';

  @override
  String get reportScreenshotOn => 'Touchez l’image pour masquer des parties';

  @override
  String get reportLog => 'Journal de l’app';

  @override
  String get reportLogHint => 'Sans adresses ni objets';

  @override
  String get reportDevice => 'Infos sur l’appareil et l’app';

  @override
  String get reportDeviceHint => 'Version, modèle, langue';

  @override
  String get reportAlways => 'Toujours';

  @override
  String get reportSeeSent => 'Voir ce qui est envoyé';

  @override
  String get reportSend => 'Envoyer';

  @override
  String get reportQueued => 'Signalement en file d’attente';

  @override
  String get reportNotKept => 'Impossible de garder le signalement';

  @override
  String get reportWhatsSent => 'Ce qui est envoyé';

  @override
  String get reportSectionReport => 'Signalement';

  @override
  String get reportSectionDevice => 'Appareil';

  @override
  String get reportSectionScreenshot => 'Capture';

  @override
  String get reportHideParts => 'Masquer des parties';

  @override
  String get reportDragToBlur => 'Faites glisser pour flouter';

  @override
  String get reportDone => 'OK';

  @override
  String get reportStatusQueued => 'En file d’attente';

  @override
  String get reportStatusSending => 'Envoi';

  @override
  String get reportStatusFailed => 'Échec';

  @override
  String get reportStatusEmailed => 'Envoyé par e-mail';

  @override
  String get reportWaitOffline => 'en attente d’un réseau';

  @override
  String get reportWaitTurn => 'part dans un instant';

  @override
  String reportWaitAt(String time) {
    return 'part à $time';
  }

  @override
  String get reportWaitPaused => 'part plus tard aujourd’hui ou demain';

  @override
  String get reportTapRetry => 'touchez pour réessayer';

  @override
  String get reportTryAgain => 'Réessayer';

  @override
  String get reportByEmail => 'Envoyer plutôt par e-mail';

  @override
  String get reportDelete => 'Supprimer';

  @override
  String get reportOptions => 'Options du signalement';

  @override
  String get crashLine =>
      'Piuma s’est fermée de façon inattendue. Envoyer un signalement ?';

  @override
  String get crashReport => 'Signaler';

  @override
  String get crashDismiss => 'Ignorer';

  @override
  String reportStatusSent(int number) {
    return 'Envoyé n° $number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines lignes',
      one: '1 ligne',
    );
    return 'Journal de l’app · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Aide';

  @override
  String get awayTitle => 'Réponse d’absence';

  @override
  String get awayNote => 'Répond pour vous, même app fermée';

  @override
  String get awayFrom => 'Du';

  @override
  String get awayToInline => 'au';

  @override
  String get awayTo => 'Au';

  @override
  String get awaySubject => 'Objet';

  @override
  String get awayMessage => 'Message';

  @override
  String get awayEndsNote =>
      'S’arrête toute seule après le dernier jour. Laissez \"au\" vide pour la garder active jusqu’à ce que vous la désactiviez.';

  @override
  String awaySubjectUntil(String date) {
    return 'Absent jusqu’au $date';
  }

  @override
  String get awaySubjectPlain => 'Absent';

  @override
  String awayBodyUntil(String date) {
    return 'Bonjour, je suis absent jusqu’au $date et je répondrai à mon retour.';
  }

  @override
  String get awayBodyPlain =>
      'Bonjour, je suis absent et je répondrai à mon retour.';

  @override
  String get awayToday => 'Aujourd’hui';

  @override
  String get awayNoEnd => 'Sans fin';

  @override
  String get awayPickFrom => 'Premier jour';

  @override
  String get awayPickTo => 'Dernier jour';

  @override
  String get awayKeepOn => 'La garder active jusqu’à ce que je la désactive';

  @override
  String get awayOtherFilters =>
      'Impossible de l’activer avec vos filtres actuels. Désactivez-les d’abord sur le serveur.';

  @override
  String get awayUnsupported =>
      'Ce serveur n’accepte plus de réponse d’absence.';

  @override
  String get awayOffline =>
      'Impossible de joindre le serveur. Réessayez dans un instant.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Réponse d’absence active pour $account jusqu’au $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Réponse d’absence active pour $account';
  }

  @override
  String get awayTurnOff => 'Désactiver';

  @override
  String get awayRowOff => 'Désactivée';

  @override
  String get awayRowOn => 'Activée';

  @override
  String awayRowUntil(String date) {
    return 'Activée jusqu’au $date';
  }

  @override
  String get featuresSubtitle =>
      'Désactivez ce que vous n’utilisez pas. Cela disparaît partout, et rien n’est supprimé.';

  @override
  String get featuresZones => 'Espaces';

  @override
  String get featuresOnDevice => 'Sur cet appareil';

  @override
  String get featuresOnDeviceNote => 'Rien ici ne quitte jamais l’appareil.';

  @override
  String get featureNewslettersHint =>
      'Les newsletters dans leur propre liste, à lire comme un magazine';

  @override
  String get featureNewslettersOff =>
      'Désactivé · les newsletters arrivent dans la boîte comme n’importe quel e-mail';

  @override
  String get featureVaultHint =>
      'Paiements, colis, voyages et échéances sous forme de cartes';

  @override
  String get featureVaultOff =>
      'Désactivé · ces e-mails restent tels quels, sans cartes ni notifications';

  @override
  String get featureAttachmentsHint =>
      'Tous les fichiers reçus, au même endroit';

  @override
  String get featureAttachmentsOff =>
      'Désactivé · les fichiers restent dans leurs e-mails, et la recherche les trouve toujours';

  @override
  String get featureInShortHint =>
      'L’essentiel des longues conversations, au-dessus du premier e-mail';

  @override
  String get featureInShortOff =>
      'Désactivé · les conversations s’ouvrent sans le résumé';

  @override
  String get featureTranslate => 'Traduire';

  @override
  String get featureTranslateHint =>
      'Propose de traduire les e-mails écrits dans d’autres langues';

  @override
  String get featureTranslateOff =>
      'Désactivé · aucune proposition de traduction, et aucune langue téléchargée';

  @override
  String get featureFoundDates => 'Dates dans les e-mails';

  @override
  String get featureFoundDatesHint =>
      'Ajouter au calendrier les dates et heures trouvées dans le texte';

  @override
  String get featureFoundDatesOff =>
      'Désactivé · les invitations affichent toujours leur carte';

  @override
  String get nextEmail => 'E-mail suivant';

  @override
  String get previousEmail => 'E-mail précédent';

  @override
  String get appearanceLanguage => 'Langue';

  @override
  String get languageDevice => 'Langue de l’appareil';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain ressemble à $like, mais c’est une autre adresse.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'Le nom dit $brand, mais l’adresse est chez $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'Cet e-mail dit venir de $domain, mais $domain ne l’a pas envoyé.';
  }

  @override
  String get senderDetails => 'Détails';

  @override
  String get senderDetailsTitle => 'Ce qui a été vérifié';

  @override
  String get senderSentBy => 'Envoyé par';

  @override
  String get senderNotKnown => 'Inconnu';

  @override
  String get senderSignature => 'Signature';

  @override
  String get senderSignatureNone => 'Aucune';

  @override
  String get senderDomainCheck => 'Vérification du domaine';

  @override
  String get senderDomainCheckFailed => 'Échouée (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Ressemble à';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails de là',
      one: '1 e-mail de là',
      zero: 'aucun e-mail de là',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'Le nom dit';

  @override
  String get senderDetailsNote =>
      'Déduit sur cet appareil de ce qu’a écrit votre serveur de messagerie. Les liens de cet e-mail demandent avant de s’ouvrir.';

  @override
  String impostorLinkBody(String real) {
    return 'Cet e-mail ne vient peut-être pas de qui il prétend. Le lien mène à $real.';
  }

  @override
  String get updates => 'Mises à jour';

  @override
  String get updatesVersion => 'Version';

  @override
  String get upToDate => 'À jour';

  @override
  String get updatesAuto => 'Piuma cherche seule les nouvelles versions';

  @override
  String get checkForUpdates => 'Rechercher';

  @override
  String get updateChecking => 'Vérification…';

  @override
  String get checkedJustNow => 'Vérifié à l’instant';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vérifié il y a $count minutes',
      one: 'Vérifié il y a 1 minute',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vérifié il y a $count heures',
      one: 'Vérifié il y a 1 heure',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vérifié il y a $count jours',
      one: 'Vérifié hier',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Téléchargement de $version · $percent %';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done sur $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Prête · $version';
  }

  @override
  String get updateGoesInOnRestart => 'S’installe au redémarrage de Piuma';

  @override
  String get restart => 'Redémarrer';

  @override
  String get updateCouldntCheck => 'Vérification impossible';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get seeWhatsNew => 'Voir les nouveautés';

  @override
  String get whatsNew => 'Nouveautés';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'Vos e-mails et brouillons sont conservés. Piuma se ferme et se rouvre en quelques secondes.';

  @override
  String get restartNow => 'Redémarrer maintenant';

  @override
  String updateReadyLine(String version) {
    return 'Mise à jour prête · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Mis à jour vers $version';
  }

  @override
  String get swipeHintArchiveSnooze =>
      'Balayez vers la droite pour archiver, vers la gauche pour reporter';

  @override
  String get swipeHintArchive => 'Balayez vers la droite pour archiver';

  @override
  String get formatting => 'Mise en forme';

  @override
  String get formatBold => 'Gras';

  @override
  String get formatItalic => 'Italique';

  @override
  String get formatLink => 'Lien';

  @override
  String get formatBullets => 'Liste à puces';

  @override
  String get formatNumbers => 'Liste numérotée';

  @override
  String get formatQuote => 'Citation';

  @override
  String get linkAddressHint => 'Collez ou tapez une adresse';

  @override
  String get linkAdd => 'Ajouter';

  @override
  String get linkRemove => 'Retirer le lien';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count images sont désactivées : $sender ne voit pas quand vous l’ouvrez.',
      one: '1 image est désactivée : $sender ne voit pas quand vous l’ouvrez.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Charger les images';

  @override
  String get alwaysForSender => 'Toujours pour cet expéditeur';

  @override
  String get cleanView => 'Vue épurée';

  @override
  String get viewOriginal => 'Original';

  @override
  String get viewClean => 'Épurée';

  @override
  String get calGoogle => 'Google Agenda';

  @override
  String get calGoogleSub =>
      'Lire les événements et la disponibilité avec un lien iCal';

  @override
  String get calGoogleLabel => 'Adresse iCal de Google Agenda';

  @override
  String get calGoogleHint =>
      'Dans Google Agenda sur un ordinateur : Paramètres › votre agenda › Intégrer l’agenda › Adresse secrète au format iCal. Lecture seule ; connexion directe.';

  @override
  String get bundledReleaseNotes =>
      '## Le courrier, tout en légèreté\n- Mises en page originales avec défilement unique et contrôle des images\n- Barre de mise en forme et ouverture de l’éditeur complet dans les réponses\n- Gestes de balayage horizontal plus précis\n- Alertes d’expéditeur pour l’usurpation de marque et les domaines ressemblants\n- Export CSV mensuel du Coffre avec numéro de TVA du marchand';
}
