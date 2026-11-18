import 'package:flutter/material.dart';

import '../core/json_editor.dart';
import '../core/save_value_priority.dart';

/// UI-only filter: preserves pointers, values, and the caller's existing order.
List<JsonField> filterSaveFields(
  List<JsonField> fields, {
  String query = '',
  SaveValueCategory? category,
  bool onlyImportant = false,
}) {
  final needle = query.trim().toLowerCase();
  return List<JsonField>.unmodifiable(fields.where((field) {
    if (onlyImportant && !field.category.important) return false;
    if (category != null && field.category != category) return false;
    return needle.isEmpty ||
        field.pointer.toLowerCase().contains(needle) ||
        field.preview.toLowerCase().contains(needle);
  }));
}

/// A cross-platform browser; edits are confirmed by its parent JSON editor.
class SaveFieldBrowser extends StatefulWidget {
  const SaveFieldBrowser({
    super.key,
    required this.fields,
    required this.onEdit,
    required this.onClose,
    this.isSave = true,
  });

  final List<JsonField> fields;
  final Future<bool> Function(JsonField) onEdit;
  final VoidCallback onClose;
  final bool isSave;

  @override
  State<SaveFieldBrowser> createState() => _SaveFieldBrowserState();
}

class _SaveFieldBrowserState extends State<SaveFieldBrowser> {
  static const _accent = Color(0xFFB68BFF);
  static const _muted = Color(0xFFA9A2C0);

  final _search = TextEditingController();
  SaveValueCategory? _category;
  bool _onlyImportant = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(JsonField field) async {
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
    final categories = SaveValueCategory.values.where((category) =>
        category.important &&
        widget.fields.any((field) => field.category == category)).toList();
    final matches = filterSaveFields(widget.fields,
      query: _search.text, category: _category,
      onlyImportant: widget.isSave && _onlyImportant);
    // Search all inspected leaves; keep the rendered list bounded.
    final filtered = matches.take(500).toList(growable: false);
    final importantCount = widget.fields
        .where((field) => field.category.important).length;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          const Expanded(child: Text('Поля сохранения · JSON',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'Закрыть список полей',
            onPressed: _busy ? null : widget.onClose,
            icon: const Icon(Icons.close)),
        ]),
      ),
      const Divider(height: 1),
      if (widget.isSave) Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: _accent),
          const SizedBox(width: 7),
          Expanded(child: Text(
            'Важные поля сначала: $importantCount из ${widget.fields.length}. '
            'Подсказки по названиям — проверь значения.',
            style: const TextStyle(fontSize: 11, color: _muted))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: TextField(
          controller: _search,
          maxLength: 128,
          enabled: !_busy,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            prefixIcon: const Icon(Icons.search, size: 19),
            labelText: 'Поиск по ключу или значению',
            hintText: 'Например hp, coins, strength, 100',
            suffixIcon: _search.text.isEmpty ? null
                : IconButton(tooltip: 'Очистить поиск',
                    onPressed: _busy ? null : _search.clear,
                    icon: const Icon(Icons.clear, size: 18)),
          ),
        ),
      ),
      if (widget.isSave) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 3),
          child: Row(children: [
            Checkbox(value: _onlyImportant,
              onChanged: _busy ? null : (enabled) =>
                  setState(() => _onlyImportant = enabled ?? false)),
            const Expanded(child: Text('Только важные',
                style: TextStyle(fontSize: 12))),
            Text('Показано: ${filtered.length} из ${matches.length}',
                style: const TextStyle(fontSize: 11, color: _muted)),
          ]),
        ),
        SizedBox(height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            const SizedBox(width: 12),
            Padding(padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: const Text('Все'),
                selected: _category == null, showCheckmark: false,
                onSelected: _busy ? null : (_) =>
                    setState(() => _category = null))),
            for (final category in categories)
              Padding(padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(category.label),
                  selected: _category == category,
                  showCheckmark: false,
                  onSelected: _busy ? null : (_) => setState(() =>
                      _category = _category == category ? null : category))),
            const SizedBox(width: 12),
          ])),
      ],
      if (matches.length > 500)
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 5),
          child: Text('Показаны первые 500 совпадений — уточни поиск.',
              style: TextStyle(fontSize: 11, color: _muted)),
        ),
      const Divider(height: 1),
      Expanded(child: filtered.isEmpty
          ? Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_alt_off, size: 28, color: _muted),
                const SizedBox(height: 6),
                const Text('Подходящих полей не найдено'),
                TextButton(onPressed: _busy ? null : () => setState(() {
                    _search.clear();
                    _onlyImportant = false;
                    _category = null;
                  }),
                  child: const Text('Сбросить фильтры')),
              ],
            ))
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final field = filtered[index];
                return ListTile(
                  enabled: !_busy,
                  dense: true,
                  leading: field.category.important && widget.isSave
                      ? const Icon(Icons.star_rounded,
                          size: 18, color: _accent)
                      : null,
                  title: Row(children: [
                    Expanded(child: Text(field.pointer,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: field.category.important && widget.isSave
                            ? FontWeight.w700 : FontWeight.w400))),
                    if (field.category.important && widget.isSave)
                      Padding(padding: const EdgeInsets.only(left: 6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(7)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                            child: Text(field.category.label,
                              style: const TextStyle(fontSize: 10,
                                  color: _accent))),
                        )),
                  ]),
                  subtitle: Text(field.preview,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: _busy ? null : () => _edit(field),
                );
              })),
      const Padding(padding: EdgeInsets.all(10),
        child: Text(
          'Выбери поле. Значение вводится в JSON-формате: '
          'число 120, строка "текст", true или false. '
          'Сортировка и фильтры ничего не записывают.',
          style: TextStyle(fontSize: 11, color: _muted))),
    ]);
  }
}
