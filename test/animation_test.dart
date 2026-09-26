import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_cai/models/animation.dart';
import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/gif_encoder.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/lgdf_codec.dart';

/// Minimal GIF reader used to verify the encoder against the spec rather than
/// against itself.
class _GifFrame {
  final int delayCs;
  final bool transparent;
  final int transparentIndex;
  final List<int> lzw;

  _GifFrame({
    required this.delayCs,
    required this.transparent,
    required this.transparentIndex,
    required this.lzw,
  });
}

class _ParsedGif {
  final int width;
  final int height;
  final bool loops;
  final List<int> globalTable;
  final List<_GifFrame> frames;

  _ParsedGif({
    required this.width,
    required this.height,
    required this.loops,
    required this.globalTable,
    required this.frames,
  });
}

_ParsedGif _parseGif(Uint8List bytes) {
  int u16(int at) => bytes[at] | (bytes[at + 1] << 8);
  final width = u16(6);
  final height = u16(8);
  final packed = bytes[10];
  final hasTable = (packed & 0x80) != 0;
  final tableSize = 1 << ((packed & 0x07) + 1);
  var pos = 13;
  var table = <int>[];
  if (hasTable) {
    table = bytes.sublist(pos, pos + tableSize * 3);
    pos += tableSize * 3;
  }

  List<int> readSubBlocks() {
    final out = <int>[];
    while (pos < bytes.length && bytes[pos] != 0) {
      final len = bytes[pos];
      out.addAll(bytes.sublist(pos + 1, pos + 1 + len));
      pos += 1 + len;
    }
    pos++; // block terminator
    return out;
  }

  var loops = false;
  final frames = <_GifFrame>[];
  var pendingDelay = 0;
  var pendingTransparent = false;
  var pendingIndex = 0;
  while (pos < bytes.length) {
    final marker = bytes[pos];
    if (marker == 0x3B) break;
    if (marker == 0x21) {
      final label = bytes[pos + 1];
      if (label == 0xF9) {
        pendingDelay = u16(pos + 4);
        final flags = bytes[pos + 3];
        pendingTransparent = (flags & 0x01) != 0;
        pendingIndex = bytes[pos + 6];
      }
      if (label == 0xFF) loops = true;
      pos += 2; // skip the 0x21 introducer and the extension label
      readSubBlocks();
      continue;
    }
    if (marker == 0x2C) {
      pos += 10; // descriptor: rect + packed
      pos++; // LZW minimum code size
      final lzw = readSubBlocks();
      frames.add(_GifFrame(
        delayCs: pendingDelay,
        transparent: pendingTransparent,
        transparentIndex: pendingIndex,
        lzw: lzw,
      ));
      continue;
    }
    // Unknown marker: stop instead of looping forever.
    break;
  }
  return _ParsedGif(
    width: width,
    height: height,
    loops: loops,
    globalTable: table,
    frames: frames,
  );
}

/// LZW decoder implementing the GIF spec, used to prove the encoder's code
/// stream is readable by an independent implementation.
List<int> _lzwDecode(List<int> data, int minCodeSize) {
  final clear = 1 << minCodeSize;
  final end = clear + 1;
  var codeSize = minCodeSize + 1;
  var dict = <List<int>>[];

  void resetDict() {
    dict = [for (var i = 0; i < clear; i++) <int>[i], <int>[], <int>[]];
    codeSize = minCodeSize + 1;
  }

  resetDict();
  final out = <int>[];
  var bitPos = 0;

  int readCode() {
    var code = 0;
    for (var i = 0; i < codeSize; i++) {
      final byteIndex = bitPos >> 3;
      if (byteIndex >= data.length) return -1;
      code |= ((data[byteIndex] >> (bitPos & 7)) & 1) << i;
      bitPos++;
    }
    return code;
  }

  var prev = -1;
  while (true) {
    final code = readCode();
    if (code < 0) break;
    if (code == clear) {
      resetDict();
      prev = -1;
      continue;
    }
    if (code == end) break;
    List<int> entry;
    if (code < dict.length && dict[code].isNotEmpty) {
      entry = dict[code];
    } else if (prev >= 0) {
      entry = [...dict[prev], dict[prev][0]];
    } else {
      break;
    }
    out.addAll(entry);
    if (prev >= 0) {
      dict.add([...dict[prev], entry[0]]);
      if (dict.length == (1 << codeSize) && codeSize < 12) codeSize++;
    }
    prev = code;
  }
  return out;
}

/// Builds a solid-colour RGBA frame (straight, non-premultiplied alpha).
Uint8List _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('AnimationFrame', () {
    test('snapshot deep-copies drawables away from live state', () {
      final live = [
        Drawable(
          id: 'd1',
          points: const [Offset(0, 0), Offset(10, 10)],
          color: const Color(0xFFFF0000),
        ),
      ];
      final frame = AnimationFrame(
        id: 'f1',
        layers: AnimationFrame.snapshot([(id: 'layer-a', drawables: live)]),
      );
      expect(frame.layers['layer-a'], hasLength(1));
      // Mutating the live list must not touch the snapshot.
      live.clear();
      expect(frame.layers['layer-a'], hasLength(1));
    });

    test('JSON round-trip keeps layer keys and drawable counts', () {
      final frame = AnimationFrame(id: 'f1', layers: {
        'a': [Drawable(id: 'x', points: const [Offset(1, 2)])],
        'b': [
          Drawable(id: 'y', points: const [Offset(3, 4)]),
          Drawable(id: 'z', points: const [Offset(5, 6)]),
        ],
      });
      final restored = AnimationFrame.fromJson(frame.toJson());
      expect(restored.id, 'f1');
      expect(restored.layers.keys, containsAll(['a', 'b']));
      expect(restored.drawableCount, 3);
    });

    test('copyWith produces an independent frame', () {
      final frame = AnimationFrame(id: 'f1', layers: {
        'a': [Drawable(id: 'x', points: const [Offset(1, 2)])],
      });
      final copy = frame.copyWith(id: 'f2');
      expect(copy.id, 'f2');
      copy.layers['a']!.clear();
      expect(frame.layers['a'], hasLength(1));
    });
  });

  group('Project animation JSON', () {
    test('frames, current frame and settings survive a round-trip', () {
      final project = Project(
        id: 'p1',
        name: 'anim',
        settings: const CanvasSettings(width: 32, height: 32),
        layers: [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        frames: [
          AnimationFrame(id: 'f1', layers: {
            'a': [Drawable(id: 'x', points: const [Offset(1, 2)])],
          }),
          AnimationFrame(id: 'f2'),
        ],
        currentFrame: 1,
      );
      project.animation.fps = 24;
      project.animation.onionSkin = true;
      project.animation.onionRange = 3;

      final restored = Project.fromJson(project.toJson());
      expect(restored.frames, hasLength(2));
      expect(restored.frames.first.id, 'f1');
      expect(restored.frames.first.layers['a'], hasLength(1));
      expect(restored.currentFrame, 1);
      expect(restored.animation.fps, 24);
      expect(restored.animation.onionSkin, isTrue);
      expect(restored.animation.onionRange, 3);
      expect(restored.isAnimated, isTrue);
    });

    test('the LGDF package round-trips the timeline', () async {
      final project = Project(
        id: 'p1',
        name: 'anim',
        settings: const CanvasSettings(width: 32, height: 32),
        layers: [
          Layer(
            id: 'base',
            name: 'base',
            drawables: [
              Drawable(id: 's1', points: const [Offset(1, 1), Offset(4, 4)]),
            ],
          ),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        frames: [
          AnimationFrame(id: 'f1', layers: {
            'base': [Drawable(id: 's1', points: const [Offset(1, 1)])],
          }),
          AnimationFrame(id: 'f2'),
        ],
        currentFrame: 1,
      );
      project.animation.fps = 15;

      final dir = await Directory.systemTemp.createTemp('huecai_anim');
      final path = '${dir.path}/a${LgdfCodec.extension}';
      await LgdfCodec.writePackage(path, project, HistoryService());
      final loaded = await LgdfCodec.readPackage(path);

      expect(loaded, isNotNull);
      expect(loaded!.frames, hasLength(2));
      expect(loaded.frames[0].id, 'f1');
      expect(loaded.frames[0].layers['base'], hasLength(1));
      expect(loaded.frames[1].layers['base'], anyOf(isNull, isEmpty));
      expect(loaded.currentFrame, 1);
      expect(loaded.animation.fps, 15);

      await dir.delete(recursive: true);
    });
  });

  group('ProjectProvider timeline', () {
    test('ensureTimeline captures the current drawing as frame 0', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      expect(pp.currentProject!.frames, isEmpty);
      expect(pp.ensureTimeline(), isTrue);
      expect(pp.currentProject!.frames, hasLength(1));
      // Starting twice must not duplicate frame 0.
      pp.ensureTimeline();
      expect(pp.currentProject!.frames, hasLength(1));
    });

    test('addFrame creates an empty frame and switching restores content',
        () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.ensureTimeline();
      final paintLayer = pp.currentProject!.layers[0];
      final baseline = paintLayer.drawables.length;
      paintLayer.drawables.add(Drawable(id: 's1', points: const [Offset(2, 2)]));

      pp.addFrame();
      final project = pp.currentProject!;
      expect(project.frames, hasLength(2));
      expect(project.currentFrame, 1);
      // The new frame starts empty.
      expect(project.layers[0].drawables, isEmpty);
      // Frame 0 kept the stroke.
      expect(project.frames[0].layers[paintLayer.id], hasLength(baseline + 1));

      pp.goToFrame(0);
      expect(project.currentFrame, 0);
      expect(project.layers[0].drawables, hasLength(baseline + 1));
      expect(
        project.layers[0].drawables.map((d) => d.id),
        contains('s1'),
      );
    });

    test('duplicateFrame copies content into the new frame', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.ensureTimeline();
      final layer = pp.currentProject!.layers[0];
      final baseline = layer.drawables.length;
      layer.drawables.add(Drawable(id: 's1', points: const [Offset(2, 2)]));
      pp.duplicateFrame();
      final project = pp.currentProject!;
      expect(project.frames, hasLength(2));
      expect(project.frames[1].layers[layer.id], hasLength(baseline + 1));
      expect(project.layers[0].drawables, hasLength(baseline + 1));
    });

    test('deleteFrame refuses to remove the only frame', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.ensureTimeline();
      pp.deleteFrame(0);
      expect(pp.currentProject!.frames, hasLength(1));
      pp.addFrame();
      pp.deleteFrame(1);
      final project = pp.currentProject!;
      expect(project.frames, hasLength(1));
      expect(project.currentFrame, 0);
    });

    test('nextFrame wraps when looping and stops without loop', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.ensureTimeline();
      pp.addFrame();
      final project = pp.currentProject!;
      project.animation.loop = true;
      pp.goToFrame(1);
      pp.nextFrame();
      expect(project.currentFrame, 0);
      // Without loop, the last frame is the end of playback.
      project.animation.loop = false;
      pp.goToFrame(1);
      pp.nextFrame();
      expect(project.currentFrame, 1);
    });

    test('onionFrames returns neighbours only when enabled', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.ensureTimeline();
      pp.addFrame();
      pp.addFrame();
      pp.goToFrame(1);
      expect(pp.onionFrames(), isEmpty);
      pp.toggleOnionSkin();
      pp.setOnionRange(2);
      final ghosts = pp.onionFrames();
      expect(ghosts, hasLength(2));
      expect(ghosts.where((g) => g.before), hasLength(1));
      expect(ghosts.where((g) => !g.before), hasLength(1));
    });

    test('setAnimationFps clamps to a sane range', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.setAnimationFps(999);
      expect(pp.currentProject!.animation.fps, 60);
      pp.setAnimationFps(0);
      expect(pp.currentProject!.animation.fps, 1);
    });
  });

  group('playbackSchedule', () {
    test('expands holds into a frame schedule', () {
      expect(playbackSchedule([1, 2, 1]), [0, 1, 1, 2]);
    });

    test('treats non-positive holds as one tick', () {
      expect(playbackSchedule([0, -3]), [0, 1]);
    });
  });

  group('GifEncoder', () {
    test('writes a GIF89a header, logical size and trailer', () {
      final bytes = GifEncoder.encode([
        GifFrameData(
          rgba: _solid(4, 3, 255, 0, 0),
          width: 4,
          height: 3,
          delayCs: 8,
        ),
      ]);
      expect(bytes.sublist(0, 6), 'GIF89a'.codeUnits);
      final parsed = _parseGif(bytes);
      expect(parsed.width, 4);
      expect(parsed.height, 3);
      expect(parsed.frames, hasLength(1));
      expect(bytes.last, 0x3B);
      // Global colour table is a power of two with at least the used colours.
      expect(parsed.globalTable.length % 3, 0);
      final entries = parsed.globalTable.length ~/ 3;
      expect(entries, greaterThanOrEqualTo(1));
      expect(entries & (entries - 1), 0);
      expect(entries, lessThanOrEqualTo(256));
    });

    test('emits a loop extension and one delay per frame', () {
      final frames = [
        GifFrameData(rgba: _solid(2, 2, 255, 0, 0), width: 2, height: 2, delayCs: 8),
        GifFrameData(rgba: _solid(2, 2, 0, 0, 255), width: 2, height: 2, delayCs: 8),
      ];
      final parsed = _parseGif(GifEncoder.encode(frames));
      expect(parsed.loops, isTrue);
      expect(parsed.frames, hasLength(2));
      expect(parsed.frames.every((f) => f.delayCs == 8), isTrue);

      final once = _parseGif(GifEncoder.encode(frames, loop: false));
      expect(once.loops, isFalse);
    });

    test('LZW stream decodes back to the quantized indices', () {
      final rgba = Uint8List(16 * 16 * 4);
      for (var i = 0; i < 16 * 16; i++) {
        // A gradient that compresses into longer runs than a solid block.
        final v = (i * 7) % 256;
        rgba[i * 4] = v;
        rgba[i * 4 + 1] = 255 - v;
        rgba[i * 4 + 2] = v ~/ 2;
        rgba[i * 4 + 3] = 255;
      }
      final data = GifFrameData(rgba: rgba, width: 16, height: 16, delayCs: 10);
      final palette = GifEncoder.buildPalette([data]);
      final expected = palette.indicesFor(rgba);
      final parsed = _parseGif(GifEncoder.encode([data]));
      final decoded = _lzwDecode(parsed.frames.first.lzw, 8);
      expect(decoded, hasLength(expected.length));
      expect(decoded, equals(expected.toList()));
    });

    test('decodes long index streams (dictionary growth + clear codes)', () {
      // 120x120 noise-ish pattern forces the LZW table past 4096 entries.
      const w = 120, h = 120;
      final rgba = Uint8List(w * h * 4);
      var seed = 12345;
      for (var i = 0; i < w * h; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        rgba[i * 4] = seed & 0xFF;
        rgba[i * 4 + 1] = (seed >> 8) & 0xFF;
        rgba[i * 4 + 2] = (seed >> 16) & 0xFF;
        rgba[i * 4 + 3] = 255;
      }
      final data = GifFrameData(rgba: rgba, width: w, height: h, delayCs: 5);
      final palette = GifEncoder.buildPalette([data]);
      final expected = palette.indicesFor(rgba);
      final parsed = _parseGif(GifEncoder.encode([data]));
      final decoded = _lzwDecode(parsed.frames.first.lzw, 8);
      expect(decoded, equals(expected.toList()));
    });

    test('reserves a transparent index when frames have alpha', () {
      final rgba = Uint8List(4 * 4 * 4);
      // Half opaque red, half fully transparent.
      for (var i = 0; i < 16; i++) {
        final opaque = i.isEven;
        rgba[i * 4] = 255;
        rgba[i * 4 + 3] = opaque ? 255 : 0;
      }
      final data = GifFrameData(rgba: rgba, width: 4, height: 4, delayCs: 5);
      final palette = GifEncoder.buildPalette([data]);
      expect(palette.transparentIndex, 0);
      final parsed = _parseGif(GifEncoder.encode([data]));
      final frame = parsed.frames.first;
      expect(frame.transparent, isTrue);
      expect(frame.transparentIndex, 0);
      final decoded = _lzwDecode(frame.lzw, 8);
      // Even pixels stay opaque, odd ones collapse to the transparent index.
      expect(decoded[0], isNot(0));
      expect(decoded[1], 0);
    });

    test('keeps the dominant colour when quantizing', () {
      final frame = GifFrameData(
        rgba: _solid(8, 8, 12, 200, 40),
        width: 8,
        height: 8,
        delayCs: 5,
      );
      final palette = GifEncoder.buildPalette([frame]);
      final index = palette.indexOf(12, 200, 40);
      expect(palette.colors[index * 3], 12);
      expect(palette.colors[index * 3 + 1], 200);
      expect(palette.colors[index * 3 + 2], 40);
    });

    test('encoding no frames yields empty output', () {
      expect(GifEncoder.encode(const []), isEmpty);
    });
  });
}
