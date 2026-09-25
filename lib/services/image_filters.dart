import 'dart:math' as math;
import 'dart:typed_data';

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

  RgbaImage apply(RgbaImage src) => switch (kind) {
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
            saturationScale:
                (params['saturation'] as num?)?.toDouble() ?? 1,
            lightnessScale: (params['lightness'] as num?)?.toDouble() ?? 1,
          ),
        _ => src.copy(),
      };

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
}
