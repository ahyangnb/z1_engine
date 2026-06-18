import 'dart:convert';
import 'dart:io';

import 'package:z1_engine/core/models/android_signing_config.dart';

class SigningConfigStore {
  Future<SigningConfigSnapshot> load() async {
    final file = File(_storageFilePath);
    if (!await file.exists()) {
      return const SigningConfigSnapshot(configs: []);
    }

    final rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return const SigningConfigSnapshot(configs: []);
    }

    final jsonValue = jsonDecode(rawContent);
    if (jsonValue is! Map<String, Object?>) {
      return const SigningConfigSnapshot(configs: []);
    }

    final configsValue = jsonValue['configs'];
    final configs = <AndroidSigningConfig>[];
    if (configsValue is List<Object?>) {
      for (final configValue in configsValue) {
        if (configValue is Map<String, Object?>) {
          configs.add(AndroidSigningConfig.fromJson(configValue));
        }
      }
    }

    return SigningConfigSnapshot(
      configs: configs,
      selectedConfigId: jsonValue['selectedConfigId'] as String?,
    );
  }

  Future<void> save({
    required List<AndroidSigningConfig> configs,
    required String? selectedConfigId,
  }) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'selectedConfigId': selectedConfigId,
        'configs': configs.map((config) => config.toJson()).toList(),
      }),
    );
  }

  String get _storageFilePath {
    if (Platform.isMacOS) {
      return _joinPath(
        _joinPath(_homeDirectory, 'Library/Application Support/Z1 Engine'),
        'signing_configs.json',
      );
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final root = appData == null || appData.trim().isEmpty
          ? _joinPath(_homeDirectory, 'AppData/Roaming')
          : appData.trim();
      return _joinPath(_joinPath(root, 'Z1 Engine'), 'signing_configs.json');
    }

    final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
    final root = xdgConfigHome == null || xdgConfigHome.trim().isEmpty
        ? _joinPath(_homeDirectory, '.config')
        : xdgConfigHome.trim();
    return _joinPath(_joinPath(root, 'z1_engine'), 'signing_configs.json');
  }

  String get _homeDirectory {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.trim().isEmpty) {
      return Directory.current.path;
    }

    return home.trim();
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }

    return '$parent${Platform.pathSeparator}$child';
  }
}

class SigningConfigSnapshot {
  const SigningConfigSnapshot({required this.configs, this.selectedConfigId});

  final List<AndroidSigningConfig> configs;
  final String? selectedConfigId;
}
