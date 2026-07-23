import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/drawable.dart';
import '../services/project_service.dart';
import '../services/history_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ProjectProvider extends ChangeNotifier {
  final ProjectService _projectService = ProjectService();
  final HistoryService _historyService = HistoryService();
  final Uuid _uuid = const Uuid();

  Project? _currentProject;
  List<Project> _recentProjects = [];
  bool _loading = false;
  bool _hasUnsavedChanges = false;
  Timer? _backupTimer;

  Project? get currentProject => _currentProject;
  List<Project> get recentProjects => _recentProjects;
  HistoryService get history => _historyService;
  bool get loading => _loading;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

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

  void setLayerOpacity(int index, double opacity) {
    if (_currentProject == null || index >= _currentProject!.layers.length) return;
    _currentProject!.layers[index].opacity = opacity.clamp(0.0, 1.0);
    notifyListeners();
  }

  void addDrawable(Drawable drawable) {
    if (_currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null || current.locked) return;
    current.drawables.add(drawable);
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
}
