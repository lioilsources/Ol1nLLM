// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Danish (`da`).
class AppLocalizationsDa extends AppLocalizations {
  AppLocalizationsDa([String locale = 'da']) : super(locale);

  @override
  String get newChat => 'Ny chat';

  @override
  String get noConversationsYet => 'Ingen samtaler endnu';

  @override
  String get newConversation => 'Ny samtale';

  @override
  String get newSession => 'Ny session';

  @override
  String get noSavedSessionsYet => 'Ingen gemte sessioner endnu';

  @override
  String get today => 'i dag';

  @override
  String get yesterday => 'i går';

  @override
  String get exportedToFinetune => 'Eksporteret til FINETUNE-galleriet';

  @override
  String get exportToFinetune => 'Eksportér til FINETUNE-galleriet';

  @override
  String get tooltipImageStudio => 'Billedstudie';

  @override
  String get tooltipMusicStudio => 'Musikstudie';

  @override
  String get tooltipVoiceStudio => 'Stemmestudie';

  @override
  String get tooltipStoryStudio => 'Historiestudie';

  @override
  String branchHint(String label) {
    return 'En ny besked starter en gren fra “$label”';
  }

  @override
  String get messageHint => 'Skriv til laboratoriet…';

  @override
  String get ocrHint => 'Valgfri instruktion…';

  @override
  String get pickImage => 'Vælg billede';

  @override
  String get inputMode => 'Tilstand';

  @override
  String get askLibrary => 'Spørg biblioteket…';

  @override
  String get askLaw => 'Spørg om loven…';

  @override
  String get askLeads => 'Spørg om virksomheder fra kontrakter…';

  @override
  String get nextMessageRole => 'Rolle til næste besked';

  @override
  String get replyCopied => 'Svaret er kopieret til udklipsholderen';

  @override
  String searchingSeconds(int seconds) {
    return 'søger… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Personaer kunne ikke indlæses:\n$error';
  }

  @override
  String get pickPersona => 'Vælg en persona';

  @override
  String get pickPersonaSub => 'Hvem vil du tale med i dag?';

  @override
  String get speakCancel => 'Annullér oplæsning';

  @override
  String get speakPause => 'Sæt på pause';

  @override
  String get speakResume => 'Fortsæt';

  @override
  String get speakAloud => 'Læs højt';

  @override
  String speakRhythm(String rhythm) {
    return 'Læs i takt ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Linket kan ikke åbnes: $uri';
  }

  @override
  String get openOriginal => 'Åbn original';

  @override
  String get figureIdCopied => 'Figurens ID er kopieret til udklipsholderen';

  @override
  String get figureNameCopied => 'Navnet er kopieret til udklipsholderen';

  @override
  String get dancingFigure => 'Dansende figur';

  @override
  String get shareGlb => 'Del GLB (Blender, 3D-fremvisere)';

  @override
  String figureLoadFailed(String error) {
    return 'Figuren kunne ikke indlæses: $error';
  }

  @override
  String get model3d => '3D-model';

  @override
  String get shareStl => 'Del STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB kunne ikke indlæses: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video gemt i Fotos';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotos afviste videoen ($code) – prøv Del';
  }

  @override
  String get share => 'Del';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Gem i Fotos';

  @override
  String get hairdresser => 'Frisør';

  @override
  String get hairdresserHint =>
      'Ansigtet bliver det samme, og det gør hårfarven også, medmindre du vælger en ny. Virker bedst med et portræt forfra, hvor hele håret kan ses, uden hat.';

  @override
  String get colourUnchanged => 'Farve uændret';

  @override
  String get colourOnly => 'Kun farve';

  @override
  String get noHairstylesYet => 'Ingen frisurer endnu.';

  @override
  String get searchHairstyle => 'Søg frisure';

  @override
  String mapLoadFailed(String error) {
    return 'kortet kunne ikke indlæses: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopieret: $text';
  }

  @override
  String get styleMaps => 'Stilkort';

  @override
  String get use => 'Brug';

  @override
  String get copy => 'Kopiér';

  @override
  String get retry => 'Prøv igen';

  @override
  String get noMapsOnServer => 'Der er endnu ikke noget kort på serveren.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count billeder',
      one: '$count billede',
    );
    return '$_temp0';
  }
}
