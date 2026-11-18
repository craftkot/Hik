import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../core/windows_live_memory.dart';
import 'onscreen_number_picker.dart';

const _purple = Color(0xFFB68BFF);
const _cyan = Color(0xFF5EE9F5);
const _muted = Color(0xFFA7A1BF);

class LiveMemoryPanel extends StatefulWidget {
  const LiveMemoryPanel({super.key, this.service});
  final WindowsLiveMemoryService? service;
  @override
  State<LiveMemoryPanel> createState() => _LiveMemoryPanelState();
}

class _LiveMemoryPanelState extends State<LiveMemoryPanel> {
  late final WindowsLiveMemoryService _service =
      widget.service ?? WindowsLiveMemoryService();
  final _value = TextEditingController();
  final _replacement = TextEditingController();
  List<LiveGameProcess> _processes = const [];
  LiveGameProcess? _selected;
  LiveValueFormat _format = LiveValueFormat.int32;
  LiveMemoryScan? _result;
  _LastPatch? _lastPatch;
  /// Independent last-observed number for each candidate address.
  Map<String, String> _snapshots = const {};
  // Read-only watchlist: up to 12 addresses already identified by the
  // normal scan. Never search for new addresses or write automatically.
  final Set<String> _watched = <String>{};
  final Map<String, String> _watchValues = <String, String>{};
  Timer? _watchTimer;
  bool _watchActive = false;
  bool _watchReading = false;
  String _watchStatus = '';
  LiveChangeMode _changeMode = LiveChangeMode.changed;
  int _budgetMiB = 512;
  bool _bytewiseScan = false;
  bool _busy = false;
  String _status = 'Выбери окно своей одиночной игры и введи число HP, маны или денег.';

  @override
  void dispose() {
    _watchTimer?.cancel();
    _service.cancel();
    _value.dispose();
    _replacement.dispose();
    super.dispose();
  }

  void _clearWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
    _watchActive = false;
    _watchReading = false;
    _watched.clear();
    _watchValues.clear();
    _watchStatus = '';
  }

  void _toggleWatchedAddress(String address) {
    if (_busy) return;
    setState(() {
      if (_watched.remove(address)) {
        _watchValues.remove(address);
        if (_watched.isEmpty) {
          _watchTimer?.cancel();
          _watchTimer = null;
          _watchActive = false;
          _watchStatus = 'Список наблюдения пуст';
        }
      } else {
        if (_watched.length >= 12) {
          _watchStatus = 'Можно отслеживать не более 12 адресов';
          return;
        }
        final baseline = _snapshots[address];
        if (baseline == null) {
          _watchStatus = 'Значение адреса неизвестно. Обнови показания.';
          return;
        }
        _watched.add(address);
        _watchValues[address] = baseline;
        _watchStatus = 'Добавлен адрес $address. Включи автообновление.';
      }
    });
  }

  void _toggleWatchUpdates() {
    if (_busy || _watched.isEmpty || _selected == null) return;
    setState(() {
      _watchTimer?.cancel();
      _watchTimer = null;
      _watchActive = !_watchActive;
      if (_watchActive) {
        _watchStatus = 'Чтение закреплённых адресов раз в 2 секунды';
        _watchTimer = Timer.periodic(
          const Duration(seconds: 2), (_) => _readWatched());
      } else {
        _watchStatus = 'Наблюдение приостановлено';
      }
    });
  }

  Future<void> _readWatched() async {
    final game = _selected;
    if (!_watchActive || _busy || game == null || _watched.isEmpty) return;
    final addresses = _watched.toList(growable: false);
    final format = _format;
    final baselines = <String>[];
    for (final address in addresses) {
      final current = _watchValues[address] ?? _snapshots[address];
      if (current == null) {
        setState(() {
          _watchActive = false;
          _watchTimer?.cancel();
          _watchTimer = null;
          _watchStatus = 'Нет исходного числа для $address. Начни новый поиск.';
        });
        return;
      }
      baselines.add(current);
    }

    setState(() {
      _busy = true;
      _watchReading = true;
    });
    try {
      final result = await _service.compare(
        pid: game.pid, format: format,
        addresses: addresses, baselines: baselines,
        mode: LiveChangeMode.snapshot,
      );
      if (!mounted || !_watchActive || _selected?.pid != game.pid ||
          _format != format) return;
      final fresh = <String, String>{
        for (var i = 0; i < result.addresses.length; i++)
          result.addresses[i]: result.values[i],
      };
      setState(() {
        // Don't overwrite comparison baselines used by "Increased/Changed"
        // filters. Watch values are a separate, read-only stream.
        for (final address in addresses) {
          if (fresh.containsKey(address)) {
            _watchValues[address] = fresh[address]!;
          } else {
            _watchValues.remove(address);
          }
        }
        _watchStatus = fresh.isEmpty
            ? 'Адреса больше недоступны. Наблюдение остановлено.'
            : 'Обновлено: ${fresh.length} из ${addresses.length}. '
                'Только чтение, память не изменялась.';
        if (fresh.isEmpty) {
          _watchActive = false;
          _watchTimer?.cancel();
          _watchTimer = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _watchActive = false;
        _watchTimer?.cancel();
        _watchTimer = null;
        _watchStatus = 'Наблюдение остановлено: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _watchReading = false;
        });
      }
    }
  }

  void _notice(Object error) {
    if (!mounted) return;
    setState(() => _status = error.toString());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString()), duration: const Duration(seconds: 4)));
  }

  Future<void> _refreshProcesses() async {
    if (_busy) return;
    setState(() { _busy = true; _status = 'Поиск видимых окон Windows…'; });
    try {
      final found = await _service.processes();
      if (!mounted) return;
      setState(() {
        _processes = found;
        _selected = found.where((p) => p.pid == _selected?.pid).firstOrNull;
        _result = null; _lastPatch = null;
        _snapshots = const {};
        _clearWatch();
        _status = found.isEmpty ? 'Нет видимых окон. Сначала открой одиночную игру.'
            : 'Найдено ${found.length} окон. Выбери игровой процесс.';
      });
    } catch (error) { _notice(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openFloatingOverlay() async {
    if (_busy || !Platform.isWindows) return;
    final executable = File(Platform.resolvedExecutable);
    final path = '${executable.parent.path}${Platform.pathSeparator}'
        'EHTID-Overlay.exe';
    if (!await File(path).exists()) {
      _notice('В архиве нет EHTID-Overlay.exe. Распакуй весь ZIP целиком.');
      return;
    }
    try {
      await Process.start(path, const [], mode: ProcessStartMode.detached);
      if (mounted) setState(() => _status =
          'Плавающая панель запущена. Перейди в оконную/безрамочную игру. '
          'Для эксклюзивного fullscreen оверлей может быть не виден.');
    } catch (error) {
      _notice('Не удалось запустить оверлей: $error');
    }
  }

  Future<void> _getFromScreenshot() async {
    final number = await showDialog<String>(context: context,
        builder: (_) => const OnScreenNumberPicker());
    if (!mounted || number == null) return;
    setState(() {
      _value.text = number;
      _result = null; _lastPatch = null;
        _snapshots = const {};
      _status = 'OCR: ${number}. Теперь выбери игру и запусти поиск. '
          'Скриншот не раскрывает адрес памяти сам по себе.';
    });
  }

  Future<void> _search(bool refine) async {
    if (_busy) return;
    final game = _selected;
    if (game == null) { _notice('Сначала выбери процесс игры'); return; }
    final number = _value.text.trim();
    try { WindowsLiveMemoryService.validateValue(number, _format); }
    catch (error) { _notice(error); return; }
    if (refine && (_result == null || _result!.addresses.isEmpty)) {
      _notice('Для уточнения сначала нужен первичный поиск');
      return;
    }
    setState(() { _busy = true; _status = refine
        ? 'Проверяю кандидатов после изменения числа в игре…'
        : 'Читаю доступные области памяти. Защиты процессов не обхожу…'; });
    try {
      final previous = _result;
      final result = refine
          ? await _service.refine(pid: game.pid, format: _format,
              value: number, addresses: previous!.addresses)
          : await _service.scan(pid: game.pid, format: _format,
              value: number, budgetMiB: _budgetMiB,
              bytewise: _bytewiseScan);
      if (!mounted || game.pid != _selected?.pid) return;
      setState(() {
        _result = result; _lastPatch = null;
        _snapshots = {for (final address in result.addresses) address: number};
        _status = result.addresses.isEmpty
            ? 'Совпадений нет. Попробуй другой формат или '
              'побайтовый поиск.'
            : 'Кандидатов: ${result.addresses.length}. '
              '${_bytewiseScan ? 'Режим: побайтовый. ' : ''}'
              '${result.truncated ? 'Достигнут лимит результатов. ' : ''}'
              'Измени число в игре, введи новое и нажми «Уточнить».';
      });
    } catch (error) { _notice(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _compare({LiveChangeMode? mode}) async {
    final game = _selected;
    final candidates = _result?.addresses ?? const <String>[];
    if (_busy || game == null || candidates.isEmpty) return;
    final currentMode = mode ?? _changeMode;
    final baselines = <String>[];
    for (final address in candidates) {
      final baseline = _snapshots[address];
      if (baseline == null) {
        _notice('Исходное значение неизвестно. Выполни новый поиск.');
        return;
      }
      baselines.add(baseline);
    }
    setState(() {
      _busy = true;
      _status = currentMode == LiveChangeMode.snapshot
          ? 'Читаю актуальные значения ${candidates.length} адресов…'
          : 'Проверяю изменения по ${candidates.length} адресам…';
    });
    try {
      final result = await _service.compare(
        pid: game.pid, format: _format,
        addresses: candidates, baselines: baselines, mode: currentMode,
      );
      if (!mounted || _selected?.pid != game.pid) return;
      setState(() {
        _result = result;
        _snapshots = {
          for (var i = 0; i < result.addresses.length; i++)
            result.addresses[i]: result.values[i],
        };
        _lastPatch = null;
        _status = currentMode == LiveChangeMode.snapshot
            ? 'Показания обновлены: ${result.addresses.length} адресов. '
              'Недоступных или нечисловых: '
              '${candidates.length - result.addresses.length}. '
              'Память игры не изменялась.'
            : 'Фильтр «${currentMode.label}»: осталось '
              '${result.addresses.length} адресов. '
              'После нового изменения в игре можно сравнить ещё раз.';
      });
    } catch (error) { _notice(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(String address) async {
    final game = _selected;
    final expected = _watchValues[address] ?? _snapshots[address];
    if (_busy || game == null || expected == null) return;
    if (_watchActive) {
      setState(() {
        _watchActive = false;
        _watchTimer?.cancel();
        _watchTimer = null;
        _watchStatus = 'Наблюдение приостановлено перед ручной записью';
      });
    }
    _replacement.clear();
    final newValue = await showDialog<String>(context: context,
      builder: (context) {
        var accepted = false;
        return StatefulBuilder(builder: (context, update) => AlertDialog(
          title: const Text('Изменение памяти игры'),
          content: SizedBox(width: 440, child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${game.name} · PID ${game.pid}',
                style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 8),
              SelectableText('${address} · ${_format.label}',
                style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text('Сейчас ожидаем: ${expected}'),
              const SizedBox(height: 14),
              TextField(controller: _replacement, autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'Новое значение')),
              const SizedBox(height: 8),
              CheckboxListTile(contentPadding: EdgeInsets.zero,
                title: const Text('Это моя одиночная игра. '
                  'Понимаю, что неверный адрес может вызвать вылет.',
                  style: TextStyle(fontSize: 12)),
                controlAffinity: ListTileControlAffinity.leading,
                value: accepted,
                onChanged: (value) => update(() => accepted = value ?? false)),
              const Text('Запись только по одному адресу, после проверки исходных байт.',
                style: TextStyle(fontSize: 11, color: _muted)),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
            FilledButton(
              onPressed: accepted ? () => Navigator.pop(context, _replacement.text) : null,
              child: const Text('Проверить и записать')),
          ],
        ));
      });
    if (!mounted || newValue == null) return;
    try { WindowsLiveMemoryService.validateValue(newValue, _format); }
    catch (error) { _notice(error); return; }
    if (expected == newValue) { _notice('Число не изменилось'); return; }
    setState(() { _busy = true; _status = 'Проверяю адрес, записываю и перечитываю…'; });
    try {
      await _service.write(pid: game.pid, format: _format,
          address: address, expected: expected, replacement: newValue);
      if (!mounted) return;
      setState(() {
        _lastPatch = _LastPatch(game.pid, address, _format, expected, newValue);
        _result = LiveMemoryScan(addresses: [address],
            scannedBytes: 0, truncated: false, regions: 0);
        _value.text = newValue;
        _snapshots = {address: newValue};
        if (_watched.contains(address)) _watchValues[address] = newValue;
        _status = 'Готово: ${expected} → ${newValue} по ${address}. '
          'Откат возможен, пока игра не изменила значение сама.';
      });
    } catch (error) { _notice('Запись отклонена: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _undo() async {
    final item = _lastPatch;
    if (item == null || _busy) return;
    setState(() { _busy = true; _status = 'Проверяю и возвращаю старое число…'; });
    try {
      await _service.write(pid: item.pid, format: item.format,
          address: item.address, expected: item.newValue,
          replacement: item.oldValue);
      if (!mounted) return;
      setState(() {
        _lastPatch = null; _value.text = item.oldValue;
        _snapshots = {item.address: item.oldValue};
        if (_watched.contains(item.address)) {
          _watchValues[item.address] = item.oldValue;
        }
        _status = 'Проверено: исходное значение восстановлено.';
      });
    } catch (error) { _notice('Откат не выполнен: $error'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final hits = _result?.addresses ?? const <String>[];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF211D32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withValues(alpha: .25)),
        boxShadow: [BoxShadow(color: _purple.withValues(alpha: .08),
          blurRadius: 32, offset: const Offset(0, 6))]),
      child: Padding(padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.memory, color: _cyan, size: 27)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Live Memory · Windows',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('Точный поиск, уточнение и запись значений',
                    style: TextStyle(fontSize: 11, color: _muted)),
                ])),
              const Text('ALPHA', style: TextStyle(color: _cyan,
                  letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshProcesses,
                icon: const Icon(Icons.refresh), label: const Text('Найти окна')),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _openFloatingOverlay,
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                label: const Text('Открыть поверх игры')),
              OutlinedButton.icon(
                onPressed: _busy ? null : _getFromScreenshot,
                icon: const Icon(Icons.touch_app_outlined),
                label: const Text('Выбрать число на скриншоте')),
              if (_busy) TextButton.icon(
                onPressed: _service.cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Прервать')),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: ValueKey('game-${_selected?.pid}'),
              initialValue: _selected?.pid, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Процесс игры'),
              items: _processes.map((p) => DropdownMenuItem(
                value: p.pid,
                child: Text('${p.name} · ${p.title} (PID ${p.pid})',
                  maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _busy ? null : (pid) => setState(() {
                _selected = _processes.where((p) => p.pid == pid).firstOrNull;
                _result = null; _lastPatch = null;
        _snapshots = const {};
        _clearWatch();
              }),
            ),
            const SizedBox(height: 10),
            TextField(controller: _value, enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Текущее число из игры, например 120')),
            const SizedBox(height: 10),
            DropdownButtonFormField<LiveValueFormat>(
              initialValue: _format, isExpanded: true,
              decoration: const InputDecoration(labelText: 'Формат числа в памяти'),
              items: LiveValueFormat.values.map((fmt) => DropdownMenuItem(
                value: fmt, child: Text(fmt.label))).toList(),
              onChanged: _busy ? null : (fmt) => setState(() {
                if (fmt != null) _format = fmt;
                _result = null; _lastPatch = null;
        _snapshots = const {};
        _clearWatch();
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Лимит RAM', style: TextStyle(color: _muted, fontSize: 11)),
              Expanded(child: Slider(
                value: _budgetMiB.toDouble(), min: 128,
                max: _bytewiseScan ? 512 : 2048,
                divisions: _bytewiseScan ? 12 : 15,
                label: '$_budgetMiB МиБ',
                onChanged: _busy ? null : (v) =>
                    setState(() => _budgetMiB = v.round()))),
              SizedBox(width: 70, child: Text('$_budgetMiB МиБ',
                style: const TextStyle(fontSize: 11))),
            ]),
            SwitchListTile(
              key: const Key('bytewise-ram-scan-toggle'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Глубокий поиск · каждый байт',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              subtitle: const Text(
                'Проверяет также невыравненные адреса. Медленнее обычного '
                'поиска; максимум 512 МиБ за запуск. Только первый поиск.',
                style: TextStyle(color: _muted, fontSize: 11)),
              value: _bytewiseScan,
              onChanged: _busy ? null : (enabled) => setState(() {
                _bytewiseScan = enabled;
                if (enabled && _budgetMiB > 512) _budgetMiB = 512;
                _result = null;
                _snapshots = const {};
                _lastPatch = null;
                _clearWatch();
                _status = enabled
                    ? 'Глубокий поиск: проверяются все смещения байт. '
                      'Для первого сканирования ограничение 512 МиБ.'
                    : 'Обычный поиск: быстрее, выравнивание по размеру числа.';
              }),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy || _selected == null ? null : () => _search(false),
                icon: const Icon(Icons.manage_search),
                label: const Text('Первый поиск')),
              FilledButton.tonalIcon(
                onPressed: _busy || hits.isEmpty ? null : () => _search(true),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Уточнить')),
              OutlinedButton.icon(
                onPressed: _busy || hits.isEmpty
                    ? null
                    : () => _compare(mode: LiveChangeMode.snapshot),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Обновить показания')),
              if (_lastPatch != null)
                OutlinedButton.icon(onPressed: _busy ? null : _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Откатить запись')),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 9, runSpacing: 9, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 188, child: DropdownButtonFormField<LiveChangeMode>(
                  initialValue: _changeMode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Фильтр изменения', isDense: true),
                  items: LiveChangeMode.values.map((mode) => DropdownMenuItem(
                    value: mode, child: Text(mode.label,
                        style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: _busy ? null : (mode) {
                    if (mode != null) setState(() => _changeMode = mode);
                  },
                )),
                OutlinedButton.icon(
                  onPressed: _busy || hits.isEmpty
                      ? null : () => _compare(),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('Сравнить с прошлым значением')),
              ],
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(
              color: _muted, fontSize: 12, height: 1.45)),
            if (_watched.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF151223),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cyan.withValues(alpha: .2))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('НАБЛЮДЕНИЕ · ${_watched.length}/12',
                          style: const TextStyle(color: _cyan,
                            fontWeight: FontWeight.w700, fontSize: 11)),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _toggleWatchUpdates,
                          icon: Icon(_watchActive ? Icons.pause_circle_outline
                              : Icons.play_circle_outline),
                          label: Text(_watchActive
                              ? 'Остановить чтение' : 'Читать каждые 2 сек'),
                        ),
                      ],
                    ),
                    if (_watchStatus.isNotEmpty)
                      Text(_watchStatus, style: const TextStyle(
                        fontSize: 11, color: _muted)),
                    if (_watchReading) const LinearProgressIndicator(),
                    for (final address in _watched)
                      Padding(padding: const EdgeInsets.only(top: 5),
                        child: Row(children: [
                          const Icon(Icons.visibility_outlined,
                            color: _cyan, size: 17),
                          const SizedBox(width: 7),
                          Expanded(child: Text(address,
                            style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11))),
                          Text(_watchValues[address] ?? 'Недоступен',
                            style: const TextStyle(
                              color: _cyan, fontWeight: FontWeight.w700)),
                          IconButton(
                            tooltip: 'Убрать адрес $address',
                            onPressed: _busy ? null :
                                () => _toggleWatchedAddress(address),
                            icon: const Icon(Icons.close, size: 18)),
                        ])),
                  ],
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text('АДРЕСА-КАНДИДАТЫ · ${hits.length}',
                style: const TextStyle(color: _cyan,
                  fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              Container(height: 190,
                decoration: BoxDecoration(color: const Color(0xFF151223),
                  borderRadius: BorderRadius.circular(11)),
                child: hits.isEmpty
                  ? const Center(child: Text('Значение не найдено'))
                  : ListView.builder(itemCount: hits.length,
                      itemBuilder: (context, i) => Material(
                        color: Colors.transparent,
                        child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.pin_outlined,
                          color: _purple, size: 19),
                        title: Text(hits[i],
                          style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(_snapshots[hits[i]] ?? ''),
                        trailing: IconButton(
                          tooltip: _watched.contains(hits[i])
                              ? 'Убрать из наблюдения'
                              : 'Отслеживать адрес',
                          onPressed: _busy ? null :
                              () => _toggleWatchedAddress(hits[i]),
                          icon: Icon(_watched.contains(hits[i])
                              ? Icons.star : Icons.star_border,
                            color: _cyan)),
                        onTap: _busy ? null : () => _edit(hits[i]))))),
            ],
            const SizedBox(height: 12),
            const Text('Работает лишь с разрешёнными Windows областями памяти. '
              'Нет обхода античита и инъекций. Изменяй только свои офлайн-игры. '
              'Неверное значение может вызвать вылет.',
              style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
          ],
        )),
    );
  }
}

class _LastPatch {
  const _LastPatch(this.pid, this.address, this.format, this.oldValue,
      this.newValue);
  final int pid;
  final String address;
  final LiveValueFormat format;
  final String oldValue;
  final String newValue;
}
