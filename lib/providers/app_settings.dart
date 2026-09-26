import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/stroke_stabilizer.dart';
import '../models/brush_preset.dart';
import '../models/pattern.dart';
import 'tool_provider.dart';

class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'zh';
  double _stabilizer = 0;
  StabilizerMode _stabilizerMode = StabilizerMode.smooth;
  bool _pressureCurveEnabled = false;
  PressureCurve _pressureCurve = PressureCurve();
  bool _velocityWidthEnabled = true;
  double _velocityMinScale = 0.35;
  double _velocityMaxScale = 1.0;
  double _velocitySmoothing = 0.4;
  bool _velocityInkEnabled = true;
  double _velocityInkMinScale = 0.45;
  bool _pressureWidthEnabled = true;
  double _pressureMinScale = 0.3;
  double _pressureMaxScale = 1.0;
  double _velocityPressureBlend = 0.0;
  bool _hasPressure = false;

  // Paint-bucket fill: colour tolerance (0-255), edge grow/shrink in pixels
  // (positive expands the region, negative contracts it) and edge
  // anti-aliasing (feathered boundary alpha).
  int _fillTolerance = 32;
  int _fillGrowShrink = 0;
  bool _fillAntiAlias = true;
  List<String> _toolbarTools = [
    'brush', 'eraser', 'shape', 'select',
    'smudge', 'willowLeaf',
  ];

  // Resource libraries (roadmap item 16): user-saved brush presets and
  // patterns. Both are small parametric JSON documents, so they live in the
  // same settings file as everything else.
  final List<BrushPreset> _brushPresets = [];
  final List<PatternSpec> _patterns = PatternSpec.builtIns();

  /// Fill tool: paint the flood-filled region with the active pattern
  /// instead of a flat colour.
  bool _fillWithPattern = false;
  String? _activePatternId;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  double get stabilizer => _stabilizer;
  StabilizerMode get stabilizerMode => _stabilizerMode;
  bool get pressureCurveEnabled => _pressureCurveEnabled;
  PressureCurve get pressureCurve => _pressureCurve;
  bool get velocityWidthEnabled => _velocityWidthEnabled;
  double get velocityMinScale => _velocityMinScale;
  double get velocityMaxScale => _velocityMaxScale;
  double get velocitySmoothing => _velocitySmoothing;
  bool get velocityInkEnabled => _velocityInkEnabled;
  double get velocityInkMinScale => _velocityInkMinScale;
  bool get pressureWidthEnabled => _pressureWidthEnabled;
  double get pressureMinScale => _pressureMinScale;
  double get pressureMaxScale => _pressureMaxScale;
  double get velocityPressureBlend => _velocityPressureBlend;
  bool get hasPressure => _hasPressure;
  int get fillTolerance => _fillTolerance;
  int get fillGrowShrink => _fillGrowShrink;
  bool get fillAntiAlias => _fillAntiAlias;
  List<String> get toolbarTools => _toolbarTools;

  /// User brush presets (built-ins come from [BrushPreset.builtIns]).
  List<BrushPreset> get brushPresets => List.unmodifiable(_brushPresets);

  /// User patterns; the library always starts with a few stock entries.
  List<PatternSpec> get patterns => List.unmodifiable(_patterns);

  bool get fillWithPattern => _fillWithPattern;

  /// Pattern currently selected for pattern fills (falls back to the first
  /// entry so a fill always has something to use).
  PatternSpec? get activePattern {
    final id = _activePatternId;
    if (id != null) {
      for (final p in _patterns) {
        if (p.id == id) return p;
      }
    }
    return _patterns.isEmpty ? null : _patterns.first;
  }

  /// Every preset the UI should offer: built-ins first, then user presets.
  List<BrushPreset> get allBrushPresets => [
        ...BrushPreset.builtIns(),
        ..._brushPresets,
      ];

  List<ToolType> get toolbarToolTypes =>
      _toolbarTools.map((s) => ToolType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => ToolType.brush,
      )).toList();

  void updatePressureCapability(bool v) {
    _hasPressure = v;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/huecai_settings.json');
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.toString() == json['themeMode'],
          orElse: () => ThemeMode.system,
        );
        _languageCode = json['languageCode'] as String? ?? 'zh';
        _stabilizer = (json['stabilizer'] as num?)?.toDouble() ?? 0;
        _stabilizerMode = StabilizerMode.values.firstWhere(
          (m) => m.name == json['stabilizerMode'],
          orElse: () => StabilizerMode.smooth,
        );
        _pressureCurveEnabled = json['pressureCurveEnabled'] as bool? ?? false;
        _pressureCurve =
            PressureCurve.fromJson(json['pressureCurvePoints'] as List?);
        _velocityWidthEnabled = json['velocityWidthEnabled'] as bool? ?? true;
        _velocityMinScale = (json['velocityMinScale'] as num?)?.toDouble() ?? 0.35;
        _velocityMaxScale = (json['velocityMaxScale'] as num?)?.toDouble() ?? 1.0;
        _velocitySmoothing = (json['velocitySmoothing'] as num?)?.toDouble() ?? 0.6;
        _velocityInkEnabled = json['velocityInkEnabled'] as bool? ?? true;
        _velocityInkMinScale = (json['velocityInkMinScale'] as num?)?.toDouble() ?? 0.45;
        _pressureWidthEnabled = json['pressureWidthEnabled'] as bool? ?? true;
        _pressureMinScale = (json['pressureMinScale'] as num?)?.toDouble() ?? 0.3;
        _pressureMaxScale = (json['pressureMaxScale'] as num?)?.toDouble() ?? 1.0;
        _velocityPressureBlend = (json['velocityPressureBlend'] as num?)?.toDouble() ?? 0.0;
        _fillTolerance = (json['fillTolerance'] as num?)?.toInt() ?? 32;
        _fillGrowShrink = (json['fillGrowShrink'] as num?)?.toInt() ?? 0;
        _fillAntiAlias = json['fillAntiAlias'] as bool? ?? true;
        _toolbarTools = (json['toolbarTools'] as List?)
            ?.map((e) => e as String)
            .toList() ?? _toolbarTools;
        // Resource libraries: only replace the seeds when the file actually
        // carries a list (a settings file from before this feature keeps the
        // stock patterns).
        if (json['brushPresets'] is List) {
          _brushPresets
            ..clear()
            ..addAll((json['brushPresets'] as List)
                .whereType<Map>()
                .map((e) => BrushPreset.fromJson(e.cast<String, dynamic>())));
        }
        if (json['patterns'] is List) {
          _patterns
            ..clear()
            ..addAll((json['patterns'] as List)
                .whereType<Map>()
                .map((e) => PatternSpec.fromJson(e.cast<String, dynamic>())));
        }
        _fillWithPattern = json['fillWithPattern'] as bool? ?? false;
        _activePatternId = json['activePatternId'] as String?;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/huecai_settings.json');
      await file.writeAsString(jsonEncode({
        'themeMode': _themeMode.toString(),
        'languageCode': _languageCode,
        'stabilizer': _stabilizer,
        'stabilizerMode': _stabilizerMode.name,
        'pressureCurveEnabled': _pressureCurveEnabled,
        'pressureCurvePoints': _pressureCurve.toJson(),
        'velocityWidthEnabled': _velocityWidthEnabled,
        'velocityMinScale': _velocityMinScale,
        'velocityMaxScale': _velocityMaxScale,
        'velocitySmoothing': _velocitySmoothing,
        'velocityInkEnabled': _velocityInkEnabled,
        'velocityInkMinScale': _velocityInkMinScale,
        'pressureWidthEnabled': _pressureWidthEnabled,
        'pressureMinScale': _pressureMinScale,
        'pressureMaxScale': _pressureMaxScale,
        'velocityPressureBlend': _velocityPressureBlend,
        'fillTolerance': _fillTolerance,
        'fillGrowShrink': _fillGrowShrink,
        'fillAntiAlias': _fillAntiAlias,
        'toolbarTools': _toolbarTools,
        'brushPresets': _brushPresets.map((p) => p.toJson()).toList(),
        'patterns': _patterns.map((p) => p.toJson()).toList(),
        'fillWithPattern': _fillWithPattern,
        'activePatternId': _activePatternId,
      }));
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _save();
    notifyListeners();
  }

  void setLanguageCode(String code) {
    _languageCode = code;
    _save();
    notifyListeners();
  }

  void setStabilizer(double value) {
    _stabilizer = value.clamp(0, 100);
    _save();
    notifyListeners();
  }

  void setStabilizerMode(StabilizerMode mode) {
    _stabilizerMode = mode;
    _save();
    notifyListeners();
  }

  void setPressureCurveEnabled(bool v) {
    _pressureCurveEnabled = v;
    _save();
    notifyListeners();
  }

  void setPressureCurve(PressureCurve curve) {
    _pressureCurve = curve;
    _save();
    notifyListeners();
  }

  /// Maps raw stylus pressure through the configured curve when enabled.
  double mapPressure(double raw) =>
      _pressureCurveEnabled ? _pressureCurve.map(raw) : raw.clamp(0.0, 1.0);

  void setVelocityWidthEnabled(bool v) { _velocityWidthEnabled = v; _save(); notifyListeners(); }
  void setVelocityMinScale(double v) { _velocityMinScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setVelocityMaxScale(double v) { _velocityMaxScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setVelocitySmoothing(double v) { _velocitySmoothing = v.clamp(0.0, 1.0); _save(); notifyListeners(); }
  void setVelocityInkEnabled(bool v) { _velocityInkEnabled = v; _save(); notifyListeners(); }
  void setVelocityInkMinScale(double v) { _velocityInkMinScale = v.clamp(0.05, 1.0); _save(); notifyListeners(); }
  void setPressureWidthEnabled(bool v) { _pressureWidthEnabled = v; _save(); notifyListeners(); }
  void setPressureMinScale(double v) { _pressureMinScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setPressureMaxScale(double v) { _pressureMaxScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setVelocityPressureBlend(double v) { _velocityPressureBlend = v.clamp(0.0, 1.0); _save(); notifyListeners(); }

  void setFillTolerance(int v) { _fillTolerance = v.clamp(0, 255); _save(); notifyListeners(); }

  void setFillGrowShrink(int v) { _fillGrowShrink = v.clamp(-25, 25); _save(); notifyListeners(); }

  void setFillAntiAlias(bool v) { _fillAntiAlias = v; _save(); notifyListeners(); }

  void setToolbarTools(List<String> tools) {
    _toolbarTools = tools;
    _save();
    notifyListeners();
  }

  void addToolbarTool(String tool) {
    if (!_toolbarTools.contains(tool)) {
      _toolbarTools.add(tool);
      _save();
      notifyListeners();
    }
  }

  void removeToolbarTool(String tool) {
    _toolbarTools.remove(tool);
    _save();
    notifyListeners();
  }

  void moveToolbarTool(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _toolbarTools.removeAt(oldIndex);
    _toolbarTools.insert(newIndex, item);
    _save();
    notifyListeners();
  }

  // ─── Resource libraries ─────────────────────────────────────────

  /// Adds a user brush preset. Re-importing the same id replaces the old
  /// entry instead of duplicating it (packs are idempotent).
  void addBrushPreset(BrushPreset preset) {
    _brushPresets.removeWhere((p) => p.id == preset.id);
    _brushPresets.add(preset);
    _save();
    notifyListeners();
  }

  /// Adds every preset from an imported pack; returns how many were added.
  int addBrushPresets(Iterable<BrushPreset> presets) {
    var count = 0;
    for (final preset in presets) {
      _brushPresets.removeWhere((p) => p.id == preset.id);
      _brushPresets.add(preset);
      count++;
    }
    if (count > 0) {
      _save();
      notifyListeners();
    }
    return count;
  }

  void removeBrushPreset(String id) {
    final before = _brushPresets.length;
    _brushPresets.removeWhere((p) => p.id == id);
    if (_brushPresets.length != before) {
      _save();
      notifyListeners();
    }
  }

  void renameBrushPreset(String id, String name) {
    for (final preset in _brushPresets) {
      if (preset.id == id) {
        preset.name = name;
        _save();
        notifyListeners();
        return;
      }
    }
  }

  /// Adds a pattern and makes it the active one.
  void addPattern(PatternSpec pattern) {
    _patterns.removeWhere((p) => p.id == pattern.id);
    _patterns.add(pattern);
    _activePatternId = pattern.id;
    _save();
    notifyListeners();
  }

  /// Adds every pattern from an imported pack; returns how many were added.
  int addPatterns(Iterable<PatternSpec> patterns) {
    var count = 0;
    for (final pattern in patterns) {
      _patterns.removeWhere((p) => p.id == pattern.id);
      _patterns.add(pattern);
      count++;
    }
    if (count > 0) {
      _activePatternId ??= patterns.first.id;
      _save();
      notifyListeners();
    }
    return count;
  }

  void removePattern(String id) {
    final before = _patterns.length;
    _patterns.removeWhere((p) => p.id == id);
    if (_patterns.length != before) {
      if (_activePatternId == id) _activePatternId = null;
      _save();
      notifyListeners();
    }
  }

  void renamePattern(String id, String name) {
    for (final pattern in _patterns) {
      if (pattern.id == id) {
        pattern.name = name;
        _save();
        notifyListeners();
        return;
      }
    }
  }

  void setActivePattern(String id) {
    _activePatternId = id;
    _save();
    notifyListeners();
  }

  void setFillWithPattern(bool v) {
    _fillWithPattern = v;
    _save();
    notifyListeners();
  }
}