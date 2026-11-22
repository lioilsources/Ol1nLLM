// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get newChat => 'Neuer Chat';

  @override
  String get noConversationsYet => 'Noch keine Unterhaltungen';

  @override
  String get newConversation => 'Neue Unterhaltung';

  @override
  String get newSession => 'Neue Sitzung';

  @override
  String get noSavedSessionsYet => 'Noch keine gespeicherten Sitzungen';

  @override
  String get today => 'heute';

  @override
  String get yesterday => 'gestern';

  @override
  String get exportedToFinetune => 'In die FINETUNE-Galerie exportiert';

  @override
  String get exportToFinetune => 'In die FINETUNE-Galerie exportieren';

  @override
  String get tooltipImageStudio => 'Bildstudio';

  @override
  String get tooltipMusicStudio => 'Musikstudio';

  @override
  String get tooltipVoiceStudio => 'Stimmenstudio';

  @override
  String get tooltipStoryStudio => 'Geschichtenstudio';

  @override
  String branchHint(String label) {
    return 'Eine neue Nachricht startet einen Zweig ab „$label“';
  }

  @override
  String get messageHint => 'Nachricht an das Labor…';

  @override
  String get ocrHint => 'Optionale Anweisung…';

  @override
  String get pickImage => 'Bild auswählen';

  @override
  String get inputMode => 'Modus';

  @override
  String get askLibrary => 'Frag die Bibliothek…';

  @override
  String get askLaw => 'Frag zum Gesetz…';

  @override
  String get askLeads => 'Frag nach Firmen aus Verträgen…';

  @override
  String get nextMessageRole => 'Rolle für die nächste Nachricht';

  @override
  String get replyCopied => 'Antwort in die Zwischenablage kopiert';

  @override
  String searchingSeconds(int seconds) {
    return 'suche… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Personas konnten nicht geladen werden:\n$error';
  }

  @override
  String get pickPersona => 'Wähle eine Persona';

  @override
  String get pickPersonaSub => 'Mit wem möchtest du heute sprechen?';

  @override
  String get speakCancel => 'Vorlesen abbrechen';

  @override
  String get speakPause => 'Pausieren';

  @override
  String get speakResume => 'Fortsetzen';

  @override
  String get speakAloud => 'Vorlesen';

  @override
  String speakRhythm(String rhythm) {
    return 'Im Rhythmus vorlesen ($rhythm)';
  }

  @override
  String get sourceOriginal => 'Original';

  @override
  String linkOpenFailed(String uri) {
    return 'Link kann nicht geöffnet werden: $uri';
  }

  @override
  String get openOriginal => 'Original öffnen';

  @override
  String get figureIdCopied => 'Figuren-ID in die Zwischenablage kopiert';

  @override
  String get figureNameCopied => 'Name in die Zwischenablage kopiert';

  @override
  String get dancingFigure => 'Tanzende Figur';

  @override
  String get shareGlb => 'GLB teilen (Blender, 3D-Viewer)';

  @override
  String figureLoadFailed(String error) {
    return 'Figur konnte nicht geladen werden: $error';
  }

  @override
  String get model3d => '3D-Modell';

  @override
  String get shareStl => 'STL teilen (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'GLB konnte nicht geladen werden: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video in Fotos gesichert';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotos hat das Video abgelehnt ($code) – versuche Teilen';
  }

  @override
  String get share => 'Teilen';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'In Fotos sichern';

  @override
  String get hairdresser => 'Friseur';

  @override
  String get hairdresserHint =>
      'Das Gesicht bleibt gleich, die Haarfarbe auch, solange du keine neue wählst. Am besten funktioniert ein frontales Porträt mit vollem Haar und ohne Mütze.';

  @override
  String get colourUnchanged => 'Farbe unverändert';

  @override
  String get colourOnly => 'Nur Farbe';

  @override
  String get noHairstylesYet => 'Noch keine Frisuren.';

  @override
  String get searchHairstyle => 'Frisuren suchen';

  @override
  String mapLoadFailed(String error) {
    return 'Karte konnte nicht geladen werden: $error';
  }

  @override
  String copiedText(String text) {
    return 'Kopiert: $text';
  }

  @override
  String get styleMaps => 'Stilkarten';

  @override
  String get use => 'Verwenden';

  @override
  String get copy => 'Kopieren';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get noMapsOnServer => 'Auf dem Server gibt es noch keine Karte.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bilder',
      one: '$count Bild',
    );
    return '$_temp0';
  }
}
