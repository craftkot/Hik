import 'dart:convert';
import 'dart:typed_data';

import 'game_file.dart';
import 'storage_service.dart';

/// One localization-file translation prepared in RAM. Nothing is written
/// until the user explicitly approves the preview.
class GameLocaleDraft {
  const GameLocaleDraft({
    required this.file,
    required this.originalBytes,
    required this.translatedBytes,
    required this.translatedStrings,
    required this.beforePreview,
    required this.afterPreview,
  });

  final GameFile file;
  final Uint8List originalBytes;
  final Uint8List translatedBytes;
  final int translatedStrings;
  final String beforePreview;
  final String afterPreview;
}

class GameLocaleBatch {
  const GameLocaleBatch({
    required this.drafts,
    required this.skipped,
    required this.inspected,
  });

  final List<GameLocaleDraft> drafts;
  final List<String> skipped;
  final int inspected;
  int get translatedStrings =>
      drafts.fold(0, (sum, draft) => sum + draft.translatedStrings);
}

class GameLocaleWriteReport {
  const GameLocaleWriteReport({
    required this.written,
    required this.failed,
  });

  final List<String> written;
  final List<String> failed;
}

/// A small, bounded list of likely JSON localization files. Ordinary saves,
/// network settings, arbitrary JSON configuration and APK/OBB archives are NOT
/// rewritten just because they belong to the selected game.
class GameLocaleCandidates {
  static const maxBatchFiles = 6;
  static const maxSourceBytes = 1024 * 1024;

  static bool canTranslate(GameFile file) {
    if (!file.isJson || file.size > maxSourceBytes ||
        file.name.contains('.ehtid-')) return false;
    final path = file.relativePath.toLowerCase().replaceAll('\\', '/');
    final name = file.name.toLowerCase();
    if (file.isSave || path.contains('/backup/') ||
        path.contains('/cache/') || path.contains('/config/')) {
      return false;
    }
    return file.isLocalization ||
        RegExp(r'^(strings|dialogue|dialog|translations|locale|localization)'
            r'([._-][a-z0-9_-]+)?\.json$').hasMatch(name) ||
        RegExp(r'^(en|en-us|en_us|english)([._-].+)?\.json$')
            .hasMatch(name);
  }

  /// Avoid translating every locale variant in a directory. A chosen source
  /// language must not rewrite ru.json, ja.json, etc. A neutral strings.json
  /// may be translated after the user checks the preview.
  static bool matchesLanguage(GameFile file, String code) {
    const known = {
      'en', 'ru', 'ja', 'zh', 'ko', 'fr', 'de', 'es', 'it',
      'pt', 'uk', 'pl', 'tr', 'nl', 'vi', 'th', 'ar',
    };
    final markers = file.relativePath.toLowerCase()
        .split(RegExp(r'[/\\\\._-]+'))
        .where(known.contains).toSet();
    return markers.isEmpty || (markers.length == 1 &&
        markers.contains(code));
  }

  static List<GameFile> prioritized(Iterable<GameFile> files,
      {String? sourceLanguage}) {
    final candidates = files.where((file) =>
        canTranslate(file) &&
        (sourceLanguage == null || matchesLanguage(file, sourceLanguage)))
        .toList();
    int score(GameFile file) {
      final path = file.relativePath.toLowerCase();
      if (RegExp(r'(en[-_]?(us|gb)?|english)\.json$')
          .hasMatch(file.name.toLowerCase())) return 0;
      if (path.contains('/lang/') || path.contains('/locales/') ||
          path.contains('/localization/') || path.contains('/i18n/')) {
        return 1;
      }
      return 2;
    }
    candidates.sort((a, b) {
      final byScore = score(a).compareTo(score(b));
      return byScore != 0
          ? byScore : a.relativePath.compareTo(b.relativePath);
    });
    return candidates;
  }
}

typedef JsonLocaleTranslate = Future<LocaleTextResult> Function(String source);

class LocaleTextResult {
  const LocaleTextResult(this.text, this.translatedStrings);
  final String text;
  final int translatedStrings;
}

/// Translation runs against user-approved SAF documents only. Save files are
/// never modified by this workflow, even if they contain some text.
class GameLocaleWorkflow {
  const GameLocaleWorkflow(this.storage);

  final GameStorage storage;

  Future<GameLocaleBatch> prepare(
    Iterable<GameFile> files,
    JsonLocaleTranslate translate, {
    String? sourceLanguage,
    void Function(int completed, int total)? onProgress,
  }) async {
    final candidates = GameLocaleCandidates.prioritized(
        files, sourceLanguage: sourceLanguage);
    final selected = candidates.take(GameLocaleCandidates.maxBatchFiles).toList();
    final drafts = <GameLocaleDraft>[];
    final skipped = <String>[];
    for (var i = 0; i < selected.length; i++) {
      final file = selected[i];
      try {
        // The file might have grown since scan; storage.read enforces 8 MiB.
        final original = await storage.read(file);
        if (original.length > GameLocaleCandidates.maxSourceBytes) {
          skipped.add('${file.name}: файл слишком большой');
          continue;
        }
        final text = decodeEditableText(original);
        if (text == null) {
          skipped.add('${file.name}: не UTF-8');
          continue;
        }
        final document = jsonDecode(text);
        if (document is! Map && document is! List) {
          skipped.add('${file.name}: нет JSON-словаря');
          continue;
        }
        final result = await translate(text);
        final parsed = jsonDecode(result.text);
        if (parsed is! Map && parsed is! List ||
            !_preservesJsonStructure(document, parsed)) {
          throw const FormatException(
            'Перевод изменил JSON-ключи, типы или значения данных');
        }
        if (result.translatedStrings <= 0 || result.text == text) {
          skipped.add('${file.name}: переводимых строк нет');
          continue;
        }
        final bytes = Uint8List.fromList(utf8.encode(result.text));
        if (bytes.length > maxEditableBytes) {
          skipped.add('${file.name}: перевод превышает 8 МБ');
          continue;
        }
        drafts.add(GameLocaleDraft(
          file: file,
          originalBytes: original,
          translatedBytes: bytes,
          translatedStrings: result.translatedStrings,
          beforePreview: text.length > 800 ? text.substring(0, 800) : text,
          afterPreview: result.text.length > 800
              ? result.text.substring(0, 800) : result.text,
        ));
      } catch (error) {
        skipped.add('${file.name}: $error');
      } finally {
        onProgress?.call(i + 1, selected.length);
      }
    }
    if (candidates.length > selected.length) {
      skipped.add('Осталось ${candidates.length - selected.length} файлов: '
          'за один запуск не более ${GameLocaleCandidates.maxBatchFiles}. '
          'Их можно перевести отдельно через редактор файла.');
    }
    return GameLocaleBatch(
        drafts: drafts, skipped: skipped, inspected: selected.length);
  }

  /// Re-reads each original immediately before the existing backup writer.
  /// Errors are reported per file; previous successful writes are NOT rolled
  /// back across files (each file keeps its own verified .bak copy).
  Future<GameLocaleWriteReport> apply(GameLocaleBatch batch,
      {void Function(int completed, int total)? onProgress}) async {
    final written = <String>[];
    final failed = <String>[];
    for (var i = 0; i < batch.drafts.length; i++) {
      final draft = batch.drafts[i];
      try {
        final current = await storage.read(draft.file);
        if (!_sameBytes(current, draft.originalBytes)) {
          throw StateError('оригинал изменился после предпросмотра');
        }
        final backup = await storage.writeWithBackup(
          draft.file, draft.translatedBytes, expected: draft.originalBytes,
        );
        written.add('${draft.file.name} · $backup');
      } catch (error) {
        failed.add('${draft.file.name}: $error');
      } finally {
        onProgress?.call(i + 1, batch.drafts.length);
      }
    }
    return GameLocaleWriteReport(written: written, failed: failed);
  }

  /// A translated locale may change only string values. Keys, array
  /// sizes, numbers, booleans and nulls must remain exactly the same.
  bool _preservesJsonStructure(dynamic before, dynamic after) {
    if (before is Map) {
      if (after is! Map || before.length != after.length) return false;
      for (final key in before.keys) {
        if (!after.containsKey(key) ||
            !_preservesJsonStructure(before[key], after[key])) return false;
      }
      return true;
    }
    if (before is List) {
      if (after is! List || before.length != after.length) return false;
      for (var i = 0; i < before.length; i++) {
        if (!_preservesJsonStructure(before[i], after[i])) return false;
      }
      return true;
    }
    if (before is String) return after is String;
    return before == after;
  }

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
