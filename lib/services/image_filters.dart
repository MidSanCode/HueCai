import 'dart:math' as math;
import 'dart:typed_data';

import 'filter_registry.dart';

/// A decoded 32-bit RGBA image (straight alpha, 4 bytes per pixel).
class RgbaImage {
  final int width;
  final int height;

  /// Length must be `width * height * 4`.
  final Uint8List pixels;

  RgbaImage(this.width, this.height, this.pixels) {
    assert(pixels.length == width * height * 4);
  }

  RgbaImage.blank(this.width, this.height)
      : pixels = Uint8List(width * height * 4);

  RgbaImage copy() => RgbaImage(width, height, Uint8List.fromList(pixels));
}

/// A serializable filter description for adjustment layers: the filter kind
/// plus its parameters, applicable to any raster via [apply].
class AdjustmentSpec {
  final String kind; // gaussianBlur | unsharpMask | levels | curves | hueSaturation
  final Map<String, dynamic> params;

  const AdjustmentSpec(this.kind, this.params);

  static const kinds = [
    'gaussianBlur',
    'unsharpMask',
    'levels',
    'curves',
    'hueSaturation',
  ];

  /// Runs the described filter. Everything registered in [FilterRegistry]
  /// is supported; the legacy switch below keeps old projects loading even
  /// if a filter is ever removed from the registry.
  RgbaImage apply(RgbaImage src) {
    if (FilterRegistry.byKind(kind) != null) {
      return FilterRegistry.apply(kind, src, params);
    }
    return switch (kind) {
      'gaussianBlur' => ImageFilters.gaussianBlur(
          src, (params['radius'] as num?)?.toDouble() ?? 5),
      'unsharpMask' => ImageFilters.unsharpMask(
          src,
          (params['radius'] as num?)?.toDouble() ?? 2,
          (params['amount'] as num?)?.toDouble() ?? 0.8,
          threshold: (params['threshold'] as num?)?.toInt() ?? 0,
        ),
      'levels' => ImageFilters.levels(
          src,
          inBlack: (params['in_black'] as num?)?.toInt() ?? 0,
          inWhite: (params['in_white'] as num?)?.toInt() ?? 255,
          gamma: (params['gamma'] as num?)?.toDouble() ?? 1,
        ),
      'curves' => ImageFilters.curves(src, curvePoints),
      'hueSaturation' => ImageFilters.hueSaturation(
          src,
          hueShift: (params['hue'] as num?)?.toDouble() ?? 0,
          saturationScale: (params['saturation'] as num?)?.toDouble() ?? 1,
          lightnessScale: (params['lightness'] as num?)?.toDouble() ?? 1,
        ),
      _ => src.copy(),
    };
  }

  List<({double x, double y})> get curvePoints =>
      ((params['points'] as List?) ?? const [])
          .map((p) => (
                x: (p['x'] as num).toDouble(),
                y: (p['y'] as num).toDouble(),
              ))
          .toList();

  Map<String, dynamic> toJson() => {'kind': kind, 'params': params};

  factory AdjustmentSpec.fromJson(Map<String, dynamic> json) =>
      AdjustmentSpec(json['kind'] as String,
          (json['params'] as Map).cast<String, dynamic>());
}

/// Pure-pixel image filters. Every function returns a new [RgbaImage] and
/// never mutates its input, so they are trivially testable and composable.
class ImageFilters {
  ImageFilters._();

  // ------------------------------------------------------------ blur / USM

  /// Gaussian blur via three separable box-blur passes (a close Gaussian
  /// approximation, O(n) regardless of [radius]).
  static RgbaImage gaussianBlur(RgbaImage src, double radius) {
    if (radius <= 0) return src.copy();
    // Box size for 3-pass Gaussian approximation.
    final sigma = radius;
    final wIdeal = math.sqrt((12 * sigma * sigma / 3) + 1);
    var wl = wIdeal.floor();
    if (wl % 2 == 0) wl--;
    final wu = wl + 2;
    final mIdeal = (12 * sigma * sigma - 3 * wl * wl - 12 * wl - 9) /
        (-4 * wl - 4);
    final m = mIdeal.round();
    final sizes = [for (var i = 0; i < 3; i++) i < m ? wl : wu];

    var current = src;
    for (final size in sizes) {
      current = _boxBlur(current, size);
    }
    return current;
  }

  /// USM sharpening: `src + (src - blur(src)) * amount`, with a threshold to
  /// leave low-contrast noise alone.
  static RgbaImage unsharpMask(
    RgbaImage src,
    double radius,
    double amount, {
    int threshold = 0,
  }) {
    final blurred = gaussianBlur(src, radius);
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i++) {
      if (i % 4 == 3) {
        out.pixels[i] = src.pixels[i]; // alpha untouched
        continue;
      }
      final diff = src.pixels[i] - blurred.pixels[i];
      final applied = diff.abs() < threshold ? 0 : diff * amount;
      out.pixels[i] = (src.pixels[i] + applied).round().clamp(0, 255);
    }
    return out;
  }

  /// One pass of a separable box blur (horizontal + vertical), alpha-aware.
  static RgbaImage _boxBlur(RgbaImage src, int boxSize) {
    final tmp = _boxBlurHorizontal(src, boxSize);
    return _boxBlurVertical(tmp, boxSize);
  }

  static RgbaImage _boxBlurHorizontal(RgbaImage src, int size) {
    final w = src.width, h = src.height;
    final out = RgbaImage.blank(w, h);
    final half = size ~/ 2;
    for (var y = 0; y < h; y++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var x = -half; x <= half; x++) {
        final cx = x.clamp(0, w - 1);
        final i = (y * w + cx) * 4;
        r += src.pixels[i];
        g += src.pixels[i + 1];
        b += src.pixels[i + 2];
        a += src.pixels[i + 3];
      }
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        out.pixels[o] = r ~/ size;
        out.pixels[o + 1] = g ~/ size;
        out.pixels[o + 2] = b ~/ size;
        out.pixels[o + 3] = a ~/ size;
        final xAdd = (x + half + 1).clamp(0, w - 1);
        final xSub = (x - half).clamp(0, w - 1);
        final ia = (y * w + xAdd) * 4;
        final isb = (y * w + xSub) * 4;
        r += src.pixels[ia] - src.pixels[isb];
        g += src.pixels[ia + 1] - src.pixels[isb + 1];
        b += src.pixels[ia + 2] - src.pixels[isb + 2];
        a += src.pixels[ia + 3] - src.pixels[isb + 3];
      }
    }
    return out;
  }

  static RgbaImage _boxBlurVertical(RgbaImage src, int size) {
    final w = src.width, h = src.height;
    final out = RgbaImage.blank(w, h);
    final half = size ~/ 2;
    for (var x = 0; x < w; x++) {
      var r = 0, g = 0, b = 0, a = 0;
      for (var y = -half; y <= half; y++) {
        final cy = y.clamp(0, h - 1);
        final i = (cy * w + x) * 4;
        r += src.pixels[i];
        g += src.pixels[i + 1];
        b += src.pixels[i + 2];
        a += src.pixels[i + 3];
      }
      for (var y = 0; y < h; y++) {
        final o = (y * w + x) * 4;
        out.pixels[o] = r ~/ size;
        out.pixels[o + 1] = g ~/ size;
        out.pixels[o + 2] = b ~/ size;
        out.pixels[o + 3] = a ~/ size;
        final yAdd = (y + half + 1).clamp(0, h - 1);
        final ySub = (y - half).clamp(0, h - 1);
        final ia = (yAdd * w + x) * 4;
        final isb = (ySub * w + x) * 4;
        r += src.pixels[ia] - src.pixels[isb];
        g += src.pixels[ia + 1] - src.pixels[isb + 1];
        b += src.pixels[ia + 2] - src.pixels[isb + 2];
        a += src.pixels[ia + 3] - src.pixels[isb + 3];
      }
    }
    return out;
  }

  // --------------------------------------------------------------- levels

  /// Levels adjustment: remaps [inBlack]..[inWhite] to [outBlack]..[outWhite]
  /// with a [gamma] curve. All inputs are 0..255 except gamma (0.1..10).
  static RgbaImage levels(
    RgbaImage src, {
    int inBlack = 0,
    int inWhite = 255,
    double gamma = 1.0,
    int outBlack = 0,
    int outWhite = 255,
  }) {
    final lut = levelsLut(
      inBlack: inBlack,
      inWhite: inWhite,
      gamma: gamma,
      outBlack: outBlack,
      outWhite: outWhite,
    );
    return applyLut(src, lut);
  }

  /// Builds the 256-entry levels lookup table.
  static Uint8List levelsLut({
    int inBlack = 0,
    int inWhite = 255,
    double gamma = 1.0,
    int outBlack = 0,
    int outWhite = 255,
  }) {
    final lut = Uint8List(256);
    final span = (inWhite - inBlack).clamp(1, 255);
    final invGamma = 1.0 / gamma.clamp(0.1, 10.0);
    for (var i = 0; i < 256; i++) {
      final t = ((i - inBlack) / span).clamp(0.0, 1.0);
      final curved = math.pow(t, invGamma).toDouble();
      lut[i] = (outBlack + curved * (outWhite - outBlack))
          .round()
          .clamp(0, 255);
    }
    return lut;
  }

  /// Applies one 256-entry LUT to the RGB channels (alpha untouched).
  static RgbaImage applyLut(RgbaImage src, Uint8List lut) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i++) {
      out.pixels[i] = (i % 4 == 3) ? src.pixels[i] : lut[src.pixels[i]];
    }
    return out;
  }

  // --------------------------------------------------------------- curves

  /// Curves adjustment: [points] are (x, y) control points in 0..255 space,
  /// interpolated monotonically (Catmull-Rom) into a 256-entry LUT.
  static RgbaImage curves(RgbaImage src, List<({double x, double y})> points) {
    return applyLut(src, curvesLut(points));
  }

  /// Builds a 256-entry LUT from curve control points.
  static Uint8List curvesLut(List<({double x, double y})> points) {
    final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = _evalCurve(sorted, i.toDouble()).round().clamp(0, 255);
    }
    return lut;
  }

  static double _evalCurve(List<({double x, double y})> pts, double x) {
    if (pts.isEmpty) return x;
    if (x <= pts.first.x) return pts.first.y;
    if (x >= pts.last.x) return pts.last.y;
    // Find the segment containing x.
    var i = 0;
    while (i < pts.length - 1 && pts[i + 1].x < x) {
      i++;
    }
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1];
    final t = (x - p1.x) / (p2.x - p1.x).clamp(1e-6, double.infinity);
    // Catmull-Rom spline.
    final t2 = t * t;
    final t3 = t2 * t;
    return 0.5 *
        ((2 * p1.y) +
            (-p0.y + p2.y) * t +
            (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
            (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3);
  }

  // -------------------------------------------------------- hue/saturation

  /// Hue/saturation/lightness adjustment.
  ///
  /// [hueShift] is in degrees (-180..180), [saturationScale] and
  /// [lightnessScale] are multipliers (1 = unchanged).
  static RgbaImage hueSaturation(
    RgbaImage src, {
    double hueShift = 0,
    double saturationScale = 1.0,
    double lightnessScale = 1.0,
  }) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final r = src.pixels[i] / 255.0;
      final g = src.pixels[i + 1] / 255.0;
      final b = src.pixels[i + 2] / 255.0;
      final hsl = _rgbToHsl(r, g, b);
      var h = (hsl.$1 + hueShift) % 360.0;
      if (h < 0) h += 360.0;
      final s = (hsl.$2 * saturationScale).clamp(0.0, 1.0);
      final l = (hsl.$3 * lightnessScale).clamp(0.0, 1.0);
      final (nr, ng, nb) = _hslToRgb(h, s, l);
      out.pixels[i] = (nr * 255).round().clamp(0, 255);
      out.pixels[i + 1] = (ng * 255).round().clamp(0, 255);
      out.pixels[i + 2] = (nb * 255).round().clamp(0, 255);
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  static (double, double, double) _rgbToHsl(double r, double g, double b) {
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final l = (max + min) / 2;
    if (max == min) return (0, 0, l);
    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    double h;
    if (max == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return (h * 60, s, l);
  }

  static (double, double, double) _hslToRgb(double h, double s, double l) {
    if (s == 0) return (l, l, l);
    double hue2rgb(double p, double q, double t) {
      var tt = t;
      if (tt < 0) tt += 1;
      if (tt > 1) tt -= 1;
      if (tt < 1 / 6) return p + (q - p) * 6 * tt;
      if (tt < 1 / 2) return q;
      if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    final hn = h / 360;
    return (
      hue2rgb(p, q, hn + 1 / 3),
      hue2rgb(p, q, hn),
      hue2rgb(p, q, hn - 1 / 3),
    );
  }

  // ==================================================== tone / exposure ===

  static double _lum(int r, int g, int b) =>
      (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

  /// Brightness (−1..1) and contrast (−1..1) around mid gray.
  static RgbaImage brightnessContrast(
    RgbaImage src,
    double brightness,
    double contrast,
  ) {
    final b = brightness * 255.0;
    final c = contrast >= 0 ? 1.0 / (1.0 - contrast).clamp(0.05, 1.0) : 1.0 + contrast;
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      final v = ((i - 127.5) * c + 127.5) + b;
      lut[i] = v.round().clamp(0, 255);
    }
    return applyLut(src, lut);
  }

  /// Photographic exposure in stops (multiplies linear-ish values by 2^stops).
  static RgbaImage exposure(RgbaImage src, double stops) {
    final factor = math.pow(2.0, stops).toDouble();
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = (i * factor).round().clamp(0, 255);
    }
    return applyLut(src, lut);
  }

  /// Per-channel gamma (1 = unchanged, <1 brighter midtones).
  static RgbaImage gamma(RgbaImage src, double g) {
    final safe = g.clamp(0.05, 5.0);
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = (math.pow(i / 255.0, 1.0 / safe) * 255).round().clamp(0, 255);
    }
    return applyLut(src, lut);
  }

  static RgbaImage invert(RgbaImage src) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i++) {
      out.pixels[i] = (i % 4 == 3) ? src.pixels[i] : 255 - src.pixels[i];
    }
    return out;
  }

  /// Solarize: values above [threshold] are inverted.
  static RgbaImage solarize(RgbaImage src, int threshold) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i++) {
      if (i % 4 == 3) {
        out.pixels[i] = src.pixels[i];
        continue;
      }
      final v = src.pixels[i];
      out.pixels[i] = v > threshold ? 255 - v : v;
    }
    return out;
  }

  /// Blends toward luminance: amount 0 = original, 1 = grayscale.
  static RgbaImage desaturate(RgbaImage src, double amount) {
    final a = amount.clamp(0.0, 1.0);
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final r = src.pixels[i], g = src.pixels[i + 1], b = src.pixels[i + 2];
      final l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      out.pixels[i] = (r + (l - r) * a).round().clamp(0, 255);
      out.pixels[i + 1] = (g + (l - g) * a).round().clamp(0, 255);
      out.pixels[i + 2] = (b + (l - b) * a).round().clamp(0, 255);
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Quantizes each channel to [levels] steps.
  static RgbaImage posterize(RgbaImage src, int levels) {
    final n = levels.clamp(2, 64);
    final step = 255.0 / (n - 1);
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = ((i / step).round() * step).round().clamp(0, 255);
    }
    return applyLut(src, lut);
  }

  /// Hard black/white threshold on luminance.
  static RgbaImage threshold(RgbaImage src, int level) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final l = _lum(src.pixels[i], src.pixels[i + 1], src.pixels[i + 2]) * 255;
      final v = l >= level ? 255 : 0;
      out.pixels[i] = v;
      out.pixels[i + 1] = v;
      out.pixels[i + 2] = v;
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Stretches each channel to the full 0..255 range.
  static RgbaImage normalize(RgbaImage src) {
    final lo = [255, 255, 255];
    final hi = [0, 0, 0];
    for (var i = 0; i < src.pixels.length; i += 4) {
      if (src.pixels[i + 3] == 0) continue;
      for (var c = 0; c < 3; c++) {
        final v = src.pixels[i + c];
        if (v < lo[c]) lo[c] = v;
        if (v > hi[c]) hi[c] = v;
      }
    }
    final luts = List.generate(3, (c) {
      final lut = Uint8List(256);
      final range = hi[c] - lo[c];
      for (var i = 0; i < 256; i++) {
        lut[i] = range <= 0
            ? i
            : (((i - lo[c]) / range) * 255).round().clamp(0, 255);
      }
      return lut;
    });
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        out.pixels[i + c] = luts[c][src.pixels[i + c]];
      }
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Histogram equalization on luminance (contrast stretch by frequency).
  static RgbaImage equalize(RgbaImage src) {
    final hist = List<int>.filled(256, 0);
    var count = 0;
    for (var i = 0; i < src.pixels.length; i += 4) {
      if (src.pixels[i + 3] == 0) continue;
      final l =
          _lum(src.pixels[i], src.pixels[i + 1], src.pixels[i + 2]).round();
      hist[l.clamp(0, 255)]++;
      count++;
    }
    if (count == 0) return src.copy();
    final lut = Uint8List(256);
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      lut[i] = ((acc / count) * 255).round().clamp(0, 255);
    }
    return applyLut(src, lut);
  }

  /// Simple white balance: [temperature] −1..1 warms/cools, [tint] −1..1
  /// shifts green↔magenta.
  static RgbaImage whiteBalance(RgbaImage src, double temperature, double tint) {
    final rGain = 1.0 + temperature * 0.3;
    final bGain = 1.0 - temperature * 0.3;
    final gGain = 1.0 - tint * 0.3;
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      out.pixels[i] = (src.pixels[i] * rGain).round().clamp(0, 255);
      out.pixels[i + 1] = (src.pixels[i + 1] * gGain).round().clamp(0, 255);
      out.pixels[i + 2] = (src.pixels[i + 2] * bGain).round().clamp(0, 255);
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Three-way color balance: nine gains (−1..1) for shadows / midtones /
  /// highlights across R, G, B.
  static RgbaImage colorBalance(
    RgbaImage src,
    List<double> shadows,
    List<double> midtones,
    List<double> highlights,
  ) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final r = src.pixels[i], g = src.pixels[i + 1], b = src.pixels[i + 2];
      final l = _lum(r, g, b);
      // Weight each range with a triangular falloff around 0 / 0.5 / 1.
      final ws = (1.0 - l * 2).clamp(0.0, 1.0);
      final wh = ((l - 0.5) * 2).clamp(0.0, 1.0);
      final wm = (1.0 - ws - wh).clamp(0.0, 1.0);
      final base = [r.toDouble(), g.toDouble(), b.toDouble()];
      final result = List<double>.filled(3, 0);
      for (var c = 0; c < 3; c++) {
        final shift = shadows[c] * ws + midtones[c] * wm + highlights[c] * wh;
        result[c] = (base[c] + shift * 255 * 0.5).clamp(0.0, 255.0);
      }
      out.pixels[i] = result[0].round();
      out.pixels[i + 1] = result[1].round();
      out.pixels[i + 2] = result[2].round();
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Channel mixer: a 3×3 matrix (rows = output R/G/B) applied to the input
  /// channels, plus a per-channel offset (−1..1).
  static RgbaImage channelMixer(
    RgbaImage src,
    List<double> matrix,
    List<double> offsets,
  ) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final r = src.pixels[i].toDouble();
      final g = src.pixels[i + 1].toDouble();
      final b = src.pixels[i + 2].toDouble();
      for (var c = 0; c < 3; c++) {
        final v = matrix[c * 3] * r +
            matrix[c * 3 + 1] * g +
            matrix[c * 3 + 2] * b +
            offsets[c] * 255;
        out.pixels[i + c] = v.round().clamp(0, 255);
      }
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Maps luminance through a color gradient (duotone / gradient map).
  static RgbaImage gradientMap(
    RgbaImage src,
    List<int> argbStops,
  ) {
    if (argbStops.isEmpty) return src.copy();
    final n = argbStops.length;
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      final l = _lum(src.pixels[i], src.pixels[i + 1], src.pixels[i + 2])
          .clamp(0.0, 1.0);
      final pos = l * (n - 1);
      final i0 = pos.floor().clamp(0, n - 1);
      final i1 = (i0 + 1).clamp(0, n - 1);
      final t = pos - i0;
      final c0 = argbStops[i0], c1 = argbStops[i1];
      int lerpCh(int shift) {
        final a = (c0 >> shift) & 0xFF, b = (c1 >> shift) & 0xFF;
        return (a + (b - a) * t).round().clamp(0, 255);
      }

      out.pixels[i] = lerpCh(16);
      out.pixels[i + 1] = lerpCh(8);
      out.pixels[i + 2] = lerpCh(0);
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  // ================================================== stylize / geometry ===

  /// Pixelation: averages each [blockSize]² block.
  static RgbaImage pixelate(RgbaImage src, int blockSize) {
    final bs = blockSize.clamp(2, 128);
    final out = RgbaImage.blank(src.width, src.height);
    for (var by = 0; by < src.height; by += bs) {
      for (var bx = 0; bx < src.width; bx += bs) {
        var r = 0, g = 0, b = 0, a = 0, n = 0;
        for (var y = by; y < math.min(by + bs, src.height); y++) {
          for (var x = bx; x < math.min(bx + bs, src.width); x++) {
            final i = (y * src.width + x) * 4;
            r += src.pixels[i];
            g += src.pixels[i + 1];
            b += src.pixels[i + 2];
            a += src.pixels[i + 3];
            n++;
          }
        }
        if (n == 0) continue;
        for (var y = by; y < math.min(by + bs, src.height); y++) {
          for (var x = bx; x < math.min(bx + bs, src.width); x++) {
            final i = (y * src.width + x) * 4;
            out.pixels[i] = r ~/ n;
            out.pixels[i + 1] = g ~/ n;
            out.pixels[i + 2] = b ~/ n;
            out.pixels[i + 3] = a ~/ n;
          }
        }
      }
    }
    return out;
  }

  /// Halftone screening: each cell becomes a dot whose radius encodes the
  /// cell's average darkness. Cells live on a grid rotated by [angle].
  static RgbaImage halftone(RgbaImage src, int cellSize, {double angle = 45}) {
    final cs = cellSize.clamp(2, 32);
    final out = RgbaImage.blank(src.width, src.height);
    final rad = angle * math.pi / 180;
    final cosA = math.cos(rad), sinA = math.sin(rad);
    // Bucket every pixel into its rotated grid cell (one pass).
    final cells = <int, ({double sum, int n})>{};
    final cellX = List<int>.filled(src.width * src.height, 0);
    final cellY = List<int>.filled(src.width * src.height, 0);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final u = x * cosA + y * sinA;
        final v = -x * sinA + y * cosA;
        final gx = (u / cs).floor();
        final gy = (v / cs).floor();
        cellX[y * src.width + x] = gx;
        cellY[y * src.width + x] = gy;
        final i = (y * src.width + x) * 4;
        final lum = _lum(src.pixels[i], src.pixels[i + 1], src.pixels[i + 2]);
        final key = gx * 100003 + gy;
        final prev = cells[key];
        cells[key] = (sum: (prev?.sum ?? 0) + lum, n: (prev?.n ?? 0) + 1);
      }
    }
    for (final entry in cells.entries) {
      final gx = entry.key ~/ 100003;
      final gy = entry.key % 100003;
      final dark = 1.0 - entry.value.sum / entry.value.n;
      final radius = math.sqrt(dark.clamp(0.0, 1.0)) * cs * 0.62;
      // Cell centre back in screen space (inverse rotation).
      final cu = (gx + 0.5) * cs, cv = (gy + 0.5) * cs;
      final px = cu * cosA - cv * sinA;
      final py = cu * sinA + cv * cosA;
      _fillCircle(out, px, py, radius, 0);
    }
    // White paper background.
    for (var i = 0; i < out.pixels.length; i += 4) {
      final v = out.pixels[i + 3] == 0 ? 255 : out.pixels[i];
      out.pixels[i] = v;
      out.pixels[i + 1] = v;
      out.pixels[i + 2] = v;
      out.pixels[i + 3] = 255;
    }
    return out;
  }

  static void _fillCircle(RgbaImage img, double cx, double cy, double r, int value) {
    if (r <= 0) return;
    final x0 = (cx - r).floor().clamp(0, img.width - 1);
    final x1 = (cx + r).ceil().clamp(0, img.width - 1);
    final y0 = (cy - r).floor().clamp(0, img.height - 1);
    final y1 = (cy + r).ceil().clamp(0, img.height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy > r * r) continue;
        final i = (y * img.width + x) * 4;
        img.pixels[i] = value;
        img.pixels[i + 1] = value;
        img.pixels[i + 2] = value;
        img.pixels[i + 3] = 255;
      }
    }
  }

  /// Oil paint: replaces each pixel with the average color of the most
  /// frequent intensity bucket in its neighbourhood (Kuwahara-lite).
  static RgbaImage oilPaint(RgbaImage src, int radius, int levels) {
    final r = radius.clamp(1, 6);
    final lv = levels.clamp(2, 32);
    final out = RgbaImage.blank(src.width, src.height);
    final binR = List<int>.filled(lv, 0);
    final binG = List<int>.filled(lv, 0);
    final binB = List<int>.filled(lv, 0);
    final binA = List<int>.filled(lv, 0);
    final binN = List<int>.filled(lv, 0);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        binN.fillRange(0, lv, 0);
        binR.fillRange(0, lv, 0);
        binG.fillRange(0, lv, 0);
        binB.fillRange(0, lv, 0);
        binA.fillRange(0, lv, 0);
        for (var dy = -r; dy <= r; dy++) {
          final yy = (y + dy).clamp(0, src.height - 1);
          for (var dx = -r; dx <= r; dx++) {
            final xx = (x + dx).clamp(0, src.width - 1);
            final i = (yy * src.width + xx) * 4;
            final bin = (_lum(src.pixels[i], src.pixels[i + 1],
                        src.pixels[i + 2]) *
                    (lv - 1))
                .round()
                .clamp(0, lv - 1);
            binR[bin] += src.pixels[i];
            binG[bin] += src.pixels[i + 1];
            binB[bin] += src.pixels[i + 2];
            binA[bin] += src.pixels[i + 3];
            binN[bin]++;
          }
        }
        var best = 0;
        for (var b = 1; b < lv; b++) {
          if (binN[b] > binN[best]) best = b;
        }
        final i = (y * src.width + x) * 4;
        final n = math.max(1, binN[best]);
        out.pixels[i] = binR[best] ~/ n;
        out.pixels[i + 1] = binG[best] ~/ n;
        out.pixels[i + 2] = binB[best] ~/ n;
        out.pixels[i + 3] = binA[best] ~/ n;
      }
    }
    return out;
  }

  /// Emboss: directional difference from the upper-left neighbour.
  static RgbaImage emboss(RgbaImage src, double strength, {bool gray = true}) {
    final out = RgbaImage.blank(src.width, src.height);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final i = (y * src.width + x) * 4;
        final x0 = math.max(0, x - 1), y0 = math.max(0, y - 1);
        final j = (y0 * src.width + x0) * 4;
        for (var c = 0; c < 3; c++) {
          final v = 128 + (src.pixels[i + c] - src.pixels[j + c]) * strength;
          out.pixels[i + c] = v.round().clamp(0, 255);
        }
        if (gray) {
          final g = _lum(out.pixels[i], out.pixels[i + 1], out.pixels[i + 2]);
          final v = (g * 255).round().clamp(0, 255);
          out.pixels[i] = v;
          out.pixels[i + 1] = v;
          out.pixels[i + 2] = v;
        }
        out.pixels[i + 3] = src.pixels[i + 3];
      }
    }
    return out;
  }

  /// Sobel edge detection; [amount] blends the edges back over the original.
  static RgbaImage edgeDetect(RgbaImage src, double amount) {
    final a = amount.clamp(0.0, 1.0);
    final out = RgbaImage.blank(src.width, src.height);
    double lumAt(int x, int y) {
      final xx = x.clamp(0, src.width - 1), yy = y.clamp(0, src.height - 1);
      final i = (yy * src.width + xx) * 4;
      return _lum(src.pixels[i], src.pixels[i + 1], src.pixels[i + 2]) * 255;
    }

    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final gx = -lumAt(x - 1, y - 1) -
            2 * lumAt(x - 1, y) -
            lumAt(x - 1, y + 1) +
            lumAt(x + 1, y - 1) +
            2 * lumAt(x + 1, y) +
            lumAt(x + 1, y + 1);
        final gy = -lumAt(x - 1, y - 1) -
            2 * lumAt(x, y - 1) -
            lumAt(x + 1, y - 1) +
            lumAt(x - 1, y + 1) +
            2 * lumAt(x, y + 1) +
            lumAt(x + 1, y + 1);
        final mag = math.sqrt(gx * gx + gy * gy).clamp(0.0, 255.0);
        final i = (y * src.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          out.pixels[i + c] =
              (src.pixels[i + c] * (1 - a) + mag * a).round().clamp(0, 255);
        }
        out.pixels[i + 3] = src.pixels[i + 3];
      }
    }
    return out;
  }

  /// Pencil sketch: color-dodge the original with its blurred inverse.
  static RgbaImage sketch(RgbaImage src, double radius) {
    final blurred = gaussianBlur(src, radius);
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        final inv = 255 - blurred.pixels[i + c];
        final v = inv >= 255 ? 255 : (src.pixels[i + c] * 255) ~/ (255 - inv);
        out.pixels[i + c] = v.clamp(0, 255);
      }
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Adds deterministic noise (same [seed] → same output).
  static RgbaImage noise(
    RgbaImage src,
    double amount, {
    bool monochrome = true,
    int seed = 1,
  }) {
    final amp = (amount.clamp(0.0, 1.0) * 255).round();
    final out = RgbaImage.blank(src.width, src.height);
    var state = (seed * 2654435761) & 0x7FFFFFFF;
    int rnd() {
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      return state % (2 * amp + 1) - amp;
    }

    for (var i = 0; i < src.pixels.length; i += 4) {
      final n = rnd();
      for (var c = 0; c < 3; c++) {
        final v = monochrome ? n : rnd();
        out.pixels[i + c] = (src.pixels[i + c] + v).clamp(0, 255);
      }
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Darkens toward the corners.
  static RgbaImage vignette(RgbaImage src, double amount, {double radius = 0.75}) {
    final a = amount.clamp(0.0, 1.0);
    if (a <= 0) return src.copy();
    final out = src.copy();
    final cx = src.width / 2, cy = src.height / 2;
    final maxD = math.sqrt(cx * cx + cy * cy);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final dx = (x - cx) / maxD, dy = (y - cy) / maxD;
        final d = math.sqrt(dx * dx + dy * dy) / math.max(0.01, radius);
        final factor = (1 - a * math.pow(d.clamp(0.0, 1.0), 2)).clamp(0.0, 1.0);
        final i = (y * src.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          out.pixels[i + c] = (src.pixels[i + c] * factor).round().clamp(0, 255);
        }
      }
    }
    return out;
  }

  /// Bloom / glow: blurred highlights screen-blended over the original.
  static RgbaImage bloom(RgbaImage src, double radius, double amount) {
    final blurred = gaussianBlur(src, radius);
    final a = amount.clamp(0.0, 1.0);
    final out = RgbaImage.blank(src.width, src.height);
    for (var i = 0; i < src.pixels.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        final base = src.pixels[i + c].toDouble();
        final glow = blurred.pixels[i + c].toDouble();
        // Screen blend, then mix by amount.
        final screen = 255 - (255 - base) * (255 - glow) / 255;
        out.pixels[i + c] =
            (base + (screen - base) * a).round().clamp(0, 255);
      }
      out.pixels[i + 3] = src.pixels[i + 3];
    }
    return out;
  }

  /// Linear motion blur along [angle] degrees.
  static RgbaImage motionBlur(RgbaImage src, int distance, double angle) {
    final d = distance.clamp(0, 64);
    if (d == 0) return src.copy();
    final rad = angle * math.pi / 180;
    final dx = math.cos(rad), dy = math.sin(rad);
    final out = RgbaImage.blank(src.width, src.height);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        var r = 0, g = 0, b = 0, a = 0, n = 0;
        for (var s = -d; s <= d; s++) {
          final sx = (x + dx * s).round().clamp(0, src.width - 1);
          final sy = (y + dy * s).round().clamp(0, src.height - 1);
          final i = (sy * src.width + sx) * 4;
          r += src.pixels[i];
          g += src.pixels[i + 1];
          b += src.pixels[i + 2];
          a += src.pixels[i + 3];
          n++;
        }
        final i = (y * src.width + x) * 4;
        out.pixels[i] = r ~/ n;
        out.pixels[i + 1] = g ~/ n;
        out.pixels[i + 2] = b ~/ n;
        out.pixels[i + 3] = a ~/ n;
      }
    }
    return out;
  }

  /// Horizontal ripple distortion.
  static RgbaImage ripple(RgbaImage src, double amplitude, double wavelength) {
    final amp = amplitude.clamp(0.0, 64.0);
    final wl = math.max(2.0, wavelength);
    if (amp <= 0) return src.copy();
    final out = RgbaImage.blank(src.width, src.height);
    for (var y = 0; y < src.height; y++) {
      final shift = amp * math.sin(2 * math.pi * y / wl);
      for (var x = 0; x < src.width; x++) {
        final sx = (x + shift).round().clamp(0, src.width - 1);
        final si = (y * src.width + sx) * 4;
        final di = (y * src.width + x) * 4;
        for (var c = 0; c < 4; c++) {
          out.pixels[di + c] = src.pixels[si + c];
        }
      }
    }
    return out;
  }
}
