import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Stages where tests may inject a storage failure.
/// Windows uses a recoverable two-rename sequence, not atomic replacement.
enum DesktopSaveCheckpoint {
  backupVerified,
  stageVerified,
  originalDisplaced,
  replacementInstalled,
}

class SafeDesktopSaveWriter {
  SafeDesktopSaveWriter({this.onCheckpoint});

  final FutureOr<void> Function(DesktopSaveCheckpoint)? onCheckpoint;
  bool _busy = false;
  static const int maxLength = 8 * 1024 * 1024;

  /// Restores only a backup created for this exact save path.
  /// The caller must show a preview and obtain explicit confirmation.
  /// [expectedCurrent] prevents overwriting a save modified after preview.
  /// The normal writer makes a new verified backup of the current save.
  Future<String> restoreBackup(
    File original,
    File backup, {
    required Uint8List expectedCurrent,
    required bool confirmed,
  }) async {
    if (!confirmed) throw StateError('Восстановление не подтверждено');
    if (!backup.path.startsWith('${original.path}.ehtid-backup-') ||
        !backup.path.endsWith('.bak')) {
      throw StateError('Резервная копия не относится к этому сейву');
    }
    if (await FileSystemEntity.type(backup.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Резервная копия отсутствует или является ссылкой');
    }
    if (await backup.length() > maxLength) {
      throw StateError('Резервная копия превышает лимит 8 МиБ');
    }
    final restored = await backup.readAsBytes();
    if (restored.length > maxLength) {
      throw StateError('Резервная копия превышает лимит 8 МиБ');
    }
    return write(original, restored, expected: expectedCurrent);
  }

  Future<String> write(
    File original,
    Uint8List replacement, {
    Uint8List? expected,
  }) async {
    if (_busy) throw StateError('Другая запись сейва ещё выполняется');
    if (replacement.length > maxLength) {
      throw StateError('Файл больше лимита безопасной записи (8 МиБ)');
    }
    if (await FileSystemEntity.type(original.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Исходный сейв отсутствует или является ссылкой');
    }

    _busy = true;
    final unique = '${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    final backup = File('${original.path}.ehtid-backup-$unique.bak');
    final pending = File('${original.path}.ehtid-pending-$unique.tmp');
    final displaced = File('${original.path}.ehtid-rollback-$unique.tmp');
    var originalDisplaced = false;
    Uint8List? before;
    try {
      before = await original.readAsBytes();
      if (before.length > maxLength) {
        throw StateError('Сейв на диске больше 8 МиБ');
      }
      if (expected != null && !_sameBytes(before, expected)) {
        throw StateError('Сейв изменился на диске. Открой его заново.');
      }
      if (_sameBytes(before, replacement)) {
        throw StateError('Новое значение совпадает со старым');
      }

      await original.copy(backup.path);
      if (!_sameBytes(await backup.readAsBytes(), before)) {
        throw StateError('Не удалось проверить резервную копию: ${backup.path}');
      }
      await _checkpoint(DesktopSaveCheckpoint.backupVerified);

      await pending.writeAsBytes(replacement, flush: true);
      if (!_sameBytes(await pending.readAsBytes(), replacement)) {
        throw StateError('Проверка подготовленного файла не прошла');
      }
      await _checkpoint(DesktopSaveCheckpoint.stageVerified);

      // Another edit during preparation must cancel the current edit.
      // This isn't a lock; close the game before editing save files.
      if (await FileSystemEntity.type(original.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !_sameBytes(await original.readAsBytes(), before)) {
        throw StateError('Игра изменила сейв перед записью — отменено');
      }

      // Windows can't reliably rename over a live destination. Displace,
      // install, verify and only then delete the displaced original.
      // If power fails between renames, a .ehtid-rollback-* copy survives.
      await original.rename(displaced.path);
      originalDisplaced = true;
      await _checkpoint(DesktopSaveCheckpoint.originalDisplaced);
      await pending.rename(original.path);
      await _checkpoint(DesktopSaveCheckpoint.replacementInstalled);
      if (!_sameBytes(await original.readAsBytes(), replacement)) {
        throw StateError('Прочитанные данные после записи не совпадают');
      }
      await displaced.delete();
      originalDisplaced = false;
      return backup.path;
    } catch (error) {
      if (originalDisplaced && await displaced.exists()) {
        try {
          if (await original.exists()) {
            // Never clobber an unrelated third-party write during rollback.
            final current = await original.readAsBytes();
            if (!_sameBytes(current, replacement)) {
              throw StateError('Содержимое файла изменилось повторно');
            }
            await original.delete();
          }
          await displaced.rename(original.path);
          if (before == null ||
              !_sameBytes(await original.readAsBytes(), before)) {
            throw StateError('Восстановленный сейв не прошёл проверку');
          }
        } catch (rollbackError) {
          throw StateError('Запись сорвалась: $error. '
              'Автовосстановление не удалось: $rollbackError. '
              'Исходник/откат: ${displaced.path}; '
              'резервная копия: ${backup.path}');
        }
      }
      rethrow;
    } finally {
      try {
        if (await pending.exists()) await pending.delete();
      } catch (_) {
        // Never mask a write/rollback failure with temporary-file cleanup.
      }
      _busy = false;
    }
  }

  Future<void> _checkpoint(DesktopSaveCheckpoint phase) async {
    if (onCheckpoint != null) await onCheckpoint!(phase);
  }

  static bool _sameBytes(Uint8List first, Uint8List second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }
}
