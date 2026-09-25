import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/project.dart';

/// Minimal PSD importer: reads the header and the *composite* (merged) image
/// data of RGB or grayscale 8-bit files, returning a single-layer project.
///
/// Layer-level PSD parsing is intentionally out of scope: the composite image
/// is what every PSD writer is required to embed, so this works with files
/// from any source. Compression modes supported: raw (0) and PackBits (1).
class PsdCodec {
  PsdCodec._();

  static const extension = '.psd';

  /// Reads [path] and builds a flattened project, or null when unsupported.
  static Future<Project?> readProject(String path) async {
    final bytes = await File(path).readAsBytes();
    return readBytes(bytes, name: _basename(path));
  }

  /// Bytes-level import (used by tests).
  static Future<Project?> readBytes(Uint8List bytes,
      {String name = 'imported'}) async {
    final reader = _Reader(bytes);

    // Header: signature "8BPS", version 1, 6 reserved bytes.
    if (reader.takeString(4) != '8BPS') return null;
    final version = reader.u16();
    if (version != 1) return null;
    reader.skip(6);
    final channels = reader.u16();
    final height = reader.u32();
    final width = reader.u32();
    final depth = reader.u16();
    final colorMode = reader.u16();
    if (depth != 8) return null;
    // 1 = grayscale, 3 = RGB. (CMYK etc. unsupported.)
    if (colorMode != 1 && colorMode != 3) return null;
    if (width <= 0 || height <= 0) return null;

    // Color mode data + image resources + layer/mask info: skipped by length.
    reader.skip(reader.u32());
    reader.skip(reader.u32());
    reader.skip(reader.u32());
    if (reader.remaining < 2) return null;

    final compression = reader.u16();
    if (compression != 0 && compression != 1) return null;

    // Channel plan: RGB has R,G,B in channels 0-2; alpha (4th) if present.
    final channelCount = colorMode == 1 ? channels : channels.clamp(0, 4);
    final needed = colorMode == 1 ? 1 : 3;
    if (channelCount < needed) return null;

    final planeSize = width * height;
    final planes = List.generate(
      channelCount,
      (_) => Uint8List(planeSize),
    );

    if (compression == 0) {
      for (var c = 0; c < channelCount; c++) {
        final data = reader.take(planeSize);
        if (data == null) return null;
        planes[c].setAll(0, data);
      }
    } else {
      // PackBits: per-channel row byte counts come first.
      final rowCounts = <int>[];
      for (var c = 0; c < channelCount * height; c++) {
        rowCounts.add(reader.u16());
      }
      for (var c = 0; c < channelCount; c++) {
        for (var row = 0; row < height; row++) {
          final len = rowCounts[c * height + row];
          final packed = reader.take(len);
          if (packed == null) return null;
          if (!_unpackPackBits(
              packed, planes[c], row * width, width)) {
            return null;
          }
        }
      }
    }

    // Assemble RGBA pixels.
    final rgba = Uint8List(planeSize * 4);
    for (var i = 0; i < planeSize; i++) {
      if (colorMode == 1) {
        final g = planes[0][i];
        rgba[i * 4] = g;
        rgba[i * 4 + 1] = g;
        rgba[i * 4 + 2] = g;
        rgba[i * 4 + 3] = channelCount > 1 ? planes[1][i] : 255;
      } else {
        rgba[i * 4] = planes[0][i];
        rgba[i * 4 + 1] = planes[1][i];
        rgba[i * 4 + 2] = planes[2][i];
        rgba[i * 4 + 3] = channelCount > 3 ? planes[3][i] : 255;
      }
    }

    final image = await _encodeRgba(rgba, width, height);
    if (image == null) return null;

    final layer = Layer(
      id: 'psd_0',
      name: 'composite',
      image: image,
    );
    return Project(
      id: 'psd_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      settings: CanvasSettings(width: width, height: height),
      layers: [layer],
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Unpacks one PackBits-compressed row into [dst] at [offset].
  static bool _unpackPackBits(
      Uint8List src, Uint8List dst, int offset, int expected) {
    var i = 0;
    var written = 0;
    while (i < src.length && written < expected) {
      var n = src[i++];
      if (n <= 127) {
        // Literal: copy n+1 bytes.
        final count = n + 1;
        for (var k = 0; k < count && written < expected; k++) {
          if (i >= src.length) return false;
          dst[offset + written++] = src[i++];
        }
      } else if (n >= 129) {
        // Repeat: next byte 257-n times.
        if (i >= src.length) return false;
        final value = src[i++];
        final count = 257 - n;
        for (var k = 0; k < count && written < expected; k++) {
          dst[offset + written++] = value;
        }
      }
      // n == 128: no-op.
    }
    return written == expected;
  }

  static Future<ui.Image?> _encodeRgba(
      Uint8List rgba, int w, int h) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba, w, h, ui.PixelFormat.rgba8888,
      completer.complete,
    );
    try {
      return await completer.future;
    } catch (_) {
      return null;
    }
  }

  static String _basename(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// Tiny big-endian reader over a byte buffer.
class _Reader {
  final Uint8List _bytes;
  int _pos = 0;

  _Reader(this._bytes);

  int get remaining => _bytes.length - _pos;

  String takeString(int n) {
    final data = take(n);
    return data == null ? '' : String.fromCharCodes(data);
  }

  int u16() {
    if (remaining < 2) return 0;
    final v = (_bytes[_pos] << 8) | _bytes[_pos + 1];
    _pos += 2;
    return v;
  }

  int u32() {
    if (remaining < 4) return 0;
    final v = (_bytes[_pos] << 24) |
        (_bytes[_pos + 1] << 16) |
        (_bytes[_pos + 2] << 8) |
        _bytes[_pos + 3];
    _pos += 4;
    return v;
  }

  void skip(int n) => _pos = (_pos + n).clamp(0, _bytes.length);

  Uint8List? take(int n) {
    if (remaining < n) return null;
    final out = Uint8List.fromList(_bytes.sublist(_pos, _pos + n));
    _pos += n;
    return out;
  }
}
