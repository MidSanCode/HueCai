import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/services/ora_codec.dart';
import 'package:hue_cai/services/psd_codec.dart';

Project _twoLayerProject() {
  final bg = Layer(
    id: 'bg',
    name: '背景',
    drawables: [
      Drawable(
        id: 'd1',
        points: const [Offset(0, 0), Offset(32, 32)],
        color: const Color(0xFF0000FF),
        strokeWidth: 8,
      ),
    ],
  );
  final top = Layer(
    id: 'top',
    name: '高光',
    opacity: 0.5,
    visible: false,
    blendMode: BlendModeExt.multiply,
    drawables: [
      Drawable(
        id: 'd2',
        points: const [Offset(8, 8), Offset(24, 24)],
        color: const Color(0xFFFF0000),
        strokeWidth: 4,
      ),
    ],
  );
  return Project(
    id: 'p1',
    name: 'ora test',
    settings: const CanvasSettings(width: 32, height: 32),
    layers: [bg, top],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

/// Builds a minimal PSD byte buffer.
Uint8List buildPsd({
  required int width,
  required int height,
  required int channels,
  int colorMode = 3,
  int compression = 0,
  required List<Uint8List> planes,
  List<int>? rowCounts,
  Uint8List? packedData,
}) {
  final b = BytesBuilder();
  b.add('8BPS'.codeUnits);
  b.add([0, 1]); // version
  b.add(List.filled(6, 0)); // reserved
  b.add([channels >> 8, channels & 0xFF]);
  b.add([
    (height >> 24) & 0xFF, (height >> 16) & 0xFF,
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 24) & 0xFF, (width >> 16) & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
  ]);
  b.add([0, 8]); // depth
  b.add([colorMode >> 8, colorMode & 0xFF]);
  b.add([0, 0, 0, 0]); // color mode data length
  b.add([0, 0, 0, 0]); // image resources length
  b.add([0, 0, 0, 0]); // layer/mask info length
  b.add([0, compression]);
  if (compression == 0) {
    for (final p in planes) {
      b.add(p);
    }
  } else {
    for (final n in rowCounts!) {
      b.add([n >> 8, n & 0xFF]);
    }
    b.add(packedData!);
  }
  return b.toBytes();
}

Future<Color> pixelAt(ui.Image img, int x, int y) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = (y * img.width + x) * 4;
  return Color.fromARGB(data!.getUint8(i + 3), data.getUint8(i),
      data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('OraCodec', () {
    test('round-trip preserves layers, flags and blend modes', () async {
      final project = _twoLayerProject();
      final dir = await Directory.systemTemp.createTemp('huecai_ora');
      final path = '${dir.path}/t.ora';
      await OraCodec.writePackage(path, project);
      final loaded = await OraCodec.readPackage(path);

      expect(loaded, isNotNull);
      expect(loaded!.settings.width, 32);
      expect(loaded.settings.height, 32);
      expect(loaded.layers, hasLength(2));

      final bg = loaded.layers[0];
      expect(bg.name, '背景');
      expect(bg.image, isNotNull);
      expect(bg.visible, isTrue);

      final top = loaded.layers[1];
      expect(top.name, '高光');
      expect(top.opacity, closeTo(0.5, 0.01));
      expect(top.visible, isFalse);
      expect(top.blendMode, BlendModeExt.multiply);

      await dir.delete(recursive: true);
    });

    test('rejects non-ORA bytes', () async {
      expect(await OraCodec.readBytes(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('PsdCodec', () {
    test('parses a raw RGB composite', () async {
      // 2x1: pixel0 = red, pixel1 = green.
      final r = Uint8List.fromList([255, 0]);
      final g = Uint8List.fromList([0, 255]);
      final b = Uint8List.fromList([0, 0]);
      final bytes = buildPsd(width: 2, height: 1, channels: 3,
          planes: [r, g, b]);
      final project = await PsdCodec.readBytes(bytes);
      expect(project, isNotNull);
      expect(project!.settings.width, 2);
      expect(project.settings.height, 1);

      final img = project.layers.first.image!;
      final p0 = await pixelAt(img, 0, 0);
      final p1 = await pixelAt(img, 1, 0);
      expect(p0.r, greaterThan(0.9));
      expect(p0.g, lessThan(0.1));
      expect(p1.g, greaterThan(0.9));
    });

    test('parses a PackBits-compressed grayscale composite', () async {
      // 4x1 grayscale: [10, 10, 10, 200] → literal(3x10 would be repeat).
      // Row: repeat-run 0xFE (=257-3) 10 → three 10s, then literal 200.
      final packed = Uint8List.fromList([0xFE, 10, 0x00, 200]);
      final bytes = buildPsd(
        width: 4,
        height: 1,
        channels: 1,
        colorMode: 1,
        compression: 1,
        planes: [],
        rowCounts: [packed.length],
        packedData: packed,
      );
      final project = await PsdCodec.readBytes(bytes);
      expect(project, isNotNull);
      final img = project!.layers.first.image!;
      expect((await pixelAt(img, 0, 0)).r * 255, closeTo(10, 2));
      expect((await pixelAt(img, 2, 0)).r * 255, closeTo(10, 2));
      expect((await pixelAt(img, 3, 0)).r * 255, closeTo(200, 2));
    });

    test('rejects wrong signature', () async {
      final bytes = Uint8List.fromList('NOPE'.codeUnits + List.filled(64, 0));
      expect(await PsdCodec.readBytes(bytes), isNull);
    });

    test('rejects 16-bit depth', () async {
      final b = BytesBuilder();
      b.add('8BPS'.codeUnits);
      b.add([0, 1]);
      b.add(List.filled(6, 0));
      b.add([0, 3]);
      b.add(List.filled(8, 0));
      b.add([0, 16]); // depth 16 — unsupported
      b.add([0, 3]);
      b.add(List.filled(14, 0));
      expect(await PsdCodec.readBytes(b.toBytes()), isNull);
    });
  });
}
