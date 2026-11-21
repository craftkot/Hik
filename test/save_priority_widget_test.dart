import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/main.dart';
import 'package:game_lab/widgets/save_field_browser.dart';

class _PriorityStorage implements GameStorage {
  static const source = '{"player":{"name":"Test","quest":42,'
      '"level":5,"strength":18,"hp":120,"gold":450}}';

  final file = GameFile(id: 'virtual/profile.json',
      name: 'profile.json', relativePath: 'Saves/profile.json',
      size: source.length);

  @override
  Future<String?> chooseFolder() async => 'virtual';
  @override
  Future<List<GameFile>> scan(String folder) async => [file];
  @override
  Future<Uint8List> read(GameFile file) async =>
      Uint8List.fromList(utf8.encode(source));
  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);
  @override
  Future<String> writeWithBackup(GameFile file, Uint8List bytes,
      {Uint8List? expected}) async => throw UnimplementedError();
}

void main() {
  testWidgets('save JSON highlights money, HP, stats before ordinary fields',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
        MaterialApp(home: GameLabHome(storage: _PriorityStorage())));
    await tester.tap(find.text('Редактор сохранений'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть папку игры'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('profile.json').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Редактировать поля JSON'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Важные поля сначала'), findsOneWidget);
    // The new inline important-fields list remains visible behind the
    // modal. Scope the legacy ordering assertions to SaveFieldBrowser.
    final modal = find.byType(SaveFieldBrowser);
    Finder inside(String label) => find.descendant(
        of: modal, matching: find.text(label));
    expect(inside('/player/gold'), findsOneWidget);
    expect(inside('/player/hp'), findsOneWidget);
    expect(inside('/player/strength'), findsOneWidget);
    expect(inside('Валюта'), findsNWidgets(2));
    expect(inside('HP / здоровье'), findsNWidgets(2));
    final gold = tester.getTopLeft(inside('/player/gold')).dy;
    final hp = tester.getTopLeft(inside('/player/hp')).dy;
    final strength = tester.getTopLeft(inside('/player/strength')).dy;
    expect(gold, lessThan(hp));
    expect(hp, lessThan(strength));

    await tester.tap(inside('/player/gold'));
    await tester.pumpAndSettle();
    expect(find.text('Изменить поле'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Изменить поле'), findsOneWidget);
  });
}
