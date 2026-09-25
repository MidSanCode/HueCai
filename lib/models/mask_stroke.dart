import 'package:flutter/painting.dart';

/// One stroke painted into a layer mask.
///
/// Masks are grayscale: white keeps the layer, black hides it. [erase] marks
/// a *conceal* stroke (painted with a dark color); a reveal stroke restores
/// hidden areas. [opacity] is the stroke strength (0..1) so soft touches
/// partially hide/reveal.
class MaskStroke {
  final String id;
  List<Offset> points;
  double width;
  double opacity;
  bool erase;

  /// Bumped on every in-stroke edit so raster caches know to re-render.
  int contentVersion = 0;

  MaskStroke({
    required this.id,
    List<Offset>? points,
    this.width = 20,
    this.opacity = 1.0,
    this.erase = false,
  }) : points = points ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'width': width,
        'opacity': opacity,
        'erase': erase,
      };

  factory MaskStroke.fromJson(Map<String, dynamic> json) => MaskStroke(
        id: json['id'] as String,
        points: (json['points'] as List?)
                ?.map((p) => Offset(
                      (p['x'] as num).toDouble(),
                      (p['y'] as num).toDouble(),
                    ))
                .toList() ??
            [],
        width: (json['width'] as num?)?.toDouble() ?? 20,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        erase: json['erase'] as bool? ?? false,
      );

  /// Paints this stroke onto the mask buffer canvas.
  ///
  /// The buffer starts fully white (alpha 1 = keep). Conceal strokes cut
  /// alpha away with [BlendMode.dstOut]; reveal strokes paint white back in
  /// with [BlendMode.srcOver]. Only the alpha channel matters downstream —
  /// the buffer is applied with dstIn.
  void drawOnMask(Canvas canvas) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.fill;
    if (erase) {
      paint
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity);
    } else {
      paint
        ..blendMode = BlendMode.srcOver
        ..color = const Color(0xFFFFFFFF).withValues(alpha: opacity);
    }
    final radius = width / 2;
    if (points.length == 1) {
      canvas.drawCircle(points.first, radius, paint);
      return;
    }
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[i - 1], points[i], paint..strokeWidth = width);
      canvas.drawCircle(points[i], radius, paint);
    }
  }
}
