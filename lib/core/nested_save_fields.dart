import 'dart:convert';
import 'dart:typed_data';

import 'lossless_json_number_editor.dart';
import 'save_value_priority.dart';

class NestedSaveField {
  const NestedSaveField(this.containers, this.pointer, this.name,
      this.value, this.category);
  final List<String> containers;
  final String pointer;
  final String name;
  final Object value;
  final SaveValueCategory category;
}

class NestedSaveFields {
  static const limit = 8 * 1024 * 1024;
  static final _number = RegExp(
      r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$');

  static String _segment(String key) =>
      key.replaceAll('~', '~0').replaceAll('/', '~1');

  static bool _skip(String key) {
    final lower = key.toLowerCase();
    return lower.contains('rollback') || lower.contains('thumbnail') ||
        lower.contains('backlog') || lower.contains('history') ||
        lower.contains('base64');
  }

  static num? _numeric(Object? value) {
    if (value is num) return value.isFinite ? value : null;
    if (value is! String || !_number.hasMatch(value)) return null;
    final parsed = num.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static bool _flag(Object? v) =>
      v is bool || (v is String && (v == 'True' || v == 'False' ||
          v == 'true' || v == 'false'));

  static List<NestedSaveField> inspect(String source) {
    if (source.length > limit) return const [];
    final results = <NestedSaveField>[];
    var nodes = 0;
    var budget = limit * 2;
    void walk(Object? value, String path, List<String> containers,
        String label, int depth, {bool paired = false}) {
      if (++nodes > 100000 || depth > 40 || results.length >= 10000) return;
      if (value is String && containers.length < 6 &&
          value.length <= budget && value.length <= limit) {
        final t = value.trimLeft();
        if (t.startsWith('{') || t.startsWith('[')) {
          budget -= value.length;
          try {
            final decoded = jsonDecode(value);
            walk(decoded, '', [...containers, path], label, depth + 1);
            return;
          } on FormatException {
            // Not serialized JSON; treat it as a normal scalar.
          }
        }
      }
      if (value is Map<String, dynamic>) {
        final keys = value['keys'];
        final values = value['values'];
        if (keys is List && values is List && keys.length == values.length &&
            keys.every((k) => k is String) &&
            keys.toSet().length == keys.length) {
          final isVariableMap = label.toLowerCase().contains('variable');
          for (var i = 0; i < keys.length && nodes < 100000; i++) {
            final key = keys[i] as String;
            if (_skip(key)) continue;
            final short = key.split(',').first;
            walk(values[i], '$path/values/$i', containers,
                short, depth + 1, paired: isVariableMap);
          }
          return;
        }
        // A malformed parallel array map must not be interpreted by index.
        if (keys is List && values is List) return;
        for (final entry in value.entries) {
          if (_skip(entry.key)) continue;
          walk(entry.value, path + '/' + _segment(entry.key), containers,
              entry.key, depth + 1);
        }
      } else if (value is List) {
        for (var i = 0; i < value.length && nodes < 100000; i++) {
          walk(value[i], '$path/$i', containers, label, depth + 1,
              paired: paired);
        }
      } else {
        final numeric = _numeric(value);
        final category = SaveValuePriority.fromPath(label, numeric);
        final eligible = (numeric != null && (category.important || paired)) ||
            (paired && value is String && _flag(value));
        if (eligible && (containers.isNotEmpty || value is String || paired)) {
          results.add(NestedSaveField(List.unmodifiable(containers), path,
              label, value!, category));
        }
      }
    }
    try {
      walk(jsonDecode(source), '', const [], '', 0);
    } on FormatException {
      return const [];
    }
    final indexed = results.asMap().entries.toList();
    indexed.sort((a,b) {
      final order = a.value.category.priority.compareTo(b.value.category.priority);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    return List.unmodifiable(indexed.take(500).map((e) => e.value));
  }

  static Object? _read(Object? root, String pointer) {
    if (!pointer.startsWith('/')) throw StateError('Invalid path');
    var node = root;
    for (final raw in pointer.substring(1).split('/')) {
      final key = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      if (node is Map && node.containsKey(key)) {
        node = node[key];
      } else if (node is List) {
        node = node[int.parse(key)];
      } else {
        throw StateError('Поле больше не существует');
      }
    }
    return node;
  }

  static String change(String source, NestedSaveField field, String input) {
    final matches = inspect(source).where((f) =>
        f.pointer == field.pointer && f.name == field.name &&
        f.value == field.value &&
        f.containers.length == field.containers.length &&
        List.generate(f.containers.length,
            (i) => f.containers[i] == field.containers[i]).every((v) => v));
    if (matches.length != 1) throw StateError('Поле изменилось');
    final replacement = input.trim();
    if (_flag(field.value)) {
      if (!_flag(replacement)) throw const FormatException('Введите True или False');
    } else {
      final n = _numeric(replacement);
      if (n == null) throw const FormatException('Введите конечное число');
      if (_numeric(field.value) is int && n is! int) {
        throw const FormatException('Поле должно остаться целым');
      }
    }
    String patch(String text, int level) {
      if (level < field.containers.length) {
        final pointer = field.containers[level];
        final old = _read(jsonDecode(text), pointer);
        if (old is! String) throw StateError('Вложенный JSON изменился');
        final next = patch(old, level + 1);
        return LosslessJsonNumberEditor.replaceString(text,
            pointer: pointer, expected: old, replacement: next);
      }
      final old = field.value;
      if (old is String) {
        final next = _flag(old)
            ? (old[0] == old[0].toUpperCase()
                ? (replacement.toLowerCase() == 'true' ? 'True' : 'False')
                : replacement.toLowerCase())
            : replacement;
        return LosslessJsonNumberEditor.replaceString(text,
            pointer: field.pointer, expected: old, replacement: next);
      }
      return LosslessJsonNumberEditor.change(text,
          pointer: field.pointer, expected: old as num, replacement: replacement);
    }
    final result = patch(source, 0);
    if (result.length > limit) throw const FormatException('Сейв слишком большой');
    return result;
  }

  /// Detect an explicitly wrapped byte array by content, not filename.
  static Uint8List? wrappedImage(String source) {
    if (source.length > limit) return null;
    try {
      final root = jsonDecode(source);
      if (root is! Map || root['data'] is! Map) return null;
      final data = root['data'] as Map;
      final type = data['__type'];
      final value = data['value'];
      if (type is! String || !type.split(',').first.trim().endsWith('Byte[]') ||
          value is! String || value.length > limit) return null;
      final bytes = base64Decode(value);
      if (bytes.length < 12) return null;
      final png = const [137,80,78,71,13,10,26,10];
      if (List.generate(8, (i) => bytes[i] == png[i]).every((v) => v) ||
          (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255)) {
        return bytes;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
