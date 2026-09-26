import 'dart:convert';

import 'brush.dart';
import '../services/brush_texture.dart';

/// A saved snapshot of the brush engine's parameters.
///
/// Everything here is parametric (type + numbers + a procedural tip texture),
/// so a pack is a small JSON document and importing it cannot fail on missing
/// binary assets.
class BrushPreset {
  final String id;
  String name;
  BrushType type;
  double size;
  double opacity;
  double hardness;
  double flow;
  double spacing;
  double mix;
  BrushTexture tipTexture;

  BrushPreset({
    required this.id,
    required this.name,
    this.type = BrushType.hardRound,
    this.size = 10,
    this.opacity = 1,
    this.hardness = 1,
    this.flow = 1,
    this.spacing = 0.1,
    this.mix = 0,
    this.tipTexture = BrushTexture.none,
  });

  /// Builds a preset from a built-in [Brush] definition, keeping its id
  /// stable (`builtin-<type>`) so re-importing never duplicates them.
  factory BrushPreset.fromBrush(Brush brush) => BrushPreset(
        id: 'builtin-${brush.type.name}',
        name: brush.nameKey,
        type: brush.type,
        size: brush.size,
        opacity: brush.opacity,
        hardness: brush.hardness,
        flow: brush.flow,
        spacing: brush.spacing,
        mix: brush.mix,
        tipTexture: brush.tipTexture,
      );

  /// The stock preset list: every built-in brush, plus a few textured
  /// variants that show what tip textures do.
  static List<BrushPreset> builtIns() => [
        ...Brush.defaults().map(BrushPreset.fromBrush),
        BrushPreset(
          id: 'builtin-dot-screen',
          name: 'preset.dot_screen',
          type: BrushType.pencil,
          size: 6,
          hardness: 0.9,
          spacing: 0.08,
          tipTexture: BrushTexture.dots,
        ),
        BrushPreset(
          id: 'builtin-canvas',
          name: 'preset.canvas',
          type: BrushType.marker,
          size: 14,
          opacity: 0.85,
          hardness: 0.7,
          spacing: 0.15,
          tipTexture: BrushTexture.canvas,
        ),
        BrushPreset(
          id: 'builtin-hatch',
          name: 'preset.hatch',
          type: BrushType.crayon,
          size: 12,
          hardness: 0.6,
          spacing: 0.2,
          tipTexture: BrushTexture.hatch,
        ),
        BrushPreset(
          id: 'builtin-wet-mix',
          name: 'preset.wet_mix',
          type: BrushType.oil,
          size: 18,
          opacity: 0.95,
          hardness: 0.5,
          spacing: 0.12,
          mix: 0.45,
        ),
      ];

  BrushPreset copyWith({
    String? name,
    BrushType? type,
    double? size,
    double? opacity,
    double? hardness,
    double? flow,
    double? spacing,
    double? mix,
    BrushTexture? tipTexture,
  }) =>
      BrushPreset(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
        hardness: hardness ?? this.hardness,
        flow: flow ?? this.flow,
        spacing: spacing ?? this.spacing,
        mix: mix ?? this.mix,
        tipTexture: tipTexture ?? this.tipTexture,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'size': size,
        'opacity': opacity,
        'hardness': hardness,
        'flow': flow,
        'spacing': spacing,
        'mix': mix,
        'tip': tipTexture.name,
      };

  /// Tolerant reader: unknown enum values fall back to a usable default so a
  /// pack written by a newer build still imports.
  factory BrushPreset.fromJson(Map<String, dynamic> json) => BrushPreset(
        id: json['id'] as String? ?? 'preset',
        name: json['name'] as String? ?? 'Preset',
        type: BrushType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => BrushType.hardRound,
        ),
        size: (json['size'] as num?)?.toDouble() ?? 10,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1,
        hardness: (json['hardness'] as num?)?.toDouble() ?? 1,
        flow: (json['flow'] as num?)?.toDouble() ?? 1,
        spacing: (json['spacing'] as num?)?.toDouble() ?? 0.1,
        mix: (json['mix'] as num?)?.toDouble() ?? 0,
        tipTexture: BrushTexture.values.firstWhere(
          (t) => t.name == json['tip'],
          orElse: () => BrushTexture.none,
        ),
      );
}

/// Import / export container for brush preset packs (`.huebrush`).
class BrushPack {
  static const String formatId = 'huecai-brush-pack';
  static const int version = 1;

  /// Serializes [presets] into a shareable JSON document.
  static String encode(List<BrushPreset> presets, {String name = 'Brushes'}) {
    final json = {
      'format': formatId,
      'version': version,
      'name': name,
      'presets': presets.map((p) => p.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Parses a pack document. Returns null when the text is not a brush pack.
  static List<BrushPreset>? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['format'] != formatId) return null;
    final raw = decoded['presets'];
    if (raw is! List) return null;
    final out = <BrushPreset>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(BrushPreset.fromJson(entry.cast<String, dynamic>()));
      } catch (_) {
        // Skip malformed entries instead of failing the whole pack.
      }
    }
    return out;
  }
}
