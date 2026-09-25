import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

import '../models/canvas_settings.dart';
import '../models/drawable.dart';
import '../models/layer.dart';
import '../models/project.dart';
import 'history_service.dart';

/// Reader/writer for the **LGDF** (Layered Generic Data Format) container,
/// following `temp/example/lgdf-standard.md` v2.0.
///
/// A drawing is stored as a directory-mode project:
///
/// ```
/// <name>.hcproj/            (package form: a ZIP with the same layout)
/// ├── info.json             project identity card
/// ├── registry.json         registered asset list
/// ├── assets/               binary resources
/// │   ├── layers/           one PNG per layer
/// │   └── images/           imported source bitmaps
/// ├── metadata/             one <asset>.json per asset (sha256, size, ...)
/// │   ├── layers/
/// │   └── images/
/// └── spec/                 human-readable description layer
///     ├── overview.md
///     └── config.json
/// ```
///
/// Notes on fidelity: the format keeps each layer's *pixels* as an asset, so
/// vector strokes are preserved separately in `spec/config.json` under the
/// `extra` container the standard reserves for format-specific data.
class LgdfCodec {
  LgdfCodec._();

  /// Extension used for packaged projects.
  static const String extension = '.hcproj';

  /// Directory-mode project folders are named with this suffix.
  static const String directorySuffix = '.hcproj';

  /// Value of `info.json.format`; lets a reader recognise the container.
  static const String formatId = 'lgdf';

  /// Minimum SDK version this writer emits / this reader requires.
  static const int minSdk = 1;

  /// SDK version implemented here.
  static const int sdkVersion = 1;

  /// True when [path] looks like a packaged hue_cai project.
  static bool isPackagePath(String path) =>
      path.toLowerCase().endsWith(extension);

  static const String _infoName = 'info.json';
  static const String _registryName = 'registry.json';
  static const String _specConfigName = 'spec/config.json';
  static const String _specOverviewName = 'spec/overview.md';

  /// Project name rules from the standard: `^[a-z0-9_-]+$`.
  static String sanitizeName(String raw) {
    final lower = raw.toLowerCase().trim();
    final cleaned = lower
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'untitled' : cleaned;
  }

  // --------------------------------------------------------------- packaging

  /// Builds the full LGDF entry map for [project].
  ///
  /// Returns forward-slash paths mapped to raw bytes. Layer content is
  /// rasterized, so the result is self-contained and does not depend on the
  /// original imported files still existing on disk.
  static Future<Map<String, Uint8List>> buildEntries(
    Project project,
    HistoryService history,
  ) async {
    final entries = <String, Uint8List>{};
    final registered = <String>[];

    // ── assets/layers/layer_<i>.png + metadata ──
    for (var i = 0; i < project.layers.length; i++) {
      final layer = project.layers[i];
      final png = await _layerToPng(
        layer,
        project.settings.width,
        project.settings.height,
      );
      if (png == null) continue;
      _registerAsset(
        entries,
        registered,
        path: 'assets/layers/layer_$i.png',
        bytes: png,
        type: 'image',
        mime: 'image/png',
        format: 'png',
        width: project.settings.width,
        height: project.settings.height,
      );
    }

    // ── assets/images/ for imported source bitmaps we can still read ──
    for (var i = 0; i < project.layers.length; i++) {
      final layer = project.layers[i];
      final src = layer.imagePath;
      if (src == null) continue;
      final file = File(src);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final ext = _extensionOf(src);
      _registerAsset(
        entries,
        registered,
        path: 'assets/images/imported_$i$ext',
        bytes: bytes,
        type: _typeForExtension(ext),
        mime: _mimeForExtension(ext),
        format: ext.replaceFirst('.', ''),
      );
    }

    // ── assets/icc/profile.icc ──
    final icc = project.settings.iccProfileData;
    if (icc != null && icc.isNotEmpty) {
      _registerAsset(
        entries,
        registered,
        path: 'assets/icc/profile.icc',
        bytes: Uint8List.fromList(icc),
        type: 'binary',
        mime: 'application/vnd.iccprofile',
        format: 'icc',
      );
    }

    // ── registry.json ──
    registered.sort();
    entries[_registryName] = _jsonBytes({
      'registered_files': registered,
      'asset_count': registered.length,
    });

    // ── info.json ──
    final createdSec = project.createdAt.millisecondsSinceEpoch ~/ 1000;
    final updatedSec = project.modifiedAt.millisecondsSinceEpoch ~/ 1000;
    entries[_infoName] = _jsonBytes({
      'format': formatId,
      'min_sdk': minSdk,
      'name': sanitizeName(project.name),
      'display_name': project.name,
      'description': 'hue_cai drawing project.',
      'tags': const <String>[],
      'created_time': createdSec,
      // The standard requires last_update_time >= created_time.
      'last_update_time': updatedSec < createdSec ? createdSec : updatedSec,
      'version': 1,
      'extra': {
        'app': 'hue_cai',
        'app_id': project.id,
      },
    });

    // ── spec/config.json (description layer + drawing payload) ──
    entries[_specConfigName] = _jsonBytes({
      'project': {
        'id': project.id,
        'name': sanitizeName(project.name),
        'display_name': project.name,
        'current_layer_index': project.currentLayerIndex,
      },
      'canvas': project.settings.toJson(),
      'layers': project.layers.map(_layerDescriptor).toList(),
      'groups': project.groups.map((g) => g.toJson()).toList(),
      'history': jsonDecode(jsonEncode(history.toJson())),
    });

    // ── spec/overview.md ──
    entries[_specOverviewName] = utf8.encode(
      '# ${project.name}\n\n'
      'hue_cai drawing project in LGDF v2.0 format.\n\n'
      '- Canvas: ${project.settings.width} x ${project.settings.height} '
      '(${project.settings.unit.name})\n'
      '- Layers: ${project.layers.length}\n'
      '- Assets: ${registered.length}\n',
    );

    return entries;
  }

  /// Serializes a layer into the `spec/config.json` layer descriptor.
  ///
  /// Pixel content lives in the assets layer; this holds everything needed to
  /// rebuild the `Layer` object (and the vector drawables).
  static Map<String, dynamic> _layerDescriptor(Layer layer) => {
        'id': layer.id,
        'name': layer.name,
        'visible': layer.visible,
        'opacity': layer.opacity,
        'locked': layer.locked,
        'blend_mode': layer.blendMode.jsonName,
        'group_id': layer.groupId,
        'image_path': layer.imagePath,
        'image_offset': {'x': layer.imageOffset.dx, 'y': layer.imageOffset.dy},
        'image_rotation': layer.imageRotation,
        'image_scale': layer.imageScale,
        'image_flip_h': layer.imageFlipH,
        'image_flip_v': layer.imageFlipV,
        'drawables': layer.drawables.map((d) => d.toJson()).toList(),
      };

  /// Rebuilds a [Layer] from a `spec/config.json` descriptor.
  static Layer layerFromDescriptor(Map<String, dynamic> json) {
    final offset = json['image_offset'] as Map<String, dynamic>?;
    return Layer(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Layer',
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      locked: json['locked'] as bool? ?? false,
      blendMode: BlendModeExt.fromJsonName(json['blend_mode'] as String?),
      groupId: json['group_id'] as String?,
      imagePath: json['image_path'] as String?,
      imageOffset: offset == null
          ? Offset.zero
          : Offset(
              (offset['x'] as num).toDouble(),
              (offset['y'] as num).toDouble(),
            ),
      imageRotation: (json['image_rotation'] as num?)?.toDouble() ?? 0,
      imageScale: (json['image_scale'] as num?)?.toDouble() ?? 1.0,
      imageFlipH: json['image_flip_h'] as bool? ?? false,
      imageFlipV: json['image_flip_v'] as bool? ?? false,
      drawables: (json['drawables'] as List?)
              ?.map((d) => Drawable.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  // -------------------------------------------------------------- directory

  /// Writes a directory-mode LGDF project at [dirPath].
  static Future<void> writeDirectory(
    String dirPath,
    Project project,
    HistoryService history,
  ) async {
    final entries = await buildEntries(project, history);
    final root = Directory(dirPath);
    if (await root.exists()) await root.delete(recursive: true);
    await root.create(recursive: true);

    for (final entry in entries.entries) {
      final file = File('$dirPath/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
  }

  /// Writes a packaged (ZIP) LGDF project at [path].
  static Future<void> writePackage(
    String path,
    Project project,
    HistoryService history,
  ) async {
    final entries = await buildEntries(project, history);
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(
        ArchiveFile(entry.key, entry.value.length, entry.value),
      );
    }
    final encoded = ZipEncoder().encode(archive);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encoded);
    // Companion checksum, as required by the standard's export step.
    await File('$path.sha256')
        .writeAsString('${sha256.convert(encoded)}\n');
  }

  // ----------------------------------------------------------------- reading

  /// Reads a packaged (`.hcproj`) project.
  static Future<Project?> readPackage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = <String, Uint8List>{};
      for (final file in archive.files) {
        final name = file.name.replaceAll('\\', '/');
        // Zip-slip guard: never accept an entry that escapes the root.
        if (name.startsWith('/') || name.split('/').contains('..')) continue;
        if (!file.isFile) continue;
        final content = file.content;
        entries[name] = content is Uint8List
            ? content
            : Uint8List.fromList(content);
      }
      return await _projectFromEntries(entries, sourcePath: path);
    } catch (_) {
      return null;
    }
  }

  /// Reads a directory-mode LGDF project.
  static Future<Project?> readDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return null;
      final entries = <String, Uint8List>{};
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path
            .substring(dir.path.length)
            .replaceAll('\\', '/')
            .replaceAll(RegExp(r'^/+'), '');
        // Skip the non-packaged directories the standard defines.
        if (rel.startsWith('work/') || rel.startsWith('dist/')) continue;
        entries[rel] = await entity.readAsBytes();
      }
      return await _projectFromEntries(entries, sourcePath: dirPath);
    } catch (_) {
      return null;
    }
  }

  /// Reconstructs a [Project] from an LGDF entry map.
  static Future<Project?> _projectFromEntries(
    Map<String, Uint8List> entries, {
    required String sourcePath,
  }) async {
    // 1 识别 — info.json must exist and declare the lgdf format.
    final infoBytes = entries[_infoName];
    if (infoBytes == null) return null;
    final info = jsonDecode(utf8.decode(infoBytes)) as Map<String, dynamic>;
    if (info['format'] != formatId) return null;

    // 2 门槛 — refuse projects written by a newer SDK.
    final required = (info['min_sdk'] as num?)?.toInt() ?? 1;
    final sdk = (info['extra'] as Map?)?['sdk'] as num?;
    if (required > sdkVersion && sdk != null && sdk > sdkVersion) return null;

    final configBytes = entries[_specConfigName];
    if (configBytes == null) return null;
    final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;

    final projectMeta = config['project'] as Map<String, dynamic>? ?? const {};
    final canvas = config['canvas'] as Map<String, dynamic>? ?? const {};
    final settings = CanvasSettings.fromJson(canvas);
    final icc = entries['assets/icc/profile.icc'];

    final layers = (config['layers'] as List?)
            ?.map((l) => layerFromDescriptor(l as Map<String, dynamic>))
            .toList() ??
        <Layer>[];

    final project = Project(
      id: projectMeta['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: projectMeta['display_name'] as String? ??
          info['display_name'] as String? ??
          info['name'] as String? ??
          'untitled',
      settings: CanvasSettings(
        width: settings.width,
        height: settings.height,
        unit: settings.unit,
        resolution: settings.resolution,
        colorModel: settings.colorModel,
        channelDepth: settings.channelDepth,
        iccProfilePath: settings.iccProfilePath,
        iccProfileData: icc == null ? settings.iccProfileData : List<int>.from(icc),
        backgroundColor: settings.backgroundColor,
      ),
      layers: layers,
      groups: (config['groups'] as List?)
          ?.map((g) => LayerGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        ((info['created_time'] as num?)?.toInt() ?? 0) * 1000,
      ),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        ((info['last_update_time'] as num?)?.toInt() ?? 0) * 1000,
      ),
      filePath: sourcePath,
      currentLayerIndex:
          (projectMeta['current_layer_index'] as num?)?.toInt() ?? 0,
    );

    // Re-attach each layer's rasterized pixels from assets/layers/.
    for (var i = 0; i < project.layers.length; i++) {
      final png = entries['assets/layers/layer_$i.png'];
      if (png == null || png.isEmpty) continue;
      try {
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        project.layers[i].image = frame.image;
        // Pixels are baked at the canvas origin, so clear the placement
        // transform to avoid applying it a second time.
        project.layers[i].imageOffset = Offset.zero;
        project.layers[i].imageRotation = 0;
        project.layers[i].imageScale = 1.0;
        project.layers[i].imageFlipH = false;
        project.layers[i].imageFlipV = false;
      } catch (_) {
        // A layer that fails to decode stays vector-only.
      }
    }

    final historyJson = config['history'];
    if (historyJson is Map<String, dynamic>) {
      // History is not restored into the project here; callers own the
      // service instance. Exposed via [readHistory] when needed.
    }

    return project;
  }

  /// Extracts the undo history payload from a packaged project, if present.
  static Future<Map<String, dynamic>?> readHistory(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.firstWhere(
        (f) => f.name.replaceAll('\\', '/') == _specConfigName,
        orElse: () => ArchiveFile(_specConfigName, 0, <int>[]),
      );
      if (entry.content.isEmpty) return null;
      final config = jsonDecode(utf8.decode(entry.content as List<int>))
          as Map<String, dynamic>;
      final history = config['history'];
      return history is Map<String, dynamic> ? history : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- validation

  /// Runs the standard's validation pass and returns the problems found.
  ///
  /// An empty result means the project is well-formed.
  static List<String> validate(Map<String, Uint8List> entries) {
    final problems = <String>[];

    final infoBytes = entries[_infoName];
    if (infoBytes == null) {
      return ['missing info.json'];
    }
    final Map<String, dynamic> info;
    try {
      info = jsonDecode(utf8.decode(infoBytes)) as Map<String, dynamic>;
    } catch (_) {
      return ['info.json is not valid UTF-8 JSON'];
    }
    if (info['format'] != formatId) {
      problems.add('info.json format must be "$formatId"');
    }
    for (final field in ['min_sdk', 'name', 'created_time', 'version']) {
      if (info[field] == null) problems.add('info.json missing "$field"');
    }
    final name = info['name'];
    if (name is String && !RegExp(r'^[a-z0-9_-]+$').hasMatch(name)) {
      problems.add('info.json name "$name" violates ^[a-z0-9_-]+\$');
    }
    final created = info['created_time'] as num?;
    final updated = info['last_update_time'] as num?;
    if (created != null && updated != null && updated < created) {
      problems.add('last_update_time must be >= created_time');
    }

    // registry.json — must exist and be consistent with the assets present.
    final registryBytes = entries[_registryName];
    if (registryBytes == null) {
      problems.add('missing registry.json');
      return problems;
    }
    final Map<String, dynamic> registry;
    try {
      registry = jsonDecode(utf8.decode(registryBytes)) as Map<String, dynamic>;
    } catch (_) {
      problems.add('registry.json is not valid UTF-8 JSON');
      return problems;
    }
    final registered =
        (registry['registered_files'] as List?)?.cast<String>() ?? const [];
    if (registered.isEmpty) problems.add('registered_files must not be empty');
    if (registered.toSet().length != registered.length) {
      problems.add('registered_files contains duplicates');
    }
    final count = (registry['asset_count'] as num?)?.toInt();
    if (count != null && count != registered.length) {
      problems.add('asset_count ($count) != registered_files length '
          '(${registered.length})');
    }

    // Every registered file needs its asset and metadata present and matching.
    for (final path in registered) {
      final asset = entries[path];
      if (asset == null) {
        problems.add('registered asset missing: $path');
        continue;
      }
      final metaPath = _metadataPathFor(path);
      final metaBytes = entries[metaPath];
      if (metaBytes == null) {
        problems.add('metadata missing for: $path (expected $metaPath)');
        continue;
      }
      final Map<String, dynamic> meta;
      try {
        meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      } catch (_) {
        problems.add('metadata for $path is not valid UTF-8 JSON');
        continue;
      }
      if (meta['path'] != path) {
        problems.add('metadata path mismatch for $path: ${meta['path']}');
      }
      if (meta['size'] != asset.length) {
        problems.add('size mismatch for $path: '
            '${meta['size']} != ${asset.length}');
      }
      final digest = sha256.convert(asset).toString();
      if (meta['sha256'] != digest) {
        problems.add('sha256 mismatch for $path');
      }
      if (meta['type'] == 'text') {
        try {
          utf8.decode(asset);
        } catch (_) {
          problems.add('text asset is not valid UTF-8: $path');
        }
      }
    }

    // Two-way mirror: no stray assets, no orphan metadata.
    for (final key in entries.keys) {
      if (!key.startsWith('assets/')) continue;
      // Directories are implied by file paths; only files are registered.
      if (!registered.contains(key)) {
        problems.add('unregistered asset: $key');
      }
    }
    for (final key in entries.keys) {
      if (!key.startsWith('metadata/') || !key.endsWith('.json')) continue;
      final rel = key.substring('metadata/'.length);
      final assetPath = 'assets/${rel.substring(0, rel.length - '.json'.length)}';
      if (!registered.contains(assetPath)) {
        problems.add('orphan metadata: $key');
      }
    }

    return problems;
  }

  // ---------------------------------------------------------------- helpers

  /// Standard metadata record for one asset.
  ///
  /// [sha256] must be the digest of the final bytes; the standard requires it
  /// to match the asset exactly, so it is computed by the caller rather than
  /// filled in later.
  static Map<String, dynamic> _assetMetadata({
    required String path,
    required String type,
    required int size,
    required String sha256,
    String? mime,
    String? format,
    int? width,
    int? height,
    int? createdTime,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'path': path,
      'type': type,
      if (mime != null) 'mime': mime,
      if (format != null) 'format': format,
      'size': size,
      'sha256': sha256,
      'hash_algorithm': 'sha256',
      'created_time': createdTime ?? now,
      'last_update_time': now,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (type == 'text') 'encoding': 'utf-8',
    };
  }

  /// Registers [bytes] as an asset: stores it and emits its metadata twin.
  ///
  /// The standard mirrors `assets/<rel>` as `metadata/<rel>.json` (see §7.1),
  /// so metadata never lives inside `assets/`.
  static void _registerAsset(
    Map<String, Uint8List> entries,
    List<String> registered, {
    required String path,
    required Uint8List bytes,
    required String type,
    String? mime,
    String? format,
    int? width,
    int? height,
  }) {
    entries[path] = bytes;
    registered.add(path);
    entries[_metadataPathFor(path)] = _jsonBytes(_assetMetadata(
      path: path,
      type: type,
      size: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mime: mime,
      format: format,
      width: width,
      height: height,
    ));
  }

  /// Maps an asset path onto its metadata twin: `metadata/<rel>.json`.
  static String _metadataPathFor(String assetPath) {
    final rel = assetPath.startsWith('assets/')
        ? assetPath.substring('assets/'.length)
        : assetPath;
    return 'metadata/$rel.json';
  }

  /// UTF-8 JSON with tab indentation and no BOM, per the standard.
  static Uint8List _jsonBytes(Map<String, dynamic> value) =>
      utf8.encode(const JsonEncoder.withIndent('\t').convert(value));

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.bin';
    return path.substring(dot).toLowerCase();
  }

  static String _typeForExtension(String ext) => switch (ext) {
        '.png' || '.jpg' || '.jpeg' || '.gif' || '.bmp' || '.webp' => 'image',
        '.txt' || '.md' || '.json' => 'text',
        _ => 'binary',
      };

  static String _mimeForExtension(String ext) => switch (ext) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.bmp' => 'image/bmp',
        '.webp' => 'image/webp',
        _ => 'application/octet-stream',
      };

  /// Rasterizes one layer (bitmap + drawables) onto a transparent canvas.
  static Future<Uint8List?> _layerToPng(
    Layer layer,
    int canvasW,
    int canvasH,
  ) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas =
          Canvas(recorder, Rect.fromLTWH(0, 0, canvasW.toDouble(), canvasH.toDouble()));
      final img = layer.image;
      if (img != null) {
        canvas.save();
        canvas.translate(layer.imageOffset.dx + img.width / 2,
            layer.imageOffset.dy + img.height / 2);
        canvas.rotate(layer.imageRotation);
        final flipX = layer.imageFlipH ? -1.0 : 1.0;
        final flipY = layer.imageFlipV ? -1.0 : 1.0;
        canvas.scale(layer.imageScale * flipX, layer.imageScale * flipY);
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(),
              img.height.toDouble()),
          Paint(),
        );
        canvas.restore();
      }
      for (final d in layer.drawables) {
        d.draw(canvas, Paint());
      }
      final picture = recorder.endRecording();
      final out = await picture.toImage(canvasW, canvasH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
