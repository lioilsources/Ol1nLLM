// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get newChat => 'Nuevo chat';

  @override
  String get noConversationsYet => 'Aún no hay conversaciones';

  @override
  String get newConversation => 'Nueva conversación';

  @override
  String get newSession => 'Nueva sesión';

  @override
  String get noSavedSessionsYet => 'Aún no hay sesiones guardadas';

  @override
  String get today => 'hoy';

  @override
  String get yesterday => 'ayer';

  @override
  String get exportedToFinetune => 'Exportado a la galería FINETUNE';

  @override
  String get exportToFinetune => 'Exportar a la galería FINETUNE';

  @override
  String get tooltipImageStudio => 'Estudio de imágenes';

  @override
  String get tooltipMusicStudio => 'Estudio de música';

  @override
  String get tooltipVoiceStudio => 'Estudio de voz';

  @override
  String get tooltipStoryStudio => 'Estudio de historias';

  @override
  String branchHint(String label) {
    return 'Un mensaje nuevo creará una rama a partir de «$label»';
  }

  @override
  String get messageHint => 'Escribe al laboratorio…';

  @override
  String get ocrHint => 'Instrucción opcional…';

  @override
  String get pickImage => 'Elegir imagen';

  @override
  String get inputMode => 'Modo';

  @override
  String get askLibrary => 'Pregunta a la biblioteca…';

  @override
  String get askLaw => 'Pregunta sobre la ley…';

  @override
  String get askLeads => 'Pregunta por empresas de los contratos…';

  @override
  String get nextMessageRole => 'Rol para el siguiente mensaje';

  @override
  String get replyCopied => 'Respuesta copiada al portapapeles';

  @override
  String searchingSeconds(int seconds) {
    return 'buscando… $seconds s';
  }

  @override
  String personasLoadFailed(String error) {
    return 'No se pudieron cargar los personajes:\n$error';
  }

  @override
  String get pickPersona => 'Elige un personaje';

  @override
  String get pickPersonaSub => '¿Con quién quieres hablar hoy?';

  @override
  String get speakCancel => 'Cancelar lectura';

  @override
  String get speakPause => 'Pausar';

  @override
  String get speakResume => 'Reanudar';

  @override
  String get speakAloud => 'Leer en voz alta';

  @override
  String speakRhythm(String rhythm) {
    return 'Leer al ritmo ($rhythm)';
  }

  @override
  String get sourceOriginal => 'original';

  @override
  String linkOpenFailed(String uri) {
    return 'No se puede abrir el enlace: $uri';
  }

  @override
  String get openOriginal => 'Abrir original';

  @override
  String get figureIdCopied => 'ID de la figura copiado al portapapeles';

  @override
  String get figureNameCopied => 'Nombre copiado al portapapeles';

  @override
  String get dancingFigure => 'Figura bailarina';

  @override
  String get shareGlb => 'Compartir GLB (Blender, visores 3D)';

  @override
  String figureLoadFailed(String error) {
    return 'No se pudo cargar la figura: $error';
  }

  @override
  String get model3d => 'Modelo 3D';

  @override
  String get shareStl => 'Compartir STL (Prusa Slicer)';

  @override
  String glbLoadFailed(String error) {
    return 'No se pudo cargar el GLB: $error';
  }

  @override
  String get videoSavedToPhotos => 'Vídeo guardado en Fotos';

  @override
  String photosRejectedVideo(String code) {
    return 'Fotos rechazó el vídeo ($code); prueba con Compartir';
  }

  @override
  String get share => 'Compartir';

  @override
  String get video => 'Vídeo';

  @override
  String get saveToPhotos => 'Guardar en Fotos';

  @override
  String get hairdresser => 'Peluquero';

  @override
  String get hairdresserHint =>
      'La cara se mantiene, y el color del pelo también si no eliges uno nuevo. Funciona mejor con un retrato frontal con todo el pelo visible y sin gorra.';

  @override
  String get colourUnchanged => 'Color sin cambios';

  @override
  String get colourOnly => 'Solo color';

  @override
  String get noHairstylesYet => 'Aún no hay peinados.';

  @override
  String get searchHairstyle => 'Buscar peinado';

  @override
  String mapLoadFailed(String error) {
    return 'no se pudo cargar el mapa: $error';
  }

  @override
  String copiedText(String text) {
    return 'Copiado: $text';
  }

  @override
  String get styleMaps => 'Mapas de estilos';

  @override
  String get use => 'Usar';

  @override
  String get copy => 'Copiar';

  @override
  String get retry => 'Reintentar';

  @override
  String get noMapsOnServer => 'Todavía no hay ningún mapa en el servidor.';

  @override
  String imageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imágenes',
      one: '$count imagen',
    );
    return '$_temp0';
  }
}
