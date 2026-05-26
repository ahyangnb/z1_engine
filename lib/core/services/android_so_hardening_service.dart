import 'dart:io';

class AndroidSoHardeningResult {
  const AndroidSoHardeningResult({required this.logs});

  final List<String> logs;
}

class AndroidSoHardeningService {
  Future<AndroidSoHardeningResult> apply({required String projectPath}) async {
    final logs = <String>[];
    final androidDirectory = _resolveAndroidDirectory(projectPath);
    if (androidDirectory == null) {
      return AndroidSoHardeningResult(
        logs: ['未找到 Android 工程，请选择 Flutter 根目录或 Android 工程目录。'],
      );
    }

    final appBuildFile = _resolveAppBuildFile(androidDirectory);
    if (appBuildFile == null) {
      return AndroidSoHardeningResult(
        logs: ['未找到 app/build.gradle 或 app/build.gradle.kts。'],
      );
    }

    logs.add('Android 工程：${androidDirectory.path}');
    await _writeHardeningFiles(androidDirectory, logs);
    await _ensureGradleApply(appBuildFile, logs);
    await _stripPrebuiltSharedLibraries(androidDirectory, logs);
    logs.add('SO 构建加固配置完成。');

    return AndroidSoHardeningResult(logs: logs);
  }

  Directory? _resolveAndroidDirectory(String projectPath) {
    final normalizedPath = projectPath.trim();
    if (normalizedPath.isEmpty) {
      return null;
    }

    final type = FileSystemEntity.typeSync(normalizedPath);
    final selectedDirectory = type == FileSystemEntityType.file
        ? File(normalizedPath).parent
        : Directory(normalizedPath);
    final candidates = <Directory>[
      selectedDirectory,
      Directory(_joinPath(selectedDirectory.path, 'android')),
      if (_lastPathSegment(selectedDirectory.path) == 'app')
        selectedDirectory.parent,
      if (_lastPathSegment(selectedDirectory.parent.path) == 'app')
        selectedDirectory.parent.parent,
    ];

    for (final candidate in candidates) {
      if (_hasAppBuildFile(candidate)) {
        return candidate.absolute;
      }
    }

    return null;
  }

  bool _hasAppBuildFile(Directory androidDirectory) {
    return _resolveAppBuildFile(androidDirectory) != null;
  }

  File? _resolveAppBuildFile(Directory androidDirectory) {
    final appDirectory = Directory(_joinPath(androidDirectory.path, 'app'));
    final kotlinBuildFile = File(
      _joinPath(appDirectory.path, 'build.gradle.kts'),
    );
    if (kotlinBuildFile.existsSync()) {
      return kotlinBuildFile;
    }

    final groovyBuildFile = File(_joinPath(appDirectory.path, 'build.gradle'));
    if (groovyBuildFile.existsSync()) {
      return groovyBuildFile;
    }

    return null;
  }

  Future<void> _writeHardeningFiles(
    Directory androidDirectory,
    List<String> logs,
  ) async {
    final gradleFile = File(
      _joinPath(androidDirectory.path, 'z1_so_hardening.gradle'),
    );
    final nativeDirectory = Directory(
      _joinPath(androidDirectory.path, 'z1_native'),
    );
    await nativeDirectory.create(recursive: true);

    await _writeFileIfChanged(
      gradleFile,
      _gradleHardeningScript,
      logs,
      label: 'Gradle SO 加固脚本',
    );
    await _writeFileIfChanged(
      File(_joinPath(nativeDirectory.path, 'z1_native_hardening.cmake')),
      _nativeHardeningCmake,
      logs,
      label: 'CMake SO 加固片段',
    );
    await _writeFileIfChanged(
      File(_joinPath(nativeDirectory.path, 'z1_string_obfuscation.h')),
      _stringObfuscationHeader,
      logs,
      label: 'C++ 字符串加密头文件',
    );
  }

  Future<void> _writeFileIfChanged(
    File file,
    String content,
    List<String> logs, {
    required String label,
  }) async {
    if (file.existsSync() && file.readAsStringSync() == content) {
      logs.add('$label 已存在：${file.path}');
      return;
    }

    await file.writeAsString(content);
    logs.add('$label 已写入：${file.path}');
  }

  Future<void> _ensureGradleApply(File buildFile, List<String> logs) async {
    final content = await buildFile.readAsString();
    if (content.contains('z1_so_hardening.gradle')) {
      logs.add('Gradle 已接入 SO 加固脚本：${buildFile.path}');
      return;
    }

    final isKotlinDsl = buildFile.path.endsWith('.kts');
    final applyLine = isKotlinDsl
        ? 'apply(from = "../z1_so_hardening.gradle")'
        : 'apply from: "../z1_so_hardening.gradle"';
    final updatedContent = _insertAfterPluginsBlock(content, applyLine);
    final backupFile = File('${buildFile.path}.z1bak');
    if (!backupFile.existsSync()) {
      await backupFile.writeAsString(content);
      logs.add('已备份 Gradle 文件：${backupFile.path}');
    }

    await buildFile.writeAsString(updatedContent);
    logs.add('已接入 SO 加固脚本：${buildFile.path}');
  }

  String _insertAfterPluginsBlock(String content, String line) {
    final pluginsMatch = RegExp(
      r'plugins\s*\{[\s\S]*?\n\}',
      multiLine: true,
    ).firstMatch(content);
    if (pluginsMatch == null) {
      return '$line\n\n$content';
    }

    return [
      content.substring(0, pluginsMatch.end),
      '\n\n$line',
      content.substring(pluginsMatch.end),
    ].join();
  }

  Future<void> _stripPrebuiltSharedLibraries(
    Directory androidDirectory,
    List<String> logs,
  ) async {
    final jniLibsDirectory = Directory(
      _joinPath(androidDirectory.path, 'app/src/main/jniLibs'),
    );
    if (!jniLibsDirectory.existsSync()) {
      logs.add('未发现 app/src/main/jniLibs 预编译 SO，跳过立即 strip。');
      return;
    }

    final stripExecutable = _findLlvmStrip(androidDirectory);
    if (stripExecutable == null) {
      logs.add('未找到 llvm-strip，已保留构建期加固配置，预编译 SO 暂未处理。');
      return;
    }

    final sharedLibraries = jniLibsDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.so'))
        .toList();
    if (sharedLibraries.isEmpty) {
      logs.add('app/src/main/jniLibs 中未发现 SO 文件。');
      return;
    }

    var strippedCount = 0;
    for (final sharedLibrary in sharedLibraries) {
      final backupFile = File('${sharedLibrary.path}.z1bak');
      if (!backupFile.existsSync()) {
        await sharedLibrary.copy(backupFile.path);
      }

      final result = await Process.run(stripExecutable, [
        '--strip-unneeded',
        sharedLibrary.path,
      ], runInShell: Platform.isWindows);
      if (result.exitCode == 0) {
        strippedCount += 1;
      } else {
        final error = result.stderr.toString().trim();
        logs.add(
          'strip 失败：${sharedLibrary.path}${error.isEmpty ? '' : '，$error'}',
        );
      }
    }

    logs.add('已 strip 预编译 SO：$strippedCount/${sharedLibraries.length}');
  }

  String? _findLlvmStrip(Directory androidDirectory) {
    for (final ndkDirectory in _ndkCandidates(androidDirectory)) {
      final llvmDirectory = Directory(
        _joinPath(ndkDirectory.path, 'toolchains/llvm/prebuilt'),
      );
      if (!llvmDirectory.existsSync()) {
        continue;
      }

      final prebuiltDirectories = llvmDirectory
          .listSync()
          .whereType<Directory>();
      for (final prebuiltDirectory in prebuiltDirectories) {
        for (final executableName in _llvmStripExecutableNames()) {
          final candidatePath = _joinPath(
            _joinPath(prebuiltDirectory.path, 'bin'),
            executableName,
          );
          if (File(candidatePath).existsSync()) {
            return candidatePath;
          }
        }
      }
    }

    return null;
  }

  Iterable<Directory> _ndkCandidates(Directory androidDirectory) {
    final sdkCandidates = <String>{
      if ((Platform.environment['ANDROID_HOME'] ?? '').trim().isNotEmpty)
        Platform.environment['ANDROID_HOME']!.trim(),
      if ((Platform.environment['ANDROID_SDK_ROOT'] ?? '').trim().isNotEmpty)
        Platform.environment['ANDROID_SDK_ROOT']!.trim(),
    };
    final localSdkPath = _readSdkPath(androidDirectory);
    if (localSdkPath != null) {
      sdkCandidates.add(localSdkPath);
    }

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.trim().isNotEmpty) {
      sdkCandidates
        ..add(_joinPath(home, 'Library/Android/sdk'))
        ..add(_joinPath(home, 'Android/Sdk'));
    }

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      sdkCandidates.add(_joinPath(localAppData, 'Android/Sdk'));
    }

    final directNdkCandidates = <Directory>[
      if ((Platform.environment['ANDROID_NDK_HOME'] ?? '').trim().isNotEmpty)
        Directory(Platform.environment['ANDROID_NDK_HOME']!.trim()),
      if ((Platform.environment['ANDROID_NDK_ROOT'] ?? '').trim().isNotEmpty)
        Directory(Platform.environment['ANDROID_NDK_ROOT']!.trim()),
    ];

    final ndkDirectories = <Directory>[...directNdkCandidates];
    for (final sdkPath in sdkCandidates.where(
      (path) => Directory(path).existsSync(),
    )) {
      final ndkRoot = Directory(_joinPath(sdkPath, 'ndk'));
      if (ndkRoot.existsSync()) {
        final versionedNdks = ndkRoot.listSync().whereType<Directory>().toList()
          ..sort((left, right) {
            return _compareVersionNames(
              _lastPathSegment(right.path),
              _lastPathSegment(left.path),
            );
          });
        ndkDirectories.addAll(versionedNdks);
      }

      ndkDirectories.add(Directory(_joinPath(sdkPath, 'ndk-bundle')));
    }

    final seen = <String>{};
    return ndkDirectories.where((directory) {
      if (!directory.existsSync()) {
        return false;
      }

      return seen.add(directory.absolute.path);
    });
  }

  String? _readSdkPath(Directory androidDirectory) {
    final localProperties = File(
      _joinPath(androidDirectory.path, 'local.properties'),
    );
    if (!localProperties.existsSync()) {
      return null;
    }

    for (final line in localProperties.readAsLinesSync()) {
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('sdk.dir=')) {
        return trimmedLine.substring('sdk.dir='.length).trim();
      }
    }

    return null;
  }

  Iterable<String> _llvmStripExecutableNames() {
    return Platform.isWindows
        ? ['llvm-strip.exe', 'llvm-strip']
        : ['llvm-strip'];
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
}

const _gradleHardeningScript = r'''
// Generated by Z1 Engine. Apply from app/build.gradle(.kts).

def z1NativeCFlags = [
        "-fvisibility=hidden",
        "-ffunction-sections",
        "-fdata-sections",
        "-fstack-protector-strong",
        "-D_FORTIFY_SOURCE=2",
        "-fPIC"
]
def z1NativeCppFlags = z1NativeCFlags + [
        "-fvisibility-inlines-hidden"
]
def z1NativeLinkFlags = [
        "-Wl,-z,relro",
        "-Wl,-z,now",
        "-Wl,--gc-sections",
        "-Wl,--exclude-libs,ALL"
]
def z1EnableCfi = providers.gradleProperty("z1.enableCfi")
        .orElse("false")
        .get()
        .toBoolean()

if (z1EnableCfi) {
    z1NativeCFlags += ["-flto=thin", "-fsanitize=cfi"]
    z1NativeCppFlags += ["-flto=thin", "-fsanitize=cfi"]
    z1NativeLinkFlags += ["-flto=thin", "-fsanitize=cfi"]
}

def z1ConfigureNativeHardening = { androidExt ->
    androidExt.defaultConfig {
        externalNativeBuild {
            cmake {
                cFlags z1NativeCFlags.join(" ")
                cppFlags z1NativeCppFlags.join(" ")
                arguments "-DZ1_ENABLE_NATIVE_HARDENING=ON",
                        "-DZ1_ENABLE_CFI=${z1EnableCfi ? "ON" : "OFF"}",
                        "-DCMAKE_SHARED_LINKER_FLAGS=${z1NativeLinkFlags.join(" ")}"
            }
        }
    }
}

plugins.withId("com.android.application") {
    z1ConfigureNativeHardening(android)
}
plugins.withId("com.android.library") {
    z1ConfigureNativeHardening(android)
}
''';

const _nativeHardeningCmake = r'''
# Generated by Z1 Engine. Include this file from CMakeLists.txt, then call:
# z1_enable_native_hardening(your_target)

function(z1_enable_native_hardening target_name)
    target_compile_options(${target_name} PRIVATE
            -fvisibility=hidden
            -ffunction-sections
            -fdata-sections
            -fstack-protector-strong
            -D_FORTIFY_SOURCE=2
            -fPIC)

    target_compile_options(${target_name} PRIVATE
            $<$<COMPILE_LANGUAGE:CXX>:-fvisibility-inlines-hidden>)

    target_link_options(${target_name} PRIVATE
            -Wl,-z,relro
            -Wl,-z,now
            -Wl,--gc-sections
            -Wl,--exclude-libs,ALL)

    if (Z1_ENABLE_CFI)
        target_compile_options(${target_name} PRIVATE -flto=thin -fsanitize=cfi)
        target_link_options(${target_name} PRIVATE -flto=thin -fsanitize=cfi)
    endif()
endfunction()
''';

const _stringObfuscationHeader = r'''
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace z1 {

constexpr uint8_t obfuscation_key(uint32_t seed, size_t index) {
    return static_cast<uint8_t>(((seed * 131u) + (index * 17u) + 0x5au) & 0xffu);
}

template <size_t Size, uint32_t Seed>
class ObfuscatedString {
public:
    constexpr explicit ObfuscatedString(const char (&value)[Size]) : data_{} {
        for (size_t index = 0; index < Size; ++index) {
            data_[index] = static_cast<char>(value[index] ^ obfuscation_key(Seed, index));
        }
    }

    std::string decrypt() const {
        std::string output;
        output.resize(Size > 0 ? Size - 1 : 0);
        for (size_t index = 0; index + 1 < Size; ++index) {
            output[index] = static_cast<char>(data_[index] ^ obfuscation_key(Seed, index));
        }
        return output;
    }

private:
    std::array<char, Size> data_;
};

template <uint32_t Seed, size_t Size>
constexpr auto make_obfuscated(const char (&value)[Size]) {
    return ObfuscatedString<Size, Seed>(value);
}

}  // namespace z1

#define Z1_OBF(value) []() { \
    static constexpr auto z1_obfuscated_value = ::z1::make_obfuscated<__LINE__>(value); \
    return z1_obfuscated_value.decrypt(); \
}()
''';
