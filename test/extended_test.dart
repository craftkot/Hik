import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/archive_inspector.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/json_editor.dart';

void main() {
  test('JSON scalar tree and nested array editing', () {
    const source = '{"player":{"coins":25,"name":"Ana"},"inventory":[{"qty":3}],"enabled":true}';
    final fields = listJsonFields(source);
    expect(fields.map((f) => f.pointer), contains('/inventory/0/qty'));
    final edited = changeJsonField(source, '/player/coins', '200');
    expect(jsonDecode(edited)['player']['coins'], 200);
    expect(jsonDecode(edited)['player']['name'], 'Ana');
    final editedArray = changeJsonField(edited, '/inventory/0/qty', '7');
    expect(jsonDecode(editedArray)['inventory'][0]['qty'], 7);
    expect(() => changeJsonField(source, '/player/coins', '"200"'), throwsFormatException);
    expect(() => changeJsonField(source, '/player/notThere', '1'), throwsFormatException);
  });

  test('JSON pointers escape / and ~ correctly', () {
    const input = '{"a/b":{"x~y":"ok"}}';
    expect(listJsonFields(input).single.pointer, '/a~1b/x~0y');
    expect(jsonDecode(changeJsonField(input, '/a~1b/x~0y', '"new"'))['a/b']['x~y'], 'new');
  });

  test('ZIP recognised and safely previewed without writing to disk', () {
    final archive = Archive()..add(ArchiveFile.string('locales/en.json', '{"hi":"Hello"}'));
    final data = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    final viewer = ArchiveInspector.open(data);
    expect(viewer.entries, hasLength(1));
    expect(utf8.decode(viewer.read(viewer.entries.single)), '{"hi":"Hello"}');
    expect(identifyFile(data), 'ZIP-контейнер');
  });

  test('ZIP rejects suspicious and oversized entries', () {
    final archive = Archive()..add(ArchiveFile.string('../escape.txt', 'bad'));
    final data = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    expect(() => ArchiveInspector.open(data), throwsFormatException);
    final big = Archive()..add(ArchiveFile.bytes('a.bin', Uint8List(ArchiveInspector.maxEntry + 1)));
    final zipped = Uint8List.fromList(ZipEncoder().encodeBytes(big));
    final viewer = ArchiveInspector.open(zipped);
    expect(() => viewer.read(viewer.entries.single), throwsStateError);
  });

  test('file signatures avoid guessing proprietary encryption', () {
    expect(identifyFile(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47])), 'PNG');
    expect(identifyFile(Uint8List.fromList([0, 0, 0, 7])), 'Неизвестный бинарный формат');
  });
}
