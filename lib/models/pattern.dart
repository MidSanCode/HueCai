import 'dart:convert';
import 'dart:ui';

/// Procedural pattern kinds offered by the pattern library / dot generator.
///
/// Every kind is axis-aligned in pixel space; [PatternSpec.angle] is applied
/// as a shader rotation instead of being baked in, so tiles stay seamless.
enum PatternKind {
  /// Halftone dot grid (网点).
  dots,

  /// Parallel lines (线条 / 斜线).
  lines,

  /// Two line sets at 90° (交叉线).
  cross,

  /// Alternating squares (棋盘格).
  checker,

  /// Grid lines (网格).
  grid,

  /// Speckle noise (噪点).
  noise,

  /// Low-frequency fibre noise (纸纹).
  paper,
}

/// A resolution-independent pattern definition.
///
/// Patterns are parametric on purpose: a definition is a few numbers plus two
/// colours, so it can be stored inline in a drawable and still render exactly
/// the same on another machine — no bitmap assets to ship or lose.
class PatternSpec {
  final String id;
  String name;
  PatternKind kind;

  /// Distance between repeating elements, in pixels.
  double spacing;

  /// Element size: dot radius, line width or checker square size.
  double thickness;

  /// Shader rotation in radians (0 = axis aligned).
  double angle;

  /// Coverage for the noise / paper kinds, 0..1.
  double density;

  Color foreground;
  Color background;

  PatternSpec({
    required this.id,
    required this.name,
    this.kind = PatternKind.dots,
    this.spacing = 8,
    this.thickness = 2.6,
    this.angle = 0,
    this.density = 0.35,
    this.foreground = const Color(0xFF000000),
    this.background = const Color(0x00000000),
  });

  /// The stock library: a small spread of usable screentones and textures so
  /// the pattern panel is never empty.
  static List<PatternSpec> builtIns() => [
        PatternSpec(
          id: 'builtin-dots-8',
          name: 'pattern.dots_8',
          kind: PatternKind.dots,
          spacing: 8,
          thickness: 2.6,
        ),
        PatternSpec(
          id: 'builtin-dots-4',
          name: 'pattern.dots_4',
          kind: PatternKind.dots,
          spacing: 4,
          thickness: 1.4,
        ),
        PatternSpec(
          id: 'builtin-lines',
          name: 'pattern.lines',
          kind: PatternKind.lines,
          spacing: 7,
          thickness: 1.4,
          angle: 0.7853981633974483,
        ),
        PatternSpec(
          id: 'builtin-cross',
          name: 'pattern.cross',
          kind: PatternKind.cross,
          spacing: 10,
          thickness: 1,
        ),
        PatternSpec(
          id: 'builtin-grid',
          name: 'pattern.grid',
          kind: PatternKind.grid,
          spacing: 12,
          thickness: 1,
        ),
        PatternSpec(
          id: 'builtin-noise',
          name: 'pattern.noise',
          kind: PatternKind.noise,
          spacing: 4,
          thickness: 1,
          density: 0.28,
        ),
        PatternSpec(
          id: 'builtin-paper',
          name: 'pattern.paper',
          kind: PatternKind.paper,
          spacing: 8,
          thickness: 1,
          density: 0.5,
        ),
      ];

  /// A screentone-style dot pattern (the dot generator's starting point).
  factory PatternSpec.dotScreen({
    String id = 'generated',
    String name = 'Dots',
    double spacing = 8,
    double radius = 2.6,
    Color foreground = const Color(0xFF000000),
    Color background = const Color(0x00000000),
  }) =>
      PatternSpec(
        id: id,
        name: name,
        kind: PatternKind.dots,
        spacing: spacing,
        thickness: radius,
        foreground: foreground,
        background: background,
      );

  PatternSpec copyWith({
    String? name,
    PatternKind? kind,
    double? spacing,
    double? thickness,
    double? angle,
    double? density,
    Color? foreground,
    Color? background,
  }) =>
      PatternSpec(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        spacing: spacing ?? this.spacing,
        thickness: thickness ?? this.thickness,
        angle: angle ?? this.angle,
        density: density ?? this.density,
        foreground: foreground ?? this.foreground,
        background: background ?? this.background,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'spacing': spacing,
        'thickness': thickness,
        'angle': angle,
        'density': density,
        'foreground': foreground.toARGB32(),
        'background': background.toARGB32(),
      };

  /// Tolerant reader: unknown kinds fall back to [PatternKind.dots] so a pack
  /// from a newer build still imports something usable.
  factory PatternSpec.fromJson(Map<String, dynamic> json) => PatternSpec(
        id: json['id'] as String? ?? 'pattern',
        name: json['name'] as String? ?? 'Pattern',
        kind: PatternKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => PatternKind.dots,
        ),
        spacing: (json['spacing'] as num?)?.toDouble() ?? 8,
        thickness: (json['thickness'] as num?)?.toDouble() ?? 2.6,
        angle: (json['angle'] as num?)?.toDouble() ?? 0,
        density: (json['density'] as num?)?.toDouble() ?? 0.35,
        foreground: Color(json['foreground'] as int? ?? 0xFF000000),
        background: Color(json['background'] as int? ?? 0x00000000),
      );
}

/// Import / export container for pattern libraries.
///
/// The pack is plain JSON so users can hand-edit or share patterns, and so
/// nothing binary has to be validated on import.
class PatternPack {
  static const String formatId = 'huecai-pattern-pack';
  static const int version = 1;

  /// Serializes [patterns] into a shareable JSON document.
  static String encode(List<PatternSpec> patterns, {String name = 'Patterns'}) {
    final json = {
      'format': formatId,
      'version': version,
      'name': name,
      'patterns': patterns.map((p) => p.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// Parses a pack document. Returns null when the text is not a pattern
  /// pack; an empty list is a valid (if useless) pack.
  static List<PatternSpec>? decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final format = decoded['format'];
    if (format != formatId) return null;
    final raw = decoded['patterns'];
    if (raw is! List) return null;
    final out = <PatternSpec>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(PatternSpec.fromJson(entry.cast<String, dynamic>()));
      } catch (_) {
        // Skip malformed entries instead of failing the whole pack.
      }
    }
    return out;
  }
}
