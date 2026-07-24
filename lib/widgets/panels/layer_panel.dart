import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/project_provider.dart';
import '../../models/layer.dart';

class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ProjectProvider>(
      builder: (ctx, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<ProjectProvider>(
                  builder: (ctx, pp, _) {
                    final canMoveUp = pp.currentProject != null &&
                        pp.currentProject!.currentLayerIndex < pp.currentProject!.layers.length - 1;
                    final canMoveDown = pp.currentProject != null &&
                        pp.currentProject!.currentLayerIndex > 0;
                    return Row(
                      children: [
                        Text('layer.panel'.tr(), style: theme.textTheme.labelMedium),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: canMoveUp
                              ? () { pp.saveSnapshot(); pp.moveLayerUp(pp.currentProject!.currentLayerIndex); }
                              : null,
                          tooltip: 'menu.layer.move_up'.tr(),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: canMoveDown
                              ? () { pp.saveSnapshot(); pp.moveLayerDown(pp.currentProject!.currentLayerIndex); }
                              : null,
                          tooltip: 'menu.layer.move_down'.tr(),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => provider.addLayer(),
                          tooltip: 'layer.new'.tr(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 8),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: project.layers.length,
                    itemBuilder: (ctx, i) {
                      final idx = project.layers.length - 1 - i;
                      final layer = project.layers[idx];
                      final isCurrent = project.currentLayerIndex == idx;
                      final isBg = idx == 0;
                      final bgColor = isBg && layer.drawables.isNotEmpty
                          ? layer.drawables.first.color
                          : null;
                      return _LayerItem(
                        layer: layer,
                        isCurrent: isCurrent,
                        index: idx,
                        isBackground: isBg,
                        bgColor: bgColor,
                        onBgColorTap: isBg ? () => _showBgColorPicker(ctx, provider, bgColor!) : null,
                        onTap: () => provider.setCurrentLayer(idx),
                        onDelete: () => provider.deleteLayer(idx),
                        onDuplicate: () => provider.duplicateLayer(idx),
                        onMergeDown: () => provider.mergeDownLayer(idx),
                        onOpacityChanged: (v) => provider.setLayerOpacity(idx, v),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LayerItem extends StatefulWidget {
  final Layer layer;
  final bool isCurrent;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMergeDown;
  final ValueChanged<double> onOpacityChanged;
  final bool isBackground;
  final Color? bgColor;
  final VoidCallback? onBgColorTap;

  const _LayerItem({
    required this.layer,
    required this.isCurrent,
    required this.index,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMergeDown,
    required this.onOpacityChanged,
    this.isBackground = false,
    this.bgColor,
    this.onBgColorTap,
  });

  @override
  State<_LayerItem> createState() => _LayerItemState();
}

class _LayerItemState extends State<_LayerItem> {
  Offset? _tapPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pp = context.read<ProjectProvider>();
    return GestureDetector(
      onSecondaryTapDown: (d) => _tapPosition = d.globalPosition,
      onSecondaryTap: () {
        if (!widget.isBackground) _showContextMenu(context);
      },
      onLongPressStart: (d) => _tapPosition = d.globalPosition,
      onLongPress: () {
        if (!widget.isBackground) _showContextMenu(context);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: widget.isCurrent ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: widget.isCurrent
              ? Border.all(color: theme.colorScheme.primary, width: 1)
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => pp.toggleLayerVisibility(widget.index),
                  child: Icon(
                    widget.layer.visible ? Icons.visibility : Icons.visibility_off,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onDoubleTap: () {
                      if (!widget.isBackground) _renameLayer(context, pp);
                    },
                    child: Text(
                      widget.layer.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: widget.isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (widget.isBackground && widget.bgColor != null)
                  GestureDetector(
                    onTap: widget.onBgColorTap,
                    child: Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline, width: 1),
                      ),
                    ),
                  ),
                if (widget.layer.locked)
                  Icon(Icons.lock, size: 12, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final pos = _tapPosition ?? Offset(100, 100);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'delete', child: ListTile(
          leading: const Icon(Icons.delete, size: 18),
          title: Text('layer.delete'.tr()),
          dense: true,
        )),
        PopupMenuItem(value: 'merge', child: ListTile(
          leading: const Icon(Icons.merge, size: 18),
          title: Text('layer.merge_down'.tr()),
          dense: true,
        )),
        PopupMenuItem(value: 'duplicate', child: ListTile(
          leading: const Icon(Icons.copy, size: 18),
          title: Text('layer.duplicate'.tr()),
          dense: true,
        )),
        PopupMenuItem(value: 'blend', child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.color_lens, size: 18),
                title: Text('layer.blend_mode'.tr()),
                subtitle: Text('layer.${widget.layer.blendMode.name}'.tr()),
                dense: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showBlendModeMenu(context);
                },
              ),
            ],
          ),
        )),
        PopupMenuItem(value: 'opacity', child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.opacity, size: 18),
                title: Text('layer.opacity'.tr()),
                subtitle: Slider(
                  value: widget.layer.opacity,
                  min: 0, max: 1,
                  divisions: 100,
                  label: '${(widget.layer.opacity * 100).round()}%',
                  onChanged: (v) {
                    widget.onOpacityChanged(v);
                    setState(() {});
                  },
                ),
                dense: true,
              ),
            ],
          ),
        )),
      ],
    ).then((value) {
      switch (value) {
        case 'delete': widget.onDelete();
        case 'merge': widget.onMergeDown();
        case 'duplicate': widget.onDuplicate();
      }
    });
  }

  void _showBlendModeMenu(BuildContext context) {
    final pp = context.read<ProjectProvider>();
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
      items: BlendModeExt.values.map((mode) {
        return PopupMenuItem<BlendModeExt>(
          value: mode,
          child: ListTile(
            leading: Icon(
              widget.layer.blendMode == mode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
            ),
            title: Text('layer.${mode.name}'.tr()),
            dense: true,
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null) {
        pp.setLayerBlendMode(widget.index, value);
      }
    });
  }

  void _renameLayer(BuildContext context, ProjectProvider pp) {
    final controller = TextEditingController(text: widget.layer.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('layer.rename'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              pp.renameLayer(widget.index, controller.text);
              Navigator.of(ctx).pop();
            },
            child: Text('dialog.confirm'.tr()),
          ),
        ],
      ),
    );
  }
}

void _showBgColorPicker(BuildContext context, ProjectProvider pp, Color currentBg) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Background Color'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: currentBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: theme.colorScheme.outline)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: [
                Colors.white, Colors.black, Colors.grey, Colors.red,
                Colors.orange, Colors.yellow, Colors.green, Colors.cyan,
                Colors.blue, Colors.indigo, Colors.purple, Colors.brown,
              ].map((c) => GestureDetector(
                onTap: () {
                  pp.setBackgroundColor(c);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c == currentBg ? theme.colorScheme.primary : theme.colorScheme.outline, width: c == currentBg ? 2 : 1),
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('dialog.cancel'.tr())),
      ],
    ),
  );
}
