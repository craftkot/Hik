import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/widgets/android_all_files_access_banner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ehtid.gamelab/storage');

  test('all-files status and settings request use Android storage bridge',
      () async {
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      if (call.method == 'allFilesAccessStatus') {
        return {'supported': true, 'granted': false, 'sdk': 35};
      }
      if (call.method == 'requestAllFilesAccess') {
        return 'settings_opened';
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    final storage = AndroidGameStorage();
    final status = await storage.allFilesAccessStatus();
    expect(status.supported, isTrue);
    expect(status.granted, isFalse);
    expect(status.sdk, 35);
    expect(await storage.requestAllFilesAccess(), 'settings_opened');
    expect(commands, ['allFilesAccessStatus', 'requestAllFilesAccess']);
  });

  testWidgets('shows consent action and refreshes when user returns',
      (tester) async {
    var granted = false;
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      if (call.method == 'allFilesAccessStatus') {
        return {'supported': true, 'granted': granted, 'sdk': 35};
      }
      if (call.method == 'requestAllFilesAccess') return 'settings_opened';
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AndroidAllFilesAccessBanner(
        storage: AndroidGameStorage(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Доступ ко всем файлам'), findsOneWidget);
    await tester.tap(find.text('Выдать разрешение'));
    await tester.pumpAndSettle();
    expect(commands, contains('requestAllFilesAccess'));

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Выдать разрешение'), findsNothing);
  });

  testWidgets('SAF remains usable when broad access is unavailable',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'allFilesAccessStatus') {
        return {'supported': false, 'granted': false, 'sdk': 29};
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AndroidAllFilesAccessBanner(
        storage: AndroidGameStorage(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Доступ ко всем файлам'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
