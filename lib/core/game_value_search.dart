import 'dart:async';
import 'dart:typed_data';

import 'binary_save_editor.dart';
import 'game_file.dart';
import 'save_value_priority.dart';
import 'storage_service.dart';

/// Searches accessible files selected by the user, never other processes or
/// private Android application directories.
class GameValueHit {
  const GameValueHit({
    required this.file,
    required this.offset,
    required this.format,
    required this.preview,
    required this.matchedValue,
    this.numericFormat,
    this.isText = false,
    this.category = SaveValueCategory.other,
  });

  final GameFile file;
  /// Byte offset for binary data; character index for UTF-8 text.
  final int offset;
  final String format;
  final String preview;
  final String matchedValue;
  final SaveNumberFormat? numericFormat;
  final bool isText;
  /// Naming heuristic, never proof of a game variable.
  final SaveValueCategory category;

  String get location =>
      isText ? 'символ $offset' : '0x${offset.toRadixString(16)}';
}

class GameSearchSummary {
  const GameSearchSummary({
    required this.hits,
    required this.scanned,
    required this.skipped,
    required this.readErrors,
    required this.cancelled,
    required this.truncated,
  });

  final List<GameValueHit> hits;
  final int scanned;
  final int skipped;
  final int readErrors;
  final bool cancelled;
  final bool truncated;
}

class GameValueSearch {
  const GameValueSearch._();

  /// Put named numeric fields first without changing order within a category.
  static List<GameValueHit> prioritizeHits(List<GameValueHit> hits) {
    final numbered = hits.asMap().entries.toList();
    numbered.sort((a, b) {
      final category = a.value.category.priority
          .compareTo(b.value.category.priority);
      return category != 0 ? category : a.key.compareTo(b.key);
    });
    return List<GameValueHit>.unmodifiable(
        numbered.map((entry) => entry.value));
  }

  /// Only classify a number immediately following a named key assignment.
  static SaveValueCategory _categoryForText(
      String text, int offset, String value) {
    if (num.tryParse(value) == null) return SaveValueCategory.other;
    final prefix = text.substring(offset > 100 ? offset - 100 : 0, offset);
    final json = RegExp(r'"([^"]{1,80})"\s*:\s*"?\s*$').firstMatch(prefix);
    if (json != null) return SaveValuePriority.fromName(json.group(1)!);
    final assignment = RegExp(
        r'([A-Za-zА-Яа-яЁё_][A-Za-zА-Яа-яЁё_0-9]{0,80})\s*[:=]\s*"?\s*$')
        .firstMatch(prefix);
    return assignment == null
        ? SaveValueCategory.other
        : SaveValuePriority.fromName(assignment.group(1)!);
  }

  /// Skip executable/media/archive payloads by default. Include unknown
  /// extensions, save blobs, JSON, ini, sqlite, XML, and extensionless files.
  /// Limits below prevent huge asset bundles from exhausting mobile memory.
  static bool isCandidate(GameFile file) {
    // Recovery and backup artifacts are not live game saves. Never suggest
    // editing them as matches for a number picked from a screenshot.
    final name = file.name.toLowerCase();
    // Includes backup, pending, stage and interrupted rollback files.
    if (name.contains('.ehtid-')) return false;
    if (file.size < 1 || file.size > maxEditableBytes) return false;
    return !const <String>{
      '.exe', '.dll', '.so', '.dylib', '.pdb', '.class', '.dex',
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg',
      '.mp3', '.ogg', '.wav', '.flac', '.mp4', '.mkv', '.webm',
      '.zip', '.apk', '.jar', '.obb', '.pak', '.xapk', '.mrpack',
      '.bundle', '.unity3d', '.assets', '.pdf', '.7z', '.rar',
    }.contains(file.extension);
  }

  /// Revalidate a search hit against the freshly opened file. OCR and an
  /// earlier scan cannot prove that the bytes still contain this value.
  static bool matchesBinaryHit(GameValueHit hit, Uint8List bytes) {
    final format = hit.numericFormat;
    if (hit.isText || format == null || hit.offset < 0) return false;
    try {
      final expected = BinarySaveEditor.encode(hit.matchedValue, format);
      if (hit.offset > bytes.length - expected.length) return false;
      for (var i = 0; i < expected.length; i++) {
        if (bytes[hit.offset + i] != expected[i]) return false;
      }
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Bounded scan; callers may cancel and inspect progress between files.
  /// Returns a snapshot of results; it never writes any game file.
  static Future<GameSearchSummary> search({
    required GameStorage storage,
    required Iterable<GameFile> files,
    required String query,
    bool Function()? shouldCancel,
    void Function(int done, int total)? onProgress,
    int maxFiles = 4000,
    int maxResults = 200,
    int maxPerFile = 12,
  }) async {
    final value = query.trim();
    if (value.isEmpty || value.length > 128) {
      throw const FormatException('Введи число или текст (до 128 символов)');
    }
    if (maxFiles < 1 || maxResults < 1 || maxPerFile < 1) {
      throw RangeError('Лимиты поиска должны быть положительными');
    }
    final candidates = <GameFile>[];
    final unique = <String>{};
    var skipped = 0;
    for (final file in files) {
      if (!unique.add(file.id)) continue;
      if (candidates.length >= maxFiles) {
        skipped++;
        continue;
      }
      if (isCandidate(file)) {
        candidates.add(file);
      } else {
        skipped++;
      }
    }

    // Pre-encode once. Decimal queries also check IEEE-754 Float32; invalid
    // integer ranges are skipped rather than failing the whole search.
    final needles = <SaveNumberFormat, Uint8List>{};
    for (final format in SaveNumberFormat.values) {
      try {
        needles[format] = BinarySaveEditor.encode(value, format);
      } on FormatException {
        // A text query or number outside this representation.
      }
    }

    final hits = <GameValueHit>[];
    var scanned = 0;
    var errors = 0;
    var cancelled = false;
    var truncated = false;
    onProgress?.call(0, candidates.length);
    for (final file in candidates) {
      if (shouldCancel?.call() == true) {
        cancelled = true;
        break;
      }
      try {
        final bytes = await storage.read(file);
        // File metadata can be stale or incorrect. Never scan a payload
        // larger than the editor's supported limit after it is read.
        if (bytes.length > maxEditableBytes) {
          skipped++;
          scanned++;
          onProgress?.call(scanned, candidates.length);
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        final text = decodeEditableText(bytes);
        if (text != null) {
          final lowered = text.toLowerCase();
          final term = value.toLowerCase();
          var start = 0;
          var inFile = 0;
          while (hits.length < maxResults && inFile < maxPerFile) {
            final offset = lowered.indexOf(term, start);
            if (offset < 0) break;
            start = offset + 1;
            if (!_matchesBoundary(text, offset, term.length, value)) continue;
            final previewStart = offset < 28 ? 0 : offset - 28;
            final previewEnd = offset + value.length + 28 > text.length
                ? text.length
                : offset + value.length + 28;
            final preview = text.substring(previewStart, previewEnd)
                .replaceAll(RegExp(r'[\r\n\t]+'), ' ');
            hits.add(GameValueHit(file: file, offset: offset,
              format: 'UTF-8', preview: preview, matchedValue: value,
              isText: true,
              category: _categoryForText(text, offset, value)));
            inFile++;
          }
        } else {
          var inFile = 0;
          for (final entry in needles.entries) {
            if (hits.length >= maxResults || inFile >= maxPerFile) break;
            final needle = entry.value;
            for (var at = 0; at <= bytes.length - needle.length; at++) {
              var equal = true;
              for (var i = 0; i < needle.length; i++) {
                if (bytes[at + i] != needle[i]) { equal = false; break; }
              }
              if (!equal) continue;
              hits.add(GameValueHit(file: file, offset: at,
                format: entry.key.label, preview: 'Точное числовое совпадение',
                matchedValue: value, numericFormat: entry.key));
              inFile++;
              if (hits.length >= maxResults || inFile >= maxPerFile) break;
            }
          }
        }
      } catch (_) {
        errors++; // Ignore inaccessible files, not the rest of the scan.
      }
      scanned++;
      onProgress?.call(scanned, candidates.length);
      if (hits.length >= maxResults) {
        truncated = true;
        break;
      }
      // Allow Flutter to handle cancel/progress gestures during larger scans.
      await Future<void>.delayed(Duration.zero);
    }
    return GameSearchSummary(hits: List.unmodifiable(hits),
      scanned: scanned, skipped: skipped, readErrors: errors,
      cancelled: cancelled, truncated: truncated);
  }

  static bool _matchesBoundary(
      String text, int offset, int length, String query) {
    if (!RegExp(r'^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$')
        .hasMatch(query)) return true;
    bool partOfNumber(String s) =>
        RegExp(r'[0-9a-zA-Z_.+-]').hasMatch(s);
    if (offset > 0 && partOfNumber(text[offset - 1])) return false;
    if (offset + length < text.length &&
        partOfNumber(text[offset + length])) return false;
    return true;
  }
}
