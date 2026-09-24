import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/project_provider.dart';
import '../models/project.dart';
import '../providers/tool_provider.dart';
import '../providers/canvas_provider.dart';
import '../widgets/menu_bar.dart';
import '../widgets/tools/tool_panel.dart';
import '../widgets/tools/image_edit_toolbar.dart';
import '../widgets/panels/color_panel.dart';
import '../widgets/panels/brush_panel.dart';
import '../widgets/panels/layer_panel.dart';
import '../widgets/canvas/paint_canvas.dart';
import '../widgets/canvas/reference_floating_window.dart';
import '../widgets/canvas/canvas_zoom_overlay.dart';
import '../widgets/dialogs/brush_editor_dialog.dart';
import '../widgets/dialogs/unsaved_changes.dart';
import '../widgets/selection_panel.dart';
import 'settings_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CanvasProvider _canvasProvider;
  late final ToolProvider _toolProvider;
  // Captured in didChangeDependencies so dispose() never performs an
  // ancestor lookup on a deactivated widget tree.
  ProjectProvider? _projectProvider;
  bool _showRightPanel = true;

  @override
  void initState() {
    super.initState();
    _canvasProvider = CanvasProvider();
    _toolProvider = ToolProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _projectProvider = context.read<ProjectProvider>();
      _projectProvider!.startBackupTimer();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _projectProvider ??= context.read<ProjectProvider>();
  }

  @override
  void dispose() {
    _projectProvider?.stopBackupTimer();
    _canvasProvider.dispose();
    _toolProvider.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final pp = context.read<ProjectProvider>();
    final allowed = await mayLeaveWithUnsavedChanges(context);
    if (allowed) pp.closeProject();
    return allowed;
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectProvider>().currentProject;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: Text('editor.no_project_title'.tr())),
        body: Center(child: Text('editor.no_project_body'.tr())),
      );
    }

    final pp = context.read<ProjectProvider>();
    final isWide = MediaQuery.of(context).size.width > 600;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _toolProvider),
        ChangeNotifierProvider.value(value: _canvasProvider),
      ],
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
              pp.smartUndo(),
          SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
              pp.redo(),
          SingleActivator(LogicalKeyboardKey.f5): () => BrushEditorDialog.show(context),
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) Navigator.of(context).pop();
            },
            child: Scaffold(
              body: _buildBody(context, project, isWide),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Project project, bool isWide) {
    if (isWide) {
      return _WideLayout(
        project: project,
        showRightPanel: _showRightPanel,
        onToggleRightPanel: () => setState(() => _showRightPanel = !_showRightPanel),
        onExit: _confirmExit,
      );
    }
    return _NarrowLayout(
      project: project,
      showMenu: () => _showTopMenu(context),
      showLayerPanel: () => _showLayerPanel(context),
      onExit: _confirmExit,
    );
  }

  /// Shows the unsaved-changes dialog if needed, then returns to workspace.
  Future<void> _confirmExit() async {
    final pp = context.read<ProjectProvider>();
    // Await the user's decision first, then navigate exactly once. The old
    // version popped from inside the dialog's button callbacks, which both
    // ignored the future result and popped twice on some paths.
    final allowed = await mayLeaveWithUnsavedChanges(context);
    if (!allowed) return;
    if (!mounted) return;
    pp.closeProject();
    Navigator.of(context).pop();
  }

  void _showTopMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(1000, 40, 0, 0),
      items: [
        PopupMenuItem(value: 'file', child: ListTile(
          leading: const Icon(Icons.folder_open, size: 18),
          title: Text('menu.file'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'image', child: ListTile(
          leading: const Icon(Icons.image, size: 18),
          title: Text('menu.image'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'tools', child: ListTile(
          leading: const Icon(Icons.build, size: 18),
          title: Text('menu.tool'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'settings', child: ListTile(
          leading: const Icon(Icons.settings, size: 18),
          title: Text('menu.settings.app_settings'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'file': _showFileMenu(context);
        case 'image': _showImageMenu(context);
        case 'tools': _showToolMenu(context);
        case 'settings': Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
    });
  }

  void _showFileMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(200, 40, 0, 0),
      items: [
        PopupMenuItem(value: 'new', child: ListTile(
          leading: const Icon(Icons.add, size: 18),
          title: Text('menu.file.new'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'save', child: ListTile(
          leading: const Icon(Icons.save, size: 18),
          title: Text('menu.file.save'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'export', child: ListTile(
          leading: const Icon(Icons.image, size: 18),
          title: Text('menu.file.export'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
      ],
    ).then((value) async {
      if (value == null) return;
      switch (value) {
        case 'new':
          // Guard unsaved work, then return to the workspace so the user can
          // create the new project there. Previously this pushed a fresh
          // EditorScreen with pushAndRemoveUntil, which silently threw away
          // the current project without ever prompting.
          if (!await mayLeaveWithUnsavedChanges(context)) return;
          if (!context.mounted) return;
          context.read<ProjectProvider>().closeProject();
          Navigator.of(context).pop();
        case 'save': context.read<ProjectProvider>().saveProject();
        case 'export': _showExportDialog(context);
      }
    });
  }

  void _showImageMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(200, 60, 0, 0),
      items: [
        PopupMenuItem(value: 'import', child: ListTile(
          leading: const Icon(Icons.add_photo_alternate, size: 18),
          title: Text('menu.image.import_image'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'import') _importImageToCanvas(context);
    });
  }

  void _showToolMenu(BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(200, 80, 0, 0),
      items: [
        PopupMenuItem(value: 'select', child: ListTile(
          leading: const Icon(Icons.crop_square, size: 18),
          title: Text('tool.select'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'move', child: ListTile(
          leading: const Icon(Icons.open_with, size: 18),
          title: Text('tool.move'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'fill', child: ListTile(
          leading: const Icon(Icons.format_color_fill, size: 18),
          title: Text('tool.fill'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'eyedropper', child: ListTile(
          leading: const Icon(Icons.colorize, size: 18),
          title: Text('tool.eyedropper'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'smudge', child: ListTile(
          leading: const Icon(Icons.blur_on, size: 18),
          title: Text('tool.smudge'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
        PopupMenuItem(value: 'liquify', child: ListTile(
          leading: const Icon(Icons.waves, size: 18),
          title: Text('tool.liquify'.tr(), style: const TextStyle(fontSize: 13)),
          dense: true, contentPadding: EdgeInsets.zero,
        )),
      ],
    ).then((value) {
      if (value == null) return;
      final tp = context.read<ToolProvider>();
      switch (value) {
        case 'select':
          tp.setTool(ToolType.select);
          context.read<ProjectProvider>().enterSelectionMode();
        case 'move': tp.setTool(ToolType.move);
        case 'fill': tp.setTool(ToolType.fill);
        case 'eyedropper': tp.setTool(ToolType.eyedropper);
        case 'smudge': tp.setTool(ToolType.smudge);
        case 'liquify': tp.setTool(ToolType.liquify);
      }
    });
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('menu.file.export'.tr()),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Icons.image, color: Theme.of(context).colorScheme.primary), title: Text('menu.file.export_png'.tr()),
            onTap: () { Navigator.of(ctx).pop(); context.read<ProjectProvider>().exportImage('png'); }),
          ListTile(leading: Icon(Icons.image, color: Theme.of(context).colorScheme.primary), title: Text('menu.file.export_jpg'.tr()),
            onTap: () { Navigator.of(ctx).pop(); context.read<ProjectProvider>().exportImage('jpg'); }),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('dialog.cancel'.tr()))],
      ),
    );
  }

  void _importImageToCanvas(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      context.read<ProjectProvider>().importImageToCanvas(result.files.single.path!);
    }
  }

  void _showLayerPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SizedBox(
        height: 300,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              Text('menu.layer'.tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () { context.read<ProjectProvider>().addLayer(); }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.of(ctx).pop(), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            ]),
          ),
          const Divider(height: 4),
          const Expanded(child: LayerPanel()),
        ]),
      ),
    );
  }

}

// ─── Wide (landscape/desktop) layout ───────────────────────────

class _WideLayout extends StatefulWidget {
  final Project project;
  final bool showRightPanel;
  final VoidCallback onToggleRightPanel;
  final VoidCallback onExit;

  const _WideLayout({
    required this.project,
    required this.showRightPanel,
    required this.onToggleRightPanel,
    required this.onExit,
  });

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    final theme = Theme.of(context);
    final rightPanel = Material(
      elevation: 4,
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: 180,
        child: Column(children: [
          Row(children: [
            const Spacer(),
            IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: widget.onToggleRightPanel,
              tooltip: 'app.hide_panels'.tr(), visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: const EdgeInsets.all(4)),
          ]),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColorPanel(toolProvider: toolProvider),
                  const BrushPanel(),
                  const LayerPanel(),
                ],
              ),
            ),
          ),
        ]),
      ),
    );

    return Column(children: [
      Row(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: widget.onExit,
            tooltip: 'app.exit'.tr(),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: const EdgeInsets.all(4),
          ),
        ),
        const Expanded(child: EditorMenuBar()),
      ]),
      const ImageEditToolbar(),
      Expanded(child: SafeArea(child: Stack(
        children: [
          Row(children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Expanded(child: ToolPanel(toolProvider: toolProvider)),
            ]),
            Expanded(child: Padding(padding: const EdgeInsets.all(4), child: PaintCanvas(project: widget.project))),
            if (!widget.showRightPanel)
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: widget.onToggleRightPanel,
                  tooltip: 'app.show_panels'.tr(), visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28), padding: const EdgeInsets.all(4)),
              ]),
            if (widget.showRightPanel) rightPanel,
          ]),
          const SelectionPanel(),
          const ReferenceFloatingWindow(),
          const CanvasZoomOverlay(),
        ],
      ))),
    ]);
  }
}

// ─── Narrow (portrait/mobile) layout ───────────────────────────

class _NarrowLayout extends StatelessWidget {
  final Project project;
  final VoidCallback showMenu;
  final VoidCallback showLayerPanel;
  final VoidCallback onExit;

  const _NarrowLayout({
    required this.project,
    required this.showMenu,
    required this.showLayerPanel,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    return Column(children: [
      _TopBar(showMenu: showMenu, showLayerPanel: showLayerPanel, onExit: onExit),
      const ImageEditToolbar(),
      Expanded(child: SafeArea(child: Stack(
        children: [
          Row(children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Expanded(child: ToolPanel(toolProvider: toolProvider, portrait: true)),
            ]),
            Expanded(child: Padding(padding: const EdgeInsets.all(4), child: PaintCanvas(project: project))),
          ]),
          const SelectionPanel(),
          const ReferenceFloatingWindow(),
          const CanvasZoomOverlay(),
        ],
      ))),
    ]);
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback showMenu;
  final VoidCallback showLayerPanel;
  final VoidCallback onExit;
  const _TopBar({required this.showMenu, required this.showLayerPanel, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final name = pp.currentProject?.name ?? '';
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: onExit,
          tooltip: 'app.exit'.tr(),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
        ),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.layers, size: 18),
          onPressed: showLayerPanel,
          tooltip: 'menu.layer'.tr(),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz, size: 18),
          onPressed: showMenu,
          tooltip: 'menu.menu'.tr(),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.all(4),
        ),
      ]),
    );
  }
}


