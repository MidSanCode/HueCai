import 'dart:math';
import 'dart:ui';

/// Pure canvas ↔ screen mapping, shared by the overview navigator and the
/// snapshot comparison overlay.
///
/// The canvas widget draws with
/// `translate(area/2 + offset) → rotate(rotation) → scale(scale) → translate(-canvas/2)`,
/// so a canvas point `p` lands on screen at
/// `area/2 + offset + R(rotation) · scale · (p - canvas/2)`.
class ViewTransform {
  final Offset offset;
  final double scale;
  final double rotation;
  final Size canvasSize;
  final Size areaSize;

  const ViewTransform({
    required this.offset,
    required this.scale,
    required this.rotation,
    required this.canvasSize,
    required this.areaSize,
  });

  Offset get canvasCenter =>
      Offset(canvasSize.width / 2, canvasSize.height / 2);

  Offset get areaCenter => Offset(areaSize.width / 2, areaSize.height / 2);

  /// The same mapping as [toScreen], as a column-major matrix for widgets
  /// that need a `Transform` (the snapshot comparison overlay draws the
  /// reference flatten through exactly this matrix).
  ///
  /// Composition: translate(area/2 + offset) · rotateZ · scale · translate(-canvas/2)
  List<double> matrix4() {
    final c = cos(rotation);
    final s = sin(rotation);
    final k = scale;
    final tx = areaCenter.dx +
        offset.dx -
        (c * canvasCenter.dx - s * canvasCenter.dy) * k;
    final ty = areaCenter.dy +
        offset.dy -
        (s * canvasCenter.dx + c * canvasCenter.dy) * k;
    return <double>[
      c * k, s * k, 0, 0, //
      -s * k, c * k, 0, 0, //
      0, 0, k, 0, //
      tx, ty, 0, 1, //
    ];
  }

  /// Canvas point → screen point.
  Offset toScreen(Offset point) {
    final v = (point - canvasCenter) * scale;
    final cosV = cos(rotation);
    final sinV = sin(rotation);
    return Offset(
      areaCenter.dx + offset.dx + v.dx * cosV - v.dy * sinV,
      areaCenter.dy + offset.dy + v.dx * sinV + v.dy * cosV,
    );
  }

  /// Screen point → canvas point.
  Offset toCanvas(Offset screen) {
    final x = screen.dx - offset.dx - areaCenter.dx;
    final y = screen.dy - offset.dy - areaCenter.dy;
    final cosV = cos(rotation);
    final sinV = sin(rotation);
    return Offset(
      (x * cosV + y * sinV) / scale + canvasCenter.dx,
      (-x * sinV + y * cosV) / scale + canvasCenter.dy,
    );
  }

  /// The part of the canvas currently visible, as an axis-aligned bounding
  /// box in canvas coordinates (exact when there is no rotation).
  Rect visibleCanvasRect() {
    final corners = [
      toCanvas(Offset.zero),
      toCanvas(Offset(areaSize.width, 0)),
      toCanvas(Offset(0, areaSize.height)),
      toCanvas(Offset(areaSize.width, areaSize.height)),
    ];
    var left = corners.first.dx;
    var top = corners.first.dy;
    var right = left;
    var bottom = top;
    for (final c in corners) {
      left = min(left, c.dx);
      top = min(top, c.dy);
      right = max(right, c.dx);
      bottom = max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Offset that puts [canvasPoint] at the centre of the viewport, keeping
  /// the current scale and rotation.
  Offset offsetToCenter(Offset canvasPoint) {
    final v = (canvasPoint - canvasCenter) * scale;
    final cosV = cos(rotation);
    final sinV = sin(rotation);
    return Offset(
      -(v.dx * cosV - v.dy * sinV),
      -(v.dx * sinV + v.dy * cosV),
    );
  }

  /// The canvas rectangle in screen coordinates (its bounding box).
  Rect canvasScreenRect() {
    final corners = [
      toScreen(Offset.zero),
      toScreen(Offset(canvasSize.width, 0)),
      toScreen(Offset(0, canvasSize.height)),
      toScreen(Offset(canvasSize.width, canvasSize.height)),
    ];
    var left = corners.first.dx;
    var top = corners.first.dy;
    var right = left;
    var bottom = top;
    for (final c in corners) {
      left = min(left, c.dx);
      top = min(top, c.dy);
      right = max(right, c.dx);
      bottom = max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// Maps the canvas rectangle into a small overview widget.
class OverviewLayout {
  /// Where the whole canvas sits inside the overview widget.
  final Rect mapRect;

  /// Canvas pixels → overview pixels.
  final double scale;
  final Size canvasSize;

  const OverviewLayout({
    required this.mapRect,
    required this.scale,
    required this.canvasSize,
  });

  /// Fits the canvas into [mapSize], leaving [padding] on every side.
  factory OverviewLayout.fit({
    required Size mapSize,
    required Size canvasSize,
    double padding = 3,
  }) {
    final availW = max(1.0, mapSize.width - padding * 2);
    final availH = max(1.0, mapSize.height - padding * 2);
    final s = canvasSize.width <= 0 || canvasSize.height <= 0
        ? 1.0
        : min(availW / canvasSize.width, availH / canvasSize.height);
    final w = canvasSize.width * s;
    final h = canvasSize.height * s;
    return OverviewLayout(
      mapRect: Rect.fromLTWH(
        (mapSize.width - w) / 2,
        (mapSize.height - h) / 2,
        w,
        h,
      ),
      scale: s,
      canvasSize: canvasSize,
    );
  }

  Offset toMap(Offset canvasPoint) =>
      mapRect.topLeft + canvasPoint * scale;

  Offset toCanvas(Offset mapPoint) =>
      (mapPoint - mapRect.topLeft) / scale;

  Rect rectFor(Rect canvasRect) => Rect.fromLTRB(
        mapRect.left + canvasRect.left * scale,
        mapRect.top + canvasRect.top * scale,
        mapRect.left + canvasRect.right * scale,
        mapRect.top + canvasRect.bottom * scale,
      );

  /// Clamps a canvas-space point to the canvas bounds (the navigator should
  /// never scroll past the artwork).
  Offset clampToCanvas(Offset canvasPoint) => Offset(
        canvasPoint.dx.clamp(0.0, canvasSize.width),
        canvasPoint.dy.clamp(0.0, canvasSize.height),
      );
}
