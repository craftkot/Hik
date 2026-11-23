import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/crash_rollback_inspector.dart';
import 'package:game_lab/core/desktop_save_recovery.dart';
import 'package:game_lab/widgets/desktop_backup_restore_dialog.dart';

class _FakeRecovery extends DesktopSaveRecovery {
  _FakeRecovery(this.save);

  final File save;
  late final File backup = File('${save.path}.ehtid-backup-test.bak');
  final Uint8List before = Uint8List.fromList([104, 112, 61, 49, 50, 48]);
  final Uint8List after = Uint8List.fromList([104, 112, 61, 57, 57, 57]);
  bool restored = false;
  bool failListing = false;
  bool failRestore = false;
  Completer<void>? pauseListing;
  int calls = 0;

  @override
  Future<List<DesktopBackupEntry>> listBackups(File original) async {
    expect(original.path, save.path);
    if (failListing) throw StateError('test listing failure');
    await pauseListing?.future;
    return [DesktopBackupEntry(
        backup, before.length, DateTime.utc(2026, 11, 18))];
  }

  @override
  Future<DesktopBackupPreview> preview(File original, File selected) async {
    expect(original.path, save.path);
    expect(selected.path, backup.path);
    return DesktopBackupPreview(
      save: save, backup: backup, currentBytes: after, backupBytes: before);
  }

  @override
  Future<String> restore(DesktopBackupPreview approved,
      {required bool confirmed}) async {
    expect(confirmed, isTrue);
    expect(approved.backup.path, backup.path);
    calls++;
    if (failRestore) throw StateError('test restore failure');
    restored = true;
    return '${save.path}.ehtid-backup-safety.bak';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_FakeRecovery> openDialog(WidgetTester tester,
      {bool interrupted = false}) async {
    // UI-only test doubles keep dart:io off the widget test's fake clock.
    // The real disk/restore implementation has separate ordinary unit tests.
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final save = File('${Directory.systemTemp.path}'
        '${Platform.pathSeparator}ehtid-test-world.sav');
    final recovery = _FakeRecovery(save);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => DesktopBackupRestoreDialog(
                save: save,
                recovery: recovery,
                inspectCrash: (_) async => interrupted
                  ? [
                      CrashRollbackPreview(
                        path: '${save.path}.ehtid-rollback-test.tmp',
                        bytes: recovery.before,
                        currentExists: true,
                        currentBytes: recovery.after,
                      ),
                    ] : [],
              )),
          child: const Text('Открыть восстановление'),
        )),
      ),
    ));
    await tester.tap(find.text('Открыть восстановление'));
    await tester.pumpAndSettle();
    return recovery;
  }

  testWidgets('preview is read-only and requires separate approval',
      (tester) async {
    final recovery = await openDialog(tester);
    expect(find.text('Восстановить сохранение'), findsOneWidget);
    expect(find.textContaining('ehtid-test-world.sav.ehtid-backup-'),
        findsWidgets);

    await tester.tap(find.textContaining(
        'ehtid-test-world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    expect(find.text('Содержимое различается'), findsOneWidget);
    expect(recovery.restored, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердить восстановление'), findsOneWidget);
    expect(recovery.restored, isFalse);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(recovery.restored, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить восстановление'));
    await tester.pumpAndSettle();
    expect(recovery.restored, isTrue);
    expect(recovery.calls, 1);
    expect(find.text('Восстановить сохранение'), findsNothing);
  });

  testWidgets('failed restore invalidates preview before retry',
      (tester) async {
    final recovery = await openDialog(tester);
    recovery.failRestore = true;
    await tester.tap(find.textContaining(
        'ehtid-test-world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    expect(find.text('Содержимое различается'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить восстановление'));
    await tester.pumpAndSettle();

    expect(find.textContaining('test restore failure'), findsOneWidget);
    expect(find.text('Содержимое различается'), findsNothing);
    final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Восстановить'));
    expect(action.onPressed, isNull);
    expect(recovery.calls, 1);
    expect(recovery.restored, isFalse);

    recovery.failRestore = false;
    await tester.tap(find.textContaining(
        'ehtid-test-world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    expect(find.text('Содержимое различается'), findsOneWidget);
  });

  testWidgets('failed refresh clears old backup list and preview',
      (tester) async {
    final recovery = await openDialog(tester);
    await tester.tap(find.textContaining(
        'ehtid-test-world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    expect(find.text('Содержимое различается'), findsOneWidget);

    recovery.failListing = true;
    await tester.tap(find.byTooltip('Обновить список бэкапов'));
    await tester.pumpAndSettle();

    expect(find.textContaining('test listing failure'), findsOneWidget);
    expect(find.text('Не удалось обновить список бэкапов'),
        findsOneWidget);
    expect(find.textContaining('ehtid-test-world.sav.ehtid-backup-'),
        findsNothing);
    expect(find.text('Содержимое различается'), findsNothing);
    final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Восстановить'));
    expect(action.onPressed, isNull);
    expect(recovery.restored, isFalse);
  });

  testWidgets('refresh shows loading instead of an empty backup result',
      (tester) async {
    final recovery = await openDialog(tester);
    recovery.pauseListing = Completer<void>();

    await tester.tap(find.byTooltip('Обновить список бэкапов'));
    await tester.pump();

    expect(find.text('Загружаю резервные копии…'), findsOneWidget);
    expect(find.text('Бэкапов для этого сейва нет'), findsNothing);
    expect(find.text('Не удалось обновить список бэкапов'), findsNothing);
    final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Восстановить'));
    expect(action.onPressed, isNull);

    recovery.pauseListing!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Загружаю резервные копии…'), findsNothing);
    expect(find.textContaining('ehtid-test-world.sav.ehtid-backup-'),
        findsWidgets);
  });

  testWidgets('unresolved crash rollback disables restoring backups',
      (tester) async {
    final recovery = await openDialog(tester, interrupted: true);
    expect(find.textContaining('Найдено аварийных файлов: 1'), findsOneWidget);
    await tester.tap(find.textContaining(
        'ehtid-test-world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Восстановить'));
    expect(action.onPressed, isNull);
    expect(recovery.restored, isFalse);
  });
}
