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
                Row(
                  children: [
                    Text('layer.panel'.tr(), style: theme.textTheme.labelMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () => provider.addLayer(),
                      tooltip: 'layer.new'.tr(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
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
                      return _LayerItem(
                        layer: layer,
                        isCurrent: isCurrent,
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

class _LayerItem extends StatelessWidget {
  final Layer layer;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMergeDown;
  final ValueChanged<double> onOpacityChanged;

  const _LayerItem({
    required this.layer,
    required this.isCurrent,
    required this.onTap,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMergeDown,
    required this.onOpacityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onSecondaryTap: () => _showContextMenu(context),
      onLongPress: () => _showContextMenu(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: isCurrent ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: isCurrent
              ? Border.all(color: theme.colorScheme.primary, width: 1)
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Icon(
                  layer.visible ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    layer.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (layer.locked)
                  Icon(Icons.lock, size: 12, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 100, 100),
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
        PopupMenuItem(value: 'opacity', child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.opacity, size: 18),
                title: Text('layer.opacity'.tr()),
                subtitle: Slider(
                  value: layer.opacity,
                  min: 0, max: 1,
                  divisions: 100,
                  label: '${(layer.opacity * 100).round()}%',
                  onChanged: (v) {
                    onOpacityChanged(v);
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
        case 'delete': onDelete();
        case 'merge': onMergeDown();
        case 'duplicate': onDuplicate();
      }
    });
  }
}
