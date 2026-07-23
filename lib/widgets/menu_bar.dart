import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../providers/tool_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/project_provider.dart';
import '../models/drawable.dart';
import '../screens/settings_screen.dart';
import '../screens/workspace_screen.dart';

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
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
                (_) => false,
              );
            }),
            _MenuItem('menu.file.open'.tr(), Icons.folder_open, () {
              context.read<ProjectProvider>().loadRecentProjects();
            }),
            _MenuItem('menu.file.save'.tr(), Icons.save, () {
              context.read<ProjectProvider>().saveProject();
            }),
            _MenuItem('menu.file.save_as'.tr(), Icons.save_alt, () {
              context.read<ProjectProvider>().saveAsProject();
            }),
            _MenuItem('menu.file.export'.tr(), Icons.file_download, () {
              context.read<ProjectProvider>().exportToPng();
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
            _MenuItem('menu.edit.paste'.tr(), Icons.content_paste, () {}),
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
            _MenuItem('menu.image.flip_h'.tr(), Icons.flip, () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Not yet implemented')));
            }),
            _MenuItem('menu.image.flip_v'.tr(), Icons.flip, () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Not yet implemented')));
            }),
            _MenuItem('menu.image.rotate_cw'.tr(), Icons.rotate_right, () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Not yet implemented')));
            }),
            _MenuItem('menu.image.rotate_ccw'.tr(), Icons.rotate_left, () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Not yet implemented')));
            }),
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
            const _MenuDivider(),
            _MenuItem('menu.tool.brush'.tr(), Icons.brush,
                () => context.read<ToolProvider>().setTool(ToolType.brush)),
            _MenuItem('menu.tool.eraser'.tr(), Icons.auto_fix_normal,
                () => context.read<ToolProvider>().setTool(ToolType.eraser)),
            _MenuItem('menu.tool.fill'.tr(), Icons.format_color_fill,
                () => context.read<ToolProvider>().setTool(ToolType.fill)),
            _MenuItem('menu.tool.eyedropper'.tr(), Icons.colorize,
                () => context.read<ToolProvider>().setTool(ToolType.eyedropper)),
          ]),
          _MenuButton(label: 'menu.settings'.tr(), children: [
            _MenuItem('menu.settings.open'.tr(), Icons.settings, () {
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
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
              (_) => false,
            );
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
              const PopupMenuDivider(),
              _popupItem('fit', Icons.fit_screen, 'menu.view.fit_screen'),
              const PopupMenuDivider(),
              _popupItem('layer_new', Icons.layers, 'menu.layer.new'),
              const PopupMenuDivider(),
              _popupItem('open_settings', Icons.settings, 'menu.settings.open'),
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
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: const EdgeInsets.all(6),
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
            value: item,
            child: ListTile(
              leading: Icon(item.icon, size: 18),
              title: Text(item.label, style: const TextStyle(fontSize: 13)),
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
      if (value != null && value is _MenuItem) {
        value.onTap();
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: _hovered
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Colors.transparent,
          child: Text(widget.label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

class _MenuDivider extends _BaseMenuItem {
  const _MenuDivider();
}

class _MenuItem extends _BaseMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _MenuItem(this.label, this.icon, this.onTap);
}

class _BaseMenuItem {
  const _BaseMenuItem();
}