import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../models/canvas_settings.dart';

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final _nameController = TextEditingController(text: 'untitled');
  final _widthController = TextEditingController(text: '1920');
  final _heightController = TextEditingController(text: '1080');
  final _resolutionController = TextEditingController(text: '72');

  CanvasUnit _unit = CanvasUnit.px;
  ColorModel _colorModel = ColorModel.sRGB;
  int _channelDepth = 8;
  String _selectedPreset = 'preset_custom';
  List<int>? _iccData;

  static const _presets = {
    'preset_custom': null,
    'preset_a4': (210, 297, CanvasUnit.mm),
    'preset_a3': (297, 420, CanvasUnit.mm),
    'preset_1920x1080': (1920, 1080, CanvasUnit.px),
    'preset_3840x2160': (3840, 2160, CanvasUnit.px),
    'preset_1080x1920': (1080, 1920, CanvasUnit.px),
    'preset_2048x2048': (2048, 2048, CanvasUnit.px),
  };

  void _onPresetChanged(String? preset) {
    if (preset == null) return;
    setState(() {
      _selectedPreset = preset;
      final data = _presets[preset];
      if (data != null) {
        _widthController.text = data.$1.toString();
        _heightController.text = data.$2.toString();
        _unit = data.$3;
      }
    });
  }

  Future<void> _selectIcc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      final file = await result.files.single.xFile.readAsBytes();
      setState(() => _iccData = file.toList());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _resolutionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('new_project.title'.tr()),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: 'new_project.name'.tr()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedPreset,
                decoration: InputDecoration(labelText: 'new_project.preset'.tr()),
                items: _presets.keys.map((key) {
                  return DropdownMenuItem(
                    value: key,
                    child: Text(key.tr()),
                  );
                }).toList(),
                onChanged: _onPresetChanged,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      decoration: InputDecoration(labelText: 'new_project.width'.tr()),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      decoration: InputDecoration(labelText: 'new_project.height'.tr()),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _resolutionController,
                      decoration: InputDecoration(
                        labelText: 'new_project.resolution'.tr(),
                        suffixText: 'DPI',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child:                   DropdownButtonFormField<CanvasUnit>(
                      initialValue: _unit,
                      decoration: InputDecoration(labelText: 'new_project.unit'.tr()),
                      items: const [
                        DropdownMenuItem(value: CanvasUnit.px, child: Text('px')),
                        DropdownMenuItem(value: CanvasUnit.mm, child: Text('mm')),
                      ],
                      onChanged: (v) => setState(() => _unit = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              Text('new_project.color_space'.tr(), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<ColorModel>(
                initialValue: _colorModel,
                decoration: InputDecoration(labelText: 'new_project.color_model'.tr()),
                items: ColorModel.values.map((m) {
                  String key;
                  switch (m) {
                    case ColorModel.sRGB:
                      key = 'color_model.srgb';
                    case ColorModel.adobeRGB:
                      key = 'color_model.adobe_rgb';
                    case ColorModel.proPhoto:
                      key = 'color_model.prophoto';
                    case ColorModel.cmyk:
                      key = 'color_model.cmyk';
                  }
                  return DropdownMenuItem(value: m, child: Text(key.tr()));
                }).toList(),
                onChanged: (v) => setState(() => _colorModel = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _channelDepth,
                decoration: InputDecoration(labelText: 'new_project.depth'.tr()),
                items: const [
                  DropdownMenuItem(value: 8, child: Text('8-bit')),
                  DropdownMenuItem(value: 16, child: Text('16-bit')),
                ],
                onChanged: (v) => setState(() => _channelDepth = v!),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'new_project.icc'.tr(),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _selectIcc,
                    child: Text('new_project.icc_select'.tr()),
                  ),
                  if (_iccData != null)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('new_project.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final width = int.tryParse(_widthController.text) ?? 1920;
            final height = int.tryParse(_heightController.text) ?? 1080;
            final resol = double.tryParse(_resolutionController.text) ?? 72;
            Navigator.of(context).pop({
              'name': _nameController.text,
              'width': width,
              'height': height,
              'unit': _unit,
              'resolution': resol,
              'colorModel': _colorModel,
              'channelDepth': _channelDepth,
              'iccData': _iccData,
            });
          },
          child: Text('new_project.create'.tr()),
        ),
      ],
    );
  }
}
