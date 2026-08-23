import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'brush.dart';

enum ShapeType { rect, ellipse, polygon, line, curve }

class LeafData {
  Offset position;
  double rotation;
  double width;
  double height;

  LeafData({
    required this.position,
    this.rotation = 0,
    this.width = 10,
    this.height = 4,
  });
}

class GradientStop {
  double position;
  Color color;

  GradientStop({required this.position, required this.color});

  Map<String, dynamic> toJson() => {
        'position': position,
        'color': color.toARGB32(),
      };

  factory GradientStop.fromJson(Map<String, dynamic> json) => GradientStop(
        position: (json['position'] as num).toDouble(),
        color: Color(json['color'] as int),
      );

  GradientStop copyWith({double? position, Color? color}) =>
      GradientStop(position: position ?? this.position, color: color ?? this.color);
}

class Drawable {
  final String id;
  final bool isShape;
  final ShapeType? shapeType;
  List<Offset> points;
  List<double>? widths;
  Color color;
  double strokeWidth;
  double opacity;
  bool isFilled;
  double rotation;
  bool selected;
  bool isGradient;
  List<GradientStop> gradientStops;
  double gradientAngle;
  List<LeafData>? leaves;
  bool isSmudge;
  ui.Image? smudgeSource;
  Uint8List? smudgePixels;
  int smudgeW = 0;
  int smudgeH = 0;
  BrushType brushType;

  Drawable({
    required this.id,
    this.isShape = false,
    this.shapeType,
    required this.points,
    this.widths,
    this.color = Colors.black,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.isFilled = false,
    this.rotation = 0.0,
    this.selected = false,
    this.isGradient = false,
    List<GradientStop>? gradientStops,
    this.gradientAngle = 0.0,
    this.leaves,
    this.isSmudge = false,
    this.brushType = BrushType.hardRound,
  }) : gradientStops = gradientStops ?? [];

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx, minY = points.first.dy;
    double maxX = minX, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  void draw(Canvas canvas, Paint paint) {
    final p = Paint()
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke;

    if (isGradient && gradientStops.length >= 2 && points.length >= 2) {
      // Gradient fill tool: a linear gradient running along the dragged
      // line. Both ends are extended far beyond the canvas so the ramp
      // reaches every edge without a hard cutoff at the drag endpoints.
      final p0 = points.first;
      final p1 = points.last;
      final d = p1 - p0;
      final len = d.distance;
      if (len < 0.5) {
        p.color = gradientStops.first.color.withValues(alpha: opacity);
      } else {
        final dir = Offset(d.dx / len, d.dy / len);
        const double ext = 10000.0;
        p.shader = ui.Gradient.linear(
          p0 - dir * ext,
          p1 + dir * ext,
          gradientStops
              .map((s) => s.color.withValues(alpha: s.color.a * opacity))
              .toList(),
        );
      }
      canvas.drawRect(
        Rect.fromPoints(p0, p1).inflate(10000),
        p,
      );
      return;
    } else {
      p.color = color.withValues(alpha: opacity);
    }

    if (isSmudge && smudgeSource != null) {
      _drawSmudge(canvas, p);
      return;
    }

    if (leaves != null) {
      _drawLeaves(canvas, p);
      return;
    }

    if (!isShape || shapeType == null) {
      _drawStroke(canvas, p);
      return;
    }

    canvas.save();
    final center = bounds.center;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);

    switch (shapeType!) {
      case ShapeType.rect:
        canvas.drawRect(bounds, p);
        break;
      case ShapeType.ellipse:
        canvas.drawOval(bounds, p);
        break;
      case ShapeType.line:
        if (points.length >= 2) {
          canvas.drawLine(points.first, points.last, p);
        }
        break;
      case ShapeType.polygon:
        if (points.length >= 3) {
          final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
          for (int i = 1; i < points.length; i++) {
            path.lineTo(points[i].dx, points[i].dy);
          }
          path.close();
          canvas.drawPath(path, p);
        }
        break;
      case ShapeType.curve:
        if (points.length >= 3) {
          final path = ui.Path()
            ..moveTo(points.first.dx, points.first.dy);
          for (int i = 1; i < points.length - 1; i += 3) {
            path.cubicTo(
              points[i].dx, points[i].dy,
              points[i + 1].dx, points[i + 1].dy,
              points[i + 2].dx, points[i + 2].dy,
            );
          }
          canvas.drawPath(path, p);
        }
        break;
    }

    canvas.restore();
    p.shader = null;
  }

  Drawable copyWith({
    String? id,
    bool? isShape,
    ShapeType? shapeType,
    List<Offset>? points,
    List<double>? widths,
    Color? color,
    double? strokeWidth,
    double? opacity,
    bool? isFilled,
    double? rotation,
    bool? selected,
    bool? isGradient,
    List<GradientStop>? gradientStops,
    double? gradientAngle,
    BrushType? brushType,
  }) =>
      Drawable(
        id: id ?? this.id,
        isShape: isShape ?? this.isShape,
        shapeType: shapeType ?? this.shapeType,
        points: points ?? List.from(this.points),
        widths: widths ?? (this.widths != null ? List.from(this.widths!) : null),
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        isFilled: isFilled ?? this.isFilled,
        rotation: rotation ?? this.rotation,
        selected: selected ?? this.selected,
        isGradient: isGradient ?? this.isGradient,
        gradientStops: gradientStops ?? List.from(this.gradientStops),
        gradientAngle: gradientAngle ?? this.gradientAngle,
        brushType: brushType ?? this.brushType,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isShape': isShape,
        'shapeType': shapeType?.name,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'widths': widths,
        'color': color.toARGB32(),
        'strokeWidth': strokeWidth,
        'opacity': opacity,
        'isFilled': isFilled,
        'rotation': rotation,
        'selected': selected,
        'isGradient': isGradient,
        'gradientStops': gradientStops.map((s) => s.toJson()).toList(),
        'gradientAngle': gradientAngle,
        'brushType': brushType.name,
      };

  factory Drawable.fromJson(Map<String, dynamic> json) => Drawable(
        id: json['id'] as String,
        isShape: json['isShape'] as bool? ?? false,
        shapeType: json['shapeType'] != null
            ? ShapeType.values.byName(json['shapeType'] as String)
            : null,
        points: (json['points'] as List)
            .map((p) => Offset(
                  (p['x'] as num).toDouble(),
                  (p['y'] as num).toDouble(),
                ))
            .toList(),
        widths: json['widths'] != null
            ? (json['widths'] as List).map((w) => (w as num).toDouble()).toList()
            : null,
        color: Color(json['color'] as int),
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
        opacity: (json['opacity'] as num).toDouble(),
        isFilled: json['isFilled'] as bool? ?? false,
        rotation: (json['rotation'] as num).toDouble(),
        selected: json['selected'] as bool? ?? false,
        isGradient: json['isGradient'] as bool? ?? false,
        gradientStops: (json['gradientStops'] as List?)
                ?.map(
                    (s) => GradientStop.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        gradientAngle: (json['gradientAngle'] as num).toDouble(),
        brushType: json['brushType'] != null
            ? BrushType.values.byName(json['brushType'] as String)
            : BrushType.hardRound,
      );

  void _drawSmudge(Canvas canvas, Paint paint) {
    if (smudgePixels == null || smudgeW == 0 || smudgeH == 0) return;
    final src = smudgePixels!;
    // For every sampled position, randomly pick source colors inside the
    // brush radius and stamp them at random nearby spots — visually
    // swapping colors within the smudged area. The RNG is seeded per
    // point index so repaints are stable.
    for (int i = 0; i < points.length; i++) {
      final w = widths != null && i < widths!.length ? widths![i] : strokeWidth;
      final radius = max(2.0, w * 0.6);
      final count = ((radius * radius) / 4).round().clamp(3, 60);
      final rng = Random((id.hashCode ^ (i * 2654435761)) & 0x7fffffff);
      final pt = points[i];
      for (int n = 0; n < count; n++) {
        // Random source position within (slightly beyond) the radius.
        final a1 = rng.nextDouble() * 2 * pi;
        final r1 = sqrt(rng.nextDouble()) * radius * 1.2;
        final sx = (pt.dx + cos(a1) * r1).floor().clamp(0, smudgeW - 1);
        final sy = (pt.dy + sin(a1) * r1).floor().clamp(0, smudgeH - 1);
        final idx = (sy * smudgeW + sx) * 4;
        final alpha = src[idx + 3];
        if (alpha < 8) continue;
        final c = Color.fromARGB(alpha, src[idx], src[idx + 1], src[idx + 2]);
        // Random destination position inside the radius.
        final a2 = rng.nextDouble() * 2 * pi;
        final r2 = sqrt(rng.nextDouble()) * radius * 0.9;
        final dotR = max(1.0, w * 0.12);
        canvas.drawCircle(
          Offset(pt.dx + cos(a2) * r2, pt.dy + sin(a2) * r2),
          dotR,
          Paint()..color = c,
        );
      }
    }
  }

  void _drawLeaves(Canvas canvas, Paint paint) {
    if (leaves == null || points.length < 2) return;
    final alpha = brushType == BrushType.softRound
        ? opacity * 0.7
        : brushType == BrushType.airbrush
            ? opacity * 0.5
            : opacity;
    final p = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: alpha);

    // Willow-leaf fill: one edge is the travelled curve, the other edge
    // is a straight line from the last point back to the first.
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
    } else {
      for (int i = 1; i < points.length - 1; i++) {
        final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
        path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawStroke(Canvas canvas, Paint paint) {
    if (points.length < 2) return;

    switch (brushType) {
      case BrushType.softRound:
        _drawSoftRoundStroke(canvas, paint);
        return;
      case BrushType.airbrush:
        _drawAirbrushStroke(canvas, paint);
        return;
      case BrushType.eraser:
        _drawEraserStroke(canvas, paint);
        return;
      case BrushType.marker:
        _drawMarkerStroke(canvas, paint);
        return;
      default:
        break;
    }

    if (widths != null && widths!.length >= points.length) {
      for (int i = 0; i < points.length - 1; i++) {
        final p = Paint()
          ..color = paint.color
          ..strokeWidth = widths![i]
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..shader = paint.shader;
        canvas.drawLine(points[i], points[i + 1], p);
      }
    } else {
      final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawSoftRoundStroke(Canvas canvas, Paint paint) {
    final radius = strokeWidth / 2;
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius);
    final gradient = RadialGradient(
      colors: [paint.color, paint.color.withValues(alpha: 0.0)],
      stops: const [0.6, 1.0],
    );
    for (final point in points) {
      final shader = gradient.createShader(rect.shift(point));
      canvas.drawCircle(point, radius, Paint()..shader = shader);
    }
  }

  void _drawAirbrushStroke(Canvas canvas, Paint paint) {
    final radius = strokeWidth / 2;
    final rng = Random();
    for (final point in points) {
      for (int i = 0; i < 24; i++) {
        final angle = rng.nextDouble() * 2 * pi;
        final dist = sqrt(rng.nextDouble()) * radius;
        final dot = Offset(
          point.dx + cos(angle) * dist,
          point.dy + sin(angle) * dist,
        );
        canvas.drawCircle(dot, 1.2, Paint()..color = paint.color.withValues(alpha: 0.25));
      }
    }
  }

  void _drawEraserStroke(Canvas canvas, Paint paint) {
    final eraserPaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (widths != null && widths!.length >= points.length) {
      for (int i = 0; i < points.length - 1; i++) {
        eraserPaint.strokeWidth = widths![i];
        canvas.drawLine(points[i], points[i + 1], eraserPaint);
      }
    } else {
      final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, eraserPaint);
    }
  }

  void _drawMarkerStroke(Canvas canvas, Paint paint) {
    final markerPaint = Paint()
      ..color = paint.color.withValues(alpha: opacity * 0.6)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.srcOver;
    if (widths != null && widths!.length >= points.length) {
      for (int i = 0; i < points.length - 1; i++) {
        markerPaint.strokeWidth = widths![i];
        canvas.drawLine(points[i], points[i + 1], markerPaint);
      }
    } else {
      final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, markerPaint);
    }
  }
}
