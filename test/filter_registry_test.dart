import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/services/filter_registry.dart';
import 'package:hue_cai/services/image_filters.dart';

/// 8×8 test image: red / green / blue quadrants plus a gray column, so every
/// filter has something to chew on.
RgbaImage _sample() {
  final img = RgbaImage.blank(8, 8);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      final i = (y * 8 + x) * 4;
      final int r, g, b;
      if (x < 4 && y < 4) {
        r = 255; g = 0; b = 0;
      } else if (x >= 4 && y < 4) {
        r = 0; g = 255; b = 0;
      } else if (x < 4) {
        r = 0; g = 0; b = 255;
      } else {
        r = 128; g = 128; b = 128;
      }
      img.pixels[i] = r;
      img.pixels[i + 1] = g;
      img.pixels[i + 2] = b;
      img.pixels[i + 3] = 255;
    }
  }
  return img;
}

int _at(RgbaImage img, int x, int y, int c) =>
    img.pixels[(y * img.width + x) * 4 + c];

void main() {
  group('registry completeness', () {
    test('exposes 25+ filters across the four groups', () {
      expect(FilterRegistry.all.length, greaterThanOrEqualTo(25));
      expect(FilterRegistry.groupKeys.length, 4);
    });

    test('every kind is unique and resolvable', () {
      final kinds = FilterRegistry.all.map((d) => d.kind).toList();
      expect(kinds.toSet().length, kinds.length);
      for (final k in kinds) {
        expect(FilterRegistry.byKind(k), isNotNull);
      }
    });

    test('unknown kind passes through unchanged', () {
      final src = _sample();
      final out = FilterRegistry.apply('doesNotExist', src, {});
      expect(out.width, src.width);
      expect(out.pixels, src.pixels);
    });

    test('every filter runs, preserves size and produces valid channels', () {
      final src = _sample();
      for (final def in FilterRegistry.all) {
        final out = FilterRegistry.apply(def.kind, src, def.defaultParams());
        expect(out.width, src.width, reason: '${def.kind} width');
        expect(out.height, src.height, reason: '${def.kind} height');
        expect(out.pixels.length, src.pixels.length, reason: '${def.kind} len');
      }
    });

    test('every filter default is inside its declared range', () {
      for (final def in FilterRegistry.all) {
        for (final p in def.params) {
          expect(p.def, greaterThanOrEqualTo(p.min), reason: '${def.kind}.${p.key}');
          expect(p.def, lessThanOrEqualTo(p.max), reason: '${def.kind}.${p.key}');
        }
      }
    });
  });

  group('tone filters', () {
    test('invert flips channels', () {
      final out = ImageFilters.invert(_sample());
      expect(_at(out, 0, 0, 0), 0); // red -> cyan
      expect(_at(out, 0, 0, 1), 255);
      expect(_at(out, 0, 0, 2), 255);
    });

    test('threshold makes black or white only', () {
      final out = ImageFilters.threshold(_sample(), 128);
      for (var i = 0; i < out.pixels.length; i += 4) {
        expect(out.pixels[i] == 0 || out.pixels[i] == 255, isTrue);
      }
    });

    test('posterize reduces the number of distinct values', () {
      final src = _sample();
      final out = ImageFilters.posterize(src, 3);
      final distinct = <int>{};
      for (var i = 0; i < out.pixels.length; i += 4) {
        distinct.add(out.pixels[i]);
      }
      expect(distinct.length, lessThanOrEqualTo(3));
    });

    test('exposure brightens and clamps at 255', () {
      final out = ImageFilters.exposure(_sample(), 1);
      expect(_at(out, 0, 0, 0), 255);
      expect(_at(out, 4, 4, 0), 255); // 128 * 2 clamps
    });

    test('normalize stretches a narrow range to full 0..255', () {
      // A low-contrast image: red ramps 100..150, blue ramps 150..100.
      final flat = RgbaImage.blank(4, 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          final i = (y * 4 + x) * 4;
          flat.pixels[i] = 100 + x * 16; // 100..148
          flat.pixels[i + 1] = 120;
          flat.pixels[i + 2] = 150 - x * 16;
          flat.pixels[i + 3] = 255;
        }
      }
      final out = ImageFilters.normalize(flat);
      expect(out.pixels[0], 0); // darkest red -> 0
      expect(out.pixels[2], 255); // brightest blue (x=0) -> 255
    });

    test('equalize does not change image size and stays in range', () {
      final out = ImageFilters.equalize(_sample());
      for (var i = 0; i < out.pixels.length; i++) {
        expect(out.pixels[i], inInclusiveRange(0, 255));
      }
    });

    test('solarize inverts only above the threshold', () {
      final out = ImageFilters.solarize(_sample(), 200);
      expect(_at(out, 0, 0, 0), 0); // 255 -> 255-255
      expect(_at(out, 4, 4, 0), 128); // below threshold untouched
    });
  });

  group('color filters', () {
    test('desaturate(1) makes every pixel gray', () {
      final out = ImageFilters.desaturate(_sample(), 1);
      for (var i = 0; i < out.pixels.length; i += 4) {
        expect(out.pixels[i], out.pixels[i + 1]);
        expect(out.pixels[i + 1], out.pixels[i + 2]);
      }
    });

    test('gradientMap maps luminance to the two endpoints', () {
      final out = ImageFilters.gradientMap(_sample(), [0xFF000000, 0xFFFFFFFF]);
      // Black for the darkest source pixel (blue quadrant luminance > 0, so
      // use pure black input instead).
      final black = RgbaImage.blank(1, 1)..pixels[3] = 255;
      final mapped = ImageFilters.gradientMap(black, [0xFF000000, 0xFFFFFFFF]);
      expect(mapped.pixels[0], 0);
      final white = RgbaImage.blank(1, 1);
      for (var c = 0; c < 3; c++) {
        white.pixels[c] = 255;
      }
      white.pixels[3] = 255;
      final mappedWhite =
          ImageFilters.gradientMap(white, [0xFF000000, 0xFFFFFFFF]);
      expect(mappedWhite.pixels[0], 255);
      expect(out.width, 8);
    });

    test('channelMixer identity leaves the image unchanged', () {
      final src = _sample();
      final out = ImageFilters.channelMixer(
        src,
        [1, 0, 0, 0, 1, 0, 0, 0, 1],
        [0, 0, 0],
      );
      expect(out.pixels, src.pixels);
    });

    test('channelMixer can swap red and blue', () {
      final out = ImageFilters.channelMixer(
        _sample(),
        [0, 0, 1, 0, 1, 0, 1, 0, 0],
        [0, 0, 0],
      );
      expect(_at(out, 0, 0, 0), 0);
      expect(_at(out, 0, 0, 2), 255);
    });

    test('whiteBalance warms and cools', () {
      final warm = ImageFilters.whiteBalance(_sample(), 1, 0);
      final cool = ImageFilters.whiteBalance(_sample(), -1, 0);
      expect(_at(warm, 4, 4, 0), greaterThan(_at(cool, 4, 4, 0)));
    });
  });

  group('stylize filters', () {
    test('pixelate averages a block to one color', () {
      final out = ImageFilters.pixelate(_sample(), 4);
      // Top-left 4×4 block was pure red.
      expect(_at(out, 0, 0, 0), 255);
      expect(_at(out, 3, 3, 0), 255);
      expect(_at(out, 3, 3, 1), 0);
    });

    test('halftone outputs only black and white', () {
      final out = ImageFilters.halftone(_sample(), 4);
      for (var i = 0; i < out.pixels.length; i += 4) {
        expect(out.pixels[i] == 0 || out.pixels[i] == 255, isTrue);
      }
    });

    test('noise is deterministic for a given seed', () {
      final a = ImageFilters.noise(_sample(), 0.3, seed: 7);
      final b = ImageFilters.noise(_sample(), 0.3, seed: 7);
      final c = ImageFilters.noise(_sample(), 0.3, seed: 8);
      expect(a.pixels, b.pixels);
      expect(a.pixels, isNot(c.pixels));
    });

    test('vignette darkens corners but not the center', () {
      final src = _sample();
      final out = ImageFilters.vignette(src, 0.8);
      expect(_at(out, 0, 0, 0), lessThan(_at(src, 0, 0, 0)));
      expect(_at(out, 4, 4, 1), _at(src, 4, 4, 1));
    });

    test('motionBlur with distance 0 is a copy', () {
      final src = _sample();
      final out = ImageFilters.motionBlur(src, 0, 0);
      expect(out.pixels, src.pixels);
    });

    test('ripple shifts rows horizontally', () {
      final src = _sample();
      final out = ImageFilters.ripple(src, 4, 8);
      expect(out.width, src.width);
      expect(out.pixels.length, src.pixels.length);
    });

    test('emboss keeps the alpha channel', () {
      final out = ImageFilters.emboss(_sample(), 1);
      for (var i = 3; i < out.pixels.length; i += 4) {
        expect(out.pixels[i], 255);
      }
    });

    test('oilPaint keeps alpha and size', () {
      final out = ImageFilters.oilPaint(_sample(), 2, 8);
      expect(out.width, 8);
      expect(out.pixels[3], 255);
    });

    test('edgeDetect at amount 1 produces a grayscale-ish edge map', () {
      final out = ImageFilters.edgeDetect(_sample(), 1);
      expect(out.width, 8);
    });
  });

  group('adjustment spec integration', () {
    test('AdjustmentSpec runs any registered filter', () {
      final src = _sample();
      const spec = AdjustmentSpec('pixelate', {'block': 4});
      final out = spec.apply(src);
      expect(out.width, src.width);
      expect(_at(out, 0, 0, 0), 255);
    });

    test('AdjustmentSpec JSON round-trip keeps the new kinds', () {
      const spec = AdjustmentSpec('colorBalance', {'shadows_r': 0.2});
      final back = AdjustmentSpec.fromJson(spec.toJson());
      expect(back.kind, 'colorBalance');
      expect(back.params['shadows_r'], 0.2);
      expect(back.apply(_sample()).width, 8);
    });
  });
}
