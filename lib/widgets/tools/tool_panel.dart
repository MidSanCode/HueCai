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
          _toolBtn(context, ToolType.eyedropper, Icons.colorize, 'tool.eyedropper'),
          const Spacer(),
          _standardModeToggle(context),
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
    final shapes = [
      (ShapeType.rect, Icons.rectangle_outlined, '矩形'),
      (ShapeType.ellipse, Icons.circle_outlined, '椭圆'),
      (ShapeType.polygon, Icons.change_history, '多边形'),
      (ShapeType.line, Icons.horizontal_rule, '直线'),
      (ShapeType.curve, Icons.timeline, '曲线'),
    ];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: shapes.map((s) {
          return ListTile(
            leading: Icon(s.$2),
            title: Text(s.$3),
            selected: toolProvider.currentShape == s.$1,
            onTap: () {
              toolProvider.setShape(s.$1);
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _standardModeToggle(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Tooltip(
        message: '标准模式',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => toolProvider.toggleStandardMode(),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: toolProvider.isStandardMode
                  ? theme.colorScheme.tertiaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: toolProvider.isStandardMode
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.checklist,
              size: 20,
              color: toolProvider.isStandardMode
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
