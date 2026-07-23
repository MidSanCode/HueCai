import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/project.dart';
import '../../models/drawable.dart';
import '../../providers/tool_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../utils/logger.dart';

class PaintCanvas extends StatefulWidget {
  final Project project;

  const PaintCanvas({super.key, required this.project});

  @override
  State<PaintCanvas> createState() => _PaintCanvasState();
}

class _PaintCanvasState extends State<PaintCanvas> {
  Drawable? _currentDrawable;
  Offset? _gradientStart;
  DateTime? _lastMultiTouchTime;
  int _lastTouchCount = 0;
  final _log = AppLogger();

  bool _isOnCanvas(Offset canvasPos) {
    return canvasPos.dx >= 0 &&
        canvasPos.dy >= 0 &&
        canvasPos.dx <= widget.project.settings.width &&
        canvasPos.dy <= widget.project.settings.height;
  }

  Offset _toCanvas(Offset screenPos, Size areaSize) {
    final cp = context.read<CanvasProvider>();
    final w = widget.project.settings.width / 2;
    final h = widget.project.settings.height / 2;
    final cx = areaSize.width / 2;
    final cy = areaSize.height / 2;
    double x = screenPos.dx - cp.offset.dx - cx;
    double y = screenPos.dy - cp.offset.dy - cy;
    final cosV = cos(cp.rotation);
    final sinV = sin(cp.rotation);
    final rx = x * cosV + y * sinV;
    final ry = -x * sinV + y * cosV;
    return Offset(rx / cp.scale + w, ry / cp.scale + h);
  }

  void _onPointerDown(Offset pos, Size areaSize) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = _toCanvas(pos, areaSize);

    _log.info('PointerDown tool=${tp.currentTool} canvasPos=(${canvasPos.dx.toStringAsFixed(1)}, ${canvasPos.dy.toStringAsFixed(1)})');

    if ((tp.currentTool == ToolType.brush || tp.currentTool == ToolType.eraser)) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        color: tp.currentTool == ToolType.eraser ? Colors.white : tp.primaryColor,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
    } else if (tp.currentTool == ToolType.shape) {
      pp.saveSnapshot();
      pp.clearSelection();
      final drawable = Drawable(
        id: const Uuid().v4(),
        isShape: true,
        shapeType: tp.currentShape,
        points: [canvasPos, canvasPos],
        color: tp.primaryColor,
        strokeWidth: tp.brushSize,
        isFilled: false,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
    } else if (tp.currentTool == ToolType.fill) {
      pp.saveSnapshot();
      final hit = _hitTest(canvasPos);
      if (hit != null) {
        pp.toggleFillDrawable(hit, tp.primaryColor);
      }
    } else if (tp.currentTool == ToolType.gradient) {
      _gradientStart = canvasPos;
      pp.saveSnapshot();
    } else if (tp.currentTool == ToolType.move) {
      final hit = _hitTest(canvasPos);
      if (hit != null) {
        pp.selectDrawable(hit);
      }
    }
  }

  void _onPointerMove(Offset pos, Size areaSize) {
    if (_currentDrawable == null && _gradientStart == null) return;
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = _toCanvas(pos, areaSize);

    if (tp.currentTool == ToolType.brush || tp.currentTool == ToolType.eraser) {
      _currentDrawable!.points.add(canvasPos);
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    } else if (tp.currentTool == ToolType.shape) {
      final snapped = _snapShapeEnd(tp, canvasPos);
      _currentDrawable!.points = [_currentDrawable!.points.first, snapped];
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    } else if (tp.currentTool == ToolType.gradient && _gradientStart != null) {
      pp.clearSelection();
      final angle = atan2(canvasPos.dy - _gradientStart!.dy, canvasPos.dx - _gradientStart!.dx) * 180 / pi;
      final drawable = Drawable(
        id: const Uuid().v4(),
        isShape: true,
        shapeType: ShapeType.rect,
        points: [_gradientStart!, canvasPos],
        color: tp.primaryColor,
        isFilled: true,
        isGradient: true,
        gradientStops: [
          GradientStop(position: 0, color: tp.primaryColor),
          GradientStop(position: 1, color: tp.secondaryColor),
        ],
        gradientAngle: angle,
      );
      if (_currentDrawable != null) {
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
      } else {
        pp.addDrawable(drawable);
        _currentDrawable = drawable;
      }
    }
  }

  void _onPointerUp() {
    if (_currentDrawable != null) {
      final pp = context.read<ProjectProvider>();
      if (_currentDrawable!.isShape) {
        _currentDrawable!.selected = true;
      }
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    }
    _currentDrawable = null;
    _gradientStart = null;
  }

  Offset _snapShapeEnd(ToolProvider tp, Offset end) {
    if (!tp.isStandardMode) return end;
    final start = _currentDrawable!.points.first;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();

    switch (tp.currentShape) {
      case ShapeType.rect:
      case ShapeType.ellipse:
        final size = absDx > absDy ? absDx : absDy;
        return Offset(
          start.dx + (dx >= 0 ? size : -size),
          start.dy + (dy >= 0 ? size : -size),
        );
      case ShapeType.line:
        final angle = atan2(dy, dx);
        final snapped = tp.snapAngle(angle);
        final len = Offset(dx, dy).distance;
        return Offset(
          start.dx + len * cos(snapped),
          start.dy + len * sin(snapped),
        );
      default:
        return end;
    }
  }

  Drawable? _hitTest(Offset canvasPos) {
    for (final layer in widget.project.layers.reversed) {
      for (final d in layer.drawables.reversed) {
        if (d.bounds.inflate(8).contains(canvasPos)) {
          return d;
        }
      }
    }
    return null;
  }

  void _handleMultiTouch(int count) {
    if (count < 2) return;
    final now = DateTime.now();
    if (_lastMultiTouchTime != null &&
        now.difference(_lastMultiTouchTime!) < const Duration(milliseconds: 400) &&
        _lastTouchCount == count) {
      final pp = context.read<ProjectProvider>();
      if (count == 2) pp.undo();
      if (count >= 3) pp.redo();
      _lastMultiTouchTime = null;
    } else {
      _lastMultiTouchTime = now;
      _lastTouchCount = count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ToolProvider>();
    final cp = context.watch<CanvasProvider>();
    final pp = context.watch<ProjectProvider>();
    final isMoveTool = tp.currentTool == ToolType.move;
    final hasSelection = pp.selectedDrawable != null;
    final isDrawingTool = tp.currentTool == ToolType.brush ||
        tp.currentTool == ToolType.eraser ||
        tp.currentTool == ToolType.shape;
    final pw = widget.project.settings.width.toDouble();
    final ph = widget.project.settings.height.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              cp.handleScroll(event);
            }
          },
          child: GestureDetector(
            onScaleStart: (details) {
              if (details.pointerCount >= 2) {
                _handleMultiTouch(details.pointerCount);
                return;
              }
              if (!isMoveTool || hasSelection) {
                _onPointerDown(details.localFocalPoint, areaSize);
              }
            },
            onScaleUpdate: (details) {
              if (details.pointerCount >= 2) {
                cp.panBy(details.focalPointDelta);
                cp.zoomBy(details.scale, details.focalPoint);
                cp.rotateBy(details.rotation);
              } else {
                if (isMoveTool && !hasSelection) {
                  cp.panBy(details.focalPointDelta);
                } else if (isDrawingTool) {
                  _onPointerMove(details.localFocalPoint, areaSize);
                }
              }
            },
            onScaleEnd: (details) {
              if (_currentDrawable != null || _gradientStart != null) {
                _onPointerUp();
              }
            },
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: ClipRect(
                child: CustomPaint(
                  size: areaSize,
                  painter: _BackgroundPainter(),
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(
                          areaSize.width / 2 + cp.offset.dx,
                          areaSize.height / 2 + cp.offset.dy, 0, 1)
                      ..rotateZ(cp.rotation)
                      ..scaleByDouble(cp.scale, cp.scale, cp.scale, 1)
                      ..translateByDouble(-pw / 2, -ph / 2, 0, 1),
                    child: CustomPaint(
                      painter: _CanvasPainter(
                        project: widget.project,
                        currentDrawable: _currentDrawable,
                      ),
                      child: SizedBox(width: pw, height: ph),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF2D2D2D),
    );
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => false;
}

class _CanvasPainter extends CustomPainter {
  final Project project;
  final Drawable? currentDrawable;

  _CanvasPainter({required this.project, this.currentDrawable});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    for (final layer in project.layers) {
      if (!layer.visible) continue;
      for (final d in layer.drawables) {
        d.draw(canvas, Paint());
        if (d.selected) {
          _drawSelectionHandles(canvas, d);
        }
      }
    }

    if (currentDrawable != null) {
      currentDrawable!.draw(canvas, Paint());
    }
    canvas.restore();
  }

  void _drawSelectionHandles(Canvas canvas, Drawable d) {
    final bounds = d.bounds;
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(bounds, paint);
    for (final corner in [
      bounds.topLeft, bounds.topRight,
      bounds.bottomLeft, bounds.bottomRight,
      bounds.centerLeft, bounds.centerRight,
      bounds.topCenter, bounds.bottomCenter,
    ]) {
      canvas.drawCircle(corner, 4, Paint()..color = Colors.white);
      canvas.drawCircle(corner, 4, Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) => true;
}
