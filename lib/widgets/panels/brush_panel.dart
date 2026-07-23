import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../models/brush.dart';

class BrushPanel extends StatefulWidget {
  const BrushPanel({super.key});

  @override
  State<BrushPanel> createState() => _BrushPanelState();
}

class _BrushPanelState extends State<BrushPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<ToolProvider>(
      builder: (ctx, provider, _) {
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    children: [
                      Text('brush.panel'.tr(), style: theme.textTheme.labelMedium),
                      const Spacer(),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: Brush.defaults().length,
                      itemBuilder: (ctx, i) {
                        final brush = Brush.defaults()[i];
                        final selected = provider.currentBrush.type == brush.type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(brush.nameKey.tr(), style: const TextStyle(fontSize: 11)),
                            selected: selected,
                            onSelected: (_) => provider.setBrush(brush),
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('brush.size'.tr(), style: const TextStyle(fontSize: 11)),
                      Expanded(
                        child: Slider(
                          value: provider.brushSize,
                          min: 1,
                          max: 200,
                          divisions: 199,
                          label: '${provider.brushSize.round()}',
                          onChanged: (v) => provider.setBrushSize(v),
                        ),
                      ),
                      Text('${provider.brushSize.round()}', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  Row(
                    children: [
                      Text('brush.opacity'.tr(), style: const TextStyle(fontSize: 11)),
                      Expanded(
                        child: Slider(
                          value: provider.brushOpacity,
                          min: 0.0,
                          max: 1.0,
                          divisions: 100,
                          label: '${(provider.brushOpacity * 100).round()}%',
                          onChanged: (v) => provider.setBrushOpacity(v),
                        ),
                      ),
                      Text('${(provider.brushOpacity * 100).round()}%', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
