import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/channel_package_config.dart';
import 'package:z1_engine/core/models/main_menu.dart';
import 'package:z1_engine/core/models/package_target.dart';
import 'package:z1_engine/core/services/apk_channel_package_service.dart';
import 'package:z1_engine/core/services/apk_hardening_service.dart';
import 'package:z1_engine/core/services/apk_md5_duplication_service.dart';
import 'package:z1_engine/core/services/android_so_hardening_service.dart';
import 'package:z1_engine/core/services/channel_package_config_store.dart';
import 'package:z1_engine/core/services/signing_config_store.dart';
import 'package:z1_engine/core/services/vip_activation_store.dart';

class EngineMenuController extends ChangeNotifier {
  EngineMenuController() {
    _loadSavedSigningConfigs();
    _loadSavedChannelPackageConfig();
    _loadSavedVipActivation();
  }

  final ApkHardeningService _apkHardeningService = ApkHardeningService();
  final AndroidSoHardeningService _androidSoHardeningService =
      AndroidSoHardeningService();
  final ApkChannelPackageService _apkChannelPackageService =
      ApkChannelPackageService();
  final ApkMd5DuplicationService _apkMd5DuplicationService =
      ApkMd5DuplicationService();
  final SigningConfigStore _signingConfigStore = SigningConfigStore();
  final ChannelPackageConfigStore _channelPackageConfigStore =
      ChannelPackageConfigStore();
  final VipActivationStore _vipActivationStore = VipActivationStore();
  MainMenu _selectedMenu = MainMenu.obfuscation;
  PackageTarget _selectedObfuscationTarget = PackageTarget.android;
  PackageTarget _selectedPackageTarget = PackageTarget.android;
  String _obfuscationProjectPath = '';
  String _packageProjectPath = '';
  String _protectProjectPath = '';
  String _protectApkPath = '';
  String _protectOutputPath = '';
  final Set<String> _androidObfuscationConfig = {};
  final Set<String> _flutterObfuscationConfig = {};
  final List<String> _obfuscationLogs = [];
  final List<AndroidSigningConfig> _androidSigningConfigs = [];
  final List<String> _signingLogs = [];
  final List<String> _channelPackageLogs = [];
  final List<String> _hardeningLogs = [];
  final List<String> _duplicationLogs = [];
  final List<String> _packageSecurityLogs = [];
  String? _selectedSigningConfigId;
  String _signingApkPath = '';
  String _signingOutputPath = '';
  String _channelPackageApkPath = '';
  String _channelPackageOutputDirectory = '';
  String _channelPackagePrefix = 'ch';
  int _channelPackageCount = 5;
  int _channelPackageStartIndex = 1;
  String _duplicationFirstApkPath = '';
  String _duplicationSecondApkPath = '';
  String _packageSecurityApkPath = '';
  bool _isSigning = false;
  bool _isHardeningApk = false;
  bool _isGeneratingChannelPackages = false;
  bool _isApplyingNativeHardening = false;
  bool _isComparingDuplication = false;
  bool _isCheckingPackageSecurity = false;
  String _vipActivationCode = '';
  String _vipActivationMessage = '';

  MainMenu get selectedMenu => _selectedMenu;
  PackageTarget get selectedObfuscationTarget => _selectedObfuscationTarget;
  PackageTarget get selectedPackageTarget => _selectedPackageTarget;
  String get obfuscationProjectPath => _obfuscationProjectPath;
  String get packageProjectPath => _packageProjectPath;
  String get protectProjectPath => _protectProjectPath;
  String get protectApkPath => _protectApkPath;
  String get protectOutputPath => _protectOutputPath;
  bool get hasObfuscationProjectPath =>
      _obfuscationProjectPath.trim().isNotEmpty;
  bool get hasPackageProjectPath => _packageProjectPath.trim().isNotEmpty;
  bool get hasProtectProjectPath => _protectProjectPath.trim().isNotEmpty;
  bool get hasProtectApkPath => _protectApkPath.trim().isNotEmpty;
  List<String> get obfuscationLogs => List.unmodifiable(_obfuscationLogs);
  List<AndroidSigningConfig> get androidSigningConfigs =>
      List.unmodifiable(_androidSigningConfigs);
  List<String> get signingLogs => List.unmodifiable(_signingLogs);
  List<String> get channelPackageLogs => List.unmodifiable(_channelPackageLogs);
  List<String> get hardeningLogs => List.unmodifiable(_hardeningLogs);
  List<String> get duplicationLogs => List.unmodifiable(_duplicationLogs);
  List<String> get packageSecurityLogs =>
      List.unmodifiable(_packageSecurityLogs);
  String get signingApkPath => _signingApkPath;
  String get signingOutputPath => _signingOutputPath;
  String get channelPackageApkPath => _channelPackageApkPath;
  String get channelPackageOutputDirectory => _channelPackageOutputDirectory;
  String get channelPackagePrefix => _channelPackagePrefix;
  int get channelPackageCount => _channelPackageCount;
  int get channelPackageStartIndex => _channelPackageStartIndex;
  String get duplicationFirstApkPath => _duplicationFirstApkPath;
  String get duplicationSecondApkPath => _duplicationSecondApkPath;
  String get packageSecurityApkPath => _packageSecurityApkPath;
  bool get isSigning => _isSigning;
  bool get isHardeningApk => _isHardeningApk;
  bool get isGeneratingChannelPackages => _isGeneratingChannelPackages;
  bool get isApplyingNativeHardening => _isApplyingNativeHardening;
  bool get isComparingDuplication => _isComparingDuplication;
  bool get isCheckingPackageSecurity => _isCheckingPackageSecurity;
  bool get hasSigningApkPath => _signingApkPath.trim().isNotEmpty;
  bool get hasChannelPackageApkPath => _channelPackageApkPath.trim().isNotEmpty;
  bool get hasDuplicationFirstApkPath =>
      _duplicationFirstApkPath.trim().isNotEmpty;
  bool get hasDuplicationSecondApkPath =>
      _duplicationSecondApkPath.trim().isNotEmpty;
  bool get hasPackageSecurityApkPath =>
      _packageSecurityApkPath.trim().isNotEmpty;
  bool get isVipServiceActive => _vipActivationCode.trim().isNotEmpty;
  String get vipActivationCode => _vipActivationCode;
  String get vipActivationMessage => _vipActivationMessage;
  int get freeChannelPackageLimit => 5;

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

  bool get canGenerateChannelPackages {
    return !_isGeneratingChannelPackages &&
        hasChannelPackageApkPath &&
        _isApkPath(_channelPackageApkPath.trim()) &&
        _channelPackageCount > 0 &&
        (isVipServiceActive ||
            _channelPackageCount <= freeChannelPackageLimit) &&
        _channelPackageStartIndex > 0 &&
        _isSafeChannelPart(_channelPackagePrefix.trim());
  }

  bool get canApplyAndroidSoHardening {
    return !_isApplyingNativeHardening && hasProtectProjectPath;
  }

  bool get canExecuteApkHardening {
    return !_isHardeningApk &&
        selectedSigningConfig != null &&
        hasProtectApkPath &&
        _isApkPath(_protectApkPath.trim()) &&
        _effectiveProtectOutputPath.trim().isNotEmpty;
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

  String get channelPackagePreview {
    final apkPath = _channelPackageApkPath.trim();
    if (apkPath.isEmpty) {
      return '上传已签名 APK 后预览输出文件名。';
    }
    if (_channelPackageCount <= 0) {
      return '请输入大于 0 的生成数量。';
    }
    if (!isVipServiceActive && _channelPackageCount > freeChannelPackageLimit) {
      return '免费渠道包单次最多生成 $freeChannelPackageLimit 个。开通增值服务后可设置超过 $freeChannelPackageLimit 个渠道包。';
    }
    if (!_isSafeChannelPart(_channelPackagePrefix.trim())) {
      return '渠道后缀仅支持字母、数字、点、下划线和短横线。';
    }

    final visibleCount = _channelPackageCount < 5 ? _channelPackageCount : 5;
    final outputDirectory = _effectiveChannelPackageOutputDirectory;
    final previewPaths = List.generate(visibleCount, (index) {
      final channelCode = _channelCodeAt(index);
      return _channelPackageOutputPath(apkPath, outputDirectory, channelCode);
    });

    if (_channelPackageCount > visibleCount) {
      previewPaths.add('... 共 $_channelPackageCount 个渠道包');
    }

    return previewPaths.join('\n');
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

  void updateProtectApkPath(String path) {
    final normalizedPath = path.trim();
    if (_protectApkPath == normalizedPath) {
      return;
    }

    final previousDefaultOutputPath = _defaultHardenedApkPath(_protectApkPath);
    final shouldRefreshOutputPath =
        _protectOutputPath.trim().isEmpty ||
        _protectOutputPath == previousDefaultOutputPath;

    _protectApkPath = normalizedPath;
    if (shouldRefreshOutputPath) {
      _protectOutputPath = _defaultHardenedApkPath(normalizedPath);
    }
    notifyListeners();
  }

  void updateProtectOutputPath(String path) {
    final normalizedPath = path.trim();
    if (_protectOutputPath == normalizedPath) {
      return;
    }

    _protectOutputPath = normalizedPath;
    notifyListeners();
  }

  void addAndroidSigningConfig({
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    required AndroidSigningScheme signingScheme,
    String remark = '',
  }) {
    final normalizedAlias = keyAlias.trim();
    final config = AndroidSigningConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: normalizedAlias,
      keystorePath: keystorePath.trim(),
      keyAlias: normalizedAlias,
      storePassword: storePassword,
      keyPassword: keyPassword,
      remark: remark.trim(),
      signingScheme: signingScheme,
    );

    _androidSigningConfigs.add(config);
    _selectedSigningConfigId = config.id;
    _signingLogs.add('[${_timestamp()}] 已添加签名配置：${config.name}');
    _saveSigningConfigs();
    notifyListeners();
  }

  void updateAndroidSigningConfig({
    required String id,
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    required AndroidSigningScheme signingScheme,
    required String remark,
  }) {
    final index = _androidSigningConfigs.indexWhere(
      (config) => config.id == id,
    );
    if (index < 0) {
      return;
    }

    final normalizedAlias = keyAlias.trim();
    final updatedConfig = _androidSigningConfigs[index].copyWith(
      name: normalizedAlias,
      keystorePath: keystorePath.trim(),
      keyAlias: normalizedAlias,
      storePassword: storePassword,
      keyPassword: keyPassword,
      remark: remark.trim(),
      signingScheme: signingScheme,
    );

    _androidSigningConfigs[index] = updatedConfig;
    _selectedSigningConfigId = updatedConfig.id;
    _signingLogs.add('[${_timestamp()}] 已更新签名配置：${updatedConfig.name}');
    _saveSigningConfigs();
    notifyListeners();
  }

  Future<String?> saveAndroidSigningConfig({
    required String? id,
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    required AndroidSigningScheme signingScheme,
    required String remark,
  }) async {
    final validationResult = await _validateAndroidSigningConfig(
      keystorePath: keystorePath,
      keyAlias: keyAlias,
      storePassword: storePassword,
      keyPassword: keyPassword,
      signingScheme: signingScheme,
    );
    if (validationResult.errorMessage != null) {
      _signingLogs.add('[${_timestamp()}] ${validationResult.errorMessage}');
      notifyListeners();
      return validationResult.errorMessage;
    }

    if (id == null) {
      addAndroidSigningConfig(
        keystorePath: keystorePath,
        keyAlias: keyAlias,
        storePassword: validationResult.storePassword,
        keyPassword: validationResult.keyPassword,
        signingScheme: signingScheme,
        remark: remark,
      );
    } else {
      updateAndroidSigningConfig(
        id: id,
        keystorePath: keystorePath,
        keyAlias: keyAlias,
        storePassword: validationResult.storePassword,
        keyPassword: validationResult.keyPassword,
        signingScheme: signingScheme,
        remark: remark,
      );
    }

    return null;
  }

  void selectAndroidSigningConfig(String id) {
    if (_selectedSigningConfigId == id) {
      return;
    }

    _selectedSigningConfigId = id;
    _saveSigningConfigs();
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
    _saveSigningConfigs();
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

  void updateChannelPackageApkPath(String path) {
    final normalizedPath = path.trim();
    if (_channelPackageApkPath == normalizedPath) {
      return;
    }

    final previousDefaultOutputDirectory = _defaultChannelOutputDirectory(
      _channelPackageApkPath,
    );
    final shouldRefreshOutputDirectory =
        _channelPackageOutputDirectory.trim().isEmpty ||
        _channelPackageOutputDirectory == previousDefaultOutputDirectory;

    _channelPackageApkPath = normalizedPath;
    if (shouldRefreshOutputDirectory) {
      _channelPackageOutputDirectory = _defaultChannelOutputDirectory(
        normalizedPath,
      );
    }
    notifyListeners();
  }

  void updateChannelPackageOutputDirectory(String path) {
    final normalizedPath = path.trim();
    if (_channelPackageOutputDirectory == normalizedPath) {
      return;
    }

    _channelPackageOutputDirectory = normalizedPath;
    _saveChannelPackageConfig();
    notifyListeners();
  }

  void updateChannelPackagePrefix(String prefix) {
    final normalizedPrefix = prefix.trim();
    if (_channelPackagePrefix == normalizedPrefix) {
      return;
    }

    _channelPackagePrefix = normalizedPrefix;
    if (_isSafeChannelPart(normalizedPrefix)) {
      _saveChannelPackageConfig();
    }
    notifyListeners();
  }

  void updateChannelPackageCount(String count) {
    final parsedCount = int.tryParse(count.trim()) ?? 0;
    if (_channelPackageCount == parsedCount) {
      return;
    }

    _channelPackageCount = parsedCount;
    if (parsedCount > 0) {
      _saveChannelPackageConfig();
    }
    notifyListeners();
  }

  void updateChannelPackageStartIndex(String startIndex) {
    final parsedStartIndex = int.tryParse(startIndex.trim()) ?? 0;
    if (_channelPackageStartIndex == parsedStartIndex) {
      return;
    }

    _channelPackageStartIndex = parsedStartIndex;
    if (parsedStartIndex > 0) {
      _saveChannelPackageConfig();
    }
    notifyListeners();
  }

  Future<bool> activateVipService(String activationCode) async {
    final normalizedCode = activationCode.trim();
    if (normalizedCode.isEmpty) {
      _vipActivationMessage = '请输入激活码';
      notifyListeners();
      return false;
    }

    if (!_isValidVipActivationCode(normalizedCode)) {
      _vipActivationMessage = '激活码格式不正确，请确认购买后弹出的激活码';
      notifyListeners();
      return false;
    }

    _vipActivationCode = normalizedCode;
    _vipActivationMessage = '增值服务已激活';
    await _saveVipActivation();
    notifyListeners();
    return true;
  }

  void openVipServicePage() {
    selectMenu(MainMenu.vipService);
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

  Future<void> executeApkHardening() async {
    if (_isHardeningApk) {
      return;
    }

    final config = selectedSigningConfig;
    final apkPath = _protectApkPath.trim();
    final outputPath = _effectiveProtectOutputPath;
    if (apkPath.isEmpty) {
      _hardeningLogs.add('[${_timestamp()}] 请先上传需要加固的 APK');
      notifyListeners();
      return;
    }
    if (!_isApkPath(apkPath)) {
      _hardeningLogs.add('[${_timestamp()}] 当前加固流程仅支持 APK 文件');
      notifyListeners();
      return;
    }
    if (!File(apkPath).existsSync()) {
      _hardeningLogs.add('[${_timestamp()}] APK 文件不存在：$apkPath');
      notifyListeners();
      return;
    }
    if (config == null) {
      _hardeningLogs.add('[${_timestamp()}] 请先在“签名”页面添加并选择签名配置');
      notifyListeners();
      return;
    }
    if (outputPath.trim().isEmpty) {
      _hardeningLogs.add('[${_timestamp()}] 输出 APK 路径为空');
      notifyListeners();
      return;
    }
    if (apkPath == outputPath) {
      _hardeningLogs.add('[${_timestamp()}] 输出路径不能与原 APK 相同');
      notifyListeners();
      return;
    }

    _isHardeningApk = true;
    _hardeningLogs.addAll([
      '[${_timestamp()}] 开始 APK 包防篡改加固',
      '[${_timestamp()}] 输入 APK：$apkPath',
      '[${_timestamp()}] 输出 APK：$outputPath',
      '[${_timestamp()}] 签名配置：${config.name}',
    ]);
    notifyListeners();

    try {
      final result = await _apkHardeningService.harden(
        sourceApkPath: apkPath,
        outputApkPath: outputPath,
        signingConfig: config,
      );
      for (final log in result.logs) {
        _hardeningLogs.add('[${_timestamp()}] $log');
      }
      _hardeningLogs.addAll([
        '[${_timestamp()}] 已注入早启动防护 Provider：com.z1.guard.Z1GuardProvider',
        '[${_timestamp()}] 已启用硬校验：包名、签名证书 SHA-256、APK 条目 SHA-256 摘要基线',
        '[${_timestamp()}] 已启用运行时检测：私有目录二进制/DEX/JS、Frida/Gadget、TracerPid、异常线程、root 信号、VPN transport',
        '[${_timestamp()}] 加固成功：${result.outputApkPath}',
      ]);
    } on ApkHardeningException catch (error) {
      _hardeningLogs.add('[${_timestamp()}] 加固失败：${error.message}');
    } on FileSystemException catch (error) {
      _hardeningLogs.add('[${_timestamp()}] 文件处理失败：${error.message}');
    } on ProcessException catch (error) {
      _hardeningLogs.add('[${_timestamp()}] 命令启动失败：${error.message}');
    } finally {
      _isHardeningApk = false;
      _hardeningLogs.add('[${_timestamp()}] APK 包防篡改加固流程结束');
      notifyListeners();
    }
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

  Future<void> executeChannelPackageGeneration() async {
    if (_isGeneratingChannelPackages) {
      return;
    }

    final apkPath = _channelPackageApkPath.trim();
    final outputDirectory = _effectiveChannelPackageOutputDirectory;
    final channelPrefix = _channelPackagePrefix.trim();
    if (apkPath.isEmpty) {
      _channelPackageLogs.add('[${_timestamp()}] 请先上传已签名 APK 母包');
      notifyListeners();
      return;
    }
    if (!_isApkPath(apkPath)) {
      _channelPackageLogs.add('[${_timestamp()}] 当前仅允许处理 APK 文件，请确认后缀为 .apk');
      notifyListeners();
      return;
    }
    if (!File(apkPath).existsSync()) {
      _channelPackageLogs.add('[${_timestamp()}] 母包文件不存在：$apkPath');
      notifyListeners();
      return;
    }
    if (_channelPackageCount <= 0) {
      _channelPackageLogs.add('[${_timestamp()}] 生成数量必须大于 0');
      notifyListeners();
      return;
    }
    if (!isVipServiceActive && _channelPackageCount > freeChannelPackageLimit) {
      _channelPackageLogs.add(
        '[${_timestamp()}] 免费渠道包单次最多生成 $freeChannelPackageLimit 个，请开通增值服务后继续',
      );
      notifyListeners();
      return;
    }
    if (_channelPackageCount > 10000) {
      _channelPackageLogs.add('[${_timestamp()}] 单次最多生成 10000 个渠道包');
      notifyListeners();
      return;
    }
    if (_channelPackageStartIndex <= 0) {
      _channelPackageLogs.add('[${_timestamp()}] 起始序号必须大于 0');
      notifyListeners();
      return;
    }
    if (!_isSafeChannelPart(channelPrefix)) {
      _channelPackageLogs.add('[${_timestamp()}] 渠道后缀仅支持字母、数字、点、下划线和短横线');
      notifyListeners();
      return;
    }
    if (outputDirectory.isEmpty) {
      _channelPackageLogs.add('[${_timestamp()}] 输出目录不能为空');
      notifyListeners();
      return;
    }

    _isGeneratingChannelPackages = true;
    _channelPackageLogs.addAll([
      '[${_timestamp()}] 开始批量生成渠道包',
      '[${_timestamp()}] 母包：$apkPath',
      '[${_timestamp()}] 输出目录：$outputDirectory',
      '[${_timestamp()}] 渠道块 ID：0x${ApkChannelPackageService.defaultChannelBlockId.toRadixString(16)}',
      '[${_timestamp()}] 生成数量：$_channelPackageCount',
    ]);
    notifyListeners();

    try {
      final apksignerExecutable = await _resolveBuildToolExecutable(
        configuredExecutable: '',
        executableName: 'apksigner',
      );
      var successCount = 0;

      for (var index = 0; index < _channelPackageCount; index += 1) {
        final channelCode = _channelCodeAt(index);
        final outputPath = _channelPackageOutputPath(
          apkPath,
          outputDirectory,
          channelCode,
        );

        _channelPackageLogs.add(
          '[${_timestamp()}] 写入渠道码 $channelCode：$outputPath',
        );
        notifyListeners();

        final result = await _apkChannelPackageService.generate(
          sourceApkPath: apkPath,
          outputApkPath: outputPath,
          channelCode: channelCode,
        );
        final fileSizeMb = result.fileSizeBytes / 1024 / 1024;
        _channelPackageLogs.add(
          '[${_timestamp()}] 已生成：${result.channelCode}，${fileSizeMb.toStringAsFixed(2)} MB',
        );

        final verified = await _verifyApkSignature(
          apksignerExecutable,
          outputPath,
          _channelPackageLogs,
        );
        if (!verified) {
          return;
        }

        successCount += 1;
      }

      _channelPackageLogs.add(
        '[${_timestamp()}] 渠道包生成完成，成功 $successCount / $_channelPackageCount',
      );
    } on ApkChannelPackageException catch (error) {
      _channelPackageLogs.add('[${_timestamp()}] 渠道包生成失败：${error.message}');
    } on FileSystemException catch (error) {
      _channelPackageLogs.add('[${_timestamp()}] 文件处理失败：${error.message}');
    } finally {
      _isGeneratingChannelPackages = false;
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

    final missingPaths = [
      if (!File(firstApkPath).existsSync()) 'APK A 不存在：$firstApkPath',
      if (!File(secondApkPath).existsSync()) 'APK B 不存在：$secondApkPath',
    ];
    if (missingPaths.isNotEmpty) {
      for (final missingPath in missingPaths) {
        _duplicationLogs.add('[${_timestamp()}] $missingPath');
      }
      notifyListeners();
      return;
    }

    _isComparingDuplication = true;
    _duplicationLogs.addAll([
      '[${_timestamp()}] 开始 APK 重复度检测',
      '[${_timestamp()}] APK A：$firstApkPath',
      '[${_timestamp()}] APK B：$secondApkPath',
      '[${_timestamp()}] 当前执行能力：真实解包后计算文件 MD5 并对比',
      '[${_timestamp()}] 暂不支持：资源文件结构、dex 内部形态、png 内部元素、smali / class 特征、代码层级关系',
    ]);
    notifyListeners();

    try {
      _duplicationLogs.add('[${_timestamp()}] 正在解包 APK 并计算文件 MD5');
      notifyListeners();

      final result = await _apkMd5DuplicationService.compare(
        firstApkPath: firstApkPath,
        secondApkPath: secondApkPath,
      );
      _appendDuplicationResultLogs(result);
    } on ApkMd5DuplicationException catch (error) {
      _duplicationLogs.add('[${_timestamp()}] APK 重复度检测失败：${error.message}');
    } finally {
      _isComparingDuplication = false;
      _duplicationLogs.add('[${_timestamp()}] APK 重复度检测流程结束');
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

  void clearChannelPackageLogs() {
    if (_channelPackageLogs.isEmpty) {
      return;
    }

    _channelPackageLogs.clear();
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

  Future<void> _loadSavedSigningConfigs() async {
    try {
      final snapshot = await _signingConfigStore.load();
      if (snapshot.configs.isEmpty) {
        return;
      }

      _androidSigningConfigs
        ..clear()
        ..addAll(snapshot.configs);
      _selectedSigningConfigId = snapshot.selectedConfigId;
      final selectedConfigExists = _androidSigningConfigs.any(
        (config) => config.id == _selectedSigningConfigId,
      );
      if (!selectedConfigExists && _androidSigningConfigs.isNotEmpty) {
        _selectedSigningConfigId = _androidSigningConfigs.first.id;
      }
      _signingLogs.add('[${_timestamp()}] 已加载本地签名配置');
      notifyListeners();
    } on FormatException catch (error) {
      _signingLogs.add('[${_timestamp()}] 本地签名配置解析失败：${error.message}');
      notifyListeners();
    } on FileSystemException catch (error) {
      _signingLogs.add('[${_timestamp()}] 本地签名配置读取失败：${error.message}');
      notifyListeners();
    }
  }

  Future<void> _saveSigningConfigs() async {
    try {
      await _signingConfigStore.save(
        configs: _androidSigningConfigs,
        selectedConfigId: _selectedSigningConfigId,
      );
    } on FileSystemException catch (error) {
      _signingLogs.add('[${_timestamp()}] 本地签名配置保存失败：${error.message}');
      notifyListeners();
    }
  }

  Future<void> _loadSavedChannelPackageConfig() async {
    try {
      final config = await _channelPackageConfigStore.load();
      _channelPackageOutputDirectory = config.outputDirectory.trim();
      final normalizedPrefix = config.prefix.trim();
      if (_isSafeChannelPart(normalizedPrefix)) {
        _channelPackagePrefix = normalizedPrefix;
      }
      if (config.count > 0) {
        _channelPackageCount = config.count;
      }
      if (config.startIndex > 0) {
        _channelPackageStartIndex = config.startIndex;
      }

      _channelPackageLogs.add('[${_timestamp()}] 已加载本地渠道配置');
      notifyListeners();
    } on FormatException catch (error) {
      _channelPackageLogs.add('[${_timestamp()}] 本地渠道配置解析失败：${error.message}');
      notifyListeners();
    } on FileSystemException catch (error) {
      _channelPackageLogs.add('[${_timestamp()}] 本地渠道配置读取失败：${error.message}');
      notifyListeners();
    }
  }

  Future<void> _saveChannelPackageConfig() async {
    try {
      await _channelPackageConfigStore.save(
        ChannelPackageConfig(
          outputDirectory: _channelPackageOutputDirectory.trim(),
          prefix: _channelPackagePrefix.trim(),
          count: _channelPackageCount,
          startIndex: _channelPackageStartIndex,
        ),
      );
    } on FileSystemException catch (error) {
      _channelPackageLogs.add('[${_timestamp()}] 本地渠道配置保存失败：${error.message}');
      notifyListeners();
    }
  }

  Future<void> _loadSavedVipActivation() async {
    try {
      final activationCode = await _vipActivationStore.loadActivationCode();
      if (activationCode.trim().isEmpty) {
        return;
      }

      _vipActivationCode = activationCode.trim();
      _vipActivationMessage = '增值服务已激活';
      notifyListeners();
    } on FormatException {
      _vipActivationMessage = '本地增值服务激活信息解析失败';
      notifyListeners();
    } on FileSystemException catch (error) {
      _vipActivationMessage = '本地增值服务激活信息读取失败：${error.message}';
      notifyListeners();
    }
  }

  Future<void> _saveVipActivation() async {
    try {
      await _vipActivationStore.saveActivationCode(_vipActivationCode);
    } on FileSystemException catch (error) {
      _vipActivationMessage = '本地增值服务激活信息保存失败：${error.message}';
      notifyListeners();
    }
  }

  Future<_SigningConfigValidationResult> _validateAndroidSigningConfig({
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    required AndroidSigningScheme signingScheme,
  }) async {
    final normalizedKeystorePath = keystorePath.trim();
    final normalizedAlias = keyAlias.trim();
    final effectiveStorePassword = storePassword.isEmpty
        ? keyPassword
        : storePassword;
    final effectiveKeyPassword = keyPassword.isEmpty
        ? effectiveStorePassword
        : keyPassword;

    if (normalizedKeystorePath.isEmpty) {
      return const _SigningConfigValidationResult.error('请选择签名文件');
    }
    if (!_fileExistsSafely(normalizedKeystorePath)) {
      return _SigningConfigValidationResult.error(
        '签名文件不存在：$normalizedKeystorePath',
      );
    }
    if (normalizedAlias.isEmpty) {
      return const _SigningConfigValidationResult.error('请输入 alias');
    }
    if (effectiveStorePassword.isEmpty || effectiveKeyPassword.isEmpty) {
      return const _SigningConfigValidationResult.error(
        '请输入密钥密码；密钥库密码为空时会自动尝试使用密钥密码',
      );
    }

    Directory? tempDirectory;
    try {
      final apksignerExecutable = await _resolveBuildToolExecutable(
        configuredExecutable: '',
        executableName: 'apksigner',
      );
      tempDirectory = await Directory.systemTemp.createTemp(
        'z1_engine_signing_validate_',
      );
      final unsignedApkPath = _joinPath(tempDirectory.path, 'probe.apk');
      final signedApkPath = _joinPath(tempDirectory.path, 'probe_signed.apk');
      await _writeSigningProbeApk(unsignedApkPath);

      final config = AndroidSigningConfig(
        id: 'validation',
        name: normalizedAlias,
        keystorePath: normalizedKeystorePath,
        keyAlias: normalizedAlias,
        storePassword: effectiveStorePassword,
        keyPassword: effectiveKeyPassword,
        signingScheme: signingScheme,
      );
      final args = _buildSigningArgs(
        config,
        unsignedApkPath,
        signedApkPath,
        false,
      )..insertAll(1, ['--min-sdk-version', '23']);
      final result = await Process.run(
        apksignerExecutable,
        args,
        runInShell: Platform.isWindows,
      );

      if (result.exitCode != 0) {
        return _SigningConfigValidationResult.error(
          _signingValidationFailureMessage(result),
        );
      }

      return _SigningConfigValidationResult.success(
        storePassword: effectiveStorePassword,
        keyPassword: effectiveKeyPassword,
      );
    } on ProcessException catch (error) {
      return _SigningConfigValidationResult.error(
        '签名配置校验失败，apksigner 启动失败：${error.message}',
      );
    } on FileSystemException catch (error) {
      return _SigningConfigValidationResult.error(
        '签名配置校验失败，文件处理失败：${error.message}',
      );
    } finally {
      if (tempDirectory != null && await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  }

  Future<void> _writeSigningProbeApk(String path) async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'AndroidManifest.xml',
          '<manifest package="z1.engine.validation" />',
        ),
      );
    final bytes = ZipEncoder().encode(archive);
    await File(path).writeAsBytes(bytes);
  }

  String _signingValidationFailureMessage(ProcessResult result) {
    final output = [
      result.stdout.toString().trim(),
      result.stderr.toString().trim(),
    ].where((text) => text.isNotEmpty).join('\n');
    if (output.contains('Wrong password') ||
        output.contains('Cannot recover key') ||
        output.contains('Failed to obtain key') ||
        output.contains('Failed to load signer')) {
      return '签名配置校验失败：alias 或密码不正确，请检查签名文件、alias、密钥库密码和密钥密码';
    }

    final summary = output
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .take(4)
        .join(' ');
    return summary.isEmpty ? '签名配置校验失败' : '签名配置校验失败：$summary';
  }

  Set<String> get _activeObfuscationConfig {
    return _selectedObfuscationTarget == PackageTarget.android
        ? _androidObfuscationConfig
        : _flutterObfuscationConfig;
  }

  bool _isValidVipActivationCode(String activationCode) {
    final normalizedCode = activationCode.trim().toUpperCase();
    return normalizedCode == 'Z1VIP200' ||
        normalizedCode == 'VIP-200' ||
        RegExp(r'^Z1VIP-[A-Z0-9]{6,}$').hasMatch(normalizedCode);
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

  String get _effectiveProtectOutputPath {
    final normalizedOutputPath = _protectOutputPath.trim();
    if (normalizedOutputPath.isNotEmpty) {
      return normalizedOutputPath;
    }

    return _defaultHardenedApkPath(_protectApkPath.trim());
  }

  String get _effectiveChannelPackageOutputDirectory {
    final normalizedOutputDirectory = _channelPackageOutputDirectory.trim();
    if (normalizedOutputDirectory.isNotEmpty) {
      return normalizedOutputDirectory;
    }

    return _defaultChannelOutputDirectory(_channelPackageApkPath.trim());
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

  Future<bool> _verifyApkSignature(
    String apksignerExecutable,
    String outputPath,
    List<String> logs,
  ) async {
    final verifyArgs = _buildVerifyArgs(outputPath);
    logs.add(
      '[${_timestamp()}] verify：${_formatCommand(apksignerExecutable, verifyArgs)}',
    );
    notifyListeners();

    try {
      final verifyResult = await Process.run(
        apksignerExecutable,
        verifyArgs,
        runInShell: Platform.isWindows,
      );
      _appendProcessOutputTo(logs, verifyResult);
      if (verifyResult.exitCode != 0) {
        logs.add('[${_timestamp()}] 签名校验失败，退出码：${verifyResult.exitCode}');
        return false;
      }

      logs.add('[${_timestamp()}] 签名校验通过：$outputPath');
      return true;
    } on ProcessException catch (error) {
      logs.add('[${_timestamp()}] 签名校验命令启动失败：${error.message}');
      return false;
    }
  }

  void _appendProcessOutput(ProcessResult result) {
    _appendProcessOutputTo(_signingLogs, result);
  }

  void _appendProcessOutputTo(List<String> logs, ProcessResult result) {
    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    if (stdoutText.isNotEmpty) {
      logs.add(stdoutText);
    }
    if (stderrText.isNotEmpty) {
      logs.add(stderrText);
    }
  }

  void _appendDuplicationResultLogs(ApkMd5DuplicationResult result) {
    final first = result.firstSnapshot;
    final second = result.secondSnapshot;

    _duplicationLogs.addAll([
      '[${_timestamp()}] APK A 文件：${first.fileCount} 个，唯一 MD5：${first.uniqueMd5Count}，总大小：${_formatFileSize(first.totalSizeBytes)}',
      '[${_timestamp()}] APK B 文件：${second.fileCount} 个，唯一 MD5：${second.uniqueMd5Count}，总大小：${_formatFileSize(second.totalSizeBytes)}',
      '[${_timestamp()}] 文件 MD5 重复度：${_formatPercent(result.md5Similarity)}（命中 ${result.matchedMd5FileCount} / 联合 ${result.md5UnionFileCount}）',
      '[${_timestamp()}] APK A MD5 覆盖：${_formatPercent(result.firstCoverage)}；APK B MD5 覆盖：${_formatPercent(result.secondCoverage)}',
      '[${_timestamp()}] 同路径文件：${result.commonPathCount}；同路径同 MD5：${result.samePathSameMd5Count}；同路径 MD5 不同：${result.samePathChangedMd5Count}',
      '[${_timestamp()}] APK A 独有 MD5 文件：${result.firstOnlyMd5FileCount}；APK B 独有 MD5 文件：${result.secondOnlyMd5FileCount}',
    ]);

    _appendMatchedMd5Samples(result.matchedSamples);
    _appendSingleApkMd5Samples('APK A 独有 MD5 样例', result.firstOnlySamples);
    _appendSingleApkMd5Samples('APK B 独有 MD5 样例', result.secondOnlySamples);
    _appendChangedPathMd5Samples(result.changedPathSamples);
  }

  void _appendMatchedMd5Samples(List<ApkMd5MatchSample> samples) {
    if (samples.isEmpty) {
      return;
    }

    _duplicationLogs.add('[${_timestamp()}] MD5 命中样例：');
    for (final sample in samples) {
      _duplicationLogs.add(
        '  ${_shortMd5(sample.md5)} | ${_formatFileSize(sample.sizeBytes)} | A: ${sample.firstPath} | B: ${sample.secondPath}',
      );
    }
  }

  void _appendSingleApkMd5Samples(String title, List<ApkFileMd5> samples) {
    if (samples.isEmpty) {
      return;
    }

    _duplicationLogs.add('[${_timestamp()}] $title：');
    for (final sample in samples) {
      _duplicationLogs.add(
        '  ${_shortMd5(sample.md5)} | ${_formatFileSize(sample.sizeBytes)} | ${sample.path}',
      );
    }
  }

  void _appendChangedPathMd5Samples(List<ApkSamePathMd5Pair> samples) {
    if (samples.isEmpty) {
      return;
    }

    _duplicationLogs.add('[${_timestamp()}] 同路径 MD5 不同样例：');
    for (final sample in samples) {
      _duplicationLogs.add(
        '  ${sample.path} | A: ${_shortMd5(sample.firstMd5)} | B: ${_shortMd5(sample.secondMd5)}',
      );
    }
  }

  String _formatPercent(double value) {
    return '${(value * 100).toStringAsFixed(2)}%';
  }

  String _formatFileSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }

    if (unitIndex == 0) {
      return '$bytes ${units[unitIndex]}';
    }

    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }

  String _shortMd5(String value) {
    return value.length <= 8 ? value : value.substring(0, 8);
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

  String _defaultHardenedApkPath(String apkPath) {
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

    return '$directory${baseName}_z1guard.apk';
  }

  String _defaultChannelOutputDirectory(String apkPath) {
    if (apkPath.trim().isEmpty) {
      return '';
    }

    final directory = _directoryOfPath(apkPath);
    if (directory.isEmpty) {
      return 'channel_packages';
    }

    return _joinPath(directory, 'channel_packages');
  }

  String _channelCodeAt(int zeroBasedIndex) {
    final currentIndex = _channelPackageStartIndex + zeroBasedIndex;
    final maxIndex = _channelPackageStartIndex + _channelPackageCount - 1;
    final width = maxIndex.toString().length > 3
        ? maxIndex.toString().length
        : 3;

    return '${_channelPackagePrefix.trim()}${currentIndex.toString().padLeft(width, '0')}';
  }

  String _channelPackageOutputPath(
    String apkPath,
    String outputDirectory,
    String channelCode,
  ) {
    final baseName = _fileNameWithoutApkExtension(apkPath);
    final fileName = '${baseName}_$channelCode.apk';
    return _joinPath(outputDirectory, fileName);
  }

  String _directoryOfPath(String path) {
    final slashIndex = path.lastIndexOf('/');
    final backslashIndex = path.lastIndexOf(r'\');
    final separatorIndex = slashIndex > backslashIndex
        ? slashIndex
        : backslashIndex;

    return separatorIndex >= 0 ? path.substring(0, separatorIndex) : '';
  }

  String _fileNameWithoutApkExtension(String path) {
    final fileName = _lastPathSegment(path);
    return fileName.toLowerCase().endsWith('.apk')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
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

  bool _isSafeChannelPart(String value) {
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
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

class _SigningConfigValidationResult {
  const _SigningConfigValidationResult.success({
    required this.storePassword,
    required this.keyPassword,
  }) : errorMessage = null;

  const _SigningConfigValidationResult.error(this.errorMessage)
    : storePassword = '',
      keyPassword = '';

  final String? errorMessage;
  final String storePassword;
  final String keyPassword;
}
