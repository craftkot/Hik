import 'dart:io';

import 'package:path/path.dart' as p;

/// Find *folder names* matching a user-chosen game inside standard Windows
/// save locations. Never scan the whole disk or bypass ACLs.
class WindowsSaveDiscovery {
  const WindowsSaveDiscovery._();

  static String normalizedGameName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), '');

  /// For a selected install folder like MyGame/Binaries/Win64, propose
  /// MyGame instead of generic Win64. Uses Windows path grammar on all OSes.
  static String suggestedGameNameFromPath(String gameFolder) {
    final segments = p.windows.split(p.windows.normalize(gameFolder)).reversed;
    const ignored = <String>{
      'bin', 'binaries', 'win64', 'win32', 'windows', 'x64', 'x86',
      'shipping', 'release', 'debug', 'build', 'common', 'steamapps',
      'steam', 'games', 'game', 'data', 'client', 'engine',
      'windowsnoeditor', 'windowsclient', 'win64shipping',
      'programfiles', 'programfilesx86',
    };
    for (final segment in segments) {
      if (segment.isEmpty) continue;
      final candidate = segment.toLowerCase().endsWith('.exe')
          ? segment.substring(0, segment.length - 4) : segment;
      final normalized = normalizedGameName(candidate);
      if (normalized.length >= 3 && !ignored.contains(normalized)) {
        return candidate;
      }
    }
    return '';
  }

  /// Only per-user save roots, never arbitrary program folders or drives.
  static List<String> knownWindowsRoots(Map<String, String> env) {
    final home = env['USERPROFILE'];
    final roaming = env['APPDATA'];
    final local = env['LOCALAPPDATA'];
    final roots = <String>[
      if (roaming != null && roaming.isNotEmpty) roaming,
      if (local != null && local.isNotEmpty) local,
      if (home != null && home.isNotEmpty) ...[
        p.join(home, 'AppData', 'LocalLow'),
        p.join(home, 'Saved Games'),
        p.join(home, 'Documents', 'My Games'),
        p.join(home, 'Documents'),
      ],
      for (final cloud in [env['OneDrive'], env['OneDriveConsumer']])
        if (cloud != null && cloud.trim().isNotEmpty) ...[
          p.join(cloud, 'Documents', 'My Games'),
          p.join(cloud, 'Documents'),
        ],
    ];
    final seen = <String>{};
    return roots.where((root) =>
        seen.add(p.windows.normalize(root).toLowerCase())).toList();
  }

  static Future<List<String>> discoverForGame(
      String selectedGameFolder) async =>
      discoverByName(suggestedGameNameFromPath(selectedGameFolder));

  /// Search by typed game name without requiring the installation path.
  static Future<List<String>> discoverByName(String gameName) async {
    if (!Platform.isWindows) return [];
    return discoverUnderRoots(
      gameName: gameName,
      rootDirectories: knownWindowsRoots(Platform.environment),
    );
  }

  /// Only exact names or documented "SaveData"/"Saves" suffixes.
  static bool matchesGameDirectory(String directory, String gameName) {
    final key = normalizedGameName(gameName);
    if (key.length < 3) return false;
    final candidate = normalizedGameName(directory);
    if (candidate == key) return true;
    for (final suffix in ['saves', 'savedgames', 'savedata']) {
      if (candidate == key + suffix) return true;
    }
    return false;
  }

  /// For integration tests, root paths are injected and traversal is bounded.
  /// Direct children are checked for every root. AppData Local, Roaming and
  /// LocalLow also inspect a single company/developer subfolder level.
  static Future<List<String>> discoverUnderRoots({
    required String gameName,
    required Iterable<String> rootDirectories,
    int maxMatches = 10,
  }) async {
    final target = normalizedGameName(gameName);
    if (target.length < 3 ||
        const <String>{
          'game', 'games', 'steam', 'common', 'bin', 'binaries',
          'userdata', 'saved', 'saves', 'data', 'windows',
          'programfiles', 'x86',
        }.contains(target)) {
      return const [];
    }
    if (maxMatches < 1 || maxMatches > 50) {
      throw RangeError('Invalid save-discovery result limit');
    }

    final result = <String>[];
    final seen = <String>{};

    Future<void> add(String path) async {
      final normalized = p.normalize(path).toLowerCase();
      if (seen.add(normalized) &&
          await Directory(path).exists() &&
          result.length < maxMatches) {
        result.add(path);
      }
    }

    Future<void> walkOneLevel(Directory root,
        {required bool includeNested}) async {
      if (!await root.exists() || result.length >= maxMatches) return;
      try {
        var count = 0;
        await for (final item in root.list(followLinks: false)) {
          if (++count > 800 || result.length >= maxMatches) break;
          if (item is! Directory) continue;
          if (matchesGameDirectory(p.basename(item.path), gameName)) {
            await add(item.path);
          } else if (includeNested) {
            var nested = 0;
            try {
              await for (final child in item.list(followLinks: false)) {
                if (++nested > 150 || result.length >= maxMatches) break;
                if (child is Directory &&
                    matchesGameDirectory(p.basename(child.path), gameName)) {
                  await add(child.path);
                }
              }
            } on FileSystemException {
              // A developer folder may be inaccessible; keep searching.
            }
          }
        }
      } on FileSystemException {
        // Inaccessible root; still inspect other permitted roots.
      }
    }

    for (final root in rootDirectories) {
      if (result.length >= maxMatches) break;
      await walkOneLevel(Directory(root),
        includeNested: <String>{'locallow', 'local', 'roaming'}
            .contains(p.basename(root).toLowerCase()));
    }
    return result;
  }
}
