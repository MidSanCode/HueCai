import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../models/project.dart';
import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/drawable.dart';
import '../services/project_service.dart';
import '../services/history_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ProjectStats {
  final String createdAt;
  int strokeCount;
  int drawingTimeSeconds;
  DateTime? _firstStrokeTime;

  ProjectStats({
    this.createdAt = '',
    this.strokeCount = 0,
    this.drawingTimeSeconds = 0,
  });

  void recordStroke() {
    strokeCount++;
    final now = DateTime.now();
    _firstStrokeTime ??= now;
    drawingTimeSeconds = now.difference(_firstStrokeTime!).inSeconds;
  }
}

class ProjectProvider extends ChangeNotifier {
  final ProjectService _projectService = ProjectService();
  final HistoryService _historyService = HistoryService();
  final Uuid _uuid = const Uuid();

  Project? _currentProject;
  List<Project> _recentProjects = [];
  bool _loading = false;
  bool _hasUnsavedChanges = false;
  Timer? _backupTimer;
  final ProjectStats _stats = ProjectStats();

  Project? get currentProject => _currentProject;
  List<Project> get recentProjects => _recentProjects;
  HistoryService get history => _historyService;
  bool get loading => _loading;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  ProjectStats get stats => _stats;

  void startBackupTimer() {
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(const Duration(minutes: 2), (_) => _autoBackup());
  }

  void stopBackupTimer() {
    _backupTimer?.cancel();
    _backupTimer = null;
  }

  Future<void> _autoBackup() async {
    if (_currentProject == null || !_hasUnsavedChanges) return;
    try {
      final dir = await getTemporaryDirectory();
      final backupDir = Directory('${dir.path}/huecai_backups');
      if (!await backupDir.exists()) await backupDir.create();
      final backupPath = '${backupDir.path}/${_currentProject!.id}_backup.hcp';
      await _projectService.saveProject(_currentProject!, _historyService,
          filePath: backupPath);
    } catch (_) {}
  }

  Future<String?> getBackupPath() async {
    final dir = await getTemporaryDirectory();
    final backupPath = '${dir.path}/huecai_backups/${_currentProject!.id}_backup.hcp';
    final file = File(backupPath);
    if (await file.exists()) return backupPath;
    return null;
  }

  Future<void> loadRecentProjects() async {
    _loading = true;
    notifyListeners();
    _recentProjects = await _projectService.listProjects();
    _loading = false;
    notifyListeners();
  }

  Future<void> createNewProject({
    required String name,
    required int width,
    required int height,
    CanvasUnit unit = CanvasUnit.px,
    double resolution = 72,
    ColorModel colorModel = ColorModel.sRGB,
    int channelDepth = 8,
    List<int>? iccProfileData,
  }) async {
    _currentProject = await _projectService.createProject(
      name: name,
      width: width,
      height: height,
      unit: unit,
      resolution: resolution,
      colorModel: colorModel,
      channelDepth: channelDepth,
      iccProfileData: iccProfileData,
    );
    _hasUnsavedChanges = true;
    _historyService.clear();
    _stats._firstStrokeTime = null;
    _stats.strokeCount = 0;
    _stats.drawingTimeSeconds = 0;
    notifyListeners();
  }

  Future<void> openProject(String filePath) async {
    final project = await _projectService.loadProject(filePath);
    if (project != null) {
      _currentProject = project;
      _hasUnsavedChanges = false;
      _historyService.clear();
      notifyListeners();
    }
  }

  Future<void> saveProject() async {
    if (_currentProject == null) return;
    await _projectService.saveProject(_currentProject!, _historyService);
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  Future<bool> deleteProject(String filePath) async {
    final result = await _projectService.deleteProject(filePath);
    if (result) {
      _recentProjects.removeWhere((p) => p.filePath == filePath);
      notifyListeners();
    }
    return result;
  }

  void closeProject() {
    stopBackupTimer();
    _currentProject = null;
    _hasUnsavedChanges = false;
    _historyService.clear();
    notifyListeners();
  }

  void saveSnapshot() {
    if (_currentProject == null) return;
    _historyService.pushEntry(HistoryEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      projectSnapshot: _currentProject!.toJson(),
    ));
  }

  void undo() {
    final snapshot = _historyService.undo();
    if (snapshot != null) restoreFromSnapshot(snapshot);
  }

  void redo() {
    final snapshot = _historyService.redo();
    if (snapshot != null) restoreFromSnapshot(snapshot);
  }

  void restoreFromSnapshot(Map<String, dynamic> snapshot) {
    if (_currentProject == null) return;
    final restored = Project.fromJson(snapshot);
    _currentProject!.layers = restored.layers;
    _currentProject!.currentLayerIndex = restored.currentLayerIndex;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void _markChanged() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  void setCurrentLayer(int index) {
    if (_currentProject != null && index < _currentProject!.layers.length) {
      _currentProject!.currentLayerIndex = index;
      notifyListeners();
    }
  }

  void addLayer({String? name}) {
    if (_currentProject == null) return;
    final layer = Layer(
      id: _uuid.v4(),
      name: name ?? 'Layer ${_currentProject!.layers.length + 1}',
    );
    _currentProject!.layers.add(layer);
    _currentProject!.currentLayerIndex = _currentProject!.layers.length - 1;
    _markChanged();
  }

  void deleteLayer(int index) {
    if (_currentProject == null || _currentProject!.layers.length <= 1) return;
    _currentProject!.layers.removeAt(index);
    if (_currentProject!.currentLayerIndex >= _currentProject!.layers.length) {
      _currentProject!.currentLayerIndex = _currentProject!.layers.length - 1;
    }
    _markChanged();
  }

  void duplicateLayer(int index) {
    if (_currentProject == null) return;
    final original = _currentProject!.layers[index];
    final copy = original.copyWith(
      id: _uuid.v4(),
      name: '${original.name} copy',
      drawables: original.drawables.map((d) => d.copyWith()).toList(),
    );
    _currentProject!.layers.insert(index + 1, copy);
    _markChanged();
  }

  void mergeDownLayer(int index) {
    if (_currentProject == null || index <= 0) return;
    final below = _currentProject!.layers[index - 1];
    final above = _currentProject!.layers[index];
    below.drawables.addAll(above.drawables);
    _currentProject!.layers.removeAt(index);
    setCurrentLayer(index - 1);
    _markChanged();
  }

  void setBackgroundColor(Color color) {
    if (_currentProject == null || _currentProject!.layers.isEmpty) return;
    final bgLayer = _currentProject!.layers.first;
    for (final d in bgLayer.drawables) {
      d.color = color;
    }
    _markChanged();
  }

  void setLayerOpacity(int index, double opacity) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].opacity = opacity.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleLayerVisibility(int index) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].visible = !_currentProject!.layers[index].visible;
    _markChanged();
  }

  void toggleLayerLock(int index) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].locked = !_currentProject!.layers[index].locked;
    _markChanged();
  }

  void renameLayer(int index, String newName) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].name = newName;
    _markChanged();
  }

  void moveLayerUp(int index) {
    if (_currentProject == null || index >= _currentProject!.layers.length - 1) return;
    final layer = _currentProject!.layers.removeAt(index);
    _currentProject!.layers.insert(index + 1, layer);
    _currentProject!.currentLayerIndex = index + 1;
    _markChanged();
  }

  void moveLayerDown(int index) {
    if (_currentProject == null || index <= 0) return;
    final layer = _currentProject!.layers.removeAt(index);
    _currentProject!.layers.insert(index - 1, layer);
    _currentProject!.currentLayerIndex = index - 1;
    _markChanged();
  }

  void setLayerBlendMode(int index, BlendModeExt mode) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].blendMode = mode;
    _markChanged();
  }

  void deleteDrawable(String drawableId) {
    if (_currentProject == null) return;
    for (final layer in _currentProject!.layers) {
      layer.drawables.removeWhere((d) => d.id == drawableId);
    }
    _markChanged();
  }

  Future<void> saveAsProject() async {
    if (_currentProject == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/huecai_projects');
    if (!await saveDir.exists()) await saveDir.create(recursive: true);
    final basePath = '${saveDir.path}/${_currentProject!.name}.hcp';
    final path = await _projectService.uniquePath(basePath);
    await _projectService.saveProject(_currentProject!, _historyService, filePath: path);
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  Future<void> exportImage(String format) async {
    if (_currentProject == null) return;
    try {
      final w = _currentProject!.settings.width;
      final h = _currentProject!.settings.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = Colors.white,
      );
      for (final layer in _currentProject!.layers) {
        if (!layer.visible) continue;
        for (final d in layer.drawables) {
          d.draw(canvas, Paint());
        }
      }
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (byteData == null) return;

      final ext = format == 'jpg' ? 'jpg' : 'png';
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'menu.file.export'.tr(),
        fileName: '${_currentProject!.name}.$ext',
        type: FileType.any,
      );
      if (result != null) {
        await File(result).writeAsBytes(byteData.buffer.asUint8List());
      }
    } catch (_) {}
  }

  Future<void> importImage(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width;
      final h = img.height;
      img.dispose();

      final name = file.uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      _currentProject = await _projectService.createProject(
        name: name,
        width: w,
        height: h,
      );
      // Rasterize imported image onto the first layer
      final layer = _currentProject!.layers.first;
      final drawable = Drawable(
        id: _uuid.v4(),
        isShape: true,
        shapeType: ShapeType.rect,
        points: [Offset.zero, Offset(w.toDouble(), h.toDouble())],
        color: Colors.transparent,
        isFilled: true,
        strokeWidth: 0,
      );
      layer.drawables.add(drawable);
      _hasUnsavedChanges = true;
      _historyService.clear();
      notifyListeners();
    } catch (_) {}
  }

  void addDrawable(Drawable drawable) {
    if (_currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null || current.locked) return;
    current.drawables.add(drawable);
    _stats.recordStroke();
    _markChanged();
  }

  void updateDrawable(String drawableId, Drawable updated) {
    if (_currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null) return;
    final idx = current.drawables.indexWhere((d) => d.id == drawableId);
    if (idx != -1) {
      current.drawables[idx] = updated;
      _markChanged();
    }
  }

  void clearSelection() {
    if (_currentProject == null) return;
    for (final layer in _currentProject!.layers) {
      for (final d in layer.drawables) {
        d.selected = false;
      }
    }
    notifyListeners();
  }

  void toggleFillDrawable(Drawable drawable, Color fillColor) {
    drawable.isFilled = !drawable.isFilled;
    drawable.color = fillColor;
    _markChanged();
  }

  void selectDrawable(Drawable drawable) {
    clearSelection();
    drawable.selected = true;
  }

  Drawable? get selectedDrawable {
    if (_currentProject == null) return null;
    for (final layer in _currentProject!.layers) {
      for (final d in layer.drawables) {
        if (d.selected) return d;
      }
    }
    return null;
  }

  // ─── Image placement ─────────────────────────────────────

  String? _imagePlacingLayerId;
  Offset _imagePlacingOffset = Offset.zero;
  double _imagePlacingRotation = 0;
  double _imagePlacingScale = 1.0;
  bool _imagePlacingFlipH = false;
  bool _imagePlacingFlipV = false;

  bool get isPlacingImage => _imagePlacingLayerId != null;
  Offset get imagePlacingOffset => _imagePlacingOffset;
  double get imagePlacingRotation => _imagePlacingRotation;
  double get imagePlacingScale => _imagePlacingScale;
  bool get imagePlacingFlipH => _imagePlacingFlipH;
  bool get imagePlacingFlipV => _imagePlacingFlipV;

  Layer? get imagePlacingLayer {
    if (_currentProject == null || _imagePlacingLayerId == null) return null;
    for (final layer in _currentProject!.layers) {
      if (layer.id == _imagePlacingLayerId) return layer;
    }
    return null;
  }

  Future<void> importImageToCanvas(String path) async {
    if (_currentProject == null) return;
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final name = file.uri.pathSegments.last;

      // Create new layer with the image
      final layer = Layer(
        id: _uuid.v4(),
        name: name,
        image: img,
        imagePath: path,
        imageOffset: Offset(
          (_currentProject!.settings.width - img.width) / 2,
          (_currentProject!.settings.height - img.height) / 2,
        ),
      );
      _currentProject!.layers.add(layer);
      _currentProject!.currentLayerIndex = _currentProject!.layers.length - 1;

      _imagePlacingLayerId = layer.id;
      _imagePlacingOffset = layer.imageOffset;
      _imagePlacingRotation = 0;
      _imagePlacingScale = 1.0;
      _imagePlacingFlipH = false;
      _imagePlacingFlipV = false;

      _hasUnsavedChanges = true;
      notifyListeners();
    } catch (_) {}
  }

  void updateImagePlacement({Offset? offset, double? rotation, double? scale, bool? flipH, bool? flipV}) {
    if (!isPlacingImage) return;
    if (offset != null) _imagePlacingOffset = offset;
    if (rotation != null) _imagePlacingRotation = rotation;
    if (scale != null) _imagePlacingScale = scale;
    if (flipH != null) _imagePlacingFlipH = flipH;
    if (flipV != null) _imagePlacingFlipV = flipV;
    final layer = imagePlacingLayer;
    if (layer != null) {
      layer.imageOffset = _imagePlacingOffset;
      layer.imageRotation = _imagePlacingRotation;
      layer.imageScale = _imagePlacingScale;
    }
    notifyListeners();
  }

  void confirmImagePlacement() {
    if (!isPlacingImage) return;
    final layer = imagePlacingLayer;
    if (layer != null) {
      layer.imageOffset = _imagePlacingOffset;
      layer.imageRotation = _imagePlacingRotation;
      layer.imageScale = _imagePlacingScale;
      layer.imageFlipH = _imagePlacingFlipH;
      layer.imageFlipV = _imagePlacingFlipV;
    }
    _imagePlacingLayerId = null;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void cancelImagePlacement() {
    if (!isPlacingImage) return;
    if (_currentProject != null && _imagePlacingLayerId != null) {
      _currentProject!.layers.removeWhere((l) => l.id == _imagePlacingLayerId);
    }
    _imagePlacingLayerId = null;
    notifyListeners();
  }

  // ─── Workspace management ────────────────────────────────

  Future<List<File>> listTrashFiles() => _projectService.listTrashFiles();
  Future<bool> restoreProject(String path) => _projectService.restoreProject(path);
  Future<bool> emptyTrash() => _projectService.emptyTrash();
  Future<bool> renameProject(String filePath, String newName) => _projectService.renameProject(filePath, newName);
  Future<bool> createFolder(String name) => _projectService.createFolder(name);
  Future<List<String>> listFolders() => _projectService.listFolders();
  Future<bool> moveToFolder(List<String> paths, String folder) => _projectService.moveToFolder(paths, folder);
  Future<bool> batchExport(List<String> paths, String destDir) => _projectService.batchExport(paths, destDir);
}
