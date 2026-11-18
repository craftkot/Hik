import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/main.dart';

void main() {
  testWidgets('Windows save finder is available before opening a folder',
      (tester) async {
    if (!Platform.isWindows) return;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const GameLabApp());
    await tester.tap(find.text('Редактор сохранений'));
    await tester.pumpAndSettle();

    expect(find.text('Открыть папку игры'), findsOneWidget);
    expect(find.text('Найти сейвы'), findsOneWidget);
    await tester.tap(find.text('Найти сейвы'));
    await tester.pumpAndSettle();

    expect(find.text('Найти сейвы по названию игры'), findsOneWidget);
    expect(find.text('Название игры'), findsOneWidget);
    expect(find.text('Искать сейвы'), findsOneWidget);
    expect(find.textContaining('Можно начать даже без папки'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Найти сейвы по названию игры'), findsNothing);
  });
}
