import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Curated system font list (Windows-first, bilingual display names).
/// Flutter resolves these through the platform font registry at paint time.
const List<(String, String)> kTextFonts = [
  ('Microsoft YaHei', '微软雅黑 Microsoft YaHei'),
  ('SimHei', '黑体 SimHei'),
  ('SimSun', '宋体 SimSun'),
  ('KaiTi', '楷体 KaiTi'),
  ('FangSong', '仿宋 FangSong'),
  ('DengXian', '等线 DengXian'),
  ('Segoe UI', 'Segoe UI'),
  ('Arial', 'Arial'),
  ('Times New Roman', 'Times New Roman'),
  ('Courier New', 'Courier New'),
  ('Georgia', 'Georgia'),
  ('Verdana', 'Verdana'),
  ('Comic Sans MS', 'Comic Sans MS'),
];

/// Modal text entry for the text tool: returns the typed string, the chosen
/// font size and font family, or null when cancelled.
Future<TextInputResult?> showTextInputDialog(
  BuildContext context, {
  double initialFontSize = 32,
  String initialFontFamily = 'Microsoft YaHei',
}) {
  final controller = TextEditingController();
  var fontSize = initialFontSize;
  var fontFamily = initialFontFamily;
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
                Navigator.of(ctx)
                    .pop(TextInputResult(v, fontSize, fontFamily));
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
            const SizedBox(height: 4),
            Row(
              children: [
                Text('text.font'.tr()),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: fontFamily,
                    isExpanded: true,
                    items: [
                      for (final f in kTextFonts)
                        DropdownMenuItem(
                          value: f.$1,
                          child: Text(
                            f.$2,
                            style: TextStyle(fontFamily: f.$1, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => fontFamily = v ?? fontFamily),
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
              Navigator.of(ctx).pop(TextInputResult(v, fontSize, fontFamily));
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
  final String fontFamily;
  const TextInputResult(this.text, this.fontSize, this.fontFamily);
}
