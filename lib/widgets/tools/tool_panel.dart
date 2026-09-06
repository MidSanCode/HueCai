import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/app_settings.dart';
import '../../models/drawable.dart';
import '../../models/brush.dart';
import '../panels/color_panel.dart';

class ToolPanel extends StatefulWidget {
  final ToolProvider toolProvider;
  final bool portrait;

  const ToolPanel({super.key, required this.toolProvider, this.portrait = false});

  @override
  State<ToolPanel> createState() => _ToolPanelState();
}

class _ToolPanelState extends State<ToolPanel> {
  bool _isDraggingBrush = false;
  double _dragStartValue = 0;
  double _dragStartY = 0;

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
    final tp = context.watch<ToolProvider>();

    List<ToolType> toolTypes;
    if (widget.portrait) {
      toolTypes = [ToolType.brush, ToolType.eraser, ToolType.shape, ToolType.willowLeaf];
    } else {
      toolTypes = context.watch<AppSettings>().toolbarToolTypes;
    }

    return Container(
      width: 48,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ...List.generate(toolTypes.length, (i) {
            final type = toolTypes[i];
            if (type == ToolType.shape) return _shapeBtn(context, tp);
            return _toolBtn(context, type, tp);
          }),
          if (tp.currentTool == ToolType.gradient) ...[
            const SizedBox(height: 4),
            _gradientControls(context),
            const SizedBox(height: 4),
          ],
          if (widget.portrait) ...[
            const SizedBox(height: 4),
            _brushControls(context),
            const SizedBox(height: 4),
            _colorPanelTrigger(context),
          ],
          // Selection panel is now shown via SelectionPanel widget
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _toolBtn(BuildContext context, ToolType type, ToolProvider tp) {
    final theme = Theme.of(context);
    // Symmetry / perspective are toggles, not transient tools: they show a
    // checked state while enabled, and picking them doesn't leave the
    // current drawing tool.
    final isToggle = type == ToolType.symmetry ||
        type == ToolType.perspectiveGuide;
    final active = isToggle
        ? (type == ToolType.symmetry
            ? tp.symmetryEnabled
            : tp.perspectiveGuideEnabled)
        : tp.currentTool == type;
    final selected = active;
    final isBrushLike = type == ToolType.brush || type == ToolType.eraser || type == ToolType.smudge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Tooltip(
        message: _toolLabels[type]?.tr() ?? '',
        child: Material(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (isToggle) {
                if (type == ToolType.symmetry) {
                  tp.toggleSymmetry();
                } else {
                  tp.togglePerspectiveGuide();
                }
                setState(() {});
                return;
              }
              if (isBrushLike && selected) {
                _showBrushMenu(context, tp);
              } else {
                tp.setTool(type);
                if (type == ToolType.select) {
                  // Enter marquee mode right away with a fresh selection.
                  context.read<ProjectProvider>().enterSelectionMode();
                }
              }
            },
            child: SizedBox(
              width: 40, height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(_toolIcons[type], size: 22,
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant),
                  if (isToggle && selected)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBrushMenu(BuildContext context, ToolProvider tp) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('brush.panel'.tr(), style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: Brush.defaults().map((brush) {
                    final selected = tp.brushType == brush.type;
                    return FilterChip(
                      label: Text(brush.nameKey.tr(), style: const TextStyle(fontSize: 10)),
                      selected: selected,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        tp.setBrushType(brush.type);
                        Navigator.of(ctx).pop();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientControls(BuildContext context) {
    final tp = widget.toolProvider;
    final theme = Theme.of(context);
    void pick(bool start) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) => ColorPanel(
          toolProvider: tp,
          currentColor: start ? tp.gradientStartColor : tp.gradientEndColor,
          onPick: (c) {
            if (start) {
              tp.setGradientStartColor(c);
            } else {
              tp.setGradientEndColor(c);
            }
          },
        ),
      );
    }

    Widget swatch(Color c, VoidCallback onTap, String tip) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
          child: Tooltip(
            message: tip,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 32,
                height: 22,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.outline, width: 1),
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        swatch(tp.gradientStartColor, () => pick(true), 'tool.gradient_start'.tr()),
        const Icon(Icons.arrow_downward, size: 12),
        swatch(tp.gradientEndColor, () => pick(false), 'tool.gradient_end'.tr()),
      ],
    );
  }

  Widget _brushControls(BuildContext context) {
    final tp = widget.toolProvider;
    return Column(
      children: [
        _brushSlider(
          icon: Icons.circle,
          value: tp.brushSize,
          min: 0.5, max: 100,
          label: tp.brushSize.toStringAsFixed(1),
          onChange: (v) => tp.setBrushSize(v),
        ),
        _brushSlider(
          icon: Icons.opacity,
          value: tp.brushOpacity,
          min: 0.0, max: 1.0,
          label: '${(tp.brushOpacity * 100).round()}%',
          onChange: (v) => tp.setBrushOpacity(v),
        ),
      ],
    );
  }

  Widget _brushSlider({
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChange,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: GestureDetector(
        onLongPressStart: (d) {
          _isDraggingBrush = true;
          _dragStartValue = value;
          _dragStartY = d.globalPosition.dy;
        },
        onLongPressMoveUpdate: (d) {
          if (!_isDraggingBrush) return;
          final deltaY = _dragStartY - d.globalPosition.dy;
          final range = max - min;
          final newValue = (_dragStartValue + deltaY * range / 200).clamp(min, max);
          onChange(newValue);
        },
        onLongPressEnd: (_) {
          _isDraggingBrush = false;
        },
        child: Tooltip(
          message: label,
          child: Container(
            width: 40, height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(label, style: const TextStyle(fontSize: 9, height: 1)),
          ),
        ),
      ),
    );
  }

  Widget _shapeBtn(BuildContext context, ToolProvider tp) {
    final theme = Theme.of(context);
    final isShapeTool = tp.currentTool == ToolType.shape;
    final shapeIcon = _shapeIcon(tp.currentShape);
    final shapeLabel = _toolLabels[ToolType.shape]?.tr() ?? 'tool.shape'.tr();
    final currentShapeLabel = _shapeLabel(tp.currentShape).tr();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Tooltip(
        message: isShapeTool ? currentShapeLabel : shapeLabel,
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

  String _shapeLabel(ShapeType type) {
    switch (type) {
      case ShapeType.rect: return 'tool.rect';
      case ShapeType.ellipse: return 'tool.ellipse';
      case ShapeType.polygon: return 'shape.polygon';
      case ShapeType.line: return 'shape.line';
      case ShapeType.curve: return 'shape.curve';
    }
  }

  Widget _colorPanelTrigger(BuildContext context) {
    final tp = widget.toolProvider;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            builder: (ctx) => ColorPanel(toolProvider: tp),
          );
        },
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: tp.primaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.primary, width: 2),
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
