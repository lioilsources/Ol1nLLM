// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Gujarati (`gu`).
class AppLocalizationsGu extends AppLocalizations {
  AppLocalizationsGu([String locale = 'gu']) : super(locale);

  @override
  String get newChat => 'નવી ચેટ';

  @override
  String get noConversationsYet => 'હજી સુધી કોઈ વાતચીત નથી';

  @override
  String get newConversation => 'નવી વાતચીત';

  @override
  String get newSession => 'નવું સત્ર';

  @override
  String get noSavedSessionsYet => 'હજી સુધી કોઈ સાચવેલું સત્ર નથી';

  @override
  String get today => 'આજે';

  @override
  String get yesterday => 'ગઈકાલે';

  @override
  String get exportedToFinetune => 'FINETUNE ગૅલેરીમાં નિકાસ કર્યું';

  @override
  String get exportToFinetune => 'FINETUNE ગૅલેરીમાં નિકાસ કરો';

  @override
  String get tooltipImageStudio => 'ઇમેજ સ્ટુડિયો';

  @override
  String get tooltipMusicStudio => 'મ્યુઝિક સ્ટુડિયો';

  @override
  String get tooltipVoiceStudio => 'વૉઇસ સ્ટુડિયો';

  @override
  String get tooltipStoryStudio => 'સ્ટોરી સ્ટુડિયો';

  @override
  String branchHint(String label) {
    return 'નવો સંદેશ “$label” પરથી શાખા બનાવશે';
  }

  @override
  String get messageHint => 'લૅબને સંદેશ લખો…';

  @override
  String get ocrHint => 'વૈકલ્પિક સૂચના…';

  @override
  String get pickImage => 'છબી પસંદ કરો';

  @override
  String get inputMode => 'મોડ';

  @override
  String get askLibrary => 'લાઇબ્રેરીને પૂછો…';

  @override
  String get askLaw => 'કાયદા વિશે પૂછો…';

  @override
  String get askLeads => 'કરારોમાંની કંપનીઓ વિશે પૂછો…';

  @override
  String get nextMessageRole => 'આગલા સંદેશની ભૂમિકા';

  @override
  String get replyCopied => 'જવાબ ક્લિપબોર્ડ પર કૉપિ થયો';

  @override
  String searchingSeconds(int seconds) {
    return 'શોધી રહ્યું છે… $seconds સે';
  }

  @override
  String personasLoadFailed(String error) {
    return 'પર્સોના લોડ થઈ શક્યા નથી:\n$error';
  }

  @override
  String get pickPersona => 'પર્સોના પસંદ કરો';

  @override
  String get pickPersonaSub => 'આજે તમે કોની સાથે વાત કરવા માગો છો?';

  @override
  String get speakCancel => 'વાંચન રદ કરો';

  @override
  String get speakPause => 'થોભાવો';

  @override
  String get speakResume => 'ચાલુ રાખો';

  @override
  String get speakAloud => 'મોટેથી વાંચો';

  @override
  String speakRhythm(String rhythm) {
    return 'લયમાં વાંચો ($rhythm)';
  }

  @override
  String get sourceOriginal => 'મૂળ';

  @override
  String linkOpenFailed(String uri) {
    return 'લિંક ખૂલી શકી નથી: $uri';
  }

  @override
  String get openOriginal => 'મૂળ ખોલો';

  @override
  String get figureIdCopied => 'ફિગરનો ID ક્લિપબોર્ડ પર કૉપિ થયો';

  @override
  String get figureNameCopied => 'નામ ક્લિપબોર્ડ પર કૉપિ થયું';

  @override
  String get dancingFigure => 'નાચતી ફિગર';

  @override
  String get shareGlb => 'GLB શેર કરો (Blender, 3D વ્યૂઅર)';

  @override
  String figureLoadFailed(String error) {
    return 'ફિગર લોડ થઈ શકી નથી: $error';
  }

  @override
  String get model3d => '3D મૉડલ';

  @override
  String get shareStl => 'STL શેર કરો (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB લોડ થઈ શક્યું નથી: $error';
  }

  @override
  String get videoSavedToPhotos => 'વીડિયો ફોટોમાં સાચવ્યો';

  @override
  String photosRejectedVideo(String code) {
    return 'ફોટોએ વીડિયો સ્વીકાર્યો નથી ($code) — શેર કરીને જુઓ';
  }

  @override
  String get share => 'શેર કરો';

  @override
  String get video => 'વીડિયો';

  @override
  String get saveToPhotos => 'ફોટોમાં સાચવો';

  @override
  String get hairdresser => 'હેરડ્રેસર';

  @override
  String get hairdresserHint =>
      'ચહેરો એવો જ રહેશે, અને વાળનો રંગ પણ, જ્યાં સુધી તમે નવો રંગ ન પસંદ કરો. સામેથી લીધેલા એવા પોર્ટ્રેટ સાથે શ્રેષ્ઠ કામ કરે છે જેમાં આખા વાળ દેખાય અને ટોપી ન હોય.';

  @override
  String get colourUnchanged => 'રંગમાં ફેરફાર નહીં';

  @override
  String get colourOnly => 'ફક્ત રંગ';

  @override
  String get noHairstylesYet => 'હજી સુધી કોઈ હેરસ્ટાઇલ નથી.';

  @override
  String get searchHairstyle => 'હેરસ્ટાઇલ શોધો';

  @override
  String mapLoadFailed(String error) {
    return 'નકશો લોડ થઈ શક્યો નથી: $error';
  }

  @override
  String copiedText(String text) {
    return 'કૉપિ થયું: $text';
  }

  @override
  String get styleMaps => 'સ્ટાઇલ મૅપ';

  @override
  String get use => 'વાપરો';

  @override
  String get copy => 'કૉપિ કરો';

  @override
  String get retry => 'ફરી પ્રયાસ કરો';

  @override
  String get noMapsOnServer => 'સર્વર પર હજી કોઈ નકશો નથી.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count છબીઓ',
      one: '$count છબી',
    );
    return '$_temp0';
  }
}
