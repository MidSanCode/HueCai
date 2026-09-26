import 'package:flutter/material.dart';

import '../../models/pattern.dart';
import '../../services/pattern_renderer.dart';

/// A small preview of a [PatternSpec], painted with the same shader the
/// canvas uses.
///
/// The tile decodes asynchronously, so the first frame falls back to the ink
/// colour and the widget repaints itself once the tile is ready.
class PatternThumb extends StatefulWidget {
  final PatternSpec spec;
  final double size;

  /// Transparency checkerboard behind the pattern (shows see-through tiles).
  final bool showCheckerboard;

  const PatternThumb({
    super.key,
    required this.spec,
    this.size = 32,
    this.showCheckerboard = true,
  });

  @override
  State<PatternThumb> createState() => _PatternThumbState();
}

class _PatternThumbState extends State<PatternThumb> {
  @override
  void initState() {
    super.initState();
    _warmUp();
  }

  @override
  void didUpdateWidget(covariant PatternThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) _warmUp();
  }

  void _warmUp() {
    PatternRenderer.ensure(widget.spec).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: PatternThumbPainter(
          widget.spec,
          showCheckerboard: widget.showCheckerboard,
        ),
      ),
    );
  }
}

class PatternThumbPainter extends CustomPainter {
  final PatternSpec spec;
  final bool showCheckerboard;

  PatternThumbPainter(this.spec, {this.showCheckerboard = true});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (showCheckerboard) {
      const cell = 6.0;
      final light = Paint()..color = const Color(0xFFFFFFFF);
      final dark = Paint()..color = const Color(0xFFDDDDDD);
      canvas.drawRect(rect, light);
      for (var y = 0.0; y < size.height; y += cell) {
        for (var x = 0.0; x < size.width; x += cell) {
          final odd = ((x ~/ cell) + (y ~/ cell)) % 2 == 1;
          if (odd) {
            canvas.drawRect(
              Rect.fromLTWH(x, y, cell, cell).intersect(rect),
              dark,
            );
          }
        }
      }
    }
    final shader = PatternRenderer.shaderFor(spec, center: rect.center);
    if (shader == null) {
      // Tile still decoding: show the ink colour so the swatch is never blank.
      canvas.drawRect(rect, Paint()..color = spec.foreground);
      return;
    }
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant PatternThumbPainter oldDelegate) =>
      oldDelegate.spec != spec ||
      oldDelegate.showCheckerboard != showCheckerboard;
}
