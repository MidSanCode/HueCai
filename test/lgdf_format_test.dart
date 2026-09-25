import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/drawable.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/lgdf_codec.dart';
import 'package:hue_cai/services/project_service.dart';

Project _project({String name = 'My Drawing'}) => Project(
      id: 'proj-1',
      name: name,
      settings: const CanvasSettings(width: 64, height: 48),
      layers: [
        Layer(
          id: 'l1',
          name: 'Background',
          drawables: [
            Drawable(
              id: 'd1',
              points: const [Offset.zero, Offset(20, 20)],
              color: const Color(0xFF112233),
              strokeWidth: 3,
            ),
          ],
        ),
        Layer(id: 'l2', name: 'Layer 2'),
      ],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000100000),
      filePath: null,
      currentLayerIndex: 1,
    );

/// Unpacks a written `.hcproj` back into an entry map for inspection.
Map<String, Uint8List> _entriesOf(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = <String, Uint8List>{};
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final c = f.content;
    out[f.name] = c is Uint8List ? c : Uint8List.fromList(c);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LGDF structure', () {
    test('emits the required top-level entries', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());

      expect(entries.keys, contains('info.json'));
      expect(entries.keys, contains('registry.json'));
      expect(entries.keys, contains('spec/config.json'));
      // At least one asset + its metadata twin under the mandatory dirs.
      expect(
        entries.keys.any((k) => k.startsWith('assets/layers/') && !k.endsWith('.json')),
        isTrue,
      );
      // Metadata mirrors assets/ under metadata/ (standard §7.1).
      expect(
        entries.keys.any((k) => k.startsWith('metadata/') && k.endsWith('.json')),
        isTrue,
      );
      expect(entries.keys, contains('metadata/layers/layer_0.png.json'));
    });

    test('info.json follows the standard fields', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      final info = jsonDecode(utf8.decode(entries['info.json']!)) as Map<String, dynamic>;

      expect(info['format'], 'lgdf');
      expect(info['min_sdk'], isA<int>());
      expect(info['version'], isA<int>());
      expect(info['created_time'], isA<int>());
      expect(info['last_update_time'], isA<int>());
      // name must satisfy ^[a-z0-9_-]+$
      expect(info['name'], matches(RegExp(r'^[a-z0-9_-]+$')));
      expect(
        info['last_update_time'] as int,
        greaterThanOrEqualTo(info['created_time'] as int),
      );
    });

    test('spec/config.json preserves drawing data', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      final config =
          jsonDecode(utf8.decode(entries['spec/config.json']!)) as Map<String, dynamic>;

      expect(config['project']['display_name'], 'My Drawing');
      expect(config['project']['current_layer_index'], 1);
      expect(config['canvas']['width'], 64);
      expect(config['canvas']['height'], 48);
      expect((config['layers'] as List), hasLength(2));
      final first = (config['layers'] as List).first as Map<String, dynamic>;
      expect(first['name'], 'Background');
      expect((first['drawables'] as List), hasLength(1));
    });

    test('passes the standard validation pass', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      expect(LgdfCodec.validate(entries), isEmpty);
    });

    test('metadata sha256 and size match the asset bytes', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      final registry =
          jsonDecode(utf8.decode(entries['registry.json']!)) as Map<String, dynamic>;
      final registered = (registry['registered_files'] as List).cast<String>();
      expect(registry['asset_count'], registered.length);

      for (final path in registered) {
        final asset = entries[path]!;
        final metaPath = 'metadata/${path.substring('assets/'.length)}.json';
        final meta = jsonDecode(utf8.decode(entries[metaPath]!)) as Map<String, dynamic>;
        expect(meta['path'], path);
        expect(meta['size'], asset.length);
        expect(meta['sha256'], sha256.convert(asset).toString());
      }
    });
  });

  group('validation catches malformed projects', () {
    test('detects a tampered asset hash', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      entries['assets/layers/layer_0.png'] = Uint8List.fromList([1, 2, 3]);
      final problems = LgdfCodec.validate(entries);
      expect(problems.any((p) => p.contains('mismatch')), isTrue);
    });

    test('detects an unregistered asset', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      entries['assets/stray.bin'] = Uint8List.fromList([9]);
      final problems = LgdfCodec.validate(entries);
      expect(problems.any((p) => p.contains('unregistered asset')), isTrue);
    });

    test('detects a wrong format id', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      entries['info.json'] = utf8.encode(jsonEncode({
        'format': 'something-else',
        'min_sdk': 1,
        'name': 'x',
        'created_time': 1,
        'version': 1,
      }));
      final problems = LgdfCodec.validate(entries);
      expect(problems.any((p) => p.contains('format')), isTrue);
    });

    test('detects an invalid project name', () async {
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      final info = jsonDecode(utf8.decode(entries['info.json']!)) as Map<String, dynamic>;
      info['name'] = 'Bad Name!';
      entries['info.json'] = utf8.encode(jsonEncode(info));
      final problems = LgdfCodec.validate(entries);
      expect(problems.any((p) => p.contains('name')), isTrue);
    });
  });

  group('name sanitisation', () {
    test('lowercases and replaces disallowed characters', () {
      expect(LgdfCodec.sanitizeName('My Drawing'), 'my-drawing');
      expect(LgdfCodec.sanitizeName('  A  B  '), 'a-b');
      expect(LgdfCodec.sanitizeName('中文名字'), 'untitled');
      expect(LgdfCodec.sanitizeName(''), 'untitled');
      expect(LgdfCodec.sanitizeName('a__b-c'), matches(RegExp(r'^[a-z0-9_-]+$')));
    });
  });

  group('package round-trip', () {
    test('writePackage then readPackage preserves the drawing', () async {
      final dir = await Directory.systemTemp.createTemp('huecai_lgdf');
      final path = '${dir.path}/drawing${LgdfCodec.extension}';
      final project = _project();

      await LgdfCodec.writePackage(path, project, HistoryService());
      expect(await File(path).exists(), isTrue);
      // The standard requires a companion checksum file on export.
      expect(await File('$path.sha256').exists(), isTrue);

      final loaded = await LgdfCodec.readPackage(path);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'My Drawing');
      expect(loaded.settings.width, 64);
      expect(loaded.settings.height, 48);
      expect(loaded.layers, hasLength(2));
      expect(loaded.currentLayerIndex, 1);
      // Vector strokes survive via spec/config.json.
      expect(loaded.layers.first.drawables, hasLength(1));
      expect(loaded.layers.first.drawables.first.color, const Color(0xFF112233));
      // Layer pixels are restored from assets/layers/.
      expect(loaded.layers.first.image, isNotNull);

      await dir.delete(recursive: true);
    });

    test('writeDirectory then readDirectory preserves the drawing', () async {
      final dir = await Directory.systemTemp.createTemp('huecai_lgdf_dir');
      final path = '${dir.path}/drawing${LgdfCodec.directorySuffix}';
      final project = _project();

      await LgdfCodec.writeDirectory(path, project, HistoryService());
      expect(await File('$path/info.json').exists(), isTrue);
      expect(await File('$path/registry.json').exists(), isTrue);
      expect(await Directory('$path/assets').exists(), isTrue);
      expect(await Directory('$path/metadata').exists(), isTrue);

      final loaded = await LgdfCodec.readDirectory(path);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'My Drawing');
      expect(loaded.layers, hasLength(2));

      await dir.delete(recursive: true);
    });

    test('readPackage rejects a ZIP that is not an LGDF container', () async {
      final dir = await Directory.systemTemp.createTemp('huecai_lgdf_bad');
      final path = '${dir.path}/bad${LgdfCodec.extension}';
      final archive = Archive()
        ..addFile(ArchiveFile('random.txt', 2, utf8.encode('hi')));
      await File(path).writeAsBytes(ZipEncoder().encode(archive));

      expect(await LgdfCodec.readPackage(path), isNull);
      await dir.delete(recursive: true);
    });

    test('readPackage ignores zip-slip entries', () async {
      final dir = await Directory.systemTemp.createTemp('huecai_lgdf_slip');
      final path = '${dir.path}/slip${LgdfCodec.extension}';
      final entries = await LgdfCodec.buildEntries(_project(), HistoryService());
      final archive = Archive();
      for (final e in entries.entries) {
        archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
      }
      archive.addFile(ArchiveFile('../../evil.txt', 4, utf8.encode('bad!')));
      await File(path).writeAsBytes(ZipEncoder().encode(archive));

      // The escape attempt must not break loading or be surfaced.
      final loaded = await LgdfCodec.readPackage(path);
      expect(loaded, isNotNull);
      expect(await File('${dir.parent.path}/evil.txt').exists(), isFalse);

      await dir.delete(recursive: true);
    });
  });

  group('ProjectService integration', () {
    test('recognises both new and legacy extensions', () {
      expect(ProjectService.isProjectPath('a.hcproj'), isTrue);
      expect(ProjectService.isProjectPath('a.HCPROJ'), isTrue);
      expect(ProjectService.isProjectPath('a.hcp'), isTrue);
      expect(ProjectService.isProjectPath('a.png'), isFalse);
      expect(ProjectService.readableExtensionNames, contains('hcproj'));
      expect(ProjectService.readableExtensionNames, contains('hcp'));
    });

    test('saveProject writes an LGDF package with .hcproj default', () async {
      final service = ProjectService();
      final dir = await Directory.systemTemp.createTemp('huecai_svc');
      final path = '${dir.path}/saved${LgdfCodec.extension}';
      final project = _project();

      await service.saveProject(project, HistoryService(), filePath: path);
      expect(project.filePath, path);

      final entries = _entriesOf(await File(path).readAsBytes());
      expect(entries.keys, contains('info.json'));
      expect(entries.keys, contains('registry.json'));
      expect(LgdfCodec.validate(entries), isEmpty);

      final reloaded = await service.loadProject(path);
      expect(reloaded, isNotNull);
      expect(reloaded!.name, 'My Drawing');

      await dir.delete(recursive: true);
    });

    test('uniquePath keeps .hcproj and adds a counter', () async {
      final service = ProjectService();
      final dir = await Directory.systemTemp.createTemp('huecai_uniq');
      final first = '${dir.path}/p${LgdfCodec.extension}';
      await File(first).writeAsBytes([1]);

      final next = await service.uniquePath(first);
      expect(next, endsWith('p(1).hcproj'));

      await dir.delete(recursive: true);
    });

    test('legacy .hcp archives still load and re-save as .hcproj', () async {
      final service = ProjectService();
      final dir = await Directory.systemTemp.createTemp('huecai_legacy');
      final project = _project();

      // Build a legacy container by hand: project.json + layer_meta.json.
      final archive = Archive();
      final projectJson = utf8.encode(jsonEncode(project.toJson()));
      archive.addFile(
        ArchiveFile('project.json', projectJson.length, projectJson),
      );
      final metaBytes = utf8.encode(
        jsonEncode(project.layers.map((l) => l.toJson()).toList()),
      );
      archive.addFile(
        ArchiveFile('layer_meta.json', metaBytes.length, metaBytes),
      );

      final legacyPath = '${dir.path}/old.hcp';
      await File(legacyPath).writeAsBytes(ZipEncoder().encode(archive));

      final loaded = await service.loadProject(legacyPath);
      expect(loaded, isNotNull, reason: 'legacy .hcp must remain readable');
      expect(loaded!.name, 'My Drawing');
      expect(loaded.layers, hasLength(2));

      // Re-saving migrates it to the LGDF package format.
      final newPath = '${dir.path}/migrated${LgdfCodec.extension}';
      await service.saveProject(loaded, HistoryService(), filePath: newPath);
      final entries = _entriesOf(await File(newPath).readAsBytes());
      expect(entries.keys, contains('info.json'));
      expect(LgdfCodec.validate(entries), isEmpty);

      await dir.delete(recursive: true);
    });
  });

  group('lgdf example conformance', () {
    test('our reader accepts the reference example layout', () async {
      // Mirrors temp/example: info.json + registry.json + assets + metadata.
      final dir = await Directory.systemTemp.createTemp('huecai_ref');
      final root = '${dir.path}/example';
      Directory(root).createSync(recursive: true);

      final png = await _tinyPng();
      final assetPath = 'assets/images/c.png';
      File('$root/info.json').writeAsStringSync(const JsonEncoder.withIndent('\t').convert({
        'format': 'lgdf',
        'min_sdk': 1,
        'name': 'example',
        'display_name': 'LGDF 示例工程',
        'created_time': 1788963970,
        'last_update_time': 1789193378,
        'version': 1,
      }));
      File('$root/registry.json').writeAsStringSync(const JsonEncoder.withIndent('\t').convert({
        'registered_files': [assetPath],
        'asset_count': 1,
      }));
      Directory('$root/${File(assetPath).parent.path}').createSync(recursive: true);
      File('$root/$assetPath').writeAsBytesSync(png);
      // Metadata mirrors the asset path under metadata/.
      final metaPath = 'metadata/${assetPath.substring('assets/'.length)}.json';
      Directory('$root/${File(metaPath).parent.path}').createSync(recursive: true);
      File('$root/$metaPath').writeAsStringSync(
        const JsonEncoder.withIndent('\t').convert({
          'path': assetPath,
          'type': 'image',
          'mime': 'image/png',
          'format': 'png',
          'size': png.length,
          'sha256': sha256.convert(png).toString(),
          'hash_algorithm': 'sha256',
          'created_time': 1789193378,
          'last_update_time': 1789193378,
          'width': 4,
          'height': 4,
        }),
      );

      // The example has no spec/, so our reader should still identify it...
      final entries = <String, Uint8List>{};
      await for (final e in Directory(root).list(recursive: true)) {
        if (e is File) {
          entries[e.path.substring(root.length + 1).replaceAll('\\', '/')] =
              e.readAsBytesSync();
        }
      }
      expect(LgdfCodec.validate(entries), isEmpty);

      await dir.delete(recursive: true);
    });
  });
}

/// A 4x4 transparent PNG for the conformance fixture.
Future<Uint8List> _tinyPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 4, 4));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFF00FF00),
  );
  final img = await recorder.endRecording().toImage(4, 4);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
