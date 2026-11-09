// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get newChat => 'แชทใหม่';

  @override
  String get noConversationsYet => 'ยังไม่มีการสนทนา';

  @override
  String get newConversation => 'การสนทนาใหม่';

  @override
  String get newSession => 'เซสชันใหม่';

  @override
  String get noSavedSessionsYet => 'ยังไม่มีเซสชันที่บันทึกไว้';

  @override
  String get today => 'วันนี้';

  @override
  String get yesterday => 'เมื่อวาน';

  @override
  String get exportedToFinetune => 'ส่งออกไปยังแกลเลอรี FINETUNE แล้ว';

  @override
  String get exportToFinetune => 'ส่งออกไปยังแกลเลอรี FINETUNE';

  @override
  String get tooltipImageStudio => 'สตูดิโอภาพ';

  @override
  String get tooltipMusicStudio => 'สตูดิโอเพลง';

  @override
  String get tooltipVoiceStudio => 'สตูดิโอเสียง';

  @override
  String get tooltipStoryStudio => 'สตูดิโอเรื่องราว';

  @override
  String branchHint(String label) {
    return 'ข้อความใหม่จะแตกแขนงจาก “$label”';
  }

  @override
  String get messageHint => 'ส่งข้อความถึงแล็บ…';

  @override
  String get ocrHint => 'คำสั่งเพิ่มเติม (ไม่บังคับ)…';

  @override
  String get pickImage => 'เลือกรูปภาพ';

  @override
  String get inputMode => 'โหมด';

  @override
  String get askLibrary => 'ถามห้องสมุด…';

  @override
  String get askLaw => 'ถามเรื่องกฎหมาย…';

  @override
  String get askLeads => 'ถามเรื่องบริษัทจากสัญญา…';

  @override
  String get nextMessageRole => 'บทบาทสำหรับข้อความถัดไป';

  @override
  String get replyCopied => 'คัดลอกคำตอบไปยังคลิปบอร์ดแล้ว';

  @override
  String searchingSeconds(int seconds) {
    return 'กำลังค้นหา… $seconds วิ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'โหลดตัวละครไม่สำเร็จ:\n$error';
  }

  @override
  String get pickPersona => 'เลือกตัวละคร';

  @override
  String get pickPersonaSub => 'วันนี้อยากคุยกับใคร';

  @override
  String get speakCancel => 'ยกเลิกการอ่าน';

  @override
  String get speakPause => 'หยุดชั่วคราว';

  @override
  String get speakResume => 'เล่นต่อ';

  @override
  String get speakAloud => 'อ่านออกเสียง';

  @override
  String speakRhythm(String rhythm) {
    return 'อ่านตามจังหวะ ($rhythm)';
  }

  @override
  String get sourceOriginal => 'ต้นฉบับ';

  @override
  String linkOpenFailed(String uri) {
    return 'เปิดลิงก์ไม่ได้: $uri';
  }

  @override
  String get openOriginal => 'เปิดต้นฉบับ';

  @override
  String get figureIdCopied => 'คัดลอก ID ฟิกเกอร์ไปยังคลิปบอร์ดแล้ว';

  @override
  String get figureNameCopied => 'คัดลอกชื่อไปยังคลิปบอร์ดแล้ว';

  @override
  String get dancingFigure => 'ฟิกเกอร์เต้นรำ';

  @override
  String get shareGlb => 'แชร์ GLB (Blender, โปรแกรมดู 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'โหลดฟิกเกอร์ไม่สำเร็จ: $error';
  }

  @override
  String get model3d => 'โมเดล 3 มิติ';

  @override
  String get shareStl => 'แชร์ STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'โหลด GLB ไม่สำเร็จ: $error';
  }

  @override
  String get videoSavedToPhotos => 'บันทึกวิดีโอลงในรูปภาพแล้ว';

  @override
  String photosRejectedVideo(String code) {
    return 'แอปรูปภาพไม่รับวิดีโอ ($code) — ลองใช้แชร์';
  }

  @override
  String get share => 'แชร์';

  @override
  String get video => 'วิดีโอ';

  @override
  String get saveToPhotos => 'บันทึกลงในรูปภาพ';

  @override
  String get hairdresser => 'ช่างทำผม';

  @override
  String get hairdresserHint =>
      'ใบหน้าจะคงเดิม และสีผมก็คงเดิมด้วยหากไม่เลือกสีใหม่ ใช้ได้ดีที่สุดกับภาพถ่ายด้านหน้าที่เห็นผมทั้งศีรษะ และไม่สวมหมวก';

  @override
  String get colourUnchanged => 'ไม่เปลี่ยนสี';

  @override
  String get colourOnly => 'เฉพาะสี';

  @override
  String get noHairstylesYet => 'ยังไม่มีทรงผม';

  @override
  String get searchHairstyle => 'ค้นหาทรงผม';

  @override
  String mapLoadFailed(String error) {
    return 'โหลดแผนที่ไม่สำเร็จ: $error';
  }

  @override
  String copiedText(String text) {
    return 'คัดลอกแล้ว: $text';
  }

  @override
  String get styleMaps => 'แผนที่สไตล์';

  @override
  String get use => 'ใช้';

  @override
  String get copy => 'คัดลอก';

  @override
  String get retry => 'ลองอีกครั้ง';

  @override
  String get noMapsOnServer => 'ยังไม่มีแผนที่บนเซิร์ฟเวอร์';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ภาพ',
    );
    return '$_temp0';
  }
}
