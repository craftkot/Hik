import 'dart:convert';

/// Represents a leaf value in a JSON tree. Paths use JSON Pointer (RFC 6901).
class JsonField {
  const JsonField(this.pointer, this.value);
  final String pointer;
  final Object? value;

  String get preview => jsonEncode(value);
}

String _escapeSegment(String value) =>
    value.replaceAll('~', '~0').replaceAll('/', '~1');

String _unescapeSegment(String value) {
  if (RegExp(r'~(?![01])').hasMatch(value)) {
    throw const FormatException('Неверный JSON Pointer');
  }
  return value.replaceAll('~1', '/').replaceAll('~0', '~');
}

List<JsonField> listJsonFields(String source, {int max = 500}) {
  final root = jsonDecode(source);
  final output = <JsonField>[];
  void visit(Object? node, String pointer, int depth) {
    if (output.length >= max || depth > 24) return;
    if (node is Map) {
      for (final entry in node.entries) {
        visit(entry.value, '$pointer/${_escapeSegment(entry.key.toString())}', depth + 1);
        if (output.length >= max) break;
      }
    } else if (node is List) {
      for (var i = 0; i < node.length && output.length < max; i++) {
        visit(node[i], '$pointer/$i', depth + 1);
      }
    } else {
      output.add(JsonField(pointer.isEmpty ? '/' : pointer, node));
    }
  }
  visit(root, '', 0);
  return output;
}

String changeJsonField(String source, String pointer, String jsonValue) {
  if (!pointer.startsWith('/') || pointer == '/') {
    throw const FormatException('Нужен путь к полю JSON');
  }
  final newValue = jsonDecode(jsonValue);
  final root = jsonDecode(source);
  final segments = pointer.substring(1).split('/').map(_unescapeSegment).toList();
  Object? node = root;
  for (final segment in segments.take(segments.length - 1)) {
    node = _child(node, segment);
  }
  final last = segments.last;
  final oldValue = _child(node, last);
  if (oldValue != null && !_sameJsonType(oldValue, newValue)) {
    throw const FormatException('Тип значения изменился. Сохранён исходный тип поля');
  }
  if (node is Map<String, dynamic>) {
    node[last] = newValue;
  } else if (node is List) {
    node[int.parse(last)] = newValue;
  } else {
    throw const FormatException('Путь не ведёт к полю');
  }
  return const JsonEncoder.withIndent('  ').convert(root);
}

Object? _child(Object? parent, String segment) {
  if (parent is Map) {
    if (!parent.containsKey(segment)) {
      throw FormatException('Нет ключа $segment');
    }
    return parent[segment];
  }
  if (parent is List) {
    final index = int.tryParse(segment);
    if (index == null || index < 0 || index >= parent.length) {
      throw const FormatException('Индекс массива за границей');
    }
    return parent[index];
  }
  throw const FormatException('Путь не ведёт к полю');
}

bool _sameJsonType(Object a, Object? b) {
  if (a is num) return b is num;
  if (a is bool) return b is bool;
  if (a is String) return b is String;
  return a.runtimeType == b.runtimeType;
}
