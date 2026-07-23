import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/services/android_toolchain_resolver.dart';
import 'package:z1_engine/core/services/hardening_artifact_inspector.dart';

class AabPublishingProtectionService {
  AabPublishingProtectionService({
    AndroidToolchainResolver? toolchain,
    Future<Uint8List> Function()? bundletoolLoader,
  }) : _toolchain = toolchain ?? AndroidToolchainResolver(),
       _bundletoolLoader = bundletoolLoader ?? _loadBundledBundletool;

  static const String bundletoolVersion = '1.18.3';
  static const String bundletoolSha256 =
      'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29';

  final AndroidToolchainResolver _toolchain;
  final Future<Uint8List> Function() _bundletoolLoader;
  final HardeningArtifactInspector _inspector = HardeningArtifactInspector();

  Future<AabPublishingProtectionResult> protect({
    required String sourceAabPath,
    required String outputAabPath,
    required AndroidSigningConfig uploadSigningConfig,
    required CodeTransparencySigningConfig transparencySigningConfig,
  }) async {
    final sourceAab = File(sourceAabPath);
    if (!await sourceAab.exists()) {
      throw AabPublishingProtectionException('AAB 文件不存在：$sourceAabPath');
    }
    if (sourceAab.absolute.path == File(outputAabPath).absolute.path) {
      throw const AabPublishingProtectionException('输出路径不能与源 AAB 相同');
    }

    final inspection = await _inspector.inspect(sourceAab.path);
    final logs = <String>['识别为 AAB，模块：${inspection.moduleNames.join('、')}'];
    final workDirectory = await Directory.systemTemp.createTemp(
      'z1_aab_protect_',
    );
    final bundletoolPath = _joinPath(workDirectory.path, 'bundletool.jar');
    final transparencyAabPath = _joinPath(
      workDirectory.path,
      'transparency.aab',
    );
    final signedAabPath = _joinPath(workDirectory.path, 'signed.aab');
    final apksPath = _joinPath(workDirectory.path, 'universal.apks');
    final universalApkPath = _joinPath(workDirectory.path, 'universal.apk');
    final uploadStorePasswordPath = _joinPath(
      workDirectory.path,
      'upload_store.pass',
    );
    final uploadKeyPasswordPath = _joinPath(
      workDirectory.path,
      'upload_key.pass',
    );
    final transparencyStorePasswordPath = _joinPath(
      workDirectory.path,
      'transparency_store.pass',
    );
    final transparencyKeyPasswordPath = _joinPath(
      workDirectory.path,
      'transparency_key.pass',
    );

    try {
      final java = await _toolchain.resolveJavaTool('java');
      final keytool = await _toolchain.resolveJavaTool('keytool');
      final jarsigner = await _toolchain.resolveJavaTool('jarsigner');
      final apksigner = await _toolchain.resolveBuildTool(
        executableName: 'apksigner',
        configuredPath: uploadSigningConfig.apksignerPath,
      );
      await _writeVerifiedBundletool(bundletoolPath);
      logs.add('bundletool：$bundletoolVersion（SHA-256 已校验）');

      final uploadCertificate = await _readCertificateSha256(
        keytool: keytool,
        keystorePath: uploadSigningConfig.keystorePath,
        keyAlias: uploadSigningConfig.keyAlias,
        storePassword: uploadSigningConfig.storePassword,
      );
      final transparencyCertificate = await _readCertificateSha256(
        keytool: keytool,
        keystorePath: transparencySigningConfig.keystorePath,
        keyAlias: transparencySigningConfig.keyAlias,
        storePassword: transparencySigningConfig.storePassword,
      );
      if (uploadCertificate == transparencyCertificate) {
        throw const AabPublishingProtectionException(
          '代码透明密钥必须与 AAB upload 签名密钥使用不同证书',
        );
      }
      logs.add('upload 证书：${_shortDigest(uploadCertificate)}');
      logs.add('代码透明证书：${_shortDigest(transparencyCertificate)}');

      await _runChecked(
        java,
        [
          '-jar',
          bundletoolPath,
          'validate',
          '--bundle=${sourceAab.absolute.path}',
        ],
        logs,
        label: 'bundletool validate（输入）',
      );

      final environment = {
        ...Platform.environment,
        'Z1_UPLOAD_STORE_PASS': uploadSigningConfig.storePassword,
        'Z1_UPLOAD_KEY_PASS': uploadSigningConfig.effectiveKeyPassword,
        'Z1_TRANSPARENCY_STORE_PASS': transparencySigningConfig.storePassword,
        'Z1_TRANSPARENCY_KEY_PASS':
            transparencySigningConfig.effectiveKeyPassword,
      };
      await _writePasswordFile(
        uploadStorePasswordPath,
        uploadSigningConfig.storePassword,
      );
      await _writePasswordFile(
        uploadKeyPasswordPath,
        uploadSigningConfig.effectiveKeyPassword,
      );
      await _writePasswordFile(
        transparencyStorePasswordPath,
        transparencySigningConfig.storePassword,
      );
      await _writePasswordFile(
        transparencyKeyPasswordPath,
        transparencySigningConfig.effectiveKeyPassword,
      );
      await _runChecked(
        java,
        [
          '-jar',
          bundletoolPath,
          'add-transparency',
          '--bundle=${sourceAab.absolute.path}',
          '--output=$transparencyAabPath',
          '--ks=${transparencySigningConfig.keystorePath}',
          '--ks-pass=file:$transparencyStorePasswordPath',
          '--ks-key-alias=${transparencySigningConfig.keyAlias}',
          '--key-pass=file:$transparencyKeyPasswordPath',
        ],
        logs,
        label: 'bundletool add-transparency',
        environment: environment,
      );

      await _runChecked(
        jarsigner,
        [
          '-keystore',
          uploadSigningConfig.keystorePath,
          '-storepass:env',
          'Z1_UPLOAD_STORE_PASS',
          '-keypass:env',
          'Z1_UPLOAD_KEY_PASS',
          '-digestalg',
          'SHA-256',
          '-signedjar',
          signedAabPath,
          transparencyAabPath,
          uploadSigningConfig.keyAlias,
        ],
        logs,
        label: 'jarsigner sign',
        environment: environment,
      );
      await _verifyJarSignature(jarsigner, signedAabPath, logs);
      await _runChecked(
        java,
        ['-jar', bundletoolPath, 'validate', '--bundle=$signedAabPath'],
        logs,
        label: 'bundletool validate（输出）',
      );
      await _runChecked(
        java,
        [
          '-jar',
          bundletoolPath,
          'check-transparency',
          '--mode=bundle',
          '--bundle=$signedAabPath',
        ],
        logs,
        label: 'bundletool check-transparency',
      );
      await _runChecked(
        java,
        [
          '-jar',
          bundletoolPath,
          'build-apks',
          '--bundle=$signedAabPath',
          '--output=$apksPath',
          '--mode=universal',
          '--overwrite',
          '--ks=${uploadSigningConfig.keystorePath}',
          '--ks-pass=file:$uploadStorePasswordPath',
          '--ks-key-alias=${uploadSigningConfig.keyAlias}',
          '--key-pass=file:$uploadKeyPasswordPath',
        ],
        logs,
        label: 'bundletool build-apks',
        environment: environment,
      );
      await _extractUniversalApk(apksPath, universalApkPath);
      await _runChecked(
        apksigner,
        ['verify', '--verbose', '--print-certs', universalApkPath],
        logs,
        label: 'apksigner verify（universal APK）',
      );

      final outputFile = File(outputAabPath);
      await outputFile.parent.create(recursive: true);
      final temporaryOutput = File('${outputFile.path}.z1tmp');
      if (await temporaryOutput.exists()) {
        await temporaryOutput.delete();
      }
      await File(signedAabPath).copy(temporaryOutput.path);
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await temporaryOutput.rename(outputFile.path);
      logs.add('AAB 发布保护完成：${outputFile.path}');

      return AabPublishingProtectionResult(
        outputAabPath: outputFile.path,
        moduleNames: inspection.moduleNames,
        uploadCertificateSha256: uploadCertificate,
        transparencyCertificateSha256: transparencyCertificate,
        logs: logs,
      );
    } on AndroidToolchainException catch (error) {
      throw AabPublishingProtectionException(error.message);
    } finally {
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _writeVerifiedBundletool(String outputPath) async {
    final bytes = await _bundletoolLoader();
    final actualSha256 = sha256.convert(bytes).toString();
    if (actualSha256 != bundletoolSha256) {
      throw AabPublishingProtectionException(
        '内置 bundletool 摘要异常：$actualSha256',
      );
    }
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }

  Future<void> _writePasswordFile(String path, String password) async {
    await File(path).writeAsString(password, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', path]);
    }
  }

  Future<String> _readCertificateSha256({
    required String keytool,
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
  }) async {
    final result = await Process.run(
      keytool,
      [
        '-exportcert',
        '-rfc',
        '-keystore',
        keystorePath,
        '-alias',
        keyAlias,
        '-storepass:env',
        'Z1_KEYSTORE_PASS',
      ],
      environment: {...Platform.environment, 'Z1_KEYSTORE_PASS': storePassword},
    );
    if (result.exitCode != 0) {
      throw AabPublishingProtectionException(
        '读取签名证书失败：${_summarizeOutput(result)}',
      );
    }
    final pem = result.stdout.toString();
    final base64Body = pem
        .split(RegExp(r'\r?\n'))
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join();
    try {
      return sha256.convert(base64.decode(base64Body)).toString();
    } on FormatException {
      throw const AabPublishingProtectionException('读取签名证书失败：证书格式异常');
    }
  }

  Future<void> _extractUniversalApk(
    String apksPath,
    String outputApkPath,
  ) async {
    final archive = ZipDecoder().decodeBytes(
      await File(apksPath).readAsBytes(),
    );
    final universalEntry = archive.files.where(
      (entry) =>
          entry.isFile && entry.name.replaceAll(r'\', '/') == 'universal.apk',
    );
    if (universalEntry.isEmpty) {
      throw const AabPublishingProtectionException(
        'bundletool 输出中未找到 universal.apk',
      );
    }
    await File(
      outputApkPath,
    ).writeAsBytes(universalEntry.first.content as List<int>, flush: true);
  }

  Future<void> _runChecked(
    String executable,
    List<String> arguments,
    List<String> logs, {
    required String label,
    Map<String, String>? environment,
  }) async {
    logs.add('$label：${_redactedCommand(executable, arguments)}');
    final result = await Process.run(
      executable,
      arguments,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw AabPublishingProtectionException(
        '$label 失败：${_summarizeOutput(result)}',
      );
    }
    final output = [
      result.stdout.toString().trim(),
      result.stderr.toString().trim(),
    ].where((value) => value.isNotEmpty).join('\n');
    if (output.isNotEmpty) {
      logs.add(output);
    }
  }

  Future<void> _verifyJarSignature(
    String jarsigner,
    String signedAabPath,
    List<String> logs,
  ) async {
    logs.add('jarsigner verify --strict');
    final strictResult = await Process.run(jarsigner, [
      '-verify',
      '-strict',
      '-certs',
      signedAabPath,
    ]);
    if (strictResult.exitCode == 0) {
      return;
    }

    final strictOutput = _summarizeOutput(strictResult);
    final regularResult = await Process.run(jarsigner, [
      '-verify',
      '-certs',
      signedAabPath,
    ]);
    if (regularResult.exitCode != 0) {
      throw AabPublishingProtectionException(
        'jarsigner verify 失败：${_summarizeOutput(regularResult)}',
      );
    }
    final regularOutput = _summarizeOutput(regularResult).toLowerCase();
    if (!regularOutput.contains('jar verified') &&
        !regularOutput.contains('jar 已验证')) {
      throw AabPublishingProtectionException(
        'jarsigner 未确认签名完整性：${_summarizeOutput(regularResult)}',
      );
    }
    logs.add('jarsigner strict 警告（自签名证书/无时间戳）：$strictOutput');
    logs.add('jarsigner 加密完整性验证通过');
  }

  String _redactedCommand(String executable, List<String> arguments) {
    return [executable, ...arguments]
        .map(
          (value) => value
              .replaceAll(RegExp(r'env:[A-Z0-9_]+'), 'env:***')
              .replaceAll(RegExp(r'file:[^\s]+\.pass'), 'file:***'),
        )
        .join(' ');
  }

  String _summarizeOutput(ProcessResult result) {
    return [
      result.stdout.toString().trim(),
      result.stderr.toString().trim(),
    ].where((value) => value.isNotEmpty).join('\n').trim();
  }

  String _shortDigest(String value) {
    return value.length <= 16 ? value : '${value.substring(0, 16)}...';
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }

  static Future<Uint8List> _loadBundledBundletool() async {
    final data = await rootBundle.load(
      'assets/tools/bundletool-all-1.18.3.jar',
    );
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

class AabPublishingProtectionResult {
  const AabPublishingProtectionResult({
    required this.outputAabPath,
    required this.moduleNames,
    required this.uploadCertificateSha256,
    required this.transparencyCertificateSha256,
    required this.logs,
  });

  final String outputAabPath;
  final List<String> moduleNames;
  final String uploadCertificateSha256;
  final String transparencyCertificateSha256;
  final List<String> logs;
}

class AabPublishingProtectionException implements Exception {
  const AabPublishingProtectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
