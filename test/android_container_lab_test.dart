import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/widgets/android_container_lab.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ehtid.gamelab/container');

  testWidgets('HTML5 demo can be created then launched inside EHTID',
      (tester) async {
    final calls = <String>[];
    var hasDemo = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'list':
          return hasDemo ? [
            {'id': 'demo-1', 'kind': 'web',
              'name': 'EHTID Test — монеты', 'package': ''},
          ] : <dynamic>[];
        case 'createDemo':
          hasDemo = true;
          return {'id': 'demo-1', 'kind': 'web'};
        case 'run':
          expect((call.arguments as Map)['id'], 'demo-1');
          return 'web_started';
        default:
          throw PlatformException(code: 'unexpected');
      }
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AndroidContainerLab()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Контейнер пуст. Для первого теста создай '
        'игру «монеты», накопи счёт, закрой и запусти повторно.'),
        findsOneWidget);
    await tester.tap(find.text('Создать тестовую игру'));
    await tester.pumpAndSettle();
    expect(find.text('EHTID Test — монеты'), findsOneWidget);
    await tester.tap(find.text('Запустить внутри EHTID'));
    await tester.pumpAndSettle();
    expect(calls, containsAllInOrder(['createDemo', 'run']));
    expect(calls, isNot(contains('install')));
  });

  testWidgets('large APK import advertises streaming and storage guard',
      (tester) async {
    const channel = MethodChannel('ehtid.gamelab/container');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'list') return <dynamic>[];
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AndroidContainerLab()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('APK: до 8 ГиБ'), findsOneWidget);
    expect(find.textContaining('потоковое копирование'), findsOneWidget);
    expect(find.text('Импорт ZIP / APK'), findsOneWidget);
  });

  testWidgets('APK staging offers only Android system installation',
      (tester) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'list') return [
        {'id': 'apk-1', 'kind': 'apk',
          'name': 'Some Game', 'package': 'com.example.game'},
      ];
      if (call.method == 'install') return 'permission_required';
      if (call.method == 'launchExternal') return 'not_installed_or_invisible';
      throw PlatformException(code: 'unexpected');
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AndroidContainerLab()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Some Game'), findsOneWidget);
    expect(find.text('Запустить внутри EHTID'), findsNothing);
    expect(find.text('Установить через Android'), findsOneWidget);
    await tester.tap(find.text('Установить через Android'));
    await tester.pumpAndSettle();
    expect(calls, contains('install'));
    expect(calls, isNot(contains('run')));
  });
}
