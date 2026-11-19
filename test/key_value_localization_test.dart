import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/translation_service.dart';

void main() {
  test('only genuine .lang/.properties locales are offered', () {
    GameFile file(String name, String path) => GameFile(
        id: path, name: name, relativePath: path, size: 100);
    expect(file('en_us.lang', 'assets/game/lang/en_us.lang')
        .isKeyValueLocale, isTrue);
    expect(file('messages.properties', 'locales/messages.properties')
        .isKeyValueLocale, isTrue);
    expect(file('strings.properties', 'resources/strings.properties')
        .isKeyValueLocale, isTrue);
    expect(file('en.properties', 'resources/en.properties')
        .isKeyValueLocale, isTrue);
    expect(file('config.properties', 'config/config.properties')
        .isKeyValueLocale, isFalse);
    expect(file('en.properties', 'saves/en.properties')
        .isKeyValueLocale, isFalse);
    expect(file('strings.properties', 'settings/strings.properties')
        .isKeyValueLocale, isFalse);
    expect(file('translation.ini', 'lang/translation.ini')
        .isKeyValueLocale, isFalse);
  });

  test('preserves keys, comments, CRLF, blank lines and game tokens', () async {
    final translator = LocaleTranslator(
      target: 'ru',
      translateText: (text) async {
        if (text.contains('Hello')) {
          return text.replaceFirst('Hello', 'Привет');
        }
        if (text.contains('Press')) {
          return text.replaceFirst('Press', 'Нажмите')
              .replaceFirst('to start', 'для начала');
        }
        if (text.contains('New game')) {
          return text.replaceFirst('New game', 'Новая игра');
        }
        return text;
      },
    );
    const input = '! header\r\n# comment with = signs\r\n\r\n'
        'menu.title = Hello world  \r\n'
        'menu.tip: Press {player} to start %1\$s\\nNow\r\n'
        'menu.color=New game §a &b\r\n'
        'server.port=25565\r\n'
        'enabled=true\r\n'
        'texture=assets/ui/title.png\r\n'
        'escaped=\\u041F\\u0440\\u0438\\u0432\\u0435\\u0442\r\n'
        'continuation=Hello\\\r\n'
        '  another part\r\n'
        'empty=   \r\n';
    final output = await translator.translateKeyValue(input);
    expect(output, contains('menu.title = Привет world  \r\n'));
    expect(output,
        contains('menu.tip: Нажмите {player} для начала %1\$s\\nNow\r\n'));
    expect(output, contains('menu.color=Новая игра §a &b\r\n'));
    expect(output, contains('! header\r\n# comment with = signs\r\n\r\n'));
    expect(output, contains('server.port=25565\r\n'));
    expect(output, contains('enabled=true\r\n'));
    expect(output, contains('texture=assets/ui/title.png\r\n'));
    expect(output, contains('escaped=\\u041F\\u0440\\u0438\\u0432\\u0435\\u0442\r\n'));
    expect(output, contains('continuation=Hello\\\r\n  another part\r\n'));
    expect(output, contains('empty=   \r\n'));
    expect(output.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(translator.translated, 3);
  });

  test('skips ambiguous syntax and honors bounded translation batches', () async {
    final translator = LocaleTranslator(
      target: 'ru',
      maxStrings: 1,
      translateText: (text) async => 'Пуск',
    );
    const input = 'start=Start\nsecond=Welcome\n'
        'not a key = Hello\n[section]\n'
        '; comment\nname.with\\=escape=Hello\n';
    final output = await translator.translateKeyValue(input);
    expect(output, 'start=Пуск\nsecond=Welcome\n'
        'not a key = Hello\n[section]\n'
        '; comment\nname.with\\=escape=Hello\n');
    expect(translator.translated, 1);
  });

  test('rejects translator output that adds a property line', () async {
    final translator = LocaleTranslator(
      target: 'ru',
      translateText: (_) async => 'Привет\nmalicious.key=changed',
    );
    await expectLater(
      translator.translateKeyValue('hello=Hello world'),
      throwsFormatException,
    );
  });

  test('does not translate a non-localized config-looking entry', () async {
    var sent = 0;
    final translator = LocaleTranslator(
      target: 'ru',
      translateText: (text) async {
        sent++;
        return text;
      },
    );
    const input = 'version=New version\n'
        'file.path=Open file\n'
        'server.url=Open server\n'
        'enabled=on\n'
        'source=\\u0048\\u0069\n'
        'literal=Hello\\! world\n'
        'inline=Hello # comment\n'
        'another = \n';
    expect(await translator.translateKeyValue(input), input);
    expect(sent, 0);
  });
}
