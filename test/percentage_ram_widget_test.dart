import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_live_memory.dart';
import 'package:game_lab/widgets/live_memory_panel.dart';

class _PercentMemory extends WindowsLiveMemoryService {
  int scans = 0;
  int refinements = 0;
  final writes = <(LiveValueFormat,String,String,int?)>[];

  @override
  Future<List<LiveGameProcess>> processes() async => const [
    LiveGameProcess(pid: 4242, name: 'TestGame.exe', title: 'Offline Test',
        processStartTicks: 98765),
  ];

  @override
  Future<LiveMemoryScan> scan({
    required int pid, required String value, required LiveValueFormat format,
    int budgetMiB = 512, int maxResults = 3000, bool bytewise = false,
  }) async {
    scans++;
    final hit = format == LiveValueFormat.float32 && value == '0.8';
    return LiveMemoryScan(addresses: hit ? const ['0x123456'] : const [],
        scannedBytes: 32, truncated: false, regions: 1);
  }

  @override
  Future<LiveMemoryScan> refine({
    required int pid, required String value, required LiveValueFormat format,
    required List<String> addresses,
  }) async {
    refinements++;
    expect(format, LiveValueFormat.float32);
    expect(value, '0.85');
    expect(addresses, ['0x123456']);
    return const LiveMemoryScan(addresses: ['0x123456'],
        scannedBytes: 4, truncated: false, regions: 1);
  }

  @override
  Future<void> write({
    required int pid, required LiveValueFormat format,
    required String address, required String expected,
    required String replacement, int? processStartTicks,
  }) async {
    expect(pid, 4242);
    expect(address, '0x123456');
    writes.add((format,expected,replacement,processStartTicks));
  }
}

void main() {
  testWidgets('percent scan, refinement, explicit typed edit and undo', (tester) async {
    if (!Platform.isWindows) return;
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _PercentMemory();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: LiveMemoryPanel(service: service)),
    )));
    await tester.tap(find.text('Найти окна'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('TestGame.exe').last);
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Текущее число из игры, например 120');
    await tester.enterText(input, '80%');
    await tester.tap(find.byKey(const Key('percent-ram-scan')));
    await tester.pumpAndSettle();
    expect(service.scans, 8);
    expect(service.writes, isEmpty);
    await tester.enterText(input, '85%');
    await tester.tap(find.byKey(const Key('refine-all-percent')));
    await tester.pumpAndSettle();
    expect(service.refinements, 1);
    expect(service.writes, isEmpty);
    await tester.tap(find.text('Float32 · коэффициент: 1'));
    await tester.pumpAndSettle();
    expect(find.text('85.0%'), findsOneWidget);
    final address = find.text('0x123456');
    await tester.ensureVisible(address);
    await tester.tap(address);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,
        'Новый процент (например 95%)'), '95%');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверить и записать'));
    await tester.pumpAndSettle();
    expect(service.writes, [(LiveValueFormat.float32,'0.85','0.95',98765)]);
    final undo = find.text('Откатить запись');
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(service.writes.last, (LiveValueFormat.float32,'0.95','0.85',98765));
  });
}
