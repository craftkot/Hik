import 'package:flutter/material.dart';

import '../core/storage_service.dart';

/// Android 11+ all-files access is a user-controlled special permission,
/// not a normal runtime permission and not an Android sandbox bypass.
/// Keep the SAF editor available when the user declines.
class AndroidAllFilesAccessBanner extends StatefulWidget {
  const AndroidAllFilesAccessBanner({
    super.key,
    required this.storage,
  });

  final AndroidGameStorage storage;

  @override
  State<AndroidAllFilesAccessBanner> createState() =>
      _AndroidAllFilesAccessBannerState();
}

class _AndroidAllFilesAccessBannerState
    extends State<AndroidAllFilesAccessBanner>
    with WidgetsBindingObserver {
  AndroidAllFilesAccessStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await widget.storage.allFilesAccessStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() =>
          _status = const AndroidAllFilesAccessStatus(
            supported: false, granted: false, sdk: 0));
    }
  }

  Future<void> _ask() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.storage.requestAllFilesAccess();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть настройки: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.supported || status.granted) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Material(
        borderRadius: BorderRadius.circular(13),
        color: const Color(0xFF29213C),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.folder_shared_outlined, size: 18,
                  color: Color(0xFFCAA9FF)),
                SizedBox(width: 8),
                Expanded(child: Text('Доступ ко всем файлам',
                  style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 4),
              const Text('Для поиска и редактирования общих файлов игр. '
                  'Разрешение включается вручную в настройках Android. '
                  'Закрытые каталоги других приложений всё равно недоступны.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFD1C9E6))),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _ask,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(_busy ? 'Открываем…' : 'Выдать разрешение'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
