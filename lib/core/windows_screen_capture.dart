import 'dart:async';
import 'dart:convert';
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
      // Prefer the local Windows OCR engine; Russian/English availability
      // depends on the installed Windows recognition language packs.
      final builtIn = await _windowsOcr(temp.path);
      if (builtIn != null) return builtIn;
      for (final args in [
        [temp.path, 'stdout', '-l', 'rus+eng', '--psm', '11', 'tsv'],
        [temp.path, 'stdout', '--psm', '11', 'tsv'],
      ]) {
        final result = await Process.run('tesseract', args)
            .timeout(const Duration(seconds: 20));
        if (result.exitCode == 0) return result.stdout.toString();
      }
      return null;
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

  static Future<String?> _windowsOcr(String path) async {
    final safePath = path.replaceAll("'", "''");
    final script = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.IRandomAccessStreamWithContentType,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap,Windows.Graphics.Imaging,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrResult,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null
[Windows.Globalization.Language,Windows.Globalization,ContentType=WindowsRuntime] | Out-Null
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and
  $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation' + [char]96 + '1'
} | Select-Object -First 1
if ($null -eq $asTask) { throw 'WinRT async bridge unavailable' }
function Await($operation,[Type]$type) {
  $task = $asTask.MakeGenericMethod($type).Invoke($null,@($operation))
  if (-not $task.Wait(15000)) { throw 'OCR operation timed out' }
  $task.Result
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('__PATH__')) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
$bitmap = $null
try {
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  if ($decoder.PixelWidth -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or
      $decoder.PixelHeight -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension) {
    throw 'Window exceeds Windows OCR dimensions'
  }
  $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  if ($null -eq $engine) { throw 'No installed OCR language' }
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
  Write-Output "level	page_num	block_num	par_num	line_num	word_num	left	top	width	height	conf	text"
  $lineNo = 0
  foreach ($line in $result.Lines) {
    $lineNo++
    $wordNo = 0
    foreach ($word in $line.Words) {
      $wordNo++
      $r = $word.BoundingRect
      $left = [int][Math]::Floor($r.X); $top = [int][Math]::Floor($r.Y)
      $width = [int][Math]::Ceiling($r.Width); $height = [int][Math]::Ceiling($r.Height)
      $text = $word.Text -replace '[\t\r\n]', ' '
      # WinRT does not expose a confidence score; 50 is a neutral marker,
      # not a measured probability or verified memory value.
      Write-Output (@(5,1,1,1,$lineNo,$wordNo,$left,$top,$width,$height,50,$text) -join [char]9)
    }
  }
} finally {
  if ($null -ne $bitmap) { $bitmap.Dispose() }
  $stream.Dispose()
}
'''.replaceAll('__PATH__', safePath);
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-Command', script,
      ], stdoutEncoding: const Utf8Codec(allowMalformed: true))
          .timeout(const Duration(seconds: 45));
      if (result.exitCode != 0) return null;
      final output = result.stdout.toString();
      return output.contains('word_num') && output.trim().split('\n').length > 1
          ? output : null;
    } catch (_) {
      return null;
    }
  }
}
