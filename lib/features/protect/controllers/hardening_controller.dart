import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:z1_engine/core/models/android_signing_config.dart';
import 'package:z1_engine/core/models/code_transparency_signing_config.dart';
import 'package:z1_engine/core/models/hardening_artifact.dart';
import 'package:z1_engine/core/services/aab_project_hardening_installer.dart';
import 'package:z1_engine/core/services/aab_publishing_protection_service.dart';
import 'package:z1_engine/core/services/android_native_build_hardening_service.dart';
import 'package:z1_engine/core/services/android_toolchain_resolver.dart';
import 'package:z1_engine/core/services/apk_hardening_service.dart';
import 'package:z1_engine/core/services/code_transparency_signing_config_store.dart';
import 'package:z1_engine/core/services/hardening_artifact_inspector.dart';
import 'package:z1_engine/core/services/so_binary_hardening_service.dart';

class HardeningController extends ChangeNotifier {
  HardeningController({
    HardeningArtifactInspector? inspector,
    ApkHardeningService? apkHardeningService,
    AabPublishingProtectionService? aabProtectionService,
    SoBinaryHardeningService? soHardeningService,
    AabProjectHardeningInstaller? projectHardeningInstaller,
    AndroidNativeBuildHardeningService? nativeBuildHardeningService,
    CodeTransparencySigningConfigStore? transparencyConfigStore,
    AndroidToolchainResolver? toolchain,
  }) : _inspector = inspector ?? HardeningArtifactInspector(),
       _apkHardeningService = apkHardeningService ?? ApkHardeningService(),
       _aabProtectionService =
           aabProtectionService ?? AabPublishingProtectionService(),
       _soHardeningService = soHardeningService ?? SoBinaryHardeningService(),
       _projectHardeningInstaller =
           projectHardeningInstaller ?? AabProjectHardeningInstaller(),
       _nativeBuildHardeningService =
           nativeBuildHardeningService ?? AndroidNativeBuildHardeningService(),
       _transparencyConfigStore =
           transparencyConfigStore ?? CodeTransparencySigningConfigStore(),
       _toolchain = toolchain ?? AndroidToolchainResolver() {
    _loadTransparencyConfigs();
  }

  final HardeningArtifactInspector _inspector;
  final ApkHardeningService _apkHardeningService;
  final AabPublishingProtectionService _aabProtectionService;
  final SoBinaryHardeningService _soHardeningService;
  final AabProjectHardeningInstaller _projectHardeningInstaller;
  final AndroidNativeBuildHardeningService _nativeBuildHardeningService;
  final CodeTransparencySigningConfigStore _transparencyConfigStore;
  final AndroidToolchainResolver _toolchain;

  HardeningArtifactType _selectedType = HardeningArtifactType.apk;
  String _artifactPath = '';
  String _outputPath = '';
  String _projectPath = '';
  String _playCertificateText = '';
  bool _saveDebugSymbols = true;
  bool _enableAabProjectGuard = true;
  bool _enableNativeBuildHardening = true;
  bool _enableCfi = false;
  bool _enableHiddenVisibility = false;
  bool _isRunning = false;
  String? _artifactInspectionMessage;
  final List<String> _logs = [];
  final List<CodeTransparencySigningConfig> _transparencyConfigs = [];
  String? _selectedTransparencyConfigId;

  HardeningArtifactType get selectedType => _selectedType;
  String get artifactPath => _artifactPath;
  String get outputPath => _outputPath;
  String get projectPath => _projectPath;
  String get playCertificateText => _playCertificateText;
  bool get saveDebugSymbols => _saveDebugSymbols;
  bool get enableAabProjectGuard => _enableAabProjectGuard;
  bool get enableNativeBuildHardening => _enableNativeBuildHardening;
  bool get enableCfi => _enableCfi;
  bool get enableHiddenVisibility => _enableHiddenVisibility;
  bool get isRunning => _isRunning;
  String? get artifactInspectionMessage => _artifactInspectionMessage;
  List<String> get logs => List.unmodifiable(_logs);
  List<CodeTransparencySigningConfig> get transparencyConfigs =>
      List.unmodifiable(_transparencyConfigs);
  String? get selectedTransparencyConfigId => selectedTransparencyConfig?.id;

  CodeTransparencySigningConfig? get selectedTransparencyConfig {
    for (final config in _transparencyConfigs) {
      if (config.id == _selectedTransparencyConfigId) {
        return config;
      }
    }
    return _transparencyConfigs.isEmpty ? null : _transparencyConfigs.first;
  }

  bool canExecuteWith(AndroidSigningConfig? uploadSigningConfig) {
    if (_isRunning) {
      return false;
    }
    return switch (_selectedType) {
      HardeningArtifactType.apk =>
        uploadSigningConfig != null &&
            _isExistingFile(_artifactPath) &&
            _artifactPath.toLowerCase().endsWith('.apk') &&
            _outputPath.isNotEmpty,
      HardeningArtifactType.aab =>
        uploadSigningConfig != null &&
            selectedTransparencyConfig != null &&
            _isExistingFile(_artifactPath) &&
            _artifactPath.toLowerCase().endsWith('.aab') &&
            _outputPath.isNotEmpty,
      HardeningArtifactType.sharedObject =>
        _isExistingFile(_artifactPath) &&
            _artifactPath.toLowerCase().endsWith('.so') &&
            _outputPath.isNotEmpty,
      HardeningArtifactType.androidProject =>
        Directory(_projectPath).existsSync() &&
            (_enableAabProjectGuard || _enableNativeBuildHardening) &&
            (!_enableAabProjectGuard ||
                (uploadSigningConfig != null &&
                    selectedTransparencyConfig != null &&
                    _playCertificateFingerprints.isNotEmpty)),
    };
  }

  void selectType(HardeningArtifactType type) {
    if (_selectedType == type) {
      return;
    }
    _selectedType = type;
    _artifactInspectionMessage = null;
    notifyListeners();
  }

  Future<void> updateArtifactPath(String path) async {
    _artifactPath = path.trim();
    _artifactInspectionMessage = null;
    _outputPath = _defaultOutputPath(_artifactPath, _selectedType);
    notifyListeners();
    if (!_isExistingFile(_artifactPath)) {
      return;
    }
    try {
      final inspection = await _inspector.inspect(_artifactPath);
      _selectedType = inspection.type;
      _outputPath = _defaultOutputPath(_artifactPath, inspection.type);
      _artifactInspectionMessage = switch (inspection.type) {
        HardeningArtifactType.aab =>
          '已识别 AAB：${inspection.moduleNames.length} 个模块',
        HardeningArtifactType.sharedObject =>
          '已识别 Android SO：${inspection.abi}',
        HardeningArtifactType.apk => '已识别 APK',
        HardeningArtifactType.androidProject => null,
      };
    } on HardeningArtifactException catch (error) {
      _artifactInspectionMessage = error.message;
    }
    notifyListeners();
  }

  void updateOutputPath(String path) {
    _outputPath = path.trim();
    notifyListeners();
  }

  void updateProjectPath(String path) {
    _projectPath = path.trim();
    notifyListeners();
  }

  void updatePlayCertificateText(String value) {
    _playCertificateText = value.trim();
    notifyListeners();
  }

  void setSaveDebugSymbols(bool value) {
    _saveDebugSymbols = value;
    notifyListeners();
  }

  void setEnableAabProjectGuard(bool value) {
    _enableAabProjectGuard = value;
    notifyListeners();
  }

  void setEnableNativeBuildHardening(bool value) {
    _enableNativeBuildHardening = value;
    notifyListeners();
  }

  void setEnableCfi(bool value) {
    _enableCfi = value;
    notifyListeners();
  }

  void setEnableHiddenVisibility(bool value) {
    _enableHiddenVisibility = value;
    notifyListeners();
  }

  Future<void> execute(AndroidSigningConfig? uploadSigningConfig) async {
    if (!canExecuteWith(uploadSigningConfig)) {
      _addLog('当前配置不完整，无法执行加固');
      notifyListeners();
      return;
    }
    _isRunning = true;
    _addLog('开始执行 ${_selectedType.label} 加固流程');
    notifyListeners();
    try {
      switch (_selectedType) {
        case HardeningArtifactType.apk:
          final result = await _apkHardeningService.harden(
            sourceApkPath: _artifactPath,
            outputApkPath: _outputPath,
            signingConfig: uploadSigningConfig!,
          );
          for (final log in result.logs) {
            _addLog(log);
          }
          _addLog('APK 运行时 Guard 加固成功：${result.outputApkPath}');
        case HardeningArtifactType.aab:
          final result = await _aabProtectionService.protect(
            sourceAabPath: _artifactPath,
            outputAabPath: _outputPath,
            uploadSigningConfig: uploadSigningConfig!,
            transparencySigningConfig: selectedTransparencyConfig!,
          );
          for (final log in result.logs) {
            _addLog(log);
          }
          _addLog('AAB 发布完整性保护成功；该模式不注入运行时 Guard');
        case HardeningArtifactType.sharedObject:
          final result = await _soHardeningService.harden(
            sourceSoPath: _artifactPath,
            outputSoPath: _outputPath,
            saveDebugSymbols: _saveDebugSymbols,
          );
          for (final log in result.logs) {
            _addLog(log);
          }
        case HardeningArtifactType.androidProject:
          if (_enableAabProjectGuard) {
            final result = await _projectHardeningInstaller.install(
              projectPath: _projectPath,
              uploadSigningConfig: uploadSigningConfig!,
              transparencySigningConfig: selectedTransparencyConfig!,
              playCertificateSha256: _playCertificateFingerprints,
            );
            for (final log in result.logs) {
              _addLog(log);
            }
          }
          if (_enableNativeBuildHardening) {
            final result = await _nativeBuildHardeningService.apply(
              projectPath: _projectPath,
              enableCfi: _enableCfi,
              enableHiddenVisibility: _enableHiddenVisibility,
            );
            for (final log in result.logs) {
              _addLog(log);
            }
          }
      }
    } on ApkHardeningException catch (error) {
      _addLog('APK 加固失败：${error.message}');
    } on AabPublishingProtectionException catch (error) {
      _addLog('AAB 发布保护失败：${error.message}');
    } on SoBinaryHardeningException catch (error) {
      _addLog('SO 加固失败：${error.message}');
    } on AabProjectHardeningException catch (error) {
      _addLog('源码工程 AAB Guard 失败：${error.message}');
    } on FileSystemException catch (error) {
      _addLog('文件处理失败：${error.message}');
    } on ProcessException catch (error) {
      _addLog('命令启动失败：${error.message}');
    } catch (error) {
      _addLog('加固失败：$error');
    } finally {
      _isRunning = false;
      _addLog('${_selectedType.label} 加固流程结束');
      notifyListeners();
    }
  }

  Future<void> removeProjectGuard() async {
    if (_isRunning || _projectPath.isEmpty) {
      return;
    }
    _isRunning = true;
    _addLog('开始移除源码工程 AAB Guard');
    notifyListeners();
    try {
      final result = await _projectHardeningInstaller.remove(
        projectPath: _projectPath,
      );
      for (final log in result.logs) {
        _addLog(log);
      }
    } on AabProjectHardeningException catch (error) {
      _addLog('移除失败：${error.message}');
    } finally {
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<String?> saveTransparencyConfig({
    String? id,
    required String keystorePath,
    required String keyAlias,
    required String storePassword,
    required String keyPassword,
    String remark = '',
  }) async {
    final normalizedPath = keystorePath.trim();
    final normalizedAlias = keyAlias.trim();
    final effectiveStorePassword = storePassword.isEmpty
        ? keyPassword
        : storePassword;
    final effectiveKeyPassword = keyPassword.isEmpty
        ? effectiveStorePassword
        : keyPassword;
    if (!_isExistingFile(normalizedPath)) {
      return '代码透明 keystore 不存在';
    }
    if (normalizedAlias.isEmpty ||
        effectiveStorePassword.isEmpty ||
        effectiveKeyPassword.isEmpty) {
      return '请完整填写 alias 和密码';
    }

    try {
      final keytool = await _toolchain.resolveJavaTool('keytool');
      final result = await Process.run(
        keytool,
        [
          '-list',
          '-keystore',
          normalizedPath,
          '-alias',
          normalizedAlias,
          '-storepass:env',
          'Z1_KEYSTORE_PASS',
        ],
        environment: {
          ...Platform.environment,
          'Z1_KEYSTORE_PASS': effectiveStorePassword,
        },
      );
      if (result.exitCode != 0) {
        return '代码透明签名配置校验失败，请检查 keystore、alias 和密码';
      }
    } on AndroidToolchainException catch (error) {
      return error.message;
    }

    final config = CodeTransparencySigningConfig(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: normalizedAlias,
      keystorePath: normalizedPath,
      keyAlias: normalizedAlias,
      storePassword: effectiveStorePassword,
      keyPassword: effectiveKeyPassword,
      remark: remark.trim(),
    );
    final existingIndex = _transparencyConfigs.indexWhere(
      (item) => item.id == config.id,
    );
    if (existingIndex < 0) {
      _transparencyConfigs.add(config);
    } else {
      _transparencyConfigs[existingIndex] = config;
    }
    _selectedTransparencyConfigId = config.id;
    await _saveTransparencyConfigs();
    notifyListeners();
    return null;
  }

  void selectTransparencyConfig(String id) {
    _selectedTransparencyConfigId = id;
    _saveTransparencyConfigs();
    notifyListeners();
  }

  void removeTransparencyConfig(String id) {
    _transparencyConfigs.removeWhere((config) => config.id == id);
    if (_selectedTransparencyConfigId == id) {
      _selectedTransparencyConfigId = _transparencyConfigs.firstOrNull?.id;
    }
    _saveTransparencyConfigs();
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  List<String> get _playCertificateFingerprints {
    return _playCertificateText
        .split(RegExp(r'[\s,;]+'))
        .map((value) => value.replaceAll(RegExp(r'[^0-9a-fA-F]'), ''))
        .where((value) => value.length == 64)
        .toSet()
        .toList();
  }

  Future<void> _loadTransparencyConfigs() async {
    try {
      final snapshot = await _transparencyConfigStore.load();
      _transparencyConfigs
        ..clear()
        ..addAll(snapshot.configs);
      _selectedTransparencyConfigId = snapshot.selectedConfigId;
      notifyListeners();
    } on FormatException {
      _addLog('代码透明签名配置解析失败');
      notifyListeners();
    } on FileSystemException catch (error) {
      _addLog('代码透明签名配置读取失败：${error.message}');
      notifyListeners();
    }
  }

  Future<void> _saveTransparencyConfigs() async {
    await _transparencyConfigStore.save(
      configs: _transparencyConfigs,
      selectedConfigId: _selectedTransparencyConfigId,
    );
  }

  String _defaultOutputPath(String inputPath, HardeningArtifactType type) {
    if (inputPath.isEmpty || type == HardeningArtifactType.androidProject) {
      return '';
    }
    final extension = type.extension;
    if (!inputPath.toLowerCase().endsWith(extension)) {
      return '';
    }
    return '${inputPath.substring(0, inputPath.length - extension.length)}'
        '_z1guard$extension';
  }

  bool _isExistingFile(String path) {
    return path.isNotEmpty && File(path).existsSync();
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _logs.add('[$timestamp] $message');
  }
}
