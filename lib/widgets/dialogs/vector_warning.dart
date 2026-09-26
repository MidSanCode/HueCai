import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../providers/project_provider.dart';

/// Asks before a destructive raster operation bakes a vector layer down to
/// pixels.
///
/// Vector layers are a semantic marker, not a rendering mode, so filters and
/// flattening still work on them — but the user gets a say first, because the
/// operation is irreversible for the layer's vector nature. Returns true when
/// the caller may proceed (also when the layer is not a vector layer).
Future<bool> confirmVectorRasterize(
  BuildContext context,
  ProjectProvider pp,
  int index,
) async {
  if (!pp.isVectorLayer(index)) return true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('layer.vector_warning_title'.tr()),
      content: Text('layer.vector_warning_body'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('dialog.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('dialog.confirm'.tr()),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
