import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/screen_menu_values.dart';

void main() {
  test('menu list splits spaced HP pair, and preserves percent suffix', () {
    final values = ScreenMenuValues.parseTsv(
      'left\ttop\twidth\theight\tconf\ttext\n'
      '10\t10\t30\t24\t95\tHP:\n'
      '250\t12\t55\t24\t95\t2750\n'
      '315\t12\t10\t24\t95\t/\n'
      '335\t12\t55\t24\t95\t2750\n'
      '10\t55\t150\t23\t95\tКритический\n'
      '170\t55\t50\t23\t95\tурон:\n'
      '335\t55\t55\t23\t95\t200\n'
      '395\t55\t15\t23\t95\t%\n');
    expect(values.map((v) => v.input), ['2750','2750','200%']);
    expect(values.first.label, 'HP');
    expect(values.first.role, contains('Текущее'));
    expect(values[1].role, contains('Максимум'));
    expect(values.last.label, 'Критический урон');
  });

  test('recognizes joined fractions and different adjacent lines', () {
    final values = ScreenMenuValues.parseTsv(
      'left\ttop\twidth\theight\tconf\ttext\n'
      '10\t10\t60\t20\t95\tHP:80/100\n'
      '10\t40\t60\t20\t95\tMP:\n'
      '200\t40\t55\t20\t95\t12,5\n'
      '10\t90\t60\t20\t20\t999\n');
    expect(values.map((v) => v.input), ['80','100','12.5']);
    expect(values.last.label, 'MP');
  });

  test('rejects invalid TSV and nonnumeric labels', () {
    expect(ScreenMenuValues.parseTsv('invalid'), isEmpty);
    expect(ScreenMenuValues.parseTsv(
      'left\ttop\twidth\theight\tconf\ttext\n'
      '10\t10\t60\t20\t95\tabc123\n'
      '10\t40\t60\t20\tNaN\t123\n'), isEmpty);
  });
}
