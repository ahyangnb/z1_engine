import 'dart:io';

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
    final unsignedApkPath = _joinPath(workDirectory.path, 'unsigned.apk');
    final alignedApkPath = _joinPath(workDirectory.path, 'aligned.apk');

    try {
      logs.add('工作目录：${workDirectory.path}');
      logs.add('apktool：$apktool');
      logs.add('javac：$javac');
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
      logs.add('目标包名：$packageName');
      logs.add('注入 dex：classes$nextDexIndex.dex');

      await manifestFile.writeAsString(
        _injectGuardProvider(manifestContent, packageName),
      );

      await _writeGuardJavaSources(guardSourceDirectory);
      await guardClassesDirectory.create(recursive: true);
      await guardDexDirectory.create(recursive: true);

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
          guardClassesDirectory.path,
          _joinPath(
            _joinPath(_joinPath(guardSourceDirectory.path, 'com'), 'z1'),
            'guard/Z1Guard.java',
          ),
          _joinPath(
            _joinPath(_joinPath(guardSourceDirectory.path, 'com'), 'z1'),
            'guard/Z1GuardProvider.java',
          ),
        ],
        logs,
        label: 'javac guard',
      );

      await _runChecked(
        d8,
        [
          '--min-api',
          minSdk.toString(),
          '--lib',
          androidJar,
          '--output',
          guardDexDirectory.path,
          _joinPath(
            _joinPath(_joinPath(guardClassesDirectory.path, 'com'), 'z1'),
            'guard/Z1Guard.class',
          ),
          _joinPath(
            _joinPath(_joinPath(guardClassesDirectory.path, 'com'), 'z1'),
            'guard/Z1GuardProvider.class',
          ),
        ],
        logs,
        label: 'd8 guard',
      );

      final guardDexFile = File(
        _joinPath(guardDexDirectory.path, 'classes.dex'),
      );
      if (!guardDexFile.existsSync()) {
        throw const ApkHardeningException('Guard dex 生成失败');
      }
      await guardDexFile.copy(
        _joinPath(decodedDirectory.path, 'classes$nextDexIndex.dex'),
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

  Future<void> _writeGuardJavaSources(Directory sourceDirectory) async {
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
    ).writeAsString(_guardJava);
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
    var maxIndex = 1;
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
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null && javaHome.trim().isNotEmpty) {
      final candidate = _joinPath(
        _joinPath(javaHome.trim(), 'bin'),
        _javacName,
      );
      if (_fileExistsSafely(candidate)) {
        return candidate;
      }
    }

    final pathExecutable = await _findExecutableOnPath('javac');
    if (pathExecutable != null) {
      return pathExecutable;
    }

    if (Platform.isMacOS) {
      try {
        final result = await Process.run('/usr/libexec/java_home', []);
        final home = result.stdout.toString().trim();
        final candidate = _joinPath(_joinPath(home, 'bin'), _javacName);
        if (result.exitCode == 0 && _fileExistsSafely(candidate)) {
          return candidate;
        }
      } on ProcessException {
        // Fall through to error below.
      }
    }

    throw const ApkHardeningException('未找到 javac，请安装 JDK 或配置 JAVA_HOME');
  }

  String get _javacName {
    return Platform.isWindows ? 'javac.exe' : 'javac';
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

const _guardJava = r'''
package com.z1.guard;

import android.app.Application;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.Process;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.util.HashSet;

public final class Z1Guard {
    private static final String TAG = "Z1Guard";
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
        Log.e(TAG, "Blocked risky runtime: " + reason);
        try {
            Process.killProcess(Process.myPid());
        } catch (Throwable ignored) {
        }
        throw new SecurityException("Z1Guard blocked risky runtime: " + reason);
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
