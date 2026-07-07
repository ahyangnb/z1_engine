import 'dart:convert';
import 'dart:io';

class VipActivationStore {
  Future<String> loadActivationCode() async {
    final file = File(_storageFilePath);
    if (!await file.exists()) {
      return '';
    }

    final rawContent = await file.readAsString();
    if (rawContent.trim().isEmpty) {
      return '';
    }

    final jsonValue = jsonDecode(rawContent);
    if (jsonValue is! Map<String, Object?>) {
      return '';
    }

    return jsonValue['activationCode'] as String? ?? '';
  }

  Future<void> saveActivationCode(String activationCode) async {
    final file = File(_storageFilePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({'activationCode': activationCode.trim()}),
    );
  }

  String get _storageFilePath {
    if (Platform.isMacOS) {
      return _joinPath(
        _joinPath(_homeDirectory, 'Library/Application Support/Z1 Engine'),
        'vip_activation.json',
      );
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final root = appData == null || appData.trim().isEmpty
          ? _joinPath(_homeDirectory, 'AppData/Roaming')
          : appData.trim();
      return _joinPath(_joinPath(root, 'Z1 Engine'), 'vip_activation.json');
    }

    final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
    final root = xdgConfigHome == null || xdgConfigHome.trim().isEmpty
        ? _joinPath(_homeDirectory, '.config')
        : xdgConfigHome.trim();
    return _joinPath(_joinPath(root, 'z1_engine'), 'vip_activation.json');
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
