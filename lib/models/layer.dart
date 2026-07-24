import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'drawable.dart';

enum BlendModeExt {
  normal,
  multiply,
  screen,
  overlay;

  BlendMode toFlutterBlendMode() {
    switch (this) {
      case BlendModeExt.normal:
        return BlendMode.srcOver;
      case BlendModeExt.multiply:
        return BlendMode.multiply;
      case BlendModeExt.screen:
        return BlendMode.screen;
      case BlendModeExt.overlay:
        return BlendMode.overlay;
    }
  }
}

class Layer {
  final String id;
  String name;
  bool visible;
  double opacity;
  bool locked;
  BlendModeExt blendMode;
  ui.Image? image;
  String? imagePath;
  Offset imageOffset;
  double imageRotation;
  double imageScale;
  bool imageFlipH;
  bool imageFlipV;
  String? thumbnailPath;
  List<Drawable> drawables;

  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.locked = false,
    this.blendMode = BlendModeExt.normal,
    this.image,
    this.imagePath,
    this.imageOffset = Offset.zero,
    this.imageRotation = 0,
    this.imageScale = 1.0,
    this.imageFlipH = false,
    this.imageFlipV = false,
    this.thumbnailPath,
    List<Drawable>? drawables,
  }) : drawables = drawables ?? [];

  Layer copyWith({
    String? id,
    String? name,
    bool? visible,
    double? opacity,
    bool? locked,
    BlendModeExt? blendMode,
    ui.Image? image,
    String? imagePath,
    Offset? imageOffset,
    double? imageRotation,
    double? imageScale,
    bool? imageFlipH,
    bool? imageFlipV,
    String? thumbnailPath,
    List<Drawable>? drawables,
  }) =>
      Layer(
        id: id ?? this.id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        opacity: opacity ?? this.opacity,
        locked: locked ?? this.locked,
        blendMode: blendMode ?? this.blendMode,
        image: image ?? this.image,
        imagePath: imagePath ?? this.imagePath,
        imageOffset: imageOffset ?? this.imageOffset,
        imageRotation: imageRotation ?? this.imageRotation,
        imageScale: imageScale ?? this.imageScale,
        imageFlipH: imageFlipH ?? this.imageFlipH,
        imageFlipV: imageFlipV ?? this.imageFlipV,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        drawables: drawables ?? this.drawables,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'locked': locked,
        'blendMode': blendMode.name,
        'imagePath': imagePath,
        'imageOffset': {'x': imageOffset.dx, 'y': imageOffset.dy},
        'imageRotation': imageRotation,
        'imageScale': imageScale,
        'imageFlipH': imageFlipH,
        'imageFlipV': imageFlipV,
        'thumbnailPath': thumbnailPath,
        'drawables': drawables.map((d) => d.toJson()).toList(),
      };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        locked: json['locked'] as bool? ?? false,
        blendMode: BlendModeExt.values.firstWhere(
            (e) => e.name == json['blendMode'],
            orElse: () => BlendModeExt.normal),
        imagePath: json['imagePath'] as String?,
        imageOffset: json['imageOffset'] != null
            ? Offset(
                (json['imageOffset'] as Map)['x'] as double,
                (json['imageOffset'] as Map)['y'] as double,
              )
            : Offset.zero,
        imageRotation: (json['imageRotation'] as num?)?.toDouble() ?? 0,
        imageScale: (json['imageScale'] as num?)?.toDouble() ?? 1.0,
        imageFlipH: json['imageFlipH'] as bool? ?? false,
        imageFlipV: json['imageFlipV'] as bool? ?? false,
        thumbnailPath: json['thumbnailPath'] as String?,
        drawables: (json['drawables'] as List?)
                ?.map(
                    (d) => Drawable.fromJson(d as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
