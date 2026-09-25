import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/layer.dart';
import '../models/drawable.dart';
import '../models/canvas_settings.dart';
import 'history_service.dart';
import 'lgdf_codec.dart';
import 'ora_codec.dart';
import 'psd_codec.dart';

class ProjectService {
  /// Extension for hue_cai projects (LGDF container).
  static const String projectExtension = LgdfCodec.extension;

  /// Legacy extension from before the LGDF migration; still readable so old
  /// projects can be opened and re-saved into the new format.
  static const String legacyExtension = '.hcp';

  /// Every extension [loadProject] understands.
  static const List<String> readableExtensions = [
    LgdfCodec.extension,
    legacyExtension,
    OraCodec.extension,
    PsdCodec.extension,
  ];

  /// Extensions accepted by the open dialog, without the leading dot.
  static final List<String> readableExtensionNames =
      readableExtensions.map((e) => e.replaceFirst('.', '')).toList();

  /// True when [path] is a project container this service can open.
  static bool isProjectPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith(LgdfCodec.extension) ||
        lower.endsWith(legacyExtension) ||
        lower.endsWith(OraCodec.extension) ||
        lower.endsWith(PsdCodec.extension);
  }

  Future<String> get _projectsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/huecai_projects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<List<Project>> listProjects() async {
    final dir = await _projectsDir;
    return _listProjectsRecursive(Directory(dir));
  }

  Future<List<Project>> _listProjectsRecursive(Directory dir) async {
    if (!await dir.exists()) return [];
    final projects = <Project>[];
    final entries = await dir.list().toList();
    for (final entry in entries) {
      if (entry is Directory) {
        if (entry.path.endsWith('.trash')) continue;
        // A directory-mode LGDF project is itself a `.hcproj` folder; treat
        // it as a project instead of descending into its internals.
        if (entry.path.toLowerCase().endsWith(LgdfCodec.directorySuffix)) {
          final project = await LgdfCodec.readDirectory(entry.path);
          if (project != null) projects.add(project);
          continue;
        }
        projects.addAll(await _listProjectsRecursive(entry));
      } else if (entry is File && isProjectPath(entry.path)) {
        try {
          final project = await loadProject(entry.path);
          if (project != null) projects.add(project);
        } catch (_) {}
      }
    }
    projects.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return projects;
  }

  Future<List<File>> listTrashFiles() async {
    final dir = await _projectsDir;
    final trashDir = Directory('$dir/.trash');
    if (!await trashDir.exists()) return [];
    return (await trashDir.list().toList())
        .whereType<File>()
        .where((f) => isProjectPath(f.path))
        .toList();
  }

  Future<bool> trashProject(String filePath) async {
    try {
      final dir = await _projectsDir;
      final trashDir = Directory('$dir/.trash');
      if (!await trashDir.exists()) await trashDir.create(recursive: true);
      final file = File(filePath);
      if (!await file.exists()) return false;
      final name = file.uri.pathSegments.last;
      await file.rename('${trashDir.path}/$name');
      // Also move thumbnail
      final thumb = File('$filePath.thumb.png');
      if (await thumb.exists()) {
        await thumb.rename('${trashDir.path}/$name.thumb.png');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restoreProject(String trashPath) async {
    try {
      final dir = await _projectsDir;
      final file = File(trashPath);
      if (!await file.exists()) return false;
      final name = file.uri.pathSegments.last;
      await file.rename('$dir/$name');
      final thumb = File('$trashPath.thumb.png');
      if (await thumb.exists()) {
        await thumb.rename('$dir/$name.thumb.png');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> emptyTrash() async {
    try {
      final dir = await _projectsDir;
      final trashDir = Directory('$dir/.trash');
      if (await trashDir.exists()) {
        await trashDir.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> renameProject(String filePath, String newName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final dir = file.parent;
      final newPath = '${dir.path}/$newName$projectExtension';
      await file.rename(newPath);
      // Also rename thumbnail
      final thumb = File('$filePath.thumb.png');
      if (await thumb.exists()) {
        await thumb.rename('$newPath.thumb.png');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createFolder(String folderName) async {
    try {
      final dir = await _projectsDir;
      final newDir = Directory('$dir/$folderName');
      if (await newDir.exists()) return false;
      await newDir.create();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> listFolders() async {
    final dir = await _projectsDir;
    final projectDir = Directory(dir);
    if (!await projectDir.exists()) return [];
    final folders = <String>[];
    final entries = await projectDir.list().toList();
    for (final entry in entries) {
      if (entry is Directory && !entry.path.endsWith('.trash')) {
        folders.add(entry.uri.pathSegments.last);
      }
    }
    return folders;
  }

  Future<List<String>> getProjectFolder(String filePath) async {
    final dir = await _projectsDir;
    final file = File(filePath);
    final parent = file.parent.path;
    if (parent == dir) return [];
    return [file.parent.uri.pathSegments.last];
  }

  Future<bool> moveToFolder(List<String> filePaths, String folderName) async {
    try {
      final dir = await _projectsDir;
      final dest = Directory('$dir/$folderName');
      if (!await dest.exists()) await dest.create();
      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          final name = file.uri.pathSegments.last;
          await file.rename('${dest.path}/$name');
          final thumb = File('$path.thumb.png');
          if (await thumb.exists()) {
            await thumb.rename('${dest.path}/$name.thumb.png');
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> batchExport(List<String> filePaths, String destDir) async {
    try {
      final dest = Directory(destDir);
      if (!await dest.exists()) await dest.create(recursive: true);
      for (final path in filePaths) {
        final file = File(path);
        if (await file.exists()) {
          final name = file.uri.pathSegments.last;
          await file.copy('${dest.path}/$name');
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads a project from disk.
  ///
  /// `.hcproj` files are LGDF packages; a `.hcproj` *directory* is read in
  /// directory mode. Legacy `.hcp` archives are still parsed so existing
  /// projects can be opened and re-saved into the new format.
  Future<Project?> loadProject(String filePath) async {
    final lower = filePath.toLowerCase();
    if (lower.endsWith(LgdfCodec.directorySuffix) &&
        await Directory(filePath).exists()) {
      return LgdfCodec.readDirectory(filePath);
    }
    if (lower.endsWith(LgdfCodec.extension)) {
      return LgdfCodec.readPackage(filePath);
    }
    if (lower.endsWith(OraCodec.extension)) {
      return OraCodec.readPackage(filePath);
    }
    if (lower.endsWith(PsdCodec.extension)) {
      return PsdCodec.readProject(filePath);
    }
    return _loadLegacyProject(filePath);
  }

  /// Parses the pre-LGDF `.hcp` container (project.json + layer PNGs).
  Future<Project?> _loadLegacyProject(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final projectFile = archive.files.firstWhere(
        (f) => f.name == 'project.json',
        orElse: () => throw Exception('Missing project.json'),
      );
      final projectData =
          jsonDecode(utf8.decode(projectFile.content)) as Map<String, dynamic>;
      final project = Project.fromJson(projectData);
      project.filePath = filePath;

      final layerMetaFile = archive.files.firstWhere(
        (f) => f.name == 'layer_meta.json',
        orElse: () => throw Exception('Missing layer_meta.json'),
      );
      final layerMetaList =
          jsonDecode(utf8.decode(layerMetaFile.content)) as List<dynamic>;

      for (int i = 0; i < layerMetaList.length; i++) {
        final meta = layerMetaList[i] as Map<String, dynamic>;
        if (i < project.layers.length) {
          project.layers[i] = Layer.fromJson(meta);
        }
      }

      // Re-attach each layer's rasterized pixels. Without this every layer
      // comes back empty: imported images (which live only as `layer.image`)
      // would vanish on reload even though their bytes are in the archive.
      for (int i = 0; i < project.layers.length; i++) {
        final entry = archive.files.firstWhere(
          (f) => f.name == 'layers/layer_$i.png',
          orElse: () => ArchiveFile('layers/layer_$i.png', 0, <int>[]),
        );
        final content = entry.content;
        if (content.isEmpty) continue;
        try {
          final codec = await ui.instantiateImageCodec(
            Uint8List.fromList(content),
          );
          final frame = await codec.getNextFrame();
          project.layers[i].image = frame.image;
          // Restored pixels are already baked at the canvas origin, so reset
          // the placement transform to avoid applying it twice.
          project.layers[i].imageOffset = Offset.zero;
          project.layers[i].imageRotation = 0;
          project.layers[i].imageScale = 1.0;
          project.layers[i].imageFlipH = false;
          project.layers[i].imageFlipV = false;
        } catch (_) {
          // A layer that fails to decode simply stays vector-only.
        }
      }

      return project;
    } catch (e) {
      return null;
    }
  }

  Future<String> saveProject(
    Project project,
    HistoryService history, {
    String? filePath,
  }) async {
    final path = filePath ??
        project.filePath ??
        await uniquePath(
          '${await _projectsDir}/${project.name}${LgdfCodec.extension}',
        );
    final savePath = path;

    // Projects are written as LGDF packages (temp/example/lgdf-standard.md).
    await LgdfCodec.writePackage(savePath, project, history);
    project.filePath = savePath;
    project.modifiedAt = DateTime.now();

    // Generate thumbnail
    try {
      final thumbBytes = await _generateThumbnail(project);
      if (thumbBytes != null) {
        await File('$savePath.thumb.png').writeAsBytes(thumbBytes);
      }
    } catch (_) {}

    return savePath;
  }

  Future<Uint8List?> _generateThumbnail(Project project) async {
    try {
      final w = project.settings.width;
      final h = project.settings.height;
      const maxThumb = 256;
      final scale = maxThumb / (w > h ? w : h);
      final thumbW = (w * scale).round().clamp(1, maxThumb);
      final thumbH = (h * scale).round().clamp(1, maxThumb);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, thumbW.toDouble(), thumbH.toDouble()));
      canvas.save();
      canvas.scale(scale, scale);
      // Respect the document background (transparent stays transparent).
      final bgColor = Color(project.settings.backgroundColor);
      if (bgColor.a > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = bgColor,
        );
      }
      void renderLayer(Layer layer) {
        if (!layer.visible) return;
        // Adjustment layers are skipped in thumbnails (approximation).
        if (layer.adjustment != null) return;
        // Clone layers render the source layer's content.
        final content = layer.cloneOfId == null
            ? layer
            : project.layers
                    .where((l) => l.id == layer.cloneOfId)
                    .firstOrNull ??
                layer;
        // Isolate each layer so its blend mode applies only to its own
        // pixels when composited back.
        canvas.saveLayer(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()
            ..color = Colors.white.withValues(alpha: layer.opacity)
            ..blendMode = layer.blendMode.toFlutterBlendMode(),
        );
        for (final d in content.drawables) {
          d.draw(canvas, Paint());
        }
        if (content.image != null) {
          final img = content.image!;
          canvas.save();
          canvas.translate(content.imageOffset.dx + img.width / 2, content.imageOffset.dy + img.height / 2);
          canvas.rotate(content.imageRotation);
          final flipX = content.imageFlipH ? -1.0 : 1.0;
          final flipY = content.imageFlipV ? -1.0 : 1.0;
          canvas.scale(content.imageScale * flipX, content.imageScale * flipY);
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
            Paint(),
          );
          canvas.restore();
        }
        // Apply the transparency mask inside the isolated layer, before the
        // blend-mode composite closes.
        final mask = (layer.maskEnabled && layer.maskStrokes != null &&
                layer.maskStrokes!.isNotEmpty)
            ? layer.maskStrokes!
            : null;
        if (mask != null) {
          canvas.saveLayer(
            Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            Paint()..blendMode = BlendMode.dstIn,
          );
          canvas.drawRect(
            Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            Paint()..color = Colors.white,
          );
          for (final s in mask) {
            s.drawOnMask(canvas);
          }
          canvas.restore();
        }
        canvas.restore();
      }

      // Group blocks composite into an isolated layer first so the group's
      // own opacity/blend mode applies to the merged members.
      for (final run in project.layerRuns()) {
        if (run.isGroup) {
          final group = run.group!;
          if (!group.visible) continue;
          canvas.saveLayer(
            Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
            Paint()
              ..color = Colors.white.withValues(alpha: group.opacity)
              ..blendMode = group.blendMode.toFlutterBlendMode(),
          );
          for (var i = run.start; i <= run.end; i++) {
            renderLayer(project.layers[i]);
          }
          canvas.restore();
        } else {
          renderLayer(project.layers[run.singleIndex!]);
        }
      }
      canvas.restore();
      final picture = recorder.endRecording();
      final thumbImg = await picture.toImage(thumbW, thumbH);
      final pngBytes = await thumbImg.toByteData(format: ui.ImageByteFormat.png);
      thumbImg.dispose();
      return pngBytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Returns [basePath], or a `name(1).hcproj`-style variant when it is taken.
  ///
  /// Splits on the *last* dot so the original extension is preserved rather
  /// than the legacy `.hcp` suffix being hardcoded.
  Future<String> uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;

    final file = File(basePath);
    final dir = file.parent;
    final fileName = file.uri.pathSegments.last;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';

    var counter = 1;
    while (true) {
      final candidate = '${dir.path}/$stem($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }

  Future<Project> createProject({
    required String name,
    required int width,
    required int height,
    CanvasUnit unit = CanvasUnit.px,
    double resolution = 72,
    ColorModel colorModel = ColorModel.sRGB,
    int channelDepth = 8,
    List<int>? iccProfileData,
  }) async {
    final settings = CanvasSettings(
      width: width,
      height: height,
      unit: unit,
      resolution: resolution,
      colorModel: colorModel,
      channelDepth: channelDepth,
      iccProfileData: iccProfileData,
    );

    final bgId = const Uuid().v4();
    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      settings: settings,
      layers: [
        Layer(
          id: bgId,
          name: 'layer.background'.tr(),
          locked: true,
          drawables: [
            Drawable(
              id: '${bgId}_bg',
              isShape: true,
              shapeType: ShapeType.rect,
              points: [Offset.zero, Offset(width.toDouble(), height.toDouble())],
              color: Colors.white,
              isFilled: true,
              strokeWidth: 0,
            ),
          ],
        ),
        Layer(
          id: const Uuid().v4(),
          name: 'layer.default_name'.tr(namedArgs: {'n': '1'}),
        ),
      ],
      currentLayerIndex: 1,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    return project;
  }

  Future<bool> deleteProject(String filePath) async {
    // Move to trash instead of permanent delete
    return trashProject(filePath);
  }

  Future<String?> selectHcpFile() async {
    return null;
  }
}
