import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_game_catalog.dart';
import 'package:path/path.dart' as p;

void main() {
  test('discovers installed games in default and additional Steam libraries',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('gamelab_steam_');
    addTearDown(() => sandbox.delete(recursive: true));

    final steam = Directory(p.join(sandbox.path, 'Steam'));
    final secondary = Directory(p.join(sandbox.path, 'Library'));
    await Directory(p.join(steam.path, 'steamapps', 'common', 'Alpha'))
        .create(recursive: true);
    await Directory(p.join(secondary.path, 'steamapps', 'common', 'Beta'))
        .create(recursive: true);
    await File(p.join(steam.path, 'steamapps', 'libraryfolders.vdf'))
        .writeAsString('"libraryfolders" { "1" { "path" "${secondary.path}" } }');
    await File(p.join(steam.path, 'steamapps', 'appmanifest_10.acf'))
        .writeAsString('"AppState" { "name" "Alpha Game" "installdir" "Alpha" }');
    await File(p.join(secondary.path, 'steamapps', 'appmanifest_11.acf'))
        .writeAsString('"AppState" { "name" "Beta Game" "installdir" "Beta" }');

    final games = await WindowsGameCatalog.discoverUnderRoots([steam.path]);
    expect(games.map((g) => g.name), ['Alpha Game', 'Beta Game']);
    expect(games.every((g) => g.source == 'Steam'), isTrue);
  });

  test('ignores nonexistent, unsafe, and oversized entries', () async {
    final root = await Directory.systemTemp.createTemp('gamelab_steam_safety_');
    addTearDown(() => root.delete(recursive: true));
    final apps = Directory(p.join(root.path, 'steamapps'));
    await apps.create(recursive: true);
    await File(p.join(apps.path, 'appmanifest_1.acf'))
        .writeAsString('"name" "Bad" "installdir" "../outside"');
    await File(p.join(apps.path, 'appmanifest_2.acf'))
        .writeAsString('"name" "Missing" "installdir" "NoGame"');
    await File(p.join(apps.path, 'appmanifest_3.acf'))
        .writeAsString(List.filled(100000, 'bad').join());
    final games = await WindowsGameCatalog.discoverUnderRoots([root.path]);
    expect(games, isEmpty);
  });

  test('validates game enumeration bound', () async {
    expect(
      () => WindowsGameCatalog.discoverUnderRoots(const [], maxGames: 0),
      throwsRangeError,
    );
  });
}
