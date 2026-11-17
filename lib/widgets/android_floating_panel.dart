import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android's opt-in SYSTEM_ALERT_WINDOW overlay. Does not read game RAM.
class AndroidFloatingPanel extends StatefulWidget {
  const AndroidFloatingPanel({super.key, this.initialNumber, required this.onSearch});
  final String? initialNumber;
  final Future<void> Function(String) onSearch;
  @override
  State<AndroidFloatingPanel> createState() => _AndroidFloatingPanelState();
}

class _AndroidFloatingPanelState extends State<AndroidFloatingPanel> {
  static const _channel = MethodChannel('ehtid.gamelab/overlay');
  final _number = TextEditingController();
  bool _busy = false;
  bool _permission = false;
  String _status = 'Нужно системное разрешение показывать поверх других приложений.';

  @override
  void initState() {
    super.initState();
    _number.text = widget.initialNumber ?? '';
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AndroidFloatingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialNumber != null &&
        widget.initialNumber != oldWidget.initialNumber) {
      _number.text = widget.initialNumber!;
      _status = 'Число пришло из оверлея. Запусти поиск по доступным сейвам.';
    }
  }

  @override
  void dispose() { _number.dispose(); super.dispose(); }

  Future<void> _refresh() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted) return;
      setState(() {
        _permission = info?['permission'] == true;
        _status = _permission
          ? 'Разрешение есть. Можно запустить плавающий значок.'
          : 'Плавающий значок требует разрешения Android. '
              'Доступ к памяти другой игры он не предоставляет.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Статус: $error');
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _channel.invokeMethod<String>('start');
      if (!mounted) return;
      setState(() => _status = result == 'permission_required'
          ? 'Открылись настройки. Разреши показ поверх приложений, '
            'вернись и нажми «Запустить» ещё раз.'
          : 'Оверлей запущен. Перейди в игру и нажми на значок E.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Ошибка оверлея: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod<String>('stop');
      if (mounted) setState(() => _status = 'Плавающий значок остановлен.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Остановка: $error');
    }
  }

  Future<void> _search() async {
    final value = _number.text.trim().replaceAll(',', '.');
    if (!RegExp(r'^[+-]?\d{1,12}(\.\d{1,6})?$').hasMatch(value)) {
      setState(() => _status = 'Введи число, например 120, 999 или 12.5');
      return;
    }
    setState(() => _busy = true);
    try { await widget.onSearch(value); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF5EE9F5);
    const muted = Color(0xFFB5ACC8);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF211C33),
        border: Border.all(color: const Color(0xFF684E95)),
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.layers_outlined, color: cyan), SizedBox(width: 10),
          Expanded(child: Text('Android · плавающее окно',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
          Text('ALPHA', style: TextStyle(color: cyan,
            fontWeight: FontWeight.bold, fontSize: 10)),
        ]),
        const SizedBox(height: 10),
        const Text('Окно поверх игры: ручной ввод числа, перемещение, '
          'сворачивание и переход в редактор сохранений. '
          'Обычный Android APK не может править RAM другой игры.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _busy ? null : _start,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Запустить поверх игры')),
          OutlinedButton.icon(onPressed: _busy ? null : _stop,
            icon: const Icon(Icons.close), label: const Text('Остановить')),
          IconButton(onPressed: _refresh,
            icon: Icon(_permission ? Icons.verified_user : Icons.security,
              color: cyan), tooltip: 'Проверить разрешение'),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _number,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: 'HP, мана или деньги из оверлея',
            hintText: 'Например 125'),
        ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(onPressed: _busy ? null : _search,
            icon: const Icon(Icons.manage_search),
            label: const Text('Найти число в сейвах'))),
        const SizedBox(height: 9),
        Text(_status, style: const TextStyle(
            color: muted, fontSize: 11, height: 1.4)),
      ]),
    );
  }
}
