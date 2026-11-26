import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/gzip_save_codec.dart';
import 'package:game_lab/core/important_save_fields.dart';
import 'package:game_lab/core/nested_save_fields.dart';

void main() {
  test('nested state uses logical variable names and preserves history', () {
    final inner = '{"LocalVariableMap":{"keys":["gold","day","flag"],'
        '"values":["120","5","False"]},"note":"unchanged"}';
    final outer = jsonEncode({
      'objectJsonMap': {
        'keys': ['Example.VariableManager, Assembly', 'Example.Camera'],
        'values': [inner, '{"x":1,"y":2}'],
      },
      'rollbackStackJson': jsonEncode({'gold': 777}),
      'thumbnailBase64': 'unrelated',
    });
    final fields = NestedSaveFields.inspect(outer);
    expect(fields.map((f) => f.name), ['gold', 'day', 'flag']);
    final changed = NestedSaveFields.change(outer, fields.first, '9000');
    expect(changed, outer.replaceFirst('120', '9000'));
    final saved = GzipSaveCodec.encode(Uint8List.fromList(utf8.encode(changed)));
    expect(utf8.decode(GzipSaveCodec.decode(saved)), changed);
    final after = NestedSaveFields.inspect(changed);
    expect(after.first.value, '9000');
    final toggle = NestedSaveFields.change(changed, after.last, 'true');
    expect(toggle, changed.replaceFirst('False', 'True'));
    expect(jsonDecode(toggle)['rollbackStackJson'],
        jsonDecode(outer)['rollbackStackJson']);
  });

  test('handles nested numeric JSON and retains literal escapes', () {
    // The escaped Unicode character and escaped slash must not be rewritten.
    const source = r'{"data":{"value":"{\"hp\":10,\"other\":\"\u0041\/B\"}"}}';
    final fields = ImportantSaveInspector.inspectText(source);
    expect(fields.length, 1);
    expect(fields.single.name, 'hp');
    final output = NestedSaveFields.change(
        source, fields.single.nested!, '999');
    expect(output, source.replaceFirst('10', '999'));
    expect(NestedSaveFields.inspect(output).single.value, 999);
  });

  test('rejects stale paths, duplicate keys and invalid values', () {
    final source = jsonEncode({
      'variables': {'keys':['gold'], 'values':['100']},
    });
    final field = NestedSaveFields.inspect(source).single;
    expect(() => NestedSaveFields.change(source, field, '1.5'),
        throwsFormatException);
    expect(() => NestedSaveFields.change(
        source.replaceFirst('gold', 'cash'), field, '900'),
        throwsStateError);
    expect(NestedSaveFields.inspect(
        '{"variables":{"keys":["gold","gold"],"values":["1","2"]}}'),
        isEmpty);
  });

  test('wrapped image is separated from game values', () {
    final data = Uint8List.fromList([
      137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,
    ]);
    final source = jsonEncode({'data': {
      '__type': 'System.Byte[],mscorlib', 'value': base64Encode(data),
    }});
    expect(NestedSaveFields.wrappedImage(source), data);
    expect(ImportantSaveInspector.inspectText(source), isEmpty);
    expect(NestedSaveFields.wrappedImage(
        '{"data":{"__type":"System.String","value":"hello"}}'), isNull);
  });
}
