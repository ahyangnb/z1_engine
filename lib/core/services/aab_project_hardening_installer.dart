import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/services/aab_publishing_protection_service.dart';
import 'package:z1_engine/core/services/android_toolchain_resolver.dart';
import 'package:z1_engine/core/services/apk_hardening_service.dart';

typedef ProjectGuardDexBuilder =
    Future<ApkProjectGuardDexResult> Function({
      required String outputDexPath,
      required String originalApplicationName,
      required List<String> acceptedCertificateSha256,
    });

typedef ProjectCertificateReader =
    Future<String> Function({
      required String keystorePath,
      required String keyAlias,
      required String storePassword,
    });

class AabProjectHardeningInstaller {
  AabProjectHardeningInstaller({
    AndroidToolchainResolver? toolchain,
    ProjectGuardDexBuilder? guardDexBuilder,
    ProjectCertificateReader? certificateReader,
    Future<Uint8List> Function()? bundletoolLoader,
  }) : _toolchain = toolchain ?? AndroidToolchainResolver(),
       _guardDexBuilder = guardDexBuilder ?? _defaultGuardDexBuilder,
       _certificateReader = certificateReader,
       _bundletoolLoader = bundletoolLoader ?? _loadBundledBundletool;

  static const String _managedDirectoryName = 'z1_guard';
  static const String _metadataFileName = 'install_metadata.json';
  static const String _applicationName = 'com.z1.guard.Z1GuardApplication';
  static const String _providerName = 'com.z1.guard.Z1GuardProvider';

  final AndroidToolchainResolver _toolchain;
  final ProjectGuardDexBuilder _guardDexBuilder;
  final ProjectCertificateReader? _certificateReader;
  final Future<Uint8List> Function() _bundletoolLoader;

  static Future<ApkProjectGuardDexResult> _defaultGuardDexBuilder({
    required String outputDexPath,
    required String originalApplicationName,
    required List<String> acceptedCertificateSha256,
  }) {
    return ApkHardeningService().buildProjectGuardDex(
      outputDexPath: outputDexPath,
      originalApplicationName: originalApplicationName,
      acceptedCertificateSha256: acceptedCertificateSha256,
    );
  }

  Future<AabProjectHardeningResult> install({
    required String projectPath,
    required AndroidSigningConfig uploadSigningConfig,
    required CodeTransparencySigningConfig transparencySigningConfig,
    required List<String> playCertificateSha256,
  }) async {
    final androidDirectory = _resolveAndroidDirectory(projectPath);
    final appBuildFile = _resolveAppBuildFile(androidDirectory);
    final manifestFile = File(
      _joinPath(androidDirectory.path, 'app/src/main/AndroidManifest.xml'),
    );
    if (!await manifestFile.exists()) {
      throw const AabProjectHardeningException(
        '未找到 app/src/main/AndroidManifest.xml',
      );
    }

    final normalizedPlayCertificates = playCertificateSha256
        .map(_normalizeFingerprint)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedPlayCertificates.isEmpty) {
      throw const AabProjectHardeningException(
        '至少需要一个 Play App Signing SHA-256 指纹',
      );
    }

    final uploadCertificate = await _readCertificateSha256(
      keystorePath: uploadSigningConfig.keystorePath,
      keyAlias: uploadSigningConfig.keyAlias,
      storePassword: uploadSigningConfig.storePassword,
    );
    final transparencyCertificate = await _readCertificateSha256(
      keystorePath: transparencySigningConfig.keystorePath,
      keyAlias: transparencySigningConfig.keyAlias,
      storePassword: transparencySigningConfig.storePassword,
    );
    if (uploadCertificate == transparencyCertificate) {
      throw const AabProjectHardeningException('代码透明密钥必须与 upload 签名密钥使用不同证书');
    }

    final acceptedCertificates = {
      uploadCertificate,
      ...normalizedPlayCertificates,
    }.toList();
    final managedDirectory = Directory(
      _joinPath(androidDirectory.path, _managedDirectoryName),
    );
    await managedDirectory.create(recursive: true);
    final metadataFile = File(
      _joinPath(managedDirectory.path, _metadataFileName),
    );
    final logs = <String>['Android 工程：${androidDirectory.path}'];

    late String originalApplicationName;
    late String originalManifestSha256;
    late String patchedManifestSha256;
    late String originalBuildSha256;
    late String patchedBuildSha256;
    final manifestBackup = File('${manifestFile.path}.z1bak');
    final buildBackup = File('${appBuildFile.path}.z1bak');

    if (await metadataFile.exists()) {
      final metadata = _readMetadata(metadataFile);
      originalApplicationName =
          metadata['originalApplicationName'] as String? ??
          'android.app.Application';
      originalManifestSha256 =
          metadata['originalManifestSha256'] as String? ?? '';
      patchedManifestSha256 =
          metadata['patchedManifestSha256'] as String? ?? '';
      originalBuildSha256 = metadata['originalBuildSha256'] as String? ?? '';
      patchedBuildSha256 = metadata['patchedBuildSha256'] as String? ?? '';
      if (_sha256File(manifestFile) != patchedManifestSha256 ||
          _sha256File(appBuildFile) != patchedBuildSha256) {
        throw const AabProjectHardeningException('源码工程加固文件已被修改，请先处理冲突后再重新接入');
      }
      logs.add('检测到已有 AAB Guard 接入，更新密钥与构建工具');
    } else {
      if (await manifestBackup.exists() || await buildBackup.exists()) {
        throw const AabProjectHardeningException(
          '发现不完整的 .z1bak 备份，拒绝覆盖，请先人工确认',
        );
      }
      final manifestContent = await manifestFile.readAsString();
      final manifestPatch = _patchManifest(manifestContent, appBuildFile);
      originalApplicationName = manifestPatch.originalApplicationName;
      originalManifestSha256 = _sha256Text(manifestContent);
      await manifestFile.copy(manifestBackup.path);
      await manifestFile.writeAsString(manifestPatch.content, flush: true);
      patchedManifestSha256 = _sha256File(manifestFile);

      final buildContent = await appBuildFile.readAsString();
      originalBuildSha256 = _sha256Text(buildContent);
      await appBuildFile.copy(buildBackup.path);
      final patchedBuild = _patchBuildFile(buildContent, appBuildFile.path);
      await appBuildFile.writeAsString(patchedBuild, flush: true);
      patchedBuildSha256 = _sha256File(appBuildFile);
      logs.add('Manifest 已注入 Guard Application/Provider');
      logs.add('Gradle 已接入 AAB 构建后加固任务');
    }

    final guardDexPath = _joinPath(managedDirectory.path, 'guard.dex');
    final guardResult = await _guardDexBuilder(
      outputDexPath: guardDexPath,
      originalApplicationName: originalApplicationName,
      acceptedCertificateSha256: acceptedCertificates,
    );
    logs.addAll(guardResult.logs);

    final bundletoolBytes = await _bundletoolLoader();
    final bundletoolDigest = sha256.convert(bundletoolBytes).toString();
    if (bundletoolDigest != AabPublishingProtectionService.bundletoolSha256) {
      throw AabProjectHardeningException(
        '内置 bundletool 摘要异常：$bundletoolDigest',
      );
    }
    await File(
      _joinPath(managedDirectory.path, 'bundletool.jar'),
    ).writeAsBytes(bundletoolBytes, flush: true);

    final gradleScript = _projectGradleScript
        .replaceAll('__DEX_XOR_KEY_HEX__', guardResult.dexXorKeyHex)
        .replaceAll('__AAB_CODE_HMAC_KEY_HEX__', guardResult.aabCodeHmacKeyHex);
    await File(
      _joinPath(managedDirectory.path, 'z1_aab_guard.gradle'),
    ).writeAsString(gradleScript, flush: true);
    await File(
      _joinPath(managedDirectory.path, 'local.properties'),
    ).writeAsString(
      _localProperties(
        uploadSigningConfig: uploadSigningConfig,
        transparencySigningConfig: transparencySigningConfig,
      ),
      flush: true,
    );
    await _restrictLocalProperties(
      _joinPath(managedDirectory.path, 'local.properties'),
    );
    await _ensureGitIgnore(androidDirectory);

    final metadata = <String, Object?>{
      'version': 1,
      'manifestPath': manifestFile.path,
      'manifestBackupPath': manifestBackup.path,
      'buildPath': appBuildFile.path,
      'buildBackupPath': buildBackup.path,
      'originalApplicationName': originalApplicationName,
      'originalManifestSha256': originalManifestSha256,
      'patchedManifestSha256': patchedManifestSha256,
      'originalBuildSha256': originalBuildSha256,
      'patchedBuildSha256': patchedBuildSha256,
      'uploadCertificateSha256': uploadCertificate,
      'playCertificateSha256': normalizedPlayCertificates,
      'transparencyCertificateSha256': transparencyCertificate,
    };
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
      flush: true,
    );

    logs.add('upload + Play 证书 allowlist：${acceptedCertificates.length} 个');
    logs.add('代码透明密钥已独立配置');
    logs.add('后续非 debug bundle 任务会额外输出 *_z1guard.aab');
    return AabProjectHardeningResult(
      androidDirectoryPath: androidDirectory.path,
      originalApplicationName: originalApplicationName,
      logs: logs,
    );
  }

  Future<AabProjectHardeningResult> remove({
    required String projectPath,
  }) async {
    final androidDirectory = _resolveAndroidDirectory(projectPath);
    final metadataFile = File(
      _joinPath(
        _joinPath(androidDirectory.path, _managedDirectoryName),
        _metadataFileName,
      ),
    );
    if (!await metadataFile.exists()) {
      throw const AabProjectHardeningException('当前工程没有已安装的 AAB Guard');
    }
    final metadata = _readMetadata(metadataFile);
    final manifestFile = File(metadata['manifestPath'] as String);
    final buildFile = File(metadata['buildPath'] as String);
    if (_sha256File(manifestFile) != metadata['patchedManifestSha256'] ||
        _sha256File(buildFile) != metadata['patchedBuildSha256']) {
      throw const AabProjectHardeningException(
        'Manifest 或 Gradle 文件在接入后发生修改，已停止移除以避免覆盖用户改动',
      );
    }

    final manifestBackup = File(metadata['manifestBackupPath'] as String);
    final buildBackup = File(metadata['buildBackupPath'] as String);
    if (!await manifestBackup.exists() || !await buildBackup.exists()) {
      throw const AabProjectHardeningException('源码工程加固备份文件缺失');
    }
    await manifestBackup.copy(manifestFile.path);
    await buildBackup.copy(buildFile.path);
    await manifestBackup.delete();
    await buildBackup.delete();
    await metadataFile.parent.delete(recursive: true);
    return AabProjectHardeningResult(
      androidDirectoryPath: androidDirectory.path,
      originalApplicationName:
          metadata['originalApplicationName'] as String? ?? '',
      logs: const ['已恢复原 Manifest 和 Gradle 文件', 'AAB Guard 源码接入已移除'],
    );
  }

  Directory _resolveAndroidDirectory(String projectPath) {
    final selected = Directory(projectPath.trim());
    final candidates = [
      selected,
      Directory(_joinPath(selected.path, 'android')),
      if (_lastPathSegment(selected.path) == 'app') selected.parent,
    ];
    for (final candidate in candidates) {
      if (_resolveAppBuildFileOrNull(candidate) != null) {
        return candidate.absolute;
      }
    }
    throw const AabProjectHardeningException(
      '未找到 Android 工程，请选择 Flutter 根目录或 Android 工程目录',
    );
  }

  File _resolveAppBuildFile(Directory androidDirectory) {
    final file = _resolveAppBuildFileOrNull(androidDirectory);
    if (file == null) {
      throw const AabProjectHardeningException(
        '未找到 app/build.gradle 或 app/build.gradle.kts',
      );
    }
    return file;
  }

  File? _resolveAppBuildFileOrNull(Directory androidDirectory) {
    for (final name in ['app/build.gradle.kts', 'app/build.gradle']) {
      final file = File(_joinPath(androidDirectory.path, name));
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  _ManifestPatch _patchManifest(String content, File appBuildFile) {
    final applicationMatch = RegExp(
      r'<application\b[^>]*>',
      multiLine: true,
    ).firstMatch(content);
    if (applicationMatch == null) {
      throw const AabProjectHardeningException('Manifest 缺少 application 节点');
    }
    final applicationTag = applicationMatch.group(0)!;
    final nameMatch = RegExp(
      r'android:name\s*=\s*["'
      "'"
      r']([^"'
      "'"
      r']+)["'
      "'"
      r']',
    ).firstMatch(applicationTag);
    final packageName =
        RegExp(
          r'<manifest\b[^>]*\bpackage\s*=\s*["'
          "'"
          r']([^"'
          "'"
          r']+)["'
          "'"
          r']',
        ).firstMatch(content)?.group(1) ??
        _readApplicationId(appBuildFile);
    final rawOriginalName = nameMatch?.group(1) ?? 'android.app.Application';
    final originalName = _normalizeApplicationName(
      rawOriginalName,
      packageName,
    );
    final patchedTag = nameMatch == null
        ? applicationTag.replaceFirst(
            RegExp(r'>$'),
            ' android:name="$_applicationName">',
          )
        : applicationTag.replaceFirst(
            nameMatch.group(0)!,
            'android:name="$_applicationName"',
          );
    final provider =
        '\n        <provider'
        ' android:name="$_providerName"'
        r' android:authorities="${applicationId}.z1guard.init"'
        ' android:exported="false"'
        ' android:initOrder="2147483000" />\n';
    final patched = content.replaceRange(
      applicationMatch.start,
      applicationMatch.end,
      '$patchedTag$provider',
    );
    return _ManifestPatch(
      content: patched,
      originalApplicationName: originalName,
    );
  }

  String _readApplicationId(File buildFile) {
    final content = buildFile.readAsStringSync();
    return RegExp(
          r'(?:applicationId|namespace)\s*(?:=|\s)\s*["'
          "'"
          r']([^"'
          "'"
          r']+)["'
          "'"
          r']',
        ).firstMatch(content)?.group(1) ??
        '';
  }

  String _normalizeApplicationName(String value, String packageName) {
    if (value == 'android.app.Application' || value == r'${applicationName}') {
      return 'android.app.Application';
    }
    if (value.startsWith('.')) {
      return '$packageName$value';
    }
    if (!value.contains('.') && packageName.isNotEmpty) {
      return '$packageName.$value';
    }
    return value;
  }

  String _patchBuildFile(String content, String path) {
    if (content.contains('z1_aab_guard.gradle')) {
      return content;
    }
    final line = path.endsWith('.kts')
        ? 'apply(from = "../z1_guard/z1_aab_guard.gradle")'
        : 'apply from: "../z1_guard/z1_aab_guard.gradle"';
    return '$content\n\n$line\n';
  }

  String _localProperties({
    required AndroidSigningConfig uploadSigningConfig,
    required CodeTransparencySigningConfig transparencySigningConfig,
  }) {
    String property(String name, String value) {
      return '$name=${value.replaceAll(r'\', r'\\').replaceAll('\n', '')}';
    }

    return [
      property('upload.keystore', uploadSigningConfig.keystorePath),
      property('upload.alias', uploadSigningConfig.keyAlias),
      property('upload.storePassword', uploadSigningConfig.storePassword),
      property('upload.keyPassword', uploadSigningConfig.effectiveKeyPassword),
      property('transparency.keystore', transparencySigningConfig.keystorePath),
      property('transparency.alias', transparencySigningConfig.keyAlias),
      property(
        'transparency.storePassword',
        transparencySigningConfig.storePassword,
      ),
      property(
        'transparency.keyPassword',
        transparencySigningConfig.effectiveKeyPassword,
      ),
      '',
    ].join('\n');
  }

  Future<String> _readCertificateSha256({
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
  }) async {
    if (_certificateReader != null) {
      return _normalizeFingerprint(
        await _certificateReader(
          keystorePath: keystorePath,
          keyAlias: keyAlias,
          storePassword: storePassword,
        ),
      );
    }
    final keytool = await _toolchain.resolveJavaTool('keytool');
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
      throw AabProjectHardeningException(
        '读取证书失败：${result.stderr.toString().trim()}',
      );
    }
    final body = result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join();
    return sha256.convert(base64.decode(body)).toString();
  }

  Future<void> _ensureGitIgnore(Directory androidDirectory) async {
    final gitIgnore = File(_joinPath(androidDirectory.path, '.gitignore'));
    final content = await gitIgnore.exists()
        ? await gitIgnore.readAsString()
        : '';
    const marker = 'z1_guard/local.properties';
    if (!content.split(RegExp(r'\r?\n')).contains(marker)) {
      await gitIgnore.writeAsString(
        '${content.isEmpty || content.endsWith('\n') ? content : '$content\n'}'
        '$marker\n',
        flush: true,
      );
    }
  }

  Future<void> _restrictLocalProperties(String path) async {
    if (Platform.isWindows) {
      return;
    }
    await Process.run('chmod', ['600', path]);
  }

  Map<String, Object?> _readMetadata(File file) {
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, Object?>) {
      throw const AabProjectHardeningException('AAB Guard 元数据格式异常');
    }
    return value;
  }

  String _normalizeFingerprint(String value) {
    return value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  }

  String _sha256File(File file) {
    return sha256.convert(file.readAsBytesSync()).toString();
  }

  String _sha256Text(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  String _lastPathSegment(String path) {
    return path
        .replaceAll(r'\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .last;
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

class AabProjectHardeningResult {
  const AabProjectHardeningResult({
    required this.androidDirectoryPath,
    required this.originalApplicationName,
    required this.logs,
  });

  final String androidDirectoryPath;
  final String originalApplicationName;
  final List<String> logs;
}

class AabProjectHardeningException implements Exception {
  const AabProjectHardeningException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ManifestPatch {
  const _ManifestPatch({
    required this.content,
    required this.originalApplicationName,
  });

  final String content;
  final String originalApplicationName;
}

const _projectGradleScript = r'''
// Generated by Z1 Engine. Applied from app/build.gradle(.kts).
import java.security.MessageDigest
import java.util.Base64
import java.util.Properties
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

def z1Root = rootProject.file("z1_guard")
def z1Properties = new Properties()
def z1LocalProperties = new File(z1Root, "local.properties")
if (!z1LocalProperties.exists()) {
    throw new GradleException("Z1 Guard missing z1_guard/local.properties")
}
z1LocalProperties.withInputStream { z1Properties.load(it) }

def z1Value = { String propertyName, String environmentName ->
    def environmentValue = System.getenv(environmentName)
    return environmentValue != null && !environmentValue.isEmpty()
            ? environmentValue
            : z1Properties.getProperty(propertyName, "")
}
def z1Sha256 = { byte[] bytes ->
    MessageDigest.getInstance("SHA-256").digest(bytes).collect {
        String.format("%02x", it & 0xff)
    }.join()
}
def z1Hex = { String value ->
    byte[] output = new byte[value.length() / 2]
    for (int index = 0; index < output.length; index++) {
        output[index] = (byte) Integer.parseInt(value.substring(index * 2, index * 2 + 2), 16)
    }
    return output
}
def z1Xor = { byte[] input, byte[] key ->
    byte[] output = new byte[input.length]
    for (int index = 0; index < input.length; index++) {
        output[index] = (byte) (input[index] ^ key[index % key.length])
    }
    return output
}
def z1HmacSha256 = { byte[] input, byte[] key ->
    Mac mac = Mac.getInstance("HmacSHA256")
    mac.init(new SecretKeySpec(key, "HmacSHA256"))
    return mac.doFinal(input).collect {
        String.format("%02x", it & 0xff)
    }.join()
}
def z1ReadAll = { InputStream input ->
    ByteArrayOutputStream output = new ByteArrayOutputStream()
    byte[] buffer = new byte[64 * 1024]
    int count
    while ((count = input.read(buffer)) >= 0) {
        if (count > 0) output.write(buffer, 0, count)
    }
    return output.toByteArray()
}
def z1AddEntry = { ZipOutputStream output, String name, byte[] bytes ->
    ZipEntry entry = new ZipEntry(name)
    entry.setMethod(ZipEntry.DEFLATED)
    output.putNextEntry(entry)
    output.write(bytes)
    output.closeEntry()
}
def z1Transform = { File sourceAab, File outputAab ->
    byte[] xorKey = z1Hex("__DEX_XOR_KEY_HEX__")
    ZipFile source = new ZipFile(sourceAab)
    List dexEntries = source.entries().findAll {
        !it.isDirectory() && it.name ==~ /base\/dex\/classes\d*\.dex/
    }.sort { left, right -> left.name <=> right.name }
    if (dexEntries.isEmpty()) {
        source.close()
        throw new GradleException("Z1 Guard: base module has no classes*.dex")
    }

    MessageDigest totalDigest = MessageDigest.getInstance("SHA-256")
    long totalSize = 0
    List profileLines = []
    Map<String, byte[]> generatedEntries = [:]
    dexEntries.eachWithIndex { dexEntry, dexIndex ->
        byte[] dexBytes = z1ReadAll(source.getInputStream(dexEntry))
        totalDigest.update(dexBytes)
        totalSize += dexBytes.length
        List partTokens = []
        int partIndex = 0
        for (int offset = 0; offset < dexBytes.length; offset += 512 * 1024) {
            int end = Math.min(offset + 512 * 1024, dexBytes.length)
            byte[] plainPart = Arrays.copyOfRange(dexBytes, offset, end)
            byte[] encryptedPart = z1Xor(plainPart, xorKey)
            String assetName = String.format(
                    "z1_guard/dex/dex_%03d_part_%04d.bin",
                    dexIndex,
                    partIndex
            )
            generatedEntries["base/assets/" + assetName] = encryptedPart
            String encodedName = Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(assetName.getBytes("UTF-8"))
            partTokens.add(encodedName + "," + encryptedPart.length + "," + z1Sha256(encryptedPart))
            partIndex++
        }
        String dexName = dexEntry.name.substring("base/dex/".length())
        String encodedDexName = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(dexName.getBytes("UTF-8"))
        profileLines.add(
                encodedDexName + "|" + dexBytes.length + "|" + z1Sha256(dexBytes) + "|" + partTokens.join(";")
        )
    }
    String totalSha = totalDigest.digest().collect {
        String.format("%02x", it & 0xff)
    }.join()
    String profile = "Z1DEXPROFILE|1|" + totalSize + "|" + totalSha + "\n" +
            profileLines.join("\n") + "\n"
    generatedEntries["base/assets/z1_guard/dex_profile.dat"] =
            Base64.getUrlEncoder().withoutPadding()
                    .encode(profile.getBytes("UTF-8"))
    byte[] guardDexBytes = new File(z1Root, "guard.dex").bytes
    generatedEntries["base/dex/classes.dex"] = guardDexBytes
    String guardDexSha = z1Sha256(guardDexBytes)
    Set<String> allowedCodeDigests = new TreeSet<String>()
    allowedCodeDigests.add(guardDexSha)
    source.entries().each { entry ->
        boolean dynamicDex = !entry.isDirectory() &&
                entry.name ==~ /[^\/]+\/dex\/classes\d*\.dex/ &&
                !entry.name.startsWith("base/dex/")
        boolean nativeLibrary = !entry.isDirectory() &&
                entry.name ==~ /[^\/]+\/lib\/[^\/]+\/.+\.so/
        if (dynamicDex || nativeLibrary) {
            allowedCodeDigests.add(z1Sha256(z1ReadAll(source.getInputStream(entry))))
        }
    }
    String codeProfileBody = "guard|" + guardDexSha + "\n"
    allowedCodeDigests.each { digest ->
        if (digest != guardDexSha) {
            codeProfileBody += "allow|" + digest + "\n"
        }
    }
    String codeProfileHmac = z1HmacSha256(
            codeProfileBody.getBytes("UTF-8"),
            z1Hex("__AAB_CODE_HMAC_KEY_HEX__")
    )
    generatedEntries["base/assets/z1_guard/aab_code_profile.dat"] =
            ("Z1AABCODEPROFILE|1|" + codeProfileHmac + "\n" + codeProfileBody)
                    .getBytes("UTF-8")

    outputAab.parentFile.mkdirs()
    ZipOutputStream output = new ZipOutputStream(new FileOutputStream(outputAab))
    try {
        source.entries().each { entry ->
            String upperName = entry.name.toUpperCase(Locale.US)
            boolean removedDex = entry.name ==~ /base\/dex\/classes\d*\.dex/
            boolean removedSignature = upperName == "META-INF/MANIFEST.MF" ||
                    upperName ==~ /META-INF\/[^\/]+\.(SF|RSA|DSA|EC)/
            boolean reserved = entry.name.startsWith("base/assets/z1_guard/")
            if (!removedDex && !removedSignature && !reserved) {
                ZipEntry copied = new ZipEntry(entry)
                output.putNextEntry(copied)
                if (!entry.isDirectory()) {
                    output.write(z1ReadAll(source.getInputStream(entry)))
                }
                output.closeEntry()
            }
        }
        generatedEntries.each { name, bytes -> z1AddEntry(output, name, bytes) }
    } finally {
        output.close()
        source.close()
    }
}

afterEvaluate {
    def z1BundleTasks = tasks.findAll {
        it.name.startsWith("bundle") && !it.name.toLowerCase(Locale.US).contains("debug")
    }
    z1BundleTasks.each { bundleTask ->
        String suffix = bundleTask.name.substring("bundle".length())
        def hardenTask = tasks.register("z1Harden${suffix}Aab") {
            group = "z1 guard"
            description = "Builds a Z1 Guard protected AAB for ${suffix}"
            mustRunAfter(bundleTask)
            doLast {
                List<File> candidates = fileTree(new File(buildDir, "outputs/bundle")) {
                    include "**/*.aab"
                    exclude "**/*_z1guard.aab"
                }.files.toList().sort { left, right ->
                    right.lastModified() <=> left.lastModified()
                }
                if (candidates.isEmpty()) {
                    throw new GradleException("Z1 Guard: bundle output not found")
                }
                File sourceAab = candidates.first()
                String baseName = sourceAab.name.substring(0, sourceAab.name.length() - 4)
                File unsignedAab = new File(sourceAab.parentFile, baseName + "_z1guard_unsigned.aab")
                File transparentAab = new File(sourceAab.parentFile, baseName + "_z1guard_transparency.aab")
                File finalAab = new File(sourceAab.parentFile, baseName + "_z1guard.aab")
                z1Transform(sourceAab, unsignedAab)

                def processEnvironment = [
                        Z1_UPLOAD_STORE_PASS: z1Value("upload.storePassword", "Z1_UPLOAD_STORE_PASS"),
                        Z1_UPLOAD_KEY_PASS: z1Value("upload.keyPassword", "Z1_UPLOAD_KEY_PASS"),
                        Z1_TRANSPARENCY_STORE_PASS: z1Value("transparency.storePassword", "Z1_TRANSPARENCY_STORE_PASS"),
                        Z1_TRANSPARENCY_KEY_PASS: z1Value("transparency.keyPassword", "Z1_TRANSPARENCY_KEY_PASS")
                ]
                File transparencyStorePass = new File(temporaryDir, "transparency_store.pass")
                File transparencyKeyPass = new File(temporaryDir, "transparency_key.pass")
                transparencyStorePass.text = processEnvironment.Z1_TRANSPARENCY_STORE_PASS
                transparencyKeyPass.text = processEnvironment.Z1_TRANSPARENCY_KEY_PASS
                transparencyStorePass.setReadable(false, false)
                transparencyStorePass.setReadable(true, true)
                transparencyKeyPass.setReadable(false, false)
                transparencyKeyPass.setReadable(true, true)
                exec {
                    environment processEnvironment
                    commandLine(
                            new File(System.getProperty("java.home"), "bin/java"),
                            "-jar", new File(z1Root, "bundletool.jar"),
                            "add-transparency",
                            "--bundle=" + unsignedAab,
                            "--output=" + transparentAab,
                            "--ks=" + z1Value("transparency.keystore", "Z1_TRANSPARENCY_KEYSTORE"),
                            "--ks-pass=file:" + transparencyStorePass,
                            "--ks-key-alias=" + z1Value("transparency.alias", "Z1_TRANSPARENCY_ALIAS"),
                            "--key-pass=file:" + transparencyKeyPass
                    )
                }
                exec {
                    environment processEnvironment
                    commandLine(
                            new File(System.getProperty("java.home"), "bin/jarsigner"),
                            "-keystore", z1Value("upload.keystore", "Z1_UPLOAD_KEYSTORE"),
                            "-storepass:env", "Z1_UPLOAD_STORE_PASS",
                            "-keypass:env", "Z1_UPLOAD_KEY_PASS",
                            "-digestalg", "SHA-256",
                            "-signedjar", finalAab,
                            transparentAab,
                            z1Value("upload.alias", "Z1_UPLOAD_ALIAS")
                    )
                }
                exec {
                    commandLine(
                            new File(System.getProperty("java.home"), "bin/java"),
                            "-jar", new File(z1Root, "bundletool.jar"),
                            "validate", "--bundle=" + finalAab
                    )
                }
                exec {
                    commandLine(
                            new File(System.getProperty("java.home"), "bin/java"),
                            "-jar", new File(z1Root, "bundletool.jar"),
                            "check-transparency", "--mode=bundle", "--bundle=" + finalAab
                    )
                }
                unsignedAab.delete()
                transparentAab.delete()
                transparencyStorePass.delete()
                transparencyKeyPass.delete()
                logger.lifecycle("Z1 Guard AAB: " + finalAab)
            }
        }
        bundleTask.finalizedBy(hardenTask)
    }
}
''';
