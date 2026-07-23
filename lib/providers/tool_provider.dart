import 'package:flutter/material.dart';
import '../models/brush.dart';
import '../models/drawable.dart';

enum ToolType {
  move,
  shape,
  pen,
  text,
  select,
  brush,
  eraser,
  fill,
  gradient,
  eyedropper,
}

class ToolProvider extends ChangeNotifier {
  ToolType _currentTool = ToolType.brush;
  ShapeType _currentShape = ShapeType.rect;
  Color _primaryColor = Colors.black;
  Color _secondaryColor = Colors.white;
  Brush _currentBrush = Brush.defaults().first;
  double _brushSize = 10.0;
  double _brushOpacity = 1.0;
  bool _isStandardMode = false;

  ToolType get currentTool => _currentTool;
  ShapeType get currentShape => _currentShape;
  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  Brush get currentBrush => _currentBrush;
  double get brushSize => _brushSize;
  double get brushOpacity => _brushOpacity;
  bool get isStandardMode => _isStandardMode;

  void setTool(ToolType tool) {
    _currentTool = tool;
    notifyListeners();
  }

  void setShape(ShapeType shape) {
    _currentShape = shape;
    _currentTool = ToolType.shape;
    notifyListeners();
  }

  void toggleStandardMode() {
    _isStandardMode = !_isStandardMode;
    notifyListeners();
  }

  double snapAngle(double angle) {
    if (!_isStandardMode) return angle;
    const step = 30.0 * 3.1415926535 / 180.0;
    return (angle / step).round() * step;
  }

  double snapToSquare(double value) {
    if (!_isStandardMode) return value;
    return value;
  }

  void setPrimaryColor(Color color) {
    _primaryColor = color;
    notifyListeners();
  }

  void setSecondaryColor(Color color) {
    _secondaryColor = color;
    notifyListeners();
  }

  void swapColors() {
    final temp = _primaryColor;
    _primaryColor = _secondaryColor;
    _secondaryColor = temp;
    notifyListeners();
  }

  void setBrush(Brush brush) {
    _currentBrush = brush;
    _brushSize = brush.size;
    _brushOpacity = brush.opacity;
    notifyListeners();
  }

  void setBrushSize(double size) {
    _brushSize = size.clamp(1.0, 500.0);
    _currentBrush.size = _brushSize;
    notifyListeners();
  }

  void setBrushOpacity(double opacity) {
    _brushOpacity = opacity.clamp(0.0, 1.0);
    _currentBrush.opacity = _brushOpacity;
    notifyListeners();
  }
}
