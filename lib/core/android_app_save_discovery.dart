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
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(?:\\.[a-zA-Z0-9_]+)+$')
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
    final lower = path.toLowerCase().replaceAll('\\\\', '/');
    final pkg = app.packageName.toLowerCase();
    // Package name must be a whole segment/token, not e.g. com.foo.fake.
    if (RegExp('(^|[^a-z0-9_.])${RegExp.escape(pkg)}(\\$|[^a-z0-9_.])')
        .hasMatch(lower)) {
      return true;
    }
    final normalizedPath = _normalize(lower);
    final normalizedLabel = _normalize(app.label.toLowerCase());
    if (normalizedLabel.length >= 5 &&
        normalizedPath.contains(normalizedLabel)) {
      return true;
    }
    final meaningful = app.label.toLowerCase().split(RegExp(r'[^a-zа-яё0-9]+'))
        .where((part) => part.length >= 6 && !const {
          'android', 'mobile', 'online', 'edition', 'games',
          'launcher', 'official',
        }.contains(part));
    return meaningful.any((part) => normalizedPath.contains(_normalize(part)));
  }

  static String _normalize(String input) =>
      input.replaceAll(RegExp(r'[^a-zа-яё0-9]'), '');
}
