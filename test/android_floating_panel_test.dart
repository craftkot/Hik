import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/widgets/android_floating_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android floating panel asks for overlay permission and can start',
      (tester) async {
    const channel = MethodChannel('ehtid.gamelab/overlay');
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      return switch (call.method) {
        'status' => <String, dynamic>{'permission': false, 'supported': true},
        'start' => 'permission_required',
        'stop' => 'stopped',
        _ => null,
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: AndroidFloatingPanel(onSearch: (_) async {})))));
    await tester.pumpAndSettle();
    expect(commands, contains('status'));
    expect(find.text('Запустить поверх игры'), findsOneWidget);
    await tester.tap(find.text('Запустить поверх игры'));
    await tester.pumpAndSettle();
    expect(commands, contains('start'));
    expect(find.textContaining('Открылись настройки'), findsOneWidget);
    await tester.tap(find.text('Остановить'));
    await tester.pumpAndSettle();
    expect(commands, contains('stop'));
  });

  testWidgets('number from overlay is passed to the file-search callback',
      (tester) async {
    const channel = MethodChannel('ehtid.gamelab/overlay');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') return {'permission': true};
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    String? searched;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: AndroidFloatingPanel(initialNumber: '125',
          onSearch: (number) async { searched = number; })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Найти число в сейвах'));
    await tester.pumpAndSettle();
    expect(searched, '125');
  });
}
