import 'dart:io';

import 'package:path/path.dart' as p;

/// Discovers *directory names* related to a selected game on Windows.
/// It does not read personal files or grant access to protected applications.
class WindowsSaveDiscovery {
  const WindowsSaveDiscovery._();

  static String normalizedGameName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-zа-яё0-9]'), '');

  /// Remove generic installation subfolders when a game is installed as
  /// GameName/Binaries/Win64. Never guess a name from generic directories.
  /// Uses the Windows path grammar even when tested on another OS.
  static String suggestedGameNameFromPath(String gameFolder) {
    final segments = p.windows.split(p.windows.normalize(gameFolder))
        .where((segment) => segment.isNotEmpty).toList().reversed;
    const ignored = <String>{
      'bin', 'binaries', 'win64', 'win32', 'windows', 'x64', 'x86',
      'shipping', 'release', 'debug', 'build', 'common', 'steamapps',
      'steam', 'games', 'game', 'data', 'client', 'engine',
      'windowsnoeditor', 'windowsclient', 'win64shipping',
      'programfiles', 'programfilesx86',
    };
    for (final segment in segments) {
      final candidate = segment.toLowerCase().endsWith('.exe')
          ? segment.substring(0, segment.length - 4) : segment;
      final normalized = normalizedGameName(candidate);
      if (normalized.length >= 3 && !ignored.contains(normalized) &&
          !RegExp(r'^[a-z]:
  /// Only these locations are inspected, never an entire disk.
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

  /// A user can search *without* choosing the game's install directory first.
  /// Restrict inspection to standard save roots of the current Windows user.
  static Future<List<String>> discoverByName(String gameName) async {
    if (!Platform.isWindows) return [];
    return discoverUnderRoots(
      gameName: gameName,
      rootDirectories: knownWindowsRoots(Platform.environment),
    );
  }

  static bool matchesGameDirectory(String directory, String gameName) {
    final key = normalizedGameName(gameName);
    if (key.length < 3) return false;
    final candidate = normalizedGameName(directory);
    if (candidate == key) return true;
    // Common named containers: MyGame Saves / MyGame SaveData.
    // Strict suffix matching avoids unrelated substring matches.
    for (final suffix in ['saves', 'savedgames', 'savedata']) {
      if (candidate == '$key$suffix') return true;
    }
    return false;
  }

  /// Public for testing with temporary folders on all platforms.
  ///
  /// Checks direct children under each known root. LocalLow also checks
  /// a second level for the common CompanyName/GameName Unity layout.
  static Future<List<String>> discoverUnderRoots({
    required String gameName,
    required Iterable<String> rootDirectories,
    int maxMatches = 10,
  }) async {
    final target = normalizedGameName(gameName);
    if (target.length < 3 ||
        const <String>{'game', 'games', 'steam', 'common', 'bin',
          'binaries', 'userdata', 'saved', 'saves', 'data',
          'windows', 'programfiles', 'x86'}.contains(target)) {
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
            // LocalLow: Unity developers usually keep GameName inside
            // a company folder. Never recurse beyond the next level.
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
              // Inaccessible developer folder; continue elsewhere.
            }
          }
        }
      } on FileSystemException {
        // Some user folders may be inaccessible.
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
).hasMatch(candidate.toLowerCase())) {
        return candidate;
      }
    }
    return '';
  }

  /// Candidate base directories for the signed-in Windows user.
  /// Only these locations are inspected, never an entire disk.
  static List<String> knownWindowsRoots(Map<String, String> env) {
    final home = env['USERPROFILE'];
    final roaming = env['APPDATA'];
    final local = env['LOCALAPPDATA'];
    return [
      if (roaming != null && roaming.isNotEmpty) roaming,
      if (local != null && local.isNotEmpty) local,
      if (home != null && home.isNotEmpty) ...[
        p.join(home, 'AppData', 'LocalLow'),
        p.join(home, 'Saved Games'),
        p.join(home, 'Documents', 'My Games'),
        p.join(home, 'Documents'),
      ],
    ];
  }

  static Future<List<String>> discoverForGame(
      String selectedGameFolder) async {
    if (!Platform.isWindows) return [];
    return discoverUnderRoots(
      gameName: p.basename(p.normalize(selectedGameFolder)),
      rootDirectories: knownWindowsRoots(Platform.environment),
    );
  }

  /// Public for testing with temporary folders on all platforms.
  ///
  /// Checks direct children under each known root. LocalLow also checks
  /// a second level for the common CompanyName/GameName Unity layout.
  static Future<List<String>> discoverUnderRoots({
    required String gameName,
    required Iterable<String> rootDirectories,
    int maxMatches = 10,
  }) async {
    final target = normalizedGameName(gameName);
    if (target.length < 3 ||
        const <String>{'game', 'games', 'steam', 'common', 'bin',
          'binaries', 'userdata', 'saved', 'saves', 'data',
          'windows', 'programfiles', 'x86'}.contains(target)) {
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
          final name = normalizedGameName(p.basename(item.path));
          if (name == target) {
            await add(item.path);
          } else if (includeNested) {
            // LocalLow: Unity developers usually keep GameName inside
            // a company folder. Never recurse beyond the next level.
            var nested = 0;
            try {
              await for (final child in item.list(followLinks: false)) {
                if (++nested > 150 || result.length >= maxMatches) break;
                if (child is Directory &&
                    normalizedGameName(p.basename(child.path)) == target) {
                  await add(child.path);
                }
              }
            } on FileSystemException {
              // Inaccessible developer folder; continue elsewhere.
            }
          }
        }
      } on FileSystemException {
        // Some user folders may be inaccessible.
      }
    }

    for (final root in rootDirectories) {
      if (result.length >= maxMatches) break;
      await walkOneLevel(Directory(root),
        includeNested: p.basename(root).toLowerCase() == 'locallow');
    }
    return result;
  }
}
