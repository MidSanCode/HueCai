import 'image_filters.dart';

/// One tunable parameter of a filter, described declaratively so a single
/// generic dialog can render every filter's UI.
class FilterParam {
  final String key;
  final String labelKey;
  final double min;
  final double max;
  final double def;

  /// True when the value is an integer (slider is stepped by 1).
  final bool isInt;

  const FilterParam({
    required this.key,
    required this.labelKey,
    required this.min,
    required this.max,
    required this.def,
    this.isInt = false,
  });

  double clampValue(double v) => v.clamp(min, max);
}

/// A registered filter: stable id, display name, parameters and the actual
/// pixel operation.
class FilterDef {
  final String kind;
  final String labelKey;

  /// Grouping key for menus (l10n).
  final String groupKey;
  final List<FilterParam> params;
  final RgbaImage Function(RgbaImage src, Map<String, dynamic> params) run;

  const FilterDef({
    required this.kind,
    required this.labelKey,
    required this.groupKey,
    required this.params,
    required this.run,
  });

  /// Default parameter map (used when a filter is applied without UI).
  Map<String, dynamic> defaultParams() => {
        for (final p in params) p.key: p.isInt ? p.def.round() : p.def,
      };
}

/// All filters the app knows about: the five originals plus the extended
/// set. Adjustment layers and the generic filter dialog both drive off this
/// registry, so adding a filter here exposes it everywhere.
class FilterRegistry {
  FilterRegistry._();

  static const _tone = 'filter.group.tone';
  static const _color = 'filter.group.color';
  static const _stylize = 'filter.group.stylize';
  static const _blur = 'filter.group.blur';

  static final List<FilterDef> all = [
    // ---------------------------------------------------------- originals
    FilterDef(
      kind: 'gaussianBlur',
      labelKey: 'filter.gaussian_blur',
      groupKey: _blur,
      params: const [
        FilterParam(key: 'radius', labelKey: 'filter.radius', min: 0, max: 60, def: 5),
      ],
      run: (src, p) =>
          ImageFilters.gaussianBlur(src, (p['radius'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'unsharpMask',
      labelKey: 'filter.unsharp_mask',
      groupKey: _blur,
      params: const [
        FilterParam(key: 'radius', labelKey: 'filter.radius', min: 0.5, max: 20, def: 2),
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 3, def: 0.8),
        FilterParam(key: 'threshold', labelKey: 'filter.threshold', min: 0, max: 64, def: 0, isInt: true),
      ],
      run: (src, p) => ImageFilters.unsharpMask(
            src,
            (p['radius'] as num).toDouble(),
            (p['amount'] as num).toDouble(),
            threshold: (p['threshold'] as num).toInt(),
          ),
    ),
    FilterDef(
      kind: 'levels',
      labelKey: 'filter.levels',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'in_black', labelKey: 'filter.in_black', min: 0, max: 254, def: 0, isInt: true),
        FilterParam(key: 'in_white', labelKey: 'filter.in_white', min: 1, max: 255, def: 255, isInt: true),
        FilterParam(key: 'gamma', labelKey: 'filter.gamma', min: 0.1, max: 4, def: 1),
      ],
      run: (src, p) => ImageFilters.levels(
            src,
            inBlack: (p['in_black'] as num).toInt(),
            inWhite: (p['in_white'] as num).toInt(),
            gamma: (p['gamma'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'curves',
      labelKey: 'filter.curves',
      groupKey: _tone,
      params: const [],
      run: (src, p) {
        final raw = (p['points'] as List?) ?? const [];
        final pts = raw
            .map((e) => (
                  x: ((e as Map)['x'] as num).toDouble(),
                  y: (e['y'] as num).toDouble(),
                ))
            .toList();
        return ImageFilters.curves(src, pts);
      },
    ),
    FilterDef(
      kind: 'hueSaturation',
      labelKey: 'filter.hue_saturation',
      groupKey: _color,
      params: const [
        FilterParam(key: 'hue', labelKey: 'filter.hue', min: -180, max: 180, def: 0),
        FilterParam(key: 'saturation', labelKey: 'filter.saturation', min: 0, max: 3, def: 1),
        FilterParam(key: 'lightness', labelKey: 'filter.lightness', min: 0, max: 2, def: 1),
      ],
      run: (src, p) => ImageFilters.hueSaturation(
            src,
            hueShift: (p['hue'] as num).toDouble(),
            saturationScale: (p['saturation'] as num).toDouble(),
            lightnessScale: (p['lightness'] as num).toDouble(),
          ),
    ),

    // ------------------------------------------------------------- tone
    FilterDef(
      kind: 'brightnessContrast',
      labelKey: 'filter.brightness_contrast',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'brightness', labelKey: 'filter.brightness', min: -1, max: 1, def: 0),
        FilterParam(key: 'contrast', labelKey: 'filter.contrast', min: -1, max: 1, def: 0),
      ],
      run: (src, p) => ImageFilters.brightnessContrast(
            src,
            (p['brightness'] as num).toDouble(),
            (p['contrast'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'exposure',
      labelKey: 'filter.exposure',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'stops', labelKey: 'filter.stops', min: -3, max: 3, def: 0.5),
      ],
      run: (src, p) => ImageFilters.exposure(src, (p['stops'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'gamma',
      labelKey: 'filter.gamma_correction',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'gamma', labelKey: 'filter.gamma', min: 0.1, max: 4, def: 1),
      ],
      run: (src, p) => ImageFilters.gamma(src, (p['gamma'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'normalize',
      labelKey: 'filter.normalize',
      groupKey: _tone,
      params: const [],
      run: (src, p) => ImageFilters.normalize(src),
    ),
    FilterDef(
      kind: 'equalize',
      labelKey: 'filter.equalize',
      groupKey: _tone,
      params: const [],
      run: (src, p) => ImageFilters.equalize(src),
    ),
    FilterDef(
      kind: 'posterize',
      labelKey: 'filter.posterize',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'levels', labelKey: 'filter.levels_count', min: 2, max: 32, def: 6, isInt: true),
      ],
      run: (src, p) => ImageFilters.posterize(src, (p['levels'] as num).toInt()),
    ),
    FilterDef(
      kind: 'threshold',
      labelKey: 'filter.threshold_bw',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'level', labelKey: 'filter.level', min: 0, max: 255, def: 128, isInt: true),
      ],
      run: (src, p) => ImageFilters.threshold(src, (p['level'] as num).toInt()),
    ),
    FilterDef(
      kind: 'solarize',
      labelKey: 'filter.solarize',
      groupKey: _tone,
      params: const [
        FilterParam(key: 'threshold', labelKey: 'filter.threshold', min: 0, max: 255, def: 128, isInt: true),
      ],
      run: (src, p) => ImageFilters.solarize(src, (p['threshold'] as num).toInt()),
    ),
    FilterDef(
      kind: 'invert',
      labelKey: 'filter.invert',
      groupKey: _tone,
      params: const [],
      run: (src, p) => ImageFilters.invert(src),
    ),

    // ------------------------------------------------------------ color
    FilterDef(
      kind: 'desaturate',
      labelKey: 'filter.desaturate',
      groupKey: _color,
      params: const [
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 1, def: 1),
      ],
      run: (src, p) => ImageFilters.desaturate(src, (p['amount'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'whiteBalance',
      labelKey: 'filter.white_balance',
      groupKey: _color,
      params: const [
        FilterParam(key: 'temperature', labelKey: 'filter.temperature', min: -1, max: 1, def: 0),
        FilterParam(key: 'tint', labelKey: 'filter.tint', min: -1, max: 1, def: 0),
      ],
      run: (src, p) => ImageFilters.whiteBalance(
            src,
            (p['temperature'] as num).toDouble(),
            (p['tint'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'colorBalance',
      labelKey: 'filter.color_balance',
      groupKey: _color,
      params: const [
        FilterParam(key: 'shadows_r', labelKey: 'filter.shadows_r', min: -1, max: 1, def: 0),
        FilterParam(key: 'shadows_g', labelKey: 'filter.shadows_g', min: -1, max: 1, def: 0),
        FilterParam(key: 'shadows_b', labelKey: 'filter.shadows_b', min: -1, max: 1, def: 0),
        FilterParam(key: 'midtones_r', labelKey: 'filter.midtones_r', min: -1, max: 1, def: 0),
        FilterParam(key: 'midtones_g', labelKey: 'filter.midtones_g', min: -1, max: 1, def: 0),
        FilterParam(key: 'midtones_b', labelKey: 'filter.midtones_b', min: -1, max: 1, def: 0),
        FilterParam(key: 'highlights_r', labelKey: 'filter.highlights_r', min: -1, max: 1, def: 0),
        FilterParam(key: 'highlights_g', labelKey: 'filter.highlights_g', min: -1, max: 1, def: 0),
        FilterParam(key: 'highlights_b', labelKey: 'filter.highlights_b', min: -1, max: 1, def: 0),
      ],
      run: (src, p) => ImageFilters.colorBalance(
            src,
            [
              (p['shadows_r'] as num).toDouble(),
              (p['shadows_g'] as num).toDouble(),
              (p['shadows_b'] as num).toDouble(),
            ],
            [
              (p['midtones_r'] as num).toDouble(),
              (p['midtones_g'] as num).toDouble(),
              (p['midtones_b'] as num).toDouble(),
            ],
            [
              (p['highlights_r'] as num).toDouble(),
              (p['highlights_g'] as num).toDouble(),
              (p['highlights_b'] as num).toDouble(),
            ],
          ),
    ),
    FilterDef(
      kind: 'channelMixer',
      labelKey: 'filter.channel_mixer',
      groupKey: _color,
      params: const [
        FilterParam(key: 'rr', labelKey: 'filter.rr', min: -2, max: 2, def: 1),
        FilterParam(key: 'rg', labelKey: 'filter.rg', min: -2, max: 2, def: 0),
        FilterParam(key: 'rb', labelKey: 'filter.rb', min: -2, max: 2, def: 0),
        FilterParam(key: 'gr', labelKey: 'filter.gr', min: -2, max: 2, def: 0),
        FilterParam(key: 'gg', labelKey: 'filter.gg', min: -2, max: 2, def: 1),
        FilterParam(key: 'gb', labelKey: 'filter.gb', min: -2, max: 2, def: 0),
        FilterParam(key: 'br', labelKey: 'filter.br', min: -2, max: 2, def: 0),
        FilterParam(key: 'bg', labelKey: 'filter.bg', min: -2, max: 2, def: 0),
        FilterParam(key: 'bb', labelKey: 'filter.bb', min: -2, max: 2, def: 1),
      ],
      run: (src, p) {
        double v(String k) => (p[k] as num).toDouble();
        return ImageFilters.channelMixer(
          src,
          [v('rr'), v('rg'), v('rb'), v('gr'), v('gg'), v('gb'), v('br'), v('bg'), v('bb')],
          [0, 0, 0],
        );
      },
    ),
    FilterDef(
      kind: 'gradientMap',
      labelKey: 'filter.gradient_map',
      groupKey: _color,
      params: const [],
      run: (src, p) {
        final stops = ((p['stops'] as List?) ?? const [0xFF000000, 0xFFFFFFFF])
            .map((e) => (e as num).toInt())
            .toList();
        return ImageFilters.gradientMap(src, stops);
      },
    ),

    // ---------------------------------------------------------- stylize
    FilterDef(
      kind: 'oilPaint',
      labelKey: 'filter.oil_paint',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'radius', labelKey: 'filter.brush_radius', min: 1, max: 6, def: 3, isInt: true),
        FilterParam(key: 'levels', labelKey: 'filter.levels_count', min: 2, max: 32, def: 12, isInt: true),
      ],
      run: (src, p) => ImageFilters.oilPaint(
            src,
            (p['radius'] as num).toInt(),
            (p['levels'] as num).toInt(),
          ),
    ),
    FilterDef(
      kind: 'halftone',
      labelKey: 'filter.halftone',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'cell', labelKey: 'filter.cell_size', min: 2, max: 24, def: 6, isInt: true),
        FilterParam(key: 'angle', labelKey: 'filter.screen_angle', min: 0, max: 90, def: 45),
      ],
      run: (src, p) => ImageFilters.halftone(
            src,
            (p['cell'] as num).toInt(),
            angle: (p['angle'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'pixelate',
      labelKey: 'filter.pixelate',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'block', labelKey: 'filter.block_size', min: 2, max: 64, def: 8, isInt: true),
      ],
      run: (src, p) => ImageFilters.pixelate(src, (p['block'] as num).toInt()),
    ),
    FilterDef(
      kind: 'emboss',
      labelKey: 'filter.emboss',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'strength', labelKey: 'filter.strength', min: 0.2, max: 5, def: 1),
      ],
      run: (src, p) => ImageFilters.emboss(src, (p['strength'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'edgeDetect',
      labelKey: 'filter.edge_detect',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 1, def: 1),
      ],
      run: (src, p) => ImageFilters.edgeDetect(src, (p['amount'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'sketch',
      labelKey: 'filter.sketch',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'radius', labelKey: 'filter.radius', min: 1, max: 30, def: 6),
      ],
      run: (src, p) => ImageFilters.sketch(src, (p['radius'] as num).toDouble()),
    ),
    FilterDef(
      kind: 'noise',
      labelKey: 'filter.noise',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 1, def: 0.2),
        FilterParam(key: 'seed', labelKey: 'filter.seed', min: 1, max: 999, def: 1, isInt: true),
      ],
      run: (src, p) => ImageFilters.noise(
            src,
            (p['amount'] as num).toDouble(),
            seed: (p['seed'] as num).toInt(),
          ),
    ),
    FilterDef(
      kind: 'vignette',
      labelKey: 'filter.vignette',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 1, def: 0.5),
        FilterParam(key: 'radius', labelKey: 'filter.radius', min: 0.2, max: 1.5, def: 0.75),
      ],
      run: (src, p) => ImageFilters.vignette(
            src,
            (p['amount'] as num).toDouble(),
            radius: (p['radius'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'bloom',
      labelKey: 'filter.bloom',
      groupKey: _blur,
      params: const [
        FilterParam(key: 'radius', labelKey: 'filter.radius', min: 1, max: 40, def: 10),
        FilterParam(key: 'amount', labelKey: 'filter.amount', min: 0, max: 1, def: 0.5),
      ],
      run: (src, p) => ImageFilters.bloom(
            src,
            (p['radius'] as num).toDouble(),
            (p['amount'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'motionBlur',
      labelKey: 'filter.motion_blur',
      groupKey: _blur,
      params: const [
        FilterParam(key: 'distance', labelKey: 'filter.distance', min: 0, max: 40, def: 10, isInt: true),
        FilterParam(key: 'angle', labelKey: 'filter.angle', min: 0, max: 360, def: 0),
      ],
      run: (src, p) => ImageFilters.motionBlur(
            src,
            (p['distance'] as num).toInt(),
            (p['angle'] as num).toDouble(),
          ),
    ),
    FilterDef(
      kind: 'ripple',
      labelKey: 'filter.ripple',
      groupKey: _stylize,
      params: const [
        FilterParam(key: 'amplitude', labelKey: 'filter.amplitude', min: 0, max: 40, def: 10),
        FilterParam(key: 'wavelength', labelKey: 'filter.wavelength', min: 4, max: 200, def: 40),
      ],
      run: (src, p) => ImageFilters.ripple(
            src,
            (p['amplitude'] as num).toDouble(),
            (p['wavelength'] as num).toDouble(),
          ),
    ),
  ];

  static final Map<String, FilterDef> _byKind = {
    for (final def in all) def.kind: def,
  };

  static FilterDef? byKind(String kind) => _byKind[kind];

  static List<FilterDef> inGroup(String groupKey) =>
      all.where((d) => d.groupKey == groupKey).toList();

  static List<String> get groupKeys =>
      all.map((d) => d.groupKey).toSet().toList();

  /// Applies a registered filter. Unknown kinds pass through unchanged.
  /// Missing parameters fall back to the filter's declared defaults, so
  /// projects saved with an older/partial parameter set still render.
  static RgbaImage apply(String kind, RgbaImage src, Map<String, dynamic> params) {
    final def = _byKind[kind];
    if (def == null) return src.copy();
    final merged = {...def.defaultParams(), ...params};
    return def.run(src, merged);
  }
}
