// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Panjabi Punjabi (`pa`).
class AppLocalizationsPa extends AppLocalizations {
  AppLocalizationsPa([String locale = 'pa']) : super(locale);

  @override
  String get newChat => 'ਨਵੀਂ ਚੈਟ';

  @override
  String get noConversationsYet => 'ਹਾਲੇ ਕੋਈ ਗੱਲਬਾਤ ਨਹੀਂ';

  @override
  String get newConversation => 'ਨਵੀਂ ਗੱਲਬਾਤ';

  @override
  String get newSession => 'ਨਵਾਂ ਸੈਸ਼ਨ';

  @override
  String get noSavedSessionsYet => 'ਹਾਲੇ ਕੋਈ ਸੰਭਾਲਿਆ ਸੈਸ਼ਨ ਨਹੀਂ';

  @override
  String get today => 'ਅੱਜ';

  @override
  String get yesterday => 'ਕੱਲ੍ਹ';

  @override
  String get exportedToFinetune => 'FINETUNE ਗੈਲਰੀ ਵਿੱਚ ਐਕਸਪੋਰਟ ਕੀਤਾ ਗਿਆ';

  @override
  String get exportToFinetune => 'FINETUNE ਗੈਲਰੀ ਵਿੱਚ ਐਕਸਪੋਰਟ ਕਰੋ';

  @override
  String get tooltipImageStudio => 'ਇਮੇਜ ਸਟੂਡੀਓ';

  @override
  String get tooltipMusicStudio => 'ਮਿਊਜ਼ਿਕ ਸਟੂਡੀਓ';

  @override
  String get tooltipVoiceStudio => 'ਵੌਇਸ ਸਟੂਡੀਓ';

  @override
  String get tooltipStoryStudio => 'ਸਟੋਰੀ ਸਟੂਡੀਓ';

  @override
  String branchHint(String label) {
    return 'ਨਵਾਂ ਸੁਨੇਹਾ “$label” ਤੋਂ ਇੱਕ ਸ਼ਾਖਾ ਬਣਾਵੇਗਾ';
  }

  @override
  String get messageHint => 'ਲੈਬ ਨੂੰ ਸੁਨੇਹਾ ਲਿਖੋ…';

  @override
  String get ocrHint => 'ਵਿਕਲਪਿਕ ਹਦਾਇਤ…';

  @override
  String get pickImage => 'ਤਸਵੀਰ ਚੁਣੋ';

  @override
  String get inputMode => 'ਮੋਡ';

  @override
  String get askLibrary => 'ਲਾਇਬ੍ਰੇਰੀ ਤੋਂ ਪੁੱਛੋ…';

  @override
  String get askLaw => 'ਕਾਨੂੰਨ ਬਾਰੇ ਪੁੱਛੋ…';

  @override
  String get askLeads => 'ਇਕਰਾਰਨਾਮਿਆਂ ਵਿਚਲੀਆਂ ਕੰਪਨੀਆਂ ਬਾਰੇ ਪੁੱਛੋ…';

  @override
  String get nextMessageRole => 'ਅਗਲੇ ਸੁਨੇਹੇ ਦੀ ਭੂਮਿਕਾ';

  @override
  String get replyCopied => 'ਜਵਾਬ ਕਲਿੱਪਬੋਰਡ ’ਤੇ ਕਾਪੀ ਹੋ ਗਿਆ';

  @override
  String searchingSeconds(int seconds) {
    return 'ਖੋਜ ਰਿਹਾ ਹੈ… $seconds ਸਕਿੰ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'ਪਰਸੋਨਾ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕੇ:\n$error';
  }

  @override
  String get pickPersona => 'ਇੱਕ ਪਰਸੋਨਾ ਚੁਣੋ';

  @override
  String get pickPersonaSub => 'ਅੱਜ ਤੁਸੀਂ ਕਿਸ ਨਾਲ ਗੱਲ ਕਰਨਾ ਚਾਹੁੰਦੇ ਹੋ?';

  @override
  String get speakCancel => 'ਪੜ੍ਹਨਾ ਰੱਦ ਕਰੋ';

  @override
  String get speakPause => 'ਰੋਕੋ';

  @override
  String get speakResume => 'ਜਾਰੀ ਰੱਖੋ';

  @override
  String get speakAloud => 'ਉੱਚੀ ਪੜ੍ਹੋ';

  @override
  String speakRhythm(String rhythm) {
    return 'ਤਾਲ ਵਿੱਚ ਪੜ੍ਹੋ ($rhythm)';
  }

  @override
  String get sourceOriginal => 'ਮੂਲ';

  @override
  String linkOpenFailed(String uri) {
    return 'ਲਿੰਕ ਨਹੀਂ ਖੁੱਲ੍ਹ ਸਕਿਆ: $uri';
  }

  @override
  String get openOriginal => 'ਮੂਲ ਖੋਲ੍ਹੋ';

  @override
  String get figureIdCopied => 'ਫਿਗਰ ਦੀ ID ਕਲਿੱਪਬੋਰਡ ’ਤੇ ਕਾਪੀ ਹੋ ਗਈ';

  @override
  String get figureNameCopied => 'ਨਾਮ ਕਲਿੱਪਬੋਰਡ ’ਤੇ ਕਾਪੀ ਹੋ ਗਿਆ';

  @override
  String get dancingFigure => 'ਨੱਚਦੀ ਫਿਗਰ';

  @override
  String get shareGlb => 'GLB ਸਾਂਝਾ ਕਰੋ (Blender, 3D ਵਿਊਅਰ)';

  @override
  String figureLoadFailed(String error) {
    return 'ਫਿਗਰ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕੀ: $error';
  }

  @override
  String get model3d => '3D ਮਾਡਲ';

  @override
  String get shareStl => 'STL ਸਾਂਝਾ ਕਰੋ (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ਲੋਡ ਨਹੀਂ ਹੋ ਸਕਿਆ: $error';
  }

  @override
  String get videoSavedToPhotos => 'ਵੀਡੀਓ ਫ਼ੋਟੋਜ਼ ਵਿੱਚ ਸੰਭਾਲਿਆ ਗਿਆ';

  @override
  String photosRejectedVideo(String code) {
    return 'ਫ਼ੋਟੋਜ਼ ਨੇ ਵੀਡੀਓ ਸਵੀਕਾਰ ਨਹੀਂ ਕੀਤਾ ($code) — ਸਾਂਝਾ ਕਰਕੇ ਵੇਖੋ';
  }

  @override
  String get share => 'ਸਾਂਝਾ ਕਰੋ';

  @override
  String get video => 'ਵੀਡੀਓ';

  @override
  String get saveToPhotos => 'ਫ਼ੋਟੋਜ਼ ਵਿੱਚ ਸੰਭਾਲੋ';

  @override
  String get hairdresser => 'ਹੇਅਰਡ੍ਰੈਸਰ';

  @override
  String get hairdresserHint =>
      'ਚਿਹਰਾ ਉਹੀ ਰਹੇਗਾ, ਅਤੇ ਜੇ ਤੁਸੀਂ ਨਵਾਂ ਰੰਗ ਨਾ ਚੁਣੋ ਤਾਂ ਵਾਲਾਂ ਦਾ ਰੰਗ ਵੀ। ਸਾਹਮਣੇ ਤੋਂ ਲਏ ਪੋਰਟਰੇਟ ਨਾਲ ਸਭ ਤੋਂ ਵਧੀਆ ਕੰਮ ਕਰਦਾ ਹੈ ਜਿਸ ਵਿੱਚ ਪੂਰੇ ਵਾਲ ਦਿਸਣ ਅਤੇ ਟੋਪੀ ਨਾ ਹੋਵੇ।';

  @override
  String get colourUnchanged => 'ਰੰਗ ਬਦਲਿਆ ਨਹੀਂ';

  @override
  String get colourOnly => 'ਸਿਰਫ਼ ਰੰਗ';

  @override
  String get noHairstylesYet => 'ਹਾਲੇ ਕੋਈ ਹੇਅਰਸਟਾਈਲ ਨਹੀਂ।';

  @override
  String get searchHairstyle => 'ਹੇਅਰਸਟਾਈਲ ਖੋਜੋ';

  @override
  String mapLoadFailed(String error) {
    return 'ਨਕਸ਼ਾ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕਿਆ: $error';
  }

  @override
  String copiedText(String text) {
    return 'ਕਾਪੀ ਹੋ ਗਿਆ: $text';
  }

  @override
  String get styleMaps => 'ਸਟਾਈਲ ਨਕਸ਼ੇ';

  @override
  String get use => 'ਵਰਤੋ';

  @override
  String get copy => 'ਕਾਪੀ ਕਰੋ';

  @override
  String get retry => 'ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ';

  @override
  String get noMapsOnServer => 'ਸਰਵਰ ’ਤੇ ਹਾਲੇ ਕੋਈ ਨਕਸ਼ਾ ਨਹੀਂ।';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ਤਸਵੀਰਾਂ',
      one: '$count ਤਸਵੀਰ',
    );
    return '$_temp0';
  }
}
