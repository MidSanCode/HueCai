import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/services/gamut.dart';
import 'package:hue_cai/services/palette_service.dart';

const _sampleGpl = '''
GIMP Palette
Name: Sunset
Columns: 8
# a comment line
255   0   0	Red
  0 128 255	Sky
 17  34  51
''';

void main() {
  group('PaletteCodec.parseGpl', () {
    test('reads name and colors', () {
      final p = PaletteCodec.parseGpl(_sampleGpl);
      expect(p, isNotNull);
      expect(p!.name, 'Sunset');
      expect(p.length, 3);
      expect(p.colors[0], const Color(0xFFFF0000));
      expect(p.colors[1], const Color(0xFF0080FF));
      expect(p.colors[2], const Color(0xFF112233));
    });

    test('tolerates a missing magic header', () {
      final p = PaletteCodec.parseGpl('Name: X\n1 2 3\n');
      expect(p!.name, 'X');
      expect(p.colors.single, const Color(0xFF010203));
    });

    test('returns null when no colors parse', () {
      expect(PaletteCodec.parseGpl('GIMP Palette\nName: Empty\n#'), isNull);
    });

    test('clamps out-of-range channel values', () {
      final p = PaletteCodec.parseGpl('GIMP Palette\n999 -5 300\n');
      expect(p!.colors.single, const Color(0xFFFF00FF));
    });
  });

  group('PaletteCodec.toGpl', () {
    test('round-trips through parse', () {
      final original = Palette(name: 'Round', colors: const [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
        Color(0xFF0000FF),
      ]);
      final text = PaletteCodec.toGpl(original);
      expect(text, startsWith('GIMP Palette'));
      final back = PaletteCodec.parseGpl(text);
      expect(back!.name, 'Round');
      expect(back.colors, original.colors);
    });

    test('hexOf produces upper-case #RRGGBB', () {
      expect(PaletteCodec.hexOf(const Color(0xFF1A2B3C)), '#1A2B3C');
    });
  });

  group('PaletteCodec.parseHexList', () {
    test('accepts 6-digit, 3-digit and bare hex', () {
      final p = PaletteCodec.parseHexList('#ff0000, 00ff00\n#0f0');
      expect(p!.length, 3);
      expect(p.colors[0], const Color(0xFFFF0000));
      expect(p.colors[1], const Color(0xFF00FF00));
      expect(p.colors[2], const Color(0xFF00FF00));
    });

    test('parse() prefers gpl over hex list', () {
      final p = PaletteCodec.parse(_sampleGpl);
      expect(p!.name, 'Sunset');
    });
  });

  group('Gamut', () {
    test('pure black and white are in gamut for every profile', () {
      for (final profile in [
        PrintProfile.coated,
        PrintProfile.uncoated,
        PrintProfile.newsprint,
      ]) {
        expect(Gamut.isOutOfGamut(const Color(0xFF000000), profile), isFalse);
        expect(Gamut.isOutOfGamut(const Color(0xFFFFFFFF), profile), isFalse);
      }
    });

    test('deep saturated colors exceed the ink limit and are flagged', () {
      // Dark saturated blue needs ~100% C + ~100% M + 70% K: far past a
      // newsprint ink limit of 220%.
      const deepBlue = Color(0xFF0000B4);
      final cmyk = Gamut.toCmyk(deepBlue);
      expect(cmyk.c + cmyk.m + cmyk.y + cmyk.k, greaterThan(2.2));
      expect(Gamut.isOutOfGamut(deepBlue, PrintProfile.newsprint), isTrue);
    });

    test('ink limiting keeps the total under the profile limit', () {
      final cmyk = Gamut.limitInk(
        Gamut.toCmyk(const Color(0xFF0000B4)),
        PrintProfile.newsprint,
      );
      expect(cmyk.c + cmyk.m + cmyk.y + cmyk.k,
          lessThanOrEqualTo(PrintProfile.newsprint.totalInkLimit + 1e-9));
    });

    test('softProof of an in-gamut color is close to the original', () {
      const gray = Color(0xFF808080);
      final proof = Gamut.softProof(gray, PrintProfile.coated);
      expect(Gamut.deviation(gray, proof), lessThan(0.12));
    });

    test('nearestInGamut returns an in-gamut color', () {
      const vivid = Color(0xFF0000B4);
      final fixed = Gamut.nearestInGamut(vivid, PrintProfile.newsprint);
      expect(
        Gamut.isOutOfGamut(fixed, PrintProfile.newsprint),
        isFalse,
        reason: 'fixed color should be printable',
      );
    });

    test('nearestInGamut leaves in-gamut colors untouched', () {
      const ok = Color(0xFF808080);
      expect(Gamut.nearestInGamut(ok, PrintProfile.coated), ok);
    });

    test('tighter profiles flag more colors', () {
      const candidate = Color(0xFF33DD44);
      final coated = Gamut.isOutOfGamut(candidate, PrintProfile.coated);
      final news = Gamut.isOutOfGamut(candidate, PrintProfile.newsprint);
      expect(news || !coated, isTrue);
    });
  });
}
