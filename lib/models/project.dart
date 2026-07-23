import 'canvas_settings.dart';
import 'layer.dart';

class Project {
  final String id;
  String name;
  final CanvasSettings settings;
  List<Layer> layers;
  final DateTime createdAt;
  DateTime modifiedAt;
  String? filePath;
  int currentLayerIndex;

  Project({
    required this.id,
    required this.name,
    required this.settings,
    required this.layers,
    required this.createdAt,
    required this.modifiedAt,
    this.filePath,
    this.currentLayerIndex = 0,
  });

  Layer? get currentLayer =>
      layers.isNotEmpty && currentLayerIndex < layers.length
          ? layers[currentLayerIndex]
          : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'settings': settings.toJson(),
        'layers': layers.map((l) => l.toJson()).toList(),
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
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        filePath: json['filePath'] as String?,
        currentLayerIndex: json['currentLayerIndex'] as int? ?? 0,
      );
}
