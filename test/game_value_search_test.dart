import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/game_file.dart';
import 'package:game_lab/core/game_value_search.dart';
import 'package:game_lab/core/storage_service.dart';

class _FakeStorage implements GameStorage {
  _FakeStorage(this.data);
  final Map<String, Uint8List> data;

  @override
  Future<String?> chooseFolder() async => null;
  @override
  Future<List<GameFile>> scan(String folder) async => [];
  @override
  Future<Uint8List> read(GameFile file) async =>
      data[file.id] ?? (throw StateError('not accessible'));
  @override
  Future<Uint8List> readPreview(GameFile file) => read(file);
  @override
  Future<String> writeWithBackup(GameFile file, Uint8List data,
      {Uint8List? expected}) async =>
      throw UnimplementedError();
}

GameFile _file(String id, String name, int size) =>
    GameFile(id: id, name: name, relativePath: 'Game/$name', size: size);

void main() {
  test('search across text and binary files, show file and offset', () async {
    final json = Uint8List.fromList(
        '{"coins":100,"max":1000}'.codeUnits);
    final binary = Uint8List.fromList([1, 2, 100, 0, 0, 0, 3, 4]);
    final files = [
      _file('a', 'profile.json', json.length),
      _file('b', 'slot.sav', binary.length),
    ];
    final report = await GameValueSearch.search(
        storage: _FakeStorage({'a': json, 'b': binary}),
        files: files,
        query: '100');
    expect(report.scanned, 2);
    expect(report.hits.length, 2);
    final txt = report.hits.first;
    expect(txt.file.id, 'a');
    expect(txt.isText, true);
    expect(txt.preview, contains('coins'));
    expect(txt.location, startsWith('символ '));
    final bin = report.hits.last;
    expect(bin.file.id, 'b');
    expect(bin.offset, 2);
    expect(bin.location, '0x2');
    expect(bin.format, contains('Int32'));
    expect(binary[2], 100, reason: 'Search is read-only');
  });

  test('text search accepts literals but numeric search has boundaries', () async {
    final bytes = Uint8List.fromList(
        'money:2000; gold:200; label=GOLD'.codeUnits);
    final file = _file('a', 'save.txt', bytes.length);
    final storage = _FakeStorage({'a': bytes});
    final numbers = await GameValueSearch.search(
        storage: storage, files: [file], query: '200');
    expect(numbers.hits, hasLength(1));
    final text = await GameValueSearch.search(
        storage: storage, files: [file], query: 'gold');
    expect(text.hits, hasLength(2)); // Case-insensitive text search.
  });

  test('skips media, huge files and inaccessible paths without crashing',
      () async {
    final files = [
      _file('img', 'icon.png', 100),
      _file('big', 'game.dat', maxEditableBytes + 1),
      _file('broken', 'lost.sav', 20),
      _file('okay', 'user.dat', 4),
    ];
    final report = await GameValueSearch.search(
        storage: _FakeStorage({'okay': Uint8List.fromList([42, 0, 0, 0])}),
        files: files, query: '42');
    expect(report.skipped, 2);
    expect(report.readErrors, 1);
    expect(report.scanned, 2);
    expect(report.hits.single.file.id, 'okay');
  });

  test('stale size metadata cannot bypass the actual payload limit',
      () async {
    final oversized = Uint8List(maxEditableBytes + 1);
    // The advertised size looks safe, but the storage backend returns
    // a larger payload containing an otherwise searchable number.
    oversized[0] = 42;
    final valid = Uint8List.fromList([42, 0, 0, 0]);
    final report = await GameValueSearch.search(
      storage: _FakeStorage({'stale': oversized, 'live': valid}),
      files: [
        _file('stale', 'stale.sav', 4),
        _file('live', 'live.sav', 4),
      ],
      query: '42',
    );
    expect(report.scanned, 2);
    expect(report.skipped, 1);
    expect(report.readErrors, 0);
    expect(report.hits, isNotEmpty);
    expect(report.hits.every((hit) => hit.file.id == 'live'), true);
  });

  test('does not search backup, rollback or staging copies as live saves',
      () async {
    final files = [
      _file('live', 'slot.sav', 4),
      _file('backup', 'slot.sav.ehtid-backup-123.tmp', 4),
      _file('rollback', 'slot.sav.ehtid-rollback-123.tmp', 4),
      _file('stage', 'slot.sav.ehtid-stage-123.tmp', 4),
      _file('pending', 'slot.sav.ehtid-pending-123.tmp', 4),
    ];
    final bytes = Uint8List.fromList([42, 0, 0, 0]);
    final report = await GameValueSearch.search(
      storage: _FakeStorage({
        for (final file in files) file.id: bytes,
      }),
      files: files,
      query: '42',
    );
    expect(report.scanned, 1);
    expect(report.skipped, 4);
    expect(report.hits, isNotEmpty);
    expect(report.hits.every((hit) => hit.file.id == 'live'), true);
  });

  test('binary hit must match freshly opened bytes at the same offset', () async {
    final original = Uint8List.fromList([9, 42, 0, 0, 0, 8]);
    final file = _file('slot', 'slot.sav', original.length);
    final report = await GameValueSearch.search(
      storage: _FakeStorage({'slot': original}),
      files: [file],
      query: '42',
    );
    final hit = report.hits.single;
    expect(GameValueSearch.matchesBinaryHit(hit, original), isTrue);
    final changed = Uint8List.fromList(original)..[1] = 43;
    expect(GameValueSearch.matchesBinaryHit(hit, changed), isFalse);
    expect(GameValueSearch.matchesBinaryHit(hit, Uint8List(2)), isFalse);
    expect(GameValueSearch.matchesBinaryHit(hit, Uint8List(0)), isFalse);
  });

  test('cancellation, duplicates, global cap and explicit file limit',
      () async {
    final data = Uint8List.fromList([1, 0, 0, 0, 1, 0, 0, 0]);
    final files = [
      _file('one', 'a.dat', 8),
      _file('one', 'a.dat', 8),
      _file('two', 'b.dat', 8),
    ];
    final storage = _FakeStorage({'one': data, 'two': data});
    var cancel = false;
    final interrupted = await GameValueSearch.search(
      storage: storage, files: files, query: '1',
      onProgress: (done, total) { if (done == 1) cancel = true; },
      shouldCancel: () => cancel,
    );
    expect(interrupted.cancelled, true);
    expect(interrupted.scanned, 1);

    final limited = await GameValueSearch.search(
      storage: storage, files: files, query: '1',
      maxFiles: 1, maxResults: 1, maxPerFile: 1,
    );
    expect(limited.hits, hasLength(1));
    expect(limited.truncated, true);
    expect(limited.skipped, 1);
    await expectLater(
      GameValueSearch.search(storage: storage, files: files, query: ''),
      throwsFormatException,
    );
  });
}
