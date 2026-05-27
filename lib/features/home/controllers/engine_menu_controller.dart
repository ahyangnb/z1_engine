import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/main_menu.dart';
import 'package:z1_engine/core/models/package_target.dart';
import 'package:z1_engine/core/services/android_so_hardening_service.dart';

class EngineMenuController extends ChangeNotifier {
  final AndroidSoHardeningService _androidSoHardeningService =
      AndroidSoHardeningService();
  MainMenu _selectedMenu = MainMenu.obfuscation;
  PackageTarget _selectedObfuscationTarget = PackageTarget.android;
  PackageTarget _selectedPackageTarget = PackageTarget.android;
  String _obfuscationProjectPath = '';
  String _packageProjectPath = '';
  String _protectProjectPath = '';
  final Set<String> _androidObfuscationConfig = {};
  final Set<String> _flutterObfuscationConfig = {};
  final List<String> _obfuscationLogs = [];
  final List<AndroidSigningConfig> _androidSigningConfigs = [];
  final List<String> _signingLogs = [];
  final List<String> _hardeningLogs = [];
  final List<String> _duplicationLogs = [];
  final List<String> _packageSecurityLogs = [];
  String? _selectedSigningConfigId;
  String _signingApkPath = '';
  String _signingOutputPath = '';
  String _duplicationFirstApkPath = '';
  String _duplicationSecondApkPath = '';
  String _packageSecurityApkPath = '';
  bool _isSigning = false;
  bool _isApplyingNativeHardening = false;
  bool _isComparingDuplication = false;
  bool _isCheckingPackageSecurity = false;

  MainMenu get selectedMenu => _selectedMenu;
  PackageTarget get selectedObfuscationTarget => _selectedObfuscationTarget;
  PackageTarget get selectedPackageTarget => _selectedPackageTarget;
  String get obfuscationProjectPath => _obfuscationProjectPath;
  String get packageProjectPath => _packageProjectPath;
  String get protectProjectPath => _protectProjectPath;
  bool get hasObfuscationProjectPath =>
      _obfuscationProjectPath.trim().isNotEmpty;
  bool get hasPackageProjectPath => _packageProjectPath.trim().isNotEmpty;
  bool get hasProtectProjectPath => _protectProjectPath.trim().isNotEmpty;
  List<String> get obfuscationLogs => List.unmodifiable(_obfuscationLogs);
  List<AndroidSigningConfig> get androidSigningConfigs =>
      List.unmodifiable(_androidSigningConfigs);
  List<String> get signingLogs => List.unmodifiable(_signingLogs);
  List<String> get hardeningLogs => List.unmodifiable(_hardeningLogs);
  List<String> get duplicationLogs => List.unmodifiable(_duplicationLogs);
  List<String> get packageSecurityLogs =>
      List.unmodifiable(_packageSecurityLogs);
  String get signingApkPath => _signingApkPath;
  String get signingOutputPath => _signingOutputPath;
  String get duplicationFirstApkPath => _duplicationFirstApkPath;
  String get duplicationSecondApkPath => _duplicationSecondApkPath;
  String get packageSecurityApkPath => _packageSecurityApkPath;
  bool get isSigning => _isSigning;
  bool get isApplyingNativeHardening => _isApplyingNativeHardening;
  bool get isComparingDuplication => _isComparingDuplication;
  bool get isCheckingPackageSecurity => _isCheckingPackageSecurity;
  bool get hasSigningApkPath => _signingApkPath.trim().isNotEmpty;
  bool get hasDuplicationFirstApkPath =>
      _duplicationFirstApkPath.trim().isNotEmpty;
  bool get hasDuplicationSecondApkPath =>
      _duplicationSecondApkPath.trim().isNotEmpty;
  bool get hasPackageSecurityApkPath =>
      _packageSecurityApkPath.trim().isNotEmpty;

  AndroidSigningConfig? get selectedSigningConfig {
    for (final config in _androidSigningConfigs) {
      if (config.id == _selectedSigningConfigId) {
        return config;
      }
    }

    return _androidSigningConfigs.isEmpty ? null : _androidSigningConfigs.first;
  }

  String? get selectedSigningConfigId => selectedSigningConfig?.id;

  bool get canExecuteSigning {
    return !_isSigning && selectedSigningConfig != null && hasSigningApkPath;
  }

  bool get canApplyAndroidSoHardening {
    return !_isApplyingNativeHardening && hasProtectProjectPath;
  }

  bool get canExecuteDuplicationCompare {
    return !_isComparingDuplication &&
        hasDuplicationFirstApkPath &&
        hasDuplicationSecondApkPath;
  }

  bool get canExecutePackageSecurityCheck {
    return !_isCheckingPackageSecurity &&
        hasPackageSecurityApkPath &&
        _isApkPath(_packageSecurityApkPath.trim());
  }

  String get signingCommandPreview {
    final config = selectedSigningConfig;
    final apkPath = _signingApkPath.trim();
    if (config == null || apkPath.isEmpty) {
      return '选择签名配置和 APK 后生成 zipalign + apksigner 命令。';
    }

    final outputPath = _effectiveSigningOutputPath;
    final alignedPath = _previewAlignedApkPath(outputPath);

    return [
      _formatCommand(
        config.effectiveZipalignPath,
        _buildZipalignArgs(config, apkPath, alignedPath),
      ),
      _formatCommand(
        config.effectiveApksignerPath,
        _buildSigningArgs(config, alignedPath, outputPath, true),
      ),
      _formatCommand(
        config.effectiveApksignerPath,
        _buildVerifyArgs(outputPath),
      ),
    ].join('\n');
  }

  String get selectedObfuscationTargetLabel {
    return _targetLabel(_selectedObfuscationTarget);
  }

  Set<String> get selectedObfuscationConfig {
    return Set.unmodifiable(_activeObfuscationConfig);
  }

  void selectMenu(MainMenu menu) {
    if (_selectedMenu == menu) {
      return;
    }

    _selectedMenu = menu;
    notifyListeners();
  }

  void selectObfuscationTarget(PackageTarget target) {
    if (_selectedObfuscationTarget == target) {
      return;
    }

    _selectedObfuscationTarget = target;
    notifyListeners();
  }

  void selectPackageTarget(PackageTarget target) {
    if (_selectedPackageTarget == target) {
      return;
    }

    _selectedPackageTarget = target;
    notifyListeners();
  }

  void updateObfuscationProjectPath(String path) {
    final normalizedPath = path.trim();
    if (_obfuscationProjectPath == normalizedPath) {
      return;
    }

    _obfuscationProjectPath = normalizedPath;
    notifyListeners();
  }

  void updatePackageProjectPath(String path) {
    final normalizedPath = path.trim();
    if (_packageProjectPath == normalizedPath) {
      return;
    }

    _packageProjectPath = normalizedPath;
    notifyListeners();
  }

  void updateProtectProjectPath(String path) {
    final normalizedPath = path.trim();
    if (_protectProjectPath == normalizedPath) {
      return;
    }

    _protectProjectPath = normalizedPath;
    notifyListeners();
  }

  void addAndroidSigningConfig({
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    required AndroidSigningScheme signingScheme,
  }) {
    final normalizedAlias = keyAlias.trim();
    final config = AndroidSigningConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: normalizedAlias,
      keystorePath: keystorePath.trim(),
      keyAlias: normalizedAlias,
      storePassword: storePassword,
      keyPassword: keyPassword,
      signingScheme: signingScheme,
    );

    _androidSigningConfigs.add(config);
    _selectedSigningConfigId = config.id;
    _signingLogs.add('[${_timestamp()}] 已添加签名配置：${config.name}');
    notifyListeners();
  }

  void selectAndroidSigningConfig(String id) {
    if (_selectedSigningConfigId == id) {
      return;
    }

    _selectedSigningConfigId = id;
    notifyListeners();
  }

  void removeAndroidSigningConfig(String id) {
    AndroidSigningConfig? removedConfig;
    for (final config in _androidSigningConfigs) {
      if (config.id == id) {
        removedConfig = config;
        break;
      }
    }

    if (removedConfig == null) {
      return;
    }

    _androidSigningConfigs.removeWhere((config) => config.id == id);
    if (_selectedSigningConfigId == id) {
      _selectedSigningConfigId = _androidSigningConfigs.isEmpty
          ? null
          : _androidSigningConfigs.first.id;
    }

    _signingLogs.add('[${_timestamp()}] 已移除签名配置：${removedConfig.name}');
    notifyListeners();
  }

  void updateSigningApkPath(String path) {
    final normalizedPath = path.trim();
    if (_signingApkPath == normalizedPath) {
      return;
    }

    final previousDefaultOutputPath = _defaultSignedApkPath(_signingApkPath);
    final shouldRefreshOutputPath =
        _signingOutputPath.trim().isEmpty ||
        _signingOutputPath == previousDefaultOutputPath;

    _signingApkPath = normalizedPath;
    if (shouldRefreshOutputPath) {
      _signingOutputPath = _defaultSignedApkPath(normalizedPath);
    }
    notifyListeners();
  }

  void updateSigningOutputPath(String path) {
    final normalizedPath = path.trim();
    if (_signingOutputPath == normalizedPath) {
      return;
    }

    _signingOutputPath = normalizedPath;
    notifyListeners();
  }

  void updateDuplicationFirstApkPath(String path) {
    final normalizedPath = path.trim();
    if (_duplicationFirstApkPath == normalizedPath) {
      return;
    }

    _duplicationFirstApkPath = normalizedPath;
    notifyListeners();
  }

  void updateDuplicationSecondApkPath(String path) {
    final normalizedPath = path.trim();
    if (_duplicationSecondApkPath == normalizedPath) {
      return;
    }

    _duplicationSecondApkPath = normalizedPath;
    notifyListeners();
  }

  void updatePackageSecurityApkPath(String path) {
    final normalizedPath = path.trim();
    if (_packageSecurityApkPath == normalizedPath) {
      return;
    }

    _packageSecurityApkPath = normalizedPath;
    notifyListeners();
  }

  void toggleObfuscationOption(String option, bool selected) {
    final config = _activeObfuscationConfig;
    final changed = selected ? config.add(option) : config.remove(option);

    if (changed) {
      notifyListeners();
    }
  }

  void executeObfuscation() {
    final targetLabel = selectedObfuscationTargetLabel;
    if (!hasObfuscationProjectPath) {
      _obfuscationLogs.add('[${_timestamp()}] 请先完成第一步：选择项目路径');
      notifyListeners();
      return;
    }

    final selectedOptions = _activeObfuscationConfig;
    final configSummary = selectedOptions.isEmpty
        ? '未选择混淆配置'
        : selectedOptions.join('、');

    _obfuscationLogs.addAll([
      '[${_timestamp()}] 开始执行$targetLabel',
      '[${_timestamp()}] 项目路径：$_obfuscationProjectPath',
      '[${_timestamp()}] 混淆配置：$configSummary',
      '[${_timestamp()}] 当前为界面演示，实际执行逻辑待接入',
      '[${_timestamp()}] $targetLabel流程结束',
    ]);
    notifyListeners();
  }

  Future<void> executeAndroidSoHardening() async {
    if (_isApplyingNativeHardening) {
      return;
    }

    final projectPath = _protectProjectPath.trim();
    if (projectPath.isEmpty) {
      _hardeningLogs.add('[${_timestamp()}] 请先选择 Android 或 Flutter 项目路径');
      notifyListeners();
      return;
    }

    _isApplyingNativeHardening = true;
    _hardeningLogs.addAll([
      '[${_timestamp()}] 开始执行 SO 构建加固配置',
      '[${_timestamp()}] 项目路径：$projectPath',
    ]);
    notifyListeners();

    try {
      final result = await _androidSoHardeningService.apply(
        projectPath: projectPath,
      );
      for (final log in result.logs) {
        _hardeningLogs.add('[${_timestamp()}] $log');
      }
    } on FileSystemException catch (error) {
      _hardeningLogs.add('[${_timestamp()}] 文件处理失败：${error.message}');
    } on ProcessException catch (error) {
      _hardeningLogs.add('[${_timestamp()}] 命令启动失败：${error.message}');
    } finally {
      _isApplyingNativeHardening = false;
      _hardeningLogs.add('[${_timestamp()}] SO 构建加固流程结束');
      notifyListeners();
    }
  }

  Future<void> executeAndroidSigning() async {
    if (_isSigning) {
      return;
    }

    final config = selectedSigningConfig;
    final apkPath = _signingApkPath.trim();
    if (config == null) {
      _signingLogs.add('[${_timestamp()}] 请先添加并选择一个签名配置');
      notifyListeners();
      return;
    }
    if (apkPath.isEmpty) {
      _signingLogs.add('[${_timestamp()}] 请先选择需要签名的 APK');
      notifyListeners();
      return;
    }
    if (!_isApkPath(apkPath)) {
      _signingLogs.add('[${_timestamp()}] 当前仅允许签名 APK 文件，请确认后缀为 .apk');
      notifyListeners();
      return;
    }
    if (!File(apkPath).existsSync()) {
      _signingLogs.add('[${_timestamp()}] APK 文件不存在：$apkPath');
      notifyListeners();
      return;
    }

    final outputPath = _effectiveSigningOutputPath;
    if (outputPath.trim().isEmpty) {
      _signingLogs.add('[${_timestamp()}] 输出 APK 路径为空');
      notifyListeners();
      return;
    }
    if (apkPath == outputPath) {
      _signingLogs.add('[${_timestamp()}] 输出路径不能与原 APK 相同');
      notifyListeners();
      return;
    }

    _isSigning = true;
    _signingLogs.addAll([
      '[${_timestamp()}] 开始执行 APK 对齐与标准签名',
      '[${_timestamp()}] 签名配置：${config.name}',
    ]);
    notifyListeners();

    String? alignedPath;
    try {
      final zipalignExecutable = await _resolveBuildToolExecutable(
        configuredExecutable: config.zipalignPath,
        executableName: 'zipalign',
      );
      final apksignerExecutable = await _resolveBuildToolExecutable(
        configuredExecutable: config.apksignerPath,
        executableName: 'apksigner',
      );
      alignedPath = _temporaryAlignedApkPath(outputPath);
      await File(outputPath).parent.create(recursive: true);

      final zipalignArgs = _buildZipalignArgs(config, apkPath, alignedPath);
      _signingLogs.add(
        '[${_timestamp()}] zipalign：${_formatCommand(zipalignExecutable, zipalignArgs)}',
      );
      notifyListeners();

      final zipalignResult = await Process.run(
        zipalignExecutable,
        zipalignArgs,
        runInShell: Platform.isWindows,
      );
      _appendProcessOutput(zipalignResult);
      if (zipalignResult.exitCode != 0) {
        _signingLogs.add(
          '[${_timestamp()}] zipalign 失败，退出码：${zipalignResult.exitCode}',
        );
        return;
      }

      final maskedSigningArgs = _buildSigningArgs(
        config,
        alignedPath,
        outputPath,
        true,
      );
      final signingArgs = _buildSigningArgs(
        config,
        alignedPath,
        outputPath,
        false,
      );
      _signingLogs.add(
        '[${_timestamp()}] apksigner：${_formatCommand(apksignerExecutable, maskedSigningArgs)}',
      );
      notifyListeners();

      final signingResult = await Process.run(
        apksignerExecutable,
        signingArgs,
        runInShell: Platform.isWindows,
      );
      _appendProcessOutput(signingResult);
      if (signingResult.exitCode != 0) {
        _signingLogs.add(
          '[${_timestamp()}] 签名失败，退出码：${signingResult.exitCode}',
        );
        return;
      }

      final verifyArgs = _buildVerifyArgs(outputPath);
      _signingLogs.add(
        '[${_timestamp()}] verify：${_formatCommand(apksignerExecutable, verifyArgs)}',
      );
      notifyListeners();

      final verifyResult = await Process.run(
        apksignerExecutable,
        verifyArgs,
        runInShell: Platform.isWindows,
      );
      _appendProcessOutput(verifyResult);
      if (verifyResult.exitCode != 0) {
        _signingLogs.add(
          '[${_timestamp()}] 签名校验失败，退出码：${verifyResult.exitCode}',
        );
        return;
      }

      _signingLogs.add('[${_timestamp()}] 签名成功：$outputPath');
      if (config.enableV4Signing) {
        _signingLogs.add('[${_timestamp()}] V4 idsig：$outputPath.idsig');
      }
    } on ProcessException catch (error) {
      _signingLogs.add('[${_timestamp()}] 签名命令启动失败：${error.message}');
    } finally {
      if (alignedPath != null) {
        final alignedFile = File(alignedPath);
        if (alignedFile.existsSync()) {
          await alignedFile.delete();
        }
      }
      _isSigning = false;
      notifyListeners();
    }
  }

  Future<void> executeApkDuplicationCompare() async {
    if (_isComparingDuplication) {
      return;
    }

    final firstApkPath = _duplicationFirstApkPath.trim();
    final secondApkPath = _duplicationSecondApkPath.trim();
    if (firstApkPath.isEmpty || secondApkPath.isEmpty) {
      _duplicationLogs.add('[${_timestamp()}] 请先选择两个 APK 包');
      notifyListeners();
      return;
    }

    if (!_isApkPath(firstApkPath) || !_isApkPath(secondApkPath)) {
      _duplicationLogs.add('[${_timestamp()}] 当前仅允许检测 APK 文件，请确认后缀为 .apk');
      notifyListeners();
      return;
    }

    if (firstApkPath == secondApkPath) {
      _duplicationLogs.add('[${_timestamp()}] 两个 APK 路径相同，请选择不同包体后再对比');
      notifyListeners();
      return;
    }

    _isComparingDuplication = true;
    _duplicationLogs.addAll([
      '[${_timestamp()}] 开始 APK 重复度检测',
      '[${_timestamp()}] APK A：$firstApkPath',
      '[${_timestamp()}] APK B：$secondApkPath',
      '[${_timestamp()}] 检测范围：资源文件结构、文件 MD5、重复/新增/缺失资源清单',
      '[${_timestamp()}] 预留深度能力：dex 内部形态、png 内部元素、smali、class 特征、代码层级关系',
    ]);
    notifyListeners();

    try {
      await Future<void>.delayed(const Duration(milliseconds: 240));

      final missingPaths = [
        if (!File(firstApkPath).existsSync()) 'APK A 不存在',
        if (!File(secondApkPath).existsSync()) 'APK B 不存在',
      ];
      if (missingPaths.isNotEmpty) {
        _duplicationLogs.add(
          '[${_timestamp()}] ${missingPaths.join('，')}，内核执行前会停止解包',
        );
      } else {
        _duplicationLogs.addAll([
          '[${_timestamp()}] 基础 UI 流程已就绪，后续接入 apktool/jadx 后执行真实解包',
          '[${_timestamp()}] 当前版本暂不生成重复度报告',
        ]);
      }

      _duplicationLogs.add('[${_timestamp()}] APK 重复度检测流程结束');
    } finally {
      _isComparingDuplication = false;
      notifyListeners();
    }
  }

  Future<void> executePackageSecurityCheck() async {
    if (_isCheckingPackageSecurity) {
      return;
    }

    final apkPath = _packageSecurityApkPath.trim();
    if (apkPath.isEmpty) {
      _packageSecurityLogs.add('[${_timestamp()}] 请先上传 APK 文件');
      notifyListeners();
      return;
    }

    if (!_isApkPath(apkPath)) {
      _packageSecurityLogs.add('[${_timestamp()}] 包安全检测仅允许上传 APK 文件');
      notifyListeners();
      return;
    }

    _isCheckingPackageSecurity = true;
    _packageSecurityLogs.addAll([
      '[${_timestamp()}] 开始包安全检测',
      '[${_timestamp()}] APK：$apkPath',
    ]);
    notifyListeners();

    try {
      await Future<void>.delayed(const Duration(milliseconds: 240));

      if (!File(apkPath).existsSync()) {
        _packageSecurityLogs.add('[${_timestamp()}] APK 文件不存在：$apkPath');
      } else {
        final fileSizeMb = File(apkPath).lengthSync() / 1024 / 1024;
        _packageSecurityLogs.addAll([
          '[${_timestamp()}] 文件类型校验：APK',
          '[${_timestamp()}] 文件大小：${fileSizeMb.toStringAsFixed(2)} MB',
          '[${_timestamp()}] 安全检测能力预留：签名证书、权限、组件暴露、调试开关、敏感配置',
          '[${_timestamp()}] 当前版本暂不生成安全检测报告',
        ]);
      }

      _packageSecurityLogs.add('[${_timestamp()}] 包安全检测流程结束');
    } finally {
      _isCheckingPackageSecurity = false;
      notifyListeners();
    }
  }

  void clearObfuscationLogs() {
    if (_obfuscationLogs.isEmpty) {
      return;
    }

    _obfuscationLogs.clear();
    notifyListeners();
  }

  void clearSigningLogs() {
    if (_signingLogs.isEmpty) {
      return;
    }

    _signingLogs.clear();
    notifyListeners();
  }

  void clearHardeningLogs() {
    if (_hardeningLogs.isEmpty) {
      return;
    }

    _hardeningLogs.clear();
    notifyListeners();
  }

  void clearDuplicationLogs() {
    if (_duplicationLogs.isEmpty) {
      return;
    }

    _duplicationLogs.clear();
    notifyListeners();
  }

  void clearPackageSecurityLogs() {
    if (_packageSecurityLogs.isEmpty) {
      return;
    }

    _packageSecurityLogs.clear();
    notifyListeners();
  }

  Set<String> get _activeObfuscationConfig {
    return _selectedObfuscationTarget == PackageTarget.android
        ? _androidObfuscationConfig
        : _flutterObfuscationConfig;
  }

  String _targetLabel(PackageTarget target) {
    return target == PackageTarget.android ? 'android混淆' : 'flutter混淆';
  }

  String get _effectiveSigningOutputPath {
    final normalizedOutputPath = _signingOutputPath.trim();
    if (normalizedOutputPath.isNotEmpty) {
      return normalizedOutputPath;
    }

    return _defaultSignedApkPath(_signingApkPath.trim());
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

  List<String> _buildZipalignArgs(
    AndroidSigningConfig config,
    String apkPath,
    String alignedPath,
  ) {
    final args = <String>['-f'];
    if (config.nativeLibraryPageAlignmentKb == 16 ||
        config.nativeLibraryPageAlignmentKb == 64) {
      args.addAll(['-P', config.nativeLibraryPageAlignmentKb.toString()]);
    } else {
      args.add('-p');
    }

    return [...args, '4', apkPath, alignedPath];
  }

  List<String> _buildVerifyArgs(String outputPath) {
    return ['verify', '--verbose', '--print-certs', outputPath];
  }

  void _appendProcessOutput(ProcessResult result) {
    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    if (stdoutText.isNotEmpty) {
      _signingLogs.add(stdoutText);
    }
    if (stderrText.isNotEmpty) {
      _signingLogs.add(stderrText);
    }
  }

  String _defaultSignedApkPath(String apkPath) {
    if (apkPath.isEmpty) {
      return '';
    }

    final slashIndex = apkPath.lastIndexOf('/');
    final backslashIndex = apkPath.lastIndexOf(r'\');
    final separatorIndex = slashIndex > backslashIndex
        ? slashIndex
        : backslashIndex;
    final directory = separatorIndex >= 0
        ? apkPath.substring(0, separatorIndex + 1)
        : '';
    final fileName = separatorIndex >= 0
        ? apkPath.substring(separatorIndex + 1)
        : apkPath;
    final lowerFileName = fileName.toLowerCase();
    final baseName = lowerFileName.endsWith('.apk')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    return '$directory${baseName}_signed.apk';
  }

  String _previewAlignedApkPath(String outputPath) {
    return '${_withoutApkExtension(outputPath)}_aligned.tmp.apk';
  }

  String _temporaryAlignedApkPath(String outputPath) {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    return '${_withoutApkExtension(outputPath)}_aligned_$suffix.tmp.apk';
  }

  String _withoutApkExtension(String path) {
    return path.toLowerCase().endsWith('.apk')
        ? path.substring(0, path.length - 4)
        : path;
  }

  bool _isApkPath(String path) {
    return path.toLowerCase().endsWith('.apk');
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

    return executableName;
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

    final List<Directory> versions;
    try {
      versions = buildToolsDirectory.listSync().whereType<Directory>().toList()
        ..sort((left, right) {
          return _compareVersionNames(
            _lastPathSegment(right.path),
            _lastPathSegment(left.path),
          );
        });
    } on FileSystemException {
      return null;
    }

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

  Iterable<String> _buildToolExecutableNames(String executableName) {
    if (!Platform.isWindows) {
      return [executableName];
    }

    return switch (executableName) {
      'apksigner' => ['apksigner.bat', 'apksigner'],
      'zipalign' => ['zipalign.exe', 'zipalign'],
      _ => [executableName],
    };
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

  String _timestamp() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return [
      twoDigits(now.hour),
      twoDigits(now.minute),
      twoDigits(now.second),
    ].join(':');
  }
}
