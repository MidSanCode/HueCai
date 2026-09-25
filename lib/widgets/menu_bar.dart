import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/tool_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/project_provider.dart';
import '../providers/app_settings.dart';
import '../services/project_service.dart';
import '../services/stroke_stabilizer.dart';
import '../services/assist_ruler.dart';
import '../services/filter_registry.dart';
import '../widgets/dialogs/generic_filter_dialog.dart';
import '../models/drawable.dart';
import '../screens/settings_screen.dart';
import '../screens/editor_screen.dart';
import 'dialogs/brush_editor_dialog.dart';
import 'dialogs/filter_dialog.dart';
import 'dialogs/unsaved_changes.dart';

class EditorMenuBar extends StatelessWidget {
  final bool compact;

  const EditorMenuBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: compact
          ? _CompactMenuBar()
          : const _FullMenuBar(),
    );
  }
}

class _FullMenuBar extends StatelessWidget {
  const _FullMenuBar();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _MenuButton(label: 'menu.file'.tr(), children: [
            _MenuItem('menu.file.new'.tr(), Icons.add, () {
              _returnToWorkspace(context);
            }),
            _MenuItem('menu.file.open'.tr(), Icons.folder_open, () {
              _openHcpFile(context);
            }),
            _MenuItem('menu.file.import'.tr(), Icons.image, () {
              _importImageFile(context);
            }),
            const _MenuDivider(),
            _MenuItem('menu.file.save'.tr(), Icons.save, () {
              context.read<ProjectProvider>().saveProject();
            }),
            _MenuItem('menu.file.save_as'.tr(), Icons.save_alt, () {
              context.read<ProjectProvider>().saveAsProject();
            }),
            const _MenuDivider(),
            _MenuItem('menu.file.export'.tr(), Icons.image, () {
              _showExportDialog(context);
            }),
            _MenuItem('menu.file.export_ora'.tr(), Icons.layers, () {
              context.read<ProjectProvider>().exportOra();
            }),
          ]),
          _MenuButton(label: 'menu.edit'.tr(), children: [
            _MenuItem('menu.edit.undo'.tr(), Icons.undo, () {
              context.read<ProjectProvider>().undo();
            }),
            _MenuItem('menu.edit.redo'.tr(), Icons.redo, () {
              context.read<ProjectProvider>().redo();
            }),
            _MenuItem('menu.edit.copy'.tr(), Icons.copy, () {
              final pp = context.read<ProjectProvider>();
              if (pp.selectedDrawable != null) {
                pp.saveSnapshot();
                pp.selectedDrawable!.copyWith();
              }
            }),
            _MenuItem.disabled('menu.edit.paste'.tr(), Icons.content_paste),
            _MenuItem('menu.edit.cut'.tr(), Icons.content_cut, () {
              final pp = context.read<ProjectProvider>();
              if (pp.selectedDrawable != null) {
                pp.saveSnapshot();
                pp.deleteDrawable(pp.selectedDrawable!.id);
              }
            }),
          ]),
          _MenuButton(label: 'menu.view'.tr(), children: [
            _MenuItem('menu.view.zoom_in'.tr(), Icons.zoom_in,
                context.read<CanvasProvider>().zoomIn),
            _MenuItem('menu.view.zoom_out'.tr(), Icons.zoom_out,
                context.read<CanvasProvider>().zoomOut),
            const _MenuDivider(),
            _MenuItem('menu.view.fit_screen'.tr(), Icons.fit_screen, () {
              final canvas = context.read<CanvasProvider>();
              final project = context.read<ProjectProvider>().currentProject;
              if (project != null) {
                canvas.fitToScreen(
                    MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height,
                    project.settings.width.toDouble(),
                    project.settings.height.toDouble());
              }
            }),
            _MenuItem('menu.view.actual_size'.tr(), Icons.image_aspect_ratio,
                context.read<CanvasProvider>().resetView),
          ]),
          _MenuButton(label: 'menu.image'.tr(), children: [
            _MenuItem.disabled('menu.image.flip_h'.tr(), Icons.flip),
            _MenuItem.disabled('menu.image.flip_v'.tr(), Icons.flip),
            _MenuItem.disabled('menu.image.rotate_cw'.tr(), Icons.rotate_right),
            _MenuItem.disabled('menu.image.rotate_ccw'.tr(), Icons.rotate_left),
            const _MenuDivider(),
            _MenuItem('menu.image.background_color'.tr(), Icons.format_color_fill,
                () => _showBackgroundColorDialog(context)),
            _MenuItem('menu.image.import_image'.tr(), Icons.add_photo_alternate,
                () => _importImageToCanvas(context)),
            _MenuItem('menu.image.import_reference'.tr(), Icons.image,
                () => _importReference(context)),
            _MenuItem('menu.image.clear_reference'.tr(), Icons.image_not_supported,
                () => context.read<CanvasProvider>().clearReference()),
            const _MenuDivider(),
            _MenuItem('filter.gaussian_blur'.tr(), Icons.blur_on,
                () => showFilterDialog(context, FilterKind.gaussianBlur)),
            _MenuItem('filter.unsharp_mask'.tr(), Icons.deblur,
                () => showFilterDialog(context, FilterKind.unsharpMask)),
            _MenuItem('filter.levels'.tr(), Icons.tune,
                () => showFilterDialog(context, FilterKind.levels)),
            _MenuItem('filter.curves'.tr(), Icons.show_chart,
                () => showFilterDialog(context, FilterKind.curves)),
            _MenuItem('filter.hue_saturation'.tr(), Icons.palette,
                () => showFilterDialog(context, FilterKind.hueSaturation)),
            const _MenuDivider(),
            _MenuItem('filter.browser'.tr(), Icons.auto_awesome,
                () => showFilterBrowser(context)),
          ]),
          _MenuButton(label: 'menu.layer'.tr(), children: [
            _MenuItem('menu.layer.new'.tr(), Icons.layers, () {
              context.read<ProjectProvider>().addLayer();
            }),
            _MenuItem('menu.layer.duplicate'.tr(), Icons.copy, () {
              final pp = context.read<ProjectProvider>();
              if (pp.currentProject != null) {
                pp.saveSnapshot();
                pp.duplicateLayer(pp.currentProject!.currentLayerIndex);
              }
            }),
            _MenuItem('menu.layer.merge'.tr(), Icons.merge, () {
              final pp = context.read<ProjectProvider>();
              if (pp.currentProject != null &&
                  pp.currentProject!.currentLayerIndex > 0) {
                pp.saveSnapshot();
                pp.mergeDownLayer(pp.currentProject!.currentLayerIndex);
              }
            }),
            _MenuItem('menu.layer.delete'.tr(), Icons.delete, () {
              final pp = context.read<ProjectProvider>();
              if (pp.currentProject != null) {
                pp.saveSnapshot();
                pp.deleteLayer(pp.currentProject!.currentLayerIndex);
              }
            }),
            const _MenuDivider(),
            _MenuItem('menu.layer.move_up'.tr(), Icons.arrow_upward, () {
              final pp = context.read<ProjectProvider>();
              if (pp.currentProject != null) {
                pp.saveSnapshot();
                pp.moveLayerUp(pp.currentProject!.currentLayerIndex);
              }
            }),
            _MenuItem('menu.layer.move_down'.tr(), Icons.arrow_downward, () {
              final pp = context.read<ProjectProvider>();
              if (pp.currentProject != null) {
                pp.saveSnapshot();
                pp.moveLayerDown(pp.currentProject!.currentLayerIndex);
              }
            }),
          ]),
          _MenuButton(label: 'menu.tool'.tr(), children: [
            _MenuItem('menu.tool.move'.tr(), Icons.open_with,
                () => context.read<ToolProvider>().setTool(ToolType.move)),
            _MenuItem('shape.rect'.tr(), Icons.rectangle_outlined,
                () => context.read<ToolProvider>().setShape(ShapeType.rect)),
            _MenuItem('shape.ellipse'.tr(), Icons.circle_outlined,
                () => context.read<ToolProvider>().setShape(ShapeType.ellipse)),
            _MenuItem('shape.polygon'.tr(), Icons.change_history,
                () => context.read<ToolProvider>().setShape(ShapeType.polygon)),
            _MenuItem('shape.line'.tr(), Icons.horizontal_rule,
                () => context.read<ToolProvider>().setShape(ShapeType.line)),
            _MenuItem('shape.curve'.tr(), Icons.timeline,
                () => context.read<ToolProvider>().setShape(ShapeType.curve)),
            const _MenuDivider(),
            _MenuItem('menu.tool.pen'.tr(), Icons.edit,
                () => context.read<ToolProvider>().setTool(ToolType.pen)),
            _MenuItem('menu.tool.text'.tr(), Icons.text_fields,
                () => context.read<ToolProvider>().setTool(ToolType.text)),
            _MenuItem('menu.tool.select'.tr(), Icons.crop_square,
                () => context.read<ToolProvider>().setTool(ToolType.select)),
            _MenuItem('menu.tool.fill'.tr(), Icons.format_color_fill,
                () => context.read<ToolProvider>().setTool(ToolType.fill)),
            _MenuItem('menu.tool.gradient'.tr(), Icons.gradient,
                () => context.read<ToolProvider>().setTool(ToolType.gradient)),
            _MenuItem('menu.tool.eyedropper'.tr(), Icons.colorize,
                () => context.read<ToolProvider>().setTool(ToolType.eyedropper)),
            const _MenuDivider(),
            _MenuItem('menu.tool.smudge'.tr(), Icons.blur_on,
                () => context.read<ToolProvider>().setTool(ToolType.smudge)),
            _MenuItem('menu.tool.willow_leaf'.tr(), Icons.eco,
                () => context.read<ToolProvider>().setTool(ToolType.willowLeaf)),
            _MenuItem('menu.tool.liquify'.tr(), Icons.waves,
                () => context.read<ToolProvider>().setTool(ToolType.liquify)),
            const _MenuDivider(),
            _MenuItem('menu.tool.stabilizer'.tr(), Icons.spa,
                () => _showStabilizerDialog(context)),
            _MenuItem('menu.tool.symmetry'.tr(), Icons.flip,
                () => context.read<ToolProvider>().toggleSymmetry(),
                checked: context.watch<ToolProvider>().symmetryEnabled),
            _MenuItem('menu.tool.perspective'.tr(), Icons.grid_on,
                () => context.read<ToolProvider>().togglePerspectiveGuide(),
                checked: context.watch<ToolProvider>().perspectiveGuideEnabled),
            const _MenuDivider(),
            _MenuItem('ruler.add_parallel'.tr(), Icons.horizontal_rule,
                () => _addRuler(context, RulerType.parallel)),
            _MenuItem('ruler.add_ellipse'.tr(), Icons.circle_outlined,
                () => _addRuler(context, RulerType.ellipse)),
            _MenuItem('ruler.add_spline'.tr(), Icons.timeline,
                () => _addRuler(context, RulerType.spline)),
            _MenuItem('ruler.snap'.tr(), Icons.center_focus_strong,
                () {
                  final tp = context.read<ToolProvider>();
                  tp.setRulerSnapEnabled(!tp.rulerSnapEnabled);
                },
                checked: context.watch<ToolProvider>().rulerSnapEnabled),
            _MenuItem('ruler.clear'.tr(), Icons.delete_sweep,
                () => context.read<ToolProvider>().clearRulers()),
          ]),
          _MenuButton(label: 'menu.settings'.tr(), children: [
            _MenuItem('menu.settings.brush'.tr(), Icons.brush, () {
              BrushEditorDialog.show(context);
            }),
            _MenuItem('menu.settings.app_settings'.tr(), Icons.settings, () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            }),
          ]),
          _MenuButton(label: 'menu.help'.tr(), children: [
            _MenuItem('menu.help.about'.tr(), Icons.info_outline, () {
              showAboutDialog(
                context: context,
                applicationName: 'app.name'.tr(),
                applicationVersion: 'dialog.about_version'.tr(),
                applicationLegalese: 'dialog.about_desc'.tr(),
              );
            }),
          ]),
        ],
      ),
    );
  }
}

class _CompactMenuBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    final canvasProvider = context.watch<CanvasProvider>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CompactBtn(Icons.add, 'menu.file.new'.tr(), () {
            _returnToWorkspace(context);
          }),
          _CompactBtn(Icons.save, 'menu.file.save'.tr(), () {
            context.read<ProjectProvider>().saveProject();
          }),
          _CompactBtn(Icons.undo, 'menu.edit.undo'.tr(), () {
            context.read<ProjectProvider>().undo();
          }),
          _CompactBtn(Icons.redo, 'menu.edit.redo'.tr(), () {
            context.read<ProjectProvider>().redo();
          }),
          _CompactBtn(Icons.zoom_in, 'menu.view.zoom_in'.tr(),
              canvasProvider.zoomIn),
          _CompactBtn(Icons.zoom_out, 'menu.view.zoom_out'.tr(),
              canvasProvider.zoomOut),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'tool_move':
                  toolProvider.setTool(ToolType.move);
                case 'tool_brush':
                  toolProvider.setTool(ToolType.brush);
                case 'tool_rect':
                  toolProvider.setTool(ToolType.shape);
                case 'tool_eraser':
                  toolProvider.setTool(ToolType.eraser);
                case 'tool_fill':
                  toolProvider.setTool(ToolType.fill);
                case 'tool_eyedropper':
                  toolProvider.setTool(ToolType.eyedropper);
                case 'tool_smudge':
                  toolProvider.setTool(ToolType.smudge);
                case 'tool_willow':
                  toolProvider.setTool(ToolType.willowLeaf);
                case 'tool_liquify':
                  toolProvider.setTool(ToolType.liquify);
                case 'tool_symmetry':
                  toolProvider.toggleSymmetry();
                case 'tool_perspective':
                  toolProvider.togglePerspectiveGuide();
                case 'layer_new':
                  context.read<ProjectProvider>().addLayer();
                case 'fit':
                  final project =
                      context.read<ProjectProvider>().currentProject;
                  if (project != null) {
                    canvasProvider.fitToScreen(
                        MediaQuery.of(context).size.width,
                        MediaQuery.of(context).size.height,
                        project.settings.width.toDouble(),
                        project.settings.height.toDouble());
                  }
                case 'stabilizer':
                  _showStabilizerDialog(context);
                case 'import_ref':
                  _importReference(context);
                case 'bg_color':
                  _showBackgroundColorDialog(context);
                case 'brush_settings':
                  BrushEditorDialog.show(context);
                case 'open_settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
                  );
                case 'about':
                  showAboutDialog(
                    context: context,
                    applicationName: 'app.name'.tr(),
                    applicationVersion: 'dialog.about_version'.tr(),
                    applicationLegalese: 'dialog.about_desc'.tr(),
                  );
              }
            },
            itemBuilder: (context) => [
              _popupItem('tool_move', Icons.open_with, 'menu.tool.move'),
              _popupItem('tool_brush', Icons.brush, 'menu.tool.brush'),
              _popupItem('tool_rect', Icons.rectangle_outlined, 'menu.tool.rect'),
              _popupItem('tool_eraser', Icons.auto_fix_normal, 'menu.tool.eraser'),
              _popupItem('tool_fill', Icons.format_color_fill, 'menu.tool.fill'),
              _popupItem('tool_eyedropper', Icons.colorize, 'menu.tool.eyedropper'),
              _popupItem('tool_smudge', Icons.blur_on, 'menu.tool.smudge'),
              _popupItem('tool_willow', Icons.eco, 'menu.tool.willow_leaf'),
              _popupItem('tool_liquify', Icons.waves, 'menu.tool.liquify'),
              const PopupMenuDivider(),
              _popupItem('stabilizer', Icons.spa, 'menu.tool.stabilizer'),
              _popupItem('tool_symmetry', Icons.flip, 'menu.tool.symmetry'),
              _popupItem('tool_perspective', Icons.grid_on, 'menu.tool.perspective'),
              _popupItem('import_ref', Icons.image, 'menu.image.import_reference'),
              _popupItem('bg_color', Icons.format_color_fill, 'menu.image.background_color'),
              const PopupMenuDivider(),
              _popupItem('fit', Icons.fit_screen, 'menu.view.fit_screen'),
              const PopupMenuDivider(),
              _popupItem('layer_new', Icons.layers, 'menu.layer.new'),
              const PopupMenuDivider(),
              _popupItem('brush_settings', Icons.brush, 'menu.settings.brush'),
              _popupItem('open_settings', Icons.settings, 'menu.settings.app_settings'),
              _popupItem('about', Icons.info_outline, 'menu.help.about'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _popupItem(
          String value, IconData icon, String labelKey) =>
      PopupMenuItem(
        value: value,
        child: ListTile(
          leading: Icon(icon, size: 20),
          title: Text(labelKey.tr(), style: const TextStyle(fontSize: 13)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      );
}

class _CompactBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _CompactBtn(this.icon, this.tooltip, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(4),
    );
  }
}

class _MenuButton extends StatefulWidget {
  final String label;
  final List<_BaseMenuItem> children;

  const _MenuButton({required this.label, required this.children});

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _hovered = false;

  void _showMenu() {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset(0, renderBox.size.height));

    final menuItems = <PopupMenuEntry<_BaseMenuItem>>[];
    for (final item in widget.children) {
      if (item is _MenuDivider) {
        menuItems.add(const PopupMenuDivider());
      } else if (item is _MenuItem) {
        menuItems.add(
          PopupMenuItem<_BaseMenuItem>(
            enabled: item.enabled,
            value: item.enabled ? item : null,
            child: ListTile(
              leading: Icon(item.icon, size: 18,
                color: item.enabled ? null : Theme.of(context).disabledColor),
              title: Text(item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: item.enabled ? null : Theme.of(context).disabledColor,
                )),
              trailing: item.checked
                  ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                  : null,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        );
      }
    }

    showMenu<_BaseMenuItem>(
      context: context,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy, offset.dx, offset.dy),
      items: menuItems,
      elevation: 2,
    ).then((value) {
      if (value != null && value is _MenuItem && value.onTap != null) {
        value.onTap!();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _showMenu,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: _hovered
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Colors.transparent,
          child: Text(widget.label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

void _showStabilizerDialog(BuildContext context) {
  final settings = context.read<AppSettings>();
  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('menu.tool.stabilizer'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<StabilizerMode>(
              segments: [
                ButtonSegment(
                  value: StabilizerMode.off,
                  label: Text('stabilizer.mode_off'.tr()),
                ),
                ButtonSegment(
                  value: StabilizerMode.smooth,
                  label: Text('stabilizer.mode_smooth'.tr()),
                ),
                ButtonSegment(
                  value: StabilizerMode.stringPull,
                  label: Text('stabilizer.mode_string'.tr()),
                ),
              ],
              selected: {settings.stabilizerMode},
              onSelectionChanged: (s) {
                settings.setStabilizerMode(s.first);
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Text('${settings.stabilizer.round()}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Slider(
              value: settings.stabilizer,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${settings.stabilizer.round()}',
              onChanged: (v) {
                settings.setStabilizer(v);
                setState(() {});
              },
            ),
            Text('menu.tool.stabilizer_hint'.tr(), style: const TextStyle(fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog.close'.tr()),
          ),
        ],
      ),
    ),
  );
}

void _addRuler(BuildContext context, RulerType type) {
  final tp = context.read<ToolProvider>();
  final pp = context.read<ProjectProvider>();
  final s = pp.currentProject?.settings;
  final center = s != null
      ? Offset(s.width / 2, s.height / 2)
      : const Offset(200, 200);
  tp.addRuler(type, center);
}

void _showBackgroundColorDialog(BuildContext context) {
  final pp = context.read<ProjectProvider>();
  const presets = [
    Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFF5F5F5), Color(0xFF2D2D2D),
    Color(0xFFE53935), Color(0xFFFFB300), Color(0xFF43A047), Color(0xFF1E88E5),
    Color(0xFF8E24AA), Color(0xFF00897B), Color(0xFF6D4C41), Color(0xFFEC407A),
  ];
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('menu.image.background_color'.tr()),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Transparent option (checkerboard tile).
          GestureDetector(
            onTap: () {
              pp.setCanvasBackgroundColor(const Color(0x00000000));
              Navigator.of(ctx).pop();
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade500, width: 1.5),
              ),
              child: CustomPaint(painter: _CheckerPainter()),
            ),
          ),
          for (final c in presets)
            GestureDetector(
              onTap: () {
                pp.setCanvasBackgroundColor(c);
                Navigator.of(ctx).pop();
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade400),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('dialog.cancel'.tr()),
        ),
      ],
    ),
  );
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF888888);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x, y, cell, cell),
          even ? light : dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

void _showExportDialog(BuildContext context) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('menu.file.export'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.image, color: theme.colorScheme.primary),
            title: Text('menu.file.export_png'.tr()),
            onTap: () {
              Navigator.of(ctx).pop();
              context.read<ProjectProvider>().exportImage('png');
            },
          ),
          ListTile(
            leading: Icon(Icons.image, color: theme.colorScheme.primary),
            title: Text('menu.file.export_jpg'.tr()),
            onTap: () {
              Navigator.of(ctx).pop();
              context.read<ProjectProvider>().exportImage('jpg');
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('dialog.cancel'.tr())),
      ],
    ),
  );
}

void _importReference(BuildContext context) async {
  final canvasProvider = context.read<CanvasProvider>();
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
  );
  if (result != null && result.files.single.path != null) {
    canvasProvider.setReferenceImage(result.files.single.path!);
  }
}

/// Leaves the editor and goes back to the workspace, first giving the user a
/// chance to save unsaved work.
///
/// The editor is always pushed on top of the workspace, so popping returns to
/// the existing screen. This used to `pushAndRemoveUntil(... (_) => false)`,
/// which tore the whole stack down and pushed a *second* WorkspaceScreen —
/// discarding the current project without ever prompting.
Future<void> _returnToWorkspace(BuildContext context) async {
  if (!await mayLeaveWithUnsavedChanges(context)) return;
  if (!context.mounted) return;
  context.read<ProjectProvider>().closeProject();
  Navigator.of(context).popUntil((route) => route.isFirst);
}

void _openHcpFile(BuildContext context) async {
  final pp = context.read<ProjectProvider>();
  // Ask about the current project *before* the picker, so cancelling the
  // dialog does not leave the picking flow half-done.
  if (!await mayLeaveWithUnsavedChanges(context)) return;
  if (!context.mounted) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ProjectService.readableExtensionNames,
  );
  if (result == null || result.files.single.path == null) return;

  await pp.openProject(result.files.single.path!);
  if (!context.mounted) return;
  // Mark the outgoing editor as already reconciled so its PopScope does not
  // prompt a second time for the project we just replaced.
  _leaveEditorForNewContent(context);
}

/// Replaces the current editor with a fresh one for newly opened content.
///
/// The old editor is popped without a second unsaved-changes prompt: the
/// caller has already resolved that, and the provider now holds the new
/// project.
void _leaveEditorForNewContent(BuildContext context, {bool push = true}) {
  final nav = Navigator.of(context);
  if (nav.canPop() && !_isWorkspaceRoot(nav)) {
    nav.pop();
  }
  if (push) {
    nav.push(MaterialPageRoute(builder: (_) => const EditorScreen()));
  }
}

/// Whether the current route is the root workspace screen.
bool _isWorkspaceRoot(NavigatorState nav) => !nav.canPop();

void _importImageToCanvas(BuildContext context) async {
  final pp = context.read<ProjectProvider>();
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
  );
  if (result != null && result.files.single.path != null) {
    await pp.importImageToCanvas(result.files.single.path!);
  }
}

void _importImageFile(BuildContext context) async {
  final pp = context.read<ProjectProvider>();
  // importImage() replaces the current project, so guard unsaved work first.
  if (!await mayLeaveWithUnsavedChanges(context)) return;
  if (!context.mounted) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
  );
  if (result == null || result.files.single.path == null) return;

  final path = result.files.single.path!;
  await pp.importImage(path);
  if (!context.mounted) return;
  if (pp.currentProject == null) return;
  _leaveEditorForNewContent(context);
}

class _MenuDivider extends _BaseMenuItem {
  const _MenuDivider();
}

class _MenuItem extends _BaseMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool checked;

  const _MenuItem(this.label, this.icon, this.onTap, {this.checked = false});

  const _MenuItem.disabled(this.label, this.icon) : onTap = null, checked = false;

  bool get enabled => onTap != null;
}

class _BaseMenuItem {
  const _BaseMenuItem();
}