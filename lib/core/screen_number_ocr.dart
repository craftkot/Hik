/// Numeric OCR tokens are hints only. They must never be treated as
/// verified locations in another application's memory.
class ScreenNumberToken {
  const ScreenNumberToken({
    required this.value,
    required this.raw,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.confidence,
  });

  final String value;
  final String raw;
  final int left;
  final int top;
  final int width;
  final int height;
  final double confidence;

  double distanceSquaredTo(double x, double y) {
    final dx = x < left ? left - x :
      x > left + width ? x - (left + width) : 0.0;
    final dy = y < top ? top - y :
      y > top + height ? y - (top + height) : 0.0;
    return dx * dx + dy * dy;
  }
}

class ScreenNumberOcr {
  const ScreenNumberOcr._();

  /// Parses Tesseract's TSV output and keeps only unambiguous numbers
  /// such as 105, -35, 1.5, 105/200. For an HP fraction, the editable
  /// candidate is the left value; the whole label stays visible.
  static List<ScreenNumberToken> parseTsv(String tsv) {
    final lines = tsv.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return const [];
    final columns = lines.first.split('\t');
    int column(String name) => columns.indexOf(name);
    final indices = <String, int>{
      for (final name in ['left', 'top', 'width', 'height', 'conf', 'text'])
        name: column(name),
    };
    if (indices.values.any((i) => i < 0)) return const [];
    final tokens = <ScreenNumberToken>[];
    final pattern = RegExp(
      r'^([+-]?\d{1,12}(?:[.,]\d{1,6})?)'
      r'(?:\s*/\s*\d{1,12}(?:[.,]\d{1,6})?)?$',
    );
    for (final line in lines.skip(1)) {
      if (tokens.length >= 10000) break;
      final parts = line.split('\t');
      if (parts.length <= indices.values.reduce(
          (a, b) => a > b ? a : b)) continue;
      final raw = parts[indices['text']!].trim();
      final match = pattern.firstMatch(raw);
      if (match == null) continue;
      final conf = double.tryParse(parts[indices['conf']!]);
      final left = int.tryParse(parts[indices['left']!]);
      final top = int.tryParse(parts[indices['top']!]);
      final width = int.tryParse(parts[indices['width']!]);
      final height = int.tryParse(parts[indices['height']!]);
      if (conf == null || conf < 30 || left == null || top == null ||
          width == null || height == null || width < 1 || height < 1) {
        continue;
      }
      tokens.add(ScreenNumberToken(
        value: match.group(1)!.replaceAll(',', '.'),
        raw: raw,
        left: left,
        top: top,
        width: width,
        height: height,
        confidence: conf,
      ));
    }
    return tokens;
  }

  /// Only use OCR results very close to the actual click.
  static ScreenNumberToken? atPoint(
    List<ScreenNumberToken> tokens,
    double x,
    double y, {
    double maxDistance = 30,
  }) {
    ScreenNumberToken? closest;
    var best = maxDistance * maxDistance;
    for (final token in tokens) {
      final distance = token.distanceSquaredTo(x, y);
      if (distance > best) continue;
      if (closest == null || distance < best ||
          (distance == best && token.confidence > closest.confidence)) {
        closest = token;
        best = distance;
      }
    }
    return closest;
  }
}
