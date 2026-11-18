/// Android launchable app selected by the user. Selecting a package does not
/// grant access to that app's private data.
class InstalledGameApp {
  const InstalledGameApp({
    required this.packageName,
    required this.label,
    this.isGame = false,
  });

  final String packageName;
  final String label;
  final bool isGame;

  String get virtualFolder => Uri(
        scheme: 'ehtid-app',
        host: packageName,
        queryParameters: {'label': label},
      ).toString();

  static InstalledGameApp fromVirtualFolder(String folder) {
    final uri = Uri.parse(folder);
    final package = uri.host;
    if (uri.scheme != 'ehtid-app' ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(?:\.[a-zA-Z0-9_]+)+$')
            .hasMatch(package)) {
      throw const FormatException('Неверный идентификатор приложения');
    }
    return InstalledGameApp(
      packageName: package,
      label: uri.queryParameters['label'] ?? package,
    );
  }
}

/// Matches *only files inside user-granted SAF trees*, never private game data.
/// A match is a path/filename hint, not proof that a file is a valid game save.
class AndroidAppSaveDiscovery {
  static bool matches({
    required InstalledGameApp app,
    required String treeUri,
    required String relativePath,
  }) {
    final parsed = Uri.tryParse(treeUri);
    if (parsed?.scheme != 'content') return false;
    final rootPath = parsed!.pathSegments.isEmpty
        ? ''
        : parsed.pathSegments.last;
    return matchesPath(app, rootPath) || matchesPath(app, relativePath);
  }

  static bool matchesPath(InstalledGameApp app, String path) {
    final lower = path.toLowerCase().replaceAll('\\', '/');
    final pkg = app.packageName.toLowerCase();
    // Package name must be a whole segment/token, not e.g. com.foo.fake.
    if (RegExp(r'(^|[^a-z0-9_.])' + RegExp.escape(pkg) + r'($|[^a-z0-9_.])')
        .hasMatch(lower)) {
      return true;
    }
    final words = app.label.toLowerCase()
        .split(RegExp(r'[^a-zа-яё0-9]+'))
        .where((part) => part.isNotEmpty).toList();
    final names = <String>{};
    final full = _normalize(app.label.toLowerCase());
    if (full.length >= 5) names.add(full);
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.length >= 6 && !const {
        'android', 'mobile', 'online', 'edition', 'games',
        'launcher', 'official',
      }.contains(word)) names.add(word);
      if (i + 1 < words.length) {
        final pair = _normalize(word + words[i + 1]);
        if (pair.length >= 6) names.add(pair);
      }
    }
    // Check individual directory/file segments. Substring-matching the whole
    // path would incorrectly associate com.foo.game.beta with com.foo.game.
    for (final segment in lower.split('/')) {
      final normalized = _normalize(segment);
      for (final name in names) {
        if (normalized == name) return true;
        if (normalized.startsWith(name) && const [
          'save', 'saves', 'data', 'files', 'profile', 'profiles',
          'slot', 'slots', 'game', 'games',
        ].any((suffix) => normalized.substring(name.length)
            .startsWith(suffix))) {
          return true;
        }
      }
    }
    return false;
  }

  static String _normalize(String input) =>
      input.replaceAll(RegExp(r'[^a-zа-яё0-9]'), '');
}
