import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'zh';
  double _stabilizer = 0;
  bool _velocityWidthEnabled = true;
  double _velocityMinScale = 0.35;
  double _velocityMaxScale = 1.0;
  double _velocitySmoothing = 0.3;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  double get stabilizer => _stabilizer;
  bool get velocityWidthEnabled => _velocityWidthEnabled;
  double get velocityMinScale => _velocityMinScale;
  double get velocityMaxScale => _velocityMaxScale;
  double get velocitySmoothing => _velocitySmoothing;

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
        _velocityWidthEnabled = json['velocityWidthEnabled'] as bool? ?? true;
        _velocityMinScale = (json['velocityMinScale'] as num?)?.toDouble() ?? 0.35;
        _velocityMaxScale = (json['velocityMaxScale'] as num?)?.toDouble() ?? 1.0;
        _velocitySmoothing = (json['velocitySmoothing'] as num?)?.toDouble() ?? 0.3;
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
        'velocityWidthEnabled': _velocityWidthEnabled,
        'velocityMinScale': _velocityMinScale,
        'velocityMaxScale': _velocityMaxScale,
        'velocitySmoothing': _velocitySmoothing,
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

  void setVelocityWidthEnabled(bool v) { _velocityWidthEnabled = v; _save(); notifyListeners(); }
  void setVelocityMinScale(double v) { _velocityMinScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setVelocityMaxScale(double v) { _velocityMaxScale = v.clamp(0.1, 1.0); _save(); notifyListeners(); }
  void setVelocitySmoothing(double v) { _velocitySmoothing = v.clamp(0.0, 1.0); _save(); notifyListeners(); }
}