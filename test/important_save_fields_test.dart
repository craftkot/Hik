import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/gzip_save_codec.dart';
import 'package:game_lab/core/important_save_fields.dart';

void main() {
  test('Shows only named numeric game stats from JSON, in priority order', () {
    const source = '{"player":{"quest":42,"gold":100,'
        '"hp":120,"mana":30,"strength":17,"level":5,'
        '"name":"gold","shopTitle":"hp","energy":60}}';
    final fields = ImportantSaveInspector.inspectText(source);
    expect(fields.map((f) => f.name), [
      '/player/gold', '/player/hp', '/player/mana',
      '/player/strength', '/player/level', '/player/energy',
    ]);
    expect(fields.every((f) => f.source == ImportantFieldSource.json), isTrue);
  });

  test('Recognizes compressed INI fields, leaving other lines out', () {
    const ini = '; comment\r\n[Player]\r\nname=Akane\r\n'
        'quest=42\r\nhp=120\r\ngold=800\r\nmp=40\r\n';
    final gz = Uint8List.fromList(gzip.encode(utf8.encode(ini)));
    final expanded = GzipSaveCodec.decode(gz);
    final fields = ImportantSaveInspector.inspectText(utf8.decode(expanded));
    expect(fields.map((f) => f.name),
        ['Player / gold', 'Player / hp', 'Player / mp']);
    expect(fields.map((f) => f.value), ['800', '120', '40']);
  });

  test('Fixed-width binary key patch preserves every other byte in GZIP', () {
    final payload = Uint8List.fromList([
      0, 0xff, 0xa1, ...ascii.encode('gold=120'), 0,
      0xe2, ...ascii.encode('hp:055'), 0, 0x93,
    ]);
    final gz = GzipSaveCodec.encode(payload);
    final expanded = GzipSaveCodec.decode(gz);
    final fields = ImportantSaveInspector.inspectBinary(expanded);
    expect(fields.map((f) => f.name), ['gold', 'hp']);
    expect(fields.map((f) => f.value), ['120', '055']);
    final oldGold = fields.first.embedded!;
    final updated = ImportantSaveInspector.patchEmbedded(
        expanded, oldGold, '999');
    expect(updated.length, expanded.length);
    var changes = 0;
    for (var i = 0; i < expanded.length; i++) {
      if (expanded[i] != updated[i]) changes++;
    }
    expect(changes, 3);
    expect(latin1.decode(updated), contains('gold=999'));
    expect(latin1.decode(updated), contains('hp:055'));
    final saved = GzipSaveCodec.encode(updated);
    expect(GzipSaveCodec.decode(saved), updated);
    expect(GzipSaveCodec.decode(gz), payload);
  });

  test('Rejects length changes and stale binary field edits', () {
    final data = Uint8List.fromList([0xff, ...ascii.encode('hp=100'), 0]);
    final field = ImportantSaveInspector.inspectBinary(data).single.embedded!;
    expect(() => ImportantSaveInspector.patchEmbedded(data, field, '2000'),
        throwsFormatException);
    expect(() => ImportantSaveInspector.patchEmbedded(data, field, '9.5'),
        throwsFormatException);
    final changed = Uint8List.fromList(data)..[field.offset] = 0x39;
    expect(() => ImportantSaveInspector.patchEmbedded(changed, field, '777'),
        throwsStateError);
  });

  test('Does not invent named values from opaque data and random numbers', () {
    final unknown = Uint8List.fromList([
      0x11, 0x09, 0x00, 0x01, 0x02,
      120, 0, 0, 0, 0xff, 0x93, 0x81,
    ]);
    expect(ImportantSaveInspector.inspectBinary(unknown), isEmpty);
    expect(ImportantSaveInspector.inspectBinary(Uint8List(0)), isEmpty);
    expect(ImportantSaveInspector.inspectText('HP is strong, quest 42'), isEmpty);
  });
}
