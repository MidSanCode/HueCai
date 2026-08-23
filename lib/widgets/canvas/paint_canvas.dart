import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/project.dart';
import '../../models/drawable.dart';
import '../../models/selection_data.dart';
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
  Offset? _downCanvasPos;
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

  // Select tool state
  Offset? _selectStart;
  List<Offset> _lassoPoints = [];
  Offset? _brushSelLast;
  int? _warpDragIndex;
  Offset? _editMoveStart;

  Future<void> _onMagicWandTap(Offset canvasPos, ProjectProvider pp) async {
    final snap = pp.canvasSnapshot;
    if (snap == null) return;
    final byteData = await snap.toByteData();
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    try {
      final mask = SelectionMask(snap.width, snap.height);
      mask.floodFill(canvasPos, bytes, 30, true);
      pp.applySelectionShape(mask, pp.selectionAddMode);
    } catch (_) {}
  }

  bool _handleEditHitTest(Offset canvasPos, ProjectProvider pp) {
    final bounds = pp.selectionClipBounds;
    if (bounds.width <= 0 || bounds.height <= 0) return false;
    if (pp.transformMode == TransformMode.scale) {
      final handles = _getScaleHandles(bounds);
      for (int i = 0; i < handles.length; i++) {
        if ((canvasPos - handles[i]).distance < 10) {
          _warpDragIndex = i;
          _selectStart = canvasPos;
          return true;
        }
      }
    } else {
      final grid = _getWarpGrid(bounds, pp.editScaleX, pp.editScaleY);
      for (int i = 0; i < grid.length; i++) {
        if ((canvasPos - grid[i]).distance < 12) {
          _warpDragIndex = i;
          _selectStart = canvasPos;
          return true;
        }
      }
    }
    return false;
  }

  void _onStartEditTransform(Offset canvasPos) {
    _warpDragIndex = null;
    _selectStart = canvasPos;
    _editMoveStart = canvasPos;
  }

  void _onEditMove(Offset canvasPos, ProjectProvider pp) {
    if (_warpDragIndex != null) {
      final bounds = pp.selectionClipBounds;
      final sx = pp.editScaleX;
      final sy = pp.editScaleY;
      final grid = _getWarpGrid(bounds, sx, sy);
      if (_warpDragIndex! < grid.length) {
        final delta = canvasPos - _selectStart!;
        _selectStart = canvasPos;
        // For scale mode handles, map delta to scale
        if (pp.transformMode == TransformMode.scale) {
          final idx = _warpDragIndex!;
          double newSx = sx, newSy = sy;
          // Corner handles
          if (idx == 0) { // top-left
            newSx = (bounds.width + delta.dx) / bounds.width;
            newSy = (bounds.height + delta.dy) / bounds.height;
          } else if (idx == 2) { // top-right
            newSx = (bounds.width - delta.dx) / bounds.width;
            newSy = (bounds.height + delta.dy) / bounds.height;
          } else if (idx == 5) { // bottom-left
            newSx = (bounds.width + delta.dx) / bounds.width;
            newSy = (bounds.height - delta.dy) / bounds.height;
          } else if (idx == 7) { // bottom-right
            newSx = (bounds.width - delta.dx) / bounds.width;
            newSy = (bounds.height - delta.dy) / bounds.height;
          }
          pp.updateSelectionEditTransform(scaleX: newSx * sx, scaleY: newSy * sy);
        }
      }
    } else if (_editMoveStart != null) {
      final delta = canvasPos - _selectStart!;
      _selectStart = canvasPos;
      pp.updateSelectionEditTransform(
        translate: pp.editTranslate + delta,
      );
    }
  }

  List<Offset> _getScaleHandles(Rect bounds) {
    return [
      bounds.topLeft, bounds.topCenter, bounds.topRight,
      bounds.centerLeft, bounds.centerRight,
      bounds.bottomLeft, bounds.bottomCenter, bounds.bottomRight,
    ];
  }

  List<Offset> _getWarpGrid(Rect bounds, double sx, double sy) {
    final pts = <Offset>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final t = col / 2;
        final u = row / 2;
        pts.add(Offset(
          bounds.left + t * bounds.width * sx,
          bounds.top + u * bounds.height * sy,
        ));
      }
    }
    return pts;
  }

  void _captureSmudgeSource() {
    final pp = context.read<ProjectProvider>();
    if (_currentDrawable == null || !_currentDrawable!.isSmudge) return;
    final pw = widget.project.settings.width.toInt();
    final ph = widget.project.settings.height.toInt();
    if (pw <= 0 || ph <= 0) return;
    final recorder = ui.PictureRecorder();
    final offscreenCanvas = Canvas(recorder, Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()));
    for (final layer in widget.project.layers) {
      if (!layer.visible) continue;
      for (final d in layer.drawables) {
        if (d.id == _currentDrawable!.id) continue;
        d.draw(offscreenCanvas, Paint());
      }
    }
    final picture = recorder.endRecording();
    picture.toImage(pw, ph).then((img) async {
      if (_currentDrawable != null && _currentDrawable!.isSmudge) {
        final data = await img.toByteData();
        if (data != null) {
          _currentDrawable!
            ..smudgeSource = img
            ..smudgePixels = data.buffer.asUint8List()
            ..smudgeW = pw
            ..smudgeH = ph;
          pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
        }
      }
    });
  }

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

  Future<void> _onPointerDown(Offset pos, Size areaSize) async {
    final tp = context.read<ToolProvider>();

    // Ignore single-finger down if we were just scaling
    if (_scaleEndTime != null &&
        DateTime.now().difference(_scaleEndTime!) < _scaleCooldown) {
      return;
    }

    final canvasPos = _toCanvas(pos, areaSize);
    _downScreenPos = pos;
    _downCanvasPos = canvasPos;
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
      if (pp.selectionPhase == SelectionPhase.editing) {
        // In edit mode, check for transform handle hit
        if (_handleEditHitTest(canvasPos, pp)) return;
        _onStartEditTransform(canvasPos);
        return;
      }
      if (pp.selectionMethod == SelectionMethod.magicWand) {
        // Wand samples the rasterized canvas, so the snapshot must exist.
        if (pp.selectionPhase == SelectionPhase.none) {
          await pp.beginSelection();
        }
        await _onMagicWandTap(canvasPos, pp);
        return;
      }
      // Other methods work on the mask directly; beginSelection registers
      // the mask synchronously, so don't block the gesture on the snapshot.
      if (pp.selectionPhase == SelectionPhase.none) {
        pp.beginSelection();
      }
      _selectStart = canvasPos;
      _lassoPoints = [canvasPos];
      _brushSelLast = null;
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

  void _tryBeginDrag(Offset pos, Size areaSize, {Offset? canvasStart}) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = canvasStart ?? _toCanvas(pos, areaSize);

    if (tp.currentTool == ToolType.smudge) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      _lastPointerTime = DateTime.now();
      _lastPointerPos = pos;
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: tp.primaryColor,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
        isSmudge: true,
        brushType: tp.brushType,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      _captureSmudgeSource();
      return;
    }

    if (tp.currentTool == ToolType.willowLeaf) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      _lastPointerTime = DateTime.now();
      _lastPointerPos = pos;
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: tp.primaryColor,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
        leaves: <LeafData>[],
        brushType: tp.brushType,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      return;
    }

    if (tp.currentTool == ToolType.liquify) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      _lastPointerTime = DateTime.now();
      _lastPointerPos = pos;
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: tp.primaryColor.withAlpha(80),
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
        brushType: tp.brushType,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      return;
    }

    if (tp.currentTool == ToolType.select) {
      if (_selectStart == null) return;
      _dragConfirmed = true;
      if (pp.selectionMethod == SelectionMethod.lasso) {
        // Will accumulate points in _onPointerMove
        return;
      }
      // Rect or ellipse: show rubber band
      final drawable = Drawable(
        id: const Uuid().v4(),
        isShape: true,
        shapeType: pp.selectionMethod == SelectionMethod.ellipse ? ShapeType.ellipse : ShapeType.rect,
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
        brushType: tp.brushType,
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
      if (_currentDrawable != null) {
        // Keep both endpoints tracking the pointer while dragging.
        _currentDrawable!.points = [_gradientStart!, canvasPos];
        pp.updateDrawable(_currentDrawable!.id, _currentDrawable!);
      } else {
        final drawable = Drawable(
          id: const Uuid().v4(),
          isShape: true,
          shapeType: ShapeType.rect,
          points: [_gradientStart!, canvasPos],
          color: tp.gradientStartColor,
          isFilled: true,
          isGradient: true,
          gradientStops: [
            GradientStop(position: 0, color: tp.gradientStartColor),
            GradientStop(position: 1, color: tp.gradientEndColor),
          ],
        );
        pp.saveSnapshot();
        pp.addDrawable(drawable);
        _currentDrawable = drawable;
      }
      return;
    }

    // Select tool: lasso / rect / ellipse / brush
    if (tp.currentTool == ToolType.select && _selectStart != null) {
      if (pp.selectionPhase == SelectionPhase.editing) {
        _onEditMove(canvasPos, pp);
        return;
      }
      if (pp.selectionMethod == SelectionMethod.brush) {
        // Paint brush on selection mask, interpolating between stamps so
        // fast strokes stay connected.
        final bs = tp.brushSize;
        final radius = bs * 0.5;
        final mask = SelectionMask(widget.project.settings.width.toInt(), widget.project.settings.height.toInt());
        final from = _brushSelLast ?? canvasPos;
        final dist = (canvasPos - from).distance;
        final step = (radius * 0.5).clamp(2.0, 12.0);
        final steps = (dist / step).ceil().clamp(1, 512);
        for (int i = 1; i <= steps; i++) {
          mask.fillCircle(Offset.lerp(from, canvasPos, i / steps)!, radius, true);
        }
        pp.applySelectionShape(mask, pp.selectionAddMode);
        _brushSelLast = canvasPos;
        return;
      }
      if (pp.selectionMethod == SelectionMethod.lasso) {
        if (_dragConfirmed || (pos - _downScreenPos!).distance >= _dragThreshold) {
          _dragConfirmed = true;
          _lassoPoints.add(canvasPos);
          pp.refresh(); // repaint for live marching-ants preview
        }
        return;
      }
      // Rect or ellipse rubber band
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
      // Begin the stroke at the true pen-down position so the mark lands
      // exactly under the pointer instead of jumping to the threshold point.
      _tryBeginDrag(pos, areaSize, canvasStart: _downCanvasPos);
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

      // Velocity-based width: fast strokes get thinner, slow strokes thicker.
      if (as.velocityWidthEnabled && _lastPointerTime != null && _lastPointerPos != null) {
        final dt = now.difference(_lastPointerTime!).inMicroseconds / 1e6;
        final dist = (pos - _lastPointerPos!).distance;
        if (dt > 0.002) {
          const double minVel = 250; // at or below this speed → thickest
          const double maxVel = 4500; // at or above this speed → thinnest
          final velocity = (dist / dt).clamp(minVel, maxVel);
          var ratio = (velocity - minVel) / (maxVel - minVel);
          ratio = pow(ratio, 0.65).toDouble(); // thin out sooner for perceptual response
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

    // Select tool: apply selection
    if (tp.currentTool == ToolType.select && _selectStart != null) {
      if (pp.selectionPhase == SelectionPhase.editing) {
        _warpDragIndex = null;
        _editMoveStart = null;
      } else if (pp.selectionMethod == SelectionMethod.lasso && _lassoPoints.length >= 3) {
        // Close lasso and fill mask
        final w = widget.project.settings.width.toInt();
        final h = widget.project.settings.height.toInt();
        final mask = SelectionMask(w, h);
        mask.fillPolygon(_lassoPoints, true);
        pp.applySelectionShape(mask, pp.selectionAddMode);
      } else if (_currentDrawable != null && (_currentDrawable!.isShape || pp.selectionMethod != SelectionMethod.lasso)) {
        if (pp.selectionMethod == SelectionMethod.rect || pp.selectionMethod == SelectionMethod.ellipse) {
          final rect = Rect.fromPoints(_selectStart!, _currentDrawable!.points.last);
          final w = widget.project.settings.width.toInt();
          final h = widget.project.settings.height.toInt();
          final mask = SelectionMask(w, h);
          if (pp.selectionMethod == SelectionMethod.ellipse) {
            mask.fillEllipse(rect, true);
          } else {
            mask.fillRect(rect, true);
          }
          pp.applySelectionShape(mask, pp.selectionAddMode);
        }
        pp.deleteDrawable(_currentDrawable!.id);
      }
      _currentDrawable = null;
      _selectStart = null;
      _lassoPoints = [];
      _brushSelLast = null;
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
    _downCanvasPos = null;
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
      if (count == 2) pp.smartUndo();
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
            // Only a real stylus reports meaningful pressure; mouse/touch
            // pressure is constant and would cancel velocity dynamics.
            final isStylus = event.kind == PointerDeviceKind.stylus ||
                event.kind == PointerDeviceKind.invertedStylus;
            context.read<AppSettings>().updatePressureCapability(
                isStylus && event.pressureMax > 0);
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
              // Finalize select-tool gestures too: lasso/wand never create a
              // drawable, so they previously skipped pointer-up entirely.
              final wasSelecting = context.read<ToolProvider>().currentTool ==
                      ToolType.select &&
                  _selectStart != null;
              if (_currentDrawable != null ||
                  _gradientStart != null ||
                  wasSelecting) {
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
                          selectionMaskImage: pp.selectionMaskImage,
                          selectionClipImage: pp.selectionClipImage,
                          selectionClipBounds: pp.selectionClipBounds,
                          selectionOutlinePath: pp.selectionOutlinePath,
                          selectionSolidImage: pp.selectionSolidImage,
                          selectionCutout: pp.selectionCutout,
                          liveLassoPoints:
                              tp.currentTool == ToolType.select &&
                                      pp.selectionMethod == SelectionMethod.lasso
                                  ? _lassoPoints
                                  : const [],
                          selectionPhase: pp.selectionPhase,
                          viewScale: cp.scale,
                          transformMode: pp.transformMode,
                          editScaleX: pp.editScaleX,
                          editScaleY: pp.editScaleY,
                          editRotate: pp.editRotate,
                          editTranslate: pp.editTranslate,
                          hasActiveSelection: pp.hasActiveSelection,
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
  final ui.Image? selectionMaskImage;
  final ui.Image? selectionClipImage;
  final Rect selectionClipBounds;
  final ui.Path? selectionOutlinePath;
  final ui.Image? selectionSolidImage;
  final bool selectionCutout;
  final List<Offset> liveLassoPoints;
  final SelectionPhase selectionPhase;
  final TransformMode transformMode;
  final double editScaleX, editScaleY, editRotate;
  final Offset editTranslate;
  final bool hasActiveSelection;
  final double viewScale;

  _CanvasPainter({
    required this.project,
    this.currentDrawable,
    this.selectionMaskImage,
    this.selectionClipImage,
    this.selectionClipBounds = Rect.zero,
    this.selectionOutlinePath,
    this.selectionSolidImage,
    this.selectionCutout = false,
    this.liveLassoPoints = const [],
    this.selectionPhase = SelectionPhase.none,
    this.transformMode = TransformMode.scale,
    this.editScaleX = 1, this.editScaleY = 1,
    this.editRotate = 0,
    this.editTranslate = Offset.zero,
    this.hasActiveSelection = false,
    this.viewScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final pw = project.settings.width.toDouble();
    final ph = project.settings.height.toDouble();
    final docRect = Rect.fromLTWH(0, 0, pw, ph);
    // Everything (strokes, previews, overlays) is hard-clipped to the
    // document rectangle: the workspace background can never be painted on.
    canvas.clipRect(docRect);

    // Document background color. Layers themselves stay transparent.
    canvas.drawRect(docRect, Paint()
      ..color = Color(project.settings.backgroundColor));

    for (final layer in project.layers) {
      if (!layer.visible) continue;
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

    // Selection overlay
    if (hasActiveSelection && selectionMaskImage != null) {
      canvas.drawImage(selectionMaskImage!, Offset.zero, Paint());
    }

    // Marching ants along the actual selection contour (PS style).
    final ws = 1.0 / viewScale;
    if (hasActiveSelection && selectionOutlinePath != null) {
      canvas.drawPath(selectionOutlinePath!, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * ws);
      _drawDashedPath(canvas, selectionOutlinePath!, Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = ws,
        dashLen: 5 * ws, gapLen: 4 * ws);
    }

    // Live lasso feedback while dragging.
    if (liveLassoPoints.length >= 2) {
      final live = ui.Path()
        ..moveTo(liveLassoPoints.first.dx, liveLassoPoints.first.dy);
      for (final p in liveLassoPoints.skip(1)) {
        live.lineTo(p.dx, p.dy);
      }
      live.close();
      canvas.drawPath(live, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * ws);
      _drawDashedPath(canvas, live, Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75 * ws,
        dashLen: 5 * ws, gapLen: 4 * ws);
    }

    // Edit mode: draw transformed clip image
    final clipBounds = selectionClipBounds;
    if (selectionPhase == SelectionPhase.editing && selectionClipImage != null && clipBounds.width > 0 && clipBounds.height > 0) {
      // After a cut, erase the original region so the floating clip
      // visibly moves away from empty space.
      if (selectionCutout && selectionSolidImage != null) {
        canvas.drawImage(selectionSolidImage!, Offset.zero, Paint()
          ..blendMode = BlendMode.dstOut);
      }
      canvas.save();
      final b = selectionClipBounds;
      canvas.translate(b.center.dx + editTranslate.dx, b.center.dy + editTranslate.dy);
      canvas.rotate(editRotate);
      canvas.scale(editScaleX, editScaleY);
      canvas.translate(-b.center.dx, -b.center.dy);
      canvas.drawImage(selectionClipImage!, b.topLeft, Paint());
      canvas.restore();

      // Draw transform handles
      if (transformMode == TransformMode.scale) {
        _drawScaleHandles(canvas);
      } else {
        _drawWarpHandles(canvas);
      }
    }

    canvas.restore();
  }

  void _drawScaleHandles(Canvas canvas) {
    if (selectionClipBounds.width <= 0 || selectionClipBounds.height <= 0) return;
    final b = selectionClipBounds;
    final cx = b.center.dx + editTranslate.dx;
    final cy = b.center.dy + editTranslate.dy;
    final hw = b.width / 2 * editScaleX;
    final hh = b.height / 2 * editScaleY;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2);
    final paint = Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawRect(rect, paint);
    final corners = [
      rect.topLeft, rect.topCenter, rect.topRight,
      rect.centerLeft, rect.centerRight,
      rect.bottomLeft, rect.bottomCenter, rect.bottomRight,
    ];
    for (final p in corners) {
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 5, Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  void _drawWarpHandles(Canvas canvas) {
    if (selectionClipBounds.width <= 0 || selectionClipBounds.height <= 0) return;
    final b = selectionClipBounds;
    final cx = b.center.dx + editTranslate.dx;
    final cy = b.center.dy + editTranslate.dy;
    final hw = b.width / 2 * editScaleX;
    final hh = b.height / 2 * editScaleY;
    final left = cx - hw, top = cy - hh, right = cx + hw, bottom = cy + hh;
    final paint = Paint()..color = Colors.teal..style = PaintingStyle.stroke..strokeWidth = 1;
    final lines = <Offset>[];
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final x = left + c * (right - left) / 2;
        final y = top + r * (bottom - top) / 2;
        lines.add(Offset(x, y));
      }
    }
    // Draw grid lines
    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 2; c++) {
        canvas.drawLine(lines[r * 3 + c], lines[r * 3 + c + 1], paint);
      }
    }
    for (int c = 0; c < 3; c++) {
      for (int r = 0; r < 2; r++) {
        canvas.drawLine(lines[r * 3 + c], lines[(r + 1) * 3 + c], paint);
      }
    }
    for (final p in lines) {
      canvas.drawCircle(p, 5, Paint()..color = Colors.teal);
      canvas.drawCircle(p, 5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
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

  void _drawDashedPath(Canvas canvas, ui.Path path, Paint paint,
      {double dashLen = 6, double gapLen = 4}) {
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool dash = true;
      while (dist < metric.length) {
        final end = (dist + (dash ? dashLen : gapLen)).clamp(0.0, metric.length);
        if (dash) {
          canvas.drawPath(metric.extractPath(dist, end), paint);
        }
        dist = end;
        dash = !dash;
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) => true;
}
