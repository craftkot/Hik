import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Numeric encodings for local Windows single-player processes only.
enum LiveValueFormat {
  int32('i32', 'Целое · 32 бит', 4),
  int64('i64', 'Целое · 64 бит', 8),
  float32('f32', 'Дробное · 32 бит', 4),
  float64('f64', 'Дробное · 64 бит', 8);

  const LiveValueFormat(this.code, this.label, this.width);
  final String code;
  final String label;
  final int width;
}

/// Different common storage representations of an on-screen percentage.
/// A percentage of 80 may be stored as 80, 0.8, or 8000 basis points.
enum LivePercentEncoding {
  int32Points(LiveValueFormat.int32, 0, 'Int32 · проценты'),
  float32Ratio(LiveValueFormat.float32, -2, 'Float32 · коэффициент'),
  float64Ratio(LiveValueFormat.float64, -2, 'Float64 · коэффициент'),
  float32Points(LiveValueFormat.float32, 0, 'Float32 · проценты'),
  float64Points(LiveValueFormat.float64, 0, 'Float64 · проценты'),
  int64Points(LiveValueFormat.int64, 0, 'Int64 · проценты'),
  int32Basis(LiveValueFormat.int32, 2, 'Int32 · базисные пункты'),
  int64Basis(LiveValueFormat.int64, 2, 'Int64 · базисные пункты');

  const LivePercentEncoding(this.format, this.decimalShift, this.label);
  final LiveValueFormat format;
  final int decimalShift;
  final String label;

  static String normalize(String input) {
    var value = input.trim().replaceAll(',', '.');
    if (value.endsWith('%')) value = value.substring(0, value.length - 1).trim();
    if (!RegExp(r'^[+-]?\d{1,12}(?:\.\d{1,6})?
  snapshot('all', 'Обновить показания'),
  changed('changed', 'Изменилось'),
  unchanged('unchanged', 'Не изменилось'),
  increased('increased', 'Увеличилось'),
  decreased('decreased', 'Уменьшилось');

  const LiveChangeMode(this.code, this.label);
  final String code;
  final String label;
}

class LiveGameProcess {
  const LiveGameProcess({required this.pid, required this.name, required this.title, this.processStartTicks});
  final int pid;
  final String name;
  final String title;
  /// UTC creation ticks; prevents writes after Windows reuses a PID.
  final int? processStartTicks;

  /// A PID can be recycled. Only preserve a UI selection when both
  /// observations have the same non-null Windows creation timestamp.
  bool isSameInstanceAs(LiveGameProcess other) =>
      pid == other.pid &&
      processStartTicks != null &&
      processStartTicks == other.processStartTicks;
}

class LiveMemoryScan {
  const LiveMemoryScan({
    required this.addresses,
    required this.scannedBytes,
    required this.truncated,
    required this.regions,
    this.values = const [],
    this.invalidated = 0,
  });
  final List<String> addresses;
  /// Snapshot of the current value for each address returned by relative scan.
  final List<String> values;
  /// Candidates skipped because their memory is no longer readable.
  final int invalidated;
  final int scannedBytes;
  final bool truncated;
  final int regions;

  static LiveMemoryScan fromJson(Map<String, dynamic> json) {
    final addresses = (json['addresses'] as List<dynamic>?) ?? const [];
    if (addresses.length > 5000 ||
        addresses.any((value) => value is! String ||
            !RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(value))) {
      throw const FormatException('Некорректные адреса в результате');
    }
    final values = (json['values'] as List<dynamic>?) ?? const [];
    if (values.isNotEmpty &&
        (values.length != addresses.length ||
         values.any((item) => item is! String ||
           !RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$')
             .hasMatch(item)))) {
      throw const FormatException('Некорректный список числовых снимков');
    }
    // A helper response is untrusted input. Do not silently truncate
    // fractional counters or accept negative/boolean-like metadata.
    int nonNegativeCount(String key) {
      final value = json[key];
      if (value == null) return 0; // Older helpers omitted these counters.
      if (value is! int || value < 0) {
        throw FormatException('Некорректное поле $key в результате');
      }
      return value;
    }

    final truncated = json['truncated'];
    if (truncated != null && truncated is! bool) {
      throw const FormatException('Некорректный признак усечения результата');
    }
    return LiveMemoryScan(
      addresses: List<String>.unmodifiable(addresses.cast<String>()),
      values: List<String>.unmodifiable(values.cast<String>()),
      invalidated: nonNegativeCount('invalidated'),
      scannedBytes: nonNegativeCount('scannedBytes'),
      truncated: truncated == true,
      regions: nonNegativeCount('regions'),
    );
  }
}

/// Only launches a local bundled helper with user-selected PID, requires OS
/// permissions, never attempts privilege escalation, injection or bypass.
class WindowsLiveMemoryService {
  Process? _active;

  String get helperPath => p.join(
        File(Platform.resolvedExecutable).parent.path, 'EHTID-MemoryHelper.exe');

  bool get isSupported => Platform.isWindows;

  void cancel() {
    _active?.kill();
    _active = null;
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Редактор памяти работает только в Windows');
    }
    if (!await File(helperPath).exists()) {
      throw StateError('EHTID-MemoryHelper.exe не найден рядом с game_lab.exe. '
          'Распакуй весь ZIP, не запускай отдельный EXE из архива.');
    }
    if (_active != null) throw StateError('Другая операция ещё выполняется');
    final process = await Process.start(helperPath, const []);
    _active = process;
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    try {
      process.stdin.write(jsonEncode(body));
      await process.stdin.close();
      final code = await process.exitCode.timeout(timeout);
      final output = await outputFuture;
      final error = await errorFuture;
      if (output.trim().isEmpty) {
        throw StateError('Нет ответа от модуля памяти. $error (код $code)');
      }
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ответ модуля памяти повреждён');
      }
      if (decoded['ok'] != true) {
        throw StateError((decoded['error'] ?? error).toString());
      }
      if (code != 0) throw StateError('Модуль памяти завершился с кодом $code');
      return decoded;
    } on TimeoutException {
      process.kill();
      throw StateError('Сканирование превысило 120 секунд и было остановлено');
    } finally {
      if (identical(process, _active)) _active = null;
    }
  }

  Future<List<LiveGameProcess>> processes() async {
    final response = await _request({'command': 'list'});
    final raw = response['processes'] as List<dynamic>? ?? const [];
    return raw.map((value) {
      final row = value as Map<String, dynamic>;
      return LiveGameProcess(
        pid: (row['pid'] as num).toInt(),
        name: row['name'] as String,
        title: row['title'] as String,
        processStartTicks: (row['processStartTicks'] as num?)?.toInt(),
      );
    }).toList(growable: false);
  }

  static void validateValue(String value, LiveValueFormat format) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty || normalized.length > 45) {
      throw const FormatException('Введи число длиной до 45 символов');
    }
    final fractional = format == LiveValueFormat.float32 ||
        format == LiveValueFormat.float64;
    if (fractional) {
      final parsed = double.tryParse(normalized);
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Нужно конечное дробное число');
      }
      // A nonzero decimal can underflow while parsing to a Dart double.
      final mantissa = normalized.split(RegExp(r'[eE]')).first;
      if (parsed == 0 && RegExp(r'[1-9]').hasMatch(mantissa)) {
        throw const FormatException('Число слишком мало для представления');
      }
      if (format == LiveValueFormat.float32) {
        // Half of the smallest Float32 subnormal rounds to zero.
        if (parsed.abs() > 3.4028235e38 ||
            (parsed != 0 && parsed.abs() < 7.006492321624085e-46)) {
          throw const FormatException('Значение вне диапазона Float32');
        }
      }
    } else {
      final parsed = BigInt.tryParse(normalized);
      if (parsed == null) throw const FormatException('Нужно целое число');
      final bitCount = format.width * 8;
      final lower = -(BigInt.one << (bitCount - 1));
      final upper = (BigInt.one << (bitCount - 1)) - BigInt.one;
      if (parsed < lower || parsed > upper) {
        throw FormatException('Число не помещается в $bitCount бит');
      }
    }
  }

  Future<LiveMemoryScan> scan({
    required int pid,
    required String value,
    required LiveValueFormat format,
    int budgetMiB = 512,
    int maxResults = 3000,
    bool bytewise = false,
  }) async {
    validateValue(value, format);
    if (budgetMiB < 16 || budgetMiB > 2048) {
      throw RangeError('Допустимо 16–2048 МиБ');
    }
    if (maxResults < 1 || maxResults > 5000) {
      throw RangeError('Допустимо 1–5000 совпадений');
    }
    // Unaligned scanning checks each byte offset instead of only every
    // fourth/eighth address. Keep the extra CPU cost bounded.
    if (bytewise && budgetMiB > 512) {
      throw RangeError('Для побайтового поиска максимум 512 МиБ');
    }
    final response = await _request({
      'command': 'scan',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'maxBytes': budgetMiB * 1024 * 1024,
      'maxResults': maxResults,
      'alignment': bytewise ? 1 : format.width,
    });
    return LiveMemoryScan.fromJson(response);
  }

  /// Try each representable percentage encoding separately, retaining the
  /// format with each result. Read-only; no candidate is written implicitly.
  Future<List<LivePercentScanGroup>> scanPercent({
    required int pid,
    required String percent,
    int budgetMiB = 512,
    bool bytewise = false,
    void Function(LivePercentEncoding encoding)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    LivePercentEncoding.normalize(percent);
    final groups = <LivePercentScanGroup>[];
    for (final encoding in LivePercentEncoding.values) {
      if (shouldContinue?.call() == false) break;
      String raw;
      try {
        raw = encoding.encode(percent);
      } on FormatException {
        continue; // Fractional percentage not representable in integer format.
      }
      onProgress?.call(encoding);
      final result = await scan(pid: pid, format: encoding.format,
          value: raw, budgetMiB: budgetMiB, bytewise: bytewise);
      groups.add(LivePercentScanGroup(encoding, raw, result));
    }
    return List.unmodifiable(groups);
  }

  Future<LiveMemoryScan> refine({
    required int pid,
    required String value,
    required LiveValueFormat format,
    required List<String> addresses,
  }) async {
    validateValue(value, format);
    final response = await _request({
      'command': 'refine',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'addresses': addresses,
    });
    return LiveMemoryScan.fromJson(response);
  }

  /// Read-only snapshot or relative refinement over existing addresses only.
  /// In snapshot mode ("all") readable candidates are kept regardless of
  /// their change and their latest numeric values are returned.
  /// Does not write process memory.
  ///
  /// Relative refinement across already-found addresses only.
  /// Every candidate needs its own previous numeric baseline to avoid
  /// treating unrelated RAM locations as one HP value.
  Future<LiveMemoryScan> compare({
    required int pid,
    required LiveValueFormat format,
    required List<String> addresses,
    required List<String> baselines,
    required LiveChangeMode mode,
  }) async {
    if (addresses.isEmpty || addresses.length > 5000 ||
        addresses.length != baselines.length) {
      throw const FormatException('Нужны 1–5000 адресов со снимками значений');
    }
    for (final value in baselines) {
      validateValue(value, format);
    }
    for (final address in addresses) {
      if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
        throw const FormatException('Некорректный адрес кандидата');
      }
    }
    final response = await _request({
      'command': 'compare',
      'pid': pid,
      'format': format.code,
      'mode': mode.code,
      'addresses': addresses,
      'baselines': baselines,
    });
    final compared = LiveMemoryScan.fromJson(response);
    if (compared.values.length != compared.addresses.length) {
      throw const FormatException('Модуль не вернул значения для адресов');
    }
    return compared;
  }

  Future<void> write({
    required int pid,
    required LiveValueFormat format,
    required String address,
    required String expected,
    required String replacement,
    int? processStartTicks,
  }) async {
    if (processStartTicks == null || processStartTicks <= 0) {
      throw StateError('Обнови список игр: не получено время запуска процесса');
    }
    validateValue(expected, format);
    validateValue(replacement, format);
    if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
      throw const FormatException('Некорректный адрес памяти');
    }
    await _request({
      'command': 'write',
      'pid': pid,
      'processStartTicks': processStartTicks,
      'format': format.code,
      'address': address,
      'expected': expected.replaceAll(',', '.'),
      'replacement': replacement.replaceAll(',', '.'),
    });
  }
}
).hasMatch(value)) {
      throw const FormatException('Введите процент, например 80% или 12,5%');
    }
    return value;
  }

  /// Decimal shift with no intermediate binary floating-point rounding.
  String encode(String input) {
    var value = normalize(input);
    final negative = value.startsWith('-');
    if (negative || value.startsWith('+')) value = value.substring(1);
    final parts = value.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final digits = parts[0] + fraction;
    final point = parts[0].length + decimalShift;
    final padded = point <= 0
        ? '0.' + ''.padLeft(-point, '0') + digits
        : point >= digits.length
            ? digits.padRight(point, '0')
            : digits.substring(0, point) + '.' + digits.substring(point);
    final halves = padded.split('.');
    final whole = BigInt.parse(halves[0]).toString();
    final tail = halves.length == 2
        ? halves[1].replaceFirst(RegExp(r'0+
  snapshot('all', 'Обновить показания'),
  changed('changed', 'Изменилось'),
  unchanged('unchanged', 'Не изменилось'),
  increased('increased', 'Увеличилось'),
  decreased('decreased', 'Уменьшилось');

  const LiveChangeMode(this.code, this.label);
  final String code;
  final String label;
}

class LiveGameProcess {
  const LiveGameProcess({required this.pid, required this.name, required this.title, this.processStartTicks});
  final int pid;
  final String name;
  final String title;
  /// UTC creation ticks; prevents writes after Windows reuses a PID.
  final int? processStartTicks;

  /// A PID can be recycled. Only preserve a UI selection when both
  /// observations have the same non-null Windows creation timestamp.
  bool isSameInstanceAs(LiveGameProcess other) =>
      pid == other.pid &&
      processStartTicks != null &&
      processStartTicks == other.processStartTicks;
}

class LiveMemoryScan {
  const LiveMemoryScan({
    required this.addresses,
    required this.scannedBytes,
    required this.truncated,
    required this.regions,
    this.values = const [],
    this.invalidated = 0,
  });
  final List<String> addresses;
  /// Snapshot of the current value for each address returned by relative scan.
  final List<String> values;
  /// Candidates skipped because their memory is no longer readable.
  final int invalidated;
  final int scannedBytes;
  final bool truncated;
  final int regions;

  static LiveMemoryScan fromJson(Map<String, dynamic> json) {
    final addresses = (json['addresses'] as List<dynamic>?) ?? const [];
    if (addresses.length > 5000 ||
        addresses.any((value) => value is! String ||
            !RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(value))) {
      throw const FormatException('Некорректные адреса в результате');
    }
    final values = (json['values'] as List<dynamic>?) ?? const [];
    if (values.isNotEmpty &&
        (values.length != addresses.length ||
         values.any((item) => item is! String ||
           !RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$')
             .hasMatch(item)))) {
      throw const FormatException('Некорректный список числовых снимков');
    }
    // A helper response is untrusted input. Do not silently truncate
    // fractional counters or accept negative/boolean-like metadata.
    int nonNegativeCount(String key) {
      final value = json[key];
      if (value == null) return 0; // Older helpers omitted these counters.
      if (value is! int || value < 0) {
        throw FormatException('Некорректное поле $key в результате');
      }
      return value;
    }

    final truncated = json['truncated'];
    if (truncated != null && truncated is! bool) {
      throw const FormatException('Некорректный признак усечения результата');
    }
    return LiveMemoryScan(
      addresses: List<String>.unmodifiable(addresses.cast<String>()),
      values: List<String>.unmodifiable(values.cast<String>()),
      invalidated: nonNegativeCount('invalidated'),
      scannedBytes: nonNegativeCount('scannedBytes'),
      truncated: truncated == true,
      regions: nonNegativeCount('regions'),
    );
  }
}

/// Only launches a local bundled helper with user-selected PID, requires OS
/// permissions, never attempts privilege escalation, injection or bypass.
class WindowsLiveMemoryService {
  Process? _active;

  String get helperPath => p.join(
        File(Platform.resolvedExecutable).parent.path, 'EHTID-MemoryHelper.exe');

  bool get isSupported => Platform.isWindows;

  void cancel() {
    _active?.kill();
    _active = null;
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Редактор памяти работает только в Windows');
    }
    if (!await File(helperPath).exists()) {
      throw StateError('EHTID-MemoryHelper.exe не найден рядом с game_lab.exe. '
          'Распакуй весь ZIP, не запускай отдельный EXE из архива.');
    }
    if (_active != null) throw StateError('Другая операция ещё выполняется');
    final process = await Process.start(helperPath, const []);
    _active = process;
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    try {
      process.stdin.write(jsonEncode(body));
      await process.stdin.close();
      final code = await process.exitCode.timeout(timeout);
      final output = await outputFuture;
      final error = await errorFuture;
      if (output.trim().isEmpty) {
        throw StateError('Нет ответа от модуля памяти. $error (код $code)');
      }
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ответ модуля памяти повреждён');
      }
      if (decoded['ok'] != true) {
        throw StateError((decoded['error'] ?? error).toString());
      }
      if (code != 0) throw StateError('Модуль памяти завершился с кодом $code');
      return decoded;
    } on TimeoutException {
      process.kill();
      throw StateError('Сканирование превысило 120 секунд и было остановлено');
    } finally {
      if (identical(process, _active)) _active = null;
    }
  }

  Future<List<LiveGameProcess>> processes() async {
    final response = await _request({'command': 'list'});
    final raw = response['processes'] as List<dynamic>? ?? const [];
    return raw.map((value) {
      final row = value as Map<String, dynamic>;
      return LiveGameProcess(
        pid: (row['pid'] as num).toInt(),
        name: row['name'] as String,
        title: row['title'] as String,
        processStartTicks: (row['processStartTicks'] as num?)?.toInt(),
      );
    }).toList(growable: false);
  }

  static void validateValue(String value, LiveValueFormat format) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty || normalized.length > 45) {
      throw const FormatException('Введи число длиной до 45 символов');
    }
    final fractional = format == LiveValueFormat.float32 ||
        format == LiveValueFormat.float64;
    if (fractional) {
      final parsed = double.tryParse(normalized);
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Нужно конечное дробное число');
      }
      // A nonzero decimal can underflow while parsing to a Dart double.
      final mantissa = normalized.split(RegExp(r'[eE]')).first;
      if (parsed == 0 && RegExp(r'[1-9]').hasMatch(mantissa)) {
        throw const FormatException('Число слишком мало для представления');
      }
      if (format == LiveValueFormat.float32) {
        // Half of the smallest Float32 subnormal rounds to zero.
        if (parsed.abs() > 3.4028235e38 ||
            (parsed != 0 && parsed.abs() < 7.006492321624085e-46)) {
          throw const FormatException('Значение вне диапазона Float32');
        }
      }
    } else {
      final parsed = BigInt.tryParse(normalized);
      if (parsed == null) throw const FormatException('Нужно целое число');
      final bitCount = format.width * 8;
      final lower = -(BigInt.one << (bitCount - 1));
      final upper = (BigInt.one << (bitCount - 1)) - BigInt.one;
      if (parsed < lower || parsed > upper) {
        throw FormatException('Число не помещается в $bitCount бит');
      }
    }
  }

  Future<LiveMemoryScan> scan({
    required int pid,
    required String value,
    required LiveValueFormat format,
    int budgetMiB = 512,
    int maxResults = 3000,
    bool bytewise = false,
  }) async {
    validateValue(value, format);
    if (budgetMiB < 16 || budgetMiB > 2048) {
      throw RangeError('Допустимо 16–2048 МиБ');
    }
    if (maxResults < 1 || maxResults > 5000) {
      throw RangeError('Допустимо 1–5000 совпадений');
    }
    // Unaligned scanning checks each byte offset instead of only every
    // fourth/eighth address. Keep the extra CPU cost bounded.
    if (bytewise && budgetMiB > 512) {
      throw RangeError('Для побайтового поиска максимум 512 МиБ');
    }
    final response = await _request({
      'command': 'scan',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'maxBytes': budgetMiB * 1024 * 1024,
      'maxResults': maxResults,
      'alignment': bytewise ? 1 : format.width,
    });
    return LiveMemoryScan.fromJson(response);
  }

  Future<LiveMemoryScan> refine({
    required int pid,
    required String value,
    required LiveValueFormat format,
    required List<String> addresses,
  }) async {
    validateValue(value, format);
    final response = await _request({
      'command': 'refine',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'addresses': addresses,
    });
    return LiveMemoryScan.fromJson(response);
  }

  /// Read-only snapshot or relative refinement over existing addresses only.
  /// In snapshot mode ("all") readable candidates are kept regardless of
  /// their change and their latest numeric values are returned.
  /// Does not write process memory.
  ///
  /// Relative refinement across already-found addresses only.
  /// Every candidate needs its own previous numeric baseline to avoid
  /// treating unrelated RAM locations as one HP value.
  Future<LiveMemoryScan> compare({
    required int pid,
    required LiveValueFormat format,
    required List<String> addresses,
    required List<String> baselines,
    required LiveChangeMode mode,
  }) async {
    if (addresses.isEmpty || addresses.length > 5000 ||
        addresses.length != baselines.length) {
      throw const FormatException('Нужны 1–5000 адресов со снимками значений');
    }
    for (final value in baselines) {
      validateValue(value, format);
    }
    for (final address in addresses) {
      if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
        throw const FormatException('Некорректный адрес кандидата');
      }
    }
    final response = await _request({
      'command': 'compare',
      'pid': pid,
      'format': format.code,
      'mode': mode.code,
      'addresses': addresses,
      'baselines': baselines,
    });
    final compared = LiveMemoryScan.fromJson(response);
    if (compared.values.length != compared.addresses.length) {
      throw const FormatException('Модуль не вернул значения для адресов');
    }
    return compared;
  }

  Future<void> write({
    required int pid,
    required LiveValueFormat format,
    required String address,
    required String expected,
    required String replacement,
    int? processStartTicks,
  }) async {
    if (processStartTicks == null || processStartTicks <= 0) {
      throw StateError('Обнови список игр: не получено время запуска процесса');
    }
    validateValue(expected, format);
    validateValue(replacement, format);
    if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
      throw const FormatException('Некорректный адрес памяти');
    }
    await _request({
      'command': 'write',
      'pid': pid,
      'processStartTicks': processStartTicks,
      'format': format.code,
      'address': address,
      'expected': expected.replaceAll(',', '.'),
      'replacement': replacement.replaceAll(',', '.'),
    });
  }
}
), '') : '';
    final raw = (negative ? '-' : '') + whole +
        (tail.isEmpty ? '' : '.' + tail);
    WindowsLiveMemoryService.validateValue(raw, format);
    return raw;
  }

  String display(String raw) {
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) return raw;
    final scaled = decimalShift == -2 ? value * 100
        : decimalShift == 2 ? value / 100 : value;
    if (!scaled.isFinite) return raw;
    return double.parse(scaled.toStringAsPrecision(12)).toString() + '%';
  }
}

class LivePercentScanGroup {
  const LivePercentScanGroup(this.encoding, this.raw, this.scan);
  final LivePercentEncoding encoding;
  final String raw;
  final LiveMemoryScan scan;
}

enum LiveChangeMode {
  snapshot('all', 'Обновить показания'),
  changed('changed', 'Изменилось'),
  unchanged('unchanged', 'Не изменилось'),
  increased('increased', 'Увеличилось'),
  decreased('decreased', 'Уменьшилось');

  const LiveChangeMode(this.code, this.label);
  final String code;
  final String label;
}

class LiveGameProcess {
  const LiveGameProcess({required this.pid, required this.name, required this.title, this.processStartTicks});
  final int pid;
  final String name;
  final String title;
  /// UTC creation ticks; prevents writes after Windows reuses a PID.
  final int? processStartTicks;

  /// A PID can be recycled. Only preserve a UI selection when both
  /// observations have the same non-null Windows creation timestamp.
  bool isSameInstanceAs(LiveGameProcess other) =>
      pid == other.pid &&
      processStartTicks != null &&
      processStartTicks == other.processStartTicks;
}

class LiveMemoryScan {
  const LiveMemoryScan({
    required this.addresses,
    required this.scannedBytes,
    required this.truncated,
    required this.regions,
    this.values = const [],
    this.invalidated = 0,
  });
  final List<String> addresses;
  /// Snapshot of the current value for each address returned by relative scan.
  final List<String> values;
  /// Candidates skipped because their memory is no longer readable.
  final int invalidated;
  final int scannedBytes;
  final bool truncated;
  final int regions;

  static LiveMemoryScan fromJson(Map<String, dynamic> json) {
    final addresses = (json['addresses'] as List<dynamic>?) ?? const [];
    if (addresses.length > 5000 ||
        addresses.any((value) => value is! String ||
            !RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(value))) {
      throw const FormatException('Некорректные адреса в результате');
    }
    final values = (json['values'] as List<dynamic>?) ?? const [];
    if (values.isNotEmpty &&
        (values.length != addresses.length ||
         values.any((item) => item is! String ||
           !RegExp(r'^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?$')
             .hasMatch(item)))) {
      throw const FormatException('Некорректный список числовых снимков');
    }
    // A helper response is untrusted input. Do not silently truncate
    // fractional counters or accept negative/boolean-like metadata.
    int nonNegativeCount(String key) {
      final value = json[key];
      if (value == null) return 0; // Older helpers omitted these counters.
      if (value is! int || value < 0) {
        throw FormatException('Некорректное поле $key в результате');
      }
      return value;
    }

    final truncated = json['truncated'];
    if (truncated != null && truncated is! bool) {
      throw const FormatException('Некорректный признак усечения результата');
    }
    return LiveMemoryScan(
      addresses: List<String>.unmodifiable(addresses.cast<String>()),
      values: List<String>.unmodifiable(values.cast<String>()),
      invalidated: nonNegativeCount('invalidated'),
      scannedBytes: nonNegativeCount('scannedBytes'),
      truncated: truncated == true,
      regions: nonNegativeCount('regions'),
    );
  }
}

/// Only launches a local bundled helper with user-selected PID, requires OS
/// permissions, never attempts privilege escalation, injection or bypass.
class WindowsLiveMemoryService {
  Process? _active;

  String get helperPath => p.join(
        File(Platform.resolvedExecutable).parent.path, 'EHTID-MemoryHelper.exe');

  bool get isSupported => Platform.isWindows;

  void cancel() {
    _active?.kill();
    _active = null;
  }

  Future<Map<String, dynamic>> _request(
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Редактор памяти работает только в Windows');
    }
    if (!await File(helperPath).exists()) {
      throw StateError('EHTID-MemoryHelper.exe не найден рядом с game_lab.exe. '
          'Распакуй весь ZIP, не запускай отдельный EXE из архива.');
    }
    if (_active != null) throw StateError('Другая операция ещё выполняется');
    final process = await Process.start(helperPath, const []);
    _active = process;
    final outputFuture = process.stdout.transform(utf8.decoder).join();
    final errorFuture = process.stderr.transform(utf8.decoder).join();
    try {
      process.stdin.write(jsonEncode(body));
      await process.stdin.close();
      final code = await process.exitCode.timeout(timeout);
      final output = await outputFuture;
      final error = await errorFuture;
      if (output.trim().isEmpty) {
        throw StateError('Нет ответа от модуля памяти. $error (код $code)');
      }
      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ответ модуля памяти повреждён');
      }
      if (decoded['ok'] != true) {
        throw StateError((decoded['error'] ?? error).toString());
      }
      if (code != 0) throw StateError('Модуль памяти завершился с кодом $code');
      return decoded;
    } on TimeoutException {
      process.kill();
      throw StateError('Сканирование превысило 120 секунд и было остановлено');
    } finally {
      if (identical(process, _active)) _active = null;
    }
  }

  Future<List<LiveGameProcess>> processes() async {
    final response = await _request({'command': 'list'});
    final raw = response['processes'] as List<dynamic>? ?? const [];
    return raw.map((value) {
      final row = value as Map<String, dynamic>;
      return LiveGameProcess(
        pid: (row['pid'] as num).toInt(),
        name: row['name'] as String,
        title: row['title'] as String,
        processStartTicks: (row['processStartTicks'] as num?)?.toInt(),
      );
    }).toList(growable: false);
  }

  static void validateValue(String value, LiveValueFormat format) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty || normalized.length > 45) {
      throw const FormatException('Введи число длиной до 45 символов');
    }
    final fractional = format == LiveValueFormat.float32 ||
        format == LiveValueFormat.float64;
    if (fractional) {
      final parsed = double.tryParse(normalized);
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Нужно конечное дробное число');
      }
      // A nonzero decimal can underflow while parsing to a Dart double.
      final mantissa = normalized.split(RegExp(r'[eE]')).first;
      if (parsed == 0 && RegExp(r'[1-9]').hasMatch(mantissa)) {
        throw const FormatException('Число слишком мало для представления');
      }
      if (format == LiveValueFormat.float32) {
        // Half of the smallest Float32 subnormal rounds to zero.
        if (parsed.abs() > 3.4028235e38 ||
            (parsed != 0 && parsed.abs() < 7.006492321624085e-46)) {
          throw const FormatException('Значение вне диапазона Float32');
        }
      }
    } else {
      final parsed = BigInt.tryParse(normalized);
      if (parsed == null) throw const FormatException('Нужно целое число');
      final bitCount = format.width * 8;
      final lower = -(BigInt.one << (bitCount - 1));
      final upper = (BigInt.one << (bitCount - 1)) - BigInt.one;
      if (parsed < lower || parsed > upper) {
        throw FormatException('Число не помещается в $bitCount бит');
      }
    }
  }

  Future<LiveMemoryScan> scan({
    required int pid,
    required String value,
    required LiveValueFormat format,
    int budgetMiB = 512,
    int maxResults = 3000,
    bool bytewise = false,
  }) async {
    validateValue(value, format);
    if (budgetMiB < 16 || budgetMiB > 2048) {
      throw RangeError('Допустимо 16–2048 МиБ');
    }
    if (maxResults < 1 || maxResults > 5000) {
      throw RangeError('Допустимо 1–5000 совпадений');
    }
    // Unaligned scanning checks each byte offset instead of only every
    // fourth/eighth address. Keep the extra CPU cost bounded.
    if (bytewise && budgetMiB > 512) {
      throw RangeError('Для побайтового поиска максимум 512 МиБ');
    }
    final response = await _request({
      'command': 'scan',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'maxBytes': budgetMiB * 1024 * 1024,
      'maxResults': maxResults,
      'alignment': bytewise ? 1 : format.width,
    });
    return LiveMemoryScan.fromJson(response);
  }

  Future<LiveMemoryScan> refine({
    required int pid,
    required String value,
    required LiveValueFormat format,
    required List<String> addresses,
  }) async {
    validateValue(value, format);
    final response = await _request({
      'command': 'refine',
      'pid': pid,
      'format': format.code,
      'value': value.replaceAll(',', '.'),
      'addresses': addresses,
    });
    return LiveMemoryScan.fromJson(response);
  }

  /// Read-only snapshot or relative refinement over existing addresses only.
  /// In snapshot mode ("all") readable candidates are kept regardless of
  /// their change and their latest numeric values are returned.
  /// Does not write process memory.
  ///
  /// Relative refinement across already-found addresses only.
  /// Every candidate needs its own previous numeric baseline to avoid
  /// treating unrelated RAM locations as one HP value.
  Future<LiveMemoryScan> compare({
    required int pid,
    required LiveValueFormat format,
    required List<String> addresses,
    required List<String> baselines,
    required LiveChangeMode mode,
  }) async {
    if (addresses.isEmpty || addresses.length > 5000 ||
        addresses.length != baselines.length) {
      throw const FormatException('Нужны 1–5000 адресов со снимками значений');
    }
    for (final value in baselines) {
      validateValue(value, format);
    }
    for (final address in addresses) {
      if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
        throw const FormatException('Некорректный адрес кандидата');
      }
    }
    final response = await _request({
      'command': 'compare',
      'pid': pid,
      'format': format.code,
      'mode': mode.code,
      'addresses': addresses,
      'baselines': baselines,
    });
    final compared = LiveMemoryScan.fromJson(response);
    if (compared.values.length != compared.addresses.length) {
      throw const FormatException('Модуль не вернул значения для адресов');
    }
    return compared;
  }

  Future<void> write({
    required int pid,
    required LiveValueFormat format,
    required String address,
    required String expected,
    required String replacement,
    int? processStartTicks,
  }) async {
    if (processStartTicks == null || processStartTicks <= 0) {
      throw StateError('Обнови список игр: не получено время запуска процесса');
    }
    validateValue(expected, format);
    validateValue(replacement, format);
    if (!RegExp(r'^0x[0-9a-fA-F]{5,16}$').hasMatch(address)) {
      throw const FormatException('Некорректный адрес памяти');
    }
    await _request({
      'command': 'write',
      'pid': pid,
      'processStartTicks': processStartTicks,
      'format': format.code,
      'address': address,
      'expected': expected.replaceAll(',', '.'),
      'replacement': replacement.replaceAll(',', '.'),
    });
  }
}
