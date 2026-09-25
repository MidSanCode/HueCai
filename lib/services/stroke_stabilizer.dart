import 'dart:ui';

import 'image_filters.dart';

/// Stroke stabilization and pressure remapping — pure logic, testable
/// without a widget tree.

/// Modes of stroke stabilization.
enum StabilizerMode {
  /// No stabilization: the brush follows the pointer exactly.
  off,

  /// Moving-average smoothing (the classic "stabilizer" slider).
  smooth,

  /// String-pull mode: the brush trails the pointer as if tied to it by a
  /// virtual string of fixed length. Produces very smooth curves with a
  /// deliberate lag, and never overshoots.
  stringPull,
}

/// String-pull stabilizer state. Feed pointer positions in; the returned
/// position is where the brush actually draws.
class StringPullStabilizer {
  /// Virtual string length in canvas units. Larger = smoother + more lag.
  double length;

  Offset? _anchor;

  StringPullStabilizer({this.length = 30});

  /// The current brush position, if a stroke is in progress.
  Offset? get anchor => _anchor;

  /// Resets the string at the start of a stroke.
  void startAt(Offset point) {
    _anchor = point;
  }

  /// Feeds a raw pointer position and returns the stabilized position.
  ///
  /// The brush stays put until the pointer has moved farther than the
  /// string length, then follows exactly at that distance.
  Offset feed(Offset point) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = point;
      return point;
    }
    final delta = point - anchor;
    final dist = delta.distance;
    if (dist <= length) return anchor;
    final next = point - delta * (length / dist);
    _anchor = next;
    return next;
  }

  void reset() => _anchor = null;
}

/// Pressure curve: remaps stylus pressure (0..1) through user control
/// points before it drives brush width.
class PressureCurve {
  /// Control points in 0..255 space (x = raw pressure, y = mapped pressure).
  List<({double x, double y})> points;

  PressureCurve({List<({double x, double y})>? points})
      : points = points ?? const [(x: 0, y: 0), (x: 255, y: 255)];

  /// True when the curve is the identity (default) — mapping can be skipped.
  bool get isIdentity =>
      points.length == 2 &&
      points.first.x == 0 &&
      points.first.y == 0 &&
      points.last.x == 255 &&
      points.last.y == 255;

  /// Maps a raw pressure value (0..1) through the curve.
  double map(double pressure) {
    if (isIdentity) return pressure.clamp(0.0, 1.0);
    final lut = ImageFilters.curvesLut(points);
    final idx = (pressure.clamp(0.0, 1.0) * 255).round();
    return lut[idx] / 255.0;
  }

  List<Map<String, double>> toJson() =>
      points.map((p) => {'x': p.x, 'y': p.y}).toList();

  factory PressureCurve.fromJson(List<dynamic>? json) {
    if (json == null || json.isEmpty) return PressureCurve();
    return PressureCurve(
      points: json
          .map((p) => (
                x: (p['x'] as num).toDouble(),
                y: (p['y'] as num).toDouble(),
              ))
          .toList(),
    );
  }
}
