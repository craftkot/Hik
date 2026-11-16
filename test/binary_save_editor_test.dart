import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/binary_save_editor.dart';

void main() {
  test('Int32 LE: scan, edit a selected offset, preserve every other byte', () {
    final original = Uint8List.fromList([
      0xaa, 0xbb, 0x64, 0x00, 0x00, 0x00, 0xcc,
      0x64, 0x00, 0x00, 0x00, 0xdd,
    ]);
    final hits = BinarySaveEditor.search(
        original, '100', SaveNumberFormat.int32Little);
    expect(hits.map((h) => h.offset).toList(), [2, 7]);
    expect(hits.first.hexOffset, '0x00000002');

    final patched = BinarySaveEditor.patch(
      original,
      offset: 7,
      expected: '100',
      replacement: '999',
      format: SaveNumberFormat.int32Little,
    );
    expect(original[7], 0x64, reason: 'Original data must remain untouched');
    expect(patched.sublist(2, 6), [0x64, 0, 0, 0]);
    expect(patched.sublist(7, 11), [0xe7, 0x03, 0, 0]);
    expect(patched.length, original.length);
    expect(patched[11], 0xdd);
  });

  test('Int32 BE and negative signed values', () {
    final bytes = Uint8List.fromList([0xfe, 0xff, 0xff, 0xff, 0xf9]);
    expect(BinarySaveEditor.search(
        bytes, '-7', SaveNumberFormat.int32Big), isEmpty);
    expect(BinarySaveEditor.search(
        bytes, '-7', SaveNumberFormat.int32Little).single.offset, 1);
    expect(BinarySaveEditor.encode(
        '-7', SaveNumberFormat.int32Big), [0xff, 0xff, 0xff, 0xf9]);
  });

  test('Float32 supports both endiannesses', () {
    expect(BinarySaveEditor.encode('1.5', SaveNumberFormat.float32Little),
        [0, 0, 0xc0, 0x3f]);
    expect(BinarySaveEditor.encode('1.5', SaveNumberFormat.float32Big),
        [0x3f, 0xc0, 0, 0]);
    final data = Uint8List.fromList([0, 0x3f, 0xc0, 0, 0, 0xff]);
    expect(BinarySaveEditor.search(
        data, '1.5', SaveNumberFormat.float32Big).single.offset, 1);
  });

  test('Search cap is respected even with repeated and overlapping matches', () {
    final data = Uint8List(100);
    final hits = BinarySaveEditor.search(
      data, '0', SaveNumberFormat.int32Little, maxResults: 3);
    expect(hits.map((h) => h.offset).toList(), [0, 1, 2]);
    expect(() => BinarySaveEditor.search(
        data, '0', SaveNumberFormat.int32Little, maxResults: 0),
        throwsRangeError);
  });

  test('Guard against changed bytes and invalid offsets', () {
    final bytes = Uint8List.fromList([100, 0, 0, 0]);
    expect(() => BinarySaveEditor.patch(
      bytes, offset: 0, expected: '99', replacement: '500',
      format: SaveNumberFormat.int32Little),
      throwsStateError);
    expect(() => BinarySaveEditor.patch(
      bytes, offset: 1, expected: '100', replacement: '500',
      format: SaveNumberFormat.int32Little),
      throwsRangeError);
    expect(bytes, [100, 0, 0, 0]);
  });

  test('Reject invalid, overflowing and non-finite numeric input', () {
    expect(() => BinarySaveEditor.encode(
        'hello', SaveNumberFormat.int32Little), throwsFormatException);
    expect(() => BinarySaveEditor.encode(
        '2147483648', SaveNumberFormat.int32Little), throwsFormatException);
    expect(() => BinarySaveEditor.encode(
        '1e100', SaveNumberFormat.float32Little), throwsFormatException);
    expect(() => BinarySaveEditor.encode(
        'NaN', SaveNumberFormat.float32Little), throwsFormatException);
    expect(() => BinarySaveEditor.encode(
        '', SaveNumberFormat.int32Little), throwsFormatException);
  });
}
