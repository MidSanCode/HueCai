import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'drawable.dart';
import 'mask_stroke.dart';
import '../services/image_filters.dart';

/// Layer blend modes, grouped by visual family.
///
/// JSON names are snake_case so saved projects stay stable; unknown names
/// fall back to [normal] on load.
enum BlendModeExt {
  // 正常系
  normal,
  // 变暗系
  darken,
  multiply,
  colorBurn,
  // 变亮系
  lighten,
  screen,
  colorDodge,
  additive,
  // 对比系
  overlay,
  hardLight,
  softLight,
  // 反相系
  difference,
  exclusion,
  xor,
  // 分量系
  hue,
  saturation,
  color,
  luminosity,
  // 合成系
  behind,
  erase;

  BlendMode toFlutterBlendMode() {
    switch (this) {
      case BlendModeExt.normal:
        return BlendMode.srcOver;
      case BlendModeExt.darken:
        return BlendMode.darken;
      case BlendModeExt.multiply:
        return BlendMode.multiply;
      case BlendModeExt.colorBurn:
        return BlendMode.colorBurn;
      case BlendModeExt.lighten:
        return BlendMode.lighten;
      case BlendModeExt.screen:
        return BlendMode.screen;
      case BlendModeExt.colorDodge:
        return BlendMode.colorDodge;
      case BlendModeExt.additive:
        return BlendMode.plus;
      case BlendModeExt.overlay:
        return BlendMode.overlay;
      case BlendModeExt.hardLight:
        return BlendMode.hardLight;
      case BlendModeExt.softLight:
        return BlendMode.softLight;
      case BlendModeExt.difference:
        return BlendMode.difference;
      case BlendModeExt.exclusion:
        return BlendMode.exclusion;
      case BlendModeExt.xor:
        return BlendMode.xor;
      case BlendModeExt.hue:
        return BlendMode.hue;
      case BlendModeExt.saturation:
        return BlendMode.saturation;
      case BlendModeExt.color:
        return BlendMode.color;
      case BlendModeExt.luminosity:
        return BlendMode.luminosity;
      case BlendModeExt.behind:
        return BlendMode.dstOver;
      case BlendModeExt.erase:
        return BlendMode.dstOut;
    }
  }

  /// JSON 序列化名（snake_case）。
  String get jsonName {
    switch (this) {
      case BlendModeExt.colorBurn:
        return 'color_burn';
      case BlendModeExt.colorDodge:
        return 'color_dodge';
      case BlendModeExt.hardLight:
        return 'hard_light';
      case BlendModeExt.softLight:
        return 'soft_light';
      default:
        return name;
    }
  }

  /// Accepts both snake_case and enum names, for backward compatibility
  /// with projects saved before the blend-mode expansion.
  static BlendModeExt fromJsonName(String? value) {
    if (value == null) return BlendModeExt.normal;
    for (final mode in values) {
      if (mode.jsonName == value || mode.name == value) return mode;
    }
    return BlendModeExt.normal;
  }

  /// Visual family for grouping in menus.
  BlendModeFamily get family {
    switch (this) {
      case BlendModeExt.normal:
        return BlendModeFamily.normal;
      case BlendModeExt.darken:
      case BlendModeExt.multiply:
      case BlendModeExt.colorBurn:
        return BlendModeFamily.darken;
      case BlendModeExt.lighten:
      case BlendModeExt.screen:
      case BlendModeExt.colorDodge:
      case BlendModeExt.additive:
        return BlendModeFamily.lighten;
      case BlendModeExt.overlay:
      case BlendModeExt.hardLight:
      case BlendModeExt.softLight:
        return BlendModeFamily.contrast;
      case BlendModeExt.difference:
      case BlendModeExt.exclusion:
      case BlendModeExt.xor:
        return BlendModeFamily.inversion;
      case BlendModeExt.hue:
      case BlendModeExt.saturation:
      case BlendModeExt.color:
      case BlendModeExt.luminosity:
        return BlendModeFamily.component;
      case BlendModeExt.behind:
      case BlendModeExt.erase:
        return BlendModeFamily.composite;
    }
  }
}

enum BlendModeFamily { normal, darken, lighten, contrast, inversion, component, composite }

/// A named group of consecutive layers.
///
/// Layers stay in the project's flat ordered list; a group is membership
/// metadata ([Layer.groupId]) whose members must be contiguous — the
/// provider enforces that invariant on every structural change. The group's
/// own [opacity]/[blendMode]/[visible] apply to the composited result of all
/// members, exactly like a folder of layers in other editors.
class LayerGroup {
  final String id;
  String name;
  bool visible;
  double opacity;
  BlendModeExt blendMode;
  bool expanded;

  LayerGroup({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blendMode = BlendModeExt.normal,
    this.expanded = true,
  });

  LayerGroup copyWith({
    String? id,
    String? name,
    bool? visible,
    double? opacity,
    BlendModeExt? blendMode,
    bool? expanded,
  }) =>
      LayerGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        opacity: opacity ?? this.opacity,
        blendMode: blendMode ?? this.blendMode,
        expanded: expanded ?? this.expanded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'blendMode': blendMode.jsonName,
        'expanded': expanded,
      };

  factory LayerGroup.fromJson(Map<String, dynamic> json) => LayerGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Group',
        visible: json['visible'] as bool? ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        blendMode: BlendModeExt.fromJsonName(json['blendMode'] as String?),
        expanded: json['expanded'] as bool? ?? true,
      );
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

  /// Id of the [LayerGroup] this layer belongs to, or null when ungrouped.
  /// Members of one group are contiguous in [Project.layers].
  String? groupId;

  /// Transparency mask strokes; null means "no mask". White keeps, black
  /// conceals. [maskEnabled] temporarily disables the mask without deleting
  /// its strokes.
  List<MaskStroke>? maskStrokes;
  bool maskEnabled;

  /// Bumped whenever mask strokes change, so raster caches rebuild.
  int maskVersion = 0;

  /// Clone layer: mirrors the content of the layer with this id. Clone
  /// layers have no drawables/image of their own.
  String? cloneOfId;

  /// Adjustment layer: non-destructively applies this filter to everything
  /// below it in the stack. Adjustment layers render no content of their own.
  AdjustmentSpec? adjustment;

  /// Vector layer: intended for resolution-independent content (paths, text,
  /// shapes) rather than painted pixels. The flag is a semantic marker —
  /// everything here already renders from vector drawables — and it tells
  /// destructive raster operations to ask before flattening the layer.
  bool isVector;

  /// Bumped whenever the image transform (offset/rotation/scale/flip)
  /// changes, so the painter's raster cache knows to re-render this layer.
  int imageVersion = 0;

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
    this.groupId,
    this.maskStrokes,
    this.maskEnabled = true,
    this.cloneOfId,
    this.adjustment,
    this.isVector = false,
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
    String? groupId,
    List<MaskStroke>? maskStrokes,
    bool? maskEnabled,
    String? cloneOfId,
    AdjustmentSpec? adjustment,
    bool? isVector,
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
        groupId: groupId ?? this.groupId,
        maskStrokes: maskStrokes ?? this.maskStrokes,
        maskEnabled: maskEnabled ?? this.maskEnabled,
        cloneOfId: cloneOfId ?? this.cloneOfId,
        adjustment: adjustment ?? this.adjustment,
        isVector: isVector ?? this.isVector,
        drawables: drawables ?? this.drawables,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'locked': locked,
        'blendMode': blendMode.jsonName,
        'imagePath': imagePath,
        'imageOffset': {'x': imageOffset.dx, 'y': imageOffset.dy},
        'imageRotation': imageRotation,
        'imageScale': imageScale,
        'imageFlipH': imageFlipH,
        'imageFlipV': imageFlipV,
        'thumbnailPath': thumbnailPath,
        'groupId': groupId,
        'maskEnabled': maskEnabled,
        'maskStrokes': maskStrokes?.map((s) => s.toJson()).toList(),
        if (cloneOfId != null) 'cloneOfId': cloneOfId,
        if (adjustment != null) 'adjustment': adjustment!.toJson(),
        if (isVector) 'isVector': isVector,
        'drawables': drawables.map((d) => d.toJson()).toList(),
      };

  factory Layer.fromJson(Map<String, dynamic> json) => Layer(
        id: json['id'] as String,
        name: json['name'] as String,
        visible: json['visible'] as bool? ?? true,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        locked: json['locked'] as bool? ?? false,
        blendMode: BlendModeExt.fromJsonName(json['blendMode'] as String?),
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
        groupId: json['groupId'] as String?,
        maskEnabled: json['maskEnabled'] as bool? ?? true,
        maskStrokes: (json['maskStrokes'] as List?)
            ?.map((s) => MaskStroke.fromJson(s as Map<String, dynamic>))
            .toList(),
        cloneOfId: json['cloneOfId'] as String?,
        adjustment: json['adjustment'] != null
            ? AdjustmentSpec.fromJson(
                (json['adjustment'] as Map).cast<String, dynamic>())
            : null,
        isVector: json['isVector'] as bool? ?? false,
        drawables: (json['drawables'] as List?)
                ?.map(
                    (d) => Drawable.fromJson(d as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
