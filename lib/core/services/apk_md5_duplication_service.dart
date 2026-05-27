import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

class ApkMd5DuplicationService {
  Future<ApkMd5DuplicationResult> compare({
    required String firstApkPath,
    required String secondApkPath,
    int sampleLimit = 8,
  }) async {
    final firstSnapshot = await _readApkSnapshot(firstApkPath);
    final secondSnapshot = await _readApkSnapshot(secondApkPath);

    return _buildResult(
      firstSnapshot: firstSnapshot,
      secondSnapshot: secondSnapshot,
      sampleLimit: sampleLimit,
    );
  }

  Future<ApkFileMd5Snapshot> _readApkSnapshot(String apkPath) async {
    final apkFile = File(apkPath);
    if (!apkFile.existsSync()) {
      throw ApkMd5DuplicationException('APK 文件不存在：$apkPath');
    }

    final input = InputFileStream(apkPath);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input);
      final files = <ApkFileMd5>[];

      for (final entry in archive.files) {
        if (!entry.isFile) {
          continue;
        }

        final normalizedPath = _normalizeArchivePath(entry.name);
        if (normalizedPath.isEmpty) {
          continue;
        }

        final bytes = entry.readBytes();
        if (bytes == null) {
          continue;
        }

        files.add(
          ApkFileMd5(
            path: normalizedPath,
            md5: md5.convert(bytes).toString(),
            sizeBytes: bytes.length,
          ),
        );
      }

      if (files.isEmpty) {
        throw ApkMd5DuplicationException('APK 解包失败：$apkPath，未发现任何文件');
      }

      files.sort((left, right) => left.path.compareTo(right.path));
      return ApkFileMd5Snapshot(apkPath: apkPath, files: files);
    } on ApkMd5DuplicationException {
      rethrow;
    } on ArchiveException catch (error) {
      throw ApkMd5DuplicationException('APK 解包失败：$apkPath，${error.message}');
    } on FileSystemException catch (error) {
      throw ApkMd5DuplicationException('APK 读取失败：${error.message}');
    } catch (error) {
      throw ApkMd5DuplicationException('APK 解包失败：$apkPath，$error');
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  ApkMd5DuplicationResult _buildResult({
    required ApkFileMd5Snapshot firstSnapshot,
    required ApkFileMd5Snapshot secondSnapshot,
    required int sampleLimit,
  }) {
    final firstMd5Counts = firstSnapshot.md5Counts;
    final secondMd5Counts = secondSnapshot.md5Counts;
    var matchedMd5FileCount = 0;

    for (final entry in firstMd5Counts.entries) {
      matchedMd5FileCount += min(entry.value, secondMd5Counts[entry.key] ?? 0);
    }

    final unionMd5FileCount =
        firstSnapshot.fileCount +
        secondSnapshot.fileCount -
        matchedMd5FileCount;
    final md5Similarity = unionMd5FileCount == 0
        ? 0.0
        : matchedMd5FileCount / unionMd5FileCount;
    final firstCoverage = firstSnapshot.fileCount == 0
        ? 0.0
        : matchedMd5FileCount / firstSnapshot.fileCount;
    final secondCoverage = secondSnapshot.fileCount == 0
        ? 0.0
        : matchedMd5FileCount / secondSnapshot.fileCount;

    final commonPaths =
        firstSnapshot.filesByPath.keys
            .where(secondSnapshot.filesByPath.containsKey)
            .toList()
          ..sort();
    final samePathSameMd5Files = <ApkSamePathMd5Pair>[];
    final samePathChangedMd5Files = <ApkSamePathMd5Pair>[];
    for (final path in commonPaths) {
      final firstFile = firstSnapshot.filesByPath[path]!;
      final secondFile = secondSnapshot.filesByPath[path]!;
      final pair = ApkSamePathMd5Pair(
        path: path,
        firstMd5: firstFile.md5,
        secondMd5: secondFile.md5,
      );
      if (firstFile.md5 == secondFile.md5) {
        samePathSameMd5Files.add(pair);
      } else {
        samePathChangedMd5Files.add(pair);
      }
    }

    final matchedSamples = _buildMatchedSamples(
      firstSnapshot,
      secondSnapshot,
      sampleLimit,
    );
    final firstOnlySamples = _buildOnlySamples(
      sourceFiles: firstSnapshot.files,
      targetMd5Counts: secondMd5Counts,
      sampleLimit: sampleLimit,
    );
    final secondOnlySamples = _buildOnlySamples(
      sourceFiles: secondSnapshot.files,
      targetMd5Counts: firstMd5Counts,
      sampleLimit: sampleLimit,
    );

    return ApkMd5DuplicationResult(
      firstSnapshot: firstSnapshot,
      secondSnapshot: secondSnapshot,
      matchedMd5FileCount: matchedMd5FileCount,
      md5UnionFileCount: unionMd5FileCount,
      md5Similarity: md5Similarity,
      firstCoverage: firstCoverage,
      secondCoverage: secondCoverage,
      commonPathCount: commonPaths.length,
      samePathSameMd5Count: samePathSameMd5Files.length,
      samePathChangedMd5Count: samePathChangedMd5Files.length,
      firstOnlyMd5FileCount: firstSnapshot.fileCount - matchedMd5FileCount,
      secondOnlyMd5FileCount: secondSnapshot.fileCount - matchedMd5FileCount,
      matchedSamples: matchedSamples,
      firstOnlySamples: firstOnlySamples,
      secondOnlySamples: secondOnlySamples,
      changedPathSamples: samePathChangedMd5Files.take(sampleLimit).toList(),
    );
  }

  List<ApkMd5MatchSample> _buildMatchedSamples(
    ApkFileMd5Snapshot firstSnapshot,
    ApkFileMd5Snapshot secondSnapshot,
    int sampleLimit,
  ) {
    final secondFilesByMd5 = <String, List<ApkFileMd5>>{};
    for (final file in secondSnapshot.files) {
      secondFilesByMd5.putIfAbsent(file.md5, () => []).add(file);
    }

    final samples = <ApkMd5MatchSample>[];
    for (final firstFile in firstSnapshot.files) {
      final secondFiles = secondFilesByMd5[firstFile.md5];
      if (secondFiles == null || secondFiles.isEmpty) {
        continue;
      }

      final secondFile = secondFiles.removeAt(0);
      samples.add(
        ApkMd5MatchSample(
          md5: firstFile.md5,
          sizeBytes: firstFile.sizeBytes,
          firstPath: firstFile.path,
          secondPath: secondFile.path,
        ),
      );
      if (samples.length >= sampleLimit) {
        break;
      }
    }

    return samples;
  }

  List<ApkFileMd5> _buildOnlySamples({
    required List<ApkFileMd5> sourceFiles,
    required Map<String, int> targetMd5Counts,
    required int sampleLimit,
  }) {
    final remainingTargetCounts = Map<String, int>.from(targetMd5Counts);
    final samples = <ApkFileMd5>[];

    for (final file in sourceFiles) {
      final remaining = remainingTargetCounts[file.md5] ?? 0;
      if (remaining > 0) {
        remainingTargetCounts[file.md5] = remaining - 1;
        continue;
      }

      samples.add(file);
      if (samples.length >= sampleLimit) {
        break;
      }
    }

    return samples;
  }

  String _normalizeArchivePath(String path) {
    var normalized = path.replaceAll(r'\', '/').trim();
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }

    return normalized;
  }
}

class ApkMd5DuplicationResult {
  const ApkMd5DuplicationResult({
    required this.firstSnapshot,
    required this.secondSnapshot,
    required this.matchedMd5FileCount,
    required this.md5UnionFileCount,
    required this.md5Similarity,
    required this.firstCoverage,
    required this.secondCoverage,
    required this.commonPathCount,
    required this.samePathSameMd5Count,
    required this.samePathChangedMd5Count,
    required this.firstOnlyMd5FileCount,
    required this.secondOnlyMd5FileCount,
    required this.matchedSamples,
    required this.firstOnlySamples,
    required this.secondOnlySamples,
    required this.changedPathSamples,
  });

  final ApkFileMd5Snapshot firstSnapshot;
  final ApkFileMd5Snapshot secondSnapshot;
  final int matchedMd5FileCount;
  final int md5UnionFileCount;
  final double md5Similarity;
  final double firstCoverage;
  final double secondCoverage;
  final int commonPathCount;
  final int samePathSameMd5Count;
  final int samePathChangedMd5Count;
  final int firstOnlyMd5FileCount;
  final int secondOnlyMd5FileCount;
  final List<ApkMd5MatchSample> matchedSamples;
  final List<ApkFileMd5> firstOnlySamples;
  final List<ApkFileMd5> secondOnlySamples;
  final List<ApkSamePathMd5Pair> changedPathSamples;
}

class ApkFileMd5Snapshot {
  ApkFileMd5Snapshot({required this.apkPath, required this.files});

  final String apkPath;
  final List<ApkFileMd5> files;

  late final Map<String, ApkFileMd5> filesByPath = {
    for (final file in files) file.path: file,
  };

  late final Map<String, int> md5Counts = _countMd5(files);

  int get fileCount => files.length;
  int get uniqueMd5Count => md5Counts.length;
  int get totalSizeBytes =>
      files.fold(0, (total, file) => total + file.sizeBytes);

  Map<String, int> _countMd5(List<ApkFileMd5> files) {
    final counts = <String, int>{};
    for (final file in files) {
      counts[file.md5] = (counts[file.md5] ?? 0) + 1;
    }

    return counts;
  }
}

class ApkFileMd5 {
  const ApkFileMd5({
    required this.path,
    required this.md5,
    required this.sizeBytes,
  });

  final String path;
  final String md5;
  final int sizeBytes;
}

class ApkMd5MatchSample {
  const ApkMd5MatchSample({
    required this.md5,
    required this.sizeBytes,
    required this.firstPath,
    required this.secondPath,
  });

  final String md5;
  final int sizeBytes;
  final String firstPath;
  final String secondPath;
}

class ApkSamePathMd5Pair {
  const ApkSamePathMd5Pair({
    required this.path,
    required this.firstMd5,
    required this.secondMd5,
  });

  final String path;
  final String firstMd5;
  final String secondMd5;
}

class ApkMd5DuplicationException implements Exception {
  const ApkMd5DuplicationException(this.message);

  final String message;

  @override
  String toString() => message;
}
