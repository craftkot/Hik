import 'dart:io';

import 'package:flutter/material.dart';

import '../core/crash_rollback_inspector.dart';
import '../core/desktop_save_recovery.dart';
import '../core/game_file.dart';

/// Windows-only UI for restoring a checked EHTID save backup.
/// The caller refreshes its open file after this dialog returns true.
class DesktopBackupRestoreDialog extends StatefulWidget {
  const DesktopBackupRestoreDialog({
    super.key,
    required this.save,
    this.recovery,
    this.inspectCrash,
  });

  final File save;
  final DesktopSaveRecovery? recovery;
  /// Allows test environments to provide read-only crash inspection without
  /// live filesystem asynchronous I/O inside a widget test's fake clock.
  final Future<List<CrashRollbackPreview>> Function(File save)? inspectCrash;

  @override
  State<DesktopBackupRestoreDialog> createState() =>
      _DesktopBackupRestoreDialogState();
}

class _DesktopBackupRestoreDialogState
    extends State<DesktopBackupRestoreDialog> {
  late final DesktopSaveRecovery _recovery =
      widget.recovery ?? DesktopSaveRecovery();

  List<DesktopBackupEntry> _entries = const [];
  DesktopBackupPreview? _preview;
  bool _busy = true;
  int _crashCount = 0;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
        _notice = null;
        _preview = null;
      });
    }
    try {
      final entries = await _recovery.listBackups(widget.save);
      final interrupted = await (widget.inspectCrash ??
          CrashRollbackInspector.inspect)(widget.save);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _crashCount = interrupted.length;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(DesktopBackupEntry entry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
      _notice = null;
    });
    try {
      final checked = await _recovery.preview(widget.save, entry.file);
      if (!mounted) return;
      setState(() => _preview = checked);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final selected = _preview;
    if (_busy || selected == null || _crashCount > 0) return;
    if (!selected.differs) {
      setState(() => _notice = 'Сейв уже совпадает с выбранной копией.');
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Восстановить этот сейв?'),
        content: Text(
          'Исходный файл: ${widget.save.path}\n\n'
          'Выбранный бэкап: ${selected.backup.path}\n\n'
          'Текущий сейв будет заменён содержимым этой копии. '
          'Сначала редактор создаст отдельную резервную копию '
          'текущего файла. Закрой игру перед восстановлением.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Подтвердить восстановление'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = 'Проверяю файлы и восстанавливаю…';
    });
    try {
      final newBackup = await _recovery.restore(selected, confirmed: true);
      if (!mounted) return;
      // Return control to the parent only after the guarded restore succeeds.
      Navigator.pop(context, newBackup);
    } catch (error) {
      if (mounted) setState(() => _error = 'Восстановление отменено: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _preview;
    final blocked = _crashCount > 0;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 610),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.restore, color: Color(0xFFB68BFF)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Восстановить сохранение',
                    style: TextStyle(fontSize: 19,
                        fontWeight: FontWeight.w800))),
                IconButton(
                  tooltip: 'Обновить список бэкапов',
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
              SelectableText(widget.save.path,
                maxLines: 2,
                style: const TextStyle(fontSize: 11,
                    color: Color(0xFFA9A2C0))),
              const SizedBox(height: 8),
              const Text('Выбери резервную копию и проверь содержимое. '
                  'Никаких изменений до отдельного подтверждения.',
                style: TextStyle(fontSize: 12)),
              if (_busy) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator()),
              if (blocked) Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Найдено аварийных файлов: $_crashCount. '
                  'Автовосстановление отключено: сначала вручную '
                  'разбери незавершённый откат. Исходники не удаляются.',
                  style: const TextStyle(color: Colors.orangeAccent,
                      fontSize: 12)),
              ),
              if (_error != null) Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(_error!,
                  style: const TextStyle(color: Colors.orangeAccent,
                      fontSize: 12)),
              ),
              if (_notice != null) Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(_notice!, style:
                    const TextStyle(fontSize: 12))),
              const SizedBox(height: 8),
              const Text('РЕЗЕРВНЫЕ КОПИИ',
                style: TextStyle(fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFFB68BFF),
                  fontWeight: FontWeight.bold)),
              Expanded(
                flex: 3,
                child: _entries.isEmpty
                  ? const Center(child: Text('Бэкапов для этого сейва нет'))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final chosen = selected?.backup.path == entry.file.path;
                        return ListTile(
                          dense: true,
                          selected: chosen,
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(entry.file.uri.pathSegments.last,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          subtitle: Text(
                            '${_date(entry.modified)}  ·  ${entry.length} байт',
                            style: const TextStyle(fontSize: 11)),
                          trailing: chosen
                              ? const Icon(Icons.check_circle_outline)
                              : const Icon(Icons.visibility_outlined),
                          onTap: _busy ? null : () => _select(entry),
                        );
                      },
                    ),
              ),
              const Divider(),
              const Text('ПРЕДПРОСМОТР',
                style: TextStyle(fontSize: 11,
                  letterSpacing: 1.2,
                  color: Color(0xFF5EE9F5),
                  fontWeight: FontWeight.bold)),
              Expanded(
                flex: 2,
                child: selected == null
                  ? const Center(child: Text('Выбери бэкап выше',
                      style: TextStyle(fontSize: 12)))
                  : ListView(children: [
                      Text(
                        'Текущий файл: ${selected.currentBytes.length} байт · '
                        'Копия: ${selected.backupBytes.length} байт',
                        style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 5),
                      Text(selected.differs
                          ? 'Содержимое различается'
                          : 'Содержимое совпадает: восстанавливать нечего',
                        style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5EE9F5))),
                      const SizedBox(height: 7),
                      const Text('Начало резервной копии (HEX):',
                          style: TextStyle(fontSize: 11)),
                      SelectableText(hexPreview(selected.backupBytes,
                          limit: 64),
                        style: const TextStyle(
                          fontSize: 10, fontFamily: 'monospace')),
                    ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Text(
                    'Только Windows · новый бэкап создаётся перед заменой',
                    style: TextStyle(fontSize: 10,
                        color: Color(0xFFA9A2C0)))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy || blocked ||
                          selected == null || !selected.differs
                      ? null : _restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Восстановить'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
