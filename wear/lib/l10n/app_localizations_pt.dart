// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appName => 'Piuma Mail';

  @override
  String get inbox => 'Caixa de entrada';

  @override
  String newCount(int count) {
    return '$count novos';
  }

  @override
  String get nothingHere => 'Nada novo na caixa';

  @override
  String get openOnPhone => 'Abra o Piuma Mail no celular, perto do relógio';

  @override
  String get reaching => 'Procurando o celular…';

  @override
  String get restOnPhone => 'O resto está no celular';

  @override
  String get archive => 'Arquivar';

  @override
  String get snooze => 'Adiar';

  @override
  String get reply => 'Responder';

  @override
  String replyTo(String name) {
    return 'Responder a $name';
  }

  @override
  String get speakOrType => 'Fale ou digite';

  @override
  String get yourTemplates => 'Seus modelos';

  @override
  String get snoozeUntil => 'Adiar até…';

  @override
  String get snoozeEvening => 'Hoje à noite';

  @override
  String get snoozeMorning => 'Amanhã de manhã';

  @override
  String get snoozeWeekend => 'Fim de semana';

  @override
  String get snoozeNextWeek => 'Semana que vem';

  @override
  String get archived => 'Arquivado';

  @override
  String get snoozed => 'Adiado';

  @override
  String get sent => 'Enviado';

  @override
  String get undo => 'Desfazer';
}
