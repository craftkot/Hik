import 'package:flutter/material.dart';

import '../core/windows_game_catalog.dart';

/// Searchable desktop installed-game picker. Returns null on cancellation.
Future<DesktopGameEntry?> showWindowsGamePicker(
    BuildContext context, List<DesktopGameEntry> games) async {
  var query = '';
  return showDialog<DesktopGameEntry>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, refresh) {
        final filtered = games.where((game) {
          final needle = query.toLowerCase().trim();
          return game.name.toLowerCase().contains(needle) ||
              game.folder.toLowerCase().contains(needle);
        }).toList();
        return AlertDialog(
          title: const Text('Выбрать установленную игру'),
          content: SizedBox(
            width: 620,
            height: 470,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Название игры или путь…',
                ),
                onChanged: (value) => refresh(() => query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text(
                        'Подходящих игр не найдено.\n'
                        'Можно указать папку игры вручную.',
                        textAlign: TextAlign.center))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final game = filtered[index];
                          return ListTile(
                            leading: const Icon(Icons.sports_esports_outlined),
                            title: Text(game.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${game.source} · ${game.folder}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(dialogContext, game),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
          ],
        );
      },
    ),
  );
}
