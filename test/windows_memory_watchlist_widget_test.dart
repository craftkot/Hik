import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_live_memory.dart';
import 'package:game_lab/widgets/live_memory_panel.dart';

class _MockWindowsMemory extends WindowsLiveMemoryService {
  int snapshotCalls = 0;
  int writeCalls = 0;

  @override
  Future<List<LiveGameProcess>> processes() async => const [
    LiveGameProcess(pid: 4242, name: 'TestGame.exe', title: 'Offline Test'),
  ];

  @override
  Future<LiveMemoryScan> scan({
    required int pid,
    required String value,
    required LiveValueFormat format,
    int budgetMiB = 512,
    int maxResults = 3000,
  }) async {
    expect(pid, 4242);
    return const LiveMemoryScan(
      addresses: ['0x123456'], scannedBytes: 4096,
      truncated: false, regions: 1);
  }

  @override
  Future<LiveMemoryScan> compare({
    required int pid,
    required LiveValueFormat format,
    required List<String> addresses,
    required List<String> baselines,
    required LiveChangeMode mode,
  }) async {
    expect(pid, 4242);
    expect(mode, LiveChangeMode.snapshot);
    expect(addresses, ['0x123456']);
    snapshotCalls++;
    return LiveMemoryScan(
      addresses: const ['0x123456'],
      values: [snapshotCalls == 1 ? '99' : '98'],
      scannedBytes: 4, truncated: false, regions: 1);
  }

  @override
  Future<void> write({
    required int pid,
    required LiveValueFormat format,
    required String address,
    required String expected,
    required String replacement,
  }) async {
    writeCalls++;
    throw StateError('Read-only test must not write');
  }
}

void main() {
  testWidgets('watchlist polls only pinned RAM candidates without any writes',
      (tester) async {
    if (!Platform.isWindows) return;
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _MockWindowsMemory();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: LiveMemoryPanel(service: service),
      )),
    ));
    await tester.tap(find.text('Найти окна'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('TestGame.exe').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField,
        'Текущее число из игры, например 120'), '100');
    await tester.tap(find.text('Первый поиск'));
    await tester.pumpAndSettle();

    expect(find.text('0x123456'), findsOneWidget);
    await tester.tap(find.byTooltip('Отслеживать адрес'));
    await tester.pumpAndSettle();
    expect(find.textContaining('НАБЛЮДЕНИЕ'), findsOneWidget);
    expect(find.text('100'), findsWidgets);

    await tester.tap(find.text('Читать каждые 2 сек'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(service.snapshotCalls, 1);
    expect(find.text('99'), findsOneWidget);
    expect(service.writeCalls, 0);

    await tester.tap(find.text('Остановить чтение'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(service.snapshotCalls, 1);
    expect(service.writeCalls, 0);

    await tester.tap(find.byTooltip('Убрать адрес 0x123456'));
    await tester.pump();
    expect(find.text('Читать каждые 2 сек'), findsNothing);
  });
}
