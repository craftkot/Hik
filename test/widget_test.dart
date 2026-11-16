import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/main.dart';

void main() {
  testWidgets('App exposes the four sections', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GameLabApp());
    expect(find.text('Предзагрузки'), findsWidgets);
    expect(find.text('Редактор сохранений'), findsOneWidget);
    expect(find.text('Перевод игры'), findsOneWidget);
    expect(find.text('Читы (соло)'), findsOneWidget);
  });
}
