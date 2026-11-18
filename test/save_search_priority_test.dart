import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/game_value_search.dart';
import 'package:game_lab/core/save_value_priority.dart';
import 'package:game_lab/core/storage_service.dart';

class _SearchStorage implements GameStorage {
  _SearchStorage(this.data);

  final Map<String, Uint8List> data;

  @override
  Future<String?> chooseFolder() async => null;
  @override
  Future<List<GameFile>> scan(String folder) async => [];
  @override
  Future<Uint8List> read(GameFile file) async => data[file.id]!;
  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);
  @override
  Future<String> writeWithBackup(GameFile file, Uint8List content,
      {Uint8List? expected}) async => throw UnimplementedError();
}

void main() {
  test('prioritizes named numeric matches over ordinary save values',
      () async {
    const source = '{"quest":100,"health":100,"gold":100,"mana":100,'
        '"strength":100,"goldenRatio":100}';
    final file = GameFile(
      id: 'save', name: 'slot.sav',
      relativePath: 'Saves/slot.sav', size: source.length,
    );
    final report = await GameValueSearch.search(
      storage: _SearchStorage({'save': Uint8List.fromList(utf8.encode(source))}),
      files: [file], query: '100',
    );
    expect(report.hits, hasLength(6));
    final ordered = GameValueSearch.prioritizeHits(report.hits);
    expect(ordered.map((hit) => hit.category), [
      SaveValueCategory.currency,
      SaveValueCategory.health,
      SaveValueCategory.mana,
      SaveValueCategory.attributes,
      SaveValueCategory.other,
      SaveValueCategory.other,
    ]);
    expect(ordered.first.preview, contains('gold'));
    expect(report.hits.first.preview, contains('quest'),
        reason: 'Original search results remain unchanged');
  });

  test('does not label incidental numbers in binary or unassigned text',
      () async {
    const source = 'goldenRatio=100; hp potion costs 100; shop=100';
    final textFile = GameFile(
      id: 'text', name: 'save.txt',
      relativePath: 'Saves/save.txt', size: source.length,
    );
    final blob = Uint8List.fromList([100, 0, 0, 0]);
    final binaryFile = GameFile(
      id: 'blob', name: 'player.sav',
      relativePath: 'Saves/player.sav', size: blob.length,
    );
    final report = await GameValueSearch.search(
      storage: _SearchStorage({
        'text': Uint8List.fromList(utf8.encode(source)),
        'blob': blob,
      }),
      files: [textFile, binaryFile],
      query: '100',
    );
    expect(report.hits, isNotEmpty);
    expect(report.hits.every((hit) =>
      hit.category == SaveValueCategory.other), isTrue);
  });

  test('recognizes Russian keys immediately preceding the number', () async {
    const source = '{"здоровье":120,"деньги":120}';
    final file = GameFile(id: 'ru', name: 'data.json',
      relativePath: 'save/data.json', size: source.length);
    final result = await GameValueSearch.search(
      storage: _SearchStorage({'ru': Uint8List.fromList(utf8.encode(source))}),
      files: [file], query: '120',
    );
    expect(GameValueSearch.prioritizeHits(result.hits)
        .map((hit) => hit.category),
        [SaveValueCategory.currency, SaveValueCategory.health]);
  });
}
