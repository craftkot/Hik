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
      if (conf == null || !conf.isFinite || conf < 30 || conf > 100 ||
          left == null || top == null || left < 0 || top < 0 ||
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
    if (!x.isFinite || !y.isFinite || !maxDistance.isFinite ||
        maxDistance < 0) return null;
    // Squaring an enormous but finite radius can overflow to Infinity,
    // accidentally accepting arbitrarily distant OCR tokens.
    final radiusSquared = maxDistance * maxDistance;
    if (!radiusSquared.isFinite) return null;
    // Direct callers must not bypass the TSV numeric-value filter.
    final numericValue = RegExp(r'^[+-]?\d{1,12}(?:\.\d{1,6})?\$');
    ScreenNumberToken? closest;
    var best = radiusSquared;
    var ambiguous = false;
    for (final token in tokens) {
      // Public callers may supply tokens without passing through parseTsv.
      // Never trust malformed geometry, confidence, or numeric text.
      if (!numericValue.hasMatch(token.value) ||
          token.left < 0 || token.top < 0 ||
          token.width <= 0 || token.height <= 0 ||
          !token.confidence.isFinite || token.confidence < 30 ||
          token.confidence > 100) continue;
      final distance = token.distanceSquaredTo(x, y);
      if (!distance.isFinite || distance > best) continue;
      if (closest == null || distance < best) {
        closest = token;
        best = distance;
        ambiguous = false;
      } else if (distance == best) {
        // Conflicting equidistant readings require manual selection.
        if (token.value != closest.value) ambiguous = true;
        if (token.confidence > closest.confidence) closest = token;
      }
    }
    return ambiguous ? null : closest;
  }
}
