import 'dart:io';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../providers/tool_provider.dart';
import '../../models/brush_preset.dart';
import '../../providers/app_settings.dart';

/// Brush presets: built-in brushes plus the user's saved presets, with pack
/// import / export.
///
/// A preset is a parametric snapshot of the brush engine's settings, so a
/// pack is a small JSON document and importing one can never fail on a
/// missing bitmap.
class BrushPresetSection extends StatelessWidget {
  const BrushPresetSection({super.key});

  static const List<String> _packExtensions = ['huebrush', 'json'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final presets = settings.allBrushPresets;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('preset.panel'.tr(), style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final preset in presets)
              _presetChip(context, settings, preset),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _iconButton(
              context,
              Icons.add,
              'preset.save_current'.tr(),
              () => _saveCurrent(context, settings),
            ),
            _iconButton(
              context,
              Icons.folder_open,
              'preset.import'.tr(),
              () => _import(context, settings),
            ),
            _iconButton(
              context,
              Icons.save_alt,
              'preset.export'.tr(),
              () => _export(context, settings),
            ),
          ],
        ),
      ],
    );
  }

  Widget _presetChip(
    BuildContext context,
    AppSettings settings,
    BrushPreset preset,
  ) {
    final provider = context.watch<ToolProvider>();
    final builtIn = preset.id.startsWith('builtin-');
    final selected = provider.activePresetId == preset.id;
    final label = builtIn && preset.name.startsWith('brush.')
        ? preset.name.tr()
        : preset.name;
    return InputChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      onSelected: (_) => provider.applyPreset(preset),
      onDeleted: builtIn
          ? null
          : () => settings.removeBrushPreset(preset.id),
      deleteIcon: const Icon(Icons.close, size: 12),
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _iconButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) =>
      IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
        padding: const EdgeInsets.all(4),
      );

  Future<void> _saveCurrent(
      BuildContext context, AppSettings settings) async {
    final provider = context.read<ToolProvider>();
    final brush = provider.currentBrush;
    final name = await _promptName(
      context,
      title: 'preset.save_current'.tr(),
      initial: '${brush.type.name} ${provider.brushSize.round()}',
    );
    if (name == null || name.trim().isEmpty) return;
    settings.addBrushPreset(BrushPreset(
      id: const Uuid().v4(),
      name: name.trim(),
      type: brush.type,
      size: provider.brushSize,
      opacity: provider.brushOpacity,
      hardness: brush.hardness,
      flow: brush.flow,
      spacing: brush.spacing,
      mix: brush.mix,
      tipTexture: brush.tipTexture,
    ));
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'preset.name'.tr(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text('dialog.confirm'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _import(BuildContext context, AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _packExtensions,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final presets = BrushPack.decode(await File(path).readAsString());
      if (presets == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('preset.import_failed'.tr())),
        );
        return;
      }
      final added = settings.addBrushPresets(presets);
      messenger.showSnackBar(
        SnackBar(
          content: Text('preset.imported'.tr(namedArgs: {'n': '$added'})),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('preset.import_failed'.tr())),
      );
    }
  }

  Future<void> _export(BuildContext context, AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    // Export the user's own presets; built-ins can always be re-created from
    // the app itself, and shipping them would make packs noisy.
    final presets = settings.brushPresets;
    if (presets.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('preset.nothing_to_export'.tr())),
      );
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'preset.export'.tr(),
      fileName: 'brushes.huebrush',
      type: FileType.custom,
      allowedExtensions: _packExtensions,
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(BrushPack.encode(presets));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'preset.exported'.tr(namedArgs: {'n': '${presets.length}'}),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('preset.export_failed'.tr())),
      );
    }
  }
}
