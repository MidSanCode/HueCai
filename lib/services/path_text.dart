import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One glyph placed on a baseline path.
class PlacedGlyph {
  final String char;

  /// Baseline point where the glyph's centre sits.
  final Offset position;

  /// Rotation to apply with `canvas.rotate` so the glyph follows the
  /// baseline, in canvas coordinates (clockwise-positive, y axis down).
  ///
  /// [ui.PathMetric.getTangentForOffset] reports the angle in the maths
  /// convention (counter-clockwise-positive with y up), so it is negated
  /// here once for every consumer.
  final double angle;

  final double width;
  final double height;

  const PlacedGlyph({
    required this.char,
    required this.position,
    required this.angle,
    required this.width,
    required this.height,
  });

  @override
  String toString() =>
      'PlacedGlyph($char @ $position, angle ${angle.toStringAsFixed(3)})';
}

/// Text-on-path layout: walk the glyphs along a [ui.Path] baseline, rotating
/// each one to the local tangent.
///
/// The measurement callback is injected so the maths can be unit-tested
/// without a font: the production caller passes [TextPainter] widths, tests
/// pass a fixed advance.
class PathTextLayout {
  /// Places [text] along [path], starting [offset] pixels in.
  ///
  /// Glyphs that would run past the end of the baseline are dropped, so a
  /// short path truncates the text instead of wrapping.
  static List<PlacedGlyph> layout({
    required ui.Path path,
    required String text,
    required double Function(String char) measure,
    required double Function(String char) height,
    double offset = 0,
  }) {
    if (text.isEmpty) return const [];
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return const [];
    final metric = metrics.first;
    final total = metric.length;
    if (total <= 0) return const [];

    final out = <PlacedGlyph>[];
    var distance = offset.clamp(0.0, total);
    final chars = <String>[
      for (final rune in text.runes) String.fromCharCode(rune),
    ];
    for (final char in chars) {
      if (char == '\n') continue;
      final w = measure(char);
      final center = distance + w / 2;
      if (center > total) break;
      final tangent = metric.getTangentForOffset(center);
      if (tangent == null) break;
      out.add(PlacedGlyph(
        char: char,
        position: tangent.position,
        // Engine angle is counter-clockwise-positive with y up; canvas.rotate
        // is clockwise-positive with y down.
        angle: -tangent.angle,
        width: w,
        height: height(char),
      ));
      distance += w;
      if (distance >= total) break;
    }
    return out;
  }

  /// Measures one glyph with a real [TextPainter].
  static double measure(
    String char,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: char, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }
}
