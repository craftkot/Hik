import 'package:flutter/material.dart';

/// Game-first Windows dashboard. The actual editors stay in the main app;
/// this widget only offers clearly labeled entry points.
class WindowsGameHub extends StatelessWidget {
  const WindowsGameHub({
    super.key,
    required this.folder,
    required this.gameName,
    required this.engine,
    required this.fileCount,
    required this.busy,
    required this.onChooseInstalled,
    required this.onChooseFolder,
    required this.onSaves,
    required this.onCheats,
    required this.onTranslation,
    required this.onResources,
    required this.onFindSaves,
  });

  final String? folder;
  final String? gameName;
  final String? engine;
  final int fileCount;
  final bool busy;
  final VoidCallback onChooseInstalled;
  final VoidCallback onChooseFolder;
  final VoidCallback onSaves;
  final VoidCallback onCheats;
  final VoidCallback onTranslation;
  final VoidCallback onResources;
  final VoidCallback onFindSaves;

  Widget _action(IconData icon, String title, String detail,
      VoidCallback onPressed) => SizedBox(
    width: 285, height: 165,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFB68BFF), size: 28),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(child: Text(detail,
                  style: const TextStyle(color: Color(0xFFAAA5BE),
                      fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: ListView(children: [
        const SizedBox(height: 28),
        Icon(folder == null ? Icons.sports_esports_outlined :
            Icons.tune_rounded, color: const Color(0xFFB68BFF), size: 60),
        const SizedBox(height: 15),
        Text(folder == null ? 'Выбери игру' :
            (gameName?.isNotEmpty == true ? gameName! : 'Меню игры'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 29,
              fontWeight: FontWeight.bold)),
        const SizedBox(height: 9),
        Text(folder == null
              ? 'Выбери установленную игру или укажи папку вручную.'
              : 'Выбирай инструмент для работы с этой игрой.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFAAA5BE))),
        const SizedBox(height: 25),
        Wrap(alignment: WrapAlignment.center, spacing: 12,
          runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: busy ? null : onChooseInstalled,
              icon: const Icon(Icons.sports_esports),
              label: const Text('Установленные игры'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onChooseFolder,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Выбрать папку вручную'),
            ),
          ]),
        if (folder != null) ...[
          const SizedBox(height: 24),
          Text(folder!, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11,
                color: Color(0xFFAAA5BE))),
          const SizedBox(height: 12),
          Center(child: Chip(label: Text(
            'Движок: ${engine ?? 'не определён'} · '
            'Файлов: $fileCount'))),
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 12,
            runSpacing: 12, children: [
              _action(Icons.save_as_outlined, 'Сохранения',
                'Деньги, HP, уровень, параметры, бэкапы и откат', onSaves),
              _action(Icons.memory_outlined, 'Читы (соло)',
                'Поиск и изменение чисел в памяти офлайн-игр', onCheats),
              _action(Icons.translate, 'Перевод',
                'Редактирование доступных текстов игры', onTranslation),
              _action(Icons.folder_zip_outlined, 'Ресурсы',
                'Просмотр файлов, архивов и предзагрузок', onResources),
            ]),
          const SizedBox(height: 16),
          Center(child: TextButton.icon(
            onPressed: busy ? null : onFindSaves,
            icon: const Icon(Icons.travel_explore_outlined),
            label: const Text('Найти сейвы в AppData и Documents'),
          )),
        ],
      ]),
    ),
  );
}
