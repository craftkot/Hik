import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/binary_save_editor.dart';

class NumericPatchRequest {
  const NumericPatchRequest({
    required this.offset,
    required this.format,
    required this.expected,
    required this.replacement,
  });

  final int offset;
  final SaveNumberFormat format;
  final String expected;
  final String replacement;
}

/// A strictly local numeric save-file editor. There is no process attachment
/// or Android sandbox bypass here.
class BinarySaveDialog extends StatefulWidget {
  const BinarySaveDialog({super.key, required this.data});
  final Uint8List data;

  @override
  State<BinarySaveDialog> createState() => _BinarySaveDialogState();
}

class _BinarySaveDialogState extends State<BinarySaveDialog> {
  final _oldValue = TextEditingController();
  final _newValue = TextEditingController();

  SaveNumberFormat _format = SaveNumberFormat.int32Little;
  List<SaveNumberHit> _hits = const [];
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _oldValue.dispose();
    _newValue.dispose();
    super.dispose();
  }

  void _search() {
    try {
      final hits = BinarySaveEditor.search(
        widget.data, _oldValue.text, _format, maxResults: 100);
      setState(() {
        _hits = hits;
        _searched = true;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _hits = const [];
        _searched = false;
        _error = error.toString();
      });
    }
  }

  void _choose(SaveNumberHit hit) {
    try {
      BinarySaveEditor.patch(widget.data,
        offset: hit.offset,
        expected: _oldValue.text,
        replacement: _newValue.text,
        format: _format,
      );
      Navigator.of(context).pop(NumericPatchRequest(
        offset: hit.offset,
        expected: _oldValue.text.trim(),
        replacement: _newValue.text.trim(),
        format: _format,
      ));
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поиск значения в сейве'),
      content: SizedBox(
        width: 475,
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Только неупакованные числовые поля в файле. '
              'При совпадениях выбери правильное смещение.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _oldValue,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Текущее значение, например 120'),
              onChanged: (_) => setState(() {
                _hits = const [];
                _searched = false;
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newValue,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Новое значение, например 9999'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SaveNumberFormat>(
              initialValue: _format,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Кодировка числа'),
              items: SaveNumberFormat.values.map((f) =>
                  DropdownMenuItem(value: f, child: Text(f.label))).toList(),
              onChanged: (next) {
                if (next == null) return;
                setState(() {
                  _format = next;
                  _hits = const [];
                  _searched = false;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.search),
              label: const Text('Найти число'),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Text(_error!, style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.error)),
            if (_searched)
              Text(_hits.isEmpty
                  ? 'Совпадений нет. Попробуй другой формат.'
                  : 'Совпадений: ${_hits.length} (не больше 100). '
                    'Нажми на смещение для записи.',
                  style: const TextStyle(fontSize: 12)),
            SizedBox(
              height: 175,
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (context, index) {
                  final hit = _hits[index];
                  return ListTile(
                    dense: true,
                    title: Text(hit.hexOffset,
                      style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text('Смещение ${hit.offset} байт'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _choose(hit),
                  );
                },
              ),
            ),
            const Text('Игра должна быть закрыта при сохранении. '
              'Сжатые, шифрованные и защищённые контрольной суммой '
              'сейвы требуют отдельного адаптера.',
              style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть')),
      ],
    );
  }
}
