// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get newChat => 'Ny chatt';

  @override
  String get noConversationsYet => 'Inga konversationer än';

  @override
  String get newConversation => 'Ny konversation';

  @override
  String get newSession => 'Ny session';

  @override
  String get noSavedSessionsYet => 'Inga sparade sessioner än';

  @override
  String get today => 'idag';

  @override
  String get yesterday => 'igår';

  @override
  String get exportedToFinetune => 'Exporterad till FINETUNE-galleriet';

  @override
  String get exportToFinetune => 'Exportera till FINETUNE-galleriet';

  @override
  String get tooltipImageStudio => 'Bildstudio';

  @override
  String get tooltipMusicStudio => 'Musikstudio';

  @override
  String get tooltipVoiceStudio => 'Röststudio';

  @override
  String get tooltipStoryStudio => 'Berättelsestudio';

  @override
  String branchHint(String label) {
    return 'Ett nytt meddelande skapar en gren från ”$label”';
  }

  @override
  String get messageHint => 'Skriv till labbet…';

  @override
  String get ocrHint => 'Valfri instruktion…';

  @override
  String get pickImage => 'Välj bild';

  @override
  String get inputMode => 'Läge';

  @override
  String get askLibrary => 'Fråga biblioteket…';

  @override
  String get askLaw => 'Fråga om lagen…';

  @override
  String get askLeads => 'Fråga om företag i avtal…';

  @override
  String get nextMessageRole => 'Roll för nästa meddelande';

  @override
  String get replyCopied => 'Svaret kopierades till urklipp';

  @override
  String searchingSeconds(int seconds) {
    return 'söker… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Det gick inte att läsa in personor:\n$error';
  }

  @override
  String get pickPersona => 'Välj en persona';

  @override
  String get pickPersonaSub => 'Vem vill du prata med i dag?';

  @override
  String get speakCancel => 'Avbryt uppläsning';

  @override
  String get speakPause => 'Pausa';

  @override
  String get speakResume => 'Återuppta';

  @override
  String get speakAloud => 'Läs upp';

  @override
  String speakRhythm(String rhythm) {
    return 'Läs i takt ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Länken kan inte öppnas: $uri';
  }

  @override
  String get openOriginal => 'Öppna originalet';

  @override
  String get figureIdCopied => 'Figurens ID kopierades till urklipp';

  @override
  String get figureNameCopied => 'Namnet kopierades till urklipp';

  @override
  String get dancingFigure => 'Dansande figur';

  @override
  String get shareGlb => 'Dela GLB (Blender, 3D-visare)';

  @override
  String figureLoadFailed(String error) {
    return 'Det gick inte att läsa in figuren: $error';
  }

  @override
  String get model3d => '3D-modell';

  @override
  String get shareStl => 'Dela STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Det gick inte att läsa in GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Videon sparades i Bilder';

  @override
  String photosRejectedVideo(String code) {
    return 'Bilder avvisade videon ($code) – prova Dela';
  }

  @override
  String get share => 'Dela';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Spara i Bilder';

  @override
  String get hairdresser => 'Frisör';

  @override
  String get hairdresserHint =>
      'Ansiktet förblir detsamma, och det gör hårfärgen också om du inte väljer en ny. Fungerar bäst med ett porträtt framifrån där hela håret syns, utan mössa.';

  @override
  String get colourUnchanged => 'Färgen oförändrad';

  @override
  String get colourOnly => 'Bara färg';

  @override
  String get noHairstylesYet => 'Inga frisyrer än.';

  @override
  String get searchHairstyle => 'Sök frisyr';

  @override
  String mapLoadFailed(String error) {
    return 'kartan kunde inte läsas in: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopierat: $text';
  }

  @override
  String get styleMaps => 'Stilkartor';

  @override
  String get use => 'Använd';

  @override
  String get copy => 'Kopiera';

  @override
  String get retry => 'Försök igen';

  @override
  String get noMapsOnServer => 'Det finns ingen karta på servern än.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bilder',
      one: '$count bild',
    );
    return '$_temp0';
  }
}
