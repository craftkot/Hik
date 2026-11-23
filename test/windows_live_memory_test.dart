import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_live_memory.dart';

void main() {
  test('all four local-game memory formats have correct widths', () {
    expect(LiveValueFormat.int32.code, 'i32');
    expect(LiveValueFormat.int64.width, 8);
    expect(LiveValueFormat.float32.width, 4);
    expect(LiveValueFormat.float64.code, 'f64');
  });

  test('numeric validation rejects overflow and non-finite input', () {
    WindowsLiveMemoryService.validateValue(
        '-2147483648', LiveValueFormat.int32);
    WindowsLiveMemoryService.validateValue(
        '9223372036854775807', LiveValueFormat.int64);
    WindowsLiveMemoryService.validateValue(
        '123.5', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue(
        '0,25', LiveValueFormat.float64);

    expect(() => WindowsLiveMemoryService.validateValue(
        '2147483648', LiveValueFormat.int32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '9223372036854775808', LiveValueFormat.int64), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        'NaN', LiveValueFormat.float32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        'Infinity', LiveValueFormat.float64), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '1e100', LiveValueFormat.float32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '1e-46', LiveValueFormat.float32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '-1e-50', LiveValueFormat.float32), throwsFormatException);
    WindowsLiveMemoryService.validateValue('0', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue('1e-44', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue('1e-45', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue('-1e-45', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue('1.401298464324817e-45', LiveValueFormat.float32);
    WindowsLiveMemoryService.validateValue('-1.401298464324817e-45', LiveValueFormat.float32);
    expect(() => WindowsLiveMemoryService.validateValue(
        '1e-324', LiveValueFormat.float64), throwsFormatException);
    WindowsLiveMemoryService.validateValue('1e-46', LiveValueFormat.float64);
    expect(() => WindowsLiveMemoryService.validateValue(
        '1e-400', LiveValueFormat.float32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '-1e-400', LiveValueFormat.float64), throwsFormatException);
    WindowsLiveMemoryService.validateValue('-0.0', LiveValueFormat.float64);
    WindowsLiveMemoryService.validateValue('0e-400', LiveValueFormat.float32);
    expect(() => WindowsLiveMemoryService.validateValue(
        '', LiveValueFormat.int32), throwsFormatException);
    expect(() => WindowsLiveMemoryService.validateValue(
        '12.3', LiveValueFormat.int32), throwsFormatException);
  });

  test('parse limited address candidates and refuse invalid helper results', () {
    final result = LiveMemoryScan.fromJson({
      'addresses': ['0x12345', '0xABCDFA'],
      'scannedBytes': 1048576,
      'regions': 20,
      'truncated': false,
    });
    expect(result.addresses, ['0x12345', '0xABCDFA']);
    expect(result.scannedBytes, 1048576);
    expect(result.regions, 20);
    expect(result.truncated, false);
    expect(() => result.addresses.add('0x12345'), throwsUnsupportedError);
    expect(() => LiveMemoryScan.fromJson({
      'addresses': ['garbage'],
    }), throwsFormatException);
    expect(() => LiveMemoryScan.fromJson({
      'addresses': List.filled(5001, '0x12345'),
    }), throwsFormatException);
  });

  test('relative refinement modes and value snapshots are validated', () {
    expect(LiveChangeMode.values.map((mode) => mode.code), [
      'all', 'changed', 'unchanged', 'increased', 'decreased',
    ]);
    final data = LiveMemoryScan.fromJson({
      'addresses': ['0x12345', '0x23456'],
      'values': ['-12', '1.25E+12'],
      'truncated': false,
    });
    expect(data.values, ['-12', '1.25E+12']);
    expect(data.invalidated, 0);
    final snapshot = LiveMemoryScan.fromJson({
      'addresses': ['0x12345'],
      'values': ['600'],
      'invalidated': 2,
    });
    expect(snapshot.addresses, ['0x12345']);
    expect(snapshot.values, ['600']);
    expect(snapshot.invalidated, 2);
    expect(() => data.values.add('0'), throwsUnsupportedError);
    expect(() => LiveMemoryScan.fromJson({
      'addresses': ['0x12345'],
      'values': ['1', '2'],
    }), throwsFormatException);
    expect(() => LiveMemoryScan.fromJson({
      'addresses': ['0x12345'],
      'values': ['NaN'],
    }), throwsFormatException);
    expect(() => LiveMemoryScan.fromJson({
      'addresses': ['0x12345'],
      'values': ['not-a-number'],
    }), throwsFormatException);
  });

  test('compare refuses invalid candidate list before starting helper', () async {
    final service = WindowsLiveMemoryService();
    await expectLater(service.compare(
      pid: 999, format: LiveValueFormat.int32,
      mode: LiveChangeMode.changed,
      addresses: ['0x12345'],
      baselines: [],
    ), throwsFormatException);
    await expectLater(service.compare(
      pid: 999, format: LiveValueFormat.int64,
      mode: LiveChangeMode.increased,
      addresses: ['0x12345'],
      baselines: ['9223372036854775808'],
    ), throwsFormatException);
    await expectLater(service.compare(
      pid: 999, format: LiveValueFormat.int32,
      mode: LiveChangeMode.unchanged,
      addresses: ['malformed'],
      baselines: ['100'],
    ), throwsFormatException);
  });

  test('deep scan bounds CPU and memory before opening any process', () async {
    final service = WindowsLiveMemoryService();
    await expectLater(service.scan(
      pid: 42, value: '100', format: LiveValueFormat.int32,
      budgetMiB: 513, bytewise: true,
    ), throwsRangeError);
    await expectLater(service.scan(
      pid: 42, value: '100', format: LiveValueFormat.int64,
      budgetMiB: 2049,
    ), throwsRangeError);
    await expectLater(service.scan(
      pid: 42, value: '100', format: LiveValueFormat.int32,
      maxResults: 5001,
    ), throwsRangeError);
    await expectLater(service.scan(
      pid: 42, value: '100', format: LiveValueFormat.int32,
      maxResults: 0,
    ), throwsRangeError);
  });

  test('RAM writes require a fresh process identity before launching helper', () async {
    final service = WindowsLiveMemoryService();
    await expectLater(service.write(
      pid: 4242, format: LiveValueFormat.int32, address: '0x12345',
      expected: '100', replacement: '200',
    ), throwsStateError);
    await expectLater(service.write(
      pid: 4242, processStartTicks: 0, format: LiveValueFormat.int32,
      address: '0x12345', expected: '100', replacement: '200',
    ), throwsStateError);
  });

  test('non-Windows helper refuses operation instead of process access',
      () async {
    final service = WindowsLiveMemoryService();
    // This test only verifies cross-platform availability reporting and
    // avoids any live RAM interaction in CI runners.
    expect(service.helperPath, contains('EHTID-MemoryHelper.exe'));
    service.cancel();
  });
}
