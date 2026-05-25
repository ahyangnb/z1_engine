import 'package:flutter/foundation.dart';
import 'package:z1_engine/core/models/main_menu.dart';
import 'package:z1_engine/core/models/package_target.dart';

class EngineMenuController extends ChangeNotifier {
  MainMenu _selectedMenu = MainMenu.obfuscation;
  PackageTarget _selectedObfuscationTarget = PackageTarget.android;
  PackageTarget _selectedPackageTarget = PackageTarget.android;
  final Set<String> _androidObfuscationConfig = {};
  final Set<String> _flutterObfuscationConfig = {};
  final List<String> _obfuscationLogs = [];

  MainMenu get selectedMenu => _selectedMenu;
  PackageTarget get selectedObfuscationTarget => _selectedObfuscationTarget;
  PackageTarget get selectedPackageTarget => _selectedPackageTarget;
  List<String> get obfuscationLogs => List.unmodifiable(_obfuscationLogs);

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

  void toggleObfuscationOption(String option, bool selected) {
    final config = _activeObfuscationConfig;
    final changed = selected ? config.add(option) : config.remove(option);

    if (changed) {
      notifyListeners();
    }
  }

  void executeObfuscation() {
    final targetLabel = selectedObfuscationTargetLabel;
    final selectedOptions = _activeObfuscationConfig;
    final configSummary = selectedOptions.isEmpty
        ? '未选择混淆配置'
        : selectedOptions.join('、');

    _obfuscationLogs.addAll([
      '[${_timestamp()}] 开始执行$targetLabel',
      '[${_timestamp()}] 混淆配置：$configSummary',
      '[${_timestamp()}] 当前为界面演示，实际执行逻辑待接入',
      '[${_timestamp()}] $targetLabel流程结束',
    ]);
    notifyListeners();
  }

  void clearObfuscationLogs() {
    if (_obfuscationLogs.isEmpty) {
      return;
    }

    _obfuscationLogs.clear();
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
