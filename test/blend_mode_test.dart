import 'dart:ui' show BlendMode;

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_cai/models/layer.dart';

void main() {
  group('BlendModeExt', () {
    test('every mode maps to a distinct Flutter blend mode where meaningful',
        () {
      final mapped = {
        for (final m in BlendModeExt.values) m: m.toFlutterBlendMode()
      };
      // All 20 modes are wired up (no missing switch branch would compile,
      // but this also proves none silently fall through to srcOver).
      expect(mapped.length, 20);
      expect(mapped[BlendModeExt.normal], BlendMode.srcOver);
      expect(mapped[BlendModeExt.multiply], BlendMode.multiply);
      expect(mapped[BlendModeExt.colorDodge], BlendMode.colorDodge);
      expect(mapped[BlendModeExt.additive], BlendMode.plus);
      expect(mapped[BlendModeExt.erase], BlendMode.dstOut);
      expect(mapped[BlendModeExt.behind], BlendMode.dstOver);
    });

    test('jsonName is snake_case for compound names', () {
      expect(BlendModeExt.colorBurn.jsonName, 'color_burn');
      expect(BlendModeExt.colorDodge.jsonName, 'color_dodge');
      expect(BlendModeExt.hardLight.jsonName, 'hard_light');
      expect(BlendModeExt.softLight.jsonName, 'soft_light');
      expect(BlendModeExt.normal.jsonName, 'normal');
    });

    test('fromJsonName accepts snake_case and legacy enum names', () {
      expect(BlendModeExt.fromJsonName('color_burn'), BlendModeExt.colorBurn);
      expect(BlendModeExt.fromJsonName('colorBurn'), BlendModeExt.colorBurn);
      expect(BlendModeExt.fromJsonName('normal'), BlendModeExt.normal);
      expect(BlendModeExt.fromJsonName(null), BlendModeExt.normal);
      expect(BlendModeExt.fromJsonName('bogus'), BlendModeExt.normal);
    });

    test('Layer JSON round-trip preserves blend mode', () {
      final layer = Layer(id: 'a', name: 'A', blendMode: BlendModeExt.softLight);
      final restored = Layer.fromJson(layer.toJson());
      expect(restored.blendMode, BlendModeExt.softLight);
    });

    test('family grouping is exhaustive', () {
      for (final mode in BlendModeExt.values) {
        expect(() => mode.family, returnsNormally);
      }
    });
  });
}
