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
  double _currentPressure = 0.5;

  // Image placement drag
  Offset? _imagePlaceStartOffset;
  Offset? _imagePlaceStartPos;

  // Multi-click shape state (line, curve, polygon)
  bool _isPlacingShapePoints = false;

  // Select tool rubber band
  Offset? _selectStart;

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

    // Cancel any pending multi-click shape if switching to non-shape tool
    if (_isPlacingShapePoints && tp.currentTool != ToolType.shape) {
      _cancelMultiClickShape();
    }

    _log.info('PointerDown tool=${tp.currentTool} canvasPos=(${canvasPos.dx.toStringAsFixed(1)}, ${canvasPos.dy.toStringAsFixed(1)})');

    final pp = context.read<ProjectProvider>();
    if (pp.isPlacingImage) {
      _dragConfirmed = true;
      _imagePlaceStartOffset = pp.imagePlacingOffset;
      _imagePlaceStartPos = pos;
      return;
    }

    if (tp.currentTool == ToolType.select) {
      pp.saveSnapshot();
      pp.clearSelection();
      _selectStart = canvasPos;
      _dragConfirmed = false;
      return;
    }

    if (tp.currentTool == ToolType.fill) {
      pp.saveSnapshot();
      final hit = _hitTest(canvasPos);
      if (hit != null) pp.toggleFillDrawable(hit, tp.primaryColor);
      return;
    }

    if (tp.currentTool == ToolType.gradient) {
      _gradientStart = canvasPos;
      return;
    }

    // Multi-click shapes: line, polygon
    if (tp.currentTool == ToolType.shape &&
        (tp.currentShape == ShapeType.line ||
         tp.currentShape == ShapeType.polygon)) {
      // Reset if no current drawable or shape type changed
      if (!_isPlacingShapePoints || _currentDrawable == null ||
          _currentDrawable!.shapeType != tp.currentShape) {
        _isPlacingShapePoints = false;
        _currentDrawable = null;
      }
      pp.saveSnapshot();

      if (_isPlacingShapePoints && _currentDrawable != null) {
        // Add point to existing shape
        _currentDrawable!.points.add(canvasPos);
        if (tp.currentShape == ShapeType.line && _currentDrawable!.points.length >= 2) {
          // Line: finalize after 2 clicks
          final start = _currentDrawable!.points.first;
          final end = _currentDrawable!.points.last;
          _currentDrawable!.points = [start, end, Offset.lerp(start, end, 0.5)!];
          _isPlacingShapePoints = false;
          _currentDrawable!.selected = true;
          _currentDrawable = null;
        } else if (tp.currentShape == ShapeType.polygon) {
          // Check if clicked near first point to close
          final dist = (canvasPos - _currentDrawable!.points.first).distance;
          if (_currentDrawable!.points.length >= 3 && dist < 15) {
            _currentDrawable!.selected = true;
            _isPlacingShapePoints = false;
            _currentDrawable = null;
          }
        }
        if (_currentDrawable == null) {
          pp.refresh();
          return;
        }
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
      } else {
        // Start new multi-click shape
        _isPlacingShapePoints = true;
        final drawable = Drawable(
          id: const Uuid().v4(),
          isShape: true,
          shapeType: tp.currentShape,
          points: [canvasPos],
          color: tp.primaryColor,
          strokeWidth: tp.brushSize,
          isFilled: false,
        );
        _currentDrawable = drawable;
        pp.addDrawable(drawable);
        _dragConfirmed = true;
      }
      return;
    }

    if (tp.currentTool == ToolType.move) {
      final hit = _hitTest(canvasPos);
      if (hit != null) {
        pp.selectDrawable(hit);
      } else {
        pp.clearSelection();
      }
      return;
    }
    // Brush/eraser/shape (rect/ellipse) start is deferred to _tryBeginDrag
  }

  void _tryBeginDrag(Offset pos, Size areaSize) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = _toCanvas(pos, areaSize);

    if (tp.currentTool == ToolType.smudge ||
        tp.currentTool == ToolType.willowLeaf ||
        tp.currentTool == ToolType.liquify) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      _lastPointerTime = DateTime.now();
      _lastPointerPos = pos;
      final color = tp.currentTool == ToolType.smudge
          ? tp.primaryColor.withAlpha(100)
          : tp.primaryColor;
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: color,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      return;
    }

    if (tp.currentTool == ToolType.select) {
      if (_selectStart == null) return;
      _dragConfirmed = true;
      final drawable = Drawable(
        id: const Uuid().v4(),
        isShape: true,
        shapeType: ShapeType.rect,
        points: [_selectStart!, canvasPos],
        color: Colors.blue.withAlpha(60),
        isFilled: true,
        strokeWidth: 1,
        opacity: 0.3,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      return;
    }

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
      _isPlacingShapePoints = false;
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

    // Image placement: move the image
    if (pp.isPlacingImage && _imagePlaceStartPos != null && _imagePlaceStartOffset != null) {
      final delta = pos - _imagePlaceStartPos!;
      final canvasDelta = delta / context.read<CanvasProvider>().scale;
      pp.updateImagePlacement(offset: _imagePlaceStartOffset! + canvasDelta);
      return;
    }

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

    // Select tool rubber band
    if (tp.currentTool == ToolType.select && _selectStart != null) {
      if (_currentDrawable == null) {
        if ((pos - _downScreenPos!).distance < _dragThreshold) return;
        _tryBeginDrag(pos, areaSize);
      }
      if (_currentDrawable != null) {
        _currentDrawable!.points = [_selectStart!, canvasPos];
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
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

    if (tp.currentTool == ToolType.brush ||
        tp.currentTool == ToolType.eraser ||
        tp.currentTool == ToolType.smudge ||
        tp.currentTool == ToolType.willowLeaf ||
        tp.currentTool == ToolType.liquify) {
      final as = context.read<AppSettings>();
      final now = DateTime.now();
      double widthFromVelocity = tp.brushSize;
      double widthFromPressure = tp.brushSize;

      // Velocity-based width
      if (as.velocityWidthEnabled && _lastPointerTime != null && _lastPointerPos != null) {
        final dt = now.difference(_lastPointerTime!).inMilliseconds / 1000.0;
        final dist = (pos - _lastPointerPos!).distance;
        if (dt > 0) {
          const double maxVel = 8000;
          const double minVel = 200;
          final velocity = (dist / dt).clamp(minVel, maxVel);
          final ratio = (velocity - minVel) / (maxVel - minVel);
          final range = as.velocityMaxScale - as.velocityMinScale;
          final scale = as.velocityMaxScale - ratio * range;
          widthFromVelocity = tp.brushSize * scale;
        }
      }

      // Pressure-based width (if supported)
      if (as.pressureWidthEnabled && as.hasPressure && _currentPressure > 0) {
        final pressureRatio = (_currentPressure).clamp(0.0, 1.0);
        final range = as.pressureMaxScale - as.pressureMinScale;
        final scale = as.pressureMinScale + pressureRatio * range;
        widthFromPressure = tp.brushSize * scale;
      } else {
        widthFromPressure = widthFromVelocity;
      }

      // Blend velocity and pressure
      double currentWidth = widthFromVelocity * (1 - as.velocityPressureBlend) + widthFromPressure * as.velocityPressureBlend;

      // Responsive smoothing
      if (_smoothedWidth > 0) {
        currentWidth = _smoothedWidth + (currentWidth - _smoothedWidth) * as.velocitySmoothing;
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
    _currentDrawable!.widths ??= [];
    // Interpolate intermediate points for smooth high-speed turns
    if (_currentDrawable!.points.isNotEmpty) {
      final lastPt = _currentDrawable!.points.last;
      final dist = (drawPos - lastPt).distance;
      const double maxStep = 4.0;
      if (dist > maxStep) {
        final steps = (dist / maxStep).ceil();
        for (int s = 1; s < steps; s++) {
          final t = s / steps;
          final mid = Offset.lerp(lastPt, drawPos, t)!;
          _currentDrawable!.points.add(mid);
          _currentDrawable!.widths!.add(currentWidth);
        }
      }
    }
    _currentDrawable!.points.add(drawPos);
    _currentDrawable!.widths!.add(currentWidth);
    pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
    } else if (tp.currentTool == ToolType.shape) {
      if (tp.currentShape == ShapeType.curve) {
        // Curve: accumulate all points during drag
        _currentDrawable!.points.add(canvasPos);
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
      } else {
        final snapped = _snapShapeEnd(tp, canvasPos);
        _currentDrawable!.points = [_currentDrawable!.points.first, snapped];
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
      }
    }
  }

  void _onPointerUp() {
    _stabilizerQueue.clear();
    _lastPointerTime = null;
    _lastPointerPos = null;
    _imagePlaceStartOffset = null;
    _imagePlaceStartPos = null;
    final pp = context.read<ProjectProvider>();
    final tp = context.read<ToolProvider>();

    // Select tool: select drawables in rubber band rect
    if (tp.currentTool == ToolType.select && _selectStart != null && _currentDrawable != null) {
      final rect = Rect.fromPoints(_selectStart!, _currentDrawable!.points.last);
      pp.clearSelection();
      for (final layer in widget.project.layers) {
        for (final d in layer.drawables) {
          if (d.id == _currentDrawable!.id) continue;
          if (d.bounds.overlaps(rect)) {
            d.selected = true;
          }
        }
      }
      pp.deleteDrawable(_currentDrawable!.id);
      _currentDrawable = null;
      _selectStart = null;
      _downScreenPos = null;
      _dragConfirmed = false;
      pp.refresh();
      return;
    }

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
    _selectStart = null;
    _downScreenPos = null;
    _dragConfirmed = false;
  }

  void _cancelMultiClickShape() {
    if (_isPlacingShapePoints && _currentDrawable != null) {
      final pp = context.read<ProjectProvider>();
      pp.deleteDrawable(_currentDrawable!.id);
      _currentDrawable = null;
    }
    _isPlacingShapePoints = false;
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
        tp.currentTool == ToolType.fill ||
        tp.currentTool == ToolType.select ||
        tp.currentTool == ToolType.smudge ||
        tp.currentTool == ToolType.willowLeaf ||
        tp.currentTool == ToolType.liquify;
    final pw = widget.project.settings.width.toDouble();
    final ph = widget.project.settings.height.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          onPointerMove: (event) {
            _currentPressure = event.pressure;
          },
          onPointerDown: (event) {
            _currentPressure = event.pressure;
            // Check if device supports pressure
            if (event.pressureMax > 0) {
              context.read<AppSettings>().updatePressureCapability(true);
            }
          },
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
      // Draw image if present
      if (layer.image != null) {
        final img = layer.image!;
        canvas.save();
        canvas.translate(layer.imageOffset.dx + img.width / 2, layer.imageOffset.dy + img.height / 2);
        canvas.rotate(layer.imageRotation);
        final flipX = layer.imageFlipH ? -1.0 : 1.0;
        final flipY = layer.imageFlipV ? -1.0 : 1.0;
        canvas.scale(layer.imageScale * flipX, layer.imageScale * flipY);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
          Paint()..color = Colors.white.withValues(alpha: layer.opacity),
        );
        canvas.restore();
      }
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
