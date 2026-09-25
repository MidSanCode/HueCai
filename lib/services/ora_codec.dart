import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/canvas_settings.dart';
import '../models/layer.dart';
import '../models/project.dart';
import 'lgdf_codec.dart';

/// OpenRaster (.ora) import/export.
///
/// An ORA file is a ZIP container with a `stack.xml` layer description and
/// one PNG per layer. This codec exports every layer as a flattened bitmap
/// and imports layer bitmaps back with their name, opacity, visibility and
/// (mapped) blend mode.
class OraCodec {
  OraCodec._();

  static const extension = '.ora';

  /// ORA composite-op → our blend mode mapping (best effort).
  static BlendModeExt _blendFromOra(String? op) => switch (op) {
        'svg:multiply' => BlendModeExt.multiply,
        'svg:screen' => BlendModeExt.screen,
        'svg:overlay' => BlendModeExt.overlay,
        'svg:darken' => BlendModeExt.darken,
        'svg:lighten' => BlendModeExt.lighten,
        'svg:color-dodge' => BlendModeExt.colorDodge,
        'svg:color-burn' => BlendModeExt.colorBurn,
        'svg:hard-light' => BlendModeExt.hardLight,
        'svg:soft-light' => BlendModeExt.softLight,
        'svg:difference' => BlendModeExt.difference,
        'svg:hue' => BlendModeExt.hue,
        'svg:saturation' => BlendModeExt.saturation,
        'svg:color' => BlendModeExt.color,
        'svg:luminosity' => BlendModeExt.luminosity,
        _ => BlendModeExt.normal,
      };

  static String _blendToOra(BlendModeExt mode) => switch (mode) {
        BlendModeExt.multiply => 'svg:multiply',
        BlendModeExt.screen => 'svg:screen',
        BlendModeExt.overlay => 'svg:overlay',
        BlendModeExt.darken => 'svg:darken',
        BlendModeExt.lighten => 'svg:lighten',
        BlendModeExt.colorDodge => 'svg:color-dodge',
        BlendModeExt.colorBurn => 'svg:color-burn',
        BlendModeExt.hardLight => 'svg:hard-light',
        BlendModeExt.softLight => 'svg:soft-light',
        BlendModeExt.difference => 'svg:difference',
        BlendModeExt.hue => 'svg:hue',
        BlendModeExt.saturation => 'svg:saturation',
        BlendModeExt.color => 'svg:color',
        BlendModeExt.luminosity => 'svg:luminosity',
        _ => 'svg:src-over',
      };

  /// Exports [project] to an ORA package at [path].
  static Future<void> writePackage(String path, Project project) async {
    final w = project.settings.width;
    final h = project.settings.height;
    final archive = Archive();

    // mimetype must be the first entry and stored uncompressed.
    archive.addFile(ArchiveFile.noCompress(
      'mimetype',
      15,
      Uint8List.fromList('image/openraster'.codeUnits),
    ));

    // One PNG per layer. ORA layer order: stack.xml lists top layer first.
    final layerPngs = <String>[];
    for (var i = project.layers.length - 1; i >= 0; i--) {
      final layer = project.layers[i];
      final png = await LgdfCodec.renderLayerToPng(layer, w, h);
      final name = 'data/layer${layerPngs.length}.png';
      layerPngs.add(name);
      archive.addFile(ArchiveFile(name, png?.length ?? 0, png ?? Uint8List(0)));
    }

    // stack.xml
    final builder = XmlBuilder();
    builder.element('image', attributes: {'w': '$w', 'h': '$h'}, nest: () {
      builder.element('stack', nest: () {
        var i = 0;
        for (var li = project.layers.length - 1; li >= 0; li--, i++) {
          final layer = project.layers[li];
          builder.element('layer', attributes: {
            'name': layer.name,
            'src': layerPngs[i],
            'opacity': layer.opacity.toStringAsFixed(3),
            'visibility': layer.visible ? 'visible' : 'hidden',
            'composite-op': _blendToOra(layer.blendMode),
          });
        }
      });
    });
    final stackXml = builder.buildDocument().toXmlString(pretty: true);
    final stackBytes = Uint8List.fromList(utf8.encode(stackXml));
    archive.addFile(ArchiveFile('stack.xml', stackBytes.length, stackBytes));

    // Merged image (flattened composite).
    final merged = await _renderMergedPng(project, w, h);
    if (merged != null) {
      archive.addFile(ArchiveFile('mergedimage.png', merged.length, merged));
    }

    final encoded = ZipEncoder().encode(archive);
    await File(path).writeAsBytes(encoded);
  }

  /// Reads an ORA package and builds a project from it. Returns null when
  /// the file is not a valid ORA package.
  static Future<Project?> readPackage(String path) async {
    final bytes = await File(path).readAsBytes();
    return readBytes(bytes, name: _basename(path));
  }

  /// Bytes-level import (used by tests).
  static Future<Project?> readBytes(Uint8List bytes,
      {String name = 'imported'}) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final stackEntry = archive.findFile('stack.xml');
    if (stackEntry == null) return null;

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(utf8.decode(stackEntry.content));
    } catch (_) {
      return null;
    }

    final imageEl = doc.findAllElements('image').firstOrNull;
    final w = int.tryParse(imageEl?.getAttribute('w') ?? '') ?? 1024;
    final h = int.tryParse(imageEl?.getAttribute('h') ?? '') ?? 1024;

    // stack.xml lists layers top-first; our model is bottom-first.
    final layerEls = doc.findAllElements('layer').toList();
    final layers = <Layer>[];
    for (var i = layerEls.length - 1; i >= 0; i--) {
      final el = layerEls[i];
      final src = el.getAttribute('src');
      ui.Image? image;
      if (src != null) {
        final entry = archive.findFile(src);
        if (entry != null) {
          image = await _decodePng(Uint8List.fromList(entry.content));
        }
      }
      layers.add(Layer(
        id: 'ora_$i',
        name: el.getAttribute('name') ?? 'Layer ${layerEls.length - i}',
        opacity:
            (double.tryParse(el.getAttribute('opacity') ?? '') ?? 1.0).clamp(0.0, 1.0),
        visible: el.getAttribute('visibility') != 'hidden',
        blendMode: _blendFromOra(el.getAttribute('composite-op')),
        image: image,
      ));
    }
    if (layers.isEmpty) return null;

    return Project(
      id: 'ora_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      settings: CanvasSettings(width: w, height: h),
      layers: layers,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  static Future<ui.Image?> _decodePng(Uint8List png) async {
    try {
      final codec = await ui.instantiateImageCodec(png);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _renderMergedPng(Project p, int w, int h) async {
    // Flatten via the history-service snapshot path used by LGDF thumbnails:
    // render every visible layer into one picture.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final layer in p.layers) {
      if (!layer.visible) continue;
      final png = await LgdfCodec.renderLayerToPng(layer, w, h);
      if (png == null) continue;
      final img = await _decodePng(png);
      if (img == null) continue;
      canvas.saveLayer(
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()
          ..color = ui.Color.fromARGB((layer.opacity * 255).round(), 255, 255, 255)
          ..blendMode = layer.blendMode.toFlutterBlendMode(),
      );
      canvas.drawImage(img, ui.Offset.zero, ui.Paint());
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static String _basename(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
