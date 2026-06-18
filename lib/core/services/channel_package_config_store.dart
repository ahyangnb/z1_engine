import 'dart:convert';
import 'dart:io';

import 'package:z1_engine/core/models/channel_package_config.dart';

class ChannelPackageConfigStore {
  Future<ChannelPackageConfig> load() async {
    final file = File(_storageFilePath);
    if (!await file.exists()) {
      return const ChannelPackageConfig();
    }

    final rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return const ChannelPackageConfig();
    }

    final jsonValue = jsonDecode(rawContent);
    if (jsonValue is! Map<String, Object?>) {
      return const ChannelPackageConfig();
    }

    return ChannelPackageConfig.fromJson(jsonValue);
  }

  Future<void> save(ChannelPackageConfig config) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config.toJson()));
  }

  String get _storageFilePath {
    if (Platform.isMacOS) {
      return _joinPath(
        _joinPath(_homeDirectory, 'Library/Application Support/Z1 Engine'),
        'channel_package_config.json',
      );
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final root = appData == null || appData.trim().isEmpty
          ? _joinPath(_homeDirectory, 'AppData/Roaming')
          : appData.trim();
      return _joinPath(
        _joinPath(root, 'Z1 Engine'),
        'channel_package_config.json',
      );
    }

    final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
    final root = xdgConfigHome == null || xdgConfigHome.trim().isEmpty
        ? _joinPath(_homeDirectory, '.config')
        : xdgConfigHome.trim();
    return _joinPath(
      _joinPath(root, 'z1_engine'),
      'channel_package_config.json',
    );
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
