import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/game_locale_workflow.dart';
import 'package:game_lab/core/storage_service.dart';

class FakeGameStorage implements GameStorage {
  FakeGameStorage(this.current);
  final Map<String, Uint8List> current;
  final List<String> writes = [];
  final List<String> backups = [];

  @override
  Future<String?> chooseFolder() async => null;

  @override
  Future<List<GameFile>> scan(String folder) async => [];

  @override
  Future<Uint8List> read(GameFile file) async =>
      Uint8List.fromList(current[file.id]!);

  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);

  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected}) async {
    if (expected == null ||
        base64Encode(expected) != base64Encode(current[file.id]!)) {
      throw StateError('Original changed');
    }
    backups.add('backup:${file.id}');
    writes.add(file.id);
    current[file.id] = Uint8List.fromList(data);
    return 'backup:${file.id}';
  }
}

void main() {
  const localeFile = GameFile(
      id: 'locale', name: 'en.json',
      relativePath: 'game/lang/en.json', size: 28);
  const configuration = GameFile(
      id: 'config', name: 'config.json',
      relativePath: 'game/config/config.json', size: 28);
  const save = GameFile(
      id: 'save', name: 'player.json',
      relativePath: 'game/save/player.json', size: 28);
  const other = GameFile(
      id: 'other', name: 'strings.json',
      relativePath: 'game/strings.json', size: 28);

  test('only eligible JSON locale files are selected', () {
    expect(GameLocaleCandidates.canTranslate(localeFile), isTrue);
    expect(GameLocaleCandidates.canTranslate(configuration), isFalse);
    expect(GameLocaleCandidates.canTranslate(save), isFalse);
    expect(GameLocaleCandidates.canTranslate(other), isTrue);
    expect(GameLocaleCandidates.prioritized([other, configuration, save,
      localeFile]).map((f) => f.id), ['locale', 'other']);
    expect(GameLocaleCandidates.canTranslate(const GameFile(
        id: 'archive', name: 'game.apk',
        relativePath: 'game/game.apk', size: 100)), isFalse);
    expect(GameLocaleCandidates.canTranslate(const GameFile(
        id: 'backup', name: 'strings.json',
        relativePath: 'game/backup/strings.json', size: 20)), isFalse);
  });

  test('prepare only reads; apply verifies originals and saves backups',
      () async {
    final original = Uint8List.fromList(utf8.encode('{"hello":"Hello"}'));
    final store = FakeGameStorage({'locale': original});
    final workflow = GameLocaleWorkflow(store);
    final batch = await workflow.prepare([localeFile],
      (source) async {
        expect(source, '{"hello":"Hello"}');
        return const LocaleTextResult('{"hello":"Привет"}', 1);
      });
    expect(batch.drafts, hasLength(1));
    expect(batch.translatedStrings, 1);
    expect(batch.drafts.single.afterPreview, contains('Привет'));
    expect(store.writes, isEmpty);
    expect(store.backups, isEmpty);
    final report = await workflow.apply(batch);
    expect(report.written, hasLength(1));
    expect(report.failed, isEmpty);
    expect(store.writes, ['locale']);
    expect(store.backups, ['backup:locale']);
    expect(utf8.decode(store.current['locale']!), '{"hello":"Привет"}');
  });

  test('changed files are blocked and no overwrite occurs', () async {
    final store = FakeGameStorage({
      'locale': Uint8List.fromList(utf8.encode('{"hello":"Hello"}')),
    });
    final workflow = GameLocaleWorkflow(store);
    final batch = await workflow.prepare([localeFile],
        (source) async =>
            const LocaleTextResult('{"hello":"Привет"}', 1));
    store.current['locale'] = Uint8List.fromList(
        utf8.encode('{"hello":"Game changed value"}'));
    final report = await workflow.apply(batch);
    expect(report.written, isEmpty);
    expect(report.failed.single, contains('изменился'));
    expect(store.writes, isEmpty);
    expect(store.backups, isEmpty);
  });

  test('invalid JSON and unrelated configuration are not translated',
      () async {
    final store = FakeGameStorage({
      'locale': Uint8List.fromList(utf8.encode('not json')),
      'config': Uint8List.fromList(utf8.encode('{"server":"x"}')),
    });
    final workflow = GameLocaleWorkflow(store);
    var translatorCalled = false;
    final batch = await workflow.prepare([localeFile, configuration],
        (source) async {
      translatorCalled = true;
      return LocaleTextResult(source, 0);
    });
    expect(batch.drafts, isEmpty);
    expect(batch.skipped, hasLength(1));
    expect(translatorCalled, isFalse);
    expect(store.writes, isEmpty);
  });

  test('translation must preserve keys and non-text JSON values', () async {
    final store = FakeGameStorage({
      'locale': Uint8List.fromList(utf8.encode(
          '{"id":5,"hello":"Hello","nested":{"enabled":true}}')),
    });
    final flow = GameLocaleWorkflow(store);
    final changedKey = await flow.prepare([localeFile],
      (source) async => const LocaleTextResult(
          '{"id":5,"hi":"Привет","nested":{"enabled":true}}', 1));
    expect(changedKey.drafts, isEmpty);
    expect(changedKey.skipped.single, contains('JSON-ключи'));

    final changedNumber = await flow.prepare([localeFile],
      (source) async => const LocaleTextResult(
          '{"id":10,"hello":"Привет","nested":{"enabled":true}}', 1));
    expect(changedNumber.drafts, isEmpty);
    expect(changedNumber.skipped.single, contains('JSON-ключи'));

    final valid = await flow.prepare([localeFile],
      (source) async => const LocaleTextResult(
          '{"id":5,"hello":"Привет","nested":{"enabled":true}}', 1));
    expect(valid.drafts, hasLength(1));
    expect(store.writes, isEmpty);
  });

  test('large, binary and backup locale files cannot enter batch', () {
    final huge = GameFile(
      id: 'huge', name: 'strings.json',
      relativePath: 'game/lang/strings.json',
      size: GameLocaleCandidates.maxSourceBytes + 1);
    final internal = GameFile(
      id: 'internal', name: 'strings.json.ehtid-backup-111.bak',
      relativePath: 'game/lang/strings.json.ehtid-backup-111.bak',
      size: 50);
    expect(GameLocaleCandidates.prioritized([huge, internal]), isEmpty);
  });
}
