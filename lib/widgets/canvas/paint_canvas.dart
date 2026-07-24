import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/project.dart';
import '../../models/drawable.dart';
import '../../providers/tool_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/app_settings.dart';
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

  // Gesture debounce
  Offset? _downScreenPos;
  bool _dragConfirmed = false;
  bool _isScaling = false;
  DateTime? _scaleEndTime;
  static const double _dragThreshold = 12.0;
  static const Duration _scaleCooldown = Duration(milliseconds: 600);

  final _log = AppLogger();

  // Stabilizer smoothing
  final List<Offset> _stabilizerQueue = [];

  // Velocity tracking for dynamic brush width
  DateTime? _lastPointerTime;
  Offset? _lastPointerPos;
  double _smoothedWidth = 0;

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

    // Ignore single-finger down if we were just scaling
    if (_scaleEndTime != null &&
        DateTime.now().difference(_scaleEndTime!) < _scaleCooldown) {
      return;
    }

    final canvasPos = _toCanvas(pos, areaSize);
    _downScreenPos = pos;
    _dragConfirmed = false;
    _lastPointerTime = null;
    _lastPointerPos = null;
    _smoothedWidth = 0;

    _log.info('PointerDown tool=${tp.currentTool} canvasPos=(${canvasPos.dx.toStringAsFixed(1)}, ${canvasPos.dy.toStringAsFixed(1)})');

    if (tp.currentTool == ToolType.fill) {
      final pp = context.read<ProjectProvider>();
      pp.saveSnapshot();
      final hit = _hitTest(canvasPos);
      if (hit != null) pp.toggleFillDrawable(hit, tp.primaryColor);
    } else if (tp.currentTool == ToolType.gradient) {
      _gradientStart = canvasPos;
    } else if (tp.currentTool == ToolType.move) {
      final hit = _hitTest(canvasPos);
      if (hit != null) context.read<ProjectProvider>().selectDrawable(hit);
    }
    // Brush/eraser/shape start is deferred to _tryBeginDrag
  }

  void _tryBeginDrag(Offset pos, Size areaSize) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = _toCanvas(pos, areaSize);

    if (tp.currentTool == ToolType.brush || tp.currentTool == ToolType.eraser) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      _lastPointerTime = DateTime.now();
      _lastPointerPos = pos;
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: tp.currentTool == ToolType.eraser ? Colors.white : tp.primaryColor,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
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
      _dragConfirmed = true;
    }
  }

  void _onPointerMove(Offset pos, Size areaSize) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = _toCanvas(pos, areaSize);

    // Gradient: apply drag threshold before updating
    if (tp.currentTool == ToolType.gradient && _gradientStart != null) {
      if (!_dragConfirmed) {
        if (_downScreenPos == null) return;
        if ((pos - _downScreenPos!).distance < _dragThreshold) return;
        _dragConfirmed = true;
      }
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
        pp.saveSnapshot();
        pp.addDrawable(drawable);
        _currentDrawable = drawable;
      }
      return;
    }

    // Brush/eraser/shape: defer start until drag threshold is met
    if (_currentDrawable == null) {
      if (_downScreenPos == null) return;
      if ((pos - _downScreenPos!).distance < _dragThreshold) return;
      _tryBeginDrag(pos, areaSize);
      if (_currentDrawable == null) return;
    }

    if (tp.currentTool == ToolType.brush || tp.currentTool == ToolType.eraser) {
      final as = context.read<AppSettings>();
      // Velocity-based dynamic width
      final now = DateTime.now();
      double currentWidth = tp.brushSize;
      if (as.velocityWidthEnabled && _lastPointerTime != null && _lastPointerPos != null) {
        final dt = now.difference(_lastPointerTime!).inMilliseconds / 1000.0;
        final dist = (pos - _lastPointerPos!).distance;
        if (dt > 0) {
          const double maxVel = 6000;
          const double minVel = 100;
          final velocity = (dist / dt).clamp(minVel, maxVel);
          final ratio = (velocity - minVel) / (maxVel - minVel);
          final range = as.velocityMaxScale - as.velocityMinScale;
          final scale = as.velocityMaxScale - ratio * range;
          currentWidth = tp.brushSize * scale;
        }
      }
      // Exponential smoothing for natural transition
      if (_smoothedWidth > 0) {
        currentWidth = currentWidth * as.velocitySmoothing + _smoothedWidth * (1 - as.velocitySmoothing);
      }
      _smoothedWidth = currentWidth;
      _lastPointerTime = now;
      _lastPointerPos = pos;

      final stabilizerLevel = context.read<AppSettings>().stabilizer.round();
      Offset drawPos;
      if (stabilizerLevel > 0) {
        _stabilizerQueue.add(canvasPos);
        while (_stabilizerQueue.length > stabilizerLevel) {
          _stabilizerQueue.removeAt(0);
        }
        if (_stabilizerQueue.length >= 2) {
          drawPos = Offset(
            _stabilizerQueue.map((p) => p.dx).reduce((a, b) => a + b) / _stabilizerQueue.length,
            _stabilizerQueue.map((p) => p.dy).reduce((a, b) => a + b) / _stabilizerQueue.length,
          );
        } else {
          drawPos = canvasPos;
        }
      } else {
        drawPos = canvasPos;
      }
      _currentDrawable!.points.add(drawPos);
      _currentDrawable!.widths ??= [];
      _currentDrawable!.widths!.add(currentWidth);
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    } else if (tp.currentTool == ToolType.shape) {
      final snapped = _snapShapeEnd(tp, canvasPos);
      _currentDrawable!.points = [_currentDrawable!.points.first, snapped];
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    }
  }

  void _onPointerUp() {
    _stabilizerQueue.clear();
    _lastPointerTime = null;
    _lastPointerPos = null;
    final pp = context.read<ProjectProvider>();
    // If drag was never confirmed, discard the pending drawable
    if (!_dragConfirmed && _currentDrawable != null) {
      pp.deleteDrawable(_currentDrawable!.id);
      _currentDrawable = null;
    } else if (_currentDrawable != null) {
      if (_currentDrawable!.isShape) {
        _currentDrawable!.selected = true;
      }
      pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    }
    // If gradient drag was never confirmed, just discard the start point
    _currentDrawable = null;
    _gradientStart = null;
    _downScreenPos = null;
    _dragConfirmed = false;
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
        tp.currentTool == ToolType.shape ||
        tp.currentTool == ToolType.gradient ||
        tp.currentTool == ToolType.fill;
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
                _isScaling = true;
                _scaleEndTime = null;
                // Cancel any pending single-finger drawing state
                _downScreenPos = null;
                _dragConfirmed = false;
                _handleMultiTouch(details.pointerCount);
                return;
              }
              // Ignore single-finger immediately after multi-touch cooldown
              if (_isScaling) return;
              if (_scaleEndTime != null &&
                  DateTime.now().difference(_scaleEndTime!) < _scaleCooldown) {
                return;
              }
              if (!isMoveTool || hasSelection) {
                _onPointerDown(details.localFocalPoint, areaSize);
              }
            },
            onScaleUpdate: (details) {
              if (details.pointerCount >= 2) {
                _isScaling = true;
                _scaleEndTime = null;
                cp.panBy(details.focalPointDelta);
                cp.zoomBy(details.scale, details.focalPoint);
                cp.rotateBy(details.rotation);
              } else {
                if (_isScaling) return;
                if (_scaleEndTime != null &&
                    DateTime.now().difference(_scaleEndTime!) < _scaleCooldown) {
                  return;
                }
                if (isMoveTool && !hasSelection) {
                  final delta = details.focalPointDelta;
                  if (delta.distance > 2.0) {
                    cp.panBy(delta);
                  }
                } else if (isDrawingTool) {
                  _onPointerMove(details.localFocalPoint, areaSize);
                }
              }
            },
            onScaleEnd: (details) {
              if (_isScaling) {
                _isScaling = false;
                _scaleEndTime = DateTime.now();
              }
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
                          referenceImage: cp.referenceImage,
                          referenceOpacity: cp.referenceOpacity,
                          showReference: cp.showReference,
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
  final ui.Image? referenceImage;
  final double referenceOpacity;
  final bool showReference;

  _CanvasPainter({
    required this.project,
    this.currentDrawable,
    this.referenceImage,
    this.referenceOpacity = 0.5,
    this.showReference = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    if (showReference && referenceImage != null) {
      final img = referenceImage!;
      final scale = min(size.width / img.width, size.height / img.height);
      final dx = (size.width - img.width * scale) / 2;
      final dy = (size.height - img.height * scale) / 2;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(dx, dy, img.width * scale, img.height * scale),
        Paint()..color = Colors.white.withAlpha((referenceOpacity * 255).round()),
      );
      canvas.restore();
    }

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
