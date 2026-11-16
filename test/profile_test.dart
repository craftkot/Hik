import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/game_profile.dart';

GameFile file(String p) => GameFile(id: p, name: p.split('/').last,
  relativePath: p, size: 123);

void main() {
  test('Unity detection does not claim to decode proprietary formats', () {
    final p = detectGameProfile([file('Game_Data/globalgamemanagers'),
      file('Game_Data/Managed/Assembly-CSharp.dll'), file('Saves/slot1.json')]);
    expect(p.engine, 'Unity');
    expect(p.saveCandidates, 1);
  });
  test('Unreal pack path detected', () {
    expect(detectGameProfile([file('Example/Content/Paks/Example.pak')]).engine,
      'Unreal Engine');
  });
  test('Unknown engines are not guessed', () {
    final p = detectGameProfile([file('game.dat'), file('notes.txt')]);
    expect(p.engine, 'Не определён');
    expect(p.localeCandidates, 0);
  });
}
