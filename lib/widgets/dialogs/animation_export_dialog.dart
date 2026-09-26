import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/animation.dart';
import '../../providers/project_provider.dart';
import '../../services/animation_export.dart';

enum AnimationExportFormat { gif, pngSequence }

/// Asks for a format + frame rate, then renders every frame and writes the
/// result. Shared by the file menu and the timeline panel.
Future<void> showAnimationExportDialog(BuildContext context) async {
  final provider = context.read<ProjectProvider>();
  final project = provider.currentProject;
  if (project == null) return;
  if (project.frames.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('animation.no_frames'.tr())),
    );
    return;
  }

  var format = AnimationExportFormat.gif;
  final fpsController = TextEditingController(text: '${project.animation.fps}');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text('animation.export_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('animation.export_hint'.tr()),
            const SizedBox(height: 12),
            SegmentedButton<AnimationExportFormat>(
              segments: [
                ButtonSegment(
                  value: AnimationExportFormat.gif,
                  icon: const Icon(Icons.gif_box_outlined, size: 18),
                  label: Text('animation.format_gif'.tr()),
                ),
                ButtonSegment(
                  value: AnimationExportFormat.pngSequence,
                  icon: const Icon(Icons.burst_mode_outlined, size: 18),
                  label: Text('animation.format_sequence'.tr()),
                ),
              ],
              selected: {format},
              onSelectionChanged: (value) =>
                  setState(() => format = value.first),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('animation.fps'.tr()),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: fpsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'animation.frame_count'.tr(namedArgs: {
                    'count': '${project.frames.length}',
                  }),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('animation.export_action'.tr()),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) {
    fpsController.dispose();
    return;
  }

  final fps = int.tryParse(fpsController.text.trim()) ?? project.animation.fps;
  fpsController.dispose();
  if (!context.mounted) return;
  await _runExport(context, provider, format, fps.clamp(1, 60));
}

Future<void> _runExport(
  BuildContext context,
  ProjectProvider provider,
  AnimationExportFormat format,
  int fps,
) async {
  final project = provider.currentProject;
  if (project == null) return;

  // Pick the destination before doing any heavy rendering.
  String? target;
  try {
    if (format == AnimationExportFormat.gif) {
      target = await FilePicker.platform.saveFile(
        dialogTitle: 'animation.export_action'.tr(),
        fileName: '${project.name}.gif',
        type: FileType.custom,
        allowedExtensions: const ['gif'],
      );
    } else {
      target = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'animation.export_action'.tr(),
      );
    }
  } catch (_) {
    target = null;
  }
  if (target == null || target.isEmpty) return;
  if (!context.mounted) return;

  final progress = ValueNotifier<int>(0);
  final total = project.frames.length;
  // Snapshot the frame list so playback/edit during export cannot shift it.
  final frames = List<AnimationFrame>.from(project.frames);
  final name = project.name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (_, done, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: total == 0 ? null : done / total,
            ),
            const SizedBox(height: 12),
            Text('animation.exporting'.tr(namedArgs: {
              'done': '$done',
              'total': '$total',
            })),
          ],
        ),
      ),
    ),
  );

  var message = '';
  try {
    final images = <ui.Image>[];
    for (final frame in frames) {
      images.add(await provider.rasterizeFrame(frame));
      progress.value = images.length;
    }
    if (format == AnimationExportFormat.gif) {
      final bytes = await AnimationExport.writeGif(images, fps, target);
      message = 'animation.export_done_gif'.tr(namedArgs: {
        'name': target.split(Platform.pathSeparator).last,
        'size': '${(bytes / 1024).round()} KB',
      });
    } else {
      final paths = await AnimationExport.writePngSequence(images, target,
          prefix: name.isEmpty ? 'frame' : name);
      message = 'animation.export_done_sequence'.tr(namedArgs: {
        'count': '${paths.length}',
        'dir': target,
      });
    }
  } catch (error) {
    message = 'animation.export_failed'.tr(namedArgs: {'error': '$error'});
  } finally {
    progress.dispose();
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
