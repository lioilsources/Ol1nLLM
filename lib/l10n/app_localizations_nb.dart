// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Norwegian Bokmål (`nb`).
class AppLocalizationsNb extends AppLocalizations {
  AppLocalizationsNb([String locale = 'nb']) : super(locale);

  @override
  String get newChat => 'Ny chat';

  @override
  String get noConversationsYet => 'Ingen samtaler ennå';

  @override
  String get newConversation => 'Ny samtale';

  @override
  String get newSession => 'Ny økt';

  @override
  String get noSavedSessionsYet => 'Ingen lagrede økter ennå';

  @override
  String get today => 'i dag';

  @override
  String get yesterday => 'i går';

  @override
  String get exportedToFinetune => 'Eksportert til FINETUNE-galleriet';

  @override
  String get exportToFinetune => 'Eksporter til FINETUNE-galleriet';

  @override
  String get tooltipImageStudio => 'Bildestudio';

  @override
  String get tooltipMusicStudio => 'Musikkstudio';

  @override
  String get tooltipVoiceStudio => 'Stemmestudio';

  @override
  String get tooltipStoryStudio => 'Historiestudio';

  @override
  String branchHint(String label) {
    return 'En ny melding starter en gren fra «$label»';
  }

  @override
  String get messageHint => 'Skriv til laben…';

  @override
  String get ocrHint => 'Valgfri instruksjon…';

  @override
  String get pickImage => 'Velg bilde';

  @override
  String get inputMode => 'Modus';

  @override
  String get askLibrary => 'Spør biblioteket…';

  @override
  String get askLaw => 'Spør om loven…';

  @override
  String get askLeads => 'Spør om firmaer fra kontrakter…';

  @override
  String get nextMessageRole => 'Rolle for neste melding';

  @override
  String get replyCopied => 'Svaret er kopiert til utklippstavlen';

  @override
  String searchingSeconds(int seconds) {
    return 'søker… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Kunne ikke laste personaer:\n$error';
  }

  @override
  String get pickPersona => 'Velg en persona';

  @override
  String get pickPersonaSub => 'Hvem vil du snakke med i dag?';

  @override
  String get speakCancel => 'Avbryt opplesing';

  @override
  String get speakPause => 'Pause';

  @override
  String get speakResume => 'Fortsett';

  @override
  String get speakAloud => 'Les opp';

  @override
  String speakRhythm(String rhythm) {
    return 'Les i takt ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Kan ikke åpne lenken: $uri';
  }

  @override
  String get openOriginal => 'Åpne originalen';

  @override
  String get figureIdCopied => 'Figurens ID er kopiert til utklippstavlen';

  @override
  String get figureNameCopied => 'Navnet er kopiert til utklippstavlen';

  @override
  String get dancingFigure => 'Dansende figur';

  @override
  String get shareGlb => 'Del GLB (Blender, 3D-visere)';

  @override
  String figureLoadFailed(String error) {
    return 'Kunne ikke laste figuren: $error';
  }

  @override
  String get model3d => '3D-modell';

  @override
  String get shareStl => 'Del STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Kunne ikke laste GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video lagret i Bilder';

  @override
  String photosRejectedVideo(String code) {
    return 'Bilder avviste videoen ($code) – prøv Del';
  }

  @override
  String get share => 'Del';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Lagre i Bilder';

  @override
  String get hairdresser => 'Frisør';

  @override
  String get hairdresserHint =>
      'Ansiktet forblir det samme, og det gjør hårfargen også med mindre du velger en ny. Fungerer best med et portrett forfra der hele håret synes, uten lue.';

  @override
  String get colourUnchanged => 'Fargen uendret';

  @override
  String get colourOnly => 'Bare farge';

  @override
  String get noHairstylesYet => 'Ingen frisyrer ennå.';

  @override
  String get searchHairstyle => 'Søk etter frisyre';

  @override
  String mapLoadFailed(String error) {
    return 'kartet kunne ikke lastes: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopiert: $text';
  }

  @override
  String get styleMaps => 'Stilkart';

  @override
  String get use => 'Bruk';

  @override
  String get copy => 'Kopier';

  @override
  String get retry => 'Prøv igjen';

  @override
  String get noMapsOnServer => 'Det er ingen kart på serveren ennå.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bilder',
      one: '$count bilde',
    );
    return '$_temp0';
  }
}
