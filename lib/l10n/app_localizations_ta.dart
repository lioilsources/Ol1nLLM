// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class AppLocalizationsTa extends AppLocalizations {
  AppLocalizationsTa([String locale = 'ta']) : super(locale);

  @override
  String get newChat => 'புதிய அரட்டை';

  @override
  String get noConversationsYet => 'இன்னும் உரையாடல்கள் இல்லை';

  @override
  String get newConversation => 'புதிய உரையாடல்';

  @override
  String get newSession => 'புதிய அமர்வு';

  @override
  String get noSavedSessionsYet => 'இன்னும் சேமித்த அமர்வுகள் இல்லை';

  @override
  String get today => 'இன்று';

  @override
  String get yesterday => 'நேற்று';

  @override
  String get exportedToFinetune => 'FINETUNE கேலரிக்கு ஏற்றுமதி செய்யப்பட்டது';

  @override
  String get exportToFinetune => 'FINETUNE கேலரிக்கு ஏற்றுமதி செய்';

  @override
  String get tooltipImageStudio => 'பட ஸ்டுடியோ';

  @override
  String get tooltipMusicStudio => 'இசை ஸ்டுடியோ';

  @override
  String get tooltipVoiceStudio => 'குரல் ஸ்டுடியோ';

  @override
  String get tooltipStoryStudio => 'கதை ஸ்டுடியோ';

  @override
  String branchHint(String label) {
    return 'புதிய செய்தி “$label” இலிருந்து ஒரு கிளையை உருவாக்கும்';
  }

  @override
  String get messageHint => 'ஆய்வகத்துக்கு செய்தி எழுதுங்கள்…';

  @override
  String get ocrHint => 'விருப்பமான அறிவுறுத்தல்…';

  @override
  String get pickImage => 'படத்தைத் தேர்ந்தெடுக்கவும்';

  @override
  String get inputMode => 'பயன்முறை';

  @override
  String get askLibrary => 'நூலகத்திடம் கேளுங்கள்…';

  @override
  String get askLaw => 'சட்டம் பற்றிக் கேளுங்கள்…';

  @override
  String get askLeads => 'ஒப்பந்தங்களில் உள்ள நிறுவனங்கள் பற்றிக் கேளுங்கள்…';

  @override
  String get nextMessageRole => 'அடுத்த செய்திக்கான பாத்திரம்';

  @override
  String get replyCopied => 'பதில் கிளிப்போர்டுக்கு நகலெடுக்கப்பட்டது';

  @override
  String searchingSeconds(int seconds) {
    return 'தேடுகிறது… $seconds வி';
  }

  @override
  String personasLoadFailed(String error) {
    return 'பாத்திரங்களை ஏற்ற முடியவில்லை:\n$error';
  }

  @override
  String get pickPersona => 'ஒரு பாத்திரத்தைத் தேர்ந்தெடுங்கள்';

  @override
  String get pickPersonaSub => 'இன்று யாருடன் பேச விரும்புகிறீர்கள்?';

  @override
  String get speakCancel => 'வாசிப்பை ரத்துசெய்';

  @override
  String get speakPause => 'இடைநிறுத்து';

  @override
  String get speakResume => 'தொடர்';

  @override
  String get speakAloud => 'உரக்க வாசி';

  @override
  String speakRhythm(String rhythm) {
    return 'தாளத்துடன் வாசி ($rhythm)';
  }

  @override
  String get sourceOriginal => 'மூலம்';

  @override
  String linkOpenFailed(String uri) {
    return 'இணைப்பைத் திறக்க முடியவில்லை: $uri';
  }

  @override
  String get openOriginal => 'மூலத்தைத் திற';

  @override
  String get figureIdCopied => 'உருவ ஐடி கிளிப்போர்டுக்கு நகலெடுக்கப்பட்டது';

  @override
  String get figureNameCopied => 'பெயர் கிளிப்போர்டுக்கு நகலெடுக்கப்பட்டது';

  @override
  String get dancingFigure => 'நடனமாடும் உருவம்';

  @override
  String get shareGlb => 'GLB பகிர் (Blender, 3D பார்வையாளர்கள்)';

  @override
  String figureLoadFailed(String error) {
    return 'உருவத்தை ஏற்ற முடியவில்லை: $error';
  }

  @override
  String get model3d => '3D மாடல்';

  @override
  String get shareStl => 'STL பகிர் (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ஐ ஏற்ற முடியவில்லை: $error';
  }

  @override
  String get videoSavedToPhotos => 'வீடியோ புகைப்படங்களில் சேமிக்கப்பட்டது';

  @override
  String photosRejectedVideo(String code) {
    return 'புகைப்படங்கள் வீடியோவை ஏற்கவில்லை ($code) — பகிர்ந்து பாருங்கள்';
  }

  @override
  String get share => 'பகிர்';

  @override
  String get video => 'வீடியோ';

  @override
  String get saveToPhotos => 'புகைப்படங்களில் சேமி';

  @override
  String get hairdresser => 'சிகையலங்கார நிபுணர்';

  @override
  String get hairdresserHint =>
      'முகம் அப்படியே இருக்கும்; புதிய நிறத்தைத் தேர்ந்தெடுக்காவிட்டால் முடியின் நிறமும் அப்படியே இருக்கும். முழு முடியும் தெரியும், தொப்பி இல்லாத முன்புற உருவப்படத்துடன் சிறப்பாகச் செயல்படும்.';

  @override
  String get colourUnchanged => 'நிறம் மாறவில்லை';

  @override
  String get colourOnly => 'நிறம் மட்டும்';

  @override
  String get noHairstylesYet => 'இன்னும் சிகை அலங்காரங்கள் இல்லை.';

  @override
  String get searchHairstyle => 'சிகை அலங்காரத்தைத் தேடு';

  @override
  String mapLoadFailed(String error) {
    return 'வரைபடத்தை ஏற்ற முடியவில்லை: $error';
  }

  @override
  String copiedText(String text) {
    return 'நகலெடுக்கப்பட்டது: $text';
  }

  @override
  String get styleMaps => 'பாணி வரைபடங்கள்';

  @override
  String get use => 'பயன்படுத்து';

  @override
  String get copy => 'நகலெடு';

  @override
  String get retry => 'மீண்டும் முயல்';

  @override
  String get noMapsOnServer => 'சேவையகத்தில் இன்னும் வரைபடங்கள் இல்லை.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count படங்கள்',
      one: '$count படம்',
    );
    return '$_temp0';
  }
}
