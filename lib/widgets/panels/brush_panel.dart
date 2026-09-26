import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../models/brush.dart';
import 'brush_preset_section.dart';

class BrushPanel extends StatelessWidget {
  const BrushPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ToolProvider>(
      builder: (ctx, provider, _) {
        return Card(
          margin: const EdgeInsets.all(4),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('brush.panel'.tr(), style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: Brush.defaults().map((brush) {
                    final selected = provider.currentBrush.type == brush.type;
                    return ChoiceChip(
                      label: Text(brush.nameKey.tr(), style: const TextStyle(fontSize: 10)),
                      selected: selected,
                      onSelected: (_) => provider.setBrush(brush),
                      visualDensity: VisualDensity.compact,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                _sliderRow('brush.size'.tr(), provider.brushSize, 1, 200,
                    (v) => provider.setBrushSize(v),
                    '${provider.brushSize.round()}'),
                _sliderRow('brush.opacity'.tr(), provider.brushOpacity, 0, 1,
                    (v) => provider.setBrushOpacity(v),
                    '${(provider.brushOpacity * 100).round()}%'),
                const Divider(height: 10),
                const BrushPresetSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String display) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(fontSize: 10)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: max > 1 ? (max - min).round() : 100,
            label: display,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(display, style: const TextStyle(fontSize: 10), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
