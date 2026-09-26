import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/view_transform.dart';

/// How the frozen snapshot and the live artwork are compared.
enum CompareMode {
  /// Draggable split: the snapshot on one side, the live canvas on the other.
  split,

  /// Both flattened and blended with [BlendMode.difference] — identical
  /// pixels go black, edits light up.
  difference,
}

/// Snapshot comparison overlay (roadmap item 17).
///
/// The reference image is a flatten in canvas coordinates, so it is drawn
/// through the very same view transform as the canvas: what you see on the
/// left of the split is the canvas *as it was*, aligned pixel for pixel.
class SnapshotCompareOverlay extends StatefulWidget {
  final Size viewportSize;

  const SnapshotCompareOverlay({super.key, required this.viewportSize});

  @override
  State<SnapshotCompareOverlay> createState() =>
      _SnapshotCompareOverlayState();
}

class _SnapshotCompareOverlayState extends State<SnapshotCompareOverlay> {
  /// Where the split line sits, as a fraction of the viewport width.
  double _split = 0.5;
  CompareMode _mode = CompareMode.split;

  ui.Image? _current;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureCurrent());
  }

  @override
  void dispose() {
    _current?.dispose();
    super.dispose();
  }

  Future<void> _captureCurrent() async {
    if (_capturing) return;
    _capturing = true;
    try {
      final pp = context.read<ProjectProvider>();
      final img = await pp.rasterizeCanvas();
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _current;
      setState(() => _current = img);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (_) {
      // Without a current flatten the overlay simply stays hidden.
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pp = context.watch<ProjectProvider>();
    final project = pp.currentProject;
    final snapshot = pp.comparisonSnapshot;
    if (project == null || snapshot == null) return const SizedBox.shrink();
    final canvasSize = Size(
      project.settings.width.toDouble(),
      project.settings.height.toDouble(),
    );
    final cp = context.watch<CanvasProvider>();
    final transform = ViewTransform(
      offset: cp.offset,
      scale: cp.scale,
      rotation: cp.rotation,
      canvasSize: canvasSize,
      areaSize: widget.viewportSize,
    );

    // One matrix drives both the snapshot and the current flatten so they land
    // exactly on the canvas rectangle.
    final matrix = Matrix4.fromFloat64List(
      Float64List.fromList(transform.matrix4()),
    );

    final splitX = widget.viewportSize.width * _split;

    return Positioned.fill(
      child: Stack(
        children: [
          if (_mode == CompareMode.split)
            // Snapshot side.
            Positioned(
              left: 0,
              top: 0,
              width: splitX,
              height: widget.viewportSize.height,
              child: ClipRect(
                child: Transform(
                  transform: matrix,
                  child: CustomPaint(
                    size: canvasSize,
                    painter: _ImagePainter(snapshot),
                  ),
                ),
              ),
            )
          else if (_current != null)
            // Difference side: current flatten with the snapshot subtracted.
            Positioned.fill(
              child: ClipRect(
                child: Transform(
                  transform: matrix,
                  child: CustomPaint(
                    size: canvasSize,
                    painter: _DifferencePainter(_current!, snapshot),
                  ),
                ),
              ),
            ),
          // Split handle.
          if (_mode == CompareMode.split)
            Positioned(
              left: splitX - 12,
              top: 0,
              bottom: 0,
              width: 24,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _split = (_split +
                            d.delta.dx / widget.viewportSize.width)
                        .clamp(0.02, 0.98);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: Center(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          // Labels + controls.
          Positioned(
            left: 8,
            top: 8,
            child: _badge(theme, 'snapshot.before'.tr()),
          ),
          if (_mode == CompareMode.split)
            Positioned(
              right: 8,
              top: 8,
              child: _badge(theme, 'snapshot.now'.tr()),
            ),
          if (_mode == CompareMode.difference)
            Positioned(
              left: 0,
              right: 0,
              bottom: 44,
              child: Center(
                child: _badge(theme, 'snapshot.difference_hint'.tr()),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _modeButton(CompareMode.split, Icons.vertical_split,
                      'snapshot.mode_split'.tr()),
                  _modeButton(CompareMode.difference, Icons.compare,
                      'snapshot.mode_difference'.tr()),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16),
                    tooltip: 'snapshot.recapture'.tr(),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      await pp.recaptureComparison();
                      await _captureCurrent();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'snapshot.close'.tr(),
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    onPressed: pp.stopComparison,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10)),
      );

  Widget _modeButton(CompareMode mode, IconData icon, String tooltip) =>
      IconButton(
        icon: Icon(icon, size: 16),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        padding: EdgeInsets.zero,
        color: _mode == mode ? Theme.of(context).colorScheme.primary : null,
        onPressed: () async {
          setState(() => _mode = mode);
          if (mode == CompareMode.difference && _current == null) {
            await _captureCurrent();
          }
        },
      );
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter oldDelegate) =>
      oldDelegate.image != image;
}

class _DifferencePainter extends CustomPainter {
  final ui.Image current;
  final ui.Image snapshot;
  _DifferencePainter(this.current, this.snapshot);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawImageRect(
      current,
      Rect.fromLTWH(0, 0, current.width.toDouble(), current.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
    canvas.drawImageRect(
      snapshot,
      Rect.fromLTWH(0, 0, snapshot.width.toDouble(), snapshot.height.toDouble()),
      dst,
      Paint()
        ..filterQuality = FilterQuality.low
        ..blendMode = BlendMode.difference,
    );
  }

  @override
  bool shouldRepaint(covariant _DifferencePainter oldDelegate) =>
      oldDelegate.current != current || oldDelegate.snapshot != snapshot;
}
