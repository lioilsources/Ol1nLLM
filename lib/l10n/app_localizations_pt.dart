// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get newChat => 'Novo chat';

  @override
  String get noConversationsYet => 'Nenhuma conversa ainda';

  @override
  String get newConversation => 'Nova conversa';

  @override
  String get newSession => 'Nova sessão';

  @override
  String get noSavedSessionsYet => 'Nenhuma sessão salva ainda';

  @override
  String get today => 'hoje';

  @override
  String get yesterday => 'ontem';

  @override
  String get exportedToFinetune => 'Exportado para a galeria FINETUNE';

  @override
  String get exportToFinetune => 'Exportar para a galeria FINETUNE';

  @override
  String get tooltipImageStudio => 'Estúdio de imagens';

  @override
  String get tooltipMusicStudio => 'Estúdio de música';

  @override
  String get tooltipVoiceStudio => 'Estúdio de voz';

  @override
  String get tooltipStoryStudio => 'Estúdio de histórias';

  @override
  String branchHint(String label) {
    return 'Uma nova mensagem criará uma ramificação a partir de “$label”';
  }

  @override
  String get messageHint => 'Escreva para o laboratório…';

  @override
  String get ocrHint => 'Instrução opcional…';

  @override
  String get pickImage => 'Escolher imagem';

  @override
  String get inputMode => 'Modo';

  @override
  String get askLibrary => 'Pergunte à biblioteca…';

  @override
  String get askLaw => 'Pergunte sobre a lei…';

  @override
  String get askLeads => 'Pergunte sobre empresas de contratos…';

  @override
  String get nextMessageRole => 'Papel para a próxima mensagem';

  @override
  String get replyCopied => 'Resposta copiada para a área de transferência';

  @override
  String searchingSeconds(int seconds) {
    return 'buscando… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Não foi possível carregar as personas:\n$error';
  }

  @override
  String get pickPersona => 'Escolha uma persona';

  @override
  String get pickPersonaSub => 'Com quem você quer conversar hoje?';

  @override
  String get speakCancel => 'Cancelar leitura';

  @override
  String get speakPause => 'Pausar';

  @override
  String get speakResume => 'Continuar';

  @override
  String get speakAloud => 'Ler em voz alta';

  @override
  String speakRhythm(String rhythm) {
    return 'Ler no ritmo ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Não foi possível abrir o link: $uri';
  }

  @override
  String get openOriginal => 'Abrir original';

  @override
  String get figureIdCopied =>
      'ID da figura copiado para a área de transferência';

  @override
  String get figureNameCopied => 'Nome copiado para a área de transferência';

  @override
  String get dancingFigure => 'Figura dançante';

  @override
  String get shareGlb => 'Compartilhar GLB (Blender, visualizadores 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Não foi possível carregar a figura: $error';
  }

  @override
  String get model3d => 'Modelo 3D';

  @override
  String get shareStl => 'Compartilhar STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Não foi possível carregar o GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Vídeo salvo em Fotos';

  @override
  String photosRejectedVideo(String code) {
    return 'O Fotos rejeitou o vídeo ($code) — tente Compartilhar';
  }

  @override
  String get share => 'Compartilhar';

  @override
  String get video => 'Vídeo';

  @override
  String get saveToPhotos => 'Salvar em Fotos';

  @override
  String get hairdresser => 'Cabeleireiro';

  @override
  String get hairdresserHint =>
      'O rosto continua o mesmo, e a cor do cabelo também, a menos que você escolha outra. Funciona melhor com um retrato de frente, com o cabelo inteiro à mostra e sem boné.';

  @override
  String get colourUnchanged => 'Cor inalterada';

  @override
  String get colourOnly => 'Só a cor';

  @override
  String get noHairstylesYet => 'Nenhum penteado ainda.';

  @override
  String get searchHairstyle => 'Buscar penteado';

  @override
  String mapLoadFailed(String error) {
    return 'falha ao carregar o mapa: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiado: $text';
  }

  @override
  String get styleMaps => 'Mapas de estilos';

  @override
  String get use => 'Usar';

  @override
  String get copy => 'Copiar';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get noMapsOnServer => 'Ainda não há nenhum mapa no servidor.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imagens',
      one: '$count imagem',
    );
    return '$_temp0';
  }
}

/// The translations for Portuguese, as used in Portugal (`pt_PT`).
class AppLocalizationsPtPt extends AppLocalizationsPt {
  AppLocalizationsPtPt() : super('pt_PT');

  @override
  String get newChat => 'Novo chat';

  @override
  String get noConversationsYet => 'Ainda sem conversas';

  @override
  String get newConversation => 'Nova conversa';

  @override
  String get newSession => 'Nova sessão';

  @override
  String get noSavedSessionsYet => 'Ainda sem sessões guardadas';

  @override
  String get today => 'hoje';

  @override
  String get yesterday => 'ontem';

  @override
  String get exportedToFinetune => 'Exportado para a galeria FINETUNE';

  @override
  String get exportToFinetune => 'Exportar para a galeria FINETUNE';

  @override
  String get tooltipImageStudio => 'Estúdio de imagens';

  @override
  String get tooltipMusicStudio => 'Estúdio de música';

  @override
  String get tooltipVoiceStudio => 'Estúdio de voz';

  @override
  String get tooltipStoryStudio => 'Estúdio de histórias';

  @override
  String branchHint(String label) {
    return 'Uma nova mensagem criará um ramo a partir de «$label»';
  }

  @override
  String get messageHint => 'Escreve ao laboratório…';

  @override
  String get ocrHint => 'Instrução opcional…';

  @override
  String get pickImage => 'Escolher imagem';

  @override
  String get inputMode => 'Modo';

  @override
  String get askLibrary => 'Pergunta à biblioteca…';

  @override
  String get askLaw => 'Pergunta sobre a lei…';

  @override
  String get askLeads => 'Pergunta por empresas dos contratos…';

  @override
  String get nextMessageRole => 'Papel para a próxima mensagem';

  @override
  String get replyCopied => 'Resposta copiada para a área de transferência';

  @override
  String searchingSeconds(int seconds) {
    return 'a pesquisar… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Não foi possível carregar as personas:\n$error';
  }

  @override
  String get pickPersona => 'Escolhe uma persona';

  @override
  String get pickPersonaSub => 'Com quem queres falar hoje?';

  @override
  String get speakCancel => 'Cancelar leitura';

  @override
  String get speakPause => 'Pausar';

  @override
  String get speakResume => 'Retomar';

  @override
  String get speakAloud => 'Ler em voz alta';

  @override
  String speakRhythm(String rhythm) {
    return 'Ler ao ritmo ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Não é possível abrir a ligação: $uri';
  }

  @override
  String get openOriginal => 'Abrir original';

  @override
  String get figureIdCopied =>
      'ID da figura copiado para a área de transferência';

  @override
  String get figureNameCopied => 'Nome copiado para a área de transferência';

  @override
  String get dancingFigure => 'Figura dançante';

  @override
  String get shareGlb => 'Partilhar GLB (Blender, visualizadores 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Não foi possível carregar a figura: $error';
  }

  @override
  String get model3d => 'Modelo 3D';

  @override
  String get shareStl => 'Partilhar STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Não foi possível carregar o GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Vídeo guardado em Fotografias';

  @override
  String photosRejectedVideo(String code) {
    return 'A app Fotografias rejeitou o vídeo ($code) — tenta Partilhar';
  }

  @override
  String get share => 'Partilhar';

  @override
  String get video => 'Vídeo';

  @override
  String get saveToPhotos => 'Guardar em Fotografias';

  @override
  String get hairdresser => 'Cabeleireiro';

  @override
  String get hairdresserHint =>
      'O rosto mantém-se, e a cor do cabelo também, a menos que escolhas outra. Funciona melhor com um retrato de frente, com o cabelo todo visível e sem boné.';

  @override
  String get colourUnchanged => 'Cor inalterada';

  @override
  String get colourOnly => 'Só a cor';

  @override
  String get noHairstylesYet => 'Ainda sem penteados.';

  @override
  String get searchHairstyle => 'Pesquisar penteado';

  @override
  String mapLoadFailed(String error) {
    return 'falha ao carregar o mapa: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiado: $text';
  }

  @override
  String get styleMaps => 'Mapas de estilos';

  @override
  String get use => 'Usar';

  @override
  String get copy => 'Copiar';

  @override
  String get retry => 'Tentar de novo';

  @override
  String get noMapsOnServer => 'Ainda não há nenhum mapa no servidor.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imagens',
      one: '$count imagem',
    );
    return '$_temp0';
  }
}
