import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/desktop_save_recovery.dart';
import 'package:game_lab/core/safe_desktop_save.dart';

Uint8List bytes(String input) => Uint8List.fromList(utf8.encode(input));

void main() {
  late Directory dir;
  late File save;
  late DesktopSaveRecovery recovery;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ehtid-backup-ui-');
    save = File('${dir.path}${Platform.pathSeparator}world.sav');
    await save.writeAsBytes(bytes('hp=120;coins=500'), flush: true);
    recovery = DesktopSaveRecovery();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('only exact save backups appear in the list', () async {
    final old = await save.readAsBytes();
    final first = await SafeDesktopSaveWriter().write(
        save, bytes('hp=200;coins=500'), expected: old);
    await File('${dir.path}${Platform.pathSeparator}'
        'world.sav-other.ehtid-backup-fake.bak').writeAsBytes(old);
    await File('${dir.path}${Platform.pathSeparator}'
        'unrelated.sav.ehtid-backup-fake.bak').writeAsBytes(old);
    final found = await recovery.listBackups(save);
    expect(found, hasLength(1));
    expect(found.single.file.path, first);
    expect(found.single.length, old.length);
  });

  test('backups with identical timestamps have stable filename ordering', () async {
    final first = File('${save.path}.ehtid-backup-a.bak');
    final second = File('${save.path}.ehtid-backup-b.bak');
    await first.writeAsBytes(bytes('old-a'));
    await second.writeAsBytes(bytes('old-b'));
    final sameTime = DateTime.utc(2026, 1, 1);
    await first.setLastModified(sameTime);
    await second.setLastModified(sameTime);
    for (var i = 0; i < 3; i++) {
      final found = await recovery.listBackups(save);
      expect(found.map((entry) => entry.file.path),
          [second.path, first.path]);
    }
  });

  test('previews both files without editing and restores only on confirmation',
      () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=999;coins=100');
    final backup = File(await SafeDesktopSaveWriter()
        .write(save, edited, expected: original));
    final preview = await recovery.preview(save, backup);
    expect(preview.currentBytes, edited);
    expect(preview.backupBytes, original);
    expect(preview.differs, isTrue);
    expect(await save.readAsBytes(), edited);
    await expectLater(
        recovery.restore(preview, confirmed: false), throwsStateError);
    expect(await save.readAsBytes(), edited);

    final safetyBackup = await recovery.restore(preview, confirmed: true);
    expect(await save.readAsBytes(), original);
    expect(await File(safetyBackup).readAsBytes(), edited);
    expect(await backup.readAsBytes(), original);
  });

  test('a different save backup cannot be previewed', () async {
    final otherSave = File('${dir.path}${Platform.pathSeparator}other.sav');
    await otherSave.writeAsBytes(bytes('other'), flush: true);
    final otherBackup = File('${otherSave.path}.ehtid-backup-1.bak');
    await otherBackup.writeAsBytes(bytes('other'), flush: true);
    await expectLater(recovery.preview(save, otherBackup), throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=120;coins=500'));
  });

  test('rejects a backup modified after user has previewed it', () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=200');
    final backup = File(await SafeDesktopSaveWriter()
        .write(save, edited, expected: original));
    final preview = await recovery.preview(save, backup);
    await backup.writeAsBytes(bytes('hp=tampered'), flush: true);
    await expectLater(
        recovery.restore(preview, confirmed: true), throwsStateError);
    expect(await save.readAsBytes(), edited);
  });

  test('deleted backup after preview never overwrites current save', () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=777;coins=500');
    final backup = File(await SafeDesktopSaveWriter()
        .write(save, edited, expected: original));
    final preview = await recovery.preview(save, backup);
    await backup.delete();
    await expectLater(
        recovery.restore(preview, confirmed: true), throwsStateError);
    expect(await save.readAsBytes(), edited);
  });

  test('backup replaced by a directory after preview cannot restore', () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=888;coins=500');
    final backup = File(await SafeDesktopSaveWriter()
        .write(save, edited, expected: original));
    final preview = await recovery.preview(save, backup);

    await backup.delete();
    await Directory(backup.path).create();

    await expectLater(
        recovery.restore(preview, confirmed: true), throwsStateError);
    expect(await save.readAsBytes(), edited);
    expect(await Directory(backup.path).exists(), isTrue);
  });

  test('rejects the game changing the current save after preview', () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=200');
    final backup = File(await SafeDesktopSaveWriter()
        .write(save, edited, expected: original));
    final preview = await recovery.preview(save, backup);
    await save.writeAsBytes(bytes('hp=201'), flush: true);
    await expectLater(
        recovery.restore(preview, confirmed: true), throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=201'));
  });

  test('limits reads before displaying oversized backup', () async {
    final backup = File('${save.path}.ehtid-backup-test.bak');
    await backup.writeAsBytes(
        Uint8List(SafeDesktopSaveWriter.maxLength + 1), flush: true);
    await expectLater(recovery.listBackups(save), throwsStateError);
    await expectLater(recovery.preview(save, backup), throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=120;coins=500'));
  });

  test('more than 64 matching backups are rejected without touching save',
      () async {
    final original = await save.readAsBytes();
    for (var i = 0; i <= DesktopSaveRecovery.maxBackups; i++) {
      final backup = File('${save.path}.ehtid-backup-${i.toString().padLeft(3, '0')}.bak');
      await backup.writeAsBytes(bytes('backup-$i'));
    }
    await expectLater(recovery.listBackups(save), throwsStateError);
    expect(await save.readAsBytes(), original);
  });

  test('matching directories do not consume the 64-file backup limit',
      () async {
    final original = await save.readAsBytes();
    for (var i = 0; i < DesktopSaveRecovery.maxBackups + 1; i++) {
      await Directory('${save.path}.ehtid-backup-dir-$i.bak').create();
    }
    final actual = File('${save.path}.ehtid-backup-real.bak');
    await actual.writeAsBytes(bytes('previous save'));
    final found = await recovery.listBackups(save);
    expect(found, hasLength(1));
    expect(found.single.file.path, actual.path);
    expect(await save.readAsBytes(), original);
  });

  test('same bytes do not require restoration', () async {
    final backup = File('${save.path}.ehtid-backup-test.bak');
    await backup.writeAsBytes(await save.readAsBytes());
    final preview = await recovery.preview(save, backup);
    expect(preview.differs, isFalse);
  });
}
