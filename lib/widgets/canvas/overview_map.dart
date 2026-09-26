import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/view_transform.dart';

/// Overview navigator (roadmap item 17): a minimap of the artwork with the
/// current viewport drawn on top. Click or drag inside it to jump there.
///
/// The thumbnail is a throttled flatten of the canvas — re-rasterising on
/// every pointer move would be far more expensive than the navigation is
/// worth, so the artwork refreshes after the drawing settles while the
/// viewport rectangle stays live.
class OverviewMap extends StatefulWidget {
  /// Size of the canvas viewport, used to work out the visible rect.
  final Size viewportSize;

  /// Size of the minimap widget itself.
  final Size mapSize;

  const OverviewMap({
    super.key,
    required this.viewportSize,
    this.mapSize = const Size(148, 104),
  });

  @override
  State<OverviewMap> createState() => _OverviewMapState();
}

class _OverviewMapState extends State<OverviewMap> {
  /// Quiet period before the thumbnail is re-flattened.
  static const Duration _refreshDelay = Duration(milliseconds: 900);

  ui.Image? _thumb;
  int _lastVersion = -1;
  Timer? _debounce;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ProjectProvider notifies on every content change; the version guard
    // keeps this cheap (a repaint-only change schedules one refresh).
    final pp = context.watch<ProjectProvider>();
    if (pp.contentVersion != _lastVersion) {
      _lastVersion = pp.contentVersion;
      _scheduleCapture();
    }
  }

  void _scheduleCapture() {
    _debounce?.cancel();
    _debounce = Timer(_refreshDelay, _capture);
  }

  Future<void> _capture() async {
    if (!mounted || _capturing) return;
    _capturing = true;
    try {
      final pp = context.read<ProjectProvider>();
      final img = await pp.rasterizeCanvas();
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _thumb;
      setState(() => _thumb = img);
      // The old flatten is only released once the new one has been built.
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (_) {
      // A failed thumbnail only means the navigator shows the outline.
    } finally {
      _capturing = false;
    }
  }

  void _jumpTo(Offset local, Size canvasSize) {
    final layout = OverviewLayout.fit(
      mapSize: widget.mapSize,
      canvasSize: canvasSize,
    );
    final target = layout.clampToCanvas(layout.toCanvas(local));
    context.read<CanvasProvider>().centerOnCanvasPoint(target, canvasSize);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cp = context.watch<CanvasProvider>();
    final pp = context.watch<ProjectProvider>();
    final project = pp.currentProject;
    if (project == null) return const SizedBox.shrink();
    final canvasSize = Size(
      project.settings.width.toDouble(),
      project.settings.height.toDouble(),
    );
    final layout = OverviewLayout.fit(
      mapSize: widget.mapSize,
      canvasSize: canvasSize,
    );
    final transform = ViewTransform(
      offset: cp.offset,
      scale: cp.scale,
      rotation: cp.rotation,
      canvasSize: canvasSize,
      areaSize: widget.viewportSize,
    );
    final visible = layout.rectFor(transform.visibleCanvasRect());

    return Container(
      width: widget.mapSize.width,
      height: widget.mapSize.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _jumpTo(d.localPosition, canvasSize),
          onPanUpdate: (d) => _jumpTo(d.localPosition, canvasSize),
          child: Stack(
            children: [
              // Checkerboard so a transparent canvas is readable.
              Positioned.fill(
                child: CustomPaint(painter: _CheckerPainter()),
              ),
              if (_thumb != null)
                Positioned.fromRect(
                  rect: layout.mapRect,
                  child: RawImage(
                    image: _thumb,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.low,
                  ),
                )
              else
                Positioned.fromRect(
                  rect: layout.mapRect,
                  child: Container(color: Colors.white),
                ),
              // Canvas border + live viewport rectangle.
              Positioned.fill(
                child: CustomPaint(
                  painter: _ViewportPainter(
                    canvasRect: layout.mapRect,
                    viewportRect: visible,
                    accent: theme.colorScheme.primary,
                    border: theme.colorScheme.outline,
                  ),
                ),
              ),
              Positioned(
                left: 4,
                bottom: 2,
                child: Text(
                  '${(cp.scale * 100).round()}%',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Positioned(
                right: 2,
                top: 0,
                child: Tooltip(
                  message: 'overview.refresh'.tr(),
                  child: InkWell(
                    onTap: _capture,
                    child: Icon(
                      Icons.refresh,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final light = Paint()..color = const Color(0xFFFFFFFF);
    final dark = Paint()..color = const Color(0xFFE8E8E8);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)) % 2 == 1) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, cell, cell)
                .intersect(Offset.zero & size),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}

class _ViewportPainter extends CustomPainter {
  final Rect canvasRect;
  final Rect viewportRect;
  final Color accent;
  final Color border;

  _ViewportPainter({
    required this.canvasRect,
    required this.viewportRect,
    required this.accent,
    required this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      canvasRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border,
    );
    final r = viewportRect.intersect(canvasRect.inflate(4000));
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent,
    );
    // Dim what is off-screen so the visible part stands out.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(canvasRect),
      Path()..addRect(r),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) =>
      oldDelegate.viewportRect != viewportRect ||
      oldDelegate.canvasRect != canvasRect ||
      oldDelegate.accent != accent;
}
