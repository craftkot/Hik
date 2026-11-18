import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'game_file.dart';
import 'safe_desktop_save.dart';

const int maxEditableBytes = 8 * 1024 * 1024;

abstract class GameStorage {
  Future<String?> chooseFolder();
  Future<List<GameFile>> scan(String folder);
  Future<Uint8List> read(GameFile file);
  Future<Uint8List> readPreview(GameFile file);
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected});
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
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected}) async {
    final backup = await _channel.invokeMethod<String>('writeWithBackup',
        <String, dynamic>{
          'uri': file.id, 'data': data, 'name': file.name,
          'expected': expected,
        });
    return backup ?? 'Резервная копия создана';
  }
}

class DesktopGameStorage implements GameStorage {
  DesktopGameStorage({SafeDesktopSaveWriter? writer})
      : _writer = writer ?? SafeDesktopSaveWriter();
  final SafeDesktopSaveWriter _writer;

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
        if (p.split(path).length > 14 ||
            p.basename(path).contains('.ehtid-')) continue;
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
    final source = File(file.id);
    // The size recorded during scanning can be stale if the game rewrites
    // the save. Read at most the editing limit plus one byte.
    final reader = await source.open();
    try {
      final bytes = await reader.read(maxEditableBytes + 1);
      if (bytes.length > maxEditableBytes) {
        throw StateError('Файл больше 8 МБ: отображение отключено');
      }
      return Uint8List.fromList(bytes);
    } finally {
      await reader.close();
    }
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
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected}) => _writer.write(
        File(file.id), data, expected: expected);

}
