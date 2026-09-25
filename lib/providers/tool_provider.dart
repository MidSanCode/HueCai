import 'package:flutter/material.dart';
import '../models/brush.dart';
import '../models/drawable.dart';
import '../services/brush_texture.dart';
import '../services/assist_ruler.dart';

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
  smudge,
  willowLeaf,
  liquify,
  perspectiveGuide,
  symmetry,
}

class ToolProvider extends ChangeNotifier {
  ToolType _currentTool = ToolType.brush;
  ShapeType _currentShape = ShapeType.rect;
  Color _primaryColor = Colors.black;
  Color _secondaryColor = Colors.white;
  Color _gradientStartColor = Colors.black;
  Color _gradientEndColor = Colors.blue;
  Brush _currentBrush = Brush.defaults().first;
  double _brushSize = 5.0;
  double _brushOpacity = 1.0;
  bool _isStandardMode = false;
  bool _symmetryEnabled = false;
  bool _perspectiveGuideEnabled = false;
  final List<AssistRuler> _rulers = [];
  bool _rulerSnapEnabled = true;
  // Last font chosen in the text dialog; remembered across placements.
  String _textFontFamily = 'Microsoft YaHei';
  final List<Color> _memoryColors = List.filled(20, Colors.transparent);

  ToolType get currentTool => _currentTool;
  ShapeType get currentShape => _currentShape;
  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  Color get gradientStartColor => _gradientStartColor;
  Color get gradientEndColor => _gradientEndColor;
  Brush get currentBrush => _currentBrush;
  BrushType get brushType => _currentBrush.type;
  double get brushSize => _brushSize;
  double get brushOpacity => _brushOpacity;
  bool get isStandardMode => _isStandardMode;
  bool get symmetryEnabled => _symmetryEnabled;
  bool get perspectiveGuideEnabled => _perspectiveGuideEnabled;
  List<AssistRuler> get rulers => List.unmodifiable(_rulers);
  bool get rulerSnapEnabled => _rulerSnapEnabled;

  void addRuler(RulerType type, Offset center) {
    _rulers.add(AssistRuler(
      id: 'ruler_${_rulers.length}_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      center: center,
      points: type == RulerType.spline
          ? [
              center + const Offset(-100, 40),
              center + const Offset(-33, -40),
              center + const Offset(33, 40),
              center + const Offset(100, -40),
            ]
          : [],
    ));
    notifyListeners();
  }

  void removeRuler(String id) {
    _rulers.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  void clearRulers() {
    _rulers.clear();
    notifyListeners();
  }

  /// Mutates a ruler (handle drag) and notifies.
  void updateRuler(String id, void Function(AssistRuler) edit) {
    final i = _rulers.indexWhere((r) => r.id == id);
    if (i < 0) return;
    edit(_rulers[i]);
    notifyListeners();
  }

  AssistRuler? rulerById(String id) {
    for (final r in _rulers) {
      if (r.id == id) return r;
    }
    return null;
  }

  void setRulerSnapEnabled(bool v) {
    _rulerSnapEnabled = v;
    notifyListeners();
  }

  /// Snaps [p] to the nearest active ruler, or returns [p] unchanged when
  /// snapping is off or no ruler exists.
  Offset snapToRulers(Offset p) {
    if (!_rulerSnapEnabled || _rulers.isEmpty) return p;
    Offset best = p;
    var bestDist = double.infinity;
    for (final r in _rulers) {
      if (!r.visible) continue;
      final q = r.snapPoint(p);
      final d = (q - p).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        best = q;
      }
    }
    return best;
  }
  String get textFontFamily => _textFontFamily;
  List<Color> get memoryColors => _memoryColors;

  void setTextFontFamily(String family) {
    _textFontFamily = family;
    notifyListeners();
  }

  void addMemoryColor(Color c) {
    _memoryColors.remove(c);
    _memoryColors.insert(0, c);
    if (_memoryColors.length > 20) _memoryColors.removeLast();
    notifyListeners();
  }

  void clearMemoryColor(int index) {
    if (index >= 0 && index < _memoryColors.length) {
      _memoryColors[index] = Colors.transparent;
      notifyListeners();
    }
  }

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

  void setGradientStartColor(Color color) {
    _gradientStartColor = color;
    notifyListeners();
  }

  void setGradientEndColor(Color color) {
    _gradientEndColor = color;
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

  void setBrushType(BrushType type) {
    _currentBrush = _currentBrush.copyWith(type: type);
    notifyListeners();
  }

  void setBrushTipTexture(BrushTexture texture) {
    _currentBrush = _currentBrush.copyWith(tipTexture: texture);
    notifyListeners();
  }

  void setBrushSize(double size) {
    _brushSize = size.clamp(0.5, 100.0);
    _currentBrush.size = _brushSize;
    notifyListeners();
  }

  void setBrushOpacity(double opacity) {
    _brushOpacity = opacity.clamp(0.0, 1.0);
    _currentBrush.opacity = _brushOpacity;
    notifyListeners();
  }

  void toggleSymmetry() {
    _symmetryEnabled = !_symmetryEnabled;
    notifyListeners();
  }

  void togglePerspectiveGuide() {
    _perspectiveGuideEnabled = !_perspectiveGuideEnabled;
    notifyListeners();
  }
}
