import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:hue_cai/providers/app_settings.dart';
import 'package:hue_cai/providers/canvas_provider.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/providers/tool_provider.dart';
import 'package:hue_cai/services/view_transform.dart';
import 'package:hue_cai/widgets/canvas/brush_hud.dart';
import 'package:hue_cai/widgets/canvas/snapshot_compare_overlay.dart';
import 'package:hue_cai/widgets/tools/touch_panel.dart';

const _canvasSize = Size(1000, 800);
const _areaSize = Size(500, 400);

ViewTransform _transform({
  Offset offset = Offset.zero,
  double scale = 1.0,
  double rotation = 0.0,
}) =>
    ViewTransform(
      offset: offset,
      scale: scale,
      rotation: rotation,
      canvasSize: _canvasSize,
      areaSize: _areaSize,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViewTransform', () {
    test('identity: canvas centre maps to the screen centre', () {
      final t = _transform();
      final screen = t.toScreen(t.canvasCenter);
      expect(screen.dx, closeTo(_areaSize.width / 2, 0.001));
      expect(screen.dy, closeTo(_areaSize.height / 2, 0.001));
    });

    test('toCanvas inverts toScreen for zoom and pan', () {
      final t = _transform(offset: const Offset(37, -21), scale: 1.7);
      for (final p in [
        Offset.zero,
        _canvasSize.center(Offset.zero),
        const Offset(120, 640),
        const Offset(-30, -10),
      ]) {
        final back = t.toCanvas(t.toScreen(p));
        expect(back.dx, closeTo(p.dx, 0.0001), reason: 'dx for $p');
        expect(back.dy, closeTo(p.dy, 0.0001), reason: 'dy for $p');
      }
    });

    test('offsetToCenter puts the requested point under the viewport centre',
        () {
      final t = _transform(scale: 2.0);
      final target = const Offset(800, 300);
      final offset = t.offsetToCenter(target);
      final moved = _transform(offset: offset, scale: 2.0);
      final screen = moved.toScreen(target);
      expect(screen.dx, closeTo(_areaSize.width / 2, 0.001));
      expect(screen.dy, closeTo(_areaSize.height / 2, 0.001));
    });

    test('visibleCanvasRect bounds the viewport at zoom 1', () {
      final t = _transform();
      final visible = t.visibleCanvasRect();
      expect(visible.width, closeTo(_areaSize.width, 0.001));
      expect(visible.height, closeTo(_areaSize.height, 0.001));
      // The viewport starts centred on the canvas.
      expect(visible.center.dx, closeTo(_canvasSize.width / 2, 0.001));
      expect(visible.center.dy, closeTo(_canvasSize.height / 2, 0.001));
    });

    test('zoomed out view shows more of the canvas', () {
      final zoomedIn = _transform(scale: 4.0).visibleCanvasRect();
      final zoomedOut = _transform(scale: 0.5).visibleCanvasRect();
      expect(zoomedOut.width, greaterThan(zoomedIn.width));
      expect(zoomedOut.height, greaterThan(zoomedIn.height));
    });

    test('matrix4 agrees with toScreen', () {
      final t = _transform(
          offset: const Offset(13, -8), scale: 1.3, rotation: 0.4);
      final matrix = Matrix4.fromFloat64List(
        Float64List.fromList(t.matrix4()),
      );
      for (final p in [
        Offset.zero,
        _canvasSize.center(Offset.zero),
        const Offset(900, 100),
      ]) {
        final expected = t.toScreen(p);
        final actual = MatrixUtils.transformPoint(matrix, p);
        expect(actual.dx, closeTo(expected.dx, 0.001));
        expect(actual.dy, closeTo(expected.dy, 0.001));
      }
    });
  });

  group('OverviewLayout', () {
    test('fit keeps the aspect ratio and centres the canvas', () {
      final layout = OverviewLayout.fit(
        mapSize: const Size(150, 100),
        canvasSize: _canvasSize,
      );
      expect(layout.scale, closeTo(94 / 800, 0.001)); // height-limited
      expect(
        layout.mapRect.width,
        closeTo(1000 * (94 / 800), 0.001),
      );
      expect(layout.mapRect.top, closeTo(3, 0.001)); // padding
    });

    test('toCanvas inverts toMap', () {
      final layout = OverviewLayout.fit(
        mapSize: const Size(150, 100),
        canvasSize: _canvasSize,
      );
      final p = const Offset(300, 420);
      final back = layout.toCanvas(layout.toMap(p));
      expect(back.dx, closeTo(p.dx, 0.001));
      expect(back.dy, closeTo(p.dy, 0.001));
    });

    test('clampToCanvas keeps the jump target on the artwork', () {
      final layout = OverviewLayout.fit(
        mapSize: const Size(150, 100),
        canvasSize: _canvasSize,
      );
      final clamped = layout.clampToCanvas(const Offset(-50, 5000));
      expect(clamped.dx, 0);
      expect(clamped.dy, _canvasSize.height);
    });
  });

  group('CanvasProvider view helpers', () {
    test('centerOnCanvasPoint puts the point at the viewport centre', () {
      final cp = CanvasProvider()..setViewportSize(_areaSize);
      final target = const Offset(700, 250);
      cp.centerOnCanvasPoint(target, _canvasSize);
      final t = ViewTransform(
        offset: cp.offset,
        scale: cp.scale,
        rotation: cp.rotation,
        canvasSize: _canvasSize,
        areaSize: _areaSize,
      );
      final screen = t.toScreen(target);
      expect(screen.dx, closeTo(_areaSize.width / 2, 0.001));
      expect(screen.dy, closeTo(_areaSize.height / 2, 0.001));
    });

    test('zoomTo keeps the viewport centre anchored', () {
      final cp = CanvasProvider()..setViewportSize(_areaSize);
      final before = ViewTransform(
        offset: cp.offset,
        scale: cp.scale,
        rotation: 0,
        canvasSize: _canvasSize,
        areaSize: _areaSize,
      ).visibleCanvasRect();
      cp.zoomTo(2.0);
      final after = ViewTransform(
        offset: cp.offset,
        scale: cp.scale,
        rotation: 0,
        canvasSize: _canvasSize,
        areaSize: _areaSize,
      ).visibleCanvasRect();
      expect(cp.scale, 2.0);
      expect(after.center.dx, closeTo(before.center.dx, 0.001));
      expect(after.center.dy, closeTo(before.center.dy, 0.001));
      expect(after.width, closeTo(before.width / 2, 0.001));
    });

    test('zoomTo clamps to the supported range', () {
      final cp = CanvasProvider();
      cp.zoomTo(500);
      expect(cp.scale, 10.0);
      cp.zoomTo(0.0001);
      expect(cp.scale, 0.1);
    });
  });

  group('interface toggles', () {
    test('default to HUD and overview on, touch panel off', () {
      final as = AppSettings();
      expect(as.brushHudEnabled, isTrue);
      expect(as.overviewEnabled, isTrue);
      expect(as.touchPanelEnabled, isFalse);
      as.setTouchPanelEnabled(true);
      expect(as.touchPanelEnabled, isTrue);
      as.setBrushHudEnabled(false);
      expect(as.brushHudEnabled, isFalse);
      as.setOverviewEnabled(false);
      expect(as.overviewEnabled, isFalse);
    });
  });

  group('snapshot comparison state', () {
    test('inactive by default and inert without a project', () async {
      final pp = ProjectProvider();
      expect(pp.comparisonActive, isFalse);
      expect(pp.comparisonSnapshot, isNull);
      await pp.startComparison();
      // No project: nothing to snapshot, so the overlay stays closed.
      expect(pp.comparisonActive, isFalse);
    });

    test('stopComparison just closes the overlay', () async {
      final pp = ProjectProvider();
      pp.stopComparison();
      expect(pp.comparisonActive, isFalse);
    });
  });

  group('CompareMode', () {
    test('has exactly the two documented modes', () {
      expect(CompareMode.values, hasLength(2));
      expect(CompareMode.values.map((m) => m.name).toSet(),
          {'split', 'difference'});
    });
  });

  group('overlay widgets', () {
    testWidgets('BrushHud renders the ring and the readout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                BrushHud(
                  position: const Offset(120, 90),
                  brushSize: 24,
                  opacity: 0.75,
                  viewScale: 1.0,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('24.0 px · 75%'), findsOneWidget);
      expect(find.byType(BrushHud), findsOneWidget);
    });

    testWidgets('TouchPanel renders tools, steppers and transport',
        (tester) async {
      final tp = ToolProvider();
      final as = AppSettings();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: tp),
            ChangeNotifierProvider.value(value: as),
            ChangeNotifierProvider(create: (_) => ProjectProvider()),
            ChangeNotifierProvider(create: (_) => CanvasProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [TouchPanel()],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Two steppers show size and opacity readouts.
      expect(find.text(tp.brushSize.round().toString()), findsOneWidget);
      expect(
        find.text('${(tp.brushOpacity * 100).round()}%'),
        findsOneWidget,
      );
      // The panel can be dismissed.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(as.touchPanelEnabled, isFalse);
    });
  });
}
