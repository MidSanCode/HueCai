import 'dart:typed_data';

/// One raw RGBA frame handed to the GIF encoder.
class GifFrameData {
  final Uint8List rgba;
  final int width;
  final int height;

  /// Frame duration in 1/100 s units (GIF's native delay unit).
  final int delayCs;

  GifFrameData({
    required this.rgba,
    required this.width,
    required this.height,
    required this.delayCs,
  });
}

/// A quantized colour table plus a lookup cache.
class GifPalette {
  /// RGB triples, `colors.length / 3` entries.
  final List<int> colors;

  /// Index reserved for fully transparent pixels, or -1.
  final int transparentIndex;

  final Map<int, int> _cache = {};

  GifPalette(this.colors, {this.transparentIndex = -1});

  int get length => colors.length ~/ 3;

  /// Index of the nearest palette colour for one straight (un-premultiplied)
  /// RGB triple.
  int indexOf(int r, int g, int b) {
    final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
    final cached = _cache[key];
    if (cached != null) return cached;
    var best = transparentIndex == 0 ? 1 : 0;
    var bestDist = 1 << 30;
    final count = length;
    for (var i = 0; i < count; i++) {
      if (i == transparentIndex) continue;
      final dr = r - colors[i * 3];
      final dg = g - colors[i * 3 + 1];
      final db = b - colors[i * 3 + 2];
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
        if (dist == 0) break;
      }
    }
    _cache[key] = best;
    return best;
  }

  /// Maps a frame's RGBA bytes to palette indices. Pixels below
  /// [alphaThreshold] become [transparentIndex] when transparency is enabled.
  Uint8List indicesFor(Uint8List rgba, {int alphaThreshold = 128}) {
    final out = Uint8List(rgba.length ~/ 4);
    for (var p = 0, i = 0; i < out.length; i++, p += 4) {
      final a = rgba[p + 3];
      if (a < alphaThreshold && transparentIndex >= 0) {
        out[i] = transparentIndex;
        continue;
      }
      // Flutter hands out premultiplied RGBA; undo it for colour matching.
      final r = a == 0 ? 0 : (rgba[p] * 255 ~/ a).clamp(0, 255);
      final g = a == 0 ? 0 : (rgba[p + 1] * 255 ~/ a).clamp(0, 255);
      final b = a == 0 ? 0 : (rgba[p + 2] * 255 ~/ a).clamp(0, 255);
      out[i] = indexOf(r, g, b);
    }
    return out;
  }
}

/// Minimal, dependency-free GIF89a writer.
///
/// The palette is built once for the whole animation with a median-cut
/// quantizer and stored as a single global colour table; LZW is applied per
/// frame. Only one transparent index is supported, which is all GIF allows.
class GifEncoder {
  /// Builds a shared palette from every frame's pixels.
  static GifPalette buildPalette(List<GifFrameData> frames,
      {int maxColors = 256, int alphaThreshold = 128}) {
    final histogram = <int, List<int>>{}; // 15-bit key → [count, rSum, gSum, bSum]
    var hasTransparent = false;
    // Sample with a stride so huge canvases stay fast; the palette only needs
    // a representative picture of the colours in play.
    var totalPixels = 0;
    for (final f in frames) {
      totalPixels += f.rgba.length ~/ 4;
    }
    final stride = totalPixels > 40000 ? (totalPixels ~/ 40000).clamp(1, 64) : 1;
    for (final f in frames) {
      final pixels = f.rgba.length ~/ 4;
      for (var i = 0; i < pixels; i += stride) {
        final p = i * 4;
        final a = f.rgba[p + 3];
        if (a < alphaThreshold) {
          hasTransparent = true;
          continue;
        }
        final r = a == 0 ? 0 : (f.rgba[p] * 255 ~/ a).clamp(0, 255);
        final g = a == 0 ? 0 : (f.rgba[p + 1] * 255 ~/ a).clamp(0, 255);
        final b = a == 0 ? 0 : (f.rgba[p + 2] * 255 ~/ a).clamp(0, 255);
        final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
        final entry = histogram[key];
        if (entry == null) {
          histogram[key] = [1, r, g, b];
        } else {
          entry[0]++;
          entry[1] += r;
          entry[2] += g;
          entry[3] += b;
        }
      }
    }

    // Reserve index 0 for transparency when the animation needs it.
    final transparentIndex = hasTransparent ? 0 : -1;
    final available = transparentIndex >= 0 ? maxColors - 1 : maxColors;
    final boxes = _medianCut(histogram.entries.toList(), available);

    final colors = <int>[];
    if (transparentIndex >= 0) colors.addAll([0, 0, 0]);
    for (final box in boxes) {
      var count = 0, r = 0, g = 0, b = 0;
      for (final e in box) {
        final v = e.value;
        count += v[0];
        r += v[1];
        g += v[2];
        b += v[3];
      }
      if (count == 0) continue;
      colors.addAll([r ~/ count, g ~/ count, b ~/ count]);
    }
    // GIF colour tables must be a power of two, at least 2 entries.
    while (colors.length < 6) {
      colors.addAll([0, 0, 0]);
    }
    var entries = 2;
    while (entries < colors.length ~/ 3) {
      entries <<= 1;
    }
    while (colors.length < entries * 3) {
      colors.addAll([0, 0, 0]);
    }
    return GifPalette(colors, transparentIndex: transparentIndex);
  }

  /// Weighted median cut: repeatedly splits the box with the widest colour
  /// spread until [maxColors] boxes (or fewer, when colours run out) exist.
  static List<List<MapEntry<int, List<int>>>> _medianCut(
    List<MapEntry<int, List<int>>> samples,
    int maxColors,
  ) {
    if (samples.isEmpty) return [];
    if (maxColors < 1) maxColors = 1;
    var boxes = <List<MapEntry<int, List<int>>>>[samples];
    while (boxes.length < maxColors) {
      // Pick the box with the largest channel range that still has >1 colour.
      var pick = -1;
      var pickRange = 0;
      var pickChannel = 0;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        if (box.length < 2) continue;
        final range = _widestChannel(box, outChannel: (ch) => ch);
        if (range.max > pickRange) {
          pickRange = range.max;
          pickChannel = range.channel;
          pick = i;
        }
      }
      if (pick < 0 || pickRange == 0) break;
      final box = boxes.removeAt(pick);
      final shift = pickChannel == 0 ? 10 : (pickChannel == 1 ? 5 : 0);
      box.sort((a, b) =>
          ((a.key >> shift) & 31).compareTo((b.key >> shift) & 31));
      final total = box.fold<int>(0, (s, e) => s + e.value[0]);
      var acc = 0;
      var split = 0;
      for (var i = 0; i < box.length - 1; i++) {
        acc += box[i].value[0];
        split = i + 1;
        if (acc * 2 >= total) break;
      }
      if (split <= 0) split = 1;
      if (split >= box.length) split = box.length - 1;
      boxes.add(box.sublist(0, split));
      boxes.add(box.sublist(split));
    }
    return boxes;
  }

  static ({int channel, int max}) _widestChannel(
    List<MapEntry<int, List<int>>> box, {
    required int Function(int) outChannel,
  }) {
    var minR = 31, maxR = 0, minG = 31, maxG = 0, minB = 31, maxB = 0;
    for (final e in box) {
      final r = (e.key >> 10) & 31;
      final g = (e.key >> 5) & 31;
      final b = e.key & 31;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (g < minG) minG = g;
      if (g > maxG) maxG = g;
      if (b < minB) minB = b;
      if (b > maxB) maxB = b;
    }
    final dr = maxR - minR, dg = maxG - minG, db = maxB - minB;
    // Weight hue-perception channels a little so greens/blues split early.
    final wr = dr * 3, wg = dg * 4, wb = db * 2;
    if (wr >= wg && wr >= wb) return (channel: 0, max: wr);
    if (wg >= wb) return (channel: 1, max: wg);
    return (channel: 2, max: wb);
  }

  /// Serializes frames into a complete GIF89a byte stream.
  static Uint8List encode(
    List<GifFrameData> frames, {
    bool loop = true,
    int alphaThreshold = 128,
  }) {
    if (frames.isEmpty) return Uint8List(0);
    final width = frames.first.width;
    final height = frames.first.height;
    final palette = buildPalette(frames, alphaThreshold: alphaThreshold);
    final out = BytesBuilder();
    out.add(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]); // "GIF89a"
    _writeShort(out, width);
    _writeShort(out, height);
    var tableBits = 1;
    while ((1 << tableBits) < palette.length) {
      tableBits++;
    }
    out.addByte(0xF0 | (tableBits - 1)); // global table, 8-bit colour res
    out.addByte(0); // background index
    out.addByte(0); // default pixel aspect ratio
    out.add(palette.colors);

    if (loop) {
      out.add(const [0x21, 0xFF, 0x0B]);
      out.add('NETSCAPE2.0'.codeUnits);
      out.add(const [0x03, 0x01]);
      _writeShort(out, 0); // 0 = loop forever
      out.addByte(0);
    }

    final transparent = palette.transparentIndex >= 0;
    for (final frame in frames) {
      final indices =
          palette.indicesFor(frame.rgba, alphaThreshold: alphaThreshold);
      final delay = frame.delayCs < 2 ? 2 : frame.delayCs;
      // Graphic control extension.
      out.add(const [0x21, 0xF9, 0x04]);
      final disposal = transparent ? 2 : 1;
      out.addByte((disposal << 2) | (transparent ? 1 : 0));
      _writeShort(out, delay);
      out.addByte(transparent ? palette.transparentIndex : 0);
      out.addByte(0);
      // Image descriptor: full frame, no local table, not interlaced.
      out.addByte(0x2C);
      _writeShort(out, 0);
      _writeShort(out, 0);
      _writeShort(out, frame.width);
      _writeShort(out, frame.height);
      out.addByte(0x00);
      out.addByte(8); // LZW minimum code size
      // lzwEncode already frames the data in sub-blocks and terminates it.
      out.add(lzwEncode(indices, 8));
    }
    out.addByte(0x3B); // trailer
    return out.toBytes();
  }

  static void _writeShort(BytesBuilder out, int value) {
    out.addByte(value & 0xFF);
    out.addByte((value >> 8) & 0xFF);
  }

  /// GIF-flavoured LZW, returned as sub-block-framed bytes (length-prefixed
  /// chunks capped at 255, terminated by a zero-length block).
  static Uint8List lzwEncode(List<int> indices, int minCodeSize) {
    final clearCode = 1 << minCodeSize;
    final endCode = clearCode + 1;
    var codeSize = minCodeSize + 1;
    var maxCode = (1 << codeSize) - 1;
    var freeEntry = endCode + 1;
    var dictionary = <int, int>{};
    var clearPending = false;

    final bytes = <int>[];
    var accumulator = 0;
    var accumulatorBits = 0;

    void writeCode(int code) {
      // A pending clear restores the initial code width *before* the next code
      // is written; the clear code itself still used the full width.
      if (clearPending) {
        codeSize = minCodeSize + 1;
        maxCode = (1 << codeSize) - 1;
        clearPending = false;
      }
      accumulator |= (code << accumulatorBits);
      accumulatorBits += codeSize;
      while (accumulatorBits >= 8) {
        bytes.add(accumulator & 0xFF);
        accumulator >>= 8;
        accumulatorBits -= 8;
      }
      if (freeEntry > maxCode && codeSize < 12) {
        // The decoder widens its codes at the same table position, so the
        // width bump applies to codes written from here on.
        codeSize++;
        maxCode = (1 << codeSize) - 1;
      }
    }

    void reset() {
      dictionary = <int, int>{};
      freeEntry = endCode + 1;
    }

    writeCode(clearCode);
    if (indices.isEmpty) {
      writeCode(endCode);
    } else {
      var prefix = indices[0];
      for (var i = 1; i < indices.length; i++) {
        final k = indices[i];
        final key = (prefix << minCodeSize) | k;
        final found = dictionary[key];
        if (found != null) {
          prefix = found;
          continue;
        }
        writeCode(prefix);
        if (freeEntry < 4096) {
          dictionary[key] = freeEntry++;
        } else {
          // Table full: restart both sides of the conversation.
          writeCode(clearCode);
          clearPending = true;
          reset();
        }
        prefix = k;
      }
      writeCode(prefix);
      writeCode(endCode);
    }
    if (accumulatorBits > 0) bytes.add(accumulator & 0xFF);

    // Frame the code stream in GIF sub-blocks.
    final out = BytesBuilder();
    for (var i = 0; i < bytes.length; i += 255) {
      final end = (i + 255) > bytes.length ? bytes.length : i + 255;
      out.addByte(end - i);
      out.add(bytes.sublist(i, end));
    }
    out.addByte(0);
    return out.toBytes();
  }
}
