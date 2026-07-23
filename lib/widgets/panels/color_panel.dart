import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../providers/tool_provider.dart';

class ColorPanel extends StatelessWidget {
  final ToolProvider toolProvider;

  const ColorPanel({super.key, required this.toolProvider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('color.panel'.tr(), style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _pickColor(context, true),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: toolProvider.primaryColor,
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => toolProvider.swapColors(),
                      child: Icon(Icons.swap_vert, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _pickColor(context, false),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: toolProvider.secondaryColor,
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context, bool isPrimary) {
    Color pickedColor = isPrimary
        ? toolProvider.primaryColor
        : toolProvider.secondaryColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('color.panel'.tr()),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) => pickedColor = color,
            enableAlpha: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('new_project.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              if (isPrimary) {
                toolProvider.setPrimaryColor(pickedColor);
              } else {
                toolProvider.setSecondaryColor(pickedColor);
              }
              Navigator.of(ctx).pop();
            },
            child: Text('dialog.save'.tr()),
          ),
        ],
      ),
    );
  }
}
