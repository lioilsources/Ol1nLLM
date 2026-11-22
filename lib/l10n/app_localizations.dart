import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_ca.dart';
import 'app_localizations_cs.dart';
import 'app_localizations_da.dart';
import 'app_localizations_de.dart';
import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fi.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_he.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_hr.dart';
import 'app_localizations_hu.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_ms.dart';
import 'app_localizations_nb.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_or.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ro.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_sk.dart';
import 'app_localizations_sl.dart';
import 'app_localizations_sv.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_ur.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
    Locale('bn'),
    Locale('ca'),
    Locale('cs'),
    Locale('da'),
    Locale('de'),
    Locale('el'),
    Locale('es'),
    Locale('fi'),
    Locale('fr'),
    Locale('gu'),
    Locale('he'),
    Locale('hi'),
    Locale('hr'),
    Locale('hu'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('kn'),
    Locale('ko'),
    Locale('ml'),
    Locale('mr'),
    Locale('ms'),
    Locale('nb'),
    Locale('nl'),
    Locale('or'),
    Locale('pa'),
    Locale('pl'),
    Locale('pt'),
    Locale('pt', 'PT'),
    Locale('ro'),
    Locale('ru'),
    Locale('sk'),
    Locale('sl'),
    Locale('sv'),
    Locale('ta'),
    Locale('te'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('ur'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @newChat.
  ///
  /// In cs, this message translates to:
  /// **'Nový chat'**
  String get newChat;

  /// No description provided for @noConversationsYet.
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádné konverzace'**
  String get noConversationsYet;

  /// No description provided for @newConversation.
  ///
  /// In cs, this message translates to:
  /// **'Nová konverzace'**
  String get newConversation;

  /// No description provided for @newSession.
  ///
  /// In cs, this message translates to:
  /// **'Nové sezení'**
  String get newSession;

  /// No description provided for @noSavedSessionsYet.
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádná uložená sezení'**
  String get noSavedSessionsYet;

  /// No description provided for @today.
  ///
  /// In cs, this message translates to:
  /// **'dnes'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In cs, this message translates to:
  /// **'včera'**
  String get yesterday;

  /// No description provided for @exportedToFinetune.
  ///
  /// In cs, this message translates to:
  /// **'Exportováno do galerie FINETUNE'**
  String get exportedToFinetune;

  /// No description provided for @exportToFinetune.
  ///
  /// In cs, this message translates to:
  /// **'Exportovat do galerie FINETUNE'**
  String get exportToFinetune;

  /// No description provided for @tooltipImageStudio.
  ///
  /// In cs, this message translates to:
  /// **'Obrázkové studio'**
  String get tooltipImageStudio;

  /// No description provided for @tooltipMusicStudio.
  ///
  /// In cs, this message translates to:
  /// **'Hudební studio'**
  String get tooltipMusicStudio;

  /// No description provided for @tooltipVoiceStudio.
  ///
  /// In cs, this message translates to:
  /// **'Hlasové studio'**
  String get tooltipVoiceStudio;

  /// No description provided for @tooltipStoryStudio.
  ///
  /// In cs, this message translates to:
  /// **'Příběhové studio'**
  String get tooltipStoryStudio;

  /// No description provided for @branchHint.
  ///
  /// In cs, this message translates to:
  /// **'Nová zpráva založí větev z „{label}“'**
  String branchHint(String label);

  /// No description provided for @messageHint.
  ///
  /// In cs, this message translates to:
  /// **'Napiš zprávu…'**
  String get messageHint;

  /// No description provided for @ocrHint.
  ///
  /// In cs, this message translates to:
  /// **'Volitelná instrukce…'**
  String get ocrHint;

  /// No description provided for @pickImage.
  ///
  /// In cs, this message translates to:
  /// **'Vybrat obrázek'**
  String get pickImage;

  /// No description provided for @inputMode.
  ///
  /// In cs, this message translates to:
  /// **'Režim'**
  String get inputMode;

  /// No description provided for @askLibrary.
  ///
  /// In cs, this message translates to:
  /// **'Zeptej se knihovny…'**
  String get askLibrary;

  /// No description provided for @askLaw.
  ///
  /// In cs, this message translates to:
  /// **'Zeptej se na zákon…'**
  String get askLaw;

  /// No description provided for @askLeads.
  ///
  /// In cs, this message translates to:
  /// **'Zeptej se na firmy ze smluv…'**
  String get askLeads;

  /// No description provided for @nextMessageRole.
  ///
  /// In cs, this message translates to:
  /// **'Role pro další zprávu'**
  String get nextMessageRole;

  /// No description provided for @replyCopied.
  ///
  /// In cs, this message translates to:
  /// **'Odpověď zkopírována do schránky'**
  String get replyCopied;

  /// No description provided for @searchingSeconds.
  ///
  /// In cs, this message translates to:
  /// **'hledám… {seconds} s'**
  String searchingSeconds(int seconds);

  /// No description provided for @personasLoadFailed.
  ///
  /// In cs, this message translates to:
  /// **'Nepodařilo se načíst persony:\n{error}'**
  String personasLoadFailed(String error);

  /// No description provided for @pickPersona.
  ///
  /// In cs, this message translates to:
  /// **'Vyber si personu'**
  String get pickPersona;

  /// No description provided for @pickPersonaSub.
  ///
  /// In cs, this message translates to:
  /// **'S kým si dnes budeš povídat?'**
  String get pickPersonaSub;

  /// No description provided for @speakCancel.
  ///
  /// In cs, this message translates to:
  /// **'Zrušit čtení'**
  String get speakCancel;

  /// No description provided for @speakPause.
  ///
  /// In cs, this message translates to:
  /// **'Pozastavit'**
  String get speakPause;

  /// No description provided for @speakResume.
  ///
  /// In cs, this message translates to:
  /// **'Pokračovat'**
  String get speakResume;

  /// No description provided for @speakAloud.
  ///
  /// In cs, this message translates to:
  /// **'Přečíst nahlas'**
  String get speakAloud;

  /// No description provided for @speakRhythm.
  ///
  /// In cs, this message translates to:
  /// **'Přečíst v rytmu ({rhythm})'**
  String speakRhythm(String rhythm);

  /// No description provided for @sourceOriginal.
  ///
  /// In cs, this message translates to:
  /// **'originál'**
  String get sourceOriginal;

  /// No description provided for @linkOpenFailed.
  ///
  /// In cs, this message translates to:
  /// **'Odkaz nejde otevřít: {uri}'**
  String linkOpenFailed(String uri);

  /// No description provided for @openOriginal.
  ///
  /// In cs, this message translates to:
  /// **'Otevřít originál'**
  String get openOriginal;

  /// No description provided for @figureIdCopied.
  ///
  /// In cs, this message translates to:
  /// **'ID figurky zkopírováno do schránky'**
  String get figureIdCopied;

  /// No description provided for @figureNameCopied.
  ///
  /// In cs, this message translates to:
  /// **'Název zkopírován do schránky'**
  String get figureNameCopied;

  /// No description provided for @dancingFigure.
  ///
  /// In cs, this message translates to:
  /// **'Tančící figurka'**
  String get dancingFigure;

  /// No description provided for @shareGlb.
  ///
  /// In cs, this message translates to:
  /// **'Sdílet GLB (Blender, 3D prohlížeče)'**
  String get shareGlb;

  /// No description provided for @figureLoadFailed.
  ///
  /// In cs, this message translates to:
  /// **'Figurku se nepodařilo načíst: {error}'**
  String figureLoadFailed(String error);

  /// No description provided for @model3d.
  ///
  /// In cs, this message translates to:
  /// **'3D model'**
  String get model3d;

  /// No description provided for @shareStl.
  ///
  /// In cs, this message translates to:
  /// **'Sdílet STL (Prusa Slicer)'**
  String get shareStl;

  /// No description provided for @glbLoadFailed.
  ///
  /// In cs, this message translates to:
  /// **'GLB se nepodařilo načíst: {error}'**
  String glbLoadFailed(String error);

  /// No description provided for @videoSavedToPhotos.
  ///
  /// In cs, this message translates to:
  /// **'Video uloženo do Fotek'**
  String get videoSavedToPhotos;

  /// No description provided for @photosRejectedVideo.
  ///
  /// In cs, this message translates to:
  /// **'Fotky video nepřijaly ({code}) — zkus Sdílet'**
  String photosRejectedVideo(String code);

  /// No description provided for @share.
  ///
  /// In cs, this message translates to:
  /// **'Sdílet'**
  String get share;

  /// No description provided for @video.
  ///
  /// In cs, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @saveToPhotos.
  ///
  /// In cs, this message translates to:
  /// **'Uložit do Fotek'**
  String get saveToPhotos;

  /// No description provided for @hairdresser.
  ///
  /// In cs, this message translates to:
  /// **'Kadeřník'**
  String get hairdresser;

  /// No description provided for @hairdresserHint.
  ///
  /// In cs, this message translates to:
  /// **'Tvář zůstane; barva vlasů taky, pokud nevybereš novou. Nejlíp funguje čelní portrét s celými vlasy, bez čepice.'**
  String get hairdresserHint;

  /// No description provided for @colourUnchanged.
  ///
  /// In cs, this message translates to:
  /// **'Barva beze změny'**
  String get colourUnchanged;

  /// No description provided for @colourOnly.
  ///
  /// In cs, this message translates to:
  /// **'Jen barva'**
  String get colourOnly;

  /// No description provided for @noHairstylesYet.
  ///
  /// In cs, this message translates to:
  /// **'Zatím žádné účesy.'**
  String get noHairstylesYet;

  /// No description provided for @searchHairstyle.
  ///
  /// In cs, this message translates to:
  /// **'Hledat účes'**
  String get searchHairstyle;

  /// No description provided for @mapLoadFailed.
  ///
  /// In cs, this message translates to:
  /// **'mapa se nenačetla: {error}'**
  String mapLoadFailed(String error);

  /// No description provided for @copiedText.
  ///
  /// In cs, this message translates to:
  /// **'Zkopírováno: {text}'**
  String copiedText(String text);

  /// No description provided for @styleMaps.
  ///
  /// In cs, this message translates to:
  /// **'Mapy stylů'**
  String get styleMaps;

  /// No description provided for @use.
  ///
  /// In cs, this message translates to:
  /// **'Použít'**
  String get use;

  /// No description provided for @copy.
  ///
  /// In cs, this message translates to:
  /// **'Kopírovat'**
  String get copy;

  /// No description provided for @retry.
  ///
  /// In cs, this message translates to:
  /// **'Znovu'**
  String get retry;

  /// No description provided for @noMapsOnServer.
  ///
  /// In cs, this message translates to:
  /// **'Na serveru zatím žádná mapa není.'**
  String get noMapsOnServer;

  /// No description provided for @imageCount.
  ///
  /// In cs, this message translates to:
  /// **'{count, plural, one{{count} obrázek} few{{count} obrázky} other{{count} obrázků}}'**
  String imageCount(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'bn',
    'ca',
    'cs',
    'da',
    'de',
    'el',
    'en',
    'es',
    'fi',
    'fr',
    'gu',
    'he',
    'hi',
    'hr',
    'hu',
    'id',
    'it',
    'ja',
    'kn',
    'ko',
    'ml',
    'mr',
    'ms',
    'nb',
    'nl',
    'or',
    'pa',
    'pl',
    'pt',
    'ro',
    'ru',
    'sk',
    'sl',
    'sv',
    'ta',
    'te',
    'th',
    'tr',
    'uk',
    'ur',
    'vi',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'PT':
            return AppLocalizationsPtPt();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'bn':
      return AppLocalizationsBn();
    case 'ca':
      return AppLocalizationsCa();
    case 'cs':
      return AppLocalizationsCs();
    case 'da':
      return AppLocalizationsDa();
    case 'de':
      return AppLocalizationsDe();
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fi':
      return AppLocalizationsFi();
    case 'fr':
      return AppLocalizationsFr();
    case 'gu':
      return AppLocalizationsGu();
    case 'he':
      return AppLocalizationsHe();
    case 'hi':
      return AppLocalizationsHi();
    case 'hr':
      return AppLocalizationsHr();
    case 'hu':
      return AppLocalizationsHu();
    case 'id':
      return AppLocalizationsId();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'kn':
      return AppLocalizationsKn();
    case 'ko':
      return AppLocalizationsKo();
    case 'ml':
      return AppLocalizationsMl();
    case 'mr':
      return AppLocalizationsMr();
    case 'ms':
      return AppLocalizationsMs();
    case 'nb':
      return AppLocalizationsNb();
    case 'nl':
      return AppLocalizationsNl();
    case 'or':
      return AppLocalizationsOr();
    case 'pa':
      return AppLocalizationsPa();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ro':
      return AppLocalizationsRo();
    case 'ru':
      return AppLocalizationsRu();
    case 'sk':
      return AppLocalizationsSk();
    case 'sl':
      return AppLocalizationsSl();
    case 'sv':
      return AppLocalizationsSv();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
    case 'th':
      return AppLocalizationsTh();
    case 'tr':
      return AppLocalizationsTr();
    case 'uk':
      return AppLocalizationsUk();
    case 'ur':
      return AppLocalizationsUr();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
