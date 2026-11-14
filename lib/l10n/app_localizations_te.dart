// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get newChat => 'కొత్త చాట్';

  @override
  String get noConversationsYet => 'ఇంకా సంభాషణలు లేవు';

  @override
  String get newConversation => 'కొత్త సంభాషణ';

  @override
  String get newSession => 'కొత్త సెషన్';

  @override
  String get noSavedSessionsYet => 'ఇంకా సేవ్ చేసిన సెషన్లు లేవు';

  @override
  String get today => 'ఈ రోజు';

  @override
  String get yesterday => 'నిన్న';

  @override
  String get exportedToFinetune => 'FINETUNE గ్యాలరీకి ఎగుమతి చేయబడింది';

  @override
  String get exportToFinetune => 'FINETUNE గ్యాలరీకి ఎగుమతి చేయండి';

  @override
  String get tooltipImageStudio => 'ఇమేజ్ స్టూడియో';

  @override
  String get tooltipMusicStudio => 'మ్యూజిక్ స్టూడియో';

  @override
  String get tooltipVoiceStudio => 'వాయిస్ స్టూడియో';

  @override
  String get tooltipStoryStudio => 'స్టోరీ స్టూడియో';

  @override
  String branchHint(String label) {
    return 'కొత్త సందేశం “$label” నుండి ఒక శాఖను సృష్టిస్తుంది';
  }

  @override
  String get messageHint => 'ల్యాబ్‌కు సందేశం రాయండి…';

  @override
  String get ocrHint => 'ఐచ్ఛిక సూచన…';

  @override
  String get pickImage => 'చిత్రాన్ని ఎంచుకోండి';

  @override
  String get inputMode => 'మోడ్';

  @override
  String get askLibrary => 'లైబ్రరీని అడగండి…';

  @override
  String get askLaw => 'చట్టం గురించి అడగండి…';

  @override
  String get askLeads => 'ఒప్పందాల్లోని కంపెనీల గురించి అడగండి…';

  @override
  String get nextMessageRole => 'తదుపరి సందేశానికి పాత్ర';

  @override
  String get replyCopied => 'సమాధానం క్లిప్‌బోర్డ్‌కు కాపీ చేయబడింది';

  @override
  String searchingSeconds(int seconds) {
    return 'వెతుకుతోంది… $seconds సె';
  }

  @override
  String personasLoadFailed(String error) {
    return 'పర్సోనాలను లోడ్ చేయడం సాధ్యం కాలేదు:\n$error';
  }

  @override
  String get pickPersona => 'ఒక పర్సోనాను ఎంచుకోండి';

  @override
  String get pickPersonaSub => 'ఈ రోజు మీరు ఎవరితో మాట్లాడాలనుకుంటున్నారు?';

  @override
  String get speakCancel => 'చదవడం రద్దు చేయండి';

  @override
  String get speakPause => 'విరామం';

  @override
  String get speakResume => 'కొనసాగించండి';

  @override
  String get speakAloud => 'బిగ్గరగా చదవండి';

  @override
  String speakRhythm(String rhythm) {
    return 'లయలో చదవండి ($rhythm)';
  }

  @override
  String get sourceOriginal => 'మూలం';

  @override
  String linkOpenFailed(String uri) {
    return 'లింక్‌ను తెరవడం సాధ్యం కాలేదు: $uri';
  }

  @override
  String get openOriginal => 'మూలాన్ని తెరవండి';

  @override
  String get figureIdCopied => 'ఫిగర్ ID క్లిప్‌బోర్డ్‌కు కాపీ చేయబడింది';

  @override
  String get figureNameCopied => 'పేరు క్లిప్‌బోర్డ్‌కు కాపీ చేయబడింది';

  @override
  String get dancingFigure => 'నాట్యం చేసే ఫిగర్';

  @override
  String get shareGlb => 'GLB షేర్ చేయండి (Blender, 3D వ్యూయర్లు)';

  @override
  String figureLoadFailed(String error) {
    return 'ఫిగర్‌ను లోడ్ చేయడం సాధ్యం కాలేదు: $error';
  }

  @override
  String get model3d => '3D మోడల్';

  @override
  String get shareStl => 'STL షేర్ చేయండి (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB లోడ్ చేయడం సాధ్యం కాలేదు: $error';
  }

  @override
  String get videoSavedToPhotos => 'వీడియో ఫోటోలలో సేవ్ చేయబడింది';

  @override
  String photosRejectedVideo(String code) {
    return 'ఫోటోలు వీడియోను అంగీకరించలేదు ($code) — షేర్ చేసి చూడండి';
  }

  @override
  String get share => 'షేర్ చేయండి';

  @override
  String get video => 'వీడియో';

  @override
  String get saveToPhotos => 'ఫోటోలలో సేవ్ చేయండి';

  @override
  String get hairdresser => 'హెయిర్‌డ్రెస్సర్';

  @override
  String get hairdresserHint =>
      'ముఖం అలాగే ఉంటుంది, మీరు కొత్త రంగును ఎంచుకోకపోతే జుట్టు రంగు కూడా అలాగే ఉంటుంది. పూర్తి జుట్టు కనిపించే, టోపీ లేని ఎదురుగా తీసిన పోర్ట్రెయిట్‌తో ఉత్తమంగా పనిచేస్తుంది.';

  @override
  String get colourUnchanged => 'రంగు మారలేదు';

  @override
  String get colourOnly => 'రంగు మాత్రమే';

  @override
  String get noHairstylesYet => 'ఇంకా హెయిర్‌స్టైల్‌లు లేవు.';

  @override
  String get searchHairstyle => 'హెయిర్‌స్టైల్ వెతకండి';

  @override
  String mapLoadFailed(String error) {
    return 'మ్యాప్ లోడ్ కాలేదు: $error';
  }

  @override
  String copiedText(String text) {
    return 'కాపీ చేయబడింది: $text';
  }

  @override
  String get styleMaps => 'స్టైల్ మ్యాప్‌లు';

  @override
  String get use => 'ఉపయోగించండి';

  @override
  String get copy => 'కాపీ చేయండి';

  @override
  String get retry => 'మళ్లీ ప్రయత్నించండి';

  @override
  String get noMapsOnServer => 'సర్వర్‌లో ఇంకా మ్యాప్‌లు లేవు.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count చిత్రాలు',
      one: '$count చిత్రం',
    );
    return '$_temp0';
  }
}
