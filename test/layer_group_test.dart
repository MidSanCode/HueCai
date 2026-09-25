import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hue_cai/models/canvas_settings.dart';
import 'package:hue_cai/models/layer.dart';
import 'package:hue_cai/models/project.dart';
import 'package:hue_cai/providers/project_provider.dart';
import 'package:hue_cai/services/history_service.dart';
import 'package:hue_cai/services/lgdf_codec.dart';
import 'package:hue_cai/services/project_service.dart';

Project _project() => Project(
      id: 'p1',
      name: 'test',
      settings: const CanvasSettings(width: 32, height: 32),
      layers: [
        Layer(id: 'l1', name: 'one'),
        Layer(id: 'l2', name: 'two'),
        Layer(id: 'l3', name: 'three'),
        Layer(id: 'l4', name: 'four'),
      ],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // easy_localization's .tr() needs the localization machinery; in tests we
  // fall back to whatever it provides without loading assets.
  EasyLocalization.logger.enableBuildModes = [];

  group('Project.layerRuns', () {
    test('flat layers produce single runs', () {
      final p = _project();
      final runs = p.layerRuns();
      expect(runs.length, 4);
      expect(runs.every((r) => !r.isGroup), isTrue);
    });

    test('consecutive same-group layers collapse into one group run', () {
      final p = _project();
      final g = LayerGroup(id: 'g1', name: 'G');
      p.groups.add(g);
      p.layers[1].groupId = 'g1';
      p.layers[2].groupId = 'g1';

      final runs = p.layerRuns();
      expect(runs.length, 3);
      expect(runs[0].isGroup, isFalse);
      expect(runs[1].isGroup, isTrue);
      expect(runs[1].start, 1);
      expect(runs[1].end, 2);
      expect(runs[2].isGroup, isFalse);
    });

    test('unknown group id falls back to single runs', () {
      final p = _project();
      p.layers[0].groupId = 'ghost';
      expect(p.layerRuns().every((r) => !r.isGroup), isTrue);
    });

    test('effective visibility combines layer and group', () {
      final p = _project();
      final g = LayerGroup(id: 'g1', name: 'G', visible: false);
      p.groups.add(g);
      p.layers[1].groupId = 'g1';
      expect(p.isLayerEffectivelyVisible(p.layers[0]), isTrue);
      expect(p.isLayerEffectivelyVisible(p.layers[1]), isFalse);
    });
  });

  group('Project group serialization', () {
    test('toJson/fromJson round-trips groups and membership', () {
      final p = _project();
      p.groups.add(LayerGroup(
        id: 'g1',
        name: 'Folder',
        opacity: 0.5,
        blendMode: BlendModeExt.multiply,
        expanded: false,
      ));
      p.layers[2].groupId = 'g1';

      final restored = Project.fromJson(p.toJson());
      expect(restored.groups, hasLength(1));
      expect(restored.groups.first.name, 'Folder');
      expect(restored.groups.first.opacity, 0.5);
      expect(restored.groups.first.blendMode, BlendModeExt.multiply);
      expect(restored.groups.first.expanded, isFalse);
      expect(restored.layers[2].groupId, 'g1');
    });
  });

  group('ProjectProvider grouping', () {
    test('createGroupFromCurrentLayer groups the current layer', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      final gid = pp.createGroupFromCurrentLayer();
      expect(gid, isNotNull);
      final project = pp.currentProject!;
      expect(project.groups, hasLength(1));
      expect(project.currentLayer!.groupId, gid);
    });

    test('dissolveGroup keeps the layers', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      final before = pp.currentProject!.layers.length;
      final gid = pp.createGroupFromCurrentLayer()!;
      pp.dissolveGroup(gid);
      final project = pp.currentProject!;
      expect(project.groups, isEmpty);
      expect(project.layers, hasLength(before));
      expect(project.layers.every((l) => l.groupId == null), isTrue);
    });

    test('deleteGroup with deleteLayers removes members only', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      pp.addLayer();
      final gid = pp.createGroupFromCurrentLayer()!;
      final total = pp.currentProject!.layers.length;
      pp.deleteGroup(gid, deleteLayers: true);
      expect(pp.currentProject!.layers.length, total - 1);
      expect(pp.currentProject!.groups, isEmpty);
    });

    test('moveLayerToGroup inserts at the group top edge', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      // New projects start with a background layer plus one editable layer.
      final total = pp.currentProject!.layers.length;
      pp.addLayer(); // one more layer, now selected
      final gid = pp.createGroupFromCurrentLayer()!;
      pp.addLayer(); // joins the group (inherits groupId)
      // Move the bottom layer (index 0) into the group.
      pp.moveLayerToGroup(0, gid);
      final project = pp.currentProject!;
      final members = project.layers.where((l) => l.groupId == gid).toList();
      expect(members, hasLength(3));
      // Members stay contiguous.
      final indices = <int>[];
      for (var i = 0; i < project.layers.length; i++) {
        if (project.layers[i].groupId == gid) indices.add(i);
      }
      expect(indices.last - indices.first, indices.length - 1);
      expect(project.layers, hasLength(total + 2));
    });

    test('moving a layer out of a group keeps the block contiguous', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      final gid = pp.createGroupFromCurrentLayer()!;
      pp.addLayer();
      pp.addLayer();
      // All three are grouped; move the middle member below the block.
      pp.moveLayerDown(1);
      pp.moveLayerDown(1);
      final project = pp.currentProject!;
      final runs = project.layerRuns();
      // The group block and the escaped layer must each be single runs.
      for (final run in runs.where((r) => r.isGroup)) {
        for (var i = run.start; i <= run.end; i++) {
          expect(project.layers[i].groupId, gid);
        }
      }
      // No group id appears in two disjoint blocks.
      final indices = <int>[];
      for (var i = 0; i < project.layers.length; i++) {
        if (project.layers[i].groupId == gid) indices.add(i);
      }
      if (indices.isNotEmpty) {
        expect(indices.last - indices.first, indices.length - 1);
      }
    });

    test('addLayer inside a group inherits the group', () async {
      final pp = ProjectProvider();
      await pp.createNewProject(name: 't', width: 32, height: 32);
      final gid = pp.createGroupFromCurrentLayer()!;
      pp.addLayer();
      expect(pp.currentProject!.currentLayer!.groupId, gid);
    });
  });

  group('LGDF group persistence', () {
    test('groups and membership survive the package round-trip', () async {
      final project = _project();
      project.groups.add(LayerGroup(
        id: 'g1',
        name: 'Folder',
        opacity: 0.7,
        blendMode: BlendModeExt.screen,
      ));
      project.layers[1].groupId = 'g1';
      project.layers[2].groupId = 'g1';

      final dir = await Directory.systemTemp.createTemp('huecai_grp');
      final path = '${dir.path}/g${LgdfCodec.extension}';
      await LgdfCodec.writePackage(path, project, HistoryService());
      final loaded = await LgdfCodec.readPackage(path);

      expect(loaded, isNotNull);
      expect(loaded!.groups, hasLength(1));
      expect(loaded.groups.first.name, 'Folder');
      expect(loaded.groups.first.opacity, 0.7);
      expect(loaded.groups.first.blendMode, BlendModeExt.screen);
      expect(loaded.layers[1].groupId, 'g1');
      expect(loaded.layers[2].groupId, 'g1');
      expect(loaded.layers[0].groupId, isNull);

      await dir.delete(recursive: true);
    });

    test('legacy projects without groups still load', () async {
      final service = ProjectService();
      final project = _project();
      final dir = await Directory.systemTemp.createTemp('huecai_grp2');
      final path = '${dir.path}/plain${LgdfCodec.extension}';
      await service.saveProject(project, HistoryService(), filePath: path);
      final loaded = await service.loadProject(path);
      expect(loaded, isNotNull);
      expect(loaded!.groups, isEmpty);
      await dir.delete(recursive: true);
    });
  });
}
