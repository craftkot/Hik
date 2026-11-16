import 'dart:typed_data';

/// Explicit numeric encodings commonly found in uncompressed offline saves.
/// This is a file editor, NOT a live process-memory scanner.
enum SaveNumberFormat {
  int32Little('Int32 · LE', 4, Endian.little, false),
  int32Big('Int32 · BE', 4, Endian.big, false),
  float32Little('Float32 · LE', 4, Endian.little, true),
  float32Big('Float32 · BE', 4, Endian.big, true);

  const SaveNumberFormat(this.label, this.width, this.endian, this.isFloat);
  final String label;
  final int width;
  final Endian endian;
  final bool isFloat;
}

class SaveNumberHit {
  const SaveNumberHit(this.offset);
  final int offset;

  String get hexOffset => '0x${offset.toRadixString(16).padLeft(8, '0')}';
}

/// Searches exact encoded bytes and applies fixed-width patches to a COPY.
/// Deliberately avoids guessing protected, compressed, or checksummed formats.
class BinarySaveEditor {
  const BinarySaveEditor._();

  static Uint8List encode(String value, SaveNumberFormat format) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw const FormatException('Введи число');
    }
    final bytes = ByteData(format.width);
    if (format.isFloat) {
      final parsed = double.tryParse(raw);
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Нужно конечное дробное число');
      }
      bytes.setFloat32(0, parsed, format.endian);
      if (!bytes.getFloat32(0, format.endian).isFinite) {
        throw const FormatException('Число не помещается в Float32');
      }
    } else {
      final parsed = int.tryParse(raw);
      if (parsed == null ||
          parsed < -2147483648 ||
          parsed > 2147483647) {
        throw const FormatException('Int32: диапазон от -2147483648 до 2147483647');
      }
      bytes.setInt32(0, parsed, format.endian);
    }
    return Uint8List.fromList(bytes.buffer.asUint8List());
  }

  static List<SaveNumberHit> search(
    Uint8List data,
    String value,
    SaveNumberFormat format, {
    int maxResults = 100,
  }) {
    if (maxResults < 1 || maxResults > 10000) {
      throw const RangeError('Лимит совпадений вне диапазона');
    }
    final needle = encode(value, format);
    final matches = <SaveNumberHit>[];
    for (var offset = 0; offset <= data.length - needle.length; offset++) {
      var matched = true;
      for (var j = 0; j < needle.length; j++) {
        if (data[offset + j] != needle[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        matches.add(SaveNumberHit(offset));
        if (matches.length >= maxResults) break;
      }
    }
    return matches;
  }

  /// The caller must compare the on-disk original before writing the result,
  /// and persist it using writeWithBackup.
  static Uint8List patch(
    Uint8List original, {
    required int offset,
    required String expected,
    required String replacement,
    required SaveNumberFormat format,
  }) {
    final before = encode(expected, format);
    final after = encode(replacement, format);
    if (offset < 0 || offset > original.length - before.length) {
      throw RangeError('Смещение вне файла');
    }
    for (var i = 0; i < before.length; i++) {
      if (original[offset + i] != before[i]) {
        throw StateError('Исходное значение изменилось: обнови поиск');
      }
    }
    final result = Uint8List.fromList(original);
    result.setRange(offset, offset + after.length, after);
    return result;
  }
}
