import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'gif_encoder.dart';

/// Writes an animation out of the app.
///
/// Format support is deliberately honest: there is no video encoder bundled
/// (no ffmpeg, no extra package), so export produces an **animated GIF** and a
/// **PNG frame sequence**, both of which can be turned into a video by any
/// external tool (or loaded straight into a video editor as an image
/// sequence).
class AnimationExport {
  /// Encodes rasterized frames into an animated GIF byte stream.
  static Future<Uint8List> encodeGif(
    List<ui.Image> frames,
    int fps, {
    bool loop = true,
  }) async {
    if (frames.isEmpty) return Uint8List(0);
    final delayCs = (100 / (fps <= 0 ? 12 : fps)).round();
    final data = <GifFrameData>[];
    for (final frame in frames) {
      final byteData =
          await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) continue;
      data.add(GifFrameData(
        rgba: byteData.buffer.asUint8List(),
        width: frame.width,
        height: frame.height,
        delayCs: delayCs,
      ));
    }
    return GifEncoder.encode(data, loop: loop);
  }

  /// Writes an animated GIF to [path]. Returns the byte size written.
  static Future<int> writeGif(
    List<ui.Image> frames,
    int fps,
    String path, {
    bool loop = true,
  }) async {
    final bytes = await encodeGif(frames, fps, loop: loop);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return bytes.length;
  }

  /// Writes `frame_0001.png`, `frame_0002.png`, … into [directory].
  /// Returns the written paths.
  static Future<List<String>> writePngSequence(
    List<ui.Image> frames,
    String directory, {
    String prefix = 'frame',
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < frames.length; i++) {
      final byteData =
          await frames[i].toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) continue;
      final name = '${prefix}_${(i + 1).toString().padLeft(4, '0')}.png';
      final path = '${dir.path}${Platform.pathSeparator}$name';
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
      paths.add(path);
    }
    return paths;
  }
}
