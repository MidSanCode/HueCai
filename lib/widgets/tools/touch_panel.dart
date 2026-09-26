import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/tool_provider.dart';

/// Touch-first floating panel (roadmap item 17).
///
/// A finger-sized companion to the desktop chrome: the handful of controls
/// that are needed mid-stroke (tool, size, opacity, undo, colour) reachable
/// without aiming at a 20px icon. Draggable so it never has to sit over the
/// artwork.
class TouchPanel extends StatefulWidget {
  const TouchPanel({super.key});

  @override
  State<TouchPanel> createState() => _TouchPanelState();
}

class _TouchPanelState extends State<TouchPanel> {
  Offset _position = const Offset(12, 96);

  static const List<ToolType> _tools = [
    ToolType.brush,
    ToolType.eraser,
    ToolType.smudge,
    ToolType.fill,
    ToolType.eyedropper,
    ToolType.move,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tp = context.watch<ToolProvider>();
    final settings = context.watch<AppSettings>();
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        // Dragging the grip moves the panel; the buttons keep their own taps.
        onPanUpdate: (d) => setState(() {
          _position = Offset(
            (_position.dx + d.delta.dx).clamp(0.0, 2400.0),
            (_position.dy + d.delta.dy).clamp(0.0, 1600.0),
          );
        }),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          child: Container(
            width: 190,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.drag_indicator, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'touch.panel'.tr(),
                      style: const TextStyle(fontSize: 11),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: 'touch.close'.tr(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                        onPressed: () =>
                            settings.setTouchPanelEnabled(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final tool in _tools)
                      _toolButton(tp, theme, tool),
                  ],
                ),
                const Divider(height: 10),
                _stepper(
                  theme,
                  icon: Icons.brush,
                  label: tp.brushSize.toStringAsFixed(0),
                  onMinus: () => tp.setBrushSize(tp.brushSize - 2),
                  onPlus: () => tp.setBrushSize(tp.brushSize + 2),
                  tooltip: 'touch.size'.tr(),
                ),
                _stepper(
                  theme,
                  icon: Icons.opacity,
                  label: '${(tp.brushOpacity * 100).round()}%',
                  onMinus: () => tp.setBrushOpacity(tp.brushOpacity - 0.1),
                  onPlus: () => tp.setBrushOpacity(tp.brushOpacity + 0.1),
                  tooltip: 'touch.opacity'.tr(),
                ),
                const Divider(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _bigButton(
                      icon: Icons.undo,
                      tooltip: 'menu.edit.undo'.tr(),
                      onTap: () => context.read<ProjectProvider>().undo(),
                    ),
                    _bigButton(
                      icon: Icons.redo,
                      tooltip: 'menu.edit.redo'.tr(),
                      onTap: () => context.read<ProjectProvider>().redo(),
                    ),
                    _bigButton(
                      icon: Icons.zoom_out,
                      tooltip: 'menu.view.zoom_out'.tr(),
                      onTap: () => context.read<CanvasProvider>().zoomOut(),
                    ),
                    _bigButton(
                      icon: Icons.zoom_in,
                      tooltip: 'menu.view.zoom_in'.tr(),
                      onTap: () => context.read<CanvasProvider>().zoomIn(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolButton(ToolProvider tp, ThemeData theme, ToolType tool) {
    final selected = tp.currentTool == tool;
    return Tooltip(
      message: _toolLabel(tool),
      child: InkWell(
        onTap: () => tp.setTool(tool),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Icon(_toolIcon(tool), size: 22),
        ),
      ),
    );
  }

  Widget _stepper(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required String tooltip,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        _smallButton(Icons.remove, tooltip, onMinus),
        Expanded(
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        ),
        _smallButton(Icons.add, tooltip, onPlus),
      ],
    );
  }

  Widget _smallButton(IconData icon, String tooltip, VoidCallback onTap) =>
      SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          icon: Icon(icon, size: 16),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: onTap,
        ),
      );

  Widget _bigButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          onPressed: onTap,
        ),
      );

  String _toolLabel(ToolType tool) => switch (tool) {
        ToolType.brush => 'tool.brush'.tr(),
        ToolType.eraser => 'tool.eraser'.tr(),
        ToolType.smudge => 'tool.smudge'.tr(),
        ToolType.fill => 'tool.fill'.tr(),
        ToolType.eyedropper => 'tool.eyedropper'.tr(),
        ToolType.move => 'tool.move'.tr(),
        _ => tool.name,
      };

  IconData _toolIcon(ToolType tool) => switch (tool) {
        ToolType.brush => Icons.brush,
        ToolType.eraser => Icons.cleaning_services,
        ToolType.smudge => Icons.blur_on,
        ToolType.fill => Icons.format_color_fill,
        ToolType.eyedropper => Icons.colorize,
        ToolType.move => Icons.open_with,
        _ => Icons.circle,
      };
}
