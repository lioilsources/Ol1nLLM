// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get newChat => 'नवीन चॅट';

  @override
  String get noConversationsYet => 'अजून कोणतेही संभाषण नाही';

  @override
  String get newConversation => 'नवीन संभाषण';

  @override
  String get newSession => 'नवीन सत्र';

  @override
  String get noSavedSessionsYet => 'अजून कोणतेही जतन केलेले सत्र नाही';

  @override
  String get today => 'आज';

  @override
  String get yesterday => 'काल';

  @override
  String get exportedToFinetune => 'FINETUNE गॅलरीमध्ये निर्यात केले';

  @override
  String get exportToFinetune => 'FINETUNE गॅलरीमध्ये निर्यात करा';

  @override
  String get tooltipImageStudio => 'इमेज स्टुडिओ';

  @override
  String get tooltipMusicStudio => 'म्युझिक स्टुडिओ';

  @override
  String get tooltipVoiceStudio => 'व्हॉइस स्टुडिओ';

  @override
  String get tooltipStoryStudio => 'स्टोरी स्टुडिओ';

  @override
  String branchHint(String label) {
    return 'नवीन संदेश “$label” पासून एक शाखा तयार करेल';
  }

  @override
  String get messageHint => 'लॅबला संदेश लिहा…';

  @override
  String get ocrHint => 'ऐच्छिक सूचना…';

  @override
  String get pickImage => 'प्रतिमा निवडा';

  @override
  String get inputMode => 'मोड';

  @override
  String get askLibrary => 'लायब्ररीला विचारा…';

  @override
  String get askLaw => 'कायद्याबद्दल विचारा…';

  @override
  String get askLeads => 'करारांमधील कंपन्यांबद्दल विचारा…';

  @override
  String get nextMessageRole => 'पुढील संदेशाची भूमिका';

  @override
  String get replyCopied => 'उत्तर क्लिपबोर्डवर कॉपी केले';

  @override
  String searchingSeconds(int seconds) {
    return 'शोधत आहे… $seconds से';
  }

  @override
  String personasLoadFailed(String error) {
    return 'पर्सोना लोड करता आले नाहीत:\n$error';
  }

  @override
  String get pickPersona => 'एक पर्सोना निवडा';

  @override
  String get pickPersonaSub => 'आज तुम्हाला कोणाशी बोलायचे आहे?';

  @override
  String get speakCancel => 'वाचन रद्द करा';

  @override
  String get speakPause => 'थांबवा';

  @override
  String get speakResume => 'पुन्हा सुरू करा';

  @override
  String get speakAloud => 'मोठ्याने वाचा';

  @override
  String speakRhythm(String rhythm) {
    return 'तालात वाचा ($rhythm)';
  }

  @override
  String get sourceOriginal => 'मूळ';

  @override
  String linkOpenFailed(String uri) {
    return 'लिंक उघडता येत नाही: $uri';
  }

  @override
  String get openOriginal => 'मूळ उघडा';

  @override
  String get figureIdCopied => 'फिगरचा आयडी क्लिपबोर्डवर कॉपी केला';

  @override
  String get figureNameCopied => 'नाव क्लिपबोर्डवर कॉपी केले';

  @override
  String get dancingFigure => 'नाचणारी फिगर';

  @override
  String get shareGlb => 'GLB शेअर करा (Blender, 3D व्ह्यूअर)';

  @override
  String figureLoadFailed(String error) {
    return 'फिगर लोड करता आली नाही: $error';
  }

  @override
  String get model3d => '3D मॉडेल';

  @override
  String get shareStl => 'STL शेअर करा (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB लोड करता आले नाही: $error';
  }

  @override
  String get videoSavedToPhotos => 'व्हिडिओ फोटोजमध्ये जतन केला';

  @override
  String photosRejectedVideo(String code) {
    return 'फोटोजने व्हिडिओ स्वीकारला नाही ($code) — शेअर करून पहा';
  }

  @override
  String get share => 'शेअर करा';

  @override
  String get video => 'व्हिडिओ';

  @override
  String get saveToPhotos => 'फोटोजमध्ये जतन करा';

  @override
  String get hairdresser => 'केशकर्तक';

  @override
  String get hairdresserHint =>
      'चेहरा तसाच राहील, आणि तुम्ही नवीन रंग निवडला नाही तर केसांचा रंगही तसाच राहील. पूर्ण केस दिसणाऱ्या, टोपी नसलेल्या समोरून काढलेल्या पोर्ट्रेटसह सर्वोत्तम काम करते.';

  @override
  String get colourUnchanged => 'रंग बदललेला नाही';

  @override
  String get colourOnly => 'फक्त रंग';

  @override
  String get noHairstylesYet => 'अजून कोणतीही केशरचना नाही.';

  @override
  String get searchHairstyle => 'केशरचना शोधा';

  @override
  String mapLoadFailed(String error) {
    return 'नकाशा लोड करता आला नाही: $error';
  }

  @override
  String copiedText(String text) {
    return 'कॉपी केले: $text';
  }

  @override
  String get styleMaps => 'स्टाइल नकाशे';

  @override
  String get use => 'वापरा';

  @override
  String get copy => 'कॉपी करा';

  @override
  String get retry => 'पुन्हा प्रयत्न करा';

  @override
  String get noMapsOnServer => 'सर्व्हरवर अजून कोणताही नकाशा नाही.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count प्रतिमा',
      one: '$count प्रतिमा',
    );
    return '$_temp0';
  }
}
