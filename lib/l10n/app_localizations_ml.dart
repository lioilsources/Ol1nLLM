// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malayalam (`ml`).
class AppLocalizationsMl extends AppLocalizations {
  AppLocalizationsMl([String locale = 'ml']) : super(locale);

  @override
  String get newChat => 'പുതിയ ചാറ്റ്';

  @override
  String get noConversationsYet => 'ഇതുവരെ സംഭാഷണങ്ങളൊന്നുമില്ല';

  @override
  String get newConversation => 'പുതിയ സംഭാഷണം';

  @override
  String get newSession => 'പുതിയ സെഷൻ';

  @override
  String get noSavedSessionsYet => 'ഇതുവരെ സേവ് ചെയ്ത സെഷനുകളില്ല';

  @override
  String get today => 'ഇന്ന്';

  @override
  String get yesterday => 'ഇന്നലെ';

  @override
  String get exportedToFinetune => 'FINETUNE ഗാലറിയിലേക്ക് എക്സ്പോർട്ട് ചെയ്തു';

  @override
  String get exportToFinetune => 'FINETUNE ഗാലറിയിലേക്ക് എക്സ്പോർട്ട് ചെയ്യുക';

  @override
  String get tooltipImageStudio => 'ഇമേജ് സ്റ്റുഡിയോ';

  @override
  String get tooltipMusicStudio => 'മ്യൂസിക് സ്റ്റുഡിയോ';

  @override
  String get tooltipVoiceStudio => 'വോയ്സ് സ്റ്റുഡിയോ';

  @override
  String get tooltipStoryStudio => 'സ്റ്റോറി സ്റ്റുഡിയോ';

  @override
  String branchHint(String label) {
    return 'പുതിയ സന്ദേശം “$label” ൽ നിന്ന് ഒരു ശാഖ ഉണ്ടാക്കും';
  }

  @override
  String get messageHint => 'ലാബിന് സന്ദേശം എഴുതുക…';

  @override
  String get ocrHint => 'ഓപ്ഷണൽ നിർദ്ദേശം…';

  @override
  String get pickImage => 'ചിത്രം തിരഞ്ഞെടുക്കുക';

  @override
  String get inputMode => 'മോഡ്';

  @override
  String get askLibrary => 'ലൈബ്രറിയോട് ചോദിക്കൂ…';

  @override
  String get askLaw => 'നിയമത്തെക്കുറിച്ച് ചോദിക്കൂ…';

  @override
  String get askLeads => 'കരാറുകളിലെ കമ്പനികളെക്കുറിച്ച് ചോദിക്കൂ…';

  @override
  String get nextMessageRole => 'അടുത്ത സന്ദേശത്തിന്റെ റോൾ';

  @override
  String get replyCopied => 'മറുപടി ക്ലിപ്ബോർഡിലേക്ക് പകർത്തി';

  @override
  String searchingSeconds(int seconds) {
    return 'തിരയുന്നു… $seconds സെ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'പേഴ്സോണകൾ ലോഡ് ചെയ്യാനായില്ല:\n$error';
  }

  @override
  String get pickPersona => 'ഒരു പേഴ്സോണ തിരഞ്ഞെടുക്കുക';

  @override
  String get pickPersonaSub => 'ഇന്ന് ആരോടാണ് സംസാരിക്കേണ്ടത്?';

  @override
  String get speakCancel => 'വായന റദ്ദാക്കുക';

  @override
  String get speakPause => 'താൽക്കാലികമായി നിർത്തുക';

  @override
  String get speakResume => 'തുടരുക';

  @override
  String get speakAloud => 'ഉറക്കെ വായിക്കുക';

  @override
  String speakRhythm(String rhythm) {
    return 'താളത്തിൽ വായിക്കുക ($rhythm)';
  }

  @override
  String get sourceOriginal => 'ഒറിജിനൽ';

  @override
  String linkOpenFailed(String uri) {
    return 'ലിങ്ക് തുറക്കാനാവുന്നില്ല: $uri';
  }

  @override
  String get openOriginal => 'ഒറിജിനൽ തുറക്കുക';

  @override
  String get figureIdCopied => 'ഫിഗർ ഐഡി ക്ലിപ്ബോർഡിലേക്ക് പകർത്തി';

  @override
  String get figureNameCopied => 'പേര് ക്ലിപ്ബോർഡിലേക്ക് പകർത്തി';

  @override
  String get dancingFigure => 'നൃത്തം ചെയ്യുന്ന ഫിഗർ';

  @override
  String get shareGlb => 'GLB പങ്കിടുക (Blender, 3D വ്യൂവറുകൾ)';

  @override
  String figureLoadFailed(String error) {
    return 'ഫിഗർ ലോഡ് ചെയ്യാനായില്ല: $error';
  }

  @override
  String get model3d => '3D മോഡൽ';

  @override
  String get shareStl => 'STL പങ്കിടുക (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ലോഡ് ചെയ്യാനായില്ല: $error';
  }

  @override
  String get videoSavedToPhotos => 'വീഡിയോ ഫോട്ടോസിൽ സേവ് ചെയ്തു';

  @override
  String photosRejectedVideo(String code) {
    return 'ഫോട്ടോസ് വീഡിയോ സ്വീകരിച്ചില്ല ($code) — പങ്കിടാൻ ശ്രമിക്കുക';
  }

  @override
  String get share => 'പങ്കിടുക';

  @override
  String get video => 'വീഡിയോ';

  @override
  String get saveToPhotos => 'ഫോട്ടോസിൽ സേവ് ചെയ്യുക';

  @override
  String get hairdresser => 'ഹെയർഡ്രെസ്സർ';

  @override
  String get hairdresserHint =>
      'മുഖം അതേപടി തുടരും; പുതിയ നിറം തിരഞ്ഞെടുത്തില്ലെങ്കിൽ മുടിയുടെ നിറവും. മുഴുവൻ മുടിയും കാണുന്ന, തൊപ്പിയില്ലാത്ത മുൻവശത്തെ പോർട്രെയ്റ്റാണ് ഏറ്റവും നല്ലത്.';

  @override
  String get colourUnchanged => 'നിറം മാറ്റമില്ല';

  @override
  String get colourOnly => 'നിറം മാത്രം';

  @override
  String get noHairstylesYet => 'ഇതുവരെ ഹെയർസ്റ്റൈലുകളില്ല.';

  @override
  String get searchHairstyle => 'ഹെയർസ്റ്റൈൽ തിരയുക';

  @override
  String mapLoadFailed(String error) {
    return 'മാപ്പ് ലോഡ് ചെയ്യാനായില്ല: $error';
  }

  @override
  String copiedText(String text) {
    return 'പകർത്തി: $text';
  }

  @override
  String get styleMaps => 'സ്റ്റൈൽ മാപ്പുകൾ';

  @override
  String get use => 'ഉപയോഗിക്കുക';

  @override
  String get copy => 'പകർത്തുക';

  @override
  String get retry => 'വീണ്ടും ശ്രമിക്കുക';

  @override
  String get noMapsOnServer => 'സെർവറിൽ ഇതുവരെ മാപ്പുകളൊന്നുമില്ല.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ചിത്രങ്ങൾ',
      one: '$count ചിത്രം',
    );
    return '$_temp0';
  }
}
