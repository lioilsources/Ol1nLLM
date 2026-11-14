// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Croatian (`hr`).
class AppLocalizationsHr extends AppLocalizations {
  AppLocalizationsHr([String locale = 'hr']) : super(locale);

  @override
  String get newChat => 'Novi chat';

  @override
  String get noConversationsYet => 'Još nema razgovora';

  @override
  String get newConversation => 'Novi razgovor';

  @override
  String get newSession => 'Nova sesija';

  @override
  String get noSavedSessionsYet => 'Još nema spremljenih sesija';

  @override
  String get today => 'danas';

  @override
  String get yesterday => 'jučer';

  @override
  String get exportedToFinetune => 'Izvezeno u galeriju FINETUNE';

  @override
  String get exportToFinetune => 'Izvezi u galeriju FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio slika';

  @override
  String get tooltipMusicStudio => 'Glazbeni studio';

  @override
  String get tooltipVoiceStudio => 'Glasovni studio';

  @override
  String get tooltipStoryStudio => 'Studio priča';

  @override
  String branchHint(String label) {
    return 'Nova poruka otvorit će granu od „$label”';
  }

  @override
  String get messageHint => 'Napiši poruku laboratoriju…';

  @override
  String get ocrHint => 'Neobavezna uputa…';

  @override
  String get pickImage => 'Odaberi sliku';

  @override
  String get inputMode => 'Način';

  @override
  String get askLibrary => 'Pitaj knjižnicu…';

  @override
  String get askLaw => 'Pitaj o zakonu…';

  @override
  String get askLeads => 'Pitaj o tvrtkama iz ugovora…';

  @override
  String get nextMessageRole => 'Uloga za sljedeću poruku';

  @override
  String get replyCopied => 'Odgovor je kopiran u međuspremnik';

  @override
  String searchingSeconds(int seconds) {
    return 'tražim… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Nije moguće učitati persone:\n$error';
  }

  @override
  String get pickPersona => 'Odaberi personu';

  @override
  String get pickPersonaSub => 'S kim danas želiš razgovarati?';

  @override
  String get speakCancel => 'Odustani od čitanja';

  @override
  String get speakPause => 'Pauziraj';

  @override
  String get speakResume => 'Nastavi';

  @override
  String get speakAloud => 'Pročitaj naglas';

  @override
  String speakRhythm(String rhythm) {
    return 'Pročitaj u ritmu ($rhythm)';
  }

  @override
  String get sourceOriginal => 'izvornik';

  @override
  String linkOpenFailed(String uri) {
    return 'Poveznicu nije moguće otvoriti: $uri';
  }

  @override
  String get openOriginal => 'Otvori izvornik';

  @override
  String get figureIdCopied => 'ID figure kopiran je u međuspremnik';

  @override
  String get figureNameCopied => 'Naziv je kopiran u međuspremnik';

  @override
  String get dancingFigure => 'Plesna figura';

  @override
  String get shareGlb => 'Podijeli GLB (Blender, 3D preglednici)';

  @override
  String figureLoadFailed(String error) {
    return 'Nije moguće učitati figuru: $error';
  }

  @override
  String get model3d => '3D model';

  @override
  String get shareStl => 'Podijeli STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Nije moguće učitati GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Videozapis je spremljen u Fotografije';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotografije su odbile videozapis ($code) – pokušaj Podijeli';
  }

  @override
  String get share => 'Podijeli';

  @override
  String get video => 'Videozapis';

  @override
  String get saveToPhotos => 'Spremi u Fotografije';

  @override
  String get hairdresser => 'Frizer';

  @override
  String get hairdresserHint =>
      'Lice ostaje isto, a tako i boja kose ako ne odabereš novu. Najbolje radi portret s prednje strane s cijelom kosom, bez kape.';

  @override
  String get colourUnchanged => 'Boja nepromijenjena';

  @override
  String get colourOnly => 'Samo boja';

  @override
  String get noHairstylesYet => 'Još nema frizura.';

  @override
  String get searchHairstyle => 'Traži frizuru';

  @override
  String mapLoadFailed(String error) {
    return 'karta se nije učitala: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopirano: $text';
  }

  @override
  String get styleMaps => 'Karte stilova';

  @override
  String get use => 'Upotrijebi';

  @override
  String get copy => 'Kopiraj';

  @override
  String get retry => 'Pokušaj ponovno';

  @override
  String get noMapsOnServer => 'Na poslužitelju još nema nijedne karte.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slika',
      few: '$count slike',
      one: '$count slika',
    );
    return '$_temp0';
  }
}
