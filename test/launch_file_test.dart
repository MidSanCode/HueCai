import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_cai/services/launch_file_service.dart';

void main() {
  group('LaunchFileService', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('huecai_launch');
      LaunchFileService.resetForTest();
    });

    tearDown(() async {
      LaunchFileService.resetForTest();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<String> makeFile(String name) async {
      final f = File('${tmp.path}/$name');
      await f.writeAsBytes([0x50, 0x4B]);
      return f.path;
    }

    test('resolves a .hcproj argument to an absolute path', () async {
      final path = await makeFile('a.hcproj');
      final resolved = await LaunchFileService.resolve([path]);
      expect(resolved, isNotNull);
      expect(resolved, endsWith('a.hcproj'));
    });

    test('resolves a legacy .hcp argument', () async {
      final path = await makeFile('old.hcp');
      expect(await LaunchFileService.resolve([path]), isNotNull);
    });

    test('strips surrounding quotes from the path', () async {
      final path = await makeFile('quoted.hcproj');
      expect(await LaunchFileService.resolve(['"$path"']), isNotNull);
    });

    test('ignores runner flags and unrelated files', () async {
      final png = await makeFile('image.png');
      expect(await LaunchFileService.resolve([png]), isNull);
      expect(
        await LaunchFileService.resolve(['--enable-dart-profiling']),
        isNull,
      );
    });

    test('ignores paths that do not exist', () async {
      expect(
        await LaunchFileService.resolve(['${tmp.path}/missing.hcproj']),
        isNull,
      );
    });

    test('consume returns the path once, then null', () async {
      final path = await makeFile('once.hcproj');
      await LaunchFileService.resolve([path]);
      expect(LaunchFileService.consume(), isNotNull);
      expect(LaunchFileService.consume(), isNull);
    });

    test('resolve is cached for the session', () async {
      final path = await makeFile('cached.hcproj');
      await LaunchFileService.resolve([path]);
      // A second resolve with no args still returns the original path.
      expect(await LaunchFileService.resolve(const []), isNotNull);
    });
  });
}
