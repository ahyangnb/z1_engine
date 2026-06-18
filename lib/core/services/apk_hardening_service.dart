import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';

class ApkHardeningService {
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

      final nextDexIndex = _nextDexIndex(decodedDirectory);
      final guardDexName = _dexFileName(nextDexIndex);
      logs.add('目标包名：$packageName');
      logs.add('注入 dex：$guardDexName');

      await manifestFile.writeAsString(
        _injectGuardProvider(manifestContent, packageName),
      );

      final expectedCertificateSha256 = await _readSigningCertificateSha256(
        keytoolExecutable: keytool,
        signingConfig: signingConfig,
      );
      logs.add('签名证书 SHA-256：${_shortDigest(expectedCertificateSha256)}');

      final profileAssetName = 'z1_guard/profile.dat';
      final profileApkEntryName = 'assets/$profileAssetName';
      final ignoredProfileEntries = {guardDexName, profileApkEntryName};
      final placeholderConfig = _GuardBuildConfig(
        expectedPackageName: packageName,
        expectedCertificateSha256: expectedCertificateSha256,
        guardDexName: guardDexName,
        profileAssetName: profileAssetName,
        profileApkEntryName: profileApkEntryName,
        expectedProfileSha256: '',
        profileXorKeyHex: '',
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
        guardDexName: guardDexName,
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
        guardDexName: guardDexName,
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
      logs.add('基线资产 SHA-256：${_shortDigest(expectedProfileSha256)}');

      final finalConfig = _GuardBuildConfig(
        expectedPackageName: packageName,
        expectedCertificateSha256: expectedCertificateSha256,
        guardDexName: guardDexName,
        profileAssetName: profileAssetName,
        profileApkEntryName: profileApkEntryName,
        expectedProfileSha256: expectedProfileSha256,
        profileXorKeyHex: _bytesToHex(profileXorKey),
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
        guardDexName: guardDexName,
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
        guardDexName: guardDexName,
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
      _joinPath(packageDirectory.path, 'Z1Guard.java'),
    ).writeAsString(_buildGuardJava(config));
  }

  String _injectGuardProvider(String manifestContent, String packageName) {
    if (manifestContent.contains('com.z1.guard.Z1GuardProvider')) {
      return manifestContent;
    }

    final authorities = '$packageName.z1guard';
    final provider =
        '''
        <provider android:name="com.z1.guard.Z1GuardProvider" android:authorities="$authorities" android:exported="false" android:initOrder="1000" />
''';
    final closeApplicationIndex = manifestContent.lastIndexOf('</application>');
    if (closeApplicationIndex < 0) {
      throw const ApkHardeningException(
        'AndroidManifest.xml 缺少 application 节点',
      );
    }

    return manifestContent.replaceRange(
      closeApplicationIndex,
      closeApplicationIndex,
      provider,
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

    final upperPath = normalizedPath.toUpperCase();
    return upperPath.startsWith('META-INF/') ||
        normalizedPath == 'stamp-cert-sha256';
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

  String _dexFileName(int dexIndex) {
    return dexIndex <= 1 ? 'classes.dex' : 'classes$dexIndex.dex';
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

  int _nextDexIndex(Directory decodedDirectory) {
    var maxIndex = 0;
    final dexPattern = RegExp(r'^classes([0-9]*)\.dex$');
    final smaliPattern = RegExp(r'^smali(?:_classes([0-9]+))?$');
    for (final entity in decodedDirectory.listSync()) {
      final name = _lastPathSegment(entity.path);
      final dexMatch = dexPattern.firstMatch(name);
      if (dexMatch != null) {
        final index = int.tryParse(dexMatch.group(1) ?? '') ?? 1;
        if (index > maxIndex) {
          maxIndex = index;
        }
        continue;
      }

      final smaliMatch = smaliPattern.firstMatch(name);
      if (smaliMatch != null) {
        final index = int.tryParse(smaliMatch.group(1) ?? '') ?? 1;
        if (index > maxIndex) {
          maxIndex = index;
        }
      }
    }

    return maxIndex + 1;
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
  });

  final String expectedPackageName;
  final String expectedCertificateSha256;
  final String guardDexName;
  final String profileAssetName;
  final String profileApkEntryName;
  final String expectedProfileSha256;
  final String profileXorKeyHex;
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
import android.os.Process;
import android.util.Base64;
import android.util.Log;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public final class Z1Guard {
    private static final String TAG = "Z1Guard";
    private static final String EXPECTED_PACKAGE_NAME = __EXPECTED_PACKAGE_NAME__;
    private static final String EXPECTED_CERTIFICATE_SHA256 = __EXPECTED_CERTIFICATE_SHA256__;
    private static final String GUARD_DEX_NAME = __GUARD_DEX_NAME__;
    private static final String PROFILE_ASSET_NAME = __PROFILE_ASSET_NAME__;
    private static final String PROFILE_APK_ENTRY_NAME = __PROFILE_APK_ENTRY_NAME__;
    private static final String EXPECTED_PROFILE_SHA256 = __EXPECTED_PROFILE_SHA256__;
    private static final String PROFILE_XOR_KEY_HEX = __PROFILE_XOR_KEY_HEX__;
    private static final int PROFILE_READ_LIMIT_BYTES = 16 * 1024 * 1024;
    private static volatile boolean initialized;

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

        StringBuilder reasons = new StringBuilder();
        int score = 0;
        score += safeCheckPackageName(appContext, reasons);
        score += safeCheckSigningCertificate(appContext, reasons);
        score += safeCheckApkIntegrity(appContext, reasons);
        score += safeCheckDebuggable(appContext, reasons);
        score += safeCheckTracerPid(reasons);
        score += safeCheckPrivateFiles(appContext, reasons);
        score += safeCheckProcMaps(reasons);
        score += safeCheckThreads(reasons);
        score += safeCheckRootSignals(reasons);
        score += safeCheckVpn(appContext, reasons);

        if (score >= 6) {
            block(reasons.toString());
        }
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
        String upper = name.toUpperCase(Locale.US);
        return GUARD_DEX_NAME.equals(name)
                || PROFILE_APK_ENTRY_NAME.equals(name)
                || upper.startsWith("META-INF/")
                || "stamp-cert-sha256".equals(name);
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
                if (lower.indexOf("frida") >= 0 || lower.indexOf("gum-js") >= 0 || lower.indexOf("gmain") >= 0 || lower.indexOf("gdbus") >= 0) {
                    appendReason(reasons, "thread=" + name.trim());
                    return 6;
                }
            }
        } catch (Throwable ignored) {
        }
        return 0;
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

    private static boolean containsHighRiskToken(String value) {
        return value.indexOf("frida") >= 0
                || value.indexOf("gum-js") >= 0
                || value.indexOf("gadget") >= 0
                || value.indexOf("re.frida") >= 0
                || value.indexOf("xposed") >= 0
                || value.indexOf("lsposed") >= 0
                || value.indexOf("lspatch") >= 0
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
