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

  test('non-Windows helper refuses operation instead of process access',
      () async {
    final service = WindowsLiveMemoryService();
    // This test only verifies cross-platform availability reporting and
    // avoids any live RAM interaction in CI runners.
    expect(service.helperPath, contains('EHTID-MemoryHelper.exe'));
    service.cancel();
  });
}
