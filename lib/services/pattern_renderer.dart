import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/pattern.dart';

/// Renders [PatternSpec] definitions into tileable RGBA tiles.
///
/// The pixel content is axis-aligned and periodic: [generate] picks a tile
/// size that is an exact multiple of the spec's period, so `TileMode.repeated`
/// wraps without a seam. Rotation lives in the shader matrix instead (see
/// [shaderFor]), which keeps rotated patterns seamless too.
class PatternRenderer {
  PatternRenderer._();

  /// Preferred tile edge length; the real size is rounded up to a multiple of
  /// the period (see [tileSizeFor]).
  static const int preferredTileSize = 64;

  /// Hard cap so a huge spacing cannot allocate a giant tile.
  static const int maxTileSize = 512;

  static final Map<String, ui.Image> _images = {};
  static final Map<String, Completer<ui.Image>> _completers = {};

  /// Cache key: every field that changes the pixels.
  static String cacheKey(PatternSpec spec) => Object.hash(
        spec.kind.index,
        spec.spacing,
        spec.thickness,
        spec.density,
        spec.foreground.toARGB32(),
        spec.background.toARGB32(),
      ).toString();

  /// Period used by [generate]: at least 2px, at most [maxTileSize].
  static int periodFor(PatternSpec spec) =>
      spec.spacing.round().clamp(2, maxTileSize);

  /// Tile edge length: the preferred size rounded up to a whole number of
  /// periods, so the tile wraps onto itself exactly.
  static int tileSizeFor(PatternSpec spec) {
    final period = periodFor(spec);
    if (period >= preferredTileSize) return period;
    final multiple = (preferredTileSize / period).ceil();
    return period * multiple;
  }

  /// Generates the RGBA tile for [spec]. Pure and deterministic.
  static Uint8List generate(PatternSpec spec) {
    final size = tileSizeFor(spec);
    final period = periodFor(spec);
    final fg = spec.foreground;
    final bg = spec.background;
    final out = Uint8List(size * size * 4);
    final thickness = spec.thickness.clamp(0.1, size.toDouble());
    final density = spec.density.clamp(0.0, 1.0);

    // Deterministic noise (LCG), independent of platform RNG.
    var seed = 0x2545F4914F6CDD1D;
    int nextByte() {
      seed = (seed * 6364136223846793005 + 1442695040888963407) &
          0x7FFFFFFFFFFFFFFF;
      return (seed >> 33) & 0xFF;
    }

    // Positional hash so the noise field is periodic in the tile (a
    // sequential RNG would break the wrap-around seam).
    int hash2(int x, int y) {
      var h = x * 374761393 + y * 668265263;
      h = (h ^ (h >> 13)) * 1274126177;
      return (h ^ (h >> 16)) & 0xFF;
    }

    // Paper: a coarse value-noise lattice sampled with smooth interpolation.
    // The lattice is indexed modulo its own size, so it wraps exactly.
    final paperCells = math.max(2, size ~/ 8);
    final paperGrid = <double>[
      for (var i = 0; i < paperCells * paperCells; i++) nextByte() / 255.0,
    ];
    double paperAt(int x, int y) {
      const cell = 8;
      final gx = (x ~/ cell) % paperCells;
      final gy = (y ~/ cell) % paperCells;
      double corner(int cx, int cy) =>
          paperGrid[((cy % paperCells) * paperCells + (cx % paperCells)) %
              paperGrid.length];
      final fx = (x % cell) / cell;
      final fy = (y % cell) / cell;
      // Smoothstep weights keep the fibres soft.
      final sx = fx * fx * (3 - 2 * fx);
      final sy = fy * fy * (3 - 2 * fy);
      final top = corner(gx, gy) * (1 - sx) + corner(gx + 1, gy) * sx;
      final bottom =
          corner(gx, gy + 1) * (1 - sx) + corner(gx + 1, gy + 1) * sx;
      return top * (1 - sy) + bottom * sy;
    }

    double coverage(int x, int y) {
      switch (spec.kind) {
        case PatternKind.dots:
          final cx = (x % period) - period / 2 + 0.5;
          final cy = (y % period) - period / 2 + 0.5;
          final d = math.sqrt(cx * cx + cy * cy);
          // Solid core with a one-pixel anti-aliased edge.
          return ((thickness - d) + 0.5).clamp(0.0, 1.0);
        case PatternKind.lines:
          final d = (x % period).toDouble();
          return (thickness - math.min(d, period - d) + 0.5).clamp(0.0, 1.0);
        case PatternKind.cross:
          final dx = (x % period).toDouble();
          final dy = (y % period).toDouble();
          final hx = (thickness - math.min(dx, period - dx) + 0.5)
              .clamp(0.0, 1.0);
          final hy = (thickness - math.min(dy, period - dy) + 0.5)
              .clamp(0.0, 1.0);
          return math.max(hx, hy);
        case PatternKind.checker:
          final half = period / 2;
          final on = ((x / half).floor() + (y / half).floor()) % 2 == 0;
          return on ? 1.0 : 0.0;
        case PatternKind.grid:
          final dx = (x % period).toDouble();
          final dy = (y % period).toDouble();
          final hx = (thickness - math.min(dx, period - dx) + 0.5)
              .clamp(0.0, 1.0);
          final hy = (thickness - math.min(dy, period - dy) + 0.5)
              .clamp(0.0, 1.0);
          return math.max(hx, hy);
        case PatternKind.noise:
          // density scales how many pixels carry ink.
          final v = hash2(x, y) / 255.0;
          return v < density ? 1.0 : 0.0;
        case PatternKind.paper:
          final v = paperAt(x, y);
          return ((v - (1 - density)) / math.max(0.05, density))
              .clamp(0.0, 1.0);
      }
    }

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final a = coverage(x, y);
        final i = (y * size + x) * 4;
        out[i] = (fg.r * 255).round().clamp(0, 255);
        out[i + 1] = (fg.g * 255).round().clamp(0, 255);
        out[i + 2] = (fg.b * 255).round().clamp(0, 255);
        // Blend ink over the background by coverage, keeping the
        // background's own alpha so transparent patterns stay transparent.
        final fgA = fg.a * a;
        final bgA = bg.a;
        final outA = fgA + bgA * (1 - fgA);
        if (outA <= 0) {
          out[i + 3] = 0;
          continue;
        }
        double channel(double fgC, double bgC) =>
            (fgC * fgA + bgC * bgA * (1 - fgA)) / outA;
        out[i] = (channel(fg.r, bg.r) * 255).round().clamp(0, 255);
        out[i + 1] = (channel(fg.g, bg.g) * 255).round().clamp(0, 255);
        out[i + 2] = (channel(fg.b, bg.b) * 255).round().clamp(0, 255);
        out[i + 3] = (outA * 255).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// The cached tile image, or null while it is being decoded.
  ///
  /// A null result also schedules the decode, so the next paint can use it —
  /// the same "preload then repaint" contract the brush tip textures use.
  static ui.Image? imageFor(PatternSpec spec) {
    final key = cacheKey(spec);
    final hit = _images[key];
    if (hit != null) return hit;
    preload(spec);
    return null;
  }

  /// Starts decoding the tile for [spec] if it is not cached yet.
  static void preload(PatternSpec spec) {
    ensure(spec);
  }

  /// Decodes the tile and resolves once it is cached (used before committing
  /// a pattern fill, so the first paint already shows the pattern).
  static Future<ui.Image> ensure(PatternSpec spec) {
    final key = cacheKey(spec);
    final hit = _images[key];
    if (hit != null) return Future.value(hit);
    final inFlight = _completers[key];
    if (inFlight != null) return inFlight.future;

    final completer = Completer<ui.Image>();
    _completers[key] = completer;
    final size = tileSizeFor(spec);
    final rgba = generate(spec);
    ui.decodeImageFromPixels(
      rgba,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (image) {
        _images[key] = image;
        _completers.remove(key);
        if (!completer.isCompleted) completer.complete(image);
      },
    );
    return completer.future;
  }

  /// Repeating shader for [spec], rotated by [spec.angle] about [center]
  /// (pass the filled region's centre so the phase stays stable per fill).
  static ui.Shader? shaderFor(PatternSpec spec, {Offset? center}) {
    final image = imageFor(spec);
    if (image == null) return null;
    final matrix = _transform(spec.angle, center ?? Offset.zero);
    return ui.ImageShader(
      image,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      matrix,
    );
  }

  /// Column-major 4x4 matrix for a 2D rotation about [pivot].
  ///
  /// Built by hand so this service only needs `dart:ui` + painting.
  static Float64List _transform(double angle, Offset pivot) {
    final m = Float64List(16);
    m[0] = 1;
    m[5] = 1;
    m[10] = 1;
    m[15] = 1;
    if (angle == 0) return m;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    // Translate(pivot) · Rotate(angle) · Translate(-pivot).
    final tx = pivot.dx - (pivot.dx * cos - pivot.dy * sin);
    final ty = pivot.dy - (pivot.dx * sin + pivot.dy * cos);
    m[0] = cos;
    m[1] = sin;
    m[4] = -sin;
    m[5] = cos;
    m[12] = tx;
    m[13] = ty;
    return m;
  }

  /// Drops every cached tile (tests, or after a big import).
  static void clearCache() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _completers.clear();
  }
}
