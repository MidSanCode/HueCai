import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/project_provider.dart';
import '../../models/layer.dart';
import '../../models/project.dart';
import '../../services/filter_registry.dart';
import '../../services/image_filters.dart';
import '../dialogs/generic_filter_dialog.dart';

Widget _buildLayerItem(
  BuildContext ctx,
  ProjectProvider provider,
  Project project,
  int idx, {
  bool indented = false,
}) {
  final layer = project.layers[idx];
  final isCurrent = project.currentLayerIndex == idx;
  final isBg = idx == 0;
  final bgColor = isBg && layer.drawables.isNotEmpty
      ? layer.drawables.first.color
      : null;
  final item = _LayerItem(
    layer: layer,
    isCurrent: isCurrent,
    index: idx,
    isBackground: isBg,
    bgColor: bgColor,
    onBgColorTap: isBg ? () => _showBgColorPicker(ctx, provider, bgColor!) : null,
    onTap: () => provider.setCurrentLayer(idx),
    onDelete: () {
      provider.saveSnapshot();
      provider.deleteLayer(idx);
    },
    onDuplicate: () {
      provider.saveSnapshot();
      provider.duplicateLayer(idx);
    },
    onClear: () => provider.clearLayer(idx),
    onMergeDown: () => provider.mergeDownLayer(idx),
    onOpacityChanged: (v) => provider.setLayerOpacity(idx, v),
  );
  if (!indented) return item;
  return Padding(
    padding: const EdgeInsets.only(left: 16),
    child: item,
  );
}

class LayerPanel extends StatelessWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ProjectProvider>(
      builder: (ctx, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox.shrink();

        final canMoveUp = project.currentLayerIndex < project.layers.length - 1;
        final canMoveDown = project.currentLayerIndex > 0;

        return Card(
          margin: const EdgeInsets.all(4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('layer.panel'.tr(), style: theme.textTheme.labelMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      onPressed: canMoveUp
                          ? () { provider.saveSnapshot(); provider.moveLayerUp(project.currentLayerIndex); }
                          : null,
                      tooltip: 'menu.layer.move_up'.tr(),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      onPressed: canMoveDown
                          ? () { provider.saveSnapshot(); provider.moveLayerDown(project.currentLayerIndex); }
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
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                      onPressed: project.layers.isEmpty
                          ? null
                          : () => provider.createGroupFromCurrentLayer(),
                      tooltip: 'layer.new_group'.tr(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const Divider(height: 8),
                SizedBox(
                  height: 120,
                  child: Builder(builder: (ctx) {
                    // Display list, top first: group headers plus (when the
                    // group is expanded) their members, indented.
                    final runs = project.layerRuns().reversed.toList();
                    final items = <Widget>[];
                    for (final run in runs) {
                      if (run.isGroup) {
                        final group = run.group!;
                        items.add(_GroupHeader(
                          group: group,
                          provider: provider,
                        ));
                        if (group.expanded) {
                          for (var i = run.end; i >= run.start; i--) {
                            items.add(_buildLayerItem(ctx, provider, project, i, indented: true));
                          }
                        }
                      } else {
                        items.add(_buildLayerItem(ctx, provider, project, run.singleIndex!));
                      }
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: items,
                    );
                  }),
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
  final VoidCallback onClear;
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
    required this.onClear,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
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
                    if (widget.layer.cloneOfId != null)
                      Icon(Icons.content_copy, size: 12, color: theme.colorScheme.onSurfaceVariant),
                    if (widget.layer.adjustment != null)
                      Icon(Icons.auto_fix_high, size: 12, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
                // Quick actions for the current non-background layer:
                // clear / duplicate / delete / mask + inline opacity slider.
                if (widget.isCurrent && !widget.isBackground)
                  Row(
                    children: [
                      _quickAction(
                        context,
                        Icons.layers_clear,
                        'layer.clear'.tr(),
                        widget.onClear,
                      ),
                      _quickAction(
                        context,
                        Icons.copy,
                        'layer.duplicate'.tr(),
                        widget.onDuplicate,
                      ),
                      _quickAction(
                        context,
                        Icons.delete_outline,
                        'layer.delete'.tr(),
                        widget.onDelete,
                      ),
                      _maskAction(context, pp),
                      Expanded(
                        child: SizedBox(
                          height: 26,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              padding: EdgeInsets.zero,
                            ),
                            child: Slider(
                              value: widget.layer.opacity,
                              min: 0,
                              max: 1,
                              onChanged: widget.onOpacityChanged,
                            ),
                          ),
                        ),
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

  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// Mask quick action: no mask → add one; mask exists → toggle mask editing;
  /// secondary tap → mask menu (enable/disable/remove).
  Widget _maskAction(BuildContext context, ProjectProvider pp) {
    final theme = Theme.of(context);
    final hasMask = widget.layer.maskStrokes != null;
    final editing = pp.maskEditing && widget.isCurrent;
    final disabled = hasMask && !widget.layer.maskEnabled;
    return Tooltip(
      message: hasMask
          ? (editing ? 'layer.mask_editing'.tr() : 'layer.mask_edit'.tr())
          : 'layer.mask_add'.tr(),
      child: GestureDetector(
        onSecondaryTap: hasMask ? () => _showMaskMenu(context, pp) : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (!hasMask) {
              pp.addLayerMask(widget.index);
            } else {
              pp.setMaskEditing(!editing);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              hasMask ? Icons.masks : Icons.masks_outlined,
              size: 15,
              color: editing
                  ? theme.colorScheme.primary
                  : disabled
                      ? theme.colorScheme.outline
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  void _showMaskMenu(BuildContext context, ProjectProvider pp) {
    final pos = _tapPosition ?? const Offset(100, 100);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
          value: 'toggle',
          child: ListTile(
            leading: Icon(
              widget.layer.maskEnabled
                  ? Icons.visibility_off
                  : Icons.visibility,
              size: 18,
            ),
            title: Text(widget.layer.maskEnabled
                ? 'layer.mask_disable'.tr()
                : 'layer.mask_enable'.tr()),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: const Icon(Icons.delete_outline, size: 18),
            title: Text('layer.mask_remove'.tr()),
            dense: true,
          ),
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'toggle':
          pp.toggleLayerMaskEnabled(widget.index);
        case 'remove':
          pp.removeLayerMask(widget.index);
      }
    });
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
        PopupMenuItem(value: 'clear', child: ListTile(
          leading: const Icon(Icons.layers_clear, size: 18),
          title: Text('layer.clear'.tr()),
          dense: true,
        )),
        if (widget.layer.groupId != null)
          PopupMenuItem(value: 'leave_group', child: ListTile(
            leading: const Icon(Icons.drive_file_move_outlined, size: 18),
            title: Text('layer.leave_group'.tr()),
            dense: true,
          )),
        if (widget.layer.cloneOfId == null && widget.layer.adjustment == null)
          PopupMenuItem(value: 'clone', child: ListTile(
            leading: const Icon(Icons.content_copy, size: 18),
            title: Text('layer.clone'.tr()),
            dense: true,
          )),
        PopupMenuItem(value: 'add_adjustment', child: ListTile(
          leading: const Icon(Icons.auto_fix_high, size: 18),
          title: Text('layer.add_adjustment'.tr()),
          dense: true,
        )),
        if (widget.layer.adjustment != null)
          PopupMenuItem(value: 'edit_adjustment', child: ListTile(
            leading: const Icon(Icons.tune, size: 18),
            title: Text('layer.edit_adjustment'.tr()),
            dense: true,
          )),
        PopupMenuItem(value: 'blend', child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.color_lens, size: 18),
                title: Text('layer.blend_mode'.tr()),
                subtitle: Text('layer.${widget.layer.blendMode.jsonName}'.tr()),
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
        case 'clear': widget.onClear();
        case 'leave_group':
          context.read<ProjectProvider>()
              .moveLayerToGroup(widget.index, null);
        case 'clone':
          context.read<ProjectProvider>().addCloneLayer(widget.index);
        case 'add_adjustment':
          _addAdjustmentLayer(context);
        case 'edit_adjustment':
          _editAdjustmentLayer(context);
      }
    });
  }

  /// Picks any registered filter, opens its parameter dialog, then creates
  /// the adjustment layer above this one.
  Future<void> _addAdjustmentLayer(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    final def = await showDialog<FilterDef>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('layer.add_adjustment'.tr()),
        children: [
          for (final group in FilterRegistry.groupKeys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(group.tr(),
                    style: Theme.of(ctx).textTheme.labelSmall),
              ),
            ),
            for (final d in FilterRegistry.inGroup(group))
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(d),
                child: Text(d.labelKey.tr()),
              ),
          ],
        ],
      ),
    );
    if (def == null || !context.mounted) return;
    final params = await pickFilterParams(context, def);
    if (params == null) return;
    pp.addAdjustmentLayer(widget.index, AdjustmentSpec(def.kind, params));
  }

  /// Reopens the parameter dialog for an existing adjustment layer.
  Future<void> _editAdjustmentLayer(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    final current = widget.layer.adjustment;
    if (current == null) return;
    final def = FilterRegistry.byKind(current.kind);
    if (def == null) return;
    final params = await pickFilterParams(context, def, initial: current.params);
    if (params == null) return;
    pp.updateAdjustmentLayer(widget.index, AdjustmentSpec(def.kind, params));
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
            title: Text('layer.${mode.jsonName}'.tr()),
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
      title: Text('layer.bg_color'.tr()),
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

/// Header row for a layer group: expand arrow, visibility eye, name, and a
/// context menu for group operations (rename / opacity / dissolve / delete).
class _GroupHeader extends StatelessWidget {
  final LayerGroup group;
  final ProjectProvider provider;

  const _GroupHeader({required this.group, required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Offset? tapPosition;
    return GestureDetector(
      onSecondaryTapDown: (d) => tapPosition = d.globalPosition,
      onSecondaryTap: () => _showGroupMenu(context, tapPosition),
      onLongPressStart: (d) => tapPosition = d.globalPosition,
      onLongPress: () => _showGroupMenu(context, tapPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => provider.toggleGroupExpanded(group.id),
                child: Icon(
                  group.expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => provider.toggleGroupVisibility(group.id),
                child: Icon(
                  group.visible ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.folder_outlined,
                  size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: InkWell(
                  onDoubleTap: () => _renameGroup(context),
                  child: Text(
                    group.name,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGroupMenu(BuildContext context, Offset? position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        (position ?? const Offset(100, 100)) & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: Text('layer.rename_group'.tr())),
        PopupMenuItem(value: 'opacity', child: Text('layer.opacity'.tr())),
        PopupMenuItem(value: 'dissolve', child: Text('layer.ungroup'.tr())),
        PopupMenuItem(
          value: 'delete_layers',
          child: Text('layer.delete_group_layers'.tr()),
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'rename':
          _renameGroup(context);
        case 'opacity':
          _showGroupOpacity(context);
        case 'dissolve':
          provider.dissolveGroup(group.id);
        case 'delete_layers':
          provider.deleteGroup(group.id, deleteLayers: true);
      }
    });
  }

  void _renameGroup(BuildContext context) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('layer.rename_group'.tr()),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              provider.renameGroup(group.id, controller.text.trim());
              Navigator.of(ctx).pop();
            },
            child: Text('dialog.ok'.tr()),
          ),
        ],
      ),
    );
  }

  void _showGroupOpacity(BuildContext context) {
    var value = group.opacity;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('layer.opacity'.tr()),
          content: Slider(
            value: value,
            onChanged: (v) {
              setState(() => value = v);
              provider.setGroupOpacity(group.id, v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('dialog.ok'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
