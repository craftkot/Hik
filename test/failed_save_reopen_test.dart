import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/main.dart';

class _FailingReopenStorage implements GameStorage {
  final file = GameFile(
    id: 'fake/save.dat',
    name: 'save.dat',
    relativePath: 'save.dat',
    size: 4,
  );
  int reads = 0;

  @override
  Future<String?> chooseFolder() async => 'fake';

  @override
  Future<List<GameFile>> scan(String folder) async => [file];

  @override
  Future<Uint8List> read(GameFile file) async {
    reads++;
    if (reads > 1) throw StateError('file became inaccessible');
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);

  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data) async =>
      throw UnimplementedError();
}

void main() {
  testWidgets('failed reopen clears previous selected save and editor', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _FailingReopenStorage();
    await tester.pumpWidget(MaterialApp(home: GameLabHome(storage: storage)));
    await tester.tap(find.text('Редактор сохранений'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку игры'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('save.dat').first);
    await tester.pumpAndSettle();
    expect(storage.reads, 1);
    expect(find.text('Выбери файл'), findsNothing);

    await tester.tap(find.text('save.dat').first);
    await tester.pumpAndSettle();
    expect(storage.reads, 2);
    expect(find.text('Выбери файл'), findsOneWidget);
    expect(find.textContaining('Не удалось прочесть файл'), findsWidgets);
    // The previously selected value is no longer available for writing.
    // With no selected file, the detail pane is replaced by the placeholder,
    // so there is no apply button to invoke.
    expect(find.widgetWithText(FilledButton, 'Применить'), findsNothing);
    expect(storage.reads, 2);
  });
}
