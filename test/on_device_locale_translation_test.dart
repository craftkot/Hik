import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/translation_service.dart';

void main() {
  test('local translator keeps JSON keys and game placeholders intact',
      () async {
    final received = <String>[];
    final translator = LocaleTranslator(
      target: 'ru',
      translateText: (masked) async {
        received.add(masked);
        return 'Привет EHTIDTOKEN0KEEP';
      },
    );
    const input = '{"greeting":"Hello {hero}","id":7,"enabled":true}';
    final output = jsonDecode(await translator.translateJson(input)) as Map;
    expect(received.single, contains('EHTIDTOKEN0KEEP'));
    expect(output.keys.toList(), ['greeting', 'id', 'enabled']);
    expect(output['greeting'], 'Привет {hero}');
    expect(output['id'], 7);
    expect(output['enabled'], true);
    expect(translator.translated, 1);
  });

  test('missing placeholder aborts translation before file changes',
      () async {
    final translator = LocaleTranslator(
      target: 'ru',
      translateText: (masked) async => 'Привет',
    );
    await expectLater(
      translator.translateJson('{"text":"Hello %s"}'),
      throwsStateError,
    );
  });
}
