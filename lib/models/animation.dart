import 'dart:ui';

import 'drawable.dart';

/// One animation frame: a snapshot of every layer's vector content.
///
/// Frames deliberately store *vector* content only. A layer's baked raster
/// ([Layer.image], e.g. an imported photo) is not animated and stays the
/// same across frames — the common case for a drawing timeline is vector
/// strokes, and duplicating full rasters per frame would multiply project
/// size by the frame count.
class AnimationFrame {
  final String id;

  /// layerId → that layer's drawables in this frame.
  final Map<String, List<Drawable>> layers;

  AnimationFrame({required this.id, Map<String, List<Drawable>>? layers})
      : layers = layers ?? {};

  bool get isEmpty => layers.values.every((list) => list.isEmpty);

  int get drawableCount =>
      layers.values.fold(0, (sum, list) => sum + list.length);

  /// Deep copy of a layer's drawables (JSON round-trip guarantees no aliasing
  /// with the live editing state).
  static List<Drawable> copyDrawables(List<Drawable> source) =>
      source.map((d) => Drawable.fromJson(d.toJson())).toList();

  AnimationFrame copyWith({String? id}) => AnimationFrame(
        id: id ?? this.id,
        layers: {
          for (final entry in layers.entries)
            entry.key: copyDrawables(entry.value),
        },
      );

  /// Captures [layers] (live) into a snapshot map.
  static Map<String, List<Drawable>> snapshot(
    Iterable<({String id, List<Drawable> drawables})> layers,
  ) =>
      {
        for (final layer in layers)
          layer.id: copyDrawables(layer.drawables),
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'layers': {
          for (final entry in layers.entries)
            entry.key: entry.value.map((d) => d.toJson()).toList(),
        },
      };

  factory AnimationFrame.fromJson(Map<String, dynamic> json) => AnimationFrame(
        id: json['id'] as String,
        layers: {
          for (final entry
              in (json['layers'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: ((entry.value as List?) ?? const [])
                .map((d) => Drawable.fromJson((d as Map).cast<String, dynamic>()))
                .toList(),
        },
      );

  /// Paints this frame's layers bottom-to-top with a flat [opacity], used by
  /// the onion-skin overlay and frame thumbnails.
  void paint(Canvas canvas, Paint paint, {List<String>? layerOrder}) {
    final order = layerOrder ?? layers.keys.toList();
    for (final layerId in order) {
      final drawables = layers[layerId];
      if (drawables == null) continue;
      for (final d in drawables) {
        d.draw(canvas, paint);
      }
    }
  }
}

/// Playback/timeline settings that travel with the project.
class AnimationSettings {
  int fps;
  bool onionSkin;

  /// How many frames before/after the current one get ghosted.
  int onionRange;

  /// Pixels-per-frame playback shortcut: frames may hold longer than one
  /// tick (a "hold" of 3 stays on screen 3 ticks).
  bool loop;

  AnimationSettings({
    this.fps = 12,
    this.onionSkin = false,
    this.onionRange = 1,
    this.loop = true,
  });

  Map<String, dynamic> toJson() => {
        'fps': fps,
        'onion_skin': onionSkin,
        'onion_range': onionRange,
        'loop': loop,
      };

  factory AnimationSettings.fromJson(Map<String, dynamic> json) =>
      AnimationSettings(
        fps: (json['fps'] as num?)?.toInt() ?? 12,
        onionSkin: json['onion_skin'] as bool? ?? false,
        onionRange: (json['onion_range'] as num?)?.toInt() ?? 1,
        loop: json['loop'] as bool? ?? true,
      );
}

/// Frame-hold helper: expands a list of holds into a playback schedule.
/// Exposed for tests; the timeline uses it to decide when to advance.
List<int> playbackSchedule(List<int> holds, {int? loopLength}) {
  final out = <int>[];
  for (var i = 0; i < holds.length; i++) {
    final hold = holds[i] < 1 ? 1 : holds[i];
    for (var k = 0; k < hold; k++) {
      out.add(i);
    }
  }
  if (loopLength != null && loopLength > 0 && out.isEmpty) {
    for (var i = 0; i < loopLength; i++) {
      out.add(i);
    }
  }
  return out;
}
