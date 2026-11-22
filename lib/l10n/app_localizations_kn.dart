// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class AppLocalizationsKn extends AppLocalizations {
  AppLocalizationsKn([String locale = 'kn']) : super(locale);

  @override
  String get newChat => 'ಹೊಸ ಚಾಟ್';

  @override
  String get noConversationsYet => 'ಇನ್ನೂ ಯಾವುದೇ ಸಂಭಾಷಣೆಗಳಿಲ್ಲ';

  @override
  String get newConversation => 'ಹೊಸ ಸಂಭಾಷಣೆ';

  @override
  String get newSession => 'ಹೊಸ ಸೆಷನ್';

  @override
  String get noSavedSessionsYet => 'ಇನ್ನೂ ಉಳಿಸಿದ ಸೆಷನ್‌ಗಳಿಲ್ಲ';

  @override
  String get today => 'ಇಂದು';

  @override
  String get yesterday => 'ನಿನ್ನೆ';

  @override
  String get exportedToFinetune => 'FINETUNE ಗ್ಯಾಲರಿಗೆ ರಫ್ತು ಮಾಡಲಾಗಿದೆ';

  @override
  String get exportToFinetune => 'FINETUNE ಗ್ಯಾಲರಿಗೆ ರಫ್ತು ಮಾಡಿ';

  @override
  String get tooltipImageStudio => 'ಇಮೇಜ್ ಸ್ಟುಡಿಯೋ';

  @override
  String get tooltipMusicStudio => 'ಮ್ಯೂಸಿಕ್ ಸ್ಟುಡಿಯೋ';

  @override
  String get tooltipVoiceStudio => 'ವಾಯ್ಸ್ ಸ್ಟುಡಿಯೋ';

  @override
  String get tooltipStoryStudio => 'ಸ್ಟೋರಿ ಸ್ಟುಡಿಯೋ';

  @override
  String branchHint(String label) {
    return 'ಹೊಸ ಸಂದೇಶವು “$label” ನಿಂದ ಒಂದು ಶಾಖೆಯನ್ನು ರಚಿಸುತ್ತದೆ';
  }

  @override
  String get messageHint => 'ಲ್ಯಾಬ್‌ಗೆ ಸಂದೇಶ ಬರೆಯಿರಿ…';

  @override
  String get ocrHint => 'ಐಚ್ಛಿಕ ಸೂಚನೆ…';

  @override
  String get pickImage => 'ಚಿತ್ರ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get inputMode => 'ಮೋಡ್';

  @override
  String get askLibrary => 'ಲೈಬ್ರರಿಯನ್ನು ಕೇಳಿ…';

  @override
  String get askLaw => 'ಕಾನೂನಿನ ಬಗ್ಗೆ ಕೇಳಿ…';

  @override
  String get askLeads => 'ಒಪ್ಪಂದಗಳಲ್ಲಿನ ಕಂಪನಿಗಳ ಬಗ್ಗೆ ಕೇಳಿ…';

  @override
  String get nextMessageRole => 'ಮುಂದಿನ ಸಂದೇಶದ ಪಾತ್ರ';

  @override
  String get replyCopied => 'ಉತ್ತರವನ್ನು ಕ್ಲಿಪ್‌ಬೋರ್ಡ್‌ಗೆ ನಕಲಿಸಲಾಗಿದೆ';

  @override
  String searchingSeconds(int seconds) {
    return 'ಹುಡುಕುತ್ತಿದೆ… $seconds ಸೆ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'ಪರ್ಸೋನಾಗಳನ್ನು ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ:\n$error';
  }

  @override
  String get pickPersona => 'ಒಂದು ಪರ್ಸೋನಾ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get pickPersonaSub => 'ಇಂದು ನೀವು ಯಾರೊಂದಿಗೆ ಮಾತನಾಡಲು ಬಯಸುತ್ತೀರಿ?';

  @override
  String get speakCancel => 'ಓದುವುದನ್ನು ರದ್ದುಮಾಡಿ';

  @override
  String get speakPause => 'ವಿರಾಮ';

  @override
  String get speakResume => 'ಮುಂದುವರಿಸಿ';

  @override
  String get speakAloud => 'ಗಟ್ಟಿಯಾಗಿ ಓದಿ';

  @override
  String speakRhythm(String rhythm) {
    return 'ಲಯದಲ್ಲಿ ಓದಿ ($rhythm)';
  }

  @override
  String get sourceOriginal => 'ಮೂಲ';

  @override
  String linkOpenFailed(String uri) {
    return 'ಲಿಂಕ್ ತೆರೆಯಲಾಗುತ್ತಿಲ್ಲ: $uri';
  }

  @override
  String get openOriginal => 'ಮೂಲವನ್ನು ತೆರೆಯಿರಿ';

  @override
  String get figureIdCopied => 'ಫಿಗರ್ ID ಅನ್ನು ಕ್ಲಿಪ್‌ಬೋರ್ಡ್‌ಗೆ ನಕಲಿಸಲಾಗಿದೆ';

  @override
  String get figureNameCopied => 'ಹೆಸರನ್ನು ಕ್ಲಿಪ್‌ಬೋರ್ಡ್‌ಗೆ ನಕಲಿಸಲಾಗಿದೆ';

  @override
  String get dancingFigure => 'ನೃತ್ಯ ಮಾಡುವ ಫಿಗರ್';

  @override
  String get shareGlb => 'GLB ಹಂಚಿಕೊಳ್ಳಿ (Blender, 3D ವೀಕ್ಷಕಗಳು)';

  @override
  String figureLoadFailed(String error) {
    return 'ಫಿಗರ್ ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ: $error';
  }

  @override
  String get model3d => '3D ಮಾದರಿ';

  @override
  String get shareStl => 'STL ಹಂಚಿಕೊಳ್ಳಿ (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ಲೋಡ್ ಮಾಡಲಾಗಲಿಲ್ಲ: $error';
  }

  @override
  String get videoSavedToPhotos => 'ವೀಡಿಯೊವನ್ನು ಫೋಟೋಗಳಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ';

  @override
  String photosRejectedVideo(String code) {
    return 'ಫೋಟೋಗಳು ವೀಡಿಯೊವನ್ನು ಸ್ವೀಕರಿಸಲಿಲ್ಲ ($code) — ಹಂಚಿಕೊಳ್ಳಲು ಪ್ರಯತ್ನಿಸಿ';
  }

  @override
  String get share => 'ಹಂಚಿಕೊಳ್ಳಿ';

  @override
  String get video => 'ವೀಡಿಯೊ';

  @override
  String get saveToPhotos => 'ಫೋಟೋಗಳಲ್ಲಿ ಉಳಿಸಿ';

  @override
  String get hairdresser => 'ಕೇಶ ವಿನ್ಯಾಸಕ';

  @override
  String get hairdresserHint =>
      'ಮುಖ ಹಾಗೆಯೇ ಇರುತ್ತದೆ, ನೀವು ಹೊಸ ಬಣ್ಣ ಆಯ್ಕೆ ಮಾಡದಿದ್ದರೆ ಕೂದಲಿನ ಬಣ್ಣವೂ ಹಾಗೆಯೇ ಇರುತ್ತದೆ. ಪೂರ್ಣ ಕೂದಲು ಕಾಣುವ, ಟೋಪಿ ಇಲ್ಲದ ಮುಂಭಾಗದ ಭಾವಚಿತ್ರದೊಂದಿಗೆ ಉತ್ತಮವಾಗಿ ಕೆಲಸ ಮಾಡುತ್ತದೆ.';

  @override
  String get colourUnchanged => 'ಬಣ್ಣ ಬದಲಾಗಿಲ್ಲ';

  @override
  String get colourOnly => 'ಬಣ್ಣ ಮಾತ್ರ';

  @override
  String get noHairstylesYet => 'ಇನ್ನೂ ಹೇರ್‌ಸ್ಟೈಲ್‌ಗಳಿಲ್ಲ.';

  @override
  String get searchHairstyle => 'ಹೇರ್‌ಸ್ಟೈಲ್ ಹುಡುಕಿ';

  @override
  String mapLoadFailed(String error) {
    return 'ನಕ್ಷೆ ಲೋಡ್ ಆಗಲಿಲ್ಲ: $error';
  }

  @override
  String copiedText(String text) {
    return 'ನಕಲಿಸಲಾಗಿದೆ: $text';
  }

  @override
  String get styleMaps => 'ಸ್ಟೈಲ್ ನಕ್ಷೆಗಳು';

  @override
  String get use => 'ಬಳಸಿ';

  @override
  String get copy => 'ನಕಲಿಸಿ';

  @override
  String get retry => 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String get noMapsOnServer => 'ಸರ್ವರ್‌ನಲ್ಲಿ ಇನ್ನೂ ಯಾವುದೇ ನಕ್ಷೆ ಇಲ್ಲ.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ಚಿತ್ರಗಳು',
      one: '$count ಚಿತ್ರ',
    );
    return '$_temp0';
  }
}
