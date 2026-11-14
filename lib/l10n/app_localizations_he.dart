// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get newChat => 'צ׳אט חדש';

  @override
  String get noConversationsYet => 'עדיין אין שיחות';

  @override
  String get newConversation => 'שיחה חדשה';

  @override
  String get newSession => 'סשן חדש';

  @override
  String get noSavedSessionsYet => 'עדיין אין סשנים שמורים';

  @override
  String get today => 'היום';

  @override
  String get yesterday => 'אתמול';

  @override
  String get exportedToFinetune => 'יוצא לגלריית FINETUNE';

  @override
  String get exportToFinetune => 'ייצוא לגלריית FINETUNE';

  @override
  String get tooltipImageStudio => 'סטודיו תמונות';

  @override
  String get tooltipMusicStudio => 'סטודיו מוזיקה';

  @override
  String get tooltipVoiceStudio => 'סטודיו קול';

  @override
  String get tooltipStoryStudio => 'סטודיו סיפורים';

  @override
  String branchHint(String label) {
    return 'הודעה חדשה תפתח ענף מתוך „$label”';
  }

  @override
  String get messageHint => 'כתוב למעבדה…';

  @override
  String get ocrHint => 'הוראה אופציונלית…';

  @override
  String get pickImage => 'בחירת תמונה';

  @override
  String get inputMode => 'מצב';

  @override
  String get askLibrary => 'שאל את הספרייה…';

  @override
  String get askLaw => 'שאל על החוק…';

  @override
  String get askLeads => 'שאל על חברות מתוך חוזים…';

  @override
  String get nextMessageRole => 'תפקיד להודעה הבאה';

  @override
  String get replyCopied => 'התשובה הועתקה ללוח';

  @override
  String searchingSeconds(int seconds) {
    return 'מחפש… $seconds שנ׳';
  }

  @override
  String personasLoadFailed(String error) {
    return 'לא ניתן לטעון את הדמויות:\n$error';
  }

  @override
  String get pickPersona => 'בחר דמות';

  @override
  String get pickPersonaSub => 'עם מי תרצה לדבר היום?';

  @override
  String get speakCancel => 'ביטול הקראה';

  @override
  String get speakPause => 'השהיה';

  @override
  String get speakResume => 'המשך';

  @override
  String get speakAloud => 'הקראה בקול';

  @override
  String speakRhythm(String rhythm) {
    return 'הקראה בקצב ($rhythm)';
  }

  @override
  String get sourceOriginal => 'מקור';

  @override
  String linkOpenFailed(String uri) {
    return 'לא ניתן לפתוח את הקישור: $uri';
  }

  @override
  String get openOriginal => 'פתיחת המקור';

  @override
  String get figureIdCopied => 'מזהה הדמות הועתק ללוח';

  @override
  String get figureNameCopied => 'השם הועתק ללוח';

  @override
  String get dancingFigure => 'דמות רוקדת';

  @override
  String get shareGlb => 'שיתוף GLB (Blender, מציגי תלת־ממד)';

  @override
  String figureLoadFailed(String error) {
    return 'לא ניתן לטעון את הדמות: $error';
  }

  @override
  String get model3d => 'מודל תלת־ממד';

  @override
  String get shareStl => 'שיתוף STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'לא ניתן לטעון את ה־GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'הסרטון נשמר ב״תמונות״';

  @override
  String photosRejectedVideo(String code) {
    return '״תמונות״ דחתה את הסרטון ($code) — נסה לשתף';
  }

  @override
  String get share => 'שיתוף';

  @override
  String get video => 'סרטון';

  @override
  String get saveToPhotos => 'שמירה ב״תמונות״';

  @override
  String get hairdresser => 'ספר';

  @override
  String get hairdresserHint =>
      'הפנים נשארות כפי שהן, וגם צבע השיער, אלא אם תבחר צבע חדש. הכי מתאים לצילום פורטרט מלפנים שבו השיער נראה במלואו, בלי כובע.';

  @override
  String get colourUnchanged => 'הצבע ללא שינוי';

  @override
  String get colourOnly => 'צבע בלבד';

  @override
  String get noHairstylesYet => 'עדיין אין תסרוקות.';

  @override
  String get searchHairstyle => 'חיפוש תסרוקת';

  @override
  String mapLoadFailed(String error) {
    return 'טעינת המפה נכשלה: $error';
  }

  @override
  String copiedText(String text) {
    return 'הועתק: $text';
  }

  @override
  String get styleMaps => 'מפות סגנונות';

  @override
  String get use => 'שימוש';

  @override
  String get copy => 'העתקה';

  @override
  String get retry => 'ניסיון חוזר';

  @override
  String get noMapsOnServer => 'עדיין אין מפות בשרת.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תמונות',
      two: 'שתי תמונות',
      one: 'תמונה אחת',
    );
    return '$_temp0';
  }
}
