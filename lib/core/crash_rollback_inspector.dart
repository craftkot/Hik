import 'dart:io';
import 'dart:typed_data';

import 'safe_desktop_save.dart';

/// Read-only inspection of interrupted Windows save swaps.
/// No file is renamed, deleted or automatically restored.
class CrashRollbackPreview {
  const CrashRollbackPreview({
    required this.path,
    required this.bytes,
    required this.currentExists,
    required this.currentBytes,
  });

  final String path;
  final Uint8List bytes;
  final bool currentExists;
  final Uint8List? currentBytes;
  bool get differsFromCurrent {
    final current = currentBytes;
    if (current == null || current.length != bytes.length) return true;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != current[i]) return true;
    }
    return false;
  }
}

class CrashRollbackInspector {
  /// Avoid retaining an unbounded number of 8 MiB snapshots in memory.
  static const int maxCandidates = 32;

  /// Returns previews only for regular, bounded rollback files belonging
  /// to [save]. Symlinks and oversized files are rejected, not followed.
  static Future<List<CrashRollbackPreview>> inspect(File save) async {
    final prefix = '${save.uri.pathSegments.last}.ehtid-rollback-';
    final currentType =
        await FileSystemEntity.type(save.path, followLinks: false);
    if (currentType != FileSystemEntityType.file &&
        currentType != FileSystemEntityType.notFound) {
      throw StateError('Сейв не является обычным файлом');
    }
    Uint8List? current;
    if (currentType == FileSystemEntityType.file) {
      if (await save.length() > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Сейв превышает лимит 8 МиБ');
      }
      current = await save.readAsBytes();
      if (current.length > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Сейв превышает лимит 8 МиБ');
      }
    }
    final result = <CrashRollbackPreview>[];
    await for (final entity in save.parent.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.tmp')) continue;
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('Аварийный файл не является обычным файлом: ${entity.path}');
      }
      final candidate = File(entity.path);
      if (await candidate.length() > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Аварийный файл превышает лимит 8 МиБ: ${entity.path}');
      }
      final data = await candidate.readAsBytes();
      if (data.length > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Аварийный файл превышает лимит 8 МиБ: ${entity.path}');
      }
      if (result.length >= maxCandidates) {
        throw StateError('Слишком много аварийных файлов (максимум $maxCandidates)');
      }
      result.add(CrashRollbackPreview(
        path: candidate.path,
        bytes: data,
        currentExists: current != null,
        currentBytes: current == null ? null : Uint8List.fromList(current),
      ));
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }
}
