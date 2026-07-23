import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/project.dart';
import '../models/layer.dart';
import '../models/canvas_settings.dart';
import 'history_service.dart';

class ProjectService {
  static const String _hcpExtension = '.hcp';

  Future<String> get _projectsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/huecai_projects');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<List<Project>> listProjects() async {
    final dir = await _projectsDir;
    final projectDir = Directory(dir);
    if (!await projectDir.exists()) return [];

    final files = await projectDir.list().toList();
    final projects = <Project>[];
    for (final file in files) {
      if (file is File && file.path.endsWith(_hcpExtension)) {
        try {
          final project = await loadProject(file.path);
          if (project != null) projects.add(project);
        } catch (_) {}
      }
    }
    projects.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return projects;
  }

  Future<Project?> loadProject(String filePath) async {
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
    final path = filePath ?? project.filePath;
    final savePath = path ?? '${await _projectsDir}/${project.name}$_hcpExtension';

    final archive = Archive();

    archive.addFile(ArchiveFile(
      'project.json',
      utf8.encode(jsonEncode(project.toJson())).length,
      utf8.encode(jsonEncode(project.toJson())),
    ));

    final layerMeta = project.layers.map((l) => l.toJson()).toList();
    archive.addFile(ArchiveFile(
      'layer_meta.json',
      utf8.encode(jsonEncode(layerMeta)).length,
      utf8.encode(jsonEncode(layerMeta)),
    ));

    for (int i = 0; i < project.layers.length; i++) {
      final layer = project.layers[i];
      final pngBytes = await _layerToPng(layer);
      if (pngBytes != null) {
        archive.addFile(ArchiveFile(
          'layers/layer_$i.png',
          pngBytes.length,
          pngBytes,
        ));
      }
    }

    final historyJson = jsonEncode(history.toJson());
    archive.addFile(ArchiveFile(
      'history.json',
      utf8.encode(historyJson).length,
      utf8.encode(historyJson),
    ));

    if (project.settings.iccProfileData != null) {
      archive.addFile(ArchiveFile(
        'icc/profile.icc',
        project.settings.iccProfileData!.length,
        project.settings.iccProfileData!,
      ));
    }

    final encoded = ZipEncoder().encode(archive);

    final file = File(savePath);
    await file.writeAsBytes(encoded);
    project.filePath = savePath;
    project.modifiedAt = DateTime.now();
    return savePath;
  }

  Future<Uint8List?> _layerToPng(Layer layer) async {
    return null;
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

    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      settings: settings,
      layers: [
        Layer(
          id: 'layer_0',
          name: 'Background',
        ),
      ],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    return project;
  }

  Future<bool> deleteProject(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> selectHcpFile() async {
    return null;
  }
}
