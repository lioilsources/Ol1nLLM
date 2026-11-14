// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get newChat => 'Новый чат';

  @override
  String get noConversationsYet => 'Пока нет бесед';

  @override
  String get newConversation => 'Новая беседа';

  @override
  String get newSession => 'Новый сеанс';

  @override
  String get noSavedSessionsYet => 'Пока нет сохранённых сеансов';

  @override
  String get today => 'сегодня';

  @override
  String get yesterday => 'вчера';

  @override
  String get exportedToFinetune => 'Экспортировано в галерею FINETUNE';

  @override
  String get exportToFinetune => 'Экспортировать в галерею FINETUNE';

  @override
  String get tooltipImageStudio => 'Студия изображений';

  @override
  String get tooltipMusicStudio => 'Музыкальная студия';

  @override
  String get tooltipVoiceStudio => 'Студия голоса';

  @override
  String get tooltipStoryStudio => 'Студия историй';

  @override
  String branchHint(String label) {
    return 'Новое сообщение создаст ветку от «$label»';
  }

  @override
  String get messageHint => 'Написать лаборатории…';

  @override
  String get ocrHint => 'Необязательная инструкция…';

  @override
  String get pickImage => 'Выбрать изображение';

  @override
  String get inputMode => 'Режим';

  @override
  String get askLibrary => 'Спросите библиотеку…';

  @override
  String get askLaw => 'Спросите о законе…';

  @override
  String get askLeads => 'Спросите о компаниях из договоров…';

  @override
  String get nextMessageRole => 'Роль для следующего сообщения';

  @override
  String get replyCopied => 'Ответ скопирован в буфер обмена';

  @override
  String searchingSeconds(int seconds) {
    return 'поиск… $seconds с';
  }

  @override
  String personasLoadFailed(String error) {
    return 'Не удалось загрузить персонажей:\n$error';
  }

  @override
  String get pickPersona => 'Выберите персонажа';

  @override
  String get pickPersonaSub => 'С кем вы хотите поговорить сегодня?';

  @override
  String get speakCancel => 'Отменить чтение';

  @override
  String get speakPause => 'Приостановить';

  @override
  String get speakResume => 'Продолжить';

  @override
  String get speakAloud => 'Прочитать вслух';

  @override
  String speakRhythm(String rhythm) {
    return 'Прочитать в ритме ($rhythm)';
  }

  @override
  String get sourceOriginal => 'оригинал';

  @override
  String linkOpenFailed(String uri) {
    return 'Не удаётся открыть ссылку: $uri';
  }

  @override
  String get openOriginal => 'Открыть оригинал';

  @override
  String get figureIdCopied => 'ID фигурки скопирован в буфер обмена';

  @override
  String get figureNameCopied => 'Название скопировано в буфер обмена';

  @override
  String get dancingFigure => 'Танцующая фигурка';

  @override
  String get shareGlb => 'Поделиться GLB (Blender, 3D-просмотрщики)';

  @override
  String figureLoadFailed(String error) {
    return 'Не удалось загрузить фигурку: $error';
  }

  @override
  String get model3d => '3D-модель';

  @override
  String get shareStl => 'Поделиться STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'Не удалось загрузить GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Видео сохранено в «Фото»';

  @override
  String photosRejectedVideo(String code) {
    return '«Фото» не приняло видео ($code) — попробуйте «Поделиться»';
  }

  @override
  String get share => 'Поделиться';

  @override
  String get video => 'Видео';

  @override
  String get saveToPhotos => 'Сохранить в «Фото»';

  @override
  String get hairdresser => 'Парикмахер';

  @override
  String get hairdresserHint =>
      'Лицо останется прежним, как и цвет волос, если вы не выберете новый. Лучше всего работает портрет анфас с целиком видимыми волосами, без головного убора.';

  @override
  String get colourUnchanged => 'Цвет без изменений';

  @override
  String get colourOnly => 'Только цвет';

  @override
  String get noHairstylesYet => 'Пока нет причёсок.';

  @override
  String get searchHairstyle => 'Искать причёску';

  @override
  String mapLoadFailed(String error) {
    return 'не удалось загрузить карту: $error';
  }

  @override
  String copiedText(String text) {
    return 'Скопировано: $text';
  }

  @override
  String get styleMaps => 'Карты стилей';

  @override
  String get use => 'Использовать';

  @override
  String get copy => 'Копировать';

  @override
  String get retry => 'Повторить';

  @override
  String get noMapsOnServer => 'На сервере пока нет ни одной карты.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count изображения',
      many: '$count изображений',
      few: '$count изображения',
      one: '$count изображение',
    );
    return '$_temp0';
  }
}
