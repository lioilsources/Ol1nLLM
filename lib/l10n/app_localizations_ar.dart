// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get newChat => 'دردشة جديدة';

  @override
  String get noConversationsYet => 'لا توجد محادثات بعد';

  @override
  String get newConversation => 'محادثة جديدة';

  @override
  String get newSession => 'جلسة جديدة';

  @override
  String get noSavedSessionsYet => 'لا توجد جلسات محفوظة بعد';

  @override
  String get today => 'اليوم';

  @override
  String get yesterday => 'أمس';

  @override
  String get exportedToFinetune => 'تم التصدير إلى معرض FINETUNE';

  @override
  String get exportToFinetune => 'التصدير إلى معرض FINETUNE';

  @override
  String get tooltipImageStudio => 'استوديو الصور';

  @override
  String get tooltipMusicStudio => 'استوديو الموسيقى';

  @override
  String get tooltipVoiceStudio => 'استوديو الصوت';

  @override
  String get tooltipStoryStudio => 'استوديو القصص';

  @override
  String branchHint(String label) {
    return 'ستنشئ الرسالة الجديدة فرعًا من «$label»';
  }

  @override
  String get messageHint => 'اكتب إلى المختبر…';

  @override
  String get ocrHint => 'تعليمات اختيارية…';

  @override
  String get pickImage => 'اختيار صورة';

  @override
  String get inputMode => 'الوضع';

  @override
  String get askLibrary => 'اسأل المكتبة…';

  @override
  String get askLaw => 'اسأل عن القانون…';

  @override
  String get askLeads => 'اسأل عن الشركات في العقود…';

  @override
  String get nextMessageRole => 'الدور للرسالة التالية';

  @override
  String get replyCopied => 'تم نسخ الرد إلى الحافظة';

  @override
  String searchingSeconds(int seconds) {
    return 'جارٍ البحث… $seconds ث';
  }

  @override
  String personasLoadFailed(String error) {
    return 'تعذّر تحميل الشخصيات:\n$error';
  }

  @override
  String get pickPersona => 'اختر شخصية';

  @override
  String get pickPersonaSub => 'مع من تريد أن تتحدث اليوم؟';

  @override
  String get speakCancel => 'إلغاء القراءة';

  @override
  String get speakPause => 'إيقاف مؤقت';

  @override
  String get speakResume => 'متابعة';

  @override
  String get speakAloud => 'قراءة بصوت عالٍ';

  @override
  String speakRhythm(String rhythm) {
    return 'قراءة على الإيقاع ($rhythm)';
  }

  @override
  String get sourceOriginal => 'الأصل';

  @override
  String linkOpenFailed(String uri) {
    return 'تعذّر فتح الرابط: $uri';
  }

  @override
  String get openOriginal => 'فتح الأصل';

  @override
  String get figureIdCopied => 'تم نسخ معرّف المجسّم إلى الحافظة';

  @override
  String get figureNameCopied => 'تم نسخ الاسم إلى الحافظة';

  @override
  String get dancingFigure => 'مجسّم راقص';

  @override
  String get shareGlb => 'مشاركة GLB (Blender وعارضات ثلاثية الأبعاد)';

  @override
  String figureLoadFailed(String error) {
    return 'تعذّر تحميل المجسّم: $error';
  }

  @override
  String get model3d => 'نموذج ثلاثي الأبعاد';

  @override
  String get shareStl => 'مشاركة STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'تعذّر تحميل GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'تم حفظ الفيديو في «الصور»';

  @override
  String photosRejectedVideo(String code) {
    return 'رفض تطبيق «الصور» الفيديو ($code) — جرّب «مشاركة»';
  }

  @override
  String get share => 'مشاركة';

  @override
  String get video => 'فيديو';

  @override
  String get saveToPhotos => 'حفظ في «الصور»';

  @override
  String get hairdresser => 'مصفّف الشعر';

  @override
  String get hairdresserHint =>
      'يبقى الوجه كما هو، ويبقى لون الشعر أيضًا ما لم تختر لونًا جديدًا. يعمل بشكل أفضل مع صورة شخصية أمامية يظهر فيها الشعر كاملًا دون قبعة.';

  @override
  String get colourUnchanged => 'اللون دون تغيير';

  @override
  String get colourOnly => 'اللون فقط';

  @override
  String get noHairstylesYet => 'لا توجد تسريحات بعد.';

  @override
  String get searchHairstyle => 'بحث عن تسريحة';

  @override
  String mapLoadFailed(String error) {
    return 'تعذّر تحميل الخريطة: $error';
  }

  @override
  String copiedText(String text) {
    return 'تم النسخ: $text';
  }

  @override
  String get styleMaps => 'خرائط الأنماط';

  @override
  String get use => 'استخدام';

  @override
  String get copy => 'نسخ';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get noMapsOnServer => 'لا توجد خرائط على الخادم بعد.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صورة',
      many: '$count صورة',
      few: '$count صور',
      two: 'صورتان',
      one: 'صورة واحدة',
      zero: 'لا صور',
    );
    return '$_temp0';
  }
}
