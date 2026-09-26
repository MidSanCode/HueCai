import 'package:flutter/material.dart';
import '../models/brush.dart';
import '../models/drawable.dart';
import '../services/brush_texture.dart';
import '../services/assist_ruler.dart';
import '../services/palette_service.dart';
import '../services/gamut.dart';
import '../models/brush_preset.dart';

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
  pathEdit,
}

class ToolProvider extends ChangeNotifier {
  ToolType _currentTool = ToolType.brush;
  ShapeType _currentShape = ShapeType.rect;
  Color _primaryColor = Colors.black;
  Color _secondaryColor = Colors.white;
  Color _gradientStartColor = Colors.black;
  Color _gradientEndColor = Colors.blue;
  Brush _currentBrush = Brush.defaults().first;
  String? _activePresetId;
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

  // Palette + soft proofing
  Palette? _palette;
  bool _gamutWarningEnabled = false;
  PrintProfile _printProfile = PrintProfile.coated;
  Color? _softProofColor;

  ToolType get currentTool => _currentTool;
  ShapeType get currentShape => _currentShape;
  Color get primaryColor => _primaryColor;
  Color get secondaryColor => _secondaryColor;
  Color get gradientStartColor => _gradientStartColor;
  Color get gradientEndColor => _gradientEndColor;
  Brush get currentBrush => _currentBrush;
  BrushType get brushType => _currentBrush.type;

  /// Id of the preset the brush currently mirrors, or null once it has been
  /// tweaked by hand.
  String? get activePresetId => _activePresetId;
  double get brushSize => _brushSize;
  double get brushOpacity => _brushOpacity;
  bool get isStandardMode => _isStandardMode;
  bool get symmetryEnabled => _symmetryEnabled;
  bool get perspectiveGuideEnabled => _perspectiveGuideEnabled;
  List<AssistRuler> get rulers => List.unmodifiable(_rulers);
  bool get rulerSnapEnabled => _rulerSnapEnabled;

  Palette? get palette => _palette;
  bool get gamutWarningEnabled => _gamutWarningEnabled;
  PrintProfile get printProfile => _printProfile;

  /// Soft-proofed preview of the primary color (null when disabled).
  Color? get softProofColor => _softProofColor;

  /// True when the active color cannot be reproduced by the print profile.
  bool get primaryOutOfGamut => _gamutWarningEnabled &&
      Gamut.isOutOfGamut(_primaryColor, _printProfile);

  void setPalette(Palette? palette) {
    _palette = palette;
    notifyListeners();
  }

  void addPaletteColor(Color color) {
    final p = _palette ??= Palette(name: 'Custom');
    if (!p.colors.contains(color)) {
      p.colors.add(color);
      notifyListeners();
    }
  }

  void removePaletteColor(int index) {
    final p = _palette;
    if (p == null || index < 0 || index >= p.colors.length) return;
    p.colors.removeAt(index);
    notifyListeners();
  }

  void toggleGamutWarning() {
    _gamutWarningEnabled = !_gamutWarningEnabled;
    _refreshSoftProof();
    notifyListeners();
  }

  void setPrintProfile(PrintProfile profile) {
    _printProfile = profile;
    _refreshSoftProof();
    notifyListeners();
  }

  /// Soft-proof preview toggle for the canvas (independent of the warning).
  void setSoftProofEnabled(bool enabled) {
    _gamutWarningEnabled = enabled;
    _refreshSoftProof();
    notifyListeners();
  }

  void _refreshSoftProof() {
    _softProofColor = _gamutWarningEnabled
        ? Gamut.softProof(_primaryColor, _printProfile)
        : null;
  }

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

  bool _textOnPath = false;
  double _textPathOffset = 0;

  /// Text tool: lay the next text out along a path instead of at one anchor.
  bool get textOnPath => _textOnPath;

  /// Distance along the baseline where text-on-path starts.
  double get textPathOffset => _textPathOffset;

  void toggleTextOnPath() {
    _textOnPath = !_textOnPath;
    notifyListeners();
  }

  void setTextPathOffset(double value) {
    _textPathOffset = value;
    notifyListeners();
  }

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
    _refreshSoftProof();
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
    _activePresetId = null;
    notifyListeners();
  }

  /// Applies a saved preset to the live brush state and remembers which one
  /// is active (cleared again as soon as the brush is tweaked by hand).
  void applyPreset(BrushPreset preset) {
    _activePresetId = preset.id;
    _currentBrush = Brush(
      type: preset.type,
      nameKey: 'preset.custom',
      size: preset.size,
      hardness: preset.hardness,
      opacity: preset.opacity,
      flow: preset.flow,
      spacing: preset.spacing,
      tipTexture: preset.tipTexture,
      mix: preset.mix,
    );
    _brushSize = preset.size;
    _brushOpacity = preset.opacity;
    notifyListeners();
  }

  void setBrushType(BrushType type) {
    _currentBrush = _currentBrush.copyWith(type: type);
    _activePresetId = null;
    notifyListeners();
  }

  void setBrushTipTexture(BrushTexture texture) {
    _currentBrush = _currentBrush.copyWith(tipTexture: texture);
    _activePresetId = null;
    notifyListeners();
  }

  void setBrushSize(double size) {
    _brushSize = size.clamp(0.5, 100.0);
    _currentBrush.size = _brushSize;
    _activePresetId = null;
    notifyListeners();
  }

  void setBrushOpacity(double opacity) {
    _brushOpacity = opacity.clamp(0.0, 1.0);
    _currentBrush.opacity = _brushOpacity;
    _activePresetId = null;
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
