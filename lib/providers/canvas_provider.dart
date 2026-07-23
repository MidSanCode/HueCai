import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

class CanvasProvider extends ChangeNotifier {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0;

  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;

  void handleScroll(PointerScrollEvent event) {
    final delta = event.scrollDelta;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl) {
      zoomBy(1 - delta.dy * 0.001, Offset.zero);
    } else if (shift) {
      _offset += Offset(delta.dy, 0);
      notifyListeners();
    } else {
      _offset += Offset(0, delta.dy);
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
}
