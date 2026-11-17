import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/safe_desktop_save.dart';
import 'package:game_lab/core/storage_service.dart';

Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  late Directory scratch;
  late File save;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('ehtid-safe-save-');
    save = File('${scratch.path}${Platform.pathSeparator}world.sav');
    await save.writeAsBytes(bytes('hp=125;coins=100'), flush: true);
  });

  tearDown(() async {
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  Future<List<File>> entries(String part) async => scratch
      .list()
      .where((file) => file is File && file.path.contains(part))
      .cast<File>()
      .toList();

  test('successful staged write preserves checked backup and new data',
      () async {
    final original = await save.readAsBytes();
    final proposed = bytes('hp=999;coins=100');
    final backupPath = await SafeDesktopSaveWriter().write(
      save, proposed, expected: original);
    expect(await save.readAsBytes(), proposed);
    expect(await File(backupPath).readAsBytes(), original);
    expect(await entries('.ehtid-pending-'), isEmpty);
    expect(await entries('.ehtid-rollback-'), isEmpty);
  });

  test('stale save is rejected before a backup or replacement is created',
      () async {
    final writer = SafeDesktopSaveWriter();
    await expectLater(
        writer.write(save, bytes('hp=999'), expected: bytes('hp=1')),
        throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=125;coins=100'));
    expect(await entries('.ehtid-backup-'), isEmpty);
  });

  test('failure while preparing stage keeps original and verified backup',
      () async {
    final original = await save.readAsBytes();
    final writer = SafeDesktopSaveWriter(
        onCheckpoint: (phase) {
          if (phase == DesktopSaveCheckpoint.stageVerified) {
            throw StateError('simulated disk failure before renames');
          }
        });
    await expectLater(
      writer.write(save, bytes('hp=200'), expected: original),
      throwsStateError,
    );
    expect(await save.readAsBytes(), original);
    expect((await entries('.ehtid-backup-')).length, 1);
    expect(await entries('.ehtid-pending-'), isEmpty);
  });

  test('failure after original is displaced immediately restores it',
      () async {
    final original = await save.readAsBytes();
    final writer = SafeDesktopSaveWriter(
        onCheckpoint: (phase) {
          if (phase == DesktopSaveCheckpoint.originalDisplaced) {
            throw StateError('simulated failure during swap');
          }
        });
    await expectLater(
        writer.write(save, bytes('hp=999'), expected: original),
        throwsStateError);
    expect(await save.readAsBytes(), original);
    expect(await entries('.ehtid-rollback-'), isEmpty);
    expect(await entries('.ehtid-pending-'), isEmpty);
    expect((await entries('.ehtid-backup-')).length, 1);
  });

  test('failure after installing new data restores exact original',
      () async {
    final original = await save.readAsBytes();
    final writer = SafeDesktopSaveWriter(
        onCheckpoint: (phase) {
          if (phase == DesktopSaveCheckpoint.replacementInstalled) {
            throw StateError('simulated verification failure');
          }
        });
    await expectLater(
        writer.write(save, bytes('hp=999'), expected: original),
        throwsStateError);
    expect(await save.readAsBytes(), original);
    expect(await entries('.ehtid-rollback-'), isEmpty);
    final backups = await entries('.ehtid-backup-');
    expect(backups.length, 1);
    expect(await backups.single.readAsBytes(), original);
  });

  test('external game save modification during staging is not overwritten',
      () async {
    final writer = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.stageVerified) {
        await save.writeAsBytes(bytes('hp=250;game-still-running'),
            flush: true);
      }
    });
    await expectLater(
      writer.write(save, bytes('hp=999'),
          expected: bytes('hp=125;coins=100')),
      throwsStateError,
    );
    expect(await save.readAsBytes(), bytes('hp=250;game-still-running'));
    expect(await entries('.ehtid-rollback-'), isEmpty);
  });

  test('backups, rollback and staging files are hidden from game scan',
      () async {
    final storage = DesktopGameStorage();
    final file = GameFile(
      id: save.path,
      name: 'world.sav',
      relativePath: 'world.sav',
      size: (await save.length()),
    );
    await storage.writeWithBackup(file, bytes('hp=75'),
        expected: bytes('hp=125;coins=100'));
    await File('${save.path}.ehtid-rollback-test.tmp')
        .writeAsString('do-not-index');
    await File('${save.path}.ehtid-pending-test.tmp')
        .writeAsString('do-not-index');

    final found = await storage.scan(scratch.path);
    expect(found.map((entry) => entry.name), ['world.sav']);
    expect(await save.readAsBytes(), bytes('hp=75'));
  });


  test('confirmed restore preserves a new backup of the edited save', () async {
    final writer = SafeDesktopSaveWriter();
    final original = await save.readAsBytes();
    final edited = bytes('hp=999;coins=100');
    final backupPath = await writer.write(save, edited, expected: original);
    final undoBackup = await writer.restoreBackup(
      save, File(backupPath), expectedCurrent: edited, confirmed: true);
    expect(await save.readAsBytes(), original);
    expect(await File(undoBackup).readAsBytes(), edited);
    expect(await File(backupPath).readAsBytes(), original);
  });

  test('restore requires explicit confirmation and does not change bytes',
      () async {
    final writer = SafeDesktopSaveWriter();
    final before = await save.readAsBytes();
    final backupPath = await writer.write(
      save, bytes('hp=999'), expected: before);
    await expectLater(
      writer.restoreBackup(save, File(backupPath),
          expectedCurrent: bytes('hp=999'), confirmed: false),
      throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=999'));
  });

  test('restore refuses stale preview and unrelated backup', () async {
    final writer = SafeDesktopSaveWriter();
    final before = await save.readAsBytes();
    final backupPath = await writer.write(
      save, bytes('hp=999'), expected: before);
    await save.writeAsBytes(bytes('hp=250;game-updated'));
    await expectLater(
      writer.restoreBackup(save, File(backupPath),
          expectedCurrent: bytes('hp=999'), confirmed: true),
      throwsStateError);
    final unrelated = File('${scratch.path}/other.ehtid-backup-test.bak');
    await unrelated.writeAsBytes(before);
    await expectLater(
      writer.restoreBackup(save, unrelated,
          expectedCurrent: bytes('hp=250;game-updated'), confirmed: true),
      throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=250;game-updated'));
  });

  test('oversized replacements rejected before changing original', () async {
    await expectLater(
      SafeDesktopSaveWriter().write(
        save, Uint8List(SafeDesktopSaveWriter.maxLength + 1)),
      throwsStateError,
    );
    expect(await save.readAsBytes(), bytes('hp=125;coins=100'));
  });
}
