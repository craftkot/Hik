import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/safe_desktop_save.dart';
import 'package:game_lab/widgets/desktop_backup_restore_dialog.dart';

Uint8List data(String content) => Uint8List.fromList(utf8.encode(content));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File save;
  late Uint8List original;
  late Uint8List modified;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ehtid-restore-widget-');
    save = File('${dir.path}${Platform.pathSeparator}world.sav');
    original = data('hp=120');
    modified = data('hp=999');
    await save.writeAsBytes(original, flush: true);
    await SafeDesktopSaveWriter()
        .write(save, modified, expected: original);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => DesktopBackupRestoreDialog(save: save)),
          child: const Text('Открыть восстановление'),
        )),
      ),
    ));
    await tester.tap(find.text('Открыть восстановление'));
    await tester.pumpAndSettle();
  }

  testWidgets('preview is read-only and requires separate approval',
      (tester) async {
    await openDialog(tester);
    expect(find.text('Восстановить сохранение'), findsOneWidget);
    expect(find.textContaining('world.sav.ehtid-backup-'), findsWidgets);

    await tester.tap(find.textContaining('world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    expect(find.text('Содержимое различается'), findsOneWidget);
    expect(await save.readAsBytes(), modified);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await tester.pumpAndSettle();
    expect(find.text('Подтвердить восстановление'), findsOneWidget);
    expect(await save.readAsBytes(), modified);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();
    expect(await save.readAsBytes(), modified);

    await tester.tap(find.widgetWithText(FilledButton, 'Восстановить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить восстановление'));
    await tester.pumpAndSettle();
    expect(await save.readAsBytes(), original);
    expect(find.text('Восстановить сохранение'), findsNothing);
  });

  testWidgets('unresolved crash rollback disables restoring backups',
      (tester) async {
    final crash = File('${save.path}.ehtid-rollback-crash.tmp');
    await crash.writeAsBytes(original, flush: true);
    await openDialog(tester);
    expect(find.textContaining('Найдено аварийных файлов: 1'), findsOneWidget);
    await tester.tap(find.textContaining('world.sav.ehtid-backup-').first);
    await tester.pumpAndSettle();
    final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Восстановить'));
    expect(action.onPressed, isNull);
    expect(await save.readAsBytes(), modified);
    expect(await crash.readAsBytes(), original);
  });
}
