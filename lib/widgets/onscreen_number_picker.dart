import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/screen_number_ocr.dart';
import '../core/windows_screen_capture.dart';

/// First stage of point-and-edit:
/// screenshot -> click number -> OCR suggestion or manual confirmation ->
/// search for the numeric value in accessible game files.
/// This dialog cannot attach to or modify another process.
class OnScreenNumberPicker extends StatefulWidget {
  const OnScreenNumberPicker({super.key});

  @override
  State<OnScreenNumberPicker> createState() => _OnScreenNumberPickerState();
}

class _OnScreenNumberPickerState extends State<OnScreenNumberPicker> {
  final _value = TextEditingController();
  Uint8List? _image;
  int _imageWidth = 1;
  int _imageHeight = 1;
  double? _pickedX;
  double? _pickedY;
  List<ScreenNumberToken> _tokens = const [];
  bool _loading = false;
  String _status = 'Сделай снимок или выбери изображение экрана игры.';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _openScreenshot() async {
    if (_loading) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (selection == null || selection.files.isEmpty) return;
      final file = selection.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw StateError('Изображение не прочитано');
      await _loadImage(bytes);
    } catch (error) {
      _setError('Не удалось открыть скриншот: $error');
    }
  }

  Future<void> _takeScreenshot() async {
    if (!Platform.isWindows || _loading) return;
    setState(() {
      _loading = true;
      _status = 'Переключись в игру — снимок рабочего стола через 4 секунды';
    });
    try {
      final bytes = await WindowsScreenCapture.captureAfter();
      await _loadImage(bytes);
    } catch (error) {
      _setError('Захват экрана не удался: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadImage(Uint8List bytes) async {
    if (bytes.length > 35 * 1024 * 1024) {
      throw StateError('Слишком большой скриншот (лимит 35 МиБ)');
    }
    if (mounted) setState(() {
      _loading = true;
      _status = 'Читаю изображение и пробую локальное распознавание цифр…';
      _tokens = const [];
    });
    try {
      final decoded = await ui.decodeImageFromList(bytes);
      final width = decoded.width;
      final height = decoded.height;
      decoded.dispose();
      if (width < 1 || height < 1 || width > 12000 || height > 12000) {
        throw StateError('Неподдерживаемое разрешение снимка');
      }
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _imageWidth = width;
        _imageHeight = height;
        _pickedX = null;
        _pickedY = null;
      });
      final tsv = await LocalScreenOcr.recognizeTsv(bytes);
      if (!mounted) return;
      setState(() {
        _tokens = tsv == null ? const [] : ScreenNumberOcr.parseTsv(tsv);
        _status = tsv == null
          ? 'Локальный OCR не найден. Нажми на число и введи его вручную.'
          : 'Распознано чисел: ${_tokens.length}. Нажми на число на снимке.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String error) {
    if (mounted) setState(() {
      _status = error;
      _loading = false;
    });
  }

  void _tapImage(TapDownDetails tap, double displayWidth,
      double displayHeight) {
    if (_image == null) return;
    final x = (tap.localPosition.dx / displayWidth * _imageWidth)
        .clamp(0.0, _imageWidth.toDouble());
    final y = (tap.localPosition.dy / displayHeight * _imageHeight)
        .clamp(0.0, _imageHeight.toDouble());
    final found = ScreenNumberOcr.atPoint(_tokens, x, y);
    setState(() {
      _pickedX = x;
      _pickedY = y;
      if (found != null) {
        _value.text = found.value;
        _status = 'OCR: ${found.raw}. Проверь значение перед поиском.';
      } else {
        _status = 'Число здесь не распознано. Введи показанное в игре '
            'значение вручную.';
      }
    });
  }

  void _confirm() {
    final value = _value.text.trim();
    if (!RegExp(r'^[+-]?\d{1,12}(?:[.,]\d{1,6})?$').hasMatch(value)) {
      _setError('Введи одно числовое значение, например 100 или 12.5');
      return;
    }
    Navigator.of(context).pop(value.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _image;
    return AlertDialog(
      title: const Text('Выбрать число на экране игры'),
      content: SizedBox(
        width: 750,
        height: MediaQuery.sizeOf(context).height * 0.66,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Windows: нажми «Снимок через 4 сек.» и переключись '
              'в одиночную игру. Android: выбери готовый скриншот. '
              'Потом нажми на цифру и проверь её значение.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (Platform.isWindows)
                OutlinedButton.icon(
                  onPressed: _loading ? null : _takeScreenshot,
                  icon: const Icon(Icons.screenshot_monitor),
                  label: const Text('Снимок через 4 сек.'),
                ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _openScreenshot,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Открыть скриншот'),
              ),
            ]),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(),
            Text(_status, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 10),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(color: Colors.black26,
                child: bytes == null
                  ? const Center(child: Text('Здесь появится экран игры'))
                  : LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final height = width * _imageHeight / _imageWidth;
                      return InteractiveViewer(
                        constrained: false,
                        minScale: 0.25,
                        maxScale: 8,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (tap) => _tapImage(tap, width, height),
                            child: Stack(children: [
                              Image.memory(bytes,
                                width: width, height: height,
                                fit: BoxFit.fill),
                              if (_pickedX != null && _pickedY != null)
                                Positioned(
                                  left: _pickedX! / _imageWidth * width - 12,
                                  top: _pickedY! / _imageHeight * height - 12,
                                  child: const IgnorePointer(
                                    child: Icon(Icons.control_camera,
                                      color: Colors.amber, size: 24)),
                                ),
                            ]),
                          ),
                        ),
                      );
                    }),
              ),
            )),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              enabled: !_loading,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Найденное число (можно исправить)',
                hintText: 'Например: 125',
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 8),
            const Text('Пока это выбор числа по снимку, а не чтение памяти '
              'игры. Значение будет использовано для поиска в доступных '
              'файлах. Изменение сейва отдельно подтверждается и '
              'делается с резервной копией.',
              style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: _loading ? null : _confirm,
          icon: const Icon(Icons.manage_search),
          label: const Text('Найти значение'),
        ),
      ],
    );
  }
}
