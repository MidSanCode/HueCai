import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/project_provider.dart';
import '../../services/image_filters.dart';
import '../common/curve_editor.dart';

/// The five built-in filters.
enum FilterKind { gaussianBlur, unsharpMask, levels, curves, hueSaturation }

/// Opens the parameter dialog for [kind] and applies the filter to the
/// current layer on confirm.
Future<void> showFilterDialog(BuildContext context, FilterKind kind) async {
  final pp = context.read<ProjectProvider>();
  final index = pp.currentProject?.currentLayerIndex;
  if (index == null) return;
  final params = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _FilterDialog(kind: kind),
  );
  if (params == null) return;

  RgbaImage Function(RgbaImage) filter = switch (kind) {
    FilterKind.gaussianBlur =>
      (img) => ImageFilters.gaussianBlur(img, params['radius'] as double),
    FilterKind.unsharpMask => (img) => ImageFilters.unsharpMask(
          img,
          params['radius'] as double,
          params['amount'] as double,
          threshold: params['threshold'] as int,
        ),
    FilterKind.levels => (img) => ImageFilters.levels(
          img,
          inBlack: params['in_black'] as int,
          inWhite: params['in_white'] as int,
          gamma: params['gamma'] as double,
        ),
    FilterKind.curves => (img) => ImageFilters.curves(
          img,
          params['points'] as List<({double x, double y})>,
        ),
    FilterKind.hueSaturation => (img) => ImageFilters.hueSaturation(
          img,
          hueShift: params['hue'] as double,
          saturationScale: params['saturation'] as double,
          lightnessScale: params['lightness'] as double,
        ),
  };
  await pp.applyFilterToLayer(index, filter);
}

class _FilterDialog extends StatefulWidget {
  final FilterKind kind;
  const _FilterDialog({required this.kind});

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  // Blur / USM
  double _radius = 5;
  double _amount = 0.8;
  int _threshold = 0;
  // Levels
  int _inBlack = 0;
  int _inWhite = 255;
  double _gamma = 1.0;
  // Curves
  List<({double x, double y})> _curvePoints = [(x: 0, y: 0), (x: 255, y: 255)];
  // Hue/Saturation
  double _hue = 0;
  double _saturation = 1.0;
  double _lightness = 1.0;

  String get _titleKey => switch (widget.kind) {
        FilterKind.gaussianBlur => 'filter.gaussian_blur',
        FilterKind.unsharpMask => 'filter.unsharp_mask',
        FilterKind.levels => 'filter.levels',
        FilterKind.curves => 'filter.curves',
        FilterKind.hueSaturation => 'filter.hue_saturation',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_titleKey.tr()),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: switch (widget.kind) {
            FilterKind.gaussianBlur => [
                _slider('filter.radius', _radius, 0, 50,
                    (v) => setState(() => _radius = v)),
              ],
            FilterKind.unsharpMask => [
                _slider('filter.radius', _radius, 0, 20,
                    (v) => setState(() => _radius = v)),
                _slider('filter.amount', _amount, 0, 3,
                    (v) => setState(() => _amount = v)),
                _slider('filter.threshold', _threshold.toDouble(), 0, 50,
                    (v) => setState(() => _threshold = v.round())),
              ],
            FilterKind.levels => [
                _slider('filter.in_black', _inBlack.toDouble(), 0, 254,
                    (v) => setState(() => _inBlack = v.round())),
                _slider('filter.in_white', _inWhite.toDouble(), 1, 255,
                    (v) => setState(() => _inWhite = v.round())),
                _slider('filter.gamma', _gamma, 0.2, 5,
                    (v) => setState(() => _gamma = v)),
              ],
            FilterKind.curves => [
                Center(
                  child: CurveEditor(
                    points: _curvePoints,
                    onChanged: (p) => setState(() => _curvePoints = p),
                  ),
                ),
              ],
            FilterKind.hueSaturation => [
                _slider('filter.hue', _hue, -180, 180,
                    (v) => setState(() => _hue = v)),
                _slider('filter.saturation', _saturation, 0, 2,
                    (v) => setState(() => _saturation = v)),
                _slider('filter.lightness', _lightness, 0, 2,
                    (v) => setState(() => _lightness = v)),
              ],
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('dialog.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_collect()),
          child: Text('dialog.confirm'.tr()),
        ),
      ],
    );
  }

  Map<String, dynamic> _collect() => switch (widget.kind) {
        FilterKind.gaussianBlur => {'radius': _radius},
        FilterKind.unsharpMask => {
            'radius': _radius,
            'amount': _amount,
            'threshold': _threshold,
          },
        FilterKind.levels => {
            'in_black': _inBlack,
            'in_white': _inWhite,
            'gamma': _gamma,
          },
        FilterKind.curves => {'points': _curvePoints},
        FilterKind.hueSaturation => {
            'hue': _hue,
            'saturation': _saturation,
            'lightness': _lightness,
          },
      };

  Widget _slider(
    String labelKey,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${labelKey.tr()}: ${value.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 12)),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
