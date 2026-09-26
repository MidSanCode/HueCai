import '../providers/project_provider.dart';
import 'script_engine.dart';

/// 把脚本操作落到当前工程：提供计数预览（运行前给用户看）与真正的执行。
///
/// 执行走 `ProjectProvider.saveSnapshot()` + `addDrawable()`，所以整个脚本的
/// 结果是一次可撤销的编辑；`layer` 命令通过 `addLayer(name:)`/`setCurrentLayer`
/// 实现，并在脚本结束后回到脚本开始时的图层。
class ScriptRunner {
  final ProjectProvider pp;

  ScriptRunner(this.pp);

  /// 快速解析，返回将添加的图形数量（不修改工程）。
  ///
  /// 抛 [ScriptException] 时原样传出，供对话框显示行级错误。
  int previewShapeCount(String source) {
    final engine = ScriptEngine();
    engine.run(source);
    return engine.shapeCount;
  }

  /// 执行脚本。返回添加的图形数。任何解析错误都在任何修改发生前抛出。
  Future<int> execute(String source) async {
    final engine = ScriptEngine();
    engine.run(source);
    final project = pp.currentProject;
    if (project == null) return 0;
    if (engine.ops.isEmpty) return 0;

    final originalLayer = project.currentLayerIndex;
    pp.saveSnapshot();
    var added = 0;
    try {
      for (final op in engine.ops) {
        switch (op) {
          case OpLayer(:final name):
            final existing = project.layers.indexWhere((l) => l.name == name);
            if (existing >= 0) {
              pp.setCurrentLayer(existing);
            } else {
              pp.addLayer(name: name);
            }
          case OpAddDrawable(:final drawable, :final layerName):
            if (layerName != null) {
              final idx = project.layers.indexWhere((l) => l.name == layerName);
              if (idx < 0) {
                pp.addLayer(name: layerName);
              }
              final idx2 = project.layers.indexWhere((l) => l.name == layerName);
              if (idx2 >= 0) pp.setCurrentLayer(idx2);
            }
            pp.addDrawable(drawable);
            added++;
        }
      }
    } finally {
      if (originalLayer < project.layers.length) {
        pp.setCurrentLayer(originalLayer);
      }
      pp.refresh();
    }
    return added;
  }
}
