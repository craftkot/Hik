import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/ini_save_editor.dart';
import 'package:game_lab/widgets/ini_save_field_browser.dart';

void main() {
  testWidgets('INI browser prioritizes and filters numeric save fields',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fields = IniSaveEditor.prioritize(IniSaveEditor.inspect(
      '[Player]\nname=Alex\nhp=80\ncoins=123\nmana=20\nquest=7\n'));
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(height: 680,
        child: IniSaveFieldBrowser(
          fields: fields, onClose: () {},
          onEdit: (field) async {
            selected = field.displayPath;
            return false;
          },
        ),
      )),
    ));
    expect(find.text('Числовые поля · INI / CFG'), findsOneWidget);
    expect(find.text('Player / coins'), findsOneWidget);
    expect(find.text('Player / hp'), findsOneWidget);
    expect(find.text('Player / quest'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hp');
    await tester.pumpAndSettle();
    expect(find.text('Player / hp'), findsOneWidget);
    expect(find.text('Player / coins'), findsNothing);
    await tester.tap(find.text('Player / hp'));
    await tester.pumpAndSettle();
    expect(selected, 'Player / hp');
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Player / hp'), findsOneWidget);
    expect(find.text('Player / quest'), findsNothing);
  });
}
