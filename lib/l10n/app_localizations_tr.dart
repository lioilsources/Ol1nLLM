// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get newChat => 'Yeni sohbet';

  @override
  String get noConversationsYet => 'Henüz konuşma yok';

  @override
  String get newConversation => 'Yeni konuşma';

  @override
  String get newSession => 'Yeni oturum';

  @override
  String get noSavedSessionsYet => 'Henüz kayıtlı oturum yok';

  @override
  String get today => 'bugün';

  @override
  String get yesterday => 'dün';

  @override
  String get exportedToFinetune => 'FINETUNE galerisine aktarıldı';

  @override
  String get exportToFinetune => 'FINETUNE galerisine aktar';

  @override
  String get tooltipImageStudio => 'Görsel Stüdyosu';

  @override
  String get tooltipMusicStudio => 'Müzik Stüdyosu';

  @override
  String get tooltipVoiceStudio => 'Ses Stüdyosu';

  @override
  String get tooltipStoryStudio => 'Hikâye Stüdyosu';

  @override
  String branchHint(String label) {
    return 'Yeni bir mesaj “$label” üzerinden yeni bir dal başlatır';
  }

  @override
  String get messageHint => 'Laboratuvara yaz…';

  @override
  String get ocrHint => 'İsteğe bağlı talimat…';

  @override
  String get pickImage => 'Görsel seç';

  @override
  String get inputMode => 'Mod';

  @override
  String get askLibrary => 'Kütüphaneye sor…';

  @override
  String get askLaw => 'Kanunla ilgili sor…';

  @override
  String get askLeads => 'Sözleşmelerdeki şirketleri sor…';

  @override
  String get nextMessageRole => 'Sonraki mesaj için rol';

  @override
  String get replyCopied => 'Yanıt panoya kopyalandı';

  @override
  String searchingSeconds(int seconds) {
    return 'aranıyor… $seconds sn';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Karakterler yüklenemedi:\n$error';
  }

  @override
  String get pickPersona => 'Bir karakter seç';

  @override
  String get pickPersonaSub => 'Bugün kiminle konuşmak istersin?';

  @override
  String get speakCancel => 'Okumayı iptal et';

  @override
  String get speakPause => 'Duraklat';

  @override
  String get speakResume => 'Sürdür';

  @override
  String get speakAloud => 'Sesli oku';

  @override
  String speakRhythm(String rhythm) {
    return 'Ritimle oku ($rhythm)';
  }

  @override
  String get sourceOriginal => 'orijinal';

  @override
  String linkOpenFailed(String uri) {
    return 'Bağlantı açılamıyor: $uri';
  }

  @override
  String get openOriginal => 'Orijinali aç';

  @override
  String get figureIdCopied => 'Figür kimliği panoya kopyalandı';

  @override
  String get figureNameCopied => 'Ad panoya kopyalandı';

  @override
  String get dancingFigure => 'Dans eden figür';

  @override
  String get shareGlb => 'GLB paylaş (Blender, 3B görüntüleyiciler)';

  @override
  String figureLoadFailed(String error) {
    return 'Figür yüklenemedi: $error';
  }

  @override
  String get model3d => '3B model';

  @override
  String get shareStl => 'STL paylaş (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB yüklenemedi: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video Fotoğraflar’a kaydedildi';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotoğraflar videoyu kabul etmedi ($code) — Paylaş’ı dene';
  }

  @override
  String get share => 'Paylaş';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Fotoğraflar’a kaydet';

  @override
  String get hairdresser => 'Kuaför';

  @override
  String get hairdresserHint =>
      'Yüz aynı kalır; yeni bir renk seçmezsen saç rengi de aynı kalır. En iyi sonucu, saçın tamamının göründüğü, şapkasız, önden çekilmiş bir portre verir.';

  @override
  String get colourUnchanged => 'Renk değişmedi';

  @override
  String get colourOnly => 'Yalnızca renk';

  @override
  String get noHairstylesYet => 'Henüz saç modeli yok.';

  @override
  String get searchHairstyle => 'Saç modeli ara';

  @override
  String mapLoadFailed(String error) {
    return 'harita yüklenemedi: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopyalandı: $text';
  }

  @override
  String get styleMaps => 'Stil haritaları';

  @override
  String get use => 'Kullan';

  @override
  String get copy => 'Kopyala';

  @override
  String get retry => 'Yeniden dene';

  @override
  String get noMapsOnServer => 'Sunucuda henüz harita yok.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count görsel',
      one: '$count görsel',
    );
    return '$_temp0';
  }
}
