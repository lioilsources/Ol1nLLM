// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovak (`sk`).
class AppLocalizationsSk extends AppLocalizations {
  AppLocalizationsSk([String locale = 'sk']) : super(locale);

  @override
  String get newChat => 'Nový čet';

  @override
  String get noConversationsYet => 'Zatiaľ žiadne konverzácie';

  @override
  String get newConversation => 'Nová konverzácia';

  @override
  String get newSession => 'Nové sedenie';

  @override
  String get noSavedSessionsYet => 'Zatiaľ žiadne uložené sedenia';

  @override
  String get today => 'dnes';

  @override
  String get yesterday => 'včera';

  @override
  String get exportedToFinetune => 'Exportované do galérie FINETUNE';

  @override
  String get exportToFinetune => 'Exportovať do galérie FINETUNE';

  @override
  String get tooltipImageStudio => 'Obrázkové štúdio';

  @override
  String get tooltipMusicStudio => 'Hudobné štúdio';

  @override
  String get tooltipVoiceStudio => 'Hlasové štúdio';

  @override
  String get tooltipStoryStudio => 'Príbehové štúdio';

  @override
  String branchHint(String label) {
    return 'Nová správa založí vetvu z „$label“';
  }

  @override
  String get messageHint => 'Napíš správu laboratóriu…';

  @override
  String get ocrHint => 'Voliteľná inštrukcia…';

  @override
  String get pickImage => 'Vybrať obrázok';

  @override
  String get inputMode => 'Režim';

  @override
  String get askLibrary => 'Opýtaj sa knižnice…';

  @override
  String get askLaw => 'Opýtaj sa na zákon…';

  @override
  String get askLeads => 'Opýtaj sa na firmy zo zmlúv…';

  @override
  String get nextMessageRole => 'Rola pre ďalšiu správu';

  @override
  String get replyCopied => 'Odpoveď skopírovaná do schránky';

  @override
  String searchingSeconds(int seconds) {
    return 'hľadám… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Nepodarilo sa načítať persóny:\n$error';
  }

  @override
  String get pickPersona => 'Vyber si persónu';

  @override
  String get pickPersonaSub => 'S kým sa dnes budeš rozprávať?';

  @override
  String get speakCancel => 'Zrušiť čítanie';

  @override
  String get speakPause => 'Pozastaviť';

  @override
  String get speakResume => 'Pokračovať';

  @override
  String get speakAloud => 'Prečítať nahlas';

  @override
  String speakRhythm(String rhythm) {
    return 'Prečítať v rytme ($rhythm)';
  }

  @override
  String get sourceOriginal => 'originál';

  @override
  String linkOpenFailed(String uri) {
    return 'Odkaz sa nedá otvoriť: $uri';
  }

  @override
  String get openOriginal => 'Otvoriť originál';

  @override
  String get figureIdCopied => 'ID figúrky skopírované do schránky';

  @override
  String get figureNameCopied => 'Názov skopírovaný do schránky';

  @override
  String get dancingFigure => 'Tancujúca figúrka';

  @override
  String get shareGlb => 'Zdieľať GLB (Blender, 3D prehliadače)';

  @override
  String figureLoadFailed(String error) {
    return 'Figúrku sa nepodarilo načítať: $error';
  }

  @override
  String get model3d => '3D model';

  @override
  String get shareStl => 'Zdieľať STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB sa nepodarilo načítať: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video uložené do Fotiek';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotky video neprijali ($code) — skús Zdieľať';
  }

  @override
  String get share => 'Zdieľať';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Uložiť do Fotiek';

  @override
  String get hairdresser => 'Kaderník';

  @override
  String get hairdresserHint =>
      'Tvár ostane; farba vlasov tiež, ak nevyberieš novú. Najlepšie funguje čelný portrét s celými vlasmi, bez čiapky.';

  @override
  String get colourUnchanged => 'Farba bez zmeny';

  @override
  String get colourOnly => 'Iba farba';

  @override
  String get noHairstylesYet => 'Zatiaľ žiadne účesy.';

  @override
  String get searchHairstyle => 'Hľadať účes';

  @override
  String mapLoadFailed(String error) {
    return 'mapa sa nenačítala: $error';
  }

  @override
  String copiedText(String text) {
    return 'Skopírované: $text';
  }

  @override
  String get styleMaps => 'Mapy štýlov';

  @override
  String get use => 'Použiť';

  @override
  String get copy => 'Kopírovať';

  @override
  String get retry => 'Znova';

  @override
  String get noMapsOnServer => 'Na serveri zatiaľ nie je žiadna mapa.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count obrázkov',
      few: '$count obrázky',
      one: '$count obrázok',
    );
    return '$_temp0';
  }
}
