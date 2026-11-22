// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get newChat => 'Chat nou';

  @override
  String get noConversationsYet => 'Încă nu există conversații';

  @override
  String get newConversation => 'Conversație nouă';

  @override
  String get newSession => 'Sesiune nouă';

  @override
  String get noSavedSessionsYet => 'Încă nu există sesiuni salvate';

  @override
  String get today => 'azi';

  @override
  String get yesterday => 'ieri';

  @override
  String get exportedToFinetune => 'Exportat în galeria FINETUNE';

  @override
  String get exportToFinetune => 'Exportă în galeria FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio de imagini';

  @override
  String get tooltipMusicStudio => 'Studio muzical';

  @override
  String get tooltipVoiceStudio => 'Studio vocal';

  @override
  String get tooltipStoryStudio => 'Studio de povești';

  @override
  String branchHint(String label) {
    return 'Un mesaj nou va crea o ramură din „$label”';
  }

  @override
  String get messageHint => 'Scrie laboratorului…';

  @override
  String get ocrHint => 'Instrucțiune opțională…';

  @override
  String get pickImage => 'Alege imaginea';

  @override
  String get inputMode => 'Mod';

  @override
  String get askLibrary => 'Întreabă biblioteca…';

  @override
  String get askLaw => 'Întreabă despre lege…';

  @override
  String get askLeads => 'Întreabă despre firmele din contracte…';

  @override
  String get nextMessageRole => 'Rol pentru mesajul următor';

  @override
  String get replyCopied => 'Răspunsul a fost copiat în clipboard';

  @override
  String searchingSeconds(int seconds) {
    return 'caut… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Nu s-au putut încărca personajele:\n$error';
  }

  @override
  String get pickPersona => 'Alege un personaj';

  @override
  String get pickPersonaSub => 'Cu cine vrei să vorbești azi?';

  @override
  String get speakCancel => 'Anulează citirea';

  @override
  String get speakPause => 'Pauză';

  @override
  String get speakResume => 'Reia';

  @override
  String get speakAloud => 'Citește cu voce tare';

  @override
  String speakRhythm(String rhythm) {
    return 'Citește în ritm ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Linkul nu poate fi deschis: $uri';
  }

  @override
  String get openOriginal => 'Deschide originalul';

  @override
  String get figureIdCopied => 'ID-ul figurinei a fost copiat în clipboard';

  @override
  String get figureNameCopied => 'Numele a fost copiat în clipboard';

  @override
  String get dancingFigure => 'Figurină dansatoare';

  @override
  String get shareGlb => 'Distribuie GLB (Blender, vizualizatoare 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Figurina nu a putut fi încărcată: $error';
  }

  @override
  String get model3d => 'Model 3D';

  @override
  String get shareStl => 'Distribuie STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB nu a putut fi încărcat: $error';
  }

  @override
  String get videoSavedToPhotos => 'Videoclip salvat în Poze';

  @override
  String photosRejectedVideo(String code) {
    return 'Poze a respins videoclipul ($code) — încearcă Distribuie';
  }

  @override
  String get share => 'Distribuie';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Salvează în Poze';

  @override
  String get hairdresser => 'Coafor';

  @override
  String get hairdresserHint =>
      'Fața rămâne aceeași, iar culoarea părului la fel, dacă nu alegi una nouă. Funcționează cel mai bine cu un portret din față, cu tot părul vizibil, fără căciulă.';

  @override
  String get colourUnchanged => 'Culoare neschimbată';

  @override
  String get colourOnly => 'Doar culoarea';

  @override
  String get noHairstylesYet => 'Încă nu există coafuri.';

  @override
  String get searchHairstyle => 'Caută o coafură';

  @override
  String mapLoadFailed(String error) {
    return 'harta nu s-a încărcat: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiat: $text';
  }

  @override
  String get styleMaps => 'Hărți de stiluri';

  @override
  String get use => 'Folosește';

  @override
  String get copy => 'Copiază';

  @override
  String get retry => 'Reîncearcă';

  @override
  String get noMapsOnServer => 'Pe server nu există încă nicio hartă.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de imagini',
      few: '$count imagini',
      one: '$count imagine',
    );
    return '$_temp0';
  }
}
