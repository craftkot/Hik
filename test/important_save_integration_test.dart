import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/gzip_save_codec.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/main.dart';

class _GzipGameStorage implements GameStorage {
  _GzipGameStorage() {
    bytes = Uint8List.fromList(gzip.encode(
      utf8.encode('{"player":{"gold":100,"hp":120,'
          '"quest":222,"name":"Sample"}}')));
  }
  late Uint8List bytes;
  int writes = 0;
  bool verifiedExpected = false;

  late final file = GameFile(
    id: 'virtual/SaveData015.gz', name: 'SaveData015.gz',
    relativePath: 'SaveData/jpg/SaveData015.gz', size: bytes.length);

  @override
  Future<String?> chooseFolder() async => 'virtual';
  @override
  Future<List<GameFile>> scan(String folder) async => [file];
  @override
  Future<Uint8List> read(GameFile file) async => Uint8List.fromList(bytes);
  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);
  @override
  Future<String> writeWithBackup(GameFile file, Uint8List next,
      {Uint8List? expected}) async {
    verifiedExpected = expected != null &&
        base64Encode(expected) == base64Encode(bytes);
    if (!verifiedExpected) throw StateError('Save changed on disk');
    writes++;
    bytes = Uint8List.fromList(next);
    return 'test-backup';
  }
}

void main() {
  testWidgets('GZIP JSON opens as important rows and saves repacked value',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _GzipGameStorage();

    await tester.pumpWidget(MaterialApp(home: GameLabHome(storage: storage)));
    await tester.tap(find.text('Редактор сохранений'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку игры'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SaveData015.gz').last);
    await tester.pumpAndSettle();

    expect(find.text('ВАЖНЫЕ ПАРАМЕТРЫ'), findsOneWidget);
    expect(find.text('/player/gold'), findsOneWidget);
    expect(find.text('/player/hp'), findsOneWidget);
    expect(find.text('/player/quest'), findsNothing);
    expect(find.text('HEX-ПРОСМОТР'), findsNothing);

    await tester.tap(find.text('/player/gold'));
    await tester.pumpAndSettle();
    expect(find.text('Изменить поле'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '999');
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    expect(find.text('999'), findsOneWidget);
    expect(storage.writes, 0);

    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать копию и применить'));
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    expect(storage.verifiedExpected, isTrue);
    final text = utf8.decode(GzipSaveCodec.decode(storage.bytes));
    final json = jsonDecode(text) as Map<String, dynamic>;
    final player = json['player'] as Map<String, dynamic>;
    expect(player['gold'], 999);
    expect(player['hp'], 120);
    expect(player['quest'], 222);
    expect(player['name'], 'Sample');

    await tester.tap(find.text('Исходный файл'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
    expect(find.byTooltip('Вернуться к списку важных параметров'),
        findsOneWidget);
  });
}
