import 'package:flutter/material.dart';

import '../core/game_file.dart';
import '../core/game_locale_workflow.dart';
import '../core/storage_service.dart';
import '../core/translation_service.dart';

/// Android game-first translation. Does not read private data, repack APKs,
/// patch executable code, or modify any file without explicit confirmation.
class AndroidGameTranslationPanel extends StatefulWidget {
  const AndroidGameTranslationPanel({
    super.key,
    required this.storage,
    required this.files,
    required this.gameName,
    required this.chooseGame,
    required this.grantFolder,
    required this.refreshFiles,
  });

  final GameStorage storage;
  final List<GameFile> files;
  final String? gameName;
  final Future<void> Function() chooseGame;
  final Future<void> Function() grantFolder;
  final Future<void> Function() refreshFiles;

  @override
  State<AndroidGameTranslationPanel> createState() =>
      _AndroidGameTranslationPanelState();
}

class _AndroidGameTranslationPanelState
    extends State<AndroidGameTranslationPanel> {
  final _endpoint = TextEditingController();
  final _apiKey = TextEditingController();
  String _language = 'ru';
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _notice(String value) {
    if (!mounted) return;
    setState(() => _status = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value), duration: const Duration(seconds: 5)));
  }

  Future<void> _prepare() async {
    if (_busy) return;
    if (widget.gameName == null) {
      await widget.chooseGame();
      return;
    }
    final candidates = GameLocaleCandidates.prioritized(widget.files);
    if (candidates.isEmpty) {
      _notice('JSON-локализации не найдены. Нажми кнопку «Доступ к папке» '
          'и разреши чтение открытой папки игры.');
      return;
    }
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    if (endpoint == null || !endpoint.hasAuthority ||
        !(endpoint.scheme == 'https' ||
          (endpoint.scheme == 'http' &&
            (endpoint.host == 'localhost' ||
             endpoint.host == '127.0.0.1')))) {
      _notice('Укажи HTTPS LibreTranslate URL /translate '
          'или локальный HTTP-сервер.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Подготовить перевод игры?'),
        content: Text('Найдены ${candidates.length} JSON-локализаций. '
          'Переведём до ${GameLocaleCandidates.maxBatchFiles} файлов '
          'и до 100 строк на файл. Тексты строк будут отправлены на '
          'сервер ${endpoint.host}. Исходные файлы пока не изменятся. '
          'Результат покажем перед применением.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Подготовить')),
        ],
      ),
    );
    if (!mounted || accepted != true) return;

    final workflow = GameLocaleWorkflow(widget.storage);
    GameLocaleBatch batch;
    setState(() {
      _busy = true;
      _status = 'Подготовка перевода…';
    });
    try {
      batch = await workflow.prepare(widget.files, (source) async {
        final translator = LocaleTranslator(
          endpoint: endpoint,
          target: _language,
          apiKey: _apiKey.text.trim(),
          maxStrings: 100,
        );
        final text = await translator.translateJson(source);
        return LocaleTextResult(text, translator.translated);
      }, onProgress: (completed, total) {
        if (mounted) setState(() =>
            _status = 'Готовим перевод: $completed/$total файлов');
      });
    } catch (error) {
      _notice('Ошибка подготовки: $error');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (batch.drafts.isEmpty) {
      _notice('Переводимых файлов нет. ${batch.skipped.take(2).join('; ')}');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Предпросмотр перевода'),
        content: SizedBox(
          width: 440,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 390),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Готово ${batch.drafts.length} файлов, '
                    '${batch.translatedStrings} строк. '
                    'Перед изменением каждого файла создаётся бэкап. '
                    'Если запись одного файла не удастся, другие '
                    'могут остаться переведёнными. Закрой игру.'),
                  const SizedBox(height: 12),
                  for (final draft in batch.drafts)
                    ExpansionTile(
                      dense: true,
                      title: Text(draft.file.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text('${draft.translatedStrings} строк · '
                          '${draft.file.relativePath}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      children: [
                        const Align(alignment: Alignment.centerLeft,
                          child: Text('Было:', style: TextStyle(
                            fontWeight: FontWeight.bold))),
                        SelectableText(draft.beforePreview,
                            style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace')),
                        const SizedBox(height: 6),
                        const Align(alignment: Alignment.centerLeft,
                          child: Text('Будет:', style: TextStyle(
                            fontWeight: FontWeight.bold))),
                        SelectableText(draft.afterPreview,
                            style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ),
                  if (batch.skipped.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Пропущено: ${batch.skipped.take(4).join('; ')}',
                      style: const TextStyle(fontSize: 11)),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Не сохранять')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Сделать копии и применить')),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      _notice('Перевод отменён: файлы не изменены.');
      return;
    }
    GameLocaleWriteReport report;
    setState(() {
      _busy = true;
      _status = 'Применяем перевод…';
    });
    try {
      report = await workflow.apply(batch, onProgress: (completed, total) {
        if (mounted) setState(() =>
            _status = 'Запись: $completed/$total файлов');
      });
    } catch (error) {
      _notice('Ошибка применения: $error');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await widget.refreshFiles();
    if (!mounted) return;
    _notice('Переведено: ${report.written.length} файлов. '
        'Ошибок: ${report.failed.length}. '
        '${report.failed.isEmpty ? 'Резервные копии созданы.'
            : report.failed.take(2).join('; ')}');
  }

  @override
  Widget build(BuildContext context) {
    final candidates = GameLocaleCandidates.prioritized(widget.files);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF181625),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF342B4E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.translate, color: Color(0xFFB68BFF)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Перевести игру',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Text('${candidates.length} JSON', style: const TextStyle(
              color: Color(0xFF5EE9F5), fontSize: 11)),
          ]),
          const SizedBox(height: 7),
          Text(widget.gameName == null
              ? 'Выбери установленную игру. Откроются доступные переводы.'
              : 'Игра: ${widget.gameName}. Переводим только доступные '
                  'JSON-локализации; приватные данные Android закрыты.',
            style: const TextStyle(fontSize: 11, color: Color(0xFFAAA5BE))),
          const SizedBox(height: 8),
          if (widget.gameName != null)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
              onPressed: _busy ? null : widget.grantFolder,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Доступ к папке игры'),
            )),
          TextField(
            controller: _endpoint,
            decoration: const InputDecoration(
              labelText: 'Сервер LibreTranslate',
              hintText: 'https://your-server/translate',
            ),
          ),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(child: TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'API-ключ (если нужен)'),
            )),
            const SizedBox(width: 8),
            SizedBox(width: 115, child: DropdownButtonFormField<String>(
              initialValue: _language,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Язык'),
              items: const [
                DropdownMenuItem(value: 'ru', child: Text('RU')),
                DropdownMenuItem(value: 'en', child: Text('EN')),
                DropdownMenuItem(value: 'ja', child: Text('JA')),
              ],
              onChanged: _busy ? null : (value) {
                if (value != null) setState(() => _language = value);
              },
            )),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _prepare,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(_busy ? 'Обрабатываем…' :
              widget.gameName == null ? 'Выбрать игру' :
              'Подготовить перевод (${candidates.length > 6
                  ? 6 : candidates.length} файлов)'),
          )),
          if (_status.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(_status, style: const TextStyle(
              color: Color(0xFF5EE9F5), fontSize: 11)),
          ),
          const SizedBox(height: 4),
          const Text('Текст уходит выбранному серверу. Сначала предпросмотр, '
              'затем подтверждение записи с резервными копиями.',
              style: TextStyle(fontSize: 10, color: Color(0xFFAAA5BE))),
        ],
      ),
    );
  }
}
