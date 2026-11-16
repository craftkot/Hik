import 'package:flutter/material.dart';

import '../core/game_file.dart';
import '../core/game_value_search.dart';
import '../core/storage_service.dart';

/// Read-only game-folder-wide search; choosing a result opens the source file
/// in the existing editor, where writes require a separate confirmation.
class GameWideSearchDialog extends StatefulWidget {
  const GameWideSearchDialog({
    super.key,
    required this.storage,
    required this.files,
    required this.folderCount,
    this.initialQuery,
  });

  final GameStorage storage;
  final List<GameFile> files;
  final int folderCount;
  final String? initialQuery;

  @override
  State<GameWideSearchDialog> createState() => _GameWideSearchDialogState();
}

class _GameWideSearchDialogState extends State<GameWideSearchDialog> {
  final _query = TextEditingController();
  GameSearchSummary? _results;
  int _done = 0;
  int _total = 0;
  bool _busy = false;
  bool _cancel = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _query.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _cancel = true;
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancel = false;
      _results = null;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      final report = await GameValueSearch.search(
        storage: widget.storage,
        files: widget.files,
        query: _query.text,
        shouldCancel: () => _cancel || !mounted,
        onProgress: (done, total) {
          if (!mounted) return;
          if (done == 0 || done == total || done % 10 == 0) {
            setState(() { _done = done; _total = total; });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _results = report;
        _done = report.scanned;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _results;
    return AlertDialog(
      title: const Text('Поиск по файлам игры'),
      content: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Доступные папки: ${widget.folderCount}. '
              'Читаем текстовые и числовые значения в файлах до 8 МиБ. '
              'Архивы и исполняемые файлы пропускаем.',
              style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Число или текст',
                hintText: 'Например 999, health или inventory'),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.manage_search),
                label: const Text('Искать по всем файлам'),
              )),
              if (_busy) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() => _cancel = true),
                  child: Text(_cancel ? 'Остановка…' : 'Остановить'),
                ),
              ],
            ]),
            if (_busy || result != null) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _total > 0 ? _done / _total
                    : result != null ? 1 : null),
              const SizedBox(height: 5),
              Text(result == null
                  ? 'Проверено: $_done / $_total'
                  : 'Проверено: ${result.scanned}; найдено: ${result.hits.length}; '
                    'пропущено: ${result.skipped}; ошибок чтения: ${result.readErrors}',
                  style: const TextStyle(fontSize: 11)),
            ],
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
            if (result?.truncated == true)
              const Text('Достигнут лимит 200 результатов. '
                'Уточни запрос для точного поиска.',
                style: TextStyle(fontSize: 11)),
            if (result?.cancelled == true)
              const Text('Поиск остановлен. Результаты выше сохранены.',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            Expanded(child: result == null || result.hits.isEmpty
                ? const Center(child: Text('Результатов пока нет'))
                : ListView.builder(
                  itemCount: result.hits.length,
                  itemBuilder: (_, index) {
                    final hit = result.hits[index];
                    return ListTile(
                      dense: true,
                      title: Text(hit.file.relativePath, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${hit.format} · ${hit.location}\n${hit.preview}',
                        maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                      isThreeLine: true,
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: _busy ? null :
                        () => Navigator.of(context).pop(hit.file),
                    );
                  },
                )),
            const Text('Поиск ничего не меняет. Нажми на результат, '
              'чтобы открыть файл в редакторе. '
              'Шифрованные и сжатые сейвы требуют отдельного адаптера.',
              style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancel = true;
            Navigator.of(context).pop();
          },
          child: const Text('Закрыть')),
      ],
    );
  }
}
