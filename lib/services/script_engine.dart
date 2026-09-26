import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/drawable.dart';

/// 行式脚本 DSL — 每行一条命令，`#` 或 `//` 开头为注释，空行忽略。
///
/// 设计原则（对应路线图第 18 项「脚本插件能力」）：
/// - **沙盒**：脚本只能产生下面的结构化操作，引擎本身不触碰文件系统、
///   网络或任何 dart:io API；宿主（脚本对话框）决定这些操作落到哪里，
///   并先用 `dryRun` 式的计数预览，用户确认后才写入工程。
/// - **可读**：行式命令比嵌套 JSON 更适合手写：`rect 10,10,100,80 #FF8800`。
/// - **可组合**：`var` 与 `repeat n { … }` 让插件能做批量布局，
///   循环体内可用 `$名字` 引用变量，循环计数器固定叫 `$i`。
///
/// 支持的命令：
/// ```text
/// # 注释（// 同效）
/// var 名 = 数字
/// repeat 次数 {        … 配对的 } 单独一行；可嵌套（≤8 层）
/// layer 名称           （后续图形放到这一层；不存在则新建）
/// rect x,y,w,h 颜色 [描边]          无描边值 = 填充
/// ellipse x,y,w,h 颜色 [描边]
/// line x1,y1,x2,y2 颜色 [宽度]
/// poly x1,y1 x2,y2 … 颜色           至少 3 个点成多边形
/// dot x,y 颜色 [半径=4]
/// text x,y 文本 [颜色] [字号]
/// grid cols,rows,w,h,gap 颜色       批量网格矩形（插件常用件）
/// ```
///
/// 颜色：`#RRGGBB` / `#AARRGGBB` / 命名色（black white red green blue
/// yellow orange purple pink brown gray transparent）。
class ScriptEngine {
  /// 每条命令产出的操作，按顺序交给宿主执行。
  final List<ScriptOp> ops = [];

  int get shapeCount =>
      ops.whereType<OpAddDrawable>().length;

  /// 解析并展开整个脚本。抛 [ScriptException] 时 ops 保持已解析部分。
  void run(String source) {
    for (final line in _expandBlocks(_tokenize(source), depth: 0)) {
      _runCommand(line);
    }
  }

  // ─── 解析 ───────────────────────────────────────────────

  List<_Line> _tokenize(String source) {
    final lines = <_Line>[];
    final stack = <List<_Line>>[lines];
    var depth = 0;
    for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      if (line == '}') {
        depth--;
        if (depth < 0) throw ScriptException('多余的 }');
        stack.removeLast();
        continue;
      }
      final repeat = RegExp(r'^repeat\s+(\S+)\s*\{$').firstMatch(line);
      if (repeat != null) {
        depth++;
        if (depth > 8) throw ScriptException('repeat 嵌套超过 8 层');
        final body = <_Line>[];
        stack.last.add(_Line(
          raw: 'repeat ${repeat.group(1)}',
          isRepeat: true,
          body: body,
        ));
        stack.add(body);
        continue;
      }
      stack.last.add(_Line(raw: line));
    }
    if (depth > 0) throw ScriptException('repeat 缺少配对的 }');
    return lines;
  }

  /// 展开 repeat 块并做变量插值（`$名字` → 数值）。
  List<String> _expandBlocks(List<_Line> lines, {required int depth}) {
    final out = <String>[];
    for (final line in lines) {
      if (line.isRepeat) {
        final count =
            _num(line.raw.substring('repeat'.length).trim())
                .round()
                .clamp(0, 10000);
        for (var i = 0; i < count; i++) {
          // The loop counter is `$i`; also alias `_i` so a user variable
          // called `_i` keeps a stable slot.
          _vars['i'] = i.toDouble();
          out.addAll(_expandBlocks(line.body!, depth: depth + 1));
        }
        _vars.remove('i');
        continue;
      }
      out.add(_expandVars(line.raw));
    }
    return out;
  }

  final Map<String, double> _vars = {};

  String _expandVars(String line) {
    var out = line;
    for (final entry in _vars.entries) {
      out = out.replaceAll('\$${entry.key}', _fmt(entry.value));
    }
    return out;
  }

  // ─── 命令 ───────────────────────────────────────────────

  void _runCommand(String line) {
    final varMatch = RegExp(r'^var\s+([^\s=]+)\s*=\s*(.+)$').firstMatch(line);
    if (varMatch != null) {
      _vars[varMatch.group(1)!] = _num(varMatch.group(2)!);
      return;
    }
    final layerMatch = RegExp(r'^layer\s+(.+)$').firstMatch(line);
    if (layerMatch != null) {
      final name = layerMatch.group(1)!.trim();
      _currentLayer = name;
      ops.add(OpLayer(name));
      return;
    }
    final parts =
        line.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final cmd = parts.first.toLowerCase();
    final args = parts.sublist(1);
    switch (cmd) {
      case 'rect':
        _rectOrEllipse(ShapeType.rect, args);
      case 'ellipse':
        _rectOrEllipse(ShapeType.ellipse, args);
      case 'line':
        _line(args);
      case 'poly':
        _poly(args);
      case 'dot':
        _dot(args);
      case 'text':
        _text(args);
      case 'grid':
        _grid(args);
      default:
        throw ScriptException('未知命令: $cmd');
    }
  }

  void _rectOrEllipse(ShapeType type, List<String> args) {
    if (args.length < 2) throw ScriptException('$type 需要 x,y,w,h 颜色');
    final nums = _coords(args[0], 4);
    final hasStroke = args.length > 2;
    ops.add(OpAddDrawable(Drawable(
      id: const Uuid().v4(),
      isShape: true,
      shapeType: type,
      points: [
        Offset(nums[0], nums[1]),
        Offset(nums[0] + nums[2], nums[1] + nums[3]),
      ],
      color: _color(args[1]),
      strokeWidth: hasStroke ? _num(args[2]) : 1.0,
      isFilled: !hasStroke,
    ), layerName: _currentLayer));
  }

  void _line(List<String> args) {
    if (args.length < 2) throw ScriptException('line 需要 x1,y1,x2,y2 颜色');
    final nums = _coords(args[0], 4);
    ops.add(OpAddDrawable(Drawable(
      id: const Uuid().v4(),
      isShape: true,
      shapeType: ShapeType.line,
      points: [Offset(nums[0], nums[1]), Offset(nums[2], nums[3])],
      color: _color(args[1]),
      strokeWidth: args.length > 2 ? _num(args[2]) : 2.0,
    ), layerName: _currentLayer));
  }

  void _poly(List<String> args) {
    if (args.length < 4) {
      throw ScriptException('poly 至少需要 3 个点和一个颜色');
    }
    final colorArg = args.last;
    final points = <Offset>[];
    for (final c in args.take(args.length - 1)) {
      final nums = _coords(c, 2);
      points.add(Offset(nums[0], nums[1]));
    }
    ops.add(OpAddDrawable(Drawable(
      id: const Uuid().v4(),
      isShape: true,
      shapeType: ShapeType.polygon,
      points: points,
      color: _color(colorArg),
      strokeWidth: 2.0,
    ), layerName: _currentLayer));
  }

  void _dot(List<String> args) {
    if (args.length < 2) throw ScriptException('dot 需要 x,y 颜色 [半径]');
    final nums = _coords(args[0], 2);
    final r = args.length > 2 ? _num(args[2]) : 4.0;
    ops.add(OpAddDrawable(Drawable(
      id: const Uuid().v4(),
      isShape: true,
      shapeType: ShapeType.ellipse,
      points: [
        Offset(nums[0] - r, nums[1] - r),
        Offset(nums[0] + r, nums[1] + r),
      ],
      color: _color(args[1]),
      strokeWidth: 1.0,
      isFilled: true,
    ), layerName: _currentLayer));
  }

  void _text(List<String> args) {
    if (args.length < 2) throw ScriptException('text 需要 x,y 文本 [颜色] [字号]');
    final nums = _coords(args[0], 2);
    final color = args.length > 2 ? _color(args[2]) : Colors.black;
    final fontSize = args.length > 3 ? _num(args[3]) : 24.0;
    ops.add(OpAddDrawable(Drawable(
      id: const Uuid().v4(),
      points: [Offset(nums[0], nums[1])],
      color: color,
      textData: args[1],
      fontSize: fontSize,
    ), layerName: _currentLayer));
  }

  void _grid(List<String> args) {
    if (args.length < 2) {
      throw ScriptException('grid 需要 cols,rows,w,h,gap 颜色');
    }
    final nums = _coords(args[0], 5);
    final cols = nums[0].round().clamp(1, 200);
    final rows = nums[1].round().clamp(1, 200);
    final w = nums[2], h = nums[3], gap = nums[4];
    final color = _color(args[1]);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * (w + gap);
        final y = r * (h + gap);
        ops.add(OpAddDrawable(Drawable(
          id: const Uuid().v4(),
          isShape: true,
          shapeType: ShapeType.rect,
          points: [Offset(x, y), Offset(x + w, y + h)],
          color: color,
          strokeWidth: 1.0,
          isFilled: false,
        ), layerName: _currentLayer));
      }
    }
  }

  // ─── 基础解析 ───────────────────────────────────────────

  String? _currentLayer;

  List<double> _coords(String raw, int count) {
    final nums = raw.split(',').map(_num).toList();
    if (nums.length != count) {
      throw ScriptException('需要 $count 个以逗号分隔的数: $raw');
    }
    return nums;
  }

  double _num(String raw) {
    final v = raw.trim();
    final fromVar = _vars[v];
    if (fromVar != null) return fromVar;
    return double.tryParse(v) ?? (throw ScriptException('不是数字或变量: $v'));
  }

  Color _color(String raw) {
    final v = raw.trim();
    const named = <String, Color>{
      'black': Colors.black,
      'white': Colors.white,
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'brown': Colors.brown,
      'gray': Colors.grey,
      'grey': Colors.grey,
      'transparent': Colors.transparent,
    };
    final n = named[v.toLowerCase()];
    if (n != null) return n;
    final hex = v.replaceFirst('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    throw ScriptException('无法解析颜色: $v');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// 语法高亮用的行分类（控制台着色/校验）。
  static ScriptLineKind classify(String line) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || t.startsWith('//')) {
      return ScriptLineKind.comment;
    }
    if (t.startsWith('var ')) return ScriptLineKind.varDecl;
    if (t.startsWith('layer ')) return ScriptLineKind.layer;
    if (t.startsWith('repeat ') || t == '}') return ScriptLineKind.control;
    return ScriptLineKind.command;
  }
}

enum ScriptLineKind { comment, varDecl, layer, control, command }

/// 脚本展开后的中间行。
class _Line {
  final String raw;
  final bool isRepeat;
  final List<_Line>? body;
  _Line({required this.raw, this.isRepeat = false, this.body});
}

/// 脚本产出的一个操作。
sealed class ScriptOp {
  const ScriptOp();
}

/// 在 [layerName] 层（null = 当前层）添加图形。
class OpAddDrawable extends ScriptOp {
  final Drawable drawable;
  final String? layerName;
  const OpAddDrawable(this.drawable, {this.layerName});
}

/// 切换/新建目标图层。
class OpLayer extends ScriptOp {
  final String name;
  const OpLayer(this.name);
}

class ScriptException implements Exception {
  final String message;
  ScriptException(this.message);
  @override
  String toString() => message;
}
