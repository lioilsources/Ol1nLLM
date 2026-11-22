// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Finnish (`fi`).
class AppLocalizationsFi extends AppLocalizations {
  AppLocalizationsFi([String locale = 'fi']) : super(locale);

  @override
  String get newChat => 'Uusi keskustelu';

  @override
  String get noConversationsYet => 'Ei vielä keskusteluja';

  @override
  String get newConversation => 'Uusi keskustelu';

  @override
  String get newSession => 'Uusi istunto';

  @override
  String get noSavedSessionsYet => 'Ei vielä tallennettuja istuntoja';

  @override
  String get today => 'tänään';

  @override
  String get yesterday => 'eilen';

  @override
  String get exportedToFinetune => 'Viety FINETUNE-galleriaan';

  @override
  String get exportToFinetune => 'Vie FINETUNE-galleriaan';

  @override
  String get tooltipImageStudio => 'Kuvastudio';

  @override
  String get tooltipMusicStudio => 'Musiikkistudio';

  @override
  String get tooltipVoiceStudio => 'Äänistudio';

  @override
  String get tooltipStoryStudio => 'Tarinastudio';

  @override
  String branchHint(String label) {
    return 'Uusi viesti aloittaa haaran kohdasta ”$label”';
  }

  @override
  String get messageHint => 'Kirjoita laboratoriolle…';

  @override
  String get ocrHint => 'Valinnainen ohje…';

  @override
  String get pickImage => 'Valitse kuva';

  @override
  String get inputMode => 'Tila';

  @override
  String get askLibrary => 'Kysy kirjastolta…';

  @override
  String get askLaw => 'Kysy laista…';

  @override
  String get askLeads => 'Kysy sopimusten yrityksistä…';

  @override
  String get nextMessageRole => 'Seuraavan viestin rooli';

  @override
  String get replyCopied => 'Vastaus kopioitu leikepöydälle';

  @override
  String searchingSeconds(int seconds) {
    return 'haetaan… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Persoonien lataus epäonnistui:\n$error';
  }

  @override
  String get pickPersona => 'Valitse persoona';

  @override
  String get pickPersonaSub => 'Kenen kanssa haluat jutella tänään?';

  @override
  String get speakCancel => 'Peruuta lukeminen';

  @override
  String get speakPause => 'Keskeytä';

  @override
  String get speakResume => 'Jatka';

  @override
  String get speakAloud => 'Lue ääneen';

  @override
  String speakRhythm(String rhythm) {
    return 'Lue rytmissä ($rhythm)';
  }

  @override
  String get sourceOriginal => 'alkuperäinen';

  @override
  String linkOpenFailed(String uri) {
    return 'Linkkiä ei voi avata: $uri';
  }

  @override
  String get openOriginal => 'Avaa alkuperäinen';

  @override
  String get figureIdCopied => 'Hahmon tunnus kopioitu leikepöydälle';

  @override
  String get figureNameCopied => 'Nimi kopioitu leikepöydälle';

  @override
  String get dancingFigure => 'Tanssiva hahmo';

  @override
  String get shareGlb => 'Jaa GLB (Blender, 3D-katseluohjelmat)';

  @override
  String figureLoadFailed(String error) {
    return 'Hahmon lataus epäonnistui: $error';
  }

  @override
  String get model3d => '3D-malli';

  @override
  String get shareStl => 'Jaa STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB:n lataus epäonnistui: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video tallennettu Kuviin';

  @override
  String photosRejectedVideo(String code) {
    return 'Kuvat hylkäsi videon ($code) – kokeile Jaa';
  }

  @override
  String get share => 'Jaa';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Tallenna Kuviin';

  @override
  String get hairdresser => 'Kampaaja';

  @override
  String get hairdresserHint =>
      'Kasvot pysyvät samoina, samoin hiusten väri, ellet valitse uutta. Toimii parhaiten edestä otetulla muotokuvalla, jossa koko tukka näkyy eikä ole lakkia.';

  @override
  String get colourUnchanged => 'Väri ennallaan';

  @override
  String get colourOnly => 'Vain väri';

  @override
  String get noHairstylesYet => 'Ei vielä kampauksia.';

  @override
  String get searchHairstyle => 'Hae kampausta';

  @override
  String mapLoadFailed(String error) {
    return 'kartan lataus epäonnistui: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopioitu: $text';
  }

  @override
  String get styleMaps => 'Tyylikartat';

  @override
  String get use => 'Käytä';

  @override
  String get copy => 'Kopioi';

  @override
  String get retry => 'Yritä uudelleen';

  @override
  String get noMapsOnServer => 'Palvelimella ei ole vielä karttoja.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kuvaa',
      one: '$count kuva',
    );
    return '$_temp0';
  }
}
