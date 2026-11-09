// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Catalan Valencian (`ca`).
class AppLocalizationsCa extends AppLocalizations {
  AppLocalizationsCa([String locale = 'ca']) : super(locale);

  @override
  String get newChat => 'Xat nou';

  @override
  String get noConversationsYet => 'Encara no hi ha converses';

  @override
  String get newConversation => 'Conversa nova';

  @override
  String get newSession => 'Sessió nova';

  @override
  String get noSavedSessionsYet => 'Encara no hi ha sessions desades';

  @override
  String get today => 'avui';

  @override
  String get yesterday => 'ahir';

  @override
  String get exportedToFinetune => 'Exportat a la galeria FINETUNE';

  @override
  String get exportToFinetune => 'Exporta a la galeria FINETUNE';

  @override
  String get tooltipImageStudio => 'Estudi d’imatges';

  @override
  String get tooltipMusicStudio => 'Estudi de música';

  @override
  String get tooltipVoiceStudio => 'Estudi de veu';

  @override
  String get tooltipStoryStudio => 'Estudi d’històries';

  @override
  String branchHint(String label) {
    return 'Un missatge nou crearà una branca a partir de «$label»';
  }

  @override
  String get messageHint => 'Escriu al laboratori…';

  @override
  String get ocrHint => 'Instrucció opcional…';

  @override
  String get pickImage => 'Tria una imatge';

  @override
  String get inputMode => 'Mode';

  @override
  String get askLibrary => 'Pregunta a la biblioteca…';

  @override
  String get askLaw => 'Pregunta sobre la llei…';

  @override
  String get askLeads => 'Pregunta per empreses dels contractes…';

  @override
  String get nextMessageRole => 'Rol per al missatge següent';

  @override
  String get replyCopied => 'Resposta copiada al porta-retalls';

  @override
  String searchingSeconds(int seconds) {
    return 'cercant… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'No s’han pogut carregar els personatges:\n$error';
  }

  @override
  String get pickPersona => 'Tria un personatge';

  @override
  String get pickPersonaSub => 'Amb qui vols parlar avui?';

  @override
  String get speakCancel => 'Cancel·la la lectura';

  @override
  String get speakPause => 'Atura';

  @override
  String get speakResume => 'Reprèn';

  @override
  String get speakAloud => 'Llegeix en veu alta';

  @override
  String speakRhythm(String rhythm) {
    return 'Llegeix al ritme ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'No es pot obrir l’enllaç: $uri';
  }

  @override
  String get openOriginal => 'Obre l’original';

  @override
  String get figureIdCopied => 'ID de la figura copiat al porta-retalls';

  @override
  String get figureNameCopied => 'Nom copiat al porta-retalls';

  @override
  String get dancingFigure => 'Figura ballarina';

  @override
  String get shareGlb => 'Comparteix el GLB (Blender, visors 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'No s’ha pogut carregar la figura: $error';
  }

  @override
  String get model3d => 'Model 3D';

  @override
  String get shareStl => 'Comparteix l’STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'No s’ha pogut carregar el GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Vídeo desat a Fotos';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotos ha rebutjat el vídeo ($code); prova Comparteix';
  }

  @override
  String get share => 'Comparteix';

  @override
  String get video => 'Vídeo';

  @override
  String get saveToPhotos => 'Desa a Fotos';

  @override
  String get hairdresser => 'Perruquer';

  @override
  String get hairdresserHint =>
      'La cara es manté, i el color del cabell també si no en tries un de nou. Funciona millor amb un retrat de front amb tot el cabell visible i sense gorra.';

  @override
  String get colourUnchanged => 'Color sense canvis';

  @override
  String get colourOnly => 'Només el color';

  @override
  String get noHairstylesYet => 'Encara no hi ha pentinats.';

  @override
  String get searchHairstyle => 'Cerca un pentinat';

  @override
  String mapLoadFailed(String error) {
    return 'no s’ha pogut carregar el mapa: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiat: $text';
  }

  @override
  String get styleMaps => 'Mapes d’estils';

  @override
  String get use => 'Fes servir';

  @override
  String get copy => 'Copia';

  @override
  String get retry => 'Torna-ho a provar';

  @override
  String get noMapsOnServer => 'Encara no hi ha cap mapa al servidor.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imatges',
      one: '$count imatge',
    );
    return '$_temp0';
  }
}
