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
