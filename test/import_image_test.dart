import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/project_service.dart';

/// Builds a small solid-red PNG in memory to act as an "imported image".
Future<Uint8List> _solidPng(int w, int h, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  final img = await recorder.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Reads back the centre pixel of what a painter would produce.
Future<Color> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData();
  final bytes = data!.buffer.asUint8List();
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
}

Project _blankProject(int w, int h, {int bg = 0xFFFFFFFF}) => Project(
      id: 'p1',
      name: 'test',
      settings: CanvasSettings(width: w, height: h, backgroundColor: bg),
      layers: [Layer(id: 'l1', name: 'Layer 1')],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('import image into canvas', () {
    test('a decoded layer image actually paints its pixels', () async {
      // This mirrors what importImageToCanvas stores on the layer.
      final png = await _solidPng(40, 30, const Color(0xFFFF0000));
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      expect(img.width, 40);
      expect(img.height, 30);

      final project = _blankProject(100, 100);
      project.layers.add(Layer(
        id: 'l2',
        name: 'imported',
        image: img,
        imageOffset: Offset(
          (100 - img.width) / 2,
          (100 - img.height) / 2,
        ),
      ));

      // Replicate the painter's per-layer draw for a layer carrying an image.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 100, 100));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = Color(project.settings.backgroundColor),
      );
      for (final layer in project.layers) {
        if (!layer.visible) continue;
        if (layer.image != null) {
          final li = layer.image!;
          canvas.save();
          canvas.translate(layer.imageOffset.dx + li.width / 2,
              layer.imageOffset.dy + li.height / 2);
          canvas.rotate(layer.imageRotation);
          final flipX = layer.imageFlipH ? -1.0 : 1.0;
          final flipY = layer.imageFlipV ? -1.0 : 1.0;
          canvas.scale(layer.imageScale * flipX, layer.imageScale * flipY);
          canvas.drawImageRect(
            li,
            Rect.fromLTWH(0, 0, li.width.toDouble(), li.height.toDouble()),
            Rect.fromLTWH(-li.width / 2, -li.height / 2, li.width.toDouble(),
                li.height.toDouble()),
            Paint()..color = Colors.white.withValues(alpha: layer.opacity),
          );
          canvas.restore();
        }
      }
      final out = await recorder.endRecording().toImage(100, 100);

      // Centre should show the imported red image, not black and not the
      // white background.
      final centre = await _pixelAt(out, 50, 50);
      expect(centre.r, greaterThan(0.9), reason: 'centre should be red');
      expect(centre.g, lessThan(0.1));
      expect(centre.b, lessThan(0.1));

      // A corner stays background (white).
      final corner = await _pixelAt(out, 2, 2);
      expect(corner.r, greaterThan(0.9));
      expect(corner.g, greaterThan(0.9));
      expect(corner.b, greaterThan(0.9));
    });

    test('stores the imported bitmap so it renders and survives save/reload',
        () async {
      // importImage() is supposed to rasterize the imported picture into the
      // project. Verify it produces something the canvas can actually show.
      final dir = await Directory.systemTemp.createTemp('huecai_import');
      final srcPath = '${dir.path}/pic.png';
      await File(srcPath).writeAsBytes(
        await _solidPng(20, 20, const Color(0xFF0000FF)),
      );

      final pp = ProjectProvider();
      await pp.importImage(srcPath);
      final project = pp.currentProject;
      expect(project, isNotNull, reason: 'importImage should create a project');

      final layer = project!.layers.last;
      // ignore: avoid_print
      print('layer.image=${layer.image != null} '
          'imagePath=${layer.imagePath} '
          'drawables=${layer.drawables.length}');

      expect(
        layer.image,
        isNotNull,
        reason: 'the imported bitmap must be stored on the layer so the '
            'canvas has something to render',
      );
      expect(layer.image!.width, 20);
      expect(layer.image!.height, 20);

      // And the imported pixels must survive the save/reload round-trip.
      // Saving always produces the new LGDF `.hcproj` container.
      final service = ProjectService();
      final tmp = await Directory.systemTemp.createTemp('huecai_save');
      final saved = await service.saveProject(
        project,
        HistoryService(),
        filePath: '${tmp.path}/roundtrip.hcproj',
      );
      final reloaded = await service.loadProject(saved);
      expect(reloaded, isNotNull);
      expect(
        reloaded!.layers.last.image,
        isNotNull,
        reason: 'layer pixels must be restored from the archive',
      );

      await dir.delete(recursive: true);
      await tmp.delete(recursive: true);
    });
  });
}
