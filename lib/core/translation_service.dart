import 'dart:convert';
import 'dart:io';

/// Only translates VALUES in a valid JSON locale dictionary, never its keys.
/// Skips paths, identifiers and printf/format tokens that the game may require.
class LocaleTranslator {
  LocaleTranslator({this.endpoint, required this.target,
    this.apiKey = '', this.maxStrings = 100, this.translateText});

  /// Optional on-device translation function. When supplied, source text is
  /// never sent to an external translation HTTP endpoint.
  final Future<String> Function(String maskedText)? translateText;
  final Uri? endpoint;
  final String target;
  final String apiKey;
  final int maxStrings;
  int translated = 0;

  Future<String> translateJson(String source) async {
    final json = jsonDecode(source);
    if (json is! Map && json is! List) {
      throw const FormatException('Нужен JSON-объект или массив');
    }
    translated = 0;
    final output = await _walk(json);
    return const JsonEncoder.withIndent('  ').convert(output);
  }

  /// Translates only VALUES in UTF-8 .lang / .properties dictionaries.
  /// Never rebuilds the entire document: comments, keys, separators, blank
  /// lines, CRLF/LF, and unsupported escape sequences remain byte-for-byte.
  Future<String> translateKeyValue(String source) async {
    if (source.length > 1024 * 1024) {
      throw const FormatException('Локализация больше 1 МиБ');
    }
    translated = 0;
    final output = StringBuffer();
    var cursor = 0;
    var continuation = false;
    final definition = RegExp(
        r'^([ \t]*[A-Za-z0-9_.-]+[ \t]*[=:][ \t]*)(.*)$');
    final forbiddenKey = RegExp(
        r'(^|[_.-])(id|path|url|file|asset|sprite|icon|key|'
        r'hash|checksum|server|port|version|enabled|debug)([_.-]|$)',
        caseSensitive: false);
    final numericOrFlag = RegExp(
        r'^(true|false|yes|no|null|on|off|[+-]?[0-9]+(\.[0-9]+)?)$',
        caseSensitive: false);

    Future<void> processLine(String line, String ending) async {
      var count = 0;
      for (var i = line.length - 1; i >= 0 && line.codeUnitAt(i) == 0x5c; i--) {
        count++;
      }
      final nextContinuation = count.isOdd;
      final skip = continuation || nextContinuation ||
          translated >= maxStrings;
      continuation = nextContinuation;
      if (skip) {
        output.write(line);
        output.write(ending);
        return;
      }
      final bom = line.startsWith('\uFEFF') ? '\uFEFF' : '';
      final text = bom.isEmpty ? line : line.substring(1);
      final match = definition.firstMatch(text);
      if (match == null) {
        output.write(line);
        output.write(ending);
        return;
      }
      final prefix = match.group(1)!;
      final value = match.group(2)!;
      final key = prefix.split(RegExp(r'[=:]')).first.trim();
      if (value.trim().isEmpty) {
        output.write(line);
        output.write(ending);
        return;
      }
      final leading = RegExp(r'^[ \t]*').firstMatch(value)!.group(0)!;
      final trailing = RegExp(r'[ \t]*$').firstMatch(value)!.group(0)!;
      final originalValue = value.substring(
          leading.length, value.length - trailing.length);
      // Escapes other than \n/\r/\t may carry semantic data. Never
      // normalize or translate them without format-aware parsing.
      final unsafeEscape = RegExp(r'\\(?![nrt])').hasMatch(originalValue);
      final inlineComment = RegExp(r'(^|[ \t])[#;]')
          .hasMatch(originalValue);
      if (forbiddenKey.hasMatch(key) ||
          numericOrFlag.hasMatch(originalValue) ||
          unsafeEscape || inlineComment ||
          !_isNaturalText(originalValue)) {
        output.write(line);
        output.write(ending);
        return;
      }

      final replacement = await _translatePreservingTokens(originalValue);
      if (replacement.contains('\n') || replacement.contains('\r') ||
          replacement.isEmpty) {
        throw const FormatException(
          'Переводчик изменил структуру строки — запись отменена');
      }
      output.write(bom);
      output.write(prefix);
      output.write(leading);
      output.write(replacement);
      output.write(trailing);
      output.write(ending);
      translated++;
    }

    for (final ending in RegExp(r'\r\n|\n|\r').allMatches(source)) {
      await processLine(source.substring(cursor, ending.start),
          ending.group(0)!);
      cursor = ending.end;
    }
    if (cursor < source.length) {
      await processLine(source.substring(cursor), '');
    }
    return output.toString();
  }

  Future<dynamic> _walk(dynamic value) async {
    if (value is Map) {
      final output = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final lower = key.toLowerCase();
        if (RegExp(r'(^id$|_id$|path|asset|url|file|icon|sprite|key$)')
            .hasMatch(lower)) {
          output[key] = entry.value;
        } else {
          output[key] = await _walk(entry.value);
        }
      }
      return output;
    }
    if (value is List) {
      final result = <dynamic>[];
      for (final child in value) {
        result.add(await _walk(child));
      }
      return result;
    }
    if (value is! String || translated >= maxStrings || !_isNaturalText(value)) {
      return value;
    }
    final result = await _translatePreservingTokens(value);
    translated++;
    return result;
  }

  bool _isNaturalText(String input) {
    if (input.trim().length < 2) return false;
    // English, Cyrillic, Japanese Kana/Kanji, Chinese Han and Korean Hangul.
    if (!RegExp(r'[A-Za-zА-Яа-яЁёぁ-ヿ㐀-鿿가-힣]')
        .hasMatch(input)) return false;
    // A second pass should continue after already translated RU values,
    // rather than repeatedly re-sending the first 100 entries.
    if (target == 'ru' &&
        RegExp(r'[А-Яа-яЁё]').hasMatch(input) &&
        !RegExp(r'[A-Za-zぁ-ヿ㐀-鿿가-힣]')
            .hasMatch(input)) return false;
    if (RegExp(r'^(https?://|res://|[\\/]|#[0-9a-fA-F]{6,8}$)').hasMatch(input)) {
      return false;
    }
    // Game localization often contains single words like 'Start' or 'Save'.
    // Only skip strings shaped like asset paths or technical identifiers.
    if (RegExp(r'^[A-Za-z0-9_./\\:-]+$').hasMatch(input) &&
        RegExp(r'[_.:/\\0-9]').hasMatch(input)) return false;
    return true;
  }

  Future<String> _translatePreservingTokens(String source) async {
    final tokens = <String>[];
    final masked = source.replaceAllMapped(
        RegExp(r'\{[^{}]+\}|%[0-9$+.-]*[a-zA-Z]|<[^<>]+>|\\n|\\t|\\r|§[0-9a-fk-or]|&[0-9a-fk-or]', caseSensitive: false),
        (match) {
      final index = tokens.length;
      tokens.add(match.group(0)!);
      // Keep the source's own whitespace. Artificial spaces around
      // protected tokens would leak into game text after restoration.
      return 'EHTIDTOKEN${index}KEEP';
    });
    var translatedText = await _send(masked);
    for (var i = 0; i < tokens.length; i++) {
      final placeholder = RegExp('EHTID\\s*TOKEN\\s*$i\\s*KEEP',
          caseSensitive: false);
      if (!placeholder.hasMatch(translatedText)) {
        throw StateError('Переводчик сломал плейсхолдер — запись отменена');
      }
      translatedText = translatedText.replaceAll(placeholder, tokens[i]);
    }
    return translatedText.trim();
  }

  Future<String> _send(String source) async {
    if (translateText != null) return translateText!(source);
    final endpoint = this.endpoint;
    if (endpoint == null) {
      throw StateError('Нужен сервер перевода или локальный движок');
    }
    if (endpoint.scheme != 'https' && endpoint.host != 'localhost' &&
        endpoint.host != '127.0.0.1') {
      throw StateError('Используй HTTPS или локальный переводчик');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(endpoint)
          .timeout(const Duration(seconds: 15));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'q': source,
        'source': 'auto',
        'target': target,
        'format': 'text',
        if (apiKey.isNotEmpty) 'api_key': apiKey,
      })));
      final response = await request.close().timeout(const Duration(seconds: 25));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException('Переводчик: HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      final translatedText = decoded is Map ? decoded['translatedText'] : null;
      if (translatedText is! String) {
        throw const FormatException('Неверный ответ переводчика');
      }
      return translatedText;
    } finally {
      client.close(force: true);
    }
  }
}
