// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get newChat => 'Cuộc trò chuyện mới';

  @override
  String get noConversationsYet => 'Chưa có cuộc trò chuyện nào';

  @override
  String get newConversation => 'Cuộc trò chuyện mới';

  @override
  String get newSession => 'Phiên mới';

  @override
  String get noSavedSessionsYet => 'Chưa có phiên nào được lưu';

  @override
  String get today => 'hôm nay';

  @override
  String get yesterday => 'hôm qua';

  @override
  String get exportedToFinetune => 'Đã xuất sang thư viện FINETUNE';

  @override
  String get exportToFinetune => 'Xuất sang thư viện FINETUNE';

  @override
  String get tooltipImageStudio => 'Xưởng ảnh';

  @override
  String get tooltipMusicStudio => 'Xưởng nhạc';

  @override
  String get tooltipVoiceStudio => 'Xưởng giọng nói';

  @override
  String get tooltipStoryStudio => 'Xưởng truyện';

  @override
  String branchHint(String label) {
    return 'Tin nhắn mới sẽ tạo một nhánh từ “$label”';
  }

  @override
  String get messageHint => 'Nhắn cho phòng thí nghiệm…';

  @override
  String get ocrHint => 'Hướng dẫn tùy chọn…';

  @override
  String get pickImage => 'Chọn ảnh';

  @override
  String get inputMode => 'Chế độ';

  @override
  String get askLibrary => 'Hỏi thư viện…';

  @override
  String get askLaw => 'Hỏi về luật…';

  @override
  String get askLeads => 'Hỏi về các công ty trong hợp đồng…';

  @override
  String get nextMessageRole => 'Vai trò cho tin nhắn tiếp theo';

  @override
  String get replyCopied => 'Đã sao chép câu trả lời vào bộ nhớ tạm';

  @override
  String searchingSeconds(int seconds) {
    return 'đang tìm… $seconds giây';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Không thể tải các nhân vật:\n$error';
  }

  @override
  String get pickPersona => 'Chọn một nhân vật';

  @override
  String get pickPersonaSub => 'Hôm nay bạn muốn trò chuyện với ai?';

  @override
  String get speakCancel => 'Hủy đọc';

  @override
  String get speakPause => 'Tạm dừng';

  @override
  String get speakResume => 'Tiếp tục';

  @override
  String get speakAloud => 'Đọc to';

  @override
  String speakRhythm(String rhythm) {
    return 'Đọc theo nhịp ($rhythm)';
  }

  @override
  String get sourceOriginal => 'bản gốc';

  @override
  String linkOpenFailed(String uri) {
    return 'Không thể mở liên kết: $uri';
  }

  @override
  String get openOriginal => 'Mở bản gốc';

  @override
  String get figureIdCopied => 'Đã sao chép ID mô hình vào bộ nhớ tạm';

  @override
  String get figureNameCopied => 'Đã sao chép tên vào bộ nhớ tạm';

  @override
  String get dancingFigure => 'Mô hình nhảy múa';

  @override
  String get shareGlb => 'Chia sẻ GLB (Blender, trình xem 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Không thể tải mô hình: $error';
  }

  @override
  String get model3d => 'Mô hình 3D';

  @override
  String get shareStl => 'Chia sẻ STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Không thể tải GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Đã lưu video vào Ảnh';

  @override
  String photosRejectedVideo(String code) {
    return 'Ảnh đã từ chối video ($code) — hãy thử Chia sẻ';
  }

  @override
  String get share => 'Chia sẻ';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Lưu vào Ảnh';

  @override
  String get hairdresser => 'Thợ làm tóc';

  @override
  String get hairdresserHint =>
      'Khuôn mặt giữ nguyên, màu tóc cũng vậy nếu bạn không chọn màu mới. Hiệu quả nhất với ảnh chân dung chính diện thấy rõ toàn bộ mái tóc, không đội mũ.';

  @override
  String get colourUnchanged => 'Giữ nguyên màu';

  @override
  String get colourOnly => 'Chỉ đổi màu';

  @override
  String get noHairstylesYet => 'Chưa có kiểu tóc nào.';

  @override
  String get searchHairstyle => 'Tìm kiểu tóc';

  @override
  String mapLoadFailed(String error) {
    return 'không tải được bản đồ: $error';
  }

  @override
  String copiedText(String text) {
    return 'Đã sao chép: $text';
  }

  @override
  String get styleMaps => 'Bản đồ phong cách';

  @override
  String get use => 'Dùng';

  @override
  String get copy => 'Sao chép';

  @override
  String get retry => 'Thử lại';

  @override
  String get noMapsOnServer => 'Máy chủ chưa có bản đồ nào.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ảnh',
    );
    return '$_temp0';
  }
}
