import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum SelectionMethod { lasso, rect, ellipse, magicWand, brush }

enum SelectionPhase { none, selecting, selected, editing }

enum TransformMode { scale, warp }

class SelectionMask {
  final int width;
  final int height;
  final Uint8List _data;

  SelectionMask(this.width, this.height) : _data = Uint8List(width * height);

  Uint8List get data => _data;

  bool get isEmpty {
    for (int i = 0; i < _data.length; i++) {
      if (_data[i] != 0) return false;
    }
    return true;
  }

  void clear() => _data.fillRange(0, _data.length, 0);
  void fillAll() => _data.fillRange(0, _data.length, 255);

  void fillRect(Rect rect, bool set) {
    final v = set ? 255 : 0;
    final x0 = rect.left.floor().clamp(0, width - 1);
    final y0 = rect.top.floor().clamp(0, height - 1);
    final x1 = rect.right.ceil().clamp(0, width);
    final y1 = rect.bottom.ceil().clamp(0, height);
    for (int y = y0; y < y1; y++) {
      final row = y * width;
      for (int x = x0; x < x1; x++) {
        _data[row + x] = v;
      }
    }
  }

  void fillEllipse(Rect rect, bool set) {
    final v = set ? 255 : 0;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = rect.width / 2;
    final ry = rect.height / 2;
    if (rx <= 0 || ry <= 0) return;
    final x0 = rect.left.floor().clamp(0, width - 1);
    final y0 = rect.top.floor().clamp(0, height - 1);
    final x1 = rect.right.ceil().clamp(0, width);
    final y1 = rect.bottom.ceil().clamp(0, height);
    for (int y = y0; y < y1; y++) {
      final row = y * width;
      final dy = (y - cy) / ry;
      for (int x = x0; x < x1; x++) {
        final dx = (x - cx) / rx;
        if (dx * dx + dy * dy <= 1) _data[row + x] = v;
      }
    }
  }

  void fillPolygon(List<Offset> polygon, bool set) {
    if (polygon.length < 3) return;
    final v = set ? 255 : 0;
    final y0 = polygon.map((p) => p.dy).reduce((a, b) => a < b ? a : b).floor().clamp(0, height - 1);
    final y1 = polygon.map((p) => p.dy).reduce((a, b) => a > b ? a : b).ceil().clamp(0, height);
    for (int y = y0; y < y1; y++) {
      final intersections = <double>[];
      for (int i = 0; i < polygon.length; i++) {
        final a = polygon[i];
        final b = polygon[(i + 1) % polygon.length];
        if ((a.dy <= y && b.dy > y) || (b.dy <= y && a.dy > y)) {
          final t = (y - a.dy) / (b.dy - a.dy);
          intersections.add(a.dx + t * (b.dx - a.dx));
        }
      }
      intersections.sort();
        for (int i = 0; i < intersections.length - 1; i += 2) {
          final x0 = intersections[i].floor().clamp(0, width - 1);
          final x1 = intersections[i + 1].ceil().clamp(0, width);
          final row = y * width;
          for (int x = x0; x < x1; x++) { _data[row + x] = v; }
        }
    }
  }

  void floodFill(Offset point, Uint8List canvasRgba, int tolerance, bool set) {
    final v = set ? 255 : 0;
    final px = point.dx.round().clamp(0, width - 1);
    final py = point.dy.round().clamp(0, height - 1);
    final targetIdx = py * width + px;
    if (_data[targetIdx] == v) return;
    final targetR = canvasRgba[targetIdx * 4];
    final targetG = canvasRgba[targetIdx * 4 + 1];
    final targetB = canvasRgba[targetIdx * 4 + 2];
    final queue = <int>[targetIdx];
    _data[targetIdx] = v;
    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      for (final n in [idx - 1, idx + 1, idx - width, idx + width]) {
        if (n < 0 || n >= _data.length) continue;
        if (_data[n] == v) continue;
        final nr = canvasRgba[n * 4];
        final ng = canvasRgba[n * 4 + 1];
        final nb = canvasRgba[n * 4 + 2];
        if ((nr - targetR).abs() + (ng - targetG).abs() + (nb - targetB).abs() <= tolerance) {
          _data[n] = v;
          queue.add(n);
        }
      }
    }
  }

  /// Extracts the mask as flat horizontal runs [y, x0, x1, alpha, …]
  /// (x1 inclusive, alpha 0-255). Compact and directly renderable as rects —
  /// used by the paint-bucket fill drawable. With [antiAlias] the boundary
  /// gets feathered partial-alpha runs (PS-style soft selection edge).
  List<int> extractSpans({bool antiAlias = false}) {
    final alphaMap = antiAlias ? buildAlphaMap() : null;
    final spans = <int>[];
    for (int y = 0; y < height; y++) {
      final row = y * width;
      int x = 0;
      while (x < width) {
        final v = _data[row + x];
        if (v != 0) {
          final x0 = x;
          final a0 = alphaMap != null ? alphaMap[row + x] : 255;
          x++;
          while (x < width && _data[row + x] != 0) {
            final a = alphaMap != null ? alphaMap[row + x] : 255;
            if (a != a0) break;
            x++;
          }
          spans..add(y)..add(x0)..add(x - 1)..add(a0);
        } else {
          x++;
        }
      }
    }
    return spans;
  }

  /// Grows the region by [px] pixels (positive) or shrinks it (negative),
  /// morphologically, via a chamfer distance transform.
  void grow(int px) {
    if (px == 0) return;
    if (px > 0) {
      final dist = _distanceToNearest(target: true);
      for (int i = 0; i < _data.length; i++) {
        if (_data[i] == 0 && dist[i] <= px) _data[i] = 255;
      }
    } else {
      final px2 = -px;
      final dist = _distanceToNearest(target: false);
      for (int i = 0; i < _data.length; i++) {
        if (_data[i] != 0 && dist[i] <= px2) _data[i] = 0;
      }
    }
  }

  /// Per-pixel edge alpha for anti-aliased rendering: interior pixels get
  /// full alpha, the boundary ring is feathered (~50-70%) so diagonal
  /// stair-steps become a smooth transition.
  Uint8List buildAlphaMap() {
    final dist = _distanceToNearest(target: false);
    final out = Uint8List(_data.length);
    for (int i = 0; i < _data.length; i++) {
      if (_data[i] == 0) {
        out[i] = 0;
      } else {
        out[i] = (dist[i] * 127.5).round().clamp(0, 255);
      }
    }
    return out;
  }

  /// Chamfer 3-4 distance transform: distance (in pixels) from every pixel
  /// to the nearest pixel whose set-state equals [target].
  Float32List _distanceToNearest({required bool target}) {
    final inf = 1 << 24;
    final dist = Int32List(_data.length);
    for (int i = 0; i < _data.length; i++) {
      final isTarget = (_data[i] != 0) == target;
      dist[i] = isTarget ? 0 : inf;
    }
    // Forward pass (top-left → bottom-right).
    for (int y = 0; y < height; y++) {
      final row = y * width;
      for (int x = 0; x < width; x++) {
        final i = row + x;
        int d = dist[i];
        if (x > 0 && dist[i - 1] + 3 < d) d = dist[i - 1] + 3;
        if (y > 0) {
          final up = i - width;
          if (dist[up] + 3 < d) d = dist[up] + 3;
          if (x > 0 && dist[up - 1] + 4 < d) d = dist[up - 1] + 4;
          if (x < width - 1 && dist[up + 1] + 4 < d) d = dist[up + 1] + 4;
        }
        dist[i] = d;
      }
    }
    // Backward pass (bottom-right → top-left).
    for (int y = height - 1; y >= 0; y--) {
      final row = y * width;
      for (int x = width - 1; x >= 0; x--) {
        final i = row + x;
        int d = dist[i];
        if (x < width - 1 && dist[i + 1] + 3 < d) d = dist[i + 1] + 3;
        if (y < height - 1) {
          final dn = i + width;
          if (dist[dn] + 3 < d) d = dist[dn] + 3;
          if (x < width - 1 && dist[dn + 1] + 4 < d) d = dist[dn + 1] + 4;
          if (x > 0 && dist[dn - 1] + 4 < d) d = dist[dn - 1] + 4;
        }
        dist[i] = d;
      }
    }
    // 3 units ≈ 1 px (4 units ≈ √2 px).
    final out = Float32List(_data.length);
    for (int i = 0; i < dist.length; i++) {
      out[i] = dist[i] / 3.0;
    }
    return out;
  }

  void fillCircle(Offset center, double radius, bool set) {    final v = set ? 255 : 0;
    final r2 = radius * radius;
    final x0 = (center.dx - radius).floor().clamp(0, width - 1);
    final y0 = (center.dy - radius).floor().clamp(0, height - 1);
    final x1 = (center.dx + radius).ceil().clamp(0, width);
    final y1 = (center.dy + radius).ceil().clamp(0, height);
    for (int y = y0; y < y1; y++) {
      final row = y * width;
      final dy = y - center.dy;
      for (int x = x0; x < x1; x++) {
        final dx = x - center.dx;
        if (dx * dx + dy * dy <= r2) _data[row + x] = v;
      }
    }
  }

  void applyMask(SelectionMask other, bool add) {
    final otherData = other._data;
    for (int i = 0; i < _data.length; i++) {
      if (add) {
        if (otherData[i] != 0) _data[i] = 255;
      } else {
        if (otherData[i] != 0) _data[i] = 0;
      }
    }
  }

  void invert() {
    for (int i = 0; i < _data.length; i++) {
      _data[i] = _data[i] == 0 ? 255 : 0;
    }
  }

  Rect get bounds {
    int minX = width, minY = height, maxX = 0, maxY = 0;
    bool found = false;
    for (int y = 0; y < height; y++) {
      final row = y * width;
      for (int x = 0; x < width; x++) {
        if (_data[row + x] != 0) {
          found = true;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (!found) return Rect.zero;
    // Exclusive bounds: max is one past the last selected pixel so clip
    // extraction keeps the full edge (thin strokes at boundaries included).
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble().clamp(0, width).toDouble(),
      (maxY + 1).toDouble().clamp(0, height).toDouble(),
    );
  }

  /// Traces the boundary of the mask and returns closed loops of lattice
  /// points (pixel corners), one loop per contiguous region outline.
  List<List<Offset>> contours() {
    final w1 = width + 1;
    // Directed boundary edges keyed by start lattice index.
    final edges = <int, List<int>>{};
    void addEdge(int x0, int y0, int x1, int y1) {
      edges.putIfAbsent(y0 * w1 + x0, () => <int>[]).add(y1 * w1 + x1);
    }

    bool m(int x, int y) =>
        x >= 0 && y >= 0 && x < width && y < height && _data[y * width + x] != 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!m(x, y)) continue;
        if (!m(x, y - 1)) addEdge(x, y, x + 1, y);
        if (!m(x + 1, y)) addEdge(x + 1, y, x + 1, y + 1);
        if (!m(x, y + 1)) addEdge(x + 1, y + 1, x, y + 1);
        if (!m(x - 1, y)) addEdge(x, y + 1, x, y);
      }
    }

    final loops = <List<Offset>>[];
    while (edges.isNotEmpty) {
      int startKey = edges.keys.first;
      int cur = startKey;
      final loop = <Offset>[];
      int guard = 0;
      final maxSteps = 4 * width * height;
      while (guard++ < maxSteps) {
        final ends = edges[cur];
        if (ends == null || ends.isEmpty) break;
        final next = ends.removeLast();
        if (ends.isEmpty) edges.remove(cur);
        loop.add(Offset((cur % w1).toDouble(), (cur ~/ w1).toDouble()));
        cur = next;
        if (cur == startKey) break;
      }
      if (loop.length >= 3) loops.add(loop);
    }
    return loops;
  }

  Future<ui.Image> toRgbaImage({int alphaDivisor = 2}) async {
    final pixels = Uint8List(width * height * 4);
    for (int i = 0; i < _data.length; i++) {
      final v = _data[i];
      pixels[i * 4] = 0;
      pixels[i * 4 + 1] = 128;
      pixels[i * 4 + 2] = 255;
      pixels[i * 4 + 3] = v ~/ alphaDivisor;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }
}
