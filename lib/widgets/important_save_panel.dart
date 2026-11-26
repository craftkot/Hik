import 'package:flutter/material.dart';
import '../core/important_save_fields.dart';

/// Important named values, one per row, with a raw-file escape hatch.
class ImportantSavePanel extends StatefulWidget {
  const ImportantSavePanel({
    super.key,
    required this.entries,
    required this.isBinary,
    required this.onEdit,
    required this.onShowRaw,
    required this.onSearchBinary,
  });

  final List<ImportantSaveField> entries;
  final bool isBinary;
  final Future<bool> Function(ImportantSaveField) onEdit;
  final VoidCallback onShowRaw;
  final VoidCallback? onSearchBinary;

  @override
  State<ImportantSavePanel> createState() => _ImportantSavePanelState();
}

class _ImportantSavePanelState extends State<ImportantSavePanel> {
  final TextEditingController _search = TextEditingController();
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

  Future<void> _edit(ImportantSaveField field) async {
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
    const accent = Color(0xFFB68BFF);
    const muted = Color(0xFFAAA5BE);
    final needle = _search.text.trim().toLowerCase();
    final entries = widget.entries.where((field) =>
      needle.isEmpty ||
      field.name.toLowerCase().contains(needle) ||
      field.category.label.toLowerCase().contains(needle) ||
      field.value.toLowerCase().contains(needle)).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Row(children: [
          const Icon(Icons.tune_rounded, color: accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('ВАЖНЫЕ ПАРАМЕТРЫ',
              style: TextStyle(fontWeight: FontWeight.w800))),
          Text(widget.entries.length.toString(),
              style: const TextStyle(color: accent)),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _busy ? null : widget.onShowRaw,
            icon: const Icon(Icons.code_rounded, size: 18),
            label: const Text('Исходный файл'),
          ),
        ]),
      ),
      if (widget.entries.isNotEmpty) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          controller: _search,
          enabled: !_busy,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'HP, деньги, мана, уровень…',
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Divider(height: 1),
      Expanded(child: entries.isEmpty
          ? Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.manage_search_rounded, color: muted, size: 38),
                const SizedBox(height: 12),
                Text(widget.entries.isEmpty
                    ? 'Понятных важных полей не найдено'
                    : 'Совпадений нет', textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(widget.isBinary
                    ? 'Содержимое бинарное. Без формата игры нельзя '
                      'надёжно определить, где HP, деньги и другие параметры.'
                    : 'Показаны распознанные параметры и игровые переменные. '
                      'Остальные данные не удаляются.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: muted)),
                if (widget.onSearchBinary != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onSearchBinary,
                    icon: const Icon(Icons.search),
                    label: const Text('Найти число вручную'),
                  ),
                ],
              ]),
            ))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, index) {
                final field = entries[index];
                return Material(color: Colors.transparent, child: ListTile(
                  enabled: !_busy,
                  leading: Icon(field.category.important ? Icons.star_rounded : Icons.data_object,
                      color: field.category.important ? accent : muted, size: 18),
                  title: Text(field.name, maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(field.category.important ? field.category.label : 'Переменная',
                      style: const TextStyle(fontSize: 11, color: muted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 155),
                      child: Text(field.value, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: accent,
                            fontWeight: FontWeight.bold))),
                    const SizedBox(width: 7),
                    const Icon(Icons.edit_outlined, size: 17),
                  ]),
                  onTap: _busy ? null : () => _edit(field),
                ));
              })),
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Text(
          'Важность определяется по названию поля. '
          'Запись — только после подтверждения и резервной копии.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ),
    ]);
  }
}
