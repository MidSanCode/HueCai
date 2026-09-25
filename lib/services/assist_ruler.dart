import 'dart:math' as math;
import 'dart:ui';

/// Drawing assistant rulers: geometric guides that snap brush strokes onto
/// themselves. Pure geometry — no widget dependencies.
enum RulerType {
  /// Straight ruler through [center] at [angle] (radians).
  parallel,

  /// Ellipse perimeter centered at [center] with radii [radiusX]/[radiusY].
  ellipse,

  /// Smooth curve through the control [points] (Catmull-Rom).
  spline,
}

class AssistRuler {
  final String id;
  RulerType type;
  Offset center;
  double angle; // parallel only
  double radiusX; // ellipse only
  double radiusY; // ellipse only
  List<Offset> points; // spline only (control points)
  bool visible;

  AssistRuler({
    required this.id,
    required this.type,
    this.center = Offset.zero,
    this.angle = 0,
    this.radiusX = 100,
    this.radiusY = 60,
    List<Offset>? points,
    this.visible = true,
  }) : points = points ?? [];

  /// Draggable handle positions for editing this ruler on the canvas.
  List<Offset> get handles => switch (type) {
        RulerType.parallel => [
            center,
            center + Offset(math.cos(angle), math.sin(angle)) * 60,
          ],
        RulerType.ellipse => [
            center,
            center + Offset(radiusX, 0),
            center + Offset(0, radiusY),
          ],
        RulerType.spline => List.of(points),
      };

  /// Moves handle [index] to [pos].
  void moveHandle(int index, Offset pos) {
    switch (type) {
      case RulerType.parallel:
        if (index == 0) {
          center = pos;
        } else if (index == 1) {
          final d = pos - center;
          if (d.distance > 4) angle = math.atan2(d.dy, d.dx);
        }
      case RulerType.ellipse:
        if (index == 0) {
          center = pos;
        } else if (index == 1) {
          radiusX = (pos.dx - center.dx).abs().clamp(4.0, 10000.0);
        } else if (index == 2) {
          radiusY = (pos.dy - center.dy).abs().clamp(4.0, 10000.0);
        }
      case RulerType.spline:
        if (index >= 0 && index < points.length) points[index] = pos;
    }
  }

  /// Snaps [p] onto the ruler geometry.
  Offset snapPoint(Offset p) => switch (type) {
        RulerType.parallel => snapToLine(p, center, angle),
        RulerType.ellipse => snapToEllipse(p, center, radiusX, radiusY),
        RulerType.spline => snapToPolyline(p, splineSamples()),
      };

  /// Samples the spline as a dense polyline (for snapping and drawing).
  List<Offset> splineSamples({int samplesPerSegment = 16}) {
    if (points.length < 2) return List.of(points);
    final out = <Offset>[];
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : points.length - 1];
      for (var s = 0; s < samplesPerSegment; s++) {
        final t = s / samplesPerSegment;
        final t2 = t * t;
        final t3 = t2 * t;
        out.add(Offset(
          0.5 *
              ((2 * p1.dx) +
                  (-p0.dx + p2.dx) * t +
                  (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
                  (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
          0.5 *
              ((2 * p1.dy) +
                  (-p0.dy + p2.dy) * t +
                  (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
                  (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
        ));
      }
    }
    out.add(points.last);
    return out;
  }

  /// Projects [p] onto the infinite line through [center] at [angle].
  static Offset snapToLine(Offset p, Offset center, double angle) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final t = (p - center).dx * dir.dx + (p - center).dy * dir.dy;
    return center + dir * t;
  }

  /// Projects [p] onto the ellipse perimeter (center + radii).
  static Offset snapToEllipse(Offset p, Offset c, double rx, double ry) {
    if (rx <= 0 || ry <= 0) return c;
    final d = p - c;
    if (d.distance < 1e-6) return c + Offset(rx, 0);
    // Scale to unit circle, normalize, scale back.
    final nx = d.dx / rx;
    final ny = d.dy / ry;
    final len = math.sqrt(nx * nx + ny * ny);
    return c + Offset(nx / len * rx, ny / len * ry);
  }

  /// Snaps [p] onto the ray from the vanishing point through [strokeStart]:
  /// the stroke becomes a perfect radial line toward the vanishing point.
  static Offset snapToVanishingRay(Offset p, Offset vp, Offset strokeStart) {
    final d = strokeStart - vp;
    if (d.distance < 1e-6) return p;
    return snapToLine(p, vp, math.atan2(d.dy, d.dx));
  }

  /// Nearest point on a polyline to [p].
  static Offset snapToPolyline(Offset p, List<Offset> polyline) {
    if (polyline.isEmpty) return p;
    if (polyline.length == 1) return polyline.first;
    var best = polyline.first;
    var bestDist = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final q = _nearestOnSegment(p, polyline[i], polyline[i + 1]);
      final d = (q - p).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = q;
      }
    }
    return best;
  }

  static Offset _nearestOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-9) return a;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2)
        .clamp(0.0, 1.0);
    return a + ab * t;
  }
}
