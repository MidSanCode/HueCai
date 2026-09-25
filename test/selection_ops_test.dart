import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/selection_data.dart';

SelectionMask maskWithRect(int w, int h, Rect rect) {
  final m = SelectionMask(w, h);
  m.fillRect(rect, true);
  return m;
}

int countSelected(SelectionMask m) {
  var n = 0;
  for (final v in m.data) {
    if (v != 0) n++;
  }
  return n;
}

void main() {
  group('SelectionMask boolean ops', () {
    test('intersect keeps only the overlap', () {
      final a = maskWithRect(20, 20, const Rect.fromLTWH(0, 0, 10, 10));
      final b = maskWithRect(20, 20, const Rect.fromLTWH(5, 5, 10, 10));
      a.intersect(b);
      // Overlap is the 5x5 corner (5..9 in both axes).
      expect(countSelected(a), 25);
      expect(a.data[5 * 20 + 5], 255);
      expect(a.data[0], 0);
      expect(a.data[9 * 20 + 14], 0); // b-only area
    });

    test('intersect with disjoint region empties the mask', () {
      final a = maskWithRect(20, 20, const Rect.fromLTWH(0, 0, 5, 5));
      final b = maskWithRect(20, 20, const Rect.fromLTWH(10, 10, 5, 5));
      a.intersect(b);
      expect(a.isEmpty, isTrue);
    });

    test('add union and subtract difference still work', () {
      final a = maskWithRect(20, 20, const Rect.fromLTWH(0, 0, 10, 10));
      final b = maskWithRect(20, 20, const Rect.fromLTWH(5, 0, 10, 10));
      a.applyMask(b, true);
      expect(countSelected(a), 150); // 15 x 10
      a.applyMask(b, false);
      expect(countSelected(a), 50); // back to left half only
    });
  });

  group('SelectionMask feather', () {
    test('softens the edge to partial alpha', () {
      final m = maskWithRect(40, 40, const Rect.fromLTWH(10, 10, 20, 20));
      m.feather(4);
      // Center stays fully opaque.
      expect(m.data[20 * 40 + 20], 255);
      // Edge band has intermediate values.
      final edge = m.data[10 * 40 + 20]; // top edge, middle
      expect(edge, greaterThan(0));
      expect(edge, lessThan(255));
      // Just outside the feather band: still zero.
      expect(m.data[2 * 40 + 20], 0);
    });

    test('feather is monotonic across the band', () {
      final m = maskWithRect(40, 40, const Rect.fromLTWH(10, 10, 20, 20));
      m.feather(4);
      var prev = -1;
      // Walk from outside (row 4) to inside (row 12) at column 20.
      for (var y = 4; y <= 12; y++) {
        final v = m.data[y * 40 + 20];
        expect(v, greaterThanOrEqualTo(prev));
        prev = v;
      }
    });

    test('feather on empty mask is a no-op', () {
      final m = SelectionMask(10, 10);
      m.feather(4);
      expect(m.isEmpty, isTrue);
    });
  });

  group('SelectionMask grow/shrink', () {
    test('grow expands the bounds symmetrically', () {
      final m = maskWithRect(30, 30, const Rect.fromLTWH(10, 10, 10, 10));
      final before = m.bounds;
      m.grow(3);
      final after = m.bounds;
      expect(after.width, greaterThan(before.width));
      expect(after.left, lessThan(before.left));
    });

    test('shrink reduces the bounds', () {
      final m = maskWithRect(30, 30, const Rect.fromLTWH(10, 10, 10, 10));
      final before = m.bounds;
      m.grow(-3);
      final after = m.bounds;
      expect(after.width, lessThan(before.width));
    });

    test('shrinking past zero empties the mask', () {
      final m = maskWithRect(20, 20, const Rect.fromLTWH(8, 8, 4, 4));
      m.grow(-10);
      expect(m.isEmpty, isTrue);
    });
  });
}
