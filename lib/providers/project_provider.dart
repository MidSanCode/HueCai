import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../models/project.dart';
import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/drawable.dart';
import '../models/selection_data.dart';
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
      name: name ??
          'layer.default_name'.tr(
            namedArgs: {'n': '${_currentProject!.layers.length + 1}'},
          ),
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

  /// Removes all content (drawables and image) from the layer at [index],
  /// keeping the layer itself.
  void clearLayer(int index) {
    if (_currentProject == null ||
        index < 0 ||
        index >= _currentProject!.layers.length) {
      return;
    }
    final layer = _currentProject!.layers[index];
    if (layer.drawables.isEmpty && layer.image == null) return;
    saveSnapshot();
    layer.drawables = [];
    layer.image = null;
    layer.imagePath = null;
    _markChanged();
  }

  void duplicateLayer(int index) {
    if (_currentProject == null) return;
    final original = _currentProject!.layers[index];
    final copy = original.copyWith(
      id: _uuid.v4(),
      name: 'layer.copy_suffix'.tr(namedArgs: {'name': original.name}),
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
      final bg = Color(_currentProject!.settings.backgroundColor);
      final isJpg = format == 'jpg';
      // PNG keeps transparency when the background is transparent;
      // JPEG has no alpha channel, so fall back to white.
      final useBg = isJpg ? (bg.a > 0 ? bg : Colors.white) : bg;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      // Draw the background only when it is visible; a transparent
      // background exports as an alpha channel in PNG.
      if (useBg.a > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = useBg,
        );
      }
      for (final layer in _currentProject!.layers) {
        if (!layer.visible) continue;
        for (final d in layer.drawables) {
          d.draw(canvas, Paint());
        }
        if (layer.image != null) {
          final img = layer.image!;
          canvas.save();
          canvas.translate(layer.imageOffset.dx + img.width / 2, layer.imageOffset.dy + img.height / 2);
          canvas.rotate(layer.imageRotation);
          final flipX = layer.imageFlipH ? -1.0 : 1.0;
          final flipY = layer.imageFlipV ? -1.0 : 1.0;
          canvas.scale(layer.imageScale * flipX, layer.imageScale * flipY);
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
            Paint()..color = Colors.white.withValues(alpha: layer.opacity),
          );
          canvas.restore();
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

  // ─── Clipboard ───────────────────────────────────────────

  Drawable? _clipboard;

  Drawable? get clipboard => _clipboard;

  void setClipboard(Drawable? drawable) {
    _clipboard = drawable;
    notifyListeners();
  }

  void pasteClipboard() {
    if (_clipboard == null || _currentProject == null) return;
    final current = _currentProject!.currentLayer;
    if (current == null || current.locked) return;
    saveSnapshot();
    final pasted = _clipboard!.copyWith(
      id: _uuid.v4(),
      points: _clipboard!.points.map((p) => p + const Offset(20, 20)).toList(),
      selected: true,
    );
    current.drawables.add(pasted);
    _markChanged();
  }

  // ─── Selection system ────────────────────────────────────

  SelectionPhase _selectionPhase = SelectionPhase.none;
  SelectionMethod _selectionMethod = SelectionMethod.rect;
  bool _selectionAddMode = true;

  /// True while an editing preview should punch a hole where pixels were
  /// cut, so the floating clip visibly moves away from empty space.
  bool _selectionCutout = false;

  /// Fully opaque mask image used to erase the cut region (dstOut).
  ui.Image? _selectionSolidImage;
  SelectionMask? _selectionMask;
  ui.Image? _canvasSnapshot;
  ui.Image? _selectionMaskImage;
  ui.Image? _selectionClipImage;
  Rect _selectionClipBounds = Rect.zero;

  /// Bounding box of the current selection mask, used to draw the dashed
  /// outline around the selected region.
  ui.Path? _selectionOutlinePath;
  TransformMode _transformMode = TransformMode.scale;
  bool _aspectRatioLocked = true;
  double _editScaleX = 1, _editScaleY = 1;
  double _editRotate = 0;
  Offset _editTranslate = Offset.zero;

  SelectionPhase get selectionPhase => _selectionPhase;
  SelectionMethod get selectionMethod => _selectionMethod;
  bool get selectionAddMode => _selectionAddMode;
  bool get selectionCutout => _selectionCutout;
  ui.Image? get selectionSolidImage => _selectionSolidImage;
  SelectionMask? get selectionMask => _selectionMask;
  ui.Image? get canvasSnapshot => _canvasSnapshot;
  ui.Image? get selectionMaskImage => _selectionMaskImage;
  ui.Image? get selectionClipImage => _selectionClipImage;
  Rect get selectionClipBounds => _selectionClipBounds;

  ui.Path? get selectionOutlinePath => _selectionOutlinePath;
  TransformMode get transformMode => _transformMode;
  bool get aspectRatioLocked => _aspectRatioLocked;
  double get editScaleX => _editScaleX;
  double get editScaleY => _editScaleY;
  double get editRotate => _editRotate;
  Offset get editTranslate => _editTranslate;
  bool get hasActiveSelection => _selectionMask != null && !_selectionMask!.isEmpty;

  void setSelectionMethod(SelectionMethod m) {
    _selectionMethod = m;
    notifyListeners();
  }

  void setSelectionAddMode(bool v) {
    _selectionAddMode = v;
    notifyListeners();
  }

  void setTransformMode(TransformMode m) {
    _transformMode = m;
    notifyListeners();
  }

  void setAspectRatioLocked(bool v) {
    _aspectRatioLocked = v;
    notifyListeners();
  }

  void _regenerateMaskImage() {
    if (_selectionMask == null) {
      _selectionMaskImage = null;
      _selectionSolidImage = null;
      _selectionOutlinePath = null;
      return;
    }
    // Build marching-ants contour paths from the mask boundary.
    final path = ui.Path();
    for (final loop in _selectionMask!.contours()) {
      if (loop.isEmpty) continue;
      path.moveTo(loop.first.dx, loop.first.dy);
      for (int i = 1; i < loop.length; i++) {
        path.lineTo(loop[i].dx, loop[i].dy);
      }
      path.close();
    }
    _selectionOutlinePath = path;
    _selectionMask!.toRgbaImage().then((img) {
      _selectionMaskImage = img;
      notifyListeners();
    });
    _selectionMask!.toRgbaImage(alphaDivisor: 1).then((img) {
      _selectionSolidImage = img;
      notifyListeners();
    });
  }

  Future<void> beginSelection() async {
    if (_currentProject == null) return;
    _selectionPhase = SelectionPhase.selecting;
    _selectionCutout = false;
    _selectionMask = SelectionMask(
      _currentProject!.settings.width.toInt(),
      _currentProject!.settings.height.toInt(),
    );
    try {
      _canvasSnapshot = await rasterizeCanvas();
    } catch (_) {
      _canvasSnapshot = null;
    }
    _regenerateMaskImage();
    notifyListeners();
  }

  void applySelectionShape(SelectionMask shape, bool add) {
    if (_selectionMask == null) return;
    if (_selectionMask!.isEmpty && !add) {
      // Nothing selected yet: a fresh drag always starts a new selection
      // (PS-like), even when the add/subtract toggle is on subtract.
      _selectionMask!.applyMask(shape, true);
    } else {
      _selectionMask!.applyMask(shape, add);
    }
    _regenerateMaskImage();
    notifyListeners();
  }

  void invertSelection() {
    if (_selectionMask == null) return;
    _selectionMask!.invert();
    _regenerateMaskImage();
    notifyListeners();
  }

  void clearPixelSelection() {
    if (_selectionMask != null) _selectionMask!.clear();
    _selectionPhase = SelectionPhase.none;
    _selectionMaskImage = null;
    _selectionClipImage = null;
    _selectionClipBounds = Rect.zero;
    _selectionOutlinePath = null;
    _selectionSolidImage = null;
    _selectionCutout = false;
    _editScaleX = _editScaleY = 1;
    _editRotate = 0;
    _editTranslate = Offset.zero;
    notifyListeners();
  }

  void confirmSelection() {
    _selectionPhase = SelectionPhase.selected;
    notifyListeners();
  }

  Color? get canvasBackgroundColor {
    final p = _currentProject;
    if (p == null) return null;
    return Color(p.settings.backgroundColor);
  }

  void setCanvasBackgroundColor(Color c) {
    final p = _currentProject;
    if (p == null) return;
    p.settings = p.settings.copyWith(backgroundColor: c.toARGB32());
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Activates marquee selection mode: resets to rect method and starts a
  /// fresh selection session so the panel is ready immediately.
  void enterSelectionMode() {    _selectionMethod = SelectionMethod.rect;
    if (_selectionPhase == SelectionPhase.none ||
        _selectionPhase == SelectionPhase.selecting) {
      beginSelection();
    }
    notifyListeners();
  }

  /// Undo that first cancels an active editing preview.
  void smartUndo() {
    if (_selectionPhase == SelectionPhase.editing) {
      cancelSelectionEdit();
      return;
    }
    undo();
  }

  Future<void> copySelection() async {
    if (!hasActiveSelection || _canvasSnapshot == null) return;
    _selectionCutout = false;
    final mask = _selectionMask!;
    final bounds = mask.bounds;
    if (bounds.isEmpty) return;
    _selectionClipBounds = bounds;
    final src = _canvasSnapshot!;
    final w = bounds.width.ceil().clamp(1, src.width);
    final h = bounds.height.ceil().clamp(1, src.height);
    final bd = await src.toByteData();
    final srcBytes = bd?.buffer.asUint8List() ?? Uint8List(0);
    final dest = Uint8List(w * h * 4);
    if (srcBytes.isNotEmpty) {
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final sx = (bounds.left + x).round().clamp(0, src.width - 1);
          final sy = (bounds.top + y).round().clamp(0, src.height - 1);
          final si = (sy * src.width + sx) * 4;
          final di = (y * w + x) * 4;
          final mi = sy * mask.width + sx;
          if (mask.data[mi] != 0) {
            dest[di] = srcBytes[si];
            dest[di + 1] = srcBytes[si + 1];
            dest[di + 2] = srcBytes[si + 2];
            dest[di + 3] = srcBytes[si + 3];
          } else {
            dest[di + 3] = 0;
          }
        }
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(dest, w, h, ui.PixelFormat.rgba8888, completer.complete);
    _selectionClipImage = await completer.future;
    _selectionPhase = SelectionPhase.editing;
    _editScaleX = _editScaleY = 1;
    _editRotate = 0;
    _editTranslate = Offset.zero;
    notifyListeners();
  }

  Future<void> cutSelection() async {
    if (!hasActiveSelection || _canvasSnapshot == null || _currentProject == null) return;
    await copySelection();
    _selectionCutout = true;
    // Clear selected pixels from canvas snapshot
    final mask = _selectionMask!;
    final src = _canvasSnapshot!;
    final bd = await src.toByteData();
    if (bd == null) return;
    final bytes = bd.buffer.asUint8List();
    for (int i = 0; i < mask.data.length && i * 4 + 3 < bytes.length; i++) {
      if (mask.data[i] != 0) {
        bytes[i * 4 + 3] = 0;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, src.width, src.height, ui.PixelFormat.rgba8888, completer.complete);
    _canvasSnapshot = await completer.future;
    notifyListeners();
  }

  Future<void> applySelectionEdit() async {
    if (_selectionClipImage == null || _currentProject == null) return;
    final project = _currentProject!;
    saveSnapshot();
    final w = project.settings.width.toInt();
    final h = project.settings.height.toInt();
    // Apply the edit to the ACTIVE layer only. The previous implementation
    // flattened the entire project into one raster, which destroyed the
    // layer structure and let a cut punch through — or appear to move —
    // the background layer.
    final curIdx = project.currentLayerIndex.clamp(0, project.layers.length - 1);
    final cur = project.layers[curIdx];
    ui.Image base = await rasterizeLayer(cur);
    if (_selectionCutout && _selectionSolidImage != null) {
      // Cut: erase the selected pixels from the active layer only, so other
      // layers (the background included) are never punched through or moved.
      base = await _eraseWithMask(base, _selectionSolidImage!, w, h);
    }
    // Composite the transformed clip onto the same layer.
    final result = await _compositeClipOnBase(base, w, h);
    _replaceLayerContentWithImage(cur, result);
    _hasUnsavedChanges = true;
    // Return to an active selection session so the user can immediately
    // keep selecting after the change is applied.
    await restartSelectionSession();
  }

  /// Rasterizes a single layer (drawables + image content) at full canvas size.
  Future<ui.Image> rasterizeLayer(Layer layer) async {
    final w = _currentProject!.settings.width.toInt();
    final h = _currentProject!.settings.height.toInt();
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    for (final d in layer.drawables) {
      d.draw(c, Paint());
    }
    if (layer.image != null) {
      final img = layer.image!;
      c.save();
      c.translate(layer.imageOffset.dx + img.width / 2, layer.imageOffset.dy + img.height / 2);
      c.rotate(layer.imageRotation);
      final flipX = layer.imageFlipH ? -1.0 : 1.0;
      final flipY = layer.imageFlipV ? -1.0 : 1.0;
      c.scale(layer.imageScale * flipX, layer.imageScale * flipY);
      c.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
        Paint()..color = Colors.white.withValues(alpha: layer.opacity),
      );
      c.restore();
    }
    return recorder.endRecording().toImage(w, h);
  }

  Future<ui.Image> _eraseWithMask(ui.Image src, ui.Image mask, int w, int h) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.drawImage(src, Offset.zero, Paint());
    c.drawImage(mask, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
    return recorder.endRecording().toImage(w, h);
  }

  Future<ui.Image> _compositeClipOnBase(ui.Image base, int w, int h) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    c.drawImage(base, Offset.zero, Paint());
    // Composite transformed clip image
    c.save();
    final bounds = _selectionClipBounds;
    c.translate(
      bounds.center.dx + _editTranslate.dx,
      bounds.center.dy + _editTranslate.dy,
    );
    c.rotate(_editRotate);
    c.scale(_editScaleX, _editScaleY);
    c.translate(-bounds.center.dx, -bounds.center.dy);
    c.drawImage(_selectionClipImage!, bounds.topLeft, Paint());
    c.restore();
    return recorder.endRecording().toImage(w, h);
  }

  /// Collapses a layer's drawables + image into a single full-canvas raster.
  void _replaceLayerContentWithImage(Layer layer, ui.Image image) {
    layer.image = image;
    layer.imagePath = null;
    layer.imageOffset = Offset.zero;
    layer.imageRotation = 0;
    layer.imageScale = 1.0;
    layer.imageFlipH = false;
    layer.imageFlipV = false;
    layer.drawables = [];
  }

  /// Bakes a raster as the layer's whole content (used by selection apply).
  Future<void> bakeLiquifyResult(Layer layer, ui.Image warped) async {
    _replaceLayerContentWithImage(layer, warped);
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Flags the project as dirty without touching content (used by canvas
  /// gestures that mutate layer objects directly).
  void markUnsavedChanges() {
    _hasUnsavedChanges = true;
  }

  /// Returns to a fresh selection session: clears the floating clip and edit
  /// transforms, and re-arms the selection mask so the user can continue
  /// selecting immediately after a change is applied.
  Future<void> restartSelectionSession() async {
    if (_currentProject == null) return;
    _selectionPhase = SelectionPhase.selecting;
    _selectionCutout = false;
    _selectionMask = SelectionMask(
      _currentProject!.settings.width.toInt(),
      _currentProject!.settings.height.toInt(),
    );
    _selectionClipImage = null;
    _selectionClipBounds = Rect.zero;
    _selectionOutlinePath = null;
    _selectionMaskImage = null;
    _selectionSolidImage = null;
    _editScaleX = _editScaleY = 1;
    _editRotate = 0;
    _editTranslate = Offset.zero;
    try {
      _canvasSnapshot = await rasterizeCanvas();
    } catch (_) {
      _canvasSnapshot = null;
    }
    notifyListeners();
  }

  void cancelSelectionEdit() {
    _selectionPhase = SelectionPhase.selected;
    _selectionClipImage = null;
    _editScaleX = _editScaleY = 1;
    _editRotate = 0;
    _editTranslate = Offset.zero;
    notifyListeners();
  }

  Future<ui.Image> rasterizeCanvas() async {
    if (_currentProject == null) {
      final c2 = Completer<ui.Image>();
      final img = await _createTransparentImage(1, 1);
      c2.complete(img);
      return c2.future;
    }
    final w = _currentProject!.settings.width.toInt();
    final h = _currentProject!.settings.height.toInt();
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    for (final layer in _currentProject!.layers) {
      if (!layer.visible) continue;
      for (final d in layer.drawables) d.draw(c, Paint());
      if (layer.image != null) {
        final img = layer.image!;
        c.save();
        c.translate(layer.imageOffset.dx + img.width / 2, layer.imageOffset.dy + img.height / 2);
        c.rotate(layer.imageRotation);
        final flipX = layer.imageFlipH ? -1.0 : 1.0;
        final flipY = layer.imageFlipV ? -1.0 : 1.0;
        c.scale(layer.imageScale * flipX, layer.imageScale * flipY);
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(-img.width / 2, -img.height / 2, img.width.toDouble(), img.height.toDouble()),
          Paint()..color = Colors.white.withValues(alpha: layer.opacity),
        );
        c.restore();
      }
    }
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  Future<ui.Image> _createTransparentImage(int w, int h) async {
    final pixels = Uint8List(w * h * 4);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  void updateSelectionEditTransform({
    double? scaleX, double? scaleY,
    double? rotate,
    Offset? translate,
  }) {
    if (!_aspectRatioLocked) {
      if (scaleX != null) _editScaleX = scaleX;
      if (scaleY != null) _editScaleY = scaleY;
    } else {
      if (scaleX != null) _editScaleX = _editScaleY = scaleX;
      if (scaleY != null) _editScaleY = _editScaleX = scaleY;
    }
    if (rotate != null) _editRotate = rotate;
    if (translate != null) _editTranslate = translate;
    notifyListeners();
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
