import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/mask_stroke.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/lgdf_codec.dart';

Project _project() => Project(
      id: 'p1',
      name: 'mask test',
      settings: const CanvasSettings(width: 64, height: 64),
      layers: [
        Layer(
          id: 'l1',
          name: 'paint',
          drawables: [
            Drawable(
              id: 'd1',
              points: const [Offset(8, 8), Offset(56, 56)],
              color: const Color(0xFFFF0000),
              strokeWidth: 12,
              isFilled: false,
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

  group('MaskStroke', () {
    test('JSON round-trip preserves all fields', () {
      final stroke = MaskStroke(
        id: 'm1',
        points: const [Offset(1, 2), Offset(3, 4)],
        width: 15,
        opacity: 0.6,
        erase: true,
      );
      final restored = MaskStroke.fromJson(stroke.toJson());
      expect(restored.id, 'm1');
      expect(restored.points, hasLength(2));
      expect(restored.points.last, const Offset(3, 4));
      expect(restored.width, 15);
      expect(restored.opacity, 0.6);
      expect(restored.erase, isTrue);
    });
  });

  group('Layer mask serialization', () {
    test('mask fields survive Layer JSON round-trip', () {
      final layer = Layer(id: 'a', name: 'A');
      layer.maskStrokes = [
        MaskStroke(id: 'm', points: const [Offset(5, 5)], erase: true),
      ];
      layer.maskEnabled = false;

      final restored = Layer.fromJson(layer.toJson());
      expect(restored.maskStrokes, hasLength(1));
      expect(restored.maskStrokes!.first.erase, isTrue);
      expect(restored.maskEnabled, isFalse);
    });

    test('layers without a mask load with null strokes and enabled flag', () {
      final restored = Layer.fromJson(Layer(id: 'a', name: 'A').toJson());
      expect(restored.maskStrokes, isNull);
      expect(restored.maskEnabled, isTrue);
    });

    test('mask survives the LGDF package round-trip', () async {
      final project = _project();
      project.layers.first.maskStrokes = [
        MaskStroke(
          id: 'm1',
          points: const [Offset(10, 10), Offset(20, 20)],
          width: 10,
          erase: true,
        ),
      ];

      final dir = await Directory.systemTemp.createTemp('huecai_mask');
      final path = '${dir.path}/m${LgdfCodec.extension}';
      await LgdfCodec.writePackage(path, project, HistoryService());
      final loaded = await LgdfCodec.readPackage(path);

      expect(loaded, isNotNull);
      expect(loaded!.layers.first.maskStrokes, hasLength(1));
      expect(loaded.layers.first.maskStrokes!.first.erase, isTrue);
      expect(loaded.layers.first.maskStrokes!.first.points, hasLength(2));

      await dir.delete(recursive: true);
    });
  });

  group('ProjectProvider mask ops', () {
    test('addLayerMask creates an empty mask and enters mask editing',
        () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      expect(pp.maskEditing, isFalse);
      pp.addLayerMask(pp.currentProject!.currentLayerIndex);
      expect(pp.currentProject!.currentLayer!.maskStrokes, isNotNull);
      expect(pp.maskEditing, isTrue);
    });

    test('setMaskEditing refuses to activate without a mask', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.setMaskEditing(true);
      expect(pp.maskEditing, isFalse);
    });

    test('begin/extend/end mask stroke accumulates points', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addLayerMask(1);
      pp.beginMaskStroke(const Offset(1, 1),
          width: 10, opacity: 1, conceal: true);
      pp.extendMaskStrokeSilent(const Offset(5, 5));
      pp.extendMaskStrokeSilent(const Offset(9, 9));
      pp.endMaskStroke();

      final strokes = pp.currentProject!.currentLayer!.maskStrokes!;
      expect(strokes, hasLength(1));
      expect(strokes.first.points, hasLength(3));
      expect(strokes.first.erase, isTrue);
    });

    test('removeLayerMask clears strokes and exits editing', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addLayerMask(1);
      pp.beginMaskStroke(const Offset(1, 1),
          width: 10, opacity: 1, conceal: true);
      pp.removeLayerMask(1);
      expect(pp.currentProject!.layers[1].maskStrokes, isNull);
      expect(pp.maskEditing, isFalse);
    });

    test('toggleLayerMaskEnabled keeps the strokes', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addLayerMask(1);
      pp.beginMaskStroke(const Offset(1, 1),
          width: 10, opacity: 1, conceal: true);
      pp.toggleLayerMaskEnabled(1);
      final layer = pp.currentProject!.layers[1];
      expect(layer.maskEnabled, isFalse);
      expect(layer.maskStrokes, hasLength(1));
    });
  });

  group('mask rendering', () {
    /// Composites [layer] onto a transparent canvas the same way the
    /// painters do (content in an isolated layer, mask via dstIn) and
    /// returns the result image.
    Future<ui.Image> composite(Layer layer) async {
      const size = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas =
          Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));
      const rect = Rect.fromLTWH(0, 0, size, size);
      canvas.saveLayer(rect, Paint());
      for (final d in layer.drawables) {
        d.draw(canvas, Paint());
      }
      final mask = layer.maskStrokes;
      if (mask != null && layer.maskEnabled && mask.isNotEmpty) {
        canvas.saveLayer(rect, Paint()..blendMode = BlendMode.dstIn);
        canvas.drawRect(rect, Paint()..color = Colors.white);
        for (final s in mask) {
          s.drawOnMask(canvas);
        }
        canvas.restore();
      }
      canvas.restore();
      return recorder.endRecording().toImage(size.toInt(), size.toInt());
    }

    /// Raw alpha byte (0-255) at the given pixel.
    Future<int> alphaAt(ui.Image img, int x, int y) async {
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.getUint8((y * img.width + x) * 4 + 3);
    }

    test('conceal stroke hides the painted content', () async {
      final layer = Layer(
        id: 'l1',
        name: 'paint',
        drawables: [
          Drawable(
            id: 'd1',
            points: const [Offset(8, 32), Offset(56, 32)],
            color: const Color(0xFFFF0000),
            strokeWidth: 12,
          ),
        ],
      );
      final before = await composite(layer);
      expect(await alphaAt(before, 32, 32), greaterThan(200));

      layer.maskStrokes = [
        MaskStroke(
          id: 'm1',
          points: const [Offset(40, 32)],
          width: 20,
          erase: true, // conceal
        ),
      ];
      final after = await composite(layer);
      // Inside the conceal stroke: content gone.
      expect(await alphaAt(after, 40, 32), lessThan(30));
      // Outside the stroke: content intact.
      expect(await alphaAt(after, 12, 32), greaterThan(200));
    });

    test('reveal stroke restores concealed content', () async {
      final layer = Layer(
        id: 'l1',
        name: 'paint',
        drawables: [
          Drawable(
            id: 'd1',
            points: const [Offset(8, 32), Offset(56, 32)],
            color: const Color(0xFFFF0000),
            strokeWidth: 12,
          ),
        ],
      );
      layer.maskStrokes = [
        MaskStroke(
          id: 'hide',
          points: const [Offset(24, 32), Offset(48, 32)],
          width: 24,
          erase: true,
        ),
        MaskStroke(
          id: 'reveal',
          points: const [Offset(40, 32)],
          width: 16,
          erase: false, // reveal
        ),
      ];
      final img = await composite(layer);
      // Revealed spot inside the concealed span.
      expect(await alphaAt(img, 40, 32), greaterThan(200));
      // Still-concealed spot away from the reveal stroke.
      expect(await alphaAt(img, 28, 32), lessThan(30));
    });

    test('disabled mask renders the full content', () async {
      final layer = Layer(
        id: 'l1',
        name: 'paint',
        maskEnabled: false,
        drawables: [
          Drawable(
            id: 'd1',
            points: const [Offset(8, 32), Offset(56, 32)],
            color: const Color(0xFFFF0000),
            strokeWidth: 12,
          ),
        ],
      );
      layer.maskStrokes = [
        MaskStroke(
          id: 'm1',
          points: const [Offset(32, 32)],
          width: 24,
          erase: true,
        ),
      ];
      final img = await composite(layer);
      expect(await alphaAt(img, 32, 32), greaterThan(200));
    });
  });
}
