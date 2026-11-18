import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/storage_service.dart';

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('ehtid-read-'));
  tearDown(() async => temp.delete(recursive: true));

  GameFile discovered(File file, int scannedSize) => GameFile(
    id: file.path,
    name: 'slot.sav',
    relativePath: 'slot.sav',
    size: scannedSize,
  );

  test('reads a small save even with stale scan metadata', () async {
    final file = File('${temp.path}/slot.sav');
    await file.writeAsBytes([1, 2, 3, 4]);
    final result = await DesktopGameStorage().read(discovered(file, 0));
    expect(result, Uint8List.fromList([1, 2, 3, 4]));
  });

  test('rejects a grown save beyond the edit limit', () async {
    final file = File('${temp.path}/slot.sav');
    await file.writeAsBytes(Uint8List(maxEditableBytes + 1));
    await expectLater(
      DesktopGameStorage().read(discovered(file, 1)),
      throwsA(isA<StateError>()),
    );
    expect(await file.length(), maxEditableBytes + 1);
  });

  test('accepts a save exactly at the limit', () async {
    final file = File('${temp.path}/slot.sav');
    await file.writeAsBytes(Uint8List(maxEditableBytes));
    final bytes = await DesktopGameStorage().read(discovered(file, 0));
    expect(bytes.length, maxEditableBytes);
  });
}
