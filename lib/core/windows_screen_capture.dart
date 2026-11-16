import 'dart:io';
import 'dart:typed_data';

/// Captures the user's visible desktop on Windows, after a short delay
/// so they can switch focus back to their single-player game.
/// Not a hidden screen recorder and not an overlay on top of other apps.
class WindowsScreenCapture {
  const WindowsScreenCapture._();

  static Future<Uint8List> captureAfter({
    Duration delay = const Duration(seconds: 4),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Захват экрана доступен только на Windows');
    }
    if (delay < Duration.zero || delay > const Duration(seconds: 15)) {
      throw RangeError('Недопустимая задержка захвата');
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final temp = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ehtid-screen-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    // Escape a single quote to prevent inserting a PowerShell statement
    // through an unusual TMP/TEMP directory name.
    final safePath = temp.path.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
\$bmp = New-Object System.Drawing.Bitmap(\$bounds.Width, \$bounds.Height)
\$graphics = [System.Drawing.Graphics]::FromImage(\$bmp)
try {
  \$graphics.CopyFromScreen(\$bounds.Left, \$bounds.Top, 0, 0, \$bmp.Size)
  \$bmp.Save('$safePath', [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  \$graphics.Dispose()
  \$bmp.Dispose()
}
''';
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      ).timeout(const Duration(seconds: 25));
      if (result.exitCode != 0 || !await temp.exists()) {
        throw StateError('Не удалось сделать снимок: ${result.stderr}');
      }
      final bytes = await temp.readAsBytes();
      if (bytes.isEmpty || bytes.length > 35 * 1024 * 1024) {
        throw StateError('Снимок слишком большой или пустой');
      }
      return bytes;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Keep the captured image private; do not let cleanup hide results.
      }
    }
  }
}

/// Optional local OCR through an already-installed Tesseract executable.
/// Graceful fallback: the user may always type the visible number manually.
class LocalScreenOcr {
  const LocalScreenOcr._();

  static Future<String?> recognizeTsv(Uint8List png) async {
    if (!Platform.isWindows) return null;
    final temp = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ehtid-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    try {
      await temp.writeAsBytes(png, flush: true);
      final result = await Process.run('tesseract',
        [temp.path, 'stdout', 'tsv'],
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) return null;
      return result.stdout.toString();
    } on ProcessException {
      return null;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // OCR failure does not block manual entry.
      }
    }
  }
}
