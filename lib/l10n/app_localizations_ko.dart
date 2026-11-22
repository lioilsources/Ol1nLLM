// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get newChat => '새 채팅';

  @override
  String get noConversationsYet => '아직 대화가 없습니다';

  @override
  String get newConversation => '새 대화';

  @override
  String get newSession => '새 세션';

  @override
  String get noSavedSessionsYet => '저장된 세션이 아직 없습니다';

  @override
  String get today => '오늘';

  @override
  String get yesterday => '어제';

  @override
  String get exportedToFinetune => 'FINETUNE 갤러리로 내보냈습니다';

  @override
  String get exportToFinetune => 'FINETUNE 갤러리로 내보내기';

  @override
  String get tooltipImageStudio => '이미지 스튜디오';

  @override
  String get tooltipMusicStudio => '음악 스튜디오';

  @override
  String get tooltipVoiceStudio => '보이스 스튜디오';

  @override
  String get tooltipStoryStudio => '스토리 스튜디오';

  @override
  String branchHint(String label) {
    return '새 메시지는 “$label”에서 분기를 만듭니다';
  }

  @override
  String get messageHint => '랩에 메시지 보내기…';

  @override
  String get ocrHint => '선택 사항 지시…';

  @override
  String get pickImage => '이미지 선택';

  @override
  String get inputMode => '모드';

  @override
  String get askLibrary => '라이브러리에 물어보세요…';

  @override
  String get askLaw => '법률에 대해 물어보세요…';

  @override
  String get askLeads => '계약서 속 회사에 대해 물어보세요…';

  @override
  String get nextMessageRole => '다음 메시지의 역할';

  @override
  String get replyCopied => '답변을 클립보드에 복사했습니다';

  @override
  String searchingSeconds(int seconds) {
    return '검색 중… $seconds초';
  }

  @override
  String personasLoadFailed(String error) {
    return '페르소나를 불러오지 못했습니다:\n$error';
  }

  @override
  String get pickPersona => '페르소나 선택';

  @override
  String get pickPersonaSub => '오늘은 누구와 이야기할까요?';

  @override
  String get speakCancel => '읽기 취소';

  @override
  String get speakPause => '일시중지';

  @override
  String get speakResume => '계속';

  @override
  String get speakAloud => '소리 내어 읽기';

  @override
  String speakRhythm(String rhythm) {
    return '리듬에 맞춰 읽기($rhythm)';
  }

  @override
  String get sourceOriginal => '원문';

  @override
  String linkOpenFailed(String uri) {
    return '링크를 열 수 없습니다: $uri';
  }

  @override
  String get openOriginal => '원문 열기';

  @override
  String get figureIdCopied => '피규어 ID를 클립보드에 복사했습니다';

  @override
  String get figureNameCopied => '이름을 클립보드에 복사했습니다';

  @override
  String get dancingFigure => '춤추는 피규어';

  @override
  String get shareGlb => 'GLB 공유(Blender, 3D 뷰어)';

  @override
  String figureLoadFailed(String error) {
    return '피규어를 불러오지 못했습니다: $error';
  }

  @override
  String get model3d => '3D 모델';

  @override
  String get shareStl => 'STL 공유(Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB를 불러오지 못했습니다: $error';
  }

  @override
  String get videoSavedToPhotos => '비디오를 사진 앱에 저장했습니다';

  @override
  String photosRejectedVideo(String code) {
    return '사진 앱이 비디오를 받지 않았습니다($code) — 공유를 시도해 보세요';
  }

  @override
  String get share => '공유';

  @override
  String get video => '비디오';

  @override
  String get saveToPhotos => '사진 앱에 저장';

  @override
  String get hairdresser => '헤어 디자이너';

  @override
  String get hairdresserHint =>
      '얼굴은 그대로 유지되며, 새 색을 선택하지 않으면 머리색도 그대로입니다. 머리카락 전체가 보이는 모자 없는 정면 인물 사진이 가장 좋습니다.';

  @override
  String get colourUnchanged => '색상 변경 없음';

  @override
  String get colourOnly => '색상만';

  @override
  String get noHairstylesYet => '아직 헤어스타일이 없습니다.';

  @override
  String get searchHairstyle => '헤어스타일 검색';

  @override
  String mapLoadFailed(String error) {
    return '맵을 불러오지 못했습니다: $error';
  }

  @override
  String copiedText(String text) {
    return '복사됨: $text';
  }

  @override
  String get styleMaps => '스타일 맵';

  @override
  String get use => '사용';

  @override
  String get copy => '복사';

  @override
  String get retry => '다시 시도';

  @override
  String get noMapsOnServer => '서버에 아직 맵이 없습니다.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이미지 $count개',
    );
    return '$_temp0';
  }
}
