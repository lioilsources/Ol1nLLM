// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get newChat => '新しいチャット';

  @override
  String get noConversationsYet => '会話はまだありません';

  @override
  String get newConversation => '新しい会話';

  @override
  String get newSession => '新しいセッション';

  @override
  String get noSavedSessionsYet => '保存されたセッションはまだありません';

  @override
  String get today => '今日';

  @override
  String get yesterday => '昨日';

  @override
  String get exportedToFinetune => 'FINETUNEギャラリーに書き出しました';

  @override
  String get exportToFinetune => 'FINETUNEギャラリーに書き出す';

  @override
  String get tooltipImageStudio => '画像スタジオ';

  @override
  String get tooltipMusicStudio => 'ミュージックスタジオ';

  @override
  String get tooltipVoiceStudio => 'ボイススタジオ';

  @override
  String get tooltipStoryStudio => 'ストーリースタジオ';

  @override
  String branchHint(String label) {
    return '新しいメッセージは「$label」から分岐を作ります';
  }

  @override
  String get messageHint => 'ラボにメッセージ…';

  @override
  String get ocrHint => '任意の指示…';

  @override
  String get pickImage => '画像を選択';

  @override
  String get inputMode => 'モード';

  @override
  String get askLibrary => 'ライブラリに質問…';

  @override
  String get askLaw => '法律について質問…';

  @override
  String get askLeads => '契約書にある企業について質問…';

  @override
  String get nextMessageRole => '次のメッセージの役割';

  @override
  String get replyCopied => '返信をクリップボードにコピーしました';

  @override
  String searchingSeconds(int seconds) {
    return '検索中… $seconds秒';
  }

  @override
  String personasLoadFailed(String error) {
    return 'ペルソナを読み込めませんでした:\n$error';
  }

  @override
  String get pickPersona => 'ペルソナを選択';

  @override
  String get pickPersonaSub => '今日は誰と話しますか？';

  @override
  String get speakCancel => '読み上げをキャンセル';

  @override
  String get speakPause => '一時停止';

  @override
  String get speakResume => '再開';

  @override
  String get speakAloud => '読み上げ';

  @override
  String speakRhythm(String rhythm) {
    return 'リズムに合わせて読み上げ（$rhythm）';
  }

  @override
  String get sourceOriginal => '原文';

  @override
  String linkOpenFailed(String uri) {
    return 'リンクを開けません: $uri';
  }

  @override
  String get openOriginal => '原文を開く';

  @override
  String get figureIdCopied => 'フィギュアIDをクリップボードにコピーしました';

  @override
  String get figureNameCopied => '名前をクリップボードにコピーしました';

  @override
  String get dancingFigure => '踊るフィギュア';

  @override
  String get shareGlb => 'GLBを共有（Blender、3Dビューア）';

  @override
  String figureLoadFailed(String error) {
    return 'フィギュアを読み込めませんでした: $error';
  }

  @override
  String get model3d => '3Dモデル';

  @override
  String get shareStl => 'STLを共有（Prusa Slicer）';

  @override
  String glbLoadFailed(String error) {
    return 'GLBを読み込めませんでした: $error';
  }

  @override
  String get videoSavedToPhotos => 'ビデオを「写真」に保存しました';

  @override
  String photosRejectedVideo(String code) {
    return '「写真」がビデオを受け付けませんでした（$code）。共有をお試しください';
  }

  @override
  String get share => '共有';

  @override
  String get video => 'ビデオ';

  @override
  String get saveToPhotos => '「写真」に保存';

  @override
  String get hairdresser => 'ヘアスタイリスト';

  @override
  String get hairdresserHint =>
      '顔はそのままで、新しい色を選ばない限り髪色もそのままです。髪全体が写った、帽子なしの正面のポートレートが最適です。';

  @override
  String get colourUnchanged => '色は変更しない';

  @override
  String get colourOnly => '色のみ';

  @override
  String get noHairstylesYet => 'ヘアスタイルはまだありません。';

  @override
  String get searchHairstyle => 'ヘアスタイルを検索';

  @override
  String mapLoadFailed(String error) {
    return 'マップを読み込めませんでした: $error';
  }

  @override
  String copiedText(String text) {
    return 'コピーしました: $text';
  }

  @override
  String get styleMaps => 'スタイルマップ';

  @override
  String get use => '使用';

  @override
  String get copy => 'コピー';

  @override
  String get retry => '再試行';

  @override
  String get noMapsOnServer => 'サーバーにはまだマップがありません。';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count枚の画像',
    );
    return '$_temp0';
  }
}
