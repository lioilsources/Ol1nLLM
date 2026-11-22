// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Oriya (`or`).
class AppLocalizationsOr extends AppLocalizations {
  AppLocalizationsOr([String locale = 'or']) : super(locale);

  @override
  String get newChat => 'ନୂଆ ଚାଟ୍';

  @override
  String get noConversationsYet => 'ଏପର୍ଯ୍ୟନ୍ତ କୌଣସି କଥାବାର୍ତ୍ତା ନାହିଁ';

  @override
  String get newConversation => 'ନୂଆ କଥାବାର୍ତ୍ତା';

  @override
  String get newSession => 'ନୂଆ ସେସନ୍';

  @override
  String get noSavedSessionsYet => 'ଏପର୍ଯ୍ୟନ୍ତ କୌଣସି ସେଭ୍ ହୋଇଥିବା ସେସନ୍ ନାହିଁ';

  @override
  String get today => 'ଆଜି';

  @override
  String get yesterday => 'ଗତକାଲି';

  @override
  String get exportedToFinetune => 'FINETUNE ଗ୍ୟାଲେରୀକୁ ଏକ୍ସପୋର୍ଟ କରାଗଲା';

  @override
  String get exportToFinetune => 'FINETUNE ଗ୍ୟାଲେରୀକୁ ଏକ୍ସପୋର୍ଟ କରନ୍ତୁ';

  @override
  String get tooltipImageStudio => 'ଇମେଜ୍ ଷ୍ଟୁଡିଓ';

  @override
  String get tooltipMusicStudio => 'ମ୍ୟୁଜିକ୍ ଷ୍ଟୁଡିଓ';

  @override
  String get tooltipVoiceStudio => 'ଭଏସ୍ ଷ୍ଟୁଡିଓ';

  @override
  String get tooltipStoryStudio => 'ଷ୍ଟୋରୀ ଷ୍ଟୁଡିଓ';

  @override
  String branchHint(String label) {
    return 'ନୂଆ ବାର୍ତ୍ତା “$label” ରୁ ଏକ ଶାଖା ତିଆରି କରିବ';
  }

  @override
  String get messageHint => 'ଲ୍ୟାବ୍‌କୁ ବାର୍ତ୍ତା ଲେଖନ୍ତୁ…';

  @override
  String get ocrHint => 'ବୈକଳ୍ପିକ ନିର୍ଦ୍ଦେଶ…';

  @override
  String get pickImage => 'ଛବି ବାଛନ୍ତୁ';

  @override
  String get inputMode => 'ମୋଡ୍';

  @override
  String get askLibrary => 'ଲାଇବ୍ରେରୀକୁ ପଚାରନ୍ତୁ…';

  @override
  String get askLaw => 'ଆଇନ ବିଷୟରେ ପଚାରନ୍ତୁ…';

  @override
  String get askLeads => 'ଚୁକ୍ତିରେ ଥିବା କମ୍ପାନୀ ବିଷୟରେ ପଚାରନ୍ତୁ…';

  @override
  String get nextMessageRole => 'ପରବର୍ତ୍ତୀ ବାର୍ତ୍ତାର ଭୂମିକା';

  @override
  String get replyCopied => 'ଉତ୍ତର କ୍ଲିପ୍‌ବୋର୍ଡକୁ କପି ହେଲା';

  @override
  String searchingSeconds(int seconds) {
    return 'ଖୋଜୁଛି… $seconds ସେ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'ପର୍ସୋନା ଲୋଡ୍ ହୋଇପାରିଲା ନାହିଁ:\n$error';
  }

  @override
  String get pickPersona => 'ଏକ ପର୍ସୋନା ବାଛନ୍ତୁ';

  @override
  String get pickPersonaSub => 'ଆଜି ଆପଣ କାହା ସହ କଥା ହେବାକୁ ଚାହାଁନ୍ତି?';

  @override
  String get speakCancel => 'ପଢ଼ିବା ବାତିଲ୍ କରନ୍ତୁ';

  @override
  String get speakPause => 'ବିରାମ';

  @override
  String get speakResume => 'ଜାରି ରଖନ୍ତୁ';

  @override
  String get speakAloud => 'ଜୋରରେ ପଢ଼ନ୍ତୁ';

  @override
  String speakRhythm(String rhythm) {
    return 'ତାଳରେ ପଢ଼ନ୍ତୁ ($rhythm)';
  }

  @override
  String get sourceOriginal => 'ମୂଳ';

  @override
  String linkOpenFailed(String uri) {
    return 'ଲିଙ୍କ୍ ଖୋଲିହେଉନାହିଁ: $uri';
  }

  @override
  String get openOriginal => 'ମୂଳ ଖୋଲନ୍ତୁ';

  @override
  String get figureIdCopied => 'ଫିଗରର ID କ୍ଲିପ୍‌ବୋର୍ଡକୁ କପି ହେଲା';

  @override
  String get figureNameCopied => 'ନାମ କ୍ଲିପ୍‌ବୋର୍ଡକୁ କପି ହେଲା';

  @override
  String get dancingFigure => 'ନାଚୁଥିବା ଫିଗର';

  @override
  String get shareGlb => 'GLB ସେୟାର୍ କରନ୍ତୁ (Blender, 3D ଭ୍ୟୁଅର୍)';

  @override
  String figureLoadFailed(String error) {
    return 'ଫିଗର ଲୋଡ୍ ହୋଇପାରିଲା ନାହିଁ: $error';
  }

  @override
  String get model3d => '3D ମଡେଲ୍';

  @override
  String get shareStl => 'STL ସେୟାର୍ କରନ୍ତୁ (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB ଲୋଡ୍ ହୋଇପାରିଲା ନାହିଁ: $error';
  }

  @override
  String get videoSavedToPhotos => 'ଭିଡିଓ ଫଟୋରେ ସେଭ୍ ହେଲା';

  @override
  String photosRejectedVideo(String code) {
    return 'ଫଟୋ ଭିଡିଓ ଗ୍ରହଣ କଲା ନାହିଁ ($code) — ସେୟାର୍ କରି ଦେଖନ୍ତୁ';
  }

  @override
  String get share => 'ସେୟାର୍ କରନ୍ତୁ';

  @override
  String get video => 'ଭିଡିଓ';

  @override
  String get saveToPhotos => 'ଫଟୋରେ ସେଭ୍ କରନ୍ତୁ';

  @override
  String get hairdresser => 'କେଶ ସଜ୍ଜାକାର';

  @override
  String get hairdresserHint =>
      'ମୁହଁ ସେମିତି ରହିବ, ଆପଣ ନୂଆ ରଙ୍ଗ ନବାଛିଲେ କେଶର ରଙ୍ଗ ମଧ୍ୟ ସେମିତି ରହିବ। ପୂରା କେଶ ଦେଖାଯାଉଥିବା, ଟୋପି ନଥିବା ସାମନାରୁ ନିଆଯାଇଥିବା ପୋର୍ଟ୍ରେଟ୍ ସହ ସବୁଠାରୁ ଭଲ କାମ କରେ।';

  @override
  String get colourUnchanged => 'ରଙ୍ଗ ବଦଳିନାହିଁ';

  @override
  String get colourOnly => 'କେବଳ ରଙ୍ଗ';

  @override
  String get noHairstylesYet => 'ଏପର୍ଯ୍ୟନ୍ତ କୌଣସି ହେୟାରଷ୍ଟାଇଲ୍ ନାହିଁ।';

  @override
  String get searchHairstyle => 'ହେୟାରଷ୍ଟାଇଲ୍ ଖୋଜନ୍ତୁ';

  @override
  String mapLoadFailed(String error) {
    return 'ମାନଚିତ୍ର ଲୋଡ୍ ହେଲା ନାହିଁ: $error';
  }

  @override
  String copiedText(String text) {
    return 'କପି ହେଲା: $text';
  }

  @override
  String get styleMaps => 'ଷ୍ଟାଇଲ୍ ମାନଚିତ୍ର';

  @override
  String get use => 'ବ୍ୟବହାର କରନ୍ତୁ';

  @override
  String get copy => 'କପି କରନ୍ତୁ';

  @override
  String get retry => 'ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ';

  @override
  String get noMapsOnServer => 'ସର୍ଭରରେ ଏପର୍ଯ୍ୟନ୍ତ କୌଣସି ମାନଚିତ୍ର ନାହିଁ।';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countଟି ଛବି',
      one: '$countଟି ଛବି',
    );
    return '$_temp0';
  }
}
