import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/selection_data.dart';
import '../models/layer.dart';
import '../providers/project_provider.dart';
import '../providers/tool_provider.dart';

class SelectionPanel extends StatelessWidget {
  const SelectionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final phase = pp.selectionPhase;
    // Show the panel as soon as the select tool is active, even before
    // the first selection gesture begins.
    final isSelectTool =
        context.watch<ToolProvider>().currentTool == ToolType.select;
    if (phase == SelectionPhase.none && !isSelectTool) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: phase == SelectionPhase.selecting
              ? _SelectingContent()
              : phase == SelectionPhase.selected
                  ? _SelectedContent()
                  : _EditingContent(),
        ),
      ),
    );
  }
}

// ─── Phase: selecting ────────────────────────────────────

class _SelectingContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final method = pp.selectionMethod;
    final combineMode = pp.selectionCombineMode;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4, runSpacing: 4,
        children: [
          // Method buttons
          _methodBtn(context, SelectionMethod.lasso, Icons.gesture, method == SelectionMethod.lasso),
          _methodBtn(context, SelectionMethod.rect, Icons.crop_square, method == SelectionMethod.rect),
          _methodBtn(context, SelectionMethod.ellipse, Icons.circle_outlined, method == SelectionMethod.ellipse),
          _methodBtn(context, SelectionMethod.magicWand, Icons.auto_fix_high, method == SelectionMethod.magicWand),
          _methodBtn(context, SelectionMethod.brush, Icons.brush, method == SelectionMethod.brush),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(width: 1, height: 24, child: VerticalDivider()),
          ),

          // Combine mode: add / subtract / intersect
          _combineToggle(context, combineMode),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(width: 1, height: 24, child: VerticalDivider()),
          ),

          // Invert
          _iconBtn(context, Icons.invert_colors, 'selection.invert', () => pp.invertSelection()),

          // Feather / grow / shrink
          _iconBtn(context, Icons.blur_on, 'selection.feather',
              () => _askPixels(context, 'selection.feather', (px) => pp.featherSelection(px))),
          _iconBtn(context, Icons.add_circle_outline, 'selection.grow',
              () => _askPixels(context, 'selection.grow', (px) => pp.growSelection(px))),
          _iconBtn(context, Icons.remove_circle_outline, 'selection.shrink',
              () => _askPixels(context, 'selection.shrink', (px) => pp.growSelection(-px))),

          // Confirm
          _iconBtn(context, Icons.check, 'selection.confirm', () => pp.confirmSelection()),
        ],
      ),
    );
  }

  /// Small dialog asking for a pixel amount, applied via [apply].
  void _askPixels(BuildContext context, String titleKey, ValueChanged<int> apply) {
    double value = 4;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(titleKey.tr()),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${value.round()} px',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Slider(
                  value: value, min: 1, max: 50, divisions: 49,
                  label: '${value.round()}',
                  onChanged: (v) => setState(() => value = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('dialog.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                apply(value.round());
              },
              child: Text('dialog.confirm'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodBtn(BuildContext context, SelectionMethod m, IconData icon, bool selected) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.read<ProjectProvider>().setSelectionMethod(m),
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Icon(icon, size: 18,
          color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _combineToggle(BuildContext context, SelectionCombineMode mode) {
    final pp = context.read<ProjectProvider>();
    final theme = Theme.of(context);
    Widget seg(SelectionCombineMode m, IconData icon) {
      final active = mode == m;
      return GestureDetector(
        onTap: () => pp.setSelectionCombineMode(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(
            icon,
            size: 14,
            color: active ? theme.colorScheme.primary : Colors.grey,
          ),
        ),
      );
    }

    return Tooltip(
      message: 'selection.combine_mode'.tr(),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            seg(SelectionCombineMode.add, Icons.add),
            seg(SelectionCombineMode.subtract, Icons.remove),
            seg(SelectionCombineMode.intersect, Icons.join_inner),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip.tr(),
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ─── Phase: selected ─────────────────────────────────────

class _SelectedContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _selBtn(context, Icons.content_copy, 'menu.edit.copy', () => context.read<ProjectProvider>().copySelection()),
          const SizedBox(width: 8),
          _selBtn(context, Icons.content_cut, 'menu.edit.cut', () => context.read<ProjectProvider>().cutSelection()),
          const SizedBox(width: 8),
          _selBtn(context, Icons.close, 'tool.select_deselect', () => context.read<ProjectProvider>().clearPixelSelection()),
        ],
      ),
    );
  }

  Widget _selBtn(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label.tr(), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ─── Phase: editing ──────────────────────────────────────

class _EditingContent extends StatefulWidget {
  @override
  State<_EditingContent> createState() => _EditingContentState();
}

class _EditingContentState extends State<_EditingContent> {
  bool _newLayer = false;

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProjectProvider>();
    final isScale = pp.transformMode == TransformMode.scale;
    final locked = pp.aspectRatioLocked;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6, runSpacing: 4,
        children: [
          // Mode toggle: scale / warp
          _modeTab('selection.scale', isScale, () => pp.setTransformMode(TransformMode.scale)),
          _modeTab('selection.warp', !isScale, () => pp.setTransformMode(TransformMode.warp)),

          if (isScale) ...[
            const SizedBox(width: 4),
            // Aspect ratio lock
            GestureDetector(
              onTap: () => pp.setAspectRatioLocked(!locked),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(locked ? Icons.lock : Icons.lock_open, size: 14),
                    const SizedBox(width: 4),
                    Text('selection.lock_aspect'.tr(), style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(width: 1, height: 24, child: VerticalDivider()),
          ),

          // New layer
          GestureDetector(
            onTap: () => setState(() => _newLayer = !_newLayer),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _newLayer ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_newLayer ? Icons.check_box : Icons.check_box_outline_blank, size: 14),
                  const SizedBox(width: 4),
                  Text('selection.new_layer'.tr(), style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),

          // Flip buttons
          _smallBtn(Icons.flip, 'selection.flip_h', () {
            pp.updateSelectionEditTransform(scaleX: -pp.editScaleX, scaleY: pp.editScaleY);
          }),
          _smallBtn(Icons.flip_camera_android, 'selection.flip_v', () {
            pp.updateSelectionEditTransform(scaleX: pp.editScaleX, scaleY: -pp.editScaleY);
          }),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(width: 1, height: 24, child: VerticalDivider()),
          ),

          // Cancel / Apply
          _actionBtn('dialog.cancel', theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer,
              () => pp.cancelSelectionEdit()),
          _actionBtn('selection.apply', theme.colorScheme.primaryContainer, theme.colorScheme.onPrimaryContainer,
              () => _onApply(context)),
        ],
      ),
    );
  }

  Widget _modeTab(String label, bool active, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label.tr(), style: TextStyle(
          fontSize: 11,
          color: active ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
        )),
      ),
    );
  }

  Widget _smallBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _actionBtn(String label, Color bg, Color fg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label.tr(), style: TextStyle(fontSize: 11, color: fg)),
      ),
    );
  }

  void _onApply(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_newLayer) {
        // Move selection to new layer
        pp.saveSnapshot();
        if (pp.selectionClipImage != null) {
          final layer = Layer(
            id: const Uuid().v4(),
            name: 'layer.selection'.tr(),
            image: pp.selectionClipImage,
            imageOffset: pp.selectionClipBounds.topLeft,
          );
          pp.currentProject?.layers.add(layer);
          pp.setCurrentLayer((pp.currentProject?.layers.length ?? 1) - 1);
          await pp.restartSelectionSession();
        } else if (pp.hasActiveSelection) {
          // No clip yet (user skipped copy/cut): extract one, then commit.
          await pp.copySelection();
          if (pp.selectionClipImage != null) {
            final layer = Layer(
              id: const Uuid().v4(),
              name: 'layer.selection'.tr(),
              image: pp.selectionClipImage,
              imageOffset: pp.selectionClipBounds.topLeft,
            );
            pp.currentProject?.layers.add(layer);
            pp.setCurrentLayer((pp.currentProject?.layers.length ?? 1) - 1);
            await pp.restartSelectionSession();
          }
        }
        messenger.showSnackBar(SnackBar(content: Text('selection.apply'.tr())));
      } else {
        if (pp.selectionClipImage == null && pp.hasActiveSelection) {
          // Nothing copied/cut yet — treat apply as a copy-move commit.
          await pp.copySelection();
        }
        if (pp.selectionClipImage == null) return;
        await pp.applySelectionEdit();
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('error.save_failed'.tr())),
      );
    }
  }
}
