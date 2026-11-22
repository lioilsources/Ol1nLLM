// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hungarian (`hu`).
class AppLocalizationsHu extends AppLocalizations {
  AppLocalizationsHu([String locale = 'hu']) : super(locale);

  @override
  String get newChat => 'Új csevegés';

  @override
  String get noConversationsYet => 'Még nincs beszélgetés';

  @override
  String get newConversation => 'Új beszélgetés';

  @override
  String get newSession => 'Új munkamenet';

  @override
  String get noSavedSessionsYet => 'Még nincs mentett munkamenet';

  @override
  String get today => 'ma';

  @override
  String get yesterday => 'tegnap';

  @override
  String get exportedToFinetune => 'Exportálva a FINETUNE galériába';

  @override
  String get exportToFinetune => 'Exportálás a FINETUNE galériába';

  @override
  String get tooltipImageStudio => 'Képstúdió';

  @override
  String get tooltipMusicStudio => 'Zenestúdió';

  @override
  String get tooltipVoiceStudio => 'Hangstúdió';

  @override
  String get tooltipStoryStudio => 'Történetstúdió';

  @override
  String branchHint(String label) {
    return 'Egy új üzenet új ágat nyit innen: „$label”';
  }

  @override
  String get messageHint => 'Írj a laborba…';

  @override
  String get ocrHint => 'Opcionális utasítás…';

  @override
  String get pickImage => 'Kép kiválasztása';

  @override
  String get inputMode => 'Mód';

  @override
  String get askLibrary => 'Kérdezd a könyvtárat…';

  @override
  String get askLaw => 'Kérdezz a törvényről…';

  @override
  String get askLeads => 'Kérdezz a szerződések cégeiről…';

  @override
  String get nextMessageRole => 'Szerep a következő üzenethez';

  @override
  String get replyCopied => 'A válasz a vágólapra másolva';

  @override
  String searchingSeconds(int seconds) {
    return 'keresés… $seconds mp';
  }

  @override
  String personasLoadFailed(String error) {
    return 'A karakterek betöltése nem sikerült:\n$error';
  }

  @override
  String get pickPersona => 'Válassz karaktert';

  @override
  String get pickPersonaSub => 'Kivel szeretnél ma beszélgetni?';

  @override
  String get speakCancel => 'Felolvasás megszakítása';

  @override
  String get speakPause => 'Szünet';

  @override
  String get speakResume => 'Folytatás';

  @override
  String get speakAloud => 'Felolvasás';

  @override
  String speakRhythm(String rhythm) {
    return 'Felolvasás ritmusra ($rhythm)';
  }

  @override
  String get sourceOriginal => 'eredeti';

  @override
  String linkOpenFailed(String uri) {
    return 'A hivatkozás nem nyitható meg: $uri';
  }

  @override
  String get openOriginal => 'Eredeti megnyitása';

  @override
  String get figureIdCopied => 'A figura azonosítója a vágólapra másolva';

  @override
  String get figureNameCopied => 'A név a vágólapra másolva';

  @override
  String get dancingFigure => 'Táncoló figura';

  @override
  String get shareGlb => 'GLB megosztása (Blender, 3D-megjelenítők)';

  @override
  String figureLoadFailed(String error) {
    return 'A figura betöltése nem sikerült: $error';
  }

  @override
  String get model3d => '3D-modell';

  @override
  String get shareStl => 'STL megosztása (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'A GLB betöltése nem sikerült: $error';
  }

  @override
  String get videoSavedToPhotos => 'A videó mentve a Fotókba';

  @override
  String photosRejectedVideo(String code) {
    return 'A Fotók elutasította a videót ($code) – próbáld a Megosztást';
  }

  @override
  String get share => 'Megosztás';

  @override
  String get video => 'Videó';

  @override
  String get saveToPhotos => 'Mentés a Fotókba';

  @override
  String get hairdresser => 'Fodrász';

  @override
  String get hairdresserHint =>
      'Az arc ugyanaz marad, és a hajszín is, ha nem választasz újat. A legjobban egy szemből készült portré működik, amelyen a teljes haj látszik, sapka nélkül.';

  @override
  String get colourUnchanged => 'A szín változatlan';

  @override
  String get colourOnly => 'Csak a szín';

  @override
  String get noHairstylesYet => 'Még nincsenek frizurák.';

  @override
  String get searchHairstyle => 'Frizura keresése';

  @override
  String mapLoadFailed(String error) {
    return 'a térkép betöltése nem sikerült: $error';
  }

  @override
  String copiedText(String text) {
    return 'Másolva: $text';
  }

  @override
  String get styleMaps => 'Stíluskártyák';

  @override
  String get use => 'Használat';

  @override
  String get copy => 'Másolás';

  @override
  String get retry => 'Újra';

  @override
  String get noMapsOnServer => 'A szerveren még nincs térkép.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kép',
      one: '$count kép',
    );
    return '$_temp0';
  }
}
