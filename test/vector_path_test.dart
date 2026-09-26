import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/lgdf_codec.dart';
import 'package:hue_cai/services/path_text.dart';

Drawable _pathDrawable({
  List<Offset> points = const [Offset(0, 0), Offset(100, 0)],
  List<Offset?>? handles,
  bool closed = false,
}) =>
    Drawable(
      id: 'path1',
      isShape: true,
      shapeType: ShapeType.path,
      points: List<Offset>.from(points),
      curveHandles: handles,
      pathClosed: closed,
      color: const Color(0xFF000000),
      strokeWidth: 2,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Drawable.buildPath', () {
    test('straight segments measure the anchor distance', () {
      final d = _pathDrawable();
      final metric = d.buildPath().computeMetrics().first;
      expect(metric.length, closeTo(100, 0.01));
    });

    test('a handle bows the segment outwards', () {
      final straight = _pathDrawable().buildPath().computeMetrics().first.length;
      final curved = _pathDrawable(
        handles: [const Offset(0, -100), null],
      ).buildPath().computeMetrics().first.length;
      expect(curved, greaterThan(straight));
    });

    test('a closed path adds the wrap-around segment', () {
      final open = _pathDrawable(
        points: const [Offset(0, 0), Offset(100, 0), Offset(50, 80)],
      );
      final closed = _pathDrawable(
        points: const [Offset(0, 0), Offset(100, 0), Offset(50, 80)],
        closed: true,
      );
      final openLength = open.buildPath().computeMetrics().first.length;
      final closedLength = closed.buildPath().computeMetrics().first.length;
      // The closing segment is the third triangle side.
      final closingSide =
          (const Offset(50, 80) - const Offset(0, 0)).distance;
      expect(closedLength - openLength, closeTo(closingSide, 0.5));
      // Only a genuinely closed contour can be filled / hit-tested inside.
      expect(closed.buildPath().contains(const Offset(50, 20)), isTrue);
    });

    test('a single anchor yields a degenerate path, not a crash', () {
      final d = _pathDrawable(points: const [Offset(5, 5)]);
      expect(d.buildPath().computeMetrics().isEmpty, isTrue);
    });
  });

  group('PathTextLayout', () {
    List<PlacedGlyph> layoutOn(
      ui.Path path,
      String text, {
      double advance = 10,
      double offset = 0,
    }) =>
        PathTextLayout.layout(
          path: path,
          text: text,
          measure: (_) => advance,
          height: (_) => 20,
          offset: offset,
        );

    test('glyphs advance along a horizontal baseline', () {
      final path = _pathDrawable().buildPath();
      final glyphs = layoutOn(path, 'ABC');
      expect(glyphs.map((g) => g.char).join(), 'ABC');
      expect(glyphs[0].position.dx, closeTo(5, 0.01));
      expect(glyphs[1].position.dx, closeTo(15, 0.01));
      expect(glyphs[2].position.dx, closeTo(25, 0.01));
      expect(glyphs[0].position.dy, closeTo(0, 0.01));
      expect(glyphs[0].angle.abs(), lessThan(0.01));
      expect(glyphs.first.width, 10);
      expect(glyphs.first.height, 20);
    });

    test('text that runs past the baseline is truncated', () {
      final path = _pathDrawable().buildPath();
      final glyphs = layoutOn(path, 'ABCDEFGHIJKL');
      // A 100px baseline with 10px advances fits 10 centred glyphs.
      expect(glyphs, hasLength(10));
    });

    test('the start offset shifts the first glyph', () {
      final path = _pathDrawable().buildPath();
      final glyphs = layoutOn(path, 'A', offset: 20);
      expect(glyphs.single.position.dx, closeTo(25, 0.01));
    });

    test('a vertical baseline rotates the glyphs a quarter turn', () {
      final path = _pathDrawable(
        points: const [Offset(0, 0), Offset(0, 100)],
      ).buildPath();
      final glyphs = layoutOn(path, 'A');
      // Screen space: a downward baseline is a +90° clockwise rotation.
      expect(glyphs.single.angle, closeTo(3.14159265 / 2, 0.01));
      expect(glyphs.single.position.dy, closeTo(5, 0.01));
    });

    test('a diagonal baseline rotates the glyphs to the tangent', () {
      final path = _pathDrawable(
        points: const [Offset(0, 0), Offset(100, 100)],
      ).buildPath();
      final glyphs = layoutOn(path, 'A');
      expect(glyphs.single.angle, closeTo(3.14159265 / 4, 0.01));
    });

    test('empty text and degenerate paths return nothing', () {
      final path = _pathDrawable().buildPath();
      expect(layoutOn(path, ''), isEmpty);
      final single = _pathDrawable(points: const [Offset(1, 1)]).buildPath();
      expect(layoutOn(single, 'A'), isEmpty);
    });

    test('the real text painter measures a non-zero advance', () {
      final width = PathTextLayout.measure(
        'A',
        const TextStyle(fontSize: 24),
      );
      expect(width, greaterThan(0));
    });
  });

  group('path drawable serialization', () {
    test('path flags survive a JSON round-trip', () {
      final d = _pathDrawable(closed: true)
        ..textData = 'hello'
        ..textOnPath = true
        ..textPathOffset = 12.5;
      final restored = Drawable.fromJson(d.toJson());
      expect(restored.shapeType, ShapeType.path);
      expect(restored.pathClosed, isTrue);
      expect(restored.textOnPath, isTrue);
      expect(restored.textPathOffset, 12.5);
      expect(restored.textData, 'hello');
    });

    test('copyWith keeps the path flags', () {
      final d = _pathDrawable(closed: true)..textOnPath = true;
      final copy = d.copyWith(textPathOffset: 7);
      expect(copy.pathClosed, isTrue);
      expect(copy.textOnPath, isTrue);
      expect(copy.textPathOffset, 7);
      expect(copy.shapeType, ShapeType.path);
    });
  });

  group('vector layer', () {
    test('Layer JSON round-trips the vector flag', () {
      final layer = Layer(id: 'v1', name: 'vector', isVector: true);
      final restored = Layer.fromJson(layer.toJson());
      expect(restored.isVector, isTrue);
      final plain = Layer(id: 'p1', name: 'paint');
      expect(Layer.fromJson(plain.toJson()).isVector, isFalse);
    });

    test('addVectorLayer flags the new layer and selects it', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 'v', width: 32, height: 32);
      final before = pp.currentProject!.layers.length;
      pp.addVectorLayer();
      final project = pp.currentProject!;
      expect(project.layers, hasLength(before + 1));
      expect(project.currentLayer!.isVector, isTrue);
      expect(pp.isVectorLayer(project.currentLayerIndex), isTrue);
      expect(pp.isVectorLayer(0), isFalse);

      pp.setLayerVector(project.currentLayerIndex, false);
      expect(pp.isVectorLayer(project.currentLayerIndex), isFalse);
    });

    test('the LGDF package round-trips vector layers and paths', () async {
      final layer = Layer(
        id: 'vec',
        name: 'vector',
        isVector: true,
        drawables: [
          _pathDrawable(closed: true)
            ..textData = 'curve text'
            ..textOnPath = true
            ..textPathOffset = 4,
        ],
      );
      final project = Project(
        id: 'p1',
        name: 'vecproj',
        settings: const CanvasSettings(width: 64, height: 64),
        layers: [layer],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final dir = await Directory.systemTemp.createTemp('huecai_vec');
      final path = '${dir.path}/v${LgdfCodec.extension}';
      await LgdfCodec.writePackage(path, project, HistoryService());
      final loaded = await LgdfCodec.readPackage(path);

      expect(loaded, isNotNull);
      final restoredLayer = loaded!.layers.single;
      expect(restoredLayer.isVector, isTrue);
      final restoredPath = restoredLayer.drawables.single;
      expect(restoredPath.shapeType, ShapeType.path);
      expect(restoredPath.pathClosed, isTrue);
      expect(restoredPath.textOnPath, isTrue);
      expect(restoredPath.textPathOffset, 4);
      expect(restoredPath.textData, 'curve text');

      await dir.delete(recursive: true);
    });
  });
}
