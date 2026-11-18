import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_lab/core/crash_rollback_inspector.dart';
import 'package:game_lab/core/safe_desktop_save.dart';

Uint8List data(String value) => Uint8List.fromList(value.codeUnits);

void main() {
  late Directory directory;
  late File save;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ehtid-crash-preview-');
    save = File('${directory.path}${Platform.pathSeparator}slot.sav');
    await save.writeAsBytes(data('new'), flush: true);
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('previews original and rollback without changing either', () async {
    final rollback = File('${save.path}.ehtid-rollback-123.tmp');
    await rollback.writeAsBytes(data('old'), flush: true);
    final previews = await CrashRollbackInspector.inspect(save);
    expect(previews, hasLength(1));
    expect(previews.single.path, rollback.path);
    expect(previews.single.bytes, data('old'));
    expect(previews.single.currentBytes, data('new'));
    expect(previews.single.differsFromCurrent, isTrue);
    expect(await rollback.readAsBytes(), data('old'));
    expect(await save.readAsBytes(), data('new'));
  });

  test('missing original is reported without recreating it', () async {
    final rollback = File('${save.path}.ehtid-rollback-123.tmp');
    await save.rename(rollback.path);
    final previews = await CrashRollbackInspector.inspect(save);
    expect(previews.single.currentExists, isFalse);
    expect(previews.single.currentBytes, isNull);
    expect(await save.exists(), isFalse);
  });

  test('unrelated files are ignored and equal content is recognized', () async {
    await File('${directory.path}/other.sav.ehtid-rollback-1.tmp')
        .writeAsBytes(data('different'));
    await File('${save.path}.ehtid-rollback-2.tmp')
        .writeAsBytes(data('new'));
    final previews = await CrashRollbackInspector.inspect(save);
    expect(previews, hasLength(1));
    expect(previews.single.differsFromCurrent, isFalse);
  });

  test('oversized rollback is rejected without touching save', () async {
    final rollback = File('${save.path}.ehtid-rollback-big.tmp');
    await rollback.writeAsBytes(
        Uint8List(SafeDesktopSaveWriter.maxLength + 1));
    await expectLater(CrashRollbackInspector.inspect(save), throwsStateError);
    expect(await save.readAsBytes(), data('new'));
    expect(await rollback.exists(), isTrue);
  });

  test('symlink rollback is rejected where supported', () async {
    final target = File('${directory.path}/target.txt');
    await target.writeAsBytes(data('old'));
    final link = Link('${save.path}.ehtid-rollback-link.tmp');
    try {
      await link.create(target.path);
    } on FileSystemException {
      return; // Windows environments without symlink permission.
    }
    await expectLater(CrashRollbackInspector.inspect(save), throwsStateError);
    expect(await target.readAsBytes(), data('old'));
  });
}
