import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/screen_number_ocr.dart';

const _tsv = '''
level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
5\t1\t1\t1\t1\t1\t100\t50\t45\t22\t93.50\t125/200
5\t1\t1\t1\t1\t2\t330\t50\t40\t20\t88.00\t75
5\t1\t1\t1\t1\t3\t460\t50\t30\t20\t25.00\t999
5\t1\t1\t1\t1\t4\t600\t50\t30\t20\t91.00\tO00
5\t1\t1\t1\t1\t5\t100\t140\t52\t20\t88.00\t-12,5
''';

void main() {
  test('parse local OCR TSV and extract HP/mana-style numeric labels', () {
    final tokens = ScreenNumberOcr.parseTsv(_tsv);
    expect(tokens.length, 3);
    expect(tokens[0].raw, '125/200');
    expect(tokens[0].value, '125');
    expect(tokens[1].value, '75');
    expect(tokens[2].value, '-12.5');
    expect(tokens.every((token) => token.confidence >= 30), true);
  });

  test('tap selects only the nearest valid OCR number', () {
    final tokens = ScreenNumberOcr.parseTsv(_tsv);
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60)?.value, '125');
    expect(ScreenNumberOcr.atPoint(tokens, 352, 60)?.value, '75');
    expect(ScreenNumberOcr.atPoint(tokens, 165, 60)?.value, '125');
    expect(ScreenNumberOcr.atPoint(tokens, 220, 60), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 130, 155)?.value, '-12.5');
  });

  test('invalid TSV, unsupported values and negative boxes ignored', () {
    expect(ScreenNumberOcr.parseTsv('not tsv'), isEmpty);
    final lines = _tsv.split('\n');
    expect(ScreenNumberOcr.parseTsv(
      '${lines.first}\n'
      '5\t1\t1\t1\t1\t1\t10\t10\t-1\t12\t99\t100\n'
      '5\t1\t1\t1\t1\t2\t10\t10\t20\t12\t95\tabc\n',
    ), isEmpty);
    expect(ScreenNumberOcr.atPoint(const [], 10, 10), isNull);
  });

  test('rejects non-finite confidence, out-of-range scores and negative positions', () {
    const header = 'left\ttop\twidth\theight\tconf\ttext';
    final tokens = ScreenNumberOcr.parseTsv(
      '$header\n'
      '0\t0\t20\t10\tNaN\t123\n'
      '0\t0\t20\t10\tInfinity\t124\n'
      '0\t0\t20\t10\t101\t125\n'
      '-1\t0\t20\t10\t90\t126\n'
      '0\t-1\t20\t10\t90\t127\n'
      '0\t0\t20\t10\t90\t128\n',
    );
    expect(tokens.map((token) => token.value), ['128']);
  });

  test('conflicting equidistant OCR readings require manual confirmation', () {
    const two = [
      ScreenNumberToken(value: '25', raw: '25', left: 50,
        top: 50, width: 25, height: 20, confidence: 50),
      ScreenNumberToken(value: '35', raw: '35', left: 50,
        top: 50, width: 25, height: 20, confidence: 90),
    ];
    expect(ScreenNumberOcr.atPoint(two, 60, 60), isNull);
    expect(ScreenNumberOcr.atPoint(two, 500, 500), isNull);
    expect(ScreenNumberOcr.atPoint(two, 500, 500,
      maxDistance: 1000), isNull);
  });
  test('identical overlapping readings remain selectable', () {
    const same = [
      ScreenNumberToken(value: '25', raw: '25', left: 50,
        top: 50, width: 25, height: 20, confidence: 50),
      ScreenNumberToken(value: '25', raw: '25', left: 50,
        top: 50, width: 25, height: 20, confidence: 90),
    ];
    expect(ScreenNumberOcr.atPoint(same, 60, 60)?.value, '25');
  });

  test('closer unambiguous reading wins over distant conflicting labels', () {
    const tokens = [
      ScreenNumberToken(value: '25', raw: '25', left: 50,
        top: 50, width: 25, height: 20, confidence: 50),
      ScreenNumberToken(value: '35', raw: '35', left: 50,
        top: 50, width: 25, height: 20, confidence: 90),
      ScreenNumberToken(value: '45', raw: '45', left: 100,
        top: 100, width: 10, height: 10, confidence: 80),
    ];
    expect(ScreenNumberOcr.atPoint(tokens, 65, 65), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 105, 105)?.value, '45');
  });

  test('invalid tap coordinates or search radius never select a number', () {
    final tokens = ScreenNumberOcr.parseTsv(_tsv);
    expect(ScreenNumberOcr.atPoint(tokens, double.nan, 60), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 120, double.infinity), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60,
      maxDistance: double.nan), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60,
      maxDistance: double.infinity), isNull);
    // A finite radius may still overflow when squared.
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60,
      maxDistance: 1e200), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60,
      maxDistance: -1), isNull);
    expect(ScreenNumberOcr.atPoint(tokens, 120, 60,
      maxDistance: 0)?.value, '125');
  });

}
