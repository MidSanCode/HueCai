import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum ShapeType { rect, ellipse, polygon, line, curve }

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
  });

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
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = isFilled ? PaintingStyle.fill : PaintingStyle.stroke;

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
