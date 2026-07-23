import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';
import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/drawable.dart';
import '../services/project_service.dart';
import '../services/history_service.dart';

class ProjectProvider extends ChangeNotifier {
  final ProjectService _projectService = ProjectService();
  final HistoryService _historyService = HistoryService();
  final Uuid _uuid = const Uuid();

  Project? _currentProject;
  List<Project> _recentProjects = [];
  bool _loading = false;

  Project? get currentProject => _currentProject;
  List<Project> get recentProjects => _recentProjects;
  HistoryService get history => _historyService;
  bool get loading => _loading;

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
    _historyService.clear();
    notifyListeners();
  }

  Future<void> openProject(String filePath) async {
    final project = await _projectService.loadProject(filePath);
    if (project != null) {
      _currentProject = project;
      _historyService.clear();
      notifyListeners();
    }
  }

  Future<void> saveProject() async {
    if (_currentProject == null) return;
    await _projectService.saveProject(_currentProject!, _historyService);
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
    _currentProject = null;
    _historyService.clear();
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
    notifyListeners();
  }

  void addDrawable(Drawable drawable) {
    if (_currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null || current.locked) return;
    current.drawables.add(drawable);
    notifyListeners();
  }

  void updateDrawable(String drawableId, Drawable updated) {
    if (_currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null) return;
    final idx = current.drawables.indexWhere((d) => d.id == drawableId);
    if (idx != -1) {
      current.drawables[idx] = updated;
      notifyListeners();
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
