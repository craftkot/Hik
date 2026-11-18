import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android-only experimental container. Standalone APKs are NOT virtualized.
/// HTML5 ZIP games run locally in EHTID's private WebView with persisted data.
class AndroidContainerLab extends StatefulWidget {
  const AndroidContainerLab({super.key});

  @override
  State<AndroidContainerLab> createState() => _AndroidContainerLabState();
}

class _AndroidContainerLabState extends State<AndroidContainerLab>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('ehtid.gamelab/container');
  static const _progressChannel = MethodChannel(
      'ehtid.gamelab/container_progress');
  List<Map<String, String>> _games = [];
  bool _busy = false;
  bool _importing = false;
  int _copiedBytes = 0;
  int? _totalBytes;
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressChannel.setMethodCallHandler((call) async {
      if (call.method != 'importProgress' || !mounted) return;
      final data = Map<Object?, Object?>.from(call.arguments as Map);
      final copied = (data['copiedBytes'] as num?)?.toInt();
      final total = (data['totalBytes'] as num?)?.toInt();
      if (copied == null || copied < 0) return;
      setState(() {
        _copiedBytes = copied;
        _totalBytes = total != null && total > 0 ? total : null;
      });
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final rows = await _channel.invokeListMethod<dynamic>('list');
      if (!mounted) return;
      setState(() {
        _games = (rows ?? []).map((item) {
          final map = Map<Object?, Object?>.from(item as Map);
          return map.map((key, value) =>
              MapEntry(key.toString(), value?.toString() ?? ''));
        }).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка списка: $error');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
  }

  Future<void> _call(String action, {String? id}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      if (action == 'import') {
        _importing = true;
        _copiedBytes = 0;
        _totalBytes = null;
        _status = 'Выбери APK или ZIP. Большой файл будет скопирован '
            'по частям, без загрузки целиком в память.';
      }
    });
    try {
      final result = await _channel.invokeMethod<dynamic>(
          action, id == null ? null : {'id': id});
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      switch (action) {
        case 'createDemo':
          _notify('Тестовая HTML5-игра создана внутри EHTID');
        case 'import':
          _notify(result == null
              ? 'Импорт отменён'
              : 'Игра скопирована в приватное хранилище EHTID');
        case 'install':
          _notify(result == 'permission_required'
              ? 'Разреши установку из EHTID в системных настройках, затем '
                  'снова нажми «Установить»'
              : 'Открыт системный установщик Android. Игра установится '
                  'отдельно от EHTID, её сейвы останутся защищены.');
        case 'launchExternal':
          _notify(result == 'not_installed_or_invisible'
              ? 'Игра не установлена или Android не разрешает её запуск '
                  'из EHTID. Попробуй значок игры в лаунчере.'
              : 'Открываем установленную игру вне контейнера');
        case 'run':
          _notify('HTML5-игра работает внутри EHTID');
        default:
          break;
      }
    } on PlatformException catch (error) {
      _notify('Ошибка: ${error.message ?? error.code}');
    } catch (error) {
      _notify('Ошибка: $error');
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _importing = false;
      });
    }
  }

  Future<void> _remove(Map<String, String> game) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить из контейнера?'),
        content: Text('Удалить локальную копию «${game['name']}» из EHTID? '
            'Для HTML5-игры это удалит файлы. '
            'Установленный Android APK автоматически не удаляется.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить копию')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _call('remove', id: game['id']);
    if (mounted) _notify('Копия игры удалена из хранилища EHTID');
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГиБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МиБ';
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      const Text('EHTID Container Lab · Android',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      const Text('Эксперимент: запускаем HTML5-игры из приватной папки EHTID. '
          'APK сохраняем внутри EHTID, но устанавливаем обычным способом '
          'через Android. Установленный APK НЕ запускается в виртуальной '
          'песочнице и НЕ отдаёт свои приватные сейвы EHTID.',
        style: TextStyle(fontSize: 12, color: Color(0xFFBBB2D2))),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _busy ? null : () => _call('createDemo'),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Создать тестовую игру'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _call('import'),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Импорт ZIP / APK'),
        ),
        IconButton(
          tooltip: 'Обновить список игр',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      const SizedBox(height: 7),
      const Text('HTML5: ZIP до 200 МиБ и 50 МиБ распаковки. '
          'APK: до 8 ГиБ, потоковое копирование, требуется свободное '
          'место для отдельной копии. XAPK/APKS и split-пакеты пока '
          'не поддерживаются.',
        style: TextStyle(color: Color(0xFFAAA5BE), fontSize: 11)),
      if (_busy) Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(
            value: _importing && _totalBytes != null
                ? (_copiedBytes / _totalBytes!).clamp(0.0, 1.0) : null,
          ),
          if (_importing) ...[
            const SizedBox(height: 5),
            Text(_totalBytes == null
                ? 'Импорт: ${_formatBytes(_copiedBytes)} (размер неизвестен)'
                : 'Скопировано ${_formatBytes(_copiedBytes)} '
                    'из ${_formatBytes(_totalBytes!)} '
                    '(${(_copiedBytes / _totalBytes! * 100).clamp(0, 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 11,
                color: Color(0xFF5EE9F5))),
          ],
        ]),
      ),
      if (_status.isNotEmpty) Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_status, style: const TextStyle(
          color: Color(0xFF5EE9F5), fontSize: 12)),
      ),
      const SizedBox(height: 13),
      if (_games.isEmpty)
        const Card(child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Контейнер пуст. Для первого теста создай '
              'игру «монеты», накопи счёт, закрой и запусти повторно.'),
        )),
      for (final game in _games)
        Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(game['kind'] == 'web'
                      ? Icons.language : Icons.android,
                    color: const Color(0xFFB68BFF)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(game['name'] ?? 'Игра',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                  IconButton(
                    onPressed: _busy ? null : () => _remove(game),
                    tooltip: 'Удалить копию из EHTID',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
                Text(game['kind'] == 'web'
                    ? 'HTML5 · работает внутри EHTID · локальный прогресс'
                    : 'APK · только копия внутри EHTID · запускается '
                        'через системную установку',
                  style: const TextStyle(fontSize: 11,
                    color: Color(0xFFAAA5BE))),
                if (game['kind'] == 'apk')
                  Text(game['package'] ?? '', style: const TextStyle(
                    fontSize: 10, color: Color(0xFFAAA5BE))),
                const SizedBox(height: 10),
                if (game['kind'] == 'web')
                  FilledButton.icon(
                    onPressed: _busy ? null :
                        () => _call('run', id: game['id']),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Запустить внутри EHTID'),
                  )
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      onPressed: _busy ? null :
                          () => _call('install', id: game['id']),
                      icon: const Icon(Icons.install_mobile_outlined),
                      label: const Text('Установить через Android'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null :
                          () => _call('launchExternal', id: game['id']),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Запустить отдельно'),
                    ),
                  ]),
              ]),
          ),
        ),
    ],
  );
}
