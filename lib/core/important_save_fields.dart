import 'dart:convert';
import 'dart:typed_data';

import 'ini_save_editor.dart';
import 'json_editor.dart';
import 'nested_save_fields.dart';
import 'save_value_priority.dart';

enum ImportantFieldSource { json, ini, embeddedText, nestedJson }

class ImportantSaveField {
  const ImportantSaveField({
    required this.name,
    required this.value,
    required this.category,
    required this.source,
    this.json,
    this.ini,
    this.embedded,
    this.nested,
  });

  final String name;
  final String value;
  final SaveValueCategory category;
  final ImportantFieldSource source;
  final JsonField? json;
  final IniSaveField? ini;
  final EmbeddedNumberField? embedded;
  final NestedSaveField? nested;
}

class EmbeddedNumberField {
  const EmbeddedNumberField({
    required this.key,
    required this.value,
    required this.offset,
    required this.category,
  });

  final String key;
  final String value;
  final int offset;
  final SaveValueCategory category;
}

class ImportantSaveInspector {
  const ImportantSaveInspector._();

  static const maxFields = 500;
  static const maxBytes = 8 * 1024 * 1024;

  static List<ImportantSaveField> inspectText(String text) {
    if (text.length > maxBytes) return const [];
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final fields = listJsonFields(text, max: 10000);
        final important = prioritizeJsonFields(fields, max: 10000)
            .where((field) => field.category.important)
            .take(maxFields);
        final nested = NestedSaveFields.inspect(text);
        final pairedPaths = nested.where((f) => f.containers.isEmpty)
            .map((f) => f.pointer).toSet();
        final combined = <ImportantSaveField>[
          ...important.where((field) => !pairedPaths.contains(field.pointer))
              .map((field) => ImportantSaveField(
            name: field.pointer, value: field.preview,
            category: field.category, source: ImportantFieldSource.json,
            json: field,
          )),
          ...nested.map((field) => ImportantSaveField(
            name: field.name, value: field.value.toString(),
            category: field.category, source: ImportantFieldSource.nestedJson,
            nested: field,
          )),
        ];
        final indexed = combined.asMap().entries.toList();
        indexed.sort((a,b) {
          final order = a.value.category.priority.compareTo(b.value.category.priority);
          return order == 0 ? a.key.compareTo(b.key) : order;
        });
        return List.unmodifiable(indexed.take(maxFields).map((e) => e.value));
      } catch (_) {
        return const [];
      }
    }
    try {
      final fields = IniSaveEditor.prioritize(
          IniSaveEditor.inspect(text, max: 10000));
      return List.unmodifiable(fields
          .where((field) => field.category.important)
          .take(maxFields)
          .map((field) => ImportantSaveField(
            name: field.displayPath, value: field.value,
            category: field.category, source: ImportantFieldSource.ini,
            ini: field,
          )));
    } catch (_) {
      return const [];
    }
  }

  // Only explicit ASCII "hp=120", "gold:45", etc. No positional guessing.
  // Latin1 preserves the byte offset of every character in binary data.
  static final RegExp _embeddedPattern = RegExp(
    r'(?:^|[^A-Za-z0-9_.-])'
    r'([A-Za-z][A-Za-z0-9_.-]{0,63})[ \t]{0,4}[:=][ \t]{0,4}'
    r'([+-]?(?:[0-9]{1,12}(?:\.[0-9]{1,8})?|\.[0-9]{1,8}))'
    r'(?=$|[^0-9A-Za-z.+-])',
  );
  static final RegExp _number = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$',
  );

  static List<ImportantSaveField> inspectBinary(Uint8List data) {
    if (data.length > maxBytes) return const [];
    final text = latin1.decode(data);
    final results = <ImportantSaveField>[];
    for (final match in _embeddedPattern.allMatches(text)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      final category = SaveValuePriority.fromPath(key, num.tryParse(value));
      if (!category.important || num.tryParse(value)?.isFinite != true) {
        continue;
      }
      // The byte offset is exact because latin1 is one character per byte.
      final valueOffset = match.start + match.group(0)!.lastIndexOf(value);
      final field = EmbeddedNumberField(
        key: key, value: value, offset: valueOffset,
        category: category,
      );
      results.add(ImportantSaveField(
        name: key, value: value, category: category,
        source: ImportantFieldSource.embeddedText, embedded: field,
      ));
      if (results.length >= maxFields) break;
    }
    results.sort((a, b) =>
        a.category.priority.compareTo(b.category.priority));
    return List.unmodifiable(results);
  }

  /// Fail closed: overwrite only a same-width numeric ASCII span, at the
  /// exact previously inspected offset. All other bytes are preserved.
  static Uint8List patchEmbedded(Uint8List source,
      EmbeddedNumberField field, String replacement) {
    final value = replacement.trim();
    if (value.length != field.value.length || !_number.hasMatch(value)) {
      throw const FormatException(
          'Длина числа должна сохраниться. Например 120 → 999.');
    }
    if (num.tryParse(value)?.isFinite != true) {
      throw const FormatException('Введи конечное число');
    }
    if (int.tryParse(field.value) != null && int.tryParse(value) == null) {
      throw const FormatException('Целое число должно остаться целым');
    }
    final at = field.offset;
    final originalBytes = ascii.encode(field.value);
    if (at < 0 || at > source.length - originalBytes.length) {
      throw StateError('Смещение поля больше не подходит');
    }
    for (var i = 0; i < originalBytes.length; i++) {
      if (source[at + i] != originalBytes[i]) {
        throw StateError('Значение файла изменилось — открой его заново');
      }
    }
    final result = Uint8List.fromList(source);
    result.setRange(at, at + value.length, ascii.encode(value));
    return result;
  }
}
