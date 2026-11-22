// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get newChat => 'नई चैट';

  @override
  String get noConversationsYet => 'अभी तक कोई बातचीत नहीं';

  @override
  String get newConversation => 'नई बातचीत';

  @override
  String get newSession => 'नया सत्र';

  @override
  String get noSavedSessionsYet => 'अभी तक कोई सहेजा गया सत्र नहीं';

  @override
  String get today => 'आज';

  @override
  String get yesterday => 'कल';

  @override
  String get exportedToFinetune => 'FINETUNE गैलरी में निर्यात किया गया';

  @override
  String get exportToFinetune => 'FINETUNE गैलरी में निर्यात करें';

  @override
  String get tooltipImageStudio => 'इमेज स्टूडियो';

  @override
  String get tooltipMusicStudio => 'म्यूज़िक स्टूडियो';

  @override
  String get tooltipVoiceStudio => 'वॉइस स्टूडियो';

  @override
  String get tooltipStoryStudio => 'स्टोरी स्टूडियो';

  @override
  String branchHint(String label) {
    return 'नया संदेश “$label” से एक शाखा बनाएगा';
  }

  @override
  String get messageHint => 'लैब को संदेश लिखें…';

  @override
  String get ocrHint => 'वैकल्पिक निर्देश…';

  @override
  String get pickImage => 'चित्र चुनें';

  @override
  String get inputMode => 'मोड';

  @override
  String get askLibrary => 'लाइब्रेरी से पूछें…';

  @override
  String get askLaw => 'कानून के बारे में पूछें…';

  @override
  String get askLeads => 'अनुबंधों में दिए गए कंपनियों के बारे में पूछें…';

  @override
  String get nextMessageRole => 'अगले संदेश की भूमिका';

  @override
  String get replyCopied => 'उत्तर क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String searchingSeconds(int seconds) {
    return 'खोज रहा है… $seconds सेकंड';
  }

  @override
  String personasLoadFailed(String error) {
    return 'पर्सोना लोड नहीं हो सके:\n$error';
  }

  @override
  String get pickPersona => 'एक पर्सोना चुनें';

  @override
  String get pickPersonaSub => 'आज आप किससे बात करना चाहेंगे?';

  @override
  String get speakCancel => 'पढ़ना रद्द करें';

  @override
  String get speakPause => 'रोकें';

  @override
  String get speakResume => 'जारी रखें';

  @override
  String get speakAloud => 'ज़ोर से पढ़ें';

  @override
  String speakRhythm(String rhythm) {
    return 'लय में पढ़ें ($rhythm)';
  }

  @override
  String get sourceOriginal => 'मूल';

  @override
  String linkOpenFailed(String uri) {
    return 'लिंक नहीं खुल सका: $uri';
  }

  @override
  String get openOriginal => 'मूल खोलें';

  @override
  String get figureIdCopied => 'फ़िगर की आईडी क्लिपबोर्ड पर कॉपी की गई';

  @override
  String get figureNameCopied => 'नाम क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get dancingFigure => 'नाचती फ़िगर';

  @override
  String get shareGlb => 'GLB साझा करें (Blender, 3D व्यूअर)';

  @override
  String figureLoadFailed(String error) {
    return 'फ़िगर लोड नहीं हो सकी: $error';
  }

  @override
  String get model3d => '3D मॉडल';

  @override
  String get shareStl => 'STL साझा करें (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB लोड नहीं हो सका: $error';
  }

  @override
  String get videoSavedToPhotos => 'वीडियो फ़ोटो में सहेजा गया';

  @override
  String photosRejectedVideo(String code) {
    return 'फ़ोटो ने वीडियो स्वीकार नहीं किया ($code) — साझा करके देखें';
  }

  @override
  String get share => 'साझा करें';

  @override
  String get video => 'वीडियो';

  @override
  String get saveToPhotos => 'फ़ोटो में सहेजें';

  @override
  String get hairdresser => 'हेयरड्रेसर';

  @override
  String get hairdresserHint =>
      'चेहरा वैसा ही रहेगा, और बालों का रंग भी, जब तक आप नया रंग न चुनें। सामने से लिया गया ऐसा पोर्ट्रेट सबसे अच्छा काम करता है जिसमें पूरे बाल दिखें और टोपी न हो।';

  @override
  String get colourUnchanged => 'रंग अपरिवर्तित';

  @override
  String get colourOnly => 'सिर्फ़ रंग';

  @override
  String get noHairstylesYet => 'अभी तक कोई हेयरस्टाइल नहीं।';

  @override
  String get searchHairstyle => 'हेयरस्टाइल खोजें';

  @override
  String mapLoadFailed(String error) {
    return 'मैप लोड नहीं हो सका: $error';
  }

  @override
  String copiedText(String text) {
    return 'कॉपी किया गया: $text';
  }

  @override
  String get styleMaps => 'स्टाइल मैप';

  @override
  String get use => 'उपयोग करें';

  @override
  String get copy => 'कॉपी करें';

  @override
  String get retry => 'फिर कोशिश करें';

  @override
  String get noMapsOnServer => 'सर्वर पर अभी कोई मैप नहीं है।';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count चित्र',
      one: '$count चित्र',
    );
    return '$_temp0';
  }
}
