// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get newChat => '新聊天';

  @override
  String get noConversationsYet => '还没有对话';

  @override
  String get newConversation => '新对话';

  @override
  String get newSession => '新会话';

  @override
  String get noSavedSessionsYet => '还没有已保存的会话';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get exportedToFinetune => '已导出到 FINETUNE 图库';

  @override
  String get exportToFinetune => '导出到 FINETUNE 图库';

  @override
  String get tooltipImageStudio => '图像工作室';

  @override
  String get tooltipMusicStudio => '音乐工作室';

  @override
  String get tooltipVoiceStudio => '语音工作室';

  @override
  String get tooltipStoryStudio => '故事工作室';

  @override
  String branchHint(String label) {
    return '新消息将从“$label”创建一个分支';
  }

  @override
  String get messageHint => '给实验室发消息…';

  @override
  String get ocrHint => '可选指令…';

  @override
  String get pickImage => '选择图片';

  @override
  String get inputMode => '模式';

  @override
  String get askLibrary => '向资料库提问…';

  @override
  String get askLaw => '询问法律问题…';

  @override
  String get askLeads => '询问合同中的公司…';

  @override
  String get nextMessageRole => '下一条消息的角色';

  @override
  String get replyCopied => '回复已复制到剪贴板';

  @override
  String searchingSeconds(int seconds) {
    return '搜索中… $seconds 秒';
  }

  @override
  String personasLoadFailed(String error) {
    return '无法加载角色：\n$error';
  }

  @override
  String get pickPersona => '选择角色';

  @override
  String get pickPersonaSub => '今天想和谁聊天？';

  @override
  String get speakCancel => '取消朗读';

  @override
  String get speakPause => '暂停';

  @override
  String get speakResume => '继续';

  @override
  String get speakAloud => '朗读';

  @override
  String speakRhythm(String rhythm) {
    return '按节奏朗读（$rhythm）';
  }

  @override
  String get sourceOriginal => '原文';

  @override
  String linkOpenFailed(String uri) {
    return '无法打开链接：$uri';
  }

  @override
  String get openOriginal => '打开原文';

  @override
  String get figureIdCopied => '手办 ID 已复制到剪贴板';

  @override
  String get figureNameCopied => '名称已复制到剪贴板';

  @override
  String get dancingFigure => '跳舞的手办';

  @override
  String get shareGlb => '分享 GLB（Blender、3D 查看器）';

  @override
  String figureLoadFailed(String error) {
    return '无法加载手办：$error';
  }

  @override
  String get model3d => '3D 模型';

  @override
  String get shareStl => '分享 STL（Prusa Slicer）';

  @override
  String glbLoadFailed(String error) {
    return '无法加载 GLB：$error';
  }

  @override
  String get videoSavedToPhotos => '视频已存入“照片”';

  @override
  String photosRejectedVideo(String code) {
    return '“照片”拒绝了该视频（$code）——请尝试分享';
  }

  @override
  String get share => '分享';

  @override
  String get video => '视频';

  @override
  String get saveToPhotos => '存入“照片”';

  @override
  String get hairdresser => '发型师';

  @override
  String get hairdresserHint => '脸部保持不变；除非你选择新颜色，否则发色也不变。最适合露出完整头发、不戴帽子的正面人像。';

  @override
  String get colourUnchanged => '颜色不变';

  @override
  String get colourOnly => '仅颜色';

  @override
  String get noHairstylesYet => '还没有发型。';

  @override
  String get searchHairstyle => '搜索发型';

  @override
  String mapLoadFailed(String error) {
    return '地图加载失败：$error';
  }

  @override
  String copiedText(String text) {
    return '已复制：$text';
  }

  @override
  String get styleMaps => '风格地图';

  @override
  String get use => '使用';

  @override
  String get copy => '复制';

  @override
  String get retry => '重试';

  @override
  String get noMapsOnServer => '服务器上还没有地图。';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张图片',
    );
    return '$_temp0';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get newChat => '新聊天';

  @override
  String get noConversationsYet => '尚無對話';

  @override
  String get newConversation => '新對話';

  @override
  String get newSession => '新工作階段';

  @override
  String get noSavedSessionsYet => '尚無已儲存的工作階段';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get exportedToFinetune => '已匯出至 FINETUNE 圖庫';

  @override
  String get exportToFinetune => '匯出至 FINETUNE 圖庫';

  @override
  String get tooltipImageStudio => '影像工作室';

  @override
  String get tooltipMusicStudio => '音樂工作室';

  @override
  String get tooltipVoiceStudio => '語音工作室';

  @override
  String get tooltipStoryStudio => '故事工作室';

  @override
  String branchHint(String label) {
    return '新訊息將從「$label」建立一個分支';
  }

  @override
  String get messageHint => '傳訊息給實驗室…';

  @override
  String get ocrHint => '選填指令…';

  @override
  String get pickImage => '選擇圖片';

  @override
  String get inputMode => '模式';

  @override
  String get askLibrary => '向資料庫提問…';

  @override
  String get askLaw => '詢問法律問題…';

  @override
  String get askLeads => '詢問合約中的公司…';

  @override
  String get nextMessageRole => '下一則訊息的角色';

  @override
  String get replyCopied => '回覆已拷貝到剪貼簿';

  @override
  String searchingSeconds(int seconds) {
    return '搜尋中… $seconds 秒';
  }

  @override
  String personasLoadFailed(String error) {
    return '無法載入角色：\n$error';
  }

  @override
  String get pickPersona => '選擇角色';

  @override
  String get pickPersonaSub => '今天想和誰聊天？';

  @override
  String get speakCancel => '取消朗讀';

  @override
  String get speakPause => '暫停';

  @override
  String get speakResume => '繼續';

  @override
  String get speakAloud => '朗讀';

  @override
  String speakRhythm(String rhythm) {
    return '依節奏朗讀（$rhythm）';
  }

  @override
  String get sourceOriginal => '原文';

  @override
  String linkOpenFailed(String uri) {
    return '無法開啟連結：$uri';
  }

  @override
  String get openOriginal => '開啟原文';

  @override
  String get figureIdCopied => '公仔 ID 已拷貝到剪貼簿';

  @override
  String get figureNameCopied => '名稱已拷貝到剪貼簿';

  @override
  String get dancingFigure => '跳舞的公仔';

  @override
  String get shareGlb => '分享 GLB（Blender、3D 檢視器）';

  @override
  String figureLoadFailed(String error) {
    return '無法載入公仔：$error';
  }

  @override
  String get model3d => '3D 模型';

  @override
  String get shareStl => '分享 STL（Prusa Slicer）';

  @override
  String glbLoadFailed(String error) {
    return '無法載入 GLB：$error';
  }

  @override
  String get videoSavedToPhotos => '影片已儲存至「照片」';

  @override
  String photosRejectedVideo(String code) {
    return '「照片」拒絕了該影片（$code）——請嘗試分享';
  }

  @override
  String get share => '分享';

  @override
  String get video => '影片';

  @override
  String get saveToPhotos => '儲存至「照片」';

  @override
  String get hairdresser => '髮型師';

  @override
  String get hairdresserHint => '臉部維持不變；除非你選擇新顏色，否則髮色也不變。最適合露出完整頭髮、未戴帽子的正面人像。';

  @override
  String get colourUnchanged => '顏色不變';

  @override
  String get colourOnly => '僅顏色';

  @override
  String get noHairstylesYet => '尚無髮型。';

  @override
  String get searchHairstyle => '搜尋髮型';

  @override
  String mapLoadFailed(String error) {
    return '地圖載入失敗：$error';
  }

  @override
  String copiedText(String text) {
    return '已拷貝：$text';
  }

  @override
  String get styleMaps => '風格地圖';

  @override
  String get use => '使用';

  @override
  String get copy => '拷貝';

  @override
  String get retry => '重試';

  @override
  String get noMapsOnServer => '伺服器上尚無地圖。';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 張圖片',
    );
    return '$_temp0';
  }
}
