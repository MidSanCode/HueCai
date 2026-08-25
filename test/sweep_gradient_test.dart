import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that Flutter's `ui.Gradient.sweep` places colors in the same
/// screen orientation as the color wheel picker's `atan2(dy, dx)` hue math.
/// The picker maps hue 0 -> +x (right), hue 90 -> +y (bottom) on screen.
void main() {
  testWidgets('sweep gradient hue direction matches wheel picker', (tester) async {
    await tester.runAsync(() async {
      const size = 128;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final center = const Offset(size / 2, size / 2);
      // Stops: red at 0° (right), green at 90° (bottom), blue at 180° (left).
      const stops = [0.0, 0.25, 0.5];
      final shader = ui.Gradient.sweep(
        center,
        [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)],
        stops,
      );
      canvas.drawCircle(center, size / 2 - 4, Paint()..shader = shader);
      final img = await recorder.endRecording().toImage(size, size);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final bytes = data!.buffer.asUint8List();

      Color pixelAt(int x, int y) {
        final i = (y * size + x) * 4;
        return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
      }

      Color right = pixelAt(size - 8, size ~/ 2); // +x, hue 0
      Color bottom = pixelAt(size ~/ 2, size - 8); // +y (down), hue 90
      Color left = pixelAt(8, size ~/ 2); // -x, hue 180

      debugPrint('RIGHT=$right BOTTOM=$bottom LEFT=$left');

      // Right should be strongly red, bottom strongly green, left strongly blue.
      expect(right.r > 0.6 && right.g < 0.3, isTrue,
          reason: 'right (0°) should be red, got $right');
      expect(bottom.g > 0.6 && bottom.r < 0.3, isTrue,
          reason: 'bottom (90°) should be green, got $bottom');
      expect(left.b > 0.6 && left.r < 0.3, isTrue,
          reason: 'left (180°) should be blue, got $left');
    });
  });
}