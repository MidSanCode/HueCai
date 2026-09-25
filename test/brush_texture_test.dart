import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/services/brush_texture.dart';
import 'package:flutter/material.dart';

void main() {
  group('BrushTextures.generatePattern', () {
    test('returns a size*size grayscale buffer', () {
      for (final t in BrushTexture.values) {
        final p = BrushTextures.generatePattern(t, size: 32);
        expect(p.length, 32 * 32);
      }
    });

    test('none is fully opaque', () {
      final p = BrushTextures.generatePattern(BrushTexture.none, size: 16);
      expect(p.every((v) => v == 255), isTrue);
    });

    test('noise is deterministic', () {
      final a = BrushTextures.generatePattern(BrushTexture.noise, size: 16);
      final b = BrushTextures.generatePattern(BrushTexture.noise, size: 16);
      expect(a, orderedEquals(b));
      // And it actually contains pores (values below 255).
      expect(a.any((v) => v < 255), isTrue);
    });

    test('canvas pattern varies periodically in both axes', () {
      final p = BrushTextures.generatePattern(BrushTexture.canvas, size: 32);
      // Not flat.
      expect(p.toSet().length, greaterThan(4));
    });

    test('dots pattern has regular transparent gaps', () {
      final p = BrushTextures.generatePattern(BrushTexture.dots, size: 32);
      final zeros = p.where((v) => v == 0).length;
      expect(zeros, greaterThan(32)); // several gaps between dots
    });

    test('hatch pattern produces diagonal bands', () {
      final p = BrushTextures.generatePattern(BrushTexture.hatch, size: 32);
      // Pixel (x, y) and (x+7, y) should match (period 7 along the diagonal).
      expect(p[2 * 32 + 3], p[2 * 32 + 10]);
    });
  });

  group('Drawable tipTexture', () {
    test('defaults to none and survives JSON round-trip', () {
      final d = Drawable(id: 'a', points: const [Offset(0, 0)]);
      expect(d.tipTexture, BrushTexture.none);

      final textured = Drawable(
        id: 'b',
        points: const [Offset(0, 0), Offset(5, 5)],
        tipTexture: BrushTexture.canvas,
      );
      final restored = Drawable.fromJson(textured.toJson());
      expect(restored.tipTexture, BrushTexture.canvas);
    });

    test('copyWith carries the texture', () {
      final d = Drawable(
        id: 'a',
        points: const [Offset(0, 0)],
        tipTexture: BrushTexture.noise,
      );
      expect(d.copyWith(color: Colors.red).tipTexture, BrushTexture.noise);
    });
  });
}
