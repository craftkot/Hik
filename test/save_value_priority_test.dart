import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/json_editor.dart';
import 'package:game_lab/core/save_value_priority.dart';

void main() {
  test('game economy, HP, mana and attributes are sorted before other keys',
      () {
    const source = '''
    {
      "player": {
        "name": "Alex",
        "description": "health potion",
        "questCount": 10,
        "level": 6,
        "experience": 800,
        "strength": 20,
        "currentMana": 40,
        "maxHP": 200,
        "coins": 987
      }
    }
    ''';
    final ranked = prioritizeJsonFields(listJsonFields(source));
    expect(ranked.take(6).map((f) => f.category), [
      SaveValueCategory.currency,
      SaveValueCategory.health,
      SaveValueCategory.mana,
      SaveValueCategory.attributes,
      SaveValueCategory.level,
      SaveValueCategory.experience,
    ]);
    expect(ranked.first.pointer, '/player/coins');
    expect(ranked[1].pointer, '/player/maxHP');
    expect(ranked[2].pointer, '/player/currentMana');
    expect(ranked.last.category, SaveValueCategory.other);
    expect(ranked.last.pointer, '/player/questCount');
    expect(jsonDecode(source)['player']['coins'], 987,
        reason: 'Ranking is read-only');
  });

  test('whole-token recognition avoids shop, golden and translations', () {
    expect(SaveValuePriority.fromPath('/data/shop', 4),
        SaveValueCategory.other);
    expect(SaveValuePriority.fromPath('/settings/goldenRatio', 2),
        SaveValueCategory.other);
    expect(SaveValuePriority.fromPath('/translations/hp', 'здоровье'),
        SaveValueCategory.other);
    expect(SaveValuePriority.fromPath('/game/coins', true),
        SaveValueCategory.other);
    expect(SaveValuePriority.fromPath('/world/gold', 0),
        SaveValueCategory.currency);
    expect(SaveValuePriority.fromPath('/hero/stats/strength', -10),
        SaveValueCategory.attributes);
  });

  test('supports Russian save field names and JSON pointer escape', () {
    expect(SaveValuePriority.fromPath('/игрок/золото', 55),
        SaveValueCategory.currency);
    expect(SaveValuePriority.fromPath('/герой/здоровье', 100),
        SaveValueCategory.health);
    expect(SaveValuePriority.fromPath('/игрок/выносливость', 12),
        SaveValueCategory.resources);
    expect(SaveValuePriority.fromPath('/player~1data/hp', 15),
        SaveValueCategory.health);
    expect(SaveValuePriority.fromName('playerStats.json'),
        SaveValueCategory.attributes);
    expect(SaveValuePriority.fromName('shop.json'),
        SaveValueCategory.other);
  });

  test('preserves original order among equally-ranked and ordinary fields', () {
    const source =
        '{"last":4,"health":30,"name":"Ana","hp":45,"first":1,"gold":10}';
    final ranked = prioritizeJsonFields(listJsonFields(source));
    expect(ranked.map((f) => f.pointer),
        ['/gold', '/health', '/hp', '/last', '/name', '/first']);
    expect(ranked.first.preview, '10');
    expect(prioritizeJsonFields(ranked, max: 2), hasLength(2));
    expect(() => prioritizeJsonFields(ranked, max: -1), throwsRangeError);
  });

  test('late high-priority fields survive display limit after larger scan',
      () {
    final content = <String, dynamic>{
      for (var i = 0; i < 600; i++) 'unimportant_$i': i,
      'wallet': {'gold': 1200, 'hp': 100},
    };
    final found = listJsonFields(jsonEncode(content), max: 2500);
    final important = prioritizeJsonFields(found, max: 500);
    expect(important.length, 500);
    expect(important.first.pointer, '/wallet/gold');
    expect(important[1].pointer, '/wallet/hp');
  });
}
