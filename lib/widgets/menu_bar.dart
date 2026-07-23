import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../providers/tool_provider.dart';
import '../providers/canvas_provider.dart';
import '../providers/project_provider.dart';
import '../models/drawable.dart';
import '../screens/settings_screen.dart';

class EditorMenuBar extends StatelessWidget {
  const EditorMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ].contains(Theme.of(context).platform);

    if (!isDesktop) {
      return const _MobileMenuBar();
    }
    return const _DesktopMenuBar();
  }
}

class _DesktopMenuBar extends StatelessWidget {
  const _DesktopMenuBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          _MenuButton(label: 'menu.file'.tr(), children: [
            _MenuItem('menu.file.new'.tr(), Icons.add, () {
              Navigator.of(context).pushReplacementNamed('/');
            }),
            _MenuItem('menu.file.open'.tr(), Icons.folder_open, () {
              context.read<ProjectProvider>().loadRecentProjects();
            }),
            _MenuItem('menu.file.save'.tr(), Icons.save, () {
              context.read<ProjectProvider>().saveProject();
            }),
            _MenuItem('menu.file.save_as'.tr(), Icons.save_alt, () {}),
            _MenuItem('menu.file.export'.tr(), Icons.file_download, () {}),
          ]),
          _MenuButton(label: 'menu.edit'.tr(), children: [
            _MenuItem('menu.edit.undo'.tr(), Icons.undo, () {
              context.read<ProjectProvider>().history.undo();
            }),
            _MenuItem('menu.edit.redo'.tr(), Icons.redo, () {
              context.read<ProjectProvider>().history.redo();
            }),
            _MenuItem('menu.edit.copy'.tr(), Icons.copy, () {}),
            _MenuItem('menu.edit.paste'.tr(), Icons.content_paste, () {}),
            _MenuItem('menu.edit.cut'.tr(), Icons.content_cut, () {}),
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
                canvas.fitToScreen(MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height,
                    project.settings.width.toDouble(),
                    project.settings.height.toDouble());
              }
            }),
            _MenuItem('menu.view.actual_size'.tr(), Icons.image_aspect_ratio,
                context.read<CanvasProvider>().resetView),
          ]),
          _MenuButton(label: 'menu.image'.tr(), children: [
            _MenuItem('menu.image.flip_h'.tr(), Icons.flip, () {}),
            _MenuItem('menu.image.flip_v'.tr(), Icons.flip, () {}),
            _MenuItem('menu.image.rotate_cw'.tr(), Icons.rotate_right, () {}),
            _MenuItem('menu.image.rotate_ccw'.tr(), Icons.rotate_left, () {}),
          ]),
          _MenuButton(label: 'menu.layer'.tr(), children: [
            _MenuItem('menu.layer.new'.tr(), Icons.layers, () {}),
            _MenuItem('menu.layer.duplicate'.tr(), Icons.copy, () {}),
            _MenuItem('menu.layer.merge'.tr(), Icons.merge, () {}),
            _MenuItem('menu.layer.delete'.tr(), Icons.delete, () {}),
            const _MenuDivider(),
            _MenuItem('menu.layer.move_up'.tr(), Icons.arrow_upward, () {}),
            _MenuItem('menu.layer.move_down'.tr(), Icons.arrow_downward, () {}),
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

class _MobileMenuBar extends StatelessWidget {
  const _MobileMenuBar();

  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    final canvasProvider = context.watch<CanvasProvider>();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _MobileBtn(Icons.add, 'menu.file.new'.tr(), () {
            Navigator.of(context).pushReplacementNamed('/');
          }),
          _MobileBtn(Icons.folder_open, 'menu.file.open'.tr(), () {}),
          _MobileBtn(Icons.save, 'menu.file.save'.tr(), () {
            context.read<ProjectProvider>().saveProject();
          }),
          _MobileBtn(Icons.undo, 'menu.edit.undo'.tr(), () {
            context.read<ProjectProvider>().history.undo();
          }),
          _MobileBtn(Icons.redo, 'menu.edit.redo'.tr(), () {
            context.read<ProjectProvider>().history.redo();
          }),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'zoom_in':
                  canvasProvider.zoomIn();
                case 'zoom_out':
                  canvasProvider.zoomOut();
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
                case 'actual':
                  canvasProvider.resetView();
                case 'tool_move':
                  toolProvider.setTool(ToolType.move);
                case 'tool_brush':
                  toolProvider.setTool(ToolType.brush);
                case 'tool_rect':
                  toolProvider.setTool(ToolType.shape);
                case 'tool_pen':
                  toolProvider.setTool(ToolType.pen);
                case 'tool_text':
                  toolProvider.setTool(ToolType.text);
                case 'tool_eraser':
                  toolProvider.setTool(ToolType.eraser);
                case 'tool_fill':
                  toolProvider.setTool(ToolType.fill);
                case 'layer_new':
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
              PopupMenuItem(
                  value: 'tool_move',
                  child: ListTile(
                      leading: const Icon(Icons.open_with),
                      title: Text('menu.tool.move'.tr()))),
              PopupMenuItem(
                  value: 'tool_brush',
                  child: ListTile(
                      leading: const Icon(Icons.brush),
                      title: Text('menu.tool.brush'.tr()))),
              PopupMenuItem(
                  value: 'tool_rect',
                  child: ListTile(
                      leading: const Icon(Icons.rectangle_outlined),
                      title: Text('menu.tool.rect'.tr()))),
              PopupMenuItem(
                  value: 'tool_pen',
                  child: ListTile(
                      leading: const Icon(Icons.edit),
                      title: Text('menu.tool.pen'.tr()))),
              PopupMenuItem(
                  value: 'tool_text',
                  child: ListTile(
                      leading: const Icon(Icons.text_fields),
                      title: Text('menu.tool.text'.tr()))),
              PopupMenuItem(
                  value: 'tool_eraser',
                  child: ListTile(
                      leading: const Icon(Icons.auto_fix_normal),
                      title: Text('menu.tool.eraser'.tr()))),
              PopupMenuItem(
                  value: 'tool_fill',
                  child: ListTile(
                      leading: const Icon(Icons.format_color_fill),
                      title: Text('menu.tool.fill'.tr()))),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'zoom_in',
                  child: ListTile(
                      leading: const Icon(Icons.zoom_in),
                      title: Text('menu.view.zoom_in'.tr()))),
              PopupMenuItem(
                  value: 'zoom_out',
                  child: ListTile(
                      leading: const Icon(Icons.zoom_out),
                      title: Text('menu.view.zoom_out'.tr()))),
              PopupMenuItem(
                  value: 'fit',
                  child: ListTile(
                      leading: const Icon(Icons.fit_screen),
                      title: Text('menu.view.fit_screen'.tr()))),
              PopupMenuItem(
                  value: 'actual',
                  child: ListTile(
                      leading: const Icon(Icons.image_aspect_ratio),
                      title: Text('menu.view.actual_size'.tr()))),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'about',
                  child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: Text('menu.help.about'.tr()))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MobileBtn(this.icon, this.tooltip, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return IconButton(
        icon: Icon(icon), onPressed: onPressed, tooltip: tooltip);
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
