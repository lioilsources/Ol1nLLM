// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get newChat => 'Nieuwe chat';

  @override
  String get noConversationsYet => 'Nog geen gesprekken';

  @override
  String get newConversation => 'Nieuw gesprek';

  @override
  String get newSession => 'Nieuwe sessie';

  @override
  String get noSavedSessionsYet => 'Nog geen opgeslagen sessies';

  @override
  String get today => 'vandaag';

  @override
  String get yesterday => 'gisteren';

  @override
  String get exportedToFinetune => 'Geëxporteerd naar de FINETUNE-galerij';

  @override
  String get exportToFinetune => 'Exporteren naar de FINETUNE-galerij';

  @override
  String get tooltipImageStudio => 'Afbeeldingenstudio';

  @override
  String get tooltipMusicStudio => 'Muziekstudio';

  @override
  String get tooltipVoiceStudio => 'Stemmenstudio';

  @override
  String get tooltipStoryStudio => 'Verhalenstudio';

  @override
  String branchHint(String label) {
    return 'Een nieuw bericht start een tak vanaf “$label”';
  }

  @override
  String get messageHint => 'Bericht aan het lab…';

  @override
  String get ocrHint => 'Optionele instructie…';

  @override
  String get pickImage => 'Afbeelding kiezen';

  @override
  String get inputMode => 'Modus';

  @override
  String get askLibrary => 'Vraag het de bibliotheek…';

  @override
  String get askLaw => 'Vraag iets over de wet…';

  @override
  String get askLeads => 'Vraag naar bedrijven uit contracten…';

  @override
  String get nextMessageRole => 'Rol voor het volgende bericht';

  @override
  String get replyCopied => 'Antwoord gekopieerd naar het klembord';

  @override
  String searchingSeconds(int seconds) {
    return 'zoeken… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Persona’s laden mislukt:\n$error';
  }

  @override
  String get pickPersona => 'Kies een persona';

  @override
  String get pickPersonaSub => 'Met wie wil je vandaag praten?';

  @override
  String get speakCancel => 'Voorlezen annuleren';

  @override
  String get speakPause => 'Pauzeren';

  @override
  String get speakResume => 'Hervatten';

  @override
  String get speakAloud => 'Voorlezen';

  @override
  String speakRhythm(String rhythm) {
    return 'Op het ritme voorlezen ($rhythm)';
  }

  @override
  String get sourceOriginal => 'origineel';

  @override
  String linkOpenFailed(String uri) {
    return 'Link kan niet worden geopend: $uri';
  }

  @override
  String get openOriginal => 'Origineel openen';

  @override
  String get figureIdCopied => 'Figuur-ID gekopieerd naar het klembord';

  @override
  String get figureNameCopied => 'Naam gekopieerd naar het klembord';

  @override
  String get dancingFigure => 'Dansende figuur';

  @override
  String get shareGlb => 'GLB delen (Blender, 3D-viewers)';

  @override
  String figureLoadFailed(String error) {
    return 'Figuur laden mislukt: $error';
  }

  @override
  String get model3d => '3D-model';

  @override
  String get shareStl => 'STL delen (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB laden mislukt: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video bewaard in Foto’s';

  @override
  String photosRejectedVideo(String code) {
    return 'Foto’s heeft de video geweigerd ($code) — probeer Delen';
  }

  @override
  String get share => 'Delen';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Bewaar in Foto’s';

  @override
  String get hairdresser => 'Kapper';

  @override
  String get hairdresserHint =>
      'Het gezicht blijft hetzelfde, en de haarkleur ook als je geen nieuwe kiest. Werkt het best met een portret van voren met het hele haar zichtbaar en zonder pet.';

  @override
  String get colourUnchanged => 'Kleur ongewijzigd';

  @override
  String get colourOnly => 'Alleen kleur';

  @override
  String get noHairstylesYet => 'Nog geen kapsels.';

  @override
  String get searchHairstyle => 'Kapsel zoeken';

  @override
  String mapLoadFailed(String error) {
    return 'kaart laden mislukt: $error';
  }

  @override
  String copiedText(String text) {
    return 'Gekopieerd: $text';
  }

  @override
  String get styleMaps => 'Stijlkaarten';

  @override
  String get use => 'Gebruiken';

  @override
  String get copy => 'Kopiëren';

  @override
  String get retry => 'Opnieuw';

  @override
  String get noMapsOnServer => 'Er staat nog geen kaart op de server.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afbeeldingen',
      one: '$count afbeelding',
    );
    return '$_temp0';
  }
}
