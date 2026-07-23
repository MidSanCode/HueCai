import 'package:flutter/material.dart';
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

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _toolProvider),
        ChangeNotifierProvider.value(value: _canvasProvider),
      ],
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
                const EditorMenuBar(),
                Expanded(
                  child: isDesktop
                      ? _DesktopLayout(project: project)
                      : _MobileLayout(project: project),
                ),
                if (!isDesktop)
                  _mobileBottomBar(_canvasProvider),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _mobileBottomBar(CanvasProvider canvasProvider) {
  return Builder(builder: (context) {
    return Container(
      height: 48,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(icon: const Icon(Icons.undo), onPressed: () {
            context.read<ProjectProvider>().history.undo();
          }, tooltip: 'menu.edit.undo'.tr()),
          IconButton(icon: const Icon(Icons.redo), onPressed: () {
            context.read<ProjectProvider>().history.redo();
          }, tooltip: 'menu.edit.redo'.tr()),
          IconButton(icon: const Icon(Icons.zoom_in), onPressed: canvasProvider.zoomIn, tooltip: 'menu.view.zoom_in'.tr()),
          IconButton(icon: const Icon(Icons.zoom_out), onPressed: canvasProvider.zoomOut, tooltip: 'menu.view.zoom_out'.tr()),
          IconButton(icon: const Icon(Icons.brush), onPressed: () {
            context.read<ToolProvider>().setTool(ToolType.brush);
          }, tooltip: 'menu.tool.brush'.tr()),
        ],
      ),
    );
  });
}

class _DesktopLayout extends StatelessWidget {
  final dynamic project;

  const _DesktopLayout({required this.project});

  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    return Row(
      children: [
        Column(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
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
              },
              tooltip: '返回工作区',
            ),
            Expanded(child: ToolPanel(toolProvider: toolProvider)),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: PaintCanvas(project: project),
          ),
        ),
        SizedBox(
          width: 180,
          child: Column(
            children: [
              ColorPanel(toolProvider: toolProvider),
              const BrushPanel(),
              const Expanded(child: LayerPanel()),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final dynamic project;

  const _MobileLayout({required this.project});

  @override
  Widget build(BuildContext context) {
    final toolProvider = context.watch<ToolProvider>();
    return Stack(
      children: [
        PaintCanvas(project: project),
        Positioned(left: 4, top: 8, child: ToolPanel(toolProvider: toolProvider)),
        Positioned(right: 4, top: 8, child: ColorPanel(toolProvider: toolProvider)),
        Positioned(
          right: 4, bottom: 8,
          child: SizedBox(width: 160, height: 150, child: LayerPanel()),
        ),
        Positioned(
          left: 4, bottom: 8,
          child: _backButton(context),
        ),
      ],
    );
  }
}

Widget _backButton(BuildContext context) {
  return FloatingActionButton.small(
    heroTag: 'back',
    onPressed: () {
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
    },
    child: const Icon(Icons.arrow_back),
  );
}
