import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/services/image_filters.dart';

/// 4x4 image, all pixels the given RGBA.
RgbaImage solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final img = RgbaImage.blank(w, h);
  for (var i = 0; i < img.pixels.length; i += 4) {
    img.pixels[i] = r;
    img.pixels[i + 1] = g;
    img.pixels[i + 2] = b;
    img.pixels[i + 3] = a;
  }
  return img;
}

/// Image with a vertical white stripe down the middle, black elsewhere.
RgbaImage stripe(int w, int h) {
  final img = RgbaImage.blank(w, h);
  final mid = w ~/ 2;
  for (var y = 0; y < h; y++) {
    final i = (y * w + mid) * 4;
    img.pixels[i] = 255;
    img.pixels[i + 1] = 255;
    img.pixels[i + 2] = 255;
    img.pixels[i + 3] = 255;
  }
  return img;
}

int r(RgbaImage img, int x, int y) => img.pixels[(y * img.width + x) * 4];

void main() {
  group('gaussianBlur', () {
    test('radius 0 is an identity copy', () {
      final src = stripe(16, 16);
      final out = ImageFilters.gaussianBlur(src, 0);
      expect(out.pixels, orderedEquals(src.pixels));
    });

    test('blurs a hard stripe into its neighbors', () {
      final src = stripe(16, 16);
      final out = ImageFilters.gaussianBlur(src, 3);
      final mid = 8;
      // Center dimmed, neighbor brightened, far edge still black.
      expect(r(out, mid, 8), lessThan(255));
      expect(r(out, mid - 1, 8), greaterThan(0));
      expect(r(out, 0, 8), 0);
    });

    test('preserves alpha channel', () {
      final src = solid(8, 8, 200, 100, 50, 128);
      final out = ImageFilters.gaussianBlur(src, 2);
      expect(out.pixels[3], 128);
    });
  });

  group('unsharpMask', () {
    test('increases edge contrast around a stripe', () {
      final src = stripe(16, 16);
      final out = ImageFilters.unsharpMask(src, 2, 1.0);
      final mid = 8;
      // White side of the edge gets whiter/clamped, black side stays dark
      // or goes darker than the blurred version would.
      expect(r(out, mid, 8), greaterThanOrEqualTo(r(src, mid, 8)));
      expect(r(out, mid - 1, 8), lessThanOrEqualTo(r(src, mid - 1, 8)));
    });

    test('threshold suppresses small differences', () {
      final src = stripe(16, 16);
      final out = ImageFilters.unsharpMask(src, 2, 2.0, threshold: 255);
      expect(out.pixels, orderedEquals(src.pixels));
    });

    test('amount 0 is identity', () {
      final src = stripe(16, 16);
      final out = ImageFilters.unsharpMask(src, 2, 0);
      expect(out.pixels, orderedEquals(src.pixels));
    });
  });

  group('levels', () {
    test('identity parameters keep pixels unchanged', () {
      final src = stripe(8, 8);
      final out = ImageFilters.levels(src);
      expect(out.pixels, orderedEquals(src.pixels));
    });

    test('narrowing the input range stretches contrast', () {
      // mid-gray 128 with inBlack 0 / inWhite 255 stays mid; with
      // inBlack=64, inWhite=192, 128 maps to the output midpoint.
      final lut = ImageFilters.levelsLut(inBlack: 64, inWhite: 192);
      expect(lut[64], 0);
      expect(lut[192], 255);
      expect(lut[128], inInclusiveRange(120, 136));
    });

    test('gamma > 1 brightens midtones', () {
      final lut = ImageFilters.levelsLut(gamma: 2);
      expect(lut[128], greaterThan(128));
    });

    test('output range clamps the result', () {
      final lut = ImageFilters.levelsLut(outBlack: 50, outWhite: 100);
      expect(lut[0], 50);
      expect(lut[255], 100);
    });

    test('alpha untouched', () {
      final src = solid(4, 4, 10, 20, 30, 99);
      final out = ImageFilters.levels(src, inBlack: 0, inWhite: 255);
      expect(out.pixels[3], 99);
    });
  });

  group('curves', () {
    test('identity curve keeps pixels unchanged', () {
      final src = stripe(8, 8);
      final out = ImageFilters.curves(src, [(x: 0, y: 0), (x: 255, y: 255)]);
      for (var i = 0; i < src.pixels.length; i += 4) {
        expect((out.pixels[i] - src.pixels[i]).abs(), lessThanOrEqualTo(2));
      }
    });

    test('inverted S-curve brightens midtones', () {
      final lut = ImageFilters.curvesLut(
          [(x: 0, y: 0), (x: 128, y: 190), (x: 255, y: 255)]);
      expect(lut[128], inInclusiveRange(170, 210));
    });

    test('full inversion flips black and white', () {
      final lut = ImageFilters.curvesLut([(x: 0, y: 255), (x: 255, y: 0)]);
      expect(lut[0], greaterThan(200));
      expect(lut[255], lessThan(55));
    });
  });

  group('hueSaturation', () {
    test('zero parameters keep pixels (approximately) unchanged', () {
      final src = solid(4, 4, 200, 80, 40);
      final out = ImageFilters.hueSaturation(src);
      expect((out.pixels[0] - 200).abs(), lessThanOrEqualTo(2));
      expect((out.pixels[1] - 80).abs(), lessThanOrEqualTo(2));
      expect((out.pixels[2] - 40).abs(), lessThanOrEqualTo(2));
    });

    test('hue shift 180 turns red into cyan-ish', () {
      final src = solid(2, 2, 255, 0, 0);
      final out = ImageFilters.hueSaturation(src, hueShift: 180);
      expect(out.pixels[0], lessThan(40)); // red channel low
      expect(out.pixels[1], greaterThan(200)); // green high
      expect(out.pixels[2], greaterThan(200)); // blue high
    });

    test('saturation 0 produces gray', () {
      final src = solid(2, 2, 255, 0, 0);
      final out = ImageFilters.hueSaturation(src, saturationScale: 0);
      expect(out.pixels[0], out.pixels[1]);
      expect(out.pixels[1], out.pixels[2]);
    });

    test('alpha untouched', () {
      final src = solid(2, 2, 255, 0, 0, 77);
      final out = ImageFilters.hueSaturation(src, hueShift: 120);
      expect(out.pixels[3], 77);
    });
  });

  group('RgbaImage', () {
    test('copy is independent of the source', () {
      final src = solid(2, 2, 1, 2, 3);
      final out = src.copy();
      out.pixels[0] = 255;
      expect(src.pixels[0], 1);
    });

    test('blank has the right size', () {
      final img = RgbaImage.blank(3, 5);
      expect(img.pixels, isA<Uint8List>());
      expect(img.pixels.length, 3 * 5 * 4);
    });
  });
}
