// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get newChat => 'নতুন চ্যাট';

  @override
  String get noConversationsYet => 'এখনও কোনো কথোপকথন নেই';

  @override
  String get newConversation => 'নতুন কথোপকথন';

  @override
  String get newSession => 'নতুন সেশন';

  @override
  String get noSavedSessionsYet => 'এখনও কোনো সংরক্ষিত সেশন নেই';

  @override
  String get today => 'আজ';

  @override
  String get yesterday => 'গতকাল';

  @override
  String get exportedToFinetune => 'FINETUNE গ্যালারিতে এক্সপোর্ট করা হয়েছে';

  @override
  String get exportToFinetune => 'FINETUNE গ্যালারিতে এক্সপোর্ট করুন';

  @override
  String get tooltipImageStudio => 'ইমেজ স্টুডিও';

  @override
  String get tooltipMusicStudio => 'মিউজিক স্টুডিও';

  @override
  String get tooltipVoiceStudio => 'ভয়েস স্টুডিও';

  @override
  String get tooltipStoryStudio => 'স্টোরি স্টুডিও';

  @override
  String branchHint(String label) {
    return 'নতুন বার্তা “$label” থেকে একটি শাখা তৈরি করবে';
  }

  @override
  String get messageHint => 'ল্যাবকে বার্তা লিখুন…';

  @override
  String get ocrHint => 'ঐচ্ছিক নির্দেশ…';

  @override
  String get pickImage => 'ছবি বেছে নিন';

  @override
  String get inputMode => 'মোড';

  @override
  String get askLibrary => 'লাইব্রেরিকে জিজ্ঞেস করুন…';

  @override
  String get askLaw => 'আইন সম্পর্কে জিজ্ঞেস করুন…';

  @override
  String get askLeads => 'চুক্তির কোম্পানিগুলো সম্পর্কে জিজ্ঞেস করুন…';

  @override
  String get nextMessageRole => 'পরের বার্তার ভূমিকা';

  @override
  String get replyCopied => 'উত্তর ক্লিপবোর্ডে কপি হয়েছে';

  @override
  String searchingSeconds(int seconds) {
    return 'খুঁজছে… $seconds সেকেন্ড';
  }

  @override
  String personasLoadFailed(String error) {
    return 'পারসোনা লোড করা যায়নি:\n$error';
  }

  @override
  String get pickPersona => 'একটি পারসোনা বেছে নিন';

  @override
  String get pickPersonaSub => 'আজ কার সঙ্গে কথা বলতে চান?';

  @override
  String get speakCancel => 'পড়া বাতিল করুন';

  @override
  String get speakPause => 'বিরতি';

  @override
  String get speakResume => 'চালিয়ে যান';

  @override
  String get speakAloud => 'জোরে পড়ুন';

  @override
  String speakRhythm(String rhythm) {
    return 'ছন্দে পড়ুন ($rhythm)';
  }

  @override
  String get sourceOriginal => 'মূল';

  @override
  String linkOpenFailed(String uri) {
    return 'লিংক খোলা যাচ্ছে না: $uri';
  }

  @override
  String get openOriginal => 'মূল খুলুন';

  @override
  String get figureIdCopied => 'ফিগারের আইডি ক্লিপবোর্ডে কপি হয়েছে';

  @override
  String get figureNameCopied => 'নাম ক্লিপবোর্ডে কপি হয়েছে';

  @override
  String get dancingFigure => 'নাচের ফিগার';

  @override
  String get shareGlb => 'GLB শেয়ার করুন (Blender, 3D ভিউয়ার)';

  @override
  String figureLoadFailed(String error) {
    return 'ফিগার লোড করা যায়নি: $error';
  }

  @override
  String get model3d => '3D মডেল';

  @override
  String get shareStl => 'STL শেয়ার করুন (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB লোড করা যায়নি: $error';
  }

  @override
  String get videoSavedToPhotos => 'ভিডিও ছবিতে সংরক্ষিত হয়েছে';

  @override
  String photosRejectedVideo(String code) {
    return 'ছবি অ্যাপ ভিডিওটি নেয়নি ($code) — শেয়ার করে দেখুন';
  }

  @override
  String get share => 'শেয়ার করুন';

  @override
  String get video => 'ভিডিও';

  @override
  String get saveToPhotos => 'ছবিতে সংরক্ষণ করুন';

  @override
  String get hairdresser => 'হেয়ারড্রেসার';

  @override
  String get hairdresserHint =>
      'মুখ একই থাকবে, চুলের রঙও থাকবে যদি না আপনি নতুন রং বেছে নেন। সামনে থেকে তোলা এমন পোর্ট্রেটে সবচেয়ে ভালো কাজ করে যেখানে পুরো চুল দেখা যায় এবং টুপি নেই।';

  @override
  String get colourUnchanged => 'রং অপরিবর্তিত';

  @override
  String get colourOnly => 'শুধু রং';

  @override
  String get noHairstylesYet => 'এখনও কোনো হেয়ারস্টাইল নেই।';

  @override
  String get searchHairstyle => 'হেয়ারস্টাইল খুঁজুন';

  @override
  String mapLoadFailed(String error) {
    return 'মানচিত্র লোড করা যায়নি: $error';
  }

  @override
  String copiedText(String text) {
    return 'কপি হয়েছে: $text';
  }

  @override
  String get styleMaps => 'স্টাইল ম্যাপ';

  @override
  String get use => 'ব্যবহার করুন';

  @override
  String get copy => 'কপি করুন';

  @override
  String get retry => 'আবার চেষ্টা করুন';

  @override
  String get noMapsOnServer => 'সার্ভারে এখনও কোনো মানচিত্র নেই।';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countটি ছবি',
      one: '$countটি ছবি',
    );
    return '$_temp0';
  }
}
