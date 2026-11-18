import 'package:flutter/material.dart';

import '../core/android_app_save_discovery.dart';

/// An in-app picker of launcher-visible packages. Selecting an app does not
/// grant Android filesystem access to its private files.
Future<InstalledGameApp?> showInstalledAppPicker(
    BuildContext context, List<InstalledGameApp> apps, {
    Future<void> Function()? onChooseFolder,
  }) async {
  var manual = false;
  final selected = await showModalBottomSheet<InstalledGameApp>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF181625),
    showDragHandle: true,
    builder: (_) => InstalledAppPicker(
      apps: apps,
      onManualFolder: () {
        manual = true;
        Navigator.of(context).pop();
      },
    ),
  );
  if (manual) {
    await onChooseFolder?.call();
    return null;
  }
  return selected;
}

class InstalledAppPicker extends StatefulWidget {
  const InstalledAppPicker({super.key, required this.apps,
    this.onManualFolder});

  final List<InstalledGameApp> apps;
  final VoidCallback? onManualFolder;

  @override
  State<InstalledAppPicker> createState() => _InstalledAppPickerState();
}

class _InstalledAppPickerState extends State<InstalledAppPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final search = query.trim().toLowerCase();
    final visible = widget.apps.where((app) =>
        app.label.toLowerCase().contains(search) ||
        app.packageName.toLowerCase().contains(search)).toList();
    return FractionallySizedBox(
      heightFactor: 0.84,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Выбери игру',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 7),
          const Text('Найдём похожие файлы в каталогах, к которым ты уже '
              'предоставил доступ. Закрытые данные других приложений '
              'Android не разрешает читать.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAA5BE))),
          const SizedBox(height: 14),
          TextField(
            autofocus: false,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: 'Название или пакет приложения',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.onManualFolder != null)
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: widget.onManualFolder,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Нет игры? Выбрать папку вручную'),
            )),
          const SizedBox(height: 6),
          Expanded(child: visible.isEmpty
              ? const Center(child: Text('Приложение не найдено'))
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final app = visible[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        app.isGame
                            ? Icons.sports_esports_outlined
                            : Icons.apps_outlined,
                        color: const Color(0xFFB68BFF),
                      ),
                      title: Text(app.label, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(app.packageName, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(app),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}
