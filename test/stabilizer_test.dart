import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/services/stroke_stabilizer.dart';

void main() {
  group('StringPullStabilizer', () {
    test('brush stays put while the pointer is within the string', () {
      final s = StringPullStabilizer(length: 10);
      s.startAt(const Offset(0, 0));
      expect(s.feed(const Offset(5, 0)), const Offset(0, 0));
      expect(s.feed(const Offset(9, 0)), const Offset(0, 0));
    });

    test('brush trails exactly at string length', () {
      final s = StringPullStabilizer(length: 10);
      s.startAt(const Offset(0, 0));
      expect(s.feed(const Offset(15, 0)), const Offset(5, 0));
      expect(s.feed(const Offset(30, 0)), const Offset(20, 0));
    });

    test('follows direction changes without overshooting', () {
      final s = StringPullStabilizer(length: 10);
      s.startAt(const Offset(0, 0));
      s.feed(const Offset(20, 0)); // anchor at 10,0
      final back = s.feed(const Offset(0, 0)); // pointer turns around
      // Anchor moves toward the pointer only once beyond the string length:
      // |0 - 10| == 10, exactly at the limit, so the brush does not move.
      expect(back, const Offset(10, 0));
    });

    test('reset re-anchors on the next feed', () {
      final s = StringPullStabilizer(length: 10);
      s.startAt(const Offset(0, 0));
      s.feed(const Offset(30, 0));
      s.reset();
      expect(s.anchor, isNull);
      expect(s.feed(const Offset(50, 50)), const Offset(50, 50));
    });
  });

  group('PressureCurve', () {
    test('identity curve returns the input unchanged', () {
      final c = PressureCurve();
      expect(c.isIdentity, isTrue);
      expect(c.map(0.25), closeTo(0.25, 1e-9));
      expect(c.map(0.8), closeTo(0.8, 1e-9));
    });

    test('custom curve remaps mid pressure', () {
      // Push midtones up: raw 0.5 → ~0.75.
      final c = PressureCurve(points: [(x: 0, y: 0), (x: 128, y: 190), (x: 255, y: 255)]);
      expect(c.isIdentity, isFalse);
      expect(c.map(0.5), greaterThan(0.65));
      expect(c.map(0.5), lessThan(0.85));
    });

    test('endpoints are clamped into range', () {
      final c = PressureCurve(points: [(x: 0, y: 50), (x: 255, y: 200)]);
      expect(c.map(0.0), closeTo(50 / 255, 0.02));
      expect(c.map(1.0), closeTo(200 / 255, 0.02));
    });

    test('JSON round-trip preserves points', () {
      final c = PressureCurve(points: [(x: 0, y: 0), (x: 100, y: 200), (x: 255, y: 255)]);
      final restored = PressureCurve.fromJson(c.toJson());
      expect(restored.points, hasLength(3));
      expect(restored.points[1].x, 100);
      expect(restored.points[1].y, 200);
    });

    test('null JSON yields the identity curve', () {
      expect(PressureCurve.fromJson(null).isIdentity, isTrue);
    });
  });
}
