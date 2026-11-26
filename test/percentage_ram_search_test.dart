import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/windows_live_memory.dart';
import 'package:game_lab/core/screen_number_ocr.dart';

class _FakeMemory extends WindowsLiveMemoryService {
  final calls = <(LiveValueFormat,String,int,bool)>[];
  @override
  Future<LiveMemoryScan> scan({
    required int pid, required String value, required LiveValueFormat format,
    int budgetMiB = 512, int maxResults = 3000, bool bytewise = false,
  }) async {
    expect(pid, 42);
    calls.add((format,value,budgetMiB,bytewise));
    return const LiveMemoryScan(addresses: ['0x123456'], scannedBytes: 32,
        truncated: false, regions: 1);
  }
}

void main() {
  test('percent encoding covers integers, ratios, basis points and decimal comma', () {
    expect(LivePercentEncoding.int32Points.encode('80%'), '80');
    expect(LivePercentEncoding.float32Ratio.encode('80%'), '0.8');
    expect(LivePercentEncoding.float64Ratio.encode('200%'), '2');
    expect(LivePercentEncoding.int32Basis.encode('12,50 %'), '1250');
    expect(LivePercentEncoding.float64Ratio.encode('29%'), '0.29');
    expect(LivePercentEncoding.float32Ratio.encode('-0.5%'), '-0.005');
    expect(LivePercentEncoding.int64Points.encode('80.00'), '80');
    expect(LivePercentEncoding.float32Ratio.display('0.8'), '80.0%');
    expect(() => LivePercentEncoding.int32Points.encode('12.5%'), throwsFormatException);
    expect(() => LivePercentEncoding.int32Points.encode('NaN%'), throwsFormatException);
    expect(() => LivePercentEncoding.int32Basis.encode('99999999999%'), throwsFormatException);
  });

  test('automatic scans retain separate typed results, skip impossible encodings', () async {
    final service = _FakeMemory();
    final groups = await service.scanPercent(pid: 42, percent: '80%', budgetMiB: 128,
        bytewise: true);
    expect(groups.length, 8);
    expect(service.calls, contains((LiveValueFormat.float32,'0.8',128,true)));
    expect(service.calls, contains((LiveValueFormat.float64,'80',128,true)));
    expect(service.calls, contains((LiveValueFormat.int32,'8000',128,true)));
    expect(groups.every((g) => g.scan.addresses.single == '0x123456'), isTrue);
    service.calls.clear();
    final fractional = await service.scanPercent(pid: 42, percent: '12.5%');
    expect(fractional.length, 6);
    expect(service.calls, isNot(contains((LiveValueFormat.int32,'12',512,false))));
    service.calls.clear();
    await service.scanPercent(pid: 42, percent: '80%',
        shouldContinue: () => service.calls.length < 2);
    expect(service.calls.length, 2);
  });

  test('OCR preserves percentage as a hint without changing numeric token', () {
    final tokens = ScreenNumberOcr.parseTsv(
        'left\ttop\twidth\theight\tconf\ttext\n'
        '0\t0\t20\t20\t95\t80%\n'
        '50\t0\t20\t20\t95\t200 %\n');
    expect(tokens.map((t) => t.value), ['80','200']);
    expect(tokens.every((t) => t.isPercent), isTrue);
    expect(ScreenNumberOcr.atPoint(tokens, 5, 5)?.isPercent, isTrue);
  });
}
