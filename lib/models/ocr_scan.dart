import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// One OCR scan: the source image (stored as a file on disk, like [GenImage],
/// to keep the Hive box small) plus the recognized text.
class OcrScan {
  final String id;
  final String imagePath;
  final String text;
  final DateTime createdAt;
  Uint8List? _bytes;

  OcrScan({
    required this.id,
    required this.imagePath,
    required this.text,
    required this.createdAt,
  });

  /// Image bytes, read lazily from [imagePath] and cached for this instance.
  Uint8List get bytes => _bytes ??= File(imagePath).readAsBytesSync();

  /// Persist [bytes] to [dir] as `<uuid>.<ext>` and return a scan record.
  static Future<OcrScan> save({
    required Uint8List bytes,
    required Directory dir,
    required String text,
    String ext = 'jpg',
  }) async {
    final id = _uuid.v4();
    final file = File('${dir.path}/$id.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return OcrScan(
      id: id,
      imagePath: file.path,
      text: text,
      createdAt: DateTime.now(),
    ).._bytes = bytes;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory OcrScan.fromJson(Map<String, dynamic> json) => OcrScan(
    id: json['id'] as String,
    imagePath: json['imagePath'] as String,
    text: json['text'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
