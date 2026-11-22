// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get newChat => 'Nový chat';

  @override
  String get noConversationsYet => 'Zatím žádné konverzace';

  @override
  String get newConversation => 'Nová konverzace';

  @override
  String get newSession => 'Nové sezení';

  @override
  String get noSavedSessionsYet => 'Zatím žádná uložená sezení';

  @override
  String get today => 'dnes';

  @override
  String get yesterday => 'včera';

  @override
  String get exportedToFinetune => 'Exportováno do galerie FINETUNE';

  @override
  String get exportToFinetune => 'Exportovat do galerie FINETUNE';

  @override
  String get tooltipImageStudio => 'Obrázkové studio';

  @override
  String get tooltipMusicStudio => 'Hudební studio';

  @override
  String get tooltipVoiceStudio => 'Hlasové studio';

  @override
  String get tooltipStoryStudio => 'Příběhové studio';

  @override
  String branchHint(String label) {
    return 'Nová zpráva založí větev z „$label“';
  }

  @override
  String get messageHint => 'Napiš zprávu…';

  @override
  String get ocrHint => 'Volitelná instrukce…';

  @override
  String get pickImage => 'Vybrat obrázek';

  @override
  String get inputMode => 'Režim';

  @override
  String get askLibrary => 'Zeptej se knihovny…';

  @override
  String get askLaw => 'Zeptej se na zákon…';

  @override
  String get askLeads => 'Zeptej se na firmy ze smluv…';

  @override
  String get nextMessageRole => 'Role pro další zprávu';

  @override
  String get replyCopied => 'Odpověď zkopírována do schránky';

  @override
  String searchingSeconds(int seconds) {
    return 'hledám… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Nepodařilo se načíst persony:\n$error';
  }

  @override
  String get pickPersona => 'Vyber si personu';

  @override
  String get pickPersonaSub => 'S kým si dnes budeš povídat?';

  @override
  String get speakCancel => 'Zrušit čtení';

  @override
  String get speakPause => 'Pozastavit';

  @override
  String get speakResume => 'Pokračovat';

  @override
  String get speakAloud => 'Přečíst nahlas';

  @override
  String speakRhythm(String rhythm) {
    return 'Přečíst v rytmu ($rhythm)';
  }

  @override
  String get sourceOriginal => 'originál';

  @override
  String linkOpenFailed(String uri) {
    return 'Odkaz nejde otevřít: $uri';
  }

  @override
  String get openOriginal => 'Otevřít originál';

  @override
  String get figureIdCopied => 'ID figurky zkopírováno do schránky';

  @override
  String get figureNameCopied => 'Název zkopírován do schránky';

  @override
  String get dancingFigure => 'Tančící figurka';

  @override
  String get shareGlb => 'Sdílet GLB (Blender, 3D prohlížeče)';

  @override
  String figureLoadFailed(String error) {
    return 'Figurku se nepodařilo načíst: $error';
  }

  @override
  String get model3d => '3D model';

  @override
  String get shareStl => 'Sdílet STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB se nepodařilo načíst: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video uloženo do Fotek';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotky video nepřijaly ($code) — zkus Sdílet';
  }

  @override
  String get share => 'Sdílet';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Uložit do Fotek';

  @override
  String get hairdresser => 'Kadeřník';

  @override
  String get hairdresserHint =>
      'Tvář zůstane; barva vlasů taky, pokud nevybereš novou. Nejlíp funguje čelní portrét s celými vlasy, bez čepice.';

  @override
  String get colourUnchanged => 'Barva beze změny';

  @override
  String get colourOnly => 'Jen barva';

  @override
  String get noHairstylesYet => 'Zatím žádné účesy.';

  @override
  String get searchHairstyle => 'Hledat účes';

  @override
  String mapLoadFailed(String error) {
    return 'mapa se nenačetla: $error';
  }

  @override
  String copiedText(String text) {
    return 'Zkopírováno: $text';
  }

  @override
  String get styleMaps => 'Mapy stylů';

  @override
  String get use => 'Použít';

  @override
  String get copy => 'Kopírovat';

  @override
  String get retry => 'Znovu';

  @override
  String get noMapsOnServer => 'Na serveru zatím žádná mapa není.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count obrázků',
      few: '$count obrázky',
      one: '$count obrázek',
    );
    return '$_temp0';
  }
}
