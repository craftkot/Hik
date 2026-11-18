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
            r'([._-][a-z0-9_-]+)?\\.json$').hasMatch(name) ||
        RegExp(r'^(en|en-us|en_us|english)([._-].+)?\\.json$')
            .hasMatch(name);
  }

  static List<GameFile> prioritized(Iterable<GameFile> files) {
    final candidates = files.where(canTranslate).toList();
    int score(GameFile file) {
      final path = file.relativePath.toLowerCase();
      if (RegExp(r'(en[-_]?(us|gb)?|english)\\.json$')
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
    void Function(int completed, int total)? onProgress,
  }) async {
    final candidates = GameLocaleCandidates.prioritized(files);
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
        if (parsed is! Map && parsed is! List) {
          throw const FormatException('Некорректный JSON перевода');
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

  bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
