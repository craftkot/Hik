import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_save_discovery.dart';
import 'package:path/path.dart' as p;

void main() {
  test('known Windows save roots from environment variables', () {
    final paths = WindowsSaveDiscovery.knownWindowsRoots({
      'APPDATA': p.join('test', 'Roaming'),
      'LOCALAPPDATA': p.join('test', 'Local'),
      'USERPROFILE': p.join('test', 'Home'),
    });
    expect(paths, contains(p.join('test', 'Home', 'Saved Games')));
    expect(paths, contains(p.join('test', 'Home',
        'Documents', 'My Games')));
    expect(paths, contains(p.join('test', 'Home',
        'AppData', 'LocalLow')));
    expect(paths, hasLength(6));
  });

  test('Windows path heuristics find game title above Binaries/Win64', () {
    expect(
      WindowsSaveDiscovery.suggestedGameNameFromPath(
          r'C:\\Games\\Sample Game\\Binaries\\Win64'),
      'Sample Game',
    );
    expect(
      WindowsSaveDiscovery.suggestedGameNameFromPath(
          r'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Stardew Valley'),
      'Stardew Valley',
    );
    expect(
      WindowsSaveDiscovery.suggestedGameNameFromPath(
          r'C:\\Program Files (x86)\\Steam\\steamapps\\common'),
      isEmpty,
    );
  });

  test('matching requires exact title or a safe saves suffix', () {
    expect(WindowsSaveDiscovery.matchesGameDirectory(
        'StardewValley SaveData', 'Stardew Valley'), isTrue);
    expect(WindowsSaveDiscovery.matchesGameDirectory(
        'Stardew Valley Saves', 'Stardew Valley'), isTrue);
    expect(WindowsSaveDiscovery.matchesGameDirectory(
        'Other Stardew Valley', 'Stardew Valley'), isFalse);
    expect(WindowsSaveDiscovery.matchesGameDirectory(
        'Stardew Valley Modding Tools', 'Stardew Valley'), isFalse);
  });

  test('onedrive documents are included and duplicate roots removed', () {
    final roots = WindowsSaveDiscovery.knownWindowsRoots({
      'USERPROFILE': r'C:\\Users\\Test',
      'APPDATA': r'C:\\Users\\Test\\AppData\\Roaming',
      'LOCALAPPDATA': r'C:\\Users\\Test\\AppData\\Local',
      'OneDrive': r'C:\\Users\\Test\\OneDrive',
      'OneDriveConsumer': r'C:\\Users\\Test\\OneDrive',
    });
    expect(roots, hasLength(8));
    expect(roots, contains(p.join(
        r'C:\\Users\\Test\\OneDrive', 'Documents', 'My Games')));
  });

  test('company subfolders in Roaming are searched one level deep', () async {
    final temp = await Directory.systemTemp.createTemp('ehtid_studios_');
    try {
      final roaming = Directory(p.join(temp.path, 'Roaming'));
      final named = Directory(p.join(
          roaming.path, 'Game Studio', 'Stardew Valley Saves'));
      final unrelated = Directory(p.join(
          roaming.path, 'Unrelated Studio', 'Other Game'));
      await named.create(recursive: true);
      await unrelated.create(recursive: true);
      final matches = await WindowsSaveDiscovery.discoverUnderRoots(
        gameName: 'Stardew Valley',
        rootDirectories: [roaming.path],
      );
      expect(matches, [named.path]);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('only finds game-named directories within scoped roots', () async {
    final temp = await Directory.systemTemp.createTemp('ehtid_roots_');
    try {
      final roaming = Directory(p.join(temp.path, 'Roaming'));
      final localLow = Directory(p.join(temp.path, 'LocalLow'));
      final savedGames = Directory(p.join(temp.path, 'Saved Games'));
      await Directory(p.join(roaming.path, 'Sample Game'))
          .create(recursive: true);
      await Directory(p.join(roaming.path, 'Other Game'))
          .create(recursive: true);
      await Directory(p.join(localLow.path, 'SomeStudio', 'SampleGame'))
          .create(recursive: true);
      await Directory(p.join(localLow.path, 'OtherStudio', 'SomeOtherGame'))
          .create(recursive: true);
      await Directory(p.join(savedGames.path, 'Sample_Game'))
          .create(recursive: true);

      final matches = await WindowsSaveDiscovery.discoverUnderRoots(
        gameName: 'Sample Game',
        rootDirectories: [roaming.path, localLow.path, savedGames.path],
      );
      expect(matches, hasLength(3));
      expect(matches, contains(p.join(roaming.path, 'Sample Game')));
      expect(matches, contains(p.join(localLow.path, 'SomeStudio', 'SampleGame')));
      expect(matches, contains(p.join(savedGames.path, 'Sample_Game')));
      expect(matches, isNot(contains(p.join(roaming.path, 'Other Game'))));
      expect(await WindowsSaveDiscovery.discoverUnderRoots(
        gameName: 'Games',
        rootDirectories: [roaming.path],
      ), isEmpty);
      expect(await WindowsSaveDiscovery.discoverUnderRoots(
        gameName: 'Sample Game',
        rootDirectories: [roaming.path, localLow.path, savedGames.path],
        maxMatches: 2,
      ), hasLength(2));
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
