import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'game_file.dart';

const int maxEditableBytes = 8 * 1024 * 1024;

abstract class GameStorage {
  Future<String?> chooseFolder();
  Future<List<GameFile>> scan(String folder);
  Future<Uint8List> read(GameFile file);
  Future<Uint8List> readPreview(GameFile file);
  Future<String> writeWithBackup(GameFile file, Uint8List data);
}

GameStorage createStorage() => Platform.isAndroid
    ? AndroidGameStorage() : DesktopGameStorage();

class AndroidGameStorage implements GameStorage {
  static const MethodChannel _channel =
      MethodChannel('ehtid.gamelab/storage');

  @override
  Future<String?> chooseFolder() => _channel.invokeMethod<String>('chooseFolder');

  @override
  Future<List<GameFile>> scan(String folder) async {
    final raw = await _channel.invokeListMethod<dynamic>('scanFolder',
        <String, dynamic>{'uri': folder});
    return (raw ?? []).map((entry) {
      final row = Map<Object?, Object?>.from(entry as Map);
      return GameFile(
        id: row['uri'] as String,
        name: row['name'] as String,
        relativePath: row['relativePath'] as String,
        size: (row['size'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  @override
  Future<Uint8List> read(GameFile file) async {
    final data = await _channel.invokeMethod<Uint8List>(
        'readDocument', <String, dynamic>{'uri': file.id});
    if (data == null) throw StateError('Пустой ответ от Android');
    return data;
  }

  @override
  Future<Uint8List> readPreview(GameFile file) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
        'readPrefix', <String, dynamic>{'uri': file.id});
    if (bytes == null) throw StateError('Не удалось получить начало файла');
    return bytes;
  }

  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data) async {
    final backup = await _channel.invokeMethod<String>('writeWithBackup',
        <String, dynamic>{'uri': file.id, 'data': data, 'name': file.name});
    return backup ?? 'Резервная копия создана';
  }
}

class DesktopGameStorage implements GameStorage {
  @override
  Future<String?> chooseFolder() => FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Выбери доступную папку игры',
  );

  @override
  Future<List<GameFile>> scan(String folder) async {
    final root = Directory(folder);
    if (!await root.exists()) throw FileSystemException('Папка недоступна', folder);
    final result = <GameFile>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (result.length >= 4000) break;
      if (entity is! File) continue;
      try {
        final path = p.relative(entity.path, from: folder);
        if (p.split(path).length > 14 || p.basename(path).startsWith('.ehtid-')) continue;
        final size = await entity.length();
        result.add(GameFile(
          id: entity.path,
          name: p.basename(entity.path),
          relativePath: path.replaceAll('\\', '/'),
          size: size,
        ));
      } on FileSystemException {
        // Some directories/files are inaccessible; keep scanning other files.
      }
    }
    return result;
  }

  @override
  Future<Uint8List> read(GameFile file) async {
    if (file.size > maxEditableBytes) {
      throw StateError('Файл больше 8 МБ: отображение отключено');
    }
    return File(file.id).readAsBytes();
  }

  @override
  Future<Uint8List> readPreview(GameFile file) async {
    final reader = await File(file.id).open();
    try {
      return Uint8List.fromList(await reader.read(4096));
    } finally {
      await reader.close();
    }
  }

  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data) async {
    if (data.length > maxEditableBytes) {
      throw StateError('Файл больше лимита безопасной записи');
    }
    final original = File(file.id);
    if (!await original.exists()) throw StateError('Исходный файл исчез');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final backup = '${file.id}.ehtid-backup-$stamp.bak';
    // Never truncate the live save: prepare and verify the replacement first.
    final temporary = File('${file.id}.ehtid-pending-$stamp.tmp');
    final displaced = File('${file.id}.ehtid-rollback-$stamp.tmp');
    await original.copy(backup); // Abort without touching original on failure.
    var movedOriginal = false;
    try {
      await temporary.writeAsBytes(data, flush: true);
      if (!_sameBytes(await temporary.readAsBytes(), data)) {
        throw StateError('Проверка временного файла не прошла');
      }
      // Moving the original aside also works on Windows, where rename cannot
      // reliably replace an existing destination. Keep it until verification.
      await original.rename(displaced.path);
      movedOriginal = true;
      await temporary.rename(original.path);
      if (!_sameBytes(await original.readAsBytes(), data)) {
        throw StateError('Проверка записи не прошла');
      }
      await displaced.delete();
      return backup;
    } catch (error) {
      if (movedOriginal) {
        // Restore the exact original, not the newly written bytes.
        try {
          if (await original.exists()) await original.delete();
          await displaced.rename(original.path);
        } catch (rollbackError) {
          throw StateError('Запись не удалась: $error. '
              'Автовосстановление не удалось: $rollbackError. '
              'Исходник сохранён в $displaced, резервная копия: $backup');
        }
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
