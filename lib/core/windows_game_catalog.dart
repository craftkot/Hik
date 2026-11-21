import 'dart:io';

import 'package:path/path.dart' as p;

/// A locally installed Steam game. Discovery never reads or modifies its files.
class DesktopGameEntry {
  const DesktopGameEntry({
    required this.name,
    required this.folder,
    required this.source,
  });

  final String name;
  final String folder;
  final String source;
}

/// Bounded, read-only discovery of Steam's installed-game manifests.
/// No registry access, privilege elevation, or full-disk scans.
class WindowsGameCatalog {
  const WindowsGameCatalog._();

  static Future<List<DesktopGameEntry>> discover() async {
    if (!Platform.isWindows) return const [];
    final env = Platform.environment;
    final roots = <String>{
      if ((env['STEAM_PATH'] ?? '').isNotEmpty) env['STEAM_PATH']!,
      for (final home in [
        env['ProgramFiles(x86)'],
        env['PROGRAMFILES(X86)'],
        env['ProgramFiles'],
        env['PROGRAMFILES'],
      ])
        if (home != null && home.isNotEmpty) p.join(home, 'Steam'),
      if ((env['LOCALAPPDATA'] ?? '').isNotEmpty)
        p.join(env['LOCALAPPDATA']!, 'Steam'),
    };
    return discoverUnderRoots(roots);
  }

  /// Public seam for testing with synthetic Steam directories on any OS.
  static Future<List<DesktopGameEntry>> discoverUnderRoots(
    Iterable<String> steamRoots, {int maxGames = 400}) async {
    if (maxGames < 1 || maxGames > 1000) {
      throw RangeError.range(maxGames, 1, 1000, 'maxGames');
    }
    final libraries = <String>{};
    final seenLibraries = <String>{};

    void addLibrary(String value) {
      if (value.isEmpty) return;
      final normalized = p.normalize(value);
      if (seenLibraries.add(normalized.toLowerCase())) libraries.add(normalized);
    }

    for (final root in steamRoots.take(10)) {
      final steamApps = Directory(p.join(root, 'steamapps'));
      if (!await steamApps.exists()) continue;
      addLibrary(root);
      final index = File(p.join(steamApps.path, 'libraryfolders.vdf'));
      try {
        if (!await index.exists() || await index.length() > 512 * 1024) {
          continue;
        }
        final text = await index.readAsString();
        // New Steam VDF format has nested "path" keys.
        final modern = RegExp(r'"path"\s*"([^"]+)"', caseSensitive: false);
        // Older clients use numbered keys with a library path value.
        final legacy = RegExp(r'"[0-9]+"\s*"([^"]+)"');
        for (final match in [...modern.allMatches(text), ...legacy.allMatches(text)]) {
          final raw = match.group(1)!.replaceAll(String.fromCharCodes([92, 92]), String.fromCharCode(92)).trim();
          if (p.isAbsolute(raw)) addLibrary(raw);
        }
      } on FileSystemException {
        // An inaccessible manifest does not stop other libraries.
      }
    }

    final games = <DesktopGameEntry>[];
    final seenGamePaths = <String>{};
    for (final library in libraries.take(30)) {
      if (games.length >= maxGames) break;
      final apps = Directory(p.join(library, 'steamapps'));
      try {
        if (!await apps.exists()) continue;
        var checked = 0;
        await for (final entity in apps.list(followLinks: false)) {
          if (++checked > 2500 || games.length >= maxGames) break;
          if (entity is! File) continue;
          if (!RegExp(r'^appmanifest_[0-9]+\.acf$', caseSensitive: false)
              .hasMatch(p.basename(entity.path))) continue;
          if (await entity.length() > 256 * 1024) continue;
          final content = await entity.readAsString();
          final name = RegExp(r'"name"\s*"([^"]+)"', caseSensitive: false)
              .firstMatch(content)?.group(1)?.trim();
          final directory = RegExp(r'"installdir"\s*"([^"]+)"',
              caseSensitive: false).firstMatch(content)?.group(1)?.trim();
          if (directory == null || directory.isEmpty ||
              directory == '.' || directory == '..' ||
              RegExp(r'[\\/:]').hasMatch(directory)) continue;
          final folder = p.normalize(p.join(apps.path, 'common', directory));
          if (!p.isWithin(p.join(apps.path, 'common'), folder)) continue;
          if (!await Directory(folder).exists()) continue;
          if (!seenGamePaths.add(folder.toLowerCase())) continue;
          games.add(DesktopGameEntry(
            name: name == null || name.isEmpty ? directory : name,
            folder: folder, source: 'Steam'));
        }
      } on FileSystemException {
        // Ignore inaccessible libraries and continue with the rest.
      }
    }
    games.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return games;
  }
}
