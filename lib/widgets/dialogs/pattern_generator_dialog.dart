import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/pattern.dart';
import '../../providers/tool_provider.dart';
import '../common/pattern_thumb.dart';
import '../panels/color_panel.dart';

/// Opens the dot / screentone generator. Returns the pattern the user built,
/// or null when cancelled.
Future<PatternSpec?> showPatternGeneratorDialog(
  BuildContext context, {
  PatternSpec? initial,
}) =>
    showDialog<PatternSpec>(
      context: context,
      builder: (_) => PatternGeneratorDialog(initial: initial),
    );

/// 网点生成器: builds a [PatternSpec] with a live preview.
///
/// The generator is deliberately parametric — the result is stored inline in
/// whatever it is applied to, so no bitmap has to be shipped or reloaded.
class PatternGeneratorDialog extends StatefulWidget {
  final PatternSpec? initial;

  const PatternGeneratorDialog({super.key, this.initial});

  @override
  State<PatternGeneratorDialog> createState() => _PatternGeneratorDialogState();
}

class _PatternGeneratorDialogState extends State<PatternGeneratorDialog> {
  late PatternKind _kind;
  late double _spacing;
  late double _thickness;
  late double _angleDegrees;
  late double _density;
  late Color _foreground;
  late Color _background;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? PatternSpec.dotScreen();
    _kind = base.kind;
    _spacing = base.spacing;
    _thickness = base.thickness;
    _angleDegrees = base.angle * 180 / 3.141592653589793;
    _density = base.density;
    _foreground = base.foreground;
    _background = base.background;
    _nameController = TextEditingController(
      text: widget.initial?.name ?? 'pattern.custom'.tr(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  PatternSpec get _spec => PatternSpec(
        id: widget.initial?.id ?? const Uuid().v4(),
        name: _nameController.text.trim().isEmpty
            ? 'pattern.custom'
            : _nameController.text.trim(),
        kind: _kind,
        spacing: _spacing,
        thickness: _thickness,
        angle: _angleDegrees * 3.141592653589793 / 180,
        density: _density,
        foreground: _foreground,
        background: _background,
      );

  bool get _showsDensity =>
      _kind == PatternKind.noise || _kind == PatternKind.paper;

  bool get _showsThickness =>
      _kind != PatternKind.noise && _kind != PatternKind.paper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('pattern.generator_title'.tr()),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: PatternThumb(spec: _spec, size: 120),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'pattern.name'.tr(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kind in PatternKind.values)
                    ChoiceChip(
                      label: Text(_kindLabel(kind),
                          style: const TextStyle(fontSize: 11)),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _slider('pattern.spacing', _spacing, 2, 48, (v) => _spacing = v),
              if (_showsThickness)
                _slider('pattern.thickness', _thickness, 0.5, 12,
                    (v) => _thickness = v),
              if (_showsDensity)
                _slider('pattern.density', _density, 0.05, 1,
                    (v) => _density = v),
              _slider('pattern.angle', _angleDegrees, 0, 180,
                  (v) => _angleDegrees = v),
              const SizedBox(height: 4),
              Row(
                children: [
                  _colorSwatch('pattern.foreground', _foreground, (c) {
                    setState(() => _foreground = c);
                  }),
                  const SizedBox(width: 12),
                  _colorSwatch('pattern.background', _background, (c) {
                    setState(() => _background = c);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('dialog.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_spec),
          child: Text('dialog.confirm'.tr()),
        ),
      ],
    );
  }

  String _kindLabel(PatternKind kind) => switch (kind) {
        PatternKind.dots => 'pattern.kind_dots'.tr(),
        PatternKind.lines => 'pattern.kind_lines'.tr(),
        PatternKind.cross => 'pattern.kind_cross'.tr(),
        PatternKind.checker => 'pattern.kind_checker'.tr(),
        PatternKind.grid => 'pattern.kind_grid'.tr(),
        PatternKind.noise => 'pattern.kind_noise'.tr(),
        PatternKind.paper => 'pattern.kind_paper'.tr(),
      };

  Widget _slider(
    String labelKey,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    final label = labelKey.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (v) => setState(() => onChanged(v)),
        ),
      ],
    );
  }

  Widget _colorSwatch(String labelKey, Color color, ValueChanged<Color> onPick) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: () {
          final tp = context.read<ToolProvider>();
          showModalBottomSheet(
            context: context,
            builder: (_) => ColorPanel(
              toolProvider: tp,
              currentColor: color,
              onPick: onPick,
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(labelKey.tr(),
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
