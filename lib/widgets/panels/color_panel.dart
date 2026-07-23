import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../providers/tool_provider.dart';

class ColorPanel extends StatefulWidget {
  final ToolProvider toolProvider;
  const ColorPanel({super.key, required this.toolProvider});

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  final List<Color> _memoryColors = List.filled(20, Colors.transparent);

  static const List<Color> _defaultColors = [
    Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFE53935),
    Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFFFFEB3B),
    Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00BCD4),
    Color(0xFF795548),
  ];

  void _addMemory(Color c) {
    _memoryColors.remove(c);
    _memoryColors.insert(0, c);
    if (_memoryColors.length > 20) _memoryColors.removeLast();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tp = widget.toolProvider;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 140, height: 140,
              child: _ColorWheel(
                selectedColor: tp.primaryColor,
                onChanged: (c) {
                  tp.setPrimaryColor(c);
                  _addMemory(c);
                },
              ),
            ),
            const SizedBox(height: 8),
            _colorRow(theme, _defaultColors, tp, isDefault: true),
            const SizedBox(height: 4),
            _colorRow(theme, _memoryColors, tp),
          ],
        ),
      ),
    );
  }

  Widget _colorRow(ThemeData theme, List<Color> colors, ToolProvider tp, {bool isDefault = false}) {
    return Wrap(
      spacing: 2, runSpacing: 2,
      children: List.generate(colors.length, (i) {
        final c = colors[i];
        if (c == Colors.transparent && !isDefault) {
          return const SizedBox(width: 14, height: 14);
        }
        return GestureDetector(
          onTap: () {
            tp.setPrimaryColor(c);
            if (!isDefault) _addMemory(c);
          },
          onSecondaryTap: !isDefault
              ? () => setState(() => _memoryColors[i] = Colors.transparent)
              : null,
          child: Container(
            width: 14, height: 14,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: c == tp.primaryColor
                    ? theme.colorScheme.primary
                    : Colors.grey.shade400,
                width: c == tp.primaryColor ? 2 : 0.5,
              ),
            ),
          ),
        );
      }),
    );
  }
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

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.7;

    for (int a = 0; a < 360; a += 2) {
      final rad = a * math.pi / 180;
      final nextRad = (a + 2) * math.pi / 180;
      final color = HSVColor.fromAHSV(1, a.toDouble(), 1, 1).toColor();
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR - innerR;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: (outerR + innerR) / 2),
        -rad - math.pi / 2, -(nextRad - rad), false, p,
      );
    }

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
