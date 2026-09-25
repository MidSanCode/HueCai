import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/brush.dart';
import 'package:hue_cai/models/drawable.dart';

Future<ui.Image> _render(Drawable d, {int w = 120, int h = 120}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  d.draw(c, Paint());
  return recorder.endRecording().toImage(w, h);
}

Future<bool> _hasPaint(ui.Image img) async {
  final data = await img.toByteData();
  if (data == null) return false;
  final b = data.buffer.asUint8List();
  for (var i = 3; i < b.length; i += 4) {
    if (b[i] > 0) return true;
  }
  return false;
}

Drawable _stroke(BrushType type) => Drawable(
      id: 's1',
      points: const [Offset(20, 60), Offset(60, 60), Offset(100, 60)],
      widths: const [20, 20, 20],
      color: const Color(0xFF3366FF),
      strokeWidth: 20,
      brushType: type,
    );

void main() {
  group('spray / bristle brushes', () {
    test('spray stroke paints pixels', () async {
      final img = await _render(_stroke(BrushType.spray));
      expect(await _hasPaint(img), isTrue);
    });

    test('bristle stroke paints pixels', () async {
      final img = await _render(_stroke(BrushType.bristle));
      expect(await _hasPaint(img), isTrue);
    });

    test('rendering is deterministic per drawable id', () async {
      // Two draws of the same drawable produce identical alpha coverage.
      Future<int> coverage() async {
        final img = await _render(_stroke(BrushType.spray));
        final data = await img.toByteData();
        final b = data!.buffer.asUint8List();
        var n = 0;
        for (var i = 3; i < b.length; i += 4) {
          if (b[i] > 0) n++;
        }
        return n;
      }

      expect(await coverage(), await coverage());
    });
  });

  group('per-point colors (mixing brush)', () {
    test('colorValues round-trip through JSON', () {
      final d = Drawable(
        id: 'm1',
        points: const [Offset(0, 0), Offset(10, 10)],
        color: const Color(0xFFFF0000),
        strokeWidth: 4,
        colorValues: [0xFFFF0000, 0xFF00FF00],
      );
      final restored = Drawable.fromJson(d.toJson());
      expect(restored.colorValues, [0xFFFF0000, 0xFF00FF00]);
    });

    test('mixed-color stroke paints pixels', () async {
      final d = Drawable(
        id: 'm2',
        points: const [Offset(20, 60), Offset(60, 60), Offset(100, 60)],
        widths: const [12, 12, 12],
        color: const Color(0xFFFF0000),
        strokeWidth: 12,
        colorValues: [0xFFFF0000, 0xFF880088, 0xFF0000FF],
      );
      final img = await _render(d);
      expect(await _hasPaint(img), isTrue);
    });
  });

  group('brush model', () {
    test('defaults include spray and bristle', () {
      final types = Brush.defaults().map((b) => b.type).toSet();
      expect(types, contains(BrushType.spray));
      expect(types, contains(BrushType.bristle));
    });

    test('mix defaults to 0 and copies through copyWith', () {
      final b = Brush(type: BrushType.spray, nameKey: 'x');
      expect(b.mix, 0);
      expect(b.copyWith(mix: 0.5).mix, 0.5);
    });
  });
}
