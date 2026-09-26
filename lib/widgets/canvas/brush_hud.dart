import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// On-canvas brush HUD (roadmap item 17).
///
/// Shown while a paint tool is long-pressed: a ring previewing the real brush
/// size plus a compact readout. Dragging horizontally changes the size and
/// vertically the opacity (the canvas widget feeds those deltas in).
class BrushHud extends StatelessWidget {
  /// Where the HUD sits, in canvas-widget local coordinates.
  final Offset position;

  /// Live brush size in canvas pixels.
  final double brushSize;

  /// Live brush opacity (0…1).
  final double opacity;

  /// Current view zoom, so the ring matches what will be painted.
  final double viewScale;

  /// Ink colour, used for the ring.
  final Color color;

  const BrushHud({
    super.key,
    required this.position,
    required this.brushSize,
    required this.opacity,
    required this.viewScale,
    required this.color,
  });

  /// Ring diameter on screen, clamped so a 1px brush stays visible and a huge
  /// brush does not cover the whole canvas.
  double get ringDiameter =>
      (brushSize * viewScale).clamp(6.0, 320.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = ringDiameter;
    final label = '${brushSize.toStringAsFixed(1)} px · '
        '${(opacity * 100).round()}%';
    // Prefer the label above the ring; flip below when the ring is near the
    // top edge so it never leaves the canvas area.
    final above = position.dy - d / 2 > 56;
    final labelTop = above ? position.dy - d / 2 - 44 : position.dy + d / 2 + 6;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: position.dx - d / 2,
              top: position.dy - d / 2,
              width: d,
              height: d,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Ring in the ink colour, with a dark halo so a white brush
                  // stays visible on white paper.
                  border: Border.all(color: color, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 2,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: position.dx - 90,
              top: labelTop,
              width: 180,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 11)),
                      Text(
                        'hud.hint'.tr(),
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
