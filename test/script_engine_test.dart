import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/script_engine.dart';
import 'package:hue_cai/services/script_runner.dart';

ScriptEngine _run(String source) {
  final engine = ScriptEngine();
  engine.run(source);
  return engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScriptEngine parsing', () {
    test('comments and blank lines are ignored', () {
      final engine = _run('# hi\n\n   \n// also a comment\n');
      expect(engine.ops, isEmpty);
    });

    test('rect: filled by default, stroke when a width is given', () {
      final engine = _run('rect 10,20,30,40 #FF8800\nrect 0,0,5,5 blue 2');
      expect(engine.ops, hasLength(2));
      final filled = (engine.ops[0] as OpAddDrawable).drawable;
      expect(filled.shapeType, ShapeType.rect);
      expect(filled.isFilled, isTrue);
      expect(filled.color, const Color(0xFFFF8800));
      expect(filled.points.first, const Offset(10, 20));
      expect(filled.points.last, const Offset(40, 60));
      final stroked = (engine.ops[1] as OpAddDrawable).drawable;
      expect(stroked.isFilled, isFalse);
      expect(stroked.color, Colors.blue);
      expect(stroked.strokeWidth, 2.0);
    });

    test('ellipse, line, poly, dot and text produce the right drawables',
        () {
      final engine = _run(
          'ellipse 0,0,10,10 red\n'
          'line 0,0,10,10 green 3\n'
          'poly 0,0 10,0 5,10 purple\n'
          'dot 50,50 orange 5\n'
          'text 10,10 hello #123456 18');
      final types = engine.ops
          .whereType<OpAddDrawable>()
          .map((op) => op.drawable.shapeType)
          .toList();
      expect(types, [
        ShapeType.ellipse,
        ShapeType.line,
        ShapeType.polygon,
        ShapeType.ellipse,
        null,
      ]);
      final poly = (engine.ops[2] as OpAddDrawable).drawable;
      expect(poly.points, hasLength(3));
      final dot = (engine.ops[3] as OpAddDrawable).drawable;
      // dot r=5 → bounding box 10x10 centred on the point.
      expect(dot.points.first, const Offset(45, 45));
      expect(dot.points.last, const Offset(55, 55));
      final text = (engine.ops[4] as OpAddDrawable).drawable;
      expect(text.textData, 'hello');
      expect(text.color, const Color(0xFF123456));
      expect(text.fontSize, 18.0);
    });

    test('layer command emits an OpLayer', () {
      final engine = _run('layer 背景\nrect 0,0,1,1 red');
      expect(engine.ops.first, isA<OpLayer>());
      expect((engine.ops.first as OpLayer).name, '背景');
      // The rect after it targets that layer.
      expect((engine.ops[1] as OpAddDrawable).layerName, '背景');
    });

    test('grid expands to cols×rows rects', () {
      final engine = _run('grid 3,2,10,10,2 red');
      expect(engine.ops, hasLength(6));
      final first = (engine.ops.first as OpAddDrawable).drawable;
      expect(first.points.first, Offset.zero);
      expect(first.points.last, const Offset(10, 10));
      final last = (engine.ops.last as OpAddDrawable).drawable;
      expect(last.points.first, const Offset(24, 12));
    });

    test('var and \$-interpolation, including the \$i loop counter', () {
      final engine = _run(
          'var size = 20\n'
          'repeat 3 {\n'
          '  rect \$i,\$i,size,size red\n'
          '}');
      expect(engine.ops, hasLength(3));
      final points = engine.ops
          .whereType<OpAddDrawable>()
          .map((op) => op.drawable.points.first)
          .toList();
      expect(points, [
        const Offset(0, 0),
        const Offset(1, 1),
        const Offset(2, 2),
      ]);
      final sizes = engine.ops
          .whereType<OpAddDrawable>()
          .map((op) => op.drawable.points.last)
          .toList();
      expect(sizes.last, const Offset(22, 22));
    });

    test('nested repeat multiplies', () {
      final engine = _run(
          'repeat 2 {\n'
          '  repeat 3 {\n'
          '    dot 0,0 red\n'
          '  }\n'
          '}');
      expect(engine.ops, hasLength(6));
    });

    test('named colors and 8-digit hex', () {
      final engine = _run('dot 0,0 #80FF0000 2\ndot 1,1 gray 2');
      final a = (engine.ops[0] as OpAddDrawable).drawable.color;
      expect(a, const Color(0x80FF0000));
      final b = (engine.ops[1] as OpAddDrawable).drawable.color;
      expect(b, Colors.grey);
    });

    test('errors: unknown command, bad number, unbalanced braces', () {
      expect(() => _run('frobnicate 1'), throwsA(isA<ScriptException>()));
      expect(() => _run('rect x,y,1,1 red'), throwsA(isA<ScriptException>()));
      expect(() => _run('rect 0,0,1,1 #zzz'), throwsA(isA<ScriptException>()));
      expect(() => _run('repeat 2 {\nrect 0,0,1,1 red'),
          throwsA(isA<ScriptException>()));
      expect(() => _run('rect 0,0,1,1 red\n}'), throwsA(isA<ScriptException>()));
      expect(() => _run('repeat 2 {\nrepeat 2 {\n}\n}\n}\n'),
          throwsA(isA<ScriptException>()));
    });

    test('repeat count can be fractional (rounded down/up) and zero', () {
      expect(_run('repeat 2.9 {\ndot 0,0 red\n}').ops, hasLength(3));
      expect(_run('repeat 0 {\ndot 0,0 red\n}').ops, isEmpty);
    });

    test('line kind classification for the console', () {
      expect(ScriptEngine.classify('# hi'), ScriptLineKind.comment);
      expect(ScriptEngine.classify('var a = 1'), ScriptLineKind.varDecl);
      expect(ScriptEngine.classify('layer x'), ScriptLineKind.layer);
      expect(ScriptEngine.classify('repeat 3 {'), ScriptLineKind.control);
      expect(ScriptEngine.classify('}'), ScriptLineKind.control);
      expect(ScriptEngine.classify('rect 0,0,1,1 red'), ScriptLineKind.command);
    });
  });

  group('ScriptRunner', () {
    test('previewShapeCount counts without touching the project', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 64, height: 64);
      final runner = ScriptRunner(pp);
      final before =
          pp.currentProject!.layers.first.drawables.length; // seeded bg rect
      final n = runner
          .previewShapeCount('rect 0,0,1,1 red\nrect 1,1,1,1 red');
      expect(n, 2);
      expect(pp.currentProject!.layers.first.drawables, hasLength(before));
    });

    test('execute adds drawables to the current layer', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 64, height: 64);
      final runner = ScriptRunner(pp);
      await runner.execute(
          'layer 脚本层\nrect 0,0,10,10 red\nellipse 5,5,10,10 blue');
      final scriptLayer =
          pp.currentProject!.layers.firstWhere((l) => l.name == '脚本层');
      expect(scriptLayer.drawables, hasLength(2));
      // One undo step reverts the whole script — including the layer it
      // created, because the snapshot was taken before anything ran.
      pp.undo();
      expect(
        pp.currentProject!.layers.where((l) => l.name == '脚本层'),
        isEmpty,
      );
    });

    test('layer command creates a named layer and routes shapes to it',
        () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 64, height: 64);
      final before = pp.currentProject!.layers.length;
      final runner = ScriptRunner(pp);
      final added = await runner
          .execute('layer 脚本层\nrect 0,0,5,5 red\ndot 1,1 blue');
      expect(added, 2);
      final project = pp.currentProject!;
      expect(project.layers, hasLength(before + 1));
      final scriptLayer =
          project.layers.firstWhere((l) => l.name == '脚本层');
      expect(scriptLayer.drawables, hasLength(2));
      // The locked background stays untouched and the original layer
      // (index 1: the default layer) is re-selected afterwards.
      expect(
        project.layers.first.drawables,
        hasLength(1), // the seeded white background rect
      );
      expect(project.currentLayerIndex, 1);
    });

    test('existing layers are reused, not duplicated', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 64, height: 64);
      final runner = ScriptRunner(pp);
      await runner.execute('layer 基础\nrect 0,0,1,1 red');
      final count = pp.currentProject!.layers.length;
      await runner.execute('layer 基础\nrect 2,0,1,1 red');
      expect(pp.currentProject!.layers, hasLength(count));
      final named =
          pp.currentProject!.layers.firstWhere((l) => l.name == '基础');
      expect(named.drawables, hasLength(2));
    });

    test('a parse error leaves the project untouched', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 64, height: 64);
      final runner = ScriptRunner(pp);
      await expectLater(
        () => runner.execute('layer 脚本层\nrect 0,0,1,1 red\nnope 1'),
        throwsA(isA<ScriptException>()),
      );
      expect(
        pp.currentProject!.layers
            .where((l) => l.name == '脚本层'),
        isEmpty,
      );
      // A fresh project has two layers (locked background + default layer);
      // the script's layer must not exist after the failed parse.
      expect(pp.currentProject!.layers, hasLength(2));
    });
  });
}
