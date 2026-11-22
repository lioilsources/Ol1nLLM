// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Modern Greek (`el`).
class AppLocalizationsEl extends AppLocalizations {
  AppLocalizationsEl([String locale = 'el']) : super(locale);

  @override
  String get newChat => 'Νέα συνομιλία';

  @override
  String get noConversationsYet => 'Δεν υπάρχουν ακόμη συνομιλίες';

  @override
  String get newConversation => 'Νέα συζήτηση';

  @override
  String get newSession => 'Νέα συνεδρία';

  @override
  String get noSavedSessionsYet => 'Δεν υπάρχουν ακόμη αποθηκευμένες συνεδρίες';

  @override
  String get today => 'σήμερα';

  @override
  String get yesterday => 'χθες';

  @override
  String get exportedToFinetune => 'Εξαγωγή στη συλλογή FINETUNE ολοκληρώθηκε';

  @override
  String get exportToFinetune => 'Εξαγωγή στη συλλογή FINETUNE';

  @override
  String get tooltipImageStudio => 'Στούντιο εικόνων';

  @override
  String get tooltipMusicStudio => 'Στούντιο μουσικής';

  @override
  String get tooltipVoiceStudio => 'Στούντιο φωνής';

  @override
  String get tooltipStoryStudio => 'Στούντιο ιστοριών';

  @override
  String branchHint(String label) {
    return 'Ένα νέο μήνυμα θα ξεκινήσει διακλάδωση από το «$label»';
  }

  @override
  String get messageHint => 'Γράψε στο εργαστήριο…';

  @override
  String get ocrHint => 'Προαιρετική οδηγία…';

  @override
  String get pickImage => 'Επιλογή εικόνας';

  @override
  String get inputMode => 'Λειτουργία';

  @override
  String get askLibrary => 'Ρώτα τη βιβλιοθήκη…';

  @override
  String get askLaw => 'Ρώτα για τον νόμο…';

  @override
  String get askLeads => 'Ρώτα για εταιρείες από συμβάσεις…';

  @override
  String get nextMessageRole => 'Ρόλος για το επόμενο μήνυμα';

  @override
  String get replyCopied => 'Η απάντηση αντιγράφηκε στο πρόχειρο';

  @override
  String searchingSeconds(int seconds) {
    return 'αναζήτηση… $seconds δ';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Δεν ήταν δυνατή η φόρτωση των περσόνων:\n$error';
  }

  @override
  String get pickPersona => 'Διάλεξε μια περσόνα';

  @override
  String get pickPersonaSub => 'Με ποιον θέλεις να μιλήσεις σήμερα;';

  @override
  String get speakCancel => 'Ακύρωση ανάγνωσης';

  @override
  String get speakPause => 'Παύση';

  @override
  String get speakResume => 'Συνέχεια';

  @override
  String get speakAloud => 'Ανάγνωση φωναχτά';

  @override
  String speakRhythm(String rhythm) {
    return 'Ανάγνωση στον ρυθμό ($rhythm)';
  }

  @override
  String get sourceOriginal => 'πρωτότυπο';

  @override
  String linkOpenFailed(String uri) {
    return 'Δεν είναι δυνατό το άνοιγμα του συνδέσμου: $uri';
  }

  @override
  String get openOriginal => 'Άνοιγμα πρωτοτύπου';

  @override
  String get figureIdCopied =>
      'Το αναγνωριστικό της φιγούρας αντιγράφηκε στο πρόχειρο';

  @override
  String get figureNameCopied => 'Το όνομα αντιγράφηκε στο πρόχειρο';

  @override
  String get dancingFigure => 'Φιγούρα που χορεύει';

  @override
  String get shareGlb => 'Κοινοποίηση GLB (Blender, προβολείς 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'Δεν ήταν δυνατή η φόρτωση της φιγούρας: $error';
  }

  @override
  String get model3d => 'Μοντέλο 3D';

  @override
  String get shareStl => 'Κοινοποίηση STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Δεν ήταν δυνατή η φόρτωση του GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Το βίντεο αποθηκεύτηκε στις Φωτογραφίες';

  @override
  String photosRejectedVideo(String code) {
    return 'Οι Φωτογραφίες απέρριψαν το βίντεο ($code) — δοκίμασε Κοινοποίηση';
  }

  @override
  String get share => 'Κοινοποίηση';

  @override
  String get video => 'Βίντεο';

  @override
  String get saveToPhotos => 'Αποθήκευση στις Φωτογραφίες';

  @override
  String get hairdresser => 'Κομμωτής';

  @override
  String get hairdresserHint =>
      'Το πρόσωπο μένει ίδιο, και το χρώμα των μαλλιών επίσης, αν δεν επιλέξεις νέο. Λειτουργεί καλύτερα με πορτρέτο από μπροστά, με ολόκληρα τα μαλλιά και χωρίς καπέλο.';

  @override
  String get colourUnchanged => 'Χρώμα αμετάβλητο';

  @override
  String get colourOnly => 'Μόνο χρώμα';

  @override
  String get noHairstylesYet => 'Δεν υπάρχουν ακόμη χτενίσματα.';

  @override
  String get searchHairstyle => 'Αναζήτηση χτενίσματος';

  @override
  String mapLoadFailed(String error) {
    return 'ο χάρτης δεν φορτώθηκε: $error';
  }

  @override
  String copiedText(String text) {
    return 'Αντιγράφηκε: $text';
  }

  @override
  String get styleMaps => 'Χάρτες στυλ';

  @override
  String get use => 'Χρήση';

  @override
  String get copy => 'Αντιγραφή';

  @override
  String get retry => 'Δοκίμασε ξανά';

  @override
  String get noMapsOnServer =>
      'Δεν υπάρχει ακόμη κανένας χάρτης στον διακομιστή.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count εικόνες',
      one: '$count εικόνα',
    );
    return '$_temp0';
  }
}
