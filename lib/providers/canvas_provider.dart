import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui' as ui;
import 'dart:io';

import '../services/view_transform.dart';

class CanvasProvider extends ChangeNotifier {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;

  /// Size of the canvas viewport (the paint area), reported by the canvas
  /// widget so the overview navigator can work out what is on screen.
  Size _viewportSize = Size.zero;

  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;
  Size get viewportSize => _viewportSize;

  void setViewportSize(Size size) {
    if (size == _viewportSize) return;
    _viewportSize = size;
    notifyListeners();
  }

  ui.Image? _referenceImage;
  String _referencePath = '';
  double _referenceOpacity = 0.5;
  bool _showReference = false;

  // Reference floating window state
  Offset _refWinOffset = const Offset(48, 48);
  Size _refWinSize = const Size(280, 220);
  double _refImgScale = 1.0;
  double _refImgRotation = 0.0;

  ui.Image? get referenceImage => _referenceImage;
  String get referencePath => _referencePath;
  double get referenceOpacity => _referenceOpacity;
  bool get showReference => _showReference;
  Offset get refWinOffset => _refWinOffset;
  Size get refWinSize => _refWinSize;
  double get refImgScale => _refImgScale;
  double get refImgRotation => _refImgRotation;

  void setRefWinOffset(Offset o) {
    _refWinOffset = Offset(o.dx.clamp(0, 4000), o.dy.clamp(0, 4000));
    notifyListeners();
  }

  void setRefWinSize(Size s) {
    _refWinSize = Size(
      s.width.clamp(140.0, 2000.0),
      s.height.clamp(110.0, 2000.0),
    );
    notifyListeners();
  }

  void setRefImgScale(double v) {
    _refImgScale = v.clamp(0.1, 8.0);
    notifyListeners();
  }

  void setRefImgRotation(double v) {
    _refImgRotation = v;
    notifyListeners();
  }

  void resetRefTransform() {
    _refImgScale = 1.0;
    _refImgRotation = 0.0;
    notifyListeners();
  }

  Future<void> setReferenceImage(String path) async {
    if (!File(path).existsSync()) return;
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _referenceImage = frame.image;
    _referencePath = path;
    _showReference = true;
    notifyListeners();
  }

  void setReferenceOpacity(double value) {
    _referenceOpacity = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleReference() {
    _showReference = !_showReference;
    notifyListeners();
  }

  void clearReference() {
    _referenceImage?.dispose();
    _referenceImage = null;
    _referencePath = '';
    _showReference = false;
    resetRefTransform();
    notifyListeners();
  }

  void handleScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    const double trackpadFactor = 3.0;

    if (ctrl) {
      zoomBy(1 - delta.dy * 0.001, Offset.zero);
    } else if (shift) {
      _offset += Offset(delta.dy * trackpadFactor, 0);
      notifyListeners();
    } else {
      _offset += Offset(0, delta.dy * trackpadFactor);
      notifyListeners();
    }
  }

  void panBy(Offset delta) {
    _offset += delta;
    notifyListeners();
  }

  void zoomBy(double scaleDelta, Offset focalPoint) {
    final oldScale = _scale;
    _scale = (_scale * scaleDelta).clamp(0.1, 10.0);
    final ratio = _scale / oldScale;
    _offset = focalPoint - (focalPoint - _offset) * ratio;
    notifyListeners();
  }

  void rotateBy(double angleDelta) {
    _rotation += angleDelta;
    notifyListeners();
  }

  void zoomIn() {
    _scale = (_scale * 1.25).clamp(0.1, 10.0);
    notifyListeners();
  }

  void zoomOut() {
    _scale = (_scale / 1.25).clamp(0.1, 10.0);
    notifyListeners();
  }

  void fitToScreen(
      double screenW, double screenH, double canvasW, double canvasH) {
    if (canvasW == 0 || canvasH == 0) return;
    final sx = screenW / canvasW;
    final sy = screenH / canvasH;
    _scale = min(sx, sy).clamp(0.1, 10.0);
    _offset = Offset.zero;
    _rotation = 0.0;
    notifyListeners();
  }

  void resetView() {
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
    notifyListeners();
  }

  /// Scrolls so [canvasPoint] sits at the centre of the viewport, keeping the
  /// current zoom and rotation. Used by the overview navigator.
  void centerOnCanvasPoint(Offset canvasPoint, Size canvasSize) {
    final transform = ViewTransform(
      offset: _offset,
      scale: _scale,
      rotation: _rotation,
      canvasSize: canvasSize,
      areaSize: _viewportSize,
    );
    _offset = transform.offsetToCenter(canvasPoint);
    notifyListeners();
  }

  /// Sets an absolute zoom level, keeping the viewport centre fixed.
  void zoomTo(double scale) {
    final target = scale.clamp(0.1, 10.0);
    if (target == _scale) return;
    final ratio = target / _scale;
    _offset = _offset * ratio;
    _scale = target;
    notifyListeners();
  }
}
