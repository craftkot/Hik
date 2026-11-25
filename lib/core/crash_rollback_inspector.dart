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
  /// Limit the combined retained rollback and per-preview current snapshots.
  static const int maxPreviewBytes = 32 * 1024 * 1024;

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
      current = await readBounded(save, SafeDesktopSaveWriter.maxLength);
    }
    final result = <CrashRollbackPreview>[];
    var retainedBytes = 0;
    await for (final entity in save.parent.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.tmp')) continue;
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('Аварийный файл не является обычным файлом: ${entity.path}');
      }
      if (result.length >= maxCandidates) {
        throw StateError('Слишком много аварийных файлов (максимум $maxCandidates)');
      }
      final candidate = File(entity.path);
      final remaining = maxPreviewBytes - retainedBytes - (current?.length ?? 0);
      if (remaining < 0) {
        throw StateError('Аварийные файлы превышают общий лимит предпросмотра 32 МиБ');
      }
      final limit = remaining < SafeDesktopSaveWriter.maxLength
          ? remaining
          : SafeDesktopSaveWriter.maxLength;
      final data = await readBounded(candidate, limit);
      retainedBytes += data.length + (current?.length ?? 0);
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
  /// Read at most [limit] + one sentinel byte, even if a file grows.
  /// The file handle is closed even when the limit is exceeded.
  static Future<Uint8List> readBounded(File file, int limit) async {
    final reader = await file.open();
    try {
      final buffer = BytesBuilder(copy: false);
      while (true) {
        final remaining = limit + 1 - buffer.length;
        final chunk = await reader.read(
            remaining < 64 * 1024 ? remaining : 64 * 1024);
        if (chunk.isEmpty) return buffer.takeBytes();
        if (chunk.length > limit - buffer.length) {
          throw StateError('Файл превышает лимит предпросмотра: ${file.path}');
        }
        buffer.add(chunk);
      }
    } finally {
      await reader.close();
    }
  }
}
