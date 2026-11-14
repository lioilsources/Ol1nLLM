// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get newChat => 'Новий чат';

  @override
  String get noConversationsYet => 'Поки що немає розмов';

  @override
  String get newConversation => 'Нова розмова';

  @override
  String get newSession => 'Новий сеанс';

  @override
  String get noSavedSessionsYet => 'Поки що немає збережених сеансів';

  @override
  String get today => 'сьогодні';

  @override
  String get yesterday => 'вчора';

  @override
  String get exportedToFinetune => 'Експортовано до галереї FINETUNE';

  @override
  String get exportToFinetune => 'Експортувати до галереї FINETUNE';

  @override
  String get tooltipImageStudio => 'Студія зображень';

  @override
  String get tooltipMusicStudio => 'Музична студія';

  @override
  String get tooltipVoiceStudio => 'Студія голосу';

  @override
  String get tooltipStoryStudio => 'Студія історій';

  @override
  String branchHint(String label) {
    return 'Нове повідомлення створить гілку від «$label»';
  }

  @override
  String get messageHint => 'Написати лабораторії…';

  @override
  String get ocrHint => 'Необов’язкова інструкція…';

  @override
  String get pickImage => 'Вибрати зображення';

  @override
  String get inputMode => 'Режим';

  @override
  String get askLibrary => 'Запитайте бібліотеку…';

  @override
  String get askLaw => 'Запитайте про закон…';

  @override
  String get askLeads => 'Запитайте про компанії з договорів…';

  @override
  String get nextMessageRole => 'Роль для наступного повідомлення';

  @override
  String get replyCopied => 'Відповідь скопійовано до буфера обміну';

  @override
  String searchingSeconds(int seconds) {
    return 'пошук… $seconds с';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Не вдалося завантажити персонажів:\n$error';
  }

  @override
  String get pickPersona => 'Виберіть персонажа';

  @override
  String get pickPersonaSub => 'З ким ви хочете поговорити сьогодні?';

  @override
  String get speakCancel => 'Скасувати читання';

  @override
  String get speakPause => 'Призупинити';

  @override
  String get speakResume => 'Продовжити';

  @override
  String get speakAloud => 'Прочитати вголос';

  @override
  String speakRhythm(String rhythm) {
    return 'Прочитати в ритмі ($rhythm)';
  }

  @override
  String get sourceOriginal => 'оригінал';

  @override
  String linkOpenFailed(String uri) {
    return 'Не вдається відкрити посилання: $uri';
  }

  @override
  String get openOriginal => 'Відкрити оригінал';

  @override
  String get figureIdCopied => 'ID фігурки скопійовано до буфера обміну';

  @override
  String get figureNameCopied => 'Назву скопійовано до буфера обміну';

  @override
  String get dancingFigure => 'Фігурка, що танцює';

  @override
  String get shareGlb => 'Поділитися GLB (Blender, 3D-переглядачі)';

  @override
  String figureLoadFailed(String error) {
    return 'Не вдалося завантажити фігурку: $error';
  }

  @override
  String get model3d => '3D-модель';

  @override
  String get shareStl => 'Поділитися STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Не вдалося завантажити GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Відео збережено у «Фото»';

  @override
  String photosRejectedVideo(String code) {
    return '«Фото» не прийняло відео ($code) — спробуйте «Поділитися»';
  }

  @override
  String get share => 'Поділитися';

  @override
  String get video => 'Відео';

  @override
  String get saveToPhotos => 'Зберегти у «Фото»';

  @override
  String get hairdresser => 'Перукар';

  @override
  String get hairdresserHint =>
      'Обличчя залишиться тим самим, як і колір волосся, якщо ви не виберете новий. Найкраще працює портрет анфас з усім волоссям, без головного убору.';

  @override
  String get colourUnchanged => 'Колір без змін';

  @override
  String get colourOnly => 'Лише колір';

  @override
  String get noHairstylesYet => 'Поки що немає зачісок.';

  @override
  String get searchHairstyle => 'Шукати зачіску';

  @override
  String mapLoadFailed(String error) {
    return 'не вдалося завантажити карту: $error';
  }

  @override
  String copiedText(String text) {
    return 'Скопійовано: $text';
  }

  @override
  String get styleMaps => 'Карти стилів';

  @override
  String get use => 'Використати';

  @override
  String get copy => 'Копіювати';

  @override
  String get retry => 'Повторити';

  @override
  String get noMapsOnServer => 'На сервері поки що немає жодної карти.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count зображення',
      many: '$count зображень',
      few: '$count зображення',
      one: '$count зображення',
    );
    return '$_temp0';
  }
}
