import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import '../../providers/canvas_provider.dart';

/// In-app floating window that displays the reference image. The window
/// itself can be dragged and resized; the image inside supports pinch
/// scale and rotation.
class ReferenceFloatingWindow extends StatelessWidget {
  const ReferenceFloatingWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CanvasProvider>();
    if (!cp.showReference || cp.referenceImage == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Positioned(
      left: cp.refWinOffset.dx,
      top: cp.refWinOffset.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        shadowColor: Colors.black54,
        child: SizedBox(
          width: cp.refWinSize.width,
          height: cp.refWinSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                _Header(theme: theme),
                const Divider(height: 1),
                Expanded(child: _ImageArea(image: cp.referenceImage!)),
                const Divider(height: 1),
                _ResizeHandle(theme: theme),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ThemeData theme;
  const _Header({required this.theme});

  @override
  Widget build(BuildContext context) {
    final cp = context.read<CanvasProvider>();
    return GestureDetector(
      onPanUpdate: (d) => cp.setRefWinOffset(cp.refWinOffset + d.delta),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        color: theme.colorScheme.surfaceContainerHigh,
        child: Row(children: [
          const SizedBox(width: 6),
          Icon(Icons.image_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'menu.image.import_reference'.tr(),
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'canvas.rotate'.tr(),
            child: InkWell(
              onTap: cp.resetRefTransform,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 16),
              ),
            ),
          ),
          Tooltip(
            message: 'dialog.close'.tr(),
            child: InkWell(
              onTap: cp.toggleReference,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ImageArea extends StatefulWidget {
  final ui.Image image;
  const _ImageArea({required this.image});

  @override
  State<_ImageArea> createState() => _ImageAreaState();
}

class _ImageAreaState extends State<_ImageArea> {
  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CanvasProvider>();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) {},
      onScaleUpdate: (d) {
        if (d.scale != 1.0) cp.setRefImgScale(cp.refImgScale * d.scale);
        if (d.rotation != 0) cp.setRefImgRotation(cp.refImgRotation + d.rotation);
      },
      onDoubleTap: cp.resetRefTransform,
      child: ColoredBox(
        color: themeColor(context),
        child: Center(
          child: Transform.rotate(
            angle: cp.refImgRotation,
            child: Transform.scale(
              scale: cp.refImgScale,
              child: RawImage(
                image: widget.image,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color themeColor(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLowest;
}

class _ResizeHandle extends StatelessWidget {
  final ThemeData theme;
  const _ResizeHandle({required this.theme});

  @override
  Widget build(BuildContext context) {
    final cp = context.read<CanvasProvider>();
    return GestureDetector(
      onPanUpdate: (d) => cp.setRefWinSize(Size(
        cp.refWinSize.width + d.delta.dx,
        cp.refWinSize.height + d.delta.dy,
      )),
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeDownRight,
        child: SizedBox(
          width: double.infinity,
          height: 14,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.drag_handle,
                  size: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
