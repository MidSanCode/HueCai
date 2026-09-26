import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Procedural brush tip textures. The texture modulates the alpha of each
/// stamped tip sprite, giving strokes a paper/pattern tooth.
enum BrushTexture {
  none,

  /// Random speckle, fixed seed for determinism.
  noise,

  /// Woven canvas: orthogonal sinusoidal threads.
  canvas,

  /// Regular dot grid (halftone-like).
  dots,

  /// Diagonal hatching lines.
  hatch,
}

/// Generates grayscale tip patterns and caches colorized tip sprites.
class BrushTextures {
  BrushTextures._();

  static const int patternSize = 64;

  /// Sprite cache: (texture, color) → rendered tip sprite.
  static final Map<int, ui.Image> _sprites = {};
  static final Set<int> _pending = {};

  /// Generates a grayscale pattern (0 = transparent, 255 = opaque).
  /// Pure and deterministic — safe for tests.
  static Uint8List generatePattern(BrushTexture texture,
      {int size = patternSize}) {
    final out = Uint8List(size * size);
    switch (texture) {
      case BrushTexture.none:
        out.fillRange(0, out.length, 255);
      case BrushTexture.noise:
        // Simple LCG so the pattern is stable between runs.
        var seed = 0x5DEECE66D;
        int next() {
          seed = (seed * 6364136223846793005 + 1442695040888963407) &
              0x7FFFFFFFFFFFFFFF;
          return (seed >> 33) & 0xFF;
        }

        for (var i = 0; i < out.length; i++) {
          final v = next();
          // Sparse pores: mostly opaque with scattered holes.
          out[i] = v < 70 ? (v * 2).clamp(0, 255) : 255;
        }
      case BrushTexture.canvas:
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final fx = math.sin(x * math.pi / 4.0);
            final fy = math.sin(y * math.pi / 4.0);
            final v = 0.55 + 0.45 * fx * fy;
            out[y * size + x] = (v * 255).round().clamp(0, 255);
          }
        }
      case BrushTexture.dots:
        const period = 8.0;
        const radius = 2.6;
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final dx = (x % period) - period / 2;
            final dy = (y % period) - period / 2;
            final d = math.sqrt(dx * dx + dy * dy);
            final v = (1.0 - (d / radius)).clamp(0.0, 1.0);
            out[y * size + x] = (v * 255).round();
          }
        }
      case BrushTexture.hatch:
        const period = 7.0;
        for (var y = 0; y < size; y++) {
          for (var x = 0; x < size; x++) {
            final d = ((x + y) % period) / period;
            final v = d < 0.4 ? 1.0 - d / 0.4 : 0.0;
            out[y * size + x] = (v * 255).round();
          }
        }
    }
    return out;
  }

  /// Returns the colorized tip sprite synchronously, or null while it is
  /// being decoded ([preload] is triggered as a side effect).
  static ui.Image? sprite(BrushTexture texture, Color color) {
    if (texture == BrushTexture.none) return null;
    final key = Object.hash(texture.index, color.toARGB32());
    final hit = _sprites[key];
    if (hit != null) return hit;
    preload(texture, color);
    return null;
  }

  /// Pre-renders the tip sprite into the cache (idempotent).
  static void preload(BrushTexture texture, Color color) {
    if (texture == BrushTexture.none) return;
    final key = Object.hash(texture.index, color.toARGB32());
    if (_sprites.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    final pattern = generatePattern(texture);
    final rgba = Uint8List(patternSize * patternSize * 4);
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    for (var i = 0; i < pattern.length; i++) {
      rgba[i * 4] = r;
      rgba[i * 4 + 1] = g;
      rgba[i * 4 + 2] = b;
      rgba[i * 4 + 3] = (pattern[i] * a / 255).round();
    }
    ui.decodeImageFromPixels(
      rgba,
      patternSize,
      patternSize,
      ui.PixelFormat.rgba8888,
      (img) {
        _sprites[key] = img;
        _pending.remove(key);
      },
    );
  }

  /// Evicts all cached sprites (tests / memory pressure).
  static void clearCache() {
    for (final img in _sprites.values) {
      img.dispose();
    }
    _sprites.clear();
    _pending.clear();
  }
}
