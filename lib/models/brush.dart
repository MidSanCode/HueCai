import '../services/brush_texture.dart';

enum BrushType {
  hardRound,
  softRound,
  pencil,
  marker,
  airbrush,
  watercolor,
  oil,
  crayon,
  charcoal,
  calligraphy,
  eraser,
}

class Brush {
  final BrushType type;
  final String nameKey;
  double size;
  double hardness;
  double opacity;
  double flow;
  double spacing;
  BrushTexture tipTexture;

  Brush({
    required this.type,
    required this.nameKey,
    this.size = 10.0,
    this.hardness = 1.0,
    this.opacity = 1.0,
    this.flow = 1.0,
    this.spacing = 0.1,
    this.tipTexture = BrushTexture.none,
  });

  static List<Brush> defaults() => [
        Brush(type: BrushType.hardRound, nameKey: 'brush.hard_round', size: 5, hardness: 1.0),
        Brush(type: BrushType.softRound, nameKey: 'brush.soft_round', size: 10, hardness: 0.0),
        Brush(type: BrushType.pencil, nameKey: 'brush.pencil', size: 2, hardness: 1.0, spacing: 0.05),
        Brush(type: BrushType.marker, nameKey: 'brush.marker', size: 8, hardness: 0.8, opacity: 0.8),
        Brush(type: BrushType.airbrush, nameKey: 'brush.airbrush', size: 15, hardness: 0.0, opacity: 0.3, flow: 0.5),
        Brush(type: BrushType.watercolor, nameKey: 'brush.watercolor', size: 12, hardness: 0.2, opacity: 0.5, flow: 0.6, spacing: 0.15),
        Brush(type: BrushType.oil, nameKey: 'brush.oil', size: 10, hardness: 0.6, opacity: 0.9, spacing: 0.2),
        Brush(type: BrushType.crayon, nameKey: 'brush.crayon', size: 6, hardness: 0.7, spacing: 0.25),
        Brush(type: BrushType.charcoal, nameKey: 'brush.charcoal', size: 8, hardness: 0.3, spacing: 0.2),
        Brush(type: BrushType.calligraphy, nameKey: 'brush.calligraphy', size: 8, hardness: 0.9, spacing: 0.1),
        Brush(type: BrushType.eraser, nameKey: 'brush.eraser', size: 10, hardness: 1.0),
      ];

  Brush copyWith({
    BrushType? type,
    String? nameKey,
    double? size,
    double? hardness,
    double? opacity,
    double? flow,
    double? spacing,
    BrushTexture? tipTexture,
  }) =>
      Brush(
        type: type ?? this.type,
        nameKey: nameKey ?? this.nameKey,
        size: size ?? this.size,
        hardness: hardness ?? this.hardness,
        opacity: opacity ?? this.opacity,
        flow: flow ?? this.flow,
        spacing: spacing ?? this.spacing,
        tipTexture: tipTexture ?? this.tipTexture,
      );
}
