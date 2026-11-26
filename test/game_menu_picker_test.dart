import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/widgets/onscreen_number_picker.dart';

void main() {
  testWidgets('menu picker returns the selected maximum HP separately', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0yQAAAAASUVORK5CYII=');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => TextButton(
        child: const Text('Open'),
        onPressed: () async {
          selected = await showDialog<String>(context: context,
            builder: (_) => OnScreenNumberPicker(
              menuMode: true, allowPercent: true, gamePid: 42, gameStartTicks: 1,
              captureOverride: () async => bytes,
              recognizeOverride: (_) async =>
                'left\ttop\twidth\theight\tconf\ttext\n'
                '10\t10\t30\t24\t95\tHP:\n'
                '100\t10\t50\t24\t95\t2500/2750\n'
                '10\t60\t30\t24\t95\tCrit:\n'
                '100\t60\t50\t24\t95\t80%\n',
            ));
        },
      )),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Снять окно игры'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Текущее / левая часть'), findsOneWidget);
    expect(find.text('Максимум / правая часть'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    await tester.tap(find.text('Максимум / правая часть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Найти в памяти'));
    await tester.pumpAndSettle();
    expect(selected, '2750');
  });
}
