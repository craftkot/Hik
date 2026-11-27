import 'save_value_priority.dart';

/// A numeric INI entry in a user-approved local save, not a claim that the
/// number is genuinely HP, money or a stat. Source positions are retained so
/// editing one value doesn't reformat the rest of the file.
class IniSaveField {
  const IniSaveField({
    required this.lineIndex,
    required this.lineStart,
    required this.originalLine,
    required this.section,
    required this.key,
    required this.value,
    required this.valueStart,
    required this.valueEnd,
  });

  final int lineIndex;
  final int lineStart;
  final String originalLine;
  final String section;
  final String key;
  final String value;
  final int valueStart;
  final int valueEnd;

  String get displayPath =>
      section.isEmpty ? key : '$section / $key';
  SaveValueCategory get category =>
      SaveValuePriority.fromPath(displayPath, num.tryParse(value));
}

/// Strict numeric INI parser. Non-numeric lines, comments, ambiguous escapes,
/// and continuation lines are left entirely to the plain text editor.
/// Never interpret a generic .ini configuration as a save without UI consent.
class IniSaveEditor {
  const IniSaveEditor._();

  static const maxSourceBytes = 8 * 1024 * 1024;

  static final _keyValue = RegExp(
    r'^([ \t]*[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=[ \t]*)'
    r'([+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)'
    r'([ \t]*(?:[;#].*)?)$',
  );
  static final _section = RegExp(
    r'^[ \t]*\[([A-Za-z0-9_. -]{1,96})\][ \t]*(?:[;#].*)?$',
  );
  static final _number = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
  );
  static final _integer = RegExp(r'^[+-]?[0-9]+$');

  /// Extract at most [max] safe numeric entries. CRLF, LF and CR are
  /// preserved; lineStart and valueStart are offsets in original source.
  static List<IniSaveField> inspect(String source, {int max = 2500}) {
    if (max < 1 || max > 10000) throw RangeError.range(max, 1, 10000);
    if (source.length > maxSourceBytes) {
      throw const FormatException('INI-файл больше 8 МиБ');
    }
    final fields = <IniSaveField>[];
    var section = '';
    var cursor = 0;
    var lineIndex = 0;
    var continuation = false;

    void inspectLine(String line, int start) {
      final priorContinuation = continuation;
      var slashCount = 0;
      for (var i = line.length - 1;
          i >= 0 && line.codeUnitAt(i) == 0x5c; i--) {
        slashCount++;
      }
      continuation = slashCount.isOdd;
      if (priorContinuation || continuation) return;

      final header = _section.firstMatch(line);
      if (header != null) {
        section = header.group(1)!.trim();
        return;
      }
      final match = _keyValue.firstMatch(line);
      if (match == null) return;
      final value = match.group(2)!;
      final parsed = num.tryParse(value);
      if (parsed == null || !parsed.isFinite) return;
      fields.add(IniSaveField(
        lineIndex: lineIndex,
        lineStart: start,
        originalLine: line,
        section: section,
        key: match.group(1)!.split('=').first.trim(),
        value: value,
        valueStart: match.start + match.group(1)!.length,
        valueEnd: match.start + match.group(1)!.length + value.length,
      ));
    }

    for (final ending in RegExp(r'\r\n|\n|\r').allMatches(source)) {
      if (fields.length >= max) break;
      inspectLine(source.substring(cursor, ending.start), cursor);
      cursor = ending.end;
      lineIndex++;
    }
    if (fields.length < max && cursor < source.length) {
      inspectLine(source.substring(cursor), cursor);
    }
    return fields;
  }

  static List<IniSaveField> prioritize(List<IniSaveField> fields) {
    final sorted = fields.asMap().entries.toList();
    sorted.sort((a, b) {
      final rank = a.value.category.priority
          .compareTo(b.value.category.priority);
      return rank != 0 ? rank : a.key.compareTo(b.key);
    });
    return List<IniSaveField>.unmodifiable(
        sorted.map((entry) => entry.value));
  }

  /// Replace only the value's original code-unit span. If the text was
  /// modified after inspection, refuse a stale edit instead of guessing.
  static String changeNumber(
      String source, IniSaveField field, String replacement) {
    if (replacement.length > 64 || !_number.hasMatch(replacement)) {
      throw const FormatException('Введи обычное конечное число');
    }
    final number = num.tryParse(replacement);
    if (number == null || !number.isFinite) {
      throw const FormatException('Число выходит за допустимый диапазон');
    }
    if (_integer.hasMatch(field.value)) {
      if (!_integer.hasMatch(replacement) ||
          int.tryParse(replacement) == null) {
        throw const FormatException('Целочисленное поле должно остаться целым');
      }
    } else if (double.tryParse(replacement) == null) {
      throw const FormatException('Некорректное дробное число');
    }
    final start = field.lineStart;
    final end = start + field.originalLine.length;
    if (start < 0 || end > source.length ||
        source.substring(start, end) != field.originalLine) {
      throw StateError('Файл изменился после просмотра — открой поля заново');
    }
    final valueStart = start + field.valueStart;
    final valueEnd = start + field.valueEnd;
    final current = inspect(source, max: 10000)
        .where((candidate) =>
            candidate.lineIndex == field.lineIndex &&
            candidate.lineStart == field.lineStart &&
            candidate.originalLine == field.originalLine &&
            candidate.valueEnd == field.valueEnd &&
            candidate.key == field.key &&
            candidate.section == field.section &&
            candidate.valueStart == field.valueStart &&
            candidate.value == field.value)
        .toList();
    if (current.length != 1) {
      throw StateError('Поле больше не совпадает с исходным');
    }
    return source.replaceRange(valueStart, valueEnd, replacement);
  }
}
