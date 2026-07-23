import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum ShapeType { rect, ellipse, polygon, line, curve }

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
  Color color;
  double strokeWidth;
  double opacity;
  bool isFilled;
  double rotation;
  bool selected;
  bool isGradient;
  List<GradientStop> gradientStops;
  double gradientAngle;

  Drawable({
    required this.id,
    this.isShape = false,
    this.shapeType,
    required this.points,
    this.color = Colors.black,
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.isFilled = false,
    this.rotation = 0.0,
    this.selected = false,
    this.isGradient = false,
    List<GradientStop>? gradientStops,
    this.gradientAngle = 0.0,
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

    if (isGradient && gradientStops.length >= 2) {
      if (isFilled || isShape) {
        final path = _createShapePath();
        if (path != null) {
          final rect = path.getBounds();
          p.shader = _createShader(rect);
        }
      }
    } else {
      p.color = color.withValues(alpha: opacity);
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

  ui.Path? _createShapePath() {
    if (shapeType == null) return null;
    switch (shapeType!) {
      case ShapeType.rect:
        return ui.Path()..addRect(bounds);
      case ShapeType.ellipse:
        return ui.Path()..addOval(bounds);
      case ShapeType.line:
        if (points.length < 2) return null;
        return ui.Path()..moveTo(points.first.dx, points.first.dy)..lineTo(points.last.dx, points.last.dy);
      case ShapeType.polygon:
        if (points.length < 3) return null;
        final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) { path.lineTo(points[i].dx, points[i].dy); }
        path.close();
        return path;
      case ShapeType.curve:
        return null;
    }
  }

  Shader _createShader(Rect rect) {
    final angleRad = gradientAngle * 3.14159265 / 180;
    final dx = cos(angleRad);
    final dy = sin(angleRad);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: gradientStops.map((s) => s.color.withValues(alpha: s.color.a * opacity)).toList(),
      stops: gradientStops.map((s) => s.position).toList(),
    ).createShader(rect);
  }

  Drawable copyWith({
    String? id,
    bool? isShape,
    ShapeType? shapeType,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    double? opacity,
    bool? isFilled,
    double? rotation,
    bool? selected,
    bool? isGradient,
    List<GradientStop>? gradientStops,
    double? gradientAngle,
  }) =>
      Drawable(
        id: id ?? this.id,
        isShape: isShape ?? this.isShape,
        shapeType: shapeType ?? this.shapeType,
        points: points ?? List.from(this.points),
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        opacity: opacity ?? this.opacity,
        isFilled: isFilled ?? this.isFilled,
        rotation: rotation ?? this.rotation,
        selected: selected ?? this.selected,
        isGradient: isGradient ?? this.isGradient,
        gradientStops: gradientStops ?? List.from(this.gradientStops),
        gradientAngle: gradientAngle ?? this.gradientAngle,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isShape': isShape,
        'shapeType': shapeType?.name,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': color.toARGB32(),
        'strokeWidth': strokeWidth,
        'opacity': opacity,
        'isFilled': isFilled,
        'rotation': rotation,
        'selected': selected,
        'isGradient': isGradient,
        'gradientStops': gradientStops.map((s) => s.toJson()).toList(),
        'gradientAngle': gradientAngle,
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
      );

  void _drawStroke(Canvas canvas, Paint paint) {
    if (points.length < 2) return;
    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }
}
