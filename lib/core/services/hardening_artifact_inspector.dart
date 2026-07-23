import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:z1_engine/core/models/hardening_artifact.dart';

class HardeningArtifactInspector {
  Future<HardeningArtifactInspection> inspect(String path) async {
    final normalizedPath = path.trim();
    final file = File(normalizedPath);
    if (normalizedPath.isEmpty || !await file.exists()) {
      throw HardeningArtifactException('文件不存在：$normalizedPath');
    }

    final lowerPath = normalizedPath.toLowerCase();
    if (lowerPath.endsWith('.so')) {
      return _inspectSharedObject(file);
    }
    if (lowerPath.endsWith('.apk') || lowerPath.endsWith('.aab')) {
      return _inspectAndroidArchive(file);
    }

    throw const HardeningArtifactException('仅支持 APK、AAB 或 SO 文件');
  }

  Future<HardeningArtifactInspection> _inspectAndroidArchive(File file) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    } on ArchiveException {
      throw const HardeningArtifactException('文件不是有效的 ZIP/Android 产物');
    }

    final entryNames = archive.files
        .where((entry) => entry.isFile)
        .map((entry) => _normalizeArchivePath(entry.name))
        .toSet();
    final lowerPath = file.path.toLowerCase();
    final isApk = entryNames.contains('AndroidManifest.xml');
    final isAab =
        entryNames.contains('BundleConfig.pb') &&
        entryNames.any(
          (name) =>
              name.split('/').length == 3 &&
              name.endsWith('/manifest/AndroidManifest.xml'),
        );

    if (isApk == isAab) {
      throw const HardeningArtifactException('无法识别 Android 产物结构');
    }
    if (isApk && !lowerPath.endsWith('.apk')) {
      throw const HardeningArtifactException('文件内容是 APK，但后缀不是 .apk');
    }
    if (isAab && !lowerPath.endsWith('.aab')) {
      throw const HardeningArtifactException('文件内容是 AAB，但后缀不是 .aab');
    }

    if (isApk) {
      return HardeningArtifactInspection(
        type: HardeningArtifactType.apk,
        path: file.absolute.path,
      );
    }

    final moduleNames =
        entryNames
            .where((name) => name.endsWith('/manifest/AndroidManifest.xml'))
            .map((name) => name.split('/').first)
            .toSet()
            .toList()
          ..sort();
    return HardeningArtifactInspection(
      type: HardeningArtifactType.aab,
      path: file.absolute.path,
      moduleNames: moduleNames,
    );
  }

  Future<HardeningArtifactInspection> _inspectSharedObject(File file) async {
    final randomAccessFile = await file.open();
    late Uint8List header;
    try {
      header = await randomAccessFile.read(64);
    } finally {
      await randomAccessFile.close();
    }

    if (header.length < 20 ||
        header[0] != 0x7f ||
        header[1] != 0x45 ||
        header[2] != 0x4c ||
        header[3] != 0x46) {
      throw const HardeningArtifactException('文件不是有效的 ELF 二进制');
    }

    final elfClass = header[4];
    final encoding = header[5];
    if ((elfClass != 1 && elfClass != 2) || (encoding != 1 && encoding != 2)) {
      throw const HardeningArtifactException('不支持的 ELF 格式');
    }

    final byteData = ByteData.sublistView(header);
    final endian = encoding == 1 ? Endian.little : Endian.big;
    final elfType = byteData.getUint16(16, endian);
    if (elfType != 3) {
      throw const HardeningArtifactException('ELF 不是共享库 ET_DYN');
    }

    final machine = byteData.getUint16(18, endian);
    final abi = switch (machine) {
      3 => 'x86',
      40 => 'armeabi-v7a',
      62 => 'x86_64',
      183 => 'arm64-v8a',
      _ => null,
    };
    if (abi == null) {
      throw HardeningArtifactException('不支持的 Android ELF machine：$machine');
    }

    return HardeningArtifactInspection(
      type: HardeningArtifactType.sharedObject,
      path: file.absolute.path,
      abi: abi,
    );
  }

  String _normalizeArchivePath(String path) {
    return path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
  }
}
