import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A simplified CMYK output profile used for soft proofing and gamut
/// warnings: a total-ink limit plus dot gain. Colors whose naive CMYK
/// round-trip through this profile drifts noticeably are "out of gamut"
/// for print, which is exactly what the warning highlights.
class PrintProfile {
  /// Maximum sum of ink coverage, e.g. 3.0 = 300% total ink.
  final double totalInkLimit;

  /// Midtone dot gain, 0 = none, 0.2 = heavy.
  final double dotGain;

  const PrintProfile({this.totalInkLimit = 3.0, this.dotGain = 0.08});

  static const coated = PrintProfile(totalInkLimit: 3.0, dotGain: 0.08);
  static const uncoated = PrintProfile(totalInkLimit: 2.6, dotGain: 0.16);
  static const newsprint = PrintProfile(totalInkLimit: 2.2, dotGain: 0.24);
}

typedef Cmyk = ({double c, double m, double y, double k});

/// sRGB ⇄ naive CMYK with ink limiting, plus gamut checks on top.
class Gamut {
  static Cmyk toCmyk(Color color) {
    final r = color.r, g = color.g, b = color.b;
    final k = 1.0 - math.max(r, math.max(g, b));
    if (k >= 1.0) return (c: 0.0, m: 0.0, y: 0.0, k: 1.0);
    final d = 1.0 - k;
    return (
      c: ((1.0 - r - k) / d).clamp(0.0, 1.0),
      m: ((1.0 - g - k) / d).clamp(0.0, 1.0),
      y: ((1.0 - b - k) / d).clamp(0.0, 1.0),
      k: k.clamp(0.0, 1.0),
    );
  }

  static Color fromCmyk(Cmyk v) {
    double ch(double ink) => (1.0 - ink.clamp(0.0, 1.0)) * (1.0 - v.k);
    return Color.fromARGB(
      255,
      (ch(v.c) * 255).round().clamp(0, 255),
      (ch(v.m) * 255).round().clamp(0, 255),
      (ch(v.y) * 255).round().clamp(0, 255),
    );
  }

  /// Applies dot gain to an ink value (midtones grow the most).
  static double _gain(double v, double gain) {
    if (gain <= 0) return v;
    return (v + gain * math.sin(math.pi * v)).clamp(0.0, 1.0);
  }

  /// Total ink after dot gain, scaled back under [profile]'s ink limit.
  static Cmyk limitInk(Cmyk v, PrintProfile profile) {
    var c = _gain(v.c, profile.dotGain);
    var m = _gain(v.m, profile.dotGain);
    var y = _gain(v.y, profile.dotGain);
    final k = v.k;
    final total = c + m + y + k;
    if (total > profile.totalInkLimit && total > 0) {
      final chroma = c + m + y;
      final allowed = (profile.totalInkLimit - k).clamp(0.0, 3.0);
      if (chroma > 0) {
        final scale = (allowed / chroma).clamp(0.0, 1.0);
        c *= scale;
        m *= scale;
        y *= scale;
      }
    }
    return (c: c, m: m, y: y, k: k);
  }

  /// What this color would look like printed through [profile].
  static Color softProof(Color color, PrintProfile profile) =>
      fromCmyk(limitInk(toCmyk(color), profile));

  /// Per-channel distance (0..1, max of the RGB deltas).
  static double deviation(Color a, Color b) => math.max(
        (a.r - b.r).abs(),
        math.max((a.g - b.g).abs(), (a.b - b.b).abs()),
      );

  /// True when [color] cannot be reproduced faithfully by [profile].
  static bool isOutOfGamut(Color color, PrintProfile profile,
          {double threshold = 0.02}) =>
      deviation(color, softProof(color, profile)) > threshold;

  /// Nearest in-gamut approximation: desaturates (then lightens/darkens)
  /// until the color round-trips within tolerance.
  static Color nearestInGamut(Color color, PrintProfile profile,
      {double threshold = 0.02}) {
    if (!isOutOfGamut(color, profile, threshold: threshold)) return color;
    final hsv = HSVColor.fromColor(color);
    // Binary search on saturation first: most ink-limit failures are
    // saturated colors that print muddy.
    var lo = 0.0, hi = hsv.saturation;
    for (var i = 0; i < 18; i++) {
      final mid = (lo + hi) / 2;
      final candidate = hsv.withSaturation(mid).toColor();
      if (isOutOfGamut(candidate, profile, threshold: threshold)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final desat = hsv.withSaturation(lo).toColor();
    if (!isOutOfGamut(desat, profile, threshold: threshold)) return desat;
    // Fall back to the soft proof itself (always representable).
    return softProof(color, profile);
  }
}
