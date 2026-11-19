import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/widgets/android_game_translation_panel.dart';

class EmptyStorage implements GameStorage {
  @override
  Future<String?> chooseFolder() async => null;
  @override
  Future<List<GameFile>> scan(String folder) async => [];
  @override
  Future<Uint8List> read(GameFile file) async => Uint8List(0);
  @override
  Future<Uint8List> readPreview(GameFile file) async => Uint8List(0);
  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected}) async => 'test backup';
}

void main() {
  testWidgets('Android translator starts by choosing a folder',
      (tester) async {
    var folderChosen = false;
    var appChosen = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: AndroidGameTranslationPanel(
          storage: EmptyStorage(),
          files: const [],
          gameName: null,
          chooseGame: () async { appChosen = true; },
          grantFolder: () async { folderChosen = true; },
          refreshFiles: () async {},
        ),
      )),
    ));
    expect(find.text('Выбрать папку игры'), findsOneWidget);
    await tester.tap(find.text('Выбрать папку игры'));
    await tester.pumpAndSettle();
    expect(folderChosen, isTrue);
    expect(appChosen, isFalse);
  });

  testWidgets('manually granted folder can translate without app listing',
      (tester) async {
    const file = GameFile(
      id: 'locale', name: 'en.json',
      relativePath: 'locales/en.json', size: 25,
    );
    var appPickerOpened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: AndroidGameTranslationPanel(
          storage: EmptyStorage(),
          files: const [file],
          gameName: null,
          hasFolder: true,
          chooseGame: () async { appPickerOpened = true; },
          grantFolder: () async {},
          refreshFiles: () async {},
        ),
      )),
    ));
    expect(find.textContaining('Ручной режим'), findsOneWidget);
    expect(find.text('1 JSON'), findsOneWidget);
    await tester.tap(find.text('Подготовить перевод (1 файлов)'));
    await tester.pumpAndSettle();
    expect(find.text('Подготовить перевод игры?'), findsOneWidget);
    expect(appPickerOpened, isFalse);
  });

  testWidgets('lists open localization files and requires configured API',
      (tester) async {
    const file = GameFile(
      id: 'one', name: 'en.json',
      relativePath: 'assets/lang/en.json', size: 30,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: AndroidGameTranslationPanel(
          storage: EmptyStorage(),
          files: const [file],
          gameName: 'Test Game',
          chooseGame: () async {},
          grantFolder: () async {},
          refreshFiles: () async {},
        ),
      )),
    ));
    expect(find.text('1 JSON'), findsOneWidget);
    expect(find.text('Доступ к папке игры'), findsOneWidget);
    await tester.tap(find.text('Подготовить перевод (1 файлов)'));
    await tester.pumpAndSettle();
    expect(find.text('Подготовить перевод игры?'), findsOneWidget);
    expect(find.textContaining('строки будут переведены'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подготовить перевод (1 файлов)'));
    await tester.pump();
    expect(find.textContaining('Укажи HTTPS LibreTranslate'), findsWidgets);
  });
}
