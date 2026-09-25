import 'package:flutter/material.dart';

/// A small editable curve editor: drag points to reshape the response curve,
/// tap empty space to add a point, double-tap a point to remove it.
///
/// Points are (x, y) in 0..255 space; the editor always keeps the list it
/// hands to [onChanged] sorted by x.
class CurveEditor extends StatefulWidget {
  final List<({double x, double y})> points;
  final ValueChanged<List<({double x, double y})>> onChanged;
  final double size;

  const CurveEditor({
    super.key,
    required this.points,
    required this.onChanged,
    this.size = 220,
  });

  @override
  State<CurveEditor> createState() => _CurveEditorState();
}

class _CurveEditorState extends State<CurveEditor> {
  Offset _toCanvas(({double x, double y}) p) =>
      Offset(p.x / 255 * widget.size, (1 - p.y / 255) * widget.size);

  ({double x, double y}) _fromCanvas(Offset o) => (
        x: (o.dx / widget.size * 255).clamp(0.0, 255.0),
        y: ((1 - o.dy / widget.size) * 255).clamp(0.0, 255.0),
      );

  int? _hit(Offset o) {
    for (var i = 0; i < widget.points.length; i++) {
      if ((_toCanvas(widget.points[i]) - o).distance < 12) return i;
    }
    return null;
  }

  void _emit(List<({double x, double y})> next) {
    next.sort((a, b) => a.x.compareTo(b.x));
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTapUp: (d) {
        if (_hit(d.localPosition) != null) return;
        _emit([...widget.points, _fromCanvas(d.localPosition)]);
      },
      onDoubleTapDown: (d) {
        final i = _hit(d.localPosition);
        if (i != null && widget.points.length > 2) {
          _emit([...widget.points]..removeAt(i));
        }
      },
      onPanUpdate: (d) {
        final i = _hit(d.localPosition - d.delta);
        if (i == null) return;
        final next = [...widget.points];
        // Endpoints keep their x; interior points move freely.
        final moved = _fromCanvas(d.localPosition);
        next[i] = (i == 0 || i == widget.points.length - 1)
            ? (x: widget.points[i].x, y: moved.y)
            : moved;
        _emit(next);
      },
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: CurvePainter(
          points: widget.points,
          lineColor: theme.colorScheme.primary,
          gridColor: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// Paints the grid, the polyline through the points, and the point handles.
class CurvePainter extends CustomPainter {
  final List<({double x, double y})> points;
  final Color lineColor;
  final Color gridColor;

  CurvePainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final t = size.width * i / 4;
      canvas.drawLine(Offset(t, 0), Offset(t, size.height), grid);
      canvas.drawLine(Offset(0, t), Offset(size.width, t), grid);
    }
    final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final o = Offset(
          sorted[i].x / 255 * size.width, (1 - sorted[i].y / 255) * size.height);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final dot = Paint()..color = lineColor;
    for (final p in sorted) {
      canvas.drawCircle(
        Offset(p.x / 255 * size.width, (1 - p.y / 255) * size.height),
        5,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(CurvePainter old) => true;
}
