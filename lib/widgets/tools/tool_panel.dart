import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/app_settings.dart';
import '../../models/drawable.dart';

class ToolPanel extends StatefulWidget {
  final ToolProvider toolProvider;

  const ToolPanel({super.key, required this.toolProvider});

  @override
  State<ToolPanel> createState() => _ToolPanelState();
}

class _ToolPanelState extends State<ToolPanel> {
  final LayerLink _layerLink = LayerLink();

  static const Map<ToolType, IconData> _toolIcons = {
    ToolType.move: Icons.open_with,
    ToolType.shape: Icons.rectangle_outlined,
    ToolType.pen: Icons.edit,
    ToolType.text: Icons.text_fields,
    ToolType.select: Icons.crop_square,
    ToolType.brush: Icons.brush,
    ToolType.eraser: Icons.auto_fix_normal,
    ToolType.fill: Icons.format_color_fill,
    ToolType.gradient: Icons.gradient,
    ToolType.eyedropper: Icons.colorize,
    ToolType.smudge: Icons.blur_on,
    ToolType.willowLeaf: Icons.eco,
    ToolType.liquify: Icons.waves,
    ToolType.perspectiveGuide: Icons.grid_on,
    ToolType.symmetry: Icons.flip,
  };

  static const Map<ToolType, String> _toolLabels = {
    ToolType.move: 'tool.move',
    ToolType.shape: 'tool.shape',
    ToolType.pen: 'tool.pen',
    ToolType.text: 'tool.text',
    ToolType.select: 'tool.select',
    ToolType.brush: 'tool.brush',
    ToolType.eraser: 'tool.eraser',
    ToolType.fill: 'tool.fill',
    ToolType.gradient: 'tool.gradient',
    ToolType.eyedropper: 'tool.eyedropper',
    ToolType.smudge: 'tool.smudge',
    ToolType.willowLeaf: 'tool.willow_leaf',
    ToolType.liquify: 'tool.liquify',
    ToolType.perspectiveGuide: 'tool.perspective_guide',
    ToolType.symmetry: 'tool.symmetry',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appSettings = context.watch<AppSettings>();
    final toolTypes = appSettings.toolbarToolTypes;
    final isSelectTool = widget.toolProvider.currentTool == ToolType.select;
    final selectedDrawable = context.watch<ProjectProvider>().selectedDrawable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          color: theme.colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              const SizedBox(height: 8),
              ...List.generate(toolTypes.length, (i) {
                final type = toolTypes[i];
                if (type == ToolType.shape) {
                  return _shapeBtn(context, isSelectTool, widget.toolProvider);
                }
                return _toolBtn(context, type, isSelectTool, widget.toolProvider);
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
        if (isSelectTool)
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.topRight,
            followerAnchor: Alignment.topLeft,
            child: _SelectConfigMenu(
              selectedDrawable: selectedDrawable,
              toolProvider: widget.toolProvider,
            ),
          ),
        if (isSelectTool)
          CompositedTransformTarget(link: _layerLink, child: const SizedBox.shrink()),
      ],
    );
  }

  Widget _toolBtn(BuildContext context, ToolType type, bool isSelectTool, ToolProvider tp) {
    final theme = Theme.of(context);
    final selected = tp.currentTool == type;
    if (type == ToolType.select) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Tooltip(
          message: _toolLabels[type]?.tr() ?? '',
          child: CompositedTransformTarget(
            link: _layerLink,
            child: Material(
              color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  tp.setTool(type);
                },
                child: SizedBox(
                  width: 40, height: 40,
                  child: Icon(_toolIcons[type], size: 22,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Tooltip(
        message: _toolLabels[type]?.tr() ?? '',
        child: Material(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => tp.setTool(type),
            child: SizedBox(
              width: 40, height: 40,
              child: Icon(_toolIcons[type], size: 22,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shapeBtn(BuildContext context, bool isSelectTool, ToolProvider tp) {
    final theme = Theme.of(context);
    final isShapeTool = tp.currentTool == ToolType.shape;
    final shapeIcon = _shapeIcon(tp.currentShape);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Tooltip(
        message: 'tool.rect'.tr(),
        child: Material(
          color: isShapeTool ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (isShapeTool) {
                _showShapeMenu(context);
              } else {
                tp.setTool(ToolType.shape);
              }
            },
            onLongPress: () => _showShapeMenu(context),
            child: SizedBox(
              width: 40, height: 40,
              child: Icon(shapeIcon, size: 22,
                color: isShapeTool
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  void _showShapeMenu(BuildContext context) {
    final shapes = {
      ShapeType.rect: 'shape.rect',
      ShapeType.ellipse: 'shape.ellipse',
      ShapeType.polygon: 'shape.polygon',
      ShapeType.line: 'shape.line',
      ShapeType.curve: 'shape.curve',
    };
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...shapes.entries.map((e) {
              return ListTile(
                leading: Icon(_shapeIcon(e.key)),
                title: Text(e.value.tr()),
                selected: widget.toolProvider.currentShape == e.key,
                onTap: () {
                  widget.toolProvider.setShape(e.key);
                  Navigator.of(ctx).pop();
                },
              );
            }),
            const Divider(),
            SwitchListTile(
              title: Text('tool.standard_mode'.tr()),
              subtitle: Text('tool.standard_mode_hint'.tr()),
              value: widget.toolProvider.isStandardMode,
              onChanged: (_) {
                widget.toolProvider.toggleStandardMode();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _shapeIcon(ShapeType type) {
    switch (type) {
      case ShapeType.rect: return Icons.rectangle_outlined;
      case ShapeType.ellipse: return Icons.circle_outlined;
      case ShapeType.polygon: return Icons.change_history;
      case ShapeType.line: return Icons.horizontal_rule;
      case ShapeType.curve: return Icons.timeline;
    }
  }
}

class _SelectConfigMenu extends StatelessWidget {
  final Drawable? selectedDrawable;
  final ToolProvider toolProvider;

  const _SelectConfigMenu({
    required this.selectedDrawable,
    required this.toolProvider,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedDrawable != null;
    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('tool.select'.tr(), style: const TextStyle(fontSize: 11)),
            const Divider(height: 6),
            if (hasSelection) ...[
              SizedBox(
                width: 36, height: 36,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'menu.edit.copy'.tr(),
                  onPressed: () {
                    final pp = context.read<ProjectProvider>();
                    pp.saveSnapshot();
                    pp.selectedDrawable?.copyWith();
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              SizedBox(
                width: 36, height: 36,
                child: IconButton(
                  icon: const Icon(Icons.content_cut, size: 18),
                  tooltip: 'menu.edit.cut'.tr(),
                  onPressed: () {
                    final pp = context.read<ProjectProvider>();
                    if (pp.selectedDrawable != null) {
                      pp.saveSnapshot();
                      pp.deleteDrawable(pp.selectedDrawable!.id);
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              const Divider(height: 6),
            ],
            SizedBox(
              width: 36, height: 36,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'tool.select_deselect'.tr(),
                onPressed: () {
                  context.read<ProjectProvider>().clearSelection();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
