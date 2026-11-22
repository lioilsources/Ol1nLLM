// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppLocalizationsUr extends AppLocalizations {
  AppLocalizationsUr([String locale = 'ur']) : super(locale);

  @override
  String get newChat => 'نئی چیٹ';

  @override
  String get noConversationsYet => 'ابھی کوئی گفتگو نہیں';

  @override
  String get newConversation => 'نئی گفتگو';

  @override
  String get newSession => 'نیا سیشن';

  @override
  String get noSavedSessionsYet => 'ابھی کوئی محفوظ سیشن نہیں';

  @override
  String get today => 'آج';

  @override
  String get yesterday => 'کل';

  @override
  String get exportedToFinetune => 'FINETUNE گیلری میں برآمد کر دیا گیا';

  @override
  String get exportToFinetune => 'FINETUNE گیلری میں برآمد کریں';

  @override
  String get tooltipImageStudio => 'امیج اسٹوڈیو';

  @override
  String get tooltipMusicStudio => 'میوزک اسٹوڈیو';

  @override
  String get tooltipVoiceStudio => 'وائس اسٹوڈیو';

  @override
  String get tooltipStoryStudio => 'اسٹوری اسٹوڈیو';

  @override
  String branchHint(String label) {
    return 'نیا پیغام «$label» سے ایک شاخ بنائے گا';
  }

  @override
  String get messageHint => 'لیب کو پیغام لکھیں…';

  @override
  String get ocrHint => 'اختیاری ہدایت…';

  @override
  String get pickImage => 'تصویر منتخب کریں';

  @override
  String get inputMode => 'موڈ';

  @override
  String get askLibrary => 'لائبریری سے پوچھیں…';

  @override
  String get askLaw => 'قانون کے بارے میں پوچھیں…';

  @override
  String get askLeads => 'معاہدوں میں موجود کمپنیوں کے بارے میں پوچھیں…';

  @override
  String get nextMessageRole => 'اگلے پیغام کا کردار';

  @override
  String get replyCopied => 'جواب کلپ بورڈ پر کاپی ہو گیا';

  @override
  String searchingSeconds(int seconds) {
    return 'تلاش جاری ہے… $seconds سیکنڈ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'کردار لوڈ نہیں ہو سکے:\n$error';
  }

  @override
  String get pickPersona => 'کوئی کردار منتخب کریں';

  @override
  String get pickPersonaSub => 'آج آپ کس سے بات کرنا چاہیں گے؟';

  @override
  String get speakCancel => 'پڑھنا منسوخ کریں';

  @override
  String get speakPause => 'روکیں';

  @override
  String get speakResume => 'جاری رکھیں';

  @override
  String get speakAloud => 'بلند آواز سے پڑھیں';

  @override
  String speakRhythm(String rhythm) {
    return 'ردھم پر پڑھیں ($rhythm)';
  }

  @override
  String get sourceOriginal => 'اصل';

  @override
  String linkOpenFailed(String uri) {
    return 'لنک نہیں کھل سکا: $uri';
  }

  @override
  String get openOriginal => 'اصل کھولیں';

  @override
  String get figureIdCopied => 'فگر کی شناخت کلپ بورڈ پر کاپی ہو گئی';

  @override
  String get figureNameCopied => 'نام کلپ بورڈ پر کاپی ہو گیا';

  @override
  String get dancingFigure => 'رقص کرتی فگر';

  @override
  String get shareGlb => 'GLB شیئر کریں (Blender، تھری ڈی ویورز)';

  @override
  String figureLoadFailed(String error) {
    return 'فگر لوڈ نہیں ہو سکی: $error';
  }

  @override
  String get model3d => 'تھری ڈی ماڈل';

  @override
  String get shareStl => 'STL شیئر کریں (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB لوڈ نہیں ہو سکا: $error';
  }

  @override
  String get videoSavedToPhotos => 'ویڈیو فوٹوز میں محفوظ ہو گئی';

  @override
  String photosRejectedVideo(String code) {
    return 'فوٹوز نے ویڈیو قبول نہیں کی ($code) — شیئر کر کے دیکھیں';
  }

  @override
  String get share => 'شیئر کریں';

  @override
  String get video => 'ویڈیو';

  @override
  String get saveToPhotos => 'فوٹوز میں محفوظ کریں';

  @override
  String get hairdresser => 'ہیئر ڈریسر';

  @override
  String get hairdresserHint =>
      'چہرہ وہی رہے گا، اور بالوں کا رنگ بھی، جب تک آپ نیا رنگ منتخب نہ کریں۔ سامنے سے لی گئی ایسی پورٹریٹ تصویر سب سے بہتر چلتی ہے جس میں پورے بال نظر آئیں اور ٹوپی نہ ہو۔';

  @override
  String get colourUnchanged => 'رنگ میں تبدیلی نہیں';

  @override
  String get colourOnly => 'صرف رنگ';

  @override
  String get noHairstylesYet => 'ابھی کوئی ہیئر اسٹائل نہیں۔';

  @override
  String get searchHairstyle => 'ہیئر اسٹائل تلاش کریں';

  @override
  String mapLoadFailed(String error) {
    return 'نقشہ لوڈ نہیں ہو سکا: $error';
  }

  @override
  String copiedText(String text) {
    return 'کاپی ہو گیا: $text';
  }

  @override
  String get styleMaps => 'اسٹائل میپس';

  @override
  String get use => 'استعمال کریں';

  @override
  String get copy => 'کاپی کریں';

  @override
  String get retry => 'دوبارہ کوشش کریں';

  @override
  String get noMapsOnServer => 'سرور پر ابھی کوئی نقشہ نہیں۔';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تصاویر',
      one: '$count تصویر',
    );
    return '$_temp0';
  }
}
