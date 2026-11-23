// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Escuro';

  @override
  String get catalogSubtitle => 'Catálogo de componentes · Fase 0';

  @override
  String get sectionColors => 'Cores';

  @override
  String get sectionTypography => 'Tipografia';

  @override
  String get sectionButtons => 'Botões';

  @override
  String get sectionFilters => 'Filtros';

  @override
  String get sectionMessageRows => 'Linhas de mensagem';

  @override
  String get colorBackground => 'Fundo';

  @override
  String get colorSurface => 'Superfície';

  @override
  String get colorText => 'Texto';

  @override
  String get colorSecondary => 'Secundário';

  @override
  String get colorAccent => 'Destaque';

  @override
  String get colorSoft => 'Suave';

  @override
  String get colorSuccess => 'Sucesso';

  @override
  String get colorWarning => 'Aviso';

  @override
  String get colorDanger => 'Perigo';

  @override
  String get typeDisplay => 'Display';

  @override
  String get typeTitle => 'Título';

  @override
  String get typeSubtitle => 'Subtítulo';

  @override
  String get typeBody => 'Corpo';

  @override
  String get typeSmall => 'Pequeno';

  @override
  String get typeMono => 'Mono';

  @override
  String get actionSend => 'Enviar';

  @override
  String get actionSnooze => 'Adiar';

  @override
  String get actionReply => 'Responder';

  @override
  String get actionDelete => 'Excluir';

  @override
  String get actionDisabled => 'Desativado';

  @override
  String get filterUnread => 'Não lidos';

  @override
  String get filterAttachments => 'Com anexos';

  @override
  String get filterPeople => 'Só pessoas';

  @override
  String get messageUnread => 'Não lido';

  @override
  String get compose => 'Escrever';

  @override
  String get unifiedInbox => 'Caixa unificada';

  @override
  String get accounts => 'Contas';

  @override
  String get addAccount => 'Adicionar uma conta';

  @override
  String get inbox => 'Caixa de entrada';

  @override
  String downloading(String done, String total) {
    return 'Baixando $done de $total';
  }

  @override
  String get offline => 'Sem conexão · tentando de novo';

  @override
  String get signInFailed => 'Uma conta precisa da senha de novo';

  @override
  String inboxSummary(int accounts, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts contas',
      one: '1 conta',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unread,
      locale: localeName,
      other: '$unread não lidos',
      zero: 'tudo lido',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get nothingSelected => 'Escolha uma mensagem para ler.';

  @override
  String get noSubject => '(sem assunto)';

  @override
  String get couldNotLoadMessage =>
      'Não foi possível baixar esta mensagem. Verifique a conexão e tente de novo.';

  @override
  String get loading => 'Carregando…';

  @override
  String toYouToday(String time) {
    return 'para você · hoje às $time';
  }

  @override
  String toYouYesterday(String time) {
    return 'para você · ontem às $time';
  }

  @override
  String toYouOn(String date, String time) {
    return 'para você · $date às $time';
  }

  @override
  String get sectionToday => 'Hoje';

  @override
  String get sectionYesterday => 'Ontem';

  @override
  String get sectionThisWeek => 'Esta semana';

  @override
  String get sectionThisMonth => 'Este mês';

  @override
  String get sectionOlder => 'Mais antigos';

  @override
  String get emailAddress => 'Endereço de e-mail';

  @override
  String get password => 'Senha';

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
  String get port => 'Porta';

  @override
  String get security => 'Segurança';

  @override
  String get accountName => 'Nome da conta';

  @override
  String get accountColor => 'Cor da conta';

  @override
  String get color => 'Cor';

  @override
  String get connect => 'Conectar';

  @override
  String get connecting => 'Conectando…';

  @override
  String get notNow => 'Agora não';

  @override
  String get enterToConnect => 'para conectar';

  @override
  String get errorWrongPassword =>
      'O servidor não aceitou este endereço e senha. Se o seu provedor usa senhas de app, crie uma e use aqui.';

  @override
  String get errorUnreachable =>
      'Não foi possível alcançar o servidor. Verifique o nome do servidor, a porta e sua conexão.';

  @override
  String get errorInsecure =>
      'Não foi possível estabelecer uma conexão segura com o servidor. Verifique o nome do servidor e a configuração de segurança.';

  @override
  String get errorKeychain =>
      'Não foi possível salvar a senha no chaveiro do sistema.';

  @override
  String get errorOther => 'Algo deu errado ao conectar. Tente de novo.';

  @override
  String get yourAccounts => 'Suas contas';

  @override
  String get noAccountsYet => 'Sua primeira conta aparecerá aqui.';

  @override
  String get connected => 'Conectada';

  @override
  String get privacyNote =>
      'Seus e-mails ficam neste dispositivo. Conectamos direto aos seus servidores, sem ninguém no meio.';

  @override
  String get newMessage => 'Nova mensagem';

  @override
  String get close => 'Fechar';

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
  String get subject => 'Assunto';

  @override
  String get messageBody => 'Mensagem';

  @override
  String get addRecipient => 'Adicionar';

  @override
  String removeRecipient(String name) {
    return 'Remover $name';
  }

  @override
  String undoSendHint(int seconds) {
    return 'Você pode desfazer o envio por $seconds segundos';
  }

  @override
  String get sendNoRecipients => 'Adicione pelo menos um destinatário.';

  @override
  String sendBadAddress(String address) {
    return '“$address” não é um endereço de e-mail.';
  }

  @override
  String get sending => 'Enviando…';

  @override
  String get sent => 'Enviado';

  @override
  String get undo => 'Desfazer';

  @override
  String get draftDiscarded => 'Rascunho descartado';

  @override
  String get sendErrorPassword =>
      'O servidor de envio não aceitou a senha. Sua mensagem continua aqui.';

  @override
  String get sendErrorUnreachable =>
      'Não foi possível alcançar o servidor de envio. Sua mensagem continua aqui.';

  @override
  String get sendErrorRejected =>
      'O servidor de envio recusou a mensagem. Sua mensagem continua aqui.';

  @override
  String get sendErrorOther =>
      'Não foi possível enviar a mensagem. Sua mensagem continua aqui.';

  @override
  String stepOf(int step, int total) {
    return '$step de $total';
  }

  @override
  String get whatsYourEmail => 'Qual é o seu e-mail?';

  @override
  String get findSettingsHint =>
      'Vamos encontrar as configurações do servidor para você.';

  @override
  String get continueAction => 'Continuar';

  @override
  String get lookingUp => 'Procurando…';

  @override
  String get setUpManually => 'Configurar manualmente';

  @override
  String get back => 'Voltar';

  @override
  String get weFoundSettings => 'Encontramos suas configurações';

  @override
  String get incoming => 'Entrada';

  @override
  String get outgoing => 'Saída';

  @override
  String get incomingAndOutgoing => 'Entrada e saída';

  @override
  String get guessedSettings =>
      'Estas são as configurações habituais do seu domínio. Se a conexão falhar, confira-as.';

  @override
  String get yourName => 'Seu nome';

  @override
  String get yourNameHint =>
      'Aparece para as pessoas a quem você escreve. Opcional.';

  @override
  String get settingsNotFound =>
      'Não encontramos as configurações deste endereço. As páginas de ajuda do seu provedor as informam.';

  @override
  String get smtpServer => 'Servidor SMTP';

  @override
  String get username => 'Nome de usuário';

  @override
  String get usedForBoth => 'Usado para e-mails de entrada e de saída.';

  @override
  String get verifyAndConnect => 'Verificar e conectar';

  @override
  String get archive => 'Arquivar';

  @override
  String get archived => 'Arquivado';

  @override
  String get movedToTrash => 'Movido para a lixeira';

  @override
  String get actionFailed =>
      'Não foi possível mover a mensagem. Ela voltou para a caixa de entrada.';

  @override
  String get replyTitle => 'Responder';

  @override
  String quoteHeader(String date, String name) {
    return 'Em $date, $name escreveu:';
  }

  @override
  String get search => 'Pesquisar…';

  @override
  String get searchAllAccounts => 'Pesquisar em todas as contas';

  @override
  String searchResults(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultados',
      one: '1 resultado',
      zero: 'Nenhum resultado',
    );
    return '$_temp0';
  }

  @override
  String get searchFilters => 'Filtros';

  @override
  String get filterLastMonth => 'Último mês';

  @override
  String get filterAccount => 'Conta';

  @override
  String get searchOperators => 'Operadores';

  @override
  String get operatorNameHint => 'nome';

  @override
  String get operatorDateHint => 'data';

  @override
  String get searchPeople => 'Pessoas';

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
  String get searchNoResults => 'Nada encontrado';

  @override
  String get searchNoResultsHint => 'Tente menos palavras ou outra grafia.';

  @override
  String get searchNoResultsFilters => 'Nenhum resultado com estes filtros';

  @override
  String get searchNoResultsFiltersHint =>
      'Remova um filtro ou operador para ampliar a pesquisa.';

  @override
  String get clearFilters => 'Limpar filtros';

  @override
  String get searchEmptyHint =>
      'Pesquise em todas as contas por palavra, remetente ou data, mesmo sem conexão.';

  @override
  String searchMatches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ocorrências',
      one: '1 ocorrência',
    );
    return '$_temp0';
  }

  @override
  String get openConversation => 'Abrir conversa';

  @override
  String get noMessageToShow => 'Nenhuma mensagem para mostrar';

  @override
  String searchStats(int accounts, String emails, String seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      accounts,
      locale: localeName,
      other: '$accounts contas',
      one: '1 conta',
    );
    return 'Pesquisado em $_temp0 · $emails e-mails · $seconds s · índice local, funciona sem conexão';
  }

  @override
  String get keyMove => 'mover';

  @override
  String get keyOpen => 'abrir';

  @override
  String get privacyImagesBlocked => 'Imagens bloqueadas';

  @override
  String privacyImagesBlockedStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rastreadores bloqueados',
      one: '1 rastreador bloqueado',
    );
    return 'Imagens bloqueadas · $_temp0';
  }

  @override
  String get privacyLoadingImages => 'Carregando imagens…';

  @override
  String get privacyImagesLoaded => 'Imagens carregadas';

  @override
  String get privacyImagesLoadedStopped =>
      'Imagens carregadas · rastreadores ainda bloqueados';

  @override
  String privacyTrackersStopped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rastreadores bloqueados',
      one: '1 rastreador bloqueado',
    );
    return '$_temp0';
  }

  @override
  String privacyLinksCleaned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count links limpos',
      one: '1 link limpo',
    );
    return '$_temp0';
  }

  @override
  String get privacySheetTitle => 'Privacidade desta mensagem';

  @override
  String get privacySheetSubtitle =>
      'O remetente não consegue saber se nem quando você a abriu.';

  @override
  String get trackerPixel => 'Pixel de abertura';

  @override
  String get trackerFont => 'Fonte remota';

  @override
  String get trackerStyle => 'Estilo remoto';

  @override
  String get trackerLinks => 'Links rastreados';

  @override
  String get trackerStopped => 'Bloqueado';

  @override
  String get loadImagesOnce => 'Carregar imagens uma vez';

  @override
  String get imagesAlreadyLoaded => 'Imagens já carregadas';

  @override
  String trustSender(String name) {
    return 'Sempre confiar em $name';
  }

  @override
  String senderTrusted(String name) {
    return '$name é confiável';
  }

  @override
  String get alwaysBlockImages => 'Sempre bloquear imagens remotas';

  @override
  String get alwaysBlockImagesHint =>
      'Vale para todos os remetentes não confiáveis';

  @override
  String get imageNotLoaded => 'Imagem não carregada';

  @override
  String get suspiciousLinkTitle => 'Confira este link';

  @override
  String suspiciousLinkBody(String shown, String real) {
    return 'O texto mostra $shown, mas o link leva a $real.';
  }

  @override
  String get openAnyway => 'Abrir mesmo assim';

  @override
  String get linkTargetTitle => 'Para onde vai este link';

  @override
  String get linkOpen => 'Abrir link';

  @override
  String get linkCopy => 'Copiar link';

  @override
  String get linkCopied => 'Link copiado';

  @override
  String get dontOpen => 'Não abrir';

  @override
  String get riskProgram => 'Um programa que pode ser executado';

  @override
  String riskDisguised(String kind) {
    return 'Um programa, com nome de $kind';
  }

  @override
  String get riskMacros => 'Tem macros que podem ser executadas';

  @override
  String get riskLocked => 'Protegido por senha';

  @override
  String get riskOpenProgram => 'Abrir este programa?';

  @override
  String get riskOpenFile => 'Abrir este arquivo?';

  @override
  String get riskOpenArchive => 'Abrir este arquivo compactado?';

  @override
  String riskBodyProgram(String name) {
    return '$name é um programa. Programas recebidos por e-mail podem tomar conta do seu dispositivo. Abra só se estava esperando.';
  }

  @override
  String riskBodyDisguised(String name, String kind) {
    return '$name parece um $kind, mas é um programa. Programas recebidos por e-mail podem tomar conta do seu dispositivo. Abra só se estava esperando.';
  }

  @override
  String riskBodyMacros(String name) {
    return '$name tem macros, que podem ser executadas ao abrir. Abra só se estava esperando.';
  }

  @override
  String riskBodyLocked(String name) {
    return '$name está protegido por senha, então ninguém pode olhar dentro. Abra só se estava esperando.';
  }

  @override
  String get riskWeb => 'Uma página web';

  @override
  String get riskOpenWeb => 'Abrir esta página web?';

  @override
  String riskBodyWeb(String name) {
    return '$name é uma página web: abre no seu navegador. Nunca digite uma senha nela: uma página enviada por e-mail pode parecer qualquer login.';
  }

  @override
  String riskFileFrom(String name, String size, String email) {
    return '$name · $size · de $email';
  }

  @override
  String get settings => 'Configurações';

  @override
  String get backToMail => 'Voltar aos e-mails';

  @override
  String get settingsAccountsTitle => 'Contas';

  @override
  String settingsAccountsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count caixas IMAP, uma só caixa de entrada.',
      one: 'Uma caixa IMAP.',
    );
    return '$_temp0 A cor mostra de onde vem cada e-mail.';
  }

  @override
  String accountKindImap(String email) {
    return '$email · IMAP';
  }

  @override
  String get addAccountShort => 'Adicionar conta';

  @override
  String get addAccountNote =>
      'IMAP e SMTP. Gmail, iCloud e Fastmail se configuram sozinhos.';

  @override
  String get privacyTitle => 'Privacidade e segurança';

  @override
  String get privacySubtitle =>
      'Tudo acontece neste dispositivo. Nenhum dado sai da sua caixa.';

  @override
  String get blockImagesSetting => 'Bloquear imagens remotas';

  @override
  String get blockImagesSettingHint =>
      'As imagens só carregam quando você pede.';

  @override
  String get stopPixelsSetting => 'Bloquear pixels de rastreamento';

  @override
  String get stopPixelsSettingHint =>
      'Os remetentes não conseguem saber se nem quando você abre uma mensagem.';

  @override
  String get cleanLinksSetting => 'Limpar links';

  @override
  String get cleanLinksSettingHint =>
      'Remove utm e parâmetros de rastreamento antes de abrir.';

  @override
  String get warnLinksSetting => 'Avisar sobre links suspeitos';

  @override
  String get warnLinksSettingHint =>
      'Pergunta antes de abrir um link que mostra um endereço e leva a outro.';

  @override
  String get last30Days => 'Últimos 30 dias';

  @override
  String get trackersStoppedLabel => 'rastreadores bloqueados';

  @override
  String get linksCleanedLabel => 'links limpos';

  @override
  String privacyStatsDetail(String pixels, String styles, int suspicious) {
    String _temp0 = intl.Intl.pluralLogic(
      suspicious,
      locale: localeName,
      other: '$suspicious links suspeitos sinalizados',
      one: '1 link suspeito sinalizado',
    );
    return 'Pixels de abertura $pixels · fontes e estilos remotos $styles · $_temp0';
  }

  @override
  String get trustedSenders => 'Remetentes confiáveis';

  @override
  String get trustedSendersHint => 'as imagens sempre carregam';

  @override
  String trustedSince(String email, String date) {
    return '$email · desde $date';
  }

  @override
  String get removeTrusted => 'Remover';

  @override
  String get noTrustedSenders =>
      'Nenhum remetente confiável. As imagens continuam bloqueadas para todos.';

  @override
  String appVersionLine(String version) {
    return 'Piuma Mail $version · GPL-3.0';
  }

  @override
  String get attachFile => 'Anexar arquivo';

  @override
  String removeAttachment(String name) {
    return 'Remover $name';
  }

  @override
  String attachmentLabel(String name, String size) {
    return '$name, $size';
  }

  @override
  String attachmentSaved(String name) {
    return '$name salvo em Downloads';
  }

  @override
  String attachmentNotSaved(String name) {
    return 'Não foi possível baixar $name. Verifique a conexão e tente de novo.';
  }

  @override
  String filesTooLarge(String max) {
    return 'Os anexos podem ter até $max no total. Remova alguns e tente de novo.';
  }

  @override
  String fileNotRead(String name) {
    return 'Não foi possível ler $name.';
  }

  @override
  String get folderSent => 'Enviados';

  @override
  String get folderArchive => 'Arquivo';

  @override
  String folderSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contas',
      one: 'Uma conta',
    );
    return '$_temp0';
  }

  @override
  String toPeopleToday(String people, String time) {
    return 'para $people · hoje às $time';
  }

  @override
  String toPeopleYesterday(String people, String time) {
    return 'para $people · ontem às $time';
  }

  @override
  String toPeopleOn(String people, String date, String time) {
    return 'para $people · $date às $time';
  }

  @override
  String get emptyFolder => 'Nada aqui ainda.';

  @override
  String threadMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensagens',
      one: '1 mensagem',
    );
    return '$_temp0';
  }

  @override
  String conversationSummary(int count, String people) {
    return '$count mensagens · $people';
  }

  @override
  String readMessages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensagens lidas',
      one: '1 mensagem lida',
    );
    return '$_temp0';
  }

  @override
  String newMessages(int count) {
    return '$count novas';
  }

  @override
  String get you => 'você';

  @override
  String get quotedTextHidden => '··· texto citado oculto';

  @override
  String get showQuotedText => 'Mostrar texto citado';

  @override
  String get youName => 'Você';

  @override
  String yesterdayAt(String time) {
    return 'Ontem $time';
  }

  @override
  String get pickMessage => 'Selecionar';

  @override
  String get unpickMessage => 'Selecionado';

  @override
  String get selectAll => 'Selecionar tudo';

  @override
  String pickedOf(int count, int total) {
    return '$count de $total selecionados';
  }

  @override
  String get deselect => 'Desmarcar';

  @override
  String conversationsPicked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'conversas selecionadas',
      one: 'conversa selecionada',
    );
    return '$_temp0';
  }

  @override
  String pickedFromOne(String name) {
    return 'de $name';
  }

  @override
  String pickedFromList(String names, String last) {
    return 'de $names e $last';
  }

  @override
  String pickedFromMore(String names, int count) {
    return 'de $names e mais $count';
  }

  @override
  String andMore(String name, int count) {
    return '$name e mais $count';
  }

  @override
  String get markRead => 'Marcar como lido';

  @override
  String get markUnread => 'Marcar como não lido';

  @override
  String get hintArchive => 'arquivar';

  @override
  String get hintUnread => 'não lido';

  @override
  String get hintDeselect => 'desmarcar';

  @override
  String archivedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas arquivadas',
      one: 'Arquivado',
    );
    return '$_temp0';
  }

  @override
  String trashedMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas movidas para a lixeira',
      one: 'Movido para a lixeira',
    );
    return '$_temp0';
  }

  @override
  String get seenFailed =>
      'Não foi possível alcançar o servidor. Lido e não lido voltaram ao que eram.';

  @override
  String get signaturesTitle => 'Assinaturas';

  @override
  String get newSignature => 'Nova assinatura';

  @override
  String get newSignatureLabel => 'Nova assinatura';

  @override
  String get noSignatures =>
      'Nenhuma assinatura ainda. Crie uma com Nova assinatura.';

  @override
  String get signatureTemplate => 'Modelo';

  @override
  String get signatureLogo => 'Logotipo';

  @override
  String get signatureLabelField => 'Nome da assinatura';

  @override
  String get signatureAccount => 'Conta';

  @override
  String get signatureName => 'Nome';

  @override
  String get signatureRole => 'Cargo';

  @override
  String get signatureCompany => 'Empresa';

  @override
  String get signaturePhone => 'Telefone';

  @override
  String get signatureWebsite => 'Site';

  @override
  String get signatureAccent => 'Cor de destaque';

  @override
  String get accentBlue => 'Destaque azul';

  @override
  String get accentBlack => 'Destaque preto';

  @override
  String get accentTerracotta => 'Destaque terracota';

  @override
  String get signatureWhen => 'Quando usar';

  @override
  String signatureForNew(String email) {
    return 'Novos e-mails de $email';
  }

  @override
  String get signatureForReplies => 'Respostas e encaminhamentos';

  @override
  String get signatureNone => 'Nenhuma';

  @override
  String get deleteSignature => 'Excluir assinatura';

  @override
  String get signatureDeleteHint => 'Os e-mails já enviados a mantêm.';

  @override
  String get signaturePreview => 'Prévia';

  @override
  String get previewLight => 'Claro';

  @override
  String get previewDark => 'Escuro';

  @override
  String get previewText => 'Texto';

  @override
  String get signatureSampleText =>
      'Oi, Luca,\nos arquivos finais estão em anexo. Me avise se precisar de mais alguma coisa.\n\nAté breve,';

  @override
  String get signatureNote =>
      'Sem imagens: a assinatura chega limpa mesmo onde as imagens são bloqueadas, e a versão em texto simples é criada para você.';

  @override
  String get signatureNoteLogo =>
      'O logotipo viaja dentro do e-mail (máx. 40 KB) com texto alternativo, então nunca pede para “carregar imagens” e não rastreia ninguém. A versão em texto simples é criada para você.';

  @override
  String get signatureUseAll => 'tudo';

  @override
  String get signatureUseNew => 'novos e-mails';

  @override
  String get signatureUseReplies => 'respostas e encaminhamentos';

  @override
  String get signatureUseNone => 'não usada';

  @override
  String get templateMinimal => 'Mínima';

  @override
  String get templateClassic => 'Clássica';

  @override
  String get templateMonogram => 'Monograma';

  @override
  String get templateLogo => 'Com logotipo';

  @override
  String get noLogo => 'SEM LOGO';

  @override
  String get logoHint => 'PNG ou JPEG, reduzido a 40 KB automaticamente';

  @override
  String get removeLogo => 'Remover';

  @override
  String get uploadLogo => 'Enviar';

  @override
  String get logoTooBig =>
      'Este logotipo continua acima de 40 KB mesmo reduzido. Tente um mais simples.';

  @override
  String get logoNotImage => 'Escolha uma imagem PNG ou JPEG.';

  @override
  String signatureChip(String label) {
    return 'Assinatura · $label';
  }

  @override
  String get noSignature => 'Sem assinatura';

  @override
  String get manageSignatures => 'Gerenciar assinaturas…';

  @override
  String get signatureUsedNew => 'Novos e-mails';

  @override
  String get signatureUsedReplies => 'Respostas';

  @override
  String get composeSignatureNote =>
      'A assinatura segue a conta De: a assinatura dela para novos e-mails, a curta para respostas e encaminhamentos.';

  @override
  String get noticeOpen => 'Abrir';

  @override
  String get noticeChannel => 'Novos e-mails';

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
  String get notificationsTitle => 'Notificações';

  @override
  String get notificationsLead => 'Poucas, e só quando importam.';

  @override
  String get notifyAbout => 'Avisar sobre';

  @override
  String get notifyPeople => 'Só pessoas';

  @override
  String get notifyPeopleHint =>
      'E-mails escritos por pessoas. Sem newsletters, recibos ou mensagens automáticas.';

  @override
  String get notifyRecommended => 'Recomendado';

  @override
  String get notifyAll => 'Todos';

  @override
  String get notifyAllHint => 'Cada novo e-mail que chega à caixa de entrada.';

  @override
  String get notifyOff => 'Nenhum';

  @override
  String get notifyOffHint =>
      'Confira quando quiser. Sem indicadores, sem sons.';

  @override
  String get quietHours => 'Horas de silêncio';

  @override
  String get quietTitle => 'Toda noite';

  @override
  String get quietHint => 'Os e-mails continuam chegando, em silêncio.';

  @override
  String get quietFrom => 'Das';

  @override
  String get quietTo => 'às';

  @override
  String quietFromLabel(String time) {
    return 'As horas de silêncio começam às $time';
  }

  @override
  String quietToLabel(String time) {
    return 'As horas de silêncio terminam às $time';
  }

  @override
  String phoneSearch(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contas',
      one: '1 conta',
    );
    return 'Pesquisar em $_temp0';
  }

  @override
  String get phoneAccountsAll => 'Todas';

  @override
  String phoneAccountsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'todas as $count contas',
      one: '1 conta',
    );
    return 'Mostrando $_temp0';
  }

  @override
  String get composeMessage => 'Escrever uma mensagem';

  @override
  String get moreActions => 'Mais ações';

  @override
  String quickReplyHint(String name) {
    return 'Responder a $name…';
  }

  @override
  String get sendReply => 'Enviar resposta';

  @override
  String get cancel => 'Cancelar';

  @override
  String get pickAll => 'Todos';

  @override
  String get pickNone => 'Nenhum';

  @override
  String get pickRead => 'Lidos';

  @override
  String get pickUnread => 'Não lidos';

  @override
  String phoneSelectedWord(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'selecionados',
      one: 'selecionado',
    );
    return '$_temp0';
  }

  @override
  String phoneOfTotal(int total) {
    return 'de $total';
  }

  @override
  String phoneSelected(int count, int total) {
    return '$count de $total selecionados';
  }

  @override
  String get phoneSelectActions => 'Ações na seleção';

  @override
  String get clearSearch => 'Limpar pesquisa';

  @override
  String get settingsAbout => 'Sobre';

  @override
  String get settingsMail => 'E-mail';

  @override
  String get settingsApp => 'App';

  @override
  String get writingTitle => 'Escrita';

  @override
  String get readingTitle => 'Leitura';

  @override
  String get readingSubtitle =>
      'Como a lista aparece, e o que ajuda você a ler.';

  @override
  String get organizingTitle => 'Organização';

  @override
  String get organizingSubtitle => 'Áreas, regras, pastas e marcadores.';

  @override
  String signaturesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count assinaturas',
      one: '1 assinatura',
    );
    return '$_temp0';
  }

  @override
  String get openSourceLine => 'Código aberto · GPL-3.0';

  @override
  String get motto => 'O e-mail, mais leve.';

  @override
  String get appName => 'Piuma Mail';

  @override
  String phoneAccountsMenu(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contas',
      one: '1 conta',
    );
    return '$_temp0, contas e Configurações';
  }

  @override
  String get allAccounts => 'Todas as contas';

  @override
  String allAccountsDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count caixas juntas',
      one: '1 caixa',
    );
    return '$_temp0';
  }

  @override
  String phoneAccountMenu(String name) {
    return 'Só $name, contas e Configurações';
  }

  @override
  String accountOnly(String name) {
    return 'Só $name';
  }

  @override
  String get showAllAccounts => 'Mostrar todas';

  @override
  String get phoneFolders => 'Pastas';

  @override
  String phoneSearchOne(String name) {
    return 'Pesquisar em $name';
  }

  @override
  String get welcomeLead =>
      'Conecte suas contas IMAP e leia tudo em uma só caixa, sem barulho.';

  @override
  String get staysOnDevice => 'Seus e-mails ficam no seu dispositivo';

  @override
  String get editServers => 'Editar';

  @override
  String get serverHost => 'Servidor';

  @override
  String get offlineTitle => 'Você está sem conexão';

  @override
  String get offlineDetail =>
      'os e-mails de saída serão enviados quando você voltar a ficar on-line';

  @override
  String downloadingAccount(String name) {
    return 'Baixando $name';
  }

  @override
  String downloadingCount(String done, String total) {
    return '$done de $total';
  }

  @override
  String accountCantConnect(String name) {
    return 'A conta $name não consegue se conectar';
  }

  @override
  String passwordChanged(String email) {
    return 'A senha mudou? Os e-mails de $email pararam de chegar.';
  }

  @override
  String get signInAgain => 'Entrar de novo';

  @override
  String get later => 'Mais tarde';

  @override
  String signInTo(String name) {
    return 'Entrar em $name';
  }

  @override
  String get signIn => 'Entrar';

  @override
  String get signingIn => 'Entrando…';

  @override
  String get allCaughtUp => 'Tudo em dia';

  @override
  String get allCaughtUpDetail =>
      'Ninguém está esperando por você. O resto do dia é seu.';

  @override
  String get countOf => 'de';

  @override
  String get draftSaved => 'Rascunho salvo';

  @override
  String get draftNotSaved => 'Não salvo';

  @override
  String get draftNotSavedToast => 'Rascunho não salvo';

  @override
  String get reopen => 'Reabrir';

  @override
  String get discard => 'Descartar';

  @override
  String get discardDraft => 'Descartar rascunho';

  @override
  String get noRecipients => 'Sem destinatários';

  @override
  String get folderDrafts => 'Rascunhos';

  @override
  String accountFolders(String name) {
    return 'Pastas de $name';
  }

  @override
  String get moveShort => 'Mover';

  @override
  String get moveTo => 'Mover para…';

  @override
  String moveToIn(String name) {
    return 'Mover para uma pasta de $name';
  }

  @override
  String get noFoldersMatch => 'Nenhuma pasta com esse nome';

  @override
  String noOtherFolders(String name) {
    return '$name ainda não tem outras pastas';
  }

  @override
  String movedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas movidas para $folder',
      one: 'Movido para $folder',
    );
    return '$_temp0';
  }

  @override
  String outboxHeader(int count) {
    return 'Caixa de saída · $count';
  }

  @override
  String outboxTo(String names) {
    return 'Para $names';
  }

  @override
  String get outboxWaiting => 'Aguardando';

  @override
  String get outboxNotSent => 'Não enviado';

  @override
  String outboxRefused(String reason) {
    return 'O servidor recusou: $reason';
  }

  @override
  String get outboxMaybeSent => 'Pode ter sido enviado';

  @override
  String get outboxMaybeSentCheck =>
      'A ligação caiu durante o envio. Veja em Enviados antes de o enviar outra vez.';

  @override
  String get outboxRedirectTitle => 'Redirecionamento em espera';

  @override
  String get outboxRedirectLine => 'Redirecionado sem alterações';

  @override
  String get outboxRedirectBody =>
      'Um redirecionamento segue tal como o email chegou, por isso não há nada para editar. Cancele-o ou tente enviá-lo outra vez.';

  @override
  String get outboxCancelRedirect => 'Cancelar redirecionamento';

  @override
  String get outboxRedirectCancelled => 'Redirecionamento cancelado';

  @override
  String get dataProblemTitle => 'O Piuma não conseguiu abrir os seus dados';

  @override
  String get dataProblemBody =>
      'O seu correio está seguro nos servidores e nada foi alterado aqui. Tente de novo; se continuar a acontecer, comunique-o com o que o Piuma indica.';

  @override
  String get dataProblemNewer =>
      'Estes dados foram escritos por uma versão mais recente do Piuma. Atualize o Piuma para os abrir; nada foi alterado aqui.';

  @override
  String get inOutbox =>
      'Na caixa de saída · sai quando você voltar a ficar on-line';

  @override
  String get editAction => 'Editar';

  @override
  String get backgroundTitle => 'Novos e-mails assim que chegam';

  @override
  String get backgroundBody =>
      'O Piuma fica conectado às suas contas, sem servidor no meio. O Android vai pedir duas coisas: mostrar notificações e deixar o Piuma rodar em segundo plano.';

  @override
  String get newMailHeading => 'Novos e-mails';

  @override
  String get deliveryInstant => 'Assim que chegam';

  @override
  String get deliveryInstantHint => 'Mantém um aviso silencioso na barra';

  @override
  String get deliveryPeriodic => 'A cada 15 minutos';

  @override
  String get deliveryPeriodicHint => 'Sem aviso; o Android pode esperar mais';

  @override
  String get folderNewsletters => 'Newsletters';

  @override
  String newslettersTileLabel(int count) {
    return 'Newsletters, $count não lidas';
  }

  @override
  String newsletterRowMeta(int minutes, String when) {
    return '$minutes min · $when';
  }

  @override
  String newsletterReadTime(int minutes, String time) {
    return '$minutes min de leitura · chegou às $time';
  }

  @override
  String newsletterArrived(String time) {
    return 'Chegou às $time';
  }

  @override
  String newsletterArrivedOn(String date) {
    return 'Chegou em $date';
  }

  @override
  String newsletterReadTimeOn(int minutes, String date) {
    return '$minutes min de leitura · chegou em $date';
  }

  @override
  String get dayToday => 'hoje';

  @override
  String get dayYesterday => 'ontem';

  @override
  String get readLater => 'Ler depois';

  @override
  String get readLaterDone => 'Mantida como não lida';

  @override
  String get unsubscribe => 'Cancelar inscrição';

  @override
  String unsubscribeTitle(String sender) {
    return 'Cancelar a inscrição em $sender?';
  }

  @override
  String unsubscribeOneClick(String sender) {
    return '$sender recebe um único pedido para parar. Nada é aberto, e o que já chegou fica aqui.';
  }

  @override
  String unsubscribeMail(String address) {
    return 'Uma mensagem sai da sua conta para $address pedindo isso. O que já chegou fica aqui.';
  }

  @override
  String unsubscribeMailTo(String address) {
    return 'Para: $address';
  }

  @override
  String unsubscribeMailSubject(String subject) {
    return 'Assunto: $subject';
  }

  @override
  String get unsubscribePage => 'A página de cancelamento abre no navegador.';

  @override
  String unsubscribeNone(String sender) {
    return '$sender não oferece como cancelar a inscrição. Mova para a caixa de entrada ou arquive o que chegar.';
  }

  @override
  String get unsubscribeConfirm => 'Cancelar inscrição';

  @override
  String get unsubscribeOpen => 'Abrir página';

  @override
  String unsubscribeDone(String sender) {
    return 'Inscrição em $sender cancelada';
  }

  @override
  String get unsubscribeFailed =>
      'Não foi possível cancelar a inscrição. Verifique a conexão e tente de novo.';

  @override
  String get alwaysInInbox => 'Sempre na caixa de entrada';

  @override
  String alwaysInInboxDone(String sender) {
    return 'Os e-mails de $sender agora vão para a caixa de entrada';
  }

  @override
  String get newslettersArchiveNote =>
      'Lidas há mais de 7 dias? Elas se arquivam sozinhas';

  @override
  String get newslettersEmpty => 'Nenhuma newsletter';

  @override
  String newslettersToRead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count para ler',
      one: '1 para ler',
      zero: 'Tudo lido',
    );
    return '$_temp0';
  }

  @override
  String newslettersMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String newslettersMinutesLong(int minutes) {
    return '$minutes minutos no total';
  }

  @override
  String newslettersNew(int count) {
    return '$count novas';
  }

  @override
  String get folderVault => 'Cofre';

  @override
  String vaultTileLabel(String status) {
    return 'Cofre, $status';
  }

  @override
  String vaultSidebarLabel(int count) {
    return 'Cofre, $count pendentes';
  }

  @override
  String vaultDue(String when) {
    return 'Vence $when';
  }

  @override
  String vaultArrives(String when) {
    return 'Chega $when';
  }

  @override
  String get vaultAllClear => 'Tudo certo';

  @override
  String get vaultToday => 'Hoje';

  @override
  String get vaultTomorrow => 'Amanhã';

  @override
  String get dayTomorrow => 'amanhã';

  @override
  String vaultInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'em $days dias',
      one: 'amanhã',
      zero: 'hoje',
    );
    return '$_temp0';
  }

  @override
  String get parcelOrdered => 'Pedido feito';

  @override
  String get parcelShipped => 'Enviado';

  @override
  String get parcelTransit => 'Em trânsito';

  @override
  String get parcelDelivered => 'Entregue';

  @override
  String vaultDeliveredOn(String day) {
    return 'Entregue $day';
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
    return 'Último registro: $place';
  }

  @override
  String get vaultDueLabel => 'Vence';

  @override
  String get vaultPaid => 'Pago';

  @override
  String get vaultDownloadPdf => 'Baixar PDF';

  @override
  String get vaultMarkPaid => 'Marcar como pago';

  @override
  String get vaultPaidFailed => 'Não foi possível salvar. Tente de novo.';

  @override
  String vaultFlight(String number, String date) {
    return 'Voo $number · $date';
  }

  @override
  String vaultCityTime(String city, String time) {
    return '$city · $time';
  }

  @override
  String get vaultSeat => 'Assento';

  @override
  String get vaultCode => 'Código';

  @override
  String get vaultBoardingPass => 'Cartão de embarque';

  @override
  String vaultPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pessoas',
      one: '1 pessoa',
    );
    return '$_temp0';
  }

  @override
  String get vaultConfirmed => 'confirmado';

  @override
  String get vaultPending => 'a confirmar';

  @override
  String get vaultCancelled => 'cancelado';

  @override
  String get vaultDirections => 'Como chegar';

  @override
  String get vaultNotePhone =>
      'Lido no dispositivo a partir do e-mail original · toque em um cartão para abri-lo';

  @override
  String get vaultEmpty =>
      'Encomendas, gastos, viagens e mais aparecem aqui, lidos neste dispositivo a partir dos e-mails.';

  @override
  String get folderAttachments => 'Anexos';

  @override
  String get attachmentsSubtitle =>
      'Todos os arquivos que você recebeu, sem abrir o e-mail';

  @override
  String get attachmentsAll => 'Todos';

  @override
  String get attachmentsMedia => 'Fotos e mídia';

  @override
  String get attachmentsDocuments => 'Documentos';

  @override
  String get attachmentsSheets => 'Planilhas';

  @override
  String get attachmentsFilter => 'Filtrar por tipo';

  @override
  String get attachmentsSearch => 'Pesquisar arquivos ou remetentes';

  @override
  String get attachmentsSearchLabel => 'Pesquisar anexos';

  @override
  String get attachmentsRecent => 'Recentes';

  @override
  String get attachmentsLargest => 'Maiores';

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
  String get attachmentsDownload => 'Baixar';

  @override
  String get attachmentsOpenEmail => 'Abrir e-mail';

  @override
  String get attachmentsEmail => 'E-mail';

  @override
  String attachmentsCardLabel(String name, String from, String size) {
    return '$name, de $from, $size';
  }

  @override
  String attachmentsDownloadLabel(String name) {
    return 'Baixar $name';
  }

  @override
  String attachmentsEmailLabel(String from) {
    return 'Abrir e-mail de $from';
  }

  @override
  String get attachmentsNoneNew => 'Nada de novo';

  @override
  String attachmentsTileLabel(String status) {
    return 'Anexos, $status';
  }

  @override
  String get attachmentsEmpty =>
      'Os arquivos que você recebe aparecem aqui, de todas as contas.';

  @override
  String attachmentsNoMatch(String query) {
    return 'Nenhum arquivo corresponde a “$query”';
  }

  @override
  String attachmentsNew(int count) {
    return '$count novos';
  }

  @override
  String get folderSnoozed => 'Adiados';

  @override
  String get snoozeUntilTitle => 'Adiar até…';

  @override
  String get snoozeEvening => 'Hoje à noite';

  @override
  String get snoozeMorning => 'Amanhã de manhã';

  @override
  String get snoozeWeekend => 'Fim de semana';

  @override
  String get snoozeNextWeek => 'Semana que vem';

  @override
  String snoozeTileToday(String time) {
    return 'hoje $time';
  }

  @override
  String snoozeToday(String time) {
    return 'hoje, $time';
  }

  @override
  String snoozeTomorrow(String time) {
    return 'amanhã, $time';
  }

  @override
  String snoozeTomorrowShort(String time) {
    return 'amanhã $time';
  }

  @override
  String snoozedMany(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas adiadas até $when',
      one: 'Adiado até $when',
    );
    return '$_temp0';
  }

  @override
  String get wakeNow => 'Voltar para a caixa';

  @override
  String wokenMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas de volta à caixa',
      one: 'De volta à caixa',
    );
    return '$_temp0';
  }

  @override
  String get sectionTomorrow => 'Amanhã';

  @override
  String get sectionLater => 'Mais tarde';

  @override
  String get sendLater => 'Enviar mais tarde';

  @override
  String get sendLaterTomorrowMorning => 'Amanhã de manhã';

  @override
  String get sendLaterTomorrowAfternoon => 'Amanhã à tarde';

  @override
  String get sendLaterMondayMorning => 'Segunda de manhã';

  @override
  String scheduleTomorrow(String time) {
    return 'Agendar para amanhã às $time';
  }

  @override
  String scheduleOn(String day, String time) {
    return 'Agendar para $day às $time';
  }

  @override
  String get sendLaterNote =>
      'Enviado deste dispositivo nesse horário. Se ele estiver desligado, sai assim que for ligado.';

  @override
  String scheduledToast(String when) {
    return 'Agendado para $when';
  }

  @override
  String get paletteLabel => 'Paleta de comandos';

  @override
  String get paletteHint => 'Pesquise ou execute um comando';

  @override
  String get paletteActions => 'Ações';

  @override
  String get paletteMessages => 'Mensagens';

  @override
  String paletteWriteTo(String name) {
    return 'Escrever para $name';
  }

  @override
  String paletteOnlyFrom(String name) {
    return 'Mostrar só mensagens de $name';
  }

  @override
  String paletteFilesFrom(String name) {
    return 'Anexos de $name';
  }

  @override
  String paletteFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos',
      one: '1 arquivo',
    );
    return '$_temp0';
  }

  @override
  String paletteSearchAll(String query) {
    return 'Pesquisar “$query” em todos os e-mails';
  }

  @override
  String paletteGoTo(String place) {
    return 'Ir para $place';
  }

  @override
  String get paletteMove => 'mover';

  @override
  String get paletteRun => 'executar';

  @override
  String get paletteAnywhere => 'de qualquer tela';

  @override
  String senderCardLabel(String name) {
    return 'Ficha de $name';
  }

  @override
  String get senderKind => 'Remetente';

  @override
  String get senderClose => 'Fechar ficha';

  @override
  String get senderWrite => 'Escrever';

  @override
  String get senderAll => 'Todos os e-mails';

  @override
  String get senderMute => 'Silenciar';

  @override
  String get senderMuted => 'Silenciado';

  @override
  String senderArrivesIn(String account) {
    return 'Chega em $account';
  }

  @override
  String get senderConversations => 'Conversas';

  @override
  String get senderNoMail =>
      'Ainda não há e-mails dessa pessoa neste dispositivo.';

  @override
  String senderMutedToast(String name) {
    return 'Sem mais notificações de $name';
  }

  @override
  String get rulesTitle => 'Regras e pastas';

  @override
  String get rulesSubtitle =>
      'Organiza seus e-mails do jeito que você faria. Cada regra se lê como uma frase.';

  @override
  String get rulesWhere =>
      'As regras rodam neste dispositivo, nos novos e-mails da caixa de entrada';

  @override
  String get rulesHeading => 'Regras';

  @override
  String get rulesNew => 'Nova regra';

  @override
  String get rulesEdit => 'Editar regra';

  @override
  String get rulesNone =>
      'Nenhuma regra sua ainda. Uma regra organiza os novos e-mails assim que chegam, do jeito que você faria.';

  @override
  String get ruleWhen => 'Quando';

  @override
  String get ruleThen => 'então';

  @override
  String get ruleFieldSender => 'o remetente';

  @override
  String get ruleFieldSubject => 'o assunto';

  @override
  String get ruleFieldRecipient => 'o destinatário';

  @override
  String get ruleOpContains => 'contém';

  @override
  String get ruleOpIs => 'é';

  @override
  String get ruleOpStarts => 'começa com';

  @override
  String get ruleOpNotContains => 'não contém';

  @override
  String get ruleDoMove => 'mover para';

  @override
  String get ruleDoArchive => 'arquivar';

  @override
  String get ruleDoRead => 'marcar como lido';

  @override
  String get ruleText => 'Texto a procurar';

  @override
  String get ruleTextHint => 'texto';

  @override
  String get ruleTrayField => 'Campo';

  @override
  String get ruleTrayOp => 'Condição';

  @override
  String get ruleTrayAction => 'Ação';

  @override
  String get ruleTrayFolder => 'Pasta';

  @override
  String get rulePickFolder => 'uma pasta';

  @override
  String get ruleNoFolders => 'Suas contas ainda não têm pastas próprias.';

  @override
  String get ruleApplyToo => 'Aplicar também a esses';

  @override
  String get ruleSave => 'Salvar regra';

  @override
  String get ruleDelete => 'Excluir regra';

  @override
  String get rulePaused => 'Pausada';

  @override
  String get ruleFresh => 'Ativa a partir de agora';

  @override
  String get foldersHeading => 'Pastas';

  @override
  String get foldersNone => 'Sem pastas próprias';

  @override
  String ruleApplies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vale para $count e-mails existentes',
      one: 'Vale para $count e-mail existente',
      zero: 'Nenhum e-mail existente corresponde',
    );
    return '$_temp0';
  }

  @override
  String ruleSorted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails organizados',
      one: '1 e-mail organizado',
    );
    return '$_temp0';
  }

  @override
  String ruleLastToday(String time) {
    return 'último hoje $time';
  }

  @override
  String ruleLastOn(String date) {
    return 'último $date';
  }

  @override
  String ruleSwitch(String rule) {
    return 'Regra ativa: $rule';
  }

  @override
  String rulesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Nenhuma',
    );
    return '$_temp0';
  }

  @override
  String get inviteLabel => 'Convite';

  @override
  String get inviteYes => 'Sim';

  @override
  String get inviteMaybe => 'Talvez';

  @override
  String get inviteNo => 'Não';

  @override
  String get inviteRespond => 'Responder ao convite';

  @override
  String get inviteAllDay => 'Dia inteiro';

  @override
  String get inviteRepeats => 'repete';

  @override
  String get inviteYouAccepted => 'Você aceitou';

  @override
  String get inviteYouTentative => 'Você respondeu talvez';

  @override
  String get inviteYouDeclined => 'Você recusou';

  @override
  String get inviteNotSent =>
      'Não foi possível enviar sua resposta. Tente de novo.';

  @override
  String get inviteCancelled => 'Este evento foi cancelado';

  @override
  String get inviteYours => 'Você enviou este convite';

  @override
  String inviteAttendees(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count participantes',
      one: '1 participante',
    );
    return '$_temp0';
  }

  @override
  String inviteWillGet(String name) {
    return '$name vai receber sua resposta';
  }

  @override
  String inviteQueued(String name) {
    return 'vai para $name quando você voltar a ficar on-line';
  }

  @override
  String inviteTheyAccepted(String name) {
    return '$name aceitou';
  }

  @override
  String inviteTheyTentative(String name) {
    return '$name respondeu talvez';
  }

  @override
  String inviteTheyDeclined(String name) {
    return '$name recusou';
  }

  @override
  String inviteSubjectAccepted(String summary) {
    return 'Aceito: $summary';
  }

  @override
  String inviteSubjectTentative(String summary) {
    return 'Talvez: $summary';
  }

  @override
  String inviteSubjectDeclined(String summary) {
    return 'Recusado: $summary';
  }

  @override
  String inviteTextAccepted(String name) {
    return '$name aceitou este convite.';
  }

  @override
  String inviteTextTentative(String name) {
    return '$name talvez vá.';
  }

  @override
  String inviteTextDeclined(String name) {
    return '$name recusou este convite.';
  }

  @override
  String inviteCard(String summary, String when) {
    return 'Convite: $summary, $when';
  }

  @override
  String get inviteFree => 'Livre · sem conflitos';

  @override
  String inviteOverlaps(String name, String time) {
    return 'Coincide com $name $time';
  }

  @override
  String inviteAvailability(String note) {
    return 'Disponibilidade: $note';
  }

  @override
  String inviteAddedTo(String name) {
    return 'adicionado a $name';
  }

  @override
  String get settingsCalendars => 'Calendários';

  @override
  String get calIntro =>
      'O Piuma não tem calendário próprio: conecte os que você já usa. Os eventos ficam lá.';

  @override
  String get calConnected => 'Calendários conectados';

  @override
  String calSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count origens',
      one: '1 origem',
    );
    return '$_temp0';
  }

  @override
  String calCalendars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calendários',
      one: '1 calendário',
    );
    return '$_temp0';
  }

  @override
  String get calConnect => 'Conectar um calendário';

  @override
  String get calChoose => 'Escolha de onde conectar';

  @override
  String get calCalDav => 'CalDAV';

  @override
  String get calCalDavParen => '(iCloud, Fastmail, Nextcloud…)';

  @override
  String get calCalDavSub => 'Servidor, e-mail e senha de app';

  @override
  String get calIcs => 'Assinar uma URL .ics';

  @override
  String get calIcsSub => 'Somente leitura, atualiza sozinho';

  @override
  String get calCalDavLabel => 'Endereço de e-mail ou servidor CalDAV';

  @override
  String get calCalDavHint =>
      'O iCloud precisa de uma senha de app; ela fica criptografada no chaveiro do sistema.';

  @override
  String get calIcsLabel => 'URL do calendário .ics';

  @override
  String get calIcsHint =>
      'Calendários .ics são somente leitura: úteis para feriados, esportes, turnos.';

  @override
  String get calUsername => 'Nome de usuário (se não for o e-mail)';

  @override
  String get calPassword => 'Senha';

  @override
  String get calConnectButton => 'Conectar';

  @override
  String get calSubscribe => 'Assinar';

  @override
  String get calSuggested =>
      'As contas de e-mail adicionadas que oferecem calendário são sugeridas automaticamente';

  @override
  String get calHasCalendar => 'também tem calendário';

  @override
  String get calDone => 'Conectado';

  @override
  String get calDisconnect => 'Desconectar';

  @override
  String calDisconnectLabel(String name) {
    return 'Desconectar $name';
  }

  @override
  String get calReadOnly => 'somente leitura';

  @override
  String get calInvitesTag => 'convites';

  @override
  String get calShowAvailability => 'Mostrar disponibilidade';

  @override
  String get calAvailabilityShort => 'disponibilidade';

  @override
  String calAvailabilityFor(String name) {
    return 'Mostrar disponibilidade de $name';
  }

  @override
  String get calNone =>
      'Nenhum calendário conectado. Os convites continuam funcionando, por e-mail.';

  @override
  String get calWhenInvite => 'Quando chega um convite';

  @override
  String get calAddTo => 'Adicionar a';

  @override
  String get calAddToSub => 'Para onde vão os convites que você aceita';

  @override
  String get calAddInvitesTo => 'Adicionar convites a';

  @override
  String get calNoWritable => 'Nenhum';

  @override
  String get calConflicts =>
      'Verificar conflitos em todos os calendários conectados';

  @override
  String get calConflictsSub =>
      'Os convites mostram na hora se você já está ocupado nesse horário.';

  @override
  String get calFooter =>
      'Sem calendários conectados, você ainda pode responder aos convites por e-mail e abrir o arquivo .ics.';

  @override
  String get calStaysHere =>
      'As conexões ficam neste dispositivo; as senhas ficam no chaveiro do sistema.';

  @override
  String get calWrongPassword => 'Nome de usuário ou senha incorretos.';

  @override
  String get calUnreachable =>
      'Nenhum calendário encontrado ali. Verifique o endereço.';

  @override
  String get calFailed => 'Não foi possível conectar. Tente de novo.';

  @override
  String get calTypeCalDav => 'CalDAV';

  @override
  String get calTypeIcs => 'URL .ics, somente leitura';

  @override
  String get calFromAccount => 'da conta de e-mail';

  @override
  String foundDateAdd(String when) {
    return 'Adicionar $when ao calendário';
  }

  @override
  String foundDateAdded(String calendar) {
    return 'Adicionado a $calendar';
  }

  @override
  String foundDateAddLabel(String when) {
    return 'Adicionar $when ao calendário, encontrado neste dispositivo';
  }

  @override
  String foundDateAddedLabel(String when, String calendar) {
    return '$when adicionado a $calendar';
  }

  @override
  String get foundOnDevice => 'Encontrado neste dispositivo';

  @override
  String get foundDateNotAdded =>
      'Não foi possível adicionar ao calendário. Tente de novo daqui a pouco.';

  @override
  String get calFindDates => 'Sugerir adicionar datas encontradas nos e-mails';

  @override
  String get calFindDatesSub =>
      'Uma pequena sugestão ao lado da frase, nunca automática.';

  @override
  String get calOnDevice => 'no dispositivo';

  @override
  String get inShort => 'Em resumo';

  @override
  String get generatedOnDevice => 'Gerado no dispositivo';

  @override
  String get yourTurn => 'Sua vez:';

  @override
  String yourTurnAsks(String name, String words) {
    return '$name escreve “$words”';
  }

  @override
  String get inShortColon => 'Em resumo:';

  @override
  String get onDevice => 'no dispositivo';

  @override
  String senderBriefTopic(String topic) {
    return 'principalmente sobre “$topic”';
  }

  @override
  String senderBriefCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails este mês',
      one: '1 e-mail este mês',
    );
    return '$_temp0';
  }

  @override
  String get senderBriefWaiting => 'o último espera sua resposta';

  @override
  String get searchByType => 'Pesquisar por tipo';

  @override
  String get frequentContacts => 'Contatos frequentes';

  @override
  String get recentSearches => 'Pesquisas recentes';

  @override
  String get clearRecent => 'Limpar';

  @override
  String get clearRecentSearches => 'Limpar pesquisas recentes';

  @override
  String get noRecentSearches => 'Nenhuma pesquisa recente.';

  @override
  String get searchOperatorsHint => 'Você também pode digitar operadores';

  @override
  String searchIndexed(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$formatted e-mails indexados neste dispositivo · funciona sem conexão',
      one: '1 e-mail indexado neste dispositivo · funciona sem conexão',
    );
    return '$_temp0';
  }

  @override
  String get searchWithAttachments => 'Com anexos';

  @override
  String get searchFromPeople => 'De pessoas';

  @override
  String searchMailFrom(String name) {
    return 'Pesquisar e-mails de $name';
  }

  @override
  String removeRecentSearch(String query) {
    return 'Remover $query';
  }

  @override
  String get searchAddWords => 'Adicionar palavras…';

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
      other: '$count anexos',
      one: '1 anexo',
    );
    return '$_temp0';
  }

  @override
  String get senderBlock => 'Bloquear';

  @override
  String get senderBlocked => 'Bloqueado';

  @override
  String showSnoozed(int count) {
    return 'Mostrar adiados ($count)';
  }

  @override
  String get hideSnoozed => 'Ocultar adiados';

  @override
  String get snoozeNoReply => 'Se ninguém responder';

  @override
  String get snoozeNoReplyHint => 'Volta em 3 dias se não houver resposta';

  @override
  String get previewClose => 'Fechar prévia';

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
  String get previewNextPage => 'Próxima página';

  @override
  String previewOpenEmail(String name) {
    return 'Abrir o e-mail de $name';
  }

  @override
  String get previewDownloadAll => 'Baixar tudo';

  @override
  String previewPhoto(int index, int count) {
    return 'Foto $index de $count · do mesmo e-mail';
  }

  @override
  String get previewPhotos => 'Fotos do e-mail';

  @override
  String get previewCantShow =>
      'Este arquivo não pode ser mostrado aqui. Você ainda pode baixá-lo.';

  @override
  String previewPageLabel(int page, String name) {
    return 'Página $page de $name';
  }

  @override
  String get vaultParcelsTitle => 'Entregas de encomendas';

  @override
  String get vaultParcelsHint => 'No dia da entrega, só uma vez.';

  @override
  String get vaultDueTitle => 'Vencimentos';

  @override
  String get vaultDueHint =>
      'Contas e renovações, com três dias de antecedência.';

  @override
  String get vaultNoticeParcel => 'Sua encomenda chega hoje';

  @override
  String get vaultNoticeDueToday => 'Vence hoje';

  @override
  String get vaultNoticeDueTomorrow => 'Vence amanhã';

  @override
  String vaultNoticeDueIn(int days) {
    return 'Vence em $days dias';
  }

  @override
  String vaultNoticeAround(String time) {
    return 'por volta das $time';
  }

  @override
  String pecCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails certificados',
      one: '1 e-mail certificado',
    );
    return '$_temp0';
  }

  @override
  String pecNotDelivered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count não entregues',
      one: '$count não entregue',
    );
    return '$_temp0';
  }

  @override
  String get pecSent => 'Enviado';

  @override
  String get pecAccepted => 'Aceito';

  @override
  String get pecDelivered => 'Entregue';

  @override
  String get pecFailed => 'Não entregue';

  @override
  String pecTo(String who) {
    return 'Para $who';
  }

  @override
  String pecToMany(int count, int delivered) {
    return 'Para $count destinatários · $delivered de $count entregues';
  }

  @override
  String pecAcceptedAt(String when) {
    return 'Aceito $when';
  }

  @override
  String pecDeliveredAt(String when) {
    return 'Entregue $when';
  }

  @override
  String pecFailedAt(String when) {
    return 'Não entregue · $when';
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
      other: '$count recibos salvos em Downloads',
      one: 'Recibo salvo em Downloads',
    );
    return '$_temp0';
  }

  @override
  String get pecNotSaved => 'Não foi possível salvar o recibo';

  @override
  String get pecNote =>
      'Os recibos ficam fora da caixa de entrada e se juntam na mensagem a que pertencem. Recibo salva a prova assinada como arquivo.';

  @override
  String get pecUnverified => 'Não verificado';

  @override
  String pecUnverifiedNote(String status) {
    return 'Indica “$status”, mas não foi possível verificar a assinatura do provedor: não vale como prova.';
  }

  @override
  String get pickDateTime => 'Escolher data e hora';

  @override
  String get previousMonth => 'Mês anterior';

  @override
  String get nextMonth => 'Próximo mês';

  @override
  String get pickTime => 'Hora';

  @override
  String get pickOtherTime => 'Outro horário';

  @override
  String get pickTimeGone => 'Esse horário já passou';

  @override
  String snoozeUntilAt(String when) {
    return 'Adiar até $when';
  }

  @override
  String scheduleAt(String when) {
    return 'Agendar para $when';
  }

  @override
  String get senderNewsletterKind => 'Newsletter';

  @override
  String newsletterPerWeek(int count) {
    return 'cerca de $count por semana';
  }

  @override
  String newsletterPerMonth(int count) {
    return 'cerca de $count por mês';
  }

  @override
  String newsletterOpened(int percent) {
    return 'você abre $percent%';
  }

  @override
  String get newsletterUnsubscribed => 'Inscrição cancelada';

  @override
  String get newsletterClearAsk => 'apagar também os e-mails antigos?';

  @override
  String get newsletterClearYes => 'Sim, apagar';

  @override
  String get newsletterClearNo => 'Não';

  @override
  String newsletterCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Inscrição cancelada · $count e-mails movidos para a lixeira',
      one: 'Inscrição cancelada · 1 e-mail movido para a lixeira',
    );
    return '$_temp0';
  }

  @override
  String get newsletterKept =>
      'Inscrição cancelada · os e-mails antigos ficam como estão';

  @override
  String get newsletterPageOpened =>
      'A página de cancelamento está aberta no navegador';

  @override
  String get moveToNewsletters => 'Mover para Newsletters';

  @override
  String get movedToNewsletters => 'Movido para Newsletters';

  @override
  String searchFileMeta(String size, String name, String when) {
    return '$size · $name · $when';
  }

  @override
  String get searchHasFiles => 'Com anexo';

  @override
  String get appearanceTitle => 'Aparência';

  @override
  String get appearanceSubtitle => 'Como você quer que seus e-mails fiquem.';

  @override
  String get appearanceTheme => 'Tema';

  @override
  String get themeAutomatic => 'Automático';

  @override
  String get appearanceDensity => 'Densidade';

  @override
  String get densityComfortable => 'Confortável';

  @override
  String get densityCompact => 'Compacta';

  @override
  String get appearancePreview => 'Prévia';

  @override
  String previewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count linhas',
      one: '1 linha',
    );
    return '$_temp0';
  }

  @override
  String get readingOpenIn => 'Abrir e-mails em';

  @override
  String get readingOpenInHint =>
      'Para e-mails com layout. Você ainda pode trocar a vista em cada um, e as imagens remotas continuam esperando seu ok.';

  @override
  String get appearanceExample => 'Exemplo';

  @override
  String get previewDrawnHere => 'Desenhado neste dispositivo';

  @override
  String get previewKeysPages => '← → páginas';

  @override
  String get previewKeysPhotos => '← → fotos';

  @override
  String get meInitials => 'EU';

  @override
  String get threadSummary => 'Resumo';

  @override
  String get signatureSheetTitle => 'Assinatura';

  @override
  String get signatureManage => 'Gerenciar';

  @override
  String get signatureSheetNote =>
      'A assinatura muda automaticamente quando você troca a conta “De”.';

  @override
  String get readerEmptyTitle => 'Nenhuma conversa selecionada';

  @override
  String readerEmptyHint(String keys) {
    return 'Clique em uma mensagem para selecioná-la, ou pressione $keys para selecionar todas.';
  }

  @override
  String get hintMove => 'mover';

  @override
  String get accountConnected => 'Conta conectada';

  @override
  String get accountConnectedLead =>
      'Você já pode começar a ler: o resto chega enquanto você usa o Piuma.';

  @override
  String get connectedDownloading => 'Baixando, os mais recentes primeiro…';

  @override
  String get connectedUpToDate => 'Em dia';

  @override
  String get goToInbox => 'Ir para a caixa de entrada';

  @override
  String get addAnotherAccount => 'Adicionar outra conta';

  @override
  String filterFrom(String name) {
    return 'De: $name';
  }

  @override
  String get syncLeftUnderMinute => 'menos de um minuto';

  @override
  String syncLeftMinutes(int n) {
    return 'cerca de $n min';
  }

  @override
  String syncLeftHours(int n) {
    return 'cerca de $n h';
  }

  @override
  String phoneSearchSyncing(String hint, String name) {
    return '$hint · sincronizando $name';
  }

  @override
  String sendTomorrowAt(String time) {
    return 'Enviar amanhã $time';
  }

  @override
  String get sendOptions => 'Opções de envio';

  @override
  String get inboxSections => 'Seções da caixa de entrada';

  @override
  String get tabPeople => 'Pessoas';

  @override
  String get tabNotifications => 'Notificações';

  @override
  String get zoneNothingNew => 'Nada de novo';

  @override
  String get tabAll => 'Todos';

  @override
  String get filterUnreadHint => 'Só os emails com algo por ler';

  @override
  String get moveToPeople => 'Mover para Pessoas';

  @override
  String movedToPeople(String sender) {
    return '$sender vai para Pessoas a partir de agora';
  }

  @override
  String movedToNotifications(String sender) {
    return '$sender vai para Notificações a partir de agora';
  }

  @override
  String get moveToNotifications => 'Mover para Notificações';

  @override
  String tabUnread(String tab, int count) {
    return '$tab, $count não lidos';
  }

  @override
  String get templatesTitle => 'Modelos';

  @override
  String get templatesSearch => 'Pesquisar modelos';

  @override
  String templatesFound(int found, int total) {
    return '$found de $total';
  }

  @override
  String get templatesNone =>
      'Nenhum modelo ainda. Salve o que você escreve como um.';

  @override
  String templatesNoMatch(String query) {
    return 'Nenhum modelo chamado “$query”';
  }

  @override
  String get templateSaveThis => 'Salvar como modelo';

  @override
  String get templatesManage => 'Gerenciar';

  @override
  String get templateUntitled => 'Modelo sem título';

  @override
  String templateSavedNote(String name) {
    return 'Salvo como modelo “$name”';
  }

  @override
  String get templatesSubtitle => 'Neste dispositivo, para todas as contas';

  @override
  String get templatesNew => 'Novo modelo';

  @override
  String get templateNameLabel => 'Nome';

  @override
  String get templateTextLabel => 'Texto';

  @override
  String templateSubjectLine(String subject) {
    return 'Assunto: $subject';
  }

  @override
  String get templateNoSubject => 'Sem assunto';

  @override
  String get templateSavedAsYouType => 'Salvo enquanto você digita';

  @override
  String get templateNotSaved => 'Não foi possível salvar o modelo';

  @override
  String get accountNameLabel => 'Nome';

  @override
  String get accountDisplayName => 'Nome de exibição';

  @override
  String get accountDisplayNameNone => 'Não definido';

  @override
  String get accountDefaultSignature => 'Assinatura padrão';

  @override
  String get accountConnection => 'Conexão';

  @override
  String accountWorkingAgo(String ago) {
    return 'Funcionando · verificado $ago';
  }

  @override
  String get accountJustNow => 'agora mesmo';

  @override
  String accountMinutesAgo(int count) {
    return 'há $count min';
  }

  @override
  String accountAtTime(String time) {
    return 'às $time';
  }

  @override
  String get accountConnecting => 'Conectando…';

  @override
  String accountCantSignInSince(String time) {
    return 'Não consegue entrar desde $time';
  }

  @override
  String get accountPasswordRefused => 'O servidor recusou a senha. Ela mudou?';

  @override
  String get accountCertificateRefused =>
      'O certificado do servidor foi recusado. Entre de novo para conferi-lo.';

  @override
  String get accountEditServers => 'Editar servidores';

  @override
  String get accountSignInAlert => 'Avisar quando não conseguir entrar';

  @override
  String get accountSignInAlertNote =>
      'Um único aviso, na primeira vez que a senha for recusada';

  @override
  String get accountRemove => 'Remover conta';

  @override
  String accountRemoveTitle(String name) {
    return 'Remover $name deste dispositivo?';
  }

  @override
  String get accountRemoveNote =>
      'Os e-mails dela aqui são apagados. No servidor, tudo fica como está.';

  @override
  String get accountRemoveConfirm => 'Remover';

  @override
  String accountRemoveBlocked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count mensagens escritas aqui ainda não saíram. Envie ou apague, depois remova a conta.',
      one: '1 mensagem escrita aqui ainda não saiu. Envie ou apague, depois remova a conta.',
    );
    return '$_temp0';
  }

  @override
  String get accountUnsentDraft => 'Rascunho neste dispositivo';

  @override
  String get accountUnsentSendNow => 'Enviar agora';

  @override
  String get accountUnsentSaveNow => 'Salvar agora';

  @override
  String get accountUnsentFailed =>
      'Não funcionou. Verifique a conexão e tente de novo, ou apague.';

  @override
  String get updatingMail => 'Atualizando seu e-mail';

  @override
  String get updatingMailNote =>
      'O Piuma foi atualizado e está preparando seu e-mail. Só acontece uma vez, e fechar o app enquanto isso não faz perder nada.';

  @override
  String get storageTitle => 'Armazenamento';

  @override
  String get storageSubtitle =>
      'O e-mail guardado neste dispositivo. No servidor fica tudo.';

  @override
  String storageTotal(String size) {
    return '$size neste dispositivo';
  }

  @override
  String storageAccountLine(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$_temp0 · $size guardados para ler offline';
  }

  @override
  String get storageClear => 'Limpar o e-mail em cache';

  @override
  String get storageClearing => 'Limpando…';

  @override
  String storageBackup(String size) {
    return 'Dos quais $size são uma cópia de antes da última atualização, removida no próximo início.';
  }

  @override
  String get storageClearFailed =>
      'Não foi possível limpar o e-mail guardado. Tente de novo.';

  @override
  String get storageNoRoom =>
      'E-mail guardado limpo. Não há espaço livre suficiente para diminuir o arquivo agora: o Piuma reutiliza o espaço.';

  @override
  String storageClearTitle(String name) {
    return 'Limpar o e-mail em cache de $name?';
  }

  @override
  String get storageClearNote =>
      'As mensagens completas e as imagens guardadas para ler offline são removidas deste dispositivo. As listas ficam, a busca ainda encontra suas palavras, o e-mail fica no servidor, e uma mensagem é baixada de novo quando você a abre. Primeiro saem os e-mails antigos que uma busca encontrou no servidor, a não ser que você os tenha marcado com estrela ou etiquetado: buscando de novo, você os encontra lá.';

  @override
  String get storageKeep => 'Guardar as mensagens completas para ler offline';

  @override
  String get storageKeepHint =>
      'As mais antigas são baixadas de novo quando você as abre. A busca ainda encontra suas palavras.';

  @override
  String get storageKeepMonth => '1 mês';

  @override
  String get storageKeepMonths => '3 meses';

  @override
  String get storageKeepYear => '1 ano';

  @override
  String get storageKeepAlways => 'Sempre';

  @override
  String get accountServersTitle => 'Servidores';

  @override
  String get accountServersSave => 'Salvar';

  @override
  String get accountServersChecking => 'Verificando…';

  @override
  String accountDetailsLabel(String name, String email) {
    return '$name, $email';
  }

  @override
  String noticeSignInTitle(String name) {
    return '$name não consegue entrar';
  }

  @override
  String get orStartFrom => 'Ou comece por';

  @override
  String needsAppPassword(String provider) {
    return '$provider precisa de uma senha de app';
  }

  @override
  String get fastmailNeedsToken => 'O Fastmail precisa de um token de API';

  @override
  String get gmailStep1 =>
      'Ative a verificação em duas etapas na sua Conta do Google.';

  @override
  String get gmailStep2 => 'Abra Senhas de app e crie uma chamada “Piuma”.';

  @override
  String get gmailStep3 => 'Cole as 16 letras aqui.';

  @override
  String get openAppPasswords => 'Abrir Senhas de app';

  @override
  String get icloudStep1 =>
      'Ative a autenticação de dois fatores na sua Conta Apple.';

  @override
  String get icloudStep2 =>
      'Em Início de Sessão e Segurança, abra Senhas Específicas de Apps e crie uma chamada “Piuma”.';

  @override
  String get icloudStep3 => 'Cole aqui.';

  @override
  String get openAppleAccount => 'Abrir Conta Apple';

  @override
  String get fastmailStep1 =>
      'Em Settings, abra Privacy & Security e depois Manage API tokens.';

  @override
  String get fastmailStep2 =>
      'Crie um token chamado “Piuma” com acesso a Email e Email submission.';

  @override
  String get fastmailStep3 => 'Cole aqui.';

  @override
  String get openApiTokens => 'Abrir tokens de API';

  @override
  String get appPassword => 'Senha de app';

  @override
  String get apiToken => 'Token de API';

  @override
  String get pecWhichProvider => 'Quem gerencia sua PEC?';

  @override
  String get pecWhichProviderHint =>
      'O e-mail certificado vem com os servidores do seu provedor.';

  @override
  String signInToPec(String provider) {
    return 'Entrar em $provider';
  }

  @override
  String get pecStep1 => 'Use o endereço PEC completo.';

  @override
  String get pecStep2 => 'Use a senha da caixa, a mesma do webmail.';

  @override
  String get verifiedSenderSetting => 'Mostrar remetente verificado';

  @override
  String get verifiedSenderSettingHint =>
      'Marca os remetentes que seu servidor de e-mail verificou com DKIM, SPF e DMARC.';

  @override
  String get verifiedBadge => 'Verificado';

  @override
  String get verifiedSenderLabel => 'Remetente verificado';

  @override
  String get ruleFieldBody => 'o corpo';

  @override
  String get newFolder => 'Nova pasta';

  @override
  String get newFolderName => 'Nome da nova pasta';

  @override
  String get create => 'Criar';

  @override
  String get newFolderFailed =>
      'O servidor não criou a pasta. Tente outro nome.';

  @override
  String get groupsTitle => 'Grupos';

  @override
  String get groupsSubtitle =>
      'Reúna endereços de contas e domínios diferentes. Cada grupo tem sua cor, sua assinatura e, se quiser, sua própria caixa de entrada.';

  @override
  String get groupsNone =>
      'Nenhum grupo ainda. Um grupo reúne endereços, mesmo de contas diferentes, sob uma cor e uma assinatura.';

  @override
  String groupsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count',
      zero: 'Nenhum',
    );
    return '$_temp0';
  }

  @override
  String groupAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count endereços',
      one: '1 endereço',
    );
    return '$_temp0';
  }

  @override
  String get groupSignatureShort => 'Assinatura';

  @override
  String get groupSendFromShort => 'Enviar de';

  @override
  String get groupNoSignature => 'Nenhuma';

  @override
  String get groupName => 'Nome do grupo';

  @override
  String get groupColor => 'Cor do grupo';

  @override
  String get groupAddressesHeading => 'Endereços';

  @override
  String get groupAccount => 'Conta';

  @override
  String get groupAlias => 'Alias';

  @override
  String groupAccountNote(String name) {
    return 'Conta $name';
  }

  @override
  String groupAliasNote(String email) {
    return 'em $email';
  }

  @override
  String groupRemoveAddress(String email) {
    return 'Remover $email do grupo';
  }

  @override
  String get groupAddAddress => 'Adicionar endereço';

  @override
  String get groupDefaultSignature => 'Assinatura padrão';

  @override
  String get groupSendFrom => 'Enviar novos e-mails de';

  @override
  String get groupSeparateInbox => 'Caixa separada';

  @override
  String get groupSeparateOn =>
      'Ganha seu próprio item na barra lateral. Também continua na caixa unificada.';

  @override
  String get groupSeparateOff => 'Os e-mails dele ficam só na caixa unificada.';

  @override
  String get groupNotifyOn => 'Segue suas regras de notificação.';

  @override
  String get groupNotifyOff => 'Sem alertas para este grupo.';

  @override
  String get groupReplyAsWritten =>
      'Sempre responder do endereço para o qual escreveram';

  @override
  String groupReplyOn(String email) {
    return 'Se alguém escrever para $email, sua resposta sai de $email, com a assinatura desse grupo.';
  }

  @override
  String get groupReplyOnAny =>
      'Se alguém escrever para um dos seus aliases, sua resposta sai dele, com a assinatura do grupo dele.';

  @override
  String get groupReplyOff => 'As respostas saem do endereço padrão do grupo.';

  @override
  String get groupNew => 'Novo grupo';

  @override
  String get groupNewName => 'Novo grupo';

  @override
  String get groupDelete => 'Excluir grupo';

  @override
  String groupDeleteAsk(String name) {
    return 'Excluir $name?';
  }

  @override
  String get groupDeleteNote =>
      'Os endereços dele ficam nas suas contas; só o grupo é excluído.';

  @override
  String get groupYourAddresses => 'Seus endereços';

  @override
  String get groupMovesHere => 'Em outro grupo: passa para cá';

  @override
  String get groupFoundInSent => 'Encontrado nos seus e-mails enviados';

  @override
  String get groupNewAlias => 'Novo alias';

  @override
  String get groupNewAliasHint => 'nome@dominio.com';

  @override
  String get groupAliasOn => 'em';

  @override
  String get groupAddAlias => 'Adicionar';

  @override
  String get groupAliasInvalid => 'Isso não parece um endereço de e-mail.';

  @override
  String get fromAutomatic => 'Automático';

  @override
  String fromAutomaticWhy(String name, String email) {
    return 'Escolhido porque $name escreveu para $email';
  }

  @override
  String rowWrittenTo(String email) {
    return 'para $email';
  }

  @override
  String get groupsAll => 'Todos os grupos';

  @override
  String groupExpand(String name) {
    return 'Expandir $name';
  }

  @override
  String groupCollapse(String name) {
    return 'Recolher $name';
  }

  @override
  String groupUnreadLine(int addresses, int unread) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses endereços',
      one: '1 endereço',
    );
    return '$_temp0 · $unread não lidos';
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
      other: '$addresses endereços',
      one: '1 endereço',
    );
    return '$_temp0 · $_temp1 · $unread não lidos';
  }

  @override
  String groupOnly(String email) {
    return 'Só $email';
  }

  @override
  String groupOnlyClear(String email) {
    return 'Só $email. Mostrar o grupo todo';
  }

  @override
  String get groupSheetTitle => 'Mostrar';

  @override
  String groupSheetLine(int addresses, int groups) {
    String _temp0 = intl.Intl.pluralLogic(
      addresses,
      locale: localeName,
      other: '$addresses endereços',
      one: '1 endereço',
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
  String get groupSheetLabel => 'Escolher grupo';

  @override
  String get groupManage => 'Gerenciar grupos';

  @override
  String get groupTitleAll => 'Grupo: todos. Trocar de grupo';

  @override
  String groupTitleOne(String name) {
    return 'Grupo: $name. Trocar de grupo';
  }

  @override
  String get syncTitle => 'Dispositivos e sincronização';

  @override
  String get syncSubtitle =>
      'Suas configurações em todos os dispositivos, com criptografia de ponta a ponta';

  @override
  String get syncOff => 'Desativada · só este dispositivo';

  @override
  String get syncOffBody =>
      'Tenha suas contas, grupos, assinaturas e configurações em todos os dispositivos. Elas são criptografadas aqui e guardadas em uma pasta oculta de uma das suas caixas. Sem servidor.';

  @override
  String get syncOffNote =>
      'As senhas só viajam dentro da cópia criptografada.';

  @override
  String get syncStoreIn => 'Guardar em';

  @override
  String get syncMailbox => 'Caixa de sincronização';

  @override
  String get syncMoving => 'Movendo…';

  @override
  String get syncFailTaken =>
      'Essa caixa já contém outro espaço de sincronização.';

  @override
  String get syncTurnOn => 'Ativar sincronização';

  @override
  String get syncAllSynced => 'Tudo sincronizado';

  @override
  String get syncNotYet => 'Ainda não sincronizado';

  @override
  String syncOnBody(String name) {
    return 'Contas, grupos, assinaturas e configurações são criptografados e guardados na sua caixa $name. Sem servidor.';
  }

  @override
  String syncOnLine(String email) {
    return '$email · pasta oculta · criptografia de ponta a ponta';
  }

  @override
  String get syncDevices => 'Dispositivos vinculados';

  @override
  String get syncThisDevice => 'Este dispositivo';

  @override
  String get syncActiveNow => 'Ativo agora';

  @override
  String syncActive(String ago) {
    return 'Ativo $ago';
  }

  @override
  String syncHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String get syncYesterday => 'ontem';

  @override
  String syncDaysAgo(int count) {
    return 'há $count dias';
  }

  @override
  String get syncUnlink => 'Desvincular';

  @override
  String syncUnlinkName(String name) {
    return 'Desvincular $name';
  }

  @override
  String syncUnlinkAsk(String name) {
    return 'Desvincular $name?';
  }

  @override
  String get syncUnlinkNote =>
      'Ele mantém o que tem agora, mas não recebe mais alterações. Sua frase de recuperação também muda: você vai anotar a nova.';

  @override
  String get syncLinkNew => 'Vincular um novo dispositivo';

  @override
  String syncLinkBody(String email) {
    return 'No novo dispositivo, abra o Piuma, escolha “Já uso o Piuma em outro dispositivo” e entre em $email. Ele mostra 6 dígitos, e este dispositivo vai pedi-los.';
  }

  @override
  String get syncLinkWaiting => 'Aguardando o novo dispositivo…';

  @override
  String get syncLinkScan =>
      'No novo telefone, abra o Piuma, escolha “Já uso o Piuma em outro dispositivo” e escaneie este código.';

  @override
  String get syncLinkQrLabel => 'Código QR para vincular um novo dispositivo';

  @override
  String syncLinkNewCode(String waiting, String time) {
    return '$waiting · novo código em $time';
  }

  @override
  String syncLinkNoCamera(String email) {
    return 'Sem câmera? Entre em $email no novo dispositivo: ele mostra 6 dígitos, e este dispositivo vai pedi-los.';
  }

  @override
  String syncLinked(String name) {
    return '$name vinculado';
  }

  @override
  String get syncPhraseRow => 'Frase de recuperação';

  @override
  String get syncPhraseRowLine =>
      'Abre seu espaço se todos os dispositivos forem perdidos';

  @override
  String get syncShow => 'Mostrar';

  @override
  String get syncPhraseTitle => 'Sua frase de recuperação';

  @override
  String get syncPhraseBody =>
      'Se você perder todos os dispositivos, estas 24 palavras são o único jeito de voltar ao seu espaço. Escreva-as em papel e guarde-as bem. O Piuma não consegue recuperá-las para você.';

  @override
  String get syncPhraseNewTitle => 'Sua nova frase de recuperação';

  @override
  String syncPhraseNewBody(String name) {
    return '$name não consegue mais abrir seu espaço, e a frase antiga não funciona mais. Escreva estas 24 palavras em papel no lugar dela.';
  }

  @override
  String get syncPhraseWarn => 'Quem tiver estas palavras pode ler seu espaço.';

  @override
  String get syncPhraseDone => 'Já anotei';

  @override
  String syncPhraseWord(int index, String word) {
    return '$index. $word';
  }

  @override
  String syncAskTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Um novo celular quer se conectar',
      'tablet': 'Um novo tablet quer se conectar',
      'other': 'Um novo computador quer se conectar',
    });
    return '$_temp0';
  }

  @override
  String syncAskLine(String name, String ago) {
    return '$name · pediu $ago';
  }

  @override
  String syncAskCode(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Digite os 6 dígitos que o celular mostra.',
      'tablet': 'Digite os 6 dígitos que o tablet mostra.',
      'other': 'Digite os 6 dígitos que o computador mostra.',
    });
    return '$_temp0';
  }

  @override
  String get syncAskDigits => 'Os 6 dígitos';

  @override
  String get syncNotMe => 'Não fui eu';

  @override
  String get syncApprove => 'Aprovar';

  @override
  String get syncApproving => 'Aprovando…';

  @override
  String syncFailOffline(String email) {
    return 'Não foi possível alcançar $email. Tente de novo quando estiver on-line.';
  }

  @override
  String get syncFailExpired =>
      'O pedido expirou. Peça de novo pelo novo dispositivo.';

  @override
  String get syncFailOther => 'Algo deu errado. Tente de novo.';

  @override
  String get syncRowOn => 'Ativada';

  @override
  String get syncRowOff => 'Desativada';

  @override
  String get pairAlready => 'Já uso o Piuma em outro dispositivo';

  @override
  String get pairAlreadyOn =>
      'Entre em uma das suas caixas. Se ela guardar seu espaço, você vincula este dispositivo em seguida.';

  @override
  String get pairLinkTitle => 'Vincular este telefone';

  @override
  String get pairLinkBody =>
      'No computador, abra Configurações › Dispositivos e sincronização › Vincular um novo dispositivo e escaneie o código que ele mostra.';

  @override
  String get pairScan => 'Escanear código';

  @override
  String get pairSignInInstead => 'Entrar em vez disso';

  @override
  String get pairScanHint => 'Aponte para o código no computador';

  @override
  String get pairScanWhere =>
      'Configurações › Dispositivos e sincronização › Vincular um novo dispositivo';

  @override
  String get pairNoCamera =>
      'O Piuma não pode usar a câmera. Permita nos ajustes do sistema, ou entre em vez disso.';

  @override
  String get pairLastStep => 'Um último passo';

  @override
  String get pairLastStepBody =>
      'Entre na caixa que guarda seu espaço. As outras contas chegam sozinhas.';

  @override
  String get pairConfirmsOwn =>
      'O computador confirma sozinho: foi ele que mostrou o código.';

  @override
  String get pairLink => 'Vincular';

  @override
  String get pairLinking => 'Vinculando…';

  @override
  String get pairFoundTitle => 'Encontramos seu espaço';

  @override
  String pairFoundBody(String email) {
    return 'A caixa $email guarda uma cópia criptografada das suas configurações. Só seus dispositivos conseguem lê-la.';
  }

  @override
  String pairAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'contas',
      one: 'conta',
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
      other: 'assinaturas',
      one: 'assinatura',
    );
    return '$_temp0';
  }

  @override
  String pairEncrypted(String when) {
    return 'Criptografia de ponta a ponta · atualizado $when';
  }

  @override
  String pairConfirmFrom(String name, String ago) {
    return 'Por segurança, confirme em um dispositivo já vinculado: $name, ativo $ago.';
  }

  @override
  String get pairShowCode => 'Mostrar código';

  @override
  String get pairUsePhrase => 'Usar frase de recuperação';

  @override
  String pairCodeTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Confirme no seu celular',
      'tablet': 'Confirme no seu tablet',
      'other': 'Confirme no seu computador',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBody(String name) {
    return 'Abra o Piuma em $name e digite o código.';
  }

  @override
  String pairCodeLabel(String digits) {
    return 'Código $digits';
  }

  @override
  String pairExpiresIn(String time) {
    return 'Expira em $time';
  }

  @override
  String pairWaiting(String name) {
    return 'Aguardando $name confirmar…';
  }

  @override
  String pairStep1(String name, String title) {
    return '$name vai mostrar “$title”';
  }

  @override
  String get pairStep2 => 'Digite os 6 dígitos e toque em Aprovar';

  @override
  String get pairExpired => 'O código expirou.';

  @override
  String pairRefused(String name) {
    return '$name disse que não era você.';
  }

  @override
  String get pairWrongCode => 'O código digitado lá não era este.';

  @override
  String get pairNewCode => 'Mostrar um novo código';

  @override
  String get pairPhraseTitle => 'Frase de recuperação';

  @override
  String get pairPhraseBody =>
      'Digite as 24 palavras que você anotou, em ordem, separadas por espaços.';

  @override
  String pairPhraseCount(int count) {
    return '$count de 24 palavras';
  }

  @override
  String get pairPhraseWrong =>
      'Estas palavras não abrem seu espaço. Confira-as e tente de novo.';

  @override
  String get pairPhraseOld =>
      'Esta frase de recuperação foi substituída: seu espaço recebeu uma mais nova quando um dispositivo foi desvinculado ou desativou a sincronização. Use a frase mais recente, ou um código de um dispositivo vinculado.';

  @override
  String get pairConflict =>
      'Dois dos seus dispositivos removeram um ao outro, por isso ainda não é possível entrar neste espaço. Altere a senha da caixa de correio que o guarda, sincronize um dispositivo que você ainda tem e tente de novo.';

  @override
  String get pairContinue => 'Continuar';

  @override
  String pairDoneTitle(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Celular vinculado',
      'tablet': 'Tablet vinculado',
      'other': 'Computador vinculado',
    });
    return '$_temp0';
  }

  @override
  String get pairDoneBody => 'Isto é o que veio do seu espaço criptografado.';

  @override
  String get pairDoneAccounts => 'Contas';

  @override
  String get pairDoneGroups => 'Grupos';

  @override
  String get pairDoneSettings => 'Assinaturas e configurações sincronizadas';

  @override
  String get pairSynced => 'Sincronizado';

  @override
  String pairStepOf(int step) {
    return 'Etapa $step de 3';
  }

  @override
  String pairTodayAt(String time) {
    return 'hoje às $time';
  }

  @override
  String pairYesterdayAt(String time) {
    return 'ontem às $time';
  }

  @override
  String pairOnDay(String day) {
    return 'em $day';
  }

  @override
  String get keyOpenWindow => 'abrir em nova janela';

  @override
  String syncedOnDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sincronizado em $count dispositivos',
      one: 'Sincronizado em 1 dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get ruleNewsletters =>
      'Quando uma newsletter foi lida há mais de 7 dias';

  @override
  String get ruleBuiltIn => 'Integrada · todas as contas';

  @override
  String get syncTurnOff => 'Desativar a sincronização neste dispositivo';

  @override
  String get syncTurnOffAsk => 'Desativar a sincronização neste dispositivo?';

  @override
  String syncTurnOffOne(String name) {
    return 'Este dispositivo sai do seu espaço e para de receber alterações. As contas e os e-mails dele ficam aqui. $name continua sincronizando.';
  }

  @override
  String syncTurnOffMany(String names) {
    return 'Este dispositivo sai do seu espaço e para de receber alterações. As contas e os e-mails dele ficam aqui. $names continuam sincronizando.';
  }

  @override
  String syncTurnOffLast(String email) {
    return 'Este dispositivo sai do seu espaço e para de receber alterações. As contas e os e-mails dele ficam aqui. Ele é seu único dispositivo: a cópia criptografada em $email também é apagada.';
  }

  @override
  String get syncTurnOffButton => 'Desativar sincronização';

  @override
  String get listAnd => 'e';

  @override
  String get composeDropFiles => 'Solte para anexar';

  @override
  String get serverType => 'Tipo de servidor';

  @override
  String get imapAndSmtp => 'IMAP e SMTP';

  @override
  String get jmapServer => 'Servidor JMAP';

  @override
  String get jmapServerHint =>
      'O nome do servidor, ou o endereço completo da sessão JMAP dele.';

  @override
  String get jmapSignsIn =>
      'Um só servidor lê, envia e traz os novos e-mails. Você entra com seu endereço.';

  @override
  String get shortcutsTitle => 'Atalhos';

  @override
  String shortcutsLine(String keys) {
    return 'Só o essencial. Todo o resto está em $keys.';
  }

  @override
  String get shortcutsTable => 'Atalhos de teclado';

  @override
  String get shortcutPalette => 'Paleta de comandos';

  @override
  String ruleSuggest(String name, String folder) {
    return 'Você costuma mover os e-mails de $name para $folder. Criar uma regra?';
  }

  @override
  String ruleSuggestMeta(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sugerido no dispositivo · $count movimentos no último mês',
      one: 'Sugerido no dispositivo · 1 movimento no último mês',
    );
    return '$_temp0';
  }

  @override
  String get actionForward => 'Encaminhar';

  @override
  String forwardBlock(String from, String date, String to, String subject) {
    return '---------- Mensagem encaminhada ----------\nDe: $from\nData: $date\nPara: $to\nAssunto: $subject';
  }

  @override
  String forwardDate(String date, String time) {
    return '$date às $time';
  }

  @override
  String get folderWaiting => 'Aguardando';

  @override
  String waitingSummary(int count) {
    return '$count enviados · ainda sem resposta';
  }

  @override
  String get waitingNoReply => 'Ainda sem resposta';

  @override
  String get waitingTo => 'Para ';

  @override
  String waitingDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dias',
      one: '1 dia',
    );
    return '$_temp0';
  }

  @override
  String get waitingToday => 'hoje';

  @override
  String get waitingYesterday => 'ontem';

  @override
  String waitingLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails enviados aguardando resposta',
      one: '1 e-mail enviado aguardando resposta',
    );
    return '$_temp0';
  }

  @override
  String get writeAgain => 'Escrever de novo';

  @override
  String get stopWaiting => 'Parar de aguardar';

  @override
  String get stoppedWaiting => 'Fora de Aguardando. Continua em Enviados.';

  @override
  String get remindMe => 'Lembrar';

  @override
  String get remindTitle => 'Lembrar se ninguém responder';

  @override
  String get remindTomorrow => 'Amanhã';

  @override
  String remindInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Em $count dias',
      one: 'Em 1 dia',
    );
    return '$_temp0';
  }

  @override
  String get remindNextWeek => 'Semana que vem';

  @override
  String get remindPickDate => 'Escolher uma data…';

  @override
  String get remindNever => 'Não lembrar';

  @override
  String remindChipToday(String time) {
    return 'Lembrar às $time';
  }

  @override
  String get remindChipTomorrow => 'Lembrar amanhã';

  @override
  String remindChipInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lembrar em $count dias',
      one: 'Lembrar em 1 dia',
    );
    return '$_temp0';
  }

  @override
  String remindChipOn(String date) {
    return 'Lembrar em $date';
  }

  @override
  String remindAt(String when) {
    return 'Lembrar $when';
  }

  @override
  String remindNoReply(String name) {
    return 'Sem resposta de $name';
  }

  @override
  String get remindSentToday => 'enviado hoje';

  @override
  String get remindSentYesterday => 'enviado ontem';

  @override
  String remindSentDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'enviado há $count dias',
      one: 'enviado há 1 dia',
    );
    return '$_temp0';
  }

  @override
  String get senderSharedFiles => 'Anexos compartilhados';

  @override
  String senderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anexos',
      one: '1 anexo',
    );
    return '$_temp0';
  }

  @override
  String get senderNoFiles => 'Ainda não há anexos dessa pessoa.';

  @override
  String get senderAddresses => 'Endereços';

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
  String get senderCopyAddress => 'Copiar endereço';

  @override
  String get senderRules => 'Regras e pastas';

  @override
  String get senderContent => 'Conteúdo do remetente';

  @override
  String folderReorder(String name) {
    return 'Arraste para reordenar $name';
  }

  @override
  String get folderMoveUp => 'Mover para cima';

  @override
  String get folderMoveDown => 'Mover para baixo';

  @override
  String get ruleUnopenedNewsletters => 'Newsletters';

  @override
  String get ruleUnopenedFor => ' não abertas há ';

  @override
  String get ruleUnopenedDays => '30 dias';

  @override
  String ruleNightly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails arquivados',
      one: '1 e-mail arquivado',
      zero: 'todas as contas',
    );
    return 'Toda noite · $_temp0';
  }

  @override
  String get rulesWhereSynced =>
      'As regras rodam neste dispositivo e são sincronizadas em todos os seus dispositivos';

  @override
  String rulesWhereSyncedAt(String ago) {
    return 'As regras rodam neste dispositivo e são sincronizadas em todos os seus dispositivos · atualizado $ago';
  }

  @override
  String get calSynced =>
      'As conexões são sincronizadas em todos os seus dispositivos; as senhas viajam criptografadas e ficam no chaveiro do sistema.';

  @override
  String calUpdatesHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'atualiza a cada $count horas',
      one: 'atualiza a cada hora',
    );
    return '$_temp0';
  }

  @override
  String calUpdatesDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'atualiza a cada $count dias',
      one: 'atualiza diariamente',
    );
    return '$_temp0';
  }

  @override
  String get calUpdatesWeekly => 'atualiza semanalmente';

  @override
  String get showOriginalLayout => 'Mostrar layout original';

  @override
  String get originalLayout => 'Layout original';

  @override
  String get originalLayoutBar =>
      'Layout original · imagens e links seguem suas configurações de privacidade';

  @override
  String get backToReadingView => 'Voltar à visualização de leitura';

  @override
  String get readingView => 'Visualização de leitura';

  @override
  String get replyFromLabel => 'Responder de';

  @override
  String get senderReadsNoReplies => 'Este remetente não lê as respostas';

  @override
  String replyFromSignature(String name) {
    return 'assinatura $name';
  }

  @override
  String get noticeReplyHint => 'Escreva uma resposta…';

  @override
  String get labelsHeading => 'Marcadores';

  @override
  String get labelsSection => 'MARCADORES';

  @override
  String get labelAction => 'Marcador';

  @override
  String get labelAdd => '+ Marcador';

  @override
  String get labelNew => 'Novo marcador';

  @override
  String get labelFind => 'Encontre ou crie um marcador';

  @override
  String labelCreate(String name) {
    return 'Criar “$name”';
  }

  @override
  String labelRemove(String name) {
    return 'Remover o marcador $name';
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
      other: '$count contas',
      one: '1 conta',
    );
    return '$_temp0';
  }

  @override
  String labelsLocalNote(String account) {
    return '$account não guarda marcadores no servidor, então os marcadores dela ficam neste dispositivo.';
  }

  @override
  String get hintLabel => 'marcador';

  @override
  String get labelName => 'Nome do marcador';

  @override
  String get labelEdit => 'Editar marcador';

  @override
  String get labelSave => 'Salvar';

  @override
  String get labelCreateButton => 'Criar';

  @override
  String get labelDelete => 'Excluir marcador';

  @override
  String get labelDeleteNote =>
      'Ele sai de todos os e-mails; os e-mails ficam onde estão.';

  @override
  String get labelColorAmber => 'Âmbar';

  @override
  String get labelColorTeal => 'Verde-azulado';

  @override
  String get labelColorCoral => 'Coral';

  @override
  String get labelColorBlue => 'Azul';

  @override
  String get labelColorViolet => 'Violeta';

  @override
  String get labelMenu => 'Marcador…';

  @override
  String get ruleDoLabel => 'marcar com';

  @override
  String get ruleTrayLabel => 'Marcador';

  @override
  String get rulePickLabel => 'um marcador';

  @override
  String get ruleNoLabels =>
      'Nenhum marcador ainda: crie um com + Marcador em Pastas e marcadores.';

  @override
  String get foldersAndLabelsHeading => 'Pastas e marcadores';

  @override
  String get labelsCardTitle => 'Marcadores';

  @override
  String get labelsCardDetail => 'compartilhados entre todas as contas';

  @override
  String get labelsNone => 'Nenhum marcador ainda.';

  @override
  String rulesFoldersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pastas',
      one: '1 pasta',
    );
    return '$_temp0';
  }

  @override
  String rulesLabelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count marcadores',
      one: '1 marcador',
    );
    return '$_temp0';
  }

  @override
  String get senderPicturesSetting => 'Fotos dos remetentes';

  @override
  String get senderPicturesSettingHint =>
      'Fotos dos seus contatos e logotipos verificados de empresas no lugar das letras.';

  @override
  String get websiteIconsSetting => 'Ícones de sites';

  @override
  String get websiteIconsSettingHint =>
      'Para empresas sem logotipo. Cada site vê seu endereço IP uma vez.';

  @override
  String tabletInboxUnread(int count) {
    return 'Caixa de entrada, $count não lidos';
  }

  @override
  String tabletAccount(String name, String email) {
    return 'Conta $name, $email';
  }

  @override
  String get tabletSearch => 'Pesquisar e-mails';

  @override
  String get tabletSearchHint => 'Pesquise ou execute um comando';

  @override
  String get vaultTrackParcel => 'Rastrear encomenda';

  @override
  String get vaultTrackingCopied => 'Código de rastreio copiado';

  @override
  String get vaultNeedsYou => 'Precisa de você';

  @override
  String get vaultNext => 'Próximos';

  @override
  String get vaultOnTheWay => 'A caminho';

  @override
  String get vaultEverything => 'Tudo';

  @override
  String vaultNeedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count coisas precisam de você',
      one: '1 coisa precisa de você',
    );
    return '$_temp0';
  }

  @override
  String vaultTodayKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'um voo hoje',
      'train': 'um trem hoje',
      'ferry': 'uma balsa hoje',
      'bus': 'um ônibus hoje',
      'stay': 'um check-in hoje',
      'parking': 'estacionamento hoje',
      'car': 'um carro alugado hoje',
      'event': 'um evento hoje',
      'table': 'uma mesa hoje',
      'other': 'uma reserva hoje',
    });
    return '$_temp0';
  }

  @override
  String vaultLegKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'flight': 'Voo',
      'train': 'Trem',
      'ferry': 'Balsa',
      'bus': 'Ônibus',
      'stay': 'Check-in',
      'parking': 'Estacionamento',
      'car': 'Aluguel de carro',
      'event': 'Evento',
      'table': 'Mesa',
      'other': 'Reserva',
    });
    return '$_temp0';
  }

  @override
  String get vaultCatParcels => 'Encomendas';

  @override
  String get vaultCatSpending => 'Gastos';

  @override
  String get vaultCatTrips => 'Viagens';

  @override
  String get vaultCatSales => 'Vendas';

  @override
  String get vaultCatSubscriptions => 'Assinaturas';

  @override
  String get vaultCatReturns => 'Devoluções e garantia';

  @override
  String get vaultCatDeadlines => 'Prazos';

  @override
  String get vaultCatBookings => 'Reservas';

  @override
  String get vaultCatVouchers => 'Vales-presente e códigos';

  @override
  String get vaultCatDocuments => 'Documentos';

  @override
  String get vaultCatCertified => 'E-mail certificado';

  @override
  String vaultOnWayCount(int count) {
    return '$count a caminho';
  }

  @override
  String vaultToPickUp(int count) {
    return '$count para retirar';
  }

  @override
  String vaultDeliveredCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entregues',
      one: '1 entregue',
    );
    return '$_temp0';
  }

  @override
  String vaultMonthMoney(String month, String money) {
    return '$month · $money';
  }

  @override
  String get vaultOnTripNow => 'Em viagem agora';

  @override
  String vaultNextWhen(String when) {
    return 'Próximo: $when';
  }

  @override
  String vaultPastCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viagens passadas',
      one: '1 viagem passada',
    );
    return '$_temp0';
  }

  @override
  String vaultToShipCount(int count) {
    return '$count para enviar';
  }

  @override
  String vaultSoldCount(int count) {
    return '$count vendidos';
  }

  @override
  String vaultPlansLine(int count, String money) {
    return '$count · $money por mês';
  }

  @override
  String vaultPlansCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count planos',
      one: '1 plano',
    );
    return '$_temp0';
  }

  @override
  String vaultReturnUntil(int count, String day) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devoluções, a primeira até $day',
      one: '1 devolução até $day',
    );
    return '$_temp0';
  }

  @override
  String vaultWarrantyCount(int count) {
    return '$count na garantia';
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
    return '$count entregues';
  }

  @override
  String vaultTitleWhen(String title, String when) {
    return '$title · $when';
  }

  @override
  String vaultNeedFailed(String who) {
    return 'Pagamento recusado · $who';
  }

  @override
  String get vaultPaymentFailed => 'Pagamento recusado';

  @override
  String vaultWasDue(String when) {
    return 'Venceu $when';
  }

  @override
  String vaultShipBy(String when) {
    return 'Enviar até $when';
  }

  @override
  String get vaultToShip => 'Para enviar';

  @override
  String get vaultYouSend => 'Você envia';

  @override
  String vaultSoldOn(String where) {
    return 'vendido em $where';
  }

  @override
  String vaultPickUpBy(String when) {
    return 'Retirar até $when';
  }

  @override
  String get vaultReadyPickup => 'Pronto para retirar';

  @override
  String vaultRenewsWhen(String when) {
    return 'Renova $when';
  }

  @override
  String vaultEndsWhen(String when) {
    return 'Termina $when';
  }

  @override
  String vaultPerPeriod(String money, String period) {
    String _temp0 = intl.Intl.selectLogic(period, {
      'week': '$money por semana',
      'month': '$money por mês',
      'year': '$money por ano',
      'other': '$money',
    });
    return '$_temp0';
  }

  @override
  String vaultSince(String day) {
    return 'desde $day';
  }

  @override
  String get vaultUpdatePayment => 'Atualizar pagamento';

  @override
  String get vaultCoach => 'Vagão';

  @override
  String get vaultTicket => 'Bilhete';

  @override
  String vaultInHours(int hours) {
    return 'em $hours h';
  }

  @override
  String vaultInMinutes(int minutes) {
    return 'em $minutes min';
  }

  @override
  String vaultDeliveredWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count encomendas entregues esta semana',
      one: '1 encomenda entregue esta semana',
    );
    return '$_temp0';
  }

  @override
  String vaultSpentIn(String month) {
    return 'Gasto em $month';
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
  String get vaultExportMonth => 'Exportar mês';

  @override
  String vaultSpentTab(String money) {
    return 'Gasto · $money';
  }

  @override
  String vaultMoneyInTab(String money) {
    return 'Recebido · $money';
  }

  @override
  String vaultVia(String service) {
    return 'via $service';
  }

  @override
  String get vaultSpendingNote =>
      'Lido no dispositivo a partir de recibos e faturas';

  @override
  String vaultExported(int count, String file) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$file e $count PDFs salvos em Downloads',
      one: '$file e 1 PDF salvos em Downloads',
      zero: '$file salvo em Downloads',
    );
    return '$_temp0';
  }

  @override
  String get vaultNotExported => 'Não foi possível exportar o mês';

  @override
  String get vaultPrevMonth => 'Mês anterior';

  @override
  String get vaultNextMonth => 'Próximo mês';

  @override
  String get vaultNothingThisMonth => 'Nenhum recibo este mês.';

  @override
  String vaultSubscriptionsRow(int count) {
    return 'Assinaturas · $count';
  }

  @override
  String get vaultCsvHeader =>
      'Data,Quem,O quê,Valor,Moeda,Pago com,Arquivo,Número de IVA';

  @override
  String vaultComingUp(int count) {
    return '$count pela frente';
  }

  @override
  String get vaultNoTrips => 'Nenhuma viagem pela frente';

  @override
  String get vaultPastTrips => 'Viagens passadas';

  @override
  String vaultThisYear(int count) {
    return '$count este ano';
  }

  @override
  String vaultTripNowBack(String when) {
    return 'Agora · volta $when';
  }

  @override
  String get vaultLegDone => 'Concluído';

  @override
  String vaultUntilTime(String time) {
    return 'Até $time';
  }

  @override
  String vaultUntilDay(String day) {
    return 'Até $day';
  }

  @override
  String get vaultTripsNote =>
      'Trens, balsas, voos, hospedagens, estacionamentos e ingressos';

  @override
  String vaultNights(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count noites',
      one: '1 noite',
    );
    return '$_temp0';
  }

  @override
  String vaultFromTime(String time) {
    return 'a partir das $time';
  }

  @override
  String vaultCoachSeat(String coach, String seat) {
    return 'vagão $coach, assento $seat';
  }

  @override
  String vaultSeatIs(String seat) {
    return 'assento $seat';
  }

  @override
  String vaultCodeIs(String code) {
    return 'código $code';
  }

  @override
  String vaultFlightLeg(String number, String from, String to) {
    return 'Voo $number · $from → $to';
  }

  @override
  String vaultSoldFor(String who, String money) {
    return 'Vendido em $who · $money';
  }

  @override
  String vaultSoldOnly(String who) {
    return 'Vendido em $who';
  }

  @override
  String get vaultSaleOnWay => 'A caminho';

  @override
  String get vaultSaleReceived => 'Recebido';

  @override
  String get vaultPaidOut => 'Pago a você';

  @override
  String get vaultCanGoBack => 'Ainda pode devolver';

  @override
  String get vaultUnderWarranty => 'Na garantia';

  @override
  String vaultDaysToReturn(String who, int days) {
    return '$who · $days dias para devolver';
  }

  @override
  String vaultBought(String day) {
    return 'comprado $day';
  }

  @override
  String vaultWarrantyTo(String month) {
    return 'Garantia $month';
  }

  @override
  String get vaultCodeCopied => 'Código copiado';

  @override
  String get vaultCopyCode => 'Copiar código';

  @override
  String vaultDocKind(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'payslip': 'Holerite',
      'statement': 'Extrato',
      'tax': 'Documento fiscal',
      'contract': 'Contrato',
      'other': 'Documento',
    });
    return '$_temp0';
  }

  @override
  String get vaultOpenFile => 'Abrir arquivo';

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
  String get vaultCategoryEmpty => 'Nada aqui no momento.';

  @override
  String get vaultFlagged => 'precisa de você';

  @override
  String get suggestWroteTo => 'Você escreveu para';

  @override
  String get suggestWroteToYou => 'Escreveu para você';

  @override
  String get readerEmptyTap => 'Toque em uma mensagem para ler.';

  @override
  String get noticeAwayTitle => 'Enquanto você estava fora';

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
      other: '$count de pessoas',
      one: '1 de uma pessoa',
    );
    return '$_temp0';
  }

  @override
  String get quietWeekends => 'Fins de semana, o dia todo';

  @override
  String get quietWeekendsHint => 'Sábado e domingo';

  @override
  String get quietWhile => 'Durante o silêncio';

  @override
  String get quietWhileHint => 'Sem avisos resume tudo no final';

  @override
  String get quietNoSound => 'Sem som';

  @override
  String get quietNoNotices => 'Sem avisos';

  @override
  String quietRingsAsUsual(String address) {
    return '$address · toca como sempre';
  }

  @override
  String get quietAccountsHint =>
      'As contas desativadas tocam como sempre nas horas de silêncio.';

  @override
  String languageName(String code) {
    String _temp0 = intl.Intl.selectLogic(code, {
      'ar': 'árabe',
      'bg': 'búlgaro',
      'ca': 'catalão',
      'cs': 'tcheco',
      'zh': 'chinês',
      'da': 'dinamarquês',
      'de': 'alemão',
      'el': 'grego',
      'en': 'inglês',
      'et': 'estoniano',
      'fi': 'finlandês',
      'fr': 'francês',
      'he': 'hebraico',
      'hi': 'hindi',
      'hr': 'croata',
      'hu': 'húngaro',
      'id': 'indonésio',
      'it': 'italiano',
      'ja': 'japonês',
      'ko': 'coreano',
      'lt': 'lituano',
      'lv': 'letão',
      'nl': 'holandês',
      'nb': 'norueguês',
      'pl': 'polonês',
      'pt': 'português',
      'ro': 'romeno',
      'ru': 'russo',
      'sk': 'eslovaco',
      'sl': 'esloveno',
      'es': 'espanhol',
      'sr': 'sérvio',
      'sv': 'sueco',
      'th': 'tailandês',
      'tr': 'turco',
      'uk': 'ucraniano',
      'vi': 'vietnamita',
      'other': '$code',
    });
    return '$_temp0';
  }

  @override
  String translateWrittenIn(String language) {
    return 'Escrito em $language';
  }

  @override
  String get translateAction => 'Traduzir';

  @override
  String translateGetting(String from, String to) {
    return 'Obtendo $from–$to';
  }

  @override
  String translateGettingSize(String from, String to, String size) {
    return 'Obtendo $from–$to · $size';
  }

  @override
  String get translating => 'Traduzindo…';

  @override
  String translatedFrom(String language) {
    return 'Traduzido do $language · neste dispositivo';
  }

  @override
  String get translatedShort => 'Traduzido';

  @override
  String get translateShowOriginal => 'Mostrar original';

  @override
  String get translateOriginalShort => 'Original';

  @override
  String translateNeedsDownload(String from, String to) {
    return 'Para traduzir, baixe primeiro $from e $to.';
  }

  @override
  String get translateFailed =>
      'Não foi possível traduzir este e-mail. Tente de novo.';

  @override
  String get appearanceTranslateInto => 'Traduzir para';

  @override
  String get translateIntoApp => 'Idioma do app';

  @override
  String get translateIntoHint =>
      'E-mails em outros idiomas oferecem Traduzir. Acontece neste dispositivo.';

  @override
  String translatePair(String from, String to) {
    return '$from → $to';
  }

  @override
  String get translateRemove => 'Remover';

  @override
  String translateRemovePair(String pair) {
    return 'Remover $pair';
  }

  @override
  String get printEmail => 'Imprimir…';

  @override
  String printTooltip(String keys) {
    return 'Imprimir… $keys';
  }

  @override
  String get printOrSavePdf => 'Imprimir ou salvar como PDF';

  @override
  String get reportSpam => 'Denunciar spam';

  @override
  String reportedSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas denunciadas como spam',
      one: 'Denunciado como spam',
    );
    return '$_temp0';
  }

  @override
  String get notSpam => 'Não é spam';

  @override
  String notSpamMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas movidas para Caixa de entrada',
      one: 'Movido para Caixa de entrada',
    );
    return '$_temp0';
  }

  @override
  String get spamFolder => 'Spam';

  @override
  String get printDate => 'Data';

  @override
  String printAttachments(String files) {
    return 'Anexos: $files';
  }

  @override
  String get helpTitle => 'Ajuda e feedback';

  @override
  String get helpSubtitle =>
      'Relate um problema ou sugira uma ideia. Nada é enviado sem você.';

  @override
  String get reportProblem => 'Relatar um problema';

  @override
  String get reportThisProblem => 'Relatar este problema';

  @override
  String get reportCantAddAccount => 'Não consigo adicionar minha conta';

  @override
  String get suggestIdea => 'Sugerir uma ideia';

  @override
  String get shakeToReport => 'Agitar para relatar';

  @override
  String get shakeToReportHint => 'Agite o celular em qualquer tela';

  @override
  String get yourReports => 'Seus relatos';

  @override
  String get reportNone => 'Nenhum relato ainda.';

  @override
  String get reportTitle => 'Relato';

  @override
  String get reportKindProblem => 'Problema';

  @override
  String get reportKindIdea => 'Ideia';

  @override
  String get reportTitleField => 'Título';

  @override
  String get reportTitleHint => 'Em poucas palavras';

  @override
  String get reportProblemField => 'O que aconteceu';

  @override
  String get reportIdeaField => 'O quê e por quê';

  @override
  String get reportDescriptionHint => 'O que você fez e o que esperava';

  @override
  String get reportScreenshot => 'Captura desta tela';

  @override
  String get reportScreenshotWindow => 'Captura desta janela';

  @override
  String get reportScreenshotOff => 'Desativada: pode mostrar seus e-mails';

  @override
  String get reportScreenshotOn => 'Toque na imagem para ocultar partes';

  @override
  String get reportLog => 'Registro do app';

  @override
  String get reportLogHint =>
      'Sem endereços nem nomes. Confira antes de enviar';

  @override
  String get reportDevice => 'Informações do dispositivo e do app';

  @override
  String get reportDeviceHint => 'Versão, modelo, idioma';

  @override
  String get reportAlways => 'Sempre';

  @override
  String get reportAttachments => 'Imagens e vídeos';

  @override
  String reportAttachmentsHint(String image, String video) {
    return 'Imagens até $image, vídeos até $video';
  }

  @override
  String get reportAttach => 'Anexar';

  @override
  String reportAttachType(String name) {
    return 'Não é possível anexar $name: escolha uma imagem PNG, JPEG, WebP ou GIF, ou um vídeo MP4, WebM ou MOV.';
  }

  @override
  String reportImageTooLarge(String name, String max) {
    return '$name é grande demais: as imagens podem ter até $max.';
  }

  @override
  String reportVideoTooLarge(String name, String max) {
    return '$name é grande demais: os vídeos podem ter até $max.';
  }

  @override
  String reportAttachTooMany(int count) {
    return 'Um relato pode levar até $count arquivos.';
  }

  @override
  String get reportAttachFailed =>
      'Não foi possível abrir os arquivos. Tente de novo.';

  @override
  String get reportSectionAttachment => 'Anexo';

  @override
  String get reportSeeSent => 'Ver o que é enviado';

  @override
  String get reportSend => 'Enviar';

  @override
  String get reportQueued => 'Relato na fila';

  @override
  String get reportNotKept => 'Não foi possível guardar o relato';

  @override
  String get reportWhatsSent => 'O que é enviado';

  @override
  String get reportSectionReport => 'Relato';

  @override
  String get reportSectionDevice => 'Dispositivo';

  @override
  String get reportSectionScreenshot => 'Captura';

  @override
  String get reportHideParts => 'Ocultar partes';

  @override
  String get reportDragToBlur => 'Arraste para desfocar';

  @override
  String get reportDone => 'Concluído';

  @override
  String get reportStatusQueued => 'Na fila';

  @override
  String get reportStatusSending => 'Enviando';

  @override
  String get reportStatusFailed => 'Falhou';

  @override
  String get reportStatusEmailed => 'Enviado por e-mail';

  @override
  String get reportWaitOffline => 'aguardando uma rede';

  @override
  String get reportWaitTurn => 'sai em instantes';

  @override
  String reportWaitAt(String time) {
    return 'sai às $time';
  }

  @override
  String get reportWaitPaused => 'sai mais tarde hoje ou amanhã';

  @override
  String get reportTapRetry => 'toque para tentar de novo';

  @override
  String get reportTryAgain => 'Tentar de novo';

  @override
  String get reportByEmail => 'Enviar por e-mail';

  @override
  String get reportDelete => 'Excluir';

  @override
  String get reportPrivacyLine =>
      'Vira uma issue privada no GitHub para quem mantém o app.';

  @override
  String get reportPrivacyLink => 'Como os relatos são tratados';

  @override
  String get reportPrivacyTitle => 'Relatos e privacidade';

  @override
  String get reportPrivacyWhat =>
      'O que é enviado: só o que “Ver o que é enviado” mostra. Suas palavras, os dados do dispositivo e do app, e a captura, o registro e os arquivos que você deixar ativados. Endereços, nomes e assuntos são tirados do registro, mas algo pode escapar: confira antes de enviar.';

  @override
  String reportPrivacyWhere(String relay, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dias',
      one: '1 dia',
    );
    return 'Para onde vai: pelo relay do projeto na Cloudflare ($relay) para uma issue privada no GitHub, nos Estados Unidos. Os anexos ficam no armazenamento da Cloudflare na UE e são apagados depois de $_temp0.';
  }

  @override
  String reportPrivacyWhereEmail(String contact) {
    return 'Para onde vai: por e-mail da sua própria conta para $contact.';
  }

  @override
  String reportPrivacyWho(String controller) {
    return 'Quem vê: $controller, as pessoas que ajudam a manter o Piuma Mail e as ferramentas que usam para organizar os relatos, assistentes de IA incluídos. Os relatos nunca são vendidos nem usados para publicidade.';
  }

  @override
  String get reportPrivacyKeep =>
      'Por quanto tempo: a issue fica enquanto ajudar a resolver o problema. Excluir um relato em Seus relatos remove só a cópia deste dispositivo.';

  @override
  String reportPrivacyErase(String contact) {
    return 'Para saber o que é guardado ou pedir que seja apagado, escreva para $contact com o número do relato.';
  }

  @override
  String get reportPrivacyFull => 'Aviso de privacidade completo';

  @override
  String get reportDeleteTitle => 'Excluir este relato?';

  @override
  String reportDeleteSent(int number) {
    return 'Remove do dispositivo. O relato enviado (#$number) continua com quem mantém o app: você pode pedir que apaguem também.';
  }

  @override
  String get reportDeleteHere => 'Excluir deste dispositivo';

  @override
  String get reportDeleteAndErase => 'Pedir também para apagar';

  @override
  String get reportOptions => 'Opções do relato';

  @override
  String get crashLine =>
      'O Piuma teve um problema da última vez. Enviar um relato?';

  @override
  String get crashReport => 'Relatar';

  @override
  String get crashDismiss => 'Dispensar';

  @override
  String reportStatusSent(int number) {
    return 'Enviado nº $number';
  }

  @override
  String reportSectionLog(int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: '$lines linhas',
      one: '1 linha',
    );
    return 'Registro do app · $_temp0';
  }

  @override
  String reportShown(String title, String status) {
    return '$title, $status';
  }

  @override
  String get paletteHelp => 'Ajuda';

  @override
  String get awayTitle => 'Resposta automática';

  @override
  String get awayNote => 'Responde por você, mesmo com o app fechado';

  @override
  String get awayFrom => 'De';

  @override
  String get awayToInline => 'até';

  @override
  String get awayTo => 'Até';

  @override
  String get awaySubject => 'Assunto';

  @override
  String get awayMessage => 'Mensagem';

  @override
  String get awayEndsNote =>
      'Termina sozinha depois do último dia. Deixe \"até\" vazio para mantê-la ativa até você desativá-la.';

  @override
  String awaySubjectUntil(String date) {
    return 'Fora até $date';
  }

  @override
  String get awaySubjectPlain => 'Fora do escritório';

  @override
  String awayBodyUntil(String date) {
    return 'Olá, estou fora até $date e respondo quando voltar.';
  }

  @override
  String get awayBodyPlain => 'Olá, estou fora e respondo quando voltar.';

  @override
  String get awayToday => 'Hoje';

  @override
  String get awayNoEnd => 'Sem fim';

  @override
  String get awayPickFrom => 'Primeiro dia';

  @override
  String get awayPickTo => 'Último dia';

  @override
  String get awayKeepOn => 'Manter ativa até eu desativar';

  @override
  String get awayOtherFilters =>
      'Não dá para ativar junto com seus filtros atuais. Desative-os primeiro no servidor.';

  @override
  String get awayUnsupported =>
      'Este servidor não aceita mais resposta automática.';

  @override
  String get awayOffline =>
      'Não foi possível alcançar o servidor. Tente de novo daqui a pouco.';

  @override
  String awayLineUntil(String account, String date) {
    return 'Resposta automática ativa para $account até $date';
  }

  @override
  String awayLineOn(String account) {
    return 'Resposta automática ativa para $account';
  }

  @override
  String get awayTurnOff => 'Desativar';

  @override
  String get awayRowOff => 'Desativada';

  @override
  String get awayRowOn => 'Ativada';

  @override
  String awayRowUntil(String date) {
    return 'Ativada até $date';
  }

  @override
  String get featuresSubtitle =>
      'Desative o que você não usa. Some de todo lugar, e nada é apagado.';

  @override
  String get featuresZones => 'Áreas';

  @override
  String get featuresOnDevice => 'Neste dispositivo';

  @override
  String get featuresOnDeviceNote => 'Nada aqui sai do dispositivo.';

  @override
  String get featureNewslettersHint =>
      'As newsletters em uma lista própria, para ler como uma revista';

  @override
  String get featureNewslettersOff =>
      'Desativado · as newsletters chegam à caixa de entrada como qualquer e-mail';

  @override
  String get featureVaultHint =>
      'Pagamentos, encomendas, viagens e prazos como cartões';

  @override
  String get featureVaultOff =>
      'Desativado · estes e-mails ficam como estão, sem cartões nem avisos';

  @override
  String get featureAttachmentsHint =>
      'Todos os arquivos que você recebeu, em um só lugar';

  @override
  String get featureAttachmentsOff =>
      'Desativado · os arquivos ficam nos e-mails, e a pesquisa continua encontrando-os';

  @override
  String get featureInShortHint =>
      'O essencial das conversas longas, acima do primeiro e-mail';

  @override
  String get featureInShortOff =>
      'Desativado · as conversas abrem sem o resumo';

  @override
  String get featureTranslate => 'Traduzir';

  @override
  String get featureTranslateHint =>
      'Oferece traduzir e-mails escritos em outros idiomas';

  @override
  String get featureTranslateOff =>
      'Desativado · nenhuma oferta de tradução, e nenhum idioma é baixado';

  @override
  String get featureFoundDates => 'Datas nos e-mails';

  @override
  String get featureFoundDatesHint =>
      'Adicionar ao calendário datas e horários encontrados no texto';

  @override
  String get featureFoundDatesOff =>
      'Desativado · os convites continuam mostrando seu cartão';

  @override
  String get nextEmail => 'Próximo e-mail';

  @override
  String get previousEmail => 'E-mail anterior';

  @override
  String get appearanceLanguage => 'Idioma';

  @override
  String get languageDevice => 'Idioma do dispositivo';

  @override
  String senderLooksLike(String domain, String like) {
    return '$domain parece $like, mas é outro endereço.';
  }

  @override
  String senderBrand(String brand, String domain) {
    return 'O nome diz $brand, mas o endereço é de $domain.';
  }

  @override
  String senderDmarcFailed(String domain) {
    return 'Este email diz ser de $domain, mas $domain não o enviou.';
  }

  @override
  String get senderDetails => 'Detalhes';

  @override
  String get senderDetailsTitle => 'O que foi verificado';

  @override
  String get senderSentBy => 'Enviado por';

  @override
  String get senderNotKnown => 'Desconhecido';

  @override
  String get senderSignature => 'Assinatura';

  @override
  String get senderSignatureNone => 'Nenhuma';

  @override
  String get senderDomainCheck => 'Verificação do domínio';

  @override
  String get senderDomainCheckFailed => 'Falhou (DMARC)';

  @override
  String get senderLooksLikeLabel => 'Parece';

  @override
  String senderLooksLikeValue(String like, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails de lá',
      one: '1 email de lá',
      zero: 'nenhum email de lá',
    );
    return '$like, $_temp0';
  }

  @override
  String get senderNameSays => 'O nome diz';

  @override
  String get senderDetailsNote =>
      'Calculado neste dispositivo a partir do que o seu servidor de email escreveu. Os links deste email perguntam antes de abrir.';

  @override
  String impostorLinkBody(String real) {
    return 'Este email pode não ser de quem diz. O link leva a $real.';
  }

  @override
  String unreadableLinkBody(String real) {
    return 'Não é possível saber com certeza para onde este link leva: $real.';
  }

  @override
  String get updates => 'Atualizações';

  @override
  String get updatesVersion => 'Versão';

  @override
  String get upToDate => 'Atualizado';

  @override
  String get updatesAuto => 'O Piuma procura novas versões sozinho';

  @override
  String get checkForUpdates => 'Procurar atualizações';

  @override
  String get updateChecking => 'Verificando…';

  @override
  String get checkedJustNow => 'Verificado agora';

  @override
  String checkedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Verificado há $count minutos',
      one: 'Verificado há 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String checkedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Verificado há $count horas',
      one: 'Verificado há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String checkedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Verificado há $count dias',
      one: 'Verificado ontem',
    );
    return '$_temp0';
  }

  @override
  String updateDownloading(String version, int percent) {
    return 'Baixando $version · $percent%';
  }

  @override
  String updateDownloadedOf(String done, String total) {
    return '$done de $total';
  }

  @override
  String updateReadyTitle(String version) {
    return 'Pronta · $version';
  }

  @override
  String get updateGoesInOnRestart => 'Entra quando o Piuma reiniciar';

  @override
  String get restart => 'Reiniciar';

  @override
  String get updateCouldntCheck => 'Não foi possível verificar';

  @override
  String get tryAgain => 'Tentar de novo';

  @override
  String get seeWhatsNew => 'Ver novidades';

  @override
  String get whatsNew => 'Novidades';

  @override
  String whatsNewVersion(String version) {
    return 'Piuma Mail $version';
  }

  @override
  String get updateKeepsMail =>
      'Seus e-mails e rascunhos são mantidos. O Piuma fecha e abre de novo em poucos segundos.';

  @override
  String get restartNow => 'Reiniciar agora';

  @override
  String updateReadyLine(String version) {
    return 'Atualização pronta · $version';
  }

  @override
  String updatedTo(String version) {
    return 'Atualizado para $version';
  }

  @override
  String updateAvailableTitle(String version) {
    return 'Disponível · $version';
  }

  @override
  String get updateAvailableHint => 'Baixe-a na página da versão';

  @override
  String get updateDownload => 'Baixar';

  @override
  String updateAvailableLine(String version) {
    return 'Nova versão · $version';
  }

  @override
  String get updatesAutomatic => 'Procurar novas versões';

  @override
  String get updatesAutomaticHint => 'Pergunta ao GitHub a cada poucas horas';

  @override
  String get updatesOnlyWhenAsked => 'O Piuma só procura quando você pede';

  @override
  String get updatesEarly => 'Versões antecipadas';

  @override
  String get updatesEarlyHint =>
      'As novas versões alguns dias antes, com mais bugs';

  @override
  String get swipeHintArchiveSnooze =>
      'Deslize para a direita para arquivar, para a esquerda para adiar';

  @override
  String get swipeHintArchive => 'Deslize para a direita para arquivar';

  @override
  String get formatting => 'Formatação';

  @override
  String get formatBold => 'Negrito';

  @override
  String get formatItalic => 'Itálico';

  @override
  String get formatLink => 'Link';

  @override
  String get formatBullets => 'Lista com marcadores';

  @override
  String get formatNumbers => 'Lista numerada';

  @override
  String get formatQuote => 'Citação';

  @override
  String get linkAddressHint => 'Cole ou digite um endereço';

  @override
  String get linkAdd => 'Adicionar';

  @override
  String get linkRemove => 'Remover link';

  @override
  String imagesOffBar(int count, String sender) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count imagens estão desligadas, assim $sender não sabe quando você abre.',
      one: '1 imagem está desligada, assim $sender não sabe quando você abre.',
    );
    return '$_temp0';
  }

  @override
  String get loadImages => 'Carregar imagens';

  @override
  String get alwaysForSender => 'Sempre deste remetente';

  @override
  String get cleanView => 'Vista limpa';

  @override
  String get viewOriginal => 'Original';

  @override
  String get viewClean => 'Limpa';

  @override
  String get calGoogle => 'Google Agenda';

  @override
  String get calGoogleSub => 'Ler eventos e disponibilidade com um link iCal';

  @override
  String get calGoogleLabel => 'Endereço iCal do Google Agenda';

  @override
  String get calGoogleHint =>
      'No Google Agenda no computador: Configurações › sua agenda › Integrar agenda › Endereço secreto no formato iCal. Somente leitura; conecta diretamente.';

  @override
  String get bundledReleaseNotes =>
      '## O e-mail, feito leve\n- Layouts originais com rolagem única e controle de imagens\n- Barra de formatação e abertura do editor completo nas respostas\n- Gestos de deslizar horizontal mais precisos\n- Avisos de remetente para imitação de marca e domínios parecidos\n- Exportação CSV mensal do Cofre com NIF/IVA do comerciante';

  @override
  String syncHeldTitle(String email) {
    return '$email foi removida em outro dispositivo';
  }

  @override
  String syncHeldWaiting(String what) {
    return 'Aqui ela ainda tem $what. Remover também deste dispositivo ou manter em todos?';
  }

  @override
  String syncHeldOutbox(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count emails esperando para serem enviados',
      one: '1 email esperando para ser enviado',
    );
    return '$_temp0';
  }

  @override
  String syncHeldDrafts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rascunhos ainda não salvos no servidor',
      one: '1 rascunho ainda não salvo no servidor',
    );
    return '$_temp0';
  }

  @override
  String syncHeldPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alterações que ainda não estão no servidor',
      one: '1 alteração que ainda não está no servidor',
    );
    return '$_temp0';
  }

  @override
  String get syncHeldHome =>
      'A caixa dela guarda seu espaço de sincronização, então ela fica aqui. Mantenha-a ou mova antes o espaço para outra caixa.';

  @override
  String get syncHeldRemove => 'Remover aqui';

  @override
  String get syncHeldKeep => 'Manter';

  @override
  String get syncRollbackTitle =>
      'Uma cópia mais antiga do seu espaço foi ignorada';

  @override
  String syncRollbackBody(String email) {
    return 'Alguém com acesso a $email, ou um dispositivo que você desvinculou, pode tê-la colocado de volta. Nada foi aproveitado dela. Se acontecer de novo, troque a senha dessa caixa.';
  }

  @override
  String get syncOutdatedTitle =>
      'Atualize o Piuma para sincronizar as alterações deste dispositivo';

  @override
  String get syncOutdatedBody =>
      'Outro dispositivo salvou seu espaço com uma versão mais nova. Este continua recebendo alterações e guarda as suas até ser atualizado.';

  @override
  String get syncExposedTitle => 'Troque estas senhas';

  @override
  String syncExposedBody(String name) {
    return '$name não consegue mais ler seu espaço, mas ainda conhece as senhas destas caixas. Troque-as no seu provedor para deixá-lo fora do seu email também.';
  }

  @override
  String get syncExposedDone => 'Entendi';

  @override
  String get syncPaused => 'Pausada neste dispositivo';

  @override
  String get syncConfirmTitle => 'Confirme este dispositivo';

  @override
  String get syncConfirmBody =>
      'O Piuma agora verifica quais dispositivos fazem parte do seu espaço. Até você confirmar este com sua frase de recuperação, ou com um código de um dispositivo já atualizado, nada é sincronizado aqui.';

  @override
  String get syncConfirm => 'Confirmar';

  @override
  String get syncConflictTitle => 'Dois dispositivos removeram um ao outro';

  @override
  String syncConflictBody(String names) {
    return '$names removeram um ao outro do seu espaço, e um deles pode não ser mais seu. A sincronização parou neste dispositivo: vincule-o de novo a partir de um dispositivo que você ainda tem.';
  }

  @override
  String get syncLinkAgain => 'Vincular de novo';

  @override
  String syncUnlinkedTitle(String name) {
    return '$name removeu este dispositivo';
  }

  @override
  String get syncUnlinkedBody =>
      'A sincronização parou neste dispositivo; as contas e os e-mails dele ficam aqui. Se não foi você, vincule-o de novo a partir de um dispositivo que você ainda tem. Caso contrário, desative a sincronização aqui.';

  @override
  String get syncExposedNowTitle => 'Troque estas senhas agora';

  @override
  String syncExposedNowBody(String name, String email) {
    return '$name ainda conhece estas senhas. Comece por $email: até a senha dela mudar, $name ainda consegue chegar à pasta que guarda seu espaço.';
  }

  @override
  String get syncExposedChanged => 'Já troquei';

  @override
  String get syncExposedFirst => 'Primeiro: guarda seu espaço';

  @override
  String get syncFailRollback =>
      'Esta caixa só tem uma cópia mais antiga do seu espaço. Nada foi alterado.';

  @override
  String get syncFailOutdated =>
      'Seu espaço foi salvo por uma versão mais nova do Piuma. Atualize o Piuma neste dispositivo.';

  @override
  String pairServer(String host) {
    return 'Entra em $host';
  }

  @override
  String get pairServerFromCode =>
      'Este servidor vem do código, não das configurações do seu provedor. Confira se é do seu provedor antes de digitar a senha.';

  @override
  String get pairServerChecking => 'Verificando o servidor…';

  @override
  String pairRefusedDevice(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Seu celular disse que não era você.',
      'tablet': 'Seu tablet disse que não era você.',
      'other': 'Seu computador disse que não era você.',
    });
    return '$_temp0';
  }

  @override
  String pairCodeBodyDevice(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Abra o Piuma no seu celular e digite o código.',
      'tablet': 'Abra o Piuma no seu tablet e digite o código.',
      'other': 'Abra o Piuma no seu computador e digite o código.',
    });
    return '$_temp0';
  }

  @override
  String pairWaitingDevice(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Aguardando seu celular confirmar…',
      'tablet': 'Aguardando seu tablet confirmar…',
      'other': 'Aguardando seu computador confirmar…',
    });
    return '$_temp0';
  }

  @override
  String pairStep1Device(String kind, String title) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone': 'Seu celular vai mostrar “$title”',
      'tablet': 'Seu tablet vai mostrar “$title”',
      'other': 'Seu computador vai mostrar “$title”',
    });
    return '$_temp0';
  }

  @override
  String pairConfirmFromDevice(String kind, String ago) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'phone':
          'Por segurança, confirme em um dispositivo já vinculado: seu celular, ativo $ago.',
      'tablet':
          'Por segurança, confirme em um dispositivo já vinculado: seu tablet, ativo $ago.',
      'other':
          'Por segurança, confirme em um dispositivo já vinculado: seu computador, ativo $ago.',
    });
    return '$_temp0';
  }

  @override
  String get syncRecoveryChangedTitle => 'Anote sua nova frase de recuperação';

  @override
  String get syncRecoveryChangedBody =>
      'Seu espaço ganhou uma nova chave e uma nova frase de recuperação, porque um dispositivo saiu ou dois foram desvinculados ao mesmo tempo. A que você anotou não funciona mais.';

  @override
  String get saveSearch => 'Guardar pesquisa';

  @override
  String get savedSearchEdit => 'Editar pesquisa guardada';

  @override
  String get savedSearchName => 'Nome';

  @override
  String get savedSearchSave => 'Guardar';

  @override
  String get savedSearchDelete => 'Eliminar pesquisa';

  @override
  String get savedSearchDeleteNote =>
      'Só a pesquisa guardada desaparece: os emails ficam onde estão.';

  @override
  String get savedSearchNameTaken =>
      'Outra pesquisa guardada já tem este nome.';

  @override
  String get savedSearchesSection => 'PESQUISAS GUARDADAS';

  @override
  String get savedSearches => 'Pesquisas guardadas';

  @override
  String get searchSuggestions => 'Sugestões';

  @override
  String get searchOnServer => 'Pesquisar no servidor';

  @override
  String get searchOnServerHeading => 'No servidor';

  @override
  String get searchingServers => 'A pesquisar no servidor…';

  @override
  String get searchServerError => 'Não foi possível pesquisar no servidor.';

  @override
  String get searchServerLocalOnly =>
      'Esta pesquisa só pode ver este dispositivo.';

  @override
  String get searchServerNothing => 'Não há mais nada no servidor.';

  @override
  String get searchFromServer => 'Encontrado no servidor';

  @override
  String get searchServerPartial =>
      'Algumas pastas não puderam ser pesquisadas por completo.';

  @override
  String get searchServerMaybe =>
      'E-mails mais antigos, e texto que este dispositivo não guardou, ainda podem estar no servidor.';

  @override
  String searchServerTextRefused(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Os servidores de $count contas só pesquisam letras simples (A–Z), por isso não lhes foi pedido este texto.',
      one: 'O servidor de 1 conta só pesquisa letras simples (A–Z), por isso não lhe foi pedido este texto.',
    );
    return '$_temp0';
  }

  @override
  String searchServerPartialIn(String accounts) {
    return 'Pesquisado só em parte: $accounts. O que foi encontrado antes de parar está aqui.';
  }

  @override
  String searchServerFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Mais $count emails encontrados no servidor, agora neste dispositivo.',
      one: 'Mais 1 email encontrado no servidor, agora neste dispositivo.',
    );
    return '$_temp0';
  }

  @override
  String searchServerUnreachable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível contactar os servidores de $count contas.',
      one: 'Não foi possível contactar o servidor de 1 conta.',
    );
    return '$_temp0';
  }

  @override
  String savedSearchEditNamed(String name) {
    return 'Mudar o nome ou eliminar $name';
  }

  @override
  String get errorNoKeyring =>
      'O Piuma guarda as senhas no chaveiro do sistema e nenhum está em execução. Instale e inicie um, como o GNOME Keyring ou o KWallet, e tente de novo. As senhas nunca ficam num arquivo sem proteção.';

  @override
  String get errorCertificate =>
      'Não é possível confiar no certificado do servidor.';

  @override
  String get errorSignInUnavailable =>
      'Esta cópia do Piuma Mail não consegue entrar neste provedor. Informe seu próprio ID do cliente em Avançado ou use uma senha de app, se o provedor permitir.';

  @override
  String get errorSignInCancelled =>
      'A página de entrada foi fechada antes de terminar. Tente de novo.';

  @override
  String get errorSignInDenied =>
      'O provedor não permitiu a entrada. Tente de novo ou confira o ID do cliente em Avançado.';

  @override
  String get errorOAuthServers =>
      'Esta conta entra pela página do provedor, então fica com os servidores do próprio provedor, com uma conexão segura.';

  @override
  String get errorPort => 'Uma porta é um número de 1 a 65535.';

  @override
  String get certUntrusted =>
      'Nenhuma autoridade em que o sistema confia garante este certificado. É assim com servidores que criam o próprio certificado.';

  @override
  String get certExpired => 'Este certificado expirou ou ainda não é válido.';

  @override
  String get certNameMismatch =>
      'Este certificado foi feito para outro nome de servidor.';

  @override
  String get certChanged =>
      'Este não é o certificado em que você confiou para este servidor. Ele pode ter sido renovado, ou alguém pode estar escutando no meio. Confie apenas se souber por que mudou.';

  @override
  String get certInvalid =>
      'Este certificado não é válido, e confiar nele não tornaria a conexão segura.';

  @override
  String get certProvider =>
      'Este é o servidor de um grande provedor, e uma autoridade sempre garante os certificados dele. Talvez alguém esteja interceptando a conexão: tente outra rede e confira a data e a hora deste dispositivo.';

  @override
  String get certIssuedTo => 'Emitido para';

  @override
  String get certIssuedBy => 'Emitido por';

  @override
  String get certValidUntil => 'Válido até';

  @override
  String get certFingerprint => 'Impressão digital SHA-256';

  @override
  String get certTrust => 'Confiar neste certificado';

  @override
  String get certTrustNew => 'Confiar no novo certificado';

  @override
  String get certCopyFingerprint => 'Copiar impressão digital';

  @override
  String get certTrustHint =>
      'Só para esta conta e exatamente este certificado. Antes, compare a impressão digital com a que seu provedor ou administrador informa.';

  @override
  String oauthSignInWith(String provider) {
    return 'Entrar com $provider';
  }

  @override
  String oauthLead(String provider) {
    return 'O Piuma Mail abre a página da $provider no navegador. Entre por lá e volte aqui: sua senha fica com a $provider.';
  }

  @override
  String get oauthWaiting => 'Aguardando o navegador…';

  @override
  String get oauthMicrosoftNoClient =>
      'A Microsoft não aceita mais sua senha de sempre em apps de e-mail. Se sua conta tem uma senha de app, ou sua organização ainda permite senhas para IMAP, use-a com as configurações do servidor. Se você tem seu próprio registro do app, informe o ID do cliente em Avançado.';

  @override
  String oauthNotYet(String provider) {
    return 'A entrada com a $provider ainda não está disponível nesta versão do Piuma Mail.';
  }

  @override
  String get contactsIntroTitle => 'Rostos conhecidos';

  @override
  String get contactsIntroBody =>
      'O Piuma pode mostrar as fotos dos seus contatos ao lado dos e-mails deles. Elas ficam neste dispositivo: nada é copiado nem enviado. Depois o sistema vai pedir para o Piuma ler seus contatos.';

  @override
  String get contactPhotosSetting => 'Fotos dos seus contatos';

  @override
  String get contactPhotosSettingHint =>
      'Lidas só neste dispositivo, para mostrar um rosto ao lado dos e-mails deles. Desative nas configurações do sistema.';

  @override
  String get oauthUseAppPassword => 'Usar uma senha de app';

  @override
  String get oauthAdvanced => 'Avançado: seu próprio ID do cliente';

  @override
  String oauthAdvancedHint(String provider) {
    return 'Para o seu próprio registro de app na $provider. Deixe vazio para usar o desta versão.';
  }

  @override
  String get oauthClientId => 'ID do cliente';

  @override
  String get oauthTenant => 'Locatário (opcional)';

  @override
  String get oauthClientSecret =>
      'Segredo do cliente (só apps para computador do Google)';

  @override
  String get listFailed => 'Não foi possível mostrar estes e-mails.';

  @override
  String get folderRefreshFailed =>
      'Não foi possível atualizar esta pasta pelo servidor.';

  @override
  String changesDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'O servidor não aceitou $count alterações que você fez: esses e-mails voltaram a ser como eram.',
      one: 'O servidor não aceitou uma alteração que você fez: esse e-mail voltou a ser como era.',
    );
    return '$_temp0';
  }

  @override
  String get composeOptions => 'Opções';

  @override
  String get composePlainText => 'Texto simples';

  @override
  String get composeHighPriority => 'Prioridade alta';

  @override
  String get composeReadReceipt => 'Pedir confirmação de leitura';

  @override
  String get composePlainTitle => 'Mudar para texto simples?';

  @override
  String get composePlainBody =>
      'O texto simples não tem negrito, itálico, links nem imagens. Os links mantêm o endereço entre parênteses e as imagens são anexadas como arquivos.';

  @override
  String get composePlainConfirm => 'Mudar para texto simples';

  @override
  String get sendForgotAttachmentTitle => 'Esqueceu o anexo?';

  @override
  String get sendForgotAttachmentBody =>
      'Sua mensagem menciona um anexo, mas nada foi anexado.';

  @override
  String get sendNoSubjectTitle => 'Enviar sem assunto?';

  @override
  String get sendNoSubjectBody =>
      'Um assunto ajuda a encontrar sua mensagem depois.';

  @override
  String get sendAddSubject => 'Adicionar assunto';

  @override
  String get sendAnyway => 'Enviar mesmo assim';

  @override
  String fileTooLarge(String name, String size) {
    return '$name é grande demais: os anexos podem ter até $size no total.';
  }

  @override
  String imageTooBig(String name) {
    return '$name é grande demais para ir no texto.';
  }

  @override
  String get pastedImage => 'A imagem colada';

  @override
  String contactGroupCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count endereços',
      one: '1 endereço',
      zero: 'Nenhum endereço',
    );
    return '$_temp0';
  }

  @override
  String get contactGroupTag => 'Grupo';

  @override
  String readReceiptAsk(String sender) {
    return '$sender pediu para ser avisado quando você ler esta mensagem.';
  }

  @override
  String get readReceiptSend => 'Enviar confirmação';

  @override
  String get readReceiptDontSend => 'Não enviar';

  @override
  String get readReceiptNever => 'Nunca para este remetente';

  @override
  String get readReceiptSent => 'Confirmação enviada';

  @override
  String get readReceiptFailed =>
      'Não foi possível enviar a confirmação. Tente novamente mais tarde.';

  @override
  String get highPriority => 'Prioridade alta';

  @override
  String get repliesTitle => 'Respostas';

  @override
  String get replyBelowQuote => 'Responder abaixo da citação';

  @override
  String get replyBelowQuoteHint =>
      'Desligado, as respostas começam acima da mensagem citada.';

  @override
  String get quoteSelection => 'Citar só as palavras selecionadas';

  @override
  String get quoteSelectionHint =>
      'Com palavras selecionadas numa mensagem, Responder cita só elas.';

  @override
  String get plainTextTitle => 'Novas mensagens em texto simples';

  @override
  String plainTextOn(String email) {
    return '$email · as novas mensagens começam em texto simples';
  }

  @override
  String get contactGroupsTitle => 'Grupos de contatos';

  @override
  String get contactGroupsHint =>
      'Digite o nome de um grupo em Para, Cc ou Cco para adicionar todos.';

  @override
  String get contactGroupNew => 'Novo grupo';

  @override
  String get contactGroupUntitled => 'Grupo sem nome';

  @override
  String get contactGroupName => 'Nome do grupo';

  @override
  String get contactGroupAddresses => 'Endereços';

  @override
  String get contactGroupAddressesHint =>
      'Um por linha, ou separados por vírgulas.';

  @override
  String contactGroupDelete(String name) {
    return 'Excluir $name';
  }

  @override
  String get composeInsertPicture => 'Inserir imagem';

  @override
  String get composePastePicture => 'Colar imagem';

  @override
  String get noPictureToPaste =>
      'Não há nenhuma imagem na área de transferência.';

  @override
  String get composeReadReceiptAsked => 'Confirmação de leitura pedida';

  @override
  String get readReceiptQueued =>
      'A confirmação está aguardando na Caixa de saída e será enviada assim que possível.';

  @override
  String oauthOwnClientNotHere(String provider) {
    return 'No Android, este app só consegue entrar na $provider com o cliente com que foi compilado. Use uma senha de app ou uma versão feita com o seu cliente.';
  }

  @override
  String get actionReplyAll => 'Responder a todos';

  @override
  String get actionReplyList => 'Responder à lista';

  @override
  String get actionForwardAttachment => 'Reencaminhar como anexo';

  @override
  String get actionRedirect => 'Redirecionar';

  @override
  String get actionEditAsNew => 'Editar como novo';

  @override
  String get actionViewSource => 'Ver código-fonte';

  @override
  String get actionSaveEml => 'Guardar como .eml';

  @override
  String get muteConversation => 'Silenciar conversa';

  @override
  String get unmuteConversation => 'Reativar conversa';

  @override
  String get conversationMuted =>
      'Conversa silenciada: as novas mensagens chegam lidas, sem notificação';

  @override
  String get conversationUnmuted => 'Conversa reativada';

  @override
  String get conversationMutedLine => 'Silenciada';

  @override
  String forwardFilesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ficheiros',
      one: 'o ficheiro',
    );
    return 'A obter $_temp0';
  }

  @override
  String forwardFilesDone(int done, int total) {
    return '$done de $total';
  }

  @override
  String forwardFilesFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível anexar estes ficheiros:',
      one: 'Não foi possível anexar este ficheiro:',
    );
    return '$_temp0';
  }

  @override
  String forwardWithoutFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Continuar sem eles',
      one: 'Continuar sem ele',
    );
    return '$_temp0';
  }

  @override
  String get gettingEmail => 'A obter o email';

  @override
  String get messageFetchFailed =>
      'Não foi possível obter o email do servidor. Verifique a ligação e tente novamente.';

  @override
  String get redirectTitle => 'Redirecionar este email';

  @override
  String redirectBody(String sender) {
    return 'Segue sem alterações, tal como chegou de $sender: as respostas vão para $sender, não para si.';
  }

  @override
  String get redirectTo => 'Para';

  @override
  String get redirectHint => 'Endereços, separados por vírgulas';

  @override
  String redirectDone(String to) {
    return 'Redirecionado para $to';
  }

  @override
  String get redirectFailed =>
      'Não foi possível redirecionar o email. Verifique os endereços e a ligação.';

  @override
  String get sourceTitle => 'Código-fonte do email';

  @override
  String get sourceHeaders => 'Cabeçalhos';

  @override
  String get sourceRaw => 'Original';

  @override
  String get sourceCopy => 'Copiar';

  @override
  String emlSaved(String name) {
    return 'Guardado como $name';
  }

  @override
  String get emlNotSaved => 'Não foi possível guardar o email';

  @override
  String recipientsMore(String names, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mais $count',
      one: 'mais 1 pessoa',
    );
    return '$names e $_temp0';
  }

  @override
  String get recipientYou => 'si';

  @override
  String get recipientsBcc => 'estava em Bcc';

  @override
  String get recipientsTo => 'Para';

  @override
  String get recipientsCc => 'Cc';

  @override
  String get recipientsBccLabel => 'Bcc';

  @override
  String get showRecipients => 'Mostrar quem o recebeu';

  @override
  String get hideRecipients => 'Ocultar quem o recebeu';

  @override
  String replyAllNames(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mais $count',
      one: 'mais 1 pessoa',
    );
    return '$name e $_temp0';
  }

  @override
  String replyAllOthers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'e mais $count',
      one: 'e mais 1 pessoa',
    );
    return '$_temp0';
  }

  @override
  String get shortcutNextEmail => 'Email seguinte';

  @override
  String get shortcutPreviousEmail => 'Email anterior';

  @override
  String get zoomIn => 'Ampliar';

  @override
  String get zoomOut => 'Reduzir';

  @override
  String get zoomReset => 'Tamanho real';

  @override
  String zoomLevel(int percent) {
    return 'Tamanho do texto $percent%';
  }

  @override
  String get textSize => 'Tamanho do texto';

  @override
  String sourceCut(int size) {
    return 'Mostram-se os primeiros $size KB. Guarde como .eml para o email inteiro.';
  }

  @override
  String get deviceHeading => 'Este dispositivo';

  @override
  String get defaultMailTitle => 'Tornar o Piuma a sua app de e-mail padrão';

  @override
  String get defaultMailHint =>
      'Os endereços de e-mail em que clica noutras apps e em sites abrem uma nova mensagem aqui.';

  @override
  String get defaultMailIsTitle => 'O Piuma é a sua app de e-mail padrão';

  @override
  String get defaultMailIs =>
      'Os endereços de e-mail em que clica noutras apps e em sites abrem aqui.';

  @override
  String get defaultMailButton => 'Tornar padrão';

  @override
  String get defaultMailOtherAndroid =>
      'Agora é outra app que abre os endereços de e-mail. Limpe as predefinições dela nas Informações da app; da próxima vez que o Android perguntar, escolha o Piuma e Sempre.';

  @override
  String get defaultMailAskAndroid =>
      'O Android pergunta que app usar quando toca num endereço de e-mail: escolha o Piuma e depois Sempre.';

  @override
  String get defaultMailAppInfo => 'Abrir informações';

  @override
  String get keepRunningTitle => 'Continuar em segundo plano ao fechar';

  @override
  String get keepRunningHint =>
      'O e-mail novo continua a notificá-lo. O Piuma fica na área de notificação; saia a partir daí.';

  @override
  String get startAtLoginTitle => 'Iniciar ao iniciar sessão';

  @override
  String get startAtLoginHint =>
      'O Piuma inicia na área de notificação, pronto para e-mail novo.';

  @override
  String get trayOpen => 'Abrir o Piuma Mail';

  @override
  String get trayQuit => 'Sair do Piuma Mail';

  @override
  String trayTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Piuma Mail: $count por ler',
      one: 'Piuma Mail: 1 por ler',
      zero: 'Piuma Mail',
    );
    return '$_temp0';
  }

  @override
  String get arrivalWhichAccount => 'Escrever a partir de que conta?';

  @override
  String get arrivalWaits => 'A nova mensagem abre quando fechar esta.';

  @override
  String arrivalFilesLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ficheiros eram demasiado grandes para anexar.',
      one: '1 ficheiro era demasiado grande para anexar.',
    );
    return '$_temp0';
  }

  @override
  String get emlFromFile => 'Aberto a partir de um ficheiro';

  @override
  String get emlImport => 'Importar para uma pasta';

  @override
  String get emlImportWhichAccount => 'Importar para que conta?';

  @override
  String emlImportIn(String account) {
    return 'Importar para uma pasta de $account';
  }

  @override
  String emlImported(String folder) {
    return 'Importado para $folder';
  }

  @override
  String get emlNotImported =>
      'Não foi possível importar. Verifique a ligação e tente novamente.';

  @override
  String get emlNotMail =>
      'Este ficheiro não é um e-mail que o Piuma consiga ler.';

  @override
  String get emlTooLarge =>
      'Este ficheiro de e-mail é demasiado grande para abrir.';

  @override
  String get arrivalNetworkFile =>
      'Os ficheiros em pastas de rede não abrem no Piuma. Copie-os primeiro para este dispositivo.';

  @override
  String imagesOffFile(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count imagens estão desligadas, assim ninguém sabe quando abre este ficheiro.',
      one: '1 imagem está desligada, assim ninguém sabe quando abre este ficheiro.',
    );
    return '$_temp0';
  }

  @override
  String get newMailClosedLead => 'Com o Piuma fechado';

  @override
  String get star => 'Marcar com estrela';

  @override
  String get unstar => 'Remover estrela';

  @override
  String get folderStarred => 'Com estrela';

  @override
  String get messageStarred => 'Com estrela';

  @override
  String starredMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas marcadas com estrela',
      one: 'Marcado com estrela',
    );
    return '$_temp0';
  }

  @override
  String unstarredMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Estrela removida de $count conversas',
      one: 'Estrela removida',
    );
    return '$_temp0';
  }

  @override
  String get starFailed =>
      'Não foi possível alterar a estrela. Tente de novo daqui a pouco.';

  @override
  String get trashFolder => 'Lixeira';

  @override
  String get deleteForever => 'Excluir para sempre';

  @override
  String deleteForeverTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count e-mails para sempre?',
      one: 'Excluir este e-mail para sempre?',
    );
    return '$_temp0';
  }

  @override
  String get deleteForeverNote =>
      'Não será possível recuperá-los, nem aqui nem no servidor.';

  @override
  String deletedForeverMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails excluídos para sempre',
      one: 'Excluído para sempre',
    );
    return '$_temp0';
  }

  @override
  String get emptyTrash => 'Esvaziar lixeira';

  @override
  String get emptySpam => 'Esvaziar spam';

  @override
  String emptyTitle(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir para sempre os $count e-mails em $folder?',
      one: 'Excluir para sempre o e-mail em $folder?',
      zero: '$folder está vazio',
    );
    return '$_temp0';
  }

  @override
  String get emptyConfirm => 'Esvaziar';

  @override
  String get emptyFailed =>
      'Não foi possível esvaziar. Tente de novo quando estiver online.';

  @override
  String get copyTo => 'Copiar para…';

  @override
  String copyToIn(String name) {
    return 'Copiar para uma pasta de $name';
  }

  @override
  String copiedMany(int count, String folder) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversas copiadas para $folder',
      one: 'Copiado para $folder',
    );
    return '$_temp0';
  }

  @override
  String folderActions(String name) {
    return 'Mais para “$name”';
  }

  @override
  String get folderRename => 'Renomear';

  @override
  String folderRenameTitle(String name) {
    return 'Renomear “$name”';
  }

  @override
  String get folderNewName => 'Novo nome';

  @override
  String get folderHide => 'Ocultar das listas';

  @override
  String get folderShow => 'Mostrar nas listas';

  @override
  String get folderHidden => 'Oculta';

  @override
  String get folderDelete => 'Excluir pasta';

  @override
  String folderDeleteTitle(String name) {
    return 'Excluir “$name”?';
  }

  @override
  String folderDeleteEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Os $count e-mails dela vão para a lixeira.',
      one: 'O e-mail dela vai para a lixeira.',
      zero: 'Não contém e-mails.',
    );
    return '$_temp0';
  }

  @override
  String folderDeleteSubfolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'As $count subpastas dela são excluídas junto.',
      one: 'A subpasta dela é excluída junto.',
    );
    return '$_temp0';
  }

  @override
  String get folderDeleteEnd =>
      'A pasta não poderá ser recuperada; os e-mails, sim, pela lixeira.';

  @override
  String get folderChangeFailed => 'Não foi possível alterar a pasta.';

  @override
  String hiddenFoldersShow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mostrar $count pastas ocultas',
      one: 'Mostrar 1 pasta oculta',
    );
    return '$_temp0';
  }

  @override
  String get hiddenFoldersHide => 'Ocultar as pastas ocultas';

  @override
  String folderExpand(String name) {
    return 'Mostrar as pastas em $name';
  }

  @override
  String folderCollapse(String name) {
    return 'Ocultar as pastas em $name';
  }

  @override
  String get specialFolders => 'Pastas especiais';

  @override
  String get specialFoldersNote =>
      'O Piuma as encontra pelas marcas do servidor e pelos nomes. Se alguma estiver errada, escolha a pasta certa.';

  @override
  String specialFoldersOf(String name) {
    return 'Pastas especiais de $name';
  }

  @override
  String get specialAutomatic => 'Como o servidor indica';

  @override
  String get specialNone => 'Nenhuma';

  @override
  String get specialChosen => 'Escolhida por você';

  @override
  String get listsHeading => 'Listas';

  @override
  String get listOrder => 'Ordem';

  @override
  String get orderNewest => 'Mais recentes primeiro';

  @override
  String get orderOldest => 'Mais antigos primeiro';

  @override
  String get orderSender => 'Por remetente';

  @override
  String get listThreads => 'Agrupar em conversas';

  @override
  String get listThreadsNote => 'Desligado, cada e-mail tem sua própria linha.';

  @override
  String get swipeRight => 'Deslizar para a direita';

  @override
  String get swipeLeft => 'Deslizar para a esquerda';

  @override
  String get swipeRead => 'Lido ou não lido';

  @override
  String get swipeStar => 'Estrela';

  @override
  String get swipeMove => 'Mover para…';

  @override
  String get swipeNothing => 'Nada';

  @override
  String get quotaLabel => 'Armazenamento';

  @override
  String quotaUsed(String used, String limit) {
    return '$used de $limit';
  }

  @override
  String get quotaNearlyFull =>
      'Quase cheio. Exclua ou arquive alguns e-mails, senão os novos podem não chegar.';

  @override
  String draggedEmails(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails',
      one: '1 e-mail',
    );
    return '$_temp0';
  }

  @override
  String get shortcutStar => 'Marcar ou desmarcar com estrela';

  @override
  String badgeTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Piuma Mail ($count)',
      zero: 'Piuma Mail',
    );
    return '$_temp0';
  }

  @override
  String badgeUnread(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count e-mails não lidos',
      one: '1 e-mail não lido',
    );
    return '$_temp0';
  }

  @override
  String get moreShort => 'Mais';

  @override
  String get swipeNote =>
      'Os deslizes funcionam em telefones e tablets. No computador, as mesmas ações estão na barra, nos menus e nos atalhos de teclado.';

  @override
  String folderDeleteProtected(String name, String inside) {
    return '“$name” não pode ser excluída: contém $inside, que seria excluída junto.';
  }

  @override
  String get specialRefused =>
      'Essa pasta não pode fazer esse trabalho: é a caixa de entrada ou já faz outro que apagaria e-mails.';

  @override
  String get fileTypeImages => 'Imagens';

  @override
  String get fileTypeEmail => 'Mensagem de e-mail';

  @override
  String get lockSetting => 'Bloquear o Piuma';

  @override
  String get lockSettingHint =>
      'Pedir o seu PIN, ou o desbloqueio deste dispositivo, para abrir o Piuma.';

  @override
  String get lockAfter => 'Bloquear após';

  @override
  String get lockAfterNow => 'Logo';

  @override
  String lockAfterMinutes(int count) {
    return '$count min';
  }

  @override
  String get lockDeviceSetting => 'Desbloquear com este dispositivo';

  @override
  String get lockDeviceHint =>
      'Impressão digital, rosto ou bloqueio de ecrã. O PIN também funciona sempre.';

  @override
  String get lockDeviceHintWindows =>
      'Windows Hello: rosto, impressão digital ou o seu PIN. O PIN do Piuma também funciona sempre.';

  @override
  String get lockDeviceHintApple =>
      'Touch ID, Face ID ou a palavra-passe do dispositivo. O PIN também funciona sempre.';

  @override
  String get lockPinLabel => 'PIN';

  @override
  String get lockPinHint =>
      'Guardado apenas como hash lento no porta-chaves do sistema.';

  @override
  String get lockChangePin => 'Alterar PIN';

  @override
  String get lockChoosePin => 'Escolha um PIN';

  @override
  String get lockPinWarning =>
      'De 4 a 12 algarismos. Se o esquecer, só o desbloqueio deste dispositivo abre o Piuma, ou apagar os dados do Piuma do dispositivo. Não há outra forma de voltar a entrar.';

  @override
  String get lockNewPin => 'Novo PIN';

  @override
  String get lockPinAgain => 'Escreva-o de novo';

  @override
  String get lockSavePin => 'Guardar PIN';

  @override
  String get lockPinRule => 'Um PIN tem de 4 a 12 algarismos.';

  @override
  String get lockPinMismatch => 'Os dois PIN não coincidem.';

  @override
  String get lockNoKeychain =>
      'O porta-chaves do sistema não conseguiu guardar o PIN, por isso o bloqueio está desligado. No Linux, o Piuma precisa do GNOME Keyring, KWallet ou outro Secret Service.';

  @override
  String get lockSettingNote =>
      'Com o bloqueio ligado, as notificações e um relógio associado nunca mostram o seu correio, mesmo com o Piuma desbloqueado: as notificações dizem só “Novas mensagens”, sem remetente, assunto nem botões, e o relógio não mostra correio. O Piuma também fica oculto nas apps recentes. O bloqueio mantém os outros fora da app; não cifra o correio guardado neste dispositivo.';

  @override
  String get noticeLocked => 'Novas mensagens';

  @override
  String get lockTitle => 'O Piuma está bloqueado';

  @override
  String get lockDevicePrompt => 'Desbloqueie para ver o seu correio.';

  @override
  String get lockPinPrompt => 'Escreva o seu PIN para ver o seu correio.';

  @override
  String get lockReason => 'Desbloquear o Piuma Mail';

  @override
  String get lockUnlock => 'Desbloquear';

  @override
  String get lockUsePin => 'Usar o PIN';

  @override
  String get lockUseDevice => 'Usar o desbloqueio do dispositivo';

  @override
  String get lockWrongPin => 'PIN errado.';

  @override
  String lockWait(String time) {
    return 'Demasiadas tentativas erradas. Tente de novo dentro de $time.';
  }

  @override
  String get lockForgot =>
      'Esqueceu o PIN? Só apagar os dados do Piuma deste dispositivo o volta a abrir; depois as contas são adicionadas de novo.';

  @override
  String get lockForgotDevice =>
      'Esqueceu o PIN? Desbloqueie com este dispositivo. Caso contrário, só apagar os dados do Piuma do dispositivo o volta a abrir.';

  @override
  String get lockPinUnreadable =>
      'O porta-chaves do sistema não devolveu o PIN ao Piuma. Desbloqueie com este dispositivo, ou tente de novo quando o porta-chaves estiver aberto.';

  @override
  String get lockPinMissing =>
      'O bloqueio do Piuma está ativado, mas o porta-chaves do sistema não tem o PIN dele. Desbloqueie com este dispositivo; sem ele, só apagar os dados do Piuma do dispositivo o abre de novo.';

  @override
  String get lockTriesNotKept =>
      'O Piuma não conseguiu registar esta tentativa no porta-chaves do sistema, por isso agora não pode verificar o PIN. Tente de novo daqui a pouco.';
}
