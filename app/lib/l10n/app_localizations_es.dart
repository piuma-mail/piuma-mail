// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get catalogSubtitle => 'Catálogo de componentes · Fase 0';

  @override
  String get sectionColors => 'Colores';

  @override
  String get sectionTypography => 'Tipografía';

  @override
  String get sectionButtons => 'Botones';

  @override
  String get sectionFilters => 'Filtros';

  @override
  String get sectionMessageRows => 'Filas de mensajes';

  @override
  String get colorBackground => 'Fondo';

  @override
  String get colorSurface => 'Superficie';

  @override
  String get colorText => 'Texto';

  @override
  String get colorSecondary => 'Secundario';

  @override
  String get colorAccent => 'Acento';

  @override
  String get colorSoft => 'Suave';

  @override
  String get colorSuccess => 'Éxito';

  @override
  String get colorWarning => 'Aviso';

  @override
  String get colorDanger => 'Peligro';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Título';

  @override
  String get typeSubtitle => 'Subtítulo';

  @override
  String get typeBody => 'Cuerpo';

  @override
  String get typeSmall => 'Pequeño';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Enviar';

  @override
  String get actionSnooze => 'Posponer';

  @override
  String get actionReply => 'Responder';

  @override
  String get actionDelete => 'Eliminar';

  @override
  String get actionDisabled => 'Desactivado';

  @override
  String get filterUnread => 'No leídos';

  @override
  String get filterAttachments => 'Con adjuntos';

  @override
  String get filterPeople => 'Solo personas';

  @override
  String get messageUnread => 'No leído';

  @override
  String get compose => 'Redactar';

  @override
  String get unifiedInbox => 'Bandeja unificada';

  @override
  String get accounts => 'Cuentas';

  @override
  String get addAccount => 'Añadir una cuenta';

  @override
  String get inbox => 'Bandeja de entrada';

  @override
  String downloading(String done, String total) {
    return 'Descargando $done de $total';
  }

  @override
  String get offline => 'Sin conexión · reintentando';

  @override
  String get signInFailed => 'Una cuenta necesita de nuevo su contraseña';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts cuentas',
      one: '1 cuenta',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread sin leer',
      zero: 'todo leído',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Elige un mensaje para leerlo.';

  @override
  String get noSubject => '(sin asunto)';

  @override
  String get couldNotLoadMessage =>
      'No se pudo descargar este mensaje. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get loading => 'Cargando…';

  @override
  String toYouToday(String time) {
    return 'para ti · hoy a las $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'para ti · ayer a las $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'para ti · $date a las $time';
  }

  @override
  String get sectionToday => 'Hoy';

  @override
  String get sectionYesterday => 'Ayer';

  @override
  String get sectionThisWeek => 'Esta semana';

  @override
  String get sectionThisMonth => 'Este mes';

  @override
  String get sectionOlder => 'Más antiguos';

  @override
  String get defaultAccountName => 'Correo';

  @override
  String get emailAddress => 'Dirección de correo';

  @override
  String get password => 'Contraseña';

  @override
  String notificationNotices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count avisos',
      one: '1 aviso',
    );
    return '$_temp0';
  }

  @override
  String get show => 'Mostrar';

  @override
  String get hide => 'Ocultar';

  @override
  String get imapServer => 'Servidor IMAP';

  @override
  String get port => 'Puerto';

  @override
  String get security => 'Seguridad';

  @override
  String get accountName => 'Nombre de la cuenta';

  @override
  String get accountColor => 'Color de la cuenta';

  @override
  String get color => 'Color';

  @override
  String get connect => 'Conectar';

  @override
  String get connecting => 'Conectando…';

  @override
  String get notNow => 'Ahora no';

  @override
  String get enterToConnect => 'para conectar';

  @override
  String get errorWrongPassword =>
      'El servidor no aceptó esta dirección y contraseña. Si tu proveedor usa contraseñas de aplicación, crea una y úsala aquí.';

  @override
  String get errorUnreachable =>
      'No se pudo contactar con el servidor. Comprueba el nombre del servidor, el puerto y tu conexión.';

  @override
  String get errorInsecure =>
      'No se pudo establecer una conexión segura con el servidor. Comprueba el nombre del servidor y la seguridad.';

  @override
  String get errorKeychain =>
      'No se pudo guardar la contraseña en el llavero del sistema.';

  @override
  String get errorOther => 'Algo salió mal al conectar. Inténtalo de nuevo.';

  @override
  String get yourAccounts => 'Tus cuentas';

  @override
  String get noAccountsYet => 'Tu primera cuenta aparecerá aquí.';

  @override
  String get connected => 'Conectada';

  @override
  String get privacyNote =>
      'Tu correo se queda en este dispositivo. Nos conectamos directamente a tus servidores, sin nadie en medio.';

  @override
  String get newMessage => 'Nuevo mensaje';

  @override
  String get close => 'Cerrar';

  @override
  String get from => 'De';

  @override
  String get to => 'Para';

  @override
  String get cc => 'Cc';

  @override
  String get bcc => 'Cco';

  @override
  String get ccBcc => 'Cc  Cco';

  @override
  String get subject => 'Asunto';

  @override
  String get messageBody => 'Mensaje';

  @override
  String get addRecipient => 'Añadir';

  @override
  String removeRecipient(String name) {
    return 'Quitar a $name';
  }

  @override
  String undoSendHint(int seconds) {
    return 'Puedes deshacer el envío durante $seconds segundos';
  }

  @override
  String get sendNoRecipients => 'Añade al menos un destinatario.';

  @override
  String sendBadAddress(String address) {
    return '“$address” no es una dirección de correo.';
  }

  @override
  String get sending => 'Enviando…';

  @override
  String get sent => 'Enviado';

  @override
  String get undo => 'Deshacer';

  @override
  String get draftDiscarded => 'Borrador descartado';

  @override
  String get sendErrorPassword =>
      'El servidor de salida no aceptó la contraseña. Tu mensaje sigue aquí.';

  @override
  String get sendErrorUnreachable =>
      'No se pudo contactar con el servidor de salida. Tu mensaje sigue aquí.';

  @override
  String get sendErrorRejected =>
      'El servidor de salida rechazó el mensaje. Tu mensaje sigue aquí.';

  @override
  String get sendErrorOther =>
      'No se pudo enviar el mensaje. Tu mensaje sigue aquí.';

  @override
  String stepOf(int step, int total) {
    return '$step de $total';
  }

  @override
  String get whatsYourEmail => '¿Cuál es tu correo?';

  @override
  String get findSettingsHint =>
      'Buscaremos la configuración del servidor por ti.';

  @override
  String get continueAction => 'Continuar';

  @override
  String get lookingUp => 'Buscando…';

  @override
  String get setUpManually => 'Configurar manualmente';

  @override
  String get back => 'Atrás';

  @override
  String get weFoundSettings => 'Hemos encontrado tu configuración';

  @override
  String get incoming => 'Entrante';

  @override
  String get outgoing => 'Saliente';

  @override
  String get incomingAndOutgoing => 'Entrante y saliente';

  @override
  String get guessedSettings =>
      'Esta es la configuración habitual para tu dominio. Si la conexión falla, revísala.';

  @override
  String get yourName => 'Tu nombre';

  @override
  String get yourNameHint =>
      'Lo ven las personas a las que escribes. Opcional.';

  @override
  String get settingsNotFound =>
      'No encontramos la configuración para esta dirección. Las páginas de ayuda de tu proveedor la indican.';

  @override
  String get smtpServer => 'Servidor SMTP';

  @override
  String get username => 'Usuario';

  @override
  String get usedForBoth => 'Se usa para el correo entrante y saliente.';

  @override
  String get verifyAndConnect => 'Verificar y conectar';

  @override
  String get archive => 'Archivar';

  @override
  String get archived => 'Archivado';

  @override
  String get movedToTrash => 'Movido a la papelera';

  @override
  String get actionFailed =>
      'No se pudo mover el mensaje. Ha vuelto a la bandeja de entrada.';

  @override
  String get replyTitle => 'Responder';

  @override
  String quoteHeader(String date, String name) {
    return 'El $date, $name escribió:';
  }

  @override
  String get search => 'Buscar…';

  @override
  String get searchAllAccounts => 'Buscar en todas las cuentas';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Sin resultados',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filtros';

  @override
  String get filterLastMonth => 'Último mes';

  @override
  String get filterAccount => 'Cuenta';

  @override
  String get searchOperators => 'Operadores';

  @override
  String get operatorNameHint => 'nombre';

  @override
  String get operatorDateHint => 'fecha';

  @override
  String get searchPeople => 'Personas';

  @override
  String get searchEmail => 'Correo';

  @override
  String personEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos',
      one: '1 correo',
    );
    return '$_temp0';
  }

  @override
  String get searchNoResults => 'No se encontró nada';

  @override
  String get searchNoResultsHint =>
      'Prueba con menos palabras u otra ortografía.';

  @override
  String get searchNoResultsFilters => 'Sin resultados con estos filtros';

  @override
  String get searchNoResultsFiltersHint =>
      'Quita un filtro u operador para ampliar la búsqueda.';

  @override
  String get clearFilters => 'Borrar filtros';

  @override
  String get searchEmptyHint =>
      'Busca en todas las cuentas por palabra, remitente o fecha, incluso sin conexión.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coincidencias',
      one: '1 coincidencia',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Abrir conversación';

  @override
  String get noMessageToShow => 'Ningún mensaje que mostrar';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts cuentas',
      one: '1 cuenta',
    );
    return 'Buscado en $_temp0 · $emails correos · $seconds s · índice local, funciona sin conexión';
  }

  @override
  String get keyMove => 'mover';

  @override
  String get keyOpen => 'abrir';

  @override
  String get privacyImagesBlocked => 'Imágenes bloqueadas';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rastreadores detenidos',
      one: '1 rastreador detenido',
    );
    return 'Imágenes bloqueadas · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Cargando imágenes…';

  @override
  String get privacyImagesLoaded => 'Imágenes cargadas';

  @override
  String get privacyImagesLoadedStopped =>
      'Imágenes cargadas · rastreadores aún detenidos';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rastreadores detenidos',
      one: '1 rastreador detenido',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enlaces limpiados',
      one: '1 enlace limpiado',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Privacidad de este mensaje';

  @override
  String get privacySheetSubtitle =>
      'El remitente no puede saber si lo abriste ni cuándo.';

  @override
  String get trackerPixel => 'Píxel de apertura';

  @override
  String get trackerFont => 'Fuente remota';

  @override
  String get trackerStyle => 'Estilo remoto';

  @override
  String get trackerLinks => 'Enlaces rastreados';

  @override
  String get trackerStopped => 'Detenido';

  @override
  String get loadImagesOnce => 'Cargar imágenes una vez';

  @override
  String get imagesAlreadyLoaded => 'Imágenes ya cargadas';

  @override
  String trustSender(String name) {
    return 'Confiar siempre en $name';
  }

  @override
  String senderTrusted(String name) {
    return '$name es de confianza';
  }

  @override
  String get alwaysBlockImages => 'Bloquear siempre las imágenes remotas';

  @override
  String get alwaysBlockImagesHint =>
      'Se aplica a todos los remitentes no de confianza';

  @override
  String get imageNotLoaded => 'Imagen no cargada';

  @override
  String get suspiciousLinkTitle => 'Revisa este enlace';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'El texto muestra $shown, pero el enlace lleva a $real.';
  }

  @override
  String get openAnyway => 'Abrir de todos modos';

  @override
  String get dontOpen => 'No abrir';

  @override
  String get riskProgram => 'Un programa que puede ejecutarse';

  @override
  String riskDisguised(String kind) {
    return 'Un programa, con nombre de $kind';
  }

  @override
  String get riskMacros => 'Tiene macros que pueden ejecutarse';

  @override
  String get riskLocked => 'Protegido con contraseña';

  @override
  String get riskOpenProgram => '¿Abrir este programa?';

  @override
  String get riskOpenFile => '¿Abrir este archivo?';

  @override
  String get riskOpenArchive => '¿Abrir este archivo comprimido?';

  @override
  String riskBodyProgram(String name) {
    return '$name es un programa. Los programas que llegan por correo pueden tomar el control de tu dispositivo. Ábrelo solo si lo esperabas.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name parece un $kind, pero es un programa. Los programas que llegan por correo pueden tomar el control de tu dispositivo. Ábrelo solo si lo esperabas.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name tiene macros, que pueden ejecutarse al abrirlo. Ábrelo solo si lo esperabas.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name está protegido con contraseña, así que nadie puede mirar dentro. Ábrelo solo si lo esperabas.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · de $email';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get backToMail => 'Volver al correo';

  @override
  String get settingsAccountsTitle => 'Cuentas';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count buzones IMAP, una sola bandeja.',
      one: 'Un buzón IMAP.',
    );
    return '$_temp0 El color indica de dónde viene cada correo.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Añadir cuenta';

  @override
  String get addAccountNote =>
      'IMAP y SMTP. Gmail, iCloud y Fastmail se configuran solos.';

  @override
  String get privacyTitle => 'Privacidad y seguridad';

  @override
  String get privacySubtitle =>
      'Todo ocurre en este dispositivo. Ningún dato sale de tu buzón.';

  @override
  String get blockImagesSetting => 'Bloquear imágenes remotas';

  @override
  String get blockImagesSettingHint =>
      'Las imágenes solo se cargan cuando lo pides.';

  @override
  String get stopPixelsSetting => 'Detener píxeles de seguimiento';

  @override
  String get stopPixelsSettingHint =>
      'Los remitentes no pueden saber si abres un mensaje ni cuándo.';

  @override
  String get cleanLinksSetting => 'Limpiar enlaces';

  @override
  String get cleanLinksSettingHint =>
      'Quita utm y parámetros de seguimiento antes de abrir.';

  @override
  String get warnLinksSetting => 'Avisar de enlaces sospechosos';

  @override
  String get warnLinksSettingHint =>
      'Pregunta antes de abrir un enlace que muestra una dirección y lleva a otra.';

  @override
  String get last30Days => 'Últimos 30 días';

  @override
  String get trackersStoppedLabel => 'rastreadores detenidos';

  @override
  String get linksCleanedLabel => 'enlaces limpiados';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious enlaces sospechosos señalados',
      one: '1 enlace sospechoso señalado',
    );
    return 'Píxeles de apertura $pixels · fuentes y estilos remotos $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Remitentes de confianza';

  @override
  String get trustedSendersHint => 'las imágenes siempre se cargan';

  @override
  String trustedSince(String email, String date) {
    return '$email · desde $date';
  }

  @override
  String get removeTrusted => 'Quitar';

  @override
  String get noTrustedSenders =>
      'Ningún remitente de confianza. Las imágenes siguen bloqueadas para todos.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Adjuntar archivo';

  @override
  String removeAttachment(String name) {
    return 'Quitar $name';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name guardado en Descargas';
  }

  @override
  String attachmentNotSaved(String name) {
    return 'No se pudo descargar $name. Comprueba la conexión e inténtalo de nuevo.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Los adjuntos pueden sumar como máximo $max. Quita alguno e inténtalo de nuevo.';
  }

  @override
  String fileNotRead(String name) {
    return 'No se pudo leer $name.';
  }

  @override
  String get folderSent => 'Enviados';

  @override
  String get folderArchive => 'Archivo';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuentas',
      one: 'Una cuenta',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'para $people · hoy a las $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'para $people · ayer a las $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'para $people · $date a las $time';
  }

  @override
  String get emptyFolder => 'Aún no hay nada aquí.';

  @override
  String threadMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes',
      one: '1 mensaje',
    );
    return '$_temp0';
  }

  @override
  String conversationSummary(int count, String people) {
    return '$count mensajes · $people';
  }

  @override
  String readMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes leídos',
      one: '1 mensaje leído',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count nuevos';
  }

  @override
  String get you => 'tú';

  @override
  String get quotedTextHidden => '··· texto citado oculto';

  @override
  String get showQuotedText => 'Mostrar texto citado';

  @override
  String get youName => 'Tú';

  @override
  String yesterdayAt(String time) {
    return 'Ayer $time';
  }

  @override
  String get pickMessage => 'Seleccionar';

  @override
  String get unpickMessage => 'Seleccionado';

  @override
  String get selectAll => 'Seleccionar todo';

  @override
  String pickedOf(int count, int total) {
    return '$count de $total seleccionados';
  }

  @override
  String get deselect => 'Deseleccionar';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversaciones seleccionadas',
      one: 'conversación seleccionada',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'de $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'de $names y $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'de $names y $count más';
  }

  @override
  String andMore(String name, int count) {
    return '$name y $count más';
  }

  @override
  String get markRead => 'Marcar como leído';

  @override
  String get markUnread => 'Marcar como no leído';

  @override
  String get hintArchive => 'archivar';

  @override
  String get hintUnread => 'no leído';

  @override
  String get hintDeselect => 'deseleccionar';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones archivadas',
      one: 'Archivado',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones movidas a la papelera',
      one: 'Movido a la papelera',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'No se pudo contactar con el servidor. Leído y no leído vuelven a estar como antes.';

  @override
  String get signaturesTitle => 'Firmas';

  @override
  String get newSignature => 'Nueva firma';

  @override
  String get newSignatureLabel => 'Nueva firma';

  @override
  String get noSignatures => 'Aún no hay firmas. Crea una con Nueva firma.';

  @override
  String get signatureTemplate => 'Plantilla';

  @override
  String get signatureLogo => 'Logotipo';

  @override
  String get signatureLabelField => 'Nombre de la firma';

  @override
  String get signatureAccount => 'Cuenta';

  @override
  String get signatureName => 'Nombre';

  @override
  String get signatureRole => 'Cargo';

  @override
  String get signatureCompany => 'Empresa';

  @override
  String get signaturePhone => 'Teléfono';

  @override
  String get signatureWebsite => 'Sitio web';

  @override
  String get signatureAccent => 'Color de acento';

  @override
  String get accentBlue => 'Acento azul';

  @override
  String get accentBlack => 'Acento negro';

  @override
  String get accentTerracotta => 'Acento terracota';

  @override
  String get signatureWhen => 'Cuándo usarla';

  @override
  String signatureForNew(String email) {
    return 'Correos nuevos de $email';
  }

  @override
  String get signatureForReplies => 'Respuestas y reenvíos';

  @override
  String get signatureNone => 'Ninguna';

  @override
  String get deleteSignature => 'Eliminar firma';

  @override
  String get signatureDeleteHint => 'Los correos ya enviados la conservan.';

  @override
  String get signaturePreview => 'Vista previa';

  @override
  String get previewLight => 'Claro';

  @override
  String get previewDark => 'Oscuro';

  @override
  String get previewText => 'Texto';

  @override
  String get signatureSampleText =>
      'Hola, Luca:\nte adjunto los archivos finales. Dime si necesitas algo más.\n\nHablamos pronto,';

  @override
  String get signatureNote =>
      'Sin imágenes: la firma llega limpia incluso donde las imágenes están bloqueadas, y la versión de texto plano se crea por ti.';

  @override
  String get signatureNoteLogo =>
      'El logotipo viaja dentro del correo (máx. 40 KB) con texto alternativo, así que nunca pide “cargar imágenes” y no rastrea a nadie. La versión de texto plano se crea por ti.';

  @override
  String get signatureUseAll => 'todo';

  @override
  String get signatureUseNew => 'correos nuevos';

  @override
  String get signatureUseReplies => 'respuestas y reenvíos';

  @override
  String get signatureUseNone => 'sin usar';

  @override
  String get templateMinimal => 'Mínima';

  @override
  String get templateClassic => 'Clásica';

  @override
  String get templateMonogram => 'Monograma';

  @override
  String get templateLogo => 'Con logotipo';

  @override
  String get noLogo => 'SIN LOGO';

  @override
  String get logoHint => 'PNG o JPEG, reducido a 40 KB automáticamente';

  @override
  String get removeLogo => 'Quitar';

  @override
  String get uploadLogo => 'Subir';

  @override
  String get logoTooBig =>
      'Este logotipo supera los 40 KB incluso reducido. Prueba con uno más sencillo.';

  @override
  String get logoNotImage => 'Elige una imagen PNG o JPEG.';

  @override
  String signatureChip(String label) {
    return 'Firma · $label';
  }

  @override
  String get noSignature => 'Sin firma';

  @override
  String get manageSignatures => 'Gestionar firmas…';

  @override
  String get signatureUsedNew => 'Correos nuevos';

  @override
  String get signatureUsedReplies => 'Respuestas';

  @override
  String get composeSignatureNote =>
      'La firma sigue a la cuenta De: su firma para correos nuevos, la corta para respuestas y reenvíos.';

  @override
  String get noticeOpen => 'Abrir';

  @override
  String get noticeChannel => 'Correo nuevo';

  @override
  String noticeTitleMany(String sender, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos',
      one: '1 correo',
    );
    return '$sender · $_temp0';
  }

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsLead => 'Pocas, y solo cuando importan.';

  @override
  String get notifyAbout => 'Avisarme de';

  @override
  String get notifyPeople => 'Solo personas';

  @override
  String get notifyPeopleHint =>
      'Correo escrito por personas. Sin boletines, recibos ni mensajes automáticos.';

  @override
  String get notifyRecommended => 'Recomendado';

  @override
  String get notifyAll => 'Todo';

  @override
  String get notifyAllHint =>
      'Cada correo nuevo que llega a la bandeja de entrada.';

  @override
  String get notifyOff => 'Nada';

  @override
  String get notifyOffHint => 'Consulta cuando quieras. Sin globos ni sonidos.';

  @override
  String get quietHours => 'Horas de silencio';

  @override
  String get quietTitle => 'Cada noche';

  @override
  String get quietHint => 'El correo sigue llegando, en silencio.';

  @override
  String get quietFrom => 'De';

  @override
  String get quietTo => 'a';

  @override
  String quietFromLabel(String time) {
    return 'Las horas de silencio empiezan a las $time';
  }

  @override
  String quietToLabel(String time) {
    return 'Las horas de silencio terminan a las $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuentas',
      one: '1 cuenta',
    );
    return 'Buscar en $_temp0';
  }

  @override
  String get phoneAccountsAll => 'Todas';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'las $count cuentas',
      one: '1 cuenta',
    );
    return 'Mostrando $_temp0';
  }

  @override
  String get composeMessage => 'Redactar un mensaje';

  @override
  String get moreActions => 'Más acciones';

  @override
  String quickReplyHint(String name) {
    return 'Responder a $name…';
  }

  @override
  String get sendReply => 'Enviar respuesta';

  @override
  String get cancel => 'Cancelar';

  @override
  String get pickAll => 'Todos';

  @override
  String get pickNone => 'Ninguno';

  @override
  String get pickRead => 'Leídos';

  @override
  String get pickUnread => 'No leídos';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'seleccionados',
      one: 'seleccionado',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'de $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count de $total seleccionados';
  }

  @override
  String get phoneSelectActions => 'Acciones sobre la selección';

  @override
  String get clearSearch => 'Borrar búsqueda';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String get settingsMail => 'Correo';

  @override
  String get settingsApp => 'Aplicación';

  @override
  String get writingTitle => 'Escritura';

  @override
  String get readingTitle => 'Lectura';

  @override
  String get readingSubtitle =>
      'Cómo se ve la lista, y lo que te ayuda a leer.';

  @override
  String get organizingTitle => 'Organización';

  @override
  String get organizingSubtitle => 'Zonas, reglas, carpetas y etiquetas.';

  @override
  String signaturesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count firmas',
      one: '1 firma',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLine => 'Código abierto · GPL-3.0';

  @override
  String get motto => 'El correo, más ligero.';

  @override
  String get appName => 'Piuma Mail';

  @override
  String phoneAccountsMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuentas',
      one: '1 cuenta',
    );
    return '$_temp0, cuentas y Ajustes';
  }

  @override
  String get allAccounts => 'Todas las cuentas';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bandejas juntas',
      one: '1 bandeja',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return 'Solo $name, cuentas y Ajustes';
  }

  @override
  String accountOnly(String name) {
    return 'Solo $name';
  }

  @override
  String get showAllAccounts => 'Mostrar todas';

  @override
  String get phoneFolders => 'Carpetas';

  @override
  String phoneSearchOne(String name) {
    return 'Buscar en $name';
  }

  @override
  String get welcomeLead =>
      'Conecta tus cuentas IMAP y léelo todo en una sola bandeja, sin ruido.';

  @override
  String get staysOnDevice => 'Tu correo se queda en tu dispositivo';

  @override
  String get editServers => 'Editar';

  @override
  String get serverHost => 'Servidor';

  @override
  String get offlineTitle => 'Estás sin conexión';

  @override
  String get offlineDetail =>
      'el correo saliente se envía cuando vuelvas a estar en línea';

  @override
  String downloadingAccount(String name) {
    return 'Descargando $name';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done de $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'La cuenta $name no puede conectarse';
  }

  @override
  String passwordChanged(String email) {
    return '¿Ha cambiado la contraseña? Ha dejado de llegar el correo de $email.';
  }

  @override
  String get signInAgain => 'Iniciar sesión de nuevo';

  @override
  String get later => 'Más tarde';

  @override
  String signInTo(String name) {
    return 'Iniciar sesión en $name';
  }

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signingIn => 'Iniciando sesión…';

  @override
  String get allCaughtUp => 'Todo al día';

  @override
  String get allCaughtUpDetail =>
      'Nadie te está esperando. El resto del día es tuyo.';

  @override
  String get countOf => 'de';

  @override
  String get draftSaved => 'Borrador guardado';

  @override
  String get draftNotSaved => 'No guardado';

  @override
  String get draftNotSavedToast => 'Borrador no guardado';

  @override
  String get reopen => 'Reabrir';

  @override
  String get discard => 'Descartar';

  @override
  String get noRecipients => 'Sin destinatarios';

  @override
  String get folderDrafts => 'Borradores';

  @override
  String accountFolders(String name) {
    return 'Carpetas de $name';
  }

  @override
  String get moveShort => 'Mover';

  @override
  String get moveTo => 'Mover a…';

  @override
  String moveToIn(String name) {
    return 'Mover a una carpeta de $name';
  }

  @override
  String get noFoldersMatch => 'Ninguna carpeta con ese nombre';

  @override
  String noOtherFolders(String name) {
    return '$name aún no tiene otras carpetas';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones movidas a $folder',
      one: 'Movido a $folder',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'Bandeja de salida · $count';
  }

  @override
  String outboxTo(String names) {
    return 'Para $names';
  }

  @override
  String get outboxWaiting => 'En espera';

  @override
  String get outboxNotSent => 'No enviado';

  @override
  String outboxRefused(String reason) {
    return 'El servidor lo rechazó: $reason';
  }

  @override
  String get inOutbox =>
      'En la bandeja de salida · se envía cuando vuelvas a estar en línea';

  @override
  String get editAction => 'Editar';

  @override
  String get backgroundTitle => 'Correo nuevo en cuanto llega';

  @override
  String get backgroundBody =>
      'Piuma permanece conectada a tus cuentas, sin ningún servidor en medio. Android te pedirá dos cosas: mostrar notificaciones y dejar que Piuma funcione en segundo plano.';

  @override
  String get newMailHeading => 'Correo nuevo';

  @override
  String get deliveryInstant => 'En cuanto llega';

  @override
  String get deliveryInstantHint => 'Mantiene un aviso silencioso en el panel';

  @override
  String get deliveryPeriodic => 'Cada 15 minutos';

  @override
  String get deliveryPeriodicHint => 'Sin aviso; Android puede esperar más';

  @override
  String get folderNewsletters => 'Boletines';

  @override
  String newslettersTileLabel(int count) {
    return 'Boletines, $count sin leer';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes min · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes min de lectura · llegó a las $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Llegó a las $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Llegó el $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes min de lectura · llegó el $date';
  }

  @override
  String get dayToday => 'hoy';

  @override
  String get dayYesterday => 'ayer';

  @override
  String get readLater => 'Leer más tarde';

  @override
  String get readLaterDone => 'Se queda sin leer';

  @override
  String get unsubscribe => 'Darse de baja';

  @override
  String unsubscribeTitle(String sender) {
    return '¿Darse de baja de $sender?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender recibe una única petición para dejar de enviar. No se abre nada, y lo que ya llegó se queda aquí.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'Se envía un mensaje desde tu cuenta a $address para pedirlo. Lo que ya llegó se queda aquí.';
  }

  @override
  String get unsubscribePage => 'Su página de baja se abre en el navegador.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender no ofrece forma de darse de baja. Muévelo a la bandeja de entrada o archiva lo que llegue.';
  }

  @override
  String get unsubscribeConfirm => 'Darse de baja';

  @override
  String get unsubscribeOpen => 'Abrir página';

  @override
  String unsubscribeDone(String sender) {
    return 'Te has dado de baja de $sender';
  }

  @override
  String get unsubscribeFailed =>
      'No se pudo dar de baja. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get alwaysInInbox => 'Siempre en la bandeja de entrada';

  @override
  String alwaysInInboxDone(String sender) {
    return 'El correo de $sender irá ahora a la bandeja de entrada';
  }

  @override
  String get newslettersArchiveNote =>
      '¿Leídos hace más de 7 días? Se archivan solos';

  @override
  String get newslettersEmpty => 'Sin boletines';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count por leer',
      one: '1 por leer',
      zero: 'Todo leído',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes minutos en total';
  }

  @override
  String newslettersNew(int count) {
    return '$count nuevos';
  }

  @override
  String get folderVault => 'Bóveda';

  @override
  String vaultTileLabel(String status) {
    return 'Bóveda, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Bóveda, $count pendientes';
  }

  @override
  String vaultDue(String when) {
    return 'Vence $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Llega $when';
  }

  @override
  String get vaultAllClear => 'Todo bien';

  @override
  String get vaultToday => 'Hoy';

  @override
  String get vaultTomorrow => 'Mañana';

  @override
  String get dayTomorrow => 'mañana';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'en $days días',
      one: 'mañana',
      zero: 'hoy',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Pedido';

  @override
  String get parcelShipped => 'Enviado';

  @override
  String get parcelTransit => 'En tránsito';

  @override
  String get parcelDelivered => 'Entregado';

  @override
  String vaultDeliveredOn(String day) {
    return 'Entregado $day';
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
    return 'Último escaneo: $place';
  }

  @override
  String get vaultDueLabel => 'Vence';

  @override
  String get vaultPaid => 'Pagado';

  @override
  String get vaultDownloadPdf => 'Descargar PDF';

  @override
  String get vaultMarkPaid => 'Marcar como pagado';

  @override
  String get vaultPaidFailed => 'No se pudo guardar. Inténtalo de nuevo.';

  @override
  String vaultFlight(String number, String date) {
    return 'Vuelo $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Asiento';

  @override
  String get vaultCode => 'Código';

  @override
  String get vaultBoardingPass => 'Tarjeta de embarque';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas',
      one: '1 persona',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'confirmado';

  @override
  String get vaultPending => 'por confirmar';

  @override
  String get vaultCancelled => 'cancelado';

  @override
  String get vaultDirections => 'Cómo llegar';

  @override
  String get vaultNotePhone =>
      'Leído en el dispositivo desde el correo original · toca una tarjeta para abrirlo';

  @override
  String get vaultEmpty =>
      'Paquetes, gastos, viajes y más aparecen aquí, leídos en este dispositivo desde sus correos.';

  @override
  String get folderAttachments => 'Adjuntos';

  @override
  String get attachmentsSubtitle =>
      'Todos los archivos que has recibido, sin abrir el correo';

  @override
  String get attachmentsAll => 'Todo';

  @override
  String get attachmentsMedia => 'Fotos y multimedia';

  @override
  String get attachmentsDocuments => 'Documentos';

  @override
  String get attachmentsSheets => 'Hojas de cálculo';

  @override
  String get attachmentsFilter => 'Filtrar por tipo';

  @override
  String get attachmentsSearch => 'Buscar archivos o remitentes';

  @override
  String get attachmentsSearchLabel => 'Buscar adjuntos';

  @override
  String get attachmentsRecent => 'Recientes';

  @override
  String get attachmentsLargest => 'Más grandes';

  @override
  String attachmentsSortLabel(String sort) {
    return 'Ordenar por: $sort';
  }

  @override
  String get attachmentsThisWeek => 'Esta semana';

  @override
  String get attachmentsEarlier => 'Antes';

  @override
  String attachmentsMeta(String name, String size, String when) {
    return 'De: $name · $size · $when';
  }

  @override
  String get attachmentsDownload => 'Descargar';

  @override
  String get attachmentsOpenEmail => 'Abrir correo';

  @override
  String get attachmentsEmail => 'Correo';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, de $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return 'Descargar $name';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'Abrir correo de $from';
  }

  @override
  String get attachmentsNoneNew => 'Nada nuevo';

  @override
  String attachmentsTileLabel(String status) {
    return 'Adjuntos, $status';
  }

  @override
  String get attachmentsEmpty =>
      'Los archivos que recibes aparecen aquí, de todas las cuentas.';

  @override
  String attachmentsNoMatch(String query) {
    return 'Ningún archivo coincide con “$query”';
  }

  @override
  String attachmentsNew(int count) {
    return '$count nuevos';
  }

  @override
  String get folderSnoozed => 'Pospuestos';

  @override
  String get snoozeUntilTitle => 'Posponer hasta…';

  @override
  String get snoozeEvening => 'Esta tarde';

  @override
  String get snoozeMorning => 'Mañana por la mañana';

  @override
  String get snoozeWeekend => 'Fin de semana';

  @override
  String get snoozeNextWeek => 'La semana que viene';

  @override
  String snoozeTileToday(String time) {
    return 'hoy $time';
  }

  @override
  String snoozeToday(String time) {
    return 'hoy, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'mañana, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'mañana $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones pospuestas hasta $when',
      one: 'Pospuesto hasta $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Volver a la bandeja';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones de vuelta en la bandeja',
      one: 'De vuelta en la bandeja',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Mañana';

  @override
  String get sectionLater => 'Más adelante';

  @override
  String get sendLater => 'Enviar más tarde';

  @override
  String get sendLaterTomorrowMorning => 'Mañana por la mañana';

  @override
  String get sendLaterTomorrowAfternoon => 'Mañana por la tarde';

  @override
  String get sendLaterMondayMorning => 'El lunes por la mañana';

  @override
  String scheduleTomorrow(String time) {
    return 'Programar para mañana a las $time';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Programar para el $day a las $time';
  }

  @override
  String get sendLaterNote =>
      'Se envía desde este dispositivo a esa hora. Si está apagado, sale en cuanto se encienda.';

  @override
  String scheduledToast(String when) {
    return 'Programado para $when';
  }

  @override
  String get paletteLabel => 'Paleta de comandos';

  @override
  String get paletteHint => 'Busca o ejecuta un comando';

  @override
  String get paletteActions => 'Acciones';

  @override
  String get paletteMessages => 'Mensajes';

  @override
  String paletteWriteTo(String name) {
    return 'Escribir a $name';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Mostrar solo mensajes de $name';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Adjuntos de $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: '1 archivo',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Buscar “$query” en todo el correo';
  }

  @override
  String paletteGoTo(String place) {
    return 'Ir a $place';
  }

  @override
  String get paletteMove => 'mover';

  @override
  String get paletteRun => 'ejecutar';

  @override
  String get paletteAnywhere => 'desde cualquier pantalla';

  @override
  String senderCardLabel(String name) {
    return 'Ficha de $name';
  }

  @override
  String get senderKind => 'Remitente';

  @override
  String get senderClose => 'Cerrar ficha';

  @override
  String get senderWrite => 'Escribir';

  @override
  String get senderAll => 'Todos los correos';

  @override
  String get senderMute => 'Silenciar';

  @override
  String get senderMuted => 'Silenciado';

  @override
  String senderArrivesIn(String account) {
    return 'Llega a $account';
  }

  @override
  String get senderConversations => 'Conversaciones';

  @override
  String get senderNoMail => 'Aún no hay correos suyos en este dispositivo.';

  @override
  String senderMutedToast(String name) {
    return 'No más notificaciones de $name';
  }

  @override
  String get rulesTitle => 'Reglas y carpetas';

  @override
  String get rulesSubtitle =>
      'Ordena tu correo como lo harías tú. Cada regla se lee como una frase.';

  @override
  String get rulesWhere =>
      'Las reglas se ejecutan en este dispositivo, sobre el correo nuevo de la bandeja de entrada';

  @override
  String get rulesHeading => 'Reglas';

  @override
  String get rulesNew => 'Nueva regla';

  @override
  String get rulesEdit => 'Editar regla';

  @override
  String get rulesNone =>
      'Aún no tienes reglas propias. Una regla ordena el correo nuevo en cuanto llega, como lo harías tú.';

  @override
  String get ruleWhen => 'Cuando';

  @override
  String get ruleThen => 'entonces';

  @override
  String get ruleFieldSender => 'el remitente';

  @override
  String get ruleFieldSubject => 'el asunto';

  @override
  String get ruleFieldRecipient => 'el destinatario';

  @override
  String get ruleOpContains => 'contiene';

  @override
  String get ruleOpIs => 'es';

  @override
  String get ruleOpStarts => 'empieza por';

  @override
  String get ruleOpNotContains => 'no contiene';

  @override
  String get ruleDoMove => 'mover a';

  @override
  String get ruleDoArchive => 'archivar';

  @override
  String get ruleDoRead => 'marcar como leído';

  @override
  String get ruleText => 'Texto que buscar';

  @override
  String get ruleTextHint => 'texto';

  @override
  String get ruleTrayField => 'Campo';

  @override
  String get ruleTrayOp => 'Condición';

  @override
  String get ruleTrayAction => 'Acción';

  @override
  String get ruleTrayFolder => 'Carpeta';

  @override
  String get rulePickFolder => 'una carpeta';

  @override
  String get ruleNoFolders => 'Tus cuentas aún no tienen carpetas propias.';

  @override
  String get ruleApplyToo => 'Aplicar también a esos';

  @override
  String get ruleSave => 'Guardar regla';

  @override
  String get ruleDelete => 'Eliminar regla';

  @override
  String get rulePaused => 'En pausa';

  @override
  String get ruleFresh => 'Activa desde ahora';

  @override
  String get foldersHeading => 'Carpetas';

  @override
  String get foldersNone => 'Sin carpetas propias';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se aplica a $count correos existentes',
      one: 'Se aplica a $count correo existente',
      zero: 'Ningún correo existente coincide',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos ordenados',
      one: '1 correo ordenado',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'último hoy $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'último $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Regla activa: $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Ninguna',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Invitación';

  @override
  String get inviteYes => 'Sí';

  @override
  String get inviteMaybe => 'Quizás';

  @override
  String get inviteNo => 'No';

  @override
  String get inviteRespond => 'Responder a la invitación';

  @override
  String get inviteAllDay => 'Todo el día';

  @override
  String get inviteRepeats => 'se repite';

  @override
  String get inviteYouAccepted => 'Has aceptado';

  @override
  String get inviteYouTentative => 'Has respondido quizás';

  @override
  String get inviteYouDeclined => 'Has rechazado';

  @override
  String get inviteNotSent =>
      'No se pudo enviar tu respuesta. Inténtalo de nuevo.';

  @override
  String get inviteCancelled => 'Este evento se ha cancelado';

  @override
  String get inviteYours => 'Enviaste esta invitación';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count asistentes',
      one: '1 asistente',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name recibirá tu respuesta';
  }

  @override
  String inviteQueued(String name) {
    return 'llega a $name cuando vuelvas a estar en línea';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name ha aceptado';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name ha respondido quizás';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name ha rechazado';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Aceptado: $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Quizás: $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Rechazado: $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name ha aceptado esta invitación.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name quizás vaya.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name ha rechazado esta invitación.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Invitación: $summary, $when';
  }

  @override
  String get inviteFree => 'Libre · sin conflictos';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Coincide con $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Disponibilidad: $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'añadido a $name';
  }

  @override
  String get settingsCalendars => 'Calendarios';

  @override
  String get calIntro =>
      'Piuma no tiene calendario propio: conecta los que ya usas. Los eventos se quedan allí.';

  @override
  String get calConnected => 'Calendarios conectados';

  @override
  String calSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orígenes',
      one: '1 origen',
    );
    return '$_temp0';
  }

  @override
  String calCalendars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calendarios',
      one: '1 calendario',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Conectar un calendario';

  @override
  String get calChoose => 'Elige desde dónde conectar';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Servidor, correo y contraseña de aplicación';

  @override
  String get calIcs => 'Suscribirse a una URL .ics';

  @override
  String get calIcsSub => 'Solo lectura, se actualiza solo';

  @override
  String get calCalDavLabel => 'Dirección de correo o servidor CalDAV';

  @override
  String get calCalDavHint =>
      'iCloud necesita una contraseña de aplicación; se guarda cifrada en el llavero del sistema.';

  @override
  String get calIcsLabel => 'URL del calendario .ics';

  @override
  String get calIcsHint =>
      'Los calendarios .ics son de solo lectura: útiles para festivos, deportes, turnos.';

  @override
  String get calUsername => 'Usuario (si no es el correo)';

  @override
  String get calPassword => 'Contraseña';

  @override
  String get calConnectButton => 'Conectar';

  @override
  String get calSubscribe => 'Suscribirse';

  @override
  String get calSuggested =>
      'Las cuentas de correo que has añadido y que ofrecen calendario se sugieren automáticamente';

  @override
  String get calHasCalendar => 'también tiene calendario';

  @override
  String get calDone => 'Conectado';

  @override
  String get calDisconnect => 'Desconectar';

  @override
  String calDisconnectLabel(String name) {
    return 'Desconectar $name';
  }

  @override
  String get calReadOnly => 'solo lectura';

  @override
  String get calInvitesTag => 'invitaciones';

  @override
  String get calShowAvailability => 'Mostrar disponibilidad';

  @override
  String get calAvailabilityShort => 'disponibilidad';

  @override
  String calAvailabilityFor(String name) {
    return 'Mostrar disponibilidad de $name';
  }

  @override
  String get calNone =>
      'Ningún calendario conectado. Las invitaciones siguen funcionando, por correo.';

  @override
  String get calWhenInvite => 'Cuando llega una invitación';

  @override
  String get calAddTo => 'Añadir a';

  @override
  String get calAddToSub => 'Dónde van las invitaciones que aceptas';

  @override
  String get calAddInvitesTo => 'Añadir invitaciones a';

  @override
  String get calNoWritable => 'Ninguno';

  @override
  String get calConflicts =>
      'Buscar conflictos en todos los calendarios conectados';

  @override
  String get calConflictsSub =>
      'Las invitaciones muestran al instante si ya estás ocupado a esa hora.';

  @override
  String get calFooter =>
      'Sin calendarios conectados puedes seguir respondiendo a las invitaciones por correo y abrir el archivo .ics.';

  @override
  String get calStaysHere =>
      'Las conexiones se quedan en este dispositivo; las contraseñas se guardan en el llavero del sistema.';

  @override
  String get calWrongPassword => 'Usuario o contraseña incorrectos.';

  @override
  String get calUnreachable =>
      'No se encontró ningún calendario ahí. Comprueba la dirección.';

  @override
  String get calFailed => 'No se pudo conectar. Inténtalo de nuevo.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => 'URL .ics, solo lectura';

  @override
  String get calFromAccount => 'de la cuenta de correo';

  @override
  String foundDateAdd(String when) {
    return 'Añadir $when al calendario';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Añadido a $calendar';
  }

  @override
  String foundDateAddLabel(String when) {
    return 'Añadir $when al calendario, encontrado en este dispositivo';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when añadido a $calendar';
  }

  @override
  String get foundOnDevice => 'Encontrado en este dispositivo';

  @override
  String get foundDateNotAdded =>
      'No se pudo añadir al calendario. Inténtalo de nuevo en un momento.';

  @override
  String get calFindDates => 'Sugerir añadir fechas encontradas en los correos';

  @override
  String get calFindDatesSub =>
      'Una pequeña sugerencia junto a la frase, nunca automática.';

  @override
  String get calOnDevice => 'en el dispositivo';

  @override
  String get inShort => 'En breve';

  @override
  String get generatedOnDevice => 'Generado en el dispositivo';

  @override
  String get yourTurn => 'Te toca:';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name escribe “$words”';
  }

  @override
  String get inShortColon => 'En breve:';

  @override
  String get onDevice => 'en el dispositivo';

  @override
  String senderBriefTopic(String topic) {
    return 'sobre todo de “$topic”';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos este mes',
      one: '1 correo este mes',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'el último espera tu respuesta';

  @override
  String get searchByType => 'Buscar por tipo';

  @override
  String get frequentContacts => 'Contactos frecuentes';

  @override
  String get recentSearches => 'Búsquedas recientes';

  @override
  String get clearRecent => 'Borrar';

  @override
  String get clearRecentSearches => 'Borrar búsquedas recientes';

  @override
  String get noRecentSearches => 'No hay búsquedas recientes.';

  @override
  String get searchOperatorsHint => 'También puedes escribir operadores';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$formatted correos indexados en este dispositivo · funciona sin conexión',
      one: '1 correo indexado en este dispositivo · funciona sin conexión',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'Con adjuntos';

  @override
  String get searchFromPeople => 'De personas';

  @override
  String searchMailFrom(String name) {
    return 'Buscar correo de $name';
  }

  @override
  String removeRecentSearch(String query) {
    return 'Quitar $query';
  }

  @override
  String get searchAddWords => 'Añadir palabras…';

  @override
  String rowPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fotos',
      one: '1 foto',
    );
    return '$_temp0';
  }

  @override
  String rowAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count adjuntos',
      one: '1 adjunto',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Bloquear';

  @override
  String get senderBlocked => 'Bloqueado';

  @override
  String showSnoozed(int count) {
    return 'Mostrar pospuestos ($count)';
  }

  @override
  String get hideSnoozed => 'Ocultar pospuestos';

  @override
  String get snoozeNoReply => 'Si nadie responde';

  @override
  String get snoozeNoReplyHint => 'Vuelve en 3 días si no hay respuesta';

  @override
  String get previewClose => 'Cerrar vista previa';

  @override
  String previewMeta(String size, String name) {
    return '$size · de $name';
  }

  @override
  String previewPage(int page, int count) {
    return 'Página $page de $count';
  }

  @override
  String get previewPrevPage => 'Página anterior';

  @override
  String get previewNextPage => 'Página siguiente';

  @override
  String previewOpenEmail(String name) {
    return 'Abrir el correo de $name';
  }

  @override
  String get previewDownloadAll => 'Descargar todo';

  @override
  String previewPhoto(int index, int count) {
    return 'Foto $index de $count · del mismo correo';
  }

  @override
  String get previewPhotos => 'Fotos del correo';

  @override
  String get previewCantShow =>
      'Este archivo no se puede mostrar aquí. Aun así puedes descargarlo.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Página $page de $name';
  }

  @override
  String get vaultParcelsTitle => 'Entregas de paquetes';

  @override
  String get vaultParcelsHint => 'El día de la entrega, solo una vez.';

  @override
  String get vaultDueTitle => 'Vencimientos';

  @override
  String get vaultDueHint =>
      'Facturas y renovaciones, con tres días de antelación.';

  @override
  String get vaultNoticeParcel => 'Tu paquete llega hoy';

  @override
  String get vaultNoticeDueToday => 'Vence hoy';

  @override
  String get vaultNoticeDueTomorrow => 'Vence mañana';

  @override
  String vaultNoticeDueIn(int days) {
    return 'Vence en $days días';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'hacia las $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos certificados',
      one: '1 correo certificado',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count no entregados',
      one: '$count no entregado',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Enviado';

  @override
  String get pecAccepted => 'Aceptado';

  @override
  String get pecDelivered => 'Entregado';

  @override
  String get pecFailed => 'No entregado';

  @override
  String pecTo(String who) {
    return 'Para $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'Para $count destinatarios · $delivered de $count entregados';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Aceptado $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Entregado $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'No entregado · $when';
  }

  @override
  String pecReasonAt(String reason, String when) {
    return '$reason · $when';
  }

  @override
  String get pecOpen => 'Abrir';

  @override
  String pecReceipt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recibos',
      one: 'Recibo',
    );
    return '$_temp0';
  }

  @override
  String pecSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recibos guardados en Descargas',
      one: 'Recibo guardado en Descargas',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'No se pudo guardar el recibo';

  @override
  String get pecNote =>
      'Los recibos no entran en la bandeja y se agrupan en el mensaje al que pertenecen. Recibo guarda la prueba firmada como archivo.';

  @override
  String get pickDateTime => 'Elegir fecha y hora';

  @override
  String get previousMonth => 'Mes anterior';

  @override
  String get nextMonth => 'Mes siguiente';

  @override
  String get pickTime => 'Hora';

  @override
  String get pickOtherTime => 'Otra hora';

  @override
  String get pickTimeGone => 'Esa hora ya ha pasado';

  @override
  String snoozeUntilAt(String when) {
    return 'Posponer hasta $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Programar para $when';
  }

  @override
  String get senderNewsletterKind => 'Boletín';

  @override
  String newsletterPerWeek(int count) {
    return 'unos $count a la semana';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'unos $count al mes';
  }

  @override
  String newsletterOpened(int percent) {
    return 'abres el $percent%';
  }

  @override
  String get newsletterUnsubscribed => 'Baja confirmada';

  @override
  String get newsletterClearAsk => '¿borrar también los correos antiguos?';

  @override
  String get newsletterClearYes => 'Sí, borrar';

  @override
  String get newsletterClearNo => 'No';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Baja confirmada · $count correos movidos a la papelera',
      one: 'Baja confirmada · 1 correo movido a la papelera',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept =>
      'Baja confirmada · los correos antiguos se quedan como están';

  @override
  String get newsletterPageOpened =>
      'Su página de baja está abierta en el navegador';

  @override
  String get moveToNewsletters => 'Mover a Boletines';

  @override
  String get movedToNewsletters => 'Movido a Boletines';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Tiene adjunto';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get appearanceSubtitle => 'Cómo quieres que se vea tu correo.';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeAutomatic => 'Automático';

  @override
  String get appearanceDensity => 'Densidad';

  @override
  String get densityComfortable => 'Cómoda';

  @override
  String get densityCompact => 'Compacta';

  @override
  String get appearancePreview => 'Vista previa';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count líneas',
      one: '1 línea',
    );
    return '$_temp0';
  }

  @override
  String get appearanceExample => 'Ejemplo';

  @override
  String get previewDrawnHere => 'Dibujado en este dispositivo';

  @override
  String get previewKeysPages => '← → páginas';

  @override
  String get previewKeysPhotos => '← → fotos';

  @override
  String get meInitials => 'YO';

  @override
  String get threadSummary => 'Resumen';

  @override
  String get signatureSheetTitle => 'Firma';

  @override
  String get signatureManage => 'Gestionar';

  @override
  String get signatureSheetNote =>
      'La firma cambia automáticamente al cambiar la cuenta “De”.';

  @override
  String get readerEmptyTitle => 'Ninguna conversación seleccionada';

  @override
  String readerEmptyHint(String keys) {
    return 'Haz clic en un mensaje para seleccionarlo, o pulsa $keys para seleccionarlos todos.';
  }

  @override
  String get hintMove => 'mover';

  @override
  String get accountConnected => 'Cuenta conectada';

  @override
  String get accountConnectedLead =>
      'Ya puedes empezar a leer: el resto llega mientras usas Piuma.';

  @override
  String get connectedDownloading => 'Descargando, los más recientes primero…';

  @override
  String get connectedUpToDate => 'Al día';

  @override
  String get goToInbox => 'Ir a la bandeja de entrada';

  @override
  String get addAnotherAccount => 'Añadir otra cuenta';

  @override
  String filterFrom(String name) {
    return 'De: $name';
  }

  @override
  String get syncLeftUnderMinute => 'menos de un minuto';

  @override
  String syncLeftMinutes(int n) {
    return 'unos $n min';
  }

  @override
  String syncLeftHours(int n) {
    return 'unas $n h';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · sincronizando $name';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Enviar mañana $time';
  }

  @override
  String get sendOptions => 'Opciones de envío';

  @override
  String get inboxSections => 'Secciones de la bandeja';

  @override
  String get tabPeople => 'Personas';

  @override
  String get tabNotifications => 'Notificaciones';

  @override
  String get zoneNothingNew => 'Nada nuevo';

  @override
  String get tabAll => 'Todos';

  @override
  String get filterUnreadHint => 'Solo los correos con algo sin leer';

  @override
  String get moveToPeople => 'Mover a Personas';

  @override
  String movedToPeople(String sender) {
    return '$sender irá a Personas a partir de ahora';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender irá a Notificaciones a partir de ahora';
  }

  @override
  String get moveToNotifications => 'Mover a Notificaciones';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count sin leer';
  }

  @override
  String get templatesTitle => 'Plantillas';

  @override
  String get templatesSearch => 'Buscar plantillas';

  @override
  String templatesFound(int found, int total) {
    return '$found de $total';
  }

  @override
  String get templatesNone =>
      'Aún no hay plantillas. Guarda lo que escribes como una.';

  @override
  String templatesNoMatch(String query) {
    return 'Ninguna plantilla llamada “$query”';
  }

  @override
  String get templateSaveThis => 'Guardar como plantilla';

  @override
  String get templatesManage => 'Gestionar';

  @override
  String get templateUntitled => 'Plantilla sin título';

  @override
  String templateSavedNote(String name) {
    return 'Guardado como plantilla “$name”';
  }

  @override
  String get templatesSubtitle => 'En este dispositivo, para todas las cuentas';

  @override
  String get templatesNew => 'Nueva plantilla';

  @override
  String get templateNameLabel => 'Nombre';

  @override
  String get templateTextLabel => 'Texto';

  @override
  String templateSubjectLine(String subject) {
    return 'Asunto: $subject';
  }

  @override
  String get templateNoSubject => 'Sin asunto';

  @override
  String get templateSavedAsYouType => 'Se guarda mientras escribes';

  @override
  String get templateNotSaved => 'No se pudo guardar la plantilla';

  @override
  String get accountNameLabel => 'Nombre';

  @override
  String get accountDisplayName => 'Nombre visible';

  @override
  String get accountDisplayNameNone => 'Sin definir';

  @override
  String get accountDefaultSignature => 'Firma predeterminada';

  @override
  String get accountConnection => 'Conexión';

  @override
  String accountWorkingAgo(String ago) {
    return 'Funciona · comprobado $ago';
  }

  @override
  String get accountJustNow => 'ahora mismo';

  @override
  String accountMinutesAgo(int count) {
    return 'hace $count min';
  }

  @override
  String accountAtTime(String time) {
    return 'a las $time';
  }

  @override
  String get accountConnecting => 'Conectando…';

  @override
  String accountCantSignInSince(String time) {
    return 'No puede iniciar sesión desde $time';
  }

  @override
  String get accountPasswordRefused =>
      'El servidor rechazó la contraseña. ¿Ha cambiado?';

  @override
  String get accountEditServers => 'Editar servidores';

  @override
  String get accountSignInAlert => 'Avisarme cuando no pueda iniciar sesión';

  @override
  String get accountSignInAlertNote =>
      'Un solo aviso, la primera vez que se rechace la contraseña';

  @override
  String get accountRemove => 'Quitar cuenta';

  @override
  String accountRemoveTitle(String name) {
    return '¿Quitar $name de este dispositivo?';
  }

  @override
  String get accountRemoveNote =>
      'Su correo se borra de aquí. En el servidor todo se queda como está.';

  @override
  String get accountRemoveConfirm => 'Quitar';

  @override
  String get accountServersTitle => 'Servidores';

  @override
  String get accountServersSave => 'Guardar';

  @override
  String get accountServersChecking => 'Comprobando…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name no puede iniciar sesión';
  }

  @override
  String get orStartFrom => 'O empieza desde';

  @override
  String needsAppPassword(String provider) {
    return '$provider necesita una contraseña de aplicación';
  }

  @override
  String get fastmailNeedsToken => 'Fastmail necesita un token de API';

  @override
  String get gmailStep1 =>
      'Activa la verificación en dos pasos en tu cuenta de Google.';

  @override
  String get gmailStep2 =>
      'Abre Contraseñas de aplicaciones y crea una llamada “Piuma”.';

  @override
  String get gmailStep3 => 'Pega aquí las 16 letras.';

  @override
  String get openAppPasswords => 'Abrir Contraseñas de aplicaciones';

  @override
  String get icloudStep1 =>
      'Activa la autenticación de doble factor en tu cuenta de Apple.';

  @override
  String get icloudStep2 =>
      'En Inicio de sesión y seguridad, abre Contraseñas específicas de apps y crea una llamada “Piuma”.';

  @override
  String get icloudStep3 => 'Pégala aquí.';

  @override
  String get openAppleAccount => 'Abrir cuenta de Apple';

  @override
  String get fastmailStep1 =>
      'En Ajustes, abre Privacidad y seguridad y luego Gestionar tokens de API.';

  @override
  String get fastmailStep2 =>
      'Crea un token llamado “Piuma” con acceso a Email y Email submission.';

  @override
  String get fastmailStep3 => 'Pégalo aquí.';

  @override
  String get openApiTokens => 'Abrir tokens de API';

  @override
  String get appPassword => 'Contraseña de aplicación';

  @override
  String get apiToken => 'Token de API';

  @override
  String get pecWhichProvider => '¿Quién gestiona tu PEC?';

  @override
  String get pecWhichProviderHint =>
      'El correo certificado viene con los servidores de su proveedor.';

  @override
  String signInToPec(String provider) {
    return 'Iniciar sesión en $provider';
  }

  @override
  String get pecStep1 => 'Usa la dirección PEC completa.';

  @override
  String get pecStep2 => 'Usa la contraseña del buzón, la misma del webmail.';

  @override
  String get verifiedSenderSetting => 'Mostrar remitente verificado';

  @override
  String get verifiedSenderSettingHint =>
      'Marca los remitentes que tu servidor de correo comprobó con DKIM, SPF y DMARC.';

  @override
  String get verifiedBadge => 'Verificado';

  @override
  String get verifiedSenderLabel => 'Remitente verificado';

  @override
  String get ruleFieldBody => 'el cuerpo';

  @override
  String get newFolder => 'Nueva carpeta';

  @override
  String get newFolderName => 'Nombre de la nueva carpeta';

  @override
  String get create => 'Crear';

  @override
  String get newFolderFailed =>
      'El servidor no creó la carpeta. Prueba con otro nombre.';

  @override
  String get groupsTitle => 'Grupos';

  @override
  String get groupsSubtitle =>
      'Reúne direcciones de distintas cuentas y dominios. Cada grupo tiene su color, su firma y, si quieres, su propia bandeja.';

  @override
  String get groupsNone =>
      'Aún no hay grupos. Un grupo reúne direcciones, incluso de cuentas distintas, bajo un color y una firma.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Ninguno',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count direcciones',
      one: '1 dirección',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Firma';

  @override
  String get groupSendFromShort => 'Enviar desde';

  @override
  String get groupNoSignature => 'Ninguna';

  @override
  String get groupName => 'Nombre del grupo';

  @override
  String get groupColor => 'Color del grupo';

  @override
  String get groupAddressesHeading => 'Direcciones';

  @override
  String get groupAccount => 'Cuenta';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return 'Cuenta $name';
  }

  @override
  String groupAliasNote(String email) {
    return 'en $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return 'Quitar $email del grupo';
  }

  @override
  String get groupAddAddress => 'Añadir dirección';

  @override
  String get groupDefaultSignature => 'Firma predeterminada';

  @override
  String get groupSendFrom => 'Enviar correos nuevos desde';

  @override
  String get groupSeparateInbox => 'Bandeja separada';

  @override
  String get groupSeparateOn =>
      'Tiene su propio elemento en la barra lateral. También sigue en la bandeja unificada.';

  @override
  String get groupSeparateOff =>
      'Sus correos solo están en la bandeja unificada.';

  @override
  String get groupNotifyOn => 'Sigue tus reglas de notificaciones.';

  @override
  String get groupNotifyOff => 'Sin avisos para este grupo.';

  @override
  String get groupReplyAsWritten =>
      'Responder siempre desde la dirección a la que escribieron';

  @override
  String groupReplyOn(String email) {
    return 'Si alguien escribe a $email, tu respuesta sale de $email, con la firma de ese grupo.';
  }

  @override
  String get groupReplyOnAny =>
      'Si alguien escribe a uno de tus alias, tu respuesta sale de él, con la firma de su grupo.';

  @override
  String get groupReplyOff =>
      'Las respuestas salen de la dirección predeterminada del grupo.';

  @override
  String get groupNew => 'Nuevo grupo';

  @override
  String get groupNewName => 'Nuevo grupo';

  @override
  String get groupDelete => 'Eliminar grupo';

  @override
  String groupDeleteAsk(String name) {
    return '¿Eliminar $name?';
  }

  @override
  String get groupDeleteNote =>
      'Sus direcciones se quedan en sus cuentas; solo se elimina el grupo.';

  @override
  String get groupYourAddresses => 'Tus direcciones';

  @override
  String get groupMovesHere => 'En otro grupo: se mueve aquí';

  @override
  String get groupFoundInSent => 'Encontrada en tu correo enviado';

  @override
  String get groupNewAlias => 'Nuevo alias';

  @override
  String get groupNewAliasHint => 'nombre@dominio.com';

  @override
  String get groupAliasOn => 'en';

  @override
  String get groupAddAlias => 'Añadir';

  @override
  String get groupAliasInvalid => 'Eso no parece una dirección de correo.';

  @override
  String get fromAutomatic => 'Automático';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Elegida porque $name escribió a $email';
  }

  @override
  String rowWrittenTo(String email) {
    return 'a $email';
  }

  @override
  String get groupsAll => 'Todos los grupos';

  @override
  String groupExpand(String name) {
    return 'Expandir $name';
  }

  @override
  String groupCollapse(String name) {
    return 'Contraer $name';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses direcciones',
      one: '1 dirección',
    );
    return '$_temp0 · $unread sin leer';
  }

  @override
  String groupsAllLine(int groups, int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups grupos',
      one: '1 grupo',
    );
    String _temp1 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses direcciones',
      one: '1 dirección',
    );
    return '$_temp0 · $_temp1 · $unread sin leer';
  }

  @override
  String groupOnly(String email) {
    return 'Solo $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Solo $email. Mostrar todo el grupo';
  }

  @override
  String get groupSheetTitle => 'Mostrar';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses direcciones',
      one: '1 dirección',
    );
    String _temp1 = intl.Intl.pluralLogic(
      groups,
      locale: localeName,
      other: '$groups grupos',
      one: '1 grupo',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get groupSheetLabel => 'Elegir grupo';

  @override
  String get groupManage => 'Gestionar grupos';

  @override
  String get groupTitleAll => 'Grupo: todos. Cambiar grupo';

  @override
  String groupTitleOne(String name) {
    return 'Grupo: $name. Cambiar grupo';
  }

  @override
  String get syncTitle => 'Dispositivos y sincronización';

  @override
  String get syncSubtitle =>
      'Tus ajustes en todos tus dispositivos, con cifrado de extremo a extremo';

  @override
  String get syncOff => 'Desactivada · solo este dispositivo';

  @override
  String get syncOffBody =>
      'Ten tus cuentas, grupos, firmas y ajustes en todos tus dispositivos. Se cifran aquí y se guardan en una carpeta oculta de uno de tus buzones. Sin servidor.';

  @override
  String get syncOffNote =>
      'Las contraseñas solo viajan dentro de la copia cifrada.';

  @override
  String get syncStoreIn => 'Guardarla en';

  @override
  String get syncMailbox => 'Buzón de sincronización';

  @override
  String get syncMoving => 'Moviendo…';

  @override
  String get syncFailTaken =>
      'Ese buzón ya contiene otro espacio de sincronización.';

  @override
  String get syncTurnOn => 'Activar sincronización';

  @override
  String get syncAllSynced => 'Todo sincronizado';

  @override
  String get syncNotYet => 'Aún no sincronizado';

  @override
  String syncOnBody(String name) {
    return 'Cuentas, grupos, firmas y ajustes se cifran y se guardan en tu buzón de $name. Sin servidor.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · carpeta oculta · cifrado de extremo a extremo';
  }

  @override
  String get syncDevices => 'Dispositivos vinculados';

  @override
  String get syncThisDevice => 'Este dispositivo';

  @override
  String get syncActiveNow => 'Activo ahora';

  @override
  String syncActive(String ago) {
    return 'Activo $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count horas',
      one: 'hace 1 hora',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'ayer';

  @override
  String syncDaysAgo(int count) {
    return 'hace $count días';
  }

  @override
  String get syncUnlink => 'Desvincular';

  @override
  String syncUnlinkName(String name) {
    return 'Desvincular $name';
  }

  @override
  String syncUnlinkAsk(String name) {
    return '¿Desvincular $name?';
  }

  @override
  String get syncUnlinkNote =>
      'Conserva lo que tiene ahora, pero ya no recibirá cambios. Tu frase de recuperación también cambia: anotarás la nueva.';

  @override
  String get syncLinkNew => 'Vincular un dispositivo nuevo';

  @override
  String syncLinkBody(String email) {
    return 'En el dispositivo nuevo, abre Piuma, elige “Ya uso Piuma en otro dispositivo” e inicia sesión en $email. Mostrará 6 cifras, y este dispositivo te las pedirá.';
  }

  @override
  String get syncLinkWaiting => 'Esperando al dispositivo nuevo…';

  @override
  String get syncLinkScan =>
      'En el teléfono nuevo, abre Piuma, elige “Ya uso Piuma en otro dispositivo” y escanea este código.';

  @override
  String get syncLinkQrLabel => 'Código QR para vincular un dispositivo nuevo';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · código nuevo en $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return '¿Sin cámara? Inicia sesión en $email en el dispositivo nuevo: mostrará 6 cifras, y este dispositivo te las pedirá.';
  }

  @override
  String syncLinked(String name) {
    return '$name vinculado';
  }

  @override
  String get syncPhraseRow => 'Frase de recuperación';

  @override
  String get syncPhraseRowLine =>
      'Abre tu espacio si pierdes todos los dispositivos';

  @override
  String get syncShow => 'Mostrar';

  @override
  String get syncPhraseTitle => 'Tu frase de recuperación';

  @override
  String get syncPhraseBody =>
      'Si pierdes todos tus dispositivos, estas 24 palabras son la única forma de volver a tu espacio. Escríbelas en papel y guárdalas bien. Piuma no puede recuperarlas por ti.';

  @override
  String get syncPhraseNewTitle => 'Tu nueva frase de recuperación';

  @override
  String syncPhraseNewBody(String name) {
    return '$name ya no puede abrir tu espacio, y la frase anterior ya no sirve. Escribe en papel estas 24 palabras en su lugar.';
  }

  @override
  String get syncPhraseWarn =>
      'Quien tenga estas palabras puede leer tu espacio.';

  @override
  String get syncPhraseDone => 'Ya las he anotado';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Un teléfono nuevo quiere conectarse',
      'tablet': 'Una tableta nueva quiere conectarse',
      'other': 'Un ordenador nuevo quiere conectarse',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · lo pidió $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Introduce las 6 cifras que muestra el teléfono.',
      'tablet': 'Introduce las 6 cifras que muestra la tableta.',
      'other': 'Introduce las 6 cifras que muestra el ordenador.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'Las 6 cifras';

  @override
  String get syncNotMe => 'No soy yo';

  @override
  String get syncApprove => 'Aprobar';

  @override
  String get syncApproving => 'Aprobando…';

  @override
  String syncFailOffline(String email) {
    return 'No se pudo contactar con $email. Inténtalo de nuevo cuando tengas conexión.';
  }

  @override
  String get syncFailExpired =>
      'La solicitud ha caducado. Pídela de nuevo desde el dispositivo nuevo.';

  @override
  String get syncFailOther => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get syncRowOn => 'Activada';

  @override
  String get syncRowOff => 'Desactivada';

  @override
  String get pairAlready => 'Ya uso Piuma en otro dispositivo';

  @override
  String get pairAlreadyOn =>
      'Inicia sesión en uno de tus buzones. Si contiene tu espacio, después vincularás este dispositivo.';

  @override
  String get pairLinkTitle => 'Vincular este teléfono';

  @override
  String get pairLinkBody =>
      'En el ordenador, abre Ajustes › Dispositivos y sincronización › Vincular un dispositivo nuevo y escanea el código que muestra.';

  @override
  String get pairScan => 'Escanear código';

  @override
  String get pairSignInInstead => 'Iniciar sesión';

  @override
  String get pairScanHint => 'Apunta al código del ordenador';

  @override
  String get pairScanWhere =>
      'Ajustes › Dispositivos y sincronización › Vincular un dispositivo nuevo';

  @override
  String get pairNoCamera =>
      'Piuma no puede usar la cámara. Permítelo en los ajustes del sistema o inicia sesión.';

  @override
  String get pairLastStep => 'Un último paso';

  @override
  String get pairLastStepBody =>
      'Inicia sesión en el buzón que guarda tu espacio. Las otras cuentas llegan solas.';

  @override
  String get pairConfirmsOwn =>
      'El ordenador lo confirma solo: es él quien te mostró el código.';

  @override
  String get pairLink => 'Vincular';

  @override
  String get pairLinking => 'Vinculando…';

  @override
  String get pairFoundTitle => 'Hemos encontrado tu espacio';

  @override
  String pairFoundBody(String email) {
    return 'El buzón $email contiene una copia cifrada de tus ajustes. Solo tus dispositivos pueden leerla.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'cuentas',
      one: 'cuenta',
    );
    return '$_temp0';
  }

  @override
  String pairGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'grupos',
      one: 'grupo',
    );
    return '$_temp0';
  }

  @override
  String pairSignatures(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'firmas',
      one: 'firma',
    );
    return '$_temp0';
  }

  @override
  String pairEncrypted(String when) {
    return 'Cifrado de extremo a extremo · actualizado $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'Por seguridad, confirma desde un dispositivo ya vinculado: $name, activo $ago.';
  }

  @override
  String get pairShowCode => 'Mostrar código';

  @override
  String get pairUsePhrase => 'Usar frase de recuperación';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Confirma en tu teléfono',
      'tablet': 'Confirma en tu tableta',
      'other': 'Confirma en tu ordenador',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Abre Piuma en $name e introduce el código.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Código $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Caduca en $time';
  }

  @override
  String pairWaiting(String name) {
    return 'Esperando a que $name confirme…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name mostrará “$title”';
  }

  @override
  String get pairStep2 => 'Introduce las 6 cifras y toca Aprobar';

  @override
  String get pairExpired => 'El código ha caducado.';

  @override
  String pairRefused(String name) {
    return '$name dijo que no eras tú.';
  }

  @override
  String get pairWrongCode => 'El código introducido allí no era este.';

  @override
  String get pairNewCode => 'Mostrar un código nuevo';

  @override
  String get pairPhraseTitle => 'Frase de recuperación';

  @override
  String get pairPhraseBody =>
      'Escribe las 24 palabras que anotaste, en orden, separadas por espacios.';

  @override
  String pairPhraseCount(int count) {
    return '$count de 24 palabras';
  }

  @override
  String get pairPhraseWrong =>
      'Estas palabras no abren tu espacio. Revísalas e inténtalo de nuevo.';

  @override
  String get pairContinue => 'Continuar';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Teléfono vinculado',
      'tablet': 'Tableta vinculada',
      'other': 'Ordenador vinculado',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody => 'Esto es lo que ha llegado de tu espacio cifrado.';

  @override
  String get pairDoneAccounts => 'Cuentas';

  @override
  String get pairDoneGroups => 'Grupos';

  @override
  String get pairDoneSettings => 'Firmas y ajustes sincronizados';

  @override
  String get pairSynced => 'Sincronizado';

  @override
  String pairStepOf(int step) {
    return 'Paso $step de 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'hoy a las $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'ayer a las $time';
  }

  @override
  String pairOnDay(String day) {
    return 'el $day';
  }

  @override
  String get keyOpenWindow => 'abrir en una ventana nueva';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizado en $count dispositivos',
      one: 'Sincronizado en 1 dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters => 'Cuando un boletín se leyó hace más de 7 días';

  @override
  String get ruleBuiltIn => 'Integrada · todas las cuentas';

  @override
  String get syncTurnOff => 'Desactivar la sincronización en este dispositivo';

  @override
  String get syncTurnOffAsk =>
      '¿Desactivar la sincronización en este dispositivo?';

  @override
  String syncTurnOffOne(String name) {
    return 'Este dispositivo sale de tu espacio y deja de recibir cambios. Sus cuentas y su correo se quedan aquí. $name sigue sincronizando.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'Este dispositivo sale de tu espacio y deja de recibir cambios. Sus cuentas y su correo se quedan aquí. $names siguen sincronizando.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'Este dispositivo sale de tu espacio y deja de recibir cambios. Sus cuentas y su correo se quedan aquí. Es tu único dispositivo: la copia cifrada en $email también se elimina.';
  }

  @override
  String get syncTurnOffButton => 'Desactivar sincronización';

  @override
  String get listAnd => 'y';

  @override
  String get composeDropFiles => 'Suelta para adjuntar';

  @override
  String get serverType => 'Tipo de servidor';

  @override
  String get imapAndSmtp => 'IMAP y SMTP';

  @override
  String get jmapServer => 'Servidor JMAP';

  @override
  String get jmapServerHint =>
      'El nombre del servidor, o la dirección completa de su sesión JMAP.';

  @override
  String get jmapSignsIn =>
      'Un solo servidor lee, envía y trae el correo nuevo. Inicias sesión con tu dirección.';

  @override
  String get shortcutsTitle => 'Atajos';

  @override
  String shortcutsLine(String keys) {
    return 'Solo lo esencial. Todo lo demás está en $keys.';
  }

  @override
  String get shortcutsTable => 'Atajos de teclado';

  @override
  String get shortcutPalette => 'Paleta de comandos';

  @override
  String ruleSuggest(String name, String folder) {
    return 'Sueles mover los correos de $name a $folder. ¿Crear una regla?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sugerido en el dispositivo · $count movimientos en el último mes',
      one: 'Sugerido en el dispositivo · 1 movimiento en el último mes',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Reenviar';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Mensaje reenviado ----------\nDe: $from\nFecha: $date\nPara: $to\nAsunto: $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date a las $time';
  }

  @override
  String get folderWaiting => 'En espera';

  @override
  String waitingSummary(int count) {
    return '$count enviados · aún sin respuesta';
  }

  @override
  String get waitingNoReply => 'Aún sin respuesta';

  @override
  String get waitingTo => 'Para ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'hoy';

  @override
  String get waitingYesterday => 'ayer';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos enviados esperan respuesta',
      one: '1 correo enviado espera respuesta',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Escribir de nuevo';

  @override
  String get stopWaiting => 'Dejar de esperar';

  @override
  String get stoppedWaiting => 'Fuera de En espera. Se queda en Enviados.';

  @override
  String get remindMe => 'Recordármelo';

  @override
  String get remindTitle => 'Recordármelo si nadie responde';

  @override
  String get remindTomorrow => 'Mañana';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'En $count días',
      one: 'En 1 día',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'La semana que viene';

  @override
  String get remindPickDate => 'Elegir una fecha…';

  @override
  String get remindNever => 'No recordármelo';

  @override
  String remindChipToday(String time) {
    return 'Recordármelo a las $time';
  }

  @override
  String get remindChipTomorrow => 'Recordármelo mañana';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Recordármelo en $count días',
      one: 'Recordármelo en 1 día',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Recordármelo el $date';
  }

  @override
  String remindAt(String when) {
    return 'Recordármelo $when';
  }

  @override
  String remindNoReply(String name) {
    return 'Sin respuesta de $name';
  }

  @override
  String get remindSentToday => 'enviado hoy';

  @override
  String get remindSentYesterday => 'enviado ayer';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'enviado hace $count días',
      one: 'enviado hace 1 día',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Adjuntos compartidos';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count adjuntos',
      one: '1 adjunto',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles => 'Aún no hay adjuntos suyos.';

  @override
  String get senderAddresses => 'Direcciones';

  @override
  String senderAddressNote(String account, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos',
      one: '1 correo',
    );
    return '$account · $_temp0';
  }

  @override
  String get senderCopyAddress => 'Copiar dirección';

  @override
  String get senderRules => 'Reglas y carpetas';

  @override
  String get senderContent => 'Contenido del remitente';

  @override
  String folderReorder(String name) {
    return 'Arrastra para reordenar $name';
  }

  @override
  String get folderMoveUp => 'Subir';

  @override
  String get folderMoveDown => 'Bajar';

  @override
  String get ruleUnopenedNewsletters => 'Boletines';

  @override
  String get ruleUnopenedFor => ' sin abrir durante ';

  @override
  String get ruleUnopenedDays => '30 días';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos archivados',
      one: '1 correo archivado',
      zero: 'todas las cuentas',
    );
    return 'Cada noche · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'Las reglas se ejecutan en este dispositivo y se sincronizan en todos tus dispositivos';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'Las reglas se ejecutan en este dispositivo y se sincronizan en todos tus dispositivos · actualizado $ago';
  }

  @override
  String get calSynced =>
      'Las conexiones se sincronizan en todos tus dispositivos; las contraseñas viajan cifradas y se quedan en el llavero del sistema.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'se actualiza cada $count horas',
      one: 'se actualiza cada hora',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'se actualiza cada $count días',
      one: 'se actualiza a diario',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'se actualiza cada semana';

  @override
  String get showOriginalLayout => 'Mostrar diseño original';

  @override
  String get originalLayout => 'Diseño original';

  @override
  String get originalLayoutBar =>
      'Diseño original · imágenes y enlaces siguen tus ajustes de privacidad';

  @override
  String get backToReadingView => 'Volver a la vista de lectura';

  @override
  String get readingView => 'Vista de lectura';

  @override
  String get replyFromLabel => 'Responder desde';

  @override
  String get senderReadsNoReplies => 'Este remitente no lee las respuestas';

  @override
  String replyFromSignature(String name) {
    return 'firma $name';
  }

  @override
  String get noticeReplyHint => 'Escribe una respuesta…';

  @override
  String get labelsHeading => 'Etiquetas';

  @override
  String get labelsSection => 'ETIQUETAS';

  @override
  String get labelAction => 'Etiqueta';

  @override
  String get labelAdd => '+ Etiqueta';

  @override
  String get labelNew => 'Nueva etiqueta';

  @override
  String get labelFind => 'Busca o crea una etiqueta';

  @override
  String labelCreate(String name) {
    return 'Crear “$name”';
  }

  @override
  String labelRemove(String name) {
    return 'Quitar la etiqueta $name';
  }

  @override
  String labelEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos',
      one: '1 correo',
    );
    return '$_temp0';
  }

  @override
  String labelAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuentas',
      one: '1 cuenta',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account no guarda etiquetas en el servidor, así que sus etiquetas se quedan en este dispositivo.';
  }

  @override
  String get hintLabel => 'etiqueta';

  @override
  String get labelName => 'Nombre de la etiqueta';

  @override
  String get labelEdit => 'Editar etiqueta';

  @override
  String get labelSave => 'Guardar';

  @override
  String get labelCreateButton => 'Crear';

  @override
  String get labelDelete => 'Eliminar etiqueta';

  @override
  String get labelDeleteNote =>
      'Se quita de todos los correos; los correos se quedan donde están.';

  @override
  String get labelColorAmber => 'Ámbar';

  @override
  String get labelColorTeal => 'Verde azulado';

  @override
  String get labelColorCoral => 'Coral';

  @override
  String get labelColorBlue => 'Azul';

  @override
  String get labelColorViolet => 'Violeta';

  @override
  String get labelMenu => 'Etiqueta…';

  @override
  String get ruleDoLabel => 'etiquetar';

  @override
  String get ruleTrayLabel => 'Etiqueta';

  @override
  String get rulePickLabel => 'una etiqueta';

  @override
  String get ruleNoLabels =>
      'Aún no hay etiquetas: crea una con + Etiqueta en Carpetas y etiquetas.';

  @override
  String get foldersAndLabelsHeading => 'Carpetas y etiquetas';

  @override
  String get labelsCardTitle => 'Etiquetas';

  @override
  String get labelsCardDetail => 'compartidas entre todas las cuentas';

  @override
  String get labelsNone => 'Aún no hay etiquetas.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carpetas',
      one: '1 carpeta',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count etiquetas',
      one: '1 etiqueta',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Fotos de remitentes';

  @override
  String get senderPicturesSettingHint =>
      'Fotos de tus contactos y logotipos verificados de empresas en lugar de las letras.';

  @override
  String get websiteIconsSetting => 'Iconos de sitios web';

  @override
  String get websiteIconsSettingHint =>
      'Para empresas sin logotipo. Cada sitio web ve tu dirección IP una vez.';

  @override
  String tabletInboxUnread(int count) {
    return 'Bandeja de entrada, $count sin leer';
  }

  @override
  String tabletAccount(String name, String email) {
    return 'Cuenta $name, $email';
  }

  @override
  String get tabletSearch => 'Buscar correo';

  @override
  String get tabletSearchHint => 'Busca o ejecuta un comando';

  @override
  String get vaultTrackParcel => 'Seguir paquete';

  @override
  String get vaultTrackingCopied => 'Número de seguimiento copiado';

  @override
  String get vaultNeedsYou => 'Te necesita';

  @override
  String get vaultNext => 'Próximo';

  @override
  String get vaultOnTheWay => 'En camino';

  @override
  String get vaultEverything => 'Todo';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cosas te necesitan',
      one: '1 cosa te necesita',
    );
    return '$_temp0';
  }

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'un vuelo hoy',
      'train': 'un tren hoy',
      'ferry': 'un ferri hoy',
      'bus': 'un autobús hoy',
      'stay': 'un check-in hoy',
      'parking': 'aparcamiento hoy',
      'car': 'un coche de alquiler hoy',
      'event': 'un evento hoy',
      'table': 'una mesa hoy',
      'other': 'una reserva hoy',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Vuelo',
      'train': 'Tren',
      'ferry': 'Ferri',
      'bus': 'Autobús',
      'stay': 'Check-in',
      'parking': 'Aparcamiento',
      'car': 'Coche de alquiler',
      'event': 'Evento',
      'table': 'Mesa',
      'other': 'Reserva',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Paquetes';

  @override
  String get vaultCatSpending => 'Gastos';

  @override
  String get vaultCatTrips => 'Viajes';

  @override
  String get vaultCatSales => 'Ventas';

  @override
  String get vaultCatSubscriptions => 'Suscripciones';

  @override
  String get vaultCatReturns => 'Devoluciones y garantía';

  @override
  String get vaultCatDeadlines => 'Plazos';

  @override
  String get vaultCatBookings => 'Reservas';

  @override
  String get vaultCatVouchers => 'Tarjetas regalo y códigos';

  @override
  String get vaultCatDocuments => 'Documentos';

  @override
  String get vaultCatCertified => 'Correo certificado';

  @override
  String vaultOnWayCount(int count) {
    return '$count en camino';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count por recoger';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entregados',
      one: '1 entregado',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'De viaje ahora';

  @override
  String vaultNextWhen(String when) {
    return 'Próximo: $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viajes pasados',
      one: '1 viaje pasado',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count por enviar';
  }

  @override
  String vaultSoldCount(int count) {
    return '$count vendidos';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money al mes';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count planes',
      one: '1 plan',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devoluciones, la primera hasta el $day',
      one: '1 devolución hasta el $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count en garantía';
  }

  @override
  String vaultCodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count códigos',
      one: '1 código',
    );
    return '$_temp0';
  }

  @override
  String vaultCountMoney(int count, String money) {
    return '$count · $money';
  }

  @override
  String vaultCertDelivered(int count) {
    return '$count entregados';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Pago fallido · $who';
  }

  @override
  String get vaultPaymentFailed => 'Pago fallido';

  @override
  String vaultWasDue(String when) {
    return 'Vencía $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'Enviar antes de $when';
  }

  @override
  String get vaultToShip => 'Por enviar';

  @override
  String get vaultYouSend => 'Envías tú';

  @override
  String vaultSoldOn(String where) {
    return 'vendido en $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'Recoger antes de $when';
  }

  @override
  String get vaultReadyPickup => 'Listo para recoger';

  @override
  String vaultRenewsWhen(String when) {
    return 'Se renueva $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Termina $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money a la semana',
      'month': '$money al mes',
      'year': '$money al año',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'desde $day';
  }

  @override
  String get vaultUpdatePayment => 'Actualizar pago';

  @override
  String get vaultCoach => 'Coche';

  @override
  String get vaultTicket => 'Billete';

  @override
  String vaultInHours(int hours) {
    return 'en $hours h';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'en $minutes min';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paquetes entregados esta semana',
      one: '1 paquete entregado esta semana',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Gastado en $month';
  }

  @override
  String vaultReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recibos',
      one: '1 recibo',
    );
    return '$_temp0';
  }

  @override
  String get vaultExportMonth => 'Exportar mes';

  @override
  String vaultSpentTab(String money) {
    return 'Gastado · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Ingresos · $money';
  }

  @override
  String vaultVia(String service) {
    return 'con $service';
  }

  @override
  String get vaultSpendingNote =>
      'Leído en el dispositivo desde recibos y facturas';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file y $count PDF guardados en Descargas',
      one: '$file y 1 PDF guardados en Descargas',
      zero: '$file guardado en Descargas',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'No se pudo exportar el mes';

  @override
  String get vaultPrevMonth => 'Mes anterior';

  @override
  String get vaultNextMonth => 'Mes siguiente';

  @override
  String get vaultNothingThisMonth => 'No hay recibos este mes.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Suscripciones · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Fecha,Quién,Qué,Importe,Moneda,Pagado con,Archivo,Número de IVA';

  @override
  String vaultComingUp(int count) {
    return '$count próximos';
  }

  @override
  String get vaultNoTrips => 'No hay viajes por delante';

  @override
  String get vaultPastTrips => 'Viajes pasados';

  @override
  String vaultThisYear(int count) {
    return '$count este año';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'Ahora · vuelta $when';
  }

  @override
  String get vaultLegDone => 'Hecho';

  @override
  String vaultUntilTime(String time) {
    return 'Hasta las $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Hasta el $day';
  }

  @override
  String get vaultTripsNote =>
      'Trenes, ferris, vuelos, alojamientos, aparcamientos y entradas';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count noches',
      one: '1 noche',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'desde las $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'coche $coach, asiento $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'asiento $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'código $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Vuelo $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Vendido en $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Vendido en $who';
  }

  @override
  String get vaultSaleOnWay => 'En camino';

  @override
  String get vaultSaleReceived => 'Recibido';

  @override
  String get vaultPaidOut => 'Cobrado';

  @override
  String get vaultCanGoBack => 'Aún se puede devolver';

  @override
  String get vaultUnderWarranty => 'En garantía';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days días para devolver';
  }

  @override
  String vaultBought(String day) {
    return 'comprado $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Garantía $month';
  }

  @override
  String get vaultCodeCopied => 'Código copiado';

  @override
  String get vaultCopyCode => 'Copiar código';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Nómina',
      'statement': 'Extracto',
      'tax': 'Documento fiscal',
      'contract': 'Contrato',
      'other': 'Documento',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Abrir archivo';

  @override
  String vaultBookingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reservas',
      one: '1 reserva',
    );
    return '$_temp0';
  }

  @override
  String vaultDocumentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count documentos',
      one: '1 documento',
    );
    return '$_temp0';
  }

  @override
  String get vaultCategoryEmpty => 'Nada por aquí ahora mismo.';

  @override
  String get vaultFlagged => 'te necesita';

  @override
  String get suggestWroteTo => 'Escribiste a';

  @override
  String get suggestWroteToYou => 'Te escribió';

  @override
  String get readerEmptyTap => 'Toca un mensaje para leerlo.';

  @override
  String get noticeAwayTitle => 'Mientras no estabas';

  @override
  String noticeAwayEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos',
      one: '1 correo',
    );
    return '$_temp0';
  }

  @override
  String noticeAwayPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de personas',
      one: '1 de una persona',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Fines de semana, todo el día';

  @override
  String get quietWeekendsHint => 'Sábado y domingo';

  @override
  String get quietWhile => 'Durante el silencio';

  @override
  String get quietWhileHint => 'Sin avisos lo resume todo al final';

  @override
  String get quietNoSound => 'Sin sonido';

  @override
  String get quietNoNotices => 'Sin avisos';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · suena como siempre';
  }

  @override
  String get quietAccountsHint =>
      'Las cuentas desactivadas suenan como siempre en las horas de silencio.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'árabe',
      'bg': 'búlgaro',
      'ca': 'catalán',
      'cs': 'checo',
      'zh': 'chino',
      'da': 'danés',
      'de': 'alemán',
      'el': 'griego',
      'en': 'inglés',
      'et': 'estonio',
      'fi': 'finés',
      'fr': 'francés',
      'he': 'hebreo',
      'hi': 'hindi',
      'hr': 'croata',
      'hu': 'húngaro',
      'id': 'indonesio',
      'it': 'italiano',
      'ja': 'japonés',
      'ko': 'coreano',
      'lt': 'lituano',
      'lv': 'letón',
      'nl': 'neerlandés',
      'nb': 'noruego',
      'pl': 'polaco',
      'pt': 'portugués',
      'ro': 'rumano',
      'ru': 'ruso',
      'sk': 'eslovaco',
      'sl': 'esloveno',
      'es': 'español',
      'sr': 'serbio',
      'sv': 'sueco',
      'th': 'tailandés',
      'tr': 'turco',
      'uk': 'ucraniano',
      'vi': 'vietnamita',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Escrito en $language';
  }

  @override
  String get translateAction => 'Traducir';

  @override
  String translateGetting(String from, String to) {
    return 'Obteniendo $from–$to';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return 'Obteniendo $from–$to · $size';
  }

  @override
  String get translating => 'Traduciendo…';

  @override
  String translatedFrom(String language) {
    return 'Traducido del $language · en este dispositivo';
  }

  @override
  String get translatedShort => 'Traducido';

  @override
  String get translateShowOriginal => 'Mostrar original';

  @override
  String get translateOriginalShort => 'Original';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'Para traducir, descarga primero $from y $to.';
  }

  @override
  String get translateFailed =>
      'No se pudo traducir este correo. Inténtalo de nuevo.';

  @override
  String get appearanceTranslateInto => 'Traducir a';

  @override
  String get translateIntoApp => 'Idioma de la app';

  @override
  String get translateIntoHint =>
      'Los correos en otros idiomas ofrecen Traducir. Ocurre en este dispositivo.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Quitar';

  @override
  String translateRemovePair(String pair) {
    return 'Quitar $pair';
  }

  @override
  String get printEmail => 'Imprimir…';

  @override
  String printTooltip(String keys) {
    return 'Imprimir… $keys';
  }

  @override
  String get printOrSavePdf => 'Imprimir o guardar como PDF';

  @override
  String get reportSpam => 'Marcar como spam';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones marcadas como spam',
      one: 'Marcado como spam',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'No es spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversaciones movidas a Bandeja de entrada',
      one: 'Movido a Bandeja de entrada',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Fecha';

  @override
  String printAttachments(String files) {
    return 'Adjuntos: $files';
  }

  @override
  String get helpTitle => 'Ayuda y comentarios';

  @override
  String get helpSubtitle =>
      'Informa de un problema o sugiere una idea. Nada se envía sin ti.';

  @override
  String get reportProblem => 'Informar de un problema';

  @override
  String get reportThisProblem => 'Informar de este problema';

  @override
  String get reportCantAddAccount => 'No puedo añadir mi cuenta';

  @override
  String get suggestIdea => 'Sugerir una idea';

  @override
  String get shakeToReport => 'Agitar para informar';

  @override
  String get shakeToReportHint => 'Agita el teléfono en cualquier pantalla';

  @override
  String get yourReports => 'Tus informes';

  @override
  String get reportNone => 'Aún no hay informes.';

  @override
  String get reportTitle => 'Informe';

  @override
  String get reportKindProblem => 'Problema';

  @override
  String get reportKindIdea => 'Idea';

  @override
  String get reportTitleField => 'Título';

  @override
  String get reportTitleHint => 'En pocas palabras';

  @override
  String get reportProblemField => 'Qué ha pasado';

  @override
  String get reportIdeaField => 'Qué y por qué';

  @override
  String get reportDescriptionHint => 'Qué hiciste y qué esperabas';

  @override
  String get reportScreenshot => 'Captura de esta pantalla';

  @override
  String get reportScreenshotWindow => 'Captura de esta ventana';

  @override
  String get reportScreenshotOff => 'Desactivada: puede mostrar tu correo';

  @override
  String get reportScreenshotOn => 'Toca la imagen para ocultar partes';

  @override
  String get reportLog => 'Registro de la app';

  @override
  String get reportLogHint => 'Sin direcciones ni asuntos';

  @override
  String get reportDevice => 'Información del dispositivo y la app';

  @override
  String get reportDeviceHint => 'Versión, modelo, idioma';

  @override
  String get reportAlways => 'Siempre';

  @override
  String get reportSeeSent => 'Ver qué se envía';

  @override
  String get reportSend => 'Enviar';

  @override
  String get reportQueued => 'Informe en cola';

  @override
  String get reportNotKept => 'No se pudo guardar el informe';

  @override
  String get reportWhatsSent => 'Qué se envía';

  @override
  String get reportSectionReport => 'Informe';

  @override
  String get reportSectionDevice => 'Dispositivo';

  @override
  String get reportSectionScreenshot => 'Captura';

  @override
  String get reportHideParts => 'Ocultar partes';

  @override
  String get reportDragToBlur => 'Arrastra para difuminar';

  @override
  String get reportDone => 'Hecho';

  @override
  String get reportStatusQueued => 'En cola';

  @override
  String get reportStatusSending => 'Enviando';

  @override
  String get reportStatusFailed => 'Fallido';

  @override
  String get reportStatusEmailed => 'Enviado por correo';

  @override
  String get reportWaitOffline => 'esperando una red';

  @override
  String get reportWaitTurn => 'sale en un momento';

  @override
  String reportWaitAt(String time) {
    return 'sale a las $time';
  }

  @override
  String get reportWaitPaused => 'sale más tarde hoy o mañana';

  @override
  String get reportTapRetry => 'toca para reintentar';

  @override
  String get reportTryAgain => 'Reintentar';

  @override
  String get reportByEmail => 'Enviar por correo en su lugar';

  @override
  String get reportDelete => 'Eliminar';

  @override
  String get reportOptions => 'Opciones del informe';

  @override
  String get crashLine => 'Piuma se cerró inesperadamente. ¿Enviar un informe?';

  @override
  String get crashReport => 'Informar';

  @override
  String get crashDismiss => 'Descartar';

  @override
  String reportStatusSent(int number) {
    return 'Enviado #$number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines líneas',
      one: '1 línea',
    );
    return 'Registro de la app · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Ayuda';

  @override
  String get awayTitle => 'Respuesta automática';

  @override
  String get awayNote => 'Responde por ti, incluso con la app cerrada';

  @override
  String get awayFrom => 'Desde';

  @override
  String get awayToInline => 'hasta';

  @override
  String get awayTo => 'Hasta';

  @override
  String get awaySubject => 'Asunto';

  @override
  String get awayMessage => 'Mensaje';

  @override
  String get awayEndsNote =>
      'Termina sola después del último día. Deja \"hasta\" vacío para mantenerla activa hasta que la desactives.';

  @override
  String awaySubjectUntil(String date) {
    return 'Fuera hasta el $date';
  }

  @override
  String get awaySubjectPlain => 'Fuera de la oficina';

  @override
  String awayBodyUntil(String date) {
    return 'Hola, estoy fuera hasta el $date y responderé a mi vuelta.';
  }

  @override
  String get awayBodyPlain => 'Hola, estoy fuera y responderé a mi vuelta.';

  @override
  String get awayToday => 'Hoy';

  @override
  String get awayNoEnd => 'Sin fin';

  @override
  String get awayPickFrom => 'Primer día';

  @override
  String get awayPickTo => 'Último día';

  @override
  String get awayKeepOn => 'Mantenerla activa hasta que la desactive';

  @override
  String get awayOtherFilters =>
      'No se puede activar junto a tus filtros actuales. Desactívalos primero en el servidor.';

  @override
  String get awayUnsupported =>
      'Este servidor ya no admite respuestas automáticas.';

  @override
  String get awayOffline =>
      'No se pudo contactar con el servidor. Inténtalo de nuevo en un momento.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Respuesta automática activa para $account hasta el $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Respuesta automática activa para $account';
  }

  @override
  String get awayTurnOff => 'Desactivar';

  @override
  String get awayRowOff => 'Desactivada';

  @override
  String get awayRowOn => 'Activada';

  @override
  String awayRowUntil(String date) {
    return 'Activada hasta el $date';
  }

  @override
  String get featuresSubtitle =>
      'Desactiva lo que no uses. Desaparece en todas partes y no se borra nada.';

  @override
  String get featuresZones => 'Zonas';

  @override
  String get featuresOnDevice => 'En este dispositivo';

  @override
  String get featuresOnDeviceNote => 'Nada de esto sale nunca del dispositivo.';

  @override
  String get featureNewslettersHint =>
      'Los boletines en su propia lista, para leerlos como una revista';

  @override
  String get featureNewslettersOff =>
      'Desactivado · los boletines llegan a la bandeja como cualquier correo';

  @override
  String get featureVaultHint =>
      'Pagos, paquetes, viajes y plazos como tarjetas';

  @override
  String get featureVaultOff =>
      'Desactivado · estos correos se quedan como están, sin tarjetas ni avisos';

  @override
  String get featureAttachmentsHint =>
      'Todos los archivos que has recibido, en un solo lugar';

  @override
  String get featureAttachmentsOff =>
      'Desactivado · los archivos se quedan en sus correos y la búsqueda los sigue encontrando';

  @override
  String get featureInShortHint =>
      'Lo esencial de las conversaciones largas, encima del primer correo';

  @override
  String get featureInShortOff =>
      'Desactivado · las conversaciones se abren sin el resumen';

  @override
  String get featureTranslate => 'Traducir';

  @override
  String get featureTranslateHint =>
      'Ofrece traducir los correos escritos en otros idiomas';

  @override
  String get featureTranslateOff =>
      'Desactivado · no se ofrece traducir y no se descarga ningún idioma';

  @override
  String get featureFoundDates => 'Fechas en los correos';

  @override
  String get featureFoundDatesHint =>
      'Añadir al calendario fechas y horas encontradas en el texto';

  @override
  String get featureFoundDatesOff =>
      'Desactivado · las invitaciones siguen mostrando su tarjeta';

  @override
  String get nextEmail => 'Correo siguiente';

  @override
  String get previousEmail => 'Correo anterior';

  @override
  String get appearanceLanguage => 'Idioma';

  @override
  String get languageDevice => 'Idioma del dispositivo';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain parece $like, pero es otra dirección.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'El nombre dice $brand, pero la dirección es de $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'Este correo dice venir de $domain, pero $domain no lo envió.';
  }

  @override
  String get senderDetails => 'Detalles';

  @override
  String get senderDetailsTitle => 'Qué se comprobó';

  @override
  String get senderSentBy => 'Enviado por';

  @override
  String get senderNotKnown => 'Desconocido';

  @override
  String get senderSignature => 'Firma';

  @override
  String get senderSignatureNone => 'Ninguna';

  @override
  String get senderDomainCheck => 'Comprobación del dominio';

  @override
  String get senderDomainCheckFailed => 'No superada (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Parece';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correos de allí',
      one: '1 correo de allí',
      zero: 'ningún correo de allí',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'El nombre dice';

  @override
  String get senderDetailsNote =>
      'Calculado en este dispositivo a partir de lo que escribió tu servidor de correo. Los enlaces de este correo preguntan antes de abrirse.';

  @override
  String impostorLinkBody(String real) {
    return 'Puede que este correo no sea de quien dice. El enlace lleva a $real.';
  }

  @override
  String get updates => 'Actualizaciones';

  @override
  String get updatesVersion => 'Versión';

  @override
  String get upToDate => 'Al día';

  @override
  String get updatesAuto => 'Piuma busca nuevas versiones por sí sola';

  @override
  String get checkForUpdates => 'Buscar actualizaciones';

  @override
  String get updateChecking => 'Comprobando…';

  @override
  String get checkedJustNow => 'Comprobado ahora';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comprobado hace $count minutos',
      one: 'Comprobado hace 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comprobado hace $count horas',
      one: 'Comprobado hace 1 hora',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Comprobado hace $count días',
      one: 'Comprobado ayer',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Descargando $version · $percent%';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done de $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Lista · $version';
  }

  @override
  String get updateGoesInOnRestart => 'Se instala cuando Piuma se reinicia';

  @override
  String get restart => 'Reiniciar';

  @override
  String get updateCouldntCheck => 'No se pudo comprobar';

  @override
  String get tryAgain => 'Reintentar';

  @override
  String get seeWhatsNew => 'Ver novedades';

  @override
  String get whatsNew => 'Novedades';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'El correo y los borradores se conservan. Piuma se cierra y se vuelve a abrir en unos segundos.';

  @override
  String get restartNow => 'Reiniciar ahora';

  @override
  String updateReadyLine(String version) {
    return 'Actualización lista · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Actualizado a $version';
  }

  @override
  String get swipeHintArchiveSnooze =>
      'Desliza a la derecha para archivar, a la izquierda para posponer';

  @override
  String get swipeHintArchive => 'Desliza a la derecha para archivar';

  @override
  String get formatting => 'Formato';

  @override
  String get formatBold => 'Negrita';

  @override
  String get formatItalic => 'Cursiva';

  @override
  String get formatLink => 'Enlace';

  @override
  String get formatBullets => 'Lista con viñetas';

  @override
  String get formatNumbers => 'Lista numerada';

  @override
  String get formatQuote => 'Cita';

  @override
  String get linkAddressHint => 'Pega o escribe una dirección';

  @override
  String get linkAdd => 'Añadir';

  @override
  String get linkRemove => 'Quitar enlace';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count imágenes están desactivadas, así $sender no sabe cuándo lo abres.',
      one: '1 imagen está desactivada, así $sender no sabe cuándo lo abres.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Cargar imágenes';

  @override
  String get alwaysForSender => 'Siempre de este remitente';

  @override
  String get cleanView => 'Vista limpia';

  @override
  String get viewOriginal => 'Original';

  @override
  String get viewClean => 'Limpia';

  @override
  String get calGoogle => 'Google Calendar';

  @override
  String get calGoogleSub => 'Lee eventos y disponibilidad con un enlace iCal';

  @override
  String get calGoogleLabel => 'Dirección iCal de Google Calendar';

  @override
  String get calGoogleHint =>
      'En Google Calendar desde un ordenador: Configuración › tu calendario › Integrar el calendario › Dirección secreta en formato iCal. Solo lectura; conexión directa.';

  @override
  String get bundledReleaseNotes =>
      '## El correo, hecho ligero\n- Diseños originales con desplazamiento único y control de imágenes\n- Barra de formato y acceso al editor completo en las respuestas\n- Gestos de deslizamiento horizontal más precisos\n- Avisos de remitente para marcas suplantadas y dominios similares\n- Exportación CSV mensual de la Bóveda con NIF/IVA del comercio';
}
