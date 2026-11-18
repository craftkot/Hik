import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/safe_desktop_save.dart';

void main() {
  test('rejects oversized current save without making a backup', () async {
    final dir = await Directory.systemTemp.createTemp('ehtid-bounded-write-');
    try {
      final original = File('${dir.path}/slot.sav');
      await original.writeAsBytes(Uint8List(SafeDesktopSaveWriter.maxLength + 1));
      await expectLater(
        SafeDesktopSaveWriter().write(original, Uint8List.fromList([1])),
        throwsA(isA<StateError>()),
      );
      expect(await original.length(), SafeDesktopSaveWriter.maxLength + 1);
      expect((await dir.list().toList()).length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('rejects save enlarged after verified backup and keeps original', () async {
    final dir = await Directory.systemTemp.createTemp('ehtid-bounded-race-');
    try {
      final original = File('${dir.path}/slot.sav');
      await original.writeAsBytes([1, 2, 3]);
      final writer = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
        if (phase == DesktopSaveCheckpoint.stageVerified) {
          await original.writeAsBytes(
            Uint8List(SafeDesktopSaveWriter.maxLength + 1),
          );
        }
      });
      await expectLater(
        writer.write(original, Uint8List.fromList([4, 5, 6]),
            expected: Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
      expect(await original.length(), SafeDesktopSaveWriter.maxLength + 1);
      final backups = await dir
          .list()
          .where((entity) => entity.path.contains('.ehtid-backup-'))
          .toList();
      expect(backups.length, 1);
      expect(await File(backups.single.path).readAsBytes(), [1, 2, 3]);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
