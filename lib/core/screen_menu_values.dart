/// OCR menu values are suggestions only, never verified RAM addresses.
class ScreenMenuValue {
  const ScreenMenuValue({
    required this.label, required this.value, required this.role,
    required this.line, required this.percent,
  });
  final String label;
  final String value;
  final String role;
  final String line;
  final bool percent;

  String get input => value + (percent ? '%' : '');
}

class _Word {
  const _Word(this.text, this.x, this.y, this.width, this.height);
  final String text;
  final int x, y, width, height;
  double get centerY => y + height / 2;
}

class ScreenMenuValues {
  const ScreenMenuValues._();

  /// Join words by visual row rather than OCR paragraph: stat names and
  /// right-aligned numbers often belong to different OCR blocks.
  static List<ScreenMenuValue> parseTsv(String tsv) {
    if (tsv.length > 4 * 1024 * 1024) return const [];
    final lines = tsv.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return const [];
    final columns = lines.first.split('\t');
    final names = ['left','top','width','height','conf','text'];
    final indices = names.map(columns.indexOf).toList();
    if (indices.any((i) => i < 0)) return const [];
    final words = <_Word>[];
    for (final line in lines.skip(1)) {
      if (words.length >= 4000) break;
      final parts = line.split('\t');
      if (indices.any((i) => i >= parts.length)) continue;
      final x = int.tryParse(parts[indices[0]]);
      final y = int.tryParse(parts[indices[1]]);
      final w = int.tryParse(parts[indices[2]]);
      final h = int.tryParse(parts[indices[3]]);
      final confidence = double.tryParse(parts[indices[4]]);
      final text = parts[indices[5]].trim();
      if (x == null || y == null || w == null || h == null ||
          x < 0 || y < 0 || w < 1 || h < 1 ||
          x > 12000 || y > 12000 || w > 12000 || h > 12000 ||
          confidence == null || !confidence.isFinite ||
          confidence < 30 || confidence > 100 ||
          text.isEmpty || text.length > 300) continue;
      words.add(_Word(text, x, y, w, h));
    }
    words.sort((a,b) => a.centerY.compareTo(b.centerY));
    final rows = <List<_Word>>[];
    for (final word in words) {
      if (rows.isEmpty) {
        rows.add([word]);
        continue;
      }
      final anchor = rows.last.first;
      final tolerance = (anchor.height < word.height
          ? anchor.height : word.height) * 0.6;
      if ((word.centerY - anchor.centerY).abs() <= tolerance) {
        rows.last.add(word);
      } else {
        rows.add([word]);
      }
    }
    const number = r'[+-]?\d{1,12}(?:[.,]\d{1,6})?';
    final pattern = RegExp(
      r'(^|[\s:])(' + number + r')'
      r'(?:\s*/\s*(' + number + r')|\s*(%))?(?=$|[\s:;])',
    );
    final result = <ScreenMenuValue>[];
    for (final row in rows) {
      if (result.length >= 200) break;
      row.sort((a,b) => a.x.compareTo(b.x));
      final line = row.map((w) => w.text).join(' ');
      var previousEnd = 0;
      var lastLabel = '';
      for (final match in pattern.allMatches(line)) {
        if (result.length >= 200) break;
        final before = line.substring(previousEnd, match.start)
            .trim().replaceFirst(RegExp(r'[:\s]+$'), '');
        final hasLetters = RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(before);
        if (hasLetters) lastLabel = before;
        final label = lastLabel.isEmpty ? 'Число на экране' : lastLabel;
        final first = match.group(2)!.replaceAll(',', '.');
        final second = match.group(3)?.replaceAll(',', '.');
        result.add(ScreenMenuValue(
          label: label, value: first, line: line,
          role: second == null ? '' : 'Текущее / левая часть',
          percent: match.group(4) != null,
        ));
        if (second != null && result.length < 200) {
          result.add(ScreenMenuValue(
            label: label, value: second, line: line,
            role: 'Максимум / правая часть', percent: false,
          ));
        }
        previousEnd = match.end;
      }
    }
    return List.unmodifiable(result);
  }
}
