import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../providers/tool_provider.dart';
import '../../models/drawable.dart';

class ToolPanel extends StatelessWidget {
  final ToolProvider toolProvider;

  const ToolPanel({super.key, required this.toolProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShapeTool = toolProvider.currentTool == ToolType.shape;
    final shapeIcon = _shapeIcon(toolProvider.currentShape);

    return Container(
      width: 48,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _toolBtn(context, ToolType.move, Icons.open_with, 'tool.move'),
          _shapeBtn(context, shapeIcon, isShapeTool),
          _toolBtn(context, ToolType.pen, Icons.edit, 'tool.pen'),
          _toolBtn(context, ToolType.text, Icons.text_fields, 'tool.text'),
          _toolBtn(context, ToolType.select, Icons.crop_square, 'tool.select'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Divider(height: 8),
          ),
          _toolBtn(context, ToolType.brush, Icons.brush, 'tool.brush'),
          _toolBtn(context, ToolType.eraser, Icons.auto_fix_normal, 'tool.eraser'),
          _toolBtn(context, ToolType.fill, Icons.format_color_fill, 'tool.fill'),
          _toolBtn(context, ToolType.gradient, Icons.gradient, 'tool.gradient'),
          _toolBtn(context, ToolType.eyedropper, Icons.colorize, 'tool.eyedropper'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _toolBtn(BuildContext context, ToolType type, IconData icon, String labelKey) {
    final theme = Theme.of(context);
    final selected = toolProvider.currentTool == type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Tooltip(
        message: labelKey.tr(),
        child: Material(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => toolProvider.setTool(type),
            child: SizedBox(
              width: 40, height: 40,
              child: Icon(icon, size: 22,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shapeBtn(BuildContext context, IconData icon, bool isShapeTool) {
    final theme = Theme.of(context);
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
                toolProvider.setTool(ToolType.shape);
              }
            },
            onLongPress: () => _showShapeMenu(context),
            child: SizedBox(
              width: 40, height: 40,
              child: Icon(icon, size: 22,
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
                selected: toolProvider.currentShape == e.key,
                onTap: () {
                  toolProvider.setShape(e.key);
                  Navigator.of(ctx).pop();
                },
              );
            }),
            const Divider(),
            SwitchListTile(
              title: Text('tool.standard_mode'.tr()),
              subtitle: Text('tool.standard_mode_hint'.tr()),
              value: toolProvider.isStandardMode,
              onChanged: (_) {
                toolProvider.toggleStandardMode();
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
