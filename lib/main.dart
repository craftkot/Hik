import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/android_app_save_discovery.dart';
import 'core/archive_inspector.dart';
import 'core/binary_save_editor.dart';
import 'core/game_file.dart';
import 'core/game_locale_workflow.dart';
import 'core/game_value_search.dart';
import 'core/game_profile.dart';
import 'core/json_editor.dart';
import 'core/storage_service.dart';
import 'core/save_value_priority.dart';
import 'core/translation_service.dart';
import 'core/windows_save_discovery.dart';
import 'widgets/binary_save_dialog.dart';
import 'widgets/game_wide_search_dialog.dart';
import 'widgets/onscreen_number_picker.dart';
import 'widgets/live_memory_panel.dart';
import 'widgets/installed_app_picker.dart';
import 'widgets/android_floating_panel.dart';
import 'widgets/android_game_translation_panel.dart';
import 'widgets/android_all_files_access_banner.dart';
import 'widgets/android_container_lab.dart';
import 'widgets/desktop_backup_restore_dialog.dart';
import 'widgets/save_field_browser.dart';

void main() => runApp(const GameLabApp());

const _background = Color(0xFF0A0A12);
const _panel = Color(0xFF181625);
const _panelLight = Color(0xFF222035);
const _accent = Color(0xFFB68BFF);
const _cyanAccent = Color(0xFF5EE9F5);
const _muted = Color(0xFFAAA5BE);

enum Workspace { preloads, saves, localize, cheats, container }

extension WorkspaceInfo on Workspace {
  String get title => switch (this) {
    Workspace.preloads => 'Предзагрузки',
    Workspace.saves => 'Редактор сохранений',
    Workspace.localize => 'Перевод игры',
    Workspace.cheats => 'Читы (соло)',
    Workspace.container => 'Контейнер игр',
  };
  String get detail => switch (this) {
    Workspace.preloads => 'Просмотр ресурсов и распознанных файлов',
    Workspace.saves => 'Редактирование доступных текстовых сейвов',
    Workspace.localize => 'Локализация без изменения ключей JSON',
    Workspace.cheats => 'Windows RAM · поиск и изменение значений в офлайн-играх',
    Workspace.container => 'Тест: игры внутри EHTID и импорт APK',
  };
  IconData get icon => switch (this) {
    Workspace.preloads => Icons.folder_zip_outlined,
    Workspace.saves => Icons.save_as_outlined,
    Workspace.localize => Icons.translate,
    Workspace.cheats => Icons.memory_outlined,
    Workspace.container => Icons.inventory_2_outlined,
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
  const GameLabHome({super.key, this.storage});
  final GameStorage? storage;
  @override
  State<GameLabHome> createState() => _GameLabHomeState();
}

class _GameLabHomeState extends State<GameLabHome> with WidgetsBindingObserver {
  late final GameStorage _storage = widget.storage ?? createStorage();
  final TextEditingController _editor = TextEditingController();
  final TextEditingController _query = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();

  Workspace _section = Workspace.preloads;
  String? _folder;
  InstalledGameApp? _selectedApp;
  String? _overlayNumber;
  final List<String> _extraFolders = [];
  // Only explicitly confirmed save-discovery directories get unfiltered
  // save listings. Installation folders still use the normal heuristics.
  final Set<String> _windowsFoundSaveRoots = {};
  Set<String> _windowsFoundSaveFileIds = {};
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
  String _state = 'Выбери игру (Android) или папку, чтобы начать';
  GameProfile? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _receiveOverlayNumber();
      });
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _editor.dispose();
    _query.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _receiveOverlayNumber();
    }
  }

  Future<void> _receiveOverlayNumber() async {
    if (!mounted || !Platform.isAndroid) return;
    try {
      const channel = MethodChannel('ehtid.gamelab/overlay');
      final value = await channel.invokeMethod<String>('takeNumber');
      if (!mounted || value == null || value.isEmpty) return;
      if (!RegExp(r'^[+-]?\d{1,12}(?:\.\d{1,6})?$').hasMatch(value)) return;
      setState(() {
        _overlayNumber = value;
        if (!_dirty) _section = Workspace.cheats;
        _state = 'Из плавающего окна получено число: $value';
      });
    } catch (_) {
      // Overlay is optional; the file editor continues working.
    }
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() => _state = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message), duration: const Duration(seconds: 4)));
  }

  Future<void> _chooseInstalledApp() async {
    if (!Platform.isAndroid || _loading ||
        _storage is! AndroidGameStorage) return;
    if (_dirty) {
      _message('Сначала сохрани или отмени правки перед сменой игры');
      return;
    }
    try {
      final apps = await _storage.listInstalledApps();
      if (!mounted) return;
      if (apps.isEmpty) {
        _message('Android не показывает установленные игры. '
            'Откроем ручной выбор папки.');
        await _chooseFolder();
        return;
      }
      final chosen = await showInstalledAppPicker(context, apps,
          onChooseFolder: _chooseFolder);
      if (!mounted || chosen == null) return;
      _query.clear();
      setState(() {
        _selectedApp = chosen;
        _folder = chosen.virtualFolder;
        _extraFolders.clear();
        // Choosing a game from Translator must stay in Translator.
        _section = _section == Workspace.localize
            ? Workspace.localize : Workspace.saves;
        _selected = null; _bytes = null; _originalText = null;
        _mobilePreview = false; _files = []; _profile = null;
        _archive = null; _archiveEntry = null; _archiveEntryBytes = null;
      });
      await _scan();
      if (mounted && _files.isEmpty) {
        _message('Файлов игры пока не нашли. Нажми значок папки, '
            'чтобы один раз разрешить доступ к каталогу игры.');
      }
    } catch (error) {
      _message('Не удалось получить список приложений: $error');
    }
  }

  Future<void> _grantAndroidGameFolder() async {
    final selected = _selectedApp;
    if (selected == null || _storage is! AndroidGameStorage) {
      await _chooseFolder();
      return;
    }
    if (_dirty) {
      _message('Сначала сохрани или отмени правки');
      return;
    }
    try {
      // The system picker provides explicit access to one directory, which
      // is then safely remembered for this particular game.
      final folder = await _storage.chooseFolder();
      if (folder == null || !mounted) return;
      await _storage.linkFolderToApp(selected, folder);
      if (!mounted) return;
      await _scan();
      if (mounted && _files.isEmpty) {
        _message('Папка доступна, но файлов не найдено. '
            'Попробуй другую общую папку игры.');
      }
    } catch (error) {
      _message('Не удалось связать папку с игрой: $error');
    }
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
      setState(() { _folder = folder; _selectedApp = null; _extraFolders.clear();
        _windowsFoundSaveRoots.clear();
        _windowsFoundSaveFileIds.clear();
        _query.clear();
        _selected = null; _bytes = null;
        _mobilePreview = false; _files = []; _profile = null;
        _archive = null; _archiveEntry = null; _archiveEntryBytes = null; });
      await _scan();
    } catch (error) { _message('Не удалось открыть папку: $error'); }
  }


  Future<void> _addFolder() async {
    if (_folder == null || _loading) return;
    if (_dirty) {
      _message('Сначала сохрани или отмени правки');
      return;
    }
    if (_extraFolders.length >= 5) {
      _message('Для одного поиска можно выбрать до 6 папок');
      return;
    }
    try {
      final folder = await _storage.chooseFolder();
      if (folder == null) return;
      if (folder == _folder || _extraFolders.contains(folder)) {
        _message('Эта папка уже добавлена');
        return;
      }
      if (!mounted) return;
      setState(() => _extraFolders.add(folder));
      await _scan();
    } catch (error) {
      _message('Не удалось добавить папку: $error');
    }
  }


  Future<void> _findWindowsSaveFolders() async {
    if (!Platform.isWindows || _loading) return;
    if (_dirty) {
      _message('Сначала сохрани или отмени правки');
      return;
    }
    if (_folder != null && _extraFolders.length >= 5) {
      _message('Уже подключены 6 папок. Удали лишние перед поиском.');
      return;
    }

    final controller = TextEditingController(
      text: _folder == null ? '' :
          WindowsSaveDiscovery.suggestedGameNameFromPath(_folder!),
    );
    String? gameName;
    try {
      gameName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Найти сейвы по названию игры'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ищем только стандартные каталоги сохранений '
                    'твоего профиля Windows, не весь диск. '
                    'Можно начать даже без папки установленной игры.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 90,
                  decoration: const InputDecoration(
                    labelText: 'Название игры',
                    hintText: 'Например: Stardew Valley',
                  ),
                  onSubmitted: (value) =>
                      Navigator.pop(dialogContext, value.trim()),
                ),
                const Text('AppData · LocalLow · Saved Games · Documents · '
                    'OneDrive Documents',
                    style: TextStyle(fontSize: 11, color: _muted)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Искать сейвы'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || gameName == null) return;
    final normalized = WindowsSaveDiscovery.normalizedGameName(gameName);
    if (normalized.length < 3) {
      _message('Введи название игры не короче трёх символов');
      return;
    }

    setState(() {
      _loading = true;
      _state = 'Ищем сохранения: $gameName…';
    });
    List<String> matches;
    try {
      matches = await WindowsSaveDiscovery.discoverByName(gameName);
    } catch (error) {
      _message('Поиск папок сохранений не удался: $error');
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;

    String key(String path) => path.replaceAll('\\', '/').toLowerCase();
    final existing = <String>{
      if (_folder != null) key(_folder!),
      for (final path in _extraFolders) key(path),
    };
    final freeSlots = _folder == null
        ? 6 : 5 - _extraFolders.length;
    final additions = matches
        .where((path) => !existing.contains(key(path)))
        .take(freeSlots).toList();
    if (additions.isEmpty) {
      _message('Для «$gameName» новых папок сейвов не найдено. '
          'Можно открыть папку вручную.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Найденные папки сохранений Windows'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('«$gameName»: найдено ${additions.length} каталогов. '
                    'Подключить их к редактору? Содержимое ещё не изменялось.'),
                const SizedBox(height: 12),
                for (final path in additions) Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: SelectableText(path, style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Подключить папки')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      if (_folder == null) {
        _folder = additions.first;
        _extraFolders.addAll(additions.skip(1));
        _selected = null;
        _bytes = null;
        _originalText = null;
        _archive = null;
        _archiveEntry = null;
        _archiveEntryBytes = null;
        _profile = null;
        _mobilePreview = false;
        _query.clear();
      } else {
        _extraFolders.addAll(additions);
      }
      _windowsFoundSaveRoots.addAll(additions);
      _section = Workspace.saves;
    });
    await _scan();
  }

  Future<void> _chooseOnScreenNumber() async {
    if (_folder == null) {
      _message('Выбери папку игры: найденное число нужно будет искать в файлах');
      return;
    }
    if (_dirty || _loading) {
      _message('Сначала закончи текущую правку');
      return;
    }
    final number = await showDialog<String>(
      context: context,
      builder: (_) => const OnScreenNumberPicker(),
    );
    if (!mounted || number == null) return;
    await _showGameWideSearch(initialQuery: number);
  }

  Future<void> _showGameWideSearch({String? initialQuery}) async {
    if (_folder == null || _loading) {
      _message('Сначала выбери папку игры');
      return;
    }
    if (_dirty) {
      _message('Сначала сохрани или отмени правки');
      return;
    }
    final hit = await showDialog<GameValueHit>(
      context: context,
      builder: (_) => GameWideSearchDialog(
        storage: _storage,
        files: List<GameFile>.of(_files),
        folderCount: 1 + _extraFolders.length,
        initialQuery: initialQuery,
      ),
    );
    if (!mounted || hit == null) return;
    if (_section == Workspace.cheats) {
      setState(() => _section = Workspace.saves);
    }
    final opened = await _openFile(hit.file);
    if (!mounted || !opened || _selected?.id != hit.file.id) return;
    if (hit.numericFormat != null && _bytes != null &&
        _originalText == null && !_loading &&
        GameValueSearch.matchesBinaryHit(hit, _bytes!)) {
      await _editFoundBinaryNumber(hit);
    }
  }

  Future<void> _editFoundBinaryNumber(GameValueHit hit) async {
    final source = _bytes;
    final format = hit.numericFormat;
    if (source == null || format == null || _dirty) return;
    final controller = TextEditingController(text: hit.matchedValue);
    String? replacement;
    try {
      replacement = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Изменить найденное число?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hit.file.relativePath,
                style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              Text('${hit.format} · ${hit.location} · '
                'значение ${hit.matchedValue}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
                decoration: const InputDecoration(labelText: 'Новое число'),
              ),
              const SizedBox(height: 12),
              const Text('Проверь, что это нужное поле HP/маны/валюты, '
                  'а не случайное совпадение.',
                style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
            FilledButton(onPressed: () =>
                Navigator.pop(dialogContext, controller.text),
              child: const Text('Проверить изменение')),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (!mounted || replacement == null) return;
    await _applyBinaryPatch(hit.file, source,
      NumericPatchRequest(
        offset: hit.offset,
        format: format,
        expected: hit.matchedValue,
        replacement: replacement,
      ),
    );
  }

  Future<void> _scan() async {
    final folder = _folder;
    if (folder == null || _loading) return;
    setState(() { _loading = true; _state = 'Сканирование файлов…'; });
    try {
      final roots = [folder, ..._extraFolders];
      final found = <GameFile>[];
      final ids = <String>{};
      final foundSaveFileIds = <String>{};
      final errors = <String>[];
      for (var i = 0; i < roots.length; i++) {
        try {
          final batch = await _storage.scan(roots[i]);
          for (final item in batch) {
            if (!ids.add(item.id)) continue;
            if (Platform.isWindows &&
                _windowsFoundSaveRoots.contains(roots[i])) {
              foundSaveFileIds.add(item.id);
            }
            found.add(GameFile(
              id: item.id, name: item.name, size: item.size,
              relativePath: roots.length == 1
                  ? item.relativePath
                  : 'Папка ${i + 1}/${item.relativePath}',
            ));
          }
        } catch (error) {
          errors.add('Папка ${i + 1}: $error');
        }
      }
      if (errors.length == roots.length) {
        throw StateError('Ни одна папка не прочитана: ${errors.join('; ')}');
      }
      found.sort((a, b) => a.relativePath.toLowerCase()
          .compareTo(b.relativePath.toLowerCase()));
      if (!mounted) return;
      setState(() { _files = found;
        _windowsFoundSaveFileIds = foundSaveFileIds;
        _profile = detectGameProfile(found);
        _selected = null; _bytes = null; _originalText = null;
        _mobilePreview = false;
        _archive = null; _archiveEntry = null; _archiveEntryBytes = null;
        _state = _selectedApp != null
            ? 'Игра: ${_selectedApp!.label} · кандидатов: ${found.length}'
                ' (только в разрешённых каталогах)'
            : 'Найдено ${found.length} файлов из ${roots.length} папок'
                ' · движок: ${_profile?.engine ?? 'неизвестен'}'
                '${errors.isNotEmpty ? ' · ошибок папок: ${errors.length}' : ''}';
      });
    } catch (error) { _message('Ошибка сканирования: $error'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  List<GameFile> get _visibleFiles {
    final search = _query.text.trim().toLowerCase();
    final visible = _files.where((f) {
      final inSection = switch (_section) {
        Workspace.preloads => f.isLikelyPreload || (!f.isSave && !f.isLocalization),
        // In Android manual-folder mode, unusual save extensions are common.
        // Show every accessible file and let the user inspect it.
        Workspace.saves => (Platform.isAndroid && _folder != null) ||
            f.isSave ||
            (Platform.isWindows && _windowsFoundSaveFileIds.contains(f.id) &&
              !f.isImage && !f.isZipCandidate),
        Workspace.localize => f.isLocalization ||
            GameLocaleCandidates.canTranslate(f),
        Workspace.cheats => false,
        Workspace.container => false,
      };
      return inSection && f.relativePath.toLowerCase().contains(search);
    }).toList();
    if (_section != Workspace.saves) return visible;
    // Only the filename is known before opening; prioritize likely save
    // files but don't claim their values are verified.
    final positioned = visible.asMap().entries.toList();
    positioned.sort((a, b) {
      final rank = SaveValuePriority.fromName(a.value.name).priority
          .compareTo(SaveValuePriority.fromName(b.value.name).priority);
      return rank != 0 ? rank : a.key.compareTo(b.key);
    });
    return positioned.map((item) => item.value).toList();
  }

  Future<bool> _openFile(GameFile file) async {
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
      if (abandon != true) return false;
    }
    if (!mounted) return false;
    setState(() {
      _loading = true;
      _state = 'Чтение ${file.name}…';
      // Invalidate previously opened bytes before the next read. A failure
      // must not leave stale data or a stale write action in the editor.
      _selected = null;
      _bytes = null;
      _archive = null;
      _archiveEntry = null;
      _archiveEntryBytes = null;
      _originalText = null;
      _editor.clear();
      _dirty = false;
      _mobilePreview = false;
    });
    try {
      final isLarge = file.size > maxEditableBytes;
      final bytes = isLarge
          ? await _storage.readPreview(file) : await _storage.read(file);
      final inspector = !isLarge && ArchiveInspector.isZip(bytes)
          ? ArchiveInspector.open(bytes) : null;
      final decoded = file.isImage || isLarge || inspector != null
          ? null : decodeEditableText(bytes);
      if (!mounted) return false;
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
      return true;
    } catch (error) {
      _message('Не удалось прочесть файл: $error');
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      final backup = await _storage.writeWithBackup(
          selected, bytes, expected: original);
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


  Future<void> _restoreOpenedSave() async {
    final selected = _selected;
    if (!Platform.isWindows || _loading || _dirty || selected == null ||
        !selected.isSave) return;
    final backupOfCurrent = await showDialog<String>(
      context: context,
      builder: (_) => DesktopBackupRestoreDialog(save: File(selected.id)),
    );
    if (!mounted || backupOfCurrent == null) return;

    // Invalidate the in-memory preview and refresh from the real file.
    // Never continue to display stale bytes after restoration.
    setState(() {
      _selected = null;
      _bytes = null;
      _originalText = null;
      _archive = null;
      _archiveEntry = null;
      _archiveEntryBytes = null;
      _mobilePreview = false;
      _editor.clear();
      _dirty = false;
    });
    await _scan();
    if (!mounted) return;
    final matches = _files.where((file) => file.id == selected.id);
    if (matches.isNotEmpty) {
      await _openFile(matches.first);
    }
    if (mounted) {
      _message('Сейв восстановлен и перечитан. '
          'Копия прежней версии: $backupOfCurrent');
    }
  }

  Future<void> _showBinarySaveEditor() async {
    final file = _selected;
    final original = _bytes;
    if (_loading || file == null || original == null ||
        file.size > maxEditableBytes) return;
    final request = await showDialog<NumericPatchRequest>(
      context: context,
      builder: (_) => BinarySaveDialog(data: original),
    );
    if (!mounted || request == null) return;
    await _applyBinaryPatch(file, original, request);
  }

  Future<void> _applyBinaryPatch(GameFile file, Uint8List original,
      NumericPatchRequest request) async {
    Uint8List patched;
    try {
      if (_selected?.id != file.id || !identical(_bytes, original)) {
        throw StateError('Открытый файл изменился: повтори поиск');
      }
      patched = BinarySaveEditor.patch(original,
        offset: request.offset,
        expected: request.expected,
        replacement: request.replacement,
        format: request.format,
      );
      if (_bytesEqual(original, patched)) {
        _message('Новое значение совпадает со старым — записывать нечего');
        return;
      }
    } catch (error) {
      _message('Не удалось подготовить правку: $error');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Изменить бинарный сейв?'),
        content: Text('Файл: ${file.relativePath}\n'
          'Смещение: 0x${request.offset.toRadixString(16)}\n'
          '${request.format.label}: ${request.expected} → ${request.replacement}\n\n'
          'Сначала создадим резервную копию. '
          'Если игра использует контрольную сумму или шифрование, '
          'отредактированный сейв может не загрузиться. Закрой игру.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Создать копию и применить')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _loading = true);
    try {
      final onDisk = await _storage.read(file);
      if (!_bytesEqual(onDisk, original)) {
        throw StateError('Сейв на диске изменился. Открой его заново.');
      }
      final backup = await _storage.writeWithBackup(
          file, patched, expected: original);
      final verify = await _storage.read(file);
      if (!_bytesEqual(verify, patched)) {
        throw StateError('Проверка записи не прошла. Бэкап: $backup');
      }
      if (!mounted) return;
      setState(() { _bytes = patched; _state = 'Бинарный сейв обновлён'; });
      _message('Записано и проверено. Бэкап: $backup');
    } catch (error) {
      _message('Не удалось применить правку: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showJsonFields() async {
    List<JsonField> fields;
    try {
      final found = listJsonFields(_editor.text,
          max: _section == Workspace.saves ? 2500 : 500);
      fields = _section == Workspace.saves
          ? prioritizeJsonFields(found, max: 2500)
          : found;
    } catch (error) {
      _message('Не удалось прочитать JSON: $error');
      return;
    }
    if (fields.isEmpty) {
      _message('В JSON нет доступных полей');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: SaveFieldBrowser(
            fields: fields,
            isSave: _section == Workspace.saves,
            onClose: () => Navigator.pop(sheetContext),
            onEdit: (field) async {
              final changed = await _editJsonField(field);
              if (changed && sheetContext.mounted) {
                Navigator.pop(sheetContext);
              }
              return changed;
            },
          ),
        ),
      ),
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
            if (Platform.isAndroid && _storage is AndroidGameStorage &&
                _section != Workspace.cheats)
              AndroidAllFilesAccessBanner(
                storage: _storage),
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
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              boxShadow: [BoxShadow(
                color: _accent.withValues(alpha: .22), blurRadius: 20)]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset('assets/brand/logo.png',
                width: 38, height: 38, fit: BoxFit.cover)),
          ),
          if (!compact) const SizedBox(width: 10),
          if (!compact) const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('EHTID', style: TextStyle(
              fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text('GAME LAB  ·  ALPHA', style: TextStyle(fontSize: 9,
                  letterSpacing: 1.2, color: _cyanAccent))],
          )),
        ])),
      const Divider(height: 1, color: Color(0xFF2D293C)),
      const SizedBox(height: 20),
      for (final section in Workspace.values)
        if (Platform.isAndroid || section != Workspace.container)
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
          child: Text(_selectedApp?.label ?? _folder!, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12))))),
      if (Platform.isWindows &&
          (_section == Workspace.saves || _section == Workspace.localize))
        if (compact)
          IconButton(
            onPressed: _loading ? null : _findWindowsSaveFolders,
            tooltip: 'Найти сейвы по названию игры',
            icon: const Icon(Icons.travel_explore_outlined))
        else
          OutlinedButton.icon(
            onPressed: _loading ? null : _findWindowsSaveFolders,
            icon: const Icon(Icons.travel_explore_outlined, size: 17),
            label: const Text('Найти сейвы')),
      if (_folder != null &&
          (_section == Workspace.saves || _section == Workspace.cheats ||
              _section == Workspace.localize)) ...[
        if (Platform.isWindows || (!compact && Platform.isAndroid))
          IconButton(onPressed: _loading ? null : _addFolder,
            tooltip: 'Добавить папку с сейвами',
            icon: const Icon(Icons.create_new_folder_outlined)),
      ],
      if (_section != Workspace.container)
        IconButton(onPressed: _loading || _folder == null ? null : _scan,
          tooltip: 'Повторное сканирование', icon: const Icon(Icons.refresh)),
      if (Platform.isAndroid && _section != Workspace.container) ...[
        if (_selectedApp != null)
          IconButton(
            onPressed: _loading ? null : _grantAndroidGameFolder,
            tooltip: 'Привязать доступную папку к выбранной игре',
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        IconButton(
          onPressed: _loading ? null : _chooseInstalledApp,
          tooltip: 'Выбрать установленную игру (дополнительный способ)',
          icon: const Icon(Icons.sports_esports_outlined),
        ),
      ],
      if (_section != Workspace.container) const SizedBox(width: 6),
      if (_section != Workspace.container)
        FilledButton.icon(
          onPressed: _loading ? null : _chooseFolder,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(compact ? 'Папка' : (Platform.isAndroid
              ? 'Выбрать папку игры' : 'Открыть папку игры'))),
    ]),
  );

  Widget _workspaceView(bool compact) {
    if (Platform.isAndroid && _section == Workspace.container) {
      return const AndroidContainerLab();
    }
    final narrow = compact || MediaQuery.sizeOf(context).width < 1000;
    if (narrow && _mobilePreview && _selected != null) return _detailView(narrow: true);
    if (Platform.isAndroid && _section == Workspace.localize) {
      return Column(children: [
        Flexible(flex: 3, child: SingleChildScrollView(
          child: AndroidGameTranslationPanel(
            storage: _storage,
            files: _files,
            gameName: _selectedApp?.label,
            hasFolder: _folder != null,
            chooseGame: _chooseInstalledApp,
            grantFolder: _selectedApp == null
                ? _chooseFolder : _grantAndroidGameFolder,
            refreshFiles: _scan,
            hasUnsavedChanges: _dirty,
          ),
        )),
        const SizedBox(height: 8),
        Expanded(flex: 2, child: _fileList()),
      ]);
    }
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
              if (_section == Workspace.saves)
                IconButton(
                  tooltip: 'Искать значение во всех выбранных папках',
                  onPressed: _loading || _folder == null ? null : _showGameWideSearch,
                  icon: const Icon(Icons.manage_search, color: _accent),
                ),
            ]),
            const SizedBox(height: 13),
            TextField(controller: _query,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по имени и пути…')),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFF2D293C)),
        Expanded(child: _folder == null
            ? _emptyMessage(Icons.folder_open,
                Platform.isAndroid ? 'Папка игры ещё не выбрана' : 'Папка ещё не выбрана',
                Platform.isAndroid ? 'Нажми «Папка» сверху, чтобы открыть доступные файлы игры.'
                    : 'Открой папку игры — появятся доступные файлы.')
            : items.isEmpty
              ? _emptyMessage(Icons.manage_search,
                  _selectedApp != null ? 'Доступных файлов игры не найдено'
                      : 'Файлы не найдены',
                  _selectedApp != null
                      ? 'Проверены только ранее разрешённые папки. '
                          'Нажми значок папки сверху, чтобы привязать ещё '
                          'один доступный каталог к этой игре. Приватные '
                          'данные Android недоступны.'
                      : Platform.isAndroid
                          ? 'В этой папке нет доступных файлов. Попробуй'
                              ' другую общую папку игры. Android/data'
                              ' и private data могут быть закрыты системой.'
                          : 'Проверь путь или выбери другую функцию слева.')
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
                        trailing: Row(mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_section == Workspace.saves &&
                                SaveValuePriority.fromName(file.name).important)
                              const Tooltip(message: 'Важное по имени файла; содержимое не проверено',
                                child: Icon(Icons.star_outline_rounded,
                                    size: 16, color: _accent)),
                            Text(_formatSize(file.size),
                                style: const TextStyle(fontSize: 10, color: _muted)),
                          ]),
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
    final canBinaryEdit = _section == Workspace.saves && !canEdit &&
        _archive == null && !file.isImage && file.size <= maxEditableBytes;
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
            if (Platform.isWindows && _section == Workspace.saves &&
                file.isSave)
              IconButton(
                tooltip: 'Просмотреть и восстановить резервную копию',
                onPressed: _loading || _dirty ? null : _restoreOpenedSave,
                icon: const Icon(Icons.restore, color: _cyanAccent)),
            if (canUseJsonEditor) IconButton(
              tooltip: 'Редактировать поля JSON',
              onPressed: _showJsonFields,
              icon: const Icon(Icons.account_tree_outlined, color: _accent)),
            if (canBinaryEdit) IconButton(
              tooltip: 'Поиск чисел в бинарном сейве',
              onPressed: _loading ? null : _showBinarySaveEditor,
              icon: const Icon(Icons.manage_search, color: _accent)),
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
                        const Text('HEX-ПРОСМОТР',
                            style: TextStyle(color: _accent,
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        if (canBinaryEdit) Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _showBinarySaveEditor,
                            icon: const Icon(Icons.manage_search),
                            label: const Text('Найти и изменить число в сейве'),
                          ),
                        ),
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
                  : canBinaryEdit
                    ? 'Числовые поля: поиск, выбор смещения, бэкап перед записью'
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

  Widget _cheatsView() => ListView(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF35204D), Color(0xFF19172F), Color(0xFF11303C)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: _accent.withValues(alpha: .24)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset('assets/brand/logo.png',
            width: 78, height: 78, fit: BoxFit.cover)),
        const SizedBox(width: 20),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('EHTID · OFFLINE LAB',
              style: TextStyle(color: _cyanAccent, letterSpacing: 1.6,
                fontSize: 11, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Редактор игры',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            SizedBox(height: 7),
            Text('HP · Мана · Валюта · Локальные сейвы',
              style: TextStyle(color: Color(0xFFD1C9E6), fontSize: 12)),
          ],
        )),
      ]),
    ),
    const SizedBox(height: 16),
    if (Platform.isWindows) const LiveMemoryPanel()
    else AndroidFloatingPanel(
      initialNumber: _overlayNumber,
      onSearch: (number) async {
        if (_folder == null) {
          if (Platform.isAndroid) await _chooseInstalledApp();
          else await _chooseFolder();
        }
        if (!mounted || _folder == null) return;
        await _showGameWideSearch(initialQuery: number);
      },
    ),
    const SizedBox(height: 16),
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF342B4E))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.save_outlined, color: _cyanAccent),
          SizedBox(width: 10),
          Expanded(child: Text('Редактирование сохранений',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 9),
        const Text('Найди число по снимку экрана или во всех выбранных '
          'файлах игры. Перед записью будет создана резервная копия.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 13),
        Wrap(spacing: 9, runSpacing: 9, children: [
          FilledButton.tonalIcon(
            onPressed: _loading || _folder == null
                ? null : _chooseOnScreenNumber,
            icon: const Icon(Icons.touch_app_outlined),
            label: const Text('Число на скриншоте')),
          OutlinedButton.icon(
            onPressed: _loading || _folder == null
                ? null : () => _showGameWideSearch(),
            icon: const Icon(Icons.search),
            label: const Text('Поиск в файлах игры')),
        ]),
        if (_folder == null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(Platform.isAndroid
              ? 'Сначала выбери игру в верхней панели.'
              : 'Сначала выбери папку игры в верхней панели.',
            style: TextStyle(color: _muted, fontSize: 11))),
      ]),
    ),
  ]);

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
      const Text('v0.4.14 α1 · Windows / Android', style: TextStyle(fontSize: 11, color: _cyanAccent)),
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
