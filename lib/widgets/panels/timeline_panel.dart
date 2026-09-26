import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/animation.dart';
import '../../models/layer.dart';
import '../../providers/project_provider.dart';
import '../dialogs/animation_export_dialog.dart';

/// Bottom timeline strip: frame thumbnails, playback transport, playback
/// settings (fps / onion skin) and the animation export entry point.
class TimelinePanel extends StatefulWidget {
  const TimelinePanel({super.key});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  Timer? _playback;
  bool _playing = false;
  bool _collapsed = false;

  @override
  void dispose() {
    _playback?.cancel();
    super.dispose();
  }

  void _togglePlay() {
    if (_playing) {
      _stopPlayback();
      return;
    }
    final provider = context.read<ProjectProvider>();
    if (provider.currentProject == null) return;
    if (provider.currentProject!.frames.isEmpty) {
      provider.ensureTimeline();
    }
    if (provider.currentProject!.frames.length < 2) return;
    setState(() => _playing = true);
    _restartTimer(provider.currentProject!.animation.fps);
  }

  void _stopPlayback() {
    _playback?.cancel();
    _playback = null;
    if (_playing) setState(() => _playing = false);
  }

  void _restartTimer(int fps) {
    _playback?.cancel();
    final interval = Duration(milliseconds: (1000 / (fps <= 0 ? 12 : fps)).round());
    _playback = Timer.periodic(interval, (_) {
      if (!mounted) return;
      final provider = context.read<ProjectProvider>();
      final project = provider.currentProject;
      if (project == null || project.frames.length < 2) {
        _stopPlayback();
        return;
      }
      if (!project.animation.loop && project.currentFrame >= project.frames.length - 1) {
        _stopPlayback();
        return;
      }
      provider.nextFrame();
      setState(() {});
    });
  }

  /// The frame list with the live (uncommitted) content substituted for the
  /// frame currently being edited, so thumbnails track the canvas.
  List<AnimationFrame> _framesWithLiveCurrent(ProjectProvider provider) {
    final project = provider.currentProject!;
    final frames = List<AnimationFrame>.from(project.frames);
    final index = project.currentFrame.clamp(0, frames.length - 1);
    frames[index] = AnimationFrame(
      id: frames[index].id,
      layers: AnimationFrame.snapshot([
        for (final layer in project.layers)
          (id: layer.id, drawables: layer.drawables),
      ]),
    );
    return frames;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProjectProvider>();
    final project = provider.currentProject;
    final theme = Theme.of(context);

    if (project == null) return const SizedBox.shrink();
    // A still project shows a single "start animation" affordance instead of
    // the full transport, so the strip does not steal space needlessly.
    final hasTimeline = project.frames.isNotEmpty;

    if (_collapsed) {
      return Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: 24,
          child: Row(children: [
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.expand_less, size: 16),
              tooltip: 'timeline.title'.tr(),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => setState(() => _collapsed = false),
            ),
            Text('timeline.title'.tr(), style: theme.textTheme.labelSmall),
            const Spacer(),
          ]),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.expand_more, size: 16),
              tooltip: 'timeline.collapse'.tr(),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                _stopPlayback();
                setState(() => _collapsed = true);
              },
            ),
            Text('timeline.title'.tr(),
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (hasTimeline)
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 18),
                tooltip: _playing ? 'timeline.pause'.tr() : 'timeline.play'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: _togglePlay,
              ),
            if (hasTimeline)
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 18),
                tooltip: 'timeline.prev_frame'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: () {
                  _stopPlayback();
                  provider.previousFrame();
                },
              ),
            if (hasTimeline)
              IconButton(
                icon: const Icon(Icons.skip_next, size: 18),
                tooltip: 'timeline.next_frame'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: () {
                  _stopPlayback();
                  provider.nextFrame();
                },
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'timeline.add_frame'.tr(),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () {
                _stopPlayback();
                provider.addFrame();
              },
            ),
            if (hasTimeline)
              IconButton(
                icon: const Icon(Icons.content_copy, size: 16),
                tooltip: 'timeline.duplicate_frame'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: () {
                  _stopPlayback();
                  provider.duplicateFrame();
                },
              ),
            if (hasTimeline)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'timeline.delete_frame'.tr(),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                onPressed: project.frames.length < 2
                    ? null
                    : () {
                        _stopPlayback();
                        provider.deleteFrame(project.currentFrame);
                      },
              ),
            const SizedBox(width: 12),
            if (hasTimeline) ...[
              Text('timeline.fps'.tr(), style: theme.textTheme.labelSmall),
              SizedBox(
                width: 44,
                height: 26,
                child: DropdownButton<int>(
                  value: project.animation.fps,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: const [6, 8, 12, 15, 24, 30]
                      .map((f) => DropdownMenuItem(value: f, child: Text('$f')))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    provider.setAnimationFps(value);
                    if (_playing) _restartTimer(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Onion skin: ghosted neighbours around the current frame.
              FilterChip(
                label: Text('timeline.onion_skin'.tr(),
                    style: theme.textTheme.labelSmall),
                selected: project.animation.onionSkin,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => provider.toggleOnionSkin(),
              ),
              if (project.animation.onionSkin)
                SizedBox(
                  width: 96,
                  child: Slider(
                    value: project.animation.onionRange.toDouble(),
                    min: 1,
                    max: 4,
                    divisions: 3,
                    label: '${project.animation.onionRange}',
                    onChanged: (value) =>
                        provider.setOnionRange(value.round()),
                  ),
                ),
            ],
            const Spacer(),
            if (hasTimeline)
              TextButton.icon(
                icon: const Icon(Icons.movie_creation_outlined, size: 16),
                label: Text('animation.export_action'.tr()),
                onPressed: () {
                  _stopPlayback();
                  showAnimationExportDialog(context);
                },
              ),
          ]),
          const SizedBox(height: 2),
          if (!hasTimeline)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: Text('timeline.start'.tr()),
                onPressed: () => provider.ensureTimeline(),
              ),
            )
          else
            SizedBox(
              height: 66,
              child: Builder(builder: (context) {
                final frames = _framesWithLiveCurrent(provider);
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: frames.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == project.currentFrame;
                    return _FrameThumb(
                      frame: frames[index],
                      layers: provider.currentProject!.layers,
                      canvasSize: Size(
                        provider.currentProject!.settings.width.toDouble(),
                        provider.currentProject!.settings.height.toDouble(),
                      ),
                      index: index,
                      selected: isCurrent,
                      onTap: () {
                        _stopPlayback();
                        provider.goToFrame(index);
                      },
                    );
                  },
                );
              }),
            ),
        ]),
      ),
    );
  }
}

class _FrameThumb extends StatelessWidget {
  final AnimationFrame frame;
  final List<Layer> layers;
  final Size canvasSize;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  const _FrameThumb({
    required this.frame,
    required this.layers,
    required this.canvasSize,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CustomPaint(
                painter: _FrameThumbPainter(
                  frame: frame,
                  layerOrder: layers.map((l) => l.id).toList(),
                  canvasSize: canvasSize,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          Text(
            '${index + 1}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? theme.colorScheme.primary : null,
              fontWeight: selected ? FontWeight.bold : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class _FrameThumbPainter extends CustomPainter {
  final AnimationFrame frame;
  final List<String> layerOrder;
  final Size canvasSize;

  _FrameThumbPainter({
    required this.frame,
    required this.layerOrder,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;
    final scale = (size.width / canvasSize.width)
        .clamp(0.0, size.height / canvasSize.height);
    canvas.save();
    canvas.scale(scale);
    frame.paint(canvas, Paint(), layerOrder: layerOrder);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FrameThumbPainter old) =>
      old.frame != frame || old.canvasSize != canvasSize;
}
