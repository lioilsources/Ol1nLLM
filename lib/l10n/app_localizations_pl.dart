// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get newChat => 'Nowy czat';

  @override
  String get noConversationsYet => 'Brak rozmów';

  @override
  String get newConversation => 'Nowa rozmowa';

  @override
  String get newSession => 'Nowa sesja';

  @override
  String get noSavedSessionsYet => 'Brak zapisanych sesji';

  @override
  String get today => 'dzisiaj';

  @override
  String get yesterday => 'wczoraj';

  @override
  String get exportedToFinetune => 'Wyeksportowano do galerii FINETUNE';

  @override
  String get exportToFinetune => 'Eksportuj do galerii FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio obrazów';

  @override
  String get tooltipMusicStudio => 'Studio muzyczne';

  @override
  String get tooltipVoiceStudio => 'Studio głosu';

  @override
  String get tooltipStoryStudio => 'Studio opowieści';

  @override
  String branchHint(String label) {
    return 'Nowa wiadomość utworzy gałąź od „$label”';
  }

  @override
  String get messageHint => 'Napisz do laboratorium…';

  @override
  String get ocrHint => 'Opcjonalna instrukcja…';

  @override
  String get pickImage => 'Wybierz obraz';

  @override
  String get inputMode => 'Tryb';

  @override
  String get askLibrary => 'Zapytaj bibliotekę…';

  @override
  String get askLaw => 'Zapytaj o prawo…';

  @override
  String get askLeads => 'Zapytaj o firmy z umów…';

  @override
  String get nextMessageRole => 'Rola dla następnej wiadomości';

  @override
  String get replyCopied => 'Odpowiedź skopiowana do schowka';

  @override
  String searchingSeconds(int seconds) {
    return 'szukam… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Nie udało się wczytać person:\n$error';
  }

  @override
  String get pickPersona => 'Wybierz personę';

  @override
  String get pickPersonaSub => 'Z kim chcesz dziś porozmawiać?';

  @override
  String get speakCancel => 'Anuluj czytanie';

  @override
  String get speakPause => 'Wstrzymaj';

  @override
  String get speakResume => 'Wznów';

  @override
  String get speakAloud => 'Czytaj na głos';

  @override
  String speakRhythm(String rhythm) {
    return 'Czytaj w rytmie ($rhythm)';
  }

  @override
  String get sourceOriginal => 'oryginał';

  @override
  String linkOpenFailed(String uri) {
    return 'Nie można otworzyć linku: $uri';
  }

  @override
  String get openOriginal => 'Otwórz oryginał';

  @override
  String get figureIdCopied => 'Identyfikator figurki skopiowany do schowka';

  @override
  String get figureNameCopied => 'Nazwa skopiowana do schowka';

  @override
  String get dancingFigure => 'Tańcząca figurka';

  @override
  String get shareGlb => 'Udostępnij GLB (Blender, przeglądarki 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Nie udało się wczytać figurki: $error';
  }

  @override
  String get model3d => 'Model 3D';

  @override
  String get shareStl => 'Udostępnij STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Nie udało się wczytać GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Wideo zapisane w Zdjęciach';

  @override
  String photosRejectedVideo(String code) {
    return 'Zdjęcia odrzuciły wideo ($code) — spróbuj Udostępnij';
  }

  @override
  String get share => 'Udostępnij';

  @override
  String get video => 'Wideo';

  @override
  String get saveToPhotos => 'Zapisz w Zdjęciach';

  @override
  String get hairdresser => 'Fryzjer';

  @override
  String get hairdresserHint =>
      'Twarz pozostaje taka sama, kolor włosów również, jeśli nie wybierzesz nowego. Najlepiej działa portret en face z całymi włosami, bez czapki.';

  @override
  String get colourUnchanged => 'Kolor bez zmian';

  @override
  String get colourOnly => 'Tylko kolor';

  @override
  String get noHairstylesYet => 'Brak fryzur.';

  @override
  String get searchHairstyle => 'Szukaj fryzury';

  @override
  String mapLoadFailed(String error) {
    return 'nie udało się wczytać mapy: $error';
  }

  @override
  String copiedText(String text) {
    return 'Skopiowano: $text';
  }

  @override
  String get styleMaps => 'Mapy stylów';

  @override
  String get use => 'Użyj';

  @override
  String get copy => 'Kopiuj';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get noMapsOnServer => 'Na serwerze nie ma jeszcze żadnej mapy.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count obrazu',
      many: '$count obrazów',
      few: '$count obrazy',
      one: '$count obraz',
    );
    return '$_temp0';
  }
}
