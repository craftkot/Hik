import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/json_editor.dart';
import 'package:game_lab/core/save_value_priority.dart';
import 'package:game_lab/widgets/save_field_browser.dart';

const source = '{"player":{"name":"Alex","quest":7,"hp":90,'
    '"gold":300,"strength":15,"mana":40,"level":5}}';

void main() {
  final fields = prioritizeJsonFields(listJsonFields(source));

  test('search and categories preserve field pointer and sorted order', () {
    final before = fields.map((field) => field.pointer).toList();
    final allImportant = filterSaveFields(fields, onlyImportant: true);
    expect(allImportant.every((field) => field.category.important), isTrue);
    expect(allImportant.map((field) => field.pointer),
        ['/player/gold', '/player/hp', '/player/mana',
          '/player/strength', '/player/level']);

    final hpOnly = filterSaveFields(fields,
        category: SaveValueCategory.health);
    expect(hpOnly.map((field) => field.pointer), ['/player/hp']);
    expect(filterSaveFields(fields, query: 'STRENGTH')
        .single.pointer, '/player/strength');
    expect(filterSaveFields(fields, query: '300')
        .single.pointer, '/player/gold');
    expect(filterSaveFields(fields, query: 'unrealistic'), isEmpty);
    expect(fields.map((field) => field.pointer), before);
  });

  testWidgets('filters key stats by category and shows count',
      (tester) async {
    tester.view.physicalSize = const Size(1250, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? edited;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(height: 700,
        child: SaveFieldBrowser(
          fields: fields,
          onClose: () {},
          onEdit: (field) async {
            edited = field.pointer;
            return false;
          },
        ),
      )),
    ));

    expect(find.textContaining('Важные поля сначала'), findsOneWidget);
    expect(find.text('/player/gold'), findsOneWidget);
    expect(find.text('/player/quest'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'HP / здоровье'));
    await tester.pumpAndSettle();
    expect(find.text('/player/hp'), findsOneWidget);
    expect(find.text('/player/gold'), findsNothing);
    expect(find.text('Показано: 1'), findsOneWidget);

    await tester.tap(find.text('/player/hp'));
    await tester.pumpAndSettle();
    expect(edited, '/player/hp');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Все'));
    await tester.pumpAndSettle();
    expect(find.text('/player/gold'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('/player/quest'), findsNothing);
    expect(find.text('/player/hp'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mana');
    await tester.pumpAndSettle();
    expect(find.text('/player/mana'), findsOneWidget);
    expect(find.text('/player/hp'), findsNothing);
  });

  testWidgets('empty filter can be reset and generic JSON stays usable',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(height: 670,
        child: SaveFieldBrowser(
          fields: fields, isSave: false,
          onClose: () {}, onEdit: (_) async => false,
        ),
      )),
    ));
    expect(find.text('Только важные'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.enterText(find.byType(TextField), 'not-a-field');
    await tester.pumpAndSettle();
    expect(find.text('Подходящих полей не найдено'), findsOneWidget);
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('/player/name'), findsOneWidget);
  });
}
