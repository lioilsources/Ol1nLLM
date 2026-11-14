// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get newChat => 'Obrolan baru';

  @override
  String get noConversationsYet => 'Belum ada percakapan';

  @override
  String get newConversation => 'Percakapan baru';

  @override
  String get newSession => 'Sesi baru';

  @override
  String get noSavedSessionsYet => 'Belum ada sesi tersimpan';

  @override
  String get today => 'hari ini';

  @override
  String get yesterday => 'kemarin';

  @override
  String get exportedToFinetune => 'Diekspor ke galeri FINETUNE';

  @override
  String get exportToFinetune => 'Ekspor ke galeri FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio Gambar';

  @override
  String get tooltipMusicStudio => 'Studio Musik';

  @override
  String get tooltipVoiceStudio => 'Studio Suara';

  @override
  String get tooltipStoryStudio => 'Studio Cerita';

  @override
  String branchHint(String label) {
    return 'Pesan baru akan membuat cabang dari “$label”';
  }

  @override
  String get messageHint => 'Kirim pesan ke lab…';

  @override
  String get ocrHint => 'Instruksi opsional…';

  @override
  String get pickImage => 'Pilih gambar';

  @override
  String get inputMode => 'Mode';

  @override
  String get askLibrary => 'Tanya perpustakaan…';

  @override
  String get askLaw => 'Tanya soal hukum…';

  @override
  String get askLeads => 'Tanya soal perusahaan dalam kontrak…';

  @override
  String get nextMessageRole => 'Peran untuk pesan berikutnya';

  @override
  String get replyCopied => 'Balasan disalin ke papan klip';

  @override
  String searchingSeconds(int seconds) {
    return 'mencari… $seconds dtk';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Gagal memuat persona:\n$error';
  }

  @override
  String get pickPersona => 'Pilih persona';

  @override
  String get pickPersonaSub => 'Hari ini mau ngobrol dengan siapa?';

  @override
  String get speakCancel => 'Batalkan pembacaan';

  @override
  String get speakPause => 'Jeda';

  @override
  String get speakResume => 'Lanjutkan';

  @override
  String get speakAloud => 'Bacakan';

  @override
  String speakRhythm(String rhythm) {
    return 'Bacakan sesuai irama ($rhythm)';
  }

  @override
  String get sourceOriginal => 'asli';

  @override
  String linkOpenFailed(String uri) {
    return 'Tidak dapat membuka tautan: $uri';
  }

  @override
  String get openOriginal => 'Buka yang asli';

  @override
  String get figureIdCopied => 'ID figur disalin ke papan klip';

  @override
  String get figureNameCopied => 'Nama disalin ke papan klip';

  @override
  String get dancingFigure => 'Figur menari';

  @override
  String get shareGlb => 'Bagikan GLB (Blender, penampil 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Gagal memuat figur: $error';
  }

  @override
  String get model3d => 'Model 3D';

  @override
  String get shareStl => 'Bagikan STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Gagal memuat GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video disimpan ke Foto';

  @override
  String photosRejectedVideo(String code) {
    return 'Foto menolak video ($code) — coba Bagikan';
  }

  @override
  String get share => 'Bagikan';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Simpan ke Foto';

  @override
  String get hairdresser => 'Penata rambut';

  @override
  String get hairdresserHint =>
      'Wajah tetap sama, begitu juga warna rambut kecuali Anda memilih warna baru. Paling baik dengan potret tampak depan yang memperlihatkan seluruh rambut, tanpa topi.';

  @override
  String get colourUnchanged => 'Warna tidak diubah';

  @override
  String get colourOnly => 'Hanya warna';

  @override
  String get noHairstylesYet => 'Belum ada gaya rambut.';

  @override
  String get searchHairstyle => 'Cari gaya rambut';

  @override
  String mapLoadFailed(String error) {
    return 'peta gagal dimuat: $error';
  }

  @override
  String copiedText(String text) {
    return 'Disalin: $text';
  }

  @override
  String get styleMaps => 'Peta gaya';

  @override
  String get use => 'Gunakan';

  @override
  String get copy => 'Salin';

  @override
  String get retry => 'Coba lagi';

  @override
  String get noMapsOnServer => 'Belum ada peta di server.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gambar',
    );
    return '$_temp0';
  }
}
