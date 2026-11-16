import 'dart:convert';
import 'dart:typed_data';

/// A file discovered under a user-selected game folder, not an arbitrary
/// external process or a claimed decrypted asset.
class GameFile {
  const GameFile({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.size,
  });

  final String id;
  final String name;
  final String relativePath;
  final int size;

  String get extension {
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i).toLowerCase();
  }

  bool get isZipCandidate => const {
    '.zip', '.apk', '.jar', '.obb', '.mcpack', '.mrpack', '.pk3', '.xapk'
  }.contains(extension);

  bool get isImage => const {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}
      .contains(extension);

  bool get isLocalization {
    final path = relativePath.toLowerCase().replaceAll('\\', '/');
    return path.contains('/localization/') || path.contains('/locales/') ||
        path.contains('/lang/') || path.contains('/languages/') ||
        path.contains('/translations/') || path.contains('/i18n/') ||
        path.startsWith('locales/') || path.startsWith('lang/') ||
        path.startsWith('i18n/') ||
        const {'.lang', '.po', '.pot', '.strings', '.locres'}
            .contains(extension) ||
        name.toLowerCase().contains('localization') ||
        name.toLowerCase().contains('translation');
  }

  bool get isSave {
    final path = relativePath.toLowerCase().replaceAll('\\', '/');
    return path.contains('save') || path.contains('profile') ||
        path.contains('userdata') ||
        const {'.sav', '.save', '.slot', '.dat', '.sqlite', '.db'}
            .contains(extension);
  }

  bool get isLikelyPreload {
    return isImage || const {
      '.apk', '.jar', '.mrpack', '.pak', '.obb', '.bundle', '.assets', '.unity3d', '.bytes', '.zip',
      '.json', '.xml', '.csv', '.txt', '.bin', '.dat', '.atlas', '.ogg', '.wav'
    }.contains(extension);
  }

  bool get isJson => extension == '.json';
}

/// Decode text conservatively; never allow editing a binary save as garbled UTF-8.
String? decodeEditableText(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  if (bytes.length > 8 * 1024 * 1024) return null;
  if (bytes.contains(0)) return null;
  try {
    final decoded = const Utf8Decoder(allowMalformed: false).convert(bytes);
    final controls = decoded.runes.where((c) => c < 32 &&
        c != 9 && c != 10 && c != 13).length;
    if (controls > decoded.length / 100) return null;
    return decoded;
  } on FormatException {
    return null;
  }
}

String hexPreview(Uint8List bytes, {int limit = 4096}) {
  final out = StringBuffer();
  for (var i = 0; i < bytes.length && i < limit; i += 16) {
    out.write(i.toRadixString(16).padLeft(8, '0'));
    out.write('  ');
    final end = (i + 16 < bytes.length) ? i + 16 : bytes.length;
    for (var p = i; p < i + 16; p++) {
      out.write(p < end ? bytes[p].toRadixString(16).padLeft(2, '0') : '  ');
      out.write(' ');
    }
    out.write(' |');
    for (var p = i; p < end; p++) {
      final n = bytes[p];
      out.write(n >= 32 && n <= 126 ? String.fromCharCode(n) : '.');
    }
    out.writeln('|');
  }
  if (bytes.length > limit) out.writeln('… ещё ${bytes.length - limit} байт');
  return out.toString();
}

/// Identify known magic headers without guessing that proprietary assets
/// have been decrypted.
String identifyFile(Uint8List bytes) {
  if (bytes.length >= 4) {
    if (bytes[0] == 0x50 && bytes[1] == 0x4b &&
        ((bytes[2] == 3 && bytes[3] == 4) ||
         (bytes[2] == 5 && bytes[3] == 6))) return 'ZIP-контейнер';
    if (bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47) return 'PNG';
    if (bytes[0] == 0xff && bytes[1] == 0xd8) return 'JPEG';
    if (bytes[0] == 0x4f && bytes[1] == 0x67 &&
        bytes[2] == 0x67 && bytes[3] == 0x53) return 'OGG';
  }
  if (bytes.length >= 16) {
    final header = String.fromCharCodes(bytes.take(16));
    if (header.startsWith('SQLite format 3')) return 'SQLite 3';
    if (header.startsWith('UnityFS')) return 'UnityFS (Unity)';
  }
  return decodeEditableText(bytes) != null ? 'UTF-8 текст' : 'Неизвестный бинарный формат';
}
