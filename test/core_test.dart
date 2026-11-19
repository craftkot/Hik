import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';

void main() {
  test('save file recognised by extension', () {
    const file = GameFile(id: '1', name: 'slot1.sav',
        relativePath: 'Saves/slot1.sav', size: 4);
    expect(file.isSave, isTrue);
    expect(file.isLocalization, isFalse);
  });

  test('localization path takes precedence in UI filtering', () {
    const file = GameFile(id: '2', name: 'ru.json',
        relativePath: 'assets/locales/ru.json', size: 4);
    expect(file.isLocalization, isTrue);
    expect(file.isJson, isTrue);
  });

  test('recognizes plausible INI saves but never arbitrary settings', () {
    const file = GameFile(id: 'save', name: 'playerStats.ini',
        relativePath: 'Game/playerStats.ini', size: 400);
    const save = GameFile(id: 'slot', name: 'slot1.cfg',
        relativePath: 'Game/slot1.cfg', size: 400);
    const config = GameFile(id: 'config', name: 'player.ini',
        relativePath: 'Game/config/player.ini', size: 400);
    const settings = GameFile(id: 'settings', name: 'settings.ini',
        relativePath: 'Game/settings.ini', size: 400);
    expect(file.isStructuredIniSaveCandidate, isTrue);
    expect(save.isStructuredIniSaveCandidate, isTrue);
    expect(config.isStructuredIniSaveCandidate, isFalse);
    expect(settings.isStructuredIniSaveCandidate, isFalse);
    expect(const GameFile(id: 'other', name: 'savegame.json',
        relativePath: 'Game/savegame.json', size: 5)
        .isStructuredIniSaveCandidate, isFalse);
  });

  test('UTF-8 valid editable, binary invalid and non-lossy', () {
    expect(decodeEditableText(Uint8List.fromList(utf8.encode('{"hp":12}'))),
        '{"hp":12}');
    expect(decodeEditableText(Uint8List.fromList([0, 1, 255])), isNull);
    expect(decodeEditableText(Uint8List.fromList([0xC3, 0x28])), isNull);
  });

  test('hex view shows bytes', () {
    final preview = hexPreview(Uint8List.fromList([0x41, 0x00, 0x42]));
    expect(preview, contains('41 00 42'));
    expect(preview, contains('A.B'));
  });
}
