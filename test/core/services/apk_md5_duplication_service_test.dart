import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:z1_engine/core/services/apk_md5_duplication_service.dart';

void main() {
  late Directory tempDirectory;
  late ApkMd5DuplicationService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('apk_md5_dup_');
    service = ApkMd5DuplicationService();
  });

  tearDown(() async {
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('returns full similarity for identical APK contents', () async {
    final firstApk = await _writeApk(tempDirectory, 'first.apk', {
      'AndroidManifest.xml': utf8.encode('<manifest />'),
      'res/drawable/icon.png': [1, 2, 3],
    });
    final secondApk = await _writeApk(tempDirectory, 'second.apk', {
      'AndroidManifest.xml': utf8.encode('<manifest />'),
      'res/drawable/icon.png': [1, 2, 3],
    });

    final result = await service.compare(
      firstApkPath: firstApk.path,
      secondApkPath: secondApk.path,
    );

    expect(result.firstSnapshot.fileCount, 2);
    expect(result.secondSnapshot.fileCount, 2);
    expect(result.matchedMd5FileCount, 2);
    expect(result.md5Similarity, 1.0);
    expect(result.firstCoverage, 1.0);
    expect(result.secondCoverage, 1.0);
    expect(result.samePathSameMd5Count, 2);
    expect(result.samePathChangedMd5Count, 0);
  });

  test('reports changed and APK-only MD5 files', () async {
    final firstApk = await _writeApk(tempDirectory, 'first.apk', {
      'AndroidManifest.xml': utf8.encode('manifest-a'),
      'classes.dex': utf8.encode('dex-a'),
      'res/drawable/icon.png': [7, 8, 9],
    });
    final secondApk = await _writeApk(tempDirectory, 'second.apk', {
      'AndroidManifest.xml': utf8.encode('manifest-b'),
      'assets/extra.txt': utf8.encode('extra'),
      'res/drawable/icon.png': [7, 8, 9],
    });

    final result = await service.compare(
      firstApkPath: firstApk.path,
      secondApkPath: secondApk.path,
    );

    expect(result.matchedMd5FileCount, 1);
    expect(result.md5UnionFileCount, 5);
    expect(result.md5Similarity, moreOrLessEquals(0.2));
    expect(result.firstOnlyMd5FileCount, 2);
    expect(result.secondOnlyMd5FileCount, 2);
    expect(result.samePathSameMd5Count, 1);
    expect(result.samePathChangedMd5Count, 1);
    expect(result.changedPathSamples.single.path, 'AndroidManifest.xml');
  });

  test('matches identical file MD5 even when internal paths differ', () async {
    final firstApk = await _writeApk(tempDirectory, 'first.apk', {
      'res/raw/payload.bin': [1, 3, 5, 7],
    });
    final secondApk = await _writeApk(tempDirectory, 'second.apk', {
      'assets/payload-copy.bin': [1, 3, 5, 7],
    });

    final result = await service.compare(
      firstApkPath: firstApk.path,
      secondApkPath: secondApk.path,
    );

    expect(result.matchedMd5FileCount, 1);
    expect(result.md5Similarity, 1.0);
    expect(result.commonPathCount, 0);
    expect(result.matchedSamples.single.firstPath, 'res/raw/payload.bin');
    expect(result.matchedSamples.single.secondPath, 'assets/payload-copy.bin');
  });

  test('throws a readable exception for broken APK zip data', () async {
    final firstApk = File('${tempDirectory.path}/first.apk');
    await firstApk.writeAsString('not a zip');
    final secondApk = await _writeApk(tempDirectory, 'second.apk', {
      'AndroidManifest.xml': utf8.encode('<manifest />'),
    });

    expect(
      service.compare(
        firstApkPath: firstApk.path,
        secondApkPath: secondApk.path,
      ),
      throwsA(
        isA<ApkMd5DuplicationException>().having(
          (error) => error.message,
          'message',
          contains('APK 解包失败'),
        ),
      ),
    );
  });
}

Future<File> _writeApk(
  Directory directory,
  String name,
  Map<String, List<int>> files,
) async {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, entry.value));
  }

  final apkFile = File('${directory.path}/$name');
  final bytes = ZipEncoder().encodeBytes(archive);
  await apkFile.writeAsBytes(bytes, flush: true);
  return apkFile;
}
