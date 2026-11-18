import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/android_app_save_discovery.dart';
import 'package:game_lab/core/storage_service.dart';
import 'package:game_lab/widgets/installed_app_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const app = InstalledGameApp(
    packageName: 'com.example.starrail',
    label: 'Star Rail',
    isGame: true,
  );
  const publicTree =
      'content://com.android.externalstorage.documents/tree/primary%3ADocuments';

  test('selected application preserves the full identity in virtual root', () {
    final decoded = InstalledGameApp.fromVirtualFolder(app.virtualFolder);
    expect(decoded.packageName, app.packageName);
    expect(decoded.label, app.label);
    expect(
      () => InstalledGameApp.fromVirtualFolder('ehtid-app://no-package'),
      throwsFormatException,
    );
  });

  test('recognizes authorized game paths but not other apps', () {
    expect(AndroidAppSaveDiscovery.matches(
      app: app, treeUri: publicTree,
      relativePath: 'StarRail/saves/player.json',
    ), isTrue);
    expect(AndroidAppSaveDiscovery.matches(
      app: app, treeUri: publicTree,
      relativePath: 'games/com.example.starrail/slot1.dat',
    ), isTrue);
    expect(AndroidAppSaveDiscovery.matches(
      app: app, treeUri: publicTree,
      relativePath: 'games/com.example.starrail.beta/slot1.dat',
    ), isFalse);
    expect(AndroidAppSaveDiscovery.matches(
      app: app, treeUri: publicTree,
      relativePath: 'othergame/slot1.dat',
    ), isFalse);
    expect(AndroidAppSaveDiscovery.matches(
      app: app,
      treeUri: 'content://com.android.externalstorage.documents/tree/'
          'primary%3ADocuments%2FStarRail',
      relativePath: 'slot1.dat',
    ), isTrue);
    expect(AndroidAppSaveDiscovery.matches(
      app: app, treeUri: 'file:///storage/emulated/0',
      relativePath: 'StarRail/player.json',
    ), isFalse);
  });

  test('Android app search stays inside previously granted SAF folders',
      () async {
    const channel = MethodChannel('ehtid.gamelab/storage');
    final scanned = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listInstalledApps':
          return [
            {'package': 'com.example.starrail', 'label': 'Star Rail',
              'isGame': true},
          ];
        case 'grantedFolders':
          return [publicTree];
        case 'linkedGameFolders':
          return <String>[];
        case 'scanFolder':
          final uri = (call.arguments as Map)['uri'] as String;
          scanned.add(uri);
          return [
            {'uri': 'content://game-save', 'name': 'player.json',
              'relativePath': 'StarRail/save/player.json', 'size': 80},
            {'uri': 'content://other-save', 'name': 'slot.dat',
              'relativePath': 'OtherGame/save/slot.dat', 'size': 80},
          ];
        default:
          throw PlatformException(code: 'unexpected');
      }
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final storage = AndroidGameStorage();
    final apps = await storage.listInstalledApps();
    expect(apps, hasLength(1));
    expect(apps.single.isGame, isTrue);
    final files = await storage.scan(apps.single.virtualFolder);
    expect(files.map((f) => f.name), ['player.json']);
    expect(scanned, [publicTree]);
  });

  test('explicitly linked folder is searched even without a game-like name',
      () async {
    const channel = MethodChannel('ehtid.gamelab/storage');
    const customRoot =
        'content://com.android.externalstorage.documents/tree/primary%3ADownload';
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      switch (call.method) {
        case 'grantedFolders':
          return [customRoot];
        case 'linkedGameFolders':
          return [customRoot];
        case 'scanFolder':
          return [
            {'uri': 'content://save', 'name': 'userdata.bin',
              'relativePath': 'unknown-folder/userdata.bin', 'size': 18},
          ];
        case 'linkGameFolder':
          return true;
      }
      throw PlatformException(code: 'unexpected');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final storage = AndroidGameStorage();
    await storage.linkFolderToApp(app, customRoot);
    final files = await storage.scan(app.virtualFolder);
    expect(files.map((f) => f.name), ['userdata.bin']);
    expect(commands, [
      'linkGameFolder', 'grantedFolders', 'linkedGameFolders', 'scanFolder',
    ]);
  });

  test('no previously granted SAF folders means no automatic access',
      () async {
    const channel = MethodChannel('ehtid.gamelab/storage');
    final commands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      commands.add(call.method);
      if (call.method == 'grantedFolders') return <String>[];
      throw PlatformException(code: 'Unexpected file read');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final files = await AndroidGameStorage().scan(app.virtualFolder);
    expect(files, isEmpty);
    expect(commands, ['grantedFolders']);
  });

  testWidgets('picker filters by name and returns package on tap',
      (tester) async {
    InstalledGameApp? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) =>
        TextButton(onPressed: () async {
          selected = await showInstalledAppPicker(context, const [
            app,
            InstalledGameApp(
              packageName: 'com.example.other',
              label: 'Other Game'),
          ]);
        }, child: const Text('Open')))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rail');
    await tester.pumpAndSettle();
    expect(find.text('Star Rail'), findsOneWidget);
    expect(find.text('Other Game'), findsNothing);
    await tester.tap(find.text('Star Rail'));
    await tester.pumpAndSettle();
    expect(selected?.packageName, 'com.example.starrail');
  });
}
