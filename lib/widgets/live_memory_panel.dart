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
  String? _expected;
  int _budgetMiB = 512;
  bool _busy = false;
  String _status = 'Выбери окно своей одиночной игры и введи число HP, маны или денег.';

  @override
  void dispose() {
    _service.cancel();
    _value.dispose();
    _replacement.dispose();
    super.dispose();
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
        _result = null; _expected = null; _lastPatch = null;
        _status = found.isEmpty ? 'Нет видимых окон. Сначала открой одиночную игру.'
            : 'Найдено ${found.length} окон. Выбери игровой процесс.';
      });
    } catch (error) { _notice(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _getFromScreenshot() async {
    final number = await showDialog<String>(context: context,
        builder: (_) => const OnScreenNumberPicker());
    if (!mounted || number == null) return;
    setState(() {
      _value.text = number;
      _result = null; _expected = null; _lastPatch = null;
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
              value: number, budgetMiB: _budgetMiB);
      if (!mounted || game.pid != _selected?.pid) return;
      setState(() {
        _result = result; _expected = number; _lastPatch = null;
        _status = result.addresses.isEmpty
            ? 'Совпадений нет. Попробуй другой числовой тип.'
            : 'Кандидатов: ${result.addresses.length}. '
              '${result.truncated ? 'Достигнут лимит результатов. ' : ''}'
              'Измени число в игре, введи новое и нажми «Уточнить».';
      });
    } catch (error) { _notice(error); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _edit(String address) async {
    final game = _selected;
    final expected = _expected;
    if (_busy || game == null || expected == null) return;
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
        _value.text = newValue; _expected = newValue;
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
        _expected = item.oldValue;
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
                _result = null; _expected = null; _lastPatch = null;
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
                _result = null; _expected = null; _lastPatch = null;
              }),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Лимит RAM', style: TextStyle(color: _muted, fontSize: 11)),
              Expanded(child: Slider(
                value: _budgetMiB.toDouble(), min: 128, max: 2048, divisions: 15,
                label: '$_budgetMiB МиБ',
                onChanged: _busy ? null : (v) =>
                    setState(() => _budgetMiB = v.round()))),
              SizedBox(width: 70, child: Text('$_budgetMiB МиБ',
                style: const TextStyle(fontSize: 11))),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy || _selected == null ? null : () => _search(false),
                icon: const Icon(Icons.manage_search),
                label: const Text('Первый поиск')),
              FilledButton.tonalIcon(
                onPressed: _busy || hits.isEmpty ? null : () => _search(true),
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Уточнить')),
              if (_lastPatch != null)
                OutlinedButton.icon(onPressed: _busy ? null : _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Откатить запись')),
            ]),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(
              color: _muted, fontSize: 12, height: 1.45)),
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
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.pin_outlined,
                          color: _purple, size: 19),
                        title: Text(hits[i],
                          style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(_expected ?? ''),
                        trailing: const Icon(Icons.edit_outlined, color: _cyan),
                        onTap: _busy ? null : () => _edit(hits[i])))),
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
