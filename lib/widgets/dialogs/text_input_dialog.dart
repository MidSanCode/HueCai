import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Modal text entry for the text tool: returns the typed string and the
/// chosen font size, or null when cancelled.
Future<TextInputResult?> showTextInputDialog(
  BuildContext context, {
  double initialFontSize = 32,
}) {
  final controller = TextEditingController();
  var fontSize = initialFontSize;
  return showDialog<TextInputResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('text.title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'text.hint'.tr(),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (v.trim().isEmpty) return;
                Navigator.of(ctx).pop(TextInputResult(v, fontSize));
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('text.size'.tr()),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 12,
                    max: 200,
                    divisions: 47,
                    label: fontSize.round().toString(),
                    onChanged: (v) => setState(() => fontSize = v),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text;
              if (v.trim().isEmpty) return;
              Navigator.of(ctx).pop(TextInputResult(v, fontSize));
            },
            child: Text('text.ok'.tr()),
          ),
        ],
      ),
    ),
  );
}

class TextInputResult {
  final String text;
  final double fontSize;
  const TextInputResult(this.text, this.fontSize);
}
