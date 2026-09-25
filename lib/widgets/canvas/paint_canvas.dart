import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/project.dart';
import '../../models/layer.dart';
import '../../models/drawable.dart';
import '../../models/selection_data.dart';
import '../../providers/tool_provider.dart';
import '../../providers/canvas_provider.dart';
import '../../providers/project_provider.dart';
import '../../providers/app_settings.dart';
import '../../utils/logger.dart';
import '../dialogs/text_input_dialog.dart';

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
  DateTime? _downTime;
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

  // Liquify state: the layer content is NEVER cleared — a liquify overlay
  // drawable renders the warped raster on top of the intact content, so the
  // canvas can never go blank (undo / save / reload all keep the original).
  // The base image is a raster of the active layer taken at pen-down; each
  // drag segment re-warps the previous result so content actually smears
  // with the pointer.
  ui.Image? _liquifyBase;
  ui.Image? _liquifyResult;
  Offset? _liquifyLast;
  double _liquifyRadius = 24;
  bool _liquifyWarped = false;
  Offset? _liquifyPendingMove;
  bool _liquifyCommitting = false;
  bool _liquifyWarpBusy = false;

  // Smudge state: an evolving raster of the active layer. Every move step
  // warps the previous raster (pulling content from behind the pointer),
  // so paint picked up in one area is carried into the next — colours from
  // different places genuinely smear into each other, like wet paint.
  ui.Image? _smudgeState;
  bool _smudgeBusy = false;
  bool _smudgeCommitting = false;
  Offset? _smudgeLast;
  Offset? _smudgePendingMove;
  double _smudgeRadius = 12;

  // Perspective-guide dragging (with the move tool).
  int? _tabDragIndex;

  // Curve tool: dragging from a freshly placed anchor pulls its bézier
  // out-handle until pointer-up.
  bool _curveDraggingHandle = false;

  // Curve tool: desktop-hover preview of a mid-segment insertion point.
  Offset? _curveHoverInsert;

  // Move-tool editing of the selected drawable:
  // 0 = none, 1 = translate, 2..5 = corner scale (text), 6 = rotate (text).
  int _selDragMode = 0;
  Offset _selDragLast = Offset.zero;
  Offset _selPivot = Offset.zero;
  double _selStartAngle = 0;
  double _selStartRotation = 0;
  double _selStartDist = 1;
  double _selStartFontSize = 0;
  Offset _selStartAnchor = Offset.zero;
  bool _selSnapshotTaken = false;

  // Symmetry: while enabled, brush/eraser strokes commit a mirrored twin
  // drawable on the same layer, kept in sync during the drag.
  Drawable? _mirrorTwin;
  double _mirrorCx = 0;

  // ─── Layer raster cache ────────────────────────────────────────
  // Finished layer content is flattened to a GPU texture once; repaints
  // blit the texture instead of re-rendering every drawable vectorially
  // each frame. Entries are keyed by layer id and validated against the
  // drawable content version + image version, so any mutation invalidates
  // exactly that layer. The layer being actively drawn is skipped while
  // its stroke is in flight (its drawable updates every frame).
  final Map<String, _LayerRasterEntry> _layerRasters = {};
  final Set<String> _rasterBusy = {};

  int _layerSignature(Layer layer) => layerContentVersion(layer);

  void _updateLayerRasters() {
    final project = widget.project;
    // Drop entries for deleted layers.
    _layerRasters.removeWhere((id, _) => !project.layers.any((l) => l.id == id));
    for (final layer in project.layers) {
      if (!layer.visible) continue;
      // Small layers render fast vectorially — don't pay texture memory.
      if (layer.drawables.length < 10 && layer.image == null) continue;
      final version = _layerSignature(layer);
      final entry = _layerRasters[layer.id];
      if (entry != null && entry.version == version) continue;
      // Never cache a layer whose stroke is mid-flight: its drawable
      // changes every frame, the raster would be stale on arrival.
      if (_currentDrawable != null &&
          layer.drawables.contains(_currentDrawable)) {
        continue;
      }
      if (_rasterBusy.contains(layer.id)) continue;
      _rasterBusy.add(layer.id);
      _rasterizeLayerCached(layer, version);
    }
  }

  Future<void> _rasterizeLayerCached(Layer layer, int version) async {
    try {
      final w = widget.project.settings.width.toInt();
      final h = widget.project.settings.height.toInt();
      if (w <= 0 || h <= 0) return;
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      if (layer.image != null) {
        final img = layer.image!;
        c.save();
        c.translate(layer.imageOffset.dx + img.width / 2,
            layer.imageOffset.dy + img.height / 2);
        c.rotate(layer.imageRotation);
        final flipX = layer.imageFlipH ? -1.0 : 1.0;
        final flipY = layer.imageFlipV ? -1.0 : 1.0;
        c.scale(layer.imageScale * flipX, layer.imageScale * flipY);
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(),
              img.height.toDouble()),
          Paint(),
        );
        c.restore();
      }
      for (final d in layer.drawables) {
        d.draw(c, Paint());
      }
      final raster = await recorder.endRecording().toImage(w, h);
      final old = _layerRasters[layer.id];
      if (old != null && !identical(old.image, raster)) old.image.dispose();
      _layerRasters[layer.id] = _LayerRasterEntry(raster, version);
      if (mounted) setState(() {});
    } catch (_) {
      // Rasterization is best-effort; the painter falls back to vectorial
      // rendering for this layer until the next attempt.
    } finally {
      _rasterBusy.remove(layer.id);
    }
  }

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
    // Screen-constant grab radius: handles must stay grabbable at any zoom.
    final viewScale = context.read<CanvasProvider>().scale;
    if (pp.transformMode == TransformMode.scale) {
      final handles = _getScaleHandles();
      final r = 12.0 / viewScale;
      for (int i = 0; i < handles.length; i++) {
        if ((canvasPos - handles[i]).distance < r) {
          _warpDragIndex = i;
          _selectStart = canvasPos;
          return true;
        }
      }
    } else {
      final grid = _getWarpGrid();
      final r = 14.0 / viewScale;
      for (int i = 0; i < grid.length; i++) {
        if ((canvasPos - grid[i]).distance < r) {
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
      final grid = _getWarpGrid();
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

  /// Scale-mode control points at their CURRENT transformed positions
  /// (edit translate + accumulated scale) — identical to what the painter
  /// draws, so the handles are always grabbable where they appear.
  List<Offset> _getScaleHandles() {
    final pp = context.read<ProjectProvider>();
    final b = pp.selectionClipBounds;
    final cx = b.center.dx + pp.editTranslate.dx;
    final cy = b.center.dy + pp.editTranslate.dy;
    final hw = b.width / 2 * pp.editScaleX;
    final hh = b.height / 2 * pp.editScaleY;
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: hw * 2, height: hh * 2);
    return [
      rect.topLeft, rect.topCenter, rect.topRight,
      rect.centerLeft, rect.centerRight,
      rect.bottomLeft, rect.bottomCenter, rect.bottomRight,
    ];
  }

  /// Warp-grid points at their CURRENT transformed positions (edit
  /// translate + scale), matching the painter's grid rendering.
  List<Offset> _getWarpGrid() {
    final pp = context.read<ProjectProvider>();
    final b = pp.selectionClipBounds;
    final cx = b.center.dx + pp.editTranslate.dx;
    final cy = b.center.dy + pp.editTranslate.dy;
    final hw = b.width / 2 * pp.editScaleX;
    final hh = b.height / 2 * pp.editScaleY;
    final pts = <Offset>[];
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        pts.add(Offset(cx - hw + col * hw, cy - hh + row * hh));
      }
    }
    return pts;
  }

  void _captureSmudgeSource() {
    final pp = context.read<ProjectProvider>();
    if (_currentDrawable == null || !_currentDrawable!.isSmudge) return;
    final curIdx = widget.project.currentLayerIndex
        .clamp(0, widget.project.layers.length - 1);
    final layer = widget.project.layers[curIdx];
    final pw = widget.project.settings.width.toInt();
    final ph = widget.project.settings.height.toInt();
    if (pw <= 0 || ph <= 0) return;
    final recorder = ui.PictureRecorder();
    final offscreenCanvas = Canvas(recorder, Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()));
    for (final d in layer.drawables) {
      if (d.id == _currentDrawable!.id) continue;
      d.draw(offscreenCanvas, Paint());
    }
    final img = layer.image;
    if (img != null) {
      offscreenCanvas.save();
      offscreenCanvas.translate(
          layer.imageOffset.dx + img.width / 2, layer.imageOffset.dy + img.height / 2);
      offscreenCanvas.rotate(layer.imageRotation);
      final flipX = layer.imageFlipH ? -1.0 : 1.0;
      final flipY = layer.imageFlipV ? -1.0 : 1.0;
      offscreenCanvas.scale(layer.imageScale * flipX, layer.imageScale * flipY);
      offscreenCanvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
        Paint(),
      );
      offscreenCanvas.restore();
    }
    final picture = recorder.endRecording();
    final strokeId = _currentDrawable!.id;
    picture.toImage(pw, ph).then((captured) {
      final d = _currentDrawable;
      if (d != null && d.id == strokeId && d.isSmudge && !_smudgeBusy) {
        d.smudgeSource = captured;
        d.smudgeW = pw;
        d.smudgeH = ph;
        _smudgeState = captured;
        pp.updateDrawableSilent(d.id, d);
        if (mounted) setState(() {});
      } else {
        captured.dispose();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Smudge: wet-paint smear.
  //
  // Each pointer move warps the evolving raster: rings behind the pointer
  // are pulled forward, so the brush carries paint along the stroke. The
  // smear accumulates because every step re-warps the previous result.
  // ---------------------------------------------------------------------------

  void _onSmudgeMove(Offset canvasPos, ProjectProvider pp) {
    final d = _currentDrawable;
    if (d == null || _smudgeCommitting) return;
    if (_smudgeBusy || _smudgeState == null) {
      // Raster not ready yet or a warp is in flight; catch up later.
      _smudgePendingMove = canvasPos;
      return;
    }
    final last = _smudgeLast ?? canvasPos;
    final delta = canvasPos - last;
    if (delta.distance < 0.5) return;
    _smudgeLast = canvasPos;
    d.points.add(canvasPos);
    if (d.widths != null) d.widths!.add(d.widths!.last);
    d.contentVersion++;
    _smudgeWarp(canvasPos, delta, pp);
  }

  Future<void> _smudgeWarp(Offset center, Offset delta, ProjectProvider pp) async {
    final src = _smudgeState;
    if (src == null) return;
    final w = widget.project.settings.width.toInt();
    final h = widget.project.settings.height.toInt();
    final radius = _smudgeRadius;
    // A finger can only carry the paint it touches: clamp the pull to
    // ~1.2 brush radii per event so fast flicks don't tear the image.
    final pullDist = delta.distance;
    final pull = pullDist > radius * 1.2
        ? delta * (radius * 1.2 / pullDist)
        : delta;
    final steps = (pull.distance / (radius * 0.45)).ceil().clamp(1, 3);
    _smudgeBusy = true;
    ui.Image current = src;
    try {
      for (int s = 1; s <= steps; s++) {
        final t = s / steps;
        final target = Offset.lerp(center - pull, center, t)!;
        final stepDelta = pull / steps.toDouble();
        current = await _liquifyWarpOnce(current, target, stepDelta, radius, w, h);
      }
      final d = _currentDrawable;
      if (!mounted || d == null) {
        if (!identical(current, src)) current.dispose();
        return;
      }
      _smudgeState = current;
      d.smudgeSource = current;
      d.smudgeW = w;
      d.smudgeH = h;
      d.contentVersion++;
      pp.updateDrawableSilent(d.id, d);
      if (mounted) setState(() {});
      if (!identical(src, current)) src.dispose();
    } catch (_) {
      if (!identical(current, src)) current.dispose();
    } finally {
      _smudgeBusy = false;
    }
    if (!mounted) return;
    final pending = _smudgePendingMove;
    if (pending != null && _currentDrawable != null && _smudgeState != null) {
      _smudgePendingMove = null;
      final last = _smudgeLast ?? pending;
      final delta2 = pending - last;
      if (delta2.distance >= 0.5) {
        _smudgeLast = pending;
        _currentDrawable!.points.add(pending);
        await _smudgeWarp(pending, delta2, pp);
      }
    }
  }

  Future<void> _finishSmudge(ProjectProvider pp) async {
    final d = _currentDrawable;
    _currentDrawable = null;
    // Snapshot the committed state BEFORE waiting: a new stroke may begin
    // (and reset _smudgeState) while we settle the in-flight warp.
    final committed = d != null && d.points.length > 1 && _smudgeState != null;
    _smudgeCommitting = true;
    // Wait for an in-flight warp to settle.
    var guard = 0;
    while (_smudgeBusy && guard < 250) {
      await Future.delayed(const Duration(milliseconds: 4));
      guard++;
    }
    if (d != null && !committed) {
      // Tap without movement: drop the overlay (identical to the layer).
      final curIdx = widget.project.currentLayerIndex
          .clamp(0, widget.project.layers.length - 1);
      final layer = widget.project.layers[curIdx];
      layer.drawables.removeWhere((x) => x.id == d.id);
      d.smudgeSource?.dispose();
    }
    _smudgeState = null;
    _smudgeLast = null;
    _smudgePendingMove = null;
    _smudgeBusy = false;
    _smudgeCommitting = false;
    pp.refresh();
  }

  void _cancelSmudge(ProjectProvider pp) {
    final d = _currentDrawable;
    if (d == null) return;
    _currentDrawable = null;
    final curIdx = widget.project.currentLayerIndex
        .clamp(0, widget.project.layers.length - 1);
    final layer = widget.project.layers[curIdx];
    layer.drawables.removeWhere((x) => x.id == d.id);
    d.smudgeSource?.dispose();
    _smudgeState = null;
    _smudgeLast = null;
    _smudgePendingMove = null;
    _smudgeBusy = false;
    pp.refresh();
  }

  bool _isOnCanvas(Offset canvasPos) {
    return canvasPos.dx >= 0 &&
        canvasPos.dy >= 0 &&
        canvasPos.dx <= widget.project.settings.width &&
        canvasPos.dy <= widget.project.settings.height;
  }

  // ---------------------------------------------------------------------------
  // Liquify: real pixel dragging.
  //
  // The active layer is rasterized at pen-down. Each drag segment stamps a
  // displacement warp onto that raster: concentric rings sample the image
  // progressively further behind the pointer, so content near the cursor is
  // pulled along the drag direction with a smooth radial falloff — the
  // classic "forward warp" behaviour instead of painted dots.
  // ---------------------------------------------------------------------------

  void _onLiquifyMove(Offset canvasPos, ProjectProvider pp, ToolProvider tp) {
    final d = _currentDrawable;
    if (d == null || _liquifyCommitting) return;
    if (_liquifyBase == null || _liquifyWarpBusy) {
      // Base raster not ready yet (capture is async) or a warp render is
      // still in flight; remember the newest position so the next warp
      // catches up with the pointer.
      _liquifyPendingMove = canvasPos;
      return;
    }
    final last = _liquifyLast ?? canvasPos;
    final delta = canvasPos - last;
    if (delta.distance < 0.5) return;
    _liquifyLast = canvasPos;
    d.points.add(canvasPos);
    d.widths!.add(tp.brushSize);
    d.contentVersion++;
    _liquifyWarp(canvasPos, delta, pp);
  }

  /// Rasterizes the current layer content (drawables + image) as the warp
  /// base. The layer is left intact — the warp result becomes an overlay.
  Future<ui.Image> _rasterizeLiquifyBase() async {
    final w = widget.project.settings.width.toInt();
    final h = widget.project.settings.height.toInt();
    final curIdx = widget.project.currentLayerIndex
        .clamp(0, widget.project.layers.length - 1);
    final layer = widget.project.layers[curIdx];
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    for (final d in layer.drawables) {
      d.draw(c, Paint());
    }
    final img = layer.image;
    if (img != null) {
      c.save();
      c.translate(layer.imageOffset.dx + img.width / 2,
          layer.imageOffset.dy + img.height / 2);
      c.rotate(layer.imageRotation);
      final flipX = layer.imageFlipH ? -1.0 : 1.0;
      final flipY = layer.imageFlipV ? -1.0 : 1.0;
      c.scale(layer.imageScale * flipX, layer.imageScale * flipY);
      c.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
            -img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
        Paint(),
      );
      c.restore();
    }
    return recorder.endRecording().toImage(w, h);
  }

  Future<void> _liquifyWarp(Offset center, Offset delta, ProjectProvider pp) async {
    final src = _liquifyResult;
    if (src == null) return;
    final w = widget.project.settings.width.toInt();
    final h = widget.project.settings.height.toInt();
    final radius = _liquifyRadius;
    // Subdivide long jumps so ring seams stay sub-pixel.
    final dist = delta.distance;
    final steps = (dist / (radius * 0.5)).ceil().clamp(1, 4);
    ui.Image current = src;
    _liquifyWarpBusy = true;
    try {
      for (int s = 1; s <= steps; s++) {
        final t = s / steps;
        final target = Offset.lerp(center - delta, center, t)!;
        final stepDelta = delta / steps.toDouble();
        current = await _liquifyWarpOnce(current, target, stepDelta, radius, w, h);
      }
      final d = _currentDrawable;
      if (!mounted || d == null || _liquifyCommitting) {
        if (!identical(current, src)) current.dispose();
        return;
      }
      final old = _liquifyResult;
      _liquifyResult = current;
      _liquifyWarped = true;
      if (old != null && !identical(old, _liquifyBase)) old.dispose();
      d.liquifyImage = current;
      d.contentVersion++;
      pp.updateDrawableSilent(d.id, d);
      // The warp completes after the pointer event's repaint; refresh so
      // the smeared result shows immediately.
      if (mounted) setState(() {});
    } catch (_) {
      if (!identical(current, src)) current.dispose();
    } finally {
      _liquifyWarpBusy = false;
    }
    // Catch up with pointer movement that arrived while warping.
    if (!mounted || _liquifyCommitting) return;
    final pending = _liquifyPendingMove;
    if (pending != null && _currentDrawable != null && _liquifyBase != null) {
      _liquifyPendingMove = null;
      final last = _liquifyLast ?? pending;
      final delta2 = pending - last;
      if (delta2.distance >= 0.5) {
        _liquifyLast = pending;
        _currentDrawable!.points.add(pending);
        _currentDrawable!.widths!.add(_currentDrawable!.widths!.last);
        await _liquifyWarp(pending, delta2, pp);
      }
    }
  }

  /// One displacement stamp: the disc at [center] samples the source image
  /// progressively further behind the drag direction towards its middle,
  /// via concentric clip rings (innermost shifts the full [delta]).
  Future<ui.Image> _liquifyWarpOnce(
      ui.Image src, Offset center, Offset delta, double radius, int w, int h) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.drawImage(src, Offset.zero, Paint());
    const ringCount = 6;
    for (int i = 0; i < ringCount; i++) {
      final frac = 1.0 - i / ringCount; // 1.0 core → ~0 edge
      final outer = radius * (ringCount - i) / ringCount;
      final inner = radius * (ringCount - 1 - i) / ringCount;
      final path = ui.Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: center, radius: outer))
        ..addOval(Rect.fromCircle(center: center, radius: inner));
      c.save();
      c.clipPath(path);
      c.drawImage(src, delta * frac, Paint());
      c.restore();
    }
    return recorder.endRecording().toImage(w, h);
  }

  void _markUnsaved(ProjectProvider pp) {
    pp.markUnsavedChanges();
  }

  /// Removes the in-progress liquify overlay from the active layer.
  void _removeLiquifyOverlay(String drawableId, ProjectProvider pp) {
    final curIdx = widget.project.currentLayerIndex
        .clamp(0, widget.project.layers.length - 1);
    final layer = widget.project.layers[curIdx];
    layer.drawables.removeWhere((x) => x.id == drawableId);
    _markUnsaved(pp);
  }

  void _cancelLiquify(ProjectProvider pp) {
    final d = _currentDrawable;
    if (d == null) {
      // No active liquify drag.
      return;
    }
    _liquifyCommitting = true;
    _currentDrawable = null;
    _removeLiquifyOverlay(d.id, pp);
    _disposeLiquifyImages();
    _liquifyCommitting = false;
    pp.refresh();
  }

  void _disposeLiquifyImages() {
    final base = _liquifyBase;
    final result = _liquifyResult;
    if (base != null) base.dispose();
    if (result != null && !identical(result, base)) result.dispose();
    _liquifyBase = null;
    _liquifyResult = null;
  }

  Future<void> _finishLiquify(ProjectProvider pp) async {
    final d = _currentDrawable;
    _currentDrawable = null;
    _liquifyCommitting = true;
    try {
      // Wait for any in-flight warp render to settle.
      var guard = 0;
      while (_liquifyWarpBusy && guard < 250) {
        await Future.delayed(const Duration(milliseconds: 4));
        guard++;
      }
      final moved = d != null && d.points.length > 1;
      if (d != null && moved && _liquifyWarped) {
        // Commit: keep the liquify overlay in the layer. It renders the
        // warped raster on top of the intact original content, so undo and
        // save/reload always fall back to the original (never blank).
        // Warp image ownership moves to the drawable.
        final base = _liquifyBase;
        if (base != null) base.dispose();
        _liquifyBase = null;
        _liquifyResult = null;
        _markUnsaved(pp);
      } else {
        // Tap without movement (or the warp never ran): drop the overlay.
        if (d != null) _removeLiquifyOverlay(d.id, pp);
        _disposeLiquifyImages();
      }
    } finally {
      _liquifyBase = null;
      _liquifyResult = null;
      _liquifyLast = null;
      _liquifyPendingMove = null;
      _liquifyCommitting = false;
      _liquifyWarped = false;
      pp.refresh();
    }
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
    _downTime = DateTime.now();
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

    if (tp.currentTool == ToolType.eyedropper) {
      // Sample the flattened canvas colour under the pointer and make it
      // the primary colour (with a memory-chip entry), like PS's eyedropper.
      if (!_isOnCanvas(canvasPos)) return;
      await _pickColorAt(canvasPos, tp, pp);
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
      // PS-style paint bucket: flood fill the clicked region of the
      // flattened canvas and commit the filled area as a span-based
      // drawable on the active layer. Tolerance and edge grow/shrink are
      // user-configurable; the edge is feathered for anti-aliasing.
      if (!_isOnCanvas(canvasPos)) return;
      final layer = widget.project.layers[widget.project.currentLayerIndex
          .clamp(0, widget.project.layers.length - 1)];
      if (layer.locked) return;
      final as = context.read<AppSettings>();
      ui.Image? snap;
      try {
        snap = await pp.rasterizeCanvas();
        final byteData = await snap.toByteData();
        if (byteData == null) return;
        final bytes = byteData.buffer.asUint8List();
        final mask = SelectionMask(snap.width, snap.height);
        mask.floodFill(canvasPos, bytes, as.fillTolerance, true);
        if (as.fillGrowShrink != 0) mask.grow(as.fillGrowShrink);
        if (mask.isEmpty) return;
        final spans = mask.extractSpans(antiAlias: as.fillAntiAlias);
        pp.saveSnapshot();
        final drawable = Drawable(
          id: const Uuid().v4(),
          points: [canvasPos],
          color: tp.primaryColor,
          opacity: tp.brushOpacity,
          fillSpans: spans,
        );
        pp.addDrawable(drawable);
        pp.refresh();
      } catch (e) {
        _log.error('fill failed: $e');
      } finally {
        snap?.dispose();
      }
      return;
    }

    if (tp.currentTool == ToolType.pen) {
      // Vector pen: taps lay anchors, dragging extends a smooth quadratic
      // path (drawn by the drawable itself). No width dynamics — pen marks
      // stay crisp and constant-width, like a technical pen.
      if (!_isOnCanvas(canvasPos)) return;
      final layer = widget.project.layers[widget.project.currentLayerIndex
          .clamp(0, widget.project.layers.length - 1)];
      if (layer.locked) return;
      pp.saveSnapshot();
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        color: tp.primaryColor,
        strokeWidth: max(0.5, tp.brushSize * 0.35),
        opacity: tp.brushOpacity,
        isPen: true,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      return;
    }

    if (tp.currentTool == ToolType.text) {
      // PS-like text tool: pick the anchor, type the text, commit a text
      // drawable that can be moved with the move tool later.
      if (!_isOnCanvas(canvasPos)) return;
      final layer = widget.project.layers[widget.project.currentLayerIndex
          .clamp(0, widget.project.layers.length - 1)];
      if (layer.locked) return;
      await _promptTextAndPlace(canvasPos, pp, tp);
      return;
    }

    if (tp.currentTool == ToolType.gradient) {
      _gradientStart = canvasPos;
      return;
    }

    // Bézier curve tool: multi-click placement with ✓ confirm / ✗
    // remove-last-anchor buttons, mid-segment anchor insertion, and
    // drag-from-anchor to pull a bézier out-handle.
    if (tp.currentTool == ToolType.shape &&
        tp.currentShape == ShapeType.curve) {
      _handleCurveDown(canvasPos, pp, tp);
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
      // Selection transform box: its control points have top priority —
      // grabbing one edits the pixel selection, never the drawables.
      if (pp.selectionPhase == SelectionPhase.editing) {
        if (!_handleEditHitTest(canvasPos, pp)) {
          _onStartEditTransform(canvasPos);
        }
        return;
      }
      // Perspective guide: dragging a vanishing-point handle (move tool).
      final handle = _perspectiveHandleAt(canvasPos, tp);
      if (handle != null) {
        _tabDragIndex = handle;
        return;
      }
      final viewScale = context.read<CanvasProvider>().scale;
      // Selected text: transform handles (rotate knob / corners) win.
      final sel = pp.selectedDrawable;
      if (sel != null && _isTextDrawable(sel)) {
        final h = _textHandleAt(canvasPos, sel, viewScale);
        if (h != 0) {
          _beginTextHandleDrag(h, sel, canvasPos);
          return;
        }
      }
      final hit = _hitTest(canvasPos);
      if (hit != null) {
        pp.selectDrawable(hit);
        _beginTranslateDrag(canvasPos);
      } else {
        pp.clearSelection();
        _selDragMode = 0;
      }
      return;
    }
    // Brush/eraser/shape (rect/ellipse) start is deferred to _tryBeginDrag
  }

  // ─── Move-tool editing of the selected drawable ────────────────

  bool _isTextDrawable(Drawable d) =>
      d.textData != null && d.textData!.trim().isNotEmpty;

  /// 0 = none, 1 = rotate knob, 2..5 = corners TL/TR/BR/BL.
  int _textHandleAt(Offset p, Drawable d, double viewScale) {
    final r = 14.0 / viewScale;
    if ((p - textRotateHandlePosition(d, viewScale)).distance <= r) return 1;
    final corners = textCornerPositions(d);
    for (int i = 0; i < 4; i++) {
      if ((p - corners[i]).distance <= r) return i + 2;
    }
    return 0;
  }

  void _beginTranslateDrag(Offset p) {
    _selDragMode = 1;
    _selDragLast = p;
    _selSnapshotTaken = false;
  }

  void _beginTextHandleDrag(int handle, Drawable d, Offset p) {
    if (handle == 1) {
      // Rotate around the visual center.
      _selDragMode = 6;
      _selPivot = d.textCenter;
      _selStartRotation = d.rotation;
      _selStartAngle = atan2(p.dy - _selPivot.dy, p.dx - _selPivot.dx);
    } else {
      // Uniform scale from the center; anchor offset scales with it so
      // the text keeps its center while growing.
      _selDragMode = handle; // 2..5
      _selPivot = d.textCenter;
      _selStartAnchor = d.points.first;
      _selStartFontSize = d.fontSize;
      _selStartDist = max(1.0, (p - _selPivot).distance);
    }
    _selSnapshotTaken = false;
  }

  void _onSelectedDragMove(Offset p, ProjectProvider pp) {
    final sel = pp.selectedDrawable;
    if (sel == null || _selDragMode == 0) return;
    if (sel.isLiquify || sel.isSmudge) return;
    if (!_selSnapshotTaken) {
      pp.saveSnapshot();
      _selSnapshotTaken = true;
    }
    switch (_selDragMode) {
      case 1:
        final delta = p - _selDragLast;
        if (delta.distance < 0.01) return;
        _selDragLast = p;
        _translateDrawable(sel, delta);
        break;
      case 6:
        final angle = atan2(p.dy - _selPivot.dy, p.dx - _selPivot.dx);
        sel.rotation = _selStartRotation + (angle - _selStartAngle);
        break;
      case 2:
      case 3:
      case 4:
      case 5:
        final dist = (p - _selPivot).distance;
        final s = (dist / _selStartDist).clamp(0.05, 40.0);
        sel.fontSize = (_selStartFontSize * s).clamp(4.0, 1000.0);
        sel.points[0] = _selPivot + (_selStartAnchor - _selPivot) * s;
        break;
    }
    sel.contentVersion++;
    pp.updateDrawableSilent(sel.id, sel);
  }

  /// Translates every position-bearing field of [d] by [delta].
  void _translateDrawable(Drawable d, Offset delta) {
    for (int i = 0; i < d.points.length; i++) {
      d.points[i] = d.points[i] + delta;
    }
    if (d.curveHandles != null) {
      for (int i = 0; i < d.curveHandles!.length; i++) {
        final h = d.curveHandles![i];
        if (h != null) d.curveHandles![i] = h + delta;
      }
    }
    if (d.fillSpans != null) {
      final dx = delta.dx.round();
      final dy = delta.dy.round();
      if (dx != 0 || dy != 0) {
        final s = d.fillSpans!;
        for (int i = 0; i + 3 < s.length; i += 4) {
          s[i] += dy;
          s[i + 1] += dx;
          s[i + 2] += dx;
        }
      }
    }
  }

  // ─── Curve tool (multi-click + bézier) ─────────────────────────

  void _handleCurveDown(Offset canvasPos, ProjectProvider pp, ToolProvider tp) {
    final layer = widget.project.layers[widget.project.currentLayerIndex
        .clamp(0, widget.project.layers.length - 1)];
    if (layer.locked) return;

    final placing = _isPlacingShapePoints &&
        _currentDrawable != null &&
        _currentDrawable!.isShape &&
        _currentDrawable!.shapeType == ShapeType.curve;

    if (!placing) {
      // Start a new curve with a single anchor.
      pp.saveSnapshot();
      final drawable = Drawable(
        id: const Uuid().v4(),
        isShape: true,
        shapeType: ShapeType.curve,
        points: [canvasPos],
        curveHandles: [null],
        color: tp.primaryColor,
        strokeWidth: tp.brushSize,
        isFilled: false,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _isPlacingShapePoints = true;
      _dragConfirmed = true;
      _curveDraggingHandle = false;
      pp.refresh();
      return;
    }

    final d = _currentDrawable!;
    final viewScale = context.read<CanvasProvider>().scale;

    // ✓ confirm / ✗ remove-last buttons sit near the last anchor.
    final btn = _curveButtonHit(canvasPos, d, viewScale);
    if (btn == 1) {
      _commitCurve(pp);
      return;
    }
    if (btn == 2) {
      _removeLastCurveAnchor(pp);
      return;
    }

    // Clicking on an existing segment inserts an anchor at that spot.
    final seg = _curveSegmentHit(canvasPos, d, viewScale);
    if (seg != null) {
      pp.saveSnapshot();
      d.points.insert(seg.$1, seg.$2);
      d.curveHandles!.insert(seg.$1, null);
      d.contentVersion++;
      pp.updateDrawable(d.id, d);
      _curveDraggingHandle = false;
      pp.refresh();
      return;
    }

    // New anchor; dragging away from it pulls its bézier out-handle.
    pp.saveSnapshot();
    d.points.add(canvasPos);
    d.curveHandles!.add(null);
    d.contentVersion++;
    pp.updateDrawable(d.id, d);
    _curveDraggingHandle = true;
    pp.refresh();
  }

  void _commitCurve(ProjectProvider pp) {
    final d = _currentDrawable;
    if (d == null) return;
    _isPlacingShapePoints = false;
    _curveDraggingHandle = false;
    _curveHoverInsert = null;
    d.selected = true;
    pp.updateDrawable(d.id, d);
    _currentDrawable = null;
    pp.refresh();
  }

  void _removeLastCurveAnchor(ProjectProvider pp) {
    final d = _currentDrawable;
    if (d == null) return;
    pp.saveSnapshot();
    if (d.points.isNotEmpty) d.points.removeLast();
    if (d.curveHandles != null && d.curveHandles!.isNotEmpty) {
      d.curveHandles!.removeLast();
    }
    d.contentVersion++;
    _curveHoverInsert = null;
    if (d.points.isEmpty) {
      // Nothing left to place: cancel the whole curve.
      pp.deleteDrawable(d.id);
      _currentDrawable = null;
      _isPlacingShapePoints = false;
      _curveDraggingHandle = false;
    } else {
      pp.updateDrawable(d.id, d);
    }
    pp.refresh();
  }

  /// 1 = confirm, 2 = remove last, 0 = none.
  int _curveButtonHit(Offset p, Drawable d, double viewScale) {
    if (d.points.isEmpty) return 0;
    final g = curveButtonGeometry(d.points.last, viewScale);
    if ((p - g.confirm).distance <= g.radius * 1.6) return 1;
    if ((p - g.cancel).distance <= g.radius * 1.6) return 2;
    return 0;
  }

  /// Index + projected position of the segment under [p], if any.
  (int, Offset)? _curveSegmentHit(Offset p, Drawable d, double viewScale) {
    if (d.points.length < 2) return null;
    final tol = 12.0 / viewScale;
    for (int i = 1; i < d.points.length; i++) {
      final a = d.points[i - 1];
      final b = d.points[i];
      final seg = b - a;
      final len2 = seg.dx * seg.dx + seg.dy * seg.dy;
      if (len2 < 1) continue;
      double t = ((p - a).dx * seg.dx + (p - a).dy * seg.dy) / len2;
      t = t.clamp(0.0, 1.0);
      final proj = a + seg * t;
      if ((p - proj).distance <= tol) return (i, proj);
    }
    return null;
  }

  /// Creates (or clears) the symmetry mirror twin for a new stroke.
  void _syncMirrorTwin(ToolProvider tp, ProjectProvider pp, Offset canvasPos) {
    if (!tp.symmetryEnabled) {
      _mirrorTwin = null;
      return;
    }
    _mirrorCx = widget.project.settings.width / 2;
    final d = _currentDrawable!;
    final twin = d.copyWith(
      id: const Uuid().v4(),
      points: [Offset(_mirrorCx * 2 - canvasPos.dx, canvasPos.dy)],
      widths: d.widths == null ? null : List<double>.from(d.widths!),
      alphas: d.alphas == null ? null : List<double>.from(d.alphas!),
      selected: false,
    );
    twin.smudgeSource = null;
    twin.isSmudge = false;
    _mirrorTwin = twin;
    pp.addDrawable(twin);
  }

  /// Rebuilds the mirror twin from the primary stroke's current points.
  void _updateMirrorTwin(ProjectProvider pp) {
    final twin = _mirrorTwin;
    final main = _currentDrawable;
    if (twin == null || main == null) return;
    twin.points = [
      for (final p in main.points) Offset(_mirrorCx * 2 - p.dx, p.dy),
    ];
    twin.widths =
        main.widths == null ? null : List<double>.from(main.widths!);
    twin.alphas = main.alphas == null ? null : List<double>.from(main.alphas!);
    twin.contentVersion++;
    pp.updateDrawableSilent(twin.id, twin);
  }

  // ─── Perspective guide ─────────────────────────────────────────
  // Up to 3 vanishing points, each casting a fan of rays across the
  // document (PS-style perspective guides). Draggable with the move tool;
  // purely an overlay — never serialized or drawn into exports.

  static const int _perspectiveMaxPoints = 3;
  final List<Offset> _perspectivePoints = [];

  Offset _defaultPerspectivePoint(int i, double w, double h) => switch (i) {
        0 => Offset(w * 0.25, h * 0.25),
        1 => Offset(w * 0.75, h * 0.25),
        _ => Offset(w * 0.5, h * 0.75),
      };

  void _ensurePerspectivePoints() {
    final w = widget.project.settings.width.toDouble();
    final h = widget.project.settings.height.toDouble();
    while (_perspectivePoints.length < _perspectiveMaxPoints) {
      _perspectivePoints
          .add(_defaultPerspectivePoint(_perspectivePoints.length, w, h));
    }
  }

  List<Offset> _perspectiveViewPoints() {
    _ensurePerspectivePoints();
    return List<Offset>.unmodifiable(_perspectivePoints);
  }

  int? _perspectiveHandleAt(Offset canvasPos, ToolProvider tp) {
    if (!tp.perspectiveGuideEnabled) return null;
    _ensurePerspectivePoints();
    for (int i = 0; i < _perspectivePoints.length; i++) {
      if ((_perspectivePoints[i] - canvasPos).distance <= 24) {
        return i;
      }
    }
    return null;
  }

  void _movePerspectiveHandle(Offset canvasPos) {
    final i = _tabDragIndex;
    if (i == null || i >= _perspectivePoints.length) return;
    final w = widget.project.settings.width.toDouble();
    final h = widget.project.settings.height.toDouble();
    _perspectivePoints[i] = Offset(
      canvasPos.dx.clamp(-w * 0.5, w * 1.5),
      canvasPos.dy.clamp(-h * 0.5, h * 1.5),
    );
    setState(() {});
  }

  /// Text tool: ask for the string, then commit a text drawable anchored at
  /// the tapped canvas position.
  Future<void> _promptTextAndPlace(
      Offset canvasPos, ProjectProvider pp, ToolProvider tp) async {
    final result = await showTextInputDialog(
      context,
      initialFontFamily: tp.textFontFamily,
    );
    if (result == null || result.text.trim().isEmpty) return;
    if (!mounted) return;
    tp.setTextFontFamily(result.fontFamily);
    pp.saveSnapshot();
    final drawable = Drawable(
      id: const Uuid().v4(),
      points: [canvasPos],
      color: tp.primaryColor,
      opacity: 1.0,
      textData: result.text,
      fontSize: result.fontSize,
      fontFamily: result.fontFamily,
    );
    pp.addDrawable(drawable);
    pp.selectDrawable(drawable);
    pp.refresh();
  }

  /// Eyedropper: samples the flattened canvas at [canvasPos] (cached layer
  /// rasters when fresh, else a one-off vector rasterization) and promotes
  /// the colour to primary + memory chips.
  Future<void> _pickColorAt(
      Offset canvasPos, ToolProvider tp, ProjectProvider pp) async {
    final w = widget.project.settings.width.toInt();
    final h = widget.project.settings.height.toInt();
    final px = canvasPos.dx.floor().clamp(0, w - 1);
    final py = canvasPos.dy.floor().clamp(0, h - 1);
    ui.Image? flat;
    // Prefer composing from the cached rasters (already validated fresh).
    final needRaster = widget.project.layers.any((l) =>
        l.visible &&
        !_layerRasters.containsKey(l.id));    if (needRaster) {
      try {
        flat = await pp.rasterizeCanvas();
      } catch (_) {
        return;
      }
    }
    ui.Image? composite;
    if (flat == null) {
      // Compose the visible cached layers onto a scratch canvas.
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      final bg = Color(widget.project.settings.backgroundColor);
      if (bg.a > 0) {
        c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            Paint()..color = bg);
      }
      for (final layer in widget.project.layers) {
        if (!layer.visible) continue;
        final entry = _layerRasters[layer.id];
        if (entry != null && entry.version == layerContentVersion(layer)) {
          c.drawImage(
              entry.image,
              Offset.zero,
              Paint()..color = Colors.white.withValues(alpha: layer.opacity));
        } else {
          for (final d in layer.drawables) {
            d.draw(c, Paint());
          }
        }
      }
      composite = await recorder.endRecording().toImage(w, h);
    }
    final img = flat ?? composite;
    if (img == null) return;
    try {
      final bd = await img.toByteData();
      if (bd == null) return;
      final bytes = bd.buffer.asUint8List();
      final idx = (py * img.width + px) * 4;
      if (idx + 3 >= bytes.length) return;
      final color = Color.fromARGB(bytes[idx + 3], bytes[idx],
          bytes[idx + 1], bytes[idx + 2]);
      tp.setPrimaryColor(color);
      tp.addMemoryColor(color);
      _log.info('eyedropper picked #$color at ($px, $py)');
    } finally {
      flat?.dispose();
      composite?.dispose();
    }
  }

  void _tryBeginDrag(Offset pos, Size areaSize, {Offset? canvasStart}) {
    final tp = context.read<ToolProvider>();
    final pp = context.read<ProjectProvider>();
    final canvasPos = canvasStart ?? _toCanvas(pos, areaSize);

    if (tp.currentTool == ToolType.smudge) {
      if (!_isOnCanvas(canvasPos)) return;
      if (_smudgeCommitting) return; // previous smear still settling
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      // Seed velocity tracking from the pen-down event (not the drag-start
      // moment) so the very first width sample of a short, quick stroke
      // already carries the real speed of the gesture.
      _lastPointerTime = _downTime;
      _lastPointerPos = _downScreenPos;
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
      _smudgeState = null;
      _smudgeLast = canvasPos;
      _smudgePendingMove = null;
      _smudgeBusy = false;
      _smudgeRadius = max(6.0, tp.brushSize * 0.55);
      _captureSmudgeSource();
      return;
    }

    if (tp.currentTool == ToolType.willowLeaf) {
      if (!_isOnCanvas(canvasPos)) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      // Seed velocity tracking from the pen-down event (not the drag-start
      // moment) so the very first width sample of a short, quick stroke
      // already carries the real speed of the gesture.
      _lastPointerTime = _downTime;
      _lastPointerPos = _downScreenPos;
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
      if (_liquifyCommitting) return; // previous warp still baking
      final curIdx = widget.project.currentLayerIndex
          .clamp(0, widget.project.layers.length - 1);
      final layer = widget.project.layers[curIdx];
      if (layer.drawables.isEmpty && layer.image == null) return;
      pp.saveSnapshot();
      _stabilizerQueue.clear();
      // Seed velocity tracking from the pen-down event (not the drag-start
      // moment) so the very first width sample of a short, quick stroke
      // already carries the real speed of the gesture.
      _lastPointerTime = _downTime;
      _lastPointerPos = _downScreenPos;
      // The layer content stays untouched. A liquify overlay drawable is
      // added on top; while the drag runs it shows the warped raster (the
      // base content is identical, so it looks seamless).
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        color: Colors.transparent,
        strokeWidth: tp.brushSize,
        opacity: 1.0,
        brushType: tp.brushType,
        isLiquify: true,
      );
      _currentDrawable = drawable;
      layer.drawables.add(drawable);
      _liquifyRadius = max(6.0, tp.brushSize * 0.5);
      _liquifyLast = canvasPos;
      _liquifyPendingMove = null;
      _liquifyBase = null;
      _liquifyResult = null;
      _liquifyWarped = false;
      _liquifyWarpBusy = false;
      _dragConfirmed = true;
      _liquifyCommitting = false;
      pp.refresh();
      _rasterizeLiquifyBase().then((img) {
        if (_currentDrawable?.id == drawable.id && !_liquifyCommitting) {
          _liquifyBase = img;
          _liquifyResult = img;
        } else {
          img.dispose();
        }
      });
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
      // Seed velocity tracking from the pen-down event (not the drag-start
      // moment) so the very first width sample of a short, quick stroke
      // already carries the real speed of the gesture.
      _lastPointerTime = _downTime;
      _lastPointerPos = _downScreenPos;
      final as = context.read<AppSettings>();
      final drawable = Drawable(
        id: const Uuid().v4(),
        points: [canvasPos],
        widths: [tp.brushSize],
        // Ink starts at the configured floor so the very first dots of a
        // fast flick are already drier, then get retrofitted like widths.
        alphas: as.velocityInkEnabled && as.velocityWidthEnabled
            ? [as.velocityInkMinScale]
            : null,
        color: tp.currentTool == ToolType.eraser ? Colors.white : tp.primaryColor,
        strokeWidth: tp.brushSize,
        opacity: tp.brushOpacity,
        brushType: tp.brushType,
      );
      _currentDrawable = drawable;
      pp.addDrawable(drawable);
      _dragConfirmed = true;
      // Symmetry: create a mirrored twin drawable that is driven point by
      // point while the primary stroke advances.
      _syncMirrorTwin(tp, pp, canvasPos);
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

    // Move tool: selection editing > VP handles > drawable editing.
    if (tp.currentTool == ToolType.move) {
      if (pp.selectionPhase == SelectionPhase.editing) {
        _onEditMove(canvasPos, pp);
        return;
      }
      if (tp.perspectiveGuideEnabled && _tabDragIndex != null) {
        _movePerspectiveHandle(canvasPos);
        return;
      }
      _onSelectedDragMove(canvasPos, pp);
      return;
    }

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
        _currentDrawable!.contentVersion++;
        pp.updateDrawableSilent(_currentDrawable!.id, _currentDrawable!);
      } else {
        final drawable = Drawable(
          id: const Uuid().v4(),
          isShape: true,
          shapeType: ShapeType.rect,
          points: [_gradientStart!, canvasPos],
          color: tp.gradientStartColor,
          strokeWidth: tp.brushSize,
          opacity: tp.brushOpacity,
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
        _currentDrawable!.contentVersion++;
        pp.updateDrawableSilent(_currentDrawable!.id, _currentDrawable!);
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

    if (tp.currentTool == ToolType.pen && _currentDrawable != null) {
      // Extend the pen path with min-distance filtering; the drawable
      // renders anchors as a smoothed quadratic curve.
      final d = _currentDrawable!;
      final last = d.points.last;
      if ((canvasPos - last).distance < 2.0) return;
      d.points.add(canvasPos);
      d.contentVersion++;
      pp.updateDrawableSilent(d.id, d);
      return;
    }

    if (tp.currentTool == ToolType.shape &&
        tp.currentShape == ShapeType.curve &&
        _currentDrawable != null) {
      // Dragging away from the freshly placed anchor pulls its bézier
      // out-handle; dragging elsewhere does nothing.
      if (_curveDraggingHandle) {
        final d = _currentDrawable!;
        final anchor = d.points.last;
        final handle = canvasPos;
        // Minimum pull distance so a plain click stays a corner anchor.
        if ((handle - anchor).distance >
            6.0 / context.read<CanvasProvider>().scale) {
          while (d.curveHandles!.length < d.points.length) {
            d.curveHandles!.add(null);
          }
          d.curveHandles![d.points.length - 1] = handle;
          d.contentVersion++;
          pp.updateDrawableSilent(d.id, d);
        }
      }
      return;
    }

    if (tp.currentTool == ToolType.liquify) {
      // Liquify ignores the drag threshold: content must follow the pointer
      // immediately (its own warps are what make the drag visible).
      _onLiquifyMove(canvasPos, pp, tp);
      return;
    }

    if (tp.currentTool == ToolType.smudge) {
      // Smudge also bypasses the threshold once the drag begins: the smear
      // itself is the feedback, same as liquify.
      _onSmudgeMove(canvasPos, pp);
      return;
    }

    if (tp.currentTool == ToolType.brush ||
        tp.currentTool == ToolType.eraser ||
        tp.currentTool == ToolType.willowLeaf) {
      final as = context.read<AppSettings>();
      final now = DateTime.now();
      double widthFromVelocity = tp.brushSize;
      double widthFromPressure = tp.brushSize;

      // Velocity-based width: fast strokes get thinner, slow strokes thicker.
      if (as.velocityWidthEnabled && _lastPointerTime != null && _lastPointerPos != null) {
        final dt = now.difference(_lastPointerTime!).inMicroseconds / 1e6;
        final dist = (pos - _lastPointerPos!).distance;
        if (dt > 0.002) {
          const double minVel = 150; // at or below this speed → thickest
          const double maxVel = 2200; // at or above this speed → thinnest
          final velocity = (dist / dt).clamp(minVel, maxVel);
          var ratio = (velocity - minVel) / (maxVel - minVel);
          // Lower exponent = reacts earlier: strokes thin out soon after
          // picking up speed (higher sensitivity).
          ratio = pow(ratio, 0.32).toDouble();
          final range = as.velocityMaxScale - as.velocityMinScale;
          final scale = as.velocityMaxScale - ratio * range;
          widthFromVelocity = tp.brushSize * scale;
        }
      }

      // Velocity-based ink amount (brush feel): fast strokes lay down less
      // ink, slow strokes pool it, like a real brush leaving the paper.
      // Computed after the width EMA below runs? No — computed from the
      // raw eased width here, then refined once the smoothed width exists.
      double inkFromVelocity = 1.0;

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

      // Velocity-based ink amount (brush feel): fast strokes lay down less
      // ink, slow strokes pool it, like a real brush leaving the paper.
      // Reuses the smoothed width so width and ink always stay in sync:
      // normalize the width scale back to 0..1, then map onto the
      // ink-floor..full-ink range.
      if (as.velocityInkEnabled &&
          as.velocityWidthEnabled &&
          currentWidth < tp.brushSize) {
        final range = (as.velocityMaxScale - as.velocityMinScale).clamp(0.01, 1.0);
        final nw = ((currentWidth / tp.brushSize) - as.velocityMinScale) / range;
        inkFromVelocity = as.velocityInkMinScale +
            (1.0 - as.velocityInkMinScale) * nw.clamp(0.0, 1.0);
      }

      // The stroke's first point was stamped before any velocity was known;
      // retrofit it with the first computed width so a short, quick flick
      // thins along its whole length instead of keeping a full-width head.
      final firstWidths = _currentDrawable!.widths;
      if (firstWidths != null && firstWidths.length == 1) {
        firstWidths[0] = currentWidth;
      }

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
    final usesInk = (tp.currentTool == ToolType.brush ||
            tp.currentTool == ToolType.eraser) &&
        as.velocityInkEnabled;
    if (usesInk) _currentDrawable!.alphas ??= [];
    // The stroke's first point was stamped before any velocity was known;
    // retrofit it with the first computed ink just like the width above.
    final firstAlphas = _currentDrawable!.alphas;
    if (firstAlphas != null && firstAlphas.length == 1) {
      firstAlphas[0] = inkFromVelocity;
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
          if (usesInk) _currentDrawable!.alphas!.add(inkFromVelocity);
        }
      }
    }
    _currentDrawable!.points.add(drawPos);
    _currentDrawable!.widths!.add(currentWidth);
    if (usesInk) _currentDrawable!.alphas!.add(inkFromVelocity);
    _currentDrawable!.contentVersion++;
    pp.updateDrawableSilent(_currentDrawable!.id, _currentDrawable!);
    if (_mirrorTwin != null) _updateMirrorTwin(pp);
    } else if (tp.currentTool == ToolType.shape) {
      if (tp.currentShape == ShapeType.curve) {
        // Curve: accumulate all points during drag
        _currentDrawable!.points.add(canvasPos);
        _currentDrawable!.contentVersion++;
        pp.updateDrawableSilent(_currentDrawable!.id, _currentDrawable!);
      } else {
        final snapped = _snapShapeEnd(tp, canvasPos);
        _currentDrawable!.points = [_currentDrawable!.points.first, snapped];
        _currentDrawable!.contentVersion++;
        pp.updateDrawableSilent(_currentDrawable!.id, _currentDrawable!);
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

    // Liquify: bake (or cancel) the warp.
    if (tp.currentTool == ToolType.liquify) {
      _finishLiquify(pp);
      return;
    }

    // Smudge: finalize the evolving smear overlay.
    if (tp.currentTool == ToolType.smudge && _currentDrawable != null) {
      _finishSmudge(pp);
      return;
    }

    // Curve: stay in placement mode (anchors accumulate until ✓/✗);
    // just end any in-progress bézier handle drag.
    if (tp.currentTool == ToolType.shape &&
        tp.currentShape == ShapeType.curve &&
        _isPlacingShapePoints &&
        _currentDrawable != null) {
      _curveDraggingHandle = false;
      pp.refresh();
      return;
    }

    // Line / polygon placement: a tap adds its point and keeps waiting for
    // more (or auto-finalizes); pointer-up must not clear the drawable.
    if (tp.currentTool == ToolType.shape &&
        (tp.currentShape == ShapeType.line ||
            tp.currentShape == ShapeType.polygon) &&
        _isPlacingShapePoints &&
        _currentDrawable != null) {
      pp.refresh();
      return;
    }

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
      if (_mirrorTwin != null) {
        pp.deleteDrawable(_mirrorTwin!.id);
      }
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
    _mirrorTwin = null;
    _tabDragIndex = null;
  }

  void _cancelMultiClickShape() {
    if (_isPlacingShapePoints && _currentDrawable != null) {
      final pp = context.read<ProjectProvider>();
      pp.deleteDrawable(_currentDrawable!.id);
      _currentDrawable = null;
    }
    _isPlacingShapePoints = false;
    _curveDraggingHandle = false;
    _curveHoverInsert = null;
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
    // Fire-and-forget: refresh per-layer raster caches for any layer whose
    // content changed since its last rasterization.
    _updateLayerRasters();
    final isMoveTool = tp.currentTool == ToolType.move;
    final hasSelection = pp.selectedDrawable != null;
    final isDrawingTool = tp.currentTool == ToolType.brush ||
        tp.currentTool == ToolType.eraser ||
        tp.currentTool == ToolType.pen ||
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
          onPointerHover: (event) {
            _currentPressure = event.pressure;
            // Curve tool: remember a mid-segment insertion candidate so the
            // painter can highlight it (desktop hover; touch gets it on tap).
            if (tp.currentTool == ToolType.shape &&
                tp.currentShape == ShapeType.curve &&
                _isPlacingShapePoints &&
                _currentDrawable != null) {
              final hit = _curveSegmentHit(
                  _toCanvas(event.position, areaSize),
                  _currentDrawable!,
                  context.read<CanvasProvider>().scale);
              final changed = hit?.$2 != _curveHoverInsert;
              _curveHoverInsert = hit?.$2;
              if (changed) setState(() {});
            }
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
                _tabDragIndex = null;
                // A pinch (likely smart-undo) must not race an in-progress
                // multi-click shape; cancel the placement cleanly.
                if (_isPlacingShapePoints) {
                  _cancelMultiClickShape();
                }
                if (tp.currentTool == ToolType.liquify) {
                  _cancelLiquify(pp);
                } else if (tp.currentTool == ToolType.smudge) {
                  _cancelSmudge(pp);
                }
                _handleMultiTouch(details.pointerCount);
                return;
              }
              // Ignore single-finger immediately after multi-touch cooldown
              if (_isScaling) return;
              if (_scaleEndTime != null &&
                  DateTime.now().difference(_scaleEndTime!) < _scaleCooldown) {
                return;
              }
              // Every tool gets pen-down. The move tool hit-tests selection
              // handles on down; panning still applies in the update phase
              // whenever nothing is being dragged.
              _onPointerDown(details.localFocalPoint, areaSize);
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
                if (isMoveTool && pp.selectionPhase == SelectionPhase.editing) {
                  // Dragging the selection transform box / its handles.
                  _onPointerMove(details.localFocalPoint, areaSize);
                  setState(() {});
                } else if (isMoveTool && !hasSelection) {
                  if (tp.perspectiveGuideEnabled && _tabDragIndex != null) {
                    // Dragging a vanishing-point handle, not panning.
                    _onPointerMove(details.localFocalPoint, areaSize);
                  } else {
                    final delta = details.focalPointDelta;
                    if (delta.distance > 2.0) {
                      cp.panBy(delta);
                    }
                  }
                } else if (isMoveTool && hasSelection) {
                  // Editing the selected drawable (translate/scale/rotate).
                  _onPointerMove(details.localFocalPoint, areaSize);
                  setState(() {});
                } else if (isDrawingTool) {
                  _onPointerMove(details.localFocalPoint, areaSize);
                  // In-stroke updates bump the content version silently
                  // (updateDrawableSilent); repaint here without rebuilding
                  // the whole provider tree every pointer event.
                  setState(() {});
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
                          layerRasters: _layerRasters,
                          mirrorEnabled: tp.symmetryEnabled,
                          perspectiveEnabled: tp.perspectiveGuideEnabled,
                          perspectivePoints: tp.perspectiveGuideEnabled
                              ? _perspectiveViewPoints()
                              : const [],
                          curveHoverInsert: _curveHoverInsert,
                          curvePlacing: _isPlacingShapePoints,
                          moveToolActive: isMoveTool,
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

  @override
  void dispose() {
    for (final entry in _layerRasters.values) {
      entry.image.dispose();
    }
    _layerRasters.clear();
    super.dispose();
  }
}

/// Cached full-canvas raster of one layer's drawables (+ baked image).
class _LayerRasterEntry {
  final ui.Image image;
  final int version;
  _LayerRasterEntry(this.image, this.version);
}

/// Stable signature of a layer's rendered content: any drawable edit or
/// image-transform change bumps it, so the raster cache knows to rebuild.
int layerContentVersion(Layer layer) => Object.hashAll([
      layer.drawables.length,
      for (final d in layer.drawables) d.contentVersion,
      identityHashCode(layer.image),
      layer.imageVersion,
    ]);

/// Screen-space geometry of the curve tool's ✓/✗ buttons, anchored to the
/// last placed anchor. Shared by the gesture code and the painter.
({Offset confirm, Offset cancel, double radius}) curveButtonGeometry(
    Offset lastAnchor, double viewScale) {
  final r = 11.0 / viewScale;
  final gap = 16.0 / viewScale;
  return (
    confirm: lastAnchor + Offset(gap, -gap),
    cancel: lastAnchor + Offset(-gap, gap),
    radius: r,
  );
}

/// Rotates [v] by [angle] radians (clockwise in Flutter's y-down space).
Offset _rotateVec2(Offset v, double angle) => angle == 0
    ? v
    : Offset(
        v.dx * cos(angle) - v.dy * sin(angle),
        v.dx * sin(angle) + v.dy * cos(angle),
      );

/// The four rotated corners of a text drawable's rendered box (TL, TR,
/// BR, BL). Shared by gesture hit-testing and the painter.
List<Offset> textCornerPositions(Drawable d) {
  final sz = d.textSize;
  final a = d.points.first;
  final r = d.rotation;
  return [
    a + _rotateVec2(Offset.zero, r),
    a + _rotateVec2(Offset(sz.width, 0), r),
    a + _rotateVec2(Offset(sz.width, sz.height), r),
    a + _rotateVec2(Offset(0, sz.height), r),
  ];
}

/// Position of the text rotation knob above the top edge.
Offset textRotateHandlePosition(Drawable d, double viewScale) {
  final sz = d.textSize;
  final a = d.points.first;
  final stem = 26.0 / viewScale;
  return a + _rotateVec2(Offset(sz.width / 2, -stem), d.rotation);
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
  final Map<String, _LayerRasterEntry> layerRasters;
  final bool mirrorEnabled;
  final bool perspectiveEnabled;
  final List<Offset> perspectivePoints;
  final bool curvePlacing;
  final Offset? curveHoverInsert;
  final bool moveToolActive;
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
    this.layerRasters = const {},
    this.mirrorEnabled = false,
    this.perspectiveEnabled = false,
    this.perspectivePoints = const [],
    this.curvePlacing = false,
    this.curveHoverInsert,
    this.moveToolActive = false,
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

    // Document background color (skipped when transparent so the
    // workspace shows through). Layers themselves stay transparent.
    final bgColor = Color(project.settings.backgroundColor);
    if (bgColor.a > 0) {
      canvas.drawRect(docRect, Paint()..color = bgColor);
    }

    for (final layer in project.layers) {
      if (!layer.visible) continue;
      final drawingHere = currentDrawable != null &&
          layer.drawables.contains(currentDrawable);
      final entry = layerRasters[layer.id];
      if (entry != null && !drawingHere && entry.version == layerContentVersion(layer)) {
        // Fast path: blit the cached layer texture with its blend mode.
        canvas.drawImage(entry.image, Offset.zero,
            Paint()
              ..color = Colors.white.withValues(alpha: layer.opacity)
              ..blendMode = layer.blendMode.toFlutterBlendMode());
        for (final d in layer.drawables) {
          if (d.selected) _drawSelectionHandles(canvas, d);
        }
        continue;
      }
      // Slow path: draw content into an isolated layer so the blend mode
      // applies only to this layer's pixels when it is composited back.
      final blendPaint = Paint()
        ..color = Colors.white.withValues(alpha: layer.opacity)
        ..blendMode = layer.blendMode.toFlutterBlendMode();
      canvas.saveLayer(docRect, blendPaint);
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
          Paint(),
        );
        canvas.restore();
      }
      for (final d in layer.drawables) {
        d.draw(canvas, Paint());
      }
      canvas.restore();
      for (final d in layer.drawables) {
        if (d.selected) {
          if (moveToolActive &&
              d.textData != null &&
              d.textData!.trim().isNotEmpty) {
            _drawTextTransformHandles(canvas, d);
          } else {
            _drawSelectionHandles(canvas, d);
          }
        }
      }
    }

    if (currentDrawable != null &&
        !currentDrawable!.isLiquify &&
        !currentDrawable!.isSmudge) {
      // Liquify / smudge overlays are already in the layer's drawable list
      // and render their raster there; drawing them again here would
      // double-blend their semi-transparent edges.
      currentDrawable!.draw(canvas, Paint());
      // While dragging a gradient, also show the direction/extent guide
      // line so the user can see exactly what defines the ramp.
      if (currentDrawable!.isGradient && currentDrawable!.points.length >= 2) {
        final a = currentDrawable!.points.first;
        final b = currentDrawable!.points.last;
        final guideWidth = 1.4 / viewScale;
        canvas.drawLine(
          a, b,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.55)
            ..strokeWidth = guideWidth * 2.6
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(
          a, b,
          Paint()
            ..color = Colors.white
            ..strokeWidth = guideWidth
            ..strokeCap = StrokeCap.round,
        );
        final dotR = 4.0 / viewScale;
        for (final pt in [a, b]) {
          canvas.drawCircle(pt, dotR, Paint()..color = Colors.white);
          canvas.drawCircle(
            pt,
            dotR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = guideWidth
              ..color = Colors.black.withValues(alpha: 0.8),
          );
        }
      }
    }

    // Curve tool overlay: anchor squares, bézier handle lines, ✓/✗ buttons.
    if (currentDrawable != null &&
        currentDrawable!.isShape &&
        currentDrawable!.shapeType == ShapeType.curve) {
      final d = currentDrawable!;
      const anchorR = 5.0;
      final anchorPaint = Paint()..color = Colors.white;
      final anchorStroke = Paint()
        ..color = const Color(0xFF29B6F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / viewScale;

      // Bézier handles: line from anchor to its out-handle + knob.
      if (d.curveHandles != null) {
        for (int i = 0; i < d.points.length && i < d.curveHandles!.length; i++) {
          final h = d.curveHandles![i];
          if (h == null) continue;
          final a = d.points[i];
          canvas.drawLine(
            a, h,
            Paint()
              ..color = const Color(0xFF29B6F6).withValues(alpha: 0.75)
              ..strokeWidth = 1.0 / viewScale,
          );
          canvas.drawCircle(h, anchorR * 0.55, anchorPaint);
          canvas.drawCircle(h, anchorR * 0.55, anchorStroke);
        }
      }

      // Anchor squares.
      for (final pt in d.points) {
        canvas.drawRect(
          Rect.fromCircle(center: pt, radius: anchorR),
          anchorPaint,
        );
        canvas.drawRect(
          Rect.fromCircle(center: pt, radius: anchorR),
          anchorStroke,
        );
      }

      // Mid-segment insertion preview (desktop hover): hollow diamond.
      if (curvePlacing && curveHoverInsert != null) {
        final c = curveHoverInsert!;
        final r = anchorR * 1.2;
        canvas.drawPath(
          ui.Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r, c.dy)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r, c.dy)
            ..close(),
          Paint()..color = const Color(0xFF29B6F6).withValues(alpha: 0.85),
        );
      }

      // ✓ confirm / ✗ remove buttons next to the last anchor.
      if (curvePlacing) {
        final g = curveButtonGeometry(d.points.last, viewScale);
        // ✓ green circle
        canvas.drawCircle(g.confirm, g.radius, Paint()..color = const Color(0xFF2E7D32));
        canvas.drawCircle(
          g.confirm,
          g.radius,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / viewScale,
        );
        // ✗ red circle
        canvas.drawCircle(g.cancel, g.radius, Paint()..color = const Color(0xFFC62828));
        canvas.drawCircle(
          g.cancel,
          g.radius,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / viewScale,
        );
        // Check / cross glyphs (drawn as strokes so no TextPainter needed).
        final glyph = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / viewScale
          ..strokeCap = StrokeCap.round;
        // ✓: two segments.
        final c = g.confirm;
        canvas.drawLine(c + Offset(-g.radius * 0.45, 0.5 / viewScale),
            c + Offset(-g.radius * 0.1, g.radius * 0.4), glyph);
        canvas.drawLine(c + Offset(-g.radius * 0.1, g.radius * 0.4),
            c + Offset(g.radius * 0.45, -g.radius * 0.4), glyph);
        // ✗: two crossing segments.
        final x = g.cancel;
        final q = g.radius * 0.4;
        canvas.drawLine(x - Offset(q, q), x + Offset(q, q), glyph);
        canvas.drawLine(x - Offset(-q, q), x + Offset(-q, q), glyph);
      }
    }

    // Perspective guide overlay: rays fanning out from each vanishing
    // point plus a draggable handle dot. Pure overlay (not serialized).
    if (perspectiveEnabled) {
      const rays = 12;
      const handleR = 9.0;
      final guidePaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.30)
        ..strokeWidth = 1.0 / viewScale;
      for (final vp in perspectivePoints) {
        final path = ui.Path();
        for (int r = 0; r < rays; r++) {
          final angle = r * 2 * pi / rays;
          final far = Offset(
            vp.dx + cos(angle) * 20000,
            vp.dy + sin(angle) * 20000,
          );
          path.moveTo(vp.dx, vp.dy);
          path.lineTo(far.dx, far.dy);
        }
        canvas.drawPath(path, guidePaint);
      }
      for (final vp in perspectivePoints) {
        canvas.drawCircle(
            vp, handleR / viewScale, Paint()..color = Colors.white);
        canvas.drawCircle(
          vp,
          handleR / viewScale,
          Paint()
            ..color = const Color(0xFF0EA5E9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 / viewScale,
        );
      }
    }

    // Selection overlay: blue tint while selecting; during editing only
    // marching ants remain so blank areas don't look like moved content.
    if (hasActiveSelection &&
        selectionMaskImage != null &&
        selectionPhase != SelectionPhase.editing) {
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

  /// PS-style text transform overlay: dashed rotated box, corner scale
  /// handles and a rotation knob on a stem above the top edge.
  void _drawTextTransformHandles(Canvas canvas, Drawable d) {
    final ws = 1.0 / viewScale;
    final corners = textCornerPositions(d);
    final blue = const Color(0xFF29B6F6);

    final box = ui.Path()
      ..addPolygon(corners, true);
    _drawDashedPath(
      canvas,
      box,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * ws,
      dashLen: 5 * ws,
      gapLen: 4 * ws,
    );

    final handleR = 5.5 * ws;
    for (final c in corners) {
      canvas.drawCircle(c, handleR, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        handleR,
        Paint()
          ..color = blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * ws,
      );
    }

    // Rotation knob on a stem above the top edge midpoint.
    final knob = textRotateHandlePosition(d, viewScale);
    final topMid = Offset.lerp(corners[0], corners[1], 0.5)!;
    canvas.drawLine(
      topMid, knob,
      Paint()
        ..color = blue
        ..strokeWidth = 1.2 * ws,
    );
    canvas.drawCircle(knob, handleR, Paint()..color = Colors.white);
    canvas.drawCircle(
      knob,
      handleR,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * ws,
    );
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
