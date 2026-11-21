import 'dart:convert';

/// Changes exactly one numeric JSON scalar, preserving all other source
/// characters and their order. This matters for game saves which store large
/// single-line JSON documents or rely on their existing formatting.
class LosslessJsonNumberEditor {
  const LosslessJsonNumberEditor._();

  static final RegExp _validNumber = RegExp(
    r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$',
  );

  static String change(String source, {
    required String pointer,
    required num expected,
    required String replacement,
  }) {
    if (source.length > 8 * 1024 * 1024) {
      throw const FormatException('JSON превышает лимит 8 МиБ');
    }
    if (!pointer.startsWith('/') || pointer == '/') {
      throw const FormatException('Некорректный путь поля');
    }
    final newValue = replacement.trim();
    if (!_validNumber.hasMatch(newValue) ||
        num.tryParse(newValue)?.isFinite != true) {
      throw const FormatException('Введи корректное JSON-число');
    }
    // Validate the source in addition to the bounded lexical walk.
    jsonDecode(source);
    final finder = _JsonNumberSpanFinder(source, pointer);
    final span = finder.find();
    final oldNumber = jsonDecode(source.substring(span.start, span.end));
    if (oldNumber is! num || oldNumber != expected) {
      throw StateError('Исходное число изменилось — открой поля заново');
    }
    final output = source.replaceRange(span.start, span.end, newValue);
    jsonDecode(output);
    return output;
  }
}

class _NumberSpan {
  const _NumberSpan(this.start, this.end);
  final int start;
  final int end;
}

/// Minimal JSON token walk with JSON Pointer tracking, not text search.
/// Duplicated paths are explicitly rejected instead of picking a random one.
class _JsonNumberSpanFinder {
  _JsonNumberSpanFinder(this.source, this.target);
  final String source;
  final String target;
  int i = 0;
  int visited = 0;
  _NumberSpan? span;
  int count = 0;

  static final _number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );

  _NumberSpan find() {
    _value('', 0);
    _whitespace();
    if (i != source.length || count != 1 || span == null) {
      throw StateError('Не удалось однозначно найти числовое поле');
    }
    return span!;
  }

  void _whitespace() {
    while (i < source.length && ' \t\r\n'.contains(source[i])) {
      i++;
    }
  }

  bool _consume(String char) {
    _whitespace();
    if (i < source.length && source[i] == char) {
      i++;
      return true;
    }
    return false;
  }

  void _expect(String char) {
    if (!_consume(char)) {
      throw const FormatException('Повреждена JSON-структура');
    }
  }

  String _string() {
    _whitespace();
    if (i >= source.length || source[i] != '"') {
      throw const FormatException('Ожидалась JSON-строка');
    }
    final start = i++;
    var terminated = false;
    while (i < source.length) {
      final char = source[i++];
      if (char.codeUnitAt(0) == 0x5c) {
        if (i >= source.length) break;
        i++;
      } else if (char == '"') {
        terminated = true;
        break;
      }
    }
    if (!terminated) throw const FormatException('Незакрытая строка JSON');
    return jsonDecode(source.substring(start, i)) as String;
  }

  void _value(String path, int depth) {
    if (depth > 64 || ++visited > 1000000) {
      throw const FormatException('Слишком сложный JSON');
    }
    _whitespace();
    if (i >= source.length) throw const FormatException('Конец JSON');
    final char = source[i];
    if (char == '{') {
      i++;
      if (_consume('}')) return;
      do {
        final key = _string();
        _expect(':');
        final encodedKey = key.replaceAll('~', '~0').replaceAll('/', '~1');
        _value('$path/$encodedKey', depth + 1);
      } while (_consume(','));
      _expect('}');
    } else if (char == '[') {
      i++;
      if (_consume(']')) return;
      var index = 0;
      do {
        _value('$path/$index', depth + 1);
        index++;
      } while (_consume(','));
      _expect(']');
    } else if (char == '"') {
      _string();
    } else {
      final at = i;
      final match = _number.matchAsPrefix(source, at);
      if (match != null) {
        i = match.end;
        if (path == target) {
          span = _NumberSpan(at, i);
          count++;
        }
      } else {
        var found = false;
        for (final literal in ['true', 'false', 'null']) {
          if (source.startsWith(literal, i)) {
            i += literal.length;
            found = true;
            break;
          }
        }
        if (!found) throw const FormatException('Неверное JSON-значение');
      }
    }
  }
}
