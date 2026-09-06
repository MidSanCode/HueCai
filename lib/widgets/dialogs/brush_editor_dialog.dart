import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../../providers/tool_provider.dart';
import '../../providers/app_settings.dart';
import '../../models/brush.dart';

class BrushEditorDialog extends StatefulWidget {
  const BrushEditorDialog({super.key});

  static Future<void> show(BuildContext context) {
    final tp = context.read<ToolProvider>();
    final as = context.read<AppSettings>();
    return showDialog(
      context: context,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tp),
          ChangeNotifierProvider.value(value: as),
        ],
        child: const BrushEditorDialog(),
      ),
    );
  }

  @override
  State<BrushEditorDialog> createState() => _BrushEditorDialogState();
}

class _BrushEditorDialogState extends State<BrushEditorDialog> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tp = context.watch<ToolProvider>();
    final as = context.watch<AppSettings>();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.brush, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('brush.editor'.tr()),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brush type selection
              Text('brush.panel'.tr(), style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: Brush.defaults().map((brush) {
                    final selected = tp.currentBrush.type == brush.type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(brush.nameKey.tr(), style: const TextStyle(fontSize: 10)),
                        selected: selected,
                        onSelected: (_) => tp.setBrush(brush),
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              _slider('brush.size'.tr(), tp.brushSize, 0.5, 100, tp.setBrushSize, tp.brushSize.toStringAsFixed(1)),
              _slider('brush.opacity'.tr(), tp.brushOpacity, 0, 1, tp.setBrushOpacity, '${(tp.brushOpacity * 100).round()}%'),
              const Divider(height: 20),
              // Velocity width section
              Text('brush.velocity'.tr(), style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('brush.velocity_enable'.tr(), style: const TextStyle(fontSize: 13)),
                value: as.velocityWidthEnabled,
                onChanged: (v) => as.setVelocityWidthEnabled(v),
              ),
              if (as.velocityWidthEnabled) ...[
                _slider('brush.velocity_min'.tr(), as.velocityMinScale, 0.1, 1.0, as.setVelocityMinScale, '${(as.velocityMinScale * 100).round()}%'),
                _slider('brush.velocity_max'.tr(), as.velocityMaxScale, 0.1, 1.0, as.setVelocityMaxScale, '${(as.velocityMaxScale * 100).round()}%'),
                _slider('brush.velocity_smooth'.tr(), as.velocitySmoothing, 0, 1, as.setVelocitySmoothing, '${(as.velocitySmoothing * 100).round()}%'),
                // Ink amount follows velocity too (brush feel: fast = drier).
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('brush.velocity_ink'.tr(), style: const TextStyle(fontSize: 13)),
                  value: as.velocityInkEnabled,
                  onChanged: (v) => as.setVelocityInkEnabled(v),
                ),
                if (as.velocityInkEnabled)
                  _slider('brush.velocity_ink_min'.tr(), as.velocityInkMinScale, 0.05, 1.0, as.setVelocityInkMinScale, '${(as.velocityInkMinScale * 100).round()}%'),
              ],
              const Divider(height: 16),
              // Pressure section
              Text('brush.pressure'.tr(), style: theme.textTheme.labelMedium),
              if (!as.hasPressure)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('brush.pressure_unavailable'.tr(), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ),
              const SizedBox(height: 4),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('brush.pressure_enable'.tr(), style: const TextStyle(fontSize: 13)),
                value: as.pressureWidthEnabled,
                onChanged: (v) => as.setPressureWidthEnabled(v),
              ),
              if (as.pressureWidthEnabled && as.hasPressure) ...[
                _slider('brush.pressure_min'.tr(), as.pressureMinScale, 0.1, 1.0, as.setPressureMinScale, '${(as.pressureMinScale * 100).round()}%'),
                _slider('brush.pressure_max'.tr(), as.pressureMaxScale, 0.1, 1.0, as.setPressureMaxScale, '${(as.pressureMaxScale * 100).round()}%'),
              ],
              // Velocity/Pressure blend slider
              _slider('brush.vp_blend'.tr(), as.velocityPressureBlend, 0, 1, as.setVelocityPressureBlend, '${(as.velocityPressureBlend * 100).round()}%'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('dialog.close'.tr()),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, String display) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(value: value, min: min, max: max, divisions: max > 1 ? (max - min).round() : 100, label: display, onChanged: onChanged),
          ),
          SizedBox(width: 36, child: Text(display, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
