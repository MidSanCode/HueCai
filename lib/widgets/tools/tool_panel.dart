import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../providers/app_settings.dart';
import '../../models/drawable.dart';
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
    final tp = widget.toolProvider;

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
          if (widget.portrait) ...[
            const SizedBox(height: 4),
            _brushControls(context),
            const SizedBox(height: 4),
            _colorPanelTrigger(context),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _toolBtn(BuildContext context, ToolType type, ToolProvider tp) {
    final theme = Theme.of(context);
    final selected = tp.currentTool == type;
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
