import 'canvas_settings.dart';
import 'layer.dart';

class Project {
  final String id;
  String name;
  CanvasSettings settings;
  List<Layer> layers;

  /// Layer groups referenced by [Layer.groupId]. Members of a group are
  /// contiguous in [layers] (enforced by the provider).
  List<LayerGroup> groups;

  final DateTime createdAt;
  DateTime modifiedAt;
  String? filePath;
  int currentLayerIndex;

  Project({
    required this.id,
    required this.name,
    required this.settings,
    required this.layers,
    List<LayerGroup>? groups,
    required this.createdAt,
    required this.modifiedAt,
    this.filePath,
    this.currentLayerIndex = 0,
  }) : groups = groups ?? [];

  Layer? get currentLayer =>
      layers.isNotEmpty && currentLayerIndex < layers.length
          ? layers[currentLayerIndex]
          : null;

  LayerGroup? groupById(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// True when [layer] should render, i.e. it is visible and so is its group.
  bool isLayerEffectivelyVisible(Layer layer) =>
      layer.visible && (groupById(layer.groupId)?.visible ?? true);

  /// Ordered bottom-to-top render runs: either a single ungrouped layer or a
  /// contiguous group block. Ungrouped members of a stale/unknown group id
  /// are treated as single layers.
  List<LayerRun> layerRuns() {
    final runs = <LayerRun>[];
    var i = 0;
    while (i < layers.length) {
      final gid = layers[i].groupId;
      final group = groupById(gid);
      if (group == null) {
        runs.add(LayerRun.single(i));
        i++;
        continue;
      }
      var end = i;
      while (end + 1 < layers.length && layers[end + 1].groupId == gid) {
        end++;
      }
      runs.add(LayerRun.group(group, i, end));
      i = end + 1;
    }
    return runs;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'settings': settings.toJson(),
        'layers': layers.map((l) => l.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'filePath': filePath,
        'currentLayerIndex': currentLayerIndex,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        settings: CanvasSettings.fromJson(json['settings'] as Map<String, dynamic>),
        layers: (json['layers'] as List)
            .map((l) => Layer.fromJson(l as Map<String, dynamic>))
            .toList(),
        groups: (json['groups'] as List?)
            ?.map((g) => LayerGroup.fromJson(g as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        filePath: json['filePath'] as String?,
        currentLayerIndex: json['currentLayerIndex'] as int? ?? 0,
      );
}

/// One render step in the layer stack: a standalone layer or a whole group.
class LayerRun {
  /// Null when this run is a group block.
  final int? singleIndex;
  final LayerGroup? group;
  final int start;
  final int end;

  LayerRun.single(int index)
      : singleIndex = index,
        group = null,
        start = index,
        end = index;

  LayerRun.group(this.group, this.start, this.end) : singleIndex = null;

  bool get isGroup => group != null;
}
