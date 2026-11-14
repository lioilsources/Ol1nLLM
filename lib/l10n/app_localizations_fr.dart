// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get newChat => 'Nouveau chat';

  @override
  String get noConversationsYet => 'Aucune conversation pour le moment';

  @override
  String get newConversation => 'Nouvelle conversation';

  @override
  String get newSession => 'Nouvelle session';

  @override
  String get noSavedSessionsYet => 'Aucune session enregistrée pour le moment';

  @override
  String get today => 'aujourd’hui';

  @override
  String get yesterday => 'hier';

  @override
  String get exportedToFinetune => 'Exporté vers la galerie FINETUNE';

  @override
  String get exportToFinetune => 'Exporter vers la galerie FINETUNE';

  @override
  String get tooltipImageStudio => 'Studio d’images';

  @override
  String get tooltipMusicStudio => 'Studio musical';

  @override
  String get tooltipVoiceStudio => 'Studio vocal';

  @override
  String get tooltipStoryStudio => 'Studio d’histoires';

  @override
  String branchHint(String label) {
    return 'Un nouveau message créera une branche à partir de « $label »';
  }

  @override
  String get messageHint => 'Écrire au labo…';

  @override
  String get ocrHint => 'Instruction facultative…';

  @override
  String get pickImage => 'Choisir une image';

  @override
  String get inputMode => 'Mode';

  @override
  String get askLibrary => 'Interroge la bibliothèque…';

  @override
  String get askLaw => 'Pose une question sur la loi…';

  @override
  String get askLeads => 'Demande des entreprises issues des contrats…';

  @override
  String get nextMessageRole => 'Rôle pour le prochain message';

  @override
  String get replyCopied => 'Réponse copiée dans le presse-papiers';

  @override
  String searchingSeconds(int seconds) {
    return 'recherche… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Impossible de charger les personas :\n$error';
  }

  @override
  String get pickPersona => 'Choisis un persona';

  @override
  String get pickPersonaSub => 'Avec qui veux-tu discuter aujourd’hui ?';

  @override
  String get speakCancel => 'Annuler la lecture';

  @override
  String get speakPause => 'Mettre en pause';

  @override
  String get speakResume => 'Reprendre';

  @override
  String get speakAloud => 'Lire à voix haute';

  @override
  String speakRhythm(String rhythm) {
    return 'Lire en rythme ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'Impossible d’ouvrir le lien : $uri';
  }

  @override
  String get openOriginal => 'Ouvrir l’original';

  @override
  String get figureIdCopied => 'ID de la figurine copié dans le presse-papiers';

  @override
  String get figureNameCopied => 'Nom copié dans le presse-papiers';

  @override
  String get dancingFigure => 'Figurine dansante';

  @override
  String get shareGlb => 'Partager le GLB (Blender, visionneuses 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Impossible de charger la figurine : $error';
  }

  @override
  String get model3d => 'Modèle 3D';

  @override
  String get shareStl => 'Partager le STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Impossible de charger le GLB : $error';
  }

  @override
  String get videoSavedToPhotos => 'Vidéo enregistrée dans Photos';

  @override
  String photosRejectedVideo(String code) {
    return 'Photos a refusé la vidéo ($code) — essaie Partager';
  }

  @override
  String get share => 'Partager';

  @override
  String get video => 'Vidéo';

  @override
  String get saveToPhotos => 'Enregistrer dans Photos';

  @override
  String get hairdresser => 'Coiffeur';

  @override
  String get hairdresserHint =>
      'Le visage reste le même, ainsi que la couleur des cheveux si tu n’en choisis pas une nouvelle. Fonctionne mieux avec un portrait de face montrant toute la chevelure, sans chapeau.';

  @override
  String get colourUnchanged => 'Couleur inchangée';

  @override
  String get colourOnly => 'Couleur seule';

  @override
  String get noHairstylesYet => 'Aucune coiffure pour le moment.';

  @override
  String get searchHairstyle => 'Rechercher une coiffure';

  @override
  String mapLoadFailed(String error) {
    return 'échec du chargement de la carte : $error';
  }

  @override
  String copiedText(String text) {
    return 'Copié : $text';
  }

  @override
  String get styleMaps => 'Cartes de styles';

  @override
  String get use => 'Utiliser';

  @override
  String get copy => 'Copier';

  @override
  String get retry => 'Réessayer';

  @override
  String get noMapsOnServer => 'Aucune carte sur le serveur pour le moment.';

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
