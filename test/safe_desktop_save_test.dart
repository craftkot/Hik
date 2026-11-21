import 'dart:async';
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


  test('second write is rejected while first is checking backup', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final original = await save.readAsBytes();
    final writer = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    });
    final first = writer.write(save, bytes('hp=200'), expected: original);
    await entered.future;
    try {
      await expectLater(
          writer.write(save, bytes('hp=300'), expected: original),
          throwsStateError);
    } finally {
      release.complete();
    }
    await first;
    expect(await save.readAsBytes(), bytes('hp=200'));
    expect((await entries('.ehtid-backup-')).length, 1);
  });

  test('different writer instances cannot edit the same save concurrently',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final original = await save.readAsBytes();
    final firstWriter = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    });
    final first = firstWriter.write(save, bytes('hp=200'), expected: original);
    await entered.future;
    try {
      await expectLater(
          SafeDesktopSaveWriter().write(
              File(save.absolute.path), bytes('hp=300'), expected: original),
          throwsStateError);
      expect(await save.readAsBytes(), original);
      expect((await entries('.ehtid-backup-')).length, 1);
    } finally {
      release.complete();
    }
    await first;
    expect(await save.readAsBytes(), bytes('hp=200'));
    expect(await entries('.ehtid-pending-'), isEmpty);
    expect(await entries('.ehtid-rollback-'), isEmpty);
  });

  test('path aliases cannot bypass cross-instance save lock', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final original = await save.readAsBytes();
    final writer = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    });
    final first = writer.write(save, bytes('hp=200'), expected: original);
    await entered.future;
    try {
      final alias = File('${scratch.path}${Platform.pathSeparator}subdir'
          '${Platform.pathSeparator}..${Platform.pathSeparator}world.sav');
      await expectLater(
          SafeDesktopSaveWriter().write(
              alias, bytes('hp=300'), expected: original),
          throwsStateError);
      expect(await save.readAsBytes(), original);
      expect((await entries('.ehtid-backup-')).length, 1);
    } finally {
      release.complete();
    }
    await first;
    expect(await save.readAsBytes(), bytes('hp=200'));
  });

  test('directory symlink aliases share the same writer lock', () async {
    final aliasDir = Link('${scratch.path}${Platform.pathSeparator}alias');
    await aliasDir.create(scratch.path);
    final alias = File('${aliasDir.path}${Platform.pathSeparator}world.sav');
    final original = await save.readAsBytes();
    final entered = Completer<void>();
    final release = Completer<void>();
    final first = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    }).write(save, bytes('hp=200'), expected: original);
    await entered.future;
    try {
      await expectLater(
          SafeDesktopSaveWriter().write(alias, bytes('hp=300'),
              expected: original),
          throwsStateError);
      expect(await save.readAsBytes(), original);
    } finally {
      release.complete();
    }
    await first;
    expect(await save.readAsBytes(), bytes('hp=200'));
  }, skip: Platform.isWindows
      ? 'Creating directory links may require Windows developer privileges'
      : false);

  test('Windows junction aliases share the same writer lock', () async {
    final aliasPath = '${scratch.path}${Platform.pathSeparator}junction';
    final created = await Process.run(
        'cmd', ['/c', 'mklink', '/J', aliasPath, scratch.path]);
    expect(created.exitCode, 0,
        reason: 'Windows junction creation failed: ${created.stderr}');
    try {
      final alias = File('$aliasPath${Platform.pathSeparator}world.sav');
      final original = await save.readAsBytes();
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
        if (phase == DesktopSaveCheckpoint.backupVerified) {
          entered.complete();
          await release.future;
        }
      }).write(save, bytes('hp=200'), expected: original);
      await entered.future;
      try {
        await expectLater(
            SafeDesktopSaveWriter().write(alias, bytes('hp=300'),
                expected: original),
            throwsStateError);
        expect(await save.readAsBytes(), original);
      } finally {
        release.complete();
      }
      await first;
      expect(await save.readAsBytes(), bytes('hp=200'));
    } finally {
      await Directory(aliasPath).delete();
    }
  }, skip: !Platform.isWindows);

  test('another writer cannot write while backup restore is running',
      () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=999');
    final backup = await SafeDesktopSaveWriter()
        .write(save, edited, expected: original);
    final entered = Completer<void>();
    final release = Completer<void>();
    final restoringWriter = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    });
    final restoring = restoringWriter.restoreBackup(save, File(backup),
        expectedCurrent: edited,
        expectedBackup: original,
        confirmed: true);
    await entered.future;
    try {
      await expectLater(
          SafeDesktopSaveWriter().write(save, bytes('hp=300'), expected: edited),
          throwsStateError);
    } finally {
      release.complete();
    }
    await restoring;
    expect(await save.readAsBytes(), original);
  });

  test('restore holds writer lock through backup verification', () async {
    final original = await save.readAsBytes();
    final edited = bytes('hp=999');
    final backupPath = await SafeDesktopSaveWriter()
        .write(save, edited, expected: original);
    final entered = Completer<void>();
    final release = Completer<void>();
    final writer = SafeDesktopSaveWriter(onCheckpoint: (phase) async {
      if (phase == DesktopSaveCheckpoint.backupVerified) {
        entered.complete();
        await release.future;
      }
    });
    final restoring = writer.restoreBackup(save, File(backupPath),
        expectedCurrent: edited,
        expectedBackup: original,
        confirmed: true);
    await entered.future;
    try {
      await expectLater(
          writer.write(save, bytes('hp=300'), expected: edited),
          throwsStateError);
    } finally {
      release.complete();
    }
    await restoring;
    expect(await save.readAsBytes(), original);
  });

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
      save, File(backupPath), expectedCurrent: edited, expectedBackup: original, confirmed: true);
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
          expectedCurrent: bytes('hp=999'), expectedBackup: before, confirmed: false),
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
          expectedCurrent: bytes('hp=999'), expectedBackup: before, confirmed: true),
      throwsStateError);
    final unrelated = File('${scratch.path}/other.ehtid-backup-test.bak');
    await unrelated.writeAsBytes(before);
    await expectLater(
      writer.restoreBackup(save, unrelated,
          expectedCurrent: bytes('hp=250;game-updated'), expectedBackup: before, confirmed: true),
      throwsStateError);
    expect(await save.readAsBytes(), bytes('hp=250;game-updated'));
  });

  test('restore refuses backup changed after preview without modifying save',
      () async {
    final writer = SafeDesktopSaveWriter();
    final original = await save.readAsBytes();
    final edited = bytes('hp=999');
    final backupPath = await writer.write(save, edited, expected: original);
    await File(backupPath).writeAsBytes(bytes('hp=1;tampered'), flush: true);
    await expectLater(
      writer.restoreBackup(save, File(backupPath),
          expectedCurrent: edited, expectedBackup: original, confirmed: true),
      throwsStateError);
    expect(await save.readAsBytes(), edited);
    expect((await entries('.ehtid-backup-')).length, 1);
  });

  test('unresolved crash rollback blocks another write without new backup',
      () async {
    final original = await save.readAsBytes();
    final crashCopy = File('${save.path}.ehtid-rollback-interrupted.tmp');
    await crashCopy.writeAsBytes(original, flush: true);
    await expectLater(
      SafeDesktopSaveWriter().write(save, bytes('hp=999'), expected: original),
      throwsStateError,
    );
    expect(await save.readAsBytes(), original);
    expect(await crashCopy.readAsBytes(), original);
    expect(await entries('.ehtid-backup-'), isEmpty);
    expect(await entries('.ehtid-pending-'), isEmpty);
  });

  test('missing original with crash rollback is not silently recreated',
      () async {
    final original = await save.readAsBytes();
    final crashCopy = File('${save.path}.ehtid-rollback-interrupted.tmp');
    await save.rename(crashCopy.path);
    await expectLater(
      SafeDesktopSaveWriter().write(save, bytes('hp=999'), expected: original),
      throwsStateError,
    );
    expect(await save.exists(), isFalse);
    expect(await crashCopy.readAsBytes(), original);
    expect(await entries('.ehtid-backup-'), isEmpty);
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
