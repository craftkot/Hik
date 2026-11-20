import 'dart:io';
import 'dart:typed_data';

import 'safe_desktop_save.dart';

/// A checked preview belongs to one exact save and one exact EHTID backup.
/// Nothing is restored without a separate explicit confirmation.
class DesktopBackupPreview {
  const DesktopBackupPreview({
    required this.save,
    required this.backup,
    required this.currentBytes,
    required this.backupBytes,
  });

  final File save;
  final File backup;
  final Uint8List currentBytes;
  final Uint8List backupBytes;

  bool get differs {
    if (currentBytes.length != backupBytes.length) return true;
    for (var i = 0; i < currentBytes.length; i++) {
      if (currentBytes[i] != backupBytes[i]) return true;
    }
    return false;
  }
}

class DesktopBackupEntry {
  const DesktopBackupEntry(this.file, this.length, this.modified);

  final File file;
  final int length;
  final DateTime modified;
}

class DesktopSaveRecovery {
  DesktopSaveRecovery({SafeDesktopSaveWriter? writer})
      : _writer = writer ?? SafeDesktopSaveWriter();

  final SafeDesktopSaveWriter _writer;
  static const int maxBackups = 64;

  /// List only backups of this exact save, not similarly-named files.
  /// Read metadata only; bytes are loaded on explicit preview.
  Future<List<DesktopBackupEntry>> listBackups(File save) async {
    final prefix = '${save.uri.pathSegments.last}.ehtid-backup-';
    final result = <DesktopBackupEntry>[];
    await for (final entity in save.parent.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.bak')) continue;
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        // Directories and symlinks are not backups and must not count
        // toward the limit for actual recovery candidates.
        continue;
      }
      if (result.length >= maxBackups) {
        throw StateError('Найдено больше $maxBackups бэкапов. '
            'Перенеси старые копии в отдельную папку вручную.');
      }
      final backup = File(entity.path);
      final length = await backup.length();
      if (length > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Бэкап превышает лимит 8 МиБ: ${backup.path}');
      }
      result.add(DesktopBackupEntry(
          backup, length, await backup.lastModified()));
    }
    result.sort((a, b) {
      final byDate = b.modified.compareTo(a.modified);
      if (byDate != 0) return byDate;
      // Filesystems with coarse timestamps can give several backups the
      // same modification time. Keep the picker order deterministic.
      return b.file.path.compareTo(a.file.path);
    });
    return result;
  }

  Future<DesktopBackupPreview> preview(File save, File backup) async {
    if (!backup.path.startsWith('${save.path}.ehtid-backup-') ||
        !backup.path.endsWith('.bak')) {
      throw StateError('Этот бэкап не относится к выбранному сейву');
    }
    if (await FileSystemEntity.type(save.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(backup.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('Сейв или бэкап не найден либо является ссылкой');
    }
    return DesktopBackupPreview(
      save: save,
      backup: backup,
      currentBytes: await _readLimited(save),
      backupBytes: await _readLimited(backup),
    );
  }

  Future<String> restore(
    DesktopBackupPreview approved, {
    required bool confirmed,
  }) {
    // The writer rechecks current bytes and previewed backup bytes before
    // creating a new verified backup and applying any replacement.
    return _writer.restoreBackup(
        approved.save, approved.backup,
        expectedCurrent: approved.currentBytes,
        expectedBackup: approved.backupBytes,
        confirmed: confirmed);
  }

  static Future<Uint8List> _readLimited(File file) async {
    final reader = await file.open();
    try {
      final bytes = await reader.read(SafeDesktopSaveWriter.maxLength + 1);
      if (bytes.length > SafeDesktopSaveWriter.maxLength) {
        throw StateError('Файл превышает лимит 8 МиБ: ${file.path}');
      }
      return Uint8List.fromList(bytes);
    } finally {
      await reader.close();
    }
  }
}
