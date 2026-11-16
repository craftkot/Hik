import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Read-only inspection of ordinary ZIP containers (also APK/JAR and ZIP OBB).
/// This does not decrypt game-specific encrypted formats.
class ArchiveEntry {
  const ArchiveEntry({required this.path, required this.size});
  final String path;
  final int size;
  String get name => path.split('/').last;
}

class ArchiveInspector {
  ArchiveInspector._(this._archive, this.entries);

  static const maxInput = 8 * 1024 * 1024;
  static const maxEntry = 4 * 1024 * 1024;
  static const maxTotal = 48 * 1024 * 1024;
  static const maxEntries = 2000;

  final Archive _archive;
  final List<ArchiveEntry> entries;

  static bool isZip(Uint8List bytes) => bytes.length >= 4 &&
      bytes[0] == 0x50 && bytes[1] == 0x4b &&
      ((bytes[2] == 3 && bytes[3] == 4) ||
       (bytes[2] == 5 && bytes[3] == 6) ||
       (bytes[2] == 7 && bytes[3] == 8));

  static ArchiveInspector open(Uint8List bytes) {
    if (bytes.length > maxInput) {
      throw const FormatException('ZIP превышает лимит просмотра 8 МиБ');
    }
    if (!isZip(bytes)) {
      throw const FormatException('Не найден заголовок ZIP');
    }
    // The archive package keeps compressed entries lazy until readBytes().
    final archive = ZipDecoder().decodeBytes(bytes, throwOnError: true);
    if (archive.length > maxEntries) {
      throw const FormatException('Слишком много файлов в архиве');
    }
    var total = 0;
    final result = <ArchiveEntry>[];
    for (final file in archive) {
      if (!file.isFile || file.isSymbolicLink) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name.startsWith('/') || name.contains('../') ||
          name == '..' || name.contains('\u0000') || file.size < 0) {
        throw const FormatException('Недопустимый путь внутри ZIP');
      }
      total += file.size;
      if (total > maxTotal) {
        throw const FormatException('Архив слишком велик после распаковки');
      }
      result.add(ArchiveEntry(path: name, size: file.size));
    }
    return ArchiveInspector._(archive, List.unmodifiable(result));
  }

  Uint8List read(ArchiveEntry entry) {
    if (entry.size > maxEntry) {
      throw StateError('Файл внутри ZIP больше лимита 4 МиБ');
    }
    final file = _archive.find(entry.path);
    if (file == null || !file.isFile || file.size != entry.size) {
      throw StateError('Файл не найден в ZIP');
    }
    final bytes = file.readBytes();
    if (bytes == null || bytes.length != entry.size || bytes.length > maxEntry) {
      throw StateError('Ошибка распаковки ZIP');
    }
    return bytes;
  }
}
