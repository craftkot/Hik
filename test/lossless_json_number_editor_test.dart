import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/lossless_json_number_editor.dart';

void main() {
  test('Change one scalar without touching other JSON chars', () {
    const input = '  {"player":{ "hp" : 120, "gold":1,'
        ' "name":"Z", "other":[4,5] }}\r\n';
    final output = LosslessJsonNumberEditor.change(input,
        pointer: '/player/hp', expected: 120, replacement: '999');
    expect(output, input.replaceFirst('120', '999'));
  });

  test('Works for JSON Pointer arrays and escaped keys', () {
    const input = '{"a/b":{"tilde~":[{"gold":20}, {"gold":30}]}}';
    final output = LosslessJsonNumberEditor.change(input,
        pointer: '/a~1b/tilde~0/1/gold', expected: 30, replacement: '12345');
    expect(output, '{"a/b":{"tilde~":[{"gold":20}, {"gold":12345}]}}');
  });

  test('Rejects duplicate paths instead of modifying an arbitrary key', () {
    const input = '{"hp":10,"hp":10}';
    expect(() => LosslessJsonNumberEditor.change(input,
        pointer: '/hp', expected: 10, replacement: '99'), throwsStateError);
  });

  test('Rejects stale values, invalid numbers and wrong pointer', () {
    const input = '{"player":{"hp":120}}';
    expect(() => LosslessJsonNumberEditor.change(input,
        pointer: '/player/hp', expected: 121, replacement: '999'),
        throwsStateError);
    expect(() => LosslessJsonNumberEditor.change(input,
        pointer: '/player/hp', expected: 120, replacement: 'NaN'),
        throwsFormatException);
    expect(() => LosslessJsonNumberEditor.change(input,
        pointer: '/player/hp', expected: 120, replacement: 'Infinity'),
        throwsFormatException);
    expect(() => LosslessJsonNumberEditor.change(input,
        pointer: '/player/coins', expected: 120, replacement: '999'),
        throwsStateError);
  });

  test('Only intended raw bytes change after UTF-8/GZIP roundtrip', () {
    const original = '{"nick":"Яна","hp":120,"gold":500,"note":"a\\nb"}';
    final result = LosslessJsonNumberEditor.change(original,
        pointer: '/hp', expected: 120, replacement: '999');
    expect(result, original.replaceFirst('120', '999'));
  });
}
