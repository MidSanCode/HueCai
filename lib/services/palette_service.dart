import 'dart:ui';

/// A named list of colors, optionally round-tripped through GIMP's `.gpl`
/// palette format.
class Palette {
  String name;
  final List<Color> colors;

  Palette({required this.name, List<Color>? colors}) : colors = colors ?? [];

  int get length => colors.length;
  bool get isEmpty => colors.isEmpty;
  bool get isNotEmpty => colors.isNotEmpty;
}

/// Reads and writes GIMP palette files (`.gpl`) plus a few plain-text
/// fallbacks (one `#RRGGBB` per line, `.hex`/`.txt` style).
class PaletteCodec {
  /// Parses a `.gpl` document. Returns null when the text is not a palette.
  static Palette? parseGpl(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return null;
    var i = 0;
    // The magic header is required by the format but tolerated missing.
    if (lines.first.trim().toLowerCase().startsWith('gimp palette')) {
      i = 1;
    }
    var name = 'Palette';
    final colors = <Color>[];
    for (; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (line.toLowerCase().startsWith('name:')) {
        final n = line.substring(5).trim();
        if (n.isNotEmpty) name = n;
        continue;
      }
      if (line.toLowerCase().startsWith('columns:')) continue;
      // `R G B [name]` separated by any run of whitespace or tabs.
      final parts = line.split(RegExp(r'[\s\t]+'));
      if (parts.length < 3) continue;
      final r = int.tryParse(parts[0]);
      final g = int.tryParse(parts[1]);
      final b = int.tryParse(parts[2]);
      if (r == null || g == null || b == null) continue;
      colors.add(Color.fromARGB(
        255,
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255),
      ));
    }
    if (colors.isEmpty) return null;
    return Palette(name: name, colors: colors);
  }

  /// Serializes [palette] to the `.gpl` format.
  static String toGpl(Palette palette) {
    final buf = StringBuffer()
      ..writeln('GIMP Palette')
      ..writeln('Name: ${palette.name}')
      ..writeln('Columns: 16')
      ..writeln('#');
    for (final c in palette.colors) {
      final r = (c.r * 255).round().clamp(0, 255);
      final g = (c.g * 255).round().clamp(0, 255);
      final b = (c.b * 255).round().clamp(0, 255);
      buf.writeln('${r.toString().padLeft(3)} '
          '${g.toString().padLeft(3)} '
          '${b.toString().padLeft(3)}\t'
          '${_hex(c)}');
    }
    return buf.toString();
  }

  /// Parses a plain list of hex colors (`#RRGGBB` / `RRGGBB` / `#RGB`),
  /// one per line or comma separated. Returns null when nothing parses.
  static Palette? parseHexList(String text, {String name = 'Palette'}) {
    final matches = RegExp(r'#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();
    if (matches.isEmpty) return null;
    final colors = <Color>[];
    for (final m in matches) {
      final hex = m.length == 3
          ? m.split('').map((ch) => '$ch$ch').join()
          : m;
      final v = int.tryParse(hex, radix: 16);
      if (v == null) continue;
      colors.add(Color(0xFF000000 | v));
    }
    if (colors.isEmpty) return null;
    return Palette(name: name, colors: colors);
  }

  /// Tries `.gpl` first, then the plain hex list.
  static Palette? parse(String text, {String fallbackName = 'Palette'}) =>
      parseGpl(text) ?? parseHexList(text, name: fallbackName);

  static String _hex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// `#RRGGBB` (upper case) for UI display.
  static String hexOf(Color c) => _hex(c);
}
