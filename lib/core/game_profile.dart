import 'game_file.dart';

/// Best-effort, read-only engine hints. A detected engine does NOT imply that
/// its proprietary bundles or save formats can be decoded.
class GameProfile {
  const GameProfile({required this.engine, required this.hints,
    required this.saveCandidates, required this.localeCandidates});

  final String engine;
  final List<String> hints;
  final int saveCandidates;
  final int localeCandidates;
}

GameProfile detectGameProfile(List<GameFile> files) {
  final paths = files.map((f) => f.relativePath.toLowerCase().replaceAll('\\', '/')).toList();
  final hints = <String>[];
  String engine = 'Не определён';
  if (paths.any((p) => p.endsWith('globalgamemanagers') ||
      p.endsWith('unityplayer.dll') || p.contains('/managed/assembly-csharp.dll'))) {
    engine = 'Unity';
    hints.add('Структура файлов похожа на Unity');
  } else if (paths.any((p) => p.endsWith('.pak') && p.contains('/content/paks/')) ||
      paths.any((p) => p.endsWith('ue4game.exe') || p.endsWith('unrealengine.exe'))) {
    engine = 'Unreal Engine';
    hints.add('Обнаружены типичные пути Unreal');
  } else if (paths.any((p) => p.endsWith('data.win') || p.endsWith('game.unx'))) {
    engine = 'GameMaker';
    hints.add('Обнаружены контейнеры GameMaker');
  } else if (paths.any((p) => p.endsWith('project.godot') ||
      p.endsWith('data.pck') || p.endsWith('game.pck'))) {
    engine = 'Godot';
    hints.add('Обнаружены файлы Godot');
  } else if (paths.any((p) => p.endsWith('renpy/common/00library.rpy') ||
      p.contains('/renpy/') || p.endsWith('.rpa'))) {
    engine = 'Ren\'Py';
    hints.add('Обнаружены файлы Ren\'Py');
  }
  final saves = files.where((f) => f.isSave).length;
  final locales = files.where((f) => f.isLocalization).length;
  if (saves > 0) hints.add('Возможные сохранения: $saves');
  if (locales > 0) hints.add('Возможные файлы перевода: $locales');
  if (engine == 'Не определён') {
    hints.insert(0, 'Формат игры пока не распознан; доступны общие операции с файлами');
  }
  return GameProfile(engine: engine, hints: List.unmodifiable(hints),
    saveCandidates: saves, localeCandidates: locales);
}
