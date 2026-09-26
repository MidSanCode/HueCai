import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/services/assist_ruler.dart';

void main() {
  group('snapToLine (parallel ruler)', () {
    test('projects onto a horizontal line', () {
      final q = AssistRuler.snapToLine(const Offset(5, 8), Offset.zero, 0);
      expect(q.dy, closeTo(0, 1e-9));
      expect(q.dx, closeTo(5, 1e-9));
    });

    test('projects onto a 45-degree line', () {
      final q = AssistRuler.snapToLine(
          const Offset(2, 0), Offset.zero, math.pi / 4);
      // (2,0) projects to (1,1) on y=x.
      expect(q.dx, closeTo(1, 1e-9));
      expect(q.dy, closeTo(1, 1e-9));
    });

    test('points already on the line stay put', () {
      final q = AssistRuler.snapToLine(
          const Offset(3, 4), const Offset(3, 4), 1.234);
      expect((q - const Offset(3, 4)).distance, lessThan(1e-9));
    });
  });

  group('snapToEllipse', () {
    test('snaps to the perimeter along the radial direction', () {
      final q = AssistRuler.snapToEllipse(
          const Offset(50, 0), Offset.zero, 20, 10);
      expect(q.dx, closeTo(20, 1e-6));
      expect(q.dy, closeTo(0, 1e-6));
    });

    test('interior points land on the nearest perimeter point', () {
      final q = AssistRuler.snapToEllipse(
          const Offset(0, 5), Offset.zero, 20, 10);
      expect(q.dx.abs(), lessThan(1e-6));
      expect(q.dy, closeTo(10, 1e-6));
    });

    test('center input does not crash', () {
      final q = AssistRuler.snapToEllipse(Offset.zero, Offset.zero, 20, 10);
      expect(q, const Offset(20, 0));
    });
  });

  group('snapToVanishingRay', () {
    test('clamps the stroke onto the ray from the VP', () {
      const vp = Offset(0, 0);
      const start = Offset(10, 0); // ray along +x
      final q = AssistRuler.snapToVanishingRay(
          const Offset(15, 7), vp, start);
      expect(q.dy, closeTo(0, 1e-9));
      expect(q.dx, closeTo(15, 1e-9));
    });
  });

  group('spline snapping', () {
    test('spline through straight control points behaves like a line', () {
      final ruler = AssistRuler(
        id: 's',
        type: RulerType.spline,
        points: [Offset(0, 0), Offset(50, 0), Offset(100, 0)],
      );
      final q = ruler.snapPoint(const Offset(50, 12));
      expect(q.dy.abs(), lessThan(2));
      expect(q.dx, closeTo(50, 5));
    });

    test('spline passes through its control points', () {
      final ruler = AssistRuler(
        id: 's',
        type: RulerType.spline,
        points: [Offset(0, 0), Offset(50, 50), Offset(100, 0)],
      );
      final q = ruler.snapPoint(const Offset(50, 50));
      expect((q - const Offset(50, 50)).distance, lessThan(6));
    });

    test('snapToPolyline picks the nearest segment point', () {
      final q = AssistRuler.snapToPolyline(
          const Offset(5, 3), [Offset.zero, const Offset(10, 0)]);
      expect(q, const Offset(5, 0));
    });
  });

  group('handle editing', () {
    test('parallel ruler center and angle handles', () {
      final r = AssistRuler(id: 'p', type: RulerType.parallel);
      expect(r.handles, hasLength(2));
      r.moveHandle(0, const Offset(10, 20));
      expect(r.center, const Offset(10, 20));
      r.moveHandle(1, const Offset(10, 80)); // straight up from center
      expect(r.angle, closeTo(math.pi / 2, 1e-9));
    });

    test('ellipse radii handles', () {
      final r = AssistRuler(
          id: 'e', type: RulerType.ellipse, center: Offset.zero);
      r.moveHandle(1, const Offset(30, 0));
      r.moveHandle(2, const Offset(0, 15));
      expect(r.radiusX, 30);
      expect(r.radiusY, 15);
    });
  });
}
