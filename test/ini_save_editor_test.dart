import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/ini_save_editor.dart';
import 'package:game_lab/core/save_value_priority.dart';

void main() {
  const save = '; untouched comment\r\n'
      '[Player]\r\n'
      'hp = 92  ; current health\r\n'
      'gold=00120\r\n'
      'mana=-4.5  # magic\r\n'
      'level=6\r\n'
      '[Inventory]\r\n'
      'gold=37\r\n'
      'enabled=true\r\n'
      'path=C:\\games\\test\r\n';

  test('indexes numeric sections and prioritizes currency, HP, mana, level', () {
    final fields = IniSaveEditor.inspect(save);
    expect(fields, hasLength(6));
    expect(fields.map((f) => f.displayPath), [
      'Player / hp', 'Player / gold', 'Player / mana',
      'Player / level', 'Inventory / gold',
    ].take(5)); // player and inventory fields; none from comments/bool/path
  });

  test('round-trip changes a single numeric span with CRLF and comments intact',
      () {
    final fields = IniSaveEditor.inspect(save);
    final hp = fields.singleWhere((f) =>
        f.section == 'Player' && f.key == 'hp');
    final after = IniSaveEditor.changeNumber(save, hp, '999');
    expect(after, save.replaceFirst('hp = 92', 'hp = 999'));
    expect(after, contains('gold=00120\r\n'));
    expect(after, contains('mana=-4.5  # magic\r\n'));
    expect(after, contains('[Inventory]\r\ngold=37'));
    expect(after.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(IniSaveEditor.inspect(after).length, fields.length);
  });

  test('duplicate keys patch only the chosen section and line', () {
    final fields = IniSaveEditor.inspect(save);
    final inventory = fields.singleWhere((f) =>
      f.section == 'Inventory' && f.key == 'gold');
    final after = IniSaveEditor.changeNumber(save, inventory, '1234');
    expect(after, contains('gold=00120\r\n'));
    expect(after, contains('[Inventory]\r\ngold=1234\r\n'));
    expect(after, isNot(equals(save)));
  });

  test('categories rely on numeric names and preserve source order on ties', () {
    final sorted = IniSaveEditor.prioritize(IniSaveEditor.inspect(save));
    expect(sorted.first.category, SaveValueCategory.currency);
    expect(sorted[1].category, SaveValueCategory.currency);
    expect(sorted[2].category, SaveValueCategory.health);
    expect(sorted[3].category, SaveValueCategory.mana);
    expect(sorted[4].category, SaveValueCategory.level);
  });

  test('rejects changed source and invalid or overflow numeric input', () {
    final hp = IniSaveEditor.inspect(save).first;
    expect(() => IniSaveEditor.changeNumber(save + '# new', hp, '95'),
        returnsNormally); // append-only unrelated text is not rewritten
    expect(() => IniSaveEditor.changeNumber(
        save.replaceFirst('hp = 92', 'hp = 93'), hp, '95'), throwsStateError);
    for (final value in ['1.5', 'inf', 'NaN', '5\ninject=1', '1e1000',
      '9223372036854775808000000000000000000000']) {
      expect(() => IniSaveEditor.changeNumber(save, hp, value),
          throwsFormatException);
    }
  });

  test('fractional fields accept finite decimals, not inserted syntax', () {
    final mana = IniSaveEditor.inspect(save)
        .singleWhere((f) => f.key == 'mana');
    expect(IniSaveEditor.changeNumber(save, mana, '-7.25'),
        contains('mana=-7.25  # magic'));
    expect(() => IniSaveEditor.changeNumber(save, mana, '1e999'),
        throwsFormatException);
    expect(() => IniSaveEditor.changeNumber(save, mana, '12; enabled=true'),
        throwsFormatException);
  });

  test('does not offer multiline escapes, hex, booleans, infinity, sections',
      () {
    const text = '[Game]\nHP=10\n'
        'multi=123\\\ncontinued=9\n'
        'hex=0xFF\nflag=true\nversion=1.2.3\n'
        '#hp=500\nunknown : 99\n'
        'nan=NaN\nhuge=1e999\n';
    final found = IniSaveEditor.inspect(text);
    expect(found.map((f) => f.key), ['HP']);
  });

  test('max fields bounds inspection while preserving file content', () {
    final source = List.generate(300, (i) => 'field$i=$i').join('\n');
    final found = IniSaveEditor.inspect(source, max: 15);
    expect(found.length, 15);
    expect(found.first.key, 'field0');
    expect(found.last.key, 'field14');
    expect(() => IniSaveEditor.inspect(source, max: 10001), throwsRangeError);
    expect(() => IniSaveEditor.inspect('A' * (8 * 1024 * 1024 + 1)),
        throwsFormatException);
  });
}
