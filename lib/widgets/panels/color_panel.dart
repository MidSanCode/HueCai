import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/tool_provider.dart';
import '../../services/gamut.dart';
import '../../services/palette_service.dart';

/// Which picker the panel shows: the classic hue wheel or the
/// square saturation/value field with a hue strip.
enum _PickerMode { wheel, square }

class ColorPanel extends StatefulWidget {
  final ToolProvider toolProvider;
  /// When provided, picked colors are routed here instead of the primary color.
  final ValueChanged<Color>? onPick;
  /// The color shown as active on the wheel when [onPick] is used.
  final Color? currentColor;
  const ColorPanel({
    super.key,
    required this.toolProvider,
    this.onPick,
    this.currentColor,
  });

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  static const List<Color> _defaultColors = [
    Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFE53935),
    Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFFFFEB3B),
    Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00BCD4),
    Color(0xFF795548),
  ];

  _PickerMode _mode = _PickerMode.wheel;
  final TextEditingController _hexCtrl = TextEditingController();
  bool _hexEditing = false;
  double _alpha = 1.0;

  @override
  void initState() {
    super.initState();
    _alpha = widget.currentColor?.a ?? widget.toolProvider.primaryColor.a;
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _active => widget.currentColor ?? widget.toolProvider.primaryColor;

  void _apply(Color c) {
    if (widget.onPick != null) {
      widget.onPick!(c);
      return;
    }
    widget.toolProvider.setPrimaryColor(c);
    widget.toolProvider.addMemoryColor(c);
  }

  /// Applies a color while keeping the panel's alpha channel.
  void _applyWithAlpha(Color c) =>
      _apply(c.withValues(alpha: _alpha));

  Future<void> _importPalette() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpl', 'txt', 'hex', 'pal'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    try {
      final text = await File(path).readAsString();
      final palette = PaletteCodec.parse(
        text,
        fallbackName: path.split(RegExp(r'[\\/]')).last,
      );
      if (palette == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('palette.import_failed'.tr())),
          );
        }
        return;
      }
      widget.toolProvider.setPalette(palette);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('palette.import_failed'.tr())),
        );
      }
    }
  }

  Future<void> _exportPalette() async {
    final palette = widget.toolProvider.palette;
    if (palette == null || palette.isEmpty) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'palette.export'.tr(),
      fileName: '${palette.name}.gpl',
      type: FileType.custom,
      allowedExtensions: ['gpl'],
    );
    if (path == null) return;
    await File(path).writeAsString(PaletteCodec.toGpl(palette));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('palette.exported'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tp = widget.toolProvider;
    final activeColor = _active;
    return Card(
      margin: const EdgeInsets.all(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<_PickerMode>(
                    segments: [
                      ButtonSegment(
                        value: _PickerMode.wheel,
                        icon: const Icon(Icons.palette, size: 14),
                        tooltip: 'color.wheel'.tr(),
                      ),
                      ButtonSegment(
                        value: _PickerMode.square,
                        icon: const Icon(Icons.crop_square, size: 14),
                        tooltip: 'color.square'.tr(),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() => _mode = s.first),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                _gamutBadge(theme, tp, activeColor),
              ],
            ),
            const SizedBox(height: 6),
            if (_mode == _PickerMode.wheel)
              SizedBox(
                width: 130, height: 130,
                child: _ColorWheel(
                  selectedColor: activeColor,
                  onChanged: _applyWithAlpha,
                ),
              )
            else
              SizedBox(
                width: 150, height: 130,
                child: _SquarePicker(
                  selectedColor: activeColor,
                  onChanged: _applyWithAlpha,
                ),
              ),
            const SizedBox(height: 6),
            _alphaRow(theme, activeColor),
            _gamutBanner(theme, tp, activeColor),
            const SizedBox(height: 4),
            _hexRow(theme, activeColor),
            const SizedBox(height: 6),
            _colorRow(theme, _defaultColors, tp, activeColor, isDefault: true),
            const SizedBox(height: 4),
            _colorRow(theme, tp.memoryColors, tp, activeColor),
            const Divider(height: 14),
            _paletteSection(theme, tp, activeColor),
          ],
        ),
      ),
    );
  }

  /// Gamut warning toggle: highlights colors the print profile cannot
  /// reproduce and offers the nearest in-gamut substitute.
  Widget _gamutBadge(ThemeData theme, ToolProvider tp, Color activeColor) {
    final enabled = tp.gamutWarningEnabled;
    final out = enabled && Gamut.isOutOfGamut(activeColor, tp.printProfile);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (enabled) ...[
          Tooltip(
            message: 'color.soft_proof'.tr(),
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: tp.softProofColor ?? activeColor,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.grey.shade400, width: 0.5),
              ),
            ),
          ),
          PopupMenuButton<PrintProfile>(
            tooltip: 'color.print_profile'.tr(),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.print_outlined, size: 15),
            onSelected: tp.setPrintProfile,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: PrintProfile.coated,
                child: Text('color.profile_coated'.tr()),
              ),
              PopupMenuItem(
                value: PrintProfile.uncoated,
                child: Text('color.profile_uncoated'.tr()),
              ),
              PopupMenuItem(
                value: PrintProfile.newsprint,
                child: Text('color.profile_newsprint'.tr()),
              ),
            ],
          ),
        ],
        Tooltip(
          message: enabled
              ? (out ? 'color.out_of_gamut'.tr() : 'color.in_gamut'.tr())
              : 'color.gamut_warning'.tr(),
          child: IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            icon: Icon(
              out
                  ? Icons.warning_amber
                  : (enabled ? Icons.visibility : Icons.visibility_off_outlined),
              size: 15,
              color: out
                  ? const Color(0xFFE65100)
                  : (enabled ? theme.colorScheme.primary : null),
            ),
            onPressed: tp.toggleGamutWarning,
          ),
        ),
      ],
    );
  }

  /// Inline "out of gamut" banner with a one-tap fix.
  Widget _gamutBanner(ThemeData theme, ToolProvider tp, Color activeColor) {
    if (!tp.gamutWarningEnabled) return const SizedBox.shrink();
    if (!Gamut.isOutOfGamut(activeColor, tp.printProfile)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'color.out_of_gamut'.tr(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: const Color(0xFFE65100)),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final fixed = Gamut.nearestInGamut(activeColor, tp.printProfile);
              _apply(fixed.withValues(alpha: activeColor.a));
            },
            child: Text('color.fix_gamut'.tr(),
                style: theme.textTheme.labelSmall),
          ),
        ],
      ),
    );
  }

  Widget _alphaRow(ThemeData theme, Color activeColor) {
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text('A', style: theme.textTheme.labelSmall),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: _alpha,
              onChanged: (v) {
                setState(() => _alpha = v);
                _apply(activeColor.withValues(alpha: v));
              },
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text('${(_alpha * 100).round()}',
              style: theme.textTheme.labelSmall),
        ),
      ],
    );
  }

  Widget _hexRow(ThemeData theme, Color activeColor) {
    final hex = PaletteCodec.hexOf(activeColor);
    if (!_hexEditing) _hexCtrl.text = hex;
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text('HEX', style: theme.textTheme.labelSmall),
        ),
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: _hexCtrl,
              style: theme.textTheme.labelSmall,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(),
              ),
              onTap: () => _hexEditing = true,
              onSubmitted: (value) {
                _hexEditing = false;
                final parsed = PaletteCodec.parseHexList(value);
                if (parsed != null && parsed.colors.isNotEmpty) {
                  _apply(parsed.colors.first.withValues(alpha: _alpha));
                }
                setState(() {});
              },
              onEditingComplete: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paletteSection(ThemeData theme, ToolProvider tp, Color activeColor) {
    final palette = tp.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                palette == null
                    ? 'palette.none'.tr()
                    : '${palette.name} (${palette.length})',
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'palette.add_color'.tr(),
              icon: const Icon(Icons.add_circle_outline, size: 15),
              onPressed: () => tp.addPaletteColor(activeColor),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'palette.import'.tr(),
              icon: const Icon(Icons.file_open, size: 15),
              onPressed: _importPalette,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'palette.export'.tr(),
              icon: const Icon(Icons.save_alt, size: 15),
              onPressed: (palette == null || palette.isEmpty)
                  ? null
                  : _exportPalette,
            ),
          ],
        ),
        if (palette != null && palette.isNotEmpty)
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: List.generate(palette.length, (i) {
              final c = palette.colors[i];
              return GestureDetector(
                onTap: () => _apply(c.withValues(alpha: _alpha)),
                onSecondaryTap: () => tp.removePaletteColor(i),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: c.toARGB32() == activeColor.toARGB32()
                          ? theme.colorScheme.primary
                          : Colors.grey.shade400,
                      width: c.toARGB32() == activeColor.toARGB32() ? 2 : 0.5,
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _colorRow(
    ThemeData theme,
    List<Color> colors,
    ToolProvider tp,
    Color activeColor, {
    bool isDefault = false,
  }) {
    return Wrap(
      spacing: 2, runSpacing: 2,
      children: List.generate(colors.length, (i) {
        final c = colors[i];
        if (c == Colors.transparent && !isDefault) {
          return const SizedBox(width: 14, height: 14);
        }
        return GestureDetector(
          onTap: () => _apply(c),
          onSecondaryTap: !isDefault
              ? () => tp.clearMemoryColor(i)
              : null,
          child: Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: c == activeColor
                    ? theme.colorScheme.primary
                    : Colors.grey.shade400,
                width: c == activeColor ? 2 : 0.5,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Square saturation/value field with a vertical hue strip — the
/// "advanced" alternative to the hue wheel.
class _SquarePicker extends StatefulWidget {
  final Color selectedColor;
  final ValueChanged<Color> onChanged;
  const _SquarePicker({required this.selectedColor, required this.onChanged});

  @override
  State<_SquarePicker> createState() => _SquarePickerState();
}

class _SquarePickerState extends State<_SquarePicker> {
  late double _hue;
  late double _sat;
  late double _val;
  bool _draggingSquare = false;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.selectedColor);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
  }

  @override
  void didUpdateWidget(_SquarePicker old) {
    super.didUpdateWidget(old);
    if (widget.selectedColor.toARGB32() != old.selectedColor.toARGB32() &&
        !_draggingSquare) {
      final hsv = HSVColor.fromColor(widget.selectedColor);
      _hue = hsv.hue;
      _sat = hsv.saturation;
      _val = hsv.value;
    }
  }

  void _emit() =>
      widget.onChanged(HSVColor.fromAHSV(1, _hue, _sat, _val).toColor());

  void _pickSquare(Offset pos, Size size) {
    final w = size.width - 14;
    setState(() {
      _sat = (pos.dx / w).clamp(0.0, 1.0);
      _val = 1.0 - (pos.dy / size.height).clamp(0.0, 1.0);
    });
    _emit();
  }

  void _pickHue(Offset pos, Size size) {
    setState(() {
      _hue = (pos.dy / size.height).clamp(0.0, 1.0) * 360.0;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Row(
          children: [
            Expanded(
              child: GestureDetector(
                onPanStart: (d) {
                  _draggingSquare = true;
                  _pickSquare(d.localPosition, size);
                },
                onPanUpdate: (d) => _pickSquare(d.localPosition, size),
                onPanEnd: (_) => _draggingSquare = false,
                onTapDown: (d) => _pickSquare(d.localPosition, size),
                child: CustomPaint(
                  painter: _SquarePainter(
                    hue: _hue,
                    sat: _sat,
                    val: _val,
                  ),
                  size: Size(size.width, size.height),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 12,
              child: GestureDetector(
                onPanStart: (d) => _pickHue(d.localPosition, size),
                onPanUpdate: (d) => _pickHue(d.localPosition, size),
                onTapDown: (d) => _pickHue(d.localPosition, size),
                child: CustomPaint(
                  painter: _HueStripPainter(),
                  size: Size(12, size.height),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SquarePainter extends CustomPainter {
  final double hue;
  final double sat;
  final double val;
  _SquarePainter({required this.hue, required this.sat, required this.val});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Horizontal: white → pure hue. Vertical: transparent → black.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(size.width, 0),
          [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [Colors.transparent, Colors.black],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.grey.shade400
        ..strokeWidth = 1,
    );
    final cx = sat * size.width;
    final cy = (1 - val) * size.height;
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      5,
      Paint()
        ..color = HSVColor.fromAHSV(1, hue, sat, val).toColor()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) =>
      old.hue != hue || old.sat != sat || old.val != val;
}

class _HueStripPainter extends CustomPainter {
  static final List<Color> _colors = List.generate(
    360,
    (i) => HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor(),
  );
  static final List<double> _stops =
      List.generate(360, (i) => i / 359.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          _colors,
          _stops,
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.grey.shade400
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_HueStripPainter old) => false;
}

class _ColorWheel extends StatefulWidget {
  final Color selectedColor;
  final ValueChanged<Color> onChanged;
  const _ColorWheel({required this.selectedColor, required this.onChanged});

  @override
  State<_ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<_ColorWheel> {
  late double _hue;
  late double _sat;
  late double _val;
  bool _inTriangle = false;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.selectedColor);
    _hue = hsv.hue;
    _sat = hsv.saturation;
    _val = hsv.value;
  }

  @override
  void didUpdateWidget(_ColorWheel old) {
    super.didUpdateWidget(old);
    if (widget.selectedColor.toARGB32() != old.selectedColor.toARGB32()) {
      final hsv = HSVColor.fromColor(widget.selectedColor);
      _hue = hsv.hue;
      _sat = hsv.saturation;
      _val = hsv.value;
    }
  }

  Offset _top(Offset center, double r) => Offset(center.dx, center.dy - r);
  Offset _bl(Offset center, double r) => Offset(center.dx - r * 0.8660254, center.dy + r * 0.5);
  Offset _br(Offset center, double r) => Offset(center.dx + r * 0.8660254, center.dy + r * 0.5);

  bool _isInTriangle(Offset p, Offset center, double r) {
    final top = _top(center, r), bl = _bl(center, r), br = _br(center, r);
    final area = _triangleArea(top, bl, br);
    if (area == 0) return false;
    final u = _triangleArea(p, bl, br) / area;
    final v = _triangleArea(top, p, br) / area;
    final w = 1 - u - v;
    return u >= -0.01 && v >= -0.01 && w >= -0.01;
  }

  void _pick(Offset pos, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final dx = pos.dx - cx, dy = pos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.7;

    if (dist > outerR || dist < 4) return;

    if (_inTriangle || dist <= innerR) {
      final triR = innerR;
      final center = Offset(cx, cy);
      final top = _top(center, triR);
      final bl = _bl(center, triR);
      final br = _br(center, triR);

      if (!_inTriangle) {
        if (!_isInTriangle(pos, center, triR)) return;
        _inTriangle = true;
      }

      final area = _triangleArea(top, bl, br);
      if (area == 0) return;
      final u = (_triangleArea(pos, bl, br) / area).clamp(0.0, 1.0);
      final v = (_triangleArea(top, pos, br) / area).clamp(0.0, 1.0);
      final w = (1 - u - v).clamp(0.0, 1.0);
      _sat = w;
      _val = (u + w).clamp(0.0, 1.0);
      widget.onChanged(HSVColor.fromAHSV(1, _hue, _sat, _val).toColor());
    } else {
      _inTriangle = false;
      final angle = math.atan2(dy, dx) * 180 / math.pi;
      _hue = (angle + 360) % 360;
      widget.onChanged(HSVColor.fromAHSV(1, _hue, _sat, _val).toColor());
    }
  }

  double _triangleArea(Offset a, Offset b, Offset c) {
    return ((b.dx - a.dx) * (c.dy - a.dy) - (c.dx - a.dx) * (b.dy - a.dy)).abs() / 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (d) {
            _inTriangle = false;
            _pick(d.localPosition, size);
          },
          onPanUpdate: (d) => _pick(d.localPosition, size),
          onPanEnd: (_) => _inTriangle = false,
          child: CustomPaint(
            painter: _WheelPainter(
              selectedColor: widget.selectedColor,
              hue: _hue,
              sat: _sat,
              val: _val,
            ),
            size: size,
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Color selectedColor;
  final double hue;
  final double sat;
  final double val;

  _WheelPainter({required this.selectedColor, required this.hue, required this.sat, required this.val});

  /// One color per degree of hue, precomputed once for the sweep ring.
  static final List<Color> _ringColors = List.generate(
    360,
    (i) => HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor(),
  );

  /// Matching stops for [_ringColors]. `ui.Gradient.sweep` requires stops to
  /// be supplied whenever more than two colors are given.
  static final List<double> _ringStops =
      List.generate(360, (i) => i / 359.0);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.7;

    // Hue ring drawn as a single sweep-gradient annulus (even‑odd fill of an
    // outer circle minus an inner circle). This replaces ~180 per‑slice arc
    // calls with one path, which also avoids banding on the wheel.
    final shader = ui.Gradient.sweep(
      Offset(cx, cy),
      _ringColors,
      _ringStops,
    );
    final ringPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outerR))
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: innerR));
    canvas.drawPath(ringPath, Paint()..shader = shader);

    final triR = innerR;
    final top = Offset(cx, cy - triR);
    final bl = Offset(cx - triR * 0.8660254, cy + triR * 0.5);
    final br = Offset(cx + triR * 0.8660254, cy + triR * 0.5);

    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final verts = ui.Vertices(
      ui.VertexMode.triangles,
      [top, bl, br],
      colors: [Colors.white, Colors.black, hueColor],
    );
    canvas.drawVertices(verts, BlendMode.srcOver, Paint());

    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..close();
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.grey.shade400
      ..strokeWidth = 1);

    final pickX = (val - sat) * top.dx + (1 - val) * bl.dx + sat * br.dx;
    final pickY = (val - sat) * top.dy + (1 - val) * bl.dy + sat * br.dy;

    canvas.drawCircle(Offset(pickX, pickY), 4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(pickX, pickY), 4, Paint()
      ..color = selectedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.selectedColor != selectedColor || old.hue != hue || old.sat != sat || old.val != val;
}
