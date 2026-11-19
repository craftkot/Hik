import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/binary_save_editor.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/gzip_save_codec.dart';

void main() {
  test('Recognizes GZIP by magic, not extension, and opens JSON text', () {
    final plain = Uint8List.fromList(utf8.encode('{"coins":100}'));
    final compressed = Uint8List.fromList(gzip.encode(plain));
    expect(GzipSaveCodec.isGzip(compressed), isTrue);
    expect(identifyFile(compressed), 'GZIP-сжатие');
    expect(utf8.decode(GzipSaveCodec.decode(compressed)), '{"coins":100}');
    expect(const GameFile(id: 'a', name: 'SaveData015.gz',
      relativePath: 'SaveData/jpg/SaveData015.gz', size: 300).isSave, isTrue);
  });

  test('Recompressing a numeric binary patch preserves unaffected bytes', () {
    final plain = Uint8List.fromList([0xaa, 100, 0, 0, 0, 0xbb, 0xcc]);
    final original = Uint8List.fromList(gzip.encode(plain));
    final expanded = GzipSaveCodec.decode(original);
    final hits = BinarySaveEditor.search(
        expanded, '100', SaveNumberFormat.int32Little);
    expect(hits.single.offset, 1);
    final changed = BinarySaveEditor.patch(expanded,
        offset: hits.single.offset, expected: '100', replacement: '999',
        format: SaveNumberFormat.int32Little);
    final repacked = GzipSaveCodec.encode(changed);
    expect(GzipSaveCodec.decode(repacked),
        [0xaa, 0xe7, 0x03, 0x00, 0x00, 0xbb, 0xcc]);
    expect(GzipSaveCodec.decode(original), plain,
        reason: 'The in-memory original must remain untouched');
    expect(GzipSaveCodec.isGzip(repacked), isTrue);
  });

  test('Bad GZIP CRC, truncated data and invalid header are rejected', () {
    final valid = Uint8List.fromList(gzip.encode(utf8.encode('hello')));
    final damaged = Uint8List.fromList(valid);
    damaged[damaged.length - 1] ^= 0xff;
    expect(() => GzipSaveCodec.decode(damaged), throwsFormatException);
    // CRC32 and ISIZE occupy separate four-byte fields in the GZIP trailer.
    // Check both independently so a future decoder cannot skip CRC validation.
    final badCrc = Uint8List.fromList(valid);
    badCrc[badCrc.length - 8] ^= 0x01;
    expect(() => GzipSaveCodec.decode(badCrc), throwsFormatException);
    final badSize = Uint8List.fromList(valid);
    badSize[badSize.length - 4] ^= 0x01;
    expect(() => GzipSaveCodec.decode(badSize), throwsFormatException);
    expect(() => GzipSaveCodec.decode(
        Uint8List.fromList(valid.sublist(0, 7))), throwsFormatException);
    expect(() => GzipSaveCodec.decode(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test('Expanded GZIP size limit defeats highly compressible bombs', () {
    final bomb = Uint8List.fromList(
        gzip.encode(Uint8List(GzipSaveCodec.maxBytes + 1)));
    expect(bomb.length, lessThan(GzipSaveCodec.maxBytes));
    expect(() => GzipSaveCodec.decode(bomb), throwsFormatException);
    expect(() => GzipSaveCodec.encode(
        Uint8List(GzipSaveCodec.maxBytes + 1)), throwsFormatException);
  });

  test('Unsupported non-GZIP bytes cannot be repacked implicitly', () {
    expect(GzipSaveCodec.isGzip(Uint8List.fromList([0x1f, 0x8b])), isFalse);
    expect(() => GzipSaveCodec.decode(Uint8List(0)), throwsFormatException);
  });
}
