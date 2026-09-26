import 'dart:io';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../models/pattern.dart';
import '../../providers/app_settings.dart';
import '../../services/pattern_renderer.dart';
import '../common/pattern_thumb.dart';
import '../dialogs/pattern_generator_dialog.dart';

/// 图案库 / 纹理库: the pattern library plus the entry point to the dot
/// generator.
///
/// Patterns are parametric, so importing and exporting is plain JSON — no
/// bitmap assets to validate, and a pattern stored in a drawing renders the
/// same on any machine.
class PatternPanel extends StatelessWidget {
  const PatternPanel({super.key});

  static const List<String> _packExtensions = ['huepattern', 'json'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final active = settings.activePattern;
    return Card(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('pattern.panel'.tr(), style: theme.textTheme.labelMedium),
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: settings.fillWithPattern,
                      onChanged: (v) => settings.setFillWithPattern(v),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'pattern.fill_with_pattern'.tr(),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final pattern in settings.patterns)
                  _patternTile(context, settings, pattern,
                      selected: active?.id == pattern.id),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _iconButton(
                  context,
                  Icons.auto_awesome,
                  'pattern.generator'.tr(),
                  () => _generate(context, settings),
                ),
                _iconButton(
                  context,
                  Icons.folder_open,
                  'pattern.import'.tr(),
                  () => _import(context, settings),
                ),
                _iconButton(
                  context,
                  Icons.save_alt,
                  'pattern.export'.tr(),
                  () => _export(context, settings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _patternTile(
    BuildContext context,
    AppSettings settings,
    PatternSpec pattern, {
    required bool selected,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: pattern.name,
      child: InkWell(
        onTap: () => settings.setActivePattern(pattern.id),
        onLongPress: () => _showPatternMenu(context, settings, pattern),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: PatternThumb(spec: pattern, size: 34),
        ),
      ),
    );
  }

  Widget _iconButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
      padding: const EdgeInsets.all(4),
    );
  }

  Future<void> _generate(BuildContext context, AppSettings settings) async {
    final generated = await showPatternGeneratorDialog(context);
    if (generated == null) return;
    settings.addPattern(generated);
    // The new pattern is now active; ask for pattern fills by default so the
    // generator has a visible effect.
    settings.setFillWithPattern(true);
  }

  void _showPatternMenu(
    BuildContext context,
    AppSettings settings,
    PatternSpec pattern,
  ) {
    final builtIn = pattern.id.startsWith('builtin-');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text('pattern.edit'.tr()),
              onTap: () async {
                Navigator.of(ctx).pop();
                final edited =
                    await showPatternGeneratorDialog(context, initial: pattern);
                if (edited == null) return;
                // Editing replaces the entry in place (stock patterns can be
                // reshaped, they just cannot be deleted).
                settings.addPattern(edited);
              },
            ),
            if (!builtIn)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('pattern.delete'.tr()),
                onTap: () {
                  Navigator.of(ctx).pop();
                  settings.removePattern(pattern.id);
                },
              ),
          ],
        ),
      ),
    );
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
      final patterns = PatternPack.decode(await File(path).readAsString());
      if (patterns == null) {
        messenger.showSnackBar(
          SnackBar(content: Text('pattern.import_failed'.tr())),
        );
        return;
      }
      final added = settings.addPatterns(patterns);
      // Warm the tile cache so the imported swatches paint immediately.
      for (final pattern in patterns) {
        PatternRenderer.preload(pattern);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('pattern.imported'.tr(namedArgs: {'n': '$added'})),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('pattern.import_failed'.tr())),
      );
    }
  }

  Future<void> _export(BuildContext context, AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    final patterns = settings.patterns;
    if (patterns.isEmpty) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'pattern.export'.tr(),
      fileName: 'patterns.huepattern',
      type: FileType.custom,
      allowedExtensions: _packExtensions,
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(PatternPack.encode(patterns));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'pattern.exported'.tr(namedArgs: {'n': '${patterns.length}'}),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('pattern.export_failed'.tr())),
      );
    }
  }
}
