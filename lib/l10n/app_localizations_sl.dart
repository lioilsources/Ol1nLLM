// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Slovenian (`sl`).
class AppLocalizationsSl extends AppLocalizations {
  AppLocalizationsSl([String locale = 'sl']) : super(locale);

  @override
  String get newChat => 'Nov klepet';

  @override
  String get noConversationsYet => 'Še ni pogovorov';

  @override
  String get newConversation => 'Nov pogovor';

  @override
  String get newSession => 'Nova seja';

  @override
  String get noSavedSessionsYet => 'Še ni shranjenih sej';

  @override
  String get today => 'danes';

  @override
  String get yesterday => 'včeraj';

  @override
  String get exportedToFinetune => 'Izvoženo v galerijo FINETUNE';

  @override
  String get exportToFinetune => 'Izvozi v galerijo FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio slik';

  @override
  String get tooltipMusicStudio => 'Glasbeni studio';

  @override
  String get tooltipVoiceStudio => 'Glasovni studio';

  @override
  String get tooltipStoryStudio => 'Studio zgodb';

  @override
  String branchHint(String label) {
    return 'Novo sporočilo bo ustvarilo vejo iz »$label«';
  }

  @override
  String get messageHint => 'Napiši laboratoriju…';

  @override
  String get ocrHint => 'Neobvezno navodilo…';

  @override
  String get pickImage => 'Izberi sliko';

  @override
  String get inputMode => 'Način';

  @override
  String get askLibrary => 'Vprašaj knjižnico…';

  @override
  String get askLaw => 'Vprašaj o zakonu…';

  @override
  String get askLeads => 'Vprašaj o podjetjih iz pogodb…';

  @override
  String get nextMessageRole => 'Vloga za naslednje sporočilo';

  @override
  String get replyCopied => 'Odgovor je kopiran v odložišče';

  @override
  String searchingSeconds(int seconds) {
    return 'iščem… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Oseb ni bilo mogoče naložiti:\n$error';
  }

  @override
  String get pickPersona => 'Izberi osebo';

  @override
  String get pickPersonaSub => 'S kom se boš danes pogovarjal?';

  @override
  String get speakCancel => 'Prekliči branje';

  @override
  String get speakPause => 'Zaustavi';

  @override
  String get speakResume => 'Nadaljuj';

  @override
  String get speakAloud => 'Preberi na glas';

  @override
  String speakRhythm(String rhythm) {
    return 'Preberi v ritmu ($rhythm)';
  }

  @override
  String get sourceOriginal => 'izvirnik';

  @override
  String linkOpenFailed(String uri) {
    return 'Povezave ni mogoče odpreti: $uri';
  }

  @override
  String get openOriginal => 'Odpri izvirnik';

  @override
  String get figureIdCopied => 'ID figure je kopiran v odložišče';

  @override
  String get figureNameCopied => 'Ime je kopirano v odložišče';

  @override
  String get dancingFigure => 'Plešoča figura';

  @override
  String get shareGlb => 'Deli GLB (Blender, 3D-pregledovalniki)';

  @override
  String figureLoadFailed(String error) {
    return 'Figure ni bilo mogoče naložiti: $error';
  }

  @override
  String get model3d => '3D-model';

  @override
  String get shareStl => 'Deli STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ni bilo mogoče naložiti: $error';
  }

  @override
  String get videoSavedToPhotos => 'Videoposnetek je shranjen v Fotografije';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotografije so zavrnile videoposnetek ($code) – poskusi Deli';
  }

  @override
  String get share => 'Deli';

  @override
  String get video => 'Videoposnetek';

  @override
  String get saveToPhotos => 'Shrani v Fotografije';

  @override
  String get hairdresser => 'Frizer';

  @override
  String get hairdresserHint =>
      'Obraz ostane enak, prav tako barva las, če ne izbereš nove. Najbolje deluje portret od spredaj s celotnimi lasmi in brez kape.';

  @override
  String get colourUnchanged => 'Barva nespremenjena';

  @override
  String get colourOnly => 'Samo barva';

  @override
  String get noHairstylesYet => 'Še ni pričesk.';

  @override
  String get searchHairstyle => 'Poišči pričesko';

  @override
  String mapLoadFailed(String error) {
    return 'zemljevida ni bilo mogoče naložiti: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopirano: $text';
  }

  @override
  String get styleMaps => 'Zemljevidi slogov';

  @override
  String get use => 'Uporabi';

  @override
  String get copy => 'Kopiraj';

  @override
  String get retry => 'Poskusi znova';

  @override
  String get noMapsOnServer => 'Na strežniku še ni nobenega zemljevida.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slik',
      few: '$count slike',
      two: '$count sliki',
      one: '$count slika',
    );
    return '$_temp0';
  }
}
