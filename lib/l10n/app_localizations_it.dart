// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get newChat => 'Nuova chat';

  @override
  String get noConversationsYet => 'Ancora nessuna conversazione';

  @override
  String get newConversation => 'Nuova conversazione';

  @override
  String get newSession => 'Nuova sessione';

  @override
  String get noSavedSessionsYet => 'Ancora nessuna sessione salvata';

  @override
  String get today => 'oggi';

  @override
  String get yesterday => 'ieri';

  @override
  String get exportedToFinetune => 'Esportato nella galleria FINETUNE';

  @override
  String get exportToFinetune => 'Esporta nella galleria FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio immagini';

  @override
  String get tooltipMusicStudio => 'Studio musicale';

  @override
  String get tooltipVoiceStudio => 'Studio vocale';

  @override
  String get tooltipStoryStudio => 'Studio storie';

  @override
  String branchHint(String label) {
    return 'Un nuovo messaggio creerà un ramo da «$label»';
  }

  @override
  String get messageHint => 'Scrivi al laboratorio…';

  @override
  String get ocrHint => 'Istruzione facoltativa…';

  @override
  String get pickImage => 'Scegli immagine';

  @override
  String get inputMode => 'Modalità';

  @override
  String get askLibrary => 'Chiedi alla biblioteca…';

  @override
  String get askLaw => 'Chiedi della legge…';

  @override
  String get askLeads => 'Chiedi delle aziende nei contratti…';

  @override
  String get nextMessageRole => 'Ruolo per il prossimo messaggio';

  @override
  String get replyCopied => 'Risposta copiata negli appunti';

  @override
  String searchingSeconds(int seconds) {
    return 'ricerca… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Impossibile caricare i personaggi:\n$error';
  }

  @override
  String get pickPersona => 'Scegli un personaggio';

  @override
  String get pickPersonaSub => 'Con chi vuoi parlare oggi?';

  @override
  String get speakCancel => 'Annulla lettura';

  @override
  String get speakPause => 'Pausa';

  @override
  String get speakResume => 'Riprendi';

  @override
  String get speakAloud => 'Leggi ad alta voce';

  @override
  String speakRhythm(String rhythm) {
    return 'Leggi a ritmo ($rhythm)';
  }

  @override
  String get sourceOriginal => 'originale';

  @override
  String linkOpenFailed(String uri) {
    return 'Impossibile aprire il link: $uri';
  }

  @override
  String get openOriginal => 'Apri originale';

  @override
  String get figureIdCopied => 'ID della figura copiato negli appunti';

  @override
  String get figureNameCopied => 'Nome copiato negli appunti';

  @override
  String get dancingFigure => 'Figura danzante';

  @override
  String get shareGlb => 'Condividi GLB (Blender, visualizzatori 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Impossibile caricare la figura: $error';
  }

  @override
  String get model3d => 'Modello 3D';

  @override
  String get shareStl => 'Condividi STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Impossibile caricare il GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video salvato in Foto';

  @override
  String photosRejectedVideo(String code) {
    return 'Foto ha rifiutato il video ($code): prova con Condividi';
  }

  @override
  String get share => 'Condividi';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Salva in Foto';

  @override
  String get hairdresser => 'Parrucchiere';

  @override
  String get hairdresserHint =>
      'Il viso resta uguale, e anche il colore dei capelli se non ne scegli uno nuovo. Funziona meglio con un ritratto frontale con i capelli interi e senza cappello.';

  @override
  String get colourUnchanged => 'Colore invariato';

  @override
  String get colourOnly => 'Solo colore';

  @override
  String get noHairstylesYet => 'Ancora nessuna acconciatura.';

  @override
  String get searchHairstyle => 'Cerca acconciatura';

  @override
  String mapLoadFailed(String error) {
    return 'caricamento della mappa non riuscito: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiato: $text';
  }

  @override
  String get styleMaps => 'Mappe di stili';

  @override
  String get use => 'Usa';

  @override
  String get copy => 'Copia';

  @override
  String get retry => 'Riprova';

  @override
  String get noMapsOnServer => 'Sul server non c’è ancora nessuna mappa.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count immagini',
      one: '$count immagine',
    );
    return '$_temp0';
  }
}
