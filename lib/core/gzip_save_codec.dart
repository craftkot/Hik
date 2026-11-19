import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// GZIP wrapper for ordinary local save files. This does not interpret any
/// proprietary serialization, encryption or game-specific checksums.
class GzipSaveCodec {
  const GzipSaveCodec._();

  /// The editor and desktop backup writer both enforce an 8 MiB file limit.
  /// Apply it to the *expanded* data too, to reject GZIP bombs.
  static const int maxBytes = 8 * 1024 * 1024;
  static const int _chunkSize = 64 * 1024;

  static bool isGzip(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0x1f && bytes[1] == 0x8b && bytes[2] == 0x08;

  /// Decodes only standard GZIP, with an enforced expanded-size bound.
  /// Raises FormatException for corrupted or unsupported streams.
  static Uint8List decode(Uint8List compressed) {
    if (!isGzip(compressed)) {
      throw const FormatException('Файл не содержит заголовок GZIP');
    }
    if (compressed.length > maxBytes) {
      throw const FormatException('Сжатый сейв превышает лимит 8 МиБ');
    }
    final output = _BoundedGzipSink(maxBytes);
    try {
      final decoder = gzip.decoder.startChunkedConversion(output);
      for (var offset = 0; offset < compressed.length; offset += _chunkSize) {
        decoder.add(compressed.sublist(
          offset, math.min(offset + _chunkSize, compressed.length)));
      }
      decoder.close();
      return output.takeBytes();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'GZIP повреждён или использует неподдерживаемую упаковку');
    }
  }

  /// Recompress a modified payload, then validate its decompressed content.
  /// Callers must use writeWithBackup(expected: originalCompressedBytes).
  static Uint8List encode(Uint8List expanded) {
    if (expanded.length > maxBytes) {
      throw const FormatException('Распакованный сейв превышает лимит 8 МиБ');
    }
    final result = Uint8List.fromList(gzip.encode(expanded));
    if (result.length > maxBytes) {
      throw const FormatException('Сжатый сейв превышает лимит 8 МиБ');
    }
    final roundTrip = decode(result);
    if (roundTrip.length != expanded.length) {
      throw StateError('GZIP не прошёл проверку после сжатия');
    }
    for (var i = 0; i < expanded.length; i++) {
      if (roundTrip[i] != expanded[i]) {
        throw StateError('GZIP не прошёл проверку после сжатия');
      }
    }
    return result;
  }
}

class _BoundedGzipSink implements Sink<List<int>> {
  _BoundedGzipSink(this.limit);

  final int limit;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _size = 0;

  @override
  void add(List<int> bytes) {
    if (bytes.length > limit - _size) {
      throw const FormatException('Распакованный GZIP превышает лимит 8 МиБ');
    }
    _builder.add(bytes);
    _size += bytes.length;
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}
