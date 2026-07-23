import 'dart:io';

class AndroidToolchainResolver {
  Future<String> resolveJavaTool(String executableName) async {
    final javaHome = Platform.environment['JAVA_HOME']?.trim();
    if (javaHome != null && javaHome.isNotEmpty) {
      final candidate = _joinPath(_joinPath(javaHome, 'bin'), executableName);
      if (_isFile(candidate)) {
        return candidate;
      }
    }

    final pathExecutable = await findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    if (Platform.isMacOS) {
      try {
        final result = await Process.run('/usr/libexec/java_home', []);
        final detectedHome = result.stdout.toString().trim();
        final candidate = _joinPath(
          _joinPath(detectedHome, 'bin'),
          executableName,
        );
        if (result.exitCode == 0 && _isFile(candidate)) {
          return candidate;
        }
      } on ProcessException {
        // Report the common error below.
      }
    }

    throw AndroidToolchainException(
      '未找到 $executableName，请安装 JDK 或配置 JAVA_HOME',
    );
  }

  Future<String> resolvePathExecutable(String executableName) async {
    final pathExecutable = await findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    for (final candidate in commonExecutableCandidates(executableName)) {
      if (_isFile(candidate)) {
        return candidate;
      }
    }

    throw AndroidToolchainException('未找到 $executableName，请先安装并加入 PATH');
  }

  Future<String> resolveBuildTool({
    required String executableName,
    String configuredPath = '',
  }) async {
    final normalizedConfiguredPath = configuredPath.trim();
    if (normalizedConfiguredPath.isNotEmpty) {
      if (!_isFile(normalizedConfiguredPath)) {
        throw AndroidToolchainException(
          '$executableName 不存在：$normalizedConfiguredPath',
        );
      }
      return normalizedConfiguredPath;
    }

    final pathExecutable = await findExecutableOnPath(executableName);
    if (pathExecutable != null) {
      return pathExecutable;
    }

    for (final sdkPath in androidSdkCandidates()) {
      final executable = _findLatestVersionedExecutable(
        _joinPath(sdkPath, 'build-tools'),
        executableName,
      );
      if (executable != null) {
        return executable;
      }
    }

    throw AndroidToolchainException(
      '未找到 $executableName，请安装 Android SDK build-tools',
    );
  }

  String resolveNdkTool(String executableName) {
    for (final sdkPath in androidSdkCandidates()) {
      final ndkRoot = Directory(_joinPath(sdkPath, 'ndk'));
      if (!ndkRoot.existsSync()) {
        continue;
      }
      final ndks = ndkRoot.listSync().whereType<Directory>().toList()
        ..sort((left, right) => right.path.compareTo(left.path));
      for (final ndk in ndks) {
        final prebuiltRoot = Directory(
          _joinPath(ndk.path, 'toolchains/llvm/prebuilt'),
        );
        if (!prebuiltRoot.existsSync()) {
          continue;
        }
        for (final prebuilt in prebuiltRoot.listSync().whereType<Directory>()) {
          final candidate = _joinPath(
            _joinPath(prebuilt.path, 'bin'),
            executableName,
          );
          if (_isFile(candidate)) {
            return candidate;
          }
        }
      }
    }

    throw AndroidToolchainException('未找到 $executableName，请安装 Android NDK');
  }

  Future<String?> findExecutableOnPath(String executableName) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        executableName,
      ], runInShell: Platform.isWindows);
      if (result.exitCode != 0) {
        return null;
      }
      final output = result.stdout.toString().trim();
      return output.isEmpty
          ? null
          : output.split(RegExp(r'\r?\n')).first.trim();
    } on ProcessException {
      return null;
    }
  }

  Iterable<String> commonExecutableCandidates(String executableName) sync* {
    if (Platform.isWindows) {
      return;
    }
    final homeDirectory = Platform.environment['HOME']?.trim();
    for (final directory in [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/opt/local/bin',
      if (homeDirectory != null && homeDirectory.isNotEmpty)
        _joinPath(homeDirectory, '.local/bin'),
    ]) {
      yield _joinPath(directory, executableName);
    }
  }

  Iterable<String> androidSdkCandidates() sync* {
    final seen = <String>{};
    final homeDirectory =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    for (final candidate in [
      Platform.environment['ANDROID_HOME'],
      Platform.environment['ANDROID_SDK_ROOT'],
      if (homeDirectory != null)
        _joinPath(homeDirectory, 'Library/Android/sdk'),
      if (homeDirectory != null) _joinPath(homeDirectory, 'Android/Sdk'),
      if (Platform.environment['LOCALAPPDATA'] != null)
        _joinPath(Platform.environment['LOCALAPPDATA']!, 'Android/Sdk'),
    ]) {
      final normalized = candidate?.trim() ?? '';
      if (normalized.isNotEmpty &&
          seen.add(normalized) &&
          Directory(normalized).existsSync()) {
        yield normalized;
      }
    }
  }

  String? _findLatestVersionedExecutable(String root, String executableName) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      return null;
    }
    final versions = directory.listSync().whereType<Directory>().toList()
      ..sort((left, right) => right.path.compareTo(left.path));
    for (final version in versions) {
      final candidate = _joinPath(version.path, executableName);
      if (_isFile(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  bool _isFile(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  String _joinPath(String parent, String child) {
    if (parent.endsWith('/') || parent.endsWith(r'\')) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }
}

class AndroidToolchainException implements Exception {
  const AndroidToolchainException(this.message);

  final String message;

  @override
  String toString() => message;
}
