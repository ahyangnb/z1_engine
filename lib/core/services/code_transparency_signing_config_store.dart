import 'dart:convert';
import 'dart:io';

import 'package:z1_engine/core/models/code_transparency_signing_config.dart';

class CodeTransparencySigningConfigStore {
  Future<CodeTransparencySigningConfigSnapshot> load() async {
    final file = File(_storageFilePath);
    if (!await file.exists()) {
      return const CodeTransparencySigningConfigSnapshot(configs: []);
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, Object?>) {
      return const CodeTransparencySigningConfigSnapshot(configs: []);
    }
    final configs = <CodeTransparencySigningConfig>[];
    final rawConfigs = value['configs'];
    if (rawConfigs is List<Object?>) {
      for (final rawConfig in rawConfigs) {
        if (rawConfig is Map<String, Object?>) {
          configs.add(CodeTransparencySigningConfig.fromJson(rawConfig));
        }
      }
    }
    return CodeTransparencySigningConfigSnapshot(
      configs: configs,
      selectedConfigId: value['selectedConfigId'] as String?,
    );
  }

  Future<void> save({
    required List<CodeTransparencySigningConfig> configs,
    required String? selectedConfigId,
  }) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'selectedConfigId': selectedConfigId,
        'configs': configs.map((config) => config.toJson()).toList(),
      }),
      flush: true,
    );
  }

  String get _storageFilePath {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    if (Platform.isMacOS) {
      return _joinPath(
        _joinPath(home, 'Library/Application Support/Z1 Engine'),
        'code_transparency_signing_configs.json',
      );
    }
    if (Platform.isWindows) {
      final root =
          Platform.environment['APPDATA'] ?? _joinPath(home, 'AppData/Roaming');
      return _joinPath(
        _joinPath(root, 'Z1 Engine'),
        'code_transparency_signing_configs.json',
      );
    }
    final root =
        Platform.environment['XDG_CONFIG_HOME'] ?? _joinPath(home, '.config');
    return _joinPath(
      _joinPath(root, 'z1_engine'),
      'code_transparency_signing_configs.json',
    );
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }
}

class CodeTransparencySigningConfigSnapshot {
  const CodeTransparencySigningConfigSnapshot({
    required this.configs,
    this.selectedConfigId,
  });

  final List<CodeTransparencySigningConfig> configs;
  final String? selectedConfigId;
}
