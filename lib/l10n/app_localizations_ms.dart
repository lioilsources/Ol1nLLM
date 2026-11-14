// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class AppLocalizationsMs extends AppLocalizations {
  AppLocalizationsMs([String locale = 'ms']) : super(locale);

  @override
  String get newChat => 'Sembang baharu';

  @override
  String get noConversationsYet => 'Belum ada perbualan';

  @override
  String get newConversation => 'Perbualan baharu';

  @override
  String get newSession => 'Sesi baharu';

  @override
  String get noSavedSessionsYet => 'Belum ada sesi disimpan';

  @override
  String get today => 'hari ini';

  @override
  String get yesterday => 'semalam';

  @override
  String get exportedToFinetune => 'Dieksport ke galeri FINETUNE';

  @override
  String get exportToFinetune => 'Eksport ke galeri FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio Imej';

  @override
  String get tooltipMusicStudio => 'Studio Muzik';

  @override
  String get tooltipVoiceStudio => 'Studio Suara';

  @override
  String get tooltipStoryStudio => 'Studio Cerita';

  @override
  String branchHint(String label) {
    return 'Mesej baharu akan mencipta cabang daripada “$label”';
  }

  @override
  String get messageHint => 'Mesej kepada makmal…';

  @override
  String get ocrHint => 'Arahan pilihan…';

  @override
  String get pickImage => 'Pilih imej';

  @override
  String get inputMode => 'Mod';

  @override
  String get askLibrary => 'Tanya perpustakaan…';

  @override
  String get askLaw => 'Tanya tentang undang-undang…';

  @override
  String get askLeads => 'Tanya tentang syarikat daripada kontrak…';

  @override
  String get nextMessageRole => 'Peranan untuk mesej seterusnya';

  @override
  String get replyCopied => 'Balasan disalin ke papan keratan';

  @override
  String searchingSeconds(int seconds) {
    return 'mencari… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Gagal memuatkan persona:\n$error';
  }

  @override
  String get pickPersona => 'Pilih persona';

  @override
  String get pickPersonaSub => 'Hari ini anda mahu berbual dengan siapa?';

  @override
  String get speakCancel => 'Batalkan bacaan';

  @override
  String get speakPause => 'Jeda';

  @override
  String get speakResume => 'Sambung';

  @override
  String get speakAloud => 'Baca dengan kuat';

  @override
  String speakRhythm(String rhythm) {
    return 'Baca mengikut rentak ($rhythm)';
  }

  @override
  String get sourceOriginal => 'asal';

  @override
  String linkOpenFailed(String uri) {
    return 'Tidak dapat membuka pautan: $uri';
  }

  @override
  String get openOriginal => 'Buka yang asal';

  @override
  String get figureIdCopied => 'ID figura disalin ke papan keratan';

  @override
  String get figureNameCopied => 'Nama disalin ke papan keratan';

  @override
  String get dancingFigure => 'Figura menari';

  @override
  String get shareGlb => 'Kongsi GLB (Blender, pemapar 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Gagal memuatkan figura: $error';
  }

  @override
  String get model3d => 'Model 3D';

  @override
  String get shareStl => 'Kongsi STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Gagal memuatkan GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video disimpan ke Foto';

  @override
  String photosRejectedVideo(String code) {
    return 'Foto menolak video ($code) — cuba Kongsi';
  }

  @override
  String get share => 'Kongsi';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Simpan ke Foto';

  @override
  String get hairdresser => 'Penata rambut';

  @override
  String get hairdresserHint =>
      'Wajah kekal sama, begitu juga warna rambut melainkan anda memilih warna baharu. Paling sesuai dengan potret menghadap depan yang menunjukkan seluruh rambut, tanpa topi.';

  @override
  String get colourUnchanged => 'Warna tidak diubah';

  @override
  String get colourOnly => 'Warna sahaja';

  @override
  String get noHairstylesYet => 'Belum ada gaya rambut.';

  @override
  String get searchHairstyle => 'Cari gaya rambut';

  @override
  String mapLoadFailed(String error) {
    return 'peta gagal dimuatkan: $error';
  }

  @override
  String copiedText(String text) {
    return 'Disalin: $text';
  }

  @override
  String get styleMaps => 'Peta gaya';

  @override
  String get use => 'Guna';

  @override
  String get copy => 'Salin';

  @override
  String get retry => 'Cuba lagi';

  @override
  String get noMapsOnServer => 'Belum ada peta pada pelayan.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imej',
    );
    return '$_temp0';
  }
}
