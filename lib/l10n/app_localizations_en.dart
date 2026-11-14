// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get newChat => 'New chat';

  @override
  String get noConversationsYet => 'No conversations yet';

  @override
  String get newConversation => 'New conversation';

  @override
  String get newSession => 'New session';

  @override
  String get noSavedSessionsYet => 'No saved sessions yet';

  @override
  String get today => 'today';

  @override
  String get yesterday => 'yesterday';

  @override
  String get exportedToFinetune => 'Exported to the FINETUNE gallery';

  @override
  String get exportToFinetune => 'Export to the FINETUNE gallery';

  @override
  String get tooltipImageStudio => 'Image Studio';

  @override
  String get tooltipMusicStudio => 'Music Studio';

  @override
  String get tooltipVoiceStudio => 'Voice Studio';

  @override
  String get tooltipStoryStudio => 'Story Studio';

  @override
  String branchHint(String label) {
    return 'A new message will start a branch from “$label”';
  }

  @override
  String get messageHint => 'Message the lab…';

  @override
  String get ocrHint => 'Optional instruction…';

  @override
  String get pickImage => 'Pick image';

  @override
  String get inputMode => 'Mode';

  @override
  String get askLibrary => 'Ask the library…';

  @override
  String get askLaw => 'Ask about the law…';

  @override
  String get askLeads => 'Ask about companies from contracts…';

  @override
  String get nextMessageRole => 'Role for the next message';

  @override
  String get replyCopied => 'Reply copied to clipboard';

  @override
  String searchingSeconds(int seconds) {
    return 'searching… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Could not load personas:\n$error';
  }

  @override
  String get pickPersona => 'Pick a persona';

  @override
  String get pickPersonaSub => 'Who do you want to talk to today?';

  @override
  String get speakCancel => 'Cancel reading';

  @override
  String get speakPause => 'Pause';

  @override
  String get speakResume => 'Resume';

  @override
  String get speakAloud => 'Read aloud';

  @override
  String speakRhythm(String rhythm) {
    return 'Read to the beat ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Can’t open link: $uri';
  }

  @override
  String get openOriginal => 'Open original';

  @override
  String get figureIdCopied => 'Figure ID copied to clipboard';

  @override
  String get figureNameCopied => 'Name copied to clipboard';

  @override
  String get dancingFigure => 'Dancing figure';

  @override
  String get shareGlb => 'Share GLB (Blender, 3D viewers)';

  @override
  String figureLoadFailed(String error) {
    return 'Could not load the figure: $error';
  }

  @override
  String get model3d => '3D model';

  @override
  String get shareStl => 'Share STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Could not load the GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Video saved to Photos';

  @override
  String photosRejectedVideo(String code) {
    return 'Photos rejected the video ($code) — try Share';
  }

  @override
  String get share => 'Share';

  @override
  String get video => 'Video';

  @override
  String get saveToPhotos => 'Save to Photos';

  @override
  String get hairdresser => 'Hairdresser';

  @override
  String get hairdresserHint =>
      'The face stays the same, and so does the hair colour unless you pick a new one. Works best with a front-facing portrait showing the full hair, no hat.';

  @override
  String get colourUnchanged => 'Colour unchanged';

  @override
  String get colourOnly => 'Colour only';

  @override
  String get noHairstylesYet => 'No hairstyles yet.';

  @override
  String get searchHairstyle => 'Search hairstyles';

  @override
  String mapLoadFailed(String error) {
    return 'map failed to load: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copied: $text';
  }

  @override
  String get styleMaps => 'Style maps';

  @override
  String get use => 'Use';

  @override
  String get copy => 'Copy';

  @override
  String get retry => 'Retry';

  @override
  String get noMapsOnServer => 'There are no maps on the server yet.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '$count image',
    );
    return '$_temp0';
  }
}
