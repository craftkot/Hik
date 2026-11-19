import 'package:flutter/material.dart';

import '../core/ini_save_editor.dart';

/// UI-only browser. The parent owns confirmation and verified disk writes.
class IniSaveFieldBrowser extends StatefulWidget {
  const IniSaveFieldBrowser({
    super.key, required this.fields, required this.onEdit,
    required this.onClose,
  });

  final List<IniSaveField> fields;
  final Future<bool> Function(IniSaveField field) onEdit;
  final VoidCallback onClose;

  @override
  State<IniSaveFieldBrowser> createState() => _IniSaveFieldBrowserState();
}

class _IniSaveFieldBrowserState extends State<IniSaveFieldBrowser> {
  static const _accent = Color(0xFFB68BFF);
  static const _muted = Color(0xFFA9A2C0);
  final _query = TextEditingController();
  bool _onlyImportant = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _query.removeListener(_refresh);
    _query.dispose();
    super.dispose();
  }

  Future<void> _edit(IniSaveField field) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onEdit(field);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();
    final matches = widget.fields.where((field) =>
      (!_onlyImportant || field.category.important) &&
      (needle.isEmpty ||
          field.displayPath.toLowerCase().contains(needle) ||
          field.value.toLowerCase().contains(needle))).toList();
    final shown = matches.take(500).toList();

    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
        child: Row(children: [
          const Expanded(child: Text('Числовые поля · INI / CFG',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: 'Закрыть список полей INI',
            onPressed: _busy ? null : widget.onClose,
            icon: const Icon(Icons.close)),
        ])),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _query,
          enabled: !_busy,
          maxLength: 128,
          decoration: const InputDecoration(
            counterText: '',
            prefixIcon: Icon(Icons.search),
            labelText: 'Поиск ключа, секции или числа',
            hintText: 'HP, gold, mana, Player, 100',
          ))),
      Row(children: [
        Checkbox(value: _onlyImportant, onChanged: _busy ? null :
          (value) => setState(() => _onlyImportant = value ?? false)),
        const Expanded(child: Text('Только важные',
            style: TextStyle(fontSize: 12))),
        Text('Показано: ' + shown.length.toString() +
             ' из ' + matches.length.toString(),
            style: const TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(width: 12),
      ]),
      const Divider(height: 1),
      Expanded(child: shown.isEmpty
          ? const Center(child: Text('Числовые поля не найдены'))
          : ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final field = shown[i];
                return Material(color: Colors.transparent,
                  child: ListTile(
                    enabled: !_busy,
                    dense: true,
                    leading: field.category.important
                        ? const Icon(Icons.star, color: _accent, size: 18)
                        : null,
                    title: Text(field.displayPath,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text('Строка ' + (field.lineIndex + 1).toString() +
                        (field.category.important ? ' · ' + field.category.label : ''),
                        style: const TextStyle(fontSize: 11, color: _muted)),
                    trailing: Text(field.value, style: const TextStyle(
                        fontWeight: FontWeight.w700, color: _accent)),
                    onTap: _busy ? null : () => _edit(field),
                  ));
              })),
      const Padding(padding: EdgeInsets.all(12), child: Text(
        'Меняется только одно число, без пересборки INI. '
        'Сначала предпросмотр, запись — отдельной кнопкой «Применить» '
        'с резервной копией.',
        style: TextStyle(color: _muted, fontSize: 11))),
    ]);
  }
}
