import 'dart:math' as math;
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

class _ColorWheel extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onChanged;
  const _ColorWheel({required this.selectedColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (d) => _pick(d.localPosition),
      onPanUpdate: (d) => _pick(d.localPosition),
      child: CustomPaint(
        painter: _WheelPainter(selectedColor: selectedColor),
        size: const Size(140, 140),
      ),
    );
  }

  void _pick(Offset pos) {
    final cx = 70.0, cy = 70.0, radius = 65.0;
    final dx = pos.dx - cx, dy = pos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > radius || dist < 5) return;
    final hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final sat = (dist / radius).clamp(0.0, 1.0);
    onChanged(HSVColor.fromAHSV(1, hue, sat, 1).toColor());
  }
}

class _WheelPainter extends CustomPainter {
  final Color selectedColor;
  _WheelPainter({required this.selectedColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = size.width / 2 - 5;
    for (int a = 0; a < 360; a += 2) {
      final rad = a * math.pi / 180;
      final nextRad = (a + 2) * math.pi / 180;
      final color = HSVColor.fromAHSV(1, a.toDouble(), 1, 1).toColor();
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -rad - math.pi / 2, -(nextRad - rad), false, p,
      );
    }
    final hsv = HSVColor.fromColor(selectedColor);
    final angle = hsv.hue * math.pi / 180 - math.pi / 2;
    final dist = hsv.saturation * r;
    final px = cx + dist * math.cos(angle);
    final py = cy + dist * math.sin(angle);
    canvas.drawCircle(Offset(px, py), 5, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(px, py), 5, Paint()
      ..color = selectedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.selectedColor != selectedColor;
}
