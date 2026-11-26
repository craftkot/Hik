import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Captures the user's visible desktop on Windows, after a short delay
/// so they can switch focus back to their single-player game.
/// Not a hidden screen recorder and not an overlay on top of other apps.
class WindowsScreenCapture {
  const WindowsScreenCapture._();

  /// Capture only the visible client area of the chosen foreground game.
  /// Require the same PID and creation time before and after the capture.
  static Future<Uint8List> captureGameAfter({
    required int pid,
    required int processStartTicks,
    Duration delay = const Duration(seconds: 4),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Захват окна доступен только на Windows');
    }
    if (pid <= 0 || processStartTicks <= 0 ||
        delay < Duration.zero || delay > const Duration(seconds: 15)) {
      throw ArgumentError('Некорректный процесс или задержка');
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final folder = await Directory.systemTemp.createTemp('ehtid-game-screen-');
    final file = File(folder.path + Platform.pathSeparator + 'game.png');
    final safePath = file.path.replaceAll("'", "''");
    final script = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class EhtidWindow {
  [StructLayout(LayoutKind.Sequential)] public struct RECT {
    public int Left,Top,Right,Bottom;
  }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][EhtidWindow]::SetProcessDPIAware()
$game = Get-Process -Id __PID__ -ErrorAction Stop
if ($game.StartTime.ToUniversalTime().Ticks -ne __TICKS__) { throw 'Game process changed' }
$window = [EhtidWindow]::GetForegroundWindow()
[uint32]$owner = 0
[void][EhtidWindow]::GetWindowThreadProcessId($window,[ref]$owner)
if ($owner -ne __PID__ -or [EhtidWindow]::IsIconic($window)) {
  throw 'Switch to the selected game before capture'
}
$r = New-Object EhtidWindow+RECT
$p = New-Object EhtidWindow+POINT
if (-not [EhtidWindow]::GetClientRect($window,[ref]$r) -or
    -not [EhtidWindow]::ClientToScreen($window,[ref]$p)) {
  throw 'Cannot locate selected game window'
}
$width = $r.Right - $r.Left
$height = $r.Bottom - $r.Top
$desktop = [System.Windows.Forms.SystemInformation]::VirtualScreen
if ($width -le 0 -or $height -le 0 -or $width -gt 8192 -or $height -gt 8192 -or
    ([long]$width * $height) -gt 33554432 -or
    $p.X -lt $desktop.Left -or $p.Y -lt $desktop.Top -or
    ($p.X + $width) -gt $desktop.Right -or ($p.Y + $height) -gt $desktop.Bottom) {
  throw 'Game window must be entirely visible on the desktop'
}
$bmp = [System.Drawing.Bitmap]::new($width,$height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
try {
  $g.CopyFromScreen($p.X,$p.Y,0,0,$bmp.Size)
  if ([EhtidWindow]::GetForegroundWindow() -ne $window) {
    throw 'Foreground window changed during capture'
  }
  $again = Get-Process -Id __PID__ -ErrorAction Stop
  if ($again.StartTime.ToUniversalTime().Ticks -ne __TICKS__) { throw 'Game process changed' }
  $bmp.Save('__PATH__',[System.Drawing.Imaging.ImageFormat]::Png)
} finally { $g.Dispose(); $bmp.Dispose() }
'''
        .replaceAll('__PID__', pid.toString())
        .replaceAll('__TICKS__', processStartTicks.toString())
        .replaceAll('__PATH__', safePath);
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-Command', script,
      ]).timeout(const Duration(seconds: 25));
      if (result.exitCode != 0 || !await file.exists()) {
        throw StateError('Не удалось снять выбранную игру: ' +
            result.stderr.toString().trim());
      }
      final size = await file.length();
      if (size <= 0 || size > 35 * 1024 * 1024) {
        throw StateError('Снимок слишком большой или пустой');
      }
      return await file.readAsBytes();
    } finally {
      try { await folder.delete(recursive: true); }
      on FileSystemException { /* Cleanup must not hide capture errors. */ }
    }
  }

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
\$bmp = [System.Drawing.Bitmap]::new(\$bounds.Width, \$bounds.Height)
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
        ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', script],
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
    } on TimeoutException {
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
