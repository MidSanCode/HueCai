import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import '../../providers/project_provider.dart';
import '../../services/filter_registry.dart';
import '../../services/image_filters.dart';
import 'filter_dialog.dart';
import 'vector_warning.dart';

/// Generic, registry-driven filter dialog: renders one slider per declared
/// parameter, so every registered filter gets a UI for free.
class GenericFilterDialog extends StatefulWidget {
  final FilterDef def;

  /// When true the dialog only picks parameters (adjustment layers) instead
  /// of applying the filter to the current layer.
  final bool pickOnly;

  /// Initial values (editing an existing adjustment layer).
  final Map<String, dynamic>? initial;

  const GenericFilterDialog({
    super.key,
    required this.def,
    this.pickOnly = false,
    this.initial,
  });

  @override
  State<GenericFilterDialog> createState() => _GenericFilterDialogState();
}

class _GenericFilterDialogState extends State<GenericFilterDialog> {
  late Map<String, dynamic> _values;

  @override
  void initState() {
    super.initState();
    _values = {
      ...widget.def.defaultParams(),
      ...?widget.initial,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.def.labelKey.tr()),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in widget.def.params) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(p.labelKey.tr(),
                          style: theme.textTheme.labelMedium),
                    ),
                    Text(
                      p.isInt
                          ? '${(_values[p.key] as num).round()}'
                          : (_values[p.key] as num).toStringAsFixed(2),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                Slider(
                  value: (p.clampValue((_values[p.key] as num).toDouble())),
                  min: p.min,
                  max: p.max,
                  divisions: p.isInt ? (p.max - p.min).round() : 100,
                  onChanged: (v) => setState(() {
                    _values[p.key] = p.isInt ? v.round() : v;
                  }),
                ),
              ],
              if (widget.def.params.isEmpty)
                Text('filter.no_params'.tr(),
                    style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () async {
            if (widget.pickOnly) {
              Navigator.of(context).pop(_values);
              return;
            }
            final pp = context.read<ProjectProvider>();
            final index = pp.currentProject?.currentLayerIndex;
            final values = Map<String, dynamic>.from(_values);
            final navigator = Navigator.of(context);
            if (index != null) {
              if (!await confirmVectorRasterize(context, pp, index)) {
                return;
              }
              await pp.applyFilterToLayer(
                index,
                (img) => FilterRegistry.apply(widget.def.kind, img, values),
              );
            }
            navigator.pop();
          },
          child: Text('common.ok'.tr()),
        ),
      ],
    );
  }
}

/// Opens the generic dialog and returns the chosen parameters (adjustment
/// layer flow), or null when cancelled.
Future<Map<String, dynamic>?> pickFilterParams(
  BuildContext context,
  FilterDef def, {
  Map<String, dynamic>? initial,
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          GenericFilterDialog(def: def, pickOnly: true, initial: initial),
    );

/// Opens the generic dialog and applies the filter to the current layer.
Future<void> showRegistryFilterDialog(BuildContext context, FilterDef def) =>
    showDialog<void>(
      context: context,
      builder: (_) => GenericFilterDialog(def: def),
    );

/// Convenience wrapper: builds an [AdjustmentSpec] from picked parameters.
AdjustmentSpec specFromParams(String kind, Map<String, dynamic> params) =>
    AdjustmentSpec(kind, params);

/// Browse-all-filters dialog: the full registry grouped by category with a
/// text filter. Picking one opens its parameter dialog.
Future<void> showFilterBrowser(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _FilterBrowserDialog(),
    );

class _FilterBrowserDialog extends StatefulWidget {
  const _FilterBrowserDialog();

  @override
  State<_FilterBrowserDialog> createState() => _FilterBrowserDialogState();
}

class _FilterBrowserDialogState extends State<_FilterBrowserDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = FilterRegistry.groupKeys;
    final q = _query.trim().toLowerCase();
    return AlertDialog(
      title: Text('filter.browser'.tr()),
      content: SizedBox(
        width: 380,
        height: 460,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'filter.search_hint'.tr(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final group in groups) ...[
                    Builder(builder: (_) {
                      final defs = FilterRegistry.inGroup(group).where((d) {
                        if (q.isEmpty) return true;
                        return d.labelKey.tr().toLowerCase().contains(q) ||
                            d.kind.toLowerCase().contains(q);
                      }).toList();
                      if (defs.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Text(group.tr(),
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary)),
                      );
                    }),
                    for (final def in FilterRegistry.inGroup(group))
                      if (q.isEmpty ||
                          def.labelKey.tr().toLowerCase().contains(q) ||
                          def.kind.toLowerCase().contains(q))
                        ListTile(
                          dense: true,
                          title: Text(def.labelKey.tr()),
                          onTap: () {
                            final navigator = Navigator.of(context);
                            final kind = def.kind;
                            if (_legacyKinds.contains(kind)) {
                              navigator.pop();
                              final legacy = FilterKind.values.firstWhere(
                                  (k) => _legacyKindName(k) == kind);
                              showFilterDialog(context, legacy);
                              return;
                            }
                            navigator.pop();
                            showRegistryFilterDialog(context, def);
                          },
                        ),
                  ],
                ],
              ),
            ),
          ],
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
}

const _legacyKinds = <String>{
  'gaussianBlur',
  'unsharpMask',
  'levels',
  'curves',
  'hueSaturation',
};

String _legacyKindName(FilterKind kind) => switch (kind) {
      FilterKind.gaussianBlur => 'gaussianBlur',
      FilterKind.unsharpMask => 'unsharpMask',
      FilterKind.levels => 'levels',
      FilterKind.curves => 'curves',
      FilterKind.hueSaturation => 'hueSaturation',
    };
