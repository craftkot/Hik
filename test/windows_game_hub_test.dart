import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/widgets/windows_game_hub.dart';

void main() {
  testWidgets('game selection opens actions only after a folder is chosen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var installedClicks = 0;
    var saveClicks = 0;

    WindowsGameHub hub(String? folder) => WindowsGameHub(
      folder: folder,
      gameName: folder == null ? null : 'Test Game',
      engine: 'Unity',
      fileCount: 7,
      busy: false,
      onChooseInstalled: () => installedClicks++,
      onChooseFolder: () {},
      onSaves: () => saveClicks++,
      onCheats: () {},
      onTranslation: () {},
      onResources: () {},
      onFindSaves: () {},
    );

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: hub(null)),
    ));
    expect(find.text('Выбери игру'), findsOneWidget);
    expect(find.text('Сохранения'), findsNothing);
    await tester.tap(find.text('Установленные игры'));
    expect(installedClicks, 1);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: hub('C:/Games/Test')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Test Game'), findsOneWidget);
    expect(find.text('Сохранения'), findsOneWidget);
    expect(find.textContaining('Файлов: 7'), findsOneWidget);
    await tester.tap(find.text('Сохранения'));
    expect(saveClicks, 1);
  });
}
