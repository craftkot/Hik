import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'core/archive_inspector.dart';
import 'core/game_file.dart';
import 'core/game_profile.dart';
import 'core/json_editor.dart';
import 'core/storage_service.dart';
import 'core/translation_service.dart';

void main() => runApp(const GameLabApp());

const _background = Color(0xFF0C0B13);
const _panel = Color(0xFF181625);
const _panelLight = Color(0xFF222035);
const _accent = Color(0xFFAA83FF);
const _muted = Color(0xFFAAA5BE);

enum Workspace { preloads, saves, localize, cheats }

extension WorkspaceInfo on Workspace {
  String get title => switch (this) {
    Workspace.preloads => 'Предзагрузки',
    Workspace.saves => 'Редактор сохранений',
    Workspace.localize => 'Перевод игры',
    Workspace.cheats => 'Читы (соло)',
  };
  String get detail => switch (this) {
    Workspace.preloads => 'Просмотр ресурсов и распознанных файлов',
    Workspace.saves => 'Редактирование доступных текстовых сейвов',
    Workspace.localize => 'Локализация без изменения ключей JSON',
    Workspace.cheats => 'Память запущенной игры: модуль в разработке',
  };
  IconData get icon => switch (this) {
    Workspace.preloads => Icons.folder_zip_outlined,
    Workspace.saves => Icons.save_as_outlined,
    Workspace.localize => Icons.translate,
    Workspace.cheats => Icons.memory_outlined,
  };
}

class GameLabApp extends StatelessWidget {
  const GameLabApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'EHTID Game Lab',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: ColorScheme.fromSeed(seedColor: _accent,
          brightness: Brightness.dark, surface: _panel),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        filled: true,
        fillColor: _panelLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      ),
      cardTheme: CardThemeData(color: _panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    home: const GameLabHome(),
  );
}

class GameLabHome extends StatefulWidget {
  const GameLabHome({super.key});
  @override
  State<GameLabHome> createState() => _GameLabHomeState();
}

class _GameLabHomeState extends State<GameLabHome> {
  final GameStorage _storage = createStorage();
  final TextEditingController _editor = TextEditingController();
  final TextEditingController _query = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();

  Workspace _section = Workspace.preloads;
  String? _folder;
  List<GameFile> _files = [];
  GameFile? _selected;
  Uint8List? _bytes;
  ArchiveInspector? _archive;
  ArchiveEntry? _archiveEntry;
  Uint8List? _archiveEntryBytes;
  String? _originalText;
  bool _dirty = false;
  bool _loading = false;
  bool _mobilePreview = false;
  String _language = 'ru';
  String _state = 'Выбери папку игры, чтобы начать';
  List<String> _runningProcesses = [];
  GameProfile? _profile;

  @override
  void initState() {
    super.initState();
    _editor.addListener(() {
      if (!mounted) return;
      final newDirty = _originalText != null &&
          _editor.text != _originalText;
      if (newDirty != _dirty) setState(() => _dirty = newDirty);
    });
    _query.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _editor.dispose();
    _query.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() => _state = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), duration: const Duration(seconds: 4)));
  }

  Future<void> _chooseFolder() async {
    try {
      final folder = await _storage.chooseFolder();
      if (folder == null) return;
      if (_dirty) {
        _message('Сначала сохрани или отмени правки перед сменой папки');
        return;
      }
      if (!mounted) return;
      setState(() { _folder = folder; _selected = null; _bytes = null;
        _mobilePreview = false; _files = []; _profile = null;
        _archive = null; _archiveEntry = null; _archiveEntryBytes = null; });
      await _scan();
    } catch (error) { _message('Не удалось открыть папку: $error'); }
  }

  Future<void> _scan() async {
    final folder = _folder;
    if (folder == null || _loading) return;
    setState(() { _loading = true; _state = 'Сканирование файлов…'; });
    try {
      final found = await _storage.scan(folder);
      found.sort((a, b) => a.relativePath.toLowerCase()
          .compareTo(b.relativePath.toLowerCase()));
      if (!mounted) return;
      setState(() { _files = found; _profile = detectGameProfile(found); _selected = null; _bytes = null;
        _originalText = null; _mobilePreview = false;
        _archive = null; _archiveEntry = null; _archiveEntryBytes = null;
        _state = 'Найдено ${found.length} файлов · движок: ${_profile?.engine ?? 'неизвестен'}'; });
    } catch (error) { _message('Ошибка сканирования: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  List<GameFile> get _visibleFiles {
    final search = _query.text.trim().toLowerCase();
    return _files.where((f) {
      final inSection = switch (_section) {
        Workspace.preloads => f.isLikelyPreload || (!f.isSave && !f.isLocalization),
        Workspace.saves => f.isSave,
        Workspace.localize => f.isLocalization,
        Workspace.cheats => false,
      };
      return inSection && f.relativePath.toLowerCase().contains(search);
    }).toList();
  }

  Future<void> _openFile(GameFile file) async {
    if (_dirty) {
      final abandon = await showDialog<bool>(context: context,
        builder: (context) => AlertDialog(
          title: const Text('Изменения не сохранены'),
          content: const Text('Перейти к другому файлу и потерять правки?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
                child: const Text('Не сохранять')),
          ],
        ));
      if (abandon != true) return;
    }
    setState(() { _loading = true; _state = 'Чтение ${file.name}…'; });
    try {
      final isLarge = file.size > maxEditableBytes;
      final bytes = isLarge
          ? await _storage.readPreview(file) : await _storage.read(file);
      final inspector = !isLarge && ArchiveInspector.isZip(bytes)
          ? ArchiveInspector.open(bytes) : null;
      final decoded = file.isImage || isLarge || inspector != null
          ? null : decodeEditableText(bytes);
      if (!mounted) return;
      setState(() {
        _selected = file;
        _bytes = bytes;
        _archive = inspector;
        _archiveEntry = null;
        _archiveEntryBytes = null;
        _originalText = decoded;
        _editor.text = decoded ?? '';
        _dirty = false;
        _mobilePreview = true;
        _state = 'Открыт ${file.relativePath}';
      });
    } catch (error) { _message('Не удалось прочесть файл: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _applyChanges() async {
    final selected = _selected;
    final original = _bytes;
    if (selected == null || _originalText == null || original == null || !_dirty) return;
    try {
      if (selected.isJson) jsonDecode(_editor.text);
    } catch (_) {
      _message('JSON содержит ошибку. Сохранять не стал.');
      return;
    }
    final shouldWrite = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(
        title: const Text('Применить изменения?'),
        content: Text('Файл: ${selected.relativePath}\n\n'
            'Перед записью создадим резервную копию. '
            'Лучше закрыть игру, если она сейчас использует этот файл.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Создать копию и применить')),
        ],
      ));
    if (shouldWrite != true) return;
    setState(() => _loading = true);
    try {
      final current = await _storage.read(selected);
      if (!_bytesEqual(current, original)) {
        throw StateError('Файл изменился после открытия. Обнови его перед записью.');
      }
      final bytes = Uint8List.fromList(utf8.encode(_editor.text));
      final backup = await _storage.writeWithBackup(selected, bytes);
      final verify = await _storage.read(selected);
      if (!_bytesEqual(verify, bytes)) {
        throw StateError('Данные после записи не совпадают. Резервная копия: $backup');
      }
      if (!mounted) return;
      setState(() { _bytes = bytes; _originalText = _editor.text;
        _dirty = false; });
      _message('Применено! Резервная копия: $backup');
    } catch (error) { _message('Запись отменена / ошибка: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _showJsonFields() async {
    List<JsonField> fields;
    try {
      fields = listJsonFields(_editor.text);
    } catch (error) {
      _message('Не удалось прочитать JSON: $error');
      return;
    }
    if (fields.isEmpty) {
      _message('В JSON нет доступных полей');
      return;
    }
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      backgroundColor: _panel, builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(heightFactor: 0.8,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Expanded(child: Text('Поля сохранения · JSON',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close)),
              ])),
            const Divider(height: 1),
            Expanded(child: ListView.builder(itemCount: fields.length,
              itemBuilder: (context, i) {
                final field = fields[i];
                return ListTile(
                  title: Text(field.pointer, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  subtitle: Text(field.preview, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.edit_outlined, size: 18),
                  onTap: () async {
                    final changed = await _editJsonField(field);
                    if (changed && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                );
              })),
            const Padding(padding: EdgeInsets.all(10),
              child: Text('Выбери поле. Значение вводится в JSON-формате: '
                  'число 120, строка "текст", true или false.',
                style: TextStyle(fontSize: 11, color: _muted))),
          ]))),
      );
  }

  Future<bool> _editJsonField(JsonField field) async {
    final controller = TextEditingController(text: field.preview);
    try {
      final updated = await showDialog<String>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Изменить поле'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(field.pointer,
              style: const TextStyle(fontSize: 12, color: _muted)),
            const SizedBox(height: 14),
            TextField(controller: controller,
              maxLines: 4, minLines: 1,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(labelText: 'Значение JSON')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Изменить')),
          ],
        ));
      if (updated == null) return false;
      try {
        final next = changeJsonField(_editor.text, field.pointer, updated);
        if (!mounted) return false;
        setState(() => _editor.text = next);
        return true;
      } catch (error) {
        _message('Поле не изменено: $error');
        return false;
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _translateJson() async {
    if (_selected?.isJson != true || _originalText == null) {
      _message('Для автоперевода открой JSON локализации');
      return;
    }
    final raw = _endpoint.text.trim();
    final url = Uri.tryParse(raw);
    if (url == null || !url.hasAuthority) {
      _message('Укажи URL LibreTranslate: https://сервер/translate');
      return;
    }
    setState(() { _loading = true; _state = 'Переводим строки JSON…'; });
    try {
      final translator = LocaleTranslator(
        endpoint: url, target: _language, apiKey: _apiKey.text.trim());
      final result = await translator.translateJson(_editor.text);
      if (!mounted) return;
      setState(() { _editor.text = result; _dirty = result != _originalText;
        _state = 'Переведено ${translator.translated} строк — проверь результат'; });
      _message('Переведено ${translator.translated} строк. Пока только предпросмотр.');
    } catch (error) { _message('Не удалось перевести: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _listProcesses() async {
    if (!Platform.isWindows) {
      _message('На Android память других игр из обычного APK недоступна');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await Process.run('tasklist', ['/fo', 'csv', '/nh']);
      if (result.exitCode != 0) throw StateError(result.stderr.toString());
      final processes = <String>[];
      for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
        final matches = RegExp(r'"([^"]*)"').allMatches(line).toList();
        if (matches.length >= 2) {
          processes.add('${matches[0].group(1)}  ·  PID ${matches[1].group(1)}');
        }
      }
      if (!mounted) return;
      setState(() { _runningProcesses = processes.take(150).toList();
        _state = 'Найдено ${processes.length} процессов (только просмотр)'; });
    } catch (error) { _message('Не удалось получить процессы: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  void _changeSection(Workspace value) {
    if (value == _section) return;
    if (_dirty) {
      _message('Сначала примени или отмени изменения в открытом файле');
      return;
    }
    setState(() { _section = value; _selected = null; _bytes = null;
      _originalText = null; _mobilePreview = false;
      _archive = null; _archiveEntry = null; _archiveEntryBytes = null; });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 880;
      return Scaffold(
        body: SafeArea(child: Row(children: [
          _sidebar(compact),
          Expanded(child: Column(children: [
            _header(compact),
            Expanded(child: Padding(
              padding: EdgeInsets.all(compact ? 10 : 20),
              child: _section == Workspace.cheats
                  ? _cheatsView()
                  : _workspaceView(compact),
            )),
            _statusBar(),
          ])),
        ])),
      );
    },
  );

  Widget _sidebar(bool compact) => Container(
    width: compact ? 66 : 216,
    color: const Color(0xFF12101D),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 18, vertical: 25),
        child: Row(children: [
          const Icon(Icons.hexagon_outlined, size: 32, color: _accent),
          if (!compact) const SizedBox(width: 10),
          if (!compact) const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('EHTID', style: TextStyle(
              fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('GAME LAB', style: TextStyle(fontSize: 10,
                  letterSpacing: 2, color: _muted))],
          )),
        ])),
      const Divider(height: 1, color: Color(0xFF2D293C)),
      const SizedBox(height: 20),
      for (final section in Workspace.values)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Tooltip(message: section.title,
            child: Material(color: _section == section ? _panelLight : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(borderRadius: BorderRadius.circular(12),
                onTap: () => _changeSection(section),
                child: Padding(padding: EdgeInsets.symmetric(
                    horizontal: compact ? 17 : 12, vertical: 14),
                  child: Row(children: [
                    Icon(section.icon, color: _section == section ? _accent : _muted,
                        size: 23),
                    if (!compact) const SizedBox(width: 12),
                    if (!compact) Expanded(child: Text(section.title,
                        style: TextStyle(fontSize: 13,
                            color: _section == section ? Colors.white : _muted,
                            fontWeight: _section == section ? FontWeight.w700 : FontWeight.w400))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      const Spacer(),
      Padding(padding: const EdgeInsets.all(15),
        child: Column(children: [
          const Icon(Icons.shield_outlined, color: _muted),
          if (!compact) const SizedBox(height: 8),
          if (!compact) const Text('Локальная работа с файлами\nБез автообхода защиты',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: _muted)),
        ]),
      ),
    ]),
  );

  Widget _header(bool compact) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 16),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(
        color: Color(0xFF2A2739)))),
    child: Row(children: [
      if (!compact) Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(_section.title, style: const TextStyle(
          fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_section.detail, style: const TextStyle(fontSize: 12, color: _muted))],
      )),
      if (compact) Expanded(child: Text(_section.title, maxLines: 2,
        style: const TextStyle(fontWeight: FontWeight.w700))),
      if (_profile != null && !compact) Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Tooltip(message: _profile!.hints.join('\n'),
          child: Chip(label: Text('Движок: ${_profile!.engine}',
            style: const TextStyle(fontSize: 11))))),
      if (_folder != null && !compact) Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(width: 180, child: Tooltip(message: _folder!,
          child: Text(_folder!, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12))))),
      IconButton(onPressed: _loading || _folder == null ? null : _scan,
          tooltip: 'Повторное сканирование', icon: const Icon(Icons.refresh)),
      const SizedBox(width: 6),
      FilledButton.icon(onPressed: _loading ? null : _chooseFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(compact ? 'Папка' : 'Открыть папку игры')),
    ]),
  );

  Widget _workspaceView(bool compact) {
    final narrow = compact || MediaQuery.sizeOf(context).width < 1000;
    if (narrow && _mobilePreview && _selected != null) return _detailView(narrow: true);
    if (narrow) return _fileList();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 345, child: _fileList()),
      const SizedBox(width: 16),
      Expanded(child: _detailView(narrow: false)),
    ]);
  }

  Widget _fileList() {
    final items = _visibleFiles;
    return Container(
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(17)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('ФАЙЛЫ ИГРЫ', style: TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 1.3, fontSize: 12)),
              const Spacer(),
              Text('${items.length}', style: const TextStyle(color: _accent)),
            ]),
            const SizedBox(height: 13),
            TextField(controller: _query,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по имени и пути…')),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFF2D293C)),
        Expanded(child: _folder == null
            ? _emptyMessage(Icons.folder_open, 'Папка ещё не выбрана',
                'Открой папку игры — появятся доступные файлы.')
            : items.isEmpty
              ? _emptyMessage(Icons.manage_search, 'Файлы не найдены',
                  'Проверь путь или выбери другую функцию слева.')
              : ListView.builder(itemCount: items.length,
                  itemBuilder: (context, index) {
                    final file = items[index];
                    final active = _selected?.id == file.id;
                    return Material(color: active ? _panelLight : Colors.transparent,
                      child: ListTile(
                        onTap: _loading ? null : () => _openFile(file),
                        selected: active, dense: true,
                        leading: Icon(_fileIcon(file), color: active ? _accent : _muted),
                        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(file.relativePath, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: _muted)),
                        trailing: Text(_formatSize(file.size),
                            style: const TextStyle(fontSize: 10, color: _muted)),
                      ),
                    );
                  })),
      ]),
    );
  }

  Widget _detailView({required bool narrow}) {
    final file = _selected;
    final bytes = _bytes;
    if (file == null || bytes == null) return Container(
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(17)),
      child: _emptyMessage(Icons.description_outlined,
          'Выбери файл', 'Два раза нажимать не обязательно — одного касания хватит.'));
    final imagePreview = _archive == null && file.isImage && file.size <= maxEditableBytes;
    final canEdit = _originalText != null && !file.isImage;
    final canUseJsonEditor = canEdit &&
        (_section == Workspace.saves || _section == Workspace.localize) &&
        (file.isJson || _editor.text.trimLeft().startsWith('{') ||
            _editor.text.trimLeft().startsWith('['));
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(17)),
      child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
          child: Row(children: [
            if (narrow) IconButton(onPressed: () => setState(() => _mobilePreview = false),
                icon: const Icon(Icons.arrow_back)),
            Icon(_fileIcon(file), color: _accent),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(file.name, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${_formatSize(file.size)}  ·  ${_archive != null ? 'ZIP · ${_archive!.entries.length} элементов' : identifyFile(bytes)}',
                      style: const TextStyle(fontSize: 11, color: _muted))])),
            if (canUseJsonEditor) IconButton(
              tooltip: 'Редактировать поля JSON',
              onPressed: _showJsonFields,
              icon: const Icon(Icons.account_tree_outlined, color: _accent)),
            if (_dirty) IconButton(
              tooltip: 'Отменить несохранённые правки',
              onPressed: () => _editor.text = _originalText ?? '',
              icon: const Icon(Icons.undo, color: _muted)),
            if (narrow) IconButton.filled(
              tooltip: 'Применить изменения с резервной копией',
              onPressed: _dirty && !_loading ? _applyChanges : null,
              icon: const Icon(Icons.check, size: 19))
            else FilledButton.icon(onPressed: _dirty && !_loading ? _applyChanges : null,
                icon: const Icon(Icons.check, size: 17), label: const Text('Применить')),
          ]),
        ),
        if (_section == Workspace.localize && canEdit)
          _translationToolbar(file),
        const Divider(height: 1, color: Color(0xFF302B42)),
        Expanded(child: _archive != null
            ? _archiveBrowser(narrow: narrow)
            : imagePreview
            ? Center(child: InteractiveViewer(
                minScale: 0.5, maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Text('Не удалось декодировать картинку'))))
            : canEdit
                ? Padding(padding: const EdgeInsets.all(12),
                    child: TextField(controller: _editor,
                      expands: true, maxLines: null, minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontFamily: 'monospace',
                          fontSize: 12, height: 1.5),
                      decoration: const InputDecoration(
                        hintText: 'Содержимое файла',
                        contentPadding: EdgeInsets.all(16)),
                    ))
                : SingleChildScrollView(padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HEX-ПРОСМОТР · только чтение',
                            style: TextStyle(color: _accent,
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 12),
                        const Text('Формат не распознан как обычный UTF-8. '
                            'Шифрование и упаковка зависят от конкретной игры.',
                            style: TextStyle(color: _muted, fontSize: 12)),
                        const SizedBox(height: 16),
                        SelectableText(hexPreview(bytes), style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                      ]))),
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(canEdit
                  ? 'Редактирование локально · резервная копия при применении'
                  : 'Просмотр без изменений исходного файла',
                  style: const TextStyle(fontSize: 11, color: _muted)))),
      ]),
    );
  }

  Widget _translationToolbar(GameFile file) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Машинный перевод через свой LibreTranslate API. '
          'Текст будет отправлен выбранному серверу; файл — нет.',
          style: TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 132, child: DropdownButtonFormField<String>(
            initialValue: _language,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Язык'),
            items: const [
              DropdownMenuItem(value: 'ru', child: Text('Русский')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'de', child: Text('Deutsch')),
              DropdownMenuItem(value: 'ja', child: Text('日本語')),
              DropdownMenuItem(value: 'fr', child: Text('Français')),
            ], onChanged: (value) { if (value != null) setState(() => _language = value); },
          )),
          SizedBox(width: 240, child: TextField(controller: _endpoint,
            decoration: const InputDecoration(labelText: 'URL /translate',
                hintText: 'https://…/translate'))),
          SizedBox(width: 135, child: TextField(controller: _apiKey,
            obscureText: true, decoration: const InputDecoration(labelText: 'API-ключ (опц.)'))),
          OutlinedButton.icon(onPressed: _loading || !file.isJson ? null : _translateJson,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Перевести до 100 строк')),
        ]),
    ]),
  );

  Widget _cheatsView() => Container(
    width: double.infinity,
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(17)),
    child: Padding(padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.memory, size: 30, color: _accent),
          SizedBox(width: 12),
          Expanded(child: Text('Live Editor · офлайн-игры',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 18),
        Text(Platform.isAndroid
            ? 'Обычный Android APK не получает доступ к памяти другого приложения. '
              'Без root, специальной отладочной сборки или интеграции с самой игрой '
              'изменение значений в реальном времени недоступно.'
            : 'Первый этап: определение запущенных процессов. '
              'Сканирование и изменение памяти пока не реализованы. '
              'Защиту сетевых игр и античит обходить не будем.',
          style: const TextStyle(color: _muted, height: 1.5)),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _loading || !Platform.isWindows ? null : _listProcesses,
            icon: const Icon(Icons.manage_search),
            label: const Text('Найти запущенные процессы (Windows)')),
        const SizedBox(height: 14),
        if (_runningProcesses.isNotEmpty) Expanded(child: ListView.builder(
          itemCount: _runningProcesses.length,
          itemBuilder: (_, i) => ListTile(dense: true,
            leading: const Icon(Icons.desktop_windows_outlined, color: _muted),
            title: Text(_runningProcesses[i], style: const TextStyle(fontSize: 12))))),
      ]),
    ),
  );

  Widget _statusBar() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    decoration: const BoxDecoration(border: Border(top: BorderSide(
        color: Color(0xFF2A2739)))),
    child: Row(children: [
      if (_loading) const Padding(padding: EdgeInsets.only(right: 10),
          child: SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2))),
      Expanded(child: Text(_state, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: _muted))),
      const Text('v0.2.0', style: TextStyle(fontSize: 11, color: _muted)),
    ]),
  );

  Widget _archiveBrowser({required bool narrow}) {
    final archive = _archive!;
    final entry = _archiveEntry;
    final preview = _archiveEntryBytes;
    final list = ListView.builder(itemCount: archive.entries.length,
      itemBuilder: (context, index) {
        final item = archive.entries[index];
        return ListTile(dense: true,
          selected: item.path == entry?.path,
          leading: const Icon(Icons.description_outlined, size: 19),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(item.path, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10)),
          trailing: Text(_formatSize(item.size),
            style: const TextStyle(fontSize: 10)),
          onTap: () {
            try {
              final bytes = archive.read(item);
              setState(() { _archiveEntry = item; _archiveEntryBytes = bytes; });
            } catch (error) {
              _message('Не удалось открыть элемент ZIP: $error');
            }
          });
      });
    final details = preview == null
        ? _emptyMessage(Icons.inventory_2_outlined,
            'ZIP распознан для просмотра',
            'Выбери файл из списка. Содержимое доступно только для чтения.')
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.all(10),
              child: Text('${entry?.path ?? ''} · ${identifyFile(preview)}',
                maxLines: 2, style: const TextStyle(fontSize: 11, color: _accent))),
            Expanded(child: _isImageBytes(preview)
              ? InteractiveViewer(child: Image.memory(preview,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text('Неизвестный формат изображения'))))
              : SingleChildScrollView(padding: const EdgeInsets.all(12),
                child: SelectableText(decodeEditableText(preview) ??
                  hexPreview(preview), style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11)))),
          ]);
    return Column(children: [
      const Padding(padding: EdgeInsets.all(10),
        child: Text('ZIP / APK / OBB · только просмотр, не дешифрование',
          style: TextStyle(fontSize: 11, color: _muted))),
      Expanded(child: narrow
        ? Column(children: [
            Expanded(flex: 3, child: list),
            const Divider(height: 2),
            Expanded(flex: 2, child: details),
          ])
        : Row(children: [
            Expanded(flex: 2, child: list),
            const VerticalDivider(width: 2),
            Expanded(flex: 3, child: details),
          ])),
    ]);
  }

  bool _isImageBytes(Uint8List bytes) => const {'PNG', 'JPEG'}
      .contains(identifyFile(bytes));

  Widget _emptyMessage(IconData icon, String title, String detail) => Center(
    child: Padding(padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: _muted),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _muted, height: 1.5)),
      ]),
    ),
  );

  IconData _fileIcon(GameFile f) {
    if (f.isImage) return Icons.image_outlined;
    if (f.isLocalization) return Icons.translate;
    if (f.isSave) return Icons.save_outlined;
    if (f.isJson) return Icons.data_object;
    if (f.isZipCandidate || const {'.pak', '.bundle', '.unity3d'}
        .contains(f.extension)) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}
