import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'android_app_save_discovery.dart';
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

class AndroidAllFilesAccessStatus {
  const AndroidAllFilesAccessStatus({
    required this.supported,
    required this.granted,
    required this.sdk,
  });

  final bool supported;
  final bool granted;
  final int sdk;
}

class AndroidGameStorage implements GameStorage {
  static const MethodChannel _channel =
      MethodChannel('ehtid.gamelab/storage');

  @override
  Future<String?> chooseFolder() => _channel.invokeMethod<String>('chooseFolder');

  /// Android 11+: special all-files access must be granted explicitly in
  /// Settings; Android 10 and older continue using the SAF picker.
  Future<AndroidAllFilesAccessStatus> allFilesAccessStatus() async {
    final response = await _channel.invokeMapMethod<String, dynamic>(
        'allFilesAccessStatus');
    return AndroidAllFilesAccessStatus(
      supported: response?['supported'] == true,
      granted: response?['granted'] == true,
      sdk: (response?['sdk'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> requestAllFilesAccess() async =>
      await _channel.invokeMethod<String>('requestAllFilesAccess') ??
          'unsupported';

  /// Only launcher-visible installed apps are listed; no broad package access.
  Future<List<InstalledGameApp>> listInstalledApps() async {
    final rows = await _channel.invokeListMethod<dynamic>('listInstalledApps');
    return (rows ?? []).map((entry) {
      final row = Map<Object?, Object?>.from(entry as Map);
      return InstalledGameApp(
        packageName: row['package'] as String,
        label: row['label'] as String,
        isGame: row['isGame'] == true,
      );
    }).toList();
  }

  Future<List<String>> approvedFolders() async =>
      await _channel.invokeListMethod<String>('grantedFolders') ?? [];

  /// One-time, explicit user-granted association survives app restarts.
  Future<void> linkFolderToApp(InstalledGameApp app, String treeUri) async {
    await _channel.invokeMethod<void>('linkGameFolder', {
      'package': app.packageName, 'uri': treeUri,
    });
  }

  Future<List<String>> _linkedFolders(InstalledGameApp app) async =>
      await _channel.invokeListMethod<String>('linkedGameFolders', {
        'package': app.packageName,
      }) ?? [];

  @override
  Future<List<GameFile>> scan(String folder) async {
    if (Uri.tryParse(folder)?.scheme == 'ehtid-app') {
      return discoverAppFiles(InstalledGameApp.fromVirtualFolder(folder));
    }
    return _scanTree(folder);
  }

  Future<List<GameFile>> discoverAppFiles(InstalledGameApp app) async {
    final roots = await approvedFolders();
    if (roots.isEmpty) return [];
    final linked = (await _linkedFolders(app)).toSet();
    final files = <String, GameFile>{};
    // Never request a new permission or read private app data.
    // The user can explicitly associate a granted game directory with a
    // package, even if its directory name has no obvious game identifier.
    for (final root in roots.take(12)) {
      try {
        final rows = await _scanTree(root);
        for (final file in rows) {
          if (linked.contains(root) || AndroidAppSaveDiscovery.matches(
              app: app, treeUri: root, relativePath: file.relativePath)) {
            files.putIfAbsent(file.id, () => file);
          }
        }
      } catch (_) {
        // The user may have revoked a permission or unmounted a provider.
      }
    }
    return files.values.toList();
  }

  Future<List<GameFile>> _scanTree(String folder) async {
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
