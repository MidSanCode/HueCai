import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/project_provider.dart';
import '../providers/tool_provider.dart';
import '../providers/canvas_provider.dart';
import '../widgets/menu_bar.dart';
import '../widgets/tools/tool_panel.dart';
import '../widgets/panels/color_panel.dart';
import '../widgets/panels/layer_panel.dart';
import '../widgets/panels/brush_panel.dart';
import '../widgets/canvas/paint_canvas.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final CanvasProvider _canvasProvider;
  late final ToolProvider _toolProvider;
  bool _showRightPanel = false;

  @override
  void initState() {
    super.initState();
    _canvasProvider = CanvasProvider();
    _toolProvider = ToolProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().startBackupTimer();
    });
  }

  @override
  void dispose() {
    context.read<ProjectProvider>().stopBackupTimer();
    _canvasProvider.dispose();
    _toolProvider.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final pp = context.read<ProjectProvider>();
    if (!pp.hasUnsavedChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('unsaved.title'.tr()),
        content: Text('unsaved.body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: Text('unsaved.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: Text('unsaved.discard'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: Text('unsaved.save'.tr()),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await pp.saveProject();
      return true;
    }
    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectProvider>().currentProject;
    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('No project')),
        body: const Center(child: Text('No project open')),
      );
    }

    final isDesktop = [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ].contains(Theme.of(context).platform);

    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _toolProvider),
        ChangeNotifierProvider.value(value: _canvasProvider),
      ],
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.keyZ, control: true):
              () => context.read<ProjectProvider>().undo(),
          SingleActivator(LogicalKeyboardKey.keyY, control: true):
              () => context.read<ProjectProvider>().redo(),
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    EditorMenuBar(compact: !isDesktop && !isWide),
                    Expanded(
                      child: _EditorLayout(
                        project: project,
                        showRightPanel: isDesktop || isWide || _showRightPanel,
                        onToggleRightPanel: () =>
                            setState(() => _showRightPanel = !_showRightPanel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorLayout extends StatelessWidget {
  final dynamic project;
  final bool showRightPanel;
  final VoidCallback onToggleRightPanel;

  const _EditorLayout({
    required this.project,
    required this.showRightPanel,
    required this.onToggleRightPanel,
  });

  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    final theme = Theme.of(context);

    return Row(
      children: [
        // Left: back button + tool panel
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => _goBack(context),
              tooltip: 'app.exit'.tr(),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.all(6),
            ),
            Expanded(child: ToolPanel(toolProvider: toolProvider)),
          ],
        ),
        // Center: canvas
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: PaintCanvas(project: project),
          ),
        ),
        // Toggle button for right panel (mobile)
        if (!showRightPanel)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: onToggleRightPanel,
                tooltip: 'app.show_panels'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
        // Right: color, brush, layer panels
        if (showRightPanel)
          Material(
            elevation: 4,
            color: theme.colorScheme.surface,
            child: SizedBox(
              width: 180,
              child: Column(
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        onPressed: onToggleRightPanel,
                        tooltip: 'app.hide_panels'.tr(),
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                  ColorPanel(toolProvider: toolProvider),
                  const BrushPanel(),
                  const Expanded(child: LayerPanel()),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _goBack(BuildContext context) {
    final pp = context.read<ProjectProvider>();
    if (pp.hasUnsavedChanges) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('unsaved.title'.tr()),
          content: Text('unsaved.body'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('unsaved.cancel'.tr()),
            ),
            TextButton(
              onPressed: () {
                pp.closeProject();
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: Text('unsaved.discard'.tr()),
            ),
            FilledButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await pp.saveProject();
                if (ctx.mounted) Navigator.of(ctx).pop();
                nav.pop();
              },
              child: Text('unsaved.save'.tr()),
            ),
          ],
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }
}