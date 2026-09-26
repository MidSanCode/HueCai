import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/brush.dart';
import 'package:hue_cai/models/brush_preset.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/pattern.dart';
import 'package:hue_cai/providers/app_settings.dart';
import 'package:hue_cai/providers/tool_provider.dart';
import 'package:hue_cai/services/brush_texture.dart';
import 'package:hue_cai/services/pattern_renderer.dart';
import 'package:hue_cai/widgets/common/pattern_thumb.dart';

/// Alpha of the RGBA pixel at (x, y) in a generated tile.
int _alphaAt(List<int> rgba, int size, int x, int y) =>
    rgba[(y * size + x) * 4 + 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PatternSpec', () {
    test('round-trips through JSON', () {
      final spec = PatternSpec(
        id: 'p1',
        name: 'Screentone',
        kind: PatternKind.cross,
        spacing: 12.5,
        thickness: 1.75,
        angle: 0.5,
        density: 0.4,
        foreground: const Color(0xFF112233),
        background: const Color(0x80FFFFFF),
      );
      final restored = PatternSpec.fromJson(spec.toJson());
      expect(restored.id, 'p1');
      expect(restored.name, 'Screentone');
      expect(restored.kind, PatternKind.cross);
      expect(restored.spacing, 12.5);
      expect(restored.thickness, 1.75);
      expect(restored.angle, 0.5);
      expect(restored.density, 0.4);
      expect(restored.foreground, const Color(0xFF112233));
      expect(restored.background, const Color(0x80FFFFFF));
    });

    test('unknown kinds and missing fields fall back safely', () {
      final restored = PatternSpec.fromJson({
        'kind': 'from-the-future',
      });
      expect(restored.kind, PatternKind.dots);
      expect(restored.spacing, 8);
      expect(restored.foreground, const Color(0xFF000000));
    });

    test('stock library has unique ids', () {
      final ids = PatternSpec.builtIns().map((p) => p.id).toList();
      expect(ids, isNotEmpty);
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  group('PatternPack', () {
    test('encodes and decodes a pack', () {
      final patterns = PatternSpec.builtIns().take(3).toList();
      final text = PatternPack.encode(patterns, name: 'My tones');
      final decoded = PatternPack.decode(text);
      expect(decoded, isNotNull);
      expect(decoded, hasLength(3));
      expect(decoded!.first.kind, patterns.first.kind);
      expect(decoded.first.spacing, patterns.first.spacing);
    });

    test('rejects text that is not a pattern pack', () {
      expect(PatternPack.decode('not json'), isNull);
      expect(PatternPack.decode('{}'), isNull);
      // A brush pack is a different format and must not be mistaken for one.
      expect(PatternPack.decode(BrushPack.encode([])), isNull);
    });

    test('skips malformed entries but keeps the good ones', () {
      final text = '{"format":"${PatternPack.formatId}","version":1,'
          '"patterns":[{"id":"a","name":"A","kind":"dots"},"nope",7]}';
      final decoded = PatternPack.decode(text);
      expect(decoded, hasLength(1));
      expect(decoded!.single.id, 'a');
    });
  });

  group('PatternRenderer', () {
    test('tile size is a whole number of periods', () {
      final spec = PatternSpec.dotScreen(spacing: 10, radius: 2);
      final size = PatternRenderer.tileSizeFor(spec);
      expect(size % PatternRenderer.periodFor(spec), 0);
      expect(size, greaterThanOrEqualTo(PatternRenderer.preferredTileSize));
    });

    test('dot screens put ink at the cell centre and leave the gaps clear',
        () {
      final spec = PatternSpec.dotScreen(spacing: 8, radius: 2.6);
      final size = PatternRenderer.tileSizeFor(spec);
      final rgba = PatternRenderer.generate(spec);
      expect(rgba, hasLength(size * size * 4));
      // Cell centre (4,4) is solid ink; the corner between four cells is not.
      expect(_alphaAt(rgba, size, 4, 4), 255);
      expect(_alphaAt(rgba, size, 0, 0), 0);
    });

    test('generation is deterministic', () {
      final spec = PatternSpec(
        id: 'n',
        name: 'Noise',
        kind: PatternKind.noise,
        spacing: 6,
        density: 0.4,
      );
      expect(PatternRenderer.generate(spec), PatternRenderer.generate(spec));
    });

    test('periodic kinds tile seamlessly (pixels repeat with the period)', () {
      // Dots / lines / cross / checker / grid are periodic with `spacing`, so
      // the tile can wrap onto itself exactly.
      const periodic = [
        PatternKind.dots,
        PatternKind.lines,
        PatternKind.cross,
        PatternKind.checker,
        PatternKind.grid,
      ];
      for (final kind in periodic) {
        final spec = PatternSpec(
          id: 'k',
          name: kind.name,
          kind: kind,
          spacing: 8,
          thickness: 2.5,
        );
        final size = PatternRenderer.tileSizeFor(spec);
        final period = PatternRenderer.periodFor(spec);
        final rgba = PatternRenderer.generate(spec);
        for (var y = 0; y < size; y += 7) {
          for (var x = 0; x < size - period; x++) {
            expect(
              _alphaAt(rgba, size, x, y),
              _alphaAt(rgba, size, x + period, y),
              reason: '${kind.name} differs at ($x,$y)',
            );
          }
        }
      }
    });

    test('noise and paper wrap because the tile itself is the repeat unit',
        () {
      // Noise is a positional hash and paper a lattice indexed modulo its own
      // cell count, so both repeat exactly once per tile.
      for (final kind in [PatternKind.noise, PatternKind.paper]) {
        final spec = PatternSpec(
          id: 'n',
          name: kind.name,
          kind: kind,
          spacing: 8,
          density: 0.5,
        );
        final size = PatternRenderer.tileSizeFor(spec);
        // The paper lattice is 8px cells: the tile must hold a whole number of
        // them or the interpolated edges would not meet.
        expect(size % 8, 0, reason: '${kind.name} tile $size');
        final rgba = PatternRenderer.generate(spec);
        expect(rgba, hasLength(size * size * 4));
      }
    });

    test('decodes a tile image and builds a repeating shader', () async {
      final spec = PatternSpec.dotScreen(spacing: 8, radius: 3);
      final image = await PatternRenderer.ensure(spec);
      expect(image.width, PatternRenderer.tileSizeFor(spec));
      expect(image.height, PatternRenderer.tileSizeFor(spec));
      expect(PatternRenderer.imageFor(spec), isNotNull);
      expect(PatternRenderer.shaderFor(spec), isNotNull);
      // A rotated shader is still a shader (rotation is shader-level).
      expect(
        PatternRenderer.shaderFor(spec.copyWith(angle: 0.7), center: Offset.zero),
        isNotNull,
      );
    });
  });

  group('BrushPreset', () {
    test('round-trips through JSON', () {
      final preset = BrushPreset(
        id: 'x1',
        name: 'My brush',
        type: BrushType.bristle,
        size: 23.5,
        opacity: 0.8,
        hardness: 0.6,
        flow: 0.7,
        spacing: 0.12,
        mix: 0.3,
        tipTexture: BrushTexture.canvas,
      );
      final restored = BrushPreset.fromJson(preset.toJson());
      expect(restored.id, 'x1');
      expect(restored.name, 'My brush');
      expect(restored.type, BrushType.bristle);
      expect(restored.size, 23.5);
      expect(restored.opacity, 0.8);
      expect(restored.hardness, 0.6);
      expect(restored.flow, 0.7);
      expect(restored.spacing, 0.12);
      expect(restored.mix, 0.3);
      expect(restored.tipTexture, BrushTexture.canvas);
    });

    test('unknown brush types fall back to a usable default', () {
      final restored = BrushPreset.fromJson({'type': 'plasma', 'tip': '???'});
      expect(restored.type, BrushType.hardRound);
      expect(restored.tipTexture, BrushTexture.none);
    });

    test('stock presets cover every built-in brush with unique ids', () {
      final presets = BrushPreset.builtIns();
      final ids = presets.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(presets, hasLength(Brush.defaults().length + 4));
      for (final brush in Brush.defaults()) {
        expect(ids, contains('builtin-${brush.type.name}'));
      }
    });

    test('a pack round-trips and rejects foreign documents', () {
      final text = BrushPack.encode(BrushPreset.builtIns().take(2).toList());
      final decoded = BrushPack.decode(text);
      expect(decoded, hasLength(2));
      expect(decoded!.first.type, BrushPreset.builtIns().first.type);
      expect(BrushPack.decode('{"format":"something-else"}'), isNull);
      expect(BrushPack.decode(PatternPack.encode([])), isNull);
    });
  });

  group('ToolProvider presets', () {
    test('applying a preset copies its parameters and marks it active', () {
      final tp = ToolProvider();
      final preset = BrushPreset(
        id: 'p1',
        name: 'Wet',
        type: BrushType.oil,
        size: 30,
        opacity: 0.6,
        hardness: 0.4,
        flow: 0.5,
        spacing: 0.2,
        mix: 0.5,
        tipTexture: BrushTexture.hatch,
      );
      tp.applyPreset(preset);
      expect(tp.activePresetId, 'p1');
      expect(tp.brushType, BrushType.oil);
      expect(tp.brushSize, 30);
      expect(tp.brushOpacity, 0.6);
      expect(tp.currentBrush.hardness, 0.4);
      expect(tp.currentBrush.flow, 0.5);
      expect(tp.currentBrush.spacing, 0.2);
      expect(tp.currentBrush.mix, 0.5);
      expect(tp.currentBrush.tipTexture, BrushTexture.hatch);

      // Tweaking the brush by hand drops the preset association.
      tp.setBrushSize(31);
      expect(tp.activePresetId, isNull);
    });
  });

  group('pattern fills in documents', () {
    test('a fill drawable keeps its pattern through JSON', () {
      final drawable = Drawable(
        id: 'f1',
        points: const [Offset(1, 1)],
        fillSpans: const [0, 0, 4, 255],
        fillPattern: PatternSpec.dotScreen(spacing: 6, radius: 2),
      );
      final restored = Drawable.fromJson(drawable.toJson());
      expect(restored.fillSpans, isNotNull);
      expect(restored.fillPattern, isNotNull);
      expect(restored.fillPattern!.kind, PatternKind.dots);
      expect(restored.fillPattern!.spacing, 6);
      expect(restored.fillPattern!.thickness, 2);
    });

    test('copyWith keeps the pattern and can replace it', () {
      final drawable = Drawable(
        id: 'f2',
        points: const [Offset(0, 0)],
        fillSpans: const [0, 0, 2, 255],
        fillPattern: PatternSpec.dotScreen(),
      );
      expect(drawable.copyWith().fillPattern, isNotNull);
      final replaced = drawable.copyWith(
        fillPattern: PatternSpec(id: 'p2', name: 'Grid', kind: PatternKind.grid),
      );
      expect(replaced.fillPattern!.kind, PatternKind.grid);
    });
  });

  group('AppSettings libraries', () {
    test('starts from the stock pattern library', () {
      final settings = AppSettings();
      expect(settings.patterns, hasLength(PatternSpec.builtIns().length));
      expect(settings.activePattern, isNotNull);
      expect(settings.fillWithPattern, isFalse);
    });

    test('adds, renames and removes patterns', () {
      final settings = AppSettings();
      final before = settings.patterns.length;
      final pattern = PatternSpec(id: 'user-1', name: 'Mine');
      settings.addPattern(pattern);
      expect(settings.patterns, hasLength(before + 1));
      // Adding makes it the active pattern.
      expect(settings.activePattern!.id, 'user-1');

      settings.renamePattern('user-1', 'Renamed');
      expect(
        settings.patterns.firstWhere((p) => p.id == 'user-1').name,
        'Renamed',
      );

      settings.removePattern('user-1');
      expect(settings.patterns, hasLength(before));
      expect(settings.activePattern!.id, isNot('user-1'));
    });

    test('re-importing a pattern replaces it instead of duplicating', () {
      final settings = AppSettings();
      settings.addPattern(PatternSpec(id: 'dup', name: 'A', spacing: 4));
      final count = settings.patterns.length;
      settings.addPatterns([PatternSpec(id: 'dup', name: 'B', spacing: 9)]);
      expect(settings.patterns, hasLength(count));
      expect(
        settings.patterns.firstWhere((p) => p.id == 'dup').spacing,
        9,
      );
    });

    test('manages user brush presets alongside the built-ins', () {
      final settings = AppSettings();
      final builtInCount = BrushPreset.builtIns().length;
      expect(settings.allBrushPresets, hasLength(builtInCount));

      settings.addBrushPreset(BrushPreset(id: 'u1', name: 'Mine', size: 12));
      expect(settings.allBrushPresets, hasLength(builtInCount + 1));
      expect(settings.brushPresets, hasLength(1));

      settings.renameBrushPreset('u1', 'Renamed');
      expect(settings.brushPresets.single.name, 'Renamed');

      settings.removeBrushPreset('u1');
      expect(settings.brushPresets, isEmpty);
      expect(settings.allBrushPresets, hasLength(builtInCount));
    });

    test('pattern fill mode is part of the settings', () {
      final settings = AppSettings();
      settings.setFillWithPattern(true);
      expect(settings.fillWithPattern, isTrue);
      settings.setActivePattern('builtin-grid');
      expect(settings.activePattern!.id, 'builtin-grid');
    });
  });

  group('pattern thumbnails', () {
    testWidgets('a thumb paints before and after its tile decodes',
        (tester) async {
      final spec = PatternSpec.dotScreen(spacing: 5, radius: 1.5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PatternThumb(spec: spec, size: 40)),
          ),
        ),
      );
      // First frame: the tile is not decoded yet, the painter falls back to
      // the ink colour and must not throw.
      expect(tester.takeException(), isNull);
      // Let the decode land, then repaint with the real pattern.
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.byType(PatternThumb), findsOneWidget);
    });
  });
}
