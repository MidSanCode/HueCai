import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/image_filters.dart';
import 'package:hue_cai/services/lgdf_codec.dart';

Project _project() => Project(
      id: 'p1',
      name: 'clone test',
      settings: const CanvasSettings(width: 32, height: 32),
      layers: [
        Layer(
          id: 'base',
          name: 'base',
          drawables: [
            Drawable(
              id: 'd1',
              points: const [Offset(4, 4), Offset(28, 28)],
              color: const Color(0xFFFF0000),
              strokeWidth: 6,
            ),
          ],
        ),
      ],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AdjustmentSpec', () {
    test('JSON round-trip preserves kind and params', () {
      const spec = AdjustmentSpec('levels', {
        'in_black': 10,
        'in_white': 240,
        'gamma': 1.4,
      });
      final restored = AdjustmentSpec.fromJson(spec.toJson());
      expect(restored.kind, 'levels');
      expect(restored.params['in_black'], 10);
      expect(restored.params['gamma'], 1.4);
    });

    test('apply routes to the matching filter', () {
      final img = RgbaImage.blank(4, 4);
      // Gray pixels.
      for (var i = 0; i < img.pixels.length; i += 4) {
        img.pixels[i] = 128;
        img.pixels[i + 1] = 128;
        img.pixels[i + 2] = 128;
        img.pixels[i + 3] = 255;
      }
      const bright = AdjustmentSpec('levels', {'in_black': 0, 'in_white': 200});
      final out = bright.apply(img);
      expect(out.pixels[0], greaterThan(128)); // contrast stretched
    });

    test('unknown kind is a pass-through copy', () {
      final img = RgbaImage.blank(2, 2);
      img.pixels[0] = 42;
      const spec = AdjustmentSpec('nope', {});
      expect(spec.apply(img).pixels[0], 42);
    });
  });

  group('Layer clone/adjustment fields', () {
    test('Layer JSON round-trip carries cloneOfId and adjustment', () {
      final layer = Layer(
        id: 'a',
        name: 'A',
        cloneOfId: 'base',
        adjustment: const AdjustmentSpec('gaussianBlur', {'radius': 8.0}),
      );
      final restored = Layer.fromJson(layer.toJson());
      expect(restored.cloneOfId, 'base');
      expect(restored.adjustment!.kind, 'gaussianBlur');
      expect(restored.adjustment!.params['radius'], 8.0);
    });

    test('LGDF package round-trip preserves clone and adjustment', () async {
      final project = _project();
      project.layers.add(Layer(id: 'clone', name: 'clone', cloneOfId: 'base'));
      project.layers.add(Layer(
        id: 'adj',
        name: 'adj',
        adjustment: const AdjustmentSpec('hueSaturation', {'hue': 30.0}),
      ));

      final dir = await Directory.systemTemp.createTemp('huecai_clone');
      final path = '${dir.path}/c${LgdfCodec.extension}';
      await LgdfCodec.writePackage(path, project, HistoryService());
      final loaded = await LgdfCodec.readPackage(path);

      expect(loaded, isNotNull);
      expect(loaded!.layers[1].cloneOfId, 'base');
      expect(loaded.layers[2].adjustment!.kind, 'hueSaturation');
      expect(loaded.layers[2].adjustment!.params['hue'], 30.0);

      await dir.delete(recursive: true);
    });
  });

  group('ProjectProvider clone/adjustment ops', () {
    test('addCloneLayer inserts a clone above the source', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addCloneLayer(0);
      final layers = pp.currentProject!.layers;
      expect(layers, hasLength(3)); // bg + paint + clone
      expect(layers[1].cloneOfId, layers[0].id);
    });

    test('clone of a clone is refused', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addCloneLayer(0);
      final before = pp.currentProject!.layers.length;
      pp.addCloneLayer(1); // layers[1] is the clone
      expect(pp.currentProject!.layers.length, before);
    });

    test('addAdjustmentLayer inserts above and selects it', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addAdjustmentLayer(
          0, const AdjustmentSpec('gaussianBlur', {'radius': 4.0}));
      final project = pp.currentProject!;
      expect(project.layers[1].adjustment, isNotNull);
      expect(project.currentLayerIndex, 1);
    });

    test('updateAdjustmentLayer replaces params on adjustment layers only',
        () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addAdjustmentLayer(
          0, const AdjustmentSpec('gaussianBlur', {'radius': 4.0}));
      pp.updateAdjustmentLayer(
          1, const AdjustmentSpec('gaussianBlur', {'radius': 12.0}));
      expect(pp.currentProject!.layers[1].adjustment!.params['radius'], 12.0);
      // Non-adjustment layer: no-op.
      pp.updateAdjustmentLayer(
          0, const AdjustmentSpec('levels', {'gamma': 2.0}));
      expect(pp.currentProject!.layers[0].adjustment, isNull);
    });
  });
}
