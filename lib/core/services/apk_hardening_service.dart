import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';

class ApkHardeningService {
  static const int _dexPartSizeBytes = 512 * 1024;
  static const String _guardApplicationName = 'com.z1.guard.Z1GuardApplication';
  static const String _guardProviderName = 'com.z1.guard.Z1GuardProvider';
  static const String _guardDexName = 'classes.dex';
  static const String _dexAssetDirectoryName = 'z1_guard/dex';

  Future<ApkHardeningDexPayloadTestResult> buildEncryptedDexPayloadForTesting({
    required Directory decodedDirectory,
    required List<File> dexFiles,
    required Uint8List xorKey,
    int partSizeBytes = _dexPartSizeBytes,
  }) async {
    final payload = await _writeEncryptedDexPayload(
      decodedDirectory: decodedDirectory,
      dexFiles: dexFiles,
      xorKey: xorKey,
      partSizeBytes: partSizeBytes,
    );
    return ApkHardeningDexPayloadTestResult(
      encodedConfig: payload.encodedConfig,
      partCount: payload.partCount,
      totalSizeBytes: payload.totalSizeBytes,
      totalSha256Hex: payload.totalSha256Hex,
      apkEntryNames: payload.apkEntryNames.toList(growable: false),
    );
  }

  Future<Map<String, Uint8List>> decryptDexPayloadForTesting({
    required Directory decodedDirectory,
    required String encodedConfig,
    required Uint8List xorKey,
  }) async {
    final text = utf8.decode(base64Url.decode(encodedConfig));
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) {
      throw const ApkHardeningException('DEX 分片配置为空');
    }

    final header = lines.first.split('|');
    if (header.length != 4 || header[0] != 'Z1DEXPROFILE' || header[1] != '1') {
      throw const ApkHardeningException('DEX 分片配置头异常');
    }
    final expectedTotalSize = int.parse(header[2]);
    final expectedTotalSha256 = header[3];
    final assetsDirectory = Directory(
      _joinPath(decodedDirectory.path, 'assets'),
    );
    final totalBytes = BytesBuilder(copy: false);
    final result = <String, Uint8List>{};

    for (final line in lines.skip(1)) {
      if (line.isEmpty) {
        continue;
      }
      final fields = line.split('|');
      if (fields.length != 4) {
        throw const ApkHardeningException('DEX 分片配置行异常');
      }
      final dexName = utf8.decode(base64Url.decode(fields[0]));
      final expectedSize = int.parse(fields[1]);
      final expectedSha256 = fields[2];
      final dexBytes = BytesBuilder(copy: false);
      for (final partText in fields[3].split(';')) {
        if (partText.isEmpty) {
          continue;
        }
        final partFields = partText.split(',');
        if (partFields.length != 3) {
          throw const ApkHardeningException('DEX 分片配置明细异常');
        }
        final assetName = utf8.decode(base64Url.decode(partFields[0]));
        final expectedPartSize = int.parse(partFields[1]);
        final expectedPartSha256 = partFields[2];
        final encryptedPart = await File(
          _joinPath(assetsDirectory.path, assetName),
        ).readAsBytes();
        if (encryptedPart.length != expectedPartSize ||
            sha256.convert(encryptedPart).toString() != expectedPartSha256) {
          throw const ApkHardeningException('DEX 加密分片摘要校验失败');
        }
        dexBytes.add(_xorBytes(encryptedPart, xorKey));
      }
      final plainDex = dexBytes.takeBytes();
      if (plainDex.length != expectedSize ||
          sha256.convert(plainDex).toString() != expectedSha256) {
        throw const ApkHardeningException('DEX 明文还原校验失败');
      }
      totalBytes.add(plainDex);
      result[dexName] = plainDex;
    }

    final plainTotalBytes = totalBytes.takeBytes();
    if (plainTotalBytes.length != expectedTotalSize ||
        sha256.convert(plainTotalBytes).toString() != expectedTotalSha256) {
      throw const ApkHardeningException('DEX 总摘要校验失败');
    }
    return result;
  }

  bool shouldIgnoreIntegrityEntryForTesting(
    String normalizedPath,
    Set<String> ignoredEntries,
  ) {
    return _shouldIgnoreIntegrityEntry(normalizedPath, ignoredEntries);
  }

  Uint8List encodeStorageProfileForTesting({
    required String packageName,
    required List<ApkHardeningStorageProfileEntryForTesting> entries,
    required Uint8List hmacKey,
    required Uint8List xorKey,
  }) {
    final sortedEntries = [...entries]
      ..sort((left, right) => left.path.compareTo(right.path));
    final body = StringBuffer()
      ..writeln(
        [
          'Z1STORAGEPROFILE',
          '1',
          base64Url.encode(utf8.encode(packageName)),
        ].join('|'),
      );

    for (final entry in sortedEntries) {
      body.writeln(
        [
          base64Url.encode(utf8.encode(entry.path)),
          entry.sizeBytes.toString(),
          entry.modifiedTimeMillis.toString(),
          entry.sha256Hex,
        ].join('|'),
      );
    }

    final bodyBytes = Uint8List.fromList(utf8.encode(body.toString()));
    final signature = Hmac(sha256, hmacKey).convert(bodyBytes).toString();
    final envelopeBytes = Uint8List.fromList(
      utf8.encode('Z1STORAGEWRAP|1|$signature\n') + bodyBytes,
    );
    return _xorBytes(envelopeBytes, xorKey);
  }

  bool verifyStorageProfileForTesting({
    required Uint8List protectedProfileBytes,
    required String packageName,
    required List<ApkHardeningStorageProfileEntryForTesting> expectedEntries,
    required Uint8List hmacKey,
    required Uint8List xorKey,
  }) {
    try {
      final envelope = utf8.decode(_xorBytes(protectedProfileBytes, xorKey));
      final newlineIndex = envelope.indexOf('\n');
      if (newlineIndex <= 0) {
        return false;
      }
      final envelopeHeader = envelope.substring(0, newlineIndex).split('|');
      if (envelopeHeader.length != 3 ||
          envelopeHeader[0] != 'Z1STORAGEWRAP' ||
          envelopeHeader[1] != '1') {
        return false;
      }

      final body = envelope.substring(newlineIndex + 1);
      final bodyBytes = Uint8List.fromList(utf8.encode(body));
      final expectedSignature = Hmac(
        sha256,
        hmacKey,
      ).convert(bodyBytes).toString();
      if (envelopeHeader[2].toLowerCase() != expectedSignature) {
        return false;
      }

      final lines = body.split(RegExp(r'\r?\n'));
      final bodyHeader = lines.first.split('|');
      if (bodyHeader.length != 3 ||
          bodyHeader[0] != 'Z1STORAGEPROFILE' ||
          bodyHeader[1] != '1' ||
          utf8.decode(base64Url.decode(bodyHeader[2])) != packageName) {
        return false;
      }

      final actualEntries =
          <String, ApkHardeningStorageProfileEntryForTesting>{};
      for (final line in lines.skip(1)) {
        if (line.isEmpty) {
          continue;
        }
        final fields = line.split('|');
        if (fields.length != 4) {
          return false;
        }
        final path = utf8.decode(base64Url.decode(fields[0]));
        actualEntries[path] = ApkHardeningStorageProfileEntryForTesting(
          path: path,
          sizeBytes: int.parse(fields[1]),
          modifiedTimeMillis: int.parse(fields[2]),
          sha256Hex: fields[3],
        );
      }

      final expectedByPath = {
        for (final entry in expectedEntries) entry.path: entry,
      };
      if (actualEntries.length != expectedByPath.length) {
        return false;
      }
      for (final expected in expectedByPath.entries) {
        final actual = actualEntries[expected.key];
        if (actual == null ||
            actual.sizeBytes != expected.value.sizeBytes ||
            actual.sha256Hex != expected.value.sha256Hex) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isStorageProfileEntryPathForTesting(String relativePath) {
    return _isStorageProfileEntryPath(relativePath);
  }

  Future<ApkHardeningResult> harden({
    required String sourceApkPath,
    required String outputApkPath,
    required AndroidSigningConfig signingConfig,
  }) async {
    final logs = <String>[];
    final sourceApk = File(sourceApkPath);
    if (!sourceApk.existsSync()) {
      throw ApkHardeningException('APK 文件不存在：$sourceApkPath');
    }

    final apktool = await _resolvePathExecutable('apktool');
    final javac = await _resolveJavac();
    final keytool = await _resolveJavaTool('keytool');
    final d8 = await _resolveBuildToolExecutable(
      configuredExecutable: '',
      executableName: 'd8',
    );
    final zipalign = await _resolveBuildToolExecutable(
      configuredExecutable: signingConfig.zipalignPath,
      executableName: 'zipalign',
    );
    final apksigner = await _resolveBuildToolExecutable(
      configuredExecutable: signingConfig.apksignerPath,
      executableName: 'apksigner',
    );
    final androidJar = _findLatestAndroidJar();
    if (androidJar == null) {
      throw const ApkHardeningException('未找到 Android SDK platform android.jar');
    }

    final workDirectory = await Directory.systemTemp.createTemp(
      'z1_apk_guard_',
    );
    final decodedDirectory = Directory(
      _joinPath(workDirectory.path, 'decoded'),
    );
    final guardSourceDirectory = Directory(
      _joinPath(workDirectory.path, 'guard_src'),
    );
    final guardClassesDirectory = Directory(
      _joinPath(workDirectory.path, 'guard_classes'),
    );
    final guardDexDirectory = Directory(
      _joinPath(workDirectory.path, 'guard_dex'),
    );
    final profileUnsignedApkPath = _joinPath(
      workDirectory.path,
      'profile_unsigned.apk',
    );
    final unsignedApkPath = _joinPath(workDirectory.path, 'unsigned.apk');
    final alignedApkPath = _joinPath(workDirectory.path, 'aligned.apk');

    try {
      logs.add('工作目录：${workDirectory.path}');
      logs.add('apktool：$apktool');
      logs.add('javac：$javac');
      logs.add('keytool：$keytool');
      logs.add('d8：$d8');
      logs.add('android.jar：$androidJar');

      await _runChecked(
        apktool,
        ['d', '-f', '-s', '-o', decodedDirectory.path, sourceApk.path],
        logs,
        label: 'apktool decode',
      );

      final manifestFile = File(
        _joinPath(decodedDirectory.path, 'AndroidManifest.xml'),
      );
      if (!manifestFile.existsSync()) {
        throw const ApkHardeningException('解包后未找到 AndroidManifest.xml');
      }

      final manifestContent = await manifestFile.readAsString();
      final packageName =
          _readPackageName(manifestContent) ??
          await _readPackageNameWithAapt(sourceApk.path);
      if (packageName == null || packageName.trim().isEmpty) {
        throw const ApkHardeningException('无法识别 APK packageName');
      }

      final minSdk = _readMinSdk(manifestContent);
      if (minSdk < 21) {
        logs.add('警告：minSdk=$minSdk。早启动 Provider 注入在 Android 5.0+ 最稳定。');
      }

      logs.add('目标包名：$packageName');
      logs.add('注入 dex：$_guardDexName');

      final manifestPatch = _injectGuardBootstrap(manifestContent, packageName);
      await manifestFile.writeAsString(manifestPatch.content);
      logs.add(
        'Manifest 原 Application：${manifestPatch.originalApplicationName}',
      );
      logs.add('Guard Application 注入结果：$_guardApplicationName');

      final originalDexFiles = _collectOriginalDexFiles(decodedDirectory);
      logs.add('原始 dex 数量：${originalDexFiles.length}');
      final dexXorKey = _secureRandomBytes(16);
      final storageHmacKey = _secureRandomBytes(32);
      final storageProfileXorKey = _secureRandomBytes(16);
      final dexPayload = await _writeEncryptedDexPayload(
        decodedDirectory: decodedDirectory,
        dexFiles: originalDexFiles,
        xorKey: dexXorKey,
        partSizeBytes: _dexPartSizeBytes,
      );
      logs.add('dex 分片数量：${dexPayload.partCount}（默认 512KB/片）');
      logs.add('DEX 加载策略：Android 8.0+ 内存加载；Android 5.0-7.x 私有 code_cache 临时加载');

      final expectedCertificateSha256 = await _readSigningCertificateSha256(
        keytoolExecutable: keytool,
        signingConfig: signingConfig,
      );
      logs.add('签名证书 SHA-256：${_shortDigest(expectedCertificateSha256)}');

      final profileAssetName = 'z1_guard/profile.dat';
      final profileApkEntryName = 'assets/$profileAssetName';
      final ignoredProfileEntries = {
        _guardDexName,
        profileApkEntryName,
        ...dexPayload.apkEntryNames,
      };
      final placeholderConfig = _GuardBuildConfig(
        expectedPackageName: packageName,
        expectedCertificateSha256: expectedCertificateSha256,
        guardDexName: _guardDexName,
        profileAssetName: profileAssetName,
        profileApkEntryName: profileApkEntryName,
        expectedProfileSha256: '',
        profileXorKeyHex: '',
        originalApplicationName: manifestPatch.originalApplicationName,
        dexPayloadConfig: dexPayload.encodedConfig,
        dexXorKeyHex: _bytesToHex(dexXorKey),
        storageHmacKeyHex: _bytesToHex(storageHmacKey),
        storageProfileXorKeyHex: _bytesToHex(storageProfileXorKey),
      );
      await _compileGuardDex(
        javac: javac,
        d8: d8,
        androidJar: androidJar,
        minSdk: minSdk,
        sourceDirectory: guardSourceDirectory,
        classesDirectory: guardClassesDirectory,
        dexDirectory: guardDexDirectory,
        config: placeholderConfig,
        logs: logs,
        labelSuffix: 'profile',
      );

      await _copyGuardDex(
        guardDexDirectory: guardDexDirectory,
        decodedDirectory: decodedDirectory,
        guardDexName: _guardDexName,
      );

      await _runChecked(
        apktool,
        ['b', '-f', '-o', profileUnsignedApkPath, decodedDirectory.path],
        logs,
        label: 'apktool build profile',
      );

      final integrityProfile = await _buildIntegrityProfile(
        apkPath: profileUnsignedApkPath,
        ignoredEntries: ignoredProfileEntries,
      );
      final plainProfileBytes = _encodeIntegrityProfile(
        packageName: packageName,
        guardDexName: _guardDexName,
        entries: integrityProfile.entries,
      );
      final profileXorKey = _secureRandomBytes(16);
      final protectedProfileBytes = _xorBytes(plainProfileBytes, profileXorKey);
      final expectedProfileSha256 = sha256
          .convert(protectedProfileBytes)
          .toString();
      await _writeProfileAsset(
        decodedDirectory: decodedDirectory,
        profileAssetName: profileAssetName,
        protectedProfileBytes: protectedProfileBytes,
      );
      logs.add('包体摘要基线：${integrityProfile.entries.length} 个条目');
      logs.add('全包产物 allowlist：未知 so/dex/asset/res/META-INF 非签名文件新增会阻断启动');
      logs.add('SP/数据库完整性保护：shared_prefs/databases 启动校验 + 运行时签名基线刷新');
      logs.add('基线资产 SHA-256：${_shortDigest(expectedProfileSha256)}');

      final finalConfig = _GuardBuildConfig(
        expectedPackageName: packageName,
        expectedCertificateSha256: expectedCertificateSha256,
        guardDexName: _guardDexName,
        profileAssetName: profileAssetName,
        profileApkEntryName: profileApkEntryName,
        expectedProfileSha256: expectedProfileSha256,
        profileXorKeyHex: _bytesToHex(profileXorKey),
        originalApplicationName: manifestPatch.originalApplicationName,
        dexPayloadConfig: dexPayload.encodedConfig,
        dexXorKeyHex: _bytesToHex(dexXorKey),
        storageHmacKeyHex: _bytesToHex(storageHmacKey),
        storageProfileXorKeyHex: _bytesToHex(storageProfileXorKey),
      );
      await _compileGuardDex(
        javac: javac,
        d8: d8,
        androidJar: androidJar,
        minSdk: minSdk,
        sourceDirectory: guardSourceDirectory,
        classesDirectory: guardClassesDirectory,
        dexDirectory: guardDexDirectory,
        config: finalConfig,
        logs: logs,
        labelSuffix: 'final',
      );
      await _copyGuardDex(
        guardDexDirectory: guardDexDirectory,
        decodedDirectory: decodedDirectory,
        guardDexName: _guardDexName,
      );

      await _runChecked(
        apktool,
        ['b', '-f', '-o', unsignedApkPath, decodedDirectory.path],
        logs,
        label: 'apktool build',
      );

      await File(outputApkPath).parent.create(recursive: true);
      await _runChecked(
        zipalign,
        ['-f', '-p', '4', unsignedApkPath, alignedApkPath],
        logs,
        label: 'zipalign',
      );

      await _runChecked(
        apksigner,
        _buildSigningArgs(signingConfig, alignedApkPath, outputApkPath, false),
        logs,
        label: 'apksigner sign',
        maskedCommandArgs: _buildSigningArgs(
          signingConfig,
          alignedApkPath,
          outputApkPath,
          true,
        ),
      );

      await _runChecked(
        apksigner,
        ['verify', '--verbose', '--print-certs', outputApkPath],
        logs,
        label: 'apksigner verify',
      );

      final finalProfile = await _buildIntegrityProfile(
        apkPath: outputApkPath,
        ignoredEntries: ignoredProfileEntries,
      );
      final finalProfileBytes = _encodeIntegrityProfile(
        packageName: packageName,
        guardDexName: _guardDexName,
        entries: finalProfile.entries,
      );
      if (!_bytesEqual(finalProfileBytes, plainProfileBytes)) {
        throw const ApkHardeningException('输出 APK 包体摘要基线复核失败');
      }
      logs.add('输出 APK 包体摘要基线复核通过');

      return ApkHardeningResult(
        outputApkPath: outputApkPath,
        packageName: packageName,
        logs: logs,
      );
    } finally {
      if (workDirectory.existsSync()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _compileGuardDex({
    required String javac,
    required String d8,
    required String androidJar,
    required int minSdk,
    required Directory sourceDirectory,
    required Directory classesDirectory,
    required Directory dexDirectory,
    required _GuardBuildConfig config,
    required List<String> logs,
    required String labelSuffix,
  }) async {
    if (sourceDirectory.existsSync()) {
      await sourceDirectory.delete(recursive: true);
    }
    if (classesDirectory.existsSync()) {
      await classesDirectory.delete(recursive: true);
    }
    if (dexDirectory.existsSync()) {
      await dexDirectory.delete(recursive: true);
    }

    await _writeGuardJavaSources(sourceDirectory, config);
    await classesDirectory.create(recursive: true);
    await dexDirectory.create(recursive: true);

    await _runChecked(
      javac,
      [
        '-source',
        '8',
        '-target',
        '8',
        '-encoding',
        'UTF-8',
        '-cp',
        androidJar,
        '-d',
        classesDirectory.path,
        _joinPath(
          _joinPath(_joinPath(sourceDirectory.path, 'com'), 'z1'),
          'guard/Z1Guard.java',
        ),
        _joinPath(
          _joinPath(_joinPath(sourceDirectory.path, 'com'), 'z1'),
          'guard/Z1GuardProvider.java',
        ),
        _joinPath(
          _joinPath(_joinPath(sourceDirectory.path, 'com'), 'z1'),
          'guard/Z1GuardApplication.java',
        ),
      ],
      logs,
      label: 'javac guard $labelSuffix',
    );

    final classFiles = _listClassFiles(classesDirectory);
    if (classFiles.isEmpty) {
      throw const ApkHardeningException('Guard class 生成失败');
    }

    await _runChecked(
      d8,
      [
        '--min-api',
        minSdk.toString(),
        '--lib',
        androidJar,
        '--output',
        dexDirectory.path,
        ...classFiles,
      ],
      logs,
      label: 'd8 guard $labelSuffix',
    );
  }

  Future<void> _copyGuardDex({
    required Directory guardDexDirectory,
    required Directory decodedDirectory,
    required String guardDexName,
  }) async {
    final guardDexFile = File(_joinPath(guardDexDirectory.path, 'classes.dex'));
    if (!guardDexFile.existsSync()) {
      throw const ApkHardeningException('Guard dex 生成失败');
    }

    await guardDexFile.copy(_joinPath(decodedDirectory.path, guardDexName));
  }

  List<String> _listClassFiles(Directory classesDirectory) {
    if (!classesDirectory.existsSync()) {
      return [];
    }

    final classFiles =
        classesDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.class'))
            .map((file) => file.path)
            .toList()
          ..sort();
    return classFiles;
  }

  Future<void> _runChecked(
    String executable,
    List<String> args,
    List<String> logs, {
    required String label,
    List<String>? maskedCommandArgs,
  }) async {
    logs.add('$label：${_formatCommand(executable, maskedCommandArgs ?? args)}');
    final result = await Process.run(
      executable,
      args,
      runInShell: Platform.isWindows,
    );
    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    if (stdoutText.isNotEmpty) {
      logs.add(stdoutText);
    }
    if (stderrText.isNotEmpty) {
      logs.add(stderrText);
    }
    if (result.exitCode != 0) {
      throw ApkHardeningException('$label 失败，退出码：${result.exitCode}');
    }
  }

  Future<void> _writeGuardJavaSources(
    Directory sourceDirectory,
    _GuardBuildConfig config,
  ) async {
    final packageDirectory = Directory(
      _joinPath(
        _joinPath(_joinPath(sourceDirectory.path, 'com'), 'z1'),
        'guard',
      ),
    );
    await packageDirectory.create(recursive: true);
    await File(
      _joinPath(packageDirectory.path, 'Z1GuardProvider.java'),
    ).writeAsString(_guardProviderJava);
    await File(
      _joinPath(packageDirectory.path, 'Z1GuardApplication.java'),
    ).writeAsString(_guardApplicationJava);
    await File(
      _joinPath(packageDirectory.path, 'Z1Guard.java'),
    ).writeAsString(_buildGuardJava(config));
  }

  _GuardManifestPatch _injectGuardBootstrap(
    String manifestContent,
    String packageName,
  ) {
    final applicationMatch = RegExp(
      r'<application\b[^>]*>',
    ).firstMatch(manifestContent);
    if (applicationMatch == null) {
      throw const ApkHardeningException(
        'AndroidManifest.xml 缺少 application 节点',
      );
    }

    final applicationTag = applicationMatch.group(0)!;
    final originalApplicationName = _normalizeApplicationName(
      _readApplicationNameFromTag(applicationTag),
      packageName,
    );
    final updatedApplicationTag = _replaceApplicationName(
      applicationTag,
      _guardApplicationName,
    );
    var updatedManifest = manifestContent.replaceRange(
      applicationMatch.start,
      applicationMatch.end,
      updatedApplicationTag,
    );

    if (updatedManifest.contains(_guardProviderName)) {
      return _GuardManifestPatch(
        content: updatedManifest,
        originalApplicationName: originalApplicationName,
      );
    }

    final authorities = '$packageName.z1guard';
    final provider =
        '''
        <provider android:name="$_guardProviderName" android:authorities="$authorities" android:exported="false" android:initOrder="1000" />
''';
    final closeApplicationIndex = updatedManifest.lastIndexOf('</application>');
    if (closeApplicationIndex < 0) {
      throw const ApkHardeningException(
        'AndroidManifest.xml 缺少 application 节点',
      );
    }

    updatedManifest = updatedManifest.replaceRange(
      closeApplicationIndex,
      closeApplicationIndex,
      provider,
    );
    return _GuardManifestPatch(
      content: updatedManifest,
      originalApplicationName: originalApplicationName,
    );
  }

  String? _readApplicationNameFromTag(String applicationTag) {
    final match = RegExp(
      r'\sandroid:name\s*=\s*"([^"]+)"',
    ).firstMatch(applicationTag);
    return match?.group(1);
  }

  String _normalizeApplicationName(
    String? applicationName,
    String packageName,
  ) {
    final normalized = (applicationName ?? '').trim();
    if (normalized.isEmpty || normalized == _guardApplicationName) {
      return 'android.app.Application';
    }
    if (normalized.startsWith('.')) {
      return '$packageName$normalized';
    }
    if (!normalized.contains('.')) {
      return '$packageName.$normalized';
    }
    return normalized;
  }

  String _replaceApplicationName(
    String applicationTag,
    String applicationName,
  ) {
    final namePattern = RegExp(r'\sandroid:name\s*=\s*"[^"]*"');
    if (namePattern.hasMatch(applicationTag)) {
      return applicationTag.replaceFirst(
        namePattern,
        ' android:name="$applicationName"',
      );
    }

    final insertIndex = applicationTag.lastIndexOf('>');
    if (insertIndex < 0) {
      throw const ApkHardeningException('AndroidManifest.xml application 节点异常');
    }
    return applicationTag.replaceRange(
      insertIndex,
      insertIndex,
      ' android:name="$applicationName"',
    );
  }

  List<File> _collectOriginalDexFiles(Directory decodedDirectory) {
    final dexPattern = RegExp(r'^classes([0-9]*)\.dex$');
    final files =
        decodedDirectory
            .listSync()
            .whereType<File>()
            .where((file) => dexPattern.hasMatch(_lastPathSegment(file.path)))
            .toList()
          ..sort((left, right) {
            return _dexSortIndex(
              _lastPathSegment(left.path),
            ).compareTo(_dexSortIndex(_lastPathSegment(right.path)));
          });

    if (files.isEmpty) {
      throw const ApkHardeningException('解包后未找到原始 classes*.dex');
    }
    return files;
  }

  int _dexSortIndex(String fileName) {
    final match = RegExp(r'^classes([0-9]*)\.dex$').firstMatch(fileName);
    if (match == null) {
      return 1 << 30;
    }
    return int.tryParse(match.group(1) ?? '') ?? 1;
  }

  Future<_EncryptedDexPayload> _writeEncryptedDexPayload({
    required Directory decodedDirectory,
    required List<File> dexFiles,
    required Uint8List xorKey,
    required int partSizeBytes,
  }) async {
    if (partSizeBytes <= 0) {
      throw const ApkHardeningException('dex 分片大小必须大于 0');
    }

    final assetsDirectory = Directory(
      _joinPath(decodedDirectory.path, 'assets'),
    );
    final dexAssetsDirectory = Directory(
      _joinPath(assetsDirectory.path, _dexAssetDirectoryName),
    );
    if (dexAssetsDirectory.existsSync()) {
      await dexAssetsDirectory.delete(recursive: true);
    }
    await dexAssetsDirectory.create(recursive: true);

    final entries = <_EncryptedDexEntry>[];
    final totalPlainBytes = BytesBuilder(copy: false);
    for (var dexIndex = 0; dexIndex < dexFiles.length; dexIndex += 1) {
      final dexFile = dexFiles[dexIndex];
      final dexName = _lastPathSegment(dexFile.path);
      final plainBytes = await dexFile.readAsBytes();
      if (plainBytes.isEmpty) {
        throw ApkHardeningException('原始 dex 为空：$dexName');
      }

      totalPlainBytes.add(plainBytes);
      final parts = <_EncryptedDexPart>[];
      var partIndex = 0;
      var offset = 0;
      while (offset < plainBytes.length) {
        final end = min(offset + partSizeBytes, plainBytes.length);
        final chunk = Uint8List.fromList(plainBytes.sublist(offset, end));
        final protectedBytes = _xorBytes(chunk, xorKey);
        final assetName =
            '$_dexAssetDirectoryName/dex_${dexIndex.toString().padLeft(3, '0')}_part_${partIndex.toString().padLeft(4, '0')}.bin';
        final assetFile = File(_joinPath(assetsDirectory.path, assetName));
        await assetFile.parent.create(recursive: true);
        await assetFile.writeAsBytes(protectedBytes, flush: true);
        parts.add(
          _EncryptedDexPart(
            assetName: assetName,
            apkEntryName: 'assets/$assetName',
            sizeBytes: protectedBytes.length,
            sha256Hex: sha256.convert(protectedBytes).toString(),
          ),
        );
        offset += partSizeBytes;
        partIndex += 1;
      }

      entries.add(
        _EncryptedDexEntry(
          name: dexName,
          sizeBytes: plainBytes.length,
          sha256Hex: sha256.convert(plainBytes).toString(),
          parts: parts,
        ),
      );
      await dexFile.delete();
    }

    return _EncryptedDexPayload(
      entries: entries,
      totalSizeBytes: entries.fold<int>(
        0,
        (sum, entry) => sum + entry.sizeBytes,
      ),
      totalSha256Hex: sha256.convert(totalPlainBytes.takeBytes()).toString(),
    );
  }

  Future<String> _readSigningCertificateSha256({
    required String keytoolExecutable,
    required AndroidSigningConfig signingConfig,
  }) async {
    final keystoreFile = File(signingConfig.keystorePath);
    if (!keystoreFile.existsSync()) {
      throw ApkHardeningException(
        '签名 keystore 不存在：${signingConfig.keystorePath}',
      );
    }

    final result = await Process.run(keytoolExecutable, [
      '-exportcert',
      '-rfc',
      '-keystore',
      signingConfig.keystorePath,
      '-alias',
      signingConfig.keyAlias,
      '-storepass',
      signingConfig.storePassword,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      throw ApkHardeningException('读取签名证书失败${error.isEmpty ? '' : '：$error'}');
    }

    final pem = result.stdout.toString();
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    ).firstMatch(pem);
    if (match == null) {
      throw const ApkHardeningException('读取签名证书失败：keytool 未输出证书内容');
    }

    final certificateBase64 = match.group(1)!.replaceAll(RegExp(r'\s+'), '');
    final certificateBytes = base64Decode(certificateBase64);
    return sha256.convert(certificateBytes).toString();
  }

  Future<_ApkIntegrityProfile> _buildIntegrityProfile({
    required String apkPath,
    required Set<String> ignoredEntries,
  }) async {
    final apkFile = File(apkPath);
    if (!apkFile.existsSync()) {
      throw ApkHardeningException('APK 文件不存在：$apkPath');
    }

    final input = InputFileStream(apkPath);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input);
      final entries = <_ApkIntegrityProfileEntry>[];
      for (final entry in archive.files) {
        if (!entry.isFile) {
          continue;
        }

        final normalizedPath = _normalizeArchivePath(entry.name);
        if (normalizedPath.isEmpty ||
            _shouldIgnoreIntegrityEntry(normalizedPath, ignoredEntries)) {
          continue;
        }

        final bytes = entry.readBytes();
        if (bytes == null) {
          continue;
        }

        entries.add(
          _ApkIntegrityProfileEntry(
            path: normalizedPath,
            sizeBytes: bytes.length,
            sha256Hex: sha256.convert(bytes).toString(),
          ),
        );
      }

      entries.sort((left, right) => left.path.compareTo(right.path));
      if (entries.isEmpty) {
        throw const ApkHardeningException('无法生成包体摘要基线：APK 中未发现可校验文件');
      }

      return _ApkIntegrityProfile(entries);
    } on ApkHardeningException {
      rethrow;
    } on ArchiveException catch (error) {
      throw ApkHardeningException('APK 解包失败：${error.message}');
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  Uint8List _encodeIntegrityProfile({
    required String packageName,
    required String guardDexName,
    required List<_ApkIntegrityProfileEntry> entries,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        [
          'Z1APKPROFILE',
          '1',
          base64Url.encode(utf8.encode(packageName)),
          base64Url.encode(utf8.encode(guardDexName)),
        ].join('|'),
      );

    for (final entry in entries) {
      buffer.writeln(
        [
          base64Url.encode(utf8.encode(entry.path)),
          entry.sizeBytes.toString(),
          entry.sha256Hex,
        ].join('|'),
      );
    }

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Future<void> _writeProfileAsset({
    required Directory decodedDirectory,
    required String profileAssetName,
    required Uint8List protectedProfileBytes,
  }) async {
    final profileAssetFile = File(
      _joinPath(_joinPath(decodedDirectory.path, 'assets'), profileAssetName),
    );
    await profileAssetFile.parent.create(recursive: true);
    await profileAssetFile.writeAsBytes(protectedProfileBytes, flush: true);
  }

  bool _shouldIgnoreIntegrityEntry(
    String normalizedPath,
    Set<String> ignoredEntries,
  ) {
    if (ignoredEntries.contains(normalizedPath)) {
      return true;
    }
    if (normalizedPath.startsWith('assets/$_dexAssetDirectoryName/')) {
      return true;
    }

    return _isSignatureGeneratedApkEntry(normalizedPath) ||
        normalizedPath == 'stamp-cert-sha256';
  }

  bool _isSignatureGeneratedApkEntry(String normalizedPath) {
    final upperPath = normalizedPath.toUpperCase();
    if (upperPath == 'META-INF/MANIFEST.MF') {
      return true;
    }
    if (!upperPath.startsWith('META-INF/')) {
      return false;
    }

    final fileName = upperPath.substring('META-INF/'.length);
    if (fileName.contains('/')) {
      return false;
    }
    return fileName.endsWith('.SF') ||
        fileName.endsWith('.RSA') ||
        fileName.endsWith('.DSA') ||
        fileName.endsWith('.EC');
  }

  bool _isStorageProfileEntryPath(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/').trim();
    return normalized.startsWith('shared_prefs/') ||
        normalized.startsWith('databases/');
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

  Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _xorBytes(Uint8List bytes, Uint8List key) {
    if (key.isEmpty) {
      return Uint8List.fromList(bytes);
    }

    final output = Uint8List(bytes.length);
    for (var index = 0; index < bytes.length; index += 1) {
      output[index] = bytes[index] ^ key[index % key.length];
    }

    return output;
  }

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }

    var diff = 0;
    for (var index = 0; index < left.length; index += 1) {
      diff |= left[index] ^ right[index];
    }

    return diff == 0;
  }

  String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }

    return buffer.toString();
  }

  String _shortDigest(String digest) {
    final normalized = digest.trim();
    if (normalized.length <= 16) {
      return normalized;
    }

    return '${normalized.substring(0, 16)}...';
  }

  String? _readPackageName(String manifestContent) {
    final match = RegExp(
      r'<manifest[^>]*\spackage="([^"]+)"',
    ).firstMatch(manifestContent);
    return match?.group(1);
  }

  int _readMinSdk(String manifestContent) {
    final match = RegExp(
      r'android:minSdkVersion="([0-9]+)"',
    ).firstMatch(manifestContent);
    return int.tryParse(match?.group(1) ?? '') ?? 21;
  }

  Future<String?> _readPackageNameWithAapt(String apkPath) async {
    final aapt = await _resolveBuildToolExecutable(
      configuredExecutable: '',
      executableName: 'aapt',
    );
    final result = await Process.run(aapt, [
      'dump',
      'badging',
      apkPath,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      return null;
    }

    final output = result.stdout.toString();
    final match = RegExp(r"package: name='([^']+)'").firstMatch(output);
    return match?.group(1);
  }

  List<String> _buildSigningArgs(
    AndroidSigningConfig config,
    String alignedApkPath,
    String outputPath,
    bool maskPasswords,
  ) {
    final storePassword = maskPasswords
        ? 'pass:******'
        : 'pass:${config.storePassword}';
    final keyPassword = maskPasswords
        ? 'pass:******'
        : 'pass:${config.effectiveKeyPassword}';

    final args = [
      'sign',
      '--ks',
      config.keystorePath,
      '--ks-key-alias',
      config.keyAlias,
      '--ks-pass',
      storePassword,
      '--key-pass',
      keyPassword,
    ];

    if (config.usesExplicitSigningScheme) {
      args.addAll([
        '--v1-signing-enabled',
        config.enableV1Signing.toString(),
        '--v2-signing-enabled',
        config.enableV2Signing.toString(),
        '--v3-signing-enabled',
        config.enableV3Signing.toString(),
      ]);
    }

    args.addAll(['--out', outputPath, alignedApkPath]);
    return args;
  }

  Future<String> _resolveJavac() async {
    return _resolveJavaTool('javac');
  }

  Future<String> _resolveJavaTool(String executableName) async {
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.trim().isNotEmpty) {
      final candidate = _joinPath(
        _joinPath(javaHome.trim(), 'bin'),
        _javaToolName(executableName),
      );
      if (_fileExistsSafely(candidate)) {
        return candidate;
      }
    }

    final pathExecutable = await _findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    if (Platform.isMacOS) {
      try {
        final result = await Process.run('/usr/libexec/java_home', []);
        final home = result.stdout.toString().trim();
        final candidate = _joinPath(
          _joinPath(home, 'bin'),
          _javaToolName(executableName),
        );
        if (result.exitCode == 0 && _fileExistsSafely(candidate)) {
          return candidate;
        }
      } on ProcessException {
        // Fall through to error below.
      }
    }

    throw ApkHardeningException('未找到 $executableName，请安装 JDK 或配置 JAVA_HOME');
  }

  String _javaToolName(String executableName) {
    if (!Platform.isWindows) {
      return executableName;
    }

    return executableName.endsWith('.exe')
        ? executableName
        : '$executableName.exe';
  }

  Future<String> _resolvePathExecutable(String executableName) async {
    final pathExecutable = await _findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    throw ApkHardeningException('未找到 $executableName，请先安装并加入 PATH');
  }

  Future<String> _resolveBuildToolExecutable({
    required String configuredExecutable,
    required String executableName,
  }) async {
    final normalizedExecutable = configuredExecutable.trim();
    if (normalizedExecutable.isNotEmpty) {
      return normalizedExecutable;
    }

    final pathExecutable = await _findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    for (final sdkPath in _androidSdkCandidates()) {
      final buildToolExecutable = _findBuildToolExecutable(
        sdkPath,
        executableName,
      );
      if (buildToolExecutable != null) {
        return buildToolExecutable;
      }
    }

    throw ApkHardeningException(
      '未找到 $executableName，请安装 Android SDK build-tools',
    );
  }

  Future<String?> _findExecutableOnPath(String executableName) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        executableName,
      ], runInShell: Platform.isWindows);
      if (result.exitCode != 0) {
        return null;
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return null;
      }

      return output.split(RegExp(r'\r?\n')).first.trim();
    } on ProcessException {
      return null;
    }
  }

  String? _findLatestAndroidJar() {
    for (final sdkPath in _androidSdkCandidates()) {
      final platformsDirectory = Directory(_joinPath(sdkPath, 'platforms'));
      if (!_directoryExistsSafely(platformsDirectory.path)) {
        continue;
      }

      final platforms =
          platformsDirectory.listSync().whereType<Directory>().toList()
            ..sort((left, right) {
              return _compareVersionNames(
                _lastPathSegment(right.path),
                _lastPathSegment(left.path),
              );
            });

      for (final platform in platforms) {
        final androidJar = _joinPath(platform.path, 'android.jar');
        if (_fileExistsSafely(androidJar)) {
          return androidJar;
        }
      }
    }

    return null;
  }

  Iterable<String> _androidSdkCandidates() {
    final candidates = <String>{
      if ((Platform.environment['ANDROID_HOME'] ?? '').trim().isNotEmpty)
        Platform.environment['ANDROID_HOME']!.trim(),
      if ((Platform.environment['ANDROID_SDK_ROOT'] ?? '').trim().isNotEmpty)
        Platform.environment['ANDROID_SDK_ROOT']!.trim(),
    };

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.trim().isNotEmpty) {
      candidates
        ..add(_joinPath(home, 'Library/Android/sdk'))
        ..add(_joinPath(home, 'Android/Sdk'));
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      candidates.add(_joinPath(localAppData, 'Android/Sdk'));
    }

    return candidates.where(_directoryExistsSafely);
  }

  String? _findBuildToolExecutable(String sdkPath, String executableName) {
    final buildToolsDirectory = Directory(_joinPath(sdkPath, 'build-tools'));
    if (!_directoryExistsSafely(buildToolsDirectory.path)) {
      return null;
    }

    final versions =
        buildToolsDirectory.listSync().whereType<Directory>().toList()
          ..sort((left, right) {
            return _compareVersionNames(
              _lastPathSegment(right.path),
              _lastPathSegment(left.path),
            );
          });

    for (final version in versions) {
      for (final candidateName in _buildToolExecutableNames(executableName)) {
        final candidatePath = _joinPath(version.path, candidateName);
        if (_fileExistsSafely(candidatePath)) {
          return candidatePath;
        }
      }
    }

    return null;
  }

  Iterable<String> _buildToolExecutableNames(String executableName) {
    if (!Platform.isWindows) {
      return [executableName];
    }

    return switch (executableName) {
      'apksigner' => ['apksigner.bat', 'apksigner'],
      'zipalign' => ['zipalign.exe', 'zipalign'],
      'd8' => ['d8.bat', 'd8'],
      'aapt' => ['aapt.exe', 'aapt'],
      _ => [executableName],
    };
  }

  bool _directoryExistsSafely(String path) {
    try {
      return Directory(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  bool _fileExistsSafely(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  int _compareVersionNames(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < maxLength; index += 1) {
      final leftValue = index < leftParts.length ? leftParts[index] : 0;
      final rightValue = index < rightParts.length ? rightParts[index] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }

    return left.compareTo(right);
  }

  List<int> _versionParts(String version) {
    return version
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }

  String _lastPathSegment(String path) {
    final slashIndex = path.lastIndexOf('/');
    final backslashIndex = path.lastIndexOf(r'\');
    final separatorIndex = slashIndex > backslashIndex
        ? slashIndex
        : backslashIndex;

    return separatorIndex >= 0 ? path.substring(separatorIndex + 1) : path;
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }

    return '$parent${Platform.pathSeparator}$child';
  }

  String _formatCommand(String executable, List<String> args) {
    return [executable, ...args].map(_quoteShellToken).join(' ');
  }

  String _quoteShellToken(String token) {
    if (token.isEmpty) {
      return '""';
    }

    final needsQuotes = token.contains(RegExp(r'\s|["]'));
    if (!needsQuotes) {
      return token;
    }

    return '"${token.replaceAll('"', r'\"')}"';
  }
}

class ApkHardeningResult {
  const ApkHardeningResult({
    required this.outputApkPath,
    required this.packageName,
    required this.logs,
  });

  final String outputApkPath;
  final String packageName;
  final List<String> logs;
}

class ApkHardeningDexPayloadTestResult {
  const ApkHardeningDexPayloadTestResult({
    required this.encodedConfig,
    required this.partCount,
    required this.totalSizeBytes,
    required this.totalSha256Hex,
    required this.apkEntryNames,
  });

  final String encodedConfig;
  final int partCount;
  final int totalSizeBytes;
  final String totalSha256Hex;
  final List<String> apkEntryNames;
}

class ApkHardeningStorageProfileEntryForTesting {
  const ApkHardeningStorageProfileEntryForTesting({
    required this.path,
    required this.sizeBytes,
    required this.modifiedTimeMillis,
    required this.sha256Hex,
  });

  final String path;
  final int sizeBytes;
  final int modifiedTimeMillis;
  final String sha256Hex;
}

class ApkHardeningException implements Exception {
  const ApkHardeningException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _GuardBuildConfig {
  const _GuardBuildConfig({
    required this.expectedPackageName,
    required this.expectedCertificateSha256,
    required this.guardDexName,
    required this.profileAssetName,
    required this.profileApkEntryName,
    required this.expectedProfileSha256,
    required this.profileXorKeyHex,
    required this.originalApplicationName,
    required this.dexPayloadConfig,
    required this.dexXorKeyHex,
    required this.storageHmacKeyHex,
    required this.storageProfileXorKeyHex,
  });

  final String expectedPackageName;
  final String expectedCertificateSha256;
  final String guardDexName;
  final String profileAssetName;
  final String profileApkEntryName;
  final String expectedProfileSha256;
  final String profileXorKeyHex;
  final String originalApplicationName;
  final String dexPayloadConfig;
  final String dexXorKeyHex;
  final String storageHmacKeyHex;
  final String storageProfileXorKeyHex;
}

class _GuardManifestPatch {
  const _GuardManifestPatch({
    required this.content,
    required this.originalApplicationName,
  });

  final String content;
  final String originalApplicationName;
}

class _EncryptedDexPayload {
  const _EncryptedDexPayload({
    required this.entries,
    required this.totalSizeBytes,
    required this.totalSha256Hex,
  });

  final List<_EncryptedDexEntry> entries;
  final int totalSizeBytes;
  final String totalSha256Hex;

  int get partCount {
    return entries.fold<int>(0, (sum, entry) => sum + entry.parts.length);
  }

  Iterable<String> get apkEntryNames sync* {
    for (final entry in entries) {
      for (final part in entry.parts) {
        yield part.apkEntryName;
      }
    }
  }

  String get encodedConfig {
    final buffer = StringBuffer()
      ..writeln(
        ['Z1DEXPROFILE', '1', totalSizeBytes, totalSha256Hex].join('|'),
      );

    for (final entry in entries) {
      final partsText = entry.parts
          .map(
            (part) => [
              base64Url.encode(utf8.encode(part.assetName)),
              part.sizeBytes.toString(),
              part.sha256Hex,
            ].join(','),
          )
          .join(';');
      buffer.writeln(
        [
          base64Url.encode(utf8.encode(entry.name)),
          entry.sizeBytes.toString(),
          entry.sha256Hex,
          partsText,
        ].join('|'),
      );
    }

    return base64Url.encode(utf8.encode(buffer.toString()));
  }
}

class _EncryptedDexEntry {
  const _EncryptedDexEntry({
    required this.name,
    required this.sizeBytes,
    required this.sha256Hex,
    required this.parts,
  });

  final String name;
  final int sizeBytes;
  final String sha256Hex;
  final List<_EncryptedDexPart> parts;
}

class _EncryptedDexPart {
  const _EncryptedDexPart({
    required this.assetName,
    required this.apkEntryName,
    required this.sizeBytes,
    required this.sha256Hex,
  });

  final String assetName;
  final String apkEntryName;
  final int sizeBytes;
  final String sha256Hex;
}

class _ApkIntegrityProfile {
  const _ApkIntegrityProfile(this.entries);

  final List<_ApkIntegrityProfileEntry> entries;
}

class _ApkIntegrityProfileEntry {
  const _ApkIntegrityProfileEntry({
    required this.path,
    required this.sizeBytes,
    required this.sha256Hex,
  });

  final String path;
  final int sizeBytes;
  final String sha256Hex;
}

String _buildGuardJava(_GuardBuildConfig config) {
  return _guardJavaTemplate
      .replaceAll(
        '__EXPECTED_PACKAGE_NAME__',
        _javaString(config.expectedPackageName),
      )
      .replaceAll(
        '__EXPECTED_CERTIFICATE_SHA256__',
        _javaString(config.expectedCertificateSha256),
      )
      .replaceAll('__GUARD_DEX_NAME__', _javaString(config.guardDexName))
      .replaceAll(
        '__PROFILE_ASSET_NAME__',
        _javaString(config.profileAssetName),
      )
      .replaceAll(
        '__PROFILE_APK_ENTRY_NAME__',
        _javaString(config.profileApkEntryName),
      )
      .replaceAll(
        '__EXPECTED_PROFILE_SHA256__',
        _javaString(config.expectedProfileSha256),
      )
      .replaceAll(
        '__PROFILE_XOR_KEY_HEX__',
        _javaString(config.profileXorKeyHex),
      )
      .replaceAll(
        '__ORIGINAL_APPLICATION_NAME__',
        _javaString(config.originalApplicationName),
      )
      .replaceAll(
        '__DEX_PAYLOAD_CONFIG__',
        _javaString(config.dexPayloadConfig),
      )
      .replaceAll('__DEX_XOR_KEY_HEX__', _javaString(config.dexXorKeyHex))
      .replaceAll(
        '__STORAGE_HMAC_KEY_HEX__',
        _javaString(config.storageHmacKeyHex),
      )
      .replaceAll(
        '__STORAGE_PROFILE_XOR_KEY_HEX__',
        _javaString(config.storageProfileXorKeyHex),
      );
}

String _javaString(String value) {
  return jsonEncode(value);
}

const _guardProviderJava = r'''
package com.z1.guard;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;

public final class Z1GuardProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        Z1Guard.init(getContext());
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
''';

const _guardApplicationJava = r'''
package com.z1.guard;

import android.app.Application;
import android.content.Context;

public final class Z1GuardApplication extends Application {
    private Application delegate;

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        Z1Guard.installShell(base);
        delegate = Z1Guard.createOriginalApplication(base, this);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        Z1Guard.init(this);
        if (delegate != null) {
            delegate.onCreate();
        }
        Z1Guard.startStorageProtection(delegate != null ? delegate : this);
    }
}
''';

const _guardJavaTemplate = r'''
package com.z1.guard;

import android.app.Application;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.FileObserver;
import android.os.Process;
import android.util.Base64;
import android.util.Log;
import dalvik.system.DexClassLoader;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.InputStream;
import java.lang.reflect.Array;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class Z1Guard {
    private static final String TAG = "Z1Guard";
    private static final String EXPECTED_PACKAGE_NAME = __EXPECTED_PACKAGE_NAME__;
    private static final String EXPECTED_CERTIFICATE_SHA256 = __EXPECTED_CERTIFICATE_SHA256__;
    private static final String GUARD_DEX_NAME = __GUARD_DEX_NAME__;
    private static final String PROFILE_ASSET_NAME = __PROFILE_ASSET_NAME__;
    private static final String PROFILE_APK_ENTRY_NAME = __PROFILE_APK_ENTRY_NAME__;
    private static final String EXPECTED_PROFILE_SHA256 = __EXPECTED_PROFILE_SHA256__;
    private static final String PROFILE_XOR_KEY_HEX = __PROFILE_XOR_KEY_HEX__;
    private static final String ORIGINAL_APPLICATION_NAME = __ORIGINAL_APPLICATION_NAME__;
    private static final String DEX_PAYLOAD_CONFIG = __DEX_PAYLOAD_CONFIG__;
    private static final String DEX_XOR_KEY_HEX = __DEX_XOR_KEY_HEX__;
    private static final String STORAGE_HMAC_KEY_HEX = __STORAGE_HMAC_KEY_HEX__;
    private static final String STORAGE_PROFILE_XOR_KEY_HEX = __STORAGE_PROFILE_XOR_KEY_HEX__;
    private static final int PROFILE_READ_LIMIT_BYTES = 16 * 1024 * 1024;
    private static final int DEX_PART_READ_LIMIT_BYTES = 2 * 1024 * 1024;
    private static final int STORAGE_PROFILE_READ_LIMIT_BYTES = 2 * 1024 * 1024;
    private static final int STORAGE_FILE_OBSERVER_MASK = FileObserver.CREATE
            | FileObserver.DELETE
            | FileObserver.MODIFY
            | FileObserver.CLOSE_WRITE
            | FileObserver.MOVED_FROM
            | FileObserver.MOVED_TO
            | FileObserver.ATTRIB
            | FileObserver.DELETE_SELF
            | FileObserver.MOVE_SELF;
    private static volatile boolean initialized;
    private static volatile boolean shellInstalled;
    private static volatile boolean storageProtectionStarted;
    private static volatile boolean storageRefreshScheduled;
    private static final ArrayList<FileObserver> storageObservers = new ArrayList<FileObserver>();
    private static final HashSet<String> storageObservedPaths = new HashSet<String>();

    private Z1Guard() {
    }

    public static void init(Context context) {
        if (context == null || initialized) {
            return;
        }
        initialized = true;

        Context appContext = context.getApplicationContext();
        if (appContext == null) {
            appContext = context;
        }
        installShell(appContext);

        StringBuilder reasons = new StringBuilder();
        int score = 0;
        score += safeCheckPackageName(appContext, reasons);
        score += safeCheckSigningCertificate(appContext, reasons);
        score += safeCheckApkIntegrity(appContext, reasons);
        score += safeCheckStorageIntegrity(appContext, reasons);
        score += safeCheckDebuggable(appContext, reasons);
        score += safeCheckTracerPid(reasons);
        score += safeCheckPrivateFiles(appContext, reasons);
        score += safeCheckProcMaps(reasons);
        score += safeCheckThreads(reasons);
        score += safeCheckHookClassesAndStack(reasons);
        score += safeCheckRootSignals(reasons);
        score += safeCheckVpn(appContext, reasons);

        if (score >= 6) {
            block(reasons.toString());
        }
    }

    public static void installShell(Context context) {
        if (context == null || shellInstalled) {
            return;
        }

        synchronized (Z1Guard.class) {
            if (shellInstalled) {
                return;
            }
            if (DEX_PAYLOAD_CONFIG.length() == 0 || DEX_XOR_KEY_HEX.length() == 0) {
                shellInstalled = true;
                return;
            }

            try {
                Context appContext = context.getApplicationContext();
                if (appContext == null) {
                    appContext = context;
                }

                DexLoadResult loadResult = loadDexPayload(appContext);
                if (loadResult.dexBytes.isEmpty()) {
                    throw new SecurityException("empty dex payload");
                }

                ClassLoader targetLoader = appContext.getClassLoader();
                if (targetLoader == null) {
                    targetLoader = Z1Guard.class.getClassLoader();
                }
                ClassLoader payloadLoader = Build.VERSION.SDK_INT >= 26
                        ? createMemoryDexLoader(loadResult.dexBytes, targetLoader)
                        : createFileDexLoader(appContext, loadResult.dexBytes, targetLoader);
                injectDexElements(targetLoader, payloadLoader);
                shellInstalled = true;
            } catch (Throwable error) {
                block("dex-shell-load-error=" + error.getClass().getSimpleName());
            }
        }
    }

    public static Application createOriginalApplication(Context base, Application guardApplication) {
        if (base == null) {
            return null;
        }
        String originalName = ORIGINAL_APPLICATION_NAME;
        if (originalName.length() == 0
                || "android.app.Application".equals(originalName)
                || "com.z1.guard.Z1GuardApplication".equals(originalName)) {
            return null;
        }

        try {
            ClassLoader loader = base.getClassLoader();
            if (loader == null) {
                loader = Z1Guard.class.getClassLoader();
            }
            Class<?> applicationClass = Class.forName(originalName, true, loader);
            Object instance = applicationClass.newInstance();
            if (!(instance instanceof Application)) {
                throw new SecurityException("not application");
            }
            Application application = (Application) instance;
            Method attach = Application.class.getDeclaredMethod("attach", Context.class);
            attach.setAccessible(true);
            attach.invoke(application, base);
            replaceRuntimeApplication(base, guardApplication, application);
            return application;
        } catch (Throwable error) {
            block("original-application-error=" + error.getClass().getSimpleName());
            return null;
        }
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    private static void replaceRuntimeApplication(
            Context base,
            Application guardApplication,
            Application originalApplication
    ) {
        if (base == null || originalApplication == null) {
            return;
        }

        try {
            Object loadedApk = readOptionalField(base, "mPackageInfo");
            if (loadedApk != null) {
                writeOptionalField(loadedApk, "mApplication", originalApplication);
                Object appInfo = readOptionalField(loadedApk, "mApplicationInfo");
                if (appInfo instanceof ApplicationInfo) {
                    ((ApplicationInfo) appInfo).className = ORIGINAL_APPLICATION_NAME;
                }
            }

            ApplicationInfo baseInfo = base.getApplicationInfo();
            if (baseInfo != null) {
                baseInfo.className = ORIGINAL_APPLICATION_NAME;
            }

            Object activityThread = currentActivityThread(base);
            if (activityThread != null) {
                Object initialApplication = readOptionalField(activityThread, "mInitialApplication");
                if (initialApplication == null || initialApplication == guardApplication) {
                    writeOptionalField(activityThread, "mInitialApplication", originalApplication);
                }

                Object allApplications = readOptionalField(activityThread, "mAllApplications");
                if (allApplications instanceof List) {
                    List applications = (List) allApplications;
                    boolean replaced = false;
                    for (int index = 0; index < applications.size(); index++) {
                        if (applications.get(index) == guardApplication) {
                            applications.set(index, originalApplication);
                            replaced = true;
                        }
                    }
                    if (!replaced && !applications.contains(originalApplication)) {
                        applications.add(originalApplication);
                    }
                }
            }
        } catch (Throwable error) {
            Log.w(TAG, "Original application runtime swap failed", error);
        }
    }

    private static Object currentActivityThread(Context base) {
        try {
            Class<?> activityThreadClass = Class.forName("android.app.ActivityThread");
            Method method = activityThreadClass.getDeclaredMethod("currentActivityThread");
            method.setAccessible(true);
            Object thread = method.invoke(null);
            if (thread != null) {
                return thread;
            }
        } catch (Throwable ignored) {
        }
        return readOptionalField(base, "mMainThread");
    }

    private static DexLoadResult loadDexPayload(Context context) throws Exception {
        byte[] configBytes = Base64.decode(DEX_PAYLOAD_CONFIG, Base64.URL_SAFE | Base64.NO_WRAP);
        String text = new String(configBytes, "UTF-8");
        String[] lines = text.split("\\r?\\n");
        if (lines.length == 0) {
            throw new SecurityException("empty dex profile");
        }

        String[] header = lines[0].split("\\|", -1);
        if (header.length != 4 || !"Z1DEXPROFILE".equals(header[0]) || !"1".equals(header[1])) {
            throw new SecurityException("bad dex profile header");
        }
        long expectedTotalSize = Long.parseLong(header[2]);
        String expectedTotalSha256 = header[3].toLowerCase(Locale.US);
        byte[] xorKey = hexToBytes(DEX_XOR_KEY_HEX);
        if (xorKey.length == 0) {
            throw new SecurityException("empty dex key");
        }

        MessageDigest totalDigest = MessageDigest.getInstance("SHA-256");
        long actualTotalSize = 0;
        ArrayList<byte[]> dexBytes = new ArrayList<byte[]>();
        for (int index = 1; index < lines.length; index++) {
            String line = lines[index];
            if (line == null || line.length() == 0) {
                continue;
            }

            DexEntry entry = parseDexEntry(line);
            ByteArrayOutputStream dexOutput = new ByteArrayOutputStream();
            for (int partIndex = 0; partIndex < entry.parts.size(); partIndex++) {
                DexPart part = entry.parts.get(partIndex);
                byte[] encryptedPart = readAssetBytes(context, part.assetName, DEX_PART_READ_LIMIT_BYTES);
                if (encryptedPart.length != part.sizeBytes) {
                    throw new SecurityException("dex part size mismatch");
                }
                String encryptedDigest = sha256Hex(encryptedPart);
                if (!part.sha256Hex.equalsIgnoreCase(encryptedDigest)) {
                    throw new SecurityException("dex part sha mismatch");
                }
                dexOutput.write(xorBytes(encryptedPart, xorKey));
            }

            byte[] dex = dexOutput.toByteArray();
            if (dex.length != entry.sizeBytes) {
                throw new SecurityException("dex size mismatch");
            }
            String dexDigest = sha256Hex(dex);
            if (!entry.sha256Hex.equalsIgnoreCase(dexDigest)) {
                throw new SecurityException("dex sha mismatch");
            }
            totalDigest.update(dex);
            actualTotalSize += dex.length;
            dexBytes.add(dex);
        }

        if (dexBytes.isEmpty()) {
            throw new SecurityException("empty dex entries");
        }
        String actualTotalSha256 = bytesToHex(totalDigest.digest());
        if (actualTotalSize != expectedTotalSize || !expectedTotalSha256.equalsIgnoreCase(actualTotalSha256)) {
            throw new SecurityException("dex total digest mismatch");
        }

        return new DexLoadResult(dexBytes);
    }

    private static DexEntry parseDexEntry(String line) throws Exception {
        String[] parts = line.split("\\|", -1);
        if (parts.length != 4) {
            throw new SecurityException("bad dex profile line");
        }

        String name = new String(
                Base64.decode(parts[0], Base64.URL_SAFE | Base64.NO_WRAP),
                "UTF-8"
        );
        long size = Long.parseLong(parts[1]);
        String sha = parts[2].toLowerCase(Locale.US);
        String[] partTokens = parts[3].split(";", -1);
        ArrayList<DexPart> dexParts = new ArrayList<DexPart>();
        for (int index = 0; index < partTokens.length; index++) {
            String token = partTokens[index];
            if (token == null || token.length() == 0) {
                continue;
            }
            dexParts.add(parseDexPart(token));
        }
        if (name.length() == 0 || size <= 0 || dexParts.isEmpty()) {
            throw new SecurityException("invalid dex entry");
        }
        return new DexEntry(name, size, sha, dexParts);
    }

    private static DexPart parseDexPart(String text) throws Exception {
        String[] parts = text.split(",", -1);
        if (parts.length != 3) {
            throw new SecurityException("bad dex part line");
        }
        String assetName = new String(
                Base64.decode(parts[0], Base64.URL_SAFE | Base64.NO_WRAP),
                "UTF-8"
        );
        long size = Long.parseLong(parts[1]);
        String sha = parts[2].toLowerCase(Locale.US);
        if (assetName.length() == 0 || size <= 0) {
            throw new SecurityException("invalid dex part");
        }
        return new DexPart(assetName, size, sha);
    }

    private static ClassLoader createMemoryDexLoader(List<byte[]> dexBytes, ClassLoader parent) throws Exception {
        ByteBuffer[] buffers = new ByteBuffer[dexBytes.size()];
        for (int index = 0; index < dexBytes.size(); index++) {
            buffers[index] = ByteBuffer.wrap(dexBytes.get(index));
        }

        Class<?> loaderClass = Class.forName("dalvik.system.InMemoryDexClassLoader");
        Constructor<?> constructor = loaderClass.getConstructor(ByteBuffer[].class, ClassLoader.class);
        return (ClassLoader) constructor.newInstance(new Object[]{buffers, parent});
    }

    private static ClassLoader createFileDexLoader(Context context, List<byte[]> dexBytes, ClassLoader parent) throws Exception {
        File cacheRoot = getCodeCacheDirCompat(context);
        File dexDir = new File(cacheRoot, "z1_guard_dex");
        File optimizedDir = new File(cacheRoot, "z1_guard_opt");
        if (!dexDir.exists() && !dexDir.mkdirs()) {
            throw new SecurityException("create dex cache failed");
        }
        if (!optimizedDir.exists() && !optimizedDir.mkdirs()) {
            throw new SecurityException("create optimized cache failed");
        }

        ArrayList<File> tempFiles = new ArrayList<File>();
        StringBuilder dexPath = new StringBuilder();
        for (int index = 0; index < dexBytes.size(); index++) {
            byte[] bytes = dexBytes.get(index);
            File dexFile = new File(dexDir, "payload_" + index + "_" + trimDigest(sha256Hex(bytes)) + ".dex");
            FileOutputStream output = null;
            try {
                output = new FileOutputStream(dexFile);
                output.write(bytes);
                output.flush();
            } finally {
                closeQuietly(output);
            }
            if (dexPath.length() > 0) {
                dexPath.append(File.pathSeparator);
            }
            dexPath.append(dexFile.getAbsolutePath());
            tempFiles.add(dexFile);
        }

        ClassLoader loader = new DexClassLoader(
                dexPath.toString(),
                optimizedDir.getAbsolutePath(),
                null,
                parent
        );
        for (int index = 0; index < tempFiles.size(); index++) {
            try {
                tempFiles.get(index).delete();
            } catch (Throwable ignored) {
            }
        }
        return loader;
    }

    private static File getCodeCacheDirCompat(Context context) {
        File directory = Build.VERSION.SDK_INT >= 21 ? context.getCodeCacheDir() : context.getCacheDir();
        if (directory == null) {
            directory = context.getCacheDir();
        }
        if (directory == null) {
            directory = context.getFilesDir();
        }
        if (directory == null) {
            throw new SecurityException("missing cache dir");
        }
        return directory;
    }

    private static void injectDexElements(ClassLoader targetLoader, ClassLoader payloadLoader) throws Exception {
        Object targetPathList = readField(targetLoader, "pathList");
        Object payloadPathList = readField(payloadLoader, "pathList");
        Field targetDexElementsField = findField(targetPathList.getClass(), "dexElements");
        Field payloadDexElementsField = findField(payloadPathList.getClass(), "dexElements");
        Object targetElements = targetDexElementsField.get(targetPathList);
        Object payloadElements = payloadDexElementsField.get(payloadPathList);
        targetDexElementsField.set(targetPathList, mergeArrays(targetElements, payloadElements));
    }

    private static Object mergeArrays(Object first, Object second) {
        int firstLength = Array.getLength(first);
        int secondLength = Array.getLength(second);
        Class<?> componentType = first.getClass().getComponentType();
        Object merged = Array.newInstance(componentType, firstLength + secondLength);
        for (int index = 0; index < firstLength; index++) {
            Array.set(merged, index, Array.get(first, index));
        }
        for (int index = 0; index < secondLength; index++) {
            Array.set(merged, firstLength + index, Array.get(second, index));
        }
        return merged;
    }

    private static Object readField(Object instance, String name) throws Exception {
        Field field = findField(instance.getClass(), name);
        return field.get(instance);
    }

    private static Object readOptionalField(Object instance, String name) {
        if (instance == null) {
            return null;
        }
        try {
            Field field = findField(instance.getClass(), name);
            return field.get(instance);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static boolean writeOptionalField(Object instance, String name, Object value) {
        if (instance == null) {
            return false;
        }
        try {
            Field field = findField(instance.getClass(), name);
            field.set(instance, value);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static Field findField(Class<?> type, String name) throws NoSuchFieldException {
        Class<?> current = type;
        while (current != null) {
            try {
                Field field = current.getDeclaredField(name);
                field.setAccessible(true);
                return field;
            } catch (NoSuchFieldException ignored) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(name);
    }

    private static int safeCheckPackageName(Context context, StringBuilder reasons) {
        try {
            String packageName = context.getPackageName();
            if (!EXPECTED_PACKAGE_NAME.equals(packageName)) {
                appendReason(reasons, "package-name=" + packageName);
                return 10;
            }
        } catch (Throwable error) {
            appendReason(reasons, "package-name-check-error");
            return 10;
        }
        return 0;
    }

    private static int safeCheckSigningCertificate(Context context, StringBuilder reasons) {
        if (EXPECTED_CERTIFICATE_SHA256.length() == 0) {
            return 0;
        }

        try {
            PackageManager packageManager = context.getPackageManager();
            PackageInfo packageInfo = packageManager.getPackageInfo(
                    context.getPackageName(),
                    Build.VERSION.SDK_INT >= 28
                            ? PackageManager.GET_SIGNING_CERTIFICATES
                            : PackageManager.GET_SIGNATURES
            );
            Signature[] signatures = readCurrentSignatures(packageInfo);
            if (signatures == null || signatures.length == 0) {
                appendReason(reasons, "missing-signature");
                return 10;
            }

            String firstDigest = "";
            for (int index = 0; index < signatures.length; index++) {
                Signature signature = signatures[index];
                if (signature == null) {
                    continue;
                }

                String digest = sha256Hex(signature.toByteArray());
                if (firstDigest.length() == 0) {
                    firstDigest = digest;
                }
                if (EXPECTED_CERTIFICATE_SHA256.equalsIgnoreCase(digest)) {
                    return 0;
                }
            }

            appendReason(reasons, "signature-sha256=" + trimDigest(firstDigest));
            return 10;
        } catch (Throwable error) {
            appendReason(reasons, "signature-check-error");
            return 10;
        }
    }

    private static Signature[] readCurrentSignatures(PackageInfo packageInfo) {
        if (packageInfo == null) {
            return null;
        }

        if (Build.VERSION.SDK_INT >= 28 && packageInfo.signingInfo != null) {
            Signature[] signers = packageInfo.signingInfo.getApkContentsSigners();
            if (signers != null && signers.length > 0) {
                return signers;
            }
            return packageInfo.signingInfo.getSigningCertificateHistory();
        }

        return packageInfo.signatures;
    }

    private static int safeCheckApkIntegrity(Context context, StringBuilder reasons) {
        if (EXPECTED_PROFILE_SHA256.length() == 0 || PROFILE_XOR_KEY_HEX.length() == 0) {
            return 0;
        }

        try {
            byte[] protectedProfile = readAssetBytes(context, PROFILE_ASSET_NAME, PROFILE_READ_LIMIT_BYTES);
            String profileDigest = sha256Hex(protectedProfile);
            if (!EXPECTED_PROFILE_SHA256.equalsIgnoreCase(profileDigest)) {
                appendReason(reasons, "profile-sha256=" + trimDigest(profileDigest));
                return 10;
            }

            byte[] profileBytes = xorBytes(protectedProfile, hexToBytes(PROFILE_XOR_KEY_HEX));
            Map<String, ExpectedEntry> expectedEntries = parseIntegrityProfile(profileBytes);
            ApplicationInfo info = context.getApplicationInfo();
            if (info == null || info.sourceDir == null || info.sourceDir.length() == 0) {
                appendReason(reasons, "missing-source-apk");
                return 10;
            }

            return verifyApkEntries(info.sourceDir, expectedEntries, reasons);
        } catch (Throwable error) {
            appendReason(reasons, "apk-integrity-check-error");
            return 10;
        }
    }

    private static int safeCheckStorageIntegrity(Context context, StringBuilder reasons) {
        if (STORAGE_HMAC_KEY_HEX.length() == 0 || STORAGE_PROFILE_XOR_KEY_HEX.length() == 0) {
            return 0;
        }

        try {
            File profileFile = getStorageProfileFile(context);
            if (!profileFile.exists()) {
                if (isStorageProfileInitialized(context)) {
                    appendReason(reasons, "storage-profile-missing");
                    return 10;
                }
                // First install or first upgrade from an unprotected/third-party-protected build:
                // defer baseline creation until the original Application has completed its own
                // startup migrations and first-run writes.
                return 0;
            }

            byte[] protectedProfile = readFileBytes(profileFile, STORAGE_PROFILE_READ_LIMIT_BYTES);
            Map<String, StorageEntry> expectedEntries = parseStorageProfile(context, protectedProfile);
            Map<String, StorageEntry> actualEntries = scanStorageEntries(context);
            HashMap<String, StorageEntry> remaining = new HashMap<String, StorageEntry>(expectedEntries);

            for (StorageEntry actualEntry : actualEntries.values()) {
                StorageEntry expectedEntry = remaining.remove(actualEntry.path);
                if (expectedEntry == null) {
                    appendReason(reasons, "storage-unexpected=" + trimReason(actualEntry.path));
                    return 10;
                }
                if (expectedEntry.sizeBytes != actualEntry.sizeBytes) {
                    appendReason(reasons, "storage-size=" + trimReason(actualEntry.path));
                    return 10;
                }
                if (!expectedEntry.sha256Hex.equalsIgnoreCase(actualEntry.sha256Hex)) {
                    appendReason(reasons, "storage-sha256=" + trimReason(actualEntry.path));
                    return 10;
                }
            }

            if (!remaining.isEmpty()) {
                appendReason(reasons, "storage-missing=" + trimReason(remaining.keySet().iterator().next()));
                return 10;
            }
        } catch (Throwable error) {
            appendReason(reasons, "storage-check-error=" + error.getClass().getSimpleName());
            return 10;
        }
        return 0;
    }

    public static void startStorageProtection(Context context) {
        if (context == null || storageProtectionStarted
                || STORAGE_HMAC_KEY_HEX.length() == 0
                || STORAGE_PROFILE_XOR_KEY_HEX.length() == 0) {
            return;
        }

        synchronized (Z1Guard.class) {
            if (storageProtectionStarted) {
                return;
            }
            Context appContext = context.getApplicationContext();
            if (appContext == null) {
                appContext = context;
            }
            try {
                ensureStorageObservers(appContext);
                scheduleStorageProfileRefresh(appContext, 0);
                storageProtectionStarted = true;
            } catch (Throwable error) {
                Log.w(TAG, "Storage protection observer start failed", error);
            }
        }
    }

    private static void ensureStorageObservers(final Context context) {
        File dataDir = getDataDirCompat(context);
        observeStoragePath(context, dataDir);
        observeStoragePath(context, new File(dataDir, "shared_prefs"));
        observeStoragePath(context, new File(dataDir, "databases"));
    }

    private static void observeStoragePath(final Context context, File directory) {
        if (directory == null || !directory.exists() || !directory.isDirectory()) {
            return;
        }
        try {
            final String path = directory.getCanonicalPath();
            synchronized (storageObservers) {
                if (!storageObservedPaths.add(path)) {
                    return;
                }
                FileObserver observer = new FileObserver(path, STORAGE_FILE_OBSERVER_MASK) {
                    @Override
                    public void onEvent(int event, String childPath) {
                        ensureStorageObservers(context);
                        scheduleStorageProfileRefresh(context, 800);
                    }
                };
                observer.startWatching();
                storageObservers.add(observer);
            }
        } catch (Throwable error) {
            Log.w(TAG, "Storage observer failed", error);
        }
    }

    private static void scheduleStorageProfileRefresh(final Context context, final long delayMillis) {
        synchronized (Z1Guard.class) {
            if (storageRefreshScheduled) {
                return;
            }
            storageRefreshScheduled = true;
        }

        Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    if (delayMillis > 0) {
                        Thread.sleep(delayMillis);
                    }
                    writeStorageProfile(context);
                } catch (Throwable error) {
                    Log.w(TAG, "Storage profile refresh failed", error);
                } finally {
                    synchronized (Z1Guard.class) {
                        storageRefreshScheduled = false;
                    }
                }
            }
        }, "z1-storage-profile");
        thread.setDaemon(true);
        thread.start();
    }

    private static boolean isStorageProfileInitialized(Context context) {
        return getStorageMarkerFile(context).exists() || getStorageMirrorMarkerFile(context).exists();
    }

    private static void writeStorageProfile(Context context) throws Exception {
        File profileFile = getStorageProfileFile(context);
        File profileDir = profileFile.getParentFile();
        if (profileDir != null && !profileDir.exists() && !profileDir.mkdirs()) {
            throw new SecurityException("create storage profile dir failed");
        }

        Map<String, StorageEntry> entries = scanStorageEntries(context);
        byte[] protectedProfile = encodeStorageProfile(context, entries);
        writeFileBytes(profileFile, protectedProfile);
        writeFileBytes(getStorageMarkerFile(context), new byte[]{'1'});
        writeFileBytes(getStorageMirrorMarkerFile(context), new byte[]{'1'});
    }

    private static byte[] encodeStorageProfile(Context context, Map<String, StorageEntry> entries) throws Exception {
        ArrayList<StorageEntry> sortedEntries = new ArrayList<StorageEntry>(entries.values());
        Collections.sort(sortedEntries, new Comparator<StorageEntry>() {
            @Override
            public int compare(StorageEntry left, StorageEntry right) {
                return left.path.compareTo(right.path);
            }
        });

        StringBuilder body = new StringBuilder();
        body.append("Z1STORAGEPROFILE|1|")
                .append(base64Url(context.getPackageName()))
                .append('\n');
        for (int index = 0; index < sortedEntries.size(); index++) {
            StorageEntry entry = sortedEntries.get(index);
            body.append(base64Url(entry.path))
                    .append('|')
                    .append(entry.sizeBytes)
                    .append('|')
                    .append(entry.modifiedTimeMillis)
                    .append('|')
                    .append(entry.sha256Hex)
                    .append('\n');
        }

        StorageKeys storageKeys = getStorageKeys(context, true);
        byte[] bodyBytes = body.toString().getBytes("UTF-8");
        String signature = hmacSha256Hex(bodyBytes, storageKeys.hmacKey);
        byte[] envelopeBytes = ("Z1STORAGEWRAP|1|" + signature + "\n" + body.toString()).getBytes("UTF-8");
        return xorBytes(envelopeBytes, storageKeys.xorKey);
    }

    private static Map<String, StorageEntry> parseStorageProfile(Context context, byte[] protectedProfile) throws Exception {
        StorageKeys storageKeys = getStorageKeys(context, false);
        byte[] envelopeBytes = xorBytes(protectedProfile, storageKeys.xorKey);
        String envelope = new String(envelopeBytes, "UTF-8");
        int firstNewline = envelope.indexOf('\n');
        if (firstNewline <= 0) {
            throw new SecurityException("bad storage envelope");
        }

        String[] envelopeHeader = envelope.substring(0, firstNewline).split("\\|", -1);
        if (envelopeHeader.length != 3
                || !"Z1STORAGEWRAP".equals(envelopeHeader[0])
                || !"1".equals(envelopeHeader[1])) {
            throw new SecurityException("bad storage envelope header");
        }

        String body = envelope.substring(firstNewline + 1);
        byte[] bodyBytes = body.getBytes("UTF-8");
        String expectedSignature = hmacSha256Hex(bodyBytes, storageKeys.hmacKey);
        if (!expectedSignature.equalsIgnoreCase(envelopeHeader[2])) {
            throw new SecurityException("bad storage profile hmac");
        }

        String[] lines = body.split("\\r?\\n");
        if (lines.length == 0) {
            throw new SecurityException("empty storage profile");
        }

        String[] bodyHeader = lines[0].split("\\|", -1);
        if (bodyHeader.length != 3
                || !"Z1STORAGEPROFILE".equals(bodyHeader[0])
                || !"1".equals(bodyHeader[1])) {
            throw new SecurityException("bad storage profile header");
        }
        String packageName = new String(
                Base64.decode(bodyHeader[2], Base64.URL_SAFE | Base64.NO_WRAP),
                "UTF-8"
        );
        if (!context.getPackageName().equals(packageName)) {
            throw new SecurityException("bad storage package");
        }

        HashMap<String, StorageEntry> entries = new HashMap<String, StorageEntry>();
        for (int index = 1; index < lines.length; index++) {
            String line = lines[index];
            if (line == null || line.length() == 0) {
                continue;
            }
            String[] parts = line.split("\\|", -1);
            if (parts.length != 4) {
                throw new SecurityException("bad storage profile line");
            }
            String path = new String(
                    Base64.decode(parts[0], Base64.URL_SAFE | Base64.NO_WRAP),
                    "UTF-8"
            );
            StorageEntry entry = new StorageEntry(
                    path,
                    Long.parseLong(parts[1]),
                    Long.parseLong(parts[2]),
                    parts[3].toLowerCase(Locale.US)
            );
            if (entries.put(path, entry) != null) {
                throw new SecurityException("duplicate storage path");
            }
        }
        return entries;
    }

    private static Map<String, StorageEntry> scanStorageEntries(Context context) throws Exception {
        HashMap<String, StorageEntry> entries = new HashMap<String, StorageEntry>();
        File dataDir = getDataDirCompat(context);
        scanStorageDirectory(new File(dataDir, "shared_prefs"), "shared_prefs", 0, entries);
        scanStorageDirectory(new File(dataDir, "databases"), "databases", 0, entries);
        return entries;
    }

    private static void scanStorageDirectory(
            File directory,
            String relativePrefix,
            int depth,
            HashMap<String, StorageEntry> entries
    ) throws Exception {
        if (directory == null || !directory.exists() || !directory.isDirectory() || depth > 3) {
            return;
        }

        File[] files = directory.listFiles();
        if (files == null) {
            return;
        }
        for (int index = 0; index < files.length && index < 2000; index++) {
            File file = files[index];
            if (file == null) {
                continue;
            }
            String relativePath = relativePrefix + "/" + file.getName();
            if (file.isDirectory()) {
                scanStorageDirectory(file, relativePath, depth + 1, entries);
                continue;
            }
            if (!file.isFile()) {
                continue;
            }
            entries.put(relativePath, digestStorageFile(file, relativePath));
        }
    }

    private static StorageEntry digestStorageFile(File file, String relativePath) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        FileInputStream input = null;
        try {
            input = new FileInputStream(file);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1) {
                digest.update(buffer, 0, read);
            }
        } finally {
            closeQuietly(input);
        }
        return new StorageEntry(
                relativePath.replace('\\', '/'),
                file.length(),
                file.lastModified(),
                bytesToHex(digest.digest())
        );
    }

    private static StorageKeys getStorageKeys(Context context, boolean allowCreate) throws Exception {
        File keyFile = getStorageKeyFile(context);
        if (keyFile.exists()) {
            byte[] bytes = readFileBytes(keyFile, 128);
            if (bytes.length != 48) {
                throw new SecurityException("bad storage key");
            }
            return new StorageKeys(
                    copyBytes(bytes, 0, 32),
                    copyBytes(bytes, 32, 16)
            );
        }

        if (!allowCreate) {
            throw new SecurityException("storage key missing");
        }

        byte[] bytes = new byte[48];
        new SecureRandom().nextBytes(bytes);
        writeFileBytes(keyFile, bytes);
        return new StorageKeys(
                copyBytes(bytes, 0, 32),
                copyBytes(bytes, 32, 16)
        );
    }

    private static byte[] copyBytes(byte[] bytes, int offset, int length) {
        byte[] result = new byte[length];
        System.arraycopy(bytes, offset, result, 0, length);
        return result;
    }

    private static File getStorageProfileFile(Context context) {
        return new File(getStorageGuardDirectory(context), "storage_profile.dat");
    }

    private static File getStorageKeyFile(Context context) {
        return new File(getStorageGuardDirectory(context), "storage_key.dat");
    }

    private static File getStorageMarkerFile(Context context) {
        return new File(getStorageGuardDirectory(context), "storage_initialized.flag");
    }

    private static File getStorageMirrorMarkerFile(Context context) {
        File filesDir = context.getFilesDir();
        if (filesDir == null) {
            filesDir = getStorageGuardDirectory(context);
        }
        return new File(filesDir, ".z1_guard_storage_initialized");
    }

    private static File getStorageGuardDirectory(Context context) {
        File base = Build.VERSION.SDK_INT >= 21 ? context.getNoBackupFilesDir() : context.getFilesDir();
        if (base == null) {
            base = context.getFilesDir();
        }
        if (base == null) {
            throw new SecurityException("missing storage profile dir");
        }
        return new File(base, "z1_guard");
    }

    private static Map<String, ExpectedEntry> parseIntegrityProfile(byte[] profileBytes) throws Exception {
        String text = new String(profileBytes, "UTF-8");
        String[] lines = text.split("\\r?\\n");
        if (lines.length == 0 || !lines[0].startsWith("Z1APKPROFILE|1|")) {
            throw new SecurityException("bad profile header");
        }

        HashMap<String, ExpectedEntry> expectedEntries = new HashMap<String, ExpectedEntry>();
        for (int index = 1; index < lines.length; index++) {
            String line = lines[index];
            if (line == null || line.length() == 0) {
                continue;
            }

            String[] parts = line.split("\\|", -1);
            if (parts.length != 3) {
                throw new SecurityException("bad profile line");
            }

            String path = new String(
                    Base64.decode(parts[0], Base64.URL_SAFE | Base64.NO_WRAP),
                    "UTF-8"
            );
            long size = Long.parseLong(parts[1]);
            String digest = parts[2].toLowerCase(Locale.US);
            if (expectedEntries.put(path, new ExpectedEntry(size, digest)) != null) {
                throw new SecurityException("duplicate profile path");
            }
        }

        if (expectedEntries.isEmpty()) {
            throw new SecurityException("empty profile");
        }
        return expectedEntries;
    }

    private static int verifyApkEntries(
            String sourceApkPath,
            Map<String, ExpectedEntry> expectedEntries,
            StringBuilder reasons
    ) {
        ZipFile zipFile = null;
        try {
            zipFile = new ZipFile(sourceApkPath);
            HashMap<String, ExpectedEntry> remaining = new HashMap<String, ExpectedEntry>(expectedEntries);
            Enumeration<? extends ZipEntry> entries = zipFile.entries();
            int actualCount = 0;
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                if (entry == null || entry.isDirectory()) {
                    continue;
                }

                String name = normalizeZipEntryName(entry.getName());
                if (name.length() == 0 || shouldIgnoreApkEntry(name)) {
                    continue;
                }

                actualCount++;
                ExpectedEntry expectedEntry = remaining.remove(name);
                if (expectedEntry == null) {
                    appendReason(reasons, "unexpected-entry=" + trimReason(name));
                    return 10;
                }

                DigestResult actualDigest = digestZipEntry(zipFile, entry);
                if (actualDigest.sizeBytes != expectedEntry.sizeBytes) {
                    appendReason(reasons, "entry-size=" + trimReason(name));
                    return 10;
                }
                if (!expectedEntry.sha256Hex.equalsIgnoreCase(actualDigest.sha256Hex)) {
                    appendReason(reasons, "entry-sha256=" + trimReason(name));
                    return 10;
                }
            }

            if (!remaining.isEmpty()) {
                appendReason(reasons, "missing-entry=" + trimReason(remaining.keySet().iterator().next()));
                return 10;
            }
            if (actualCount != expectedEntries.size()) {
                appendReason(reasons, "entry-count=" + actualCount);
                return 10;
            }
        } catch (Throwable error) {
            appendReason(reasons, "apk-entry-check-error");
            return 10;
        } finally {
            closeQuietly(zipFile);
        }

        return 0;
    }

    private static boolean shouldIgnoreApkEntry(String name) {
        return GUARD_DEX_NAME.equals(name)
                || PROFILE_APK_ENTRY_NAME.equals(name)
                || name.startsWith("assets/z1_guard/dex/")
                || isSignatureGeneratedApkEntry(name)
                || "stamp-cert-sha256".equals(name);
    }

    private static boolean isSignatureGeneratedApkEntry(String name) {
        String upper = name.toUpperCase(Locale.US);
        if ("META-INF/MANIFEST.MF".equals(upper)) {
            return true;
        }
        if (!upper.startsWith("META-INF/")) {
            return false;
        }

        String fileName = upper.substring("META-INF/".length());
        if (fileName.indexOf('/') >= 0) {
            return false;
        }
        return fileName.endsWith(".SF")
                || fileName.endsWith(".RSA")
                || fileName.endsWith(".DSA")
                || fileName.endsWith(".EC");
    }

    private static DigestResult digestZipEntry(ZipFile zipFile, ZipEntry entry) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        InputStream input = null;
        long size = 0;
        try {
            input = zipFile.getInputStream(entry);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = input.read(buffer)) != -1) {
                digest.update(buffer, 0, read);
                size += read;
            }
        } finally {
            closeQuietly(input);
        }

        return new DigestResult(size, bytesToHex(digest.digest()));
    }

    private static String normalizeZipEntryName(String name) {
        if (name == null) {
            return "";
        }

        String normalized = name.replace('\\', '/').trim();
        while (normalized.startsWith("/")) {
            normalized = normalized.substring(1);
        }
        while (normalized.startsWith("./")) {
            normalized = normalized.substring(2);
        }
        return normalized;
    }

    private static int safeCheckDebuggable(Context context, StringBuilder reasons) {
        try {
            ApplicationInfo info = context.getApplicationInfo();
            if (info != null && (info.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                appendReason(reasons, "debuggable-app");
                return 2;
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static int safeCheckTracerPid(StringBuilder reasons) {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new FileReader("/proc/self/status"));
            String line;
            while ((line = reader.readLine()) != null) {
                if (!line.startsWith("TracerPid:")) {
                    continue;
                }
                String value = line.substring("TracerPid:".length()).trim();
                if (!"0".equals(value)) {
                    appendReason(reasons, "tracer-pid=" + value);
                    return 6;
                }
                return 0;
            }
        } catch (Throwable ignored) {
        } finally {
            closeQuietly(reader);
        }
        return 0;
    }

    private static int safeCheckPrivateFiles(Context context, StringBuilder reasons) {
        try {
            HashSet<String> seen = new HashSet<String>();
            File dataDir = getDataDirCompat(context);
            int score = 0;
            score = Math.max(score, scanPrivateRoot(dataDir, seen, reasons));
            score = Math.max(score, scanPrivateRoot(context.getFilesDir(), seen, reasons));
            score = Math.max(score, scanPrivateRoot(context.getCacheDir(), seen, reasons));
            if (Build.VERSION.SDK_INT >= 21) {
                score = Math.max(score, scanPrivateRoot(context.getCodeCacheDir(), seen, reasons));
                score = Math.max(score, scanPrivateRoot(context.getNoBackupFilesDir(), seen, reasons));
            }
            return score;
        } catch (Throwable ignored) {
            return 0;
        }
    }

    private static File getDataDirCompat(Context context) {
        if (Build.VERSION.SDK_INT >= 24) {
            return context.getDataDir();
        }
        File filesDir = context.getFilesDir();
        return filesDir == null ? null : filesDir.getParentFile();
    }

    private static int scanPrivateRoot(File root, HashSet<String> seen, StringBuilder reasons) {
        if (root == null || !root.exists()) {
            return 0;
        }
        try {
            String canonical = root.getCanonicalPath();
            if (!seen.add(canonical)) {
                return 0;
            }
        } catch (Throwable ignored) {
        }
        return scanPrivateDirectory(root, 0, 0, reasons);
    }

    private static int scanPrivateDirectory(File directory, int depth, int visited, StringBuilder reasons) {
        if (directory == null || !directory.exists() || depth > 5 || visited > 1500) {
            return 0;
        }
        File[] files = directory.listFiles();
        if (files == null) {
            return 0;
        }

        int bestScore = 0;
        for (int i = 0; i < files.length && i < 600; i++) {
            File file = files[i];
            if (file == null) {
                continue;
            }
            if (file.isDirectory()) {
                bestScore = Math.max(bestScore, scanPrivateDirectory(file, depth + 1, visited + i + 1, reasons));
                continue;
            }
            int score = scoreSuspiciousPrivateFile(file);
            if (score >= 6) {
                appendReason(reasons, "private-injection-file=" + file.getAbsolutePath());
                return score;
            }
            bestScore = Math.max(bestScore, score);
        }
        return bestScore;
    }

    private static int scoreSuspiciousPrivateFile(File file) {
        try {
            if (isKnownRuntimePluginFile(file)) {
                return 0;
            }
            String name = file.getName().toLowerCase();
            if (containsHighRiskToken(name)) {
                return 6;
            }
            if (file.canExecute()) {
                return isElf(file) ? 6 : 4;
            }
            if (name.endsWith(".so") || name.endsWith(".dex") || name.endsWith(".jar") || name.endsWith(".apk")) {
                return isElf(file) ? 6 : 5;
            }
            if (name.endsWith(".js") || name.endsWith(".config")) {
                return containsHighRiskToken(name) ? 6 : 3;
            }
            if (isElf(file)) {
                return 6;
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static boolean isKnownRuntimePluginFile(File file) {
        try {
            String path = file.getAbsolutePath().replace('\\', '/');
            String lowerPath = path.toLowerCase(Locale.US);
            int marker = lowerPath.indexOf("/files/pangle_p/");
            if (marker < 0 || !lowerPath.endsWith(".so")) {
                return false;
            }

            String relative = lowerPath.substring(marker + "/files/pangle_p/".length());
            if (!relative.startsWith("com.byted.")) {
                return false;
            }
            return relative.indexOf("/version-") > 0
                    && relative.indexOf("/lib/") > 0
                    && relative.indexOf("..") < 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private static boolean isElf(File file) {
        FileInputStream input = null;
        try {
            byte[] magic = new byte[4];
            input = new FileInputStream(file);
            if (input.read(magic) != 4) {
                return false;
            }
            return magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
        } catch (Throwable ignored) {
            return false;
        } finally {
            closeQuietly(input);
        }
    }

    private static int safeCheckProcMaps(StringBuilder reasons) {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new FileReader("/proc/self/maps"));
            String line;
            int executableAnonymous = 0;
            while ((line = reader.readLine()) != null) {
                String lower = line.toLowerCase();
                if (containsHighRiskToken(lower)) {
                    appendReason(reasons, "maps=" + trimReason(line));
                    return 6;
                }
                if (line.indexOf("rwxp") > 0 && lower.indexOf("/dev/ashmem/dalvik") < 0 && lower.indexOf("[anon:dalvik") < 0) {
                    executableAnonymous++;
                }
            }
            if (executableAnonymous >= 2) {
                appendReason(reasons, "unexpected-rwx-maps");
                return 4;
            }
        } catch (Throwable ignored) {
        } finally {
            closeQuietly(reader);
        }
        return 0;
    }

    private static int safeCheckThreads(StringBuilder reasons) {
        try {
            File taskDir = new File("/proc/self/task");
            File[] tasks = taskDir.listFiles();
            if (tasks == null) {
                return 0;
            }
            for (int i = 0; i < tasks.length; i++) {
                File comm = new File(tasks[i], "comm");
                String name = readFirstLine(comm);
                if (name == null) {
                    continue;
                }
                String lower = name.toLowerCase();
                if (containsHighRiskToken(lower) || lower.indexOf("gmain") >= 0 || lower.indexOf("gdbus") >= 0) {
                    appendReason(reasons, "thread=" + name.trim());
                    return 6;
                }
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static int safeCheckHookClassesAndStack(StringBuilder reasons) {
        try {
            String[] classNames = new String[]{
                    "de.robv.android.xposed.XposedBridge",
                    "de.robv.android.xposed.XC_MethodHook",
                    "org.lsposed.lspd.impl.LSPosedBridge",
                    "org.lsposed.lspd.nativebridge.HookBridge",
                    "org.lsposed.hiddenapibypass.HiddenApiBypass",
                    "com.swift.sandhook.SandHook",
                    "com.swift.sandhook.xposedcompat.XposedCompat",
                    "me.weishu.epic.art.Epic",
                    "me.weishu.epic.art.entry.Entry",
                    "com.taobao.android.dexposed.DexposedBridge",
                    "com.wind.meditor.core.FileProcesser",
                    "com.junge.algorithmaide.AlgorithmAide"
            };
            for (int index = 0; index < classNames.length; index++) {
                if (isClassPresent(classNames[index])) {
                    appendReason(reasons, "hook-class=" + classNames[index]);
                    return 6;
                }
            }

            StackTraceElement[] stack = Thread.currentThread().getStackTrace();
            if (stack != null) {
                for (int index = 0; index < stack.length; index++) {
                    StackTraceElement element = stack[index];
                    if (element == null) {
                        continue;
                    }
                    String token = (element.getClassName() + "." + element.getMethodName()).toLowerCase(Locale.US);
                    if (containsHighRiskToken(token)) {
                        appendReason(reasons, "hook-stack=" + trimReason(token));
                        return 6;
                    }
                }
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static boolean isClassPresent(String className) {
        try {
            ClassLoader loader = Z1Guard.class.getClassLoader();
            Class.forName(className, false, loader);
            return true;
        } catch (Throwable ignored) {
            try {
                Class.forName(className);
                return true;
            } catch (Throwable ignoredAgain) {
                return false;
            }
        }
    }

    private static int safeCheckRootSignals(StringBuilder reasons) {
        try {
            String tags = Build.TAGS;
            if (tags != null && tags.indexOf("test-keys") >= 0) {
                appendReason(reasons, "test-keys");
                return 2;
            }
            String[] paths = new String[]{
                    "/system/bin/su",
                    "/system/xbin/su",
                    "/sbin/su",
                    "/su/bin/su",
                    "/data/adb/magisk",
                    "/data/adb/ksu",
                    "/data/adb/modules"
            };
            for (int i = 0; i < paths.length; i++) {
                if (new File(paths[i]).exists()) {
                    appendReason(reasons, "root-signal=" + paths[i]);
                    return 2;
                }
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static int safeCheckVpn(Context context, StringBuilder reasons) {
        try {
            ConnectivityManager manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (manager == null || Build.VERSION.SDK_INT < 21) {
                return 0;
            }
            Network[] networks = manager.getAllNetworks();
            if (networks == null) {
                return 0;
            }
            for (int i = 0; i < networks.length; i++) {
                NetworkCapabilities capabilities = manager.getNetworkCapabilities(networks[i]);
                if (capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                    appendReason(reasons, "vpn-transport");
                    return 2;
                }
            }
        } catch (Throwable ignored) {
        }
        return 0;
    }

    private static String readFirstLine(File file) {
        BufferedReader reader = null;
        try {
            reader = new BufferedReader(new FileReader(file));
            return reader.readLine();
        } catch (Throwable ignored) {
            return null;
        } finally {
            closeQuietly(reader);
        }
    }

    private static byte[] readAssetBytes(Context context, String assetName, int maxBytes) throws Exception {
        InputStream input = null;
        try {
            input = context.getAssets().open(assetName);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int total = 0;
            int read;
            while ((read = input.read(buffer)) != -1) {
                total += read;
                if (total > maxBytes) {
                    throw new SecurityException("profile too large");
                }
                output.write(buffer, 0, read);
            }
            return output.toByteArray();
        } finally {
            closeQuietly(input);
        }
    }

    private static byte[] readFileBytes(File file, int maxBytes) throws Exception {
        FileInputStream input = null;
        try {
            input = new FileInputStream(file);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int total = 0;
            int read;
            while ((read = input.read(buffer)) != -1) {
                total += read;
                if (total > maxBytes) {
                    throw new SecurityException("file too large");
                }
                output.write(buffer, 0, read);
            }
            return output.toByteArray();
        } finally {
            closeQuietly(input);
        }
    }

    private static void writeFileBytes(File file, byte[] bytes) throws Exception {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new SecurityException("create parent failed");
        }
        FileOutputStream output = null;
        try {
            output = new FileOutputStream(file);
            output.write(bytes);
            output.flush();
        } finally {
            closeQuietly(output);
        }
    }

    private static byte[] xorBytes(byte[] bytes, byte[] key) {
        if (key == null || key.length == 0) {
            return bytes;
        }

        byte[] output = new byte[bytes.length];
        for (int index = 0; index < bytes.length; index++) {
            output[index] = (byte) (bytes[index] ^ key[index % key.length]);
        }
        return output;
    }

    private static String sha256Hex(byte[] bytes) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        return bytesToHex(digest.digest(bytes));
    }

    private static String hmacSha256Hex(byte[] bytes, byte[] key) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return bytesToHex(mac.doFinal(bytes));
    }

    private static String base64Url(String value) throws Exception {
        return Base64.encodeToString(
                value.getBytes("UTF-8"),
                Base64.URL_SAFE | Base64.NO_WRAP
        );
    }

    private static byte[] hexToBytes(String hex) {
        if (hex == null) {
            return new byte[0];
        }

        String normalized = hex.trim();
        int length = normalized.length();
        if (length == 0 || length % 2 != 0) {
            return new byte[0];
        }

        byte[] output = new byte[length / 2];
        for (int index = 0; index < length; index += 2) {
            output[index / 2] = (byte) Integer.parseInt(normalized.substring(index, index + 2), 16);
        }
        return output;
    }

    private static String bytesToHex(byte[] bytes) {
        char[] hex = new char[bytes.length * 2];
        char[] alphabet = "0123456789abcdef".toCharArray();
        for (int index = 0; index < bytes.length; index++) {
            int value = bytes[index] & 0xff;
            hex[index * 2] = alphabet[value >>> 4];
            hex[index * 2 + 1] = alphabet[value & 0x0f];
        }
        return new String(hex);
    }

    private static String trimDigest(String digest) {
        if (digest == null || digest.length() <= 16) {
            return digest == null ? "" : digest;
        }
        return digest.substring(0, 16);
    }

    private static final class ExpectedEntry {
        private final long sizeBytes;
        private final String sha256Hex;

        private ExpectedEntry(long sizeBytes, String sha256Hex) {
            this.sizeBytes = sizeBytes;
            this.sha256Hex = sha256Hex;
        }
    }

    private static final class DigestResult {
        private final long sizeBytes;
        private final String sha256Hex;

        private DigestResult(long sizeBytes, String sha256Hex) {
            this.sizeBytes = sizeBytes;
            this.sha256Hex = sha256Hex;
        }
    }

    private static final class StorageKeys {
        private final byte[] hmacKey;
        private final byte[] xorKey;

        private StorageKeys(byte[] hmacKey, byte[] xorKey) {
            this.hmacKey = hmacKey;
            this.xorKey = xorKey;
        }
    }

    private static final class StorageEntry {
        private final String path;
        private final long sizeBytes;
        private final long modifiedTimeMillis;
        private final String sha256Hex;

        private StorageEntry(String path, long sizeBytes, long modifiedTimeMillis, String sha256Hex) {
            this.path = path;
            this.sizeBytes = sizeBytes;
            this.modifiedTimeMillis = modifiedTimeMillis;
            this.sha256Hex = sha256Hex;
        }
    }

    private static final class DexLoadResult {
        private final ArrayList<byte[]> dexBytes;

        private DexLoadResult(ArrayList<byte[]> dexBytes) {
            this.dexBytes = dexBytes;
        }
    }

    private static final class DexEntry {
        private final String name;
        private final long sizeBytes;
        private final String sha256Hex;
        private final ArrayList<DexPart> parts;

        private DexEntry(String name, long sizeBytes, String sha256Hex, ArrayList<DexPart> parts) {
            this.name = name;
            this.sizeBytes = sizeBytes;
            this.sha256Hex = sha256Hex;
            this.parts = parts;
        }
    }

    private static final class DexPart {
        private final String assetName;
        private final long sizeBytes;
        private final String sha256Hex;

        private DexPart(String assetName, long sizeBytes, String sha256Hex) {
            this.assetName = assetName;
            this.sizeBytes = sizeBytes;
            this.sha256Hex = sha256Hex;
        }
    }

    private static boolean containsHighRiskToken(String value) {
        return value.indexOf("frida") >= 0
                || value.indexOf("gum-js") >= 0
                || value.indexOf("gadget") >= 0
                || value.indexOf("re.frida") >= 0
                || value.indexOf("xposed") >= 0
                || value.indexOf("lsposed") >= 0
                || value.indexOf("lspatch") >= 0
                || value.indexOf("edxp") >= 0
                || value.indexOf("riru") >= 0
                || value.indexOf("lspd") >= 0
                || value.indexOf("sandhook") >= 0
                || value.indexOf("yahfa") >= 0
                || value.indexOf("epic") >= 0
                || value.indexOf("whale") >= 0
                || value.indexOf("dexposed") >= 0
                || value.indexOf("algorithmaide") >= 0
                || value.indexOf("algorithm") >= 0
                || value.indexOf("junge") >= 0
                || value.indexOf("substrate") >= 0
                || value.indexOf("zygisk") >= 0
                || value.indexOf("magisk") >= 0;
    }

    private static void appendReason(StringBuilder builder, String reason) {
        if (builder.length() > 0) {
            builder.append("; ");
        }
        builder.append(reason);
    }

    private static String trimReason(String reason) {
        if (reason == null) {
            return "";
        }
        String trimmed = reason.trim();
        return trimmed.length() > 180 ? trimmed.substring(0, 180) : trimmed;
    }

    private static void block(String reason) {
        Log.e(TAG, "Blocked APK integrity/runtime risk: " + reason);
        try {
            Process.killProcess(Process.myPid());
        } catch (Throwable ignored) {
        }
        throw new SecurityException("Z1Guard blocked APK integrity/runtime risk: " + reason);
    }

    private static void closeQuietly(java.io.Closeable closeable) {
        if (closeable == null) {
            return;
        }
        try {
            closeable.close();
        } catch (Throwable ignored) {
        }
    }
}
''';
